part of 'crypto_business_payments.dart';

extension _CryptoPaymentCatchup on CryptoBusinessPayments {
  Future<Map<String, dynamic>> _finishTargets(
    String scope,
    Map params,
    String request,
    String hash,
  ) async {
    final reply = await _eventReply(scope, params['eventId'] as String);
    if (params['personalTarget'] == null &&
        params['householdScopeId'] == null) {
      return reply;
    }
    final source = await _require(scope, params['eventId'], 'paymentEvent');
    final event = PaymentEvent.fromJson(_raw(source));
    if (event.payerAccountId != actor) {
      // A different financial contributor may reimburse atomically, but never
      // gains the payer's private keys or silently acknowledges their sidecars.
      return {...reply, 'projectionPending': true};
    }
    var pending = false;
    final targets = <({String scope, String? account})>[
      if (params['personalTarget'] is Map)
        (
          scope: params['personalTarget']['scopeId'],
          account: params['personalTarget']['accountId'],
        ),
      if (params['householdScopeId'] != null)
        (scope: params['householdScopeId'], account: null),
    ];
    for (final target in targets) {
      try {
        if (!await _catchupTarget(
          source,
          event,
          target.scope,
          target.account,
          request,
          hash,
        )) {
          pending = true;
        }
      } on CryptoAuthorityPending catch (error) {
        lastPendingCode = error.reason;
        pending = true;
      } on CryptoProjectionPending catch (_, trace) {
        lastPendingCode = 'crypto_projection_pending';
        lastPendingTrace = trace;
        pending = true;
      } on CollaborationException catch (error) {
        lastPendingCode = error.code;
        if (!const {
          'permission_revoked',
          'finance_forbidden',
          'scope_unavailable',
          'crypto_device_keys_pending',
        }.contains(error.code)) {
          rethrow;
        }
        pending = true;
      }
    }
    return {...reply, 'projectionPending': pending};
  }

