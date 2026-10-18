import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:sodium/sodium.dart';

import 'account_crypto_v2_workflow.dart';
import 'account_directory_repository.dart';
import 'account_directory_v2.dart';
import 'crypto_account_archive.dart';
import 'crypto_archive_cold_database.dart';
import 'crypto_archive_cold_restore.dart';
import 'crypto_identity_store.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';

/// The migration archive is account-private, even when its source rows came
/// from shared scopes. This path never sends the recovery file or raw DEK.
class CryptoMigrationArchive {
  CryptoMigrationArchive({
    required this.account,
    required this.queue,
    this.verifyColdBusiness,
    Future<CryptoArchiveColdDatabase> Function()? coldDatabase,
  }) : _coldDatabase = coldDatabase ?? CryptoArchiveColdDatabase.create;
  final Future<CryptoArchiveColdDatabase> Function() _coldDatabase;
  final AccountCryptoV2Workflow account;
  final CryptoSyncRepository queue;
  final Future<void> Function(
    CryptoArchiveColdDatabase cold,
    AccountCryptoV2Workflow account,
    Map<String, dynamic> header,
  )?
  verifyColdBusiness;
  String get partition => account.store.partition;
  Future<Map<String, dynamic>> _read(
    String operation,
    Map<String, dynamic> payload,
  ) => account.directory.call(operation, payload);
  Future<Map<String, dynamic>> _write(
    String action,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final id = await queue.enqueueCommand(
      actionKey: action,
      operation: operation,
      payload: payload,
    );
    await queue.resumeUnresolved(requestIds: {id});
    return queue.commandResult(id);
  }

