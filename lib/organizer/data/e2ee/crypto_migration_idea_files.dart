import 'dart:convert';
import 'dart:typed_data';

import '../../domain/idea_models.dart';
import '../idea_repository.dart' show verifyIdeaAsset;
import 'crypto_business_router.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_archive.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_business_parity_v3.dart';
import 'account_directory_v2.dart' show cryptoDirectoryDomain;
import 'crypto_capture_v3.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_file_object.dart';
import 'crypto_migration_idea_payload.dart';
import 'crypto_migration_witness.dart';
import 'crypto_migration_witness_transport.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// Physical source assets remain distinct from business records, including
/// complete uploads not yet referenced by a saved board. Nothing is projected.
class CryptoMigrationIdeaFiles {
  CryptoMigrationIdeaFiles(this.runtime);
  final CryptoBusinessSession runtime;
  String get partition => runtime.partition;

  static String sidecarName(String partition, String capture, String binding) =>
      'migration_file_sidecar:$partition:$capture:$binding';
  static String cell(Map row, String key) {
    final value = row[key];
    if (value is! Map || value['valueBase64'] is! String) {
      throw const FormatException('crypto_migration_idea_file_source');
    }
    return utf8.decode(cryptoBase64(value['valueBase64']));
  }

  static IdeaAsset asset(Map row) => IdeaAsset.fromJson({
    'sha256': cell(row, 'sha256'),
    'mime': cell(row, 'mime'),
    'size': int.parse(cell(row, 'size')),
    'width': int.parse(cell(row, 'width')),
    'height': int.parse(cell(row, 'height')),
  });

  Future<void> stageAll(CryptoCaptureKeyDescriptor capture, String root) async {
    var after = '';
    while (true) {
      final rows = await runtime.db.rows(
        "SELECT binding_id,context,typed_row,binding FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? AND json_extract(context,'\$.sourceTable')='familyhub_idea_assets' ORDER BY binding_id LIMIT 1",
        [partition, capture.captureId, after],
      );
      if (rows.isEmpty) return;
      final row = rows.single;
      after = row['binding_id'] as String;
      final source = CryptoCaptureSourceContext.fromJson(
        jsonDecode(row['context'] as String),
      );
      final binding = CryptoCaptureBinding.fromJson(
        jsonDecode(row['binding'] as String),
      );
      final typed = jsonDecode(row['typed_row'] as String) as Map;
      final metadata = asset(typed), board = cell(typed, 'board_id');
      if (source.domain != 'content' ||
          !capture.scopeIds.contains(source.scopeId) ||
          !isCryptoCanonicalUuid(board) ||
          cell(typed, 'scope_id') != source.scopeId ||
          cell(typed, 'complete') != '1' ||
          int.parse(cell(typed, 'received')) != metadata.size) {
        throw const CryptoAuthorityPending('crypto_migration_pending_upload');
      }
      final candidate = await runtime.access.migrationCandidate(
        scopeId: source.scopeId!,
        migrationId: capture.migrationId,
        captureId: capture.captureId,
      );
      final address = runtime.address(
        source.scopeId!,
        'content',
        'idea',
        board,
      );
      final context = CryptoMigrationWitnessContext({
        'version': 3,
        'purpose': 'migrationWitness',
        'serverId': source.serverId,
        'accountId': source.accountId,
        'captureId': capture.captureId,
        'migrationId': capture.migrationId,
        'bindingId': binding.bindingId,
        'sourceInventoryRoot': root,
        'sourceCommitment': binding.sourceCommitment,
        'scopeId': source.scopeId,
        'domain': 'content',
        'epoch': candidate.head.epoch,
        'accessRevision': candidate.head.accessRevision,
        'membershipHeadHash': candidate.head.headHash,
        'type': 'idea',
        'sourceKind': address.sourceKind,
        'canonicalId': board,
        'wireId': address.wireId,
      });
      final base = {
        'migrationId': capture.migrationId,
        'captureId': capture.captureId,
        'bindingId': binding.bindingId,
      };
      final file = await runtime.account.directory.call(
        'crypto2.migration.capture.file',
        base,
      );
      if (file['captureVersion'] != 3 ||
          file['bindingId'] != binding.bindingId ||
          file['kind'] != 'idea' ||
          file['state'] != 'present' ||
          file['size'] != metadata.size ||
          file['stamp'] is! String) {
        throw const CryptoAuthorityPending(
          'crypto_migration_idea_file_missing',
        );
      }
      final lease = await candidate.key('content');
      final plain = Uint8List(metadata.size);
      try {
        var offset = 0;
        while (offset < metadata.size) {
          final page = await runtime.account.directory.call(
            'crypto2.migration.capture.fileChunk',
            {
              ...base,
              'offset': offset,
              'limit': 196608,
              'stamp': file['stamp'],
            },
          );
          final part = cryptoBase64(page['dataBase64'], max: 196608);
          try {
            if (page['captureVersion'] != 3 ||
                page['bindingId'] != binding.bindingId ||
                page['kind'] != 'idea' ||
                page['size'] != metadata.size ||
                page['stamp'] != file['stamp'] ||
                page['offset'] != offset ||
                page['nextOffset'] != offset + part.length ||
                part.length != (metadata.size - offset).clamp(0, 196608)) {
              throw const FormatException(
                'crypto_migration_idea_file_transport',
              );
            }
            plain.setRange(offset, offset + part.length, part);
            offset += part.length;
          } finally {
            part.fillRange(0, part.length, 0);
          }
        }
        await verifyIdeaAsset(metadata, plain);
        final files = CryptoMigrationFileObject(
          database: runtime.db,
          partition: partition,
          crypto: runtime.codec.crypto,
        );
        final object = await files.stage(
          context: context,
          plainSize: metadata.size,
          plainSha256: metadata.sha256,
          plaintext: Stream.value(plain),
          domainKey: lease.key,
        );
        await files.upload(
          transport: CryptoMigrationWitnessTransport(
            queue: runtime.queue,
            read: runtime.account.directory.call,
          ),
          context: context,
          object: object,
        );
        final original = await runtime.db.rows(
          'SELECT o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
          [
            partition,
            'capture3:ideaAsset:${capture.captureId}:${binding.bindingId}:${object['blob']['id']}:begin',
          ],
        );
        if (original.length != 1) {
          throw const FormatException('crypto_migration_idea_file_proof');
        }
        final sidecar = {
          'context': context.value,
          'object': object,
          'authorization': jsonDecode(original.single['signed_body'] as String),
        };
        final name = sidecarName(
          partition,
          capture.captureId,
          binding.bindingId,
        );
        final old = await runtime.db.rows(
          'SELECT value FROM local_meta WHERE name=?',
          [name],
        );
        final encoded = CryptoInventoryJson.canonical(sidecar);
        if (old.isEmpty) {
          await runtime.db.execute('INSERT INTO local_meta VALUES(?,?)', [
            name,
            encoded,
          ]);
        } else if (old.single['value'] != encoded) {
          throw const FormatException('crypto_migration_idea_file_immutable');
        }
      } finally {
        plain.fillRange(0, plain.length, 0);
        lease.release();
      }
    }
  }

