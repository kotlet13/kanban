import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
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
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    if (operation == 'inbox.read' && readError != null) {
      throw CollaborationApiException(readError!);
    }
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
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
}
