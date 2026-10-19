import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_finance_policy_actions.dart';
import 'crypto_business_router.dart';
import 'crypto_lifecycle_evidence.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';
import 'session_crypto_access.dart';

bool _same(Object? a, Object? b) =>
    base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

/// A narrow local capability for one recipient's inherited access. Neither a
/// catalog row nor a durable work journal can construct this capability.
final class VerifiedInheritedInvitationAdmission {
  VerifiedInheritedInvitationAdmission._({
    required this.access,
    required this.parent,
    required this.source,
    required this.invitationId,
    required this.acceptanceProofHash,
    required this.recipientAccountId,
    required this.recipientDirectory,
    required this.member,
    required this.parentDescriptor,
    required this.childDescriptor,
    required this.lifecycle,
    required this.lifecycleService,
    required this.financePolicyService,
    required this.financePolicyHash,
    required this.liveAccess,
  });

  final SessionCryptoAccess access;
  final VerifiedScopeHead parent, source;
  final String invitationId, acceptanceProofHash, recipientAccountId;
  final VerifiedAccountDirectory recipientDirectory;
  final Map<String, dynamic> member,
      parentDescriptor,
      childDescriptor,
      lifecycle;
  final CryptoLifecycleEvidence lifecycleService;
  final CryptoFinancePolicyActions financePolicyService;
  final String financePolicyHash;
  final Map<String, dynamic> liveAccess;

