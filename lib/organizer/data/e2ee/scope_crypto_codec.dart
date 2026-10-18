import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart';
import 'crypto_codec.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'session_crypto_access.dart' show VerifiedProjectRelocationGenesis;

typedef CryptoDirectoryAtHead =
    Future<VerifiedAccountDirectory> Function(
      String accountId,
      String headHash,
    );
typedef CryptoIdentityCheck =
    Future<void> Function(String accountId, String fingerprint);

class VerifiedScopeHead {
  const VerifiedScopeHead._(
    this.body,
    this.authorization,
    this.headHash,
    this.active,
  );
  final Map<String, dynamic> body, authorization;
  final String headHash;
  final bool active;
  String get scopeId => body['scopeId'] as String;
  int get epoch => body['epoch'] as int;
  int get accessRevision => body['accessRevision'] as int;
  List<Map<String, dynamic>> get members =>
      (body['members'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> member(String account) => members.singleWhere(
    (m) => m['accountId'] == account,
    orElse: () =>
        throw const CryptoDirectoryException('scope_membership_missing'),
  );
  String? commitment(String domain) =>
      (body['keyCommitments'] as Map)[domain] as String?;
}

/// Application authorization formats over standard Ed25519/sealed boxes. Every
/// member root is checked independently; SQL membership is only server parity.
class ScopeCryptoCodec {
  ScopeCryptoCodec(this.crypto);
  final CryptoCodec crypto;
  static const headDomain = 'JivieScopeHead/v2\n';
  static const keyDomain = 'JivieScopeKey/v2\n';
  Future<String> keyCommitment(Uint8List rawKey) async {
    if (rawKey.length != 32) throw const FormatException('scope_key_length');
    return cryptoSha256([...utf8.encode(keyDomain), ...rawKey]);
  }

  Future<String> headHash(Map<String, dynamic> payload) =>
      cryptoSha256([...utf8.encode(headDomain), ...CryptoJson.encode(payload)]);
  Future<VerifiedScopeHead> verifyProposal({
    required String serverId,
    required Map<String, dynamic> authorization,
    required VerifiedScopeHead? previous,
    required VerifiedAccountDirectory authorDirectory,
    required CryptoDirectoryAtHead directoryAtHead,
    required CryptoIdentityCheck checkIdentity,
    int? accessPolicyVersion,
    VerifiedProjectRelocationGenesis? expectedProjectRelocation,
  }) async {
    final raw =
        CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
            as Map<String, dynamic>;
    final actor = authorDirectory.activeDevice(raw['deviceId'] as String);
    final command = crypto.verifyDomain(
      authorization,
      cryptoBase64(actor['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    _fields(command, {
      'version',
      'operation',
      'requestId',
      'serverId',
      'accountId',
      'deviceId',
      'signer',
      'payload',
    });
    if (command['version'] != 2 ||
        command['operation'] != 'crypto2.scope.headPut' ||
        command['serverId'] != serverId ||
        authorDirectory.serverId != serverId ||
        command['accountId'] != authorDirectory.accountId ||
        command['signer'] != 'device') {
      throw const FormatException('scope_author');
    }
    final p = Map<String, dynamic>.from(command['payload'] as Map);
    validateBody(p);
    if (p['previousHeadHash'] != (previous?.headHash ?? cryptoZeroHash) ||
        p['epoch'] != (previous?.epoch ?? 0) + 1 ||
        (previous != null && p['scopeId'] != previous.scopeId)) {
      throw const FormatException('scope_head_chain');
    }
    if (previous != null &&
        p['initialLifecycleHash'] != previous.body['initialLifecycleHash']) {
      throw const FormatException('scope_lifecycle_baseline_changed');
    }
    if (previous == null) {
      final owners = (p['members'] as List)
          .where((m) => m['role'] == 'owner')
          .toList();
      if (expectedProjectRelocation == null) {
        if (owners.single['accountId'] != authorDirectory.accountId) {
          throw const FormatException('scope_genesis_owner');
        }
      } else {
        final relocation = expectedProjectRelocation.proposalContext;
        if (expectedProjectRelocation.scopeId != p['scopeId'] ||
            expectedProjectRelocation.headHash != await headHash(p)) {
          throw const FormatException('scope_genesis_relocation_context');
        }
        _fields(relocation, {
          'version',
          'actionId',
          'planHash',
          'expectedOwnerAccountId',
        });
        final managers = (p['members'] as List).where(
          (m) =>
              m['accountId'] == authorDirectory.accountId &&
              m['manageKeys'] == true,
        );
        if (relocation['version'] != 2 ||
            !isCryptoCanonicalUuid(relocation['actionId']) ||
            !isCryptoCanonicalUuid(relocation['expectedOwnerAccountId']) ||
            relocation['planHash'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(relocation['planHash']) ||
            p['epoch'] != 1 ||
            p['previousHeadHash'] != cryptoZeroHash ||
            p['accessIntentProof'] != null ||
            p['financePolicyIntentProof'] != null ||
            owners.single['accountId'] !=
                relocation['expectedOwnerAccountId'] ||
            managers.length != 1) {
          throw const FormatException('scope_genesis_relocation_context');
        }
      }
    } else if (expectedProjectRelocation != null ||
        previous.member(authorDirectory.accountId)['manageKeys'] != true) {
      throw const FormatException('scope_management_forbidden');
    }
    if (previous != null) {
      final oldOwner = previous.members.singleWhere(
        (m) => m['role'] == 'owner',
      )['accountId'];
      final newOwner = (p['members'] as List).singleWhere(
        (m) => m['role'] == 'owner',
      )['accountId'];
      if (oldOwner != newOwner && authorDirectory.accountId != oldOwner) {
        throw const FormatException('scope_transfer_owner_authority');
      }
    }
    if (p['authorDirectoryHeadHash'] != authorDirectory.headHash) {
      throw const FormatException('scope_author_directory_binding');
    }
    for (final m in (p['members'] as List).cast<Map<String, dynamic>>()) {
      final directory = await directoryAtHead(
        m['accountId'],
        m['directoryHeadHash'],
      );
      if (directory.serverId != serverId ||
          directory.accountId != m['accountId'] ||
          directory.headHash != m['directoryHeadHash'] ||
          directory.deviceSnapshotHash != m['deviceSnapshotHash'] ||
          [
            'rootSigningKeyBase64',
            'rootEncryptionKeyBase64',
            'identityEpochId',
            'recoveryRootEpochId',
          ].any((k) => m[k] != directory.snapshot[k])) {
        throw const FormatException('scope_directory_substitution');
      }
      await checkIdentity(
        m['accountId'],
        crypto.fingerprint(
          cryptoBase64(m['rootSigningKeyBase64'], length: 32),
          cryptoBase64(m['rootEncryptionKeyBase64'], length: 32),
        ),
      );
    }
    for (final domain in ['content', 'finance']) {
      final old = previous?.commitment(domain),
          next = (p['keyCommitments'] as Map)[domain];
      if (old != null && old == next) {
        throw const FormatException('scope_key_reused');
      }
      final closed = (p['closures'] as Map)[domain];
      if (previous == null && closed != null ||
          previous != null && old != null && closed == null) {
        throw const FormatException('scope_closure_required');
      }
    }
    await verifyAccessIntent(
      body: p,
      previous: previous,
      authorDirectory: authorDirectory,
      proposalCommand: command,
    );
    await verifyFinancePolicyIntent(
      body: p,
      previous: previous,
      directoryAtHead: directoryAtHead,
      accessPolicyVersion: accessPolicyVersion,
    );
    await verifyContentKeyProposal(
      body: p,
      managerAccountId: authorDirectory.accountId,
      directoryAtHead: directoryAtHead,
    );
    await verifyFinanceKeyProposal(
      body: p,
      previous: previous,
      directoryAtHead: directoryAtHead,
    );
    return VerifiedScopeHead._(
      _freeze(p) as Map<String, dynamic>,
      _freeze(authorization) as Map<String, dynamic>,
      await headHash(p),
      false,
    );
  }

  Future<VerifiedScopeHead> verifyActivation({
    required VerifiedScopeHead pending,
    required VerifiedScopeHead? previous,
    required Map<String, dynamic> authorization,
    required VerifiedAccountDirectory authorDirectory,
    required String grantManifestHash,
    required CryptoDirectoryAtHead directoryAtHead,
    VerifiedProjectRelocationGenesis? expectedProjectRelocation,
  }) async {
    final raw =
        CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
            as Map<String, dynamic>;
    final actor = authorDirectory.activeDevice(raw['deviceId'] as String);
    final c = crypto.verifyDomain(
      authorization,
      cryptoBase64(actor['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    final p = Map<String, dynamic>.from(c['payload'] as Map);
    _fields(p, {
      'scopeId',
      'headHash',
      'grantManifestHash',
      'authorDirectoryHeadHash',
      if (p.containsKey('ownerAcceptanceProof')) 'ownerAcceptanceProof',
      if (p.containsKey('contentGrantManifestProof'))
        'contentGrantManifestProof',
      if (p.containsKey('financeGrantManifestProof'))
        'financeGrantManifestProof',
      if (p.containsKey('accessIntentHash')) 'accessIntentHash',
      if (p.containsKey('affectedCount')) 'affectedCount',
      if (p.containsKey('affectedHash')) 'affectedHash',
      if (p.containsKey('projectRelocation')) 'projectRelocation',
      if (p.containsKey('parentTopologyBatchHash')) 'parentTopologyBatchHash',
    });
    if (p.containsKey('parentTopologyBatchHash') &&
        (previous != null ||
            pending.epoch != 1 ||
            p['parentTopologyBatchHash'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(p['parentTopologyBatchHash']) ||
            p.containsKey('projectRelocation') ||
            p.containsKey('accessIntentHash'))) {
      throw const FormatException('crypto_topology_activation_context');
    }
    if (expectedProjectRelocation != null) {
      final relocation = expectedProjectRelocation.activationContext;
      if (expectedProjectRelocation.scopeId != pending.scopeId ||
          expectedProjectRelocation.headHash != pending.headHash) {
        throw const FormatException('scope_activation_relocation_context');
      }
      _fields(relocation, {'version', 'actionId', 'planHash'});
      if (relocation['version'] != 2 ||
          !isCryptoCanonicalUuid(relocation['actionId']) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(
            relocation['planHash'] is String
                ? relocation['planHash'] as String
                : '',
          ) ||
          previous != null ||
          pending.epoch != 1 ||
          pending.body['previousHeadHash'] != cryptoZeroHash ||
          pending.body['accessIntentProof'] != null ||
          pending.body['financePolicyIntentProof'] != null ||
          base64Encode(CryptoJson.encode(p['projectRelocation'])) !=
              base64Encode(CryptoJson.encode(relocation))) {
        throw const FormatException('scope_activation_relocation_context');
      }
    } else if (p.containsKey('projectRelocation')) {
      throw const FormatException('scope_activation_relocation_context');
    }
    final consentProof = pending.body['accessIntentProof'];
    if (consentProof == null) {
      if (p.containsKey('accessIntentHash') ||
          p.containsKey('affectedCount') ||
          p.containsKey('affectedHash')) {
        throw const FormatException('scope_activation_access_context');
      }
    } else {
      final consent =
          CryptoJson.decode(cryptoBase64(consentProof['commandBase64'])) as Map;
      if (p['accessIntentHash'] != consent['intentHash'] ||
          p['affectedCount'] != consent['affectedCount'] ||
          p['affectedHash'] != consent['affectedHash']) {
        throw const FormatException('scope_activation_access_context');
      }
    }
    final manager =
        previous?.member(authorDirectory.accountId) ??
        pending.member(authorDirectory.accountId);
    if (c['version'] != 2 ||
        c['operation'] != 'crypto2.scope.activate' ||
        c['signer'] != 'device' ||
        c['serverId'] != authorDirectory.serverId ||
        c['accountId'] != authorDirectory.accountId ||
        manager['manageKeys'] != true ||
        p['scopeId'] != pending.scopeId ||
        p['headHash'] != pending.headHash ||
        p['grantManifestHash'] != grantManifestHash ||
        p['authorDirectoryHeadHash'] != authorDirectory.headHash) {
      throw const FormatException('scope_activation');
    }
    if (previous != null) {
      final oldOwner = previous.members.singleWhere(
        (m) => m['role'] == 'owner',
      )['accountId'];
      final newOwner = pending.members.singleWhere((m) => m['role'] == 'owner');
      if (oldOwner != newOwner['accountId']) {
        if (c['accountId'] != oldOwner || p['ownerAcceptanceProof'] is! Map) {
          throw const FormatException('scope_owner_acceptance_required');
        }
        final proof = Map<String, dynamic>.from(
          p['ownerAcceptanceProof'] as Map,
        );
        final raw =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        final directory = await directoryAtHead(
          newOwner['accountId'],
          raw['authorDirectoryHeadHash'],
        );
        final device = directory.activeDevice(raw['deviceId']);
        final accepted = crypto.verifyDomain(
          proof,
          cryptoBase64(device['signingKeyBase64'], length: 32),
          'JivieE2EE/scopeOwnerAcceptance/v2\n',
        );
        final expected = {
          'version': 2,
          'operation': 'crypto2.scope.ownerAccept',
          'serverId': authorDirectory.serverId,
          'scopeId': pending.scopeId,
          'headHash': pending.headHash,
          'previousHeadHash': previous.headHash,
          'grantManifestHash': grantManifestHash,
          'accountId': newOwner['accountId'],
          'deviceId': raw['deviceId'],
          'authorDirectoryHeadHash': newOwner['directoryHeadHash'],
        };
        if (base64Encode(CryptoJson.encode(accepted)) !=
            base64Encode(CryptoJson.encode(expected))) {
          throw const FormatException('scope_owner_acceptance_binding');
        }
      }
    }
    if (pending.body['contentKeyProposalProof'] != null) {
      await verifyContentGrantManifest(
        head: pending,
        proof: p['contentGrantManifestProof'] == null
            ? null
            : Map<String, dynamic>.from(p['contentGrantManifestProof'] as Map),
        directoryAtHead: directoryAtHead,
      );
    }
    await verifyFinanceGrantManifest(
      head: pending,
      previous: previous,
      proof: p['financeGrantManifestProof'] == null
          ? null
          : Map<String, dynamic>.from(p['financeGrantManifestProof'] as Map),
      directoryAtHead: directoryAtHead,
    );
    return VerifiedScopeHead._(
      pending.body,
      pending.authorization,
      pending.headHash,
      true,
    );
  }

  Future<String> financeCoreHash(Map<String, dynamic> body) => cryptoSha256([
    ...utf8.encode('JivieScopeHeadCore/v2\n'),
    ...CryptoJson.encode(
      {...body}
        ..remove('financeKeyProposalProof')
        ..remove('contentKeyProposalProof'),
    ),
  ]);

  Future<void> verifyContentKeyProposal({
    required Map<String, dynamic> body,
    required String managerAccountId,
    required CryptoDirectoryAtHead directoryAtHead,
  }) async {
    final proof = body['contentKeyProposalProof'];
    if (proof == null) {
      if (!(body['members'] as List).any(
        (m) => m['accountId'] == managerAccountId,
      )) {
        throw const FormatException('content_successor_key_required');
      }
      return;
    }
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final directory = await directoryAtHead(
      raw['accountId'],
      raw['authorDirectoryHeadHash'],
    );
    final member = (body['members'] as List).singleWhere(
      (m) => m['accountId'] == directory.accountId,
    );
    if (member['role'] != 'owner' ||
        member['deviceSnapshotHash'] != directory.deviceSnapshotHash) {
      throw const FormatException('content_contributor_role');
    }
    final device = directory.activeDevice(raw['deviceId']);
    final verified = crypto.verifyDomain(
      Map<String, dynamic>.from(proof as Map),
      cryptoBase64(device['signingKeyBase64'], length: 32),
      'JivieE2EE/contentKeyProposal/v2\n',
    );
    final expected = {
      'version': 2,
      'operation': 'crypto2.scope.contentKeyProposal',
      'serverId': directory.serverId,
      'scopeId': body['scopeId'],
      'epoch': body['epoch'],
      'previousHeadHash': body['previousHeadHash'],
      'proposalContextHash': await financeCoreHash(body),
      'keyId': body['keyIds']['content'],
      'keyCommitment': body['keyCommitments']['content'],
      'accountId': directory.accountId,
      'deviceId': raw['deviceId'],
      'authorDirectoryHeadHash': directory.headHash,
    };
    if (base64Encode(CryptoJson.encode(verified)) !=
        base64Encode(CryptoJson.encode(expected))) {
      throw const FormatException('content_contribution_binding');
    }
  }

  Future<String?> verifyContentGrantManifest({
    required VerifiedScopeHead head,
    required Map<String, dynamic>? proof,
    required CryptoDirectoryAtHead directoryAtHead,
  }) async {
    if (head.body['contentKeyProposalProof'] == null) {
      if (proof != null) {
        throw const FormatException('content_manifest_unexpected');
      }
      return null;
    }
    if (proof == null) throw const FormatException('content_manifest_required');
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final card =
        CryptoJson.decode(
              cryptoBase64(
                head.body['contentKeyProposalProof']['commandBase64'],
              ),
            )
            as Map;
    final directory = await directoryAtHead(
      raw['accountId'],
      raw['authorDirectoryHeadHash'],
    );
    if (raw['accountId'] != card['accountId'] ||
        raw['deviceId'] != card['deviceId'] ||
        head.member(directory.accountId)['role'] != 'owner' ||
        head.member(directory.accountId)['deviceSnapshotHash'] !=
            directory.deviceSnapshotHash) {
      throw const FormatException('content_manifest_contributor');
    }
    final device = directory.activeDevice(raw['deviceId']);
    final verified = crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      'JivieE2EE/contentGrantManifest/v2\n',
    );
    _hash(raw['contentManifestHash']);
    final expected = {
      'version': 2,
      'operation': 'crypto2.scope.contentGrantManifest',
      'serverId': directory.serverId,
      'scopeId': head.scopeId,
      'headHash': head.headHash,
      'contentManifestHash': raw['contentManifestHash'],
      'accountId': directory.accountId,
      'deviceId': raw['deviceId'],
      'authorDirectoryHeadHash': directory.headHash,
    };
    if (base64Encode(CryptoJson.encode(verified)) !=
        base64Encode(CryptoJson.encode(expected))) {
      throw const FormatException('content_manifest_binding');
    }
    return raw['contentManifestHash'];
  }

  Future<void> verifyFinanceKeyProposal({
    required Map<String, dynamic> body,
    required VerifiedScopeHead? previous,
    required CryptoDirectoryAtHead directoryAtHead,
  }) async {
    final proof = body['financeKeyProposalProof'];
    if ((body['keyCommitments'] as Map)['finance'] == null) {
      if (proof != null) {
        throw const FormatException('finance_contribution_unexpected');
      }
      return;
    }
    if (proof is! Map) {
      throw const FormatException('finance_contribution_required');
    }
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final directory = await directoryAtHead(
      raw['accountId'],
      raw['authorDirectoryHeadHash'],
    );
    final candidate = (body['members'] as List).cast<Map>().singleWhere(
      (m) => m['accountId'] == directory.accountId,
    );
    if (candidate['financeRole'] == 'none' ||
        candidate['deviceSnapshotHash'] != directory.deviceSnapshotHash ||
        previous != null &&
            previous.commitment('finance') != null &&
            previous.member(directory.accountId)['financeRole'] == 'none') {
      throw const FormatException('finance_contributor_role');
    }
    final device = directory.activeDevice(raw['deviceId']);
    final verified = crypto.verifyDomain(
      Map<String, dynamic>.from(proof),
      cryptoBase64(device['signingKeyBase64'], length: 32),
      'JivieE2EE/financeKeyProposal/v2\n',
    );
    final expected = {
      'version': 2,
      'operation': 'crypto2.scope.financeKeyProposal',
      'serverId': directory.serverId,
      'scopeId': body['scopeId'],
      'epoch': body['epoch'],
      'previousHeadHash': body['previousHeadHash'],
      'proposalContextHash': await financeCoreHash(body),
      'keyId': body['keyIds']['finance'],
      'keyCommitment': body['keyCommitments']['finance'],
      'accountId': directory.accountId,
      'deviceId': raw['deviceId'],
      'authorDirectoryHeadHash': directory.headHash,
    };
    if (base64Encode(CryptoJson.encode(verified)) !=
        base64Encode(CryptoJson.encode(expected))) {
      throw const FormatException('finance_contribution_binding');
    }
  }

  Future<String?> verifyFinanceGrantManifest({
    required VerifiedScopeHead head,
    required VerifiedScopeHead? previous,
    required Map<String, dynamic>? proof,
    required CryptoDirectoryAtHead directoryAtHead,
  }) async {
    if (head.commitment('finance') == null) {
      if (proof != null) {
        throw const FormatException('finance_manifest_unexpected');
      }
      return null;
    }
    if (proof == null) throw const FormatException('finance_manifest_required');
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final directory = await directoryAtHead(
      raw['accountId'],
      raw['authorDirectoryHeadHash'],
    );
    final candidate = head.member(directory.accountId);
    if (candidate['financeRole'] == 'none' ||
        candidate['deviceSnapshotHash'] != directory.deviceSnapshotHash ||
        previous != null &&
            previous.commitment('finance') != null &&
            previous.member(directory.accountId)['financeRole'] == 'none') {
      throw const FormatException('finance_contributor_role');
    }
    final keyCard =
        CryptoJson.decode(
              cryptoBase64(
                head.body['financeKeyProposalProof']['commandBase64'],
              ),
            )
            as Map;
    if (keyCard['accountId'] != directory.accountId ||
        keyCard['deviceId'] != raw['deviceId']) {
      throw const FormatException('finance_manifest_contributor_changed');
    }
    final device = directory.activeDevice(raw['deviceId']);
    final verified = crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      'JivieE2EE/financeGrantManifest/v2\n',
    );
    _hash(raw['financeManifestHash']);
    final expected = {
      'version': 2,
      'operation': 'crypto2.scope.financeGrantManifest',
      'serverId': directory.serverId,
      'scopeId': head.scopeId,
      'headHash': head.headHash,
      'financeManifestHash': raw['financeManifestHash'],
      'accountId': directory.accountId,
      'deviceId': raw['deviceId'],
      'authorDirectoryHeadHash': directory.headHash,
    };
    if (base64Encode(CryptoJson.encode(verified)) !=
        base64Encode(CryptoJson.encode(expected))) {
      throw const FormatException('finance_manifest_binding');
    }
    return raw['financeManifestHash'];
  }

  Future<Map<String, dynamic>?> verifyFinancePolicyIntent({
    required Map<String, dynamic> body,
    required VerifiedScopeHead? previous,
    required CryptoDirectoryAtHead directoryAtHead,
    int? accessPolicyVersion,
  }) async {
    final proof = body['financePolicyIntentProof'];
    if (proof == null) return null;
    if (proof is! Map<String, dynamic> || previous == null) {
      throw const FormatException('finance_policy_intent');
    }
    final raw =
        CryptoJson.decode(cryptoBase64(proof['commandBase64']))
            as Map<String, dynamic>;
    _fields(raw, {
      'version',
      'operation',
      'requestId',
      'serverId',
      'accountId',
      'deviceId',
      'signer',
      'payload',
    });
    final p = Map<String, dynamic>.from(raw['payload'] as Map);
    _fields(p, {
      'scopeId',
      'membershipHeadHash',
      'expectedAccessRevision',
      'authorDirectoryHeadHash',
      'expectedFinancePolicyRevision',
      'previousPolicyHash',
      'resultingFinancePolicyRevision',
      'resultingPolicyHash',
      'action',
    });
    for (final field in [
      'previousPolicyHash',
      'resultingPolicyHash',
      'authorDirectoryHeadHash',
    ]) {
      _hash(p[field]);
    }
    if (raw['version'] != 2 ||
        raw['operation'] != 'crypto2.scope.financePolicy.propose' ||
        raw['signer'] != 'device' ||
        p['scopeId'] != previous.scopeId ||
        p['membershipHeadHash'] != previous.headHash ||
        p['expectedAccessRevision'] != body['expectedAccessRevision'] ||
        p['expectedFinancePolicyRevision'] is! int ||
        p['expectedFinancePolicyRevision'] < 0 ||
        p['resultingFinancePolicyRevision'] !=
            p['expectedFinancePolicyRevision'] + 1 ||
        p['previousPolicyHash'] == p['resultingPolicyHash']) {
      throw const FormatException('finance_policy_binding');
    }
    final directory = await directoryAtHead(
      raw['accountId'],
      p['authorDirectoryHeadHash'],
    );
    if (raw['serverId'] != directory.serverId ||
        directory.headHash != p['authorDirectoryHeadHash'] ||
        previous.member(directory.accountId)['manageKeys'] != true) {
      throw const FormatException('finance_policy_author');
    }
    final device = directory.activeDevice(raw['deviceId']);
    crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    final action = Map<String, dynamic>.from(p['action'] as Map);
    final members = (body['members'] as List).cast<Map<String, dynamic>>();
    final managed = accessPolicyVersion == 3;
    if (managed &&
        (members.length != previous.members.length ||
            members.any(
              (m) => !previous.members.any(
                (old) =>
                    old['accountId'] == m['accountId'] &&
                    old['financeRole'] == m['financeRole'],
              ),
            ))) {
      throw const FormatException('finance_policy_managed_roles');
    }
    if (action['kind'] == 'enable') {
      _fields(action, {'kind', 'enabled'});
      if (action['enabled'] is! bool ||
          action['enabled'] == false &&
              members.any((m) => m['financeRole'] != 'none') ||
          action['enabled'] == true &&
              members.singleWhere(
                    (m) => m['accountId'] == directory.accountId,
                  )['financeRole'] !=
                  'write') {
        throw const FormatException('finance_policy_roles');
      }
    } else if (action['kind'] == 'grant') {
      _fields(action, {'kind', 'accountId', 'grant'});
      _uuid(action['accountId']);
      if (!['none', 'read', 'write'].contains(action['grant']) ||
          members
                  .where(
                    (m) =>
                        m['accountId'] == action['accountId'] &&
                        (managed || m['financeRole'] == action['grant']),
                  )
                  .length !=
              1) {
        throw const FormatException('finance_policy_roles');
      }
    } else {
      throw const FormatException('finance_policy_action');
    }
    return p;
  }

  Future<void> verifyAccessIntent({
    required Map<String, dynamic> body,
    required VerifiedScopeHead? previous,
    required VerifiedAccountDirectory authorDirectory,
    required Map<String, dynamic> proposalCommand,
  }) async {
    final proof = body['accessIntentProof'];
    if (proof == null) return;
    if (proof is! Map || previous == null) {
      throw const FormatException('scope_access_consent');
    }
    final value = crypto.verifyDomain(
      Map<String, dynamic>.from(proof),
      cryptoBase64(
        authorDirectory.activeDevice(
          proposalCommand['deviceId'],
        )['signingKeyBase64'],
        length: 32,
      ),
      'JivieE2EE/accessScopeConsent/v2\n',
    );
    _fields(value, {
      'version',
      'operation',
      'serverId',
      'scopeId',
      'intentHash',
      'affectedCount',
      'affectedHash',
      'previousHeadHash',
      'expectedAccessRevision',
      'accessBasis',
      'resultingAccessRevision',
      'resultingDescriptor',
      'membersHash',
      'accountId',
      'deviceId',
      'authorDirectoryHeadHash',
      if (value.containsKey('resultingFinancePolicy')) 'resultingFinancePolicy',
      if (value.containsKey('invitationConsequences')) 'invitationConsequences',
    });
    if (value.containsKey('invitationConsequences')) {
      final consequence = value['invitationConsequences'];
      if (consequence is! Map) {
        throw const FormatException('scope_access_invitation_consequences');
      }
      _fields(Map<String, dynamic>.from(consequence), {
        'version',
        'invitationCount',
        'invitationSetHash',
      });
      if (consequence['version'] != 1 ||
          consequence['invitationCount'] is! int ||
          consequence['invitationCount'] < 0 ||
          consequence['invitationCount'] > 9007199254740991) {
        throw const FormatException('scope_access_invitation_consequences');
      }
      _hash(consequence['invitationSetHash']);
    }
    if (value.containsKey('resultingFinancePolicy')) {
      final policy = value['resultingFinancePolicy'];
      if (policy is! Map ||
          policy.length != 2 ||
          policy['revision'] is! int ||
          policy['revision'] < 0 ||
          policy['revision'] > 9007199254740991) {
        throw const FormatException('scope_access_finance_policy');
      }
      _hash(policy['policyHash']);
    }
    final descriptor = value['resultingDescriptor'];
    if (descriptor is! Map) {
      throw const FormatException('scope_access_descriptor');
    }
    _fields(Map<String, dynamic>.from(descriptor), {
      'kind',
      'accessPolicyVersion',
      'parentScopeToken',
      if (descriptor.containsKey('leaderAccountIds')) 'leaderAccountIds',
    });
    if (descriptor.containsKey('leaderAccountIds')) {
      final leaders = descriptor['leaderAccountIds'];
      if (descriptor['kind'] != 'organization' ||
          leaders is! List ||
          leaders.length > (body['members'] as List).length ||
          descriptor['accessPolicyVersion'] == 3 && leaders.isNotEmpty) {
        throw const FormatException('scope_access_leaders');
      }
      String? previousLeader;
      for (final leader in leaders) {
        _uuid(leader);
        if (previousLeader != null && previousLeader.compareTo(leader) >= 0 ||
            !(body['members'] as List).any(
              (member) => (member as Map)['accountId'] == leader,
            )) {
          throw const FormatException('scope_access_leaders');
        }
        previousLeader = leader as String;
      }
    }
    if (!const [
          'personal',
          'household',
          'organization',
          'project',
        ].contains(descriptor['kind']) ||
        !const [1, 2, 3].contains(descriptor['accessPolicyVersion']) ||
        descriptor['kind'] == 'personal' &&
            descriptor['accessPolicyVersion'] != 1) {
      throw const FormatException('scope_access_descriptor');
    }
    if (descriptor['parentScopeToken'] != null) {
      _hash(descriptor['parentScopeToken']);
    }
    for (final field in ['intentHash', 'affectedHash', 'membersHash']) {
      _hash(value[field]);
    }
    if (value['version'] != 2 ||
        value['operation'] != 'crypto2.access.scopeConsent' ||
        value['serverId'] != proposalCommand['serverId'] ||
        value['scopeId'] != body['scopeId'] ||
        value['previousHeadHash'] != previous.headHash ||
        value['expectedAccessRevision'] != body['expectedAccessRevision'] ||
        value['resultingAccessRevision'] != body['accessRevision'] ||
        base64Encode(CryptoJson.encode(value['accessBasis'])) !=
            base64Encode(CryptoJson.encode(body['accessBasis'])) ||
        value['membersHash'] !=
            await cryptoSha256(CryptoJson.encode(body['members'])) ||
        value['accountId'] != proposalCommand['accountId'] ||
        value['deviceId'] != proposalCommand['deviceId'] ||
        value['authorDirectoryHeadHash'] != body['authorDirectoryHeadHash'] ||
        value['affectedCount'] is! int ||
        value['affectedCount'] < 1 ||
        value['affectedCount'] > 9007199254740991) {
      throw const FormatException('scope_access_consent');
    }
  }

  void validateBody(Map<String, dynamic> p) {
    _fields(p, {
      'scopeId',
      'epoch',
      'previousHeadHash',
      'accessRevision',
      'expectedAccessRevision',
      'accessBasis',
      'members',
      'membershipIntents',
      'initialLifecycleHash',
      'previousLifecycleHash',
      'closures',
      'keyCommitments',
      'keyIds',
      'authorDirectoryHeadHash',
      'financeKeyProposalProof',
      'contentKeyProposalProof',
      if (p.containsKey('financePolicyIntentProof')) 'financePolicyIntentProof',
      if (p.containsKey('accessIntentProof')) 'accessIntentProof',
    });
    _uuid(p['scopeId']);
    _hash(p['previousHeadHash']);
    _hash(p['authorDirectoryHeadHash']);
    _hash(p['initialLifecycleHash']);
    if (p['epoch'] == 1) {
      if (p['previousLifecycleHash'] != null) {
        throw const FormatException('scope_genesis_lifecycle');
      }
    } else {
      _hash(p['previousLifecycleHash']);
    }
    if (p['epoch'] is! int ||
        (p['epoch'] as int) < 1 ||
        p['accessRevision'] is! int ||
        (p['accessRevision'] as int) < 0 ||
        (p['accessRevision'] as int) > 9007199254740991 ||
        p['members'] is! List ||
        (p['members'] as List).isEmpty) {
      throw const FormatException('scope_head_shape');
    }
    if (p['expectedAccessRevision'] is! int ||
        p['expectedAccessRevision'] < 0 ||
        p['expectedAccessRevision'] > 9007199254740991 ||
        p['accessBasis'] is! List ||
        p['accessBasis'].isEmpty ||
        p['accessBasis'].length > 2 ||
        p['accessRevision'] < p['expectedAccessRevision'] ||
        p['accessIntentProof'] == null &&
            p['accessRevision'] > p['expectedAccessRevision'] + 1) {
      throw const FormatException('scope_access_basis');
    }
    String lastToken = '';
    for (final basis in p['accessBasis'] as List) {
      if (basis is! Map<String, dynamic>) {
        throw const FormatException('scope_access_basis');
      }
      _fields(basis, {'scopeToken', 'accessRevision'});
      _hash(basis['scopeToken']);
      if ((basis['scopeToken'] as String).compareTo(lastToken) <= 0 ||
          basis['accessRevision'] is! int ||
          basis['accessRevision'] < 0) {
        throw const FormatException('scope_access_basis');
      }
      lastToken = basis['scopeToken'];
    }
    String last = '';
    var owners = 0;
    var finance = false;
    for (final raw in p['members'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('scope_member_shape');
      }
      _fields(raw, {
        'accountId',
        'rootSigningKeyBase64',
        'rootEncryptionKeyBase64',
        'recoveryRootEpochId',
        'identityEpochId',
        'directoryHeadHash',
        'deviceSnapshotHash',
        'role',
        'financeRole',
        'manageKeys',
      });
      for (final key in [
        'accountId',
        'identityEpochId',
        'recoveryRootEpochId',
      ]) {
        _uuid(raw[key]);
      }
      for (final key in ['directoryHeadHash', 'deviceSnapshotHash']) {
        _hash(raw[key]);
      }
      if ((raw['accountId'] as String).compareTo(last) <= 0 ||
          !['owner', 'member', 'viewer'].contains(raw['role']) ||
          !['none', 'read', 'write'].contains(raw['financeRole']) ||
          raw['manageKeys'] is! bool) {
        throw const FormatException('scope_member_shape');
      }
      last = raw['accountId'];
      owners += raw['role'] == 'owner' ? 1 : 0;
      finance = finance || raw['financeRole'] != 'none';
      cryptoBase64(raw['rootSigningKeyBase64'], length: 32);
      cryptoBase64(raw['rootEncryptionKeyBase64'], length: 32);
    }
    if (p['membershipIntents'] is! List ||
        p['membershipIntents'].length > 100) {
      throw const FormatException('scope_membership_intents');
    }
    String lastIntent = '';
    for (final raw in p['membershipIntents'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('scope_membership_intents');
      }
      _fields(raw, {'accountId', 'invitationId', 'acceptanceProofHash'});
      _uuid(raw['accountId']);
      _uuid(raw['invitationId']);
      _hash(raw['acceptanceProofHash']);
      if ((raw['accountId'] as String).compareTo(lastIntent) <= 0 ||
          !(p['members'] as List).any(
            (m) => m['accountId'] == raw['accountId'],
          )) {
        throw const FormatException('scope_membership_intents');
      }
      lastIntent = raw['accountId'];
    }
    if (owners != 1) throw const FormatException('scope_owner_required');
    final ids = Map<String, dynamic>.from(p['keyIds'] as Map);
    _fields(ids, {'content', 'finance'});
    for (final id in ids.values) {
      if (id != null) _uuid(id);
    }
    if (ids['content'] == null ||
        (finance && ids['finance'] == null) ||
        (ids['finance'] != null && ids['finance'] == ids['content'])) {
      throw const FormatException('scope_key_id');
    }
    for (final name in ['closures', 'keyCommitments']) {
      final value = Map<String, dynamic>.from(p[name] as Map);
      _fields(value, {'content', 'finance'});
      for (final hash in value.values) {
        if (hash != null) _hash(hash);
      }
    }
    if ((p['keyCommitments'] as Map)['finance'] != null &&
        (p['keyCommitments'] as Map)['finance'] ==
            (p['keyCommitments'] as Map)['content']) {
      throw const FormatException('scope_domain_key_reused');
    }
    if ((p['keyCommitments'] as Map)['content'] == null ||
        finance && (p['keyCommitments'] as Map)['finance'] == null) {
      throw const FormatException('scope_key_commitment_required');
    }
  }

  /// A complete, sorted manifest is bounded by paginated transport, not silently
  /// truncated. A caller compares its exact hash to the signed closure proof.
  Future<String> closureManifestHash(
    List<Map<String, dynamic>> descriptors,
  ) async {
    String previous = '';
    final sink = Sha256().newHashSink();
    for (final descriptor in descriptors) {
      _fields(descriptor, {
        'id',
        'revision',
        'recordProofHash',
        'sequence',
        'recordEpoch',
      });
      if (!isCryptoWireRecordId(descriptor['id']) &&
          !isCryptoCanonicalUuid(descriptor['id'])) {
        throw const FormatException('scope_record_id');
      }
      _hash(descriptor['recordProofHash']);
      if ((descriptor['id'] as String).compareTo(previous) <= 0 ||
          [
            'revision',
            'sequence',
            'recordEpoch',
          ].any((k) => descriptor[k] is! int || (descriptor[k] as int) < 1)) {
        throw const FormatException('scope_closure_manifest');
      }
      previous = descriptor['id'];
      sink.add(CryptoJson.encode(descriptor));
      sink.add([10]);
    }
    sink.close();
    return (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Map<String, dynamic> wrapperContext({
    required String serverId,
    required VerifiedScopeHead head,
    required VerifiedScopeHead keySourceHead,
    required String domain,
    required String keyId,
    required Map<String, dynamic> recipient,
  }) => {
    'version': 2,
    'purpose': 'scopeDomainKey',
    'serverId': serverId,
    'scopeId': head.scopeId,
    'membershipHeadHash': head.headHash,
    'epoch': keySourceHead.epoch,
    'keySourceHeadHash': keySourceHead.headHash,
    'domain': domain,
    'keyId': keyId,
    'recipientKind': recipient['recipientKind'],
    'recipientId': recipient['recipientId'],
    'recipientPublicKeyBase64': recipient['publicKeyBase64'],
    'recoveryRootEpochId': recipient['recoveryRootEpochId'],
    'keyCommitment': keySourceHead.commitment(domain),
  };
  void _fields(Map<String, dynamic> m, Set<String> fields) {
    if (m.length != fields.length || m.keys.any((k) => !fields.contains(k))) {
      throw const FormatException('scope_fields');
    }
  }

  void _uuid(Object? v) {
    if (!isCryptoCanonicalUuid(v)) {
      throw const FormatException('scope_uuid');
    }
  }

  void _hash(Object? v) {
    if (v is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(v)) {
      throw const FormatException('scope_hash');
    }
  }

  Object? _freeze(Object? v) => v is Map<String, dynamic>
      ? Map<String, dynamic>.unmodifiable(
          v.map((k, x) => MapEntry(k, _freeze(x))),
        )
      : v is List
      ? List<Object?>.unmodifiable(v.map(_freeze))
      : v;
}
