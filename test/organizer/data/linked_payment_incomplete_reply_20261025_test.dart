import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/linked_payments_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/linked_payment_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport;

class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected protected fixture operation');
}

class _Transport extends OrganizationFinanceTransport {
  _Transport() : super(FakeServer());
  bool? complete;
  int replyRevision = 1, replySequence = 4;
  Future<void> Function()? beforeReply;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'finance3.payments') {
      await beforeReply?.call();
      return {
        'events': <Object>[],
        'projections': <Object>[],
        'cashMovements': <Object>[],
        'accessRevision': replyRevision,
        'scopeSequence': replySequence,
        if (complete != null) 'complete': complete,
      };
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    return operation == 'capabilities'
        ? {
            ...reply,
            'features': <String, dynamic>{
              ...reply['features'] as Map,
              'linkedPayments': true,
            },
          }
        : reply;
  }
}

Future<
  ({
    CollaborationRepository repo,
    _Transport transport,
    PaymentSpaceRef space,
    LinkedPaymentsRepository payments,
  })
>
_open() async {
  final transport = _Transport()..seed(parentAccess: true);
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
    serverUrl: 'https://example.test',
    username: 'alice',
    password: 'synthetic',
  );
  final space = PaymentSpaceRef(
    transport.parent,
    partition: repo.state.session!.partition,
  );
  await repo.fetchLinkedPayments(space);
  final now = DateTime.utc(2026, 10, 25);
  final event = PaymentEvent(
    eventId: newSharedId(),
    sourceScopeId: space.id,
    sourceEntryId: newSharedId(),
    sourceRevision: 1,
    payerAccountId: repo.state.session!.accountId,
    amountMinor: 1234,
    currency: 'EUR',
    paidAt: now,
    expectReimbursement: true,
    revision: 1,
  );
  final projection = PaymentProjection(
    event: event,
    state: PaymentProjectionState.complete,
  );
  final cash = PaymentCashMovement(
    id: newSharedId(),
    accountId: transport.account,
    amountMinor: -1234,
    currency: 'EUR',
    paidAt: now,
  );
  await repo.database.execute(
    'INSERT INTO linked_payment_events(space_key,event_id,data) VALUES(?,?,?)',
    [space.key, event.eventId, jsonEncode(event.toJson())],
  );
  await repo.database.execute(
    'INSERT INTO linked_payment_projections(space_key,event_id,data) VALUES(?,?,?)',
    [space.key, event.eventId, jsonEncode(projection.toJson())],
  );
  await repo.database.execute(
    'INSERT INTO linked_payment_cash(space_key,movement_id,data) VALUES(?,?,?)',
    [space.key, cash.id, jsonEncode(cash.toJson())],
  );
  await repo.database.execute(
    'INSERT INTO linked_payment_intents(id,data,state) VALUES(?,?,?)',
    [
      'pending-fixture',
      jsonEncode({'partition': space.partition, 'sourceSpaceKey': space.key}),
      'pending',
    ],
  );
  return (
    repo: repo,
    transport: transport,
    space: space,
    payments: LinkedPaymentsRepository(repo.database, collaboration: repo),
  );
}

Future<List<List<Map<String, Object?>>>> _facts(
  CollaborationRepository repo,
) async => [
  for (final table in [
    'linked_payment_events',
    'linked_payment_projections',
    'linked_payment_cash',
    'linked_payment_intents',
  ])
    await repo.database.rows('SELECT * FROM $table'),
];

