import 'package:kanban/organizer/domain/payment_completion_diagnostics.dart';
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
  Object? incompleteReason;
  Object? completionDiagnostics;
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
        'completionDiagnostics': completionDiagnostics,
        if (complete != null) 'complete': complete,
        if (incompleteReason != null) 'incompleteReason': incompleteReason,
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
    'completion detail parser rejects unknown steps and strips arbitrary metadata',
    () {
      for (final raw in [
        null,
        'secret',
        12,
        {'checkpointStep': 'private_value'},
      ]) {
        expect(
          PaymentCompletionDiagnostics.fromJson(
            raw,
            sanitizeReason: safeSyncFailureReason,
          ),
          isNull,
        );
      }
      for (final reason in [
        'crypto_authority_pending',
        'crypto_record_verification',
        'crypto_semantic_verification',
        'crypto_restore_record_equivocation',
      ]) {
        final parsed = PaymentCompletionDiagnostics.fromJson({
          'checkpointStep': 'receivedInventoryUncovered',
          'recordVerdict': 'quarantined',
          'recordReason': reason,
          'recordId': 'secret',
        }, sanitizeReason: safeSyncFailureReason)!;
        expect(
          parsed.toSafeDiagnosticJson(sanitizeReason: safeSyncFailureReason),
          {
            'checkpointStep': 'receivedInventoryUncovered',
            'recordVerdict': 'quarantined',
            'recordReason': reason,
          },
        );
      }
      final malformed = PaymentCompletionDiagnostics.fromJson({
        'checkpointStep': 'projectedRecordMissing',
        'recordVerdict': {'private': 'data'},
        'recordReason': {'private': 'data'},
      }, sanitizeReason: safeSyncFailureReason)!;
      expect(
        malformed.toSafeDiagnosticJson(sanitizeReason: safeSyncFailureReason),
        {'checkpointStep': 'projectedRecordMissing'},
      );
    },
  );

  test(
    'completion detail crosses actual incomplete receiver without changing facts',
    () async {
      final f = await _open();
      final before = await _facts(f.repo);
      f.transport.complete = false;
      f.transport.incompleteReason = 'crypto_payment_records_pending';
      f.transport.completionDiagnostics = {
        'checkpointStep': 'projectedRevisionMismatch',
        'recordVerdict': 'received',
        'recordReason': 'crypto_record_policy_predecessor_pending',
        'recordId': 'must-not-export',
        'payload': {'secret': 'must-not-export'},
      };
      CryptoAuthorityPending? failure;
      try {
        await f.repo.fetchLinkedPayments(f.space);
      } on CryptoAuthorityPending catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      final detail = SyncFailureDetails(
        stage: SyncFailureStage.linkedPayments,
        reason: failure!.reason,
        occurredAt: DateTime.utc(2026, 11, 2),
        scopeId: f.space.id,
        completionDiagnostics: failure.completionDiagnostics,
      );
      final exported = jsonDecode(syncFailureDiagnosticsJson([detail])) as Map;
      final entry = (exported['syncFailures'] as List).single as Map;
      expect(entry['completionDiagnostics'], {
        'checkpointStep': 'projectedRevisionMismatch',
        'recordVerdict': 'received',
        'recordReason': 'crypto_record_policy_predecessor_pending',
      });
      expect(jsonEncode(exported), isNot(contains('must-not-export')));
      expect(jsonEncode(exported), isNot(contains(f.space.id)));
      expect(await _facts(f.repo), before);
      expect((await f.payments.read(f.space)).fresh, isFalse);
    },
  );

  test(
    'untrusted malformed completion details do not replace sync error or expose text',
    () async {
      final f = await _open();
      final before = await _facts(f.repo);
      f.transport.complete = false;
      f.transport.incompleteReason = 'crypto_payment_records_pending';
      f.transport.completionDiagnostics = {
        'checkpointStep': 'projectedRevisionMismatch',
        'recordVerdict': 'received',
        'recordReason': 'crypto_secret_user_token',
      };
      await expectLater(
        f.repo.fetchLinkedPayments(f.space),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.completionDiagnostics?.toSafeDiagnosticJson(
              sanitizeReason: safeSyncFailureReason,
            ),
            'sanitized details',
            {
              'checkpointStep': 'projectedRevisionMismatch',
              'recordVerdict': 'received',
              'recordReason': 'unknown',
            },
          ),
        ),
      );
      expect(await _facts(f.repo), before);
    },
  );

  test(
    'stale boundary wins over new diagnostic metadata and retains old proof',
    () async {
      final f = await _open();
      final before = await _facts(f.repo);
      f.transport.complete = false;
      f.transport.replyRevision = 0;
      f.transport.completionDiagnostics = {
        'checkpointStep': 'projectedRevisionMismatch',
      };
      await expectLater(
        f.repo.fetchLinkedPayments(f.space),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'finance_access_changed',
          ),
        ),
      );
      expect(await _facts(f.repo), before);
      expect((await f.payments.read(f.space)).fresh, isTrue);
    },
  );
}
