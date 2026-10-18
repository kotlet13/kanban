import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import 'account_crypto_v2_workflow.dart';
import 'session_crypto_access.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';
import 'scope_crypto_manager.dart';

/// A manager's immutable public intent is followed by independently generated
/// domain-key offers. Both cards countersign the same complete core; neither
/// signing order nor a server-selected field can create a circular commitment.
class ScopeKeyContributions {
  ScopeKeyContributions(this.manager);
  final ScopeCryptoManager manager;
  SessionCryptoAccess get access => manager.access;
  AccountCryptoV2Workflow get account => manager.access.account;
  Map<String, dynamic> _decode(Object value) =>
      CryptoJson.decode(Uint8List.fromList((value as List).cast<int>()))
          as Map<String, dynamic>;
  bool _same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

  Future<List<Map<String, dynamic>>> list(String scopeId) async {
    final result = <Map<String, dynamic>>[];
    String? after;
    while (true) {
      final page = await account.directory.call('crypto2.scope.keyDraft.list', {
        'scopeId': scopeId,
        'limit': 20,
        if (after != null) 'afterId': after,
      });
      if (page['drafts'] is! List || page['hasMore'] is! bool) {
        throw const FormatException('scope_key_drafts');
      }
      result.addAll((page['drafts'] as List).cast<Map<String, dynamic>>());
      if (page['hasMore'] != true) break;
      final next = page['nextAfterId'];
      if (next is! String || after != null && next.compareTo(after) <= 0) {
        throw const FormatException('scope_key_cursor');
      }
      after = next;
    }
    return result;
  }

