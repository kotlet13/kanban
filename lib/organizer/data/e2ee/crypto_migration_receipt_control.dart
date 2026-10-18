import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_legacy.dart';
import 'crypto_json.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_local_artifact_cold.dart';
import 'crypto_migration_receipt_codec.dart';
import 'account_directory_v2.dart' show cryptoSha256;

/// The complete FILE-verified source archive already compared every original
/// request/outcome/response byte, including a combined task+cost ACK. This
/// control intersects its independent tuple roots with exact own-log certs.
class CryptoMigrationReceiptControl implements CryptoMigrationColdControl {
  CryptoMigrationReceiptControl(this.runtime, this.source, this.local)
    : evidence = CryptoMigrationColdEvidence(runtime, source);
  final CryptoBusinessSession runtime;
  final VerifiedCryptoCaptureArchive source;
  final VerifiedCryptoMigrationLocalArtifact local;
  final CryptoMigrationColdEvidence evidence;
  final _certs = <String, Map<String, dynamic>>{};
  final _counts = {'content': 0, 'finance': 0};
  Future<void> _prepare() async {
    if (_certs.isNotEmpty) return;
    final own = await evidence.own();
    final localContext = local.descriptor['context'] as Map;
    for (final e in evidence.common.entries) {
      if (localContext[e.key] != e.value) {
        throw const FormatException('crypto_receipts_context');
      }
    }
    for (final domain in ['content', 'finance']) {
      final result = await runtime.account.directory.call(
        'crypto2.migration.legacy.status',
        {'migrationId': source.capture.migrationId, 'domain': domain},
      );
      final cert = Map<String, dynamic>.from(
        result['certificateAuthorization'] as Map,
      );
      final event = Map<String, dynamic>.from(
        result['eventAuthorization'] as Map,
      );
      final command =
          CryptoJson.decode(cryptoBase64(cert['commandBase64'])) as Map;
      final p = command['payload'] as Map,
          header = Map<String, dynamic>.from(p['header'] as Map);
      final expected = CryptoLegacyReceiptInventory.header(
        serverId: own.serverId,
        accountId: own.accountId,
        captureId: source.capture.captureId,
        migrationId: source.capture.migrationId,
        domain: domain,
        sourceInventoryRoot: source.sourceInventoryRoot,
        archiveManifestHash: source.manifest.cipherManifestHash,
        receiptCount: source.receiptCounts[domain]!,
        receiptSelectionHash: await CryptoLegacyReceiptInventory.selectionHash(
          serverId: own.serverId,
          accountId: own.accountId,
          captureId: source.capture.captureId,
          migrationId: source.capture.migrationId,
          receiptSelections: source.capture.receiptSelections,
        ),
      );
      if (command['version'] != 2 ||
          command['signer'] != 'device' ||
          command['operation'] != 'crypto2.migration.legacy.certify' ||
          command['serverId'] != own.serverId ||
          command['accountId'] != own.accountId ||
          p.length != 4 ||
          !CryptoMigrationColdEvidence.same(header, expected) ||
          p['manifestRoot'] != source.receiptRoots[domain]) {
        throw const FormatException('crypto_receipts_certificate');
      }
      final prefix = await evidence.ownAt(p['authorDirectoryHeadHash']);
      runtime.codec.crypto.verifyDomain(
        cert,
        cryptoBase64(
          prefix.activeDevice(command['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        'JivieE2EE/v2\n',
      );
      final eventBody =
          CryptoJson.decode(cryptoBase64(event['commandBase64'])) as Map;
      final ep = eventBody['payload'] as Map;
      final eventHash = await cryptoSha256(
        cryptoBase64(event['commandBase64']),
      );
      final row = await runtime.account.store.entryByHash(
        own.accountId,
        eventHash,
      );
      final certHash = await cryptoSha256(CryptoJson.encode(cert));
      if (eventBody['operation'] != 'crypto2.account.migrationAttest' ||
          eventBody['accountId'] != own.accountId ||
          eventBody['serverId'] != own.serverId ||
          ep['migrationId'] != source.capture.migrationId ||
          ep['domain'] != domain ||
          ep['scopeToken'] !=
              await CryptoLegacyReceiptInventory.scopeToken(header) ||
          ep['attestationHash'] != certHash ||
          row == null ||
          !own.includesAnchor(row['generation'], row['headHash']) ||
          !CryptoMigrationColdEvidence.same(row['authorization'], event)) {
        throw const FormatException('crypto_receipts_anchor');
      }
      _certs[domain] = {
        'certificateHash': certHash,
        'manifestRoot': p['manifestRoot'],
        'receiptCount': header['receiptCount'],
      };
    }
  }

  @override
  Future<String> verify(CryptoMigrationColdSource row) async {
    await _prepare();
    final domain = switch (row.context.sourceTable) {
      'familyhub_finance_operations' => 'finance',
      'familyhub_operations' || 'familyhub_document_requests' => 'content',
      _ => throw const FormatException('crypto_receipts_source'),
    };
    if (row.context.accountId != runtime.account.directory.accountId ||
        row.context.captureId != source.capture.captureId ||
        row.context.migrationId != source.capture.migrationId) {
      throw const FormatException('crypto_receipts_context');
    }
    _counts[domain] = _counts[domain]! + 1;
    return CryptoMigrationReceiptCodec.artifact(
      bindingId: row.binding.bindingId,
      sourceCommitment: row.binding.sourceCommitment,
      domain: domain,
      cert: _certs[domain]!,
    );
  }

  @override
  Future<Map<String, dynamic>> finish() async {
    await _prepare();
    for (final domain in ['content', 'finance']) {
      if (_counts[domain] != source.receiptCounts[domain]) {
        throw const FormatException('crypto_receipts_coverage');
      }
    }
    return CryptoMigrationReceiptCodec.section(
      context: evidence.common,
      content: _certs['content']!,
      finance: _certs['finance']!,
      localIntents: local.result,
    );
  }
}