  Future<Map<String, dynamic>> archiveAndVerify(
    String migrationId,
    Uint8List externalFile,
  ) async {
    final crypto = account.directory.reducer.crypto;
    final snapshot = await _read('crypto2.migration.inventory', {
      'migrationId': migrationId,
    });
    final inventory = Map<String, dynamic>.from(snapshot['inventory'] as Map);
    final hash = await CryptoInventoryJson.hash(inventory);
    if (!['fenced', 'verified'].contains(snapshot['state']) ||
        snapshot['inventoryHash'] != hash ||
        inventory['serverId'] != account.directory.session.profile.serverId ||
        inventory['accountId'] != account.directory.accountId) {
      throw const FormatException('crypto_archive_inventory');
    }
    // Only the exact consented own fence permits raw capture. The server's
    // unsigned inventory response cannot substitute a different source set.
    var consent = false;
    final commands = await account.store.database.rows(
      "SELECT signed_body FROM crypto_outbox WHERE partition=? AND operation='crypto2.migration.fence' AND state='applied'",
      [partition],
    );
    for (final row in commands) {
      final signed = jsonDecode(row['signed_body'] as String) as Map;
      final command =
          CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
      final p = command['payload'] as Map;
      if (p['migrationId'] == migrationId && p['inventoryHash'] == hash)
        consent = true;
    }
    if (!consent)
      throw const CryptoAuthorityPending('crypto_archive_consent_pending');
    final header = <String, dynamic>{
      'kind': 'header',
      'version': 2,
      'serverId': account.directory.session.profile.serverId,
      'accountId': account.directory.accountId,
      'migrationId': migrationId,
      'inventoryHash': hash,
      'challenge': snapshot['challenge'],
      'inventory': inventory,
    };
    final staging = CryptoArchiveStagingStore(
      database: account.store.database,
      partition: partition,
      crypto: crypto,
    );
    final jobs = await account.store.database.rows(
      'SELECT state FROM crypto_archive_jobs WHERE partition=? AND migration_id=?',
      [partition, migrationId],
    );
    if (jobs.isNotEmpty && jobs.single['state'] == 'draft') {
      await staging.abandonUnpublished(migrationId);
    }
    final manifest = await staging.stage(
      migrationId: migrationId,
      plaintext: _source(migrationId, header),
    );
    final keys = CryptoAccountArchiveKeyService(account);
    await keys.publish(manifest);
    for (final segment in manifest.segments) {
      final description = base64Encode(
        CryptoInventoryJson.encode({
          'version': 2,
          'keyId': manifest.keyId,
          'cipherManifestHash': manifest.cipherManifestHash,
          'index': segment.index,
        }),
      );
      await _write(
        'archive:$migrationId:${segment.id}:begin',
        'crypto2.migration.archiveBegin',
        {
          'migrationId': migrationId,
          'id': segment.id,
          'size': segment.size,
          'sha256': segment.sha256,
          'manifestBase64': description,
        },
      );
      var offset = 0;
      await for (final bytes in staging.cipher(segment)) {
        await _write(
          'archive:$migrationId:${segment.id}:$offset',
          'crypto2.migration.archiveChunk',
          {
            'migrationId': migrationId,
            'id': segment.id,
            'offset': offset,
            'dataBase64': base64Encode(bytes),
          },
        );
        offset += bytes.length;
      }
      await _write(
        'archive:$migrationId:${segment.id}:complete',
        'crypto2.migration.archiveComplete',
        {'migrationId': migrationId, 'id': segment.id},
      );
    }
    await account.store.database.execute(
      "UPDATE crypto_archive_jobs SET state='uploaded' WHERE partition=? AND migration_id=?",
      [partition, migrationId],
    );
    // A fresh encrypted SQL database receives SERVER bytes. Reopen the account
    // directory and archive recovery envelope there; the staging key is absent.
    final cold = await _coldDatabase();
    CryptoKeyLease? archiveKey;
    try {
      final coldStore = CryptoIdentityStore(
        cold.database,
        account.store.secure,
        partition,
      );
      final directory = AccountDirectoryRepository(
        reducer: account.directory.reducer,
        session: account.directory.session,
        transport: account.directory.transport,
        store: coldStore,
        isCurrent: account.directory.isCurrent,
      );
      final file = account.files.inspect(
        externalFile,
        serverId: account.directory.session.profile.serverId,
        accountId: account.directory.accountId,
      );
      final verified = await directory.refresh(
        externalFingerprint: file['fingerprint'] as String,
      );
      if (verified == null)
        throw const CryptoAuthorityPending('crypto_archive_identity_pending');
      final status = await directory.call('crypto2.account.status');
      final rootCipher = cryptoBase64(status['keyringCiphertextBase64']);
      if (await cryptoSha256(rootCipher) !=
          verified.snapshot['recoveryRootCiphertextHash']) {
        throw const FormatException('crypto_archive_recovery_bundle');
      }
      final recovered = account.files.open(
        file: externalFile,
        encryptedRoot: CryptoJson.decode(rootCipher) as Map<String, dynamic>,
        serverId: account.directory.session.profile.serverId,
        accountId: account.directory.accountId,
        expectedFingerprint: file['fingerprint'] as String,
      );
      try {
        archiveKey =
            await CryptoAccountArchiveKeyService(
              AccountCryptoV2Workflow(directory),
            ).open(
              manifest,
              recoveryOnly: true,
              recoveryKey: (public) async {
                for (final pair in [
                  recovered.encryption,
                  ...recovered.historicalEncryption,
                ]) {
                  if (base64Encode(pair.publicKey) != public) continue;
                  final secret = pair.secretKey.extractBytes();
                  try {
                    return KeyPair(
                      publicKey: Uint8List.fromList(pair.publicKey),
                      secretKey: crypto.sodium.secureCopy(secret),
                    );
                  } finally {
                    secret.fillRange(0, secret.length, 0);
                  }
                }
                return null;
              },
            );
      } finally {
        recovered.dispose();
      }
      final coldStaging = CryptoArchiveStagingStore(
        database: cold.database,
        partition: partition,
        crypto: crypto,
      );
      for (final segment in manifest.segments) {
        await coldStaging.importSegment(
          manifest: manifest,
          segment: segment,
          ciphertext: _download(migrationId, manifest, segment),
        );
      }
      final restored = await CryptoArchiveColdRestorer(cold.database).restore(
        plaintext: coldStaging.open(manifest, archiveKey.key),
        expectedHeader: header,
      );
      if (restored.inventoryHash != hash)
        throw const FormatException('crypto_archive_restore_parity');
      await verifyColdBusiness?.call(
        cold,
        AccountCryptoV2Workflow(directory),
        header,
      );
      final manifestPlaintext = CryptoInventoryJson.encode({
        'header': header,
        'archive': manifest.toJson(),
      });
      final manifestContext = {
        ...keys.context(manifest),
        'kind': 'accountArchiveManifest',
      };
      late Uint8List encoded;
      final existing = await account.store.database.rows(
        'SELECT o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
        [partition, 'archive:$migrationId:verify'],
      );
      try {
        if (existing.isNotEmpty) {
          final signed =
              jsonDecode(existing.single['signed_body'] as String) as Map;
          final command =
              CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
          encoded = cryptoBase64(
            (command['payload'] as Map)['encryptedManifestBase64'],
          );
          final opened = crypto.decrypt(
            envelope: CryptoJson.decode(encoded) as Map<String, dynamic>,
            key: archiveKey.key,
            context: manifestContext,
          );
          try {
            if (base64Encode(opened) != base64Encode(manifestPlaintext))
              throw const FormatException('crypto_archive_immutable_manifest');
          } finally {
            opened.fillRange(0, opened.length, 0);
          }
        } else {
          encoded = CryptoJson.encode(
            crypto.encrypt(
              plaintext: manifestPlaintext,
              key: archiveKey.key,
              context: manifestContext,
            ),
          );
        }
      } finally {
        manifestPlaintext.fillRange(0, manifestPlaintext.length, 0);
      }
      if (encoded.length > 196608)
        throw const FormatException('crypto_archive_manifest_size');
      final result = await _write(
        'archive:$migrationId:verify',
        'crypto2.migration.verify',
        {
          'migrationId': migrationId,
          'inventoryHash': hash,
          'encryptedManifestBase64': base64Encode(encoded),
          'contributions': {
            'keyId': manifest.keyId,
            'cipherManifestHash': manifest.cipherManifestHash,
            'segmentCount': manifest.segments.length,
          },
          'coldRestoreProof': {
            'version': 2,
            'challenge': snapshot['challenge'],
            'inventoryHash': hash,
            'manifestCipherHash': await cryptoSha256(encoded),
            'archiveCipherHash': manifest.cipherManifestHash,
            'restoredInventoryHash': restored.inventoryHash,
          },
        },
      );
      await account.store.database.execute(
        "UPDATE crypto_archive_jobs SET state='verified' WHERE partition=? AND migration_id=?",
        [partition, migrationId],
      );
      return result;
    } finally {
      archiveKey?.release();
      await cold.close();
    }
  }

