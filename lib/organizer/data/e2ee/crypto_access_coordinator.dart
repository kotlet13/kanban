import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_anchor_lock.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';
import 'scope_crypto_manager.dart';

/// A per-scope review. Transport proposals are displayed for explicit approval;
/// they never replace the source head's authenticated authority.
class CryptoAccessReview {
  const CryptoAccessReview(
    this.source,
    this.proposal,
    this.history, {
    this.invitations = const [],
  });
  final List<Map<String, dynamic>> invitations;
  final VerifiedScopeHead source;
  final Map<String, dynamic> proposal;
  final ScopeRotationReview history;
  String get scopeId => source.scopeId;
  String get intentHash => proposal['intentHash'] as String;
  List<Map<String, dynamic>> get members => [
    for (final value in (proposal['future'] as Map)['members'] as List)
      Map<String, dynamic>.from(value as Map),
  ];
  Map<String, dynamic> get descriptor => Map<String, dynamic>.from(
    (proposal['future'] as Map)['descriptor'] as Map,
  );
}

/// Bounded prepare -> independently reviewed scope approvals -> atomic apply.
/// An individual approval never installs a new current head or SQL membership.
class CryptoAccessCoordinator {
  CryptoAccessCoordinator(this.context);
  final CryptoBusinessSession context;
  ScopeCryptoManager get manager => ScopeCryptoManager(context.access);
  static final _hash = RegExp(r'^[a-f0-9]{64}$');

