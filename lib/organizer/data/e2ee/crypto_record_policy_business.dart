part of 'crypto_business_router.dart';

class _PreparedRecordPolicy {
  const _PreparedRecordPolicy(this.raw, this.policy);
  final Map<String, dynamic>? raw, policy;
  bool get active => policy != null;
}

extension CryptoBusinessRecordPolicies on CryptoBusinessSession {
  Future<void> _requirePolicyAuthority(
    Map<String, dynamic> record,
    VerifiedScopeHead head,
    Map<String, dynamic>? previousPolicy,
    Iterable<String> previousAssignees,
  ) async {
    final member = head.member(record['accountId']);
    try {
      CryptoRecordPolicy.requireAuthority(
        record: record,
        role: member['role'],
        financeRole: member['financeRole'],
        previousPolicy: previousPolicy,
        previousAssignees: previousAssignees,
      );
    } on FormatException catch (error) {
      if (!const {
        'crypto_record_policy_author_forbidden',
        'crypto_record_policy_creation',
      }.contains(error.message))
        rethrow;
      if (!await access.isRecordOwner(
        record['scopeId'],
        record['accountId'],
        head: head,
        requireParentEvidence:
            record['accountId'] != account.directory.accountId,
      ))
        rethrow;
      CryptoRecordPolicy.requireAuthority(
        record: record,
        role: 'owner',
        financeRole: member['financeRole'],
        previousPolicy: previousPolicy,
        previousAssignees: previousAssignees,
      );
    }
  }

