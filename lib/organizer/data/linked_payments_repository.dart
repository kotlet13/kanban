import 'dart:async';
import 'dart:convert';
import '../domain/linked_payment_models.dart';
import '../domain/local_space_models.dart';
import '../domain/organizer_models.dart';
import '../domain/collaboration_models.dart';
import 'collaboration_database.dart';
import 'collaboration_repository.dart';
import 'organizer_repository.dart' show OrganizerConflictException;
import 'sqlite_organizer_storage.dart';

part 'linked_payment_actions.dart';
part 'linked_payment_intents.dart';

/// Canonical expenses remain in their source. These durable sidecars represent
/// personal cash and receivables without booking a second expense or income.
class LinkedPaymentsRepository {
  LinkedPaymentsRepository(this.database, {this.collaboration});
  final CollaborationDatabase database;
  final CollaborationRepository? collaboration;
  Stream<void> get changes => database.personalChanges.stream;
  Map<String, dynamic> _map(Object? raw) =>
      jsonDecode(raw as String) as Map<String, dynamic>;

  Future<String> recordPersonalPayment(
    PaymentSourceRef source, {
    required PaymentSpaceRef personal,
    required String personalAccountId,
    PaymentSpaceRef? household,
    required DateTime paidAt,
    required bool expectReimbursement,
  }) => _recordPersonalPayment(
    source,
    personal: personal,
    personalAccountId: personalAccountId,
    household: household,
    paidAt: paidAt,
    expectReimbursement: expectReimbursement,
  );
  Future<void> reimburse(
    PaymentSpaceRef sourceSpace,
    String eventId, {
    required int expectedRevision,
    required int amountMinor,
    required DateTime paidAt,
    required String organizationAccountId,
    PaymentSpaceRef? organizationAccountScope,
  }) => _reimburse(
    sourceSpace,
    eventId,
    expectedRevision: expectedRevision,
    amountMinor: amountMinor,
    paidAt: paidAt,
    organizationAccountId: organizationAccountId,
    organizationAccountScope: organizationAccountScope,
  );
  static final _resumeRuns = Expando<Future<void>>();
  static final _deliveryRuns = Expando<Map<String, Future<void>>>();
  Future<void> resumePending() {
    final prior = _resumeRuns[database];
    if (prior != null) return prior;
    final future = () async {
      try {
        await _resumePending();
      } finally {
        _resumeRuns[database] = null;
      }
    }();
    _resumeRuns[database] = future;
    return future;
  }

  Future<void> _deliver(String id, Map<String, dynamic> intent) {
    final runs = _deliveryRuns[database] ??= <String, Future<void>>{};
    return runs.putIfAbsent(id, () async {
      try {
        await _deliverIntent(id, intent);
      } finally {
        runs.remove(id);
      }
    });
  }

  Future<PaymentSpaceRef> resolveSpace(PaymentSpaceRef ref) async {
    if (ref.isLocal &&
        ref.id == 'local' &&
        collaboration?.state.privateSync.enabled == true) {
      final state = collaboration!.state;
      return PaymentSpaceRef(
        state.privateSync.scopeId!,
        partition: state.session!.partition,
      );
    }
    if (ref.isLocal && ref.id != 'local') {
      final rows = await database.rows(
        'SELECT data FROM local_spaces WHERE id=?',
        [ref.id],
      );
      final binding = rows.isEmpty
          ? null
          : LocalSpace.fromJson(_map(rows.single['data'])).binding;
      if (binding != null) {
        return PaymentSpaceRef(binding.scopeId, partition: binding.partition);
      }
    }
    return ref;
  }

  Future<OrganizerSnapshot> _local(
    PaymentSpaceRef space, {
    LocalSpaceKind? kind,
  }) async {
    final rows = await database.rows(
      'SELECT data FROM local_spaces WHERE id=?',
      [space.id],
    );
    if (!space.isLocal || rows.isEmpty) {
      throw const CollaborationException('space_missing');
    }
    final descriptor = LocalSpace.fromJson(_map(rows.single['data']));
    if (descriptor.binding != null ||
        descriptor.financeRecoveryIncomplete ||
        kind != null && descriptor.kind != kind) {
      throw const CollaborationException('finance_forbidden');
    }
    final snapshot = await SqliteOrganizerStorage(
      database,
      workspaceId: space.id,
    ).read();
    if (snapshot.workspaceKey != space.id) {
      throw const CollaborationException('use_private_sync');
    }
    return snapshot;
  }

  void _remote(PaymentSpaceRef space) {
    final state = collaboration?.state;
    final scope = state?.scopes.where((s) => s.id == space.id).firstOrNull;
    if (state?.session?.partition != space.partition ||
        state?.localAccessAllowed != true) {
      throw const CollaborationException('session_changed');
    }
    if (scope == null ||
        scope.revoked ||
        scope.blocked ||
        !state!.financePolicyForScope(space.id).canRead) {
      throw const CollaborationException('finance_forbidden');
    }
  }