  Future<VerifiedAccountDirectory> _author(
    String scopeId,
    String source,
    Map command,
    String reference,
  ) async {
    final current = await access.currentMemberDirectory(
      scopeId,
      source,
      command['accountId'],
    );
    final exact = await access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: source,
      accountId: command['accountId'],
      directoryHeadHash: reference,
      online: true,
    );
    if (current.deviceSnapshotHash != exact.deviceSnapshotHash) {
      throw const CryptoAuthorityPending('scope_key_authority_changed');
    }
    return exact;
  }

  Future<Map<String, dynamic>> get(String scopeId, String draftId) async {
    final wire = await account.directory.call('crypto2.scope.keyDraft.get', {
      'scopeId': scopeId,
      'draftId': draftId,
    });
    final core = Map<String, dynamic>.from(wire['core'] as Map);
    final source = core['previousHeadHash'] as String;
    final proof = Map<String, dynamic>.from(wire['authorization'] as Map);
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final author = await _author(
      scopeId,
      source,
      raw,
      core['authorDirectoryHeadHash'],
    );
    final device = author.activeDevice(raw['deviceId']);
    final command = account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    if (command.length != 8 ||
        command['version'] != 2 ||
        command['operation'] != 'crypto2.scope.keyDraft.put' ||
        command['signer'] != 'device' ||
        command['serverId'] != author.serverId ||
        command['payload']['scopeId'] != scopeId ||
        command['payload']['draftId'] != draftId ||
        !_same(command['payload']['core'], core) ||
        !_same(
          command['payload']['requestedDomains'],
          wire['requestedDomains'],
        ) ||
        wire['managerDraftHash'] !=
            await cryptoSha256(CryptoJson.encode(proof))) {
      throw const FormatException('scope_key_draft_signature');
    }
    final previous = source == cryptoZeroHash
        ? null
        : await access.recoveryCandidateHead(scopeId);
    if (previous != null && previous.headHash != source) {
      throw const CryptoAuthorityPending('scope_key_draft_expired');
    }
    if (previous != null &&
        previous.member(author.accountId)['manageKeys'] != true) {
      throw const FormatException('scope_key_manager');
    }
    final domains = (wire['requestedDomains'] as List).cast<String>();
    if (domains.isEmpty ||
        domains.length > 2 ||
        domains.any((d) => !['content', 'finance'].contains(d)) ||
        domains.toSet().length != domains.length ||
        !_same([...domains]..sort(), domains)) {
      throw const FormatException('scope_key_domains');
    }
    final filled =
        CryptoJson.decode(CryptoJson.encode(core)) as Map<String, dynamic>;
    final seen = <String>{};
    for (final value in wire['offers'] as List) {
      final offer = Map<String, dynamic>.from(value as Map),
          authorization = Map<String, dynamic>.from(
            value['authorization'] as Map,
          );
      final untrusted =
          CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
              as Map;
      final p = Map<String, dynamic>.from(untrusted['payload'] as Map),
          domain = p['domain'];
      if (!domains.contains(domain) || !seen.add(domain as String)) {
        throw const FormatException('scope_key_offer_domain');
      }
      final directory = await _author(
        scopeId,
        source,
        untrusted,
        p['authorDirectoryHeadHash'],
      );
      final actor = directory.activeDevice(untrusted['deviceId']);
      final verified = account.directory.reducer.crypto.verifyDomain(
        authorization,
        cryptoBase64(actor['signingKeyBase64'], length: 32),
        cryptoDirectoryDomain,
      );
      final member = (core['members'] as List).singleWhere(
        (m) => m['accountId'] == directory.accountId,
      );
      if (verified['version'] != 2 ||
          verified['operation'] != 'crypto2.scope.keyDraft.offer' ||
          verified['signer'] != 'device' ||
          verified['serverId'] != author.serverId ||
          p['scopeId'] != scopeId ||
          p['draftId'] != draftId ||
          p['managerDraftHash'] != wire['managerDraftHash'] ||
          member['deviceSnapshotHash'] != directory.deviceSnapshotHash ||
          (domain == 'content'
              ? member['role'] != 'owner'
              : member['financeRole'] == 'none' ||
                    previous != null &&
                        previous.commitment('finance') != null &&
                        previous.member(directory.accountId)['financeRole'] ==
                            'none') ||
          offer['domain'] != domain ||
          offer['keyId'] != p['keyId'] ||
          offer['keyCommitment'] != p['keyCommitment']) {
        throw const FormatException('scope_key_offer_authority');
      }
      filled['keyIds'][domain] = p['keyId'];
      filled['keyCommitments'][domain] = p['keyCommitment'];
      if (domain == 'finance') {
        filled['closures']['finance'] = p['financeClosureHash'];
      }
    }
    if (seen.length == domains.length) {
      if (!_same(filled, wire['finalCore'])) {
        throw const FormatException('scope_key_core_substitution');
      }
    } else if (wire['finalCore'] != null)
      throw const FormatException('scope_key_core_premature');
    final body = {
      ...filled,
      'contentKeyProposalProof': null,
      'financeKeyProposalProof': null,
    };
    for (final value in wire['signatures'] as List) {
      final domain = value['domain'];
      if (!domains.contains(domain) ||
          body['${domain}KeyProposalProof'] != null) {
        throw const FormatException('scope_key_signature_domain');
      }
      body['${domain}KeyProposalProof'] = value['keyProposalProof'];
    }
    if (body['contentKeyProposalProof'] != null) {
      await access.codec.verifyContentKeyProposal(
        body: body,
        managerAccountId: author.accountId,
        directoryAtHead: (id, h) => access.directoryAt(
          scopeId: scopeId,
          scopeHeadHash: source,
          accountId: id,
          directoryHeadHash: h,
          online: true,
        ),
      );
    }
    if (body['financeKeyProposalProof'] != null) {
      await access.codec.verifyFinanceKeyProposal(
        body: body,
        previous: previous,
        directoryAtHead: (id, h) => access.directoryAt(
          scopeId: scopeId,
          scopeHeadHash: source,
          accountId: id,
          directoryHeadHash: h,
          online: true,
        ),
      );
    }
    return {...wire, 'verifiedBody': body};
  }

  Future<VerifiedScopeHead> prepareDeparture(
    ScopeRotationReview review,
    VerifiedScopeHead source,
    VerifiedAccountDirectory author,
    List<Map<String, dynamic>> members,
    Map<String, dynamic> catalog, {
    List<Map<String, dynamic>> membershipIntents = const [],
    Map<String, dynamic>? financePolicyIntentProof,
    Map<String, dynamic>? accessIntentProof,
  }) async {
    final rows = await account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeSuccessorDraft'",
      [account.store.partition, review.scopeId, '${review.id}:successor'],
    );
    late Map<String, dynamic> core;
    final domains = [
      'content',
      if (members.any((m) => m['financeRole'] != 'none')) 'finance',
    ];
    if (rows.isEmpty) {
      core = {
        'scopeId': review.scopeId,
        'epoch': source.epoch + 1,
        'previousHeadHash': source.headHash,
        'initialLifecycleHash': source.body['initialLifecycleHash'],
        'previousLifecycleHash': review.value['previousLifecycleHash'],
        'financePolicyIntentProof': financePolicyIntentProof,
        'accessIntentProof': accessIntentProof,
        'accessRevision': (catalog['expectedAccessRevision'] as int) + 1,
        'expectedAccessRevision': catalog['expectedAccessRevision'],
        'accessBasis': catalog['accessBasis'],
        'authorDirectoryHeadHash': author.headHash,
        'members': members,
        'membershipIntents': membershipIntents,
        'closures': {
          'content': review.domains['content']?['manifestHash'],
          'finance': null,
        },
        'keyIds': {'content': null, 'finance': null},
        'keyCommitments': {'content': null, 'finance': null},
      };
      await account.store.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          account.store.partition,
          review.scopeId,
          '${review.id}:successor',
          'scopeSuccessorDraft',
          CryptoJson.encode(core),
        ],
      );
    } else {
      core = _decode(rows.single['payload']!);
      if (base64Encode(CryptoJson.encode(core['members'])) !=
              base64Encode(CryptoJson.encode(members)) ||
          base64Encode(CryptoJson.encode(core['financePolicyIntentProof'])) !=
              base64Encode(CryptoJson.encode(financePolicyIntentProof)) ||
          base64Encode(CryptoJson.encode(core['accessIntentProof'])) !=
              base64Encode(CryptoJson.encode(accessIntentProof)))
        throw const CryptoAuthorityPending(
          'scope_rotation_reauthorization_required',
        );
    }
    await manager.keyCommand('crypto2.scope.keyDraft.put', review.scopeId, {
      'scopeId': review.scopeId,
      'draftId': review.id,
      'requestedDomains': domains,
      'core': core,
    });
    final wire = await get(review.scopeId, review.id);
    final body = Map<String, dynamic>.from(wire['verifiedBody'] as Map);
    if (domains.any((d) => body['${d}KeyProposalProof'] == null)) {
      throw const CryptoAuthorityPending(
        'scope_successor_key_contribution_required',
      );
    }
    access.codec.validateBody(body);
    return manager.publishReviewedCandidate(review, body, source, author);
  }

  Future<void> offer(
    String scopeId,
    String draftId,
    String domain, {
    ScopeRotationReview? financeReview,
  }) => manager.serialize(scopeId, () async {
    final own = await account.directory.requireFresh(),
        wire = await get(scopeId, draftId);
    if (!(wire['requestedDomains'] as List).contains(domain)) {
      throw const FormatException('scope_key_domain');
    }
    final core = wire['core'] as Map,
        member = (wire['core']['members'] as List).singleWhere(
          (m) => m['accountId'] == own.accountId,
        );
    if (domain == 'content'
        ? member['role'] != 'owner'
        : member['financeRole'] == 'none') {
      throw const CryptoAuthorityPending('scope_key_contributor_required');
    }
    final local = await account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeKeyOffer'",
      [account.store.partition, scopeId, '$draftId:$domain'],
    );
    late Map<String, dynamic> payload;
    if (local.isNotEmpty) {
      payload = _decode(local.single['payload']!);
    } else {
      if (domain == 'finance' && core['epoch'] > 1) {
        final previous = await access.recoveryCandidateHead(scopeId);
        if (previous.commitment('finance') != null &&
            (financeReview == null ||
                financeReview.sourceHeadHash != previous.headHash ||
                financeReview.domains['finance'] == null)) {
          throw const CryptoAuthorityPending(
            'finance_inventory_review_required',
          );
        }
      }
      final key = account.directory.reducer.crypto.sodium.secureRandom(32),
          keyId = account.directory.reducer.crypto.randomId();
      try {
        final bytes = key.extractBytes();
        late String commitment;
        try {
          commitment = await access.codec.keyCommitment(bytes);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
        payload = {
          'scopeId': scopeId,
          'draftId': draftId,
          'managerDraftHash': wire['managerDraftHash'],
          'domain': domain,
          'keyId': keyId,
          'keyCommitment': commitment,
          'authorDirectoryHeadHash': own.headHash,
          if (domain == 'finance')
            'financeClosureHash':
                financeReview?.domains['finance']?['manifestHash'],
        };
        final context = {
          'version': 2,
          'purpose': 'pendingScopeKey',
          'scopeId': scopeId,
          'domain': domain,
          'keyId': keyId,
          'intentId': draftId,
          'serverId': own.serverId,
          'accountId': own.accountId,
          'recipientKind': 'recovery',
          'recipientId': own.snapshot['recoveryRootEpochId'],
          'recipientPublicKeyBase64': own.snapshot['rootEncryptionKeyBase64'],
        };
        final crypto = account.directory.reducer.crypto,
            sealed = crypto.sealKey(
              key: key,
              recipientPublicKey: cryptoBase64(
                own.snapshot['rootEncryptionKeyBase64'],
                length: 32,
              ),
              context: context,
            ),
            lease = await account.signingKey();
        try {
          final proof = crypto.signDomain(
            {
              'version': 2,
              'operation': 'crypto2.localScopeKeyIntent',
              'serverId': own.serverId,
              'accountId': own.accountId,
              'deviceId': account.deviceId,
              'context': context,
              'sealedEnvelopeBase64': sealed,
            },
            lease.key,
            'JivieE2EE/localKeyIntent/v2\n',
          );
          await account.store.database.transaction(() async {
            final raw = key.extractBytes();
            try {
              await account.store.database.execute(
                'INSERT INTO crypto_scope_keys VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                [
                  account.store.partition,
                  scopeId,
                  domain,
                  core['epoch'],
                  'draft:$draftId:$domain',
                  keyId,
                  raw,
                  'draft:$draftId',
                  CryptoJson.encode(proof),
                  0,
                  0,
                ],
              );
            } finally {
              raw.fillRange(0, raw.length, 0);
            }
            await account.store.database.execute(
              'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
              [
                account.store.partition,
                scopeId,
                '$draftId:$domain',
                'scopeKeyOffer',
                CryptoJson.encode(payload),
              ],
            );
            if (financeReview != null) {
              await account.store.database.execute(
                'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
                [
                  account.store.partition,
                  scopeId,
                  '$draftId:finance-review',
                  'scopeKeyFinanceReview',
                  CryptoJson.encode(financeReview.value),
                ],
              );
            }
          });
        } finally {
          lease.release();
        }
      } finally {
        key.dispose();
      }
    }
    await manager.keyCommand(
      'crypto2.scope.keyDraft.offer',
      scopeId,
      payload,
      actionKey: 'keyoffer:$draftId:$domain',
    );
  });

  Future<void> sign(
    String scopeId,
    String draftId,
    String domain,
  ) => manager.serialize(scopeId, () async {
    final own = await account.directory.requireFresh(),
        wire = await get(scopeId, draftId);
    if (wire['finalCore'] == null) {
      throw const CryptoAuthorityPending('scope_key_other_contributor_pending');
    }
    final body = Map<String, dynamic>.from(wire['verifiedBody'] as Map);
    // Each contributor independently checks the full roster and device state
    // before countersigning the shared final core.
    access.codec.validateBody(body);
    for (final member
        in (body['members'] as List).cast<Map<String, dynamic>>()) {
      final current = await access.currentMemberDirectory(
        scopeId,
        body['previousHeadHash'],
        member['accountId'],
      );
      if (current.deviceSnapshotHash != member['deviceSnapshotHash']) {
        throw const CryptoAuthorityPending('scope_key_authority_changed');
      }
      if (current.accountId != own.accountId) {
        await access.identities.requireVerified(
          current.accountId,
          access.identities.fingerprint(current),
        );
      }
    }
    final selected = (wire['offers'] as List).singleWhere(
          (v) => v['domain'] == domain,
        ),
        raw =
            CryptoJson.decode(
                  cryptoBase64(selected['authorization']['commandBase64']),
                )
                as Map;
    if (raw['accountId'] != own.accountId ||
        raw['deviceId'] != account.deviceId) {
      throw const CryptoAuthorityPending(
        'scope_key_other_contributor_selected',
      );
    }
    final rows = await account.store.database.rows(
      'SELECT key_bytes FROM crypto_scope_keys WHERE partition=? AND scope_id=? AND domain=? AND key_id=?',
      [account.store.partition, scopeId, domain, body['keyIds'][domain]],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('scope_key_device_required');
    }
    final bytes = Uint8List.fromList(
      (rows.single['key_bytes'] as List).cast<int>(),
    );
    try {
      if (await access.codec.keyCommitment(bytes) !=
          body['keyCommitments'][domain]) {
        throw const FormatException('scope_key_commitment');
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    final lease = await account.signingKey();
    try {
      final proof = account.directory.reducer.crypto.signDomain(
        {
          'version': 2,
          'operation': 'crypto2.scope.${domain}KeyProposal',
          'serverId': own.serverId,
          'scopeId': scopeId,
          'epoch': body['epoch'],
          'previousHeadHash': body['previousHeadHash'],
          'proposalContextHash': await access.codec.financeCoreHash(body),
          'keyId': body['keyIds'][domain],
          'keyCommitment': body['keyCommitments'][domain],
          'accountId': own.accountId,
          'deviceId': account.deviceId,
          'authorDirectoryHeadHash': own.headHash,
        },
        lease.key,
        'JivieE2EE/${domain}KeyProposal/v2\n',
      );
      await manager.keyCommand('crypto2.scope.keyDraft.sign', scopeId, {
        'scopeId': scopeId,
        'draftId': draftId,
        'domain': domain,
        'keyProposalProof': proof,
      });
    } finally {
      lease.release();
    }
  });

  Future<String> _ready(String scopeId, String draftId) async {
    final wire = await get(scopeId, draftId),
        body = Map<String, dynamic>.from(wire['verifiedBody'] as Map);
    if ((wire['requestedDomains'] as List).any(
      (d) => body['${d}KeyProposalProof'] == null,
    )) {
      throw const CryptoAuthorityPending('scope_key_other_contributor_pending');
    }
    access.codec.validateBody(body);
    final hash = await access.codec.headHash(body);
    for (final domain in wire['requestedDomains'] as List) {
      await account.store.database.execute(
        'UPDATE crypto_scope_keys SET epoch_id=?,scope_head_hash=? WHERE partition=? AND scope_id=? AND domain=? AND epoch_id=?',
        [
          hash,
          hash,
          account.store.partition,
          scopeId,
          domain,
          'draft:$draftId:$domain',
        ],
      );
    }
    return hash;
  }

  Future<void> publishContent(String scopeId, String draftId) =>
      manager.serialize(scopeId, () async {
        final author = await account.directory.requireFresh(),
            hash = await _ready(scopeId, draftId),
            pending = await access.pendingHead(scopeId, hash);
        final source = pending.epoch == 1
            ? null
            : await access.recoveryCandidateHead(scopeId);
        await manager.publishNewContentGrants(pending, source, author);
      });

  Future<void> publishFinance(
    String scopeId,
    String draftId,
  ) => manager.serialize(scopeId, () async {
    final author = await account.directory.requireFresh(),
        hash = await _ready(scopeId, draftId),
        pending = await access.pendingHead(scopeId, hash),
        source = await access.recoveryCandidateHead(scopeId);
    final rows = await account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeKeyFinanceReview'",
      [account.store.partition, scopeId, '$draftId:finance-review'],
    );
    if (source.commitment('finance') != null) {
      if (rows.length != 1) {
        throw const CryptoAuthorityPending('finance_inventory_review_required');
      }
      final review = ScopeRotationReview(_decode(rows.single['payload']!)),
          inventory = review.domains['finance'];
      await manager.financeCommand('crypto2.scope.closeDomain', scopeId, {
        'scopeId': scopeId,
        'candidateHeadHash': hash,
        'domain': 'finance',
        'epoch': source.epoch,
        'membershipHeadHash': source.headHash,
        'authorDirectoryHeadHash': author.headHash,
        'expectedSequence': inventory['sequence'],
        'recordCount': inventory['count'],
        'manifestHash': inventory['manifestHash'],
        'historyBasis': review.historyBasis,
      });
    }
    await manager.publishFinanceDomainGrants(pending, source, author);
  });

  Future<void> acceptOwnership(String scopeId, String draftId) =>
      manager.serialize(scopeId, () async {
        final own = await account.directory.requireFresh(),
            hash = await _ready(scopeId, draftId),
            pending = await access.pendingHead(scopeId, hash);
        if (pending.member(own.accountId)['role'] != 'owner') {
          throw const CryptoAuthorityPending('scope_owner_required');
        }
        final top = await access.hydrateCandidateKeys(scopeId, hash);
        final wire = await account.directory.call('crypto2.scope.headGet', {
          'scopeId': scopeId,
          'headHash': hash,
        });
        final manifest = await account.directory.call(
              'crypto2.grants.manifest',
              {'scopeId': scopeId, 'headHash': hash},
            ),
            source = await access.recoveryCandidateHead(scopeId);
        if (manifest['grantManifestHash'] != top) {
          throw const CryptoAuthorityPending('scope_grants_changed');
        }
        final content = await access.codec.verifyContentGrantManifest(
          head: pending,
          proof: Map<String, dynamic>.from(
            wire['contentGrantManifestProof'] as Map,
          ),
          directoryAtHead: (id, h) => access.directoryAt(
            scopeId: scopeId,
            scopeHeadHash: hash,
            accountId: id,
            directoryHeadHash: h,
            online: true,
          ),
        );
        if (content != manifest['domains']['content']) {
          throw const FormatException('scope_content_manifest');
        }
        if (pending.commitment('finance') != null) {
          final finance = await access.codec.verifyFinanceGrantManifest(
            head: pending,
            previous: source,
            proof: Map<String, dynamic>.from(
              wire['financeGrantManifestProof'] as Map,
            ),
            directoryAtHead: (id, h) => access.directoryAt(
              scopeId: scopeId,
              scopeHeadHash: hash,
              accountId: id,
              directoryHeadHash: h,
              online: true,
            ),
          );
          if (finance != manifest['domains']['finance']) {
            throw const FormatException('scope_finance_manifest');
          }
        }
        final lease = await account.signingKey();
        try {
          final proof = account.directory.reducer.crypto.signDomain(
            {
              'version': 2,
              'operation': 'crypto2.scope.ownerAccept',
              'serverId': own.serverId,
              'scopeId': scopeId,
              'headHash': hash,
              'previousHeadHash': source.headHash,
              'grantManifestHash': top,
              'accountId': own.accountId,
              'deviceId': account.deviceId,
              'authorDirectoryHeadHash': own.headHash,
            },
            lease.key,
            'JivieE2EE/scopeOwnerAcceptance/v2\n',
          );
          await manager.keyCommand(
            'crypto2.scope.ownerAcceptance.put',
            scopeId,
            {
              'scopeId': scopeId,
              'headHash': hash,
              'ownerAcceptanceProof': proof,
            },
          );
        } finally {
          lease.release();
        }
      });

  Future<void> cancel(String scopeId, String draftId) => manager.serialize(
    scopeId,
    () => manager.keyCommand('crypto2.scope.keyDraft.cancel', scopeId, {
      'scopeId': scopeId,
      'draftId': draftId,
    }),
  );
}
