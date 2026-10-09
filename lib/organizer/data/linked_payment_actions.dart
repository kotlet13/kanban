part of 'linked_payments_repository.dart';

extension LinkedPaymentActions on LinkedPaymentsRepository {
  Future<String> _recordPersonalPayment(
    PaymentSourceRef source, {
    required PaymentSpaceRef personal,
    required String personalAccountId,
    PaymentSpaceRef? household,
    required DateTime paidAt,
    required bool expectReimbursement,
  }) async {
    final destination = await resolveSpace(personal),
        home = household == null ? null : await resolveSpace(household);
    final waitingSource =
        source.space.isLocal &&
        (!destination.isLocal || home?.isLocal == false);
    if (waitingSource &&
        !destination.isLocal &&
        home?.isLocal == false &&
        destination.partition != home!.partition) {
      throw const CollaborationException('backup_wrong_account');
    }
    if (!source.space.isLocal &&
        [
          destination,
          if (home != null) home,
        ].any((s) => !s.isLocal && s.partition != source.space.partition)) {
      throw const CollaborationException('backup_wrong_account');
    }
    final personalSnapshot = destination.isLocal
        ? await _local(destination, kind: LocalSpaceKind.personal)
        : null;
    if (destination.isLocal &&
        !personalSnapshot!.financeAccounts.any(
          (a) => a.id == personalAccountId && !a.archived,
        )) {
      throw const CollaborationException('validation_error');
    }
    if (!destination.isLocal) {
      _remote(destination);
      if (collaboration!.state.scopes
                  .firstWhere((scope) => scope.id == destination.id)
                  .kind !=
              SharedScopeKind.personal ||
          !collaboration!.state
              .financePolicyForScope(destination.id)
              .canWrite ||
          collaboration!.state.financeSnapshotComplete[destination.id] !=
              true) {
        throw const CollaborationException('finance_forbidden');
      }
      final mapping = await database.rows(
        'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
        ['private:${destination.partition}', personalAccountId],
      );
      personalAccountId =
          mapping.firstOrNull?['remote_id'] as String? ?? personalAccountId;
      final account = await database.rows(
        "SELECT payload FROM finance_records WHERE partition=? AND scope_id=? AND id=? AND type='personalFinanceAccount' AND deleted=0",
        [destination.partition, destination.id, personalAccountId],
      );
      if (account.isEmpty ||
          _map(account.single['payload'])['archived'] == true) {
        throw const CollaborationException('validation_error');
      }
    }
    if (home != null) {
      if (home.isLocal) {
        await _local(home, kind: LocalSpaceKind.household);
      } else {
        _remote(home);
        if (collaboration!.state.scopes
                .firstWhere((s) => s.id == home.id)
                .kind !=
            SharedScopeKind.household) {
          throw const CollaborationException('validation_error');
        }
      }
    }
    final id = newSharedId(),
        requestId = newSharedId(),
        identity = database.personalIdentityGeneration;
    if (source.space.isLocal) {
      await database.transaction(() async {
        final snapshot = await _local(
              source.space,
              kind: LocalSpaceKind.organization,
            ),
            entry = snapshot.financeEntries
                .where((e) => e.id == source.entryId)
                .firstOrNull;
        if (entry == null ||
            entry.revision != source.expectedRevision ||
            entry.kind != FinanceEntryKind.expense) {
          throw const OrganizerConflictException('Payment source changed');
        }
        if (personalSnapshot != null &&
            personalSnapshot.financeAccounts
                    .firstWhere((a) => a.id == personalAccountId)
                    .currency !=
                entry.currency) {
          throw const CollaborationException('validation_error');
        }
        await _validateTargetAccount(
          destination,
          personalAccountId,
          entry.currency,
        );
        if (home != null) await _validateHousehold(home);
        if ((await database.rows(
          r"SELECT event_id FROM linked_payment_events WHERE space_key=? AND json_extract(data,'$.sourceEntryId')=?",
          [source.space.key, source.entryId],
        )).isNotEmpty) {
          throw const CollaborationException('linked_payment_exists');
        }
        var profile = await database.rows(
          "SELECT value FROM local_meta WHERE name='local_payment_actor'",
        );
        if (profile.isEmpty) {
          await database.execute(
            "INSERT INTO local_meta(name,value) VALUES('local_payment_actor',?)",
            [newSharedId()],
          );
          profile = await database.rows(
            "SELECT value FROM local_meta WHERE name='local_payment_actor'",
          );
        }
        final event = PaymentEvent(
          eventId: id,
          sourceScopeId: source.space.id,
          sourceEntryId: entry.id,
          sourceRevision: entry.revision + 1,
          payerAccountId: profile.single['value'] as String,
          amountMinor: entry.amountMinor,
          currency: entry.currency,
          paidAt: paidAt,
          expectReimbursement: expectReimbursement,
          revision: 1,
        );
        if (identity != database.personalIdentityGeneration) {
          throw const CollaborationException('session_changed');
        }
        final paid = entry.copyWith(
          status: FinanceEntryStatus.posted,
          paidAt: paidAt,
          occurredAt: paidAt,
          revision: entry.revision + 1,
          updatedAt: DateTime.now().toUtc(),
        );
        await SqliteOrganizerStorage(
          database,
          workspaceId: source.space.id,
        ).write(
          snapshot.copyWith(
            revision: snapshot.revision + 1,
            financeEntries: snapshot.financeEntries.map(
              (e) => e.id == entry.id ? paid : e,
            ),
          ),
        );
        await _saveEvent(source.space, event);
        await _saveProjection(
          destination,
          event,
          account: personalAccountId,
          state: waitingSource
              ? PaymentProjectionState.pending
              : PaymentProjectionState.complete,
        );
        if (home != null) {
          await _saveProjection(
            home,
            event,
            state: waitingSource
                ? PaymentProjectionState.pending
                : PaymentProjectionState.complete,
          );
        }
        final partition = destination.partition ?? home?.partition;
        final intent = {
          'source': source.toJson(),
          'sourceSpaceKey': source.space.key,
          'personalSpaceKey': destination.key,
          'householdSpaceKey': home?.key,
          'personal': destination.toJson(),
          'personalAccountId': personalAccountId,
          'household': home?.toJson(),
          'partition': partition,
          'deviceId': partition == null
              ? null
              : collaboration!.state.session!.deviceId,
          'operation': 'finance3.paymentCommit',
          'localEvent': event.toJson(),
          'requestId': requestId,
          'refundRequests': <String, String>{},
        };
        await database.execute(
          'INSERT INTO linked_payment_intents(id,data,state) VALUES(?,?,?)',
          [
            requestId,
            jsonEncode(intent),
            waitingSource ? 'waiting_source_publication' : 'local_only',
          ],
        );
        await database.touchPersonal();
      });
    } else {
      _remote(source.space);
      final state = collaboration!.state, partition = source.space.partition!;
      if (!state.financePolicyForScope(source.space.id).canWrite) {
        throw const CollaborationException('finance_forbidden');
      }
      final rows = await database.rows(
        "SELECT * FROM finance_records WHERE partition=? AND scope_id=? AND id=? AND deleted=0",
        [partition, source.space.id, source.entryId],
      );
      if (rows.isEmpty ||
          rows.single['local_revision'] != source.expectedRevision ||
          (await database.rows(
            'SELECT op_id FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=?',
            [partition, source.space.id, source.entryId],
          )).isNotEmpty) {
        throw const OrganizerConflictException(
          'Payment source must be synchronized',
        );
      }
      final entry = SharedFinanceEntry.fromJson({
        ..._map(rows.single['payload']),
        'id': source.entryId,
        'revision': source.expectedRevision,
      });
      if (entry.kind != FinanceEntryKind.expense ||
          personalSnapshot != null &&
              personalSnapshot.financeAccounts
                      .firstWhere((a) => a.id == personalAccountId)
                      .currency !=
                  entry.currency) {
        throw const CollaborationException('validation_error');
      }
      await _validateTargetAccount(
        destination,
        personalAccountId,
        entry.currency,
      );
      if (home != null) await _validateHousehold(home);
      final params = <String, Object?>{
        'scopeId': source.space.id,
        'entryId': source.entryId,
        'expectedEntryRevision': rows.single['server_revision'],
        'eventId': id,
        'paidAt': paidAt.toUtc().toIso8601String(),
        'expectReimbursement': expectReimbursement,
        'requestId': requestId,
        if (!destination.isLocal)
          'personalTarget': {
            'scopeId': destination.id,
            'accountId': personalAccountId,
          },
        if (home != null && !home.isLocal) 'householdScopeId': home.id,
      };
      final intent = {
        'source': source.toJson(),
        'sourceSpaceKey': source.space.key,
        'personalSpaceKey': destination.key,
        'householdSpaceKey': home?.key,
        'personal': destination.toJson(),
        'personalAccountId': personalAccountId,
        'household': home?.toJson(),
        'partition': partition,
        'deviceId': state.session!.deviceId,
        'operation': 'finance3.paymentCommit',
        'params': params,
        'currency': entry.currency,
        'amountMinor': entry.amountMinor,
      };
      await database.execute(
        'INSERT INTO linked_payment_intents(id,data,state) VALUES(?,?,?)',
        [requestId, jsonEncode(intent), 'pending'],
      );
      await _deliver(requestId, intent);
    }
    database.personalChanged();
    return id;
  }

