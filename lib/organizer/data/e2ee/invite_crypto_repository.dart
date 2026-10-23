import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import '../collaboration_transport.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart' show isCryptoCanonicalUuid;
import 'crypto_sync_repository.dart';
import 'scope_crypto_manager.dart';
import 'session_crypto_access.dart';
import 'crypto_scope_observations.dart';
import 'crypto_directory_promotion.dart';
import 'crypto_legacy_invitation_capsule.dart';
import 'crypto_legacy_invitation_evidence.dart';
import 'crypto_directory_consistency.dart';
import 'crypto_inherited_invitation_grants.dart';
import 'crypto_preauthorized_invitation.dart';
import 'crypto_invitation_preauthorization_codec.dart';
import 'scope_crypto_codec.dart';

part 'crypto_invitation_autoapproval.dart';

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

class _PreauthorizedRecipient {
  _PreauthorizedRecipient(
    this.recipient,
    this.preauthorization,
    this.directory,
  );
  final Map<String, dynamic> recipient, preauthorization;
  final VerifiedAccountDirectory directory;
}

class _RetainedPreauthorizationAction {
  _RetainedPreauthorizationAction(
    this.action,
    this.state,
    this.payload,
    this.publicationPending,
  );
  final String action, state;
  final Map<String, dynamic> payload;
  final bool publicationPending;
}

/// Legacy acceptance records an intent. Preauthorized Send installs the exact
/// signed roster and sealed grants before recipient consent opens SQL access.
class InviteCryptoRepository {
  InviteCryptoRepository(this.access);
  final SessionCryptoAccess access;
  ScopeCryptoManager get manager => ScopeCryptoManager(access);

