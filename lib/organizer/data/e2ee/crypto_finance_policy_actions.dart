import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart' show cryptoSha256, cryptoZeroHash;
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_manager.dart';

String _canonical(Object? value) => utf8.decode(CryptoJson.encode(value));

/// A complete policy stream. Its hash is checked against a signed scope anchor,
/// never against an unsigned receipt or the stream's own claimed hash.
class CryptoFinancePolicySnapshot {
  CryptoFinancePolicySnapshot({
    required this.enabled,
    required this.revision,
    required this.requiredContractVersion,
    required List<Map<String, dynamic>> grants,
  }) : grants = List.unmodifiable(
         grants.map(Map<String, dynamic>.unmodifiable),
       ) {
    if (revision < 0 ||
        revision > 9007199254740991 ||
        requiredContractVersion < 1 ||
        requiredContractVersion > 3) {
      throw const FormatException('crypto_finance_policy_header');
    }
    String? previous;
    for (final item in this.grants) {
      if (item.length != 2 ||
          !isCryptoCanonicalUuid(item['accountId']) ||
          !['none', 'read', 'write'].contains(item['grant']) ||
          previous != null &&
              (item['accountId'] as String).compareTo(previous) <= 0) {
        throw const FormatException('crypto_finance_policy_grants');
      }
      previous = item['accountId'];
    }
  }
  final bool enabled;
  final int revision, requiredContractVersion;
  final List<Map<String, dynamic>> grants;
  Map<String, dynamic> get header => {
    'enabled': enabled,
    'revision': revision,
    'requiredContractVersion': requiredContractVersion,
  };
  Future<String> hash() => cryptoSha256(
    utf8.encode(
      'JivieFinancePolicy/v2\n${_canonical(header)}\n'
      '${grants.map((g) => '${_canonical(g)}\n').join()}'
      '${_canonical({'grantCount': grants.length})}',
    ),
  );
  CryptoFinancePolicySnapshot apply(Map<String, dynamic> action, String actor) {
    final next = {
      for (final g in grants) g['accountId'] as String: g['grant'] as String,
    };
    var active = enabled;
    if (action['kind'] == 'enable' &&
        action.length == 2 &&
        action['enabled'] is bool) {
      active = action['enabled'];
      if (active) next[actor] = 'write';
    } else if (action['kind'] == 'grant' &&
        action.length == 3 &&
        isCryptoCanonicalUuid(action['accountId']) &&
        ['none', 'read', 'write'].contains(action['grant'])) {
      next[action['accountId']] = action['grant'];
    } else {
      throw const FormatException('crypto_finance_policy_action');
    }
    final ids = next.keys.toList()..sort();
    return CryptoFinancePolicySnapshot(
      enabled: active,
      revision: revision + 1,
      requiredContractVersion: requiredContractVersion,
      grants: [
        for (final id in ids) {'accountId': id, 'grant': next[id]},
      ],
    );
  }
}

class CryptoFinancePolicyActions {
  CryptoFinancePolicyActions(this.context);
  final CryptoBusinessSession context;
  static final _operation = RegExp(
    r'^finance[24]?\.(policy|grants|enable|grant)$',
  );
  bool supports(String operation) => _operation.hasMatch(operation);

  Map<String, dynamic> _decode(Object value) => Map<String, dynamic>.from(
    CryptoJson.decode(Uint8List.fromList((value as List).cast<int>())) as Map,
  );

