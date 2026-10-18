import 'dart:typed_data';

import 'crypto_business_router.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_activation_v3.dart';
import 'crypto_migration_business_parity_v3.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_commitments_v3.dart';
import 'crypto_migration_committed_origin.dart';
import 'crypto_migration_domain_contributions.dart';

/// Manager's explicit final scoped publication. The whole-component commit
/// transports only opaque references to these independently signed approvals.
class CryptoMigrationActivationProducer {
  CryptoMigrationActivationProducer(this.runtime);
  final CryptoBusinessSession runtime;
  static Map<String, dynamic> map(Object? value) =>
      Map<String, dynamic>.from(value as Map);
  static Map<String, dynamic> body(Map<String, dynamic> proof) =>
      map(CryptoJson.decode(cryptoBase64(proof['commandBase64'])));
  static bool same(Object? a, Object? b) =>
      CryptoInventoryJson.canonical(a) == CryptoInventoryJson.canonical(b);

  Future<Map<String, dynamic>> stage({
    required VerifiedCryptoMigrationColdBusiness verified,
    required String scopeId,
  }) async {
    final migration = verified.header['migrationId'];
    final journal = 'activation3:$migration:$scopeId';
    final saved = await runtime.db.rows(
      'SELECT payload,authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [runtime.partition, migration, journal],
    );
    late Map<String, dynamic> h, proof;
    if (saved.isNotEmpty) {
      if (saved.length != 1) {
        throw const FormatException('crypto_migration_activation_immutable');
      }
      h = map(
        CryptoJson.decode(
          Uint8List.fromList((saved.single['payload'] as List).cast<int>()),
        ),
      );
      proof = map(
        CryptoJson.decode(
          Uint8List.fromList(
            (saved.single['authorization'] as List).cast<int>(),
          ),
        ),
      );
      if (h['scopeId'] != scopeId ||
          h['migrationId'] != migration ||
          ![
            'serverId',
            'componentId',
            'componentCommitment',
          ].every((k) => h[k] == verified.header[k])) {
        throw const FormatException('crypto_migration_activation_immutable');
      }
    } else {
      Map<String, dynamic> page = await runtime.account.directory.call(
        'crypto2.migration.activation',
        {'scopeId': scopeId, 'limit': 20},
      );
      if (page['candidate'] != true) {
        throw const FormatException('crypto_migration_activation_state');
      }
      h = map(page['header']);
      CryptoMigrationActivationV3.validate(h);
      if (h['componentCommitment'] !=
          await CryptoMigrationCommitmentsV3.componentCommitment(
            serverId: h['serverId'],
            migrationId: h['migrationId'],
            componentId: h['componentId'],
            inventoryCommitment: h['inventoryCommitment'],
          )) {
        throw const FormatException('crypto_migration_activation_context');
      }
      final candidate = await runtime.access.migrationCandidate(
        scopeId: scopeId,
        migrationId: migration,
        captureId: verified.header['captureId'],
        headHash: h['membershipHeadHash'],
      );
      final head = candidate.head,
          own = await runtime.account.directory.requireFresh();
      if (h['scopeId'] != scopeId ||
          h['migrationId'] != migration ||
          h['managerAccountId'] != own.accountId ||
          h['managerDirectoryHeadHash'] != own.headHash ||
          h['membershipHeadHash'] != head.headHash ||
          h['lifecycleHash'] != await candidate.lifecycleHash() ||
          head.member(own.accountId)['manageKeys'] != true ||
          ![
            'serverId',
            'componentId',
            'componentCommitment',
          ].every((k) => h[k] == verified.header[k])) {
        throw const FormatException('crypto_migration_activation_context');
      }
      final certificates = map(page['domainCertificates']),
          events = map(page['domainEvents']);
      final domainPayloads = <String, Map<String, dynamic>>{};
      final verifier = CryptoMigrationCommittedOrigin(runtime.access);
      for (final domain in ['content', 'finance']) {
        final certificate = map(certificates[domain]);
        final payload = await CryptoMigrationDomainContributions(
          runtime,
        ).verifyCertificateCandidate(certificate);
        final dh = map(payload['header']);
        if (dh['domain'] != domain ||
            ![
              'serverId',
              'migrationId',
              'componentId',
              'componentCommitment',
              'inventoryCommitment',
              'scopeId',
              'membershipHeadHash',
              'managerAccountId',
            ].every((k) => dh[k] == h[k]) ||
            await runtime.codec.digest(certificate) !=
                h['${domain}CertificateHash']) {
          throw const FormatException(
            'crypto_migration_activation_certificate',
          );
        }
        await verifier.event(
          map(events[domain]),
          certificate,
          scopeId: scopeId,
          headHash: head.headHash,
          accountId: dh['managerAccountId'],
          prefixHead: dh['managerDirectoryHeadHash'],
          migrationId: migration,
          domain: domain,
          token: dh['scopeToken'],
          candidate: candidate,
        );
        domainPayloads[domain] = payload;
      }
      final expected = <String, Map<String, dynamic>>{};
      for (final item in domainPayloads['content']!['contributions'] as List) {
        final c = body(map(item['authorization'])),
            p = map(c['payload']),
            ch = map(p['header']);
        for (final kind in [
          'audit',
          'invitations',
          'notifications',
          'receipts',
          'structure',
        ]) {
          final section = kind == 'audit'
                  ? CryptoMigrationBusinessParityV3.scopedAudit(
                      p['scopeControlSections'],
                    )
                  : p['controlSections'][kind],
              link = p['controlLinks'][kind];
          final leaf = <String, dynamic>{
            'version': 3,
            'scopeId': scopeId,
            'kind': kind,
            'portionToken': ch['portionToken'],
            'captureId': ch['captureId'],
            'sourceInventoryRoot': ch['sourceInventoryRoot'],
            'verify3ProofHash': ch['coldParityProofHash'],
            'selectionCount': section['count'],
            'selectionRoot': section['root'],
            'certificateHash': link?['certificateHash'],
            'eventCommandHash': link?['eventCommandHash'],
          };
          final hash = await CryptoMigrationActivationV3.controlHash(leaf);
          if (expected.containsKey(hash)) {
            throw const FormatException(
              'crypto_migration_activation_duplicate',
            );
          }
          expected[hash] = leaf;
        }
      }
      if (expected.length != h['controlCount'] || expected.length > 5000) {
        throw const FormatException('crypto_migration_activation_coverage');
      }
      final hashes = expected.keys.toList()..sort();
      if (await CryptoMigrationActivationV3.controlRoot(
            h,
            Stream.fromIterable(hashes),
          ) !=
          h['controlRoot']) {
        throw const FormatException('crypto_migration_activation_coverage');
      }
      var matched = 0;
      String? after;
      while (true) {
        if (!same(page['header'], h) ||
            !same(page['domainCertificates'], certificates) ||
            !same(page['domainEvents'], events)) {
          throw const FormatException('crypto_migration_activation_changed');
        }
        final controls = page['controls'];
        if (controls is! List || controls.length > 20) {
          throw const FormatException('crypto_migration_activation_coverage');
        }
        for (final item in controls) {
          final hash = item['controlHash'];
          if (hash is! String ||
              after != null && after.compareTo(hash) >= 0 ||
              !same(expected[hash], item['control'])) {
            throw const FormatException('crypto_migration_activation_coverage');
          }
          after = hash;
          matched++;
        }
        if (page['hasMore'] == false) break;
        if (page['hasMore'] != true ||
            page['nextAfterHash'] != after ||
            after == null) {
          throw const FormatException('crypto_migration_activation_coverage');
        }
        page = await runtime.account.directory.call(
          'crypto2.migration.activation',
          {'scopeId': scopeId, 'afterHash': after, 'limit': 20},
        );
      }
      if (matched != expected.length) {
        throw const FormatException('crypto_migration_activation_coverage');
      }
      final key = await runtime.account.signingKey();
      try {
        proof = runtime.codec.crypto.signDomain(
          h,
          key.key,
          'JivieMigrationActivation/v3\n',
        );
      } finally {
        key.release();
      }
      await runtime.db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
        [
          runtime.partition,
          migration,
          journal,
          'migrationActivation',
          CryptoJson.encode(h),
          CryptoJson.encode(proof),
        ],
      );
    }
    final hash = await runtime.codec.digest(proof);
    final event = await runtime.account.attestMigration(
      migrationId: migration,
      scopeToken: await CryptoMigrationActivationV3.token(h),
      domain: 'content',
      attestationHash: hash,
    );
    runtime.access.invalidateAuthorityOperation();
    final request = await CryptoCaptureCoordinator(runtime.account).queue
        .enqueueCommand(
          actionKey: journal,
          operation: 'crypto2.migration.activation.stage',
          payload: {
            'authorization': proof,
            'eventAuthorization': event['authorization'],
          },
        );
    final queue = CryptoCaptureCoordinator(runtime.account).queue;
    await queue.resumeUnresolved(requestIds: {request});
    final result = await queue.commandResult(request);
    if (result['state'] != 'staged' || result['activationHash'] != hash) {
      throw const FormatException('crypto_migration_activation_receipt');
    }
    return {
      'scopeToken': await CryptoMigrationCommitmentsV3.scopeToken(
        serverId: h['serverId'],
        migrationId: migration,
        scopeId: scopeId,
        domain: 'content',
      ),
      'activationHash': hash,
    };
  }

  /// All scoped managers have already signed their final publication. This
  /// private trigger carries no foreign scope UUID or private control bundles.
  Future<Map<String, dynamic>> commit({
    required VerifiedCryptoMigrationColdBusiness verified,
    required List<Map<String, dynamic>> scopeActivations,
  }) async {
    if (scopeActivations.isEmpty || scopeActivations.length > 1000) {
      throw const FormatException('crypto_migration_activation_capacity');
    }
    String? previous;
    for (final ref in scopeActivations) {
      CryptoMigrationBusinessParityV3.exact(ref, {
        'scopeToken',
        'activationHash',
      });
      if (!CryptoMigrationBusinessParityV3.hash(ref['scopeToken']) ||
          !CryptoMigrationBusinessParityV3.hash(ref['activationHash']) ||
          previous != null && previous.compareTo(ref['scopeToken']) >= 0) {
        throw const FormatException('crypto_migration_activation_refs');
      }
      previous = ref['scopeToken'];
    }
    final headers = await runtime.db.rows(
      "SELECT payload,authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='migrationActivation'",
      [runtime.partition, verified.header['migrationId']],
    );
    String? inventory;
    for (final row in headers) {
      final h = map(
        CryptoJson.decode(
          Uint8List.fromList((row['payload'] as List).cast<int>()),
        ),
      );
      final proof = map(
        CryptoJson.decode(
          Uint8List.fromList((row['authorization'] as List).cast<int>()),
        ),
      );
      if (h['migrationId'] != verified.header['migrationId'] ||
          h['componentCommitment'] != verified.header['componentCommitment']) {
        throw const FormatException('crypto_migration_activation_context');
      }
      final hash = await runtime.codec.digest(proof);
      if (!scopeActivations.any((ref) => ref['activationHash'] == hash)) {
        throw const FormatException('crypto_migration_activation_refs');
      }
      if (inventory != null && inventory != h['inventoryCommitment']) {
        throw const FormatException('crypto_migration_activation_context');
      }
      inventory = h['inventoryCommitment'];
    }
    if (inventory == null) {
      throw const FormatException('crypto_migration_activation_pending');
    }
    final queue = CryptoCaptureCoordinator(runtime.account).queue;
    final request = await queue.enqueueCommand(
      actionKey: 'commit3:${verified.header['migrationId']}',
      operation: 'crypto2.migration.commit3',
      payload: {
        'version': 3,
        for (final k in ['migrationId', 'componentId', 'componentCommitment'])
          k: verified.header[k],
        'inventoryCommitment': inventory,
        'scopeActivations': scopeActivations,
      },
    );
    await queue.resumeUnresolved(requestIds: {request});
    final result = await queue.commandResult(request);
    if (result['state'] != 'committed' ||
        result['migrationId'] != verified.header['migrationId'] ||
        !same(result['scopeActivations'], scopeActivations)) {
      throw const FormatException('crypto_migration_commit_receipt');
    }
    return result;
  }
}