  static Future<VerifiedInheritedInvitationAdmission> verify({
    required SessionCryptoAccess access,
    required String parentScopeId,
    required String childScopeId,
    required String invitationId,
    required String acceptanceProofHash,
    required String recipientAccountId,
    CryptoLifecycleEvidence? lifecycleService,
    CryptoFinancePolicyActions? financePolicyService,
  }) async {
    if (parentScopeId == childScopeId ||
        !access.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_changed');
    }
    final parent = await requireParent(
      access: access,
      parentScopeId: parentScopeId,
      invitationId: invitationId,
      acceptanceProofHash: acceptanceProofHash,
      recipientAccountId: recipientAccountId,
    );
    final descriptor = await access.verifiedScopeDescriptor(
      parentScopeId,
      online: true,
    );
    final current = parent.member(recipientAccountId);
    final child = await access.recoveryCandidateHead(childScopeId);
    final childDescriptor = await access.verifiedScopeDescriptor(
      childScopeId,
      online: true,
    );
    final lifecycleApi = lifecycleService ?? CryptoLifecycleEvidence(access);
    final expectedToken = await lifecycleApi.parentToken(
      childScopeId,
      parentScopeId,
    );
    if (childDescriptor['kind'] != 'project' ||
        childDescriptor['accessPolicyVersion'] != 3 ||
        childDescriptor['parentScopeToken'] != expectedToken) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_parent');
    }
    if (child.member(access.account.directory.accountId)['manageKeys'] !=
        true) {
      throw const CryptoAuthorityPending(
        'crypto_inherited_invitation_manager_required',
      );
    }
    final state = await lifecycleApi.forRecoveryReview(
      childScopeId,
      sourceHeadHash: child.headHash,
      financeOnly: false,
    );
    final policies =
        financePolicyService ??
        CryptoFinancePolicyActions(
          CryptoBusinessSession(
            access.account,
            access,
            access.account.store.database,
          ),
        );
    final policy = await policies.readVerified(childScopeId);
    final liveAccess = await _freshAccess(access, childScopeId);
    if (liveAccess['headHash'] != child.headHash) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_changed');
    }
    if (state['ownArchived'] is! bool || state['inheritedArchived'] is! bool) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_policy');
    }
    final old = child.members
        .where((m) => m['accountId'] == recipientAccountId)
        .firstOrNull;
    // Existing direct ownership and membership are retained. A direct viewer
    // acquires the member access already authorized by the signed parent.
    final role = old?['role'] == 'owner'
        ? 'owner'
        : old?['role'] == 'member' || current['role'] != 'viewer'
        ? 'member'
        : 'viewer';
    final archived =
        state['ownArchived'] == true || state['inheritedArchived'] == true;
    final directory = await access.currentMemberDirectory(
      parentScopeId,
      parent.headHash,
      recipientAccountId,
    );
    if (directory.snapshot['rootSigningKeyBase64'] !=
            current['rootSigningKeyBase64'] ||
        directory.snapshot['rootEncryptionKeyBase64'] !=
            current['rootEncryptionKeyBase64'] ||
        directory.identityEpochId != current['identityEpochId'] ||
        directory.snapshot['recoveryRootEpochId'] !=
            current['recoveryRootEpochId'] ||
        directory.deviceSnapshotHash != current['deviceSnapshotHash']) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_changed');
    }
    final capability = VerifiedInheritedInvitationAdmission._(
      access: access,
      parent: parent,
      source: child,
      invitationId: invitationId,
      acceptanceProofHash: acceptanceProofHash,
      recipientAccountId: recipientAccountId,
      recipientDirectory: directory,
      member: Map.unmodifiable({
        ...?old,
        'accountId': recipientAccountId,
        'role': role,
        'financeRole': !policy.enabled
            ? 'none'
            : role == 'viewer' || archived
            ? 'read'
            : 'write',
        'manageKeys': role != 'viewer',
      }),
      parentDescriptor: Map.unmodifiable(descriptor),
      childDescriptor: Map.unmodifiable(childDescriptor),
      lifecycle: Map.unmodifiable(state),
      lifecycleService: lifecycleApi,
      financePolicyService: policies,
      financePolicyHash: await policy.hash(),
      liveAccess: liveAccess,
    );
    await capability.revalidate(access: access, source: child);
    return capability;
  }

  /// A restored routing row cannot stand in for this signed admission proof,
  /// including when the parent presently has no child projects.
  static Future<VerifiedScopeHead> requireParent({
    required SessionCryptoAccess access,
    required String parentScopeId,
    required String invitationId,
    required String acceptanceProofHash,
    required String recipientAccountId,
  }) => access.withVerifiedOperation(() async {
    if (!access.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
    final parent = await access.currentHead(parentScopeId, online: true);
    final descriptor = await access.verifiedScopeDescriptor(
      parentScopeId,
      online: true,
    );
    if (!const {'household', 'organization'}.contains(descriptor['kind']) ||
        descriptor['accessPolicyVersion'] != 3) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_policy');
    }
    final current = parent.member(recipientAccountId);
    var ancestor = parent;
    Map<String, dynamic>? admitted;
    while (true) {
      final intents = ancestor.body['membershipIntents'] as List;
      if (intents.any(
        (value) =>
            value['accountId'] == recipientAccountId &&
            value['invitationId'] == invitationId &&
            value['acceptanceProofHash'] == acceptanceProofHash,
      )) {
        admitted = ancestor.member(recipientAccountId);
        break;
      }
      if (ancestor.epoch == 1) break;
      ancestor = access.verifiedCandidateAncestor(
        ancestor.body['previousHeadHash'],
      );
    }
    if (admitted == null ||
        !const {'owner', 'member', 'viewer'}.contains(current['role']) ||
        [
          'rootSigningKeyBase64',
          'rootEncryptionKeyBase64',
          'identityEpochId',
          'recoveryRootEpochId',
          'role',
        ].any((field) => current[field] != admitted![field])) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_changed');
    }
    return parent;
  }, freshBoundary: true);

  List<Map<String, dynamic>> get members =>
      [
        for (final existing in source.members)
          if (existing['accountId'] != recipientAccountId)
            Map<String, dynamic>.from(existing),
        Map<String, dynamic>.from(member),
      ]..sort(
        (a, b) =>
            (a['accountId'] as String).compareTo(b['accountId'] as String),
      );

  bool get alreadyAvailable {
    final old = source.members
        .where((m) => m['accountId'] == recipientAccountId)
        .firstOrNull;
    return source.active &&
        liveAccess['headHash'] == source.headHash &&
        liveAccess['expectedAccessRevision'] == source.accessRevision &&
        _same(liveAccess['accessBasis'], source.body['accessBasis']) &&
        _same(
          _roles((liveAccess['members'] as List).cast<Map<String, dynamic>>()),
          _roles(source.members),
        ) &&
        old != null &&
        [
          'role',
          'financeRole',
          'manageKeys',
        ].every((f) => old[f] == member[f]) &&
        old['rootSigningKeyBase64'] ==
            recipientDirectory.snapshot['rootSigningKeyBase64'] &&
        old['rootEncryptionKeyBase64'] ==
            recipientDirectory.snapshot['rootEncryptionKeyBase64'] &&
        old['recoveryRootEpochId'] ==
            recipientDirectory.snapshot['recoveryRootEpochId'] &&
        old['identityEpochId'] == recipientDirectory.identityEpochId &&
        old['deviceSnapshotHash'] == recipientDirectory.deviceSnapshotHash;
  }

  Future<void> revalidate({
    required SessionCryptoAccess access,
    required VerifiedScopeHead source,
    List<Map<String, dynamic>>? proposedMembers,
  }) => access.withVerifiedOperation(() async {
    if (!identical(access, this.access) ||
        source.headHash != this.source.headHash ||
        source.scopeId != this.source.scopeId ||
        !access.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_changed');
    }
    final parentNow = await access.currentHead(parent.scopeId, online: true);
    final childNow = await access.recoveryCandidateHead(source.scopeId);
    final parentPolicy = await access.verifiedScopeDescriptor(
      parent.scopeId,
      online: true,
    );
    final childPolicy = await access.verifiedScopeDescriptor(
      source.scopeId,
      online: true,
    );
    final state = await lifecycleService.forRecoveryReview(
      source.scopeId,
      sourceHeadHash: source.headHash,
      financeOnly: false,
    );
    final currentFinance = await financePolicyService.readVerified(
      source.scopeId,
    );
    final currentAccess = await _freshAccess(access, source.scopeId);
    final directory = await access.currentMemberDirectory(
      parent.scopeId,
      parent.headHash,
      recipientAccountId,
    );
    if (parentNow.headHash != parent.headHash ||
        childNow.headHash != source.headHash ||
        !_same(parentDescriptor, parentPolicy) ||
        !_same(childDescriptor, childPolicy) ||
        !_same(lifecycle, state) ||
        await currentFinance.hash() != financePolicyHash ||
        !_same(liveAccess, currentAccess) ||
        directory.headHash != recipientDirectory.headHash ||
        directory.deviceSnapshotHash != recipientDirectory.deviceSnapshotHash ||
        childNow.member(access.account.directory.accountId)['manageKeys'] !=
            true ||
        proposedMembers != null &&
            !_same(_roles(proposedMembers), _roles(members))) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_changed');
    }
  }, freshBoundary: true);

  static Future<Map<String, dynamic>> _freshAccess(
    SessionCryptoAccess access,
    String scopeId,
  ) async {
    String? after;
    var count = 0;
    while (true) {
      final page = await access.account.directory.call(
        'crypto2.scopes.catalog',
        {'limit': 50, if (after != null) 'afterId': after},
      );
      final rows = page['scopes'];
      if (rows is! List || rows.length > 50 || (count += rows.length) > 1000) {
        throw const FormatException('crypto_scope_catalog');
      }
      for (final value in rows) {
        if (value is! Map ||
            value['id'] is! String ||
            after != null && (value['id'] as String).compareTo(after) <= 0) {
          throw const FormatException('crypto_scope_catalog_cursor');
        }
        after = value['id'];
        if (value['id'] == scopeId) {
          if (value['expectedAccessRevision'] is! int ||
              value['accessBasis'] is! List ||
              value['members'] is! List) {
            throw const FormatException('crypto_scope_catalog');
          }
          return {
            'headHash': value['headHash'],
            'expectedAccessRevision': value['expectedAccessRevision'],
            'accessBasis': value['accessBasis'],
            'members': _roles(
              (value['members'] as List)
                  .map((m) => Map<String, dynamic>.from(m as Map))
                  .toList(),
            ),
          };
        }
      }
      if (page['hasMore'] != true ||
          rows.isEmpty ||
          page['nextAfterId'] != after) {
        throw const CryptoAuthorityPending(
          'crypto_inherited_invitation_changed',
        );
      }
    }
  }

  static List<Map<String, dynamic>> _roles(List<Map<String, dynamic>> input) =>
      [
        for (final value in input)
          {
            for (final field in [
              'accountId',
              'role',
              'financeRole',
              'manageKeys',
            ])
              field: value[field],
          },
      ]..sort(
        (a, b) =>
            (a['accountId'] as String).compareTo(b['accountId'] as String),
      );
}