  Future<Map<String, dynamic>> foregroundInvitationRights(
    Map<String, dynamic> payload, {
    String? accountId,
  }) async {
    final descriptor = await access.verifiedScopeDescriptor(
      payload['scopeId'],
      online: true,
    );
    return projectedInvitationRights(
      access: access,
      scopeId: payload['scopeId'],
      policyVersion: descriptor['accessPolicyVersion'],
      role: payload['role'],
      accountId: accountId,
    );
  }

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
      final known = await store.anchor(directory.accountId);
      if (compare != null &&
          known != null &&
          (known['generation'] as int) > directory.generation &&
          known['fingerprint'] == directory.rootFingerprint) {
        // Hosting verification has reconnected this historical invitation
        // prefix to the newer secure head; keep that stronger anchor intact.
        return;
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
    var action =
        params['requestId'] as String? ??
        access.account.directory.reducer.crypto.randomId();
    final created = await manager.serialize(scope, () async {
      final db = access.account.store.database,
          partition = access.account.store.partition;
      var saved = await db.rows(
        'SELECT payload,token FROM crypto_invitation_drafts WHERE partition=? AND action_id=?',
        [partition, action],
      );
      var resumedAuthorizedDraft = false;
      if (saved.isEmpty && (kind == 'create' || kind == 'resend')) {
        final retained = await _unfinishedPreauthorizationAction(
          kind,
          scope,
          params,
        );
        if (retained != null) {
          action = retained;
          resumedAuthorizedDraft = true;
          saved = await db.rows(
            'SELECT payload,token FROM crypto_invitation_drafts WHERE partition=? AND action_id=?',
            [partition, action],
          );
        }
      }
      late Map<String, dynamic> payload;
      String? token;
      final op = 'crypto2.invitations.$kind';
      final callerHash = await cryptoSha256(
        CryptoJson.encode({'operation': operation, 'params': params}),
      );
      if (saved.isNotEmpty) {
        final draft = jsonDecode(saved.single['payload'] as String) as Map;
        if (!resumedAuthorizedDraft && draft['callerHash'] != callerHash) {
          throw const FormatException('invitation_intent_changed');
        }
        payload = Map<String, dynamic>.from(draft['payload'] as Map);
        token = saved.single['token'] as String?;
      } else {
        Map<String, dynamic>? foregroundIntent;
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
          var unregistered = false;
          if (!payload.containsKey('preauthorization')) {
            final resolved = await _resolvePreauthorized(
              scope,
              recipient['value'] as String,
              role,
              onUnregistered: () => unregistered = true,
            );
            if (resolved != null) {
              recipient = resolved.recipient;
              payload['preauthorization'] = resolved.preauthorization;
            }
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
          if (unregistered && recipient['kind'] == 'email') {
            foregroundIntent = await _prepareForegroundApproval(
              action,
              payload,
            );
          }
        }
        await db.transaction(() async {
          await db.execute(
            'INSERT INTO crypto_invitation_drafts VALUES(?,?,?,?)',
            [
              partition,
              action,
              jsonEncode({'callerHash': callerHash, 'payload': payload}),
              token,
            ],
          );
          if (foregroundIntent != null) {
            await db.execute(
              'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
              [
                partition,
                scope,
                'autoInvitation:${payload['invitationId']}',
                'invitationForegroundApproval',
                CryptoJson.encode(foregroundIntent),
              ],
            );
          }
        });
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
    // The scope manager queue is deliberately not reentrant. Rotation starts
    // only after exact invitation creation has left that queue.
    final authorization = created['authorization'];
    if (authorization is Map) {
      final command =
          CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
              as Map;
      if ((command['payload'] as Map)['preauthorization'] != null) {
        return _completePreauthorization(
          created,
          Map<String, dynamic>.from(authorization),
        );
      }
    }
    return created;
  }

  /// A new form request after restart may continue only an unfinished Send
  /// whose immutable signed meaning is the same. Completed/manual invitations
  /// never enter this path, and the original action, token and proof survive.
  Future<String?> _unfinishedPreauthorizationAction(
    String kind,
    String scope,
    Map<String, Object?> params,
  ) async {
    final recipient =
        params['recipient'] ??
        params['recipientEmail'] ??
        params['recipientUsername'];
    if (kind == 'create' && recipient is! String) return null;
    final language = params['language'] ?? 'sl';
    final role = params['role'] ?? 'member';
    final replacing = kind == 'resend' ? params['invitationId'] : null;
    final rows = await access.account.store.database.rows(
      '''SELECT d.action_id,d.payload,i.authorization,i.intent_id,i.state
         FROM crypto_invitation_drafts d
         JOIN crypto_membership_action_keys a
           ON a.partition=d.partition AND a.action_key='invite:'||d.action_id
         JOIN crypto_membership_intents i
           ON i.partition=a.partition AND i.scope_id=a.scope_id
          AND i.intent_id=a.request_id
         WHERE d.partition=? AND i.scope_id=? AND i.state IN ('pending','confirmed')
           AND json_extract(d.payload,'\$.payload.preauthorization.version')=1
           AND json_extract(d.payload,'\$.payload.expiresAt')>?
           AND json_extract(d.payload,'\$.payload.language')=?
           AND ${kind == 'create' ? "json_extract(d.payload,'\$.payload.replacesInvitationId') IS NULL AND lower(json_extract(d.payload,'\$.payload.recipient.value'))=? AND json_extract(d.payload,'\$.payload.role')=?" : "json_extract(d.payload,'\$.payload.replacesInvitationId')=?"}
           AND NOT EXISTS (
             SELECT 1 FROM crypto_membership_action_keys p
             JOIN crypto_membership_intents publication
               ON publication.partition=p.partition
              AND publication.scope_id=p.scope_id
              AND publication.intent_id=p.request_id
             WHERE p.partition=d.partition AND p.scope_id=i.scope_id
               AND p.action_key='preauthorize-publish:'||json_extract(d.payload,'\$.payload.invitationId')
               AND publication.state IN ('confirmed','rejected'))
         ORDER BY d.rowid DESC LIMIT 33''',
      [
        access.account.store.partition,
        scope,
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        language,
        if (kind == 'create') ...[
          (recipient as String).trim().toLowerCase(),
          role,
        ] else
          replacing,
      ],
    );
    if (rows.length > 32) {
      throw const CryptoAuthorityPending(
        'invitation_preparation_review_required',
      );
    }
    if (rows.isEmpty) return null;
    final candidates = <_RetainedPreauthorizationAction>[];
    for (final row in rows) {
      final draft = jsonDecode(row['payload'] as String) as Map;
      final payload = Map<String, dynamic>.from(draft['payload'] as Map);
      final proof = Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList((row['authorization'] as List).cast<int>()),
            )
            as Map,
      );
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      if (command['operation'] != 'crypto2.invitations.$kind' ||
          command['version'] != 2 ||
          command['signer'] != 'device' ||
          command['requestId'] != row['intent_id'] ||
          payload['scopeId'] != scope ||
          command['serverId'] !=
              access.account.directory.session.profile.serverId ||
          command['accountId'] != access.account.directory.accountId ||
          command['deviceId'] != access.account.deviceId ||
          !samePreauthorizationValue(command['payload'], payload)) {
        throw const FormatException(
          'invitation_preparation_draft_substitution',
        );
      }
      final publication = await access.account.store.database.rows(
        '''SELECT i.state FROM crypto_membership_action_keys a
           JOIN crypto_membership_intents i
             ON i.partition=a.partition AND i.scope_id=a.scope_id
            AND i.intent_id=a.request_id
           WHERE a.partition=? AND a.scope_id=? AND a.action_key=?''',
        [
          access.account.store.partition,
          scope,
          'preauthorize-publish:${payload['invitationId']}',
        ],
      );
      candidates.add(
        _RetainedPreauthorizationAction(
          row['action_id'] as String,
          row['state'] as String,
          payload,
          publication.isNotEmpty && publication.single['state'] == 'pending',
        ),
      );
    }
    // Classify every candidate without replaying any request. An ambiguous
    // unknown create must not transmit several old actions before rejection.
    final pendingIds = candidates.map((c) => c.payload['invitationId']).toSet();
    final invitations = <String, Map<String, dynamic>>{};
    String? after;
    var complete = false;
    for (var page = 0; page < 20; page++) {
      final response = await _call('list', {
        'scopeId': scope,
        'limit': 50,
        if (after != null) 'afterId': after,
      });
      if (response['invitations'] is! List ||
          (response['invitations'] as List).length > 50 ||
          response['hasMore'] is! bool) {
        throw const FormatException('invitation_list_page');
      }
      for (final raw in response['invitations'] as List) {
        if (raw is! Map || !isCryptoCanonicalUuid(raw['id'])) {
          throw const FormatException('invitation_list_page');
        }
        final id = raw['id'] as String;
        if (pendingIds.remove(id)) {
          invitations[id] = Map<String, dynamic>.from(raw);
        }
      }
      complete = response['hasMore'] == false;
      if (complete || pendingIds.isEmpty) break;
      final next = response['nextAfterId'];
      if (!isCryptoCanonicalUuid(next) ||
          after != null && (next as String).compareTo(after) <= 0) {
        throw const FormatException('invitation_list_cursor');
      }
      after = next as String;
    }
    String? selected;
    for (final candidate in candidates) {
      final invitation = invitations[candidate.payload['invitationId']];
      if (invitation == null) {
        // Only an unsent/unknown original creation may be absent. A confirmed
        // creation missing from the list cannot authorize a replacement.
        if (!complete || candidate.state != 'pending') {
          throw const CryptoAuthorityPending('invitation_list_pending');
        }
      } else if (invitation['expiresAtEpoch'] !=
              candidate.payload['expiresAt'] ||
          !(const ['pending', 'accepted'].contains(invitation['state']) ||
              candidate.publicationPending &&
                  invitation['state'] == 'consumed')) {
        continue;
      }
      if (selected != null) {
        throw const CryptoAuthorityPending(
          'invitation_preparation_review_required',
        );
      }
      selected = candidate.action;
    }
    return selected;
  }

  Future<_PreauthorizedRecipient?> _resolvePreauthorized(
    String scope,
    String recipient,
    String role, {
    void Function()? onUnregistered,
  }) async {
    final capabilities = await access.account.directory.call(
      'capabilities',
      const {},
    );
    if (capabilities['serverId'] !=
        access.account.directory.session.profile.serverId) {
      throw const FormatException('invitation_server_identity');
    }
    if (!(capabilities['invitationPreauthorizationVersions'] as List? ??
            const [])
        .contains(1)) {
      return null; // Explicit old-host compatibility; never a failed v5 fallback.
    }
    Map<String, dynamic>? bound, target;
    VerifiedAccountDirectory? state;
    String? genesis;
    final entries = <Map<String, dynamic>>[];
    var after = 0;
    while (true) {
      late Map<String, dynamic> response;
      try {
        response = await _call('resolvePreauthorization', {
          'scopeId': scope,
          'recipient': recipient,
          'role': role,
          'afterGeneration': after,
          'limit': 50,
        });
      } on CollaborationApiException catch (error) {
        if (after == 0 &&
            error.code == 'crypto_invitation_recipient_unregistered') {
          onUnregistered?.call();
          return null;
        }
        rethrow;
      }
      final nextBound = Map<String, dynamic>.from(
            response['preauthorization'] as Map,
          ),
          nextTarget = Map<String, dynamic>.from(response['recipient'] as Map),
          page = response['recipientDirectory'] as Map;
      if (bound != null &&
          (!samePreauthorizationValue(bound, nextBound) ||
              !samePreauthorizationValue(target, nextTarget))) {
        throw const CryptoAuthorityPending(
          'crypto_invitation_recipient_changed',
        );
      }
      bound = nextBound;
      target = nextTarget;
      final values = page['entries'];
      if (values is! List ||
          values.isEmpty ||
          values.length > 50 ||
          entries.length + values.length > 100000) {
        throw const FormatException('invitation_directory_page');
      }
      for (final value in values) {
        final entry = Map<String, dynamic>.from(value as Map);
        if (genesis == null) {
          final first =
              CryptoJson.decode(
                    cryptoBase64(entry['authorization']['commandBase64']),
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
          serverId: access.account.directory.session.profile.serverId,
          accountId: target['accountId'] as String,
          pinnedRootFingerprint: genesis,
        );
        entries.add(entry);
        after = state.generation;
      }
      if (page['hasMore'] != true) {
        if (state!.headHash != page['headHash'] ||
            state.generation != page['generation'] ||
            state.snapshotHash != page['snapshotHash'] ||
            bound['member']['directoryHeadHash'] != state.headHash ||
            bound['member']['deviceSnapshotHash'] != state.deviceSnapshotHash) {
          throw const FormatException('invitation_directory_head');
        }
        await verifyPreauthorizedMemberRights(
          access: access,
          scopeId: scope,
          policyVersion: bound['policyVersion'] as int,
          member: Map<String, dynamic>.from(bound['member'] as Map),
        );
        await _promoteDirectory(
          state,
          entries,
          compare: () => access.identities.trustHostDirectory(
            directory: state!,
            expectedServerId: access.account.directory.session.profile.serverId,
            isCurrent: access.account.directory.isCurrent,
          ),
        );
        return _PreauthorizedRecipient(target, bound, state);
      }
      if (page['nextGeneration'] != after) {
        throw const FormatException('invitation_directory_cursor');
      }
    }
  }

  Future<VerifiedAccountDirectory> _retainedRecipientPrefix(
    String accountId,
    String headHash,
  ) async {
    VerifiedAccountDirectory? state;
    String? genesis;
    var count = 0;
    await for (final entry in access.account.store.streamEntries(accountId)) {
      if (++count > 100000) break;
      if (genesis == null) {
        final raw =
            CryptoJson.decode(
                  cryptoBase64(entry['authorization']['commandBase64']),
                )
                as Map;
        genesis = access.account.directory.reducer.crypto.fingerprint(
          cryptoBase64(raw['payload']['rootSigningKeyBase64'], length: 32),
          cryptoBase64(raw['payload']['rootEncryptionKeyBase64'], length: 32),
        );
      }
      state = await access.account.directory.reducer.apply(
        previous: state,
        entry: entry,
        serverId: access.account.directory.session.profile.serverId,
        accountId: accountId,
        pinnedRootFingerprint: genesis,
      );
      if (state.headHash == headHash) {
        await requireKnownDirectoryPrefix(
          directory: access.account.directory,
          store: access.account.store,
          prefix: state,
        );
        return state;
      }
    }
    throw const CryptoAuthorityPending(
      'crypto_invitation_recipient_prefix_pending',
    );
  }

  static final _preparations = <String, Future<Map<String, dynamic>>>{};
  Future<Map<String, dynamic>> _completePreauthorization(
    Map<String, dynamic> created,
    Map<String, dynamic> authorization,
  ) async {
    final command =
        CryptoJson.decode(cryptoBase64(authorization['commandBase64'])) as Map;
    final p = command['payload'] as Map;
    final key = '${access.account.store.partition}:${p['invitationId']}';
    final running = _preparations[key];
    if (running != null) return running;
    final task = _preparePreauthorization(created, authorization);
    _preparations[key] = task;
    try {
      return await task;
    } finally {
      if (identical(_preparations[key], task)) _preparations.remove(key);
    }
  }

  Future<Map<String, dynamic>> _preparePreauthorization(
    Map<String, dynamic> created,
    Map<String, dynamic> authorization,
  ) async {
    final p =
        (CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
                as Map)['payload']
            as Map;
    final target = p['preauthorization']['member'] as Map;
    final savedPublication = await access.account.store.database.rows(
      'SELECT i.authorization FROM crypto_membership_action_keys a JOIN crypto_membership_intents i ON i.partition=a.partition AND i.scope_id=a.scope_id AND i.intent_id=a.request_id WHERE a.partition=? AND a.scope_id=? AND a.action_key=?',
      [
        access.account.store.partition,
        p['scopeId'],
        'preauthorize-publish:${p['invitationId']}',
      ],
    );
    if (savedPublication.isNotEmpty) {
      final proof = Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList(
                (savedPublication.single['authorization'] as List).cast<int>(),
              ),
            )
            as Map,
      );
      final savedCommand =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final payload = Map<String, dynamic>.from(savedCommand['payload'] as Map);
      if (savedCommand['operation'] !=
              'crypto2.invitations.publishPreauthorization' ||
          payload['scopeId'] != p['scopeId'] ||
          payload['invitationId'] != p['invitationId']) {
        throw const FormatException(
          'crypto_invitation_publication_substitution',
        );
      }
      final published = await manager.invitationCommand(
        'crypto2.invitations.publishPreauthorization',
        p['scopeId'],
        payload,
        actionKey: 'preauthorize-publish:${p['invitationId']}',
      );
      return _publishedInvitation(created, published);
    }
    // Re-resolve current keys before disclosure. Directory-head-only changes are
    // allowed through their verified prefix; root/device replacement is not.
    final fresh = await _resolvePreauthorized(
      p['scopeId'],
      p['recipient']['value'],
      p['role'],
    );
    if (fresh == null ||
        !samePreauthorizationValue(
          preauthorizedIdentity(fresh.preauthorization['member'] as Map),
          preauthorizedIdentity(target),
        )) {
      throw const CryptoAuthorityPending('crypto_invitation_recipient_changed');
    }
    final directory = await _retainedRecipientPrefix(
      target['accountId'],
      target['directoryHeadHash'],
    );
    final admission = await VerifiedPreauthorizedInvitationAdmission.verify(
      access: access,
      authorization: authorization,
      recipientDirectory: directory,
    );
    final parent = await _preparePreauthorizedScope(admission);
    final childHeads = <Map<String, dynamic>>[];
    final children = await CryptoInheritedInvitationGrants(
      access,
    ).preauthorizationChildren(admission.invitationScopeId);
    for (final child in children) {
      final childAdmission = await admission.forChild(child);
      final head = await _preparePreauthorizedScope(childAdmission);
      childHeads.add({'scopeId': child, 'headHash': head.headHash});
    }
    childHeads.sort(
      (a, b) => (a['scopeId'] as String).compareTo(b['scopeId'] as String),
    );
    final own = await access.account.directory.requireFresh();
    final published = await manager.invitationCommand(
      'crypto2.invitations.publishPreauthorization',
      admission.scopeId,
      {
        'scopeId': admission.scopeId,
        'invitationId': admission.invitationId,
        'preauthorizationHeadHash': parent.headHash,
        'childHeads': childHeads,
        'authorDirectoryHeadHash': own.headHash,
      },
      actionKey: 'preauthorize-publish:${admission.invitationId}',
    );
    return _publishedInvitation(created, published);
  }

