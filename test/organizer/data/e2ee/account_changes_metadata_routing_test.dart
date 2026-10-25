import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../collaboration_repository_test.dart' show MemorySessionStore;

class _Transport implements CollaborationTransport {
  _Transport(this.profile);
  final AccountSession profile;
  final operations = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    if (operation != 'account.changes')
      throw StateError('Unexpected content/auth read $operation');
    return {
      'version': 1,
      'serverId': profile.serverId,
      'accountId': profile.accountId,
      'deviceId': profile.deviceId,
      'cursor': 'unchanged',
      'changed': false,
      'resetRequired': false,
      'hasMore': false,
      'accountDomains': <String>[],
      'scopes': <Object>[],
    };
  }

  @override
  void close() {}
}

void main() {
  for (final fenced in [false, true]) {
    test(
      'actual crypto router account changes bypasses content readiness fenced=$fenced',
      () async {
        final profile = AccountSession(
          serverUrl: 'https://example.test/',
          serverId: newSharedId(),
          accountId: newSharedId(),
          userId: 1,
          username: 'metadata',
          displayName: 'Metadata',
          deviceId: newSharedId(),
          expiresAt: DateTime.utc(2030),
        );
        final store = MemorySessionStore()
          ..value = DeviceSession(profile, 'synthetic');
        final db = CollaborationDatabase(NativeDatabase.memory()),
            transport = _Transport(profile);
        await db.rows('SELECT name FROM local_meta LIMIT 1');
        await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
          'capabilities:${profile.partition}',
          jsonEncode({
            'features': {'recordSync': true},
            'accountChangeVersions': [1],
          }),
        ]);
        await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
          'account_changes_v1:${profile.partition}:${profile.deviceId}',
          'unchanged',
        ]);
        if (fenced)
          await db.execute(
            'INSERT INTO crypto_restore_fences(partition,minimum_transport,backup_id,state) VALUES(?,?,?,?)',
            [
              profile.partition,
              2,
              'synthetic-backup',
              'requires_reconciliation',
            ],
          );
        var cryptoAccountCalls = 0;
        final repo = CollaborationRepository(
          db,
          transport,
          store,
          cryptoRouter: CryptoBusinessRouter(
            database: db,
            accountFor: (_) async {
              cryptoAccountCalls++;
              throw StateError('Metadata must not initialize E2EE account');
            },
          ),
        );
        addTearDown(repo.close);
        await repo.initialize();
        await repo.syncNow();
        expect(transport.operations, ['account.changes']);
        expect(cryptoAccountCalls, 0);
        expect(repo.state.lastError, isNull);
        await expectLater(
          routeProtectedCryptoDomain(
            database: db,
            session: store.value!,
            operation: 'account.changes.reset',
            params: {},
            router: null,
            checkCurrent: () {},
          ),
          throwsA(isA<CollaborationException>()),
        );
      },
    );
  }
}
