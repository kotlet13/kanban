import 'dart:convert';

import '../collaboration_transport.dart';
import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_business_parity_v3.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_commitments_v3.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';

/// A selected contributor attests its own complete FILE-compared leaf set.
/// Managers without finance READ consume only opaque contribution digests.
class CryptoMigrationDomainContributions {
  CryptoMigrationDomainContributions(this.runtime);
  final CryptoBusinessSession runtime;
  CryptoCaptureCoordinator get coordinator =>
      CryptoCaptureCoordinator(runtime.account);
  String get partition => runtime.partition;

  /// Fresh issuance prerequisite for a scoped final activation. This performs
  /// the same complete assignment/contributor checks as certificate creation;
  /// it never treats a server's selected subset as the expected contribution.
  Future<Map<String, dynamic>> verifyCertificateCandidate(
    Map<String, dynamic> proof,
  ) async {
    final c = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    final p = Map<String, dynamic>.from(c['payload'] as Map),
        h = Map<String, dynamic>.from((c['payload'] as Map)['header'] as Map);
    await CryptoMigrationCommitmentsV3.validateHeader(h);
    final head = (await runtime.access.migrationCandidate(
      scopeId: h['scopeId'],
      migrationId: h['migrationId'],
      headHash: h['membershipHeadHash'],
    )).head;
    if (c['operation'] != 'crypto2.migration.domains.certify' ||
        c['accountId'] != h['managerAccountId'] ||
        c['serverId'] != h['serverId'] ||
        h['membershipHeadHash'] != head.headHash ||
        head.member(c['accountId'])['manageKeys'] != true) {
      throw const FormatException('crypto_migration_domain_certificate');
    }
    final manager = await runtime.access.currentMemberDirectory(
      h['scopeId'],
      head.headHash,
      c['accountId'],
    );
    final prefix = await runtime.access.directoryAt(
      scopeId: h['scopeId'],
      scopeHeadHash: head.headHash,
      accountId: c['accountId'],
      directoryHeadHash: h['managerDirectoryHeadHash'],
      online: true,
    );
    if (prefix.identityEpochId != manager.identityEpochId ||
        prefix.deviceSnapshotHash != manager.deviceSnapshotHash) {
      throw const FormatException('crypto_migration_domain_certificate');
    }
    runtime.codec.crypto.verifyDomain(
      proof,
      cryptoBase64(
        prefix.activeDevice(c['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    final assignments = (p['assignments'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    await _validateAssignments(h, assignments, head);
    final contributions = p['contributions'] as List;
    if (contributions.length != assignments.length) {
      throw const FormatException('crypto_migration_domain_assignment');
    }
    for (var i = 0; i < assignments.length; i++) {
      if (contributions[i]['accountId'] != assignments[i]['accountId']) {
        throw const FormatException('crypto_migration_domain_assignment');
      }
      await _verifyContribution(
        h,
        assignments[i],
        contributions[i] as Map,
        head,
      );
    }
    return p;
  }

  Future<Map<String, dynamic>> prepare({
    required String migrationId,
    required String scopeId,
    required String domain,
  }) async {
    final candidate = await runtime.account.directory.call(
      'crypto2.migration.domains.get',
      {'migrationId': migrationId, 'scopeId': scopeId, 'domain': domain},
    );
    final header = Map<String, dynamic>.from(candidate['header'] as Map);
    await CryptoMigrationCommitmentsV3.validateHeader(header);
    final head = (await runtime.access.migrationCandidate(
      scopeId: scopeId,
      migrationId: migrationId,
    )).head;
    final member = head.member(runtime.account.directory.accountId);
    if (header['migrationId'] != migrationId ||
        header['scopeId'] != scopeId ||
        header['domain'] != domain ||
        header['serverId'] !=
            runtime.account.directory.session.profile.serverId ||
        header['membershipHeadHash'] != head.headHash ||
        header['managerAccountId'] != runtime.account.directory.accountId ||
        member['manageKeys'] != true) {
      throw const FormatException('crypto_migration_domain_context');
    }
    await _validateAssignments(
      header,
      (candidate['assignments'] as List).cast<Map<String, dynamic>>(),
      head,
    );
    return _send(
      'domainPrepare3:$migrationId:$scopeId:$domain',
      'crypto2.migration.domains.prepare',
      {'header': header, 'assignments': candidate['assignments']},
    );
  }

  /// Select from the authenticated complete frozen assignment, including an
  /// explicit zero-leaf manager fallback. Current READ alone never assigns a
  /// second materializer and a NONE role alone never proves an empty domain.
  Future<bool> isAssigned({
    required VerifiedCryptoMigrationColdBusiness verified,
    required String scopeId,
    required String domain,
  }) async {
    final migration = verified.header['migrationId'] as String;
    final head = (await runtime.access.migrationCandidate(
      scopeId: scopeId,
      migrationId: migration,
      captureId: verified.header['captureId'],
    )).head;
    late Map<String, dynamic> page;
    try {
      page = await runtime.account.directory.call(
        'crypto2.migration.domains.leaves',
        {
          'migrationId': migration,
          'scopeId': scopeId,
          'domain': domain,
          'limit': 1,
        },
      );
    } on CollaborationApiException catch (error) {
      if (error.code != 'crypto_migration_domain_pending') rethrow;
      throw const CryptoAuthorityPending(
        'crypto_migration_dependencies_pending',
      );
    }
    final h = Map<String, dynamic>.from(page['header'] as Map);
    await CryptoMigrationCommitmentsV3.validateHeader(h);
    final proof = Map<String, dynamic>.from(
      page['prepareAuthorization'] as Map,
    );
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    if (h['migrationId'] != migration ||
        h['scopeId'] != scopeId ||
        h['domain'] != domain ||
        h['serverId'] != verified.header['serverId'] ||
        h['componentCommitment'] != verified.header['componentCommitment'] ||
        h['membershipHeadHash'] != head.headHash ||
        body['accountId'] != h['managerAccountId'] ||
        ![
          'crypto2.migration.domains.prepare',
          'crypto2.migration.domains.certify',
        ].contains(body['operation']) ||
        CryptoInventoryJson.canonical(body['payload']['header']) !=
            CryptoInventoryJson.canonical(h) ||
        head.member(h['managerAccountId'])['manageKeys'] != true) {
      throw const FormatException('crypto_migration_domain_assignment');
    }
    final assignments = (body['payload']['assignments'] as List)
        .cast<Map<String, dynamic>>();
    await _validateAssignments(h, assignments, head);
    final manager = await runtime.access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: head.headHash,
      accountId: h['managerAccountId'],
      directoryHeadHash: h['managerDirectoryHeadHash'],
    );
    runtime.codec.crypto.verifyDomain(
      proof,
      cryptoBase64(
        manager.activeDevice(body['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    final own = assignments
        .where((a) => a['accountId'] == runtime.account.directory.accountId)
        .toList();
    if (own.length > 1 ||
        (own.isEmpty
            ? page['assignment'] != null
            : CryptoInventoryJson.canonical(page['assignment']) !=
                  CryptoInventoryJson.canonical(own.single))) {
      throw const FormatException('crypto_migration_domain_assignment');
    }
    return own.isNotEmpty;
  }

  Future<Map<String, dynamic>> contribute({
    required VerifiedCryptoMigrationColdBusiness verified,
    required String scopeId,
    required String domain,
  }) async {
    final cold = CryptoMigrationColdBusiness(runtime.account);
    final verification = await cold.verificationAuthorization(verified);
    final migration = verified.header['migrationId'] as String;
    final head = (await runtime.access.migrationCandidate(
      scopeId: scopeId,
      migrationId: migration,
      captureId: verified.header['captureId'],
    )).head;
    final account = runtime.account.directory.accountId;
    final existing = await _existing(
      'domainContribution3:${verified.header['captureId']}:$scopeId:$domain',
      'crypto2.migration.domains.contribute',
    );
    if (existing != null) {
      final ch = Map<String, dynamic>.from(existing.payload['header'] as Map);
      if (ch['captureId'] != verified.header['captureId'] ||
          ch['sourceInventoryRoot'] != verified.header['sourceInventoryRoot'] ||
          ch['coldParityProofHash'] !=
              await cryptoSha256(CryptoJson.encode(verification)) ||
          ch['scopeToken'] !=
              await CryptoMigrationCommitmentsV3.scopeToken(
                serverId: verified.header['serverId'],
                migrationId: migration,
                scopeId: scopeId,
                domain: domain,
              )) {
        throw const FormatException('crypto_migration_domain_immutable');
      }
      return _anchorContribution(
        verified,
        scopeId,
        domain,
        ch,
        existing.result,
      );
    }
    // Server leaf values are candidates only. Every own canonical source must
    // match the full capability-bound frame stream before signing any root.
    final page = await runtime.account.directory.call(
      'crypto2.migration.domains.leaves',
      {
        'migrationId': migration,
        'scopeId': scopeId,
        'domain': domain,
        'limit': 20,
      },
    );
    final header = Map<String, dynamic>.from(page['header'] as Map);
    await CryptoMigrationCommitmentsV3.validateHeader(header);
    if (header['membershipHeadHash'] != head.headHash ||
        header['componentCommitment'] !=
            verified.header['componentCommitment'] ||
        header['componentId'] != verified.header['componentId'] ||
        header['migrationId'] != migration ||
        header['scopeId'] != scopeId ||
        header['domain'] != domain ||
        header['serverId'] != verified.header['serverId']) {
      throw const FormatException('crypto_migration_domain_context');
    }
    final assignment = Map<String, dynamic>.from(page['assignment'] as Map);
    final prepareProof = Map<String, dynamic>.from(
      page['prepareAuthorization'] as Map,
    );
    final prepareBody = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(prepareProof['commandBase64'])) as Map,
    );
    final manager = await runtime.access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: head.headHash,
      accountId: header['managerAccountId'],
      directoryHeadHash: header['managerDirectoryHeadHash'],
    );
    if (head.member(header['managerAccountId'])['manageKeys'] != true ||
        prepareBody['accountId'] != header['managerAccountId'] ||
        prepareBody['operation'] != 'crypto2.migration.domains.prepare' ||
        CryptoInventoryJson.canonical(prepareBody['payload']['header']) !=
            CryptoInventoryJson.canonical(header) ||
        assignment['accountId'] != account ||
        assignment['captureId'] != verified.header['captureId'] ||
        assignment['sourceInventoryRoot'] !=
            verified.header['sourceInventoryRoot'] ||
        !(prepareBody['payload']['assignments'] as List).any(
          (v) =>
              CryptoInventoryJson.canonical(v) ==
              CryptoInventoryJson.canonical(assignment),
        )) {
      throw const FormatException('crypto_migration_domain_assignment');
    }
    runtime.codec.crypto.verifyDomain(
      prepareProof,
      cryptoBase64(
        manager.activeDevice(prepareBody['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    await runtime.db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_migration_contribution_facts('
      'partition TEXT NOT NULL,capture_id TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,'
      'proof_hash TEXT NOT NULL,leaf_hash TEXT NOT NULL,leaf TEXT NOT NULL,'
      'PRIMARY KEY(partition,capture_id,scope_id,domain,proof_hash),'
      'UNIQUE(partition,capture_id,scope_id,domain,leaf_hash))',
    );
    final key = [partition, verified.header['captureId'], scopeId, domain];
    await runtime.db.execute(
      'DELETE FROM crypto_migration_contribution_facts WHERE partition=? AND capture_id=? AND scope_id=? AND domain=?',
      key,
    );
    final coldHash = await cryptoSha256(CryptoJson.encode(verification));
    final author = await runtime.account.directory.requireFresh();
    var sourceCount = 0, leafCount = 0;
    await for (final frame in cold.verifiedFrames(verified)) {
      if (frame['tag'] != 'binding') continue;
      final value = frame['value'] as Map, binding = value['binding'] as Map;
      if (value['adapter'] != 'canonical' ||
          binding['scopeId'] != scopeId ||
          binding['domain'] != domain) {
        continue;
      }
      sourceCount++;
      final hashes = <String>[
        value['primaryRecordProofHash'] as String,
        ...(value['companionProofHashes'] as List).cast<String>(),
      ];
      for (final hash in hashes) {
        final rows = await runtime.db.rows(
          'SELECT * FROM crypto_migration_staged_records WHERE partition=? AND migration_id=? AND scope_id=? AND domain=? AND record_proof_hash=?',
          [partition, migration, scopeId, domain, hash],
        );
        if (rows.length != 1) {
          throw const FormatException('crypto_migration_domain_coverage');
        }
        final row = rows.single;
        final signedBinding = Map<String, dynamic>.from(
          jsonDecode(row['source_binding'] as String) as Map,
        );
        if (await CryptoMigrationBusinessParityV3.canonicalArtifact(
                  signedBinding,
                ) !=
                value['artifactHash'] ||
            signedBinding['bindingId'] != binding['bindingId']) {
          throw const FormatException('crypto_migration_domain_coverage');
        }
        final proof = Map<String, dynamic>.from(
          jsonDecode(row['record_proof'] as String) as Map,
        );
        if (await runtime.codec.digest(proof) != hash) {
          throw const FormatException('crypto_migration_domain_coverage');
        }
        final record = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
        );
        runtime.codec.validateUntrustedRecord(record);
        if (record['accountId'] != account ||
            record['scopeId'] != scopeId ||
            record['domain'] != domain ||
            record['membershipHeadHash'] != head.headHash ||
            record['expectedRevision'] != 0 ||
            record['previousRecordHash'] != '0' * 64) {
          throw const FormatException('crypto_migration_domain_coverage');
        }
        runtime.codec.crypto.verifyDomain(
          proof,
          cryptoBase64(
            author.activeDevice(record['deviceId'])['signingKeyBase64'],
            length: 32,
          ),
          'JivieE2EE/record/v2\n',
        );
        final identity = record['metadata']['identity'] as Map;
        final leaf = <String, dynamic>{
          'version': 3,
          'migrationId': migration,
          'scopeId': scopeId,
          'domain': domain,
          'membershipHeadHash': head.headHash,
          'captureId': verified.header['captureId'],
          'sourceInventoryRoot': verified.header['sourceInventoryRoot'],
          'bindingId': binding['bindingId'],
          'sourceCommitment': binding['sourceCommitment'],
          'legacyRevision': signedBinding['legacyRevision'],
          'sourceKind': identity['sourceKind'],
          'canonicalId': identity['canonicalId'],
          'wireId': record['id'],
          'type': record['type'],
          'recordProofHash': hash,
          'materializationRole': hash == signedBinding['recordProofHash']
              ? 'primary'
              : record['type'],
          'contributorAccountId': account,
          'contributorDeviceId': record['deviceId'],
          'contributorDeviceSnapshotHash': author.deviceSnapshotHash,
          'archiveManifestHash': verified.header['archiveManifestHash'],
          'coldParityHash': coldHash,
          'witnessCipherManifestHash':
              (signedBinding['witness'] as Map?)?['cipherManifestHash'],
        };
        final digest = await CryptoMigrationCommitmentsV3.leafHash(
          header,
          leaf,
        );
        await runtime.db.execute(
          'INSERT INTO crypto_migration_contribution_facts VALUES(?,?,?,?,?,?,?)',
          [...key, hash, digest, CryptoInventoryJson.canonical(leaf)],
        );
        leafCount++;
      }
    }
    String? after;
    var observed = page;
    var matched = 0;
    while (true) {
      for (final value in observed['leaves'] as List) {
        final v = value as Map, hash = v['leafHash'];
        if (after != null && after.compareTo(hash) >= 0) {
          throw const FormatException('crypto_migration_domain_coverage');
        }
        final rows = await runtime.db.rows(
          'SELECT leaf FROM crypto_migration_contribution_facts WHERE partition=? AND capture_id=? AND scope_id=? AND domain=? AND leaf_hash=?',
          [...key, hash],
        );
        if (rows.length != 1 ||
            rows.single['leaf'] != CryptoInventoryJson.canonical(v['leaf'])) {
          throw const FormatException('crypto_migration_domain_coverage');
        }
        after = hash;
        matched++;
      }
      if (observed['hasMore'] != true) break;
      if (after == null || observed['nextAfterHash'] != after) {
        throw const FormatException('crypto_migration_domain_coverage');
      }
      observed = await runtime.account.directory
          .call('crypto2.migration.domains.leaves', {
            'migrationId': migration,
            'scopeId': scopeId,
            'domain': domain,
            'limit': 20,
            'afterHash': after,
          });
      if (CryptoInventoryJson.canonical(observed['header']) !=
          CryptoInventoryJson.canonical(header)) {
        throw const FormatException('crypto_migration_domain_context');
      }
    }
    if (matched != leafCount ||
        sourceCount != assignment['sourceRowCount'] ||
        leafCount != assignment['leafCount']) {
      throw const FormatException('crypto_migration_domain_coverage');
    }
    Stream<String> digests() async* {
      String? cursor;
      while (true) {
        final rows = await runtime.db.rows(
          'SELECT leaf_hash FROM crypto_migration_contribution_facts WHERE partition=? AND capture_id=? AND scope_id=? AND domain=?'
          '${cursor == null ? '' : ' AND leaf_hash>?'} ORDER BY leaf_hash LIMIT 20',
          [...key, if (cursor != null) cursor],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          cursor = row['leaf_hash'] as String;
          yield cursor;
        }
      }
    }

    final ch = <String, dynamic>{
      'version': 3,
      'serverId': verified.header['serverId'],
      'migrationId': migration,
      'scopeToken': header['scopeToken'],
      'domain': domain,
      'headerHash': await CryptoMigrationCommitmentsV3.headerHash(header),
      'portionToken': await cryptoSha256([
        ...utf8.encode('JivieMigrationPortion/v2\n'),
        ...CryptoJson.encode({
          'version': 2,
          'serverId': verified.header['serverId'],
          'migrationId': migration,
          'accountId': account,
        }),
      ]),
      'captureId': verified.header['captureId'],
      'sourceInventoryRoot': verified.header['sourceInventoryRoot'],
      'coldParityProofHash': coldHash,
      'leafCount': leafCount,
      'sourceRowCount': sourceCount,
      'authorDirectoryHeadHash': author.headHash,
    };
    final root = await CryptoMigrationCommitmentsV3.contributionRoot(
      ch,
      digests(),
    );
    final result = await _send(
      'domainContribution3:${verified.header['captureId']}:$scopeId:$domain',
      'crypto2.migration.domains.contribute',
      {
        'header': ch,
        'leafSetRoot': root,
        'controlSections': verified.controlSections,
        'scopeControlSections': {
          'audit':
              verified.scopedAuditSections[scopeId] ??
              (throw const FormatException(
                'crypto_migration_scoped_audit_pending',
              )),
        },
        'controlLinks': await _controlLinks(verified),
      },
    );
    if (result['leafSetRoot'] != root) {
      throw const FormatException('crypto_migration_domain_receipt');
    }
    return _anchorContribution(verified, scopeId, domain, ch, result);
  }

  Future<Map<String, dynamic>> _controlLinks(
    VerifiedCryptoMigrationColdBusiness verified,
  ) async {
    final result = <String, dynamic>{};
    for (final kind in ['invitations', 'notifications']) {
      final capture = verified.header['captureId'];
      final certAction = kind == 'invitations'
          ? 'legacyInvitationCertificate:$capture'
          : 'notification3certify:$capture';
      final anchorAction = kind == 'invitations'
          ? '$certAction:anchor'
          : 'notification3anchor:$capture';
      final cert = await _existing(
        certAction,
        'crypto2.migration.$kind.certify',
      );
      final anchor = await _existing(
        anchorAction,
        'crypto2.migration.$kind.anchor',
      );
      if (cert == null || anchor == null) {
        throw const FormatException('crypto_migration_domain_controls_pending');
      }
      final h = Map<String, dynamic>.from(cert.payload['header'] as Map);
      if (![
            'migrationId',
            'captureId',
            'sourceInventoryRoot',
            'archiveManifestHash',
          ].every((k) => h[k] == verified.header[k]) ||
          h['coldParityProofHash'] !=
              await cryptoSha256(
                CryptoJson.encode(
                  await CryptoMigrationColdBusiness(
                    runtime.account,
                  ).verificationAuthorization(verified),
                ),
              ) ||
          cert.result['selectionRoot'] !=
              verified.controlSections[kind]!['root'] ||
          cert.result[kind == 'invitations'
                  ? 'bridgeCount'
                  : 'transformCount'] !=
              verified.controlSections[kind]!['count'] ||
          anchor.result['state'] != 'anchored' ||
          anchor.payload['certificateHash'] != cert.result['certificateHash']) {
        throw const FormatException('crypto_migration_domain_control_links');
      }
      result[kind] = {
        'certificateHash': cert.result['certificateHash'],
        'eventCommandHash': anchor.payload['eventCommandHash'],
      };
    }
    return result;
  }

  Future<Map<String, dynamic>> _anchorContribution(
    VerifiedCryptoMigrationColdBusiness verified,
    String scopeId,
    String domain,
    Map<String, dynamic> ch,
    Map<String, dynamic> result,
  ) async {
    final migration = verified.header['migrationId'] as String;
    final entry = await runtime.account.attestMigration(
      migrationId: migration,
      scopeToken: ch['scopeToken'],
      domain: domain,
      attestationHash: result['contributionHash'],
    );
    runtime.access.invalidateAuthorityOperation();
    await _send(
      'domainContributionAnchor3:${verified.header['captureId']}:$scopeId:$domain',
      'crypto2.migration.domains.anchorContribution',
      {
        'migrationId': migration,
        'scopeId': scopeId,
        'domain': domain,
        'contributionHash': result['contributionHash'],
        'eventAuthorization': entry['authorization'],
      },
    );
    return result;
  }

  Future<Map<String, dynamic>> certify({
    required VerifiedCryptoMigrationColdBusiness verified,
    required String scopeId,
    required String domain,
  }) async {
    final migration = verified.header['migrationId'] as String;
    final head = (await runtime.access.migrationCandidate(
      scopeId: scopeId,
      migrationId: migration,
      captureId: verified.header['captureId'],
    )).head;
    final me = runtime.account.directory.accountId;
    final existing = await _existing(
      'domainCertify3:$migration:$scopeId:$domain',
      'crypto2.migration.domains.certify',
    );
    if (existing != null) {
      final header = Map<String, dynamic>.from(
        existing.payload['header'] as Map,
      );
      if (header['componentCommitment'] !=
              verified.header['componentCommitment'] ||
          header['managerAccountId'] != me ||
          header['membershipHeadHash'] != head.headHash ||
          header['scopeId'] != scopeId ||
          header['domain'] != domain) {
        throw const FormatException('crypto_migration_domain_immutable');
      }
      return _anchorCertificate(
        migration,
        scopeId,
        domain,
        header,
        existing.result,
      );
    }
    final pages = await runtime.account.directory.call(
      'crypto2.migration.domains.get',
      {
        'migrationId': migration,
        'scopeId': scopeId,
        'domain': domain,
        'limit': 50,
      },
    );
    final header = Map<String, dynamic>.from(pages['header'] as Map);
    await CryptoMigrationCommitmentsV3.validateHeader(header);
    if (header['managerAccountId'] != me ||
        header['membershipHeadHash'] != head.headHash ||
        header['componentCommitment'] !=
            verified.header['componentCommitment'] ||
        header['componentId'] != verified.header['componentId'] ||
        header['scopeId'] != scopeId ||
        header['domain'] != domain ||
        header['migrationId'] != migration ||
        header['serverId'] != verified.header['serverId'] ||
        head.member(me)['manageKeys'] != true) {
      throw const FormatException('crypto_migration_domain_context');
    }
    final assignments = (pages['assignments'] as List)
        .cast<Map<String, dynamic>>();
    await _validateAssignments(header, assignments, head);
    final contributions = (pages['contributions'] as List).cast<Map>();
    if (contributions.length > assignments.length ||
        CryptoInventoryJson.canonical(pages['contributorAccounts']) !=
            CryptoInventoryJson.canonical(
              assignments.map((a) => a['accountId']).toList(),
            )) {
      throw const FormatException(
        'crypto_migration_domain_contribution_pending',
      );
    }
    final expectedAccounts = assignments.map((a) => a['accountId']).toSet();
    String? previousAccount;
    var pending = contributions.length < assignments.length;
    for (final item in contributions) {
      final account = item['accountId'];
      if (account is! String ||
          !expectedAccounts.contains(account) ||
          previousAccount != null && account.compareTo(previousAccount) <= 0 ||
          !const {'staged', 'anchored'}.contains(item['state'])) {
        throw const FormatException(
          'crypto_migration_domain_contribution_pending',
        );
      }
      previousAccount = account;
      pending = pending || item['state'] != 'anchored';
    }
    if (pending) {
      throw const CryptoAuthorityPending(
        'crypto_migration_dependencies_pending',
      );
    }
    final checked =
        <
          ({
            Map<String, dynamic> header,
            Map<String, dynamic> authorization,
            Map<String, dynamic> event,
          })
        >[];
    for (var i = 0; i < assignments.length; i++) {
      final item = contributions[i], assignment = assignments[i];
      if (item['accountId'] != assignment['accountId'] ||
          item['state'] != 'anchored') {
        throw const FormatException(
          'crypto_migration_domain_contribution_pending',
        );
      }
      checked.add(await _verifyContribution(header, assignment, item, head));
    }
    await runtime.db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_migration_manager_digests('
      'partition TEXT NOT NULL,header_hash TEXT NOT NULL,digest TEXT NOT NULL,PRIMARY KEY(partition,header_hash,digest))',
    );
    final headerHash = await CryptoMigrationCommitmentsV3.headerHash(header);
    await runtime.db.execute(
      'DELETE FROM crypto_migration_manager_digests WHERE partition=? AND header_hash=?',
      [partition, headerHash],
    );
    var page = pages;
    String? previous;
    var count = 0;
    while (true) {
      for (final raw in page['leafDigests'] as List) {
        final hash = raw as String;
        if (previous != null && previous.compareTo(hash) >= 0) {
          throw const FormatException('crypto_migration_domain_coverage');
        }
        previous = hash;
        count++;
        await runtime.db.execute(
          'INSERT INTO crypto_migration_manager_digests VALUES(?,?,?)',
          [partition, headerHash, hash],
        );
      }
      if (page['hasMore'] != true) break;
      if (previous == null || page['nextAfterHash'] != previous) {
        throw const FormatException('crypto_migration_domain_coverage');
      }
      page = await runtime.account.directory
          .call('crypto2.migration.domains.get', {
            'migrationId': migration,
            'scopeId': scopeId,
            'domain': domain,
            'afterHash': previous,
            'limit': 50,
          });
      if (CryptoInventoryJson.canonical(page['header']) !=
              CryptoInventoryJson.canonical(header) ||
          CryptoInventoryJson.canonical(page['contributions']) !=
              CryptoInventoryJson.canonical(contributions)) {
        throw const FormatException('crypto_migration_domain_context');
      }
    }
    if (count != header['materializedRecordProofCount']) {
      throw const FormatException('crypto_migration_domain_coverage');
    }
    Stream<String> hashes() async* {
      String? after;
      while (true) {
        final rows = await runtime.db.rows(
          'SELECT digest FROM crypto_migration_manager_digests WHERE partition=? AND header_hash=?'
          '${after == null ? '' : ' AND digest>?'} ORDER BY digest LIMIT 20',
          [partition, headerHash, if (after != null) after],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          after = row['digest'] as String;
          yield after;
        }
      }
    }

    for (final item in checked) {
      final h = item.header;
      final body =
          CryptoJson.decode(cryptoBase64(item.authorization['commandBase64']))
              as Map;
      if (await CryptoMigrationCommitmentsV3.contributionRoot(
            h,
            h['leafCount'] == 0 ? const Stream<String>.empty() : hashes(),
          ) !=
          body['payload']['leafSetRoot']) {
        throw const FormatException('crypto_migration_domain_coverage');
      }
    }
    final root = await CryptoMigrationCommitmentsV3.domainRoot(
      header,
      hashes(),
    );
    final result = await _send(
      'domainCertify3:$migration:$scopeId:$domain',
      'crypto2.migration.domains.certify',
      {
        'header': header,
        'domainRoot': root,
        'assignments': assignments,
        'contributions': [
          for (final item in checked)
            {
              'accountId':
                  item.header['accountId'] ??
                  (CryptoJson.decode(
                        cryptoBase64(item.authorization['commandBase64']),
                      )
                      as Map)['accountId'],
              'authorization': item.authorization,
              'eventAuthorization': item.event,
            },
        ],
      },
    );
    if (result['domainRoot'] != root) {
      throw const FormatException('crypto_migration_domain_receipt');
    }
    return _anchorCertificate(migration, scopeId, domain, header, result);
  }

  Future<
    ({
      Map<String, dynamic> header,
      Map<String, dynamic> authorization,
      Map<String, dynamic> event,
    })
  >
  _verifyContribution(
    Map<String, dynamic> header,
    Map<String, dynamic> assignment,
    Map item,
    VerifiedScopeHead head,
  ) async {
    final selected = assignment['accountId'] as String,
        scopeId = header['scopeId'] as String,
        domain = header['domain'] as String,
        migration = header['migrationId'] as String;
    final contribution = Map<String, dynamic>.from(
      item['authorization'] as Map,
    );
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(contribution['commandBase64'])) as Map,
    );
    final ch = Map<String, dynamic>.from(body['payload']['header'] as Map);
    final directory = await runtime.access.currentMemberDirectory(
      scopeId,
      head.headHash,
      selected,
    );
    final prefix = await runtime.access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: head.headHash,
      accountId: selected,
      directoryHeadHash: ch['authorDirectoryHeadHash'],
    );
    if (prefix.deviceSnapshotHash != directory.deviceSnapshotHash ||
        prefix.identityEpochId != directory.identityEpochId ||
        body['serverId'] != header['serverId'] ||
        body['accountId'] != selected ||
        body['operation'] != 'crypto2.migration.domains.contribute' ||
        ch['headerHash'] !=
            await CryptoMigrationCommitmentsV3.headerHash(header) ||
        ch['serverId'] != header['serverId'] ||
        ch['migrationId'] != migration ||
        ch['scopeToken'] != header['scopeToken'] ||
        ch['domain'] != domain ||
        ch['leafCount'] != assignment['leafCount'] ||
        ch['sourceRowCount'] != assignment['sourceRowCount']) {
      throw const FormatException('crypto_migration_domain_contribution');
    }
    runtime.codec.crypto.verifyDomain(
      contribution,
      cryptoBase64(
        prefix.activeDevice(body['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    final event = Map<String, dynamic>.from(item['eventAuthorization'] as Map);
    final eventBody = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(event['commandBase64'])) as Map,
    );
    final ep = eventBody['payload'] as Map;
    CryptoMigrationBusinessParityV3.exact(body['payload'], {
      'header',
      'leafSetRoot',
      'controlSections',
      'scopeControlSections',
      'controlLinks',
    });
    final links = body['payload']['controlLinks'];
    CryptoMigrationBusinessParityV3.exact(links, {
      'notifications',
      'invitations',
    });
    for (final kind in ['notifications', 'invitations']) {
      CryptoMigrationBusinessParityV3.exact(links[kind], {
        'certificateHash',
        'eventCommandHash',
      });
      if (!CryptoMigrationBusinessParityV3.hash(
            links[kind]['certificateHash'],
          ) ||
          !CryptoMigrationBusinessParityV3.hash(
            links[kind]['eventCommandHash'],
          )) {
        throw const FormatException('crypto_migration_domain_control_links');
      }
    }
    CryptoMigrationBusinessParityV3.scopedAudit(
      body['payload']['scopeControlSections'],
    );
    final sections = body['payload']['controlSections'];
    if (sections is! Map) {
      throw const FormatException('crypto_migration_domain_control_sections');
    }
    CryptoMigrationBusinessParityV3.exact(
      sections,
      CryptoMigrationBusinessParityV3.requiredSections,
    );
    for (final kind in CryptoMigrationBusinessParityV3.requiredSections) {
      final v = sections[kind];
      if (v is! Map) {
        throw const FormatException('crypto_migration_domain_control_sections');
      }
      CryptoMigrationBusinessParityV3.exact(v, {'kind', 'count', 'root'});
      if (v['kind'] != kind ||
          !CryptoMigrationBusinessParityV3.count(v['count']) ||
          !CryptoMigrationBusinessParityV3.hash(v['root'])) {
        throw const FormatException('crypto_migration_domain_control_sections');
      }
    }
    final contributionHash = await cryptoSha256(
      CryptoJson.encode(contribution),
    );
    final commandHash = await cryptoSha256(
      cryptoBase64(event['commandBase64']),
    );
    final eventHead = await cryptoSha256([
      ...utf8.encode(cryptoDirectoryLogDomain),
      ...CryptoJson.encode({
        'serverId': header['serverId'],
        'accountId': selected,
        'generation': (ep['expectedGeneration'] as int) + 1,
        'previousHeadHash': ep['previousHeadHash'],
        'commandHash': commandHash,
        'signatureBase64': event['signatureBase64'],
      }),
    ]);
    if (eventBody['operation'] != 'crypto2.account.migrationAttest' ||
        eventBody['accountId'] != selected ||
        eventBody['serverId'] != header['serverId'] ||
        ep['migrationId'] != migration ||
        ep['domain'] != domain ||
        ep['scopeToken'] != header['scopeToken'] ||
        ep['attestationHash'] != contributionHash ||
        !directory.includesAnchor(ep['expectedGeneration'] + 1, eventHead)) {
      throw const FormatException('crypto_migration_domain_contribution_event');
    }
    if (ch['captureId'] != assignment['captureId'] ||
        ch['sourceInventoryRoot'] != assignment['sourceInventoryRoot'] ||
        ch['portionToken'] != assignment['portionToken']) {
      throw const FormatException('crypto_migration_domain_assignment');
    }
    return (header: ch, authorization: contribution, event: event);
  }

  Future<void> _validateAssignments(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> assignments,
    VerifiedScopeHead head,
  ) async {
    if (assignments.isEmpty || assignments.length > 1000) {
      throw const FormatException('crypto_migration_domain_assignment');
    }
    final eligible =
        head.members
            .where((m) => m['financeRole'] != 'none')
            .map((m) => m['accountId'] as String)
            .toList()
          ..sort();
    final manager = header['managerAccountId'];
    final materializer =
        header['domain'] == 'content' ||
            eligible.isEmpty ||
            eligible.contains(manager)
        ? manager
        : eligible.first;
    String? previous;
    var sources = 0, leaves = 0;
    final publicInventory = await runtime.account.directory.call(
      'crypto2.migration.capture.commitments',
      {'migrationId': header['migrationId'], 'limit': 50},
    );
    final matched = <String>{};
    final scopedTokens = <String, String>{};
    for (final member in head.members) {
      final id = member['accountId'] as String;
      scopedTokens[await cryptoSha256([
            ...utf8.encode('JivieMigrationPortion/v2\n'),
            ...CryptoJson.encode({
              'version': 2,
              'serverId': header['serverId'],
              'migrationId': header['migrationId'],
              'accountId': id,
            }),
          ])] =
          id;
    }
    final expectedAccounts = <String>{};

    Stream<Map<String, dynamic>> portions() async* {
      var page = publicInventory;
      String? after;
      while (true) {
        if (page['serverId'] != header['serverId'] ||
            page['migrationId'] != header['migrationId'] ||
            page['componentId'] != header['componentId'] ||
            page['inventoryCommitment'] != header['inventoryCommitment'] ||
            page['componentCommitment'] != header['componentCommitment'] ||
            page['portionCount'] != publicInventory['portionCount']) {
          throw const FormatException('crypto_migration_domain_assignment');
        }
        for (final raw in page['portions'] as List) {
          final p = Map<String, dynamic>.from(raw as Map);
          if (scopedTokens[p['portionToken']] != null) {
            expectedAccounts.add(scopedTokens[p['portionToken']]!);
          }
          for (final a in assignments) {
            if (a['portionToken'] == p['portionToken']) {
              if (a['captureId'] != p['captureId'] ||
                  a['sourceInventoryRoot'] != p['sourceInventoryRoot'] ||
                  !matched.add(a['portionToken'])) {
                throw const FormatException(
                  'crypto_migration_domain_assignment',
                );
              }
            }
          }
          after = p['portionToken'];
          yield p;
        }
        if (page['hasMore'] != true) break;
        if (after == null || page['nextAfterToken'] != after) {
          throw const FormatException('crypto_migration_domain_assignment');
        }
        page = await runtime.account.directory.call(
          'crypto2.migration.capture.commitments',
          {
            'migrationId': header['migrationId'],
            'limit': 50,
            'afterToken': after,
          },
        );
      }
    }

    final inventory = await CryptoMigrationCommitmentsV3.inventoryCommitment(
      serverId: header['serverId'],
      migrationId: header['migrationId'],
      componentId: header['componentId'],
      portionCount: publicInventory['portionCount'],
      portions: portions(),
    );
    if (header['domain'] == 'finance') {
      expectedAccounts
        ..clear()
        ..add(materializer as String);
    }
    final actualAccounts = assignments
        .map((a) => a['accountId'] as String)
        .toSet();
    if (inventory != header['inventoryCommitment'] ||
        matched.length != assignments.length ||
        !actualAccounts.containsAll(expectedAccounts) ||
        !expectedAccounts.containsAll(actualAccounts)) {
      throw const FormatException('crypto_migration_domain_assignment');
    }
    final captures = <String>{}, tokens = <String>{};
    for (final a in assignments) {
      CryptoMigrationBusinessParityV3.exact(a, {
        'accountId',
        'portionToken',
        'captureId',
        'sourceInventoryRoot',
        'sourceRowCount',
        'leafCount',
      });
      final id = a['accountId'];
      head.member(id);
      final token = await cryptoSha256([
        ...utf8.encode('JivieMigrationPortion/v2\n'),
        ...CryptoJson.encode({
          'version': 2,
          'serverId': header['serverId'],
          'migrationId': header['migrationId'],
          'accountId': id,
        }),
      ]);
      if (previous != null && previous.compareTo(id) >= 0 ||
          token != a['portionToken'] ||
          !captures.add(a['captureId']) ||
          !tokens.add(token) ||
          !CryptoMigrationBusinessParityV3.count(a['sourceRowCount']) ||
          !CryptoMigrationBusinessParityV3.count(a['leafCount']) ||
          a['leafCount'] < a['sourceRowCount'] ||
          id != materializer &&
              (a['sourceRowCount'] != 0 || a['leafCount'] != 0) ||
          header['domain'] == 'finance' &&
              (assignments.length != 1 || id != materializer)) {
        throw const FormatException('crypto_migration_domain_assignment');
      }
      previous = id;
      sources += a['sourceRowCount'] as int;
      leaves += a['leafCount'] as int;
    }
    if (sources != header['sourceRowCount'] ||
        leaves != header['materializedRecordProofCount'] ||
        !assignments.any((a) => a['accountId'] == materializer)) {
      throw const FormatException('crypto_migration_domain_assignment');
    }
  }

  Future<Map<String, dynamic>> _anchorCertificate(
    String migration,
    String scopeId,
    String domain,
    Map<String, dynamic> header,
    Map<String, dynamic> result,
  ) async {
    final entry = await runtime.account.attestMigration(
      migrationId: migration,
      scopeToken: header['scopeToken'],
      domain: domain,
      attestationHash: result['certificateHash'],
    );
    runtime.access.invalidateAuthorityOperation();
    return _send(
      'domainAnchor3:$migration:$scopeId:$domain',
      'crypto2.migration.domains.anchor',
      {
        'migrationId': migration,
        'scopeId': scopeId,
        'domain': domain,
        'certificateHash': result['certificateHash'],
        'eventAuthorization': entry['authorization'],
      },
    );
  }

  Future<({Map<String, dynamic> payload, Map<String, dynamic> result})?>
  _existing(String action, String operation) async {
    final rows = await runtime.db.rows(
      'SELECT o.request_id,o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
      [partition, action],
    );
    if (rows.isEmpty) return null;
    if (rows.length != 1) {
      throw const FormatException('crypto_migration_domain_immutable');
    }
    final proof = Map<String, dynamic>.from(
      jsonDecode(rows.single['signed_body'] as String) as Map,
    );
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    if (body['accountId'] != runtime.account.directory.accountId ||
        body['serverId'] !=
            runtime.account.directory.session.profile.serverId ||
        body['operation'] != operation) {
      throw const FormatException('crypto_migration_domain_immutable');
    }
    final queue = coordinator.queue;
    await queue.resumeUnresolved(
      requestIds: {rows.single['request_id'] as String},
    );
    return (
      payload: Map<String, dynamic>.from(body['payload'] as Map),
      result: await queue.commandResult(rows.single['request_id'] as String),
    );
  }

  Future<Map<String, dynamic>> _send(
    String action,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final queue = coordinator.queue;
    final request = await queue.enqueueCommand(
      actionKey: action,
      operation: operation,
      payload: payload,
    );
    await queue.resumeUnresolved(requestIds: {request});
    return queue.commandResult(request);
  }
}