  static bool _same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));
  static void _fields(Map value, Set<String> names) {
    if (value.length != names.length ||
        value.keys.any((name) => !names.contains(name))) {
      throw const FormatException('crypto_access_fields');
    }
  }

  static void validateAction(Map<String, dynamic> action) {
    switch (action['kind']) {
      case 'memberRemove':
        _fields(action, {'kind', 'accountId'});
        if (!isCryptoCanonicalUuid(action['accountId'])) {
          throw const FormatException('crypto_access_member');
        }
      case 'leader':
        _fields(action, {'kind', 'accountId', 'enabled'});
        if (!isCryptoCanonicalUuid(action['accountId']) ||
            action['enabled'] is! bool) {
          throw const FormatException('crypto_access_leader');
        }
      case 'accessPolicy':
        _fields(action, {'kind', 'targetVersion'});
        if (!const [2, 3].contains(action['targetVersion'])) {
          throw const FormatException('crypto_access_policy');
        }
      default:
        throw const FormatException('crypto_access_action');
    }
  }

  static void _invitationConsequence(Map value) {
    _fields(value, {'version', 'invitationCount', 'invitationSetHash'});
    if (value['version'] != 1 ||
        value['invitationCount'] is! int ||
        value['invitationCount'] < 0 ||
        value['invitationCount'] > 65536 ||
        !_hash.hasMatch(value['invitationSetHash'] as String? ?? '')) {
      throw const FormatException('crypto_access_invitation_consequence');
    }
  }

  Future<Map<String, dynamic>> invitationSnapshot({
    required String scopeId,
    required String headHash,
    required String requestId,
  }) async {
    final result = await _invitationStream('crypto2.access.consequences', {
      'scopeId': scopeId,
      'membershipHeadHash': headHash,
      'requestId': requestId,
    });
    final snapshot = Map<String, dynamic>.from(result['snapshot'] as Map);
    _fields(snapshot, {
      'version',
      'kind',
      'scopeId',
      'invitationCount',
      'invitationSetHash',
    });
    if (snapshot['kind'] != 'pendingInvitationRevocation' ||
        snapshot['scopeId'] != scopeId) {
      throw const FormatException('crypto_access_invitation_context');
    }
    _invitationConsequence({
      for (final field in ['version', 'invitationCount', 'invitationSetHash'])
        field: snapshot[field],
    });
    return snapshot;
  }

  Future<List<Map<String, dynamic>>> invitationConsequences(
    String scopeId,
    String intentHash,
    Map<String, dynamic> expected,
  ) async {
    _invitationConsequence(expected);
    final result = await _invitationStream(
      'crypto2.access.invitationConsequences',
      {'scopeId': scopeId, 'intentHash': intentHash},
    );
    if (!_same(result['snapshot'], expected)) {
      throw const FormatException('crypto_access_invitation_changed');
    }
    return (result['invitations'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _invitationStream(
    String operation,
    Map<String, dynamic> params,
  ) async {
    final global = operation == 'crypto2.access.consequences';
    final leaves = <String>[];
    final invitations = <Map<String, dynamic>>[];
    Map<String, dynamic>? snapshot;
    String? after, request, token;
    do {
      final page = await context.account.directory.call(operation, {
        ...params,
        'limit': 20,
        if (after != null) 'afterHash': after,
      });
      _fields(page, {
        'requestId',
        'scopeToken',
        'consequenceSnapshot',
        'invitationConsequences',
        'entries',
        'hasMore',
        'nextAfterHash',
      });
      if (!isCryptoCanonicalUuid(page['requestId']) ||
          !_hash.hasMatch(page['scopeToken'] as String? ?? '') ||
          request != null && request != page['requestId'] ||
          token != null && token != page['scopeToken'] ||
          global && page['requestId'] != params['requestId'] ||
          page['entries'] is! List ||
          (page['entries'] as List).length > 20 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_access_invitation_page');
      }
      request = page['requestId'];
      token = page['scopeToken'];
      final current = Map<String, dynamic>.from(
        page[global ? 'consequenceSnapshot' : 'invitationConsequences'] as Map,
      );
      if (snapshot != null && !_same(snapshot, current)) {
        throw const FormatException('crypto_access_invitation_changed');
      }
      snapshot = current;
      for (final raw in page['entries'] as List) {
        final item = raw as Map;
        _fields(item, {
          'leafHash',
          if (item.containsKey('invitation')) 'invitation',
        });
        final hash = item['leafHash'] as String? ?? '';
        if (!_hash.hasMatch(hash) ||
            after != null && hash.compareTo(after) <= 0 ||
            leaves.length >= 65536) {
          throw const FormatException('crypto_access_invitation_order');
        }
        if (item['invitation'] != null) {
          final entry = Map<String, dynamic>.from(item['invitation'] as Map);
          _fields(entry, {'scopeToken', 'kind', 'id'});
          if (!_hash.hasMatch(entry['scopeToken'] as String? ?? '') ||
              !const ['legacy', 'crypto'].contains(entry['kind']) ||
              !isCryptoCanonicalUuid(entry['id']) ||
              !global && entry['scopeToken'] != token) {
            throw const FormatException('crypto_access_invitation_entry');
          }
          final actual = await cryptoSha256([
            ...utf8.encode('JivieAccessInvitationConsequenceEntry/v2\n'),
            ...CryptoJson.encode({
              'version': 2,
              'serverId': context.account.directory.session.profile.serverId,
              'requestId': request,
              ...entry,
            }),
          ]);
          if (actual != hash) {
            throw const FormatException('crypto_access_invitation_hash');
          }
          invitations.add(entry);
        } else if (!global) {
          throw const FormatException('crypto_access_invitation_missing');
        }
        leaves.add(hash);
        after = hash;
      }
      if (page['nextAfterHash'] != after ||
          page['hasMore'] == true && (page['entries'] as List).isEmpty) {
        throw const FormatException('crypto_access_invitation_cursor');
      }
      if (page['hasMore'] == false) break;
    } while (true);
    final header = global
        ? {
            'version': 2,
            'serverId': context.account.directory.session.profile.serverId,
            'scopeId': params['scopeId'],
            'requestId': request,
          }
        : {
            'version': 2,
            'serverId': context.account.directory.session.profile.serverId,
            'requestId': request,
            'scopeToken': token,
          };
    final domain = global
        ? 'JivieAccessInvitationConsequences/v2\n'
        : 'JivieAccessInvitationScopeConsequences/v2\n';
    final actual = await cryptoSha256([
      ...utf8.encode(domain),
      ...CryptoJson.encode(header),
      10,
      ...utf8.encode(leaves.map((h) => '$h\n').join()),
    ]);
    if (snapshot['invitationCount'] != leaves.length ||
        snapshot['invitationSetHash'] != actual) {
      throw const FormatException('crypto_access_invitation_incomplete');
    }
    return {'snapshot': snapshot, 'invitations': invitations};
  }

  Future<Map<String, dynamic>> prepare({
    required String scopeId,
    required String requestId,
    required Map<String, dynamic> action,
    String? leaveRequestHash,
  }) async {
    if (!isCryptoCanonicalUuid(scopeId) || !isCryptoCanonicalUuid(requestId)) {
      throw const FormatException('crypto_access_request');
    }
    validateAction(action);
    if (leaveRequestHash != null &&
        (action['kind'] != 'memberRemove' ||
            !_hash.hasMatch(leaveRequestHash))) {
      throw const FormatException('crypto_leave_request_binding');
    }
    final key = 'access:$requestId:prepare';
    final saved = await context.database.rows(
      'SELECT i.authorization FROM crypto_membership_action_keys k JOIN crypto_membership_intents i ON i.partition=k.partition AND i.scope_id=k.scope_id AND i.intent_id=k.request_id WHERE k.partition=? AND k.scope_id=? AND k.action_key=?',
      [context.partition, scopeId, key],
    );
    late Map<String, dynamic> payload;
    if (saved.isNotEmpty) {
      final proof = _decode(saved.single['authorization']);
      final command = _command(proof);
      payload = Map<String, dynamic>.from(command['payload'] as Map);
      if (command['requestId'] != requestId ||
          command['operation'] != 'crypto2.access.prepare' ||
          payload['scopeId'] != scopeId ||
          !_same(payload['action'], action) ||
          payload['leaveRequestHash'] != leaveRequestHash) {
        throw const FormatException('crypto_access_immutable_action');
      }
      await _ownPrepare(proof, scopeId);
    } else {
      final head = await context.access.currentHead(scopeId, online: true);
      final own = await context.account.directory.requireFresh();
      if (head.member(own.accountId)['manageKeys'] != true ||
          action['kind'] != 'memberRemove' &&
              head.member(own.accountId)['role'] != 'owner') {
        throw const CryptoAuthorityPending('scope_management_forbidden');
      }
      if (action['kind'] == 'memberRemove' &&
          head.member(action['accountId'])['role'] == 'owner') {
        throw const CryptoAuthorityPending('scope_owner_transfer_required');
      }
      payload = {
        'scopeId': scopeId,
        'membershipHeadHash': head.headHash,
        'expectedAccessRevision': head.accessRevision,
        'authorDirectoryHeadHash': own.headHash,
        'action': action,
        if (leaveRequestHash != null) 'leaveRequestHash': leaveRequestHash,
        if (action['kind'] == 'accessPolicy' && action['targetVersion'] == 3)
          'consequenceSnapshot': await invitationSnapshot(
            scopeId: scopeId,
            headHash: head.headHash,
            requestId: requestId,
          ),
      };
    }
    final result = await manager.accessCommand(
      'crypto2.access.prepare',
      scopeId,
      payload,
      actionKey: key,
      prepareRequestId: requestId,
    );
    final proof = Map<String, dynamic>.from(result['authorization'] as Map);
    if (_command(proof)['requestId'] != requestId) {
      throw const FormatException('crypto_access_prepare_request');
    }
    await _ownPrepare(proof, scopeId);
    if (result['intentHash'] != await cryptoSha256(CryptoJson.encode(proof)) ||
        result['affectedCount'] is! int ||
        result['affectedCount'] < 1 ||
        !_hash.hasMatch(result['affectedHash'] as String? ?? '')) {
      throw const FormatException('crypto_access_prepare_response');
    }
    return result;
  }

  Future<void> _ownPrepare(Map<String, dynamic> proof, String scopeId) async {
    final command = _command(proof), payload = command['payload'] as Map;
    final own = await context.account.directory.requireFresh();
    if (command['version'] != 2 ||
        command['signer'] != 'device' ||
        command['serverId'] != own.serverId ||
        command['accountId'] != own.accountId ||
        payload['scopeId'] != scopeId ||
        !isCryptoCanonicalUuid(command['requestId']) ||
        !isCryptoCanonicalUuid(command['deviceId'])) {
      throw const FormatException('crypto_access_prepare_context');
    }
    final author = await ownDirectoryAt(payload['authorDirectoryHeadHash']);
    if (!own.includesAnchor(author.generation, author.headHash)) {
      throw const FormatException('crypto_access_prepare_prefix');
    }
    context.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(
        author.activeDevice(command['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    final digest = await cryptoSha256(CryptoJson.encode(proof));
    await withCryptoAnchorLock(context.partition, () async {
      if (!context.account.directory.isCurrent()) {
        throw const CryptoAuthorityPending('crypto_identity_changed');
      }
      final latest = await context.account.store.anchor(own.accountId);
      if (latest == null ||
          latest['deviceSnapshotHash'] != own.deviceSnapshotHash ||
          latest['fingerprint'] != own.rootFingerprint) {
        throw const CryptoAuthorityPending('crypto_access_authority_changed');
      }
      final slot = 'accessPrepare2:${context.partition}:$scopeId:$digest';
      final remembered = await context.account.store.secure.read(slot);
      if (remembered != null && remembered != digest) {
        throw const FormatException('crypto_access_anchor');
      }
      final key = author.activeDevice(command['deviceId'])['signingKeyBase64'];
      if (remembered == null &&
          !own.devices.any(
            (device) =>
                device['deviceId'] == command['deviceId'] &&
                device['revokedGeneration'] == null &&
                device['identityEpochId'] == own.identityEpochId &&
                device['signingKeyBase64'] == key,
          )) {
        throw const CryptoAuthorityPending('crypto_access_historical_pending');
      }
      await context.account.store.secure.write(slot, digest);
    });
  }

  Future<VerifiedAccountDirectory> ownDirectoryAt(String reference) async {
    final own = await context.account.directory.requireFresh();
    final anchor = await context.account.store.anchor(own.accountId);
    if (anchor == null) {
      throw const CryptoAuthorityPending('crypto_access_own_anchor_missing');
    }
    VerifiedAccountDirectory? state;
    await for (final entry in context.account.store.streamEntries(
      own.accountId,
    )) {
      state = await context.account.directory.reducer.apply(
        previous: state,
        entry: entry,
        serverId: own.serverId,
        accountId: own.accountId,
        pinnedRootFingerprint:
            anchor['genesisFingerprint'] ?? anchor['fingerprint'],
      );
      if (state.headHash == reference) {
        if (!own.includesAnchor(state.generation, reference)) {
          throw const FormatException('crypto_access_own_prefix');
        }
        return state;
      }
    }
    throw const CryptoAuthorityPending('crypto_access_own_prefix_missing');
  }

  Future<List<Map<String, dynamic>>> pendingApprovals(
    String scopeId, {
    void Function(bool required)? cleanup,
  }) async {
    final head = await context.access.currentHead(scopeId, online: true);
    if (head.member(context.account.directory.accountId)['manageKeys'] !=
        true) {
      throw const CryptoAuthorityPending('scope_management_forbidden');
    }
    final result = <Map<String, dynamic>>[];
    String? after;
    do {
      final page = await context.account.directory.call(
        'crypto2.access.pending',
        {
          'scopeId': scopeId,
          if (after != null) 'afterHash': after,
          'limit': 20,
        },
      );
      if (page['cleanupRequired'] == true) cleanup?.call(true);
      if (page['intents'] is! List ||
          (page['intents'] as List).length > 20 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_access_page');
      }
      for (final raw in page['intents'] as List) {
        final value = Map<String, dynamic>.from(raw as Map);
        _validateProposal(value, head);
        final hash = value['intentHash'] as String;
        if (after != null && hash.compareTo(after) <= 0) {
          throw const FormatException('crypto_access_page_order');
        }
        after = hash;
        result.add(value);
      }
      if (page['nextAfterHash'] != after ||
          page['hasMore'] == true && (page['intents'] as List).isEmpty) {
        throw const FormatException('crypto_access_page_cursor');
      }
      if (page['hasMore'] == false) return result;
    } while (true);
  }

  void _validateProposal(Map<String, dynamic> value, VerifiedScopeHead head) {
    _fields(value, {
      'intentHash',
      'affectedCount',
      'affectedHash',
      'expiresAt',
      'scopeId',
      'previousHeadHash',
      'expectedAccessRevision',
      'accessBasis',
      'future',
      'state',
    });
    final future = value['future'] as Map;
    _fields(future, {
      'descriptor',
      'accessRevision',
      'members',
      'financePolicy',
      if (future.containsKey('invitationConsequences'))
        'invitationConsequences',
    });
    final policy = future['financePolicy'] as Map;
    _fields(policy, {'revision', 'policyHash'});
    if (policy['revision'] is! int ||
        policy['revision'] < 0 ||
        policy['revision'] > 9007199254740991 ||
        !_hash.hasMatch(policy['policyHash'] as String? ?? '')) {
      throw const FormatException('crypto_access_finance_policy');
    }
    final descriptor = future['descriptor'] as Map;
    _fields(descriptor, {
      'kind',
      'accessPolicyVersion',
      'parentScopeToken',
      if (descriptor.containsKey('leaderAccountIds')) 'leaderAccountIds',
    });
    if (descriptor.containsKey('leaderAccountIds')) {
      final leaders = descriptor['leaderAccountIds'];
      if (descriptor['kind'] != 'organization' ||
          leaders is! List ||
          leaders.length > 100 ||
          descriptor['accessPolicyVersion'] == 3 && leaders.isNotEmpty) {
        throw const FormatException('crypto_access_leaders');
      }
      String? previous;
      for (final id in leaders) {
        if (!isCryptoCanonicalUuid(id) ||
            previous != null && (id as String).compareTo(previous) <= 0 ||
            !(future['members'] as List).any(
              (m) => (m as Map)['accountId'] == id,
            )) {
          throw const FormatException('crypto_access_leaders');
        }
        previous = id;
      }
    }
    final invitations = future['invitationConsequences'];
    if (invitations != null) _invitationConsequence(invitations);
    if (value['scopeId'] != head.scopeId ||
        value['previousHeadHash'] != head.headHash ||
        value['expectedAccessRevision'] != head.accessRevision ||
        value['affectedCount'] is! int ||
        value['affectedCount'] < 1 ||
        !_hash.hasMatch(value['intentHash'] as String? ?? '') ||
        !_hash.hasMatch(value['affectedHash'] as String? ?? '') ||
        !const ['approvalRequired', 'approved'].contains(value['state']) ||
        future['accessRevision'] is! int ||
        future['accessRevision'] < head.accessRevision ||
        future['accessRevision'] > 9007199254740991 ||
        !const [
          'personal',
          'household',
          'organization',
          'project',
        ].contains(descriptor['kind']) ||
        !const [1, 2, 3].contains(descriptor['accessPolicyVersion']) ||
        descriptor['parentScopeToken'] != null &&
            !_hash.hasMatch(descriptor['parentScopeToken'] as String? ?? '')) {
      throw const FormatException('crypto_access_proposal');
    }
    final basis = value['accessBasis'];
    if (basis is! List || basis.isEmpty || basis.length > 256) {
      throw const FormatException('crypto_access_basis');
    }
    String lastToken = '';
    for (final raw in basis) {
      final item = raw as Map;
      _fields(item, {'scopeToken', 'accessRevision'});
      if (!_hash.hasMatch(item['scopeToken'] as String? ?? '') ||
          (item['scopeToken'] as String).compareTo(lastToken) <= 0 ||
          item['accessRevision'] is! int ||
          item['accessRevision'] < 0 ||
          item['accessRevision'] > 9007199254740991) {
        throw const FormatException('crypto_access_basis');
      }
      lastToken = item['scopeToken'];
    }
    final members = future['members'];
    if (members is! List || members.isEmpty || members.length > 100) {
      throw const FormatException('scope_members_limit');
    }
    String previous = '';
    var owners = 0;
    for (final raw in members) {
      final member = raw as Map;
      _fields(member, {'accountId', 'role', 'financeRole', 'manageKeys'});
      if (!isCryptoCanonicalUuid(member['accountId']) ||
          (member['accountId'] as String).compareTo(previous) <= 0 ||
          !const ['owner', 'member', 'viewer'].contains(member['role']) ||
          !const ['none', 'read', 'write'].contains(member['financeRole']) ||
          member['manageKeys'] is! bool) {
        throw const FormatException('crypto_access_members');
      }
      previous = member['accountId'];
      if (member['role'] == 'owner') owners++;
    }
    if (owners != 1) throw const FormatException('crypto_access_owner');
  }

  Future<VerifiedScopeHead> approve(
    String scopeId,
    String intentHash, {
    required Future<bool> Function(CryptoAccessReview review) review,
  }) async {
    final source = await context.access.currentHead(scopeId, online: true);
    final proposal = (await pendingApprovals(scopeId)).singleWhere(
      (value) => value['intentHash'] == intentHash,
      orElse: () => throw const CryptoAuthorityPending(
        'crypto_access_intent_unavailable',
      ),
    );
    final id = 'accessReview:$intentHash';
    final stored = await context.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeAccessReview'",
      [context.partition, scopeId, id],
    );
    late ScopeRotationReview history;
    if (stored.isEmpty) {
      history = await manager.reviewRotation(scopeId);
    } else {
      final prior = _decode(stored.single['payload']);
      if (!_same(
        _stableProposal(prior['proposal'] as Map),
        _stableProposal(proposal),
      )) {
        throw const FormatException('crypto_access_review_changed');
      }
      history = ScopeRotationReview(
        Map<String, dynamic>.from(prior['history'] as Map),
      );
    }
    final cancellation = (proposal['future'] as Map)['invitationConsequences'];
    final invitations = cancellation == null
        ? <Map<String, dynamic>>[]
        : await invitationConsequences(
            scopeId,
            intentHash,
            Map<String, dynamic>.from(cancellation as Map),
          );
    final item = CryptoAccessReview(
      source,
      proposal,
      history,
      invitations: invitations,
    );
    if (!await review(item)) {
      throw const CryptoAuthorityPending('crypto_access_review_required');
    }
    if (stored.isEmpty) {
      await context.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          context.partition,
          scopeId,
          id,
          'scopeAccessReview',
          CryptoJson.encode({'proposal': proposal, 'history': history.value}),
        ],
      );
    }
    return manager.confirmRotation(
      history,
      acceptedCandidateHistory: true,
      members: item.members,
      accessConsentBuilder: (members, author) async {
        final lease = await context.account.signingKey();
        try {
          return context.account.directory.reducer.crypto.signDomain(
            {
              'version': 2,
              'operation': 'crypto2.access.scopeConsent',
              'serverId': author.serverId,
              'scopeId': scopeId,
              'intentHash': intentHash,
              'affectedCount': proposal['affectedCount'],
              'affectedHash': proposal['affectedHash'],
              'previousHeadHash': source.headHash,
              'expectedAccessRevision': proposal['expectedAccessRevision'],
              'accessBasis': proposal['accessBasis'],
              'resultingAccessRevision':
                  (proposal['future'] as Map)['accessRevision'],
              'resultingDescriptor': item.descriptor,
              'resultingFinancePolicy':
                  (proposal['future'] as Map)['financePolicy'],
              if (cancellation != null) 'invitationConsequences': cancellation,
              'membersHash': await cryptoSha256(CryptoJson.encode(members)),
              'accountId': author.accountId,
              'deviceId': context.account.deviceId,
              'authorDirectoryHeadHash': author.headHash,
            },
            lease.key,
            'JivieE2EE/accessScopeConsent/v2\n',
          );
        } finally {
          lease.release();
        }
      },
    );
  }

  Future<Map<String, dynamic>> finish({
    required String scopeId,
    required Map<String, dynamic> prepared,
    required bool cancel,
  }) async {
    final proof = Map<String, dynamic>.from(prepared['authorization'] as Map);
    await _ownPrepare(proof, scopeId);
    final hash = await cryptoSha256(CryptoJson.encode(proof));
    if (prepared['intentHash'] != hash ||
        prepared['affectedCount'] is! int ||
        prepared['affectedCount'] < 1 ||
        !_hash.hasMatch(prepared['affectedHash'] as String? ?? '')) {
      throw const FormatException('crypto_access_intent');
    }
    final operation = cancel
        ? 'crypto2.access.cancel'
        : 'crypto2.access.activate';
    final actionKey = 'access:$hash:${cancel ? 'cancel' : 'activate'}';
    final saved = await context.database.rows(
      'SELECT i.authorization FROM crypto_membership_action_keys k JOIN crypto_membership_intents i ON i.partition=k.partition AND i.scope_id=k.scope_id AND i.intent_id=k.request_id WHERE k.partition=? AND k.scope_id=? AND k.action_key=?',
      [context.partition, scopeId, actionKey],
    );
    if (!cancel && saved.isEmpty) await _completePortions(prepared);
    final result = await manager.accessCommand(operation, scopeId, {
      'intentHash': hash,
      'affectedCount': prepared['affectedCount'],
      'affectedHash': prepared['affectedHash'],
    }, actionKey: actionKey);
    final finalProof = Map<String, dynamic>.from(
      result['authorization'] as Map,
    );
    final finalCommand = _command(finalProof);
    _fields(finalCommand, {
      'version',
      'operation',
      'requestId',
      'serverId',
      'accountId',
      'deviceId',
      'signer',
      'payload',
    });
    final own = await context.account.directory.requireFresh();
    if (finalCommand['version'] != 2 ||
        finalCommand['operation'] != operation ||
        finalCommand['signer'] != 'device' ||
        finalCommand['serverId'] != own.serverId ||
        finalCommand['accountId'] != own.accountId ||
        !isCryptoCanonicalUuid(finalCommand['requestId']) ||
        !_same(finalCommand['payload'], {
          'intentHash': hash,
          'affectedCount': prepared['affectedCount'],
          'affectedHash': prepared['affectedHash'],
        })) {
      throw const FormatException('crypto_access_outcome_signature_context');
    }
    final signers = own.devices.where(
      (device) => device['deviceId'] == finalCommand['deviceId'],
    );
    if (signers.length != 1) {
      throw const FormatException('crypto_access_outcome_signer');
    }
    context.account.directory.reducer.crypto.verifyDomain(
      finalProof,
      cryptoBase64(signers.single['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    if (result['intentHash'] != hash ||
        result['state'] != (cancel ? 'cancelled' : 'applied')) {
      throw const FormatException('crypto_access_outcome');
    }
    // Activation installs the component's new current heads. The enclosing
    // operation may still contain the source heads reviewed before this commit,
    // including when the result was recovered from an immutable saved receipt.
    if (!cancel) context.access.invalidateAuthorityOperation();
    return result;
  }

  Future<Map<String, dynamic>?> reconcile(
    String scopeId,
    Map<String, dynamic> prepared,
  ) async {
    final key = 'access:${prepared['intentHash']}:activate';
    final saved = await context.database.rows(
      'SELECT request_id FROM crypto_membership_action_keys WHERE partition=? AND scope_id=? AND action_key=?',
      [context.partition, scopeId, key],
    );
    return saved.isEmpty
        ? null
        : finish(scopeId: scopeId, prepared: prepared, cancel: false);
  }

  // The final nonce is allocated only after the complete frozen set has
  // approvals. A normal not-yet-approved state must not become a permanently
  // rejected immutable activation request.
  Future<Set<String>> affectedScopeTokens(Map<String, dynamic> prepared) =>
      _completePortions(prepared, requireApprovals: false);

  Future<String> scopeToken(String scopeId, String rootScopeId) =>
      cryptoSha256([
        ...utf8.encode('JivieAccessPortion/v2\n'),
        ...CryptoJson.encode({
          'version': 2,
          'serverId': context.account.directory.session.profile.serverId,
          'scopeId': scopeId,
          'rootScopeId': rootScopeId,
        }),
      ]);

  Future<Set<String>> _completePortions(
    Map<String, dynamic> prepared, {
    bool requireApprovals = true,
  }) async {
    final encoded = Sha256().newHashSink()
      ..add(utf8.encode('JivieAccessComponent/v2\n'))
      ..add(
        CryptoJson.encode({
          'version': 2,
          'serverId': context.account.directory.session.profile.serverId,
          'intentHash': prepared['intentHash'],
        }),
      )
      ..add([10]);
    String? after;
    var count = 0;
    var complete = true;
    final tokens = <String>{};
    do {
      final page = await context.account.directory
          .call('crypto2.access.portions', {
            'intentHash': prepared['intentHash'],
            if (after != null) 'afterToken': after,
            'limit': 20,
          });
      if (page['intentHash'] != prepared['intentHash'] ||
          page['affectedCount'] != prepared['affectedCount'] ||
          page['affectedHash'] != prepared['affectedHash'] ||
          page['portions'] is! List ||
          (page['portions'] as List).length > 20 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_access_portions');
      }
      for (final raw in page['portions'] as List) {
        final item = raw as Map;
        _fields(item, {
          'scopeToken',
          'headHash',
          'accessRevision',
          'rawAccessRevision',
          'policyVersion',
          'approvalHash',
          'cleanupRequired',
        });
        final token = item['scopeToken'] as String? ?? '';
        if (!_hash.hasMatch(token) ||
            after != null && token.compareTo(after) <= 0 ||
            !_hash.hasMatch(item['headHash'] as String? ?? '') ||
            item['accessRevision'] is! int ||
            item['accessRevision'] < 0 ||
            item['rawAccessRevision'] is! int ||
            item['rawAccessRevision'] < 0 ||
            !const [1, 2, 3].contains(item['policyVersion']) ||
            item['approvalHash'] != null &&
                !_hash.hasMatch(item['approvalHash'] as String? ?? '')) {
          throw const FormatException('crypto_access_portion');
        }
        after = token;
        tokens.add(token);
        encoded.add(
          CryptoJson.encode({
            for (final field in const [
              'scopeToken',
              'headHash',
              'accessRevision',
              'rawAccessRevision',
              'policyVersion',
            ])
              field: item[field],
          }),
        );
        encoded.add([10]);
        count++;
        complete = complete && item['approvalHash'] != null;
      }
      if (page['nextAfterToken'] != after ||
          page['hasMore'] == true && (page['portions'] as List).isEmpty) {
        throw const FormatException('crypto_access_portion_cursor');
      }
      if (page['hasMore'] == false) break;
    } while (true);
    encoded.close();
    final root = (await encoded.hash()).bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    if (count != prepared['affectedCount'] ||
        root != prepared['affectedHash']) {
      throw const FormatException('crypto_access_component_incomplete');
    }
    if (requireApprovals && !complete) {
      throw const CryptoAuthorityPending('crypto_access_approval_required');
    }
    return tokens;
  }

  static Map<String, dynamic> _stableProposal(Map source) =>
      Map<String, dynamic>.from(source)..remove('state');

  static Map<String, dynamic> _decode(Object? value) =>
      Map<String, dynamic>.from(
        CryptoJson.decode(Uint8List.fromList((value as List).cast<int>()))
            as Map,
      );
  static Map<String, dynamic> _command(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
}
