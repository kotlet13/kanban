part of 'invite_crypto_repository.dart';

enum ForegroundInvitationApprovalStatus { completed, pending, manualReview }

class ForegroundInvitationApprovalResult {
  const ForegroundInvitationApprovalResult(this.status, [this.reason]);
  final ForegroundInvitationApprovalStatus status;
  final String? reason;
}

/// Static codes only: never expose exception text, invitation IDs, tokens,
/// account labels or other server-provided values in automatic diagnostics.
String safeForegroundInvitationApprovalReason(Object error) {
  final code = error is String
      ? error
      : error is CryptoAuthorityPending
      ? error.reason
      : error is CollaborationApiException
      ? error.code
      : error is FormatException
      ? error.message
      : 'invitation_approval_pending';
  const allowed = {
    'crypto_invitation_foreground_required',
    'crypto_stale_identity',
    'invitation_acceptance_pending',
    'invitation_send_pending',
    'invitation_list_pending',
    'invitation_not_accepted',
    'invitation_invalid',
    'invitation_acceptance_changed',
    'invitation_acceptance_binding',
    'crypto_invitation_auto_policy_changed',
    'crypto_invitation_auto_membership_changed',
    'crypto_invitation_auto_acceptance_changed',
    'crypto_invitation_auto_acceptance',
    'crypto_invitation_auto_binding',
    'crypto_invitation_auto_rights',
    'crypto_invitation_auto_hint',
    'scope_review_confirmation_required',
    'scope_receipt_pending',
    'crypto_invitation_original_intent_missing',
    'network_unavailable',
    'invitation_approval_pending',
  };
  return allowed.contains(code) ? code : 'invitation_approval_pending';
}

/// Routing and display only. Every transition still requires the exact signed
/// Send, recipient acceptance, fresh verified policy and foreground authority.
class ForegroundInvitationApprovalPending {
  const ForegroundInvitationApprovalPending(
    this.scopeId,
    this.invitationId,
    this.errorCode,
  );
  final String scopeId, invitationId, errorCode;
}

class ForegroundInvitationApprovalSummary {
  const ForegroundInvitationApprovalSummary({
    this.completed = 0,
    this.examined = 0,
    this.invitations = const [],
  });
  final int completed, examined;
  final List<ForegroundInvitationApprovalPending> invitations;
  int get pending => invitations.length;
}

final _foregroundInvitationRuns =
    <String, Future<ForegroundInvitationApprovalSummary>>{};

extension ForegroundInvitationApproval on InviteCryptoRepository {
  Future<ForegroundInvitationApprovalResult>
  _finishForegroundInvitationApproval({
    required String scopeId,
    required String invitationId,
    required bool Function() isForegroundCurrent,
    InvitationAcceptanceNotification? expectedAcceptance,
  }) async {
    _foregroundGuard(isForegroundCurrent);
    // The page must wait for a sweep already completing this same account,
    // then verify using its own foreground capability and exact notification.
    final running = _foregroundInvitationRuns[access.account.store.partition];
    if (running != null) await running;
    _foregroundGuard(isForegroundCurrent);
    final summary = await _accountWorkProcessForegroundAutoApprovals(
      isForegroundCurrent: isForegroundCurrent,
      invitationIds: {invitationId},
      targetScopeId: scopeId,
      expectedAcceptance: expectedAcceptance,
      reconcileCompleted: true,
    );
    _foregroundGuard(isForegroundCurrent);
    if (summary.completed == 1) {
      return const ForegroundInvitationApprovalResult(
        ForegroundInvitationApprovalStatus.completed,
      );
    }
    final reason = summary.examined == 0
        ? 'crypto_invitation_original_intent_missing'
        : summary.invitations.firstOrNull?.errorCode ??
              'invitation_approval_pending';
    const manualReasons = {
      'crypto_invitation_original_intent_missing',
      'crypto_invitation_auto_policy_changed',
      'crypto_invitation_auto_rights',
      'invitation_acceptance_changed',
      'crypto_invitation_auto_acceptance_changed',
    };
    return ForegroundInvitationApprovalResult(
      manualReasons.contains(reason)
          ? ForegroundInvitationApprovalStatus.manualReview
          : ForegroundInvitationApprovalStatus.pending,
      reason,
    );
  }

