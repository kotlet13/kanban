part of 'linked_payments_repository.dart';

extension LinkedPaymentIntents on LinkedPaymentsRepository {
  Future<void> _deliverIntent(String id, Map<String, dynamic> intent) async {
    final partition = intent['partition'] as String;
    final deviceId = collaboration?.state.session?.deviceId;
    if (collaboration?.state.session?.partition != partition ||
        deviceId == null) {
      throw const CollaborationException('session_changed');
    }
    final personal = intent['personal'] == null
        ? null
        : PaymentSpaceRef.fromJson(
            Map<String, dynamic>.from(intent['personal'] as Map),
          );
    final home = intent['household'] == null
        ? null
        : PaymentSpaceRef.fromJson(
            Map<String, dynamic>.from(intent['household'] as Map),
          );
    if (personal?.isLocal == true) {
      await _local(personal!, kind: LocalSpaceKind.personal);
    }
    if (home?.isLocal == true) {
      await _local(home!, kind: LocalSpaceKind.household);
    }
    final source = PaymentSourceRef.fromJson(
      Map<String, dynamic>.from(intent['source'] as Map),
    );
    _remote(source.space);
    for (final space in [
      source.space,
      if (personal != null) personal,
      if (home != null) home,
    ].where((s) => !s.isLocal)) {
      if ((await database.rows('SELECT value FROM local_meta WHERE name=?', [
        'scope_reconciliation:${space.partition}:${space.id}',
      ])).isNotEmpty) {
        throw const CollaborationException('scope_unavailable');
      }
    }
    if (intent['operation'] != 'finance3.paymentProject' &&
        !collaboration!.state.financePolicyForScope(source.space.id).canWrite) {
      throw const CollaborationException('finance_forbidden');
    }
    final refundAccountSpace = intent['organizationAccountScope'] == null
        ? null
        : PaymentSpaceRef.fromJson(
            Map<String, dynamic>.from(
              intent['organizationAccountScope'] as Map,
            ),
          );
    final access = await _accessStamp([
      source.space,
      if (refundAccountSpace != null) refundAccountSpace,
      if (personal != null) personal,
      if (home != null) home,
    ]);
    final reply = await collaboration!.linkedPaymentCall(
      intent['operation'] as String,
      Map<String, Object?>.from(intent['params'] as Map),
      partition: partition,
    );
    if (collaboration!.state.session?.partition != partition ||
        collaboration!.state.session?.deviceId != deviceId) {
      throw const CollaborationException('session_changed');
    }
    var event = PaymentEvent.fromJson({
      ...Map<String, dynamic>.from(reply['event'] as Map),
      'sourcePartition': partition,
    });
    final params = Map<String, dynamic>.from(intent['params'] as Map);
    if (event.eventId != params['eventId'] ||
        event.sourceScopeId != source.space.id ||
        event.sourceEntryId != source.entryId ||
        intent['currency'] != null && event.currency != intent['currency'] ||
        intent['amountMinor'] != null &&
            event.amountMinor != intent['amountMinor']) {
      throw const CollaborationException('invalid_response');
    }
    if (intent['refunds'] is List) {
      for (final refund in intent['refunds'] as List) {
        final applied = await collaboration!.linkedPaymentCall(
          'finance3.paymentReimburse',
          Map<String, Object?>.from(refund as Map),
          partition: partition,
        );
        event = PaymentEvent.fromJson({
          ...Map<String, dynamic>.from(applied['event'] as Map),
          'sourcePartition': partition,
        });
        if (event.eventId != params['eventId'] ||
            event.sourceScopeId != source.space.id ||
            event.sourceEntryId != source.entryId ||
            event.currency != intent['currency'] ||
            event.amountMinor != intent['amountMinor']) {
          throw const CollaborationException('invalid_response');
        }
      }
    }
    await database.transaction(() async {
      if (collaboration!.state.session?.partition != partition ||
          collaboration!.state.session?.deviceId != deviceId) {
        throw const CollaborationException('session_changed');
      }
      if (access !=
          await _accessStamp([
            source.space,
            if (refundAccountSpace != null) refundAccountSpace,
            if (personal != null) personal,
            if (home != null) home,
          ])) {
        throw const CollaborationException('finance_access_changed');
      }
      _remote(source.space);
      if (personal != null) {
        await _validateTargetAccount(
          personal,
          intent['personalAccountId'] as String,
          event.currency,
        );
      }
      if (home != null) await _validateHousehold(home);
      if (refundAccountSpace != null) {
        await _validateOrganizationAccount(
          refundAccountSpace,
          intent['organizationAccountId'] as String,
          event.currency,
        );
      }
      await _saveEvent(source.space, event);
      if (personal != null) {
        await _saveProjection(
          personal,
          event,
          account: intent['personalAccountId'] as String,
        );
      }
      if (home != null) await _saveProjection(home, event);
      for (final row in await database.rows(
        'SELECT space_key,data FROM linked_payment_projections WHERE event_id=?',
        [event.eventId],
      )) {
        final old = PaymentProjection.fromJson(_map(row['data']));
        if (old.event.revision > event.revision) continue;
        if (old.event.sourcePartition == event.sourcePartition &&
            old.event.sourceScopeId == event.sourceScopeId) {
          await database.execute(
            'UPDATE linked_payment_projections SET data=? WHERE space_key=? AND event_id=?',
            [
              jsonEncode(
                PaymentProjection(
                  event: event,
                  state: old.state,
                  privateAccountId: old.privateAccountId,
                ).toJson(),
              ),
              row['space_key'],
              event.eventId,
            ],
          );
        }
      }
      await database.execute(
        "UPDATE linked_payment_intents SET state='complete' WHERE id=?",
        [id],
      );
      await database.touchPersonal();
    });
    database.personalChanged();
  }