  Future<PaymentSnapshot> read(PaymentSpaceRef raw) async {
    final space = await resolveSpace(raw);
    if (space.isLocal) {
      await _local(space);
    } else {
      _remote(space);
    }
    final events = (await database.rows(
      'SELECT data FROM linked_payment_events WHERE space_key=?',
      [space.key],
    )).map((r) => PaymentEvent.fromJson(_map(r['data']))).toList();
    final projections =
        (await database.rows(
              'SELECT data FROM linked_payment_projections WHERE space_key=?',
              [space.key],
            ))
            .map((r) => PaymentProjection.fromJson(_map(r['data'])))
            .where(
              (p) =>
                  p.event.sourcePartition == null ||
                  collaboration?.state.session?.partition ==
                      p.event.sourcePartition,
            )
            .toList();
    final intents = await database.rows(
      "SELECT data FROM linked_payment_intents WHERE state IN ('pending','waiting_source_publication','quarantine')",
    );
    final pending = intents.where((r) {
      final j = _map(r['data']);
      if (j['partition'] != null &&
          j['partition'] != collaboration?.state.session?.partition) {
        return false;
      }
      return [
        j['sourceSpaceKey'],
        j['personalSpaceKey'],
        j['householdSpaceKey'],
      ].contains(space.key);
    }).length;
    return PaymentSnapshot(
      events: events,
      projections: projections,
      pendingCount: pending,
      fresh: space.isLocal || await _fresh(space),
      cashMovements: {
        for (final movement in [
          for (final row in await database.rows(
            'SELECT data FROM linked_payment_cash WHERE space_key=?',
            [space.key],
          ))
            PaymentCashMovement.fromJson(_map(row['data'])),
          for (final projection in projections.where(
            (p) =>
                p.privateAccountId != null &&
                p.state != PaymentProjectionState.blocked,
          )) ...[
            PaymentCashMovement(
              id: projection.eventId,
              accountId: projection.privateAccountId!,
              amountMinor: -projection.event.amountMinor,
              currency: projection.event.currency,
              paidAt: projection.event.paidAt,
            ),
            for (final leg in projection.event.reimbursements)
              PaymentCashMovement(
                id: leg.legId,
                accountId: projection.privateAccountId!,
                amountMinor: leg.amountMinor,
                currency: projection.event.currency,
                paidAt: leg.paidAt,
              ),
          ],
        ])
          movement.id: movement,
      }.values,
    );
  }

  Future<PaymentSnapshot> refresh(PaymentSpaceRef raw) async {
    final space = await resolveSpace(raw);
    if (space.isLocal) return read(space);
    _remote(space);
    return collaboration!.fetchLinkedPayments(space);
  }

  Future<void> _saveEvent(PaymentSpaceRef source, PaymentEvent event) async {
    final previous = await database.rows(
      'SELECT data FROM linked_payment_events WHERE space_key=? AND event_id=?',
      [source.key, event.eventId],
    );
    if (previous.isNotEmpty) {
      final old = PaymentEvent.fromJson(_map(previous.single['data']));
      if (old.sourceEntryId != event.sourceEntryId ||
          old.sourceScopeId != event.sourceScopeId ||
          old.sourcePartition != event.sourcePartition) {
        throw const CollaborationException('invalid_response');
      }
      if (old.revision > event.revision) return;
      if (old.revision == event.revision &&
          jsonEncode(old.toJson()) != jsonEncode(event.toJson())) {
        throw const CollaborationException('invalid_response');
      }
    }
    await database.execute(
      'INSERT INTO linked_payment_events(space_key,event_id,data) VALUES(?,?,?) ON CONFLICT(space_key,event_id) DO UPDATE SET data=excluded.data',
      [source.key, event.eventId, jsonEncode(event.toJson())],
    );
  }

  Future<void> _saveProjection(
    PaymentSpaceRef target,
    PaymentEvent event, {
    String? account,
    PaymentProjectionState state = PaymentProjectionState.complete,
  }) async {
    final previous = await database.rows(
      'SELECT data FROM linked_payment_projections WHERE space_key=? AND event_id=?',
      [target.key, event.eventId],
    );
    if (previous.isNotEmpty) {
      final old = PaymentProjection.fromJson(_map(previous.single['data']));
      if (old.event.sourceEntryId != event.sourceEntryId ||
          old.privateAccountId != account ||
          !(old.event.sourcePartition == null &&
                  event.sourcePartition != null) &&
              (old.event.sourcePartition != event.sourcePartition ||
                  old.event.sourceScopeId != event.sourceScopeId)) {
        throw const CollaborationException('invalid_response');
      }
      if (old.event.revision > event.revision) return;
      if (old.event.revision == event.revision &&
          old.event.sourcePartition == event.sourcePartition &&
          jsonEncode(old.toJson()) !=
              jsonEncode(
                PaymentProjection(
                  event: event,
                  state: old.state,
                  privateAccountId: old.privateAccountId,
                ).toJson(),
              )) {
        throw const CollaborationException('invalid_response');
      }
    }
    await database.execute(
      'INSERT INTO linked_payment_projections(space_key,event_id,data) VALUES(?,?,?) ON CONFLICT(space_key,event_id) DO UPDATE SET data=excluded.data',
      [
        target.key,
        event.eventId,
        jsonEncode(
          PaymentProjection(
            event: event,
            state: state,
            privateAccountId: account,
          ).toJson(),
        ),
      ],
    );
  }

