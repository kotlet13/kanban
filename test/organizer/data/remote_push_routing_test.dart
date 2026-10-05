import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, MemorySessionStore, code;
import 'remote_push_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory directory;
  late FakeServer server;
  late PushTransport transport;
  late MemorySessionStore sessions;
  late MemoryPushStore pushes;
  final repositories = <CollaborationRepository>[];
  Future<CollaborationRepository> open() async {
    final r = CollaborationRepository(
      CollaborationDatabase(NativeDatabase(File('${directory.path}/a.sqlite'))),
      transport,
      sessions,
      pushStore: pushes,
    );
    await r.initialize();
    repositories.add(r);
    return r;
  }

  Future<void> login(CollaborationRepository r) => r.login(
    serverUrl: 'https://synthetic.invalid/kanboard',
    username: 'alice',
    password: 'synthetic',
  );
  RemotePushReference reference(CollaborationRepository r, int id) =>
      RemotePushReference(
        serverId: r.state.session!.serverId,
        accountId: r.state.session!.accountId,
        notificationId: id,
      );
  Future<(String, RemotePushReference)> createGroup(
    CollaborationRepository r,
  ) async {
    await login(r);
    final scope = await r.createScope('Synthetic');
    for (var i = 1; i <= 3; i++) {
      final id = await r.createTask(scopeId: scope, title: 'Synthetic $i');
      transport.items.add(
        SharedInboxEntry(
          id: i,
          revision: 1,
          sequence: i,
          targetRevision: 1,
          scopeId: scope,
          kind: 'task.assigned',
          category: 'tasks',
          audience: InboxAudience.personal,
          targetType: 'task',
          targetId: id,
          groupKey: 'synthetic-group',
          createdAt: DateTime.utc(2026, 10, 5, 12),
        ),
      );
    }
    await r.syncNow();
    return (scope, reference(r, 3));
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('push-route-');
    server = FakeServer();
    transport = PushTransport(server);
    sessions = MemorySessionStore();
    pushes = MemoryPushStore();
  });
  tearDown(() async {
    for (final r in repositories) {
      await r.close();
    }
    repositories.clear();
    await directory.delete(recursive: true);
  });

  test('provider data is strict reference-only canonical strings', () {
    final valid = {
      'type': 'familyhub.inbox.v1',
      'serverId': server.serverId,
      'accountId': server.accountIds['alice']!,
      'notificationId': '1',
    };
    expect(RemotePushReference.parse(valid).notificationId, 1);
    final invalid = <Map<String, Object?>>[
      {...valid, 'url': 'https://evil.invalid'},
      {...valid, 'scopeId': newSharedId()},
      {...valid, 'type': 'other'},
      {...valid, 'notificationId': 1},
      {...valid, 'notificationId': '01'},
      {...valid, 'notificationId': '0'},
      {...valid, 'notificationId': '-1'},
      {...valid, 'notificationId': '9007199254740992'},
      {...valid, 'notificationId': '1.0'},
      {...valid, 'accountId': server.accountIds['alice']!.toUpperCase()},
      {...valid, 'serverId': 'https://evil.invalid'},
      {...valid, 'serverId': null},
    ];
    for (final data in invalid) {
      expect(RemotePushReference.tryParse(data), isNull);
    }
  });

  test(
    'cold reference waits for login and never selects or switches an account',
    () async {
      final r = await open();
      final ref = RemotePushReference(
        serverId: server.serverId,
        accountId: server.accountIds['alice']!,
        notificationId: 3,
      );
      expect(
        (await r.openRemotePushReference(ref)).status,
        RemotePushOpenStatus.requiresLogin,
      );
      expect(transport.calls, isEmpty);
      final (_, correct) = await createGroup(r);
      expect(
        (await r.openRemotePushReference(correct)).status,
        RemotePushOpenStatus.available,
      );
      final calls = transport.calls.length;
      for (final wrong in [
        RemotePushReference(
          serverId: newSharedId(),
          accountId: correct.accountId,
          notificationId: 3,
        ),
        RemotePushReference(
          serverId: correct.serverId,
          accountId: server.accountIds['bob']!,
          notificationId: 3,
        ),
      ]) {
        expect(
          (await r.openRemotePushReference(wrong)).status,
          RemotePushOpenStatus.wrongAccount,
        );
        expect(await r.receiveRemotePushReference(wrong), isFalse);
      }
      expect(transport.calls.length, calls);
    },
  );

  test(
    'push-only group resolves all exact canonical targets and survives offline restart',
    () async {
      var r = await open();
      final (_, ref) = await createGroup(r);
      expect(
        r.state.inbox,
        isEmpty,
      ); // Channel inApp is not required for routing.
      final result = await r.openRemotePushReference(ref);
      expect(result.status, RemotePushOpenStatus.available);
      expect(result.target!.inboxIds.toSet(), {1, 2, 3});
      expect(result.target!.records.length, 3);
      expect(
        transport.calls.where((c) => c.operation == 'inbox.open').length,
        3,
      );
      await r.close();
      repositories.remove(r);
      r = await open();
      transport.offline = true;
      final offline = await r.openRemotePushReference(ref);
      expect(offline.status, RemotePushOpenStatus.offline);
      expect(offline.target!.records.length, 3);
      await r.database.execute('DELETE FROM local_meta WHERE name=?', [
        'push_reference:${r.state.session!.partition}:1',
      ]);
      expect(
        (await r.openRemotePushReference(ref)).status,
        RemotePushOpenStatus.requiresConnection,
      );
    },
  );

  test(
    'partial ordinary inbox snapshot cannot be represented as complete offline group',
    () async {
      final r = await open();
      final (_, ref) = await createGroup(r);
      final p = r.state.session!.partition;
      final entry = transport.items.last;
      await r.database.execute(
        'INSERT INTO inbox(partition,id,data,remote) VALUES(?,?,?,?)',
        [p, entry.id, jsonEncode(entry.toJson()), jsonEncode(entry.toJson())],
      );
      transport.offline = true;
      expect(
        (await r.openRemotePushReference(ref)).status,
        RemotePushOpenStatus.requiresConnection,
      );
    },
  );

  test(
    'foreground receipt only syncs matching account without routing or OS presentation',
    () async {
      final r = await open();
      final (_, ref) = await createGroup(r);
      final before = transport.calls.length;
      expect(await r.receiveRemotePushReference(ref), isTrue);
      final newCalls = transport.calls.skip(before);
      expect(newCalls.any((c) => c.operation == 'scopes.list'), isTrue);
      expect(
        newCalls.any(
          (c) => c.operation == 'inbox.open' || c.operation == 'inbox.group',
        ),
        isFalse,
      );
    },
  );

  test(
    'known revoke purges references and prevents later offline access',
    () async {
      final r = await open();
      final (scope, ref) = await createGroup(r);
      await r.openRemotePushReference(ref);
      transport.denyGroup = true;
      expect(
        (await r.openRemotePushReference(ref)).status,
        RemotePushOpenStatus.permissionDenied,
      );
      expect(r.state.scopes.singleWhere((s) => s.id == scope).revoked, isTrue);
      transport.offline = true;
      expect(
        (await r.openRemotePushReference(ref)).status,
        RemotePushOpenStatus.requiresConnection,
      );
      final rows = await r.database.rows(
        "SELECT name FROM local_meta WHERE name LIKE 'push_%'",
      );
      expect(rows, isEmpty);
    },
  );

  test(
    'malicious pagination cannot loop, grow without bound, or present partial targets',
    () async {
      final r = await open();
      final (_, ref) = await createGroup(r);
      final items = transport.items.reversed.map((i) => i.toJson()).toList();
      final cases = <Map<String, dynamic> Function(Map<String, Object?>)>[
        (_) => {'items': [], 'hasMore': true, 'nextBeforeId': 1},
        (_) => {
          'items': [items[0], items[0]],
          'hasMore': false,
        },
        (_) => {
          'items': [items[1], items[0]],
          'hasMore': false,
        },
        (_) => {
          'items': [items[0]],
          'hasMore': true,
          'nextBeforeId': 4,
        },
        (_) => {'items': List.filled(101, items[0]), 'hasMore': false},
      ];
      for (final reply in cases) {
        transport.groupOverride = reply;
        await expectLater(
          r.openRemotePushReference(ref),
          throwsA(code('invalid_response')),
        );
      }
      expect(
        transport.calls.where((c) => c.operation == 'inbox.open'),
        isEmpty,
      );
      final cached = await r.database.rows(
        "SELECT name FROM local_meta WHERE name LIKE 'push_group:%'",
      );
      expect(cached, isEmpty);
    },
  );
  test(
    'bounded group pages preserve all targets and reject excessive groups',
    () async {
      final r = await open();
      await login(r);
      final scope = await r.createScope('Synthetic');
      final id = await r.createTask(scopeId: scope, title: 'Synthetic');
      await r.syncNow();
      for (var i = 1; i <= 101; i++) {
        transport.items.add(
          SharedInboxEntry(
            id: i,
            scopeId: scope,
            kind: 'task.assigned',
            category: 'tasks',
            audience: InboxAudience.personal,
            targetType: 'task',
            targetId: id,
            groupKey: 'synthetic-group',
            createdAt: DateTime.utc(2026, 10, 5, 12),
          ),
        );
      }
      final result = await r.openRemotePushReference(reference(r, 101));
      expect(result.status, RemotePushOpenStatus.available);
      expect(result.target!.inboxIds.length, 101);
      expect(
        transport.calls.where((c) => c.operation == 'inbox.group').length,
        2,
      );
      for (var i = 102; i <= 501; i++) {
        transport.items.add(
          SharedInboxEntry(
            id: i,
            scopeId: scope,
            kind: 'task.assigned',
            category: 'tasks',
            audience: InboxAudience.personal,
            targetType: 'task',
            targetId: id,
            groupKey: 'synthetic-group',
            createdAt: DateTime.utc(2026, 10, 5, 12),
          ),
        );
      }
      final before = transport.calls
          .where((c) => c.operation == 'inbox.open')
          .length;
      await expectLater(
        r.openRemotePushReference(reference(r, 501)),
        throwsA(code('invalid_response')),
      );
      expect(
        transport.calls.where((c) => c.operation == 'inbox.open').length,
        before,
      );
    },
  );
}