  Future<bool> _catchupTarget(
    Map<String, Object?> source,
    PaymentEvent event,
    String target,
    String? accountId,
    String request,
    String intentHash,
  ) async {
    final descriptor = await context.access.verifiedScopeDescriptor(
      target,
      online: true,
    );
    if (descriptor['kind'] != (accountId == null ? 'household' : 'personal')) {
      throw const FormatException('crypto_payment_target_kind');
    }
    if (accountId != null) {
      await _account(
        target,
        accountId,
        'personalFinanceAccount',
        event.currency,
      );
    }
    await context.pullVerified(target, 'finance');
    final sourceScope = event.sourceScopeId;
    final sourceHash = source['record_proof_hash'] as String;
    await context.database.execute(
      '''CREATE TABLE IF NOT EXISTS crypto_export_drafts (
      partition TEXT NOT NULL, scope_id TEXT NOT NULL, action_id TEXT NOT NULL,
      payload TEXT NOT NULL, PRIMARY KEY(partition,scope_id,action_id))''',
    );
    final saved = await context.database.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [p, target, request],
    );
    late Map<String, dynamic> journal;
    if (saved.isNotEmpty) {
      journal = Map<String, dynamic>.from(
        jsonDecode(saved.single['payload'] as String) as Map,
      );
      if (journal['operation'] != 'crypto2.payment.catchup' ||
          journal['intentHash'] != intentHash ||
          journal['sourceScopeId'] != sourceScope ||
          journal['eventId'] != event.eventId ||
          journal['accountId'] != accountId) {
        throw const FormatException('crypto_payment_immutable_catchup');
      }
      if (journal['sourceRecordProofHash'] != sourceHash) {
        if (!await _reconcileCatchupGeneration(journal)) return false;
        // The source advanced after all earlier immutable deliveries reached
        // known outcomes. Preserve the old generation and all of its bytes;
        // the original explicit target selection starts a fresh successor.
        final retiredId = context.codec.crypto.randomId();
        final retired = {
          ...journal,
          'operation': 'crypto2.payment.catchup.superseded',
          'successorSourceHash': sourceHash,
        };
        String id() => context.codec.crypto.randomId();
        journal = {
          ...journal,
          'sourceRecordProofHash': sourceHash,
          'sourceRaw': _raw(source),
          'offerAction': id(),
          'delegateAction': id(),
          'certificateAction': id(),
          'subjectNonce': id(),
          'groups': <Map<String, dynamic>>[],
          'state': 'preparing',
          'previousGenerationId': retiredId,
        };
        journal.remove('finalRequest');
        journal.remove('cashManifest');
        await context.database.transaction(() async {
          if (!context.account.directory.isCurrent()) {
            throw const CryptoAuthorityPending('crypto_identity_changed');
          }
          await context.database.execute(
            'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)',
            [p, target, retiredId, jsonEncode(retired)],
          );
          await context.database.execute(
            'UPDATE crypto_export_drafts SET payload=? WHERE partition=? AND scope_id=? AND action_id=?',
            [jsonEncode(journal), p, target, request],
          );
        });
      }
    } else {
      String id() => context.codec.crypto.randomId();
      journal = {
        'operation': 'crypto2.payment.catchup',
        'intentHash': intentHash,
        'sourceScopeId': sourceScope,
        'eventId': event.eventId,
        'accountId': accountId,
        'sourceRecordProofHash': sourceHash,
        'sourceRaw': _raw(source),
        'offerAction': id(),
        'delegateAction': id(),
        'certificateAction': id(),
        'subjectNonce': id(),
        'groups': <Map<String, dynamic>>[],
        'state': 'preparing',
      };
      await context.database.execute(
        'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)',
        [p, target, request, jsonEncode(journal)],
      );
    }
    Future<void> persist() => context.database.execute(
      'UPDATE crypto_export_drafts SET payload=? WHERE partition=? AND scope_id=? AND action_id=?',
      [jsonEncode(journal), p, target, request],
    );
    if (journal['state'] == 'complete') {
      return _verifyCompletedCatchup(target, event.eventId, journal);
    }
    final workflow = CryptoScopedExportWorkflow(context);
    final targetHead = await context.access.currentHead(target, online: true);
    final offer = await workflow.propose(
      actionId: journal['offerAction'],
      purpose: 'paymentSource',
      sourceScopeId: sourceScope,
      sourceCanonicalId: event.eventId,
      sourceType: 'paymentEvent',
      targetScopeId: target,
      targetHeadHash: targetHead.headHash,
      subjectNonce: journal['subjectNonce'],
    );
    late Map<String, dynamic> delegation;
    if (targetHead.member(actor)['manageKeys'] == true) {
      delegation = await workflow.delegate(
        actionId: journal['delegateAction'],
        targetScopeId: target,
        offerProof: offer['offerProof'],
      );
    } else {
      final discovered = await context.account.directory
          .call('crypto2.exports.delegation.forOffer', {
            'scopeId': target,
            'offerHash': await CryptoScopedExports.proofHash(
              Map<String, dynamic>.from(offer['offerProof'] as Map),
            ),
          });
      if (discovered['authorization'] == null) return false;
      delegation = {
        'delegationProof': Map<String, dynamic>.from(
          discovered['authorization'] as Map,
        ),
      };
    }
    final certificate = await workflow.certify(
      actionId: journal['certificateAction'],
      offerActionId: journal['offerAction'],
      targetScopeId: target,
      delegationProof: Map<String, dynamic>.from(
        delegation['delegationProof'] as Map,
      ),
    );
    final witness = {
      'version': 2,
      'delegationProof': delegation['delegationProof'],
      'certificateProof': certificate['certificateProof'],
      'disclosureSaltBase64': certificate['disclosureSaltBase64'],
      'disclosure': certificate['disclosure'],
    };
    final old = await _knownPaymentRow(
      target,
      event.eventId,
      'paymentProjection',
    );
    if (old != null && _raw(old)['privateAccountId'] != accountId) {
      throw const CollaborationException('payment_projection_locked');
    }
    final pendingRaw = Map<String, dynamic>.from(
      mergeCryptoPaymentPayload(old == null ? null : _raw(old), {
            ...PaymentProjection(
              event: event,
              state: PaymentProjectionState.pending,
              privateAccountId: accountId,
            ).toJson(),
            'paymentFormat': 2,
            'sourceState': journal['sourceRaw']['sourceState'],
            'paymentSourceWitness': witness,
          })
          as Map,
    );
    final cash = <_PaymentWrite>[];
    if (accountId != null) {
      cash.add(
        await _cash(
          target,
          event.eventId,
          accountId,
          -event.amountMinor,
          event.currency,
          event.paidAt,
          event,
          'advance',
          null,
        ),
      );
      for (final leg in event.reimbursements) {
        cash.add(
          await _cash(
            target,
            leg.legId,
            accountId,
            leg.amountMinor,
            event.currency,
            leg.paidAt,
            event,
            'refundCredit',
            leg.legId,
          ),
        );
      }
    }
    pendingRaw['cashConfirmations'] = {
      'version': 1,
      'records': [
        for (final item in cash.where((c) => c.before != null))
          {
            'id': context
                .address(target, 'finance', 'cashMovement', item.id)
                .wireId,
            'revision': item.before!['crypto_revision'],
            'recordProofHash': item.before!['record_proof_hash'],
            'kind': item.raw['paymentLink']['kind'],
            'legId': item.raw['paymentLink']['legId'],
          },
      ]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String)),
    };
    final groups = journal['groups'] as List;
    final chunks = cryptoPaymentCatchupGroups(cash);
    // Even a household with no private cash needs one durable projection.
    if (chunks.isEmpty) chunks.add(<_PaymentWrite>[]);
    for (var index = 0; index < chunks.length; index++) {
      if (groups.length <= index) {
        groups.add({
          'requestId': context.codec.crypto.randomId(),
          'state': 'pending',
          'ids': [for (final cash in chunks[index]) cash.id],
        });
        await persist();
      }
      final group = groups[index] as Map;
      if (CryptoBusinessJson.canonical(group['ids']) !=
          CryptoBusinessJson.canonical([
            for (final cash in chunks[index]) cash.id,
          ])) {
        throw const FormatException('crypto_payment_catchup_partition');
      }
      if (group['state'] == 'applied') continue;
      final writes = <_PaymentWrite>[];
      for (final item in chunks[index]) {
        if (item.before != null) {
          continue; // Never rewrite a previously proven leg.
        }
        writes.add(
          _PaymentWrite(item.scope, item.id, item.type, null, {
            ...item.raw,
            'paymentSourceWitness': witness,
          }),
        );
      }
      final currentProjection = await _knownPaymentRow(
        target,
        event.eventId,
        'paymentProjection',
      );
      writes.add(
        _PaymentWrite(
          target,
          event.eventId,
          'paymentProjection',
          currentProjection,
          pendingRaw,
        ),
      );
      final groupHash = await CryptoBusinessJson.hash({
        'parentIntent': intentHash,
        'sourceProof': sourceHash,
        'group': index,
        'ids': group['ids'],
      });
      await _publish(group['requestId'], groupHash, writes);
      await context.pullVerified(target, 'finance');
      group['state'] = 'applied';
      await persist();
    }
    // Completion is deliberately separate from every bounded cash group. Its
    // exact manifest is authenticated before any aggregate is called complete.
    final manifest = <Map<String, dynamic>>[];
    for (final item in cash) {
      final row = await context.record(
        target,
        'finance',
        item.id,
        type: 'cashMovement',
      );
      if (row == null) return false;
      final raw = _raw(row);
      CryptoPaymentSemantics.cash(
        raw: raw,
        before: raw,
        event: PaymentEvent.fromJson({
          ...event.toJson(),
          'revision': raw['paymentLink']['eventRevision'],
        }),
        scopeId: target,
        movementId: item.id,
        kind: raw['paymentLink']['kind'],
        legId: raw['paymentLink']['legId'],
        accountId: accountId!,
      );
      manifest.add({
        'id': context
            .address(target, 'finance', 'cashMovement', item.id)
            .wireId,
        'revision': row['crypto_revision'],
        'recordProofHash': row['record_proof_hash'],
        'kind': raw['paymentLink']['kind'],
        'legId': raw['paymentLink']['legId'],
      });
    }
    manifest.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    journal['cashManifest'] = {
      'version': 1,
      'sourceRecordProofHash': sourceHash,
      'count': manifest.length,
      'records': manifest,
      'manifestHash': await cryptoSha256(CryptoJson.encode(manifest)),
    };
    journal['state'] = 'ready';
    journal['finalRequest'] ??= context.codec.crypto.randomId();
    await persist();
    final currentProjection = await _knownPaymentRow(
      target,
      event.eventId,
      'paymentProjection',
    );
    final finalRaw = {
      ...pendingRaw,
      'state': 'complete',
      'cashManifest': journal['cashManifest'],
    };
    await _publish(
      journal['finalRequest'],
      await CryptoBusinessJson.hash({
        'parentIntent': intentHash,
        'manifest': journal['cashManifest'],
      }),
      [
        _PaymentWrite(
          target,
          event.eventId,
          'paymentProjection',
          currentProjection,
          finalRaw,
        ),
      ],
    );
    journal['state'] = 'complete';
    await persist();
    return true;
  }
}

