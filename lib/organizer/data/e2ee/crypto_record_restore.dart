part of 'crypto_business_router.dart';

class _RecordRestoreSource {
  const _RecordRestoreSource(this.tag, this.policy, this.raw, this.wireRaw);
  final Map<String, dynamic> tag, policy, raw, wireRaw;
}

extension CryptoBusinessRecordRestores on CryptoBusinessSession {
  Future<bool> _supportsRecordRestores() => _recordRestoreSupport ??= () async {
    final directory = account.directory;
    final caps = await CryptoCapabilityDiscovery.read(
      transport: directory.transport,
      session: directory.session,
    );
    if (!directory.isCurrent())
      throw const CryptoAuthorityPending('crypto_stale_identity');
    if (caps['serverId'] != directory.session.profile.serverId) {
      throw const FormatException('crypto_record_restore_invalid');
    }
    return caps['recordPolicyRestores'] == true &&
        await recordPolicies.supported();
  }();

  Future<Map<String, dynamic>> _restoreWire(
    String scope,
    String domain,
    String wireId,
    int revision,
    String hash,
  ) async {
    final rows = await db.rows(
      "SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND verdict='verified' UNION ALL SELECT wire FROM crypto_business_history_proofs WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?",
      [
        p,
        scope,
        domain,
        wireId,
        revision,
        p,
        scope,
        domain,
        wireId,
        revision,
        hash,
      ],
    );
    for (final row in rows) {
      final wire = Map<String, dynamic>.from(
        jsonDecode(row['wire'] as String) as Map,
      );
      if (await codec.digest(
            Map<String, dynamic>.from(
              wire['authorization']['recordProof'] as Map,
            ),
          ) ==
          hash)
        return wire;
    }
    final read = await access.readContext(scope, domain);
    final response = await account.directory
        .call('crypto2.records.historyGet', {
          'scopeId': scope,
          'domain': domain,
          'accessRevision': read.accessRevision,
          'recordProofHash': hash,
        });
    final wire = Map<String, dynamic>.from(response['record'] as Map);
    final proof = Map<String, dynamic>.from(
      wire['authorization']['recordProof'] as Map,
    );
    final body = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    if (await codec.digest(proof) != hash ||
        wire['revision'] != revision ||
        body['scopeId'] != scope ||
        body['domain'] != domain ||
        body['id'] != wireId) {
      throw const FormatException('crypto_record_restore_predecessor');
    }
    return wire;
  }