  Future<({Map<String, dynamic> policy, Map<String, dynamic>? raw})?>
  _policyPredecessor({
    required String scope,
    required String domain,
    required String type,
    required String canonicalId,
    required Map<String, Object?> before,
  }) async {
    var raw = before['raw_payload'] == null
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(before['raw_payload'] as String) as Map,
          );
    final wire = address(scope, domain, type, canonicalId).wireId;
    final policy = await _previousSchedule(
      scope,
      domain,
      wire,
      before['crypto_revision'] as int,
      stateKey: 'recordPolicy',
    );
    if (policy != null) {
      CryptoRecordPolicy.validate(policy);
      return (policy: policy, raw: raw);
    }
    final baseline = await recordPolicies.record(
      scopeId: scope,
      domain: domain,
      id: wire,
      recordProofHash: before['record_proof_hash'] as String,
    );
    if (baseline == null) return null;
    try {
      final attached = CryptoRecordPolicy.attachSecret(
        raw ?? const {},
        baseline.key,
      );
      final actual = await CryptoRecordPolicy.commitments(
        serverId: account.directory.session.profile.serverId,
        scopeId: scope,
        domain: domain,
        wireId: wire,
        type: type,
        payload: attached,
        deleted: before['deleted'] == 1,
      );
      if (CryptoBusinessJson.canonical(actual) !=
          CryptoBusinessJson.canonical(baseline.policy['fieldCommitments'])) {
        throw const FormatException('crypto_record_policy_baseline_payload');
      }
      final canonical = before['projection'] == null
          ? null
          : jsonDecode(before['projection'] as String) as Map;
      if (canonical?['creatorProvenance'] != null &&
          canonical?['createdByAccountId'] !=
              baseline.policy['createdByAccountId']) {
        throw const FormatException('crypto_record_author_substitution');
      }
      if (raw != null) raw = attached;
      return (policy: baseline.policy, raw: raw);
    } finally {
      baseline.key.fillRange(0, baseline.key.length, 0);
    }
  }

  Future<_PreparedRecordPolicy> prepareRecordPolicy({
    required String scope,
    required String domain,
    required String type,
    required String canonicalId,
    required int expectedRevision,
    required Map<String, dynamic>? raw,
    Map<String, Object?>? before,
    Map<String, dynamic>? restoreTag,
  }) async {
    if (!CryptoRecordPolicy.businessTypes.contains(type) ||
        !await recordPolicies.active(scope))
      return _PreparedRecordPolicy(raw, null);
    final head = await access.currentHead(scope);
    Map<String, dynamic>? previousPolicy, previousRaw;
    String? creator;
    String operation;
    Map<String, dynamic>? prepared = raw == null
        ? null
        : Map<String, dynamic>.from(raw);
    if (expectedRevision == 0) {
      creator = account.directory.accountId;
      operation = 'create';
      if (prepared == null || before != null)
        throw const FormatException('crypto_record_policy_creation');
      final secret = account.directory.reducer.crypto.sodium.randombytes.buf(
        32,
      );
      try {
        prepared = CryptoRecordPolicy.attachSecret(prepared, secret);
      } finally {
        secret.fillRange(0, secret.length, 0);
      }
    } else {
      if (before == null || before['crypto_revision'] != expectedRevision)
        throw const CryptoAuthorityPending(
          'crypto_record_policy_predecessor_pending',
        );
      final prior = await _policyPredecessor(
        scope: scope,
        domain: domain,
        type: type,
        canonicalId: canonicalId,
        before: before,
      );
      if (prior == null)
        throw const CryptoAuthorityPending(
          'crypto_record_policy_baseline_pending',
        );
      previousPolicy = prior.policy;
      previousRaw = prior.raw;
      if (before['deleted'] == 1 && prepared != null) {
        if (restoreTag == null || !await _supportsRecordRestores()) {
          throw const CryptoAuthorityPending(
            'crypto_record_restore_intent_required',
          );
        }
        if (type == 'table')
          throw const CryptoAuthorityPending(
            'crypto_record_restore_table_pending',
          );
        final source = await _recordRestoreSource(
          scope: scope,
          domain: domain,
          type: type,
          canonicalId: canonicalId,
          before: before,
          expectedTag: restoreTag,
        );
        previousRaw = source.raw;
        _requireUnpairedRestore(type, prepared);
        if (type == 'task')
          await _requireUnpairedTaskRestore(scope, canonicalId);
      } else if (restoreTag != null) {
        throw const FormatException('crypto_record_restore_invalid');
      }
      creator = previousPolicy['createdByAccountId'] as String?;
      operation = prepared == null
          ? 'delete'
          : restoreTag != null
          ? 'restore'
          : 'edit';
      if (prepared != null) {
        if (previousRaw == null)
          throw const FormatException(
            'crypto_record_policy_deleted_predecessor',
          );
        final key = CryptoRecordPolicy.secret(previousRaw);
        try {
          prepared = CryptoRecordPolicy.attachSecret(prepared, key);
        } finally {
          key.fillRange(0, key.length, 0);
        }
      }
    }
    var policy = prepared == null
        ? <String, dynamic>{...previousPolicy!, 'operation': 'delete'}
        : await CryptoRecordPolicy.prepare(
            serverId: account.directory.session.profile.serverId,
            scopeId: scope,
            domain: domain,
            wireId: address(scope, domain, type, canonicalId).wireId,
            type: type,
            creator: creator,
            operation: operation,
            payload: prepared,
          );
    if (restoreTag == null &&
        type == 'shoppingItem' &&
        prepared != null &&
        previousPolicy != null &&
        const ['content', 'assignment'].every(
          (group) =>
              policy['fieldCommitments'][group] ==
              previousPolicy!['fieldCommitments'][group],
        )) {
      policy = {...policy, 'operation': 'shoppingCheck'};
    }
    final record = <String, dynamic>{
      'serverId': account.directory.session.profile.serverId,
      'scopeId': scope,
      'domain': domain,
      'id': address(scope, domain, type, canonicalId).wireId,
      'type': type,
      'accountId': account.directory.accountId,
      'expectedRevision': expectedRevision,
      'deleted': prepared == null,
      'previousRecordHash': before?['record_proof_hash'] ?? '0' * 64,
      'metadata': {
        'recordPolicy': policy,
        if (restoreTag != null) 'recordRestore': restoreTag,
      },
    };
    try {
      await _requirePolicyAuthority(
        record,
        head,
        previousPolicy,
        (previousRaw?['assigneeAccountIds'] as List? ?? const [])
            .cast<String>(),
      );
    } on FormatException {
      final assignment =
          type == 'task' &&
          previousPolicy != null &&
          previousPolicy['fieldCommitments']['assignment'] !=
              policy['fieldCommitments']['assignment'];
      throw CollaborationApiException(
        prepared == null
            ? 'record_delete_forbidden'
            : assignment
            ? 'record_assignment_forbidden'
            : 'record_edit_forbidden',
      );
    }
    await CryptoRecordPolicy.verifyPayload(
      record: record,
      payload: prepared,
      previousPayload: previousRaw,
      previousPolicy: previousPolicy,
    );
    return _PreparedRecordPolicy(prepared, policy);
  }

  Future<bool> supportsRecordPolicyBlobTargets() =>
      _recordPolicyBlobSupport ??= () async {
        final directory = account.directory;
        final caps = await CryptoCapabilityDiscovery.read(
          transport: directory.transport,
          session: directory.session,
        );
        if (!directory.isCurrent())
          throw const CryptoAuthorityPending('crypto_stale_identity');
        if (caps['serverId'] != directory.session.profile.serverId)
          throw const FormatException('crypto_record_policy_blob_server');
        return caps['recordPolicyBlobTargets'] == true &&
            await recordPolicies.supported();
      }();

  Future<void> authorizeBlobPolicyTarget(
    String scope,
    Map<String, dynamic> target,
  ) async {
    CryptoRecordBlobTarget.validate(target);
    if (!await supportsRecordPolicyBlobTargets() ||
        !await recordPolicies.active(scope)) {
      throw const CryptoAuthorityPending(
        'crypto_record_policy_blob_target_upgrade_pending',
      );
    }
    final before = await _wireRow(scope, 'content', target['wireId']);
    if (before == null ||
        before['deleted'] == 1 ||
        before['type'] != target['type'] ||
        before['record_proof_hash'] != target['currentRecordProofHash']) {
      throw const CryptoAuthorityPending(
        'crypto_record_policy_blob_target_changed',
      );
    }
    final canonical = jsonDecode(before['projection'] as String) as Map;
    final prior = await _policyPredecessor(
      scope: scope,
      domain: 'content',
      type: target['type'],
      canonicalId: canonical['id'],
      before: before,
    );
    if (prior == null)
      throw const CryptoAuthorityPending(
        'crypto_record_policy_baseline_pending',
      );
    final head = await access.currentHead(scope, online: true);
    await _requirePolicyAuthority(
      {
        'serverId': account.directory.session.profile.serverId,
        'scopeId': scope,
        'domain': 'content',
        'id': target['wireId'],
        'type': target['type'],
        'expectedRevision': before['crypto_revision'],
        'accountId': account.directory.accountId,
        'deleted': false,
        'metadata': {
          'recordPolicy': {...prior.policy, 'operation': 'edit'},
        },
      },
      head,
      prior.policy,
      (prior.raw?['assigneeAccountIds'] as List? ?? const []).cast<String>(),
    );
  }

  Future<bool> authorizeTablePolicyWrite(String scope, String wireId) async {
    if (!await recordPolicies.active(scope)) return false;
    final before = await _wireRow(scope, 'content', wireId);
    if (before == null || before['type'] != 'table' || before['deleted'] == 1)
      throw const CryptoAuthorityPending('crypto_record_policy_table_pending');
    final canonical = jsonDecode(before['projection'] as String) as Map;
    final prior = await _policyPredecessor(
      scope: scope,
      domain: 'content',
      type: 'table',
      canonicalId: canonical['id'],
      before: before,
    );
    if (prior == null)
      throw const CryptoAuthorityPending(
        'crypto_record_policy_baseline_pending',
      );
    final head = await access.currentHead(scope, online: true);
    final actor = account.directory.accountId;
    if (prior.policy['createdByAccountId'] != actor &&
        !await access.isRecordOwner(scope, actor, head: head)) {
      throw const CryptoAuthorityPending('record_edit_forbidden');
    }
    return true;
  }

  Future<void> verifyRecordPolicyProjection(
    CryptoProjectionRecord value,
    Map<String, dynamic>? raw,
    Map<String, Object?>? previous,
    List<CryptoProjectionRecord> batch,
  ) async {
    final r = value.record;
    final companion = (r['metadata'] as Map)['recordPolicyCompanion'];
    if (companion is Map) {
      final sources = batch.where(
        (source) =>
            source.record['id'] == companion['taskId'] &&
            source.record['type'] == 'task' &&
            source.record['contentContract'] == 7 &&
            source.record['expectedRevision'] + 1 ==
                companion['taskRevision'] &&
            source.record['metadata']['recordPolicy'] is Map &&
            const [
              'scopeId',
              'batchId',
              'operationId',
              'accountId',
              'deviceId',
            ].every((key) => source.record[key] == r[key]),
      );
      if (sources.length != 1 || raw == null)
        throw const FormatException('crypto_record_policy_companion_source');
      final source = sources.single;
      final sourceHash = await codec.digest(
        Map<String, dynamic>.from(
          source.wire['authorization']['recordProof'] as Map,
        ),
      );
      final sourceBatch = source.wire['authorization']['batchCommitment'];
      if (sourceHash != companion['taskProofHash'] ||
          CryptoJson.encode(sourceBatch).toString() !=
              CryptoJson.encode(
                value.wire['authorization']['batchCommitment'],
              ).toString() ||
          raw['taskId'] !=
              cryptoRecordAddressFromMetadata(source.record).canonicalId ||
          raw['targetOperationId'] != source.record['operationId'] ||
          raw['targetCryptoRevision'] != companion['taskRevision']) {
        throw const FormatException('crypto_record_policy_companion_binding');
      }
      return;
    }
    final policy = (r['metadata'] as Map)['recordPolicy'];
    if (policy == null) return; // Original signed history retains its contract.
    final head = await access.headAt(r['scopeId'], r['membershipHeadHash']);
    Map<String, dynamic>? previousPolicy, previousRaw;
    if (r['expectedRevision'] > 0) {
      if (previous == null) throw const CryptoProjectionPending();
      final prior = await _policyPredecessor(
        scope: r['scopeId'],
        domain: r['domain'],
        type: r['type'],
        canonicalId: cryptoRecordAddressFromMetadata(r).canonicalId,
        before: previous,
      );
      if (prior == null) throw const CryptoProjectionPending();
      previousPolicy = prior.policy;
      previousRaw = prior.raw;
      final restoreTag = (r['metadata'] as Map)['recordRestore'];
      if (previous['deleted'] == 1 && raw != null) {
        if (restoreTag is! Map)
          throw const FormatException('crypto_record_restore_intent_required');
        final source = await _recordRestoreSource(
          scope: r['scopeId'],
          domain: r['domain'],
          type: r['type'],
          canonicalId: cryptoRecordAddressFromMetadata(r).canonicalId,
          before: previous,
          expectedTag: Map<String, dynamic>.from(restoreTag),
        );
        previousRaw = source.raw;
        _requireUnpairedRestore(r['type'], raw);
        if (r['type'] == 'task')
          await _requireUnpairedTaskRestore(
            r['scopeId'],
            cryptoRecordAddressFromMetadata(r).canonicalId,
          );
        if (r['type'] == 'table')
          throw const CryptoAuthorityPending(
            'crypto_record_restore_table_pending',
          );
      } else if (restoreTag != null) {
        throw const FormatException('crypto_record_restore_predecessor');
      }
    }
    await _requirePolicyAuthority(
      r,
      head,
      previousPolicy,
      (previousRaw?['assigneeAccountIds'] as List? ?? const []).cast<String>(),
    );
    await CryptoRecordPolicy.verifyPayload(
      record: r,
      payload: raw,
      previousPayload: previousRaw,
      previousPolicy: previousPolicy,
    );
  }
}