  Future<List<Map<String, dynamic>>> objectsForBoard({
    required String captureId,
    required String scopeId,
    required String boardId,
    required Map<String, dynamic> raw,
  }) async {
    final expected = cryptoMigrationIdeaAssets(raw),
        hashes = expected.keys.toList()..sort();
    final out = <Map<String, dynamic>>[];
    for (final hash in hashes) {
      final rows = await runtime.db.rows(
        "SELECT binding_id,typed_row FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND json_extract(context,'\$.sourceTable')='familyhub_idea_assets' AND json_extract(context,'\$.scopeId')=? AND json_extract(typed_row,'\$.board_id.valueBase64')=? AND json_extract(typed_row,'\$.sha256.valueBase64')=? LIMIT 2",
        [
          partition,
          captureId,
          scopeId,
          base64Encode(utf8.encode(boardId)),
          base64Encode(utf8.encode(hash)),
        ],
      );
      if (rows.length != 1) {
        throw const CryptoAuthorityPending(
          'crypto_migration_idea_files_pending',
        );
      }
      final typed = jsonDecode(rows.single['typed_row'] as String) as Map;
      if (!CryptoMigrationColdEvidence.same(
        asset(typed).toJson(),
        expected[hash]!.toJson(),
      )) {
        throw const FormatException('crypto_migration_idea_asset_metadata');
      }
      final saved = await runtime.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [
          sidecarName(
            partition,
            captureId,
            rows.single['binding_id'] as String,
          ),
        ],
      );
      if (saved.length != 1) {
        throw const CryptoAuthorityPending(
          'crypto_migration_idea_files_pending',
        );
      }
      final sidecar = jsonDecode(saved.single['value'] as String) as Map;
      final context = sidecar['context'];
      if (context is! Map ||
          context['canonicalId'] != boardId ||
          context['scopeId'] != scopeId ||
          context['captureId'] != captureId ||
          context['bindingId'] != rows.single['binding_id']) {
        throw const FormatException('crypto_migration_idea_asset_binding');
      }
      out.add(Map<String, dynamic>.from(sidecar['object'] as Map));
    }
    return out;
  }

  /// Actual FILE-pinned physical comparison. A private archive sidecar is only
  /// discovery until its exact own signed begin and decrypted bytes agree.
  Future<Map<String, dynamic>> verifyCold({
    required VerifiedCryptoCaptureArchive archive,
    required CryptoMigrationColdSource source,
    required Uint8List recoveryFile,
  }) async {
    if (source.context.sourceTable != 'familyhub_idea_assets' ||
        source.context.domain != 'content') {
      throw const FormatException('crypto_migration_idea_file_source');
    }
    final rows = await runtime.db.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [
        sidecarName(
          partition,
          archive.capture.captureId,
          source.binding.bindingId,
        ),
      ],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('crypto_migration_idea_files_pending');
    }
    final sidecar = jsonDecode(rows.single['value'] as String) as Map;
    final context = CryptoMigrationWitnessContext(
      Map<String, dynamic>.from(sidecar['context'] as Map),
    );
    context.requireSource(source.context);
    final metadata = asset(source.typedRow);
    final object = Map<String, dynamic>.from(sidecar['object'] as Map);
    final d = CryptoMigrationFileObject.descriptor(context, object);
    if (context.value['bindingId'] != source.binding.bindingId ||
        context.value['sourceCommitment'] != source.binding.sourceCommitment ||
        context.value['sourceInventoryRoot'] != archive.sourceInventoryRoot ||
        context.value['canonicalId'] != cell(source.typedRow, 'board_id') ||
        cell(source.typedRow, 'scope_id') != source.context.scopeId ||
        cell(source.typedRow, 'complete') != '1' ||
        int.parse(cell(source.typedRow, 'received')) != metadata.size ||
        object['plainSize'] != metadata.size) {
      throw const FormatException('crypto_migration_idea_file_source');
    }
    final proof = Map<String, dynamic>.from(sidecar['authorization'] as Map);
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    CryptoMigrationBusinessParityV3.exact(command, {
      'version',
      'operation',
      'requestId',
      'serverId',
      'accountId',
      'deviceId',
      'signer',
      'payload',
    });
    final expected = {
      'captureVersion': 3,
      for (final k in [
        'migrationId',
        'captureId',
        'sourceInventoryRoot',
        'bindingId',
        'scopeId',
        'domain',
        'epoch',
        'membershipHeadHash',
        'accessRevision',
      ])
        k: context.value[k],
      'id': d['id'],
      'purpose': 'ideaAsset',
      'size': d['cipherSize'],
      'sha256': d['cipherSha256'],
      'manifestBase64': d['manifestBase64'],
    };
    if (command['version'] != 2 ||
        command['operation'] != 'crypto2.migration.blob.begin' ||
        command['serverId'] != source.context.serverId ||
        command['accountId'] != source.context.accountId ||
        command['signer'] != 'device' ||
        !isCryptoCanonicalUuid(command['requestId']) ||
        !CryptoMigrationColdEvidence.same(command['payload'], expected)) {
      throw const FormatException('crypto_migration_idea_file_proof');
    }
    await runtime.access.withReadOnlyFrozenScope<void>(
      scopeId: source.context.scopeId!,
      candidateHeadHash: context.value['membershipHeadHash'],
      recoveryFile: recoveryFile,
      body: () async {
        final head = await runtime.access.recoveryCandidateHead(
          source.context.scopeId!,
        );
        final member = head.member(source.context.accountId);
        await CryptoMigrationColdEvidence(runtime, archive).verifyOwn(
          proof,
          member['directoryHeadHash'],
          command['deviceId'],
          cryptoDirectoryDomain,
        );
        await runtime.access.recoverScopeCandidateKeys(
          source.context.scopeId!,
          recoveryFile,
        );
        final lease = await runtime.access.getScopeKey(
          source.context.scopeId!,
          'content',
          context.value['epoch'],
        );
        try {
          final bytes =
              await CryptoMigrationFileObject(
                database: runtime.db,
                partition: partition,
                crypto: runtime.codec.crypto,
              ).open(
                transport: CryptoMigrationWitnessTransport(
                  read: runtime.account.directory.call,
                ),
                context: context,
                object: object,
                domainKey: lease.key,
                plainSize: metadata.size,
                plainSha256: metadata.sha256,
              );
          try {
            await verifyIdeaAsset(metadata, bytes);
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        } finally {
          lease.release();
        }
      },
    );
    return {
      'artifactHash':
          await CryptoMigrationBusinessParityV3.canonicalFileArtifact(proof),
      'object': object,
    };
  }
}
