import 'dart:convert';

import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart';
import 'crypto_account_archive.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_local_intents.dart';
import 'crypto_migration_receipt_codec.dart';
import 'crypto_sync_repository.dart';

/// Immutable private snapshot generation. Neither upload nor the own log event
/// activates any imported legacy operation. The cold consumer separately checks
/// all encrypted frames before the final receipt section can be signed.
class CryptoStagedMigrationLocalArtifact {
  CryptoStagedMigrationLocalArtifact._(
    this.result,
    this.descriptor,
    this.event,
  );
  final Map<String, dynamic> result, descriptor, event;
}

class CryptoMigrationLocalArtifact {
  CryptoMigrationLocalArtifact(this.account);
  final AccountCryptoV2Workflow account;
  String get partition => account.store.partition;
  Future<CryptoStagedMigrationLocalArtifact> stageAndUpload({
    required CryptoCaptureKeyDescriptor capture,
    required String sourceInventoryRoot,
  }) async {
    final db = account.store.database,
        crypto = account.directory.reducer.crypto;
    final common = <String, dynamic>{
      'version': 3,
      'serverId': account.directory.session.profile.serverId,
      'migrationId': capture.migrationId,
      'captureId': capture.captureId,
      'accountId': account.directory.accountId,
      'sourceInventoryRoot': sourceInventoryRoot,
    };
    CryptoMigrationReceiptCodec.common(common);
    final name = 'migration_local_artifact:$partition:${capture.captureId}';
    Map<String, dynamic>? saved;
    await db.transaction(() async {
      final rows = await db.rows('SELECT value FROM local_meta WHERE name=?', [
        name,
      ]);
      if (rows.isNotEmpty) {
        saved = Map<String, dynamic>.from(
          jsonDecode(rows.single['value'] as String),
        );
        return;
      }
      saved = {'context': common, 'artifactId': crypto.randomId()};
      await db.execute('INSERT INTO local_meta VALUES(?,?)', [
        name,
        jsonEncode(saved),
      ]);
    });
    if (CryptoInventoryJson.canonical(saved!['context']) !=
        CryptoInventoryJson.canonical(common)) {
      throw const FormatException('crypto_local_artifact_context');
    }
    final artifactId = saved!['artifactId'] as String;
    final context = {
      ...common,
      'artifactId': artifactId,
      'purpose': 'migrationLocalIntents',
    };
    final staging = CryptoArchiveStagingStore(
      database: db,
      partition: partition,
      crypto: crypto,
    );
    if (saved!['descriptor'] == null) {
      await db.transaction(() async {
        await staging.restartUnpublishedDraft(
          migrationId: capture.migrationId,
          artifactId: artifactId,
          artifactKind: 'migrationLocalIntentsV3',
          artifactContext: context,
        );
        var count = -1, total = 0;
        Stream<List<int>> input() async* {
          await for (final bytes in CryptoMigrationLocalIntentSnapshot(
            database: db,
            partition: partition,
            capture: capture,
            sourceInventoryRoot: sourceInventoryRoot,
          ).frames(artifactId: artifactId)) {
            total += bytes.length;
            if (total > 240 * 1024 * 1024) {
              throw const FormatException('crypto_local_artifact_capacity');
            }
            final f = jsonDecode(utf8.decode(bytes)) as Map;
            if (f['kind'] == 'localIntentFooter') {
              count = f['intentCount'] as int;
            }
            yield bytes;
          }
        }

        final manifest = await staging.stage(
          migrationId: capture.migrationId,
          artifactId: artifactId,
          artifactKind: 'migrationLocalIntentsV3',
          artifactContext: context,
          plaintext: input(),
        );
        if (count < 0) {
          throw const FormatException('crypto_local_artifact_snapshot');
        }
        saved!['descriptor'] = {
          'context': context,
          'manifest': manifest.toJson(),
          'intentCount': count,
        };
        await db.execute('UPDATE local_meta SET value=? WHERE name=?', [
          jsonEncode(saved),
          name,
        ]);
      });
    }
    final descriptor = Map<String, dynamic>.from(saved!['descriptor'] as Map);
    final manifest = CryptoArchiveManifest.fromJson(
      Map<String, dynamic>.from(descriptor['manifest'] as Map),
    );
    if (CryptoInventoryJson.canonical(manifest.artifactContext) !=
        CryptoInventoryJson.canonical(context)) {
      throw const FormatException('crypto_local_artifact_context');
    }
    await CryptoAccountArchiveKeyService(account).publish(manifest);
    final queue = CryptoCaptureCoordinator(account).queue;
    // Keep the original account/session runtime; the queue itself still performs
    // its independent fresh-beforeDelivery and exact receipt checks.
    Future<void> send(String action, String op, Map<String, dynamic> p) async {
      final id = await queue.enqueueCommand(
        actionKey: action,
        operation: op,
        payload: p,
      );
      await queue.resumeUnresolved(requestIds: {id});
      await queue.commandResult(id);
    }

    for (final segment in manifest.segments) {
      final base = 'localArtifact:$artifactId:${segment.id}';
      await send('$base:begin', 'crypto2.migration.archiveBegin', {
        'migrationId': capture.migrationId,
        'id': segment.id,
        'size': segment.size,
        'sha256': segment.sha256,
        'manifestBase64': base64Encode(
          CryptoJson.encode({
            'version': 3,
            'keyId': manifest.keyId,
            'cipherManifestHash': manifest.cipherManifestHash,
            'index': segment.index,
            'artifactKind': 'migrationLocalIntentsV3',
            'artifact': descriptor,
          }),
        ),
      });
      var offset = 0;
      await for (final bytes in staging.cipher(segment)) {
        await send('$base:$offset', 'crypto2.migration.archiveChunk', {
          'migrationId': capture.migrationId,
          'id': segment.id,
          'offset': offset,
          'dataBase64': base64Encode(bytes),
        });
        offset += bytes.length;
      }
      await send('$base:complete', 'crypto2.migration.archiveComplete', {
        'migrationId': capture.migrationId,
        'id': segment.id,
      });
    }
    final hash = await cryptoSha256(CryptoInventoryJson.encode(descriptor));
    final token = await cryptoSha256([
      ...utf8.encode('JivieMigrationLocalIntentToken/v3\n'),
      ...CryptoInventoryJson.encode({...common, 'artifactId': artifactId}),
    ]);
    final entry = await account.attestMigration(
      migrationId: capture.migrationId,
      scopeToken: token,
      domain: 'content',
      attestationHash: hash,
    );
    final event = Map<String, dynamic>.from(entry['authorization'] as Map);
    final result = {
      'artifactId': artifactId,
      'cipherManifestHash': manifest.cipherManifestHash,
      'intentCount': descriptor['intentCount'],
      'ownEventCommandHash': await cryptoSha256(
        cryptoBase64(event['commandBase64']),
      ),
    };
    CryptoMigrationReceiptCodec.local(result);
    saved!['event'] = event;
    saved!['result'] = result;
    await db.execute('UPDATE local_meta SET value=? WHERE name=?', [
      jsonEncode(saved),
      name,
    ]);
    if (!account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_session_changed');
    }
    return CryptoStagedMigrationLocalArtifact._(
      Map.unmodifiable(result),
      Map.unmodifiable(descriptor),
      Map.unmodifiable(event),
    );
  }
}
