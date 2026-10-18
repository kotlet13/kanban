import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import '../collaboration_transport.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_manager.dart';
import 'session_crypto_access.dart';
import 'crypto_scope_observations.dart';
import 'crypto_directory_promotion.dart';
import 'crypto_legacy_invitation_capsule.dart';
import 'crypto_legacy_invitation_evidence.dart';
import 'crypto_directory_consistency.dart';

class VerifiedCryptoInvitation {
  VerifiedCryptoInvitation(
    this.response,
    this.creator,
    this.entries, {
    this.legacyEvidence,
  });
  final Map<String, dynamic> response;
  final VerifiedAccountDirectory creator;
  final List<Map<String, dynamic>> entries;
  final VerifiedCryptoLegacyInvitationEvidence? legacyEvidence;
  Map<String, dynamic> get invitation =>
      Map<String, dynamic>.from(response['invitation'] as Map);
  Map<String, dynamic> get authorization =>
      Map<String, dynamic>.from(response['creatorAuthorization'] as Map);
}

/// Recipient acceptance is an intent only. It never installs an unsigned SQL
/// membership or exposes business records before the signed head activates.
class InviteCryptoRepository {
  InviteCryptoRepository(this.access);
  final SessionCryptoAccess access;
  ScopeCryptoManager get manager => ScopeCryptoManager(access);

