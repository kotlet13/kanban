part of 'collaboration_repository.dart';

extension CollaborationLinkedPayments on CollaborationRepository {
  Future<Map<String, dynamic>> linkedPaymentCall(
    String operation,
    Map<String, Object?> params, {
    required String partition,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    if (session.profile.partition != partition) {
      throw const CollaborationException('session_changed');
    }
    // Public capabilities verify server identity before bearer or financial params.
    await _negotiate(session, epoch);
    if (!const {
      'finance3.paymentCommit',
      'finance3.paymentReimburse',
      'finance3.paymentProject',
      'finance3.payments',
    }.contains(operation)) {
      throw const CollaborationException('unsupported_operation');
    }
    final caps = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['capabilities:$partition'],
    );
    _checkEpoch(epoch);
    final features = caps.isEmpty
        ? null
        : CollaborationRepository._map(caps.single['value'])['features'];
    if (features is! Map || features['linkedPayments'] != true) {
      throw const CollaborationException('client_upgrade_required');
    }
    final reply = await _callSession(session, epoch, operation, params);
    _checkEpoch(epoch);
    return reply;
  }

  Future<PaymentSnapshot> fetchLinkedPayments(PaymentSpaceRef space) async {
    final session = _requireSession(), epoch = _epoch;
    if (space.isLocal || space.partition != session.profile.partition) {
      throw const CollaborationException('session_changed');
    }
    final partition = session.profile.partition;
    await _negotiate(session, epoch);
    final policy = await _fetchFinancePolicy(session, epoch, space.id);
    if (!policy.canRead) {
      throw const CollaborationException('finance_forbidden');
    }
    final generation = await _financeAccessGeneration(partition, space.id);
    final reply = await linkedPaymentCall('finance3.payments', {
      'scopeId': space.id,
    }, partition: partition);
    if (reply['accessRevision'] != policy.revision ||
        reply['scopeSequence'] is! int) {
      throw const CollaborationException('finance_access_changed');
    }
    final events = (reply['events'] as List).map((raw) {
      final j = Map<String, dynamic>.from(raw as Map);
      j['sourcePartition'] = partition;
      return PaymentEvent.fromJson(j);
    }).toList();
    final movements = (reply['cashMovements'] as List)
        .map(
          (raw) => PaymentCashMovement.fromJson(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
    final projections = (reply['projections'] as List).map((raw) {
      final j = Map<String, dynamic>.from(raw as Map);
      j['sourcePartition'] = partition;
      return PaymentProjection.fromJson(j);
    }).toList();
    if (events.any((e) => e.sourceScopeId != space.id)) {
      throw const CollaborationException('invalid_response');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      if (generation != await _financeAccessGeneration(partition, space.id)) {
        throw const CollaborationException('finance_access_changed');
      }
      final proofs = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['linked_payment_complete:${space.key}'],
      );
      if (proofs.isNotEmpty &&
          (CollaborationRepository._map(proofs.single['value'])['scopeSequence']
                  as int) >
              (reply['scopeSequence'] as int)) {
        throw const CollaborationException('payment_changed');
      }
      for (final event in events) {
        final known = await database.rows(
          'SELECT data FROM linked_payment_events WHERE space_key=? AND event_id=?',
          [space.key, event.eventId],
        );
        if (known.isNotEmpty) {
          final previous = PaymentEvent.fromJson(
            CollaborationRepository._map(known.single['data']),
          );
          if (event.revision < previous.revision) {
            throw const CollaborationException('payment_changed');
          }
          if (!shouldReplacePaymentEvent(previous, event)) continue;
        }
        await database.execute(
          'INSERT INTO linked_payment_events(space_key,event_id,data) VALUES(?,?,?) ON CONFLICT(space_key,event_id) DO UPDATE SET data=excluded.data',
          [space.key, event.eventId, jsonEncode(event.toJson())],
        );
      }
      for (final projection in projections) {
        final known = await database.rows(
          'SELECT data FROM linked_payment_projections WHERE space_key=? AND event_id=?',
          [space.key, projection.eventId],
        );
        if (known.isNotEmpty) {
          final previous = PaymentProjection.fromJson(
            CollaborationRepository._map(known.single['data']),
          );
          if (projection.event.revision < previous.event.revision) {
            throw const CollaborationException('payment_changed');
          }
          shouldReplacePaymentEvent(previous.event, projection.event);
          if (previous.privateAccountId != projection.privateAccountId) {
            throw const CollaborationException('invalid_response');
          }
        }
        await database.execute(
          'INSERT INTO linked_payment_projections(space_key,event_id,data) VALUES(?,?,?) ON CONFLICT(space_key,event_id) DO UPDATE SET data=excluded.data',
          [space.key, projection.eventId, jsonEncode(projection.toJson())],
        );
      }
      await database.execute(
        'DELETE FROM linked_payment_cash WHERE space_key=?',
        [space.key],
      );
      for (final movement in movements) {
        await database.execute(
          'INSERT INTO linked_payment_cash(space_key,movement_id,data) VALUES(?,?,?)',
          [space.key, movement.id, jsonEncode(movement.toJson())],
        );
      }
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        [
          'linked_payment_complete:${space.key}',
          jsonEncode({
            'generation': generation,
            'scopeSequence': reply['scopeSequence'],
            'accessRevision': policy.revision,
          }),
        ],
      );
      _checkEpoch(epoch);
    });
    database.personalChanged();
    return PaymentSnapshot(
      events: events,
      projections: projections,
      cashMovements: movements,
      fresh: true,
    );
  }
}