  void _foregroundGuard(bool Function() current) {
    if (!current() || !access.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending(
        'crypto_invitation_foreground_required',
      );
    }
  }

  Map<String, dynamic> _autoDecode(Object? bytes) => Map<String, dynamic>.from(
    CryptoJson.decode(Uint8List.fromList((bytes as List).cast<int>())) as Map,
  );

  Future<Map<String, dynamic>> _prepareForegroundApproval(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final rights = await foregroundInvitationRights(payload);
    final session = access.account.directory.session.profile;
    return {
      'version': 1,
      'action': action,
      'serverId': session.serverId,
      'creatorAccountId': session.accountId,
      'payload': payload,
      'rights': rights,
      'reviewId': access.account.directory.reducer.crypto.randomId(),
    };
  }

  Future<VerifiedCryptoInvitation> _retainedConsumedRecipient(
    Map<String, dynamic> saved,
    String scope,
    String id,
    VerifiedScopeHead head,
  ) async {
    if (saved['acceptanceAuthorization'] is! Map ||
        saved['recipientAccountId'] is! String) {
      throw const CryptoAuthorityPending('invitation_acceptance_pending');
    }
    final proof = Map<String, dynamic>.from(
      saved['acceptanceAuthorization'] as Map,
    );
    if (await cryptoSha256(CryptoJson.encode(proof)) !=
        saved['acceptanceProofHash']) {
      throw const FormatException('crypto_invitation_auto_acceptance_changed');
    }
    final directory = await access.currentMemberDirectory(
      scope,
      head.headHash,
      saved['recipientAccountId'],
    );
    if (directory.rootFingerprint != saved['recipientRootFingerprint'] ||
        directory.deviceSnapshotHash != saved['recipientDeviceSnapshotHash'] ||
        !directory.includesAnchor(
          saved['recipientDirectoryGeneration'],
          saved['recipientDirectoryHeadHash'],
        )) {
      throw const CryptoAuthorityPending('invitation_acceptance_changed');
    }
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    if (command['version'] != 2 ||
        command['operation'] != 'crypto2.invitations.accept' ||
        command['serverId'] !=
            access.account.directory.session.profile.serverId ||
        command['accountId'] != directory.accountId ||
        command['signer'] != 'device') {
      throw const FormatException('crypto_invitation_auto_acceptance_changed');
    }
    access.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(
        directory.activeDevice(command['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    return VerifiedCryptoInvitation(
      {
        'invitation': {'id': id, 'scopeId': scope},
        'creatorAuthorization': proof,
        'acceptanceProofHash': saved['acceptanceProofHash'],
        'proposedMember': {
          for (final key in ['accountId', 'role', 'financeRole', 'manageKeys'])
            key: head.member(directory.accountId)[key],
        },
      },
      directory,
      const [],
    );
  }

  /// Event driven foreground sweep. Old invitations have no captured intent and
  /// cannot enter this path. A notification only wakes this bounded read.
  Future<ForegroundInvitationApprovalSummary> processForegroundAutoApprovals({
    required bool Function() isForegroundCurrent,
    Set<String> invitationIds = const {},
  }) => withAccountWorkJob(
    access.account.directory.transport,
    AccountWorkKind.foregroundInvitation,
    () => _accountWorkProcessForegroundAutoApprovals(
      isForegroundCurrent: isForegroundCurrent,
      invitationIds: invitationIds,
    ),
    priority: AccountWorkPriority.background,
  );

  Future<ForegroundInvitationApprovalSummary>
  _accountWorkProcessForegroundAutoApprovals({
    required bool Function() isForegroundCurrent,
    Set<String> invitationIds = const {},
    String? targetScopeId,
    InvitationAcceptanceNotification? expectedAcceptance,
    bool reconcileCompleted = false,
  }) async {
    _foregroundGuard(isForegroundCurrent);
    final partition = access.account.store.partition;
    // A second account/device caller must never inherit another foreground
    // capability. It may ask for a later sweep after this run completes.
    final running = _foregroundInvitationRuns[partition];
    if (running != null) {
      if (!reconcileCompleted) {
        return const ForegroundInvitationApprovalSummary();
      }
      await running;
      _foregroundGuard(isForegroundCurrent);
      return _accountWorkProcessForegroundAutoApprovals(
        isForegroundCurrent: isForegroundCurrent,
        invitationIds: invitationIds,
        targetScopeId: targetScopeId,
        expectedAcceptance: expectedAcceptance,
        reconcileCompleted: true,
      );
    }
    final task = _processForegroundApprovals(
      isForegroundCurrent,
      invitationIds,
      targetScopeId: targetScopeId,
      expectedAcceptance: expectedAcceptance,
      reconcileCompleted: reconcileCompleted,
    );
    _foregroundInvitationRuns[partition] = task;
    try {
      return await task;
    } finally {
      if (identical(_foregroundInvitationRuns[partition], task)) {
        _foregroundInvitationRuns.remove(partition);
      }
    }
  }

  Future<ForegroundInvitationApprovalSummary> _processForegroundApprovals(
    bool Function() current,
    Set<String> invitationIds, {
    String? targetScopeId,
    InvitationAcceptanceNotification? expectedAcceptance,
    bool reconcileCompleted = false,
  }) async {
    final store = access.account.store,
        session = access.account.directory.session.profile;
    if (invitationIds.length > 100 ||
        invitationIds.any((id) => !isCryptoCanonicalUuid(id))) {
      throw const FormatException('crypto_invitation_auto_hint');
    }
    final hints = invitationIds.isEmpty
        ? ''
        : " AND intent_id IN (${List.filled(invitationIds.length, '?').join(',')})";
    final states = reconcileCompleted
        ? "state IN ('invitationForegroundApproval','invitationForegroundApprovalComplete')"
        : "state='invitationForegroundApproval'";
    final target = targetScopeId == null ? '' : ' AND scope_id=?';
    final rows = await store.database.rows(
      "SELECT scope_id,intent_id,payload,state FROM crypto_membership_intents WHERE partition=? AND $states$hints$target ORDER BY COALESCE(json_extract(CAST(payload AS TEXT),'\$.lastExamined'),0),scope_id,intent_id LIMIT 100",
      [
        store.partition,
        ...invitationIds.map((id) => 'autoInvitation:$id'),
        if (targetScopeId != null) targetScopeId,
      ],
    );
    var completed = 0;
    final pending = <ForegroundInvitationApprovalPending>[];
    final lists = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      _foregroundGuard(current);
      final saved = _autoDecode(row['payload']);
      final original = Map<String, dynamic>.from(saved['payload'] as Map);
      final scope = row['scope_id'] as String,
          id = original['invitationId'] as String;
      try {
        if (saved['version'] != 1 ||
            saved['serverId'] != session.serverId ||
            saved['creatorAccountId'] != session.accountId ||
            original['scopeId'] != scope ||
            original['preauthorization'] != null ||
            original['recipient']['kind'] != 'email') {
          throw const FormatException('crypto_invitation_auto_binding');
        }
        final commands = await store.database.rows(
          'SELECT i.authorization,i.state FROM crypto_membership_action_keys a JOIN crypto_membership_intents i ON i.partition=a.partition AND i.scope_id=a.scope_id AND i.intent_id=a.request_id WHERE a.partition=? AND a.scope_id=? AND a.action_key=?',
          [store.partition, scope, 'invite:${saved['action']}'],
        );
        // Never resend an unknown Send on a background notification. The
        // explicit Send continuation owns receipt-first delivery of that step.
        if (commands.length != 1 || commands.single['state'] != 'confirmed') {
          throw const CryptoAuthorityPending('invitation_send_pending');
        }
        final proof = _autoDecode(commands.single['authorization']);
        if (expectedAcceptance != null &&
            (expectedAcceptance.scopeId != scope ||
                expectedAcceptance.invitationId != id ||
                expectedAcceptance.tokenHash != original['tokenHash'] ||
                expectedAcceptance.creatorProofHash !=
                    await cryptoSha256(CryptoJson.encode(proof)))) {
          throw const FormatException('invitation_acceptance_changed');
        }
        final command =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        if (command['serverId'] != session.serverId ||
            command['accountId'] != session.accountId ||
            !const {
              'crypto2.invitations.create',
              'crypto2.invitations.resend',
            }.contains(command['operation']) ||
            !samePreauthorizationValue(command['payload'], original)) {
          throw const FormatException('crypto_invitation_auto_binding');
        }
        _foregroundGuard(current);
        final list = lists[scope] ??= (await dispatch('invitations3.list', {
          'scopeId': scope,
        }))['invitations'].cast<Map<String, dynamic>>();
        _foregroundGuard(current);
        final selected = list.where((v) => v['id'] == id).toList();
        if (selected.length != 1) {
          throw const CryptoAuthorityPending('invitation_list_pending');
        }
        final state = selected.single['state'];
        if (state == 'revoked' || state == 'expired') {
          if (reconcileCompleted) {
            throw const CryptoAuthorityPending('invitation_invalid');
          }
          await store.database.execute(
            "UPDATE crypto_membership_intents SET state='invitationForegroundApprovalClosed' WHERE partition=? AND scope_id=? AND intent_id=?",
            [store.partition, scope, row['intent_id']],
          );
          continue;
        }
        if (state != 'accepted' && state != 'consumed') {
          if (reconcileCompleted) {
            throw const CryptoAuthorityPending('invitation_not_accepted');
          }
          continue;
        }
        final head = await access.currentHead(scope, online: true);
        final recipient = state == 'consumed'
            ? await _retainedConsumedRecipient(saved, scope, id, head)
            : await acceptedRecipient(
                scope,
                id,
                acceptanceProofHash: saved['acceptanceProofHash'],
              );
        final acceptanceHash = recipient.response['acceptanceProofHash'];
        if (expectedAcceptance != null &&
            expectedAcceptance.acceptanceProofHash != acceptanceHash) {
          throw const FormatException('invitation_acceptance_changed');
        }
        final acceptedCommand =
            CryptoJson.decode(
                  cryptoBase64(recipient.authorization['commandBase64']),
                )
                as Map;
        final accepted = acceptedCommand['payload'] as Map;
        if (acceptedCommand['accountId'] != recipient.creator.accountId ||
            accepted['creatorProofHash'] !=
                await cryptoSha256(CryptoJson.encode(proof)) ||
            ![
              'scopeId',
              'invitationId',
              'role',
              'tokenHash',
              'expiresAt',
              'membershipHeadHash',
            ].every((k) => accepted[k] == original[k]) ||
            accepted.containsKey('preauthorizationHeadHash')) {
          throw const FormatException('crypto_invitation_auto_acceptance');
        }
        final rights = Map<String, dynamic>.from(saved['rights'] as Map);
        final nowRights = await foregroundInvitationRights(
          original,
          accountId: recipient.creator.accountId,
        );
        if (!samePreauthorizationValue(rights, nowRights)) {
          throw const CryptoAuthorityPending(
            'crypto_invitation_auto_policy_changed',
          );
        }
        final proposed = recipient.response['proposedMember'] as Map;
        if (proposed['accountId'] != recipient.creator.accountId ||
            ![
              'role',
              'financeRole',
              'manageKeys',
            ].every((k) => proposed[k] == rights[k])) {
          throw const FormatException('crypto_invitation_auto_rights');
        }
        final boundAccount = saved['recipientAccountId'],
            boundHash = saved['acceptanceProofHash'];
        if ((boundAccount != null &&
                boundAccount != recipient.creator.accountId) ||
            (boundHash != null && boundHash != acceptanceHash)) {
          throw const FormatException(
            'crypto_invitation_auto_acceptance_changed',
          );
        }
        if (boundAccount == null) {
          saved['recipientAccountId'] = recipient.creator.accountId;
          saved['acceptanceProofHash'] = acceptanceHash;
          saved['acceptanceAuthorization'] = recipient.authorization;
          saved['recipientRootFingerprint'] = recipient.creator.rootFingerprint;
          saved['recipientDeviceSnapshotHash'] =
              recipient.creator.deviceSnapshotHash;
          saved['recipientDirectoryGeneration'] = recipient.creator.generation;
          saved['recipientDirectoryHeadHash'] = recipient.creator.headHash;
          await store.database.execute(
            'UPDATE crypto_membership_intents SET payload=? WHERE partition=? AND scope_id=? AND intent_id=?',
            [
              CryptoJson.encode(saved),
              store.partition,
              scope,
              row['intent_id'],
            ],
          );
        }
        Future<void> guard(VerifiedCryptoInvitation checked) async {
          _foregroundGuard(current);
          if (checked.creator.accountId != recipient.creator.accountId ||
              checked.creator.rootFingerprint !=
                  recipient.creator.rootFingerprint ||
              checked.creator.deviceSnapshotHash !=
                  recipient.creator.deviceSnapshotHash ||
              checked.response['acceptanceProofHash'] != acceptanceHash) {
            throw const CryptoAuthorityPending('invitation_acceptance_changed');
          }
        }

        bool exactMembership(VerifiedScopeHead candidate) =>
            candidate.members.any(
              (member) =>
                  member['accountId'] == recipient.creator.accountId &&
                  [
                    'role',
                    'financeRole',
                    'manageKeys',
                  ].every((key) => member[key] == rights[key]),
            ) &&
            (candidate.body['membershipIntents'] as List).any(
              (intent) =>
                  intent['accountId'] == recipient.creator.accountId &&
                  intent['invitationId'] == id &&
                  intent['acceptanceProofHash'] == acceptanceHash,
            );
        Future<void> freshBoundary() => access.withVerifiedOperation(() async {
          await guard(recipient);
          await access.account.directory.requireFresh();
          final updatedRights = await foregroundInvitationRights(
            original,
            accountId: recipient.creator.accountId,
          );
          if (!samePreauthorizationValue(rights, updatedRights)) {
            throw const CryptoAuthorityPending(
              'crypto_invitation_auto_policy_changed',
            );
          }
          final parent = await access.currentHead(scope, online: true);
          if (row['state'] == 'invitationForegroundApprovalComplete' &&
              !exactMembership(parent)) {
            throw const CryptoAuthorityPending(
              'crypto_invitation_auto_membership_changed',
            );
          }
          if (parent.members.any(
            (m) => m['accountId'] == recipient.creator.accountId,
          )) {
            final directory = await access.currentMemberDirectory(
              scope,
              parent.headHash,
              recipient.creator.accountId,
            );
            if (directory.rootFingerprint !=
                    recipient.creator.rootFingerprint ||
                directory.deviceSnapshotHash !=
                    recipient.creator.deviceSnapshotHash) {
              throw const CryptoAuthorityPending(
                'invitation_acceptance_changed',
              );
            }
          } else {
            await guard(
              await acceptedRecipient(
                scope,
                id,
                acceptanceProofHash: acceptanceHash,
              ),
            );
          }
          await guard(recipient);
        }, freshBoundary: true);
        await guard(recipient);
        final already = (head.body['membershipIntents'] as List).any(
          (v) =>
              v['accountId'] == recipient.creator.accountId &&
              v['invitationId'] == id &&
              v['acceptanceProofHash'] == acceptanceHash,
        );
        if (row['state'] == 'invitationForegroundApprovalComplete') {
          // A local completion marker alone is not proof. Recheck the exact
          // signed acceptance, live membership intent, rights and directory.
          if (!already) {
            throw const CryptoAuthorityPending(
              'crypto_invitation_auto_membership_changed',
            );
          }
          await freshBoundary();
          _foregroundGuard(current);
          completed++;
          continue;
        }
        if (already) {
          await manager.reconcileAppliedRotation(
            scopeId: scope,
            reviewId: saved['reviewId'],
            headHash: head.headHash,
            beforeDisclosure: () => guard(recipient),
          );
          await ScopeCryptoManager.foregroundInvitationOperation(
            id,
            () async {
              await CryptoInheritedInvitationGrants(access).finish(
                scope,
                id,
                verifiedHistoryOnly: true,
                freshDisclosureBoundary: freshBoundary,
                beforeDisclosure: () => guard(recipient),
              );
            },
            isForegroundCurrent: () =>
                current() && access.account.directory.isCurrent(),
          );
        } else {
          if (state == 'consumed' ||
              head.members.any(
                (m) => m['accountId'] == recipient.creator.accountId,
              )) {
            throw const CryptoAuthorityPending(
              'crypto_invitation_auto_membership_changed',
            );
          }
          final reviews = await manager.pendingRotationReviews(scope);
          var review = reviews
              .where((r) => r.id == saved['reviewId'])
              .firstOrNull;
          if (review == null) {
            final existing = await store.database.rows(
              'SELECT state FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
              [store.partition, scope, saved['reviewId']],
            );
            if (existing.isNotEmpty) {
              throw const CryptoAuthorityPending(
                'scope_review_confirmation_required',
              );
            }
            review = await manager.reviewRotation(
              scope,
              fixedReviewId: saved['reviewId'],
            );
          }
          if (review.historyBasis != 'verifiedCheckpoint') {
            throw const CryptoAuthorityPending(
              'scope_review_confirmation_required',
            );
          }
          await guard(recipient);
          final exactReview = review;
          await ScopeCryptoManager.foregroundInvitationOperation(
            id,
            () async {
              await admit(
                recipient,
                exactReview,
                beforeDisclosure: guard,
                freshDisclosureBoundary: freshBoundary,
              );
            },
            isForegroundCurrent: () =>
                current() && access.account.directory.isCurrent(),
          );
        }
        _foregroundGuard(current);
        await store.database.execute(
          "UPDATE crypto_membership_intents SET state='invitationForegroundApprovalComplete' WHERE partition=? AND scope_id=? AND intent_id=?",
          [store.partition, scope, row['intent_id']],
        );
        completed++;
      } catch (error) {
        final code = safeForegroundInvitationApprovalReason(error);
        pending.add(ForegroundInvitationApprovalPending(scope, id, code));
      } finally {
        // Fair bounded backlog on later foreground events. Exact inbox hints
        // bypass older waiting Sends without granting them any authority.
        saved['lastExamined'] = DateTime.now().toUtc().microsecondsSinceEpoch;
        await store.database.execute(
          "UPDATE crypto_membership_intents SET payload=? WHERE partition=? AND scope_id=? AND intent_id=? AND state='invitationForegroundApproval'",
          [CryptoJson.encode(saved), store.partition, scope, row['intent_id']],
        );
      }
    }
    return ForegroundInvitationApprovalSummary(
      completed: completed,
      examined: rows.length,
      invitations: List.unmodifiable(pending),
    );
  }
}