  Future<void> _promoteDirectory(
    VerifiedAccountDirectory directory,
    List<Map<String, dynamic>> entries, {
    Future<void> Function()? compare,
  }) async {
    final store = access.account.store;
    if (!access.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
    final run = access.account.directory.reducer.crypto.randomId();
    for (final entry in entries) {
      await store.stageReplay(run, directory.accountId, entry);
    }
    try {
      await compare?.call();
      if (!access.account.directory.isCurrent()) {
        throw const CryptoAuthorityPending('crypto_stale_identity');
      }
      // The shared secure-anchor CAS must succeed before any immutable live
      // directory row is installed. A newer fork cannot poison this cache.
      await store.remember(directory, 'verified');
      await finishCryptoDirectoryPromotion(
        store: store,
        reducer: access.account.directory.reducer,
        accountId: directory.accountId,
        serverId: directory.serverId,
        isCurrent: access.account.directory.isCurrent,
      );
    } finally {
      final committed = await store.anchor(directory.accountId);
      if (committed == null ||
          committed['generation'] != directory.generation ||
          committed['headHash'] != directory.headHash ||
          committed['snapshotHash'] != directory.snapshotHash) {
        await store.database.execute(
          'DELETE FROM crypto_directory_replay_staging WHERE partition=? AND run_id=?',
          [store.partition, run],
        );
      }
      // On a secure commit followed by SQL failure, retain the exact verified
      // prefix so the normal promotion journal can finish after restart.
    }
  }

  Future<Map<String, dynamic>> _call(
    String suffix,
    Map<String, dynamic> params,
  ) => access.account.directory.call('crypto2.invitations.$suffix', params);

  Map<String, dynamic> _legacyWire(Map source) {
    final recipient = source['recipient'] as Map;
    return {
      ...Map<String, dynamic>.from(source),
      'expiresAt': source['expiresAtEpoch'],
      'recipientUsername': recipient['kind'] == 'username'
          ? recipient['value']
          : '',
      'recipientEmail': recipient['kind'] == 'email'
          ? recipient['value']
          : null,
      'pendingKeys':
          source['state'] == 'accepted' &&
          source['legacyAcceptedAtEpoch'] == null,
      'revokedAt':
          source['legacyRevokedAtEpoch'] ??
          (source['state'] == 'revoked' ? 0 : null),
      'acceptedAt':
          source['legacyAcceptedAtEpoch'] ??
          (source['state'] == 'consumed' ? 0 : null),
    };
  }

  bool supports(String operation) => RegExp(
    r'^invitations[23]?\.(create|resend|revoke|list|pending)$',
  ).hasMatch(operation);
  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    final kind = operation.split('.').last;
    if (kind == 'pending') {
      return _call('pending', Map<String, dynamic>.from(params));
    }
    if (kind == 'list') {
      final all = <Map<String, dynamic>>[];
      String? after;
      while (true) {
        final page = await _call('list', {
          'scopeId': params['scopeId'],
          'limit': 50,
          if (after != null) 'afterId': after,
        });
        all.addAll(
          (page['invitations'] as List).map((v) => _legacyWire(v as Map)),
        );
        if (page['hasMore'] != true) break;
        final next = page['nextAfterId'];
        if (next is! String || after != null && next.compareTo(after) <= 0) {
          throw const FormatException('invitation_list_cursor');
        }
        after = next;
      }
      return {'invitations': all};
    }
    final scope = params['scopeId'] as String;
    final action =
        params['requestId'] as String? ??
        access.account.directory.reducer.crypto.randomId();
    return manager.serialize(scope, () async {
      final db = access.account.store.database,
          partition = access.account.store.partition;
      final saved = await db.rows(
        'SELECT payload,token FROM crypto_invitation_drafts WHERE partition=? AND action_id=?',
        [partition, action],
      );
      late Map<String, dynamic> payload;
      String? token;
      final op = 'crypto2.invitations.$kind';
      final callerHash = await cryptoSha256(
        CryptoJson.encode({'operation': operation, 'params': params}),
      );
      if (saved.isNotEmpty) {
        final draft = jsonDecode(saved.single['payload'] as String) as Map;
        if (draft['callerHash'] != callerHash) {
          throw const FormatException('invitation_intent_changed');
        }
        payload = Map<String, dynamic>.from(draft['payload'] as Map);
        token = saved.single['token'] as String?;
      } else {
        final own = await access.account.directory.requireFresh();
        final head = await access.currentHead(scope, online: true);
        final actor = head.member(access.account.directory.accountId);
        if (actor['manageKeys'] != true) {
          throw const CryptoAuthorityPending('scope_management_required');
        }
        payload = {
          'scopeId': scope,
          'membershipHeadHash': head.headHash,
          'expectedAccessRevision': head.accessRevision,
          'authorDirectoryHeadHash': own.headHash,
        };
        if (kind == 'revoke') {
          payload['invitationId'] = params['invitationId'];
        } else {
          final replacing = kind == 'resend'
              ? params['invitationId'] as String
              : null;
          Map<String, dynamic> recipient;
          String role = params['role'] as String? ?? 'member';
          if (replacing != null) {
            final listed = await _call('list', {'scopeId': scope, 'limit': 50});
            final old = (listed['invitations'] as List)
                .cast<Map>()
                .where((v) => v['id'] == replacing)
                .firstOrNull;
            if (old == null) {
              throw const CryptoAuthorityPending('invitation_list_pending');
            }
            recipient = Map<String, dynamic>.from(old['recipient'] as Map);
            role = old['role'];
          } else {
            final value =
                params['recipient'] ??
                params['recipientEmail'] ??
                params['recipientUsername'];
            final resolved = await _call('resolve', {
              'scopeId': scope,
              'recipient': value,
            });
            recipient = Map<String, dynamic>.from(resolved['recipient'] as Map);
          }
          final crypto = access.account.directory.reducer.crypto;
          token =
              'fhi4_${crypto.randomId().replaceAll('-', '')}${crypto.randomId().replaceAll('-', '')}';
          payload.addAll({
            'invitationId': crypto.randomId(),
            'recipient': recipient,
            'role': role,
            'expiresAt':
                DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 604700,
            'language': params['language'] ?? 'sl',
            'tokenHash': await cryptoSha256(
              Uint8List.fromList(utf8.encode(token)),
            ),
            if (replacing != null) 'replacesInvitationId': replacing,
          });
        }
        await db.execute(
          'INSERT INTO crypto_invitation_drafts VALUES(?,?,?,?)',
          [
            partition,
            action,
            jsonEncode({'callerHash': callerHash, 'payload': payload}),
            token,
          ],
        );
      }
      final response = await manager.invitationCommand(
        op,
        scope,
        payload,
        actionKey: 'invite:$action',
        deliveryToken:
            token != null && (payload['recipient'] as Map?)?['kind'] == 'email'
            ? token
            : null,
      );
      return {
        ...response,
        if (response['invitation'] is Map)
          'invitation': _legacyWire(response['invitation'] as Map),
        if (token != null) 'localToken': token,
      };
    });
  }