void main() {
  test(
    'new race delayed older complete reply cannot restore proof after incomplete observation',
    () async {
      final f = await _open();
      final before = await _facts(f.repo);
      f.transport.complete = false;
      await expectLater(
        f.repo.fetchLinkedPayments(f.space),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      f.transport.complete = true;
      f.transport.replySequence = 3;
      await expectLater(
        f.repo.fetchLinkedPayments(f.space),
        throwsA(
          isA<CollaborationException>().having(
            (error) => error.code,
            'code',
            'payment_changed',
          ),
        ),
      );
      expect(await _facts(f.repo), before);
      expect(
        await f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['linked_payment_complete:${f.space.key}'],
        ),
        isEmpty,
      );
      expect(
        await f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['linked_payment_incomplete:${f.space.key}'],
        ),
        hasLength(1),
      );
      f.transport.replySequence = 4;
      final recovered = await f.repo.fetchLinkedPayments(f.space);
      expect(recovered.fresh, isTrue);
      expect(
        await f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['linked_payment_incomplete:${f.space.key}'],
        ),
        isEmpty,
      );
      final proof = await f.repo.database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['linked_payment_complete:${f.space.key}'],
      );
      expect(jsonDecode(proof.single['value'] as String)['scopeSequence'], 4);
    },
  );
  for (final flag in <bool?>[null, true]) {
    test(
      'new control complete=$flag retains legacy/full authoritative replacement',
      () async {
        final f = await _open();
        f.transport.complete = flag;
        final reply = await f.repo.fetchLinkedPayments(f.space);
        expect(reply.fresh, isTrue);
        expect(
          await f.repo.database.rows(
            'SELECT * FROM linked_payment_cash WHERE space_key=?',
            [f.space.key],
          ),
          isEmpty,
        );
        expect(
          await f.repo.database.rows(
            'SELECT value FROM local_meta WHERE name=?',
            ['linked_payment_complete:${f.space.key}'],
          ),
          hasLength(1),
        );
      },
    );
  }
  for (final boundary in ['revision', 'sequence', 'generation']) {
    test(
      'new control incomplete $boundary boundary preserves current proof and facts',
      () async {
        final f = await _open();
        final before = await _facts(f.repo);
        final proof = await f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['linked_payment_complete:${f.space.key}'],
        );
        f.transport.complete = false;
        if (boundary == 'revision') f.transport.replyRevision = 0;
        if (boundary == 'sequence') f.transport.replySequence = 3;
        if (boundary == 'generation') {
          f.transport.beforeReply = () async {
            await f.repo.database.execute(
              'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
              [
                'finance_access_generation:${f.space.partition}:${f.space.id}',
                '99',
              ],
            );
          };
        }
        await expectLater(
          f.repo.fetchLinkedPayments(f.space),
          throwsA(
            isA<CollaborationException>().having(
              (error) => error.code,
              'code',
              boundary == 'sequence'
                  ? 'payment_changed'
                  : 'finance_access_changed',
            ),
          ),
        );
        expect(await _facts(f.repo), before);
        expect(
          await f.repo.database.rows(
            'SELECT value FROM local_meta WHERE name=?',
            ['linked_payment_complete:${f.space.key}'],
          ),
          proof,
        );
      },
    );
  }
  test(
    'new control incomplete freshness withdrawal notifies payments after proof commit',
    () async {
      final f = await _open();
      final observed = f.payments.changes.first.then(
        (_) async => f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['linked_payment_complete:${f.space.key}'],
        ),
      );
      f.transport.complete = false;
      await expectLater(
        f.repo.fetchLinkedPayments(f.space),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(await observed.timeout(const Duration(seconds: 1)), isEmpty);
    },
  );

  test(
    'explicit incomplete payment reply preserves all facts and pending intent but withdraws freshness',
    () async {
      final f = await _open();
      expect((await f.payments.read(f.space)).fresh, isTrue);
      final before = await _facts(f.repo);
      f.transport.complete = false;
      Object? failure;
      try {
        await f.repo.fetchLinkedPayments(f.space);
      } catch (error) {
        failure = error;
      }
      expect(
        await _facts(f.repo),
        before,
        reason:
            'Partial/empty reply must not delete retained cash or replace facts',
      );
      expect(failure, isA<CryptoAuthorityPending>());
      expect(
        (failure as CryptoAuthorityPending).reason,
        'crypto_payment_snapshot_incomplete',
      );
      expect(
        await f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['linked_payment_complete:${f.space.key}'],
        ),
        isEmpty,
      );
      final read = await f.payments.read(f.space);
      expect(read.fresh, isFalse);
      expect(read.pendingCount, 1);
      expect(read.cashMovements, hasLength(1));
    },
  );
}
