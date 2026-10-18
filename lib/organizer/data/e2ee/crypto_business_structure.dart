import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart' show cryptoSha256, cryptoZeroHash;
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_manager.dart';
import 'crypto_anchor_lock.dart';
import 'crypto_member_action.dart';
import 'crypto_access_coordinator.dart';
import 'crypto_business_leave.dart';

/// Exact existing member action over the signed membership transition. More
/// typed component actions join this adapter only when their full flow exists.
class CryptoBusinessStructure {
  CryptoBusinessStructure(this.context, {this.reviewRecovery});
  final CryptoBusinessSession context;
  final Future<bool> Function(ScopeRotationReview review)? reviewRecovery;
  static const operations = {'scopes.removeMember'};
  bool supports(String operation) => operations.contains(operation);

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    if (!supports(operation) ||
        !isCryptoCanonicalUuid(params['scopeId']) ||
        !isCryptoCanonicalUuid(params['requestId']) ||
        !isCryptoCanonicalUuid(params['accountId'])) {
      throw const FormatException('crypto_membership_action');
    }
    final scope = params['scopeId'] as String;
    final request = params['requestId'] as String;
    final target = params['accountId'] as String;
    if (target == context.account.directory.accountId) {
      return CryptoBusinessLeave(context).request(scope, request);
    }
    final manager = ScopeCryptoManager(context.access);
    final id = 'removeMember:$request';
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [context.partition, scope, id],
    );
    late Map<String, dynamic> action;
    if (rows.isEmpty) {
      final head = await context.access.currentHead(scope, online: true);
      final own = head.member(context.account.directory.accountId);
      final removed = head.member(target);
      if (own['manageKeys'] != true || removed['role'] == 'owner') {
        throw const CryptoAuthorityPending('scope_owner_transfer_required');
      }
      final review = await manager.reviewRotation(scope);
      if (review.sourceHeadHash != head.headHash) {
        throw const CryptoAuthorityPending('crypto_scope_head_changed');
      }
      action = {
        'operation': operation,
        'requestId': request,
        'accountId': target,
        'review': review.value,
        'acceptedCandidateHistory': false,
        'members': [
          for (final member in head.members)
            if (member['accountId'] != target)
              Map<String, dynamic>.from(member),
        ],
      };
      final author = await context.account.directory.requireFresh();
      final lease = await context.account.signingKey();
      try {
        action['authorization'] = context.account.directory.reducer.crypto
            .signDomain(
              {
                'version': 2,
                'operation': 'removeMember',
                'serverId': author.serverId,
                'accountId': author.accountId,
                'deviceId': context.account.deviceId,
                'scopeId': scope,
                'requestId': request,
                'reviewId': review.id,
                'sourceHeadHash': review.sourceHeadHash,
                'targetAccountId': target,
                'membersHash': await cryptoSha256(
                  CryptoJson.encode(_roster(action['members'] as List)),
                ),
                'authorDirectoryHeadHash': author.headHash,
              },
              lease.key,
              CryptoMemberAction.domain,
            );
      } finally {
        lease.release();
      }
      await context.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          context.partition,
          scope,
          id,
          'removeMemberWorkflow',
          CryptoJson.encode(action),
        ],
      );
    } else {
      action = Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList((rows.single['payload'] as List).cast<int>()),
            )
            as Map,
      );
      if (action['operation'] != operation ||
          action['requestId'] != request ||
          action['accountId'] != target) {
        throw const FormatException('crypto_membership_immutable_action');
      }
    }
    final review = ScopeRotationReview(
      Map<String, dynamic>.from(action['review'] as Map),
    );
    final trustedAction = await _verifyAction(action, review);
    action['acceptedCandidateHistory'] =
        trustedAction['acceptedCandidateHistory'] == true;
    if (review.historyBasis == 'reviewedRecoveryBaseline' &&
        action['acceptedCandidateHistory'] != true) {
      if (reviewRecovery == null || !await reviewRecovery!(review)) {
        throw const CryptoAuthorityPending(
          'scope_review_confirmation_required',
        );
      }
      await _rememberAction(action, review, acceptedHistory: true);
      action['acceptedCandidateHistory'] = true;
      await context.database.execute(
        'UPDATE crypto_membership_intents SET payload=? WHERE partition=? AND scope_id=? AND intent_id=?',
        [CryptoJson.encode(action), context.partition, scope, id],
      );
    }
    final coordinator = CryptoAccessCoordinator(context);
    final prepared = await coordinator.prepare(
      scopeId: scope,
      requestId: request,
      action: {'kind': 'memberRemove', 'accountId': target},
    );
    final reconciled = await coordinator.reconcile(scope, prepared);
    if (reconciled != null) {
      if (target == context.account.directory.accountId) {
        return {'removed': true, 'scopeId': scope, 'accountId': target};
      }
      return _verifiedComponentResult(scope, target, prepared, action);
    }
    final affected = await coordinator.affectedScopeTokens(prepared);
    // Catalog pages are discovery only. Each selected source head is verified
    // independently; missing/private children still block the atomic final set
    // until their own managers approve through pendingApprovals.
    String? after;
    do {
      final page = await context.account.directory.call(
        'crypto2.scopes.catalog',
        {'limit': 50, if (after != null) 'afterId': after},
      );
      if (page['scopes'] is! List ||
          (page['scopes'] as List).length > 50 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_membership_catalog');
      }
      for (final raw in page['scopes'] as List) {
        final sid = (raw as Map)['id'];
        if (!isCryptoCanonicalUuid(sid) ||
            after != null && (sid as String).compareTo(after) <= 0) {
          throw const FormatException('crypto_membership_catalog_order');
        }
        after = sid;
        if (!affected.contains(await coordinator.scopeToken(sid, scope))) {
          continue;
        }
        final source = await context.access.currentHead(sid, online: true);
        if (source.member(context.account.directory.accountId)['manageKeys'] !=
            true) {
          continue;
        }
        final pending = await coordinator.pendingApprovals(sid);
        if (!pending.any((p) => p['intentHash'] == prepared['intentHash'])) {
          continue;
        }
        await coordinator.approve(
          sid,
          prepared['intentHash'],
          review: (item) async {
            final expected = [
              for (final member in item.source.members)
                if (member['accountId'] != target) _roles(member),
            ];
            if (sid == scope && item.source.headHash != review.sourceHeadHash ||
                base64Encode(CryptoJson.encode(expected)) !=
                    base64Encode(CryptoJson.encode(item.members))) {
              throw const FormatException(
                'crypto_membership_unreviewed_change',
              );
            }
            final descriptor = await context.access.verifiedScopeDescriptor(
              sid,
            );
            if (base64Encode(
                  CryptoJson.encode({
                    for (final field in const [
                      'kind',
                      'accessPolicyVersion',
                      'parentScopeToken',
                    ])
                      field: descriptor[field],
                    if (descriptor['kind'] == 'organization' &&
                        descriptor.containsKey('leaderAccountIds'))
                      'leaderAccountIds': [
                        for (final id in descriptor['leaderAccountIds'] as List)
                          if (id != target) id,
                      ],
                  }),
                ) !=
                base64Encode(CryptoJson.encode(item.descriptor))) {
              throw const FormatException(
                'crypto_membership_descriptor_changed',
              );
            }
            if (item.history.historyBasis == 'reviewedRecoveryBaseline') {
              if (sid == scope && action['acceptedCandidateHistory'] == true) {
                return true;
              }
              return reviewRecovery != null &&
                  await reviewRecovery!(item.history);
            }
            return true;
          },
        );
      }
      if (page['nextAfterId'] != after ||
          page['hasMore'] == true && (page['scopes'] as List).isEmpty) {
        throw const FormatException('crypto_membership_catalog_cursor');
      }
      if (page['hasMore'] == false) break;
    } while (true);
    await coordinator.finish(scopeId: scope, prepared: prepared, cancel: false);
    if (target == context.account.directory.accountId) {
      return {'removed': true, 'scopeId': scope, 'accountId': target};
    }
    return _verifiedComponentResult(scope, target, prepared, action);
  }

  Future<Map<String, dynamic>> _verifiedComponentResult(
    String scope,
    String target,
    Map<String, dynamic> prepared,
    Map<String, dynamic> action,
  ) async {
    var activated = await context.access.currentHead(scope, online: true);
    late Map consent;
    while (true) {
      final proof = activated.body['accessIntentProof'];
      if (proof is Map) {
        final value =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        if (value['intentHash'] == prepared['intentHash']) {
          consent = value;
          break;
        }
      }
      final previous = activated.body['previousHeadHash'];
      if (previous == cryptoZeroHash) {
        throw const FormatException('crypto_membership_applied_head_missing');
      }
      activated = await context.access.headAt(scope, previous);
    }
    if (consent['intentHash'] != prepared['intentHash'] ||
        activated.body['previousHeadHash'] !=
            (action['review'] as Map)['sourceHeadHash'] ||
        activated.members.any((member) => member['accountId'] == target) ||
        base64Encode(CryptoJson.encode(_roster(activated.members))) !=
            base64Encode(
              CryptoJson.encode(_roster(action['members'] as List)),
            )) {
      throw const FormatException('crypto_membership_activation_mismatch');
    }
    return _result(scope, target, activated.headHash);
  }

  static Map<String, dynamic> _roles(Map member) => {
    for (final field in const [
      'accountId',
      'role',
      'financeRole',
      'manageKeys',
    ])
      field: member[field],
  };

  Map<String, dynamic> _result(String scope, String target, String head) => {
    'removed': true,
    'scopeId': scope,
    'accountId': target,
    'headHash': head,
  };

  String _actionSlot(ScopeRotationReview review) =>
      'memberAction2:${context.partition}:${review.scopeId}:${review.id}';

  Future<Map<String, dynamic>> _rememberAction(
    Map<String, dynamic> action,
    ScopeRotationReview review, {
    bool acceptedHistory = false,
  }) async {
    final hash = await cryptoSha256(CryptoJson.encode(action['authorization']));
    final own = await context.account.directory.requireFresh();
    own.activeDevice(context.account.deviceId);
    final command =
        CryptoJson.decode(
              cryptoBase64((action['authorization'] as Map)['commandBase64']),
            )
            as Map;
    return withCryptoAnchorLock(context.partition, () async {
      if (!context.account.directory.isCurrent()) {
        throw const CryptoAuthorityPending('crypto_identity_changed');
      }
      final old = await context.account.store.secure.read(_actionSlot(review));
      final anchor = old == null
          ? null
          : CryptoMemberAction.anchor(
              jsonDecode(old) as Map,
              actionProofHash: hash,
              requestId: action['requestId'],
              reviewId: review.id,
            );
      final latest = await context.account.store.anchor(own.accountId);
      if (latest == null ||
          latest['deviceSnapshotHash'] != own.deviceSnapshotHash ||
          latest['fingerprint'] != own.rootFingerprint) {
        throw const CryptoAuthorityPending(
          'crypto_member_action_authority_changed',
        );
      }
      if (anchor == null &&
          !own.devices.any(
            (d) =>
                d['deviceId'] == command['deviceId'] &&
                d['revokedGeneration'] == null &&
                d['identityEpochId'] == own.identityEpochId,
          )) {
        throw const CryptoAuthorityPending(
          'crypto_member_action_historical_pending',
        );
      }

      final next = <String, dynamic>{
        'version': 2,
        'actionProofHash': hash,
        'requestId': action['requestId'],
        'reviewId': review.id,
        'acceptedCandidateHistory':
            anchor?['acceptedCandidateHistory'] == true || acceptedHistory,
      };
      await context.account.store.secure.write(
        _actionSlot(review),
        jsonEncode(next),
      );
      return next;
    });
  }

  Future<Map<String, dynamic>> _verifyAction(
    Map<String, dynamic> action,
    ScopeRotationReview review,
  ) async {
    final proof = Map<String, dynamic>.from(action['authorization'] as Map);
    final body = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final own = await context.account.directory.requireFresh();
    CryptoMemberAction.requireBinding(body, {
      'version': 2,
      'operation': 'removeMember',
      'serverId': own.serverId,
      'accountId': own.accountId,
      'deviceId': body['deviceId'],
      'scopeId': review.scopeId,
      'requestId': action['requestId'],
      'reviewId': review.id,
      'sourceHeadHash': review.sourceHeadHash,
      'targetAccountId': action['accountId'],
      'membersHash': await cryptoSha256(
        CryptoJson.encode(_roster(action['members'] as List)),
      ),
      'authorDirectoryHeadHash': body['authorDirectoryHeadHash'],
    });
    final author = await CryptoAccessCoordinator(
      context,
    ).ownDirectoryAt(body['authorDirectoryHeadHash']);
    if (!own.includesAnchor(author.generation, author.headHash)) {
      throw const FormatException('crypto_member_action_prefix');
    }
    final device = author.activeDevice(body['deviceId']);
    context.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      CryptoMemberAction.domain,
    );
    final prior = await context.account.store.secure.read(_actionSlot(review));
    final digest = await cryptoSha256(CryptoJson.encode(proof));
    final anchored =
        prior != null &&
        CryptoMemberAction.anchor(
              jsonDecode(prior) as Map,
              actionProofHash: digest,
              requestId: action['requestId'],
              reviewId: review.id,
            )['actionProofHash'] ==
            digest;
    if (!anchored &&
        !own.devices.any(
          (d) =>
              d['deviceId'] == body['deviceId'] &&
              d['revokedGeneration'] == null &&
              d['identityEpochId'] == own.identityEpochId &&
              d['signingKeyBase64'] == device['signingKeyBase64'],
        )) {
      throw const CryptoAuthorityPending(
        'crypto_member_action_historical_pending',
      );
    }
    return _rememberAction(action, review);
  }

  static List<Map<String, dynamic>> _roster(Iterable<dynamic> members) {
    final result = [
      for (final raw in members)
        {
          for (final field in const [
            'accountId',
            'role',
            'financeRole',
            'manageKeys',
            'rootSigningKeyBase64',
            'rootEncryptionKeyBase64',
            'identityEpochId',
            'recoveryRootEpochId',
          ])
            field: (raw as Map)[field],
        },
    ];
    result.sort(
      (a, b) => (a['accountId'] as String).compareTo(b['accountId'] as String),
    );
    return result;
  }
}