  Future<void> _verifyBoundLegacyRecipient(
    Map<String, dynamic> response,
    Map<String, dynamic> original,
    Map<String, dynamic> bridgeProof,
  ) async {
    final own = await access.account.directory.cachedVerifiedDirectory();
    final proof = Map<String, dynamic>.from(
      response['recipientAcceptanceAuthorization'] as Map? ??
          (throw const CryptoAuthorityPending('invitation_acceptance_pending')),
    );
    final command =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
        p = command['payload'] as Map,
        invitation = response['invitation'] as Map;
    final payloadFields = {
      'scopeId',
      'invitationId',
      'tokenHash',
      'creatorProofHash',
      'role',
      'expiresAt',
      'membershipHeadHash',
      'authorDirectoryHeadHash',
    };
    if (command.length != 8 ||
        !{
          'version',
          'operation',
          'requestId',
          'serverId',
          'accountId',
          'deviceId',
          'signer',
          'payload',
        }.every(command.containsKey) ||
        command['version'] != 2 ||
        command['operation'] != 'crypto2.invitations.accept' ||
        command['signer'] != 'device' ||
        command['serverId'] != own.serverId ||
        command['accountId'] != own.accountId ||
        invitation['recipient']['accountId'] != own.accountId ||
        original['kind'] != 'email' ||
        original['value'] != invitation['recipient']['value'] ||
        p.length != payloadFields.length ||
        !payloadFields.every(p.containsKey) ||
        p['scopeId'] != invitation['scopeId'] ||
        p['invitationId'] != invitation['id'] ||
        p['tokenHash'] != invitation['tokenHash'] ||
        p['membershipHeadHash'] !=
            (CryptoJson.decode(cryptoBase64(bridgeProof['commandBase64']))
                as Map)['payload']['context']['membershipHeadHash'] ||
        p['creatorProofHash'] !=
            await cryptoSha256(CryptoJson.encode(bridgeProof)) ||
        p['role'] != invitation['role'] ||
        p['expiresAt'] != invitation['expiresAtEpoch']) {
      throw const FormatException('crypto_invitation_recipient_acceptance');
    }
    VerifiedAccountDirectory? state;
    String? genesis;
    var count = 0;
    await for (final entry in access.account.store.streamEntries(
      own.accountId,
    )) {
      if (++count > 100000) {
        throw const CryptoAuthorityPending('invitation_acceptance_pending');
      }
      if (genesis == null) {
        final first =
            CryptoJson.decode(
                  cryptoBase64(
                    (entry['authorization'] as Map)['commandBase64'],
                  ),
                )
                as Map;
        genesis = access.account.directory.reducer.crypto.fingerprint(
          cryptoBase64(first['payload']['rootSigningKeyBase64'], length: 32),
          cryptoBase64(first['payload']['rootEncryptionKeyBase64'], length: 32),
        );
      }
      state = await access.account.directory.reducer.apply(
        previous: state,
        entry: entry,
        serverId: own.serverId,
        accountId: own.accountId,
        pinnedRootFingerprint: genesis,
      );
      if (state.headHash == p['authorDirectoryHeadHash']) break;
    }
    if (state == null ||
        state.headHash != p['authorDirectoryHeadHash'] ||
        !own.includesAnchor(state.generation, state.headHash)) {
      throw const CryptoAuthorityPending('invitation_acceptance_pending');
    }
    final actor = state.activeDevice(command['deviceId']);
    access.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(actor['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    await requireKnownDirectoryPrefix(
      directory: access.account.directory,
      store: access.account.store,
      prefix: state,
    );
  }

  Future<VerifiedCryptoInvitation> inspect({
    String? token,
    String? invitationId,
  }) async {
    if ((token == null) == (invitationId == null)) {
      throw const FormatException('invitation_identifier');
    }
    final params = <String, dynamic>{
      if (token != null) 'token': token,
      if (invitationId != null) 'invitationId': invitationId,
    };
    final response = await _call('preview', params);
    final proof = Map<String, dynamic>.from(
      response['creatorAuthorization'] as Map,
    );
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final p = command['payload'] as Map;
    final legacyBridge =
        command['operation'] == 'crypto2.invitations.bridgeLegacy';
    if (command['version'] != 2 ||
        command['serverId'] !=
            access.account.directory.session.profile.serverId ||
        (!legacyBridge &&
            (![
                  'crypto2.invitations.create',
                  'crypto2.invitations.resend',
                ].contains(command['operation']) ||
                p['invitationId'] != response['invitation']['id'] ||
                p['scopeId'] != response['scope']['id'] ||
                p['tokenHash'] != response['invitation']['tokenHash'])) ||
        token != null &&
            response['invitation']['tokenHash'] !=
                await cryptoSha256(utf8.encode(token))) {
      throw const FormatException('invitation_proof_binding');
    }
    final requiredPrefixes = <String>{p['authorDirectoryHeadHash']};
    if (legacyBridge) {
      final bridge = response['legacyBridge'] as Map;
      final cert =
          CryptoJson.decode(
                cryptoBase64(
                  bridge['certificateAuthorization']['commandBase64'],
                ),
              )
              as Map;
      requiredPrefixes.add(
        cert['payload']['header']['authorDirectoryHeadHash'],
      );
      requiredPrefixes.add(bridge['eventHeadHash']);
      if (bridge['cutover'] is Map) {
        final headCommand =
            CryptoJson.decode(
                  cryptoBase64(
                    bridge['cutover']['membershipAuthorization']['commandBase64'],
                  ),
                )
                as Map;
        requiredPrefixes.add(headCommand['payload']['authorDirectoryHeadHash']);
      }
    }
    final prefixes = <String, VerifiedAccountDirectory>{};
    final entries = <Map<String, dynamic>>[];
    VerifiedAccountDirectory? state;
    String? genesis;
    var page = Map<String, dynamic>.from(response['creatorDirectory'] as Map);
    var after = 0;
    while (true) {
      if (page['entries'] is! List ||
          (page['entries'] as List).isEmpty ||
          (page['entries'] as List).length > 50) {
        throw const FormatException('invitation_directory_page');
      }
      for (final value in page['entries'] as List) {
        final entry = Map<String, dynamic>.from(value as Map);
        if (genesis == null) {
          final first =
              CryptoJson.decode(
                    cryptoBase64(
                      (entry['authorization'] as Map)['commandBase64'],
                    ),
                  )
                  as Map;
          genesis = access.account.directory.reducer.crypto.fingerprint(
            cryptoBase64(first['payload']['rootSigningKeyBase64'], length: 32),
            cryptoBase64(
              first['payload']['rootEncryptionKeyBase64'],
              length: 32,
            ),
          );
        }
        state = await access.account.directory.reducer.apply(
          previous: state,
          entry: entry,
          serverId: command['serverId'],
          accountId: command['accountId'],
          pinnedRootFingerprint: genesis,
        );
        entries.add(entry);
        if (requiredPrefixes.contains(state.headHash)) {
          prefixes[state.headHash] = state;
        }
        after = state.generation;
      }
      if (page['hasMore'] != true) break;
      if (page['nextGeneration'] != after) {
        throw const FormatException('invitation_directory_cursor');
      }
      page = await _call('directory', {
        ...params,
        'afterGeneration': after,
        'limit': 50,
      });
    }
    if ((!legacyBridge && state!.headHash != p['authorDirectoryHeadHash']) ||
        state!.headHash != page['headHash'] ||
        state.generation != page['generation'] ||
        state.snapshotHash != page['snapshotHash']) {
      throw const FormatException('invitation_directory_head');
    }
    if (legacyBridge) {
      final verified = await verifyCryptoLegacyInvitationEvidence(
        capsules: CryptoLegacyInvitationCapsule(
          access.account.directory.reducer.crypto,
        ),
        proof: proof,
        evidence: Map<String, dynamic>.from(response['legacyBridge'] as Map),
        invitation: Map<String, dynamic>.from(response['invitation'] as Map),
        creator: state,
        directoryAt: (ref) async =>
            prefixes[ref] ??
            (throw const FormatException('crypto_invitation_bridge_directory')),
        digestPage: (after) => _call('bridgeDigests', {
          ...params,
          if (after != null) 'afterHash': after,
          'limit': 20,
        }),
        activationDirectoryPage: (after) => _call('directory', {
          ...params,
          'bridgeActivation': true,
          'afterGeneration': after,
          'limit': 50,
        }),
        requireKnownPrefix: (prefix) => requireKnownDirectoryPrefix(
          directory: access.account.directory,
          store: access.account.store,
          prefix: prefix,
        ),
        verifyRecipientBinding: (original) =>
            _verifyBoundLegacyRecipient(response, original, proof),
        token: token,
      );
      return VerifiedCryptoInvitation(
        {...response, 'legacyAcceptancePayload': verified.acceptancePayload},
        state,
        entries,
        legacyEvidence: verified,
      );
    }
    final actor = state.activeDevice(command['deviceId']);
    access.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(actor['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    return VerifiedCryptoInvitation(response, state, entries);
  }

  Future<VerifiedCryptoInvitation> acceptedRecipient(
    String scopeId,
    String invitationId,
  ) async {
    final response = await _call('acceptance', {
      'scopeId': scopeId,
      'invitationId': invitationId,
      'limit': 50,
    });
    final proof = Map<String, dynamic>.from(response['authorization'] as Map);
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    if (raw['version'] != 2 ||
        raw['operation'] != 'crypto2.invitations.accept' ||
        raw['serverId'] != access.account.directory.session.profile.serverId ||
        raw['payload']['scopeId'] != scopeId ||
        raw['payload']['invitationId'] != invitationId ||
        response['acceptanceProofHash'] !=
            await cryptoSha256(CryptoJson.encode(proof))) {
      throw const FormatException('invitation_acceptance_binding');
    }
    var page = Map<String, dynamic>.from(response['recipientDirectory'] as Map);
    VerifiedAccountDirectory? state;
    final entries = <Map<String, dynamic>>[];
    String? genesis;
    var after = 0;
    while (true) {
      if (page['entries'] is! List ||
          (page['entries'] as List).isEmpty ||
          (page['entries'] as List).length > 50) {
        throw const FormatException('invitation_directory_page');
      }
      for (final value in page['entries'] as List) {
        final entry = Map<String, dynamic>.from(value as Map);
        if (genesis == null) {
          final first =
              CryptoJson.decode(
                    cryptoBase64(
                      (entry['authorization'] as Map)['commandBase64'],
                    ),
                  )
                  as Map;
          genesis = access.account.directory.reducer.crypto.fingerprint(
            cryptoBase64(first['payload']['rootSigningKeyBase64'], length: 32),
            cryptoBase64(
              first['payload']['rootEncryptionKeyBase64'],
              length: 32,
            ),
          );
        }
        state = await access.account.directory.reducer.apply(
          previous: state,
          entry: entry,
          serverId: raw['serverId'],
          accountId: raw['accountId'],
          pinnedRootFingerprint: genesis,
        );
        entries.add(entry);
        after = state.generation;
      }
      if (page['hasMore'] != true) break;
      if (page['nextGeneration'] != after) {
        throw const FormatException('invitation_directory_cursor');
      }
      final next = await _call('acceptance', {
        'scopeId': scopeId,
        'invitationId': invitationId,
        'acceptanceProofHash': response['acceptanceProofHash'],
        'afterGeneration': after,
        'limit': 50,
      });
      if (next['acceptanceProofHash'] != response['acceptanceProofHash']) {
        throw const FormatException('invitation_acceptance_changed');
      }
      page = Map<String, dynamic>.from(next['recipientDirectory'] as Map);
    }
    if (state!.headHash != page['headHash'] ||
        state.generation != page['generation'] ||
        state.snapshotHash != page['snapshotHash']) {
      throw const FormatException('invitation_directory_head');
    }
    final device = state.activeDevice(raw['deviceId']);
    access.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    return VerifiedCryptoInvitation(
      {
        'invitation': {'id': invitationId, 'scopeId': scopeId},
        'creatorAuthorization': proof,
        'acceptanceProofHash': response['acceptanceProofHash'],
        'proposedMember': response['proposedMember'],
      },
      state,
      entries,
    );
  }

  Future<void> admit(
    VerifiedCryptoInvitation recipient,
    ScopeRotationReview reviewedInventory,
  ) async {
    final directory = recipient.creator;
    await access.identities.requireVerified(
      directory.accountId,
      access.identities.fingerprint(directory),
    );
    final fresh = await acceptedRecipient(
      reviewedInventory.scopeId,
      recipient.invitation['id'],
    );
    if (fresh.creator.deviceSnapshotHash != directory.deviceSnapshotHash ||
        fresh.response['acceptanceProofHash'] !=
            recipient.response['acceptanceProofHash']) {
      throw const CryptoAuthorityPending('invitation_acceptance_changed');
    }
    final command =
        CryptoJson.decode(cryptoBase64(fresh.authorization['commandBase64']))
            as Map;
    final source = await access.recoveryCandidateHead(
      reviewedInventory.scopeId,
    );
    final proposed = Map<String, dynamic>.from(
      fresh.response['proposedMember'] as Map,
    );
    if (proposed['accountId'] != directory.accountId ||
        proposed['role'] != command['payload']['role'] ||
        !['none', 'read', 'write'].contains(proposed['financeRole']) ||
        proposed['manageKeys'] is! bool) {
      throw const FormatException('invitation_proposed_member');
    }
    final members = [...source.members, proposed]
      ..sort(
        (a, b) =>
            (a['accountId'] as String).compareTo(b['accountId'] as String),
      );
    final intents = <Map<String, dynamic>>[
      {
        'accountId': directory.accountId,
        'invitationId': recipient.invitation['id'],
        'acceptanceProofHash': fresh.response['acceptanceProofHash'],
      },
    ];
    await manager.confirmRotation(
      reviewedInventory,
      acceptedCandidateHistory: true,
      members: members,
      membershipIntents: intents,
      joiningDirectory: (id) async {
        final checked = await acceptedRecipient(
          reviewedInventory.scopeId,
          recipient.invitation['id'],
        );
        await access.identities.requireVerified(
          id,
          access.identities.fingerprint(checked.creator),
        );
        await _promoteDirectory(checked.creator, checked.entries);
        return checked.creator;
      },
    );
  }

  Future<void> compareCreator(
    VerifiedCryptoInvitation invite,
    String externalCard,
  ) async {
    final card = CryptoJson.decode(
      Uint8List.fromList(utf8.encode(externalCard)),
    );
    if (card is! Map ||
        card.length != 7 ||
        card['version'] != 2 ||
        card['purpose'] != 'identityVerification' ||
        card['serverId'] != invite.creator.serverId ||
        card['accountId'] != invite.creator.accountId ||
        card['generation'] != invite.creator.generation ||
        card['headHash'] != invite.creator.headHash ||
        card['safetyCode'] is! String) {
      throw const FormatException('identity_card_mismatch');
    }
    final externalSafetyCode = card['safetyCode'] as String;
    await _promoteDirectory(
      invite.creator,
      invite.entries,
      compare: () => access.identities.compareAndPin(
        directory: invite.creator,
        externallyComparedSafetyCode: externalSafetyCode,
        externallyComparedGeneration: invite.creator.generation,
        externallyComparedHeadHash: invite.creator.headHash,
      ),
    );
  }

  Future<String?> resumeAccepted(String invitationId) async {
    late Map<String, dynamic> status;
    try {
      status = await _call('status', {'invitationId': invitationId});
    } on CollaborationApiException catch (error) {
      if (error.code == 'invitation_invalid') return null;
      rethrow;
    }
    if (status['state'] != 'consumed') return null;
    final scopeId = status['scope']['id'] as String;
    final stored = await access.account.store.database.rows(
      "SELECT authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state IN ('invitationPendingAnchor','invitationScopeAnchor')",
      [access.account.store.partition, scopeId, invitationId],
    );
    if (stored.length != 1) {
      throw const CryptoAuthorityPending('invitation_proof_pending');
    }
    final anchor =
        CryptoJson.decode(
              Uint8List.fromList(
                (stored.single['authorization'] as List).cast<int>(),
              ),
            )
            as Map<String, dynamic>;
    final scoped = SessionCryptoAccess(
      account: access.account,
      invitationAnchor: anchor,
    );
    final current = await scoped.currentHead(scopeId, online: true);
    current.member(access.account.directory.accountId);
    final activated = scoped.verifiedCandidateAncestor(
      status['activatedHeadHash'],
    );
    final own = (activated.body['membershipIntents'] as List).where(
      (i) =>
          i['accountId'] == access.account.directory.accountId &&
          i['invitationId'] == invitationId &&
          i['acceptanceProofHash'] == status['acceptanceProofHash'],
    );
    if (own.length != 1) {
      throw const FormatException('invitation_activation_substitution');
    }
    await scoped.hydrateScopeKeys(scopeId);
    await CryptoScopeObservations(access.account).observe(scoped, scopeId);
    await access.account.store.database.execute(
      "UPDATE crypto_membership_intents SET state='invitationScopeAnchor' WHERE partition=? AND scope_id=? AND intent_id=?",
      [access.account.store.partition, scopeId, invitationId],
    );
    return scopeId;
  }

  Future<Map<String, dynamic>> accept(
    VerifiedCryptoInvitation invite, {
    required String actionId,
  }) async {
    if (invite.response['legacyAcceptancePayload'] != null &&
        invite.legacyEvidence == null) {
      throw const CryptoAuthorityPending(
        'crypto_invitation_bridge_cutover_pending',
      );
    }
    if (invite.legacyEvidence != null &&
        (invite.legacyEvidence!.creatorAccountId != invite.creator.accountId ||
            invite.legacyEvidence!.creatorProofHash !=
                await cryptoSha256(CryptoJson.encode(invite.authorization)))) {
      throw const FormatException('crypto_invitation_bridge_binding');
    }
    final own = await access.account.directory.requireFresh();
    await access.identities.requireVerified(
      invite.creator.accountId,
      access.identities.fingerprint(invite.creator),
    );
    final command =
        CryptoJson.decode(cryptoBase64(invite.authorization['commandBase64']))
            as Map;
    final p =
        invite.legacyEvidence?.acceptancePayload ?? command['payload'] as Map;
    var payload = <String, dynamic>{
      'scopeId': p['scopeId'],
      'invitationId': p['invitationId'],
      'tokenHash': p['tokenHash'],
      'creatorProofHash': await cryptoSha256(
        CryptoJson.encode(invite.authorization),
      ),
      'role': p['role'],
      'expiresAt': p['expiresAt'],
      'membershipHeadHash': p['membershipHeadHash'],
      'authorDirectoryHeadHash': own.headHash,
    };
    await access.account.store.database.execute(
      'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?) ON CONFLICT(partition,scope_id,intent_id) DO NOTHING',
      [
        access.account.store.partition,
        p['scopeId'],
        p['invitationId'],
        'invitationPendingAnchor',
        CryptoJson.encode({
          'creatorProofHash': payload['creatorProofHash'],
          if (invite.response['legacyBridge'] != null)
            'legacyBridge': invite.response['legacyBridge'],
          if (invite.response['legacyAcceptancePayload'] != null)
            'legacyAcceptancePayload':
                invite.response['legacyAcceptancePayload'],
        }),
        CryptoJson.encode(invite.authorization),
      ],
    );
    final key = 'accept:$actionId';
    final saved = await access.account.store.database.rows(
      'SELECT payload FROM crypto_invitation_drafts WHERE partition=? AND action_id=?',
      [access.account.store.partition, key],
    );
    if (saved.isNotEmpty) {
      payload = Map<String, dynamic>.from(
        jsonDecode(saved.single['payload'] as String) as Map,
      );
      if (payload['creatorProofHash'] !=
          await cryptoSha256(CryptoJson.encode(invite.authorization))) {
        throw const FormatException('invitation_acceptance_changed');
      }
    } else {
      await access.account.store.database.execute(
        'INSERT INTO crypto_invitation_drafts VALUES(?,?,?,NULL)',
        [access.account.store.partition, key, jsonEncode(payload)],
      );
    }
    return manager.serialize(
      p['scopeId'],
      () => manager.invitationCommand(
        'crypto2.invitations.accept',
        p['scopeId'],
        payload,
        actionKey: 'accept:$actionId',
      ),
    );
  }
}