  /// All heads in this walk have already passed Session's exact predecessor,
  /// identity, activation and closure verification. An older intent remains an
  /// anchor after unrelated rotations; it is not current issuance authority.
  Future<Map<String, dynamic>> _anchor(String scope) async {
    var head = await context.access.currentHead(scope, online: true);
    Map<String, dynamic>? newest;
    bool? enabled;
    while (true) {
      final policy = head.body['financePolicyIntentProof'];
      final access = head.body['accessIntentProof'];
      if (policy is Map) {
        final command =
            CryptoJson.decode(cryptoBase64(policy['commandBase64'])) as Map;
        final p = command['payload'] as Map;
        newest ??= {
          'revision': p['resultingFinancePolicyRevision'],
          'policyHash': p['resultingPolicyHash'],
        };
        if ((p['action'] as Map)['kind'] == 'enable') {
          enabled ??= p['action']['enabled'];
        }
      }
      if (access is Map) {
        final consent =
            CryptoJson.decode(cryptoBase64(access['commandBase64'])) as Map;
        final result = consent['resultingFinancePolicy'];
        // Historical previews without this commitment cannot authenticate a
        // policy changed by structural effects. Do not reuse an older anchor.
        if (newest == null && result is! Map) {
          throw const CryptoAuthorityPending(
            'crypto_finance_policy_structural_anchor_pending',
          );
        }
        if (result is Map) newest ??= Map<String, dynamic>.from(result);
      }
      if (head.body['previousHeadHash'] == cryptoZeroHash) break;
      head = await context.access.headAt(scope, head.body['previousHeadHash']);
    }
    final baseline = await context.account.directory.call(
      'crypto2.scope.lifecycle.baseline',
      {'scopeId': scope},
    );
    if (await context.access.verifyInitialLifecycle(
          scope,
          baseline,
          scopeHeadHash: head.headHash,
        ) !=
        head.body['initialLifecycleHash']) {
      throw const FormatException('crypto_finance_policy_origin');
    }
    final origin =
        CryptoJson.decode(
              cryptoBase64(baseline['originAuthorization']['commandBase64']),
            )
            as Map;
    final relocated =
        origin['operation'] == 'crypto2.scope.origin' &&
        origin.containsKey('projectRelocation');
    if (relocated || origin['operation'] != 'crypto2.scope.origin') {
      final committed = relocated
          ? await context.access.verifiedRelocatedScopeBaseline(scope)
          : await context.access.verifiedMigrationScopeBaseline(scope);
      final policy = committed['financePolicy'];
      if (policy is! Map ||
          policy.length != 5 ||
          !policy.keys.toSet().containsAll({
            'enabled',
            'revision',
            'requiredContractVersion',
            'policyHash',
            'grantCount',
          }) ||
          policy['enabled'] is! bool ||
          policy['revision'] is! int ||
          policy['revision'] < 0 ||
          policy['requiredContractVersion'] is! int ||
          policy['requiredContractVersion'] < 1 ||
          policy['grantCount'] is! int ||
          policy['grantCount'] < 0 ||
          policy['grantCount'] > 10000 ||
          policy['policyHash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(policy['policyHash'])) {
        throw const FormatException('crypto_finance_policy_migration_baseline');
      }
      final result = <String, dynamic>{
        ...Map<String, dynamic>.from(policy),
        ...?newest,
        'enabled': enabled ?? policy['enabled'],
      };
      if (newest != null) result.remove('grantCount');
      return result;
    }
    final initial = CryptoFinancePolicySnapshot(
      enabled: true,
      revision: 1,
      requiredContractVersion: 3,
      grants: [
        {'accountId': origin['accountId'], 'grant': 'write'},
      ],
    );
    return {
      ...?newest,
      if (newest == null) 'revision': 1,
      if (newest == null) 'policyHash': await initial.hash(),
      'enabled': enabled ?? true,
      'requiredContractVersion': 3,
    };
  }

  Future<CryptoFinancePolicySnapshot> readVerified(String scope) async {
    final anchor = await _anchor(scope);
    final grants = <Map<String, dynamic>>[];
    String? after;
    Map<String, dynamic>? header;
    while (true) {
      final page = await context.account.directory.call(
        'crypto2.scope.financePolicy.current',
        {
          'scopeId': scope,
          'limit': 50,
          if (after != null) 'afterAccountId': after,
        },
      );
      final nextHeader = {
        for (final f in [
          'enabled',
          'revision',
          'requiredContractVersion',
          'policyHash',
          'grantCount',
        ])
          f: page[f],
      };
      if (page['grants'] is! List ||
          (page['grants'] as List).length > 50 ||
          page['hasMore'] is! bool ||
          header != null && _canonical(header) != _canonical(nextHeader)) {
        throw const FormatException('crypto_finance_policy_page');
      }
      header ??= nextHeader;
      for (final raw in page['grants'] as List) {
        if (raw is! Map ||
            !isCryptoCanonicalUuid(raw['accountId']) ||
            after != null &&
                (raw['accountId'] as String).compareTo(after) <= 0) {
          throw const FormatException('crypto_finance_policy_page_order');
        }
        grants.add(Map<String, dynamic>.from(raw));
        after = raw['accountId'];
      }
      if (grants.length > 10000) {
        throw const FormatException('crypto_finance_policy_capacity');
      }
      if (page['hasMore'] == false) break;
      if ((page['grants'] as List).isEmpty || page['nextAccountId'] != after) {
        throw const FormatException('crypto_finance_policy_cursor');
      }
    }
    if (header['enabled'] is! bool ||
        header['revision'] is! int ||
        header['requiredContractVersion'] is! int) {
      throw const FormatException('crypto_finance_policy_header');
    }
    final state = CryptoFinancePolicySnapshot(
      enabled: header['enabled'],
      revision: header['revision'],
      requiredContractVersion: header['requiredContractVersion'],
      grants: grants,
    );
    final hash = await state.hash();
    if (grants.length != header['grantCount'] ||
        anchor['grantCount'] != null &&
            anchor['revision'] == state.revision &&
            anchor['policyHash'] == hash &&
            grants.length != anchor['grantCount'] ||
        hash != header['policyHash'] ||
        hash != anchor['policyHash'] ||
        state.revision != anchor['revision'] ||
        state.enabled != anchor['enabled']) {
      throw const CryptoAuthorityPending(
        'crypto_finance_policy_anchor_mismatch',
      );
    }
    if (!context.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
    return state;
  }

  Future<Map<String, dynamic>> policy(String scope) async {
    final anchor = await _anchor(scope);
    final head = await context.access.currentHead(scope, online: true);
    final descriptor = await context.access.verifiedScopeDescriptor(scope);
    if (!context.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
    return {
      'enabled': anchor['enabled'],
      'grant': head.member(context.account.directory.accountId)['financeRole'],
      'revision': (anchor['revision'] as int) + head.accessRevision,
      'requiredContractVersion': anchor['requiredContractVersion'],
      'linkedPaymentsRequired': true,
      'managedByOrganizationPolicy': descriptor['accessPolicyVersion'] >= 2,
      'readAccessFromMembership': descriptor['accessPolicyVersion'] >= 2,
      'organizationFinanceComplete': false,
      'organizationFinanceScopeIds': <String>[],
      'organizationFinanceSequences': <String, int>{},
    };
  }

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    if (!supports(operation) || !isCryptoCanonicalUuid(params['scopeId'])) {
      throw const FormatException('crypto_finance_policy_request');
    }
    final scope = params['scopeId'] as String,
        actionName = operation.split('.').last;
    if (actionName == 'policy') {
      // Only external policy responses carry aggregate coverage. Internal
      // revision reads must not recursively pull/project finance records.
      final head = await context.access.currentHead(scope, online: true);
      final reply = await policy(scope);
      if (context.financePolicyOnly ||
          reply['enabled'] != true ||
          !const ['read', 'write'].contains(reply['grant'])) {
        return reply;
      }
      return {
        ...reply,
        ...await context.organizationFinanceCoverage(
          scope,
          refreshRootFinance: true,
          expectedHeadHash: head.headHash,
        ),
      };
    }
    final head = await context.access.currentHead(scope, online: true);
    if (head.member(context.account.directory.accountId)['manageKeys'] !=
        true) {
      throw const CryptoAuthorityPending(
        'crypto_finance_policy_manager_required',
      );
    }
    if (actionName == 'grants') {
      return {'grants': (await readVerified(scope)).grants};
    }
    return _change(scope, actionName, params);
  }

  Future<Map<String, dynamic>> _change(
    String scope,
    String name,
    Map<String, Object?> params,
  ) async {
    final request = params['requestId'];
    if (!isCryptoCanonicalUuid(request)) {
      throw const FormatException('crypto_finance_policy_request');
    }
    final action = <String, dynamic>{
      'kind': name,
      if (name == 'enable') 'enabled': params['enabled'],
      if (name == 'grant') ...{
        'accountId': params['accountId'],
        'grant': params['grant'],
      },
    };
    final key = 'financePolicy:$request', db = context.database;
    final rows = await db.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [context.partition, scope, key],
    );
    late Map<String, dynamic> saved;
    if (rows.isEmpty) {
      final before = await readVerified(scope);
      final next = before.apply(action, context.account.directory.accountId);
      final descriptor = await context.access.verifiedScopeDescriptor(scope);
      if (descriptor['kind'] == 'personal') {
        throw const FormatException('personal_not_shareable');
      }
      if (name == 'enable' &&
          action['enabled'] == false &&
          descriptor['accessPolicyVersion'] >= 2) {
        throw const FormatException('managed_by_organization_policy');
      }
      final manager = ScopeCryptoManager(context.access),
          review = await manager.reviewRotation(scope);
      if (review.historyBasis == 'reviewedRecoveryBaseline') {
        throw const CryptoAuthorityPending(
          'scope_review_confirmation_required',
        );
      }
      final head = await context.access.currentHead(scope, online: true),
          own = await context.account.directory.requireFresh();
      if (head.headHash != review.sourceHeadHash) {
        throw const CryptoAuthorityPending('crypto_scope_head_changed');
      }
      saved = {
        'action': action,
        'review': review.value,
        'payload': {
          'scopeId': scope,
          'membershipHeadHash': head.headHash,
          'expectedAccessRevision': head.accessRevision,
          'authorDirectoryHeadHash': own.headHash,
          'expectedFinancePolicyRevision': before.revision,
          'previousPolicyHash': await before.hash(),
          'resultingFinancePolicyRevision': next.revision,
          'resultingPolicyHash': await next.hash(),
          'action': action,
        },
      };
      await db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          context.partition,
          scope,
          key,
          'financePolicyWorkflow',
          CryptoJson.encode(saved),
        ],
      );
    } else {
      saved = _decode(rows.single['payload']!);
      if (_canonical(saved['action']) != _canonical(action)) {
        throw const FormatException('crypto_finance_policy_immutable_action');
      }
    }
    final original = await context.queue.enqueueCommand(
      actionKey: key,
      requestId: request as String,
      operation: 'crypto2.scope.financePolicy.propose',
      payload: Map<String, dynamic>.from(saved['payload'] as Map),
    );
    await context.queue.resumeUnresolved(requestIds: {original});
    await context.queue.commandResult(original);
    final journal = (await db.rows(
      'SELECT signed_body FROM crypto_outbox WHERE partition=? AND request_id=?',
      [context.partition, original],
    )).single;
    final proof = Map<String, dynamic>.from(
      jsonDecode(journal['signed_body'] as String) as Map,
    );
    final review = ScopeRotationReview(
      Map<String, dynamic>.from(saved['review'] as Map),
    );
    final published = await db.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationPublished'",
      [context.partition, scope, '${review.id}:published'],
    );
    if (published.isNotEmpty) {
      final value = _decode(published.single['payload']!);
      try {
        final applied = await context.access.headAt(
          scope,
          value['headHash'],
          online: true,
        );
        if (_canonical(applied.body) != _canonical(value['body']) ||
            _canonical(applied.body['financePolicyIntentProof']) !=
                _canonical(proof)) {
          throw const FormatException(
            'crypto_finance_policy_activation_substitution',
          );
        }
        return await policy(scope);
      } on CryptoAuthorityPending catch (error) {
        if (error.reason != 'scope_history_pending') rethrow;
      }
    }
    final source = await context.access.headAt(
      scope,
      review.sourceHeadHash,
      online: true,
    );
    final descriptor = await context.access.verifiedScopeDescriptor(scope);
    final members = [
      for (final member in source.members)
        <String, dynamic>{
          ...member,
          if (descriptor['accessPolicyVersion'] != 3 &&
              name == 'enable' &&
              action['enabled'] == false)
            'financeRole': 'none',
          if (descriptor['accessPolicyVersion'] != 3 &&
              name == 'enable' &&
              action['enabled'] == true &&
              member['accountId'] == context.account.directory.accountId)
            'financeRole': 'write',
          if (descriptor['accessPolicyVersion'] != 3 &&
              name == 'grant' &&
              member['accountId'] == action['accountId'])
            'financeRole': action['grant'],
        },
    ];
    await ScopeCryptoManager(context.access).confirmRotation(
      review,
      acceptedCandidateHistory: false,
      members: members,
      financePolicyIntentProof: proof,
    );
    context.access.invalidateAuthorityOperation();
    return policy(scope);
  }
}