  Future<void> _resumePending() async {
    Object? firstError;
    StackTrace? firstStack;
    Future<void> attempt(
      Map<String, dynamic> row,
      Future<void> Function(String, Map<String, dynamic>) action,
    ) async {
      final id = row['id'] as String,
          intent = _map(row['data']),
          session = collaboration?.state.session;
      if (intent['partition'] != null &&
          intent['partition'] != session?.partition) {
        return;
      }
      try {
        await action(id, intent);
        await database.execute('DELETE FROM local_meta WHERE name=?', [
          'linked_payment_error:$id',
        ]);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
          [
            'linked_payment_error:$id',
            error is CollaborationException ? error.code : 'payment_changed',
          ],
        );
      }
    }

    for (final row in await database.rows(
      "SELECT id,data FROM linked_payment_intents WHERE state='complete' ORDER BY rowid",
    )) {
      await attempt(row, _prepareTargetPublication);
    }
    for (final row in await database.rows(
      "SELECT id,data FROM linked_payment_intents WHERE state IN ('local_only','waiting_source_publication') ORDER BY rowid",
    )) {
      await attempt(row, _preparePublishedIntent);
    }
    for (final row in await database.rows(
      "SELECT id,data FROM linked_payment_intents WHERE state='pending' ORDER BY rowid",
    )) {
      await attempt(row, _deliver);
    }
    if (firstError != null) Error.throwWithStackTrace(firstError!, firstStack!);
  }

  Future<PaymentSpaceRef> _publishedTarget(PaymentSpaceRef ref) async {
    if (!ref.isLocal) return ref;
    if (ref.id == 'local') return resolveSpace(ref);
    final rows = await database.rows(
      'SELECT data FROM local_spaces WHERE id=?',
      [ref.id],
    );
    final binding = rows.isEmpty
        ? null
        : LocalSpace.fromJson(_map(rows.single['data'])).binding;
    return binding == null
        ? ref
        : PaymentSpaceRef(binding.scopeId, partition: binding.partition);
  }

  Future<void> _prepareTargetPublication(
    String id,
    Map<String, dynamic> intent,
  ) async {
    if (intent['personal'] == null && intent['household'] == null) return;
    final source = PaymentSourceRef.fromJson(
      Map<String, dynamic>.from(intent['source'] as Map),
    );
    if (source.space.isLocal ||
        collaboration?.state.session?.partition != source.space.partition) {
      return;
    }
    final personal = intent['personal'] == null
        ? null
        : PaymentSpaceRef.fromJson(
            Map<String, dynamic>.from(intent['personal'] as Map),
          );
    final home = intent['household'] == null
        ? null
        : PaymentSpaceRef.fromJson(
            Map<String, dynamic>.from(intent['household'] as Map),
          );
    final newPersonal = personal == null
        ? null
        : await _publishedTarget(personal);
    final newHome = home == null ? null : await _publishedTarget(home);
    if (newPersonal?.key == personal?.key && newHome?.key == home?.key) return;
    if ([
      if (newPersonal != null) newPersonal,
      if (newHome != null) newHome,
    ].any((s) => !s.isLocal && s.partition != source.space.partition)) {
      throw const CollaborationException('session_changed');
    }
    final rows = await database.rows(
      'SELECT data FROM linked_payment_events WHERE space_key=? AND event_id=?',
      [source.space.key, (intent['params'] as Map)['eventId']],
    );
    if (rows.isEmpty) return;
    final event = PaymentEvent.fromJson(_map(rows.single['data']));
    var account = intent['personalAccountId'];
    if (newPersonal?.isLocal == false && personal?.isLocal == true) {
      final map = await database.rows(
        'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
        ['private:${newPersonal!.partition}', account],
      );
      account = map.firstOrNull?['remote_id'] ?? account;
    }
    final request = newSharedId();
    final next = <String, dynamic>{
      'source': source.toJson(),
      'sourceSpaceKey': source.space.key,
      'partition': source.space.partition,
      'deviceId': collaboration!.state.session!.deviceId,
      'operation': 'finance3.paymentProject',
      'personal': newPersonal?.toJson(),
      'personalSpaceKey': newPersonal?.key,
      'personalAccountId': account,
      'household': newHome?.toJson(),
      'householdSpaceKey': newHome?.key,
      'currency': event.currency,
      'amountMinor': event.amountMinor,
      'params': {
        'scopeId': source.space.id,
        'eventId': event.eventId,
        'expectedRevision': event.revision,
        'requestId': request,
        if (newPersonal?.isLocal == false)
          'personalTarget': {'scopeId': newPersonal!.id, 'accountId': account},
        if (newHome?.isLocal == false) 'householdScopeId': newHome!.id,
      },
    };
    await database.transaction(() async {
      await database.execute(
        "INSERT INTO linked_payment_intents(id,data,state) VALUES(?,?,'pending')",
        [request, jsonEncode(next)],
      );
      await database.execute(
        'UPDATE linked_payment_intents SET data=? WHERE id=?',
        [
          jsonEncode({
            ...intent,
            'personal': newPersonal?.toJson(),
            'personalSpaceKey': newPersonal?.key,
            'personalAccountId': account,
            'household': newHome?.toJson(),
            'householdSpaceKey': newHome?.key,
          }),
          id,
        ],
      );
    });
  }

  Future<void> _preparePublishedIntent(
    String id,
    Map<String, dynamic> intent,
  ) async {
    final original = PaymentSourceRef.fromJson(
      Map<String, dynamic>.from(intent['source'] as Map),
    );
    final source = await _publishedTarget(original.space);
    if (source.isLocal ||
        collaboration?.state.session?.partition != source.partition) {
      return;
    }
    final entry = (await SqliteOrganizerStorage(database).localSnapshot(
      workspace: original.space.id,
    )).financeEntries.where((e) => e.id == original.entryId).firstOrNull;
    if (entry == null) throw const CollaborationException('record_missing');
    final destination = await _publishedTarget(
      PaymentSpaceRef.fromJson(
        Map<String, dynamic>.from(intent['personal'] as Map),
      ),
    );
    final household = intent['household'] == null
        ? null
        : await _publishedTarget(
            PaymentSpaceRef.fromJson(
              Map<String, dynamic>.from(intent['household'] as Map),
            ),
          );
    final partition = source.partition!;
    if (intent['partition'] != null && intent['partition'] != partition ||
        collaboration?.state.session?.partition != partition ||
        !destination.isLocal && destination.partition != partition ||
        household?.isLocal == false && household!.partition != partition) {
      throw const CollaborationException('session_changed');
    }
    final actual = PaymentSpaceRef(
      entry.projectId ?? source.id,
      partition: partition,
    );
    _remote(actual);
    final rows = await database.rows(
      'SELECT * FROM finance_records WHERE partition=? AND scope_id=? AND id=? AND deleted=0',
      [partition, actual.id, entry.id],
    );
    if (rows.isEmpty ||
        rows.single['server_revision'] == 0 ||
        (await database.rows(
          'SELECT op_id FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=?',
          [partition, actual.id, entry.id],
        )).isNotEmpty) {
      return;
    }
    final event = PaymentEvent.fromJson(
      Map<String, dynamic>.from(intent['localEvent'] as Map),
    );
    if (!destination.isLocal) {
      final mapping = await database.rows(
        'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
        ['private:${destination.partition}', intent['personalAccountId']],
      );
      intent['personalAccountId'] =
          mapping.firstOrNull?['remote_id'] ?? intent['personalAccountId'];
    }
    final params = {
      'scopeId': actual.id,
      'entryId': entry.id,
      'expectedEntryRevision': rows.single['server_revision'],
      'eventId': event.eventId,
      'paidAt': event.paidAt.toUtc().toIso8601String(),
      'expectReimbursement': event.expectReimbursement,
      'requestId': id,
      if (!destination.isLocal)
        'personalTarget': {
          'scopeId': destination.id,
          'accountId': intent['personalAccountId'],
        },
      if (household != null && !household.isLocal)
        'householdScopeId': household.id,
    };
    final refunds = <Map<String, Object?>>[];
    for (var n = 0; n < event.reimbursements.length; n++) {
      final leg = event.reimbursements[n];
      final accountSpace = await _publishedTarget(
        PaymentSpaceRef(leg.organizationAccountScopeId ?? original.space.id),
      );
      if (accountSpace.isLocal) return;
      refunds.add({
        'scopeId': actual.id,
        'eventId': event.eventId,
        'expectedRevision': n + 1,
        'legId': leg.legId,
        'amountMinor': leg.amountMinor,
        'paidAt': leg.paidAt.toUtc().toIso8601String(),
        'organizationAccountId': leg.organizationAccountId,
        'organizationAccountScopeId': accountSpace.id,
        'requestId': (intent['refundRequests'] as Map)[leg.legId],
      });
    }
    intent = {
      ...intent,
      'source': PaymentSourceRef(
        space: actual,
        entryId: entry.id,
        expectedRevision: rows.single['local_revision'] as int,
      ).toJson(),
      'sourceSpaceKey': actual.key,
      'personal': destination.toJson(),
      'personalSpaceKey': destination.key,
      'household': household?.toJson(),
      'householdSpaceKey': household?.key,
      'partition': partition,
      'deviceId': intent['deviceId'] ?? collaboration!.state.session!.deviceId,
      'params': params,
      'refunds': refunds,
      'currency': event.currency,
      'amountMinor': event.amountMinor,
    };
    await database.execute(
      "UPDATE linked_payment_intents SET data=?,state='pending' WHERE id=?",
      [jsonEncode(intent), id],
    );
  }
}
