import 'dart:convert';
import 'dart:typed_data';
import 'package:sodium/sodium.dart' show KeyPair;

import 'account_directory_v2.dart';
import 'crypto_account_archive.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_document_backup_drafts.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart' show CryptoKeyLease;
import 'crypto_migration_business_parity_v3.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_local_intents.dart';
import 'crypto_migration_receipt_codec.dart';
import 'crypto_migration_own_attestation.dart';

/// Only this full FILE-pinned streaming verifier can create the capability.
/// Its SQL rows are quarantined observations, never deliverable legacy queues.
class VerifiedCryptoMigrationLocalArtifact {
  VerifiedCryptoMigrationLocalArtifact._(this.result, this.descriptor);
  final Map<String, dynamic> result, descriptor;
}

Future<VerifiedCryptoMigrationLocalArtifact>
verifyCryptoMigrationLocalArtifact({
  required CryptoBusinessSession runtime,
  required VerifiedCryptoCaptureArchive source,
  required Uint8List recoveryFile,
  required Map<String, dynamic> descriptor,
  required Map<String, dynamic> ownEvent,
}) async {
  final evidence = CryptoMigrationColdEvidence(runtime, source);
  return _verifyCryptoMigrationLocalArtifact(
    runtime: runtime,
    common: evidence.common,
    own: await evidence.own(),
    recoveryFile: recoveryFile,
    descriptor: descriptor,
    ownEvent: ownEvent,
  );
}

/// Own-log authenticated private installation work can be recovered separately
/// from a shared source archive. It always remains quarantined for review.
Future<VerifiedCryptoMigrationLocalArtifact>
restoreCryptoMigrationOwnLocalArtifact({
  required CryptoBusinessSession runtime,
  required VerifiedCryptoOwnAttestation attestation,
  required Uint8List recoveryFile,
  required Map<String, dynamic> ownEvent,
}) async {
  if (!attestation.privateArtifact || attestation.descriptor == null) {
    throw const FormatException('crypto_local_artifact_capability');
  }
  final inspected = runtime.account.files.inspect(
    recoveryFile,
    serverId: runtime.account.directory.session.profile.serverId,
    accountId: runtime.account.directory.accountId,
  );
  final own = await runtime.account.directory.replayFileAnchoredCandidate(
    inspected['fingerprint'],
  );
  final descriptor = attestation.descriptor!;
  final context = Map<String, dynamic>.from(descriptor['context'] as Map);
  final common = {
    for (final k in [
      'version',
      'serverId',
      'migrationId',
      'captureId',
      'accountId',
      'sourceInventoryRoot',
    ])
      k: context[k],
  };
  CryptoMigrationReceiptCodec.common(common);
  return _verifyCryptoMigrationLocalArtifact(
    runtime: runtime,
    common: common,
    own: own,
    recoveryFile: recoveryFile,
    descriptor: descriptor,
    ownEvent: ownEvent,
  );
}