extension _CryptoPaymentManifest on CryptoBusinessPayments {
  Future<bool> _reconcileCatchupGeneration(Map journal) async {
    final operations = <String>{
      for (final group in journal['groups'] as List)
        group['requestId'] as String,
      if (journal['finalRequest'] is String) journal['finalRequest'] as String,
    };
    for (final operationId in operations) {
      final rows = await context.database.rows(
        'SELECT o.request_id,o.state FROM crypto_business_requests b JOIN crypto_outbox o ON o.partition=b.partition AND o.request_id=b.request_id WHERE b.partition=? AND b.operation_id=?',
        [p, operationId],
      );
      if (rows.isEmpty) continue; // Complete journal-before-send contract.
      if (rows.length != 1) {
        throw const FormatException('crypto_payment_catchup_request');
      }
      await context.queue.resumeUnresolved(
        requestIds: {rows.single['request_id'] as String},
      );
      final finalRows = await context.database.rows(
        'SELECT state FROM crypto_outbox WHERE partition=? AND request_id=?',
        [p, rows.single['request_id']],
      );
      if (finalRows.length != 1 ||
          !const {'applied', 'rejected'}.contains(finalRows.single['state'])) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _verifyCompletedCatchup(
    String scope,
    String eventId,
    Map journal,
  ) async {
    final current = await context.record(
      scope,
      'finance',
      eventId,
      type: 'paymentProjection',
    );
    if (current == null || current['deleted'] == 1) return false;
    final wireId = context
        .address(scope, 'finance', 'paymentProjection', eventId)
        .wireId;
    final rows = await context.database.rows(
      'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
      [p, scope, 'finance', wireId, current['crypto_revision']],
    );
    if (rows.length != 1) return false;
    final wire = Map<String, dynamic>.from(
      jsonDecode(rows.single['wire'] as String) as Map,
    );
    final proof = Map<String, dynamic>.from(
      (wire['authorization'] as Map)['recordProof'] as Map,
    );
    if (await context.codec.digest(proof) != current['record_proof_hash']) {
      throw const FormatException('crypto_payment_catchup_projection');
    }
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    context.codec.validateUntrustedRecord(body);
    final authority = await _paymentWireAuthority(wire, body);
    final verified = await context.codec.verifyWire(
      serverId: context.account.directory.session.profile.serverId,
      wire: wire,
      trustedSigningKey: authority.signingKey,
      currentEpoch: authority.currentEpoch,
      closedRecordProofHash: authority.closedRecordProofHash,
    );
    final key = await context.access.getScopeKey(
      scope,
      'finance',
      verified['epoch'],
    );
    Uint8List? plaintext;
    try {
      plaintext = context.codec.openVerified(verified, key.key);
      if (plaintext == null) return false;
      final incoming = CryptoProjectionRecord(
        wire,
        verified,
        plaintext,
        historyBasis: authority.historyBasis ?? 'currentEpoch',
        batchKey: verified['batchId'],
      );
      final envelope = jsonDecode(utf8.decode(plaintext)) as Map;
      final raw =
          await context.expandPayload?.call(
            incoming,
            Map<String, dynamic>.from(envelope['payload'] as Map),
          ) ??
          Map<String, dynamic>.from(envelope['payload'] as Map);
      if (raw['state'] != 'complete' ||
          CryptoBusinessJson.canonical(raw['cashManifest']) !=
              CryptoBusinessJson.canonical(journal['cashManifest'])) {
        return false;
      }
      await _prepareRecords([incoming]);
      await _preparedWitness(
        CryptoBusinessProjection(
          record: verified,
          raw: raw,
          previousRaw: null,
          wire: wire,
        ),
      );
      return _preparedManifests.contains(await context.codec.digest(proof));
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
      key.release();
    }
  }

  Future<void> _verifyCashManifest(
    Map<String, dynamic> raw,
    Map<String, dynamic> record,
  ) async {
    final manifest = raw['cashManifest'];
    if (manifest is! Map ||
        manifest.length != 5 ||
        manifest['version'] != 1 ||
        manifest['records'] is! List ||
        manifest['count'] is! int ||
        manifest['count'] < 0 ||
        manifest['count'] > 501 ||
        (manifest['records'] as List).length != manifest['count'] ||
        manifest['manifestHash'] !=
            await cryptoSha256(CryptoJson.encode(manifest['records']))) {
      throw const FormatException('crypto_payment_cash_manifest');
    }
    final witness = raw['paymentSourceWitness'];
    if (witness is! Map) throw const CryptoProjectionPending();
    final certificate =
        CryptoJson.decode(
              cryptoBase64(witness['certificateProof']['commandBase64']),
            )
            as Map;
    if (manifest['sourceRecordProofHash'] !=
        certificate['sourceRecordProofHash']) {
      throw const FormatException('crypto_payment_cash_manifest');
    }
    final event = PaymentEvent.fromJson(raw),
        scope = record['scopeId'] as String;
    final expected = <String, ({String kind, String? leg})>{};
    if (raw['privateAccountId'] != null) {
      expected[context
          .address(scope, 'finance', 'cashMovement', event.eventId)
          .wireId] = (
        kind: 'advance',
        leg: null,
      );
      for (final leg in event.reimbursements) {
        final id = context
            .address(scope, 'finance', 'cashMovement', leg.legId)
            .wireId;
        if (expected.containsKey(id)) {
          throw const FormatException('crypto_payment_duplicate_cash');
        }
        expected[id] = (kind: 'refundCredit', leg: leg.legId);
      }
    }
    if (expected.length != manifest['count']) {
      throw const FormatException('crypto_payment_cash_manifest');
    }
    String? previous;
    for (final descriptor in manifest['records'] as List) {
      if (descriptor is! Map ||
          descriptor.length != 5 ||
          !isCryptoWireRecordId(descriptor['id']) ||
          descriptor['revision'] is! int ||
          descriptor['revision'] < 1 ||
          descriptor['recordProofHash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(descriptor['recordProofHash']) ||
          previous != null && previous.compareTo(descriptor['id']) >= 0) {
        throw const FormatException('crypto_payment_cash_manifest');
      }
      previous = descriptor['id'];
      final expectation = expected.remove(descriptor['id']);
      if (expectation == null ||
          descriptor['kind'] != expectation.kind ||
          descriptor['legId'] != expectation.leg) {
        throw const FormatException('crypto_payment_cash_manifest');
      }
      final current = await context.wireRecord(
        scope,
        'finance',
        descriptor['id'],
      );
      if (current == null ||
          current['deleted'] == 1 ||
          current['type'] != 'cashMovement' ||
          current['crypto_revision'] != descriptor['revision'] ||
          current['record_proof_hash'] != descriptor['recordProofHash']) {
        throw const CryptoProjectionPending();
      }
      final rows = await context.database.rows(
        'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
        [p, scope, 'finance', descriptor['id'], descriptor['revision']],
      );
      if (rows.length != 1) throw const CryptoProjectionPending();
      final wire = Map<String, dynamic>.from(
        jsonDecode(rows.single['wire'] as String) as Map,
      );
      final proof = Map<String, dynamic>.from(
        (wire['authorization'] as Map)['recordProof'] as Map,
      );
      if (await context.codec.digest(proof) != descriptor['recordProofHash']) {
        throw const FormatException('crypto_payment_cash_manifest_proof');
      }
      final body = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      context.codec.validateUntrustedRecord(body);
      final authority = await _paymentWireAuthority(wire, body);
      final verified = await context.codec.verifyWire(
        serverId: context.account.directory.session.profile.serverId,
        wire: wire,
        trustedSigningKey: authority.signingKey,
        currentEpoch: authority.currentEpoch,
        closedRecordProofHash: authority.closedRecordProofHash,
      );
      final key = await context.access.getScopeKey(
        scope,
        'finance',
        verified['epoch'],
      );
      Uint8List? plaintext;
      try {
        plaintext = context.codec.openVerified(verified, key.key);
        if (plaintext == null) {
          throw const FormatException('crypto_payment_cash_manifest_proof');
        }
        final incoming = CryptoProjectionRecord(
          wire,
          verified,
          plaintext,
          historyBasis: authority.historyBasis ?? 'currentEpoch',
          batchKey: verified['batchId'],
        );
        final envelope = jsonDecode(utf8.decode(plaintext)) as Map;
        if (envelope['format'] != 2 ||
            envelope.length != 3 ||
            CryptoBusinessJson.canonical(envelope['identity']) !=
                CryptoBusinessJson.canonical(
                  verified['metadata']['identity'],
                )) {
          throw const FormatException('crypto_payment_envelope');
        }
        final cashRaw =
            await context.expandPayload?.call(
              incoming,
              Map<String, dynamic>.from(envelope['payload'] as Map),
            ) ??
            Map<String, dynamic>.from(envelope['payload'] as Map);
        await _prepareRecords([incoming]);
        final source = await _preparedWitness(
          CryptoBusinessProjection(
            record: verified,
            raw: cashRaw,
            previousRaw: null,
            wire: wire,
          ),
        );
        var prior = PaymentEvent.fromJson(source.disclosure);
        final cashHash = await context.codec.digest(proof);
        if (_preparedWitnesses[cashHash]?.confirmedByTargetProofHash != null) {
          prior = PaymentEvent.fromJson({
            ...source.disclosure,
            'revision': cashRaw['paymentLink']['eventRevision'],
          });
        }
        if (prior.eventId != event.eventId ||
            prior.sourceScopeId != event.sourceScopeId ||
            prior.sourceEntryId != event.sourceEntryId ||
            prior.payerAccountId != event.payerAccountId ||
            prior.currency != event.currency ||
            prior.amountMinor != event.amountMinor ||
            prior.paidAt != event.paidAt ||
            prior.revision > event.revision) {
          throw const FormatException('crypto_payment_cash_manifest_facts');
        }
        CryptoPaymentSemantics.cash(
          raw: cashRaw,
          before: cashRaw,
          event: prior,
          scopeId: scope,
          movementId: verified['metadata']['identity']['canonicalId'],
          kind: expectation.kind,
          legId: expectation.leg,
          accountId: raw['privateAccountId'],
        );
        if (expectation.leg != null) {
          final old = prior.reimbursements
              .where((l) => l.legId == expectation.leg)
              .single;
          final now = event.reimbursements
              .where((l) => l.legId == expectation.leg)
              .single;
          if (CryptoBusinessJson.canonical(old.toJson(projection: true)) !=
              CryptoBusinessJson.canonical(now.toJson(projection: true))) {
            throw const FormatException('crypto_payment_cash_manifest_facts');
          }
        }
      } finally {
        plaintext?.fillRange(0, plaintext.length, 0);
        key.release();
      }
    }
    if (expected.isNotEmpty) {
      throw const FormatException('crypto_payment_cash_manifest');
    }
  }
}

extension _CryptoPaymentGroupJournal on CryptoBusinessPayments {
  Future<Map<String, dynamic>> _paymentGroupJournal(
    String request,
    String hash,
    List<_PaymentWrite> writes,
  ) async {
    await context.database.execute(
      '''CREATE TABLE IF NOT EXISTS crypto_export_drafts (
      partition TEXT NOT NULL,scope_id TEXT NOT NULL,action_id TEXT NOT NULL,payload TEXT NOT NULL,
      PRIMARY KEY(partition,scope_id,action_id))''',
    );
    final rows = await context.database.rows(
      "SELECT payload FROM crypto_export_drafts WHERE partition=? AND action_id=? AND json_extract(payload,'\$.operation')='crypto2.payment.group'",
      [p, request],
    );
    if (rows.length > 1) {
      throw const FormatException('crypto_payment_group_journal');
    }
    if (rows.isNotEmpty) {
      final journal = Map<String, dynamic>.from(
        jsonDecode(rows.single['payload'] as String) as Map,
      );
      if (journal['localHash'] != hash) {
        throw const FormatException('crypto_payment_immutable_group');
      }
      return journal;
    }
    if (writes.isEmpty || writes.length > 32) {
      throw const FormatException('crypto_payment_group_size');
    }
    final journal = <String, dynamic>{
      'operation': 'crypto2.payment.group',
      'localHash': hash,
      'scopeId': writes.first.scope,
      'batchId': context.codec.crypto.randomId(),
      'proofs': <Map<String, dynamic>>[],
      'exportBindings': <Map<String, dynamic>>[],
      'exportActions': <String, dynamic>{},
      'writes': [
        for (final w in writes)
          {
            'scope': w.scope,
            'id': w.id,
            'type': w.type,
            'before': w.before,
            'raw': w.raw,
          },
      ],
    };
    await context.database.execute(
      'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)',
      [p, writes.first.scope, request, jsonEncode(journal)],
    );
    return journal;
  }

  Future<void> _savePaymentGroup(
    Map journal,
    String request,
  ) => context.database.execute(
    'UPDATE crypto_export_drafts SET payload=? WHERE partition=? AND scope_id=? AND action_id=?',
    [jsonEncode(journal), p, journal['scopeId'], request],
  );

  Future<void> _bindCrossScopeCash(
    Map<String, dynamic> journal,
    String request,
    int index,
    _PaymentWrite target,
    List<Map<String, dynamic>> proofs,
    Map<String, dynamic> targetRecord,
  ) async {
    final link = target.raw['paymentLink'] as Map;
    final candidates = proofs.where((proof) {
      final body =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      return body['scopeId'] == link['sourceScopeId'] &&
          body['type'] == 'paymentEvent' &&
          body['metadata']['identity']['canonicalId'] == link['eventId'];
    }).toList();
    if (candidates.length != 1) throw const CryptoProjectionPending();
    final sourceProof = candidates.single;
    final sourceBody =
        CryptoJson.decode(cryptoBase64(sourceProof['commandBase64'])) as Map;
    final sourceWrite =
        (journal['writes'] as List)
                .where(
                  (w) =>
                      w['scope'] == link['sourceScopeId'] &&
                      w['id'] == link['eventId'] &&
                      w['type'] == 'paymentEvent',
                )
                .single
            as Map;
    final actions = journal['exportActions'] as Map;
    final key = targetRecord['id'] as String;
    if (!actions.containsKey(key)) {
      String id() => context.codec.crypto.randomId();
      actions[key] = {
        'offerAction': id(),
        'delegateAction': id(),
        'bindingAction': id(),
        'subjectNonce': id(),
      };
      await _savePaymentGroup(journal, request);
    }
    final action = actions[key] as Map;
    final workflow = CryptoScopedExportWorkflow(context);
    final offer = await workflow.propose(
      actionId: action['offerAction'],
      purpose: 'paymentSource',
      sourceScopeId: link['sourceScopeId'],
      sourceCanonicalId: link['eventId'],
      sourceType: 'paymentEvent',
      targetScopeId: target.scope,
      targetHeadHash: targetRecord['membershipHeadHash'],
      subjectNonce: action['subjectNonce'],
      sourceProof: sourceBody['expectedRevision'] == 0 ? sourceProof : null,
    );
    final targetHead = await context.access.currentHead(
      target.scope,
      online: true,
    );
    Map<String, dynamic>? delegationProof;
    if (targetHead.member(actor)['manageKeys'] == true) {
      final delegation = await workflow.delegate(
        actionId: action['delegateAction'],
        targetScopeId: target.scope,
        offerProof: offer['offerProof'],
      );
      delegationProof = Map<String, dynamic>.from(
        delegation['delegationProof'] as Map,
      );
    } else {
      final discovered = await context.account.directory
          .call('crypto2.exports.delegation.forOffer', {
            'scopeId': target.scope,
            'offerHash': await CryptoScopedExports.proofHash(
              Map<String, dynamic>.from(offer['offerProof'] as Map),
            ),
          });
      if (discovered['authorization'] is Map) {
        delegationProof = Map<String, dynamic>.from(
          discovered['authorization'] as Map,
        );
      }
    }
    if (delegationProof == null) {
      throw const CryptoAuthorityPending(
        'crypto_payment_target_approval_pending',
      );
    }
    final prepared = await workflow.prepareBatchCertificate(
      actionId: action['bindingAction'],
      targetScopeId: target.scope,
      offerActionId: action['offerAction'],
      delegationProof: delegationProof,
      sourceProof: sourceProof,
      sourceRaw: Map<String, dynamic>.from(sourceWrite['raw'] as Map),
      targetRecord: targetRecord,
    );
    target.raw['paymentSourceWitness'] = prepared['witness'];
    (journal['writes'] as List)[index]['raw'] = target.raw;
    (journal['exportBindings'] as List).add(prepared['binding']);
    await _savePaymentGroup(journal, request);
  }
}

class _LatestPaymentFacts {
  const _LatestPaymentFacts(
    this.disclosure,
    this.raw,
    this.wire,
    this.pins,
    this.proofHash,
  );
  final VerifiedScopedDisclosure disclosure;
  final Map<String, dynamic> raw, wire;
  final Map<String, String?> pins;
  final String proofHash;
}

extension _CryptoPaymentConfirmations on CryptoBusinessPayments {
  Future<Map<String, Object?>?> _knownPaymentRow(
    String scope,
    String canonicalId,
    String type,
  ) async {
    final current = await context.record(
      scope,
      'finance',
      canonicalId,
      type: type,
    );
    final id = context.address(scope, 'finance', type, canonicalId).wireId;
    final rows = await context.database.rows(
      'SELECT wire,revision FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? ORDER BY revision DESC LIMIT 1',
      [p, scope, 'finance', id],
    );
    if (rows.isEmpty ||
        current != null &&
            (current['crypto_revision'] as int) >=
                (rows.single['revision'] as int)) {
      return current;
    }
    final wire = Map<String, dynamic>.from(
      jsonDecode(rows.single['wire'] as String) as Map,
    );
    final body = await _verifiedPaymentWire(wire);
    if (body['scopeId'] != scope ||
        body['id'] != id ||
        body['type'] != type ||
        body['deleted'] == true) {
      throw const FormatException('crypto_payment_known_row');
    }
    final key = await context.access.getScopeKey(
      scope,
      'finance',
      body['epoch'],
    );
    Uint8List? bytes;
    try {
      bytes = context.codec.openVerified(body, key.key);
      if (bytes == null) return null;
      final incoming = CryptoProjectionRecord(
        wire,
        body,
        bytes,
        historyBasis: 'currentEpoch',
        batchKey: body['batchId'],
      );
      final documents = CryptoBusinessDocuments(context);
      await documents.prepareRecords([incoming]);
      final envelope = jsonDecode(utf8.decode(bytes)) as Map;
      if (envelope['format'] != 2 ||
          envelope.length != 3 ||
          CryptoBusinessJson.canonical(envelope['identity']) !=
              CryptoBusinessJson.canonical(body['metadata']['identity'])) {
        throw const FormatException('crypto_payment_envelope');
      }
      final raw = await documents.expandPayload(
        incoming,
        Map<String, dynamic>.from(envelope['payload'] as Map),
      );
      validateRaw('finance', type, raw);
      return {
        'id': id,
        'type': type,
        'scope_id': scope,
        'domain': 'finance',
        'deleted': 0,
        'raw_payload': jsonEncode(raw),
        'projection': jsonEncode(raw),
        'crypto_revision': wire['revision'],
        'legacy_revision': 0,
        'revision_namespace': 'crypto',
        'record_proof_hash': await context.codec.digest(
          Map<String, dynamic>.from(
            (wire['authorization'] as Map)['recordProof'] as Map,
          ),
        ),
      };
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      key.release();
    }
  }

  Future<Map<String, dynamic>> _verifiedPaymentWire(
    Map<String, dynamic> wire,
  ) async {
    final proof = Map<String, dynamic>.from(
      (wire['authorization'] as Map)['recordProof'] as Map,
    );
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    context.codec.validateUntrustedRecord(body);
    final authority = await _paymentWireAuthority(wire, body);
    return context.codec.verifyWire(
      serverId: context.account.directory.session.profile.serverId,
      wire: wire,
      trustedSigningKey: authority.signingKey,
      currentEpoch: authority.currentEpoch,
      closedRecordProofHash: authority.closedRecordProofHash,
    );
  }

  Future<CryptoRecordAuthority> _paymentWireAuthority(
    Map<String, dynamic> wire,
    Map<String, dynamic> body,
  ) async {
    try {
      return await context.access.recordAuthority(body);
    } on CryptoAuthorityPending {
      // Only this actual target proof can use an independently verified
      // closure/own-observed checkpoint. No current-epoch or old-author bypass.
      return context.access.historicalTargetAuthority(wire);
    }
  }

  Future<void> _factsPins(_LatestPaymentFacts facts) async {
    if (!context.account.directory.isCurrent()) {
      throw const CryptoProjectionPending();
    }
    for (final pin in facts.pins.entries) {
      if (await context.account.store.secure.read(pin.key) != pin.value) {
        throw const CryptoProjectionPending();
      }
    }
    if (!context.account.directory.isCurrent()) {
      throw const CryptoProjectionPending();
    }
  }

  Future<void> _prepareCashConfirmations(
    CryptoProjectionRecord projection,
    Map raw,
    _LatestPaymentFacts facts,
  ) async {
    final confirmations = raw['cashConfirmations'];
    if (confirmations == null) return;
    if (confirmations is! Map ||
        confirmations.length != 2 ||
        confirmations['version'] != 1 ||
        confirmations['records'] is! List ||
        (confirmations['records'] as List).length > 501) {
      throw const FormatException('crypto_payment_cash_confirmations');
    }
    final event = PaymentEvent.fromJson(facts.disclosure.disclosure),
        scope = projection.record['scopeId'] as String;
    String? previous;
    for (final descriptor in confirmations['records'] as List) {
      if (descriptor is! Map ||
          descriptor.length != 5 ||
          !isCryptoWireRecordId(descriptor['id']) ||
          descriptor['revision'] is! int ||
          descriptor['revision'] < 1 ||
          descriptor['recordProofHash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(descriptor['recordProofHash']) ||
          previous != null && previous.compareTo(descriptor['id']) >= 0) {
        throw const FormatException('crypto_payment_cash_confirmations');
      }
      previous = descriptor['id'];
      var rows = await context.database.rows(
        'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
        [p, scope, 'finance', descriptor['id'], descriptor['revision']],
      );
      Map<String, dynamic> wire;
      if (rows.length == 1) {
        wire = Map<String, dynamic>.from(
          jsonDecode(rows.single['wire'] as String) as Map,
        );
      } else {
        final head = await context.access.currentHead(scope, online: true);
        final response = await context.account.directory
            .call('crypto2.records.historyGet', {
              'scopeId': scope,
              'domain': 'finance',
              'accessRevision': head.accessRevision,
              'id': descriptor['id'],
              'revision': descriptor['revision'],
              'recordProofHash': descriptor['recordProofHash'],
            });
        wire = Map<String, dynamic>.from(response['record'] as Map);
      }
      final hash = await context.codec.digest(
        Map<String, dynamic>.from(
          (wire['authorization'] as Map)['recordProof'] as Map,
        ),
      );
      if (hash != descriptor['recordProofHash'] ||
          wire['revision'] != descriptor['revision']) {
        throw const FormatException('crypto_payment_cash_confirmations');
      }
      final body = await _verifiedPaymentWire(wire);
      if (body['scopeId'] != scope ||
          body['domain'] != 'finance' ||
          body['type'] != 'cashMovement' ||
          body['id'] != descriptor['id']) {
        throw const FormatException('crypto_payment_cash_confirmations');
      }
      final key = await context.access.getScopeKey(
        scope,
        'finance',
        body['epoch'],
      );
      Uint8List? bytes;
      try {
        bytes = context.codec.openVerified(body, key.key);
        if (bytes == null) {
          throw const FormatException('crypto_payment_cash_confirmations');
        }
        final value = CryptoProjectionRecord(
          wire,
          body,
          bytes,
          historyBasis: 'currentEpoch',
          batchKey: body['batchId'],
        );
        final envelope = jsonDecode(utf8.decode(bytes)) as Map;
        if (envelope['format'] != 2 ||
            envelope.length != 3 ||
            CryptoBusinessJson.canonical(envelope['identity']) !=
                CryptoBusinessJson.canonical(body['metadata']['identity'])) {
          throw const FormatException('crypto_payment_envelope');
        }
        final documents = CryptoBusinessDocuments(context);
        await documents.prepareRecords([value]);
        final cash = await documents.expandPayload(
          value,
          Map<String, dynamic>.from(envelope['payload'] as Map),
        );
        final kind = descriptor['kind'], leg = descriptor['legId'];
        if (!const {'advance', 'refundCredit'}.contains(kind) ||
            raw['privateAccountId'] == null ||
            descriptor['id'] !=
                context
                    .address(
                      scope,
                      'finance',
                      'cashMovement',
                      kind == 'advance' ? event.eventId : leg,
                    )
                    .wireId ||
            cash['paymentLink']?['eventRevision'] is! int ||
            cash['paymentLink']['eventRevision'] > event.revision) {
          throw const FormatException('crypto_payment_cash_confirmations');
        }
        CryptoPaymentSemantics.cash(
          raw: cash,
          before: cash,
          event: PaymentEvent.fromJson({
            ...facts.disclosure.disclosure,
            'revision': cash['paymentLink']['eventRevision'],
          }),
          scopeId: scope,
          movementId: body['metadata']['identity']['canonicalId'],
          kind: kind,
          legId: leg,
          accountId: raw['privateAccountId'],
        );
        final unique = await _unique(scope, 'cashMovement', cash);
        if (CryptoBusinessJson.canonical(body['metadata']['uniqueRefs']) !=
            CryptoBusinessJson.canonical([unique])) {
          throw const FormatException('crypto_payment_unique_binding');
        }
        await _factsPins(facts);
        _preparedUnique[hash] = unique;
        _preparedWitnesses[hash] = _PreparedPaymentWitness(
          facts.disclosure,
          facts.pins,
          confirmedByTargetProofHash: facts.proofHash,
        );
      } finally {
        bytes?.fillRange(0, bytes.length, 0);
        key.release();
      }
    }
  }

  Future<VerifiedScopedDisclosure?> _confirmedFactsFor(
    CryptoProjectionRecord value,
    Map raw,
    String hash,
  ) async {
    final memo = _preparedWitnesses[hash];
    if (memo?.confirmedByTargetProofHash != null) {
      final candidate = CryptoBusinessProjection(
        record: value.record,
        raw: Map<String, dynamic>.from(raw),
        previousRaw: null,
        wire: value.wire,
      );
      try {
        return await _preparedWitness(candidate);
      } on CryptoProjectionPending {
        // A new own observation may advance the directory while cash remains
        // immutable. Reverify the actual current confirming projection, never
        // reuse its stale memo or promote the older issuer certificate.
        await _refreshCashConfirmation(value, raw);
        return _preparedWitness(candidate);
      }
    }
    if (value.record['type'] != 'paymentProjection') return null;
    final facts =
        _latestFacts['${value.record['scopeId']}:${raw['sourceScopeId']}:${raw['eventId']}'];
    if (facts == null ||
        facts.proofHash == hash ||
        (facts.wire['revision'] as int) <= (value.wire['revision'] as int)) {
      return null;
    }
    await _factsPins(facts);
    final current = await context.wireRecord(
      value.record['scopeId'],
      'finance',
      value.record['id'],
    );
    if (current == null ||
        current['record_proof_hash'] != facts.proofHash ||
        (current['crypto_revision'] as int) <=
            (value.wire['revision'] as int)) {
      return null;
    }
    final old = CryptoScopedExportWorkflow.paymentDisclosure(
          Map<String, dynamic>.from(raw),
        ),
        now = facts.disclosure.disclosure;
    for (final key in old.keys.where(
      (k) => !const {'revision', 'reimbursements', 'sourceState'}.contains(k),
    )) {
      if (CryptoBusinessJson.canonical(old[key]) !=
          CryptoBusinessJson.canonical(now[key])) {
        throw const FormatException('crypto_payment_projection_confirmation');
      }
    }
    if (old['revision'] > now['revision'] ||
        (old['reimbursements'] as List).length >
            (now['reimbursements'] as List).length) {
      throw const FormatException('crypto_payment_projection_confirmation');
    }
    for (var i = 0; i < (old['reimbursements'] as List).length; i++) {
      if (CryptoBusinessJson.canonical(old['reimbursements'][i]) !=
          CryptoBusinessJson.canonical(now['reimbursements'][i])) {
        throw const FormatException('crypto_payment_projection_confirmation');
      }
    }
    final chain = await context.access.openHistoryChain(facts.wire);
    var found = false;
    while (chain.nextRevision >= value.wire['revision']) {
      final rows = await context.database.rows(
        'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
        [
          p,
          value.record['scopeId'],
          'finance',
          value.record['id'],
          chain.nextRevision,
        ],
      );
      if (rows.length != 1) return null;
      final ancestor = Map<String, dynamic>.from(
        jsonDecode(rows.single['wire'] as String) as Map,
      );
      final digest = await context.codec.digest(
        Map<String, dynamic>.from(
          (ancestor['authorization'] as Map)['recordProof'] as Map,
        ),
      );
      await chain.authority(ancestor);
      if (ancestor['revision'] == value.wire['revision']) {
        found = digest == hash;
        break;
      }
    }
    if (!found) {
      throw const FormatException('crypto_payment_projection_confirmation');
    }
    _preparedWitnesses[hash] = _PreparedPaymentWitness(
      facts.disclosure,
      facts.pins,
      confirmedByTargetProofHash: facts.proofHash,
    );
    return facts.disclosure;
  }

  Future<void> _refreshCashConfirmation(
    CryptoProjectionRecord cash,
    Map raw,
  ) async {
    if (cash.record['type'] != 'cashMovement') {
      throw const CryptoProjectionPending();
    }
    final scope = cash.record['scopeId'] as String,
        eventId = raw['paymentLink']['eventId'] as String;
    final guard = '$scope:$eventId';
    if (!_refreshingConfirmations.add(guard)) {
      throw const CryptoProjectionPending();
    }
    try {
      final current = await context.record(
        scope,
        'finance',
        eventId,
        type: 'paymentProjection',
      );
      if (current == null || current['deleted'] == 1) {
        throw const CryptoProjectionPending();
      }
      final rows = await context.database.rows(
        'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
        [p, scope, 'finance', current['id'], current['crypto_revision']],
      );
      if (rows.length != 1) throw const CryptoProjectionPending();
      final wire = Map<String, dynamic>.from(
        jsonDecode(rows.single['wire'] as String) as Map,
      );
      final proof = Map<String, dynamic>.from(
        (wire['authorization'] as Map)['recordProof'] as Map,
      );
      if (await context.codec.digest(proof) != current['record_proof_hash']) {
        throw const FormatException('crypto_payment_confirmation_projection');
      }
      final body = await _verifiedPaymentWire(wire);
      if (body['type'] != 'paymentProjection' ||
          body['scopeId'] != scope ||
          body['domain'] != 'finance' ||
          body['metadata']['identity']['canonicalId'] != eventId) {
        throw const FormatException('crypto_payment_confirmation_projection');
      }
      final key = await context.access.getScopeKey(
        scope,
        'finance',
        body['epoch'],
      );
      Uint8List? plaintext;
      try {
        plaintext = context.codec.openVerified(body, key.key);
        if (plaintext == null) throw const CryptoProjectionPending();
        await _prepareRecords([
          CryptoProjectionRecord(
            wire,
            body,
            plaintext,
            historyBasis: 'currentEpoch',
            batchKey: body['batchId'],
          ),
        ]);
      } finally {
        plaintext?.fillRange(0, plaintext.length, 0);
        key.release();
      }
    } finally {
      _refreshingConfirmations.remove(guard);
    }
  }
}
