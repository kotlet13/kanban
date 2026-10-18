import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:sodium/sodium.dart' show SodiumInit;
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/crypto_read_retry.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test(
    'normal read throttle remains resumable and disposal cancels before a second HTTP',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var current = true, calls = 0, invalidations = 0;
      final paused = Completer<void>();
      final transport = HttpCollaborationTransport(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'v': 1,
              'error': {
                'code': 'rate_limited',
                'details': {'retryAfter': 30},
              },
            }),
            429,
          );
        }),
      );
      addTearDown(transport.close);
      final result = expectLater(
        cryptoReadWithRatePause(
          database: db,
          partition: 'own',
          scopeId: 'scope',
          domain: 'content',
          isCurrent: () => current,
          invalidateOperation: () {
            invalidations++;
            if (!paused.isCompleted) paused.complete();
          },
          read: () => transport.call(
            serverUrl: 'http://127.0.0.1/',
            operation: 'crypto2.blob.get',
            allowLocalHttp: true,
          ),
        ),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      await paused.future;
      current = false;
      await result.timeout(const Duration(seconds: 2));
      expect(calls, 1);
      expect(invalidations, greaterThanOrEqualTo(1));
      expect(
        (await db.rows('SELECT value FROM local_meta WHERE name=?', [
          'crypto_read_retry:own:scope:content',
        ])),
        hasLength(1),
      );
      expect(
        await db.rows('SELECT 1 FROM crypto_received_candidates'),
        isEmpty,
      );
    },
  );
  test(
    'closing a durably paused coordinator cancels its timer before another HTTP',
    () async {
      var calls = 0;
      final transport = HttpCollaborationTransport(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'v': 1,
              'error': {
                'code': 'rate_limited',
                'details': {'retryAfter': 30},
              },
            }),
            429,
          );
        }),
      );
      final db = CollaborationDatabase(NativeDatabase.memory());
      final crypto = CryptoCodec(await SodiumInit.init());
      final login = DeviceSession(
        AccountSession(
          serverUrl: 'http://127.0.0.1/',
          serverId: crypto.randomId(),
          accountId: crypto.randomId(),
          userId: 1,
          username: 'synthetic',
          displayName: 'Synthetic',
          deviceId: crypto.randomId(),
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          allowLocalHttp: true,
        ),
        'synthetic',
      );
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: login,
          transport: transport,
          store: CryptoIdentityStore(db, _Secure(), login.profile.partition),
          isCurrent: () => true,
        ),
      );
      final coordinator = CryptoMigrationCoordinator(account: account);
      final paused = Completer<void>();
      final listener = coordinator.changes.listen((state) {
        if (state.retryAfterSeconds == 30 && !paused.isCompleted) {
          paused.complete();
        }
      });
      final outcome = expectLater(
        coordinator.prepare(crypto.randomId()),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      try {
        await paused.future.timeout(const Duration(seconds: 5));
        expect(calls, 1);
        final saved = (await db.rows(
          'SELECT journal FROM crypto_migrations',
        )).single;
        expect(
          (jsonDecode(saved['journal'] as String) as Map)['retryNotBefore'],
          greaterThan(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        );
        await coordinator.close();
        await outcome;
        expect(calls, 1);
      } finally {
        await listener.cancel();
        await coordinator.close();
        await db.close();
        transport.close();
      }
    },
  );
  test(
    'scoped RetryAfter repeats exact encoded intent, ordinary callers still pause explicitly',
    () async {
      final bodies = <String>[];
      var deny = true, pauses = 0;
      final transport = HttpCollaborationTransport(
        client: MockClient((request) async {
          bodies.add(request.body);
          if (deny) {
            deny = false;
            return http.Response(
              jsonEncode({
                'v': 1,
                'error': {
                  'code': 'rate_limited',
                  'details': {'retryAfter': 1},
                },
              }),
              429,
            );
          }
          return http.Response(
            jsonEncode({
              'v': 1,
              'data': {'accepted': true},
            }),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      final params = <String, Object?>{'requestId': 'original', 'value': 7};
      final result = await withCollaborationRateLimitPause(
        () => transport.call(
          serverUrl: 'http://127.0.0.1/',
          operation: 'crypto2.test',
          params: params,
          allowLocalHttp: true,
        ),
        pause: (seconds) async {
          expect(seconds, 1);
          pauses++;
          params['requestId'] = 'changed outside transport';
        },
      );
      expect(result, {'accepted': true});
      expect(pauses, 1);
      expect(bodies, hasLength(2));
      expect(bodies[1], bodies[0]);
      expect(jsonDecode(bodies[0])['params']['requestId'], 'original');
      deny = true;
      await expectLater(
        transport.call(
          serverUrl: 'http://127.0.0.1/',
          operation: 'crypto2.test',
          allowLocalHttp: true,
        ),
        throwsA(isA<CollaborationApiException>()),
      );
      expect(bodies, hasLength(3));
    },
  );

  test('cancel and non-rate authorization failure never repeat HTTP', () async {
    for (final code in ['rate_limited', 'permission_revoked']) {
      var calls = 0;
      final transport = HttpCollaborationTransport(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'v': 1,
              'error': {
                'code': code,
                'details': {'retryAfter': 1},
              },
            }),
            403,
          );
        }),
      );
      try {
        await expectLater(
          withCollaborationRateLimitPause(
            () => transport.call(
              serverUrl: 'http://127.0.0.1/',
              operation: 'crypto2.test',
              allowLocalHttp: true,
            ),
            pause: (_) async => throw StateError('cancelled'),
          ),
          throwsA(
            code == 'rate_limited'
                ? isA<StateError>()
                : isA<CollaborationApiException>(),
          ),
        );
        expect(calls, 1);
      } finally {
        transport.close();
      }
    }
  });
}
