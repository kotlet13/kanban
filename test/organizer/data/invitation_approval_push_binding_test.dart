import '../support/synthetic_content_route_guard.dart';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart'
    show CollaborationApiException;
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, MemorySessionStore, code;
import 'remote_push_test_support.dart';

/// This legacy notification seam has no crypto identity or projection cursor.
/// The explicit content guard permits only the synthetic legacy transport;
/// unexpectedly dispatching any protected crypto operation still fails closed.
class _SyntheticNotificationRouter implements CryptoDomainRouter {
  const _SyntheticNotificationRouter();
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError(
    'Unexpected crypto dispatch in legacy notification seam',
  );
}

class _Transport extends PushTransport {
  _Transport(super.server);
  bool substitute = false;
  bool readMissing = false;
  final operationNames = <String>[];
  final capabilityInboxFlags = <bool>[];
  final terminalReadErrors = <String>[];
  Future<Map<String, dynamic>> Function(Map<String, Object?>)? listReply;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operationNames.add(operation);
    if (operation == 'inbox.read' && readMissing) {
      terminalReadErrors.add('notification_missing');
      throw const CollaborationApiException('notification_missing');
    }
    if (operation == 'inbox.list' && listReply != null) {
      return listReply!(params);
    }
    if (readMissing) {
      if (operation == 'inbox.sync') {
        return {
          'items': [],
          'cursor': 0,
          'hasMore': false,
          'visibilityRevision': 1,
        };
      }
      if (operation == 'inbox.preferences.get') return {'preferences': {}};
      if (operation == 'reminders.list') {
        return {'reminders': [], 'hasMore': false, 'nextBeforeId': null};
      }
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities' && readMissing) {
      capabilityInboxFlags.add(true);
      return {
        ...reply,
        'features': {
          ...Map<String, dynamic>.from(reply['features'] as Map),
          'inbox': true,
        },
      };
    }
    if (operation == 'capabilities') capabilityInboxFlags.add(false);
    if (operation == 'inbox.open' && substitute) {
      final item = Map<String, dynamic>.from(reply['item'] as Map);
      item['invitationAcceptance'] = {
        ...Map<String, dynamic>.from(item['invitationAcceptance'] as Map),
        'acceptanceProofHash': List.filled(64, 'd').join(),
      };
      return {...reply, 'item': item};
    }
    return reply;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CollaborationRepository repository;
  late _Transport transport;
  late RemotePushReference reference;
  setUp(() async {
    final server = FakeServer();
    transport = _Transport(server);
    repository = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: const _SyntheticNotificationRouter(),
    );
    await repository.initialize();
    await repository.login(
      serverUrl: 'https://synthetic.invalid/kanboard',
      username: 'alice',
      password: 'synthetic',
    );
    final scope = await repository.createScope('Synthetic owner scope');
    const id = '80000000-0000-4000-8000-000000000003';
    transport.items.add(
      SharedInboxEntry(
        id: 1,
        revision: 1,
        sequence: 1,
        scopeId: scope,
        kind: InvitationAcceptanceNotification.kind,
        category: 'membership',
        audience: InboxAudience.personal,
        targetType: 'membership',
        targetId: id,
        groupKey: id,
        createdAt: DateTime.utc(2026),
        invitationAcceptance: InvitationAcceptanceNotification(
          scopeId: scope,
          invitationId: id,
          acceptanceProofHash: List.filled(64, 'a').join(),
          creatorProofHash: List.filled(64, 'b').join(),
          tokenHash: List.filled(64, 'c').join(),
        ),
      ),
    );
    final session = repository.state.session!;
    reference = RemotePushReference(
      serverId: session.serverId,
      accountId: session.accountId,
      notificationId: 1,
    );
  });
  tearDown(() async => repository.close());
  Future<void> seed(SharedInboxEntry entry) async {
    await repository.database.execute(
      'INSERT INTO inbox(partition,id,data) VALUES(?,?,?)',
      [
        repository.state.session!.partition,
        entry.id,
        jsonEncode(entry.toJson()),
      ],
    );
    await repository.refreshLocal();
  }

  SharedInboxEntry other(int id, {bool approval = false}) {
    final source = transport.items.single;
    return SharedInboxEntry.fromJson({
      ...source.toJson(),
      'id': id,
      if (!approval) ...{'kind': 'member.joined', 'invitationAcceptance': null},
    });
  }

  test(
    'fresh wire serialized host accepted notice opens exact current invitation',
    () async {
      final original = transport.items.single;
      final wire = {...original.toJson(), 'kind': 'invitation.accepted'};
      transport.items[0] = SharedInboxEntry.fromJson(wire);
      final result = await repository.openRemotePushReference(reference);
      expect(result.status, RemotePushOpenStatus.available);
      expect(
        result.target!.invitationAcceptance!.same(
          original.invitationAcceptance,
        ),
        isTrue,
      );
    },
  );
  test(
    'completed notice refresh preserves unrelated and newly received exact events',
    () async {
      await seed(transport.items.single);
      await seed(other(2));
      transport.listReply = (_) async {
        await seed(other(3, approval: true));
        return {'items': [], 'hasMore': false, 'nextBeforeId': null};
      };
      await repository.refreshInvitationApprovalInbox(isCurrent: () => true);
      expect(repository.state.inbox.map((e) => e.id).toSet(), {2, 3});
      expect(
        transport.calls.where((c) => c.operation.startsWith('sync')),
        isEmpty,
      );
    },
  );
  test(
    'completed notice refresh preserves exact pending on incomplete bounded snapshot',
    () async {
      await seed(transport.items.single);
      var pages = 0;
      transport.listReply = (params) async {
        pages++;
        return {'items': [], 'hasMore': true, 'nextBeforeId': 100 - pages};
      };
      await repository.refreshInvitationApprovalInbox(isCurrent: () => true);
      expect(pages, 5);
      expect(repository.state.inbox.single.id, 1);
    },
  );
  test(
    'completed notice refresh rechecks foreground identity before local mutation',
    () async {
      await seed(transport.items.single);
      var current = true;
      transport.listReply = (_) async {
        current = false;
        return {'items': [], 'hasMore': false, 'nextBeforeId': null};
      };
      await repository.refreshInvitationApprovalInbox(isCurrent: () => current);
      expect(repository.state.inbox.single.id, 1);
    },
  );
  test(
    'queued accepted notice read survives display refresh then safely retires without blocking scope',
    () async {
      await seed(transport.items.single);
      await repository.markInboxRead([1]);
      final before = await repository.database.rows(
        'SELECT * FROM commands ORDER BY sequence',
      );
      expect(before.length, 1);
      transport.listReply = (_) async => {
        'items': [],
        'hasMore': false,
        'nextBeforeId': null,
      };
      await repository.refreshInvitationApprovalInbox(isCurrent: () => true);
      expect(repository.state.inbox.single.id, 1);
      expect(
        await repository.database.rows(
          'SELECT * FROM commands ORDER BY sequence',
        ),
        before,
      );
      transport.readMissing = true;
      expect(
        await repository.database.rows('SELECT 1 FROM crypto_scope_state'),
        isEmpty,
      );
      final syncTraceStart = transport.operationNames.length;
      await repository.syncNow();
      final after = await repository.database.rows(
        'SELECT state FROM commands ORDER BY sequence',
      );
      final completion = repository.lastSyncCompletion;
      String? safeError(Object? value) => value == null
          ? null
          : value is CollaborationException
          ? value.code
          : value.runtimeType.toString();
      // Bounded synthetic test evidence, without payloads, tokens or keys.
      // ignore: avoid_print
      print(
        'INVITATION_APPROVAL_DIAGNOSTIC ${jsonEncode({
          'phase': 'queued_read_after_sync',
          'operations': transport.operationNames.skip(syncTraceStart).toList(),
          'capabilityInboxFlags': transport.capabilityInboxFlags,
          'terminalReadErrors': transport.terminalReadErrors,
          'inboxSupported': repository.state.inboxSupported,
          'inboxCount': repository.state.inbox.length,
          'commands': after.map((row) => row['state']).toList(),
          'error': safeError(repository.state.lastError),
          'scopeBlocked': repository.state.scopes.map((s) => s.blocked).toList(),
          'scopeRevoked': repository.state.scopes.map((s) => s.revoked).toList(),
          'completion': completion == null ? null : {'sequence': completion.sequence, 'error': safeError(completion.error), 'workUnresolved': completion.work.unresolved},
        })}',
      );
      expect(completion, isNotNull);
      expect(completion!.error, isNull);
      expect(
        transport.operationNames.skip(syncTraceStart),
        contains('inbox.read'),
      );
      expect(transport.terminalReadErrors, ['notification_missing']);
      expect(repository.state.inbox, isEmpty);
      expect(await repository.database.rows('SELECT * FROM commands'), isEmpty);
      expect(repository.state.scopes.single.blocked, isFalse);
      expect(repository.state.scopes.single.revoked, isFalse);
      expect(repository.state.lastError, isNull);
    },
  );
  test(
    'accepted invitation push resolves exact authenticated invitation without key writes',
    () async {
      final result = await repository.openRemotePushReference(reference);
      expect(result.status, RemotePushOpenStatus.available);
      expect(
        result.target!.invitationAcceptance!.same(
          transport.items.single.invitationAcceptance,
        ),
        isTrue,
      );
      expect(result.target!.records.single.type, 'membership');
      expect(
        transport.calls.where((c) => c.operation == 'inbox.open').length,
        1,
      );
      expect(
        transport.calls.where((c) => c.operation.startsWith('crypto2.scope.')),
        isEmpty,
      );
    },
  );
  test(
    'accepted invitation open rejects changed authenticated acceptance hint',
    () async {
      transport.substitute = true;
      await expectLater(
        repository.openRemotePushReference(reference),
        throwsA(code('invalid_notification_target')),
      );
    },
  );
  test(
    'cached accepted invitation push cannot open manual approval offline',
    () async {
      final initial = await repository.openRemotePushReference(reference);
      expect(initial.status, RemotePushOpenStatus.available);
      transport.offline = true;
      final offline = await repository.openRemotePushReference(reference);
      expect(offline.status, RemotePushOpenStatus.requiresConnection);
      expect(offline.target!.invitationAcceptance, isNotNull);
    },
  );
}