  Future<void> _validateHousehold(PaymentSpaceRef space) async {
    if (space.isLocal) {
      await _local(space, kind: LocalSpaceKind.household);
      return;
    }
    _remote(space);
    final state = collaboration!.state;
    if (state.scopes.firstWhere((s) => s.id == space.id).kind !=
            SharedScopeKind.household ||
        !state.financePolicyForScope(space.id).canWrite ||
        state.financeSnapshotComplete[space.id] != true) {
      throw const CollaborationException('finance_forbidden');
    }
  }

  Future<void> _validateOrganizationAccount(
    PaymentSpaceRef space,
    String accountId,
    String currency,
  ) async {
    if (space.isLocal) {
      final snapshot = await _local(space, kind: LocalSpaceKind.organization);
      if (!snapshot.financeAccounts.any(
        (a) => a.id == accountId && a.currency == currency && !a.archived,
      )) {
        throw const CollaborationException('validation_error');
      }
      return;
    }
    _remote(space);
    if (!collaboration!.state.financePolicyForScope(space.id).canWrite ||
        collaboration!.state.financeSnapshotComplete[space.id] != true) {
      throw const CollaborationException('finance_forbidden');
    }
    final rows = await database.rows(
      "SELECT payload FROM finance_records WHERE partition=? AND scope_id=? AND id=? AND type='financeAccount' AND deleted=0",
      [space.partition, space.id, accountId],
    );
    if (rows.isEmpty ||
        _map(rows.single['payload'])['currency'] != currency ||
        _map(rows.single['payload'])['archived'] == true) {
      throw const CollaborationException('validation_error');
    }
  }

  Future<void> _validateTargetAccount(
    PaymentSpaceRef space,
    String accountId,
    String currency,
  ) async {
    if (space.isLocal) {
      final snapshot = await _local(space, kind: LocalSpaceKind.personal);
      if (!snapshot.financeAccounts.any(
        (a) => a.id == accountId && a.currency == currency && !a.archived,
      )) {
        throw const CollaborationException('validation_error');
      }
    } else {
      _remote(space);
      if (!collaboration!.state.financePolicyForScope(space.id).canWrite ||
          collaboration!.state.financeSnapshotComplete[space.id] != true) {
        throw const CollaborationException('finance_forbidden');
      }
      final rows = await database.rows(
        "SELECT payload FROM finance_records WHERE partition=? AND scope_id=? AND id=? AND type='personalFinanceAccount' AND deleted=0",
        [space.partition, space.id, accountId],
      );
      if (rows.isEmpty ||
          _map(rows.single['payload'])['currency'] != currency ||
          _map(rows.single['payload'])['archived'] == true) {
        throw const CollaborationException('validation_error');
      }
    }
  }

  Future<String> _accessStamp(
    List<PaymentSpaceRef> spaces,
  ) async => jsonEncode([
    for (final space in spaces)
      space.isLocal
          ? await database.rows('SELECT data FROM local_spaces WHERE id=?', [
              space.id,
            ])
          : [
              await database.rows(
                'SELECT data,finance_policy,finance_blocked,finance_complete FROM scopes WHERE partition=? AND id=?',
                [space.partition, space.id],
              ),
              await database.rows('SELECT value FROM local_meta WHERE name=?', [
                'finance_access_generation:${space.partition}:${space.id}',
              ]),
            ],
  ]);
  Future<bool> _fresh(PaymentSpaceRef space) async {
    final proof = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['linked_payment_complete:${space.key}'],
    );
    if (proof.isEmpty) return false;
    final decoded = _map(proof.single['value']);
    final generation = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['finance_access_generation:${space.partition}:${space.id}'],
    );
    final scope = await database.rows(
      'SELECT finance_access_revision,finance_blocked FROM scopes WHERE partition=? AND id=?',
      [space.partition, space.id],
    );
    return scope.isNotEmpty &&
        scope.single['finance_blocked'] == 0 &&
        decoded['generation'] ==
            (generation.isEmpty
                ? 0
                : int.parse(generation.single['value'] as String)) &&
        decoded['accessRevision'] == scope.single['finance_access_revision'];
  }
}