  // The signed tombstone is the authority anchor. Every hop is checked by the
  // existing historical authority verifier; a cached plaintext never grants
  // restoration authority. The first live predecessor is the only eligible one.
  Future<_RecordRestoreSource> _recordRestoreSource({
    required String scope,
    required String domain,
    required String type,
    required String canonicalId,
    required Map<String, Object?> before,
    Map<String, dynamic>? expectedTag,
  }) async {
    final wireId = address(scope, domain, type, canonicalId).wireId;
    if (before['deleted'] != 1 || before['type'] != type) {
      throw const FormatException('crypto_record_restore_predecessor');
    }
    final tombstoneHash = before['record_proof_hash'] as String;
    final tombstone = await _restoreWire(
      scope,
      domain,
      wireId,
      before['crypto_revision'] as int,
      tombstoneHash,
    );
    final tombstoneBody = Map<String, dynamic>.from(
      CryptoJson.decode(
            cryptoBase64(
              tombstone['authorization']['recordProof']['commandBase64'],
            ),
          )
          as Map,
    );
    if (tombstoneBody['deleted'] != true || tombstoneBody['type'] != type) {
      throw const FormatException('crypto_record_restore_predecessor');
    }
    final prior = await _policyPredecessor(
      scope: scope,
      domain: domain,
      type: type,
      canonicalId: canonicalId,
      before: before,
    );
    if (prior == null)
      throw const CryptoAuthorityPending(
        'crypto_record_restore_history_pending',
      );
    final chain = await access.openHistoryChain(tombstone);
    for (var count = 0; count < 63 && chain.nextRevision > 0; count++) {
      final hash = chain.nextHash, revision = chain.nextRevision;
      final wire = await _restoreWire(scope, domain, wireId, revision, hash);
      final authority = await chain.authority(wire);
      final body = await codec.verifyWire(
        serverId: account.directory.session.profile.serverId,
        wire: wire,
        trustedSigningKey: authority.signingKey,
        currentEpoch: authority.currentEpoch,
        closedRecordProofHash: authority.closedRecordProofHash,
      );
      if (body['type'] != type)
        throw const FormatException('crypto_record_restore_predecessor');
      if (body['deleted'] == true) continue;
      final tag = <String, dynamic>{
        'version': 1,
        'tombstoneProofHash': tombstoneHash,
        'previousLiveProofHash': hash,
      };
      if (expectedTag != null &&
          CryptoBusinessJson.canonical(tag) !=
              CryptoBusinessJson.canonical(expectedTag)) {
        throw const FormatException('crypto_record_restore_predecessor');
      }
      final key = await access.recordKey(body);
      Uint8List? bytes;
      try {
        bytes = codec.openVerified(body, key.key);
      } finally {
        key.release();
      }
      if (bytes == null)
        throw const FormatException('crypto_record_restore_predecessor');
      try {
        final envelope = jsonDecode(utf8.decode(bytes));
        if (envelope is! Map ||
            !const [1, 2].contains(envelope['format']) ||
            envelope['payload'] is! Map ||
            envelope['format'] == 2 &&
                envelope.length !=
                    (authority.migrationOrigin == null ||
                            authority.migrationOrigin!['sourceTable'] ==
                                'familyhub_scopes' ||
                            authority.migrationOrigin!['captureVersion'] == 3
                        ? 3
                        : 4) ||
            envelope['format'] == 2 &&
                CryptoInventoryJson.canonical(envelope['identity']) !=
                    CryptoInventoryJson.canonical(
                      body['metadata']['identity'],
                    )) {
          throw const FormatException('crypto_record_restore_invalid');
        }
        var raw = Map<String, dynamic>.from(envelope['payload'] as Map);
        if (authority.migrationOrigin != null) {
          raw =
              await verifyCryptoMigrationWitness(
                record: body,
                origin: authority.migrationOrigin!,
                recordProofHash: hash,
                envelope: Map<String, dynamic>.from(envelope),
                detachedWitness: authority.migrationWitness,
                reservedId: reservedRecordId,
              ) ??
              (throw const FormatException(
                'crypto_record_restore_predecessor',
              ));
        }
        final wireRaw = Map<String, dynamic>.from(raw);
        final observed = CryptoProjectionRecord(
          wire,
          body,
          bytes,
          historyBasis: authority.currentEpoch
              ? 'currentEpoch'
              : authority.historyBasis ?? 'unconfirmed',
          batchKey: await codec.digest(
            Map<String, dynamic>.from(
              wire['authorization']['batchCommitment'] as Map,
            ),
          ),
          migrationOrigin: authority.migrationOrigin,
          relocationOrigin: authority.relocationOrigin,
          migrationWitness: authority.migrationWitness,
        );
        await prepareHistoricalPayload?.call([observed]);
        if (expandPayload != null) raw = await expandPayload!(observed, raw);
        await validateHistoricalPayload?.call(observed, raw);
        final livePolicy = (body['metadata'] as Map)['recordPolicy'];
        if (livePolicy is Map) {
          await CryptoRecordPolicy.verifyPayload(record: body, payload: raw);
          if (livePolicy['createdByAccountId'] !=
                  prior.policy['createdByAccountId'] ||
              tombstoneBody['metadata']['recordPolicy'] is Map &&
                  CryptoBusinessJson.canonical(
                        livePolicy['fieldCommitments'],
                      ) !=
                      CryptoBusinessJson.canonical(
                        prior.policy['fieldCommitments'],
                      )) {
            throw const FormatException('crypto_record_author_substitution');
          }
        }
        // A baseline installed over a legacy tombstone owns the stable secret.
        // Its deleted commitments are checked against that exact signed sidecar.
        if (tombstoneBody['metadata']['recordPolicy'] == null ||
            livePolicy == null) {
          final baseline = await recordPolicies.record(
            scopeId: scope,
            domain: domain,
            id: wireId,
            recordProofHash: tombstoneBody['metadata']['recordPolicy'] == null
                ? tombstoneHash
                : hash,
          );
          if (baseline == null)
            throw const CryptoAuthorityPending(
              'crypto_record_restore_history_pending',
            );
          try {
            if (baseline.policy['createdByAccountId'] !=
                    prior.policy['createdByAccountId'] ||
                tombstoneBody['metadata']['recordPolicy'] is Map &&
                    CryptoBusinessJson.canonical(
                          baseline.policy['fieldCommitments'],
                        ) !=
                        CryptoBusinessJson.canonical(
                          prior.policy['fieldCommitments'],
                        )) {
              throw const FormatException('crypto_record_author_substitution');
            }
            raw = CryptoRecordPolicy.attachSecret(raw, baseline.key);
            final actual = await CryptoRecordPolicy.commitments(
              serverId: account.directory.session.profile.serverId,
              scopeId: scope,
              domain: domain,
              wireId: wireId,
              type: type,
              payload: raw,
              deleted: tombstoneBody['metadata']['recordPolicy'] == null,
            );
            if (CryptoBusinessJson.canonical(actual) !=
                CryptoBusinessJson.canonical(
                  baseline.policy['fieldCommitments'],
                )) {
              throw const FormatException('crypto_record_restore_invalid');
            }
          } finally {
            baseline.key.fillRange(0, baseline.key.length, 0);
          }
        }
        _requireUnpairedRestore(type, raw);
        return _RecordRestoreSource(tag, prior.policy, raw, wireRaw);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    throw const CryptoAuthorityPending('crypto_record_restore_history_pending');
  }

  Future<void> _requireUnpairedTaskRestore(
    String scope,
    String canonicalId,
  ) async {
    final head = await access.currentHead(scope);
    // Finance links are hidden from content-only readers. Until a compatible
    // proof of their absence exists, never publish a task restore in a scope
    // with finance keys, even when this device currently sees no cost.
    if ((head.body['keyIds'] as Map)['finance'] != null) {
      throw const CryptoAuthorityPending(
        'crypto_record_restore_paired_pending',
      );
    }
  }

  void _requireUnpairedRestore(String type, Map<String, dynamic> raw) {
    if (type == 'task' && raw['cost'] != null ||
        const {
              'financeEntry',
              'financeTransfer',
              'personalFinanceEntry',
            }.contains(type) &&
            raw['taskId'] != null) {
      throw const CryptoAuthorityPending(
        'crypto_record_restore_paired_pending',
      );
    }
  }

  Future<Map<String, dynamic>> prepareExplicitRestore({
    required String scope,
    required String domain,
    required String type,
    required String canonicalId,
    required int expectedRevision,
  }) async {
    if (!await _supportsRecordRestores() ||
        !await recordPolicies.active(scope)) {
      throw const CryptoAuthorityPending(
        'crypto_record_restore_upgrade_pending',
      );
    }
    final before = await _row(scope, domain, canonicalId, type: type);
    if (before == null ||
        jsonDecode(before['projection'] as String)['revision'] !=
            expectedRevision) {
      throw const CryptoAuthorityPending('crypto_record_restore_predecessor');
    }
    if (type == 'table')
      throw const CryptoAuthorityPending('crypto_record_restore_table_pending');
    final source = await _recordRestoreSource(
      scope: scope,
      domain: domain,
      type: type,
      canonicalId: canonicalId,
      before: before,
    );
    if (type == 'idea' &&
        (source.raw['elements'] as List? ?? const []).any(
          (e) => e is Map && e['asset'] != null,
        )) {
      throw const CryptoAuthorityPending(
        'crypto_record_restore_large_blob_pending',
      );
    }
    final head = await access.currentHead(scope, online: true);
    final member = head.member(account.directory.accountId);
    if (domain == 'finance' && member['financeRole'] != 'write' ||
        source.policy['createdByAccountId'] != account.directory.accountId &&
            !await access.isRecordOwner(
              scope,
              account.directory.accountId,
              head: head,
            )) {
      throw const CollaborationApiException('record_restore_forbidden');
    }
    if (type == 'task') {
      await _requireUnpairedTaskRestore(scope, canonicalId);
    }
    return {
      'version': 1,
      'scopeId': scope,
      'domain': domain,
      'type': type,
      'recordId': canonicalId,
      'expectedRevision': expectedRevision,
      'createdByAccountId': source.policy['createdByAccountId'],
      'recordRestore': source.tag,
    };
  }
}
