part of 'crypto_business_router.dart';

// The full catalog and already-visible target path deliberately share these
// authenticated projection rules. Cached rows select work, never authority.
extension CryptoVisibleTaskScope on CryptoBusinessSession {
  Future<({Map<String, dynamic>? value, bool pending})> _projectScopeForRead(
    Map<String, dynamic> scope,
    Map<String, Map<String, dynamic>> descriptors, {
    bool allowBootstrap = true,
  }) async {
    final cached = await db.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [p, scope['id']],
    );
    final local = cached.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(cached.single['data'] as String) as Map,
          );
    var metadata = await _row(
      scope['id'] as String,
      'content',
      await _reservedId(scope['id'] as String, 'scopeMetadata'),
      type: 'scopeMetadata',
    );
    if (metadata == null && !allowBootstrap) {
      return (value: null, pending: false);
    }
    if (metadata == null) {
      try {
        await access.currentHead(scope['id'] as String, online: true);
      } on CollaborationException catch (error) {
        if (error.code != 'crypto_scope_head_missing') rethrow;
        // Catalog absence of a head is discovery, not authority to synthesize
        // a policy/name or revoke retained local records. P7 handles the
        // explicit legacy migration; an unrelated new origin can proceed.
        return (
          value: local.isNotEmpty ? {...local, 'blocked': true} : null,
          pending: true,
        );
      }
      await pullVerified(scope['id'] as String, 'content');
      metadata = await _row(
        scope['id'] as String,
        'content',
        await _reservedId(scope['id'] as String, 'scopeMetadata'),
        type: 'scopeMetadata',
      );
    }
    final source = metadata == null
        ? local
        : jsonDecode(metadata['raw_payload'] as String) as Map;
    final lifecycle = await CryptoLifecycleEvidence(
      access,
    ).current(scope['id'] as String);
    final descriptor = await _verifiedScopeDescriptor(scope['id'] as String);
    descriptors[scope['id'] as String] = descriptor;
    final head = await access.currentHead(scope['id'] as String);
    final member = head.member(account.directory.accountId);
    final roots = await cryptoProjectRootCandidates(
      database: db,
      partition: p,
      serverId: account.directory.session.profile.serverId,
      scopeId: scope['id'] as String,
    );
    final rootNeedsInventory = roots.any(
      (row) =>
          row['deleted'] == 0 &&
          (row['id'] != scope['id'] ||
              row['legacy_revision'] != 0 ||
              row['revision_namespace'] == 'legacy'),
    );
    final rootId = cryptoProjectRootProjection(
      scopeId: scope['id'] as String,
      descriptor: descriptor,
      projects: roots,
      completeVerifiedInventory:
          rootNeedsInventory &&
          await _hasReusableCheckpoint(
            scope['id'] as String,
            'content',
            head.headHash,
            head.epoch,
            head.accessRevision,
          ),
    );
    // Catalog titles are never accepted; only already local or authenticated
    // encrypted scope metadata supplies the visible name/address.
    return (
      value: {
        ...local,
        'id': scope['id'],
        'kind': descriptor['kind'],
        'projectRootId': rootId,
        'role': member['role'],
        'accessRevision': head.accessRevision,
        'name': source['name'] ?? 'Jivie',
        'address': source['address'],
        'sequence': local['sequence'] ?? 0,
        'archived':
            lifecycle['ownArchived'] == true ||
            lifecycle['inheritedArchived'] == true,
        'requiredRecordContractVersion': 6,
        'accessPolicyVersion': descriptor['accessPolicyVersion'],
        'metadataRevision': metadata == null ? 0 : _localRevision(metadata),
      },
      pending: false,
    );
  }

  Future<void> _finishScopeForRead(
    Map<String, dynamic> scope,
    List<Map<String, dynamic>> discovered,
    Map<String, Map<String, dynamic>> descriptors, {
    bool forcePolicyCheck = false,
  }) async {
    final descriptor = descriptors[scope['id']];
    if (descriptor == null) return;
    scope.addAll(
      await cryptoScopeParentProjection(
        scopeId: scope['id'] as String,
        descriptor: descriptor,
        cached: scope,
        catalog: discovered,
        verifiedDescriptors: descriptors,
        parentToken: CryptoLifecycleEvidence(access).parentToken,
      ),
    );
    final discovery = discovered
        .where((row) => row['id'] == scope['id'])
        .firstOrNull;
    final wasActive = scope['recordPolicyVersion'] == 1;
    if (wasActive ||
        discovery?['recordPolicyVersion'] == 1 ||
        forcePolicyCheck) {
      final active = await recordPolicies.active(scope['id'] as String);
      if (!active && (wasActive || discovery?['recordPolicyVersion'] == 1)) {
        throw const CryptoAuthorityPending(
          'crypto_record_policy_activation_rollback',
        );
      }
      scope['recordPolicyVersion'] = active ? 1 : 0;
    } else {
      // Discovery only selects which signed evidence to verify. Known
      // inactive scopes incur no per-scope policy status/content request.
      scope['recordPolicyVersion'] = 0;
    }
    scope['verifiedParentOwner'] =
        scope['role'] != 'owner' &&
        await access.isRecordOwner(
          scope['id'] as String,
          account.directory.accountId,
          parentScopeId: scope['parentScopeId'] as String?,
        );
  }

  /// Null asks the existing fenced router to perform its established discovery.
  /// No missing local evidence can revoke or block a retained visible record.
  Future<Map<String, dynamic>?> visibleTaskScope(
    CryptoVisibleTaskMetadataTarget target,
  ) async {
    final cached = await db.rows(
      'SELECT data,blocked FROM scopes WHERE partition=? AND id=?',
      [p, target.scopeId],
    );
    final task = await db.rows(
      "SELECT 1 FROM records WHERE partition=? AND scope_id=? AND id=? AND type='task' AND deleted=0",
      [p, target.scopeId, target.recordId],
    );
    if (cached.length != 1 ||
        cached.single['blocked'] == 1 ||
        task.length != 1) {
      return null;
    }
    final local = Map<String, dynamic>.from(
      jsonDecode(cached.single['data'] as String) as Map,
    );
    final known = SharedScope.fromJson(local);
    if (known.revoked || known.blocked || known.archived || known.deleted) {
      return null;
    }
    await account.directory.requireFresh();
    final descriptors = <String, Map<String, dynamic>>{};
    final projected = await _projectScopeForRead(
      local,
      descriptors,
      allowBootstrap: false,
    );
    final value = projected.value;
    if (value == null || projected.pending) return null;
    final candidates =
        (await db.rows('SELECT data FROM scopes WHERE partition=?', [p]))
            .map(
              (row) => Map<String, dynamic>.from(
                jsonDecode(row['data'] as String) as Map,
              ),
            )
            .toList();
    final descriptor = descriptors[target.scopeId]!;
    final parent = await cryptoScopeParentProjection(
      scopeId: target.scopeId,
      descriptor: descriptor,
      cached: value,
      catalog: candidates,
      verifiedDescriptors: descriptors,
      parentToken: CryptoLifecycleEvidence(access).parentToken,
    );
    final parentId = parent['parentScopeId'] as String?;
    if (descriptor['parentScopeToken'] != null && parentId == null) return null;
    final parentCandidate = candidates
        .where((row) => row['id'] == parentId)
        .firstOrNull;
    if (parentId != null && parentCandidate != null) {
      final visibleParent = SharedScope.fromJson(parentCandidate);
      if (!visibleParent.revoked &&
          !visibleParent.blocked &&
          !visibleParent.archived &&
          !visibleParent.deleted) {
        try {
          await access.currentHead(parentId, online: true);
          descriptors[parentId] = await _verifiedScopeDescriptor(parentId);
        } on CryptoAuthorityPending {
          return null;
        } on CollaborationException catch (error) {
          if (!const {
            'permission_revoked',
            'scope_deleted',
          }.contains(error.code)) {
            rethrow;
          }
          return null;
        }
      }
    }
    await _finishScopeForRead(
      value,
      candidates,
      descriptors,
      forcePolicyCheck: true,
    );
    if (!account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
    return {
      'scopes': [value],
      'pendingCryptoScopeIds': <String>[],
    };
  }
}
