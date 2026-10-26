import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_account_changes.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;
import 'inbox_retention_test.dart' show InboxTransport;

// Exercise the legacy inbox adapter without inventing E2EE authority.
class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) => throw StateError('Unexpected protected crypto dispatch');
}

class _Transport extends InboxTransport {
  final operations = <String>[];
  String? readError;
  MemorySessionStore? changeStore;
  int? notificationVersion = 1;
  bool configChanged = false;
  List<String> domains = ['inbox'];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    if (operation == 'account.changes' && changeStore != null) {
      final session = changeStore!.value!.profile;
      final reset = params['cursor'] == null;
      return {
        'version': 1,
        'serverId': session.serverId,
        'accountId': session.accountId,
        'deviceId': session.deviceId,
        'cursor': 'configuration-cursor',
        'changed': reset || domains.isNotEmpty,
        'resetRequired': reset,
        'accountDomains': domains,
        'scopes': <Object>[],
        'hasMore': false,
        if (notificationVersion != null) ...{
          'notificationHintsVersion': notificationVersion,
          'notificationConfigurationChanged': configChanged,
        },
      };
    }
    if (operation == 'inbox.read' && readError != null) {
      throw CollaborationApiException(readError!);
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities' && changeStore != null) {
      return {
        ...reply,
        'accountChanges': true,
        'accountChangeVersions': [1],
      };
    }
    return reply;
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  for (final outcome in [
    'empty',
    'ack',
    'notification_missing',
    'inbox_conflict',
  ]) {
    test(
      'coordinator inbox second pull only follows a remote command: $outcome',
      () async {
        final transport = _Transport()..serverReadAt = DateTime.now().toUtc();
        final repo = CollaborationRepository(
          CollaborationDatabase(NativeDatabase.memory()),
          transport,
          MemorySessionStore(),
          contentRouteGuard: const SyntheticContentRouteGuard(),
          cryptoRouter: _LegacyRouter(),
        );
        addTearDown(repo.close);
        await repo.initialize();
        await repo.login(
          serverUrl: 'https://synthetic.invalid',
          username: 'alice',
          password: 'synthetic',
        );
        final scope = await repo.createScope('Inbox optimization fixture');
        transport.inbox = [
          SharedInboxEntry(
            id: 1,
            revision: 1,
            sequence: 1,
            scopeId: scope,
            kind: 'task.created',
            category: 'tasks',
            audience: InboxAudience.scope,
            targetType: 'task',
            targetId: 'task',
            groupKey: 'task',
            createdAt: DateTime.now().toUtc(),
          ),
        ];
        await repo.syncNow();
        expect(repo.state.lastError, isNull);
        if (outcome != 'empty') await repo.markInboxRead([1]);
        if (outcome == 'notification_missing') {
          transport.missingRead = true;
          transport.inbox = [];
        }
        if (outcome == 'inbox_conflict') transport.readError = outcome;
        transport.operations.clear();
        await repo.syncNow();
        expect(
          transport.operations.where((op) => op == 'inbox.sync').length,
          outcome == 'empty' ? 1 : 2,
        );
        expect(
          transport.operations.where((op) => op == 'inbox.read').length,
          outcome == 'empty' ? 0 : 1,
        );
        final commands = await repo.database.rows('SELECT state FROM commands');
        if (outcome == 'inbox_conflict') {
          expect(commands.single['state'], 'blocked');
        } else {
          expect(commands, isEmpty);
          expect(repo.state.lastError, isNull);
        }
        expect(
          repo.state.scopes.singleWhere((s) => s.id == scope).canRead,
          isTrue,
        );
        if (outcome == 'ack') expect(repo.state.inbox.single.isRead, isTrue);
        if (outcome == 'notification_missing') {
          expect(repo.state.inbox, isEmpty);
        }
      },
    );
  }
  for (final hint in [
    'inbox',
    'configuration',
    'access',
    'legacy',
    'unknown',
    'command',
  ]) {
    test('coordinator configuration selection: $hint', () async {
      final store = MemorySessionStore();
      final transport = _Transport()
        ..changeStore = store
        ..serverReadAt = DateTime.now().toUtc();
      final repo = CollaborationRepository(
        CollaborationDatabase(NativeDatabase.memory()),
        transport,
        store,
        contentRouteGuard: const SyntheticContentRouteGuard(),
        cryptoRouter: _LegacyRouter(),
      );
      addTearDown(repo.close);
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://synthetic.invalid',
        username: 'alice',
        password: 'synthetic',
      );
      final scope = await repo.createScope('Configuration A');
      await repo.createScope('Configuration B');
      transport.inbox = [
        SharedInboxEntry(
          id: 1,
          revision: 1,
          sequence: 1,
          scopeId: scope,
          kind: 'task.created',
          category: 'tasks',
          audience: InboxAudience.scope,
          targetType: 'task',
          targetId: 'task',
          groupKey: 'task',
          createdAt: DateTime.now().toUtc(),
        ),
      ];
      await repo.syncNow();
      expect(repo.state.lastError, isNull);
      if (hint == 'configuration') transport.configChanged = true;
      if (hint == 'access') transport.domains = ['access'];
      if (hint == 'legacy') transport.notificationVersion = null;
      if (hint == 'unknown') transport.notificationVersion = 99;
      if (hint == 'command') await repo.markInboxRead([1]);
      transport.operations.clear();
      await repo.syncNow();
      expect(repo.state.lastError, isNull);
      final configReads = hint == 'inbox' ? 0 : 2;
      expect(
        transport.operations.where((v) => v == 'inbox.preferences.get').length,
        configReads,
      );
      expect(
        transport.operations.where((v) => v == 'reminders.list').length,
        configReads,
      );
      expect(
        transport.operations.where((v) => v == 'inbox.sync').length,
        hint == 'access'
            ? 0
            : hint == 'command'
            ? 2
            : 1,
      );
      expect(repo.state.scopes.where((s) => s.canRead).length, 2);
    });
  }
  test('coordinator rejects malformed explicit notification hint', () {
    expect(
      () => CollaborationAccountChanges.parse(
        {
          'version': 1,
          'serverId': 's',
          'accountId': 'a',
          'deviceId': 'd',
          'cursor': 'c',
          'changed': true,
          'resetRequired': false,
          'hasMore': false,
          'scopes': <Object>[],
          'accountDomains': ['inbox'],
          'notificationHintsVersion': 1,
          'notificationConfigurationChanged': 'false',
        },
        serverId: 's',
        accountId: 'a',
        deviceId: 'd',
      ),
      throwsFormatException,
    );
  });
}