  Future<void> _reimburse(
    PaymentSpaceRef sourceSpace,
    String eventId, {
    required int expectedRevision,
    required int amountMinor,
    required DateTime paidAt,
    required String organizationAccountId,
    PaymentSpaceRef? organizationAccountScope,
  }) async {
    final accountSpace = organizationAccountScope ?? sourceSpace;
    if (!sourceSpace.isLocal) {
      _remote(sourceSpace);
      if (accountSpace.isLocal ||
          accountSpace.partition != sourceSpace.partition) {
        throw const CollaborationException('unsupported_payment_destination');
      }
      final request = newSharedId(),
          params = {
            'scopeId': sourceSpace.id,
            'eventId': eventId,
            'expectedRevision': expectedRevision,
            'legId': newSharedId(),
            'amountMinor': amountMinor,
            'paidAt': paidAt.toUtc().toIso8601String(),
            'organizationAccountId': organizationAccountId,
            'organizationAccountScopeId': accountSpace.id,
            'requestId': request,
          };
      final existing = await database.rows(
        'SELECT data FROM linked_payment_events WHERE space_key=? AND event_id=?',
        [sourceSpace.key, eventId],
      );
      if (existing.isEmpty) {
        throw const CollaborationException('record_missing');
      }
      final original = PaymentEvent.fromJson(_map(existing.single['data']));
      if (original.revision != expectedRevision ||
          !original.expectReimbursement ||
          amountMinor <= 0 ||
          amountMinor > original.receivableMinor ||
          paidAt.isBefore(original.paidAt)) {
        throw const CollaborationException('validation_error');
      }
      await _validateOrganizationAccount(
        accountSpace,
        organizationAccountId,
        original.currency,
      );
      final intent = {
        'source': PaymentSourceRef(
          space: sourceSpace,
          entryId: original.sourceEntryId,
          expectedRevision: expectedRevision,
        ).toJson(),
        'sourceSpaceKey': sourceSpace.key,
        'partition': sourceSpace.partition,
        'deviceId': collaboration!.state.session!.deviceId,
        'operation': 'finance3.paymentReimburse',
        'params': params,
        'currency': original.currency,
        'amountMinor': original.amountMinor,
        'organizationAccountScope': accountSpace.toJson(),
        'organizationAccountId': organizationAccountId,
      };
      await database.execute(
        'INSERT INTO linked_payment_intents(id,data,state) VALUES(?,?,?)',
        [request, jsonEncode(intent), 'pending'],
      );
      await _deliver(request, intent);
      return;
    }
    await database.transaction(() async {
      await _local(sourceSpace, kind: LocalSpaceKind.organization);
      final accounts = await _local(
        accountSpace,
        kind: LocalSpaceKind.organization,
      );
      final row = await database.rows(
        'SELECT data FROM linked_payment_events WHERE space_key=? AND event_id=?',
        [sourceSpace.key, eventId],
      );
      if (row.isEmpty) throw const CollaborationException('record_missing');
      final previous = PaymentEvent.fromJson(_map(row.single['data']));
      if (previous.revision != expectedRevision ||
          !previous.expectReimbursement ||
          amountMinor <= 0 ||
          amountMinor > previous.receivableMinor ||
          paidAt.isBefore(previous.paidAt) ||
          !accounts.financeAccounts.any(
            (a) =>
                a.id == organizationAccountId &&
                a.currency == previous.currency &&
                !a.archived,
          )) {
        throw const CollaborationException('validation_error');
      }
      final event = PaymentEvent.fromJson({
        ...previous.toJson(),
        'revision': previous.revision + 1,
        'reimbursements': [
          ...previous.toJson()['reimbursements'] as List,
          PaymentReimbursement(
            legId: newSharedId(),
            amountMinor: amountMinor,
            paidAt: paidAt,
            approvedByAccountId: previous.payerAccountId,
            organizationAccountId: organizationAccountId,
            organizationAccountScopeId: accountSpace.id,
          ).toJson(),
        ],
      });
      final last = event.reimbursements.last;
      await database.execute(
        'INSERT INTO linked_payment_cash(space_key,movement_id,data) VALUES(?,?,?)',
        [
          accountSpace.key,
          last.legId,
          jsonEncode(
            PaymentCashMovement(
              id: last.legId,
              accountId: organizationAccountId,
              amountMinor: -amountMinor,
              currency: previous.currency,
              paidAt: paidAt,
            ).toJson(),
          ),
        ],
      );
      await _saveEvent(sourceSpace, event);
      for (final row in await database.rows(
        "SELECT id,data FROM linked_payment_intents WHERE state IN ('local_only','waiting_source_publication')",
      )) {
        final intent = _map(row['data']);
        final original = PaymentEvent.fromJson(
          Map<String, dynamic>.from(intent['localEvent'] as Map),
        );
        if (original.eventId == eventId) {
          intent['localEvent'] = event.toJson();
          final requests = Map<String, dynamic>.from(
            intent['refundRequests'] as Map,
          );
          for (final leg in event.reimbursements) {
            requests.putIfAbsent(leg.legId, newSharedId);
          }
          intent['refundRequests'] = requests;
          await database.execute(
            'UPDATE linked_payment_intents SET data=? WHERE id=?',
            [jsonEncode(intent), row['id']],
          );
        }
      }
      for (final projection in await database.rows(
        'SELECT space_key,data FROM linked_payment_projections WHERE event_id=?',
        [eventId],
      )) {
        final old = PaymentProjection.fromJson(_map(projection['data']));
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
            projection['space_key'],
            eventId,
          ],
        );
      }
      await database.touchPersonal();
    });
    database.personalChanged();
  }
}