Future<VerifiedCryptoMigrationLocalArtifact>
_verifyCryptoMigrationLocalArtifact({
  required CryptoBusinessSession runtime,
  required Map<String, dynamic> common,
  required VerifiedAccountDirectory own,
  required Uint8List recoveryFile,
  required Map<String, dynamic> descriptor,
  required Map<String, dynamic> ownEvent,
}) async {
  CryptoMigrationBusinessParityV3.exact(descriptor, {
    'context',
    'manifest',
    'intentCount',
  });
  final context = Map<String, dynamic>.from(descriptor['context'] as Map);
  CryptoMigrationBusinessParityV3.exact(context, {
    ...common.keys,
    'artifactId',
    'purpose',
  });
  if (context['purpose'] != 'migrationLocalIntents' ||
      !CryptoMigrationBusinessParityV3.count(descriptor['intentCount'])) {
    throw const FormatException('crypto_local_artifact_context');
  }
  for (final entry in common.entries) {
    if (context[entry.key] != entry.value) {
      throw const FormatException('crypto_local_artifact_context');
    }
  }
  final manifest = CryptoArchiveManifest.fromJson(
    Map<String, dynamic>.from(descriptor['manifest'] as Map),
  );
  if (manifest.artifactKind != 'migrationLocalIntentsV3' ||
      manifest.artifactId != context['artifactId'] ||
      manifest.migrationId != common['migrationId'] ||
      !CryptoMigrationColdEvidence.same(manifest.artifactContext, context) ||
      manifest.segments.isEmpty ||
      manifest.segments.length > 16 ||
      manifest.segments.fold<int>(0, (n, s) => n + s.size) >
          256 * 1024 * 1024) {
    throw const FormatException('crypto_local_artifact_manifest');
  }
  final command =
      CryptoJson.decode(cryptoBase64(ownEvent['commandBase64'])) as Map;
  final hash = await cryptoSha256(CryptoInventoryJson.encode(descriptor));
  final token = await cryptoSha256([
    ...utf8.encode('JivieMigrationLocalIntentToken/v3\n'),
    ...CryptoInventoryJson.encode({
      ...common,
      'artifactId': context['artifactId'],
    }),
  ]);
  final eventHash = await cryptoSha256(cryptoBase64(ownEvent['commandBase64']));
  final included = await runtime.account.store.entryByHash(
    own.accountId,
    eventHash,
  );
  final payload = command['payload'];
  if (command['operation'] != 'crypto2.account.migrationAttest' ||
      command['serverId'] != own.serverId ||
      command['accountId'] != own.accountId ||
      payload is! Map ||
      payload['migrationId'] != common['migrationId'] ||
      payload['scopeToken'] != token ||
      payload['domain'] != 'content' ||
      payload['attestationHash'] != hash ||
      included == null ||
      !own.includesAnchor(included['generation'], included['headHash']) ||
      !CryptoMigrationColdEvidence.same(included['authorization'], ownEvent)) {
    throw const FormatException('crypto_local_artifact_anchor');
  }
  final status = await runtime.account.status();
  final root = cryptoBase64(status['keyringCiphertextBase64']);
  if (await cryptoSha256(root) != own.snapshot['recoveryRootCiphertextHash']) {
    throw const FormatException('crypto_local_artifact_root');
  }
  final inspected = runtime.account.files.inspect(
    recoveryFile,
    serverId: own.serverId,
    accountId: own.accountId,
  );
  final recovered = runtime.account.files.open(
    file: recoveryFile,
    encryptedRoot: CryptoJson.decode(root) as Map<String, dynamic>,
    serverId: own.serverId,
    accountId: own.accountId,
    expectedFingerprint: inspected['fingerprint'],
  );
  final crypto = runtime.codec.crypto;
  final keys = CryptoAccountArchiveKeyService(runtime.account);
  late final CryptoKeyLease key;
  try {
    Future<KeyPair?> recoveryKey(String public) async {
      for (final pair in [
        recovered.encryption,
        ...recovered.historicalEncryption,
      ]) {
        if (base64Encode(pair.publicKey) != public) continue;
        final bytes = pair.secretKey.extractBytes();
        try {
          return KeyPair(
            publicKey: Uint8List.fromList(pair.publicKey),
            secretKey: crypto.sodium.secureCopy(bytes),
          );
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      return null;
    }

    key = await keys.openBoundKey(
      keyId: manifest.keyId,
      expectedContext: keys.context(manifest),
      recoveryOnly: true,
      recoveryDirectory: own,
      recoveryKey: recoveryKey,
    );
  } finally {
    recovered.dispose();
  }
  final staging = CryptoArchiveStagingStore(
    database: runtime.db,
    partition: runtime.partition,
    crypto: crypto,
  );
  try {
    for (final segment in manifest.segments) {
      Stream<List<int>> download() async* {
        var offset = 0;
        while (offset < segment.size) {
          final page = await runtime.account.directory
              .call('crypto2.migration.archiveGet', {
                'migrationId': common['migrationId'],
                'id': segment.id,
                'offset': offset,
              });
          if (page['id'] != segment.id ||
              page['complete'] != true ||
              page['size'] != segment.size ||
              page['sha256'] != segment.sha256 ||
              page['offset'] != offset) {
            throw const FormatException('crypto_local_artifact_remote');
          }
          final description =
              CryptoJson.decode(cryptoBase64(page['manifestBase64'])) as Map;
          if (!CryptoMigrationColdEvidence.same(description, {
            'version': 3,
            'keyId': manifest.keyId,
            'cipherManifestHash': manifest.cipherManifestHash,
            'index': segment.index,
            'artifactKind': 'migrationLocalIntentsV3',
            'artifact': descriptor,
          })) {
            throw const FormatException('crypto_local_artifact_remote');
          }
          final bytes = cryptoBase64(
            page['dataBase64'],
            max: CryptoArchiveStagingStore.chunkSize,
          );
          if (bytes.isEmpty || page['nextOffset'] != offset + bytes.length) {
            throw const FormatException('crypto_local_artifact_cursor');
          }
          offset += bytes.length;
          yield bytes;
        }
      }

      await staging.importSegment(
        manifest: manifest,
        segment: segment,
        ciphertext: download(),
      );
    }
    await runtime.db.execute(
      'CREATE TABLE IF NOT EXISTS cold_local_intents(artifact_id TEXT NOT NULL,ordinal INTEGER NOT NULL,frame TEXT NOT NULL,PRIMARY KEY(artifact_id,ordinal))',
    );
    var count = 0;
    await runtime.db.transaction(() async {
      await runtime.db.execute(
        'DELETE FROM cold_local_intents WHERE artifact_id=?',
        [manifest.artifactId],
      );
      var phase = 0;
      await for (final line in _lines(staging.open(manifest, key.key))) {
        final f = jsonDecode(line) as Map<String, dynamic>;
        if (CryptoInventoryJson.canonical(f) != line) {
          throw const FormatException('crypto_local_artifact_frame');
        }
        if (phase == 0) {
          if (!CryptoMigrationColdEvidence.same(f, {
            'kind': 'localIntentHeader',
            'version': 3,
            'artifactId': manifest.artifactId,
            'partition': runtime.partition,
            'captureId': common['captureId'],
            'migrationId': common['migrationId'],
            'sourceInventoryRoot': common['sourceInventoryRoot'],
          })) {
            throw const FormatException('crypto_local_artifact_header');
          }
          phase = 1;
          continue;
        }
        if (f['kind'] == 'localIntentFooter') {
          if (phase != 1 ||
              !CryptoMigrationColdEvidence.same(f, {
                'kind': 'localIntentFooter',
                'version': 3,
                'artifactId': manifest.artifactId,
                'intentCount': count,
              }) ||
              count != descriptor['intentCount']) {
            throw const FormatException('crypto_local_artifact_count');
          }
          phase = 2;
          continue;
        }
        if (phase != 1) {
          throw const FormatException('crypto_local_artifact_trailing');
        }
        _privateFrame(f, runtime.partition, common);
        if (++count > descriptor['intentCount']) {
          throw const FormatException('crypto_local_artifact_count');
        }
        await runtime.db.execute(
          'INSERT INTO cold_local_intents VALUES(?,?,?)',
          [manifest.artifactId, count, line],
        );
      }
      if (phase != 2) {
        throw const FormatException('crypto_local_artifact_incomplete');
      }
    });
    final result = {
      'artifactId': manifest.artifactId,
      'cipherManifestHash': manifest.cipherManifestHash,
      'intentCount': count,
      'ownEventCommandHash': eventHash,
    };
    CryptoMigrationReceiptCodec.local(result);
    return VerifiedCryptoMigrationLocalArtifact._(
      Map.unmodifiable(result),
      Map.unmodifiable(descriptor),
    );
  } finally {
    key.release();
  }
}

void _privateFrame(
  Map<String, dynamic> f,
  String partition,
  Map<String, dynamic> common,
) {
  final row = f['row'];
  if (row is! Map) throw const FormatException('crypto_local_artifact_frame');
  if (f['kind'] == 'cryptoReceiptRow') {
    CryptoMigrationLocalIntentSnapshot.validateReceiptFrame(
      f,
      partition: partition,
      serverId: common['serverId'],
      accountId: common['accountId'],
    );
  } else if (f['kind'] == 'legacyRow') {
    CryptoMigrationBusinessParityV3.exact(f, {'kind', 'table', 'row'});
    final table = f['table'];
    if (table == 'local_meta') {
      if (row.length != 2 ||
          row['name'] is! String ||
          !CryptoMigrationLocalIntentSnapshot.metadataPrefixes.any(
            (p) => (row['name'] as String).startsWith('$p$partition:'),
          )) {
        throw const FormatException('crypto_local_artifact_partition');
      }
    } else if (table == 'linked_payment_intents') {
      final data = jsonDecode(row['data'] as String);
      if (data is! Map || data['partition'] != partition) {
        throw const FormatException('crypto_local_artifact_partition');
      }
    } else if (!CryptoMigrationLocalIntentSnapshot.queueTables.contains(
          table,
        ) ||
        row['partition'] != partition) {
      throw const FormatException('crypto_local_artifact_partition');
    }
  } else if (f['kind'] == 'ideaDraftRow') {
    CryptoMigrationBusinessParityV3.exact(f, {'kind', 'table', 'row'});
    final table = f['table'];
    final keys = table == 'idea_drafts'
        ? const {'workspace', 'id', 'payload', 'base'}
        : table == 'idea_assets'
        ? const {'workspace', 'sha256', 'metadata', 'bytes'}
        : <String>{};
    if (keys.isEmpty ||
        row.length != keys.length ||
        !row.keys.every(keys.contains) ||
        row['workspace'] is! String ||
        !(row['workspace'] as String).startsWith('shared:$partition:') ||
        row.values.any((v) => v != null && v is! String)) {
      throw const FormatException('crypto_local_artifact_partition');
    }
    if (table == 'idea_assets') cryptoBase64(row['bytes'], max: 2097152);
  } else if (f['kind'] == 'draftRow') {
    CryptoMigrationBusinessParityV3.exact(f, {
      'kind',
      'candidateId',
      'partition',
      'table',
      'row',
    });
    final columns = cryptoDocumentDraftTables[f['table']];
    if (f['partition'] != partition ||
        columns == null ||
        row.keys.any((k) => !columns.contains(k)) ||
        row.length != columns.length ||
        row['partition'] != partition) {
      throw const FormatException('crypto_local_artifact_partition');
    }
  } else {
    throw const FormatException('crypto_local_artifact_frame');
  }
}

Stream<String> _lines(Stream<List<int>> source) async* {
  var pending = BytesBuilder(copy: false), total = 0;
  await for (final chunk in source) {
    total += chunk.length;
    if (total > 240 * 1024 * 1024) {
      throw const FormatException('crypto_local_artifact_capacity');
    }
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 10) continue;
      pending.add(chunk.sublist(start, i));
      if (pending.length > 32 * 1024 * 1024) {
        throw const FormatException('crypto_local_artifact_frame_size');
      }
      yield utf8.decode(pending.takeBytes());
      start = i + 1;
    }
    pending.add(chunk.sublist(start));
    if (pending.length > 32 * 1024 * 1024) {
      throw const FormatException('crypto_local_artifact_frame_size');
    }
  }
  if (pending.length != 0) {
    throw const FormatException('crypto_local_artifact_truncated');
  }
}
