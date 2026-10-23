import 'account_directory_v2.dart';
import 'crypto_invitation_preauthorization_codec.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';
import 'session_crypto_access.dart';
import 'crypto_lifecycle_evidence.dart';
import 'crypto_finance_policy_actions.dart';
import 'crypto_business_router.dart' show CryptoBusinessSession;

/// Owner's exact Send-time authority. This never represents recipient consent.
final class VerifiedPreauthorizedInvitationAdmission {
  VerifiedPreauthorizedInvitationAdmission._({
    required this.access,
    required this.scopeId,
    required this.invitationScopeId,
    required this.invitationId,
    required this.proofHash,
    required this.directory,
    required this.member,
    required this.sourceHeadHash,
    required this.proof,
  });
  final SessionCryptoAccess access;
  final String scopeId,
      invitationScopeId,
      invitationId,
      proofHash,
      sourceHeadHash;
  final VerifiedAccountDirectory directory;
  final Map<String, dynamic> member, proof;
  String get recipientAccountId => directory.accountId;
  Map<String, dynamic> get condition => {
    'accountId': recipientAccountId,
    'invitationId': invitationId,
    'preauthorizationProofHash': proofHash,
    'invitationScopeId': invitationScopeId,
  };
  Map<String, dynamic> get intent => {
    'accountId': recipientAccountId,
    'invitationId': invitationId,
    'preauthorizationProofHash': proofHash,
  };