  Map<String, dynamic> _publishedInvitation(
    Map<String, dynamic> created,
    Map<String, dynamic> published,
  ) => {
    ...created,
    ...published,
    'admissionMode': 'preauthorized',
    if (created['invitation'] is Map)
      'invitation': {
        ...Map<String, dynamic>.from(created['invitation'] as Map),
        'deliveryQueued': published['deliveryQueued'] == true,
      },
  };

  Future<VerifiedScopeHead> _preparePreauthorizedScope(
    VerifiedPreauthorizedInvitationAdmission admission,
  ) async {
    final current = await access.recoveryCandidateHead(admission.scopeId);
    if (current.invitationPreauthorizations.any(
      (c) => samePreauthorizationValue(c, admission.condition),
    )) {
      final member = current.member(admission.recipientAccountId);
      if (!samePreauthorizationValue(
            preauthorizedIdentity(member),
            preauthorizedIdentity(admission.member),
          ) ||
          !const [
            'role',
            'financeRole',
            'manageKeys',
          ].every((key) => member[key] == admission.member[key])) {
        throw const CryptoAuthorityPending(
          'crypto_invitation_preauthorization_changed',
        );
      }
      // Preparation is already installed. Before the first publication use the
      // current verified descendant, not a frozen original head; no new keys.
      return current;
    }
    final db = access.account.store.database,
        partition = access.account.store.partition;
    final id = 'preauthorize:${admission.invitationId}';
    final rows = await db.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [partition, admission.scopeId, id],
    );
    Map<String, dynamic> journal;
    if (rows.isEmpty) {
      journal = {
        'proofHash': admission.proofHash,
        'reviewId': access.account.directory.reducer.crypto.randomId(),
      };
      await db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          partition,
          admission.scopeId,
          id,
          'invitationPreauthorization',
          CryptoJson.encode(journal),
        ],
      );
    } else {
      journal = Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList((rows.single['payload'] as List).cast<int>()),
            )
            as Map,
      );
      if (journal['proofHash'] != admission.proofHash ||
          journal['activatedHeadHash'] != null) {
        throw const CryptoAuthorityPending(
          'crypto_invitation_preauthorization_changed',
        );
      }
    }
    await admission.revalidate(current);
    final review = await manager.reviewRotation(
      admission.scopeId,
      preauthorizedInvitationAdmission: admission,
      fixedReviewId: journal['reviewId'] as String,
    );
    if (review.historyBasis != 'verifiedCheckpoint') {
      throw const CryptoAuthorityPending(
        'crypto_invitation_preauthorization_review',
      );
    }
    final members =
        [
          for (final m in current.members)
            if (m['accountId'] != admission.recipientAccountId) m,
          admission.member,
        ]..sort(
          (a, b) =>
              (a['accountId'] as String).compareTo(b['accountId'] as String),
        );
    final head = await manager.confirmRotation(
      review,
      acceptedCandidateHistory: false,
      members: members,
      membershipIntents: [admission.intent],
      preauthorizedInvitationAdmission: admission,
    );
    await db.execute(
      'UPDATE crypto_membership_intents SET payload=? WHERE partition=? AND scope_id=? AND intent_id=?',
      [
        CryptoJson.encode({...journal, 'activatedHeadHash': head.headHash}),
        partition,
        admission.scopeId,
        id,
      ],
    );
    return head;
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
    String invitationId, {
    String? acceptanceProofHash,
  }) async {
    final response = await _call('acceptance', {
      if (acceptanceProofHash != null)
        'acceptanceProofHash': acceptanceProofHash,
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
            await cryptoSha256(CryptoJson.encode(proof)) ||
        acceptanceProofHash != null &&
            response['acceptanceProofHash'] != acceptanceProofHash) {
      throw const FormatException('invitation_acceptance_binding');
    }
    var page = Map<String, dynamic>.from(response['recipientDirectory'] as Map);
    VerifiedAccountDirectory? state;
    VerifiedAccountDirectory? authorPrefix;
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
        if (state.headHash == raw['payload']['authorDirectoryHeadHash']) {
          authorPrefix = state;
        }
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
        state.snapshotHash != page['snapshotHash'] ||
        authorPrefix == null) {
      throw const FormatException('invitation_directory_head');
    }
    // The acceptance signature must belong to the signed author prefix as
    // well as an active current recipient device before owner key disclosure.
    final originalDevice = authorPrefix.activeDevice(raw['deviceId']);
    access.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(originalDevice['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
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

  /// A normal invitation trusts the hosting public-key directory at first use.
  /// Re-fetch the exact creator/acceptance proof before installing its signed
  /// history, so a stale UI selection never establishes a replacement identity.
  /// This grants identity trust only; acceptance and owner key admission remain
  /// separate signed operations.
  Future<void> trustCreatorFromDirectory(
    VerifiedCryptoInvitation invitation,
  ) async {
    final accepted = invitation.response['acceptanceProofHash'] != null;
    final fresh = accepted
        ? await acceptedRecipient(
            invitation.invitation['scopeId'],
            invitation.invitation['id'],
          )
        : await inspect(invitationId: invitation.invitation['id']);
    if (fresh.creator.rootFingerprint != invitation.creator.rootFingerprint) {
      throw const CryptoDirectoryException('directory_root_changed');
    }
    if (fresh.creator.accountId != invitation.creator.accountId ||
        fresh.creator.headHash != invitation.creator.headHash ||
        fresh.creator.snapshotHash != invitation.creator.snapshotHash ||
        await cryptoSha256(CryptoJson.encode(fresh.authorization)) !=
            await cryptoSha256(CryptoJson.encode(invitation.authorization)) ||
        fresh.response['acceptanceProofHash'] !=
            invitation.response['acceptanceProofHash']) {
      throw const CryptoAuthorityPending('invitation_acceptance_changed');
    }
    await _promoteDirectory(
      fresh.creator,
      fresh.entries,
      compare: () => access.identities.trustHostDirectory(
        directory: fresh.creator,
        expectedServerId: access.account.directory.session.profile.serverId,
        isCurrent: access.account.directory.isCurrent,
      ),
    );
  }

  Future<void> admit(
    VerifiedCryptoInvitation recipient,
    ScopeRotationReview reviewedInventory, {
    Future<void> Function(VerifiedCryptoInvitation)? beforeDisclosure,
    Future<void> Function()? freshDisclosureBoundary,
  }) async {
    await beforeDisclosure?.call(recipient);
    final directory = recipient.creator;
    await trustCreatorFromDirectory(recipient);
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
    await beforeDisclosure?.call(fresh);
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
    final inherited = CryptoInheritedInvitationGrants(access);
    // Retain the continuation before the parent activates: invitation
    // consumption or a lost response must not hide outstanding child keys.
    await inherited.prepare(
      parentScopeId: reviewedInventory.scopeId,
      invitationId: recipient.invitation['id'],
      recipientAccountId: directory.accountId,
      acceptanceProofHash: fresh.response['acceptanceProofHash'],
      foregroundOnly: beforeDisclosure != null,
    );
    await manager.confirmRotation(
      reviewedInventory,
      acceptedCandidateHistory: beforeDisclosure == null,
      freshDisclosureBoundary: freshDisclosureBoundary,
      beforeDisclosure: beforeDisclosure == null
          ? null
          : () => beforeDisclosure(fresh),
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
    await inherited.finish(
      reviewedInventory.scopeId,
      recipient.invitation['id'],
      verifiedHistoryOnly: beforeDisclosure != null,
      freshDisclosureBoundary: freshDisclosureBoundary,
      beforeDisclosure: beforeDisclosure == null
          ? null
          : () => beforeDisclosure(fresh),
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
    final anchorPayload =
        (CryptoJson.decode(cryptoBase64(anchor['commandBase64']))
                as Map)['payload']
            as Map;
    final preauthorized = anchorPayload['preauthorization'] != null;
    final anchorHash = await cryptoSha256(CryptoJson.encode(anchor));
    if (preauthorized) {
      final acceptance = Map<String, dynamic>.from(
        status['recipientAcceptanceAuthorization'] as Map? ??
            (throw const CryptoAuthorityPending(
              'invitation_acceptance_pending',
            )),
      );
      final command =
          CryptoJson.decode(cryptoBase64(acceptance['commandBase64'])) as Map;
      final payload = command['payload'];
      final ownDirectory = await access.account.directory.requireFresh();
      if (command.length != 8 ||
          command['version'] != 2 ||
          command['operation'] != 'crypto2.invitations.accept' ||
          command['signer'] != 'device' ||
          command['serverId'] != ownDirectory.serverId ||
          command['accountId'] != ownDirectory.accountId ||
          payload is! Map ||
          payload.length != 9 ||
          payload['creatorProofHash'] != anchorHash ||
          payload['preauthorizationHeadHash'] != status['activatedHeadHash'] ||
          !const [
            'scopeId',
            'invitationId',
            'tokenHash',
            'role',
            'expiresAt',
            'membershipHeadHash',
          ].every((key) => payload[key] == anchorPayload[key]) ||
          await cryptoSha256(CryptoJson.encode(acceptance)) !=
              status['acceptanceProofHash']) {
        throw const FormatException('invitation_activation_substitution');
      }
      final signer = await _retainedRecipientPrefix(
        ownDirectory.accountId,
        payload['authorDirectoryHeadHash'] as String,
      );
      if (!ownDirectory.includesAnchor(signer.generation, signer.headHash)) {
        throw const FormatException('invitation_acceptance_fork');
      }
      access.account.directory.reducer.crypto.verifyDomain(
        acceptance,
        cryptoBase64(
          signer.activeDevice(command['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        cryptoDirectoryDomain,
      );
      final journal = await access.account.store.database.rows(
        'SELECT i.authorization,a.action_key FROM crypto_membership_intents i JOIN crypto_membership_action_keys a ON a.partition=i.partition AND a.scope_id=i.scope_id AND a.request_id=i.intent_id WHERE i.partition=? AND i.scope_id=? AND i.intent_id=?',
        [access.account.store.partition, scopeId, command['requestId']],
      );
      if (journal.length != 1 ||
          journal.single['action_key'] is! String ||
          !samePreauthorizationValue(
            CryptoJson.decode(
              Uint8List.fromList(
                (journal.single['authorization'] as List).cast<int>(),
              ),
            ),
            acceptance,
          )) {
        throw const CryptoAuthorityPending('invitation_acceptance_pending');
      }
      // The original accept request reconciles its exact receipt before any
      // scope anchor/key material is used. An applied lost ACK is never resent.
      await manager.serialize(
        scopeId,
        () => manager.invitationCommand(
          'crypto2.invitations.accept',
          scopeId,
          Map<String, dynamic>.from(payload),
          actionKey: journal.single['action_key'] as String,
        ),
      );
    }
    final scoped = SessionCryptoAccess(
      account: access.account,
      invitationAnchor: anchor,
    );
    final current = await scoped.currentHead(scopeId, online: true);
    current.member(access.account.directory.accountId);
    final activated = scoped.verifiedCandidateAncestor(
      status['activatedHeadHash'],
    );
    final own =
        (preauthorized
                ? activated.invitationPreauthorizations
                : (activated.body['membershipIntents'] as List))
            .where(
              (i) =>
                  i['accountId'] == access.account.directory.accountId &&
                  i['invitationId'] == invitationId &&
                  (preauthorized
                      ? status['admissionMode'] == 'preauthorized' &&
                            i['preauthorizationProofHash'] == anchorHash &&
                            i['invitationScopeId'] == scopeId
                      : i['acceptanceProofHash'] ==
                            status['acceptanceProofHash']),
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
    await trustCreatorFromDirectory(invite);
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
      if (p['preauthorization'] != null)
        'preauthorizationHeadHash':
            invite.response['preauthorizationHeadHash'] ??
            (throw const CryptoAuthorityPending(
              'crypto_invitation_preauthorization_unready',
            )),
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
