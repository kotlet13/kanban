part of 'invite_crypto_repository.dart';

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
    this.invitations = const [],
  });
  final int completed;
  final List<ForegroundInvitationApprovalPending> invitations;
  int get pending => invitations.length;
}

final _foregroundInvitationRuns =
    <String, Future<ForegroundInvitationApprovalSummary>>{};

extension ForegroundInvitationApproval on InviteCryptoRepository {
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
  }) async {
    _foregroundGuard(isForegroundCurrent);
    final partition = access.account.store.partition;
    // A second account/device caller must never inherit another foreground
    // capability. It may ask for a later sweep after this run completes.
    if (_foregroundInvitationRuns.containsKey(partition)) {
      return const ForegroundInvitationApprovalSummary();
    }
    final task = _processForegroundApprovals(
      isForegroundCurrent,
      invitationIds,
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
    Set<String> invitationIds,
  ) async {
    final store = access.account.store,
        session = access.account.directory.session.profile;
    if (invitationIds.length > 100 ||
        invitationIds.any((id) => !isCryptoCanonicalUuid(id))) {
      throw const FormatException('crypto_invitation_auto_hint');
    }
    final hints = invitationIds.isEmpty
        ? ''
        : " AND intent_id IN (${List.filled(invitationIds.length, '?').join(',')})";
    final rows = await store.database.rows(
      "SELECT scope_id,intent_id,payload FROM crypto_membership_intents WHERE partition=? AND state='invitationForegroundApproval'$hints ORDER BY COALESCE(json_extract(CAST(payload AS TEXT),'\$.lastExamined'),0),scope_id,intent_id LIMIT 100",
      [store.partition, ...invitationIds.map((id) => 'autoInvitation:$id')],
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
          await store.database.execute(
            "UPDATE crypto_membership_intents SET state='invitationForegroundApprovalClosed' WHERE partition=? AND scope_id=? AND intent_id=?",
            [store.partition, scope, row['intent_id']],
          );
          continue;
        }
        if (state != 'accepted' && state != 'consumed') continue;
        final head = await access.currentHead(scope, online: true);
        final recipient = state == 'consumed'
            ? await _retainedConsumedRecipient(saved, scope, id, head)
            : await acceptedRecipient(
                scope,
                id,
                acceptanceProofHash: saved['acceptanceProofHash'],
              );
        final acceptanceHash = recipient.response['acceptanceProofHash'];
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
        final code = error is CryptoAuthorityPending
            ? error.reason
            : error is CollaborationApiException
            ? error.code
            : error is FormatException
            ? error.message
            : 'invitation_approval_pending';
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
      invitations: List.unmodifiable(pending),
    );
  }
}
