import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kanban/organizer/data/account_work_coordinator.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/crypto_authority_snapshot.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

void main() {
  late AccountWorkCoordinator coordinator;
  late AccountWorkOwner owner;
  late DateTime now;
  var current = true;
  setUp(() {
    now = DateTime.utc(2026, 10, 24);
    current = true;
    coordinator = AccountWorkCoordinator(clock: () => now);
    owner = AccountWorkOwner(
      serverUrl: 'https://synthetic.invalid/',
      identity: Object(),
      isCurrent: () => current,
    );
  });
  tearDown(() => coordinator.close());

  Future<Map<String, dynamic>> request(
    String op,
    CollaborationAttempt send, {
    Map<String, Object?> params = const {},
  }) => coordinator.runAttempt(
    owner: owner,
    operation: op,
    params: params,
    send: send,
  );

  test(
    'reads bound concurrency while exact mutation dispatch never waits behind them',
    () async {
      final release = Completer<Map<String, dynamic>>();
      var started = 0;
      Future<Map<String, dynamic>> read() {
        started++;
        return release.future;
      }

      final a = request('crypto2.directory.status', read);
      final b = request('crypto2.scope.headGet', read);
      final c = request('crypto2.records.pull', read);
      expect(started, 2);
      var sent = false;
      const exact = 'original-opaque-command-bytes';
      await request('crypto2.records.write', () async {
        sent = true;
        return {'proof': exact};
      }, params: {'commandBase64': exact});
      expect(sent, isTrue);
      expect(started, 2);
      now = now.add(const Duration(milliseconds: 100));
      release.complete({'read': true});
      await Future.wait([a, b, c]);
      expect(started, 3);
      final startedEvents = coordinator.events.where(
        (e) => e.event == AccountWorkEventKind.started,
      );
      expect(startedEvents.every((e) => e.activeReads <= 2), isTrue);
      expect(startedEvents.last.queueWait, const Duration(milliseconds: 100));
    },
  );

  test(
    'same explicit phase shares only pending hint and isolates consumer maps',
    () async {
      var calls = 0;
      await coordinator.withJob(AccountWorkKind.sync, () async {
        final release = Completer<Map<String, dynamic>>();
        Future<Map<String, dynamic>> send() {
          calls++;
          return release.future;
        }

        final a = request(
          'account.changes',
          send,
          params: {'cursor': 'opaque'},
        );
        final b = request(
          'account.changes',
          send,
          params: {'cursor': 'opaque'},
        );
        expect(calls, 1);
        release.complete({
          'nested': {'value': 1},
        });
        final values = await Future.wait([a, b]);
        values.first['nested']['value'] = 2;
        expect(values.last['nested']['value'], 1);
        await request('account.changes', () async {
          calls++;
          return {};
        }, params: {'cursor': 'opaque'});
        expect(calls, 2, reason: 'completed replies are never cached');
      });
      expect(
        coordinator.events.where((e) => e.event == AccountWorkEventKind.shared),
        hasLength(1),
      );
    },
  );

  test(
    'crypto proofs and receipts stay independent and are not JSON cloned',
    () async {
      await coordinator.withJob(AccountWorkKind.protection, () async {
        for (final op in ['crypto2.directory.status', 'crypto2.receipt.get']) {
          final release = Completer<Map<String, dynamic>>();
          var calls = 0;
          Future<Map<String, dynamic>> send() {
            calls++;
            return release.future;
          }

          final a = request(op, send), b = request(op, send);
          expect(calls, 2);
          final proof = <String, dynamic>{'opaque': Object()};
          release.complete(proof);
          final values = await Future.wait([a, b]);
          expect(identical(values.first, proof), isTrue);
          expect(identical(values.last, proof), isTrue);
        }
      });
      expect(
        coordinator.events.where((e) => e.event == AccountWorkEventKind.shared),
        isEmpty,
      );
    },
  );

  test(
    'independent phases late joins and mutation barriers do not share hints',
    () async {
      Future<void> exercise({
        required bool separate,
        required bool late,
        required bool mutation,
      }) async {
        final release = Completer<Map<String, dynamic>>();
        var calls = 0;
        Future<Map<String, dynamic>> send() {
          calls++;
          return release.future;
        }

        Future<void> body() async {
          final a = request('capabilities', send);
          if (late) now = now.add(const Duration(seconds: 5));
          if (mutation) await request('unclassified.operation', () async => {});
          final b = separate
              ? runZoned(() => request('capabilities', send))
              : request('capabilities', send);
          // Independent withJob phases are created outside the outer phase below.
          release.complete({});
          await Future.wait([a, b]);
        }

        if (separate) {
          final a = coordinator.withJob(
            AccountWorkKind.account,
            () => request('capabilities', send),
          );
          final b = coordinator.withJob(
            AccountWorkKind.account,
            () => request('capabilities', send),
          );
          release.complete({});
          await Future.wait([a, b]);
        } else {
          await coordinator.withJob(AccountWorkKind.account, body);
        }
        expect(calls, 2);
      }

      await exercise(separate: true, late: false, mutation: false);
      await exercise(separate: false, late: true, mutation: false);
      await exercise(separate: false, late: false, mutation: true);
    },
  );

  test(
    'stale owner rejects queued work and in-flight result without sending queued request',
    () async {
      coordinator = AccountWorkCoordinator(
        clock: () => now,
        maxConcurrentReads: 1,
      );
      final release = Completer<Map<String, dynamic>>();
      var sends = 0;
      final a = request('crypto2.account.status', () {
        sends++;
        return release.future;
      });
      final b = request('crypto2.directory.status', () async {
        sends++;
        return {};
      });
      final ae = expectLater(a, throwsA(isA<CollaborationException>()));
      final be = expectLater(b, throwsA(isA<CollaborationException>()));
      current = false;
      coordinator.cancelStale();
      release.complete({});
      await Future.wait([ae, be]);
      expect(sends, 1);
    },
  );

  test(
    'observed cooldown rejects reads and mutations without extending its deadline',
    () async {
      var sends = 0;
      await expectLater(
        request('crypto2.account.status', () async {
          sends++;
          throw const CollaborationApiException(
            'rate_limited',
            details: {'retryAfter': 10},
          );
        }),
        throwsA(isA<CollaborationApiException>()),
      );
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(milliseconds: 100));
        await expectLater(
          request(
            i.isEven ? 'crypto2.scope.headGet' : 'unknown.mutation',
            () async {
              sends++;
              return {};
            },
          ),
          throwsA(isA<CollaborationApiException>()),
        );
      }
      expect(sends, 1);
      now = DateTime.utc(2026, 10, 24).add(const Duration(seconds: 10));
      await request('crypto2.account.status', () async {
        sends++;
        return {};
      });
      expect(sends, 2);
    },
  );

  test(
    'bounded pending reads reject overload and close cancels unsent work',
    () async {
      coordinator = AccountWorkCoordinator(
        clock: () => now,
        maxConcurrentReads: 1,
        maxPendingReads: 1,
      );
      final release = Completer<Map<String, dynamic>>();
      var sends = 0;
      final active = request('crypto2.account.status', () {
        sends++;
        return release.future;
      });
      final pending = request('crypto2.directory.status', () async {
        sends++;
        return {};
      });
      final activeError = expectLater(
        active,
        throwsA(isA<CollaborationException>()),
      );
      final pendingError = expectLater(
        pending,
        throwsA(isA<CollaborationException>()),
      );
      await expectLater(
        request('crypto2.scope.headGet', () async {
          sends++;
          return {};
        }),
        throwsA(
          isA<CollaborationApiException>().having(
            (e) => e.code,
            'code',
            'account_work_overloaded',
          ),
        ),
      );
      coordinator.close();
      release.complete({});
      await Future.wait([activeError, pendingError]);
      expect(sends, 1);
    },
  );

  test(
    'HTTP single-attempt seam releases before explicit pause and retains exact body',
    () async {
      coordinator = AccountWorkCoordinator(
        clock: () => now,
        maxConcurrentReads: 1,
      );
      final bodies = <String>[];
      var capabilities = 0;
      final raw = HttpCollaborationTransport(
        client: MockClient((req) async {
          final body = jsonDecode(req.body) as Map;
          if (body['op'] == 'capabilities') {
            bodies.add(req.body);
            if (capabilities++ == 0) {
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
          }
          return http.Response(
            jsonEncode({
              'v': 1,
              'data': {'ok': true},
            }),
            200,
          );
        }),
      );
      final wrapped = CoordinatedCollaborationTransport(
        inner: raw,
        coordinator: coordinator,
        ownerFor: (_, __, ___, ____) => owner,
      );
      addTearDown(wrapped.close);
      var pauses = 0;
      final reply = await withCollaborationRateLimitPause(
        () => wrapped.call(
          serverUrl: owner.serverUrl,
          operation: 'capabilities',
          params: {'opaque': 'original'},
        ),
        pause: (seconds) async {
          pauses++;
          now = now.add(Duration(seconds: seconds));
          final nested = await wrapped.call(
            serverUrl: owner.serverUrl,
            operation: 'account.changes',
          );
          expect(nested['ok'], isTrue);
        },
      );
      expect(reply['ok'], isTrue);
      expect(pauses, 1);
      expect(bodies, hasLength(2));
      expect(bodies.first, bodies.last);
    },
  );

  test(
    'queued proof crossing original authority lease is freshly read instead of retained',
    () async {
      coordinator = AccountWorkCoordinator(
        clock: () => now,
        maxConcurrentReads: 1,
      );
      final started = now;
      final release = Completer<Map<String, dynamic>>();
      final blocker = request('crypto2.account.status', () => release.future);
      var proofReads = 0;
      final snapshot = CryptoAuthoritySnapshot(
        serverId: 'synthetic-server',
        accountId: 'synthetic-account',
        deviceId: 'synthetic-device',
        isValid: () async =>
            now.difference(started) < const Duration(seconds: 5),
        onMutation: () => fail('read must not mutate'),
        read: (operation, params) => request(
          operation,
          () async => {'proofVersion': ++proofReads},
          params: params,
        ),
      );
      addTearDown(snapshot.close);
      final proof = snapshot.call('crypto2.domain.inventory', {
        'scopeId': 'synthetic-scope',
      });
      await Future<void>.delayed(Duration.zero);
      expect(proofReads, 0);
      now = now.add(const Duration(seconds: 6));
      release.complete({});
      await blocker;
      expect((await proof)['proofVersion'], 2);
      expect(
        proofReads,
        2,
        reason: 'expired original operation cannot admit queued reply',
      );
      expect(
        (await snapshot.call('crypto2.domain.inventory', {
          'scopeId': 'synthetic-scope',
        }))['proofVersion'],
        3,
      );
    },
  );
}