  Stream<List<int>> _download(
    String migrationId,
    CryptoArchiveManifest manifest,
    CryptoArchiveSegment segment,
  ) async* {
    var offset = 0;
    while (offset < segment.size) {
      final page = await _read('crypto2.migration.archiveGet', {
        'migrationId': migrationId,
        'id': segment.id,
        'offset': offset,
      });
      if (page['id'] != segment.id ||
          page['complete'] != true ||
          page['size'] != segment.size ||
          page['sha256'] != segment.sha256 ||
          page['offset'] != offset)
        throw const FormatException('crypto_archive_remote');
      final description =
          jsonDecode(utf8.decode(cryptoBase64(page['manifestBase64']))) as Map;
      if (description['keyId'] != manifest.keyId ||
          description['cipherManifestHash'] != manifest.cipherManifestHash ||
          description['index'] != segment.index)
        throw const FormatException('crypto_archive_manifest');
      final bytes = cryptoBase64(page['dataBase64'], max: 196608);
      if (bytes.isEmpty || page['nextOffset'] != offset + bytes.length)
        throw const FormatException('crypto_archive_cursor');
      offset += bytes.length;
      yield bytes;
    }
  }

  Stream<List<int>> _source(
    String migrationId,
    Map<String, dynamic> header,
  ) async* {
    List<int> frame(Map<String, dynamic> value) =>
        utf8.encode('${CryptoInventoryJson.canonical(value)}\n');
    yield frame(header);
    final inventory = header['inventory'] as Map;
    final tables = inventory['tables'] as Map;
    final tableKeys = tables.keys.cast<String>().toList()..sort();
    for (final key in tableKeys) {
      final table = tables[key] as Map;
      var cursor = 0;
      while (cursor < table['rows']) {
        final page = await _read('crypto2.migration.exportPage', {
          'migrationId': migrationId,
          'table': table['table'],
          'domain': table['domain'],
          'cursor': cursor,
          'limit': 20,
        });
        if (page['inventoryHash'] != header['inventoryHash'] ||
            page['rows'] is! List ||
            (page['rows'] as List).isEmpty ||
            (page['rows'] as List).length > 20)
          throw const FormatException('crypto_archive_source');
        for (final raw in page['rows'] as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          for (final column in row.keys.toList()) {
            final cell = row[column] as Map;
            if (cell['external'] == null) continue;
            final external = cell['external'] as Map;
            if (external['size'] is! int ||
                external['size'] < 0 ||
                external['size'] > 24 * 1024 * 1024) {
              throw const CryptoAuthorityPending(
                'crypto_archive_large_sql_cell_pending',
              );
            }
            final bytes = BytesBuilder(copy: false),
                hash = Sha256().newHashSink();
            var offset = 0;
            while (offset < external['size']) {
              final part = await _read('crypto2.migration.exportCell', {
                'migrationId': migrationId,
                'table': table['table'],
                'domain': table['domain'],
                'cursor': cursor,
                'column': column,
                'offset': offset,
                'limit': 196608,
              });
              final data = cryptoBase64(part['dataBase64'], max: 196608);
              if (part['inventoryHash'] != header['inventoryHash'] ||
                  part['offset'] != offset ||
                  part['nextOffset'] != offset + data.length ||
                  part['size'] != external['size'] ||
                  part['sha256'] != external['sha256'] ||
                  part['type'] != cell['type'] ||
                  data.isEmpty) {
                throw const FormatException('crypto_archive_source_cell');
              }
              hash.add(data);
              bytes.add(data);
              offset += data.length;
            }
            hash.close();
            final digest = (await hash.hash()).bytes
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join();
            final content = bytes.takeBytes();
            try {
              if (digest != external['sha256'])
                throw const FormatException('crypto_archive_source_cell');
              row[column] = {
                'type': cell['type'],
                'valueBase64': base64Encode(content),
              };
            } finally {
              content.fillRange(0, content.length, 0);
            }
          }
          yield frame({
            'kind': 'row',
            'table': table['table'],
            'domain': table['domain'],
            'index': cursor,
            'values': row,
          });
          cursor++;
        }
        if (page['cursor'] != cursor || cursor > table['rows'])
          throw const FormatException('crypto_archive_source_cursor');
      }
    }
    for (final scope in (inventory['files'] as Map).keys.cast<String>()) {
      var cursor = 0;
      while (true) {
        final page = await _read('crypto2.migration.fileList', {
          'migrationId': migrationId,
          'scopeId': scope,
          'cursor': cursor,
          'limit': 20,
        });
        if (page['inventoryHash'] != header['inventoryHash'] ||
            page['files'] is! List ||
            (page['files'] as List).length > 20)
          throw const FormatException('crypto_archive_source_files');
        for (final raw in page['files'] as List) {
          final descriptor = Map<String, dynamic>.from(raw as Map);
          final stamp = descriptor.remove('stamp');
          yield frame({
            'kind': 'file',
            'scopeId': scope,
            'index': cursor,
            'descriptor': descriptor,
          });
          cursor++;
          if (descriptor['state'] != 'present') continue;
          var offset = 0;
          while (offset < descriptor['size']) {
            final part = await _read('crypto2.migration.fileChunk', {
              'migrationId': migrationId,
              'scopeId': scope,
              'kind': descriptor['kind'],
              'fileId': descriptor['id'],
              'offset': offset,
              'limit': 196608,
              'stamp': stamp,
            });
            final bytes = cryptoBase64(part['dataBase64'], max: 196608);
            if (part['inventoryHash'] != header['inventoryHash'] ||
                part['stamp'] != stamp ||
                part['offset'] != offset ||
                part['nextOffset'] != offset + bytes.length ||
                bytes.isEmpty) {
              throw const FormatException('crypto_archive_source_file_chunk');
            }
            yield frame({
              'kind': 'fileChunk',
              'scopeId': scope,
              'fileKind': descriptor['kind'],
              'id': descriptor['id'],
              'offset': offset,
              'dataBase64': base64Encode(bytes),
            });
            offset += bytes.length;
          }
        }
        if (page['cursor'] != cursor)
          throw const FormatException('crypto_archive_source_cursor');
        if (page['hasMore'] != true) break;
        if ((page['files'] as List).isEmpty)
          throw const FormatException('crypto_archive_source_cursor');
      }
    }
    yield frame({'kind': 'complete', 'inventoryHash': header['inventoryHash']});
  }
}
