part of 'collaboration_repository.dart';

/// Account choices are a separate sanitized projection. Project-only members
/// never need the parent scope, its members, or its ledger snapshot in storage.
extension CollaborationFinanceAccountChoices on CollaborationRepository {
  Future<SharedScope?> _financeStoredScope(String partition, String id) async {
    final rows = await database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [partition, id],
    );
    return rows.isEmpty
        ? null
        : SharedScope.fromJson(
            CollaborationRepository._map(rows.single['data']),
          );
  }

  Future<void> _clearFinanceAccountChoices(String partition, String scopeId) =>
      database.execute('DELETE FROM local_meta WHERE name=?', [
        'finance_account_choices:$partition:$scopeId',
      ]);

  Future<List<SharedFinanceAccountChoice>> _cachedFinanceAccountChoices(
    String partition,
    String scopeId,
  ) async {
    if (!_organizationFinanceSupported) return const [];
    final scope = await _financeStoredScope(partition, scopeId);
    final policy = await _cachedFinancePolicy(partition, scopeId);
    if (scope == null ||
        scope.revoked ||
        scope.deleted ||
        !scope.canRead ||
        scope.kind != SharedScopeKind.project ||
        !policy.canRead) {
      return const [];
    }
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['finance_account_choices:$partition:$scopeId'],
    );
    if (rows.isEmpty) return const [];
    final value = CollaborationRepository._map(rows.single['value']);
    if (value['accessRevision'] != policy.revision ||
        value['accountScopeId'] != scope.parentSpaceId) {
      return const [];
    }
    return _parseFinanceAccountChoices(value, scope.parentSpaceId);
  }

  List<SharedFinanceAccountChoice> _parseFinanceAccountChoices(
    Map<String, dynamic> value,
    String? parentId,
  ) {
    try {
      if (value['accounts'] is! List ||
          value['accessRevision'] is! int ||
          (value['accessRevision'] as int) < 0 ||
          value['accountSequence'] is! int ||
          (value['accountSequence'] as int) < 0 ||
          value['accountScopeId'] != null &&
              !isSharedUuid(value['accountScopeId'])) {
        throw const FormatException('Invalid choices');
      }
      final choices = (value['accounts'] as List)
          .map(
            (v) => SharedFinanceAccountChoice.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          )
          .toList();
      if (choices.any(
            (a) =>
                a.scopeId != parentId ||
                a.scopeId != value['accountScopeId'] ||
                !isSharedUuid(a.id),
          ) ||
          choices.map((a) => a.id).toSet().length != choices.length) {
        throw const FormatException('Invalid choices');
      }
      return List.unmodifiable(choices);
    } on Object {
      throw const CollaborationException('invalid_response');
    }
  }

  Future<void> refreshFinanceAccountChoices(
    String scopeId, {
    bool refreshPolicy = true,
  }) async {
    if (!_organizationFinanceSupported) {
      throw const CollaborationException('unsupported_version');
    }
    final session = _requireSession(), epoch = _epoch;
    final policy = refreshPolicy
        ? await _fetchFinancePolicy(session, epoch, scopeId)
        : await _cachedFinancePolicy(session.profile.partition, scopeId);
    _checkEpoch(epoch);
    if (!policy.canRead) {
      throw const CollaborationException('finance_forbidden');
    }
    if (!refreshPolicy) {
      await _checkFinanceEntrySelectorPolicy(session, epoch, scopeId);
    }
    try {
      await _fetchFinanceAccountChoices(
        session,
        epoch,
        scopeId,
        deferChangedAccess: !refreshPolicy,
      );
    } on CryptoAuthorityPending catch (error) {
      if (!refreshPolicy && error.reason == 'scope_read_forbidden') {
        // Selector derivation can also fail on the source parent. Recheck only
        // this target's verified policy; never infer its denial from that reason.
        await _checkFinanceEntrySelectorPolicy(session, epoch, scopeId);
      }
      rethrow;
    }
    await refreshLocal(scopeIds: {scopeId});
  }

  /// Selector preparation does not apply a same-authorization access epoch to
  /// an open editor. A verified own authorization change still takes the normal
  /// denial/downgrade path; aggregate coverage never substitutes for authority.
  Future<void> _checkFinanceEntrySelectorPolicy(
    DeviceSession session,
    int epoch,
    String scopeId,
  ) async {
    final partition = session.profile.partition;
    final generation = await _financeAccessGeneration(partition, scopeId);
    _checkEpoch(epoch);
    late final SharedFinancePolicy fresh;
    try {
      Future<Map<String, dynamic>> read() => _callSession(
        session,
        epoch,
        '$_financeNamespace.policy',
        {'scopeId': scopeId},
      );
      final router = cryptoRouter;
      final Map<String, dynamic> reply;
      if (router is CryptoFinancePolicyReadContext) {
        reply =
            (await (router as CryptoFinancePolicyReadContext)
                    .withFinancePolicyOnly(read))
                .value;
      } else {
        reply = await read();
      }
      fresh = SharedFinancePolicy.fromJson(reply);
    } on CollaborationApiException catch (error) {
      if (!const {
        'finance_forbidden',
        'permission_revoked',
      }.contains(error.code)) {
        rethrow;
      }
      fresh = const SharedFinancePolicy();
    }
    final changed = await database.transaction(() async {
      _checkEpoch(epoch);
      if (generation != await _financeAccessGeneration(partition, scopeId)) {
        throw const CryptoAuthorityPending(
          'finance_policy_changed_during_read',
        );
      }
      final cached = await _cachedFinancePolicy(partition, scopeId);
      _checkEpoch(epoch);
      final sameAuthorization =
          cached.enabled == fresh.enabled &&
          cached.grant == fresh.grant &&
          cached.requiredContractVersion == fresh.requiredContractVersion &&
          cached.managedByOrganizationPolicy ==
              fresh.managedByOrganizationPolicy &&
          cached.readAccessFromMembership == fresh.readAccessFromMembership &&
          cached.linkedPaymentsRequired == fresh.linkedPaymentsRequired;
      if (sameAuthorization) {
        if (cached.revision != fresh.revision) {
          throw const CryptoAuthorityPending(
            'finance_policy_changed_during_read',
          );
        }
        return false;
      }
      await _storeFinancePolicy(partition, scopeId, fresh);
      return true;
    });
    _checkEpoch(epoch);
    if (changed) {
      await refreshLocal(scopeIds: {scopeId});
      _checkEpoch(epoch);
      // Never continue preparing after the captured editor guard became stale.
      throw const CryptoAuthorityPending('finance_policy_changed_during_read');
    }
  }

  Future<void> _fetchFinanceAccountChoices(
    DeviceSession session,
    int epoch,
    String scopeId, {
    bool syncLease = false,
    bool deferChangedAccess = false,
  }) async {
    final partition = session.profile.partition;
    final scope = await _financeStoredScope(partition, scopeId);
    if (scope == null ||
        scope.revoked ||
        scope.deleted ||
        !scope.canRead ||
        scope.kind != SharedScopeKind.project) {
      throw const CollaborationException('permission_revoked');
    }
    final generation = await _financeAccessGeneration(partition, scopeId);
    _checkEpoch(epoch);
    late final Map<String, dynamic> reply;
    try {
      reply = await _callSession(session, epoch, 'finance4.accountChoices', {
        'scopeId': scopeId,
      });
    } on CollaborationApiException catch (e) {
      if (e.code == 'finance_forbidden' || e.code == 'permission_revoked') {
        await database.transaction(() async {
          _checkEpoch(epoch);
          if (syncLease) await _validLease(partition);
          _checkEpoch(epoch);
          // Increment the same access fence used by finance policy so an older
          // concurrent response cannot restore the denied selector projection.
          await _storeFinancePolicy(
            partition,
            scopeId,
            const SharedFinancePolicy(),
          );
        });
        await refreshLocal();
      }
      rethrow;
    }
    final choices = _parseFinanceAccountChoices(reply, scope.parentSpaceId);
    if (reply['accountScopeId'] != null &&
        reply['accountScopeId'] != scope.parentSpaceId) {
      throw const CollaborationException('invalid_response');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      if (syncLease) await _validLease(partition);
      _checkEpoch(epoch);
      final currentScope = await _financeStoredScope(partition, scopeId);
      final policy = await _cachedFinancePolicy(partition, scopeId);
      if (generation != await _financeAccessGeneration(partition, scopeId) ||
          currentScope?.revoked != false ||
          currentScope?.deleted != false ||
          currentScope?.parentSpaceId != scope.parentSpaceId ||
          !policy.canRead ||
          reply['accessRevision'] != policy.revision) {
        if (deferChangedAccess) {
          // An open editor retains its captured policy and complete projection.
          // Ordinary synchronization will verify/apply the new access epoch.
          throw const CryptoAuthorityPending(
            'finance_policy_changed_during_read',
          );
        }
        return;
      }
      final key = 'finance_account_choices:$partition:$scopeId';
      final old = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      );
      if (old.isNotEmpty) {
        final previous = CollaborationRepository._map(old.single['value']);
        if (previous['accountScopeId'] == reply['accountScopeId'] &&
            previous['accessRevision'] == reply['accessRevision'] &&
            (previous['accountSequence'] as int? ?? 0) >
                (reply['accountSequence'] as int)) {
          return;
        }
      }
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        [
          key,
          jsonEncode({
            'accounts': [for (final choice in choices) choice.toJson()],
            'accessRevision': reply['accessRevision'],
            'accountScopeId': reply['accountScopeId'],
            'accountSequence': reply['accountSequence'],
          }),
        ],
      );
    });
  }
}