  static Future<VerifiedPreauthorizedInvitationAdmission> verify({
    required SessionCryptoAccess access,
    required Map<String, dynamic> authorization,
    required VerifiedAccountDirectory recipientDirectory,
  }) async {
    final raw =
        CryptoJson.decode(cryptoBase64(authorization['commandBase64'])) as Map;
    final p = raw['payload'] as Map;
    final own = await access.directoryAt(
      scopeId: p['scopeId'],
      scopeHeadHash: p['membershipHeadHash'],
      accountId: raw['accountId'],
      directoryHeadHash: p['authorDirectoryHeadHash'],
      online: true,
    );
    access.account.directory.reducer.crypto.verifyDomain(
      authorization,
      cryptoBase64(
        own.activeDevice(raw['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    final pre = p['preauthorization'];
    final source = await access.headAt(p['scopeId'], p['membershipHeadHash']);
    final current = await access.recoveryCandidateHead(p['scopeId']);
    final proofHash = await cryptoSha256(CryptoJson.encode(authorization));
    final descriptor = await access.verifiedScopeDescriptor(
      p['scopeId'],
      online: true,
    );
    Map? freshAccess;
    if (current.headHash == source.headHash) {
      String? after;
      while (freshAccess == null) {
        final page = await access.account.directory.call(
          'crypto2.scopes.catalog',
          {'limit': 50, if (after != null) 'afterId': after},
        );
        for (final value in page['scopes'] as List) {
          if (value['id'] == source.scopeId) freshAccess = value as Map;
        }
        if (freshAccess != null) break;
        final next = page['nextAfterId'];
        if (page['hasMore'] != true ||
            next is! String ||
            after != null && next.compareTo(after) <= 0) {
          throw const CryptoAuthorityPending('scope_discovery_pending');
        }
        after = next;
      }
    } else {
      var origin = current;
      while (origin.body['previousHeadHash'] != source.headHash &&
          origin.epoch > 1) {
        origin = access.verifiedCandidateAncestor(
          origin.body['previousHeadHash'],
        );
      }
      if (origin.body['previousHeadHash'] != source.headHash ||
          !origin.invitationPreauthorizations.any(
            (c) => c['preauthorizationProofHash'] == proofHash,
          )) {
        throw const CryptoAuthorityPending(
          'crypto_invitation_preauthorization_changed',
        );
      }
      freshAccess = origin.body;
    }
    if (raw['version'] != 2 ||
        raw['signer'] != 'device' ||
        raw['serverId'] != access.account.directory.session.profile.serverId ||
        raw['accountId'] != access.account.directory.accountId ||
        !const {
          'crypto2.invitations.create',
          'crypto2.invitations.resend',
        }.contains(raw['operation']) ||
        source.headHash != p['membershipHeadHash'] ||
        (current.headHash != source.headHash &&
            !current.invitationPreauthorizations.any(
              (c) =>
                  c['invitationId'] == p['invitationId'] &&
                  c['preauthorizationProofHash'] == proofHash,
            )) ||
        current.member(own.accountId)['manageKeys'] != true ||
        source.member(own.accountId)['manageKeys'] != true ||
        pre is! Map ||
        pre['version'] != 1 ||
        pre.length != 4 ||
        pre['policyVersion'] != descriptor['accessPolicyVersion'] ||
        !samePreauthorizationValue(
          pre['accessBasis'],
          freshAccess['accessBasis'],
        ) ||
        p['expectedAccessRevision'] != freshAccess['expectedAccessRevision'] ||
        pre['member'] is! Map ||
        pre['member']['accountId'] != recipientDirectory.accountId ||
        p['recipient']['accountId'] != recipientDirectory.accountId ||
        pre['member']['role'] != p['role']) {
      throw const FormatException('crypto_invitation_preauthorization_binding');
    }
    final target = Map<String, dynamic>.from(pre['member'] as Map);
    final expected = {
      ...target,
      'accountId': recipientDirectory.accountId,
      'rootSigningKeyBase64':
          recipientDirectory.snapshot['rootSigningKeyBase64'],
      'rootEncryptionKeyBase64':
          recipientDirectory.snapshot['rootEncryptionKeyBase64'],
      'recoveryRootEpochId': recipientDirectory.snapshot['recoveryRootEpochId'],
      'identityEpochId': recipientDirectory.identityEpochId,
      'directoryHeadHash': recipientDirectory.headHash,
      'deviceSnapshotHash': recipientDirectory.deviceSnapshotHash,
    };
    if (target.length != 10 ||
        !samePreauthorizationValue(target, expected) ||
        !const {'none', 'read', 'write'}.contains(target['financeRole']) ||
        target['manageKeys'] is! bool) {
      throw const FormatException(
        'crypto_invitation_preauthorization_directory',
      );
    }
    await access.identities.requireVerified(
      recipientDirectory.accountId,
      access.identities.fingerprint(recipientDirectory),
    );
    return VerifiedPreauthorizedInvitationAdmission._(
      access: access,
      scopeId: source.scopeId,
      invitationScopeId: source.scopeId,
      invitationId: p['invitationId'],
      proofHash: proofHash,
      directory: recipientDirectory,
      member: Map.unmodifiable(target),
      sourceHeadHash: source.headHash,
      proof: Map.unmodifiable(authorization),
    );
  }

  Future<void> revalidate(VerifiedScopeHead source) async {
    if (!access.account.directory.isCurrent() ||
        source.scopeId != scopeId ||
        source.headHash != sourceHeadHash ||
        source.member(access.account.directory.accountId)['manageKeys'] !=
            true) {
      throw const CryptoAuthorityPending(
        'crypto_invitation_preauthorization_changed',
      );
    }
    await access.identities.requireVerified(
      directory.accountId,
      access.identities.fingerprint(directory),
    );
    if (scopeId != invitationScopeId) {
      final parent = await access.currentHead(invitationScopeId, online: true);
      if (!parent.invitationPreauthorizations.any(
        (c) => samePreauthorizationValue(c, condition),
      )) {
        throw const CryptoAuthorityPending(
          'crypto_invitation_preauthorization_parent',
        );
      }
    }
  }

  Future<VerifiedPreauthorizedInvitationAdmission> forChild(
    String child,
  ) async {
    final parent = await access.currentHead(invitationScopeId, online: true);
    final parentDescriptor = await access.verifiedScopeDescriptor(
      invitationScopeId,
      online: true,
    );
    final source = await access.recoveryCandidateHead(child);
    final descriptor = await access.verifiedScopeDescriptor(
      child,
      online: true,
    );
    if (parentDescriptor['accessPolicyVersion'] != 3 ||
        descriptor['accessPolicyVersion'] != 3 ||
        descriptor['kind'] != 'project' ||
        descriptor['parentScopeToken'] !=
            await CryptoLifecycleEvidence(
              access,
            ).parentToken(child, invitationScopeId) ||
        !parent.invitationPreauthorizations.any(
          (c) => samePreauthorizationValue(c, condition),
        ) ||
        source.member(access.account.directory.accountId)['manageKeys'] !=
            true) {
      throw const CryptoAuthorityPending(
        'crypto_invitation_preauthorization_parent',
      );
    }
    final policy = await CryptoFinancePolicyActions(
      CryptoBusinessSession(
        access.account,
        access,
        access.account.store.database,
      ),
    ).readVerified(child);
    final lifecycle = await CryptoLifecycleEvidence(access).forRecoveryReview(
      child,
      sourceHeadHash: source.headHash,
      financeOnly: false,
    );
    final role = member['role'] == 'viewer' ? 'viewer' : 'member';
    return VerifiedPreauthorizedInvitationAdmission._(
      access: access,
      scopeId: child,
      invitationScopeId: invitationScopeId,
      invitationId: invitationId,
      proofHash: proofHash,
      directory: directory,
      sourceHeadHash: source.headHash,
      proof: proof,
      member: Map.unmodifiable({
        ...member,
        'role': role,
        'financeRole': !policy.enabled
            ? 'none'
            : role == 'viewer' ||
                  lifecycle['ownArchived'] == true ||
                  lifecycle['inheritedArchived'] == true
            ? 'read'
            : 'write',
        'manageKeys': role != 'viewer',
      }),
    );
  }
}

/// Resolve permission labels from signed scope/finance/lifecycle evidence before
/// the owner's invitation signature or any envelope disclosure.
Future<void> verifyPreauthorizedMemberRights({
  required SessionCryptoAccess access,
  required String scopeId,
  required int policyVersion,
  required Map<String, dynamic> member,
}) async {
  final descriptor = await access.verifiedScopeDescriptor(
    scopeId,
    online: true,
  );
  final source = await access.recoveryCandidateHead(scopeId);
  if (descriptor['accessPolicyVersion'] != policyVersion ||
      !const {1, 2, 3}.contains(policyVersion) ||
      !const {'member', 'viewer'}.contains(member['role']) ||
      member['manageKeys'] !=
          (policyVersion == 3 && member['role'] == 'member')) {
    throw const FormatException('crypto_invitation_preauthorization_rights');
  }
  final policy = await CryptoFinancePolicyActions(
    CryptoBusinessSession(
      access.account,
      access,
      access.account.store.database,
    ),
  ).readVerified(scopeId);
  final lifecycle = await CryptoLifecycleEvidence(access).forRecoveryReview(
    scopeId,
    sourceHeadHash: source.headHash,
    financeOnly: false,
  );
  var grant = 'none';
  if (policyVersion == 3) {
    grant = member['role'] == 'viewer' ? 'read' : 'write';
  } else {
    for (final value in policy.grants) {
      if (value['accountId'] == member['accountId'])
        grant = value['grant'] as String;
    }
    if (grant == 'none' &&
        policyVersion == 2 &&
        descriptor['kind'] == 'project' &&
        descriptor['parentScopeToken'] != null) {
      // Existing policy2 organization projects provide membership read. Resolve
      // the parent hint only by matching its signed token and descriptor kind.
      String? after;
      var organizationParent = false;
      while (true) {
        final page = await access.account.directory.call(
          'crypto2.scopes.catalog',
          {'limit': 50, if (after != null) 'afterId': after},
        );
        for (final value in page['scopes'] as List) {
          if (value['id'] != scopeId) continue;
          final parent = value['parentScopeId'];
          if (parent is String &&
              descriptor['parentScopeToken'] ==
                  await CryptoLifecycleEvidence(
                    access,
                  ).parentToken(scopeId, parent)) {
            final checked = await access.verifiedScopeDescriptor(
              parent,
              online: true,
            );
            organizationParent = checked['kind'] == 'organization';
          }
        }
        if (organizationParent || page['hasMore'] != true) break;
        final next = page['nextAfterId'];
        if (next is! String || after != null && next.compareTo(after) <= 0) {
          throw const FormatException('scope_catalog_cursor');
        }
        after = next;
      }
      if (organizationParent) grant = 'read';
    }
  }
  if (!policy.enabled) grant = 'none';
  if (grant == 'write' &&
      (member['role'] == 'viewer' ||
          lifecycle['ownArchived'] == true ||
          lifecycle['inheritedArchived'] == true)) {
    grant = 'read';
  }
  if (member['financeRole'] != grant) {
    throw const FormatException('crypto_invitation_preauthorization_rights');
  }
}
