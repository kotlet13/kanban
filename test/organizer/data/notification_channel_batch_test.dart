import 'dart:convert';
import 'package:kanban/organizer/data/portable_backup_document.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'scheduled_reminder_repository_test.dart' show ReminderTransport;

class PreferencesTransport extends ReminderTransport {
  PreferencesTransport(super.server);
  int recordVersion = 5;
  final saved = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (offline) {
      throw const CollaborationException('network');
    }
    if (operation == 'inbox.preferences.set') {
      (saved[params['scopeId'] as String] ??= {})[params['category']
              as String] =
          params['settings'];
      return {'preferences': saved[params['scopeId']]};
    }
    if (operation == 'inbox.preferences.get') {
      return {'preferences': saved[params['scopeId']] ?? {}};
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation == 'sync5.pull' ? 'sync2.pull' : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities') {
      reply['recordContractVersions'] = [1, 2, if (recordVersion >= 5) 5];
    }
    return reply;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Future<(CollaborationRepository, PreferencesTransport, List<String>)>
  fixture({bool finance = true, int version = 5}) async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    final transport = PreferencesTransport(FakeServer())
      ..financeEnabled = finance
      ..recordVersion = version;
    final repo = CollaborationRepository(db, transport, MemorySessionStore());
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.test/',
      username: 'alice',
      password: 'synthetic',
    );
    final scopes = [
      await repo.createScope('Home'),
      await repo.createScope('Organization'),
    ];
    await repo.syncNow();
    addTearDown(repo.close);
    return (repo, transport, scopes);
  }

  test(
    'bulk channel retains other flags and Ideas, queues offline and survives server ACK',
    () async {
      final (repo, transport, scopes) = await fixture();
      final p = repo.state.session!.partition;
      transport.offline = true;
      for (final id in scopes) {
        await repo.setNotificationPreferences(
          scopeId: id,
          category: 'ideas',
          settings: const SharedNotificationSettings(
            push: false,
            email: true,
            inApp: false,
          ),
        );
      }
      await repo.setNotificationChannel(
        scopeIds: scopes,
        channel: 'sound',
        enabled: true,
        expectedPartition: p,
      );
      for (final id in scopes) {
        final saved = repo.state.notificationPreferences[id]!;
        expect(saved.categories, hasLength(7));
        expect(saved.forCategory('ideas').toJson(), {
          'inApp': false,
          'push': false,
          'sound': true,
          'email': true,
        });
        expect(saved.forCategory('tasks').push, isTrue);
        expect(saved.forCategory('tasks').email, isFalse);
      }
      final queued = await repo.database.rows('SELECT * FROM commands');
      expect(queued, hasLength(16));
      for (final row in queued) {
        validateBackupCommand(
          row['operation'] as String,
          jsonDecode(row['params'] as String) as Map<String, dynamic>,
          scopes.toSet(),
        );
      }
      transport.offline = false;
      await repo.syncNow();
      expect(await repo.database.rows('SELECT * FROM commands'), isEmpty);
      expect(
        repo.state.notificationPreferences[scopes.first]!
            .forCategory('ideas')
            .sound,
        isTrue,
      );
      expect(
        repo.state.notificationPreferences[scopes.first]!
            .forCategory('ideas')
            .push,
        isFalse,
      );
      expect(transport.saved[scopes.first]!.keys, contains('ideas'));
    },
  );
  test(
    'one invalid target rolls back all preference and queue writes',
    () async {
      final (repo, _, scopes) = await fixture();
      final before = await repo.database.rows(
        'SELECT * FROM notification_preferences',
      );
      await expectLater(
        repo.setNotificationChannel(
          scopeIds: [...scopes, newSharedId()],
          channel: 'sound',
          enabled: true,
          expectedPartition: repo.state.session!.partition,
        ),
        throwsA(isA<CollaborationException>()),
      );
      expect(
        await repo.database.rows('SELECT * FROM notification_preferences'),
        before,
      );
      expect(await repo.database.rows('SELECT * FROM commands'), isEmpty);
    },
  );
  test('stale account partition rejects the entire batch', () async {
    final (repo, _, scopes) = await fixture();
    await expectLater(
      repo.setNotificationChannel(
        scopeIds: scopes,
        channel: 'push',
        enabled: false,
        expectedPartition: 'another-account',
      ),
      throwsA(
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'session_changed',
        ),
      ),
    );
    expect(await repo.database.rows('SELECT * FROM commands'), isEmpty);
  });
  test(
    'older server and unreadable finance do not get unsupported category commands',
    () async {
      final (repo, _, scopes) = await fixture(finance: false, version: 2);
      await repo.setNotificationChannel(
        scopeIds: scopes,
        channel: 'push',
        enabled: false,
        expectedPartition: repo.state.session!.partition,
      );
      final commands = await repo.database.rows('SELECT params FROM commands');
      final categories = commands
          .map((r) => (jsonDecode(r['params'] as String) as Map)['category'])
          .toSet();
      expect(categories, isNot(contains('ideas')));
      expect(categories, isNot(contains('finance')));
      expect(commands, hasLength(10));
    },
  );
  test(
    'failure after the first scope write rolls back the whole batch',
    () async {
      final (repo, _, scopes) = await fixture();
      final partition = repo.state.session!.partition;
      final before = await repo.database.rows(
        'SELECT * FROM notification_preferences',
      );
      await repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        ['project_sharing_pending:$partition:${scopes.last}', '1'],
      );
      await expectLater(
        repo.setNotificationChannel(
          scopeIds: scopes,
          channel: 'sound',
          enabled: true,
          expectedPartition: partition,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'project_sharing_pending_changes',
          ),
        ),
      );
      expect(
        await repo.database.rows('SELECT * FROM notification_preferences'),
        before,
      );
      expect(await repo.database.rows('SELECT * FROM commands'), isEmpty);
    },
  );
  test(
    'shared cache keeps materialized saved sound flags byte-exact; missing sound alone defaults true',
    () async {
      final (repo, transport, scopes) = await fixture();
      final original = {
        for (final category in sharedNotificationCategories)
          category: {
            'inApp': true,
            'push': true,
            'sound': false,
            'email': false,
          },
      };
      original['ideas'] = {'inApp': false};
      original['events'] = {'sound': true};
      transport.saved[scopes.first] = original;
      await repo.syncNow();
      final cached = await repo.database.rows(
        'SELECT data FROM notification_preferences WHERE scope_id=?',
        [scopes.first],
      );
      expect(cached.single['data'], jsonEncode(original));
      final prefs = repo.state.notificationPreferences[scopes.first]!;
      for (final category in sharedNotificationCategories.where(
        (v) => v != 'ideas' && v != 'events',
      )) {
        expect(prefs.forCategory(category).sound, isFalse);
      }
      expect(prefs.forCategory('ideas').sound, isTrue);
      expect(prefs.forCategory('events').sound, isTrue);
      expect(
        repo.state.notificationPreferences[scopes.last]!
            .forCategory('reminders')
            .sound,
        isTrue,
      );
      expect(await repo.database.rows('SELECT * FROM commands'), isEmpty);
      await repo.refreshLocal();
      expect(
        (await repo.database.rows(
          'SELECT data FROM notification_preferences WHERE scope_id=?',
          [scopes.first],
        )).single['data'],
        jsonEncode(original),
      );
      transport.offline = true;
      await repo.setNotificationChannel(
        scopeIds: [scopes.first],
        channel: 'push',
        enabled: false,
        expectedPartition: repo.state.session!.partition,
        category: 'tasks',
      );
      expect(
        repo.state.notificationPreferences[scopes.first]!
            .forCategory('tasks')
            .sound,
        isFalse,
      );
      expect(
        (jsonDecode(
              (await repo.database.rows(
                    'SELECT params FROM commands',
                  )).single['params']
                  as String,
            )
            as Map)['settings']['sound'],
        false,
      );
    },
  );
}
