import 'dart:convert';
import 'dart:typed_data';

import 'crypto_account_archive.dart';
import 'crypto_json.dart';
import 'crypto_migration_witness.dart';
import 'crypto_sync_repository.dart';

/// Transport of an already staged witness. The caller must authenticate the
/// enclosing source binding/certificate before using a downloaded witness as
/// migration evidence. This class never installs business rows or grants keys.
class CryptoMigrationWitnessTransport {
  CryptoMigrationWitnessTransport({this.queue, required this.read});
  final CryptoSyncRepository? queue;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  read;

  Map<String, dynamic> _base(
    CryptoMigrationWitnessContext context,
    String id, {
    String purpose = 'typedWitness',
  }) => {
    'captureVersion': 3,
    for (final key in [
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
      key: context.value[key],
    'id': id,
    'purpose': context.value['purpose'] == 'migrationAudit'
        ? 'auditWitness'
        : purpose,
  };

  Future<void> upload({
    required CryptoMigrationWitness producer,
    required CryptoMigrationWitnessContext context,
    required Map<String, dynamic> descriptor,
  }) async {
    final segments = await CryptoMigrationWitness.validateDescriptor(
      context,
      descriptor,
    );
    await uploadCipher(
      staging: producer.staging,
      context: context,
      segments: segments,
      manifestBase64: descriptor['manifestBase64'],
      purpose: context.value['purpose'] == 'migrationAudit'
          ? 'auditWitness'
          : 'typedWitness',
    );
  }

  Future<void> uploadCipher({
    required CryptoArchiveStagingStore staging,
    required CryptoMigrationWitnessContext context,
    required List<CryptoArchiveSegment> segments,
    required String manifestBase64,
    String purpose = 'typedWitness',
  }) async {
    if (![
          'typedWitness',
          'canonicalPayload',
          'ideaAsset',
          'auditWitness',
        ].contains(purpose) ||
        (context.value['purpose'] == 'migrationAudit') !=
            (purpose == 'auditWitness')) {
      throw const FormatException('crypto_migration_blob_purpose');
    }
    if (purpose == 'ideaAsset' &&
        (context.value['type'] != 'idea' ||
            context.value['domain'] != 'content')) {
      throw const FormatException('crypto_migration_blob_purpose');
    }
    Future<void> send(
      String action,
      String operation,
      Map<String, dynamic> payload,
    ) async {
      final request = await queue!.enqueueCommand(
        actionKey: action,
        operation: operation,
        payload: payload,
      );
      await queue!.resumeUnresolved(requestIds: {request});
      await queue!.commandResult(request);
    }

    for (final segment in segments) {
      final base = _base(context, segment.id, purpose: purpose);
      final action =
          'capture3:$purpose:${context.value['captureId']}:${context.value['bindingId']}:${segment.id}';
      await send('$action:begin', 'crypto2.migration.blob.begin', {
        ...base,
        'size': segment.size,
        'sha256': segment.sha256,
        'manifestBase64': manifestBase64,
      });
      var offset = 0;
      // SQL secretstream frame boundaries need not equal the wire chunk size.
      // Retain at most one wire chunk while repacking the exact ciphertext.
      final buffer = Uint8List(CryptoArchiveStagingStore.chunkSize);
      var used = 0;
      await for (final bytes in staging.cipher(segment)) {
        var input = 0;
        while (input < bytes.length) {
          final take = (buffer.length - used).clamp(0, bytes.length - input);
          buffer.setRange(used, used + take, bytes, input);
          input += take;
          used += take;
          if (used == buffer.length) {
            await send('$action:$offset', 'crypto2.migration.blob.chunk', {
              ...base,
              'offset': offset,
              'dataBase64': base64Encode(buffer),
            });
            offset += used;
            used = 0;
          }
        }
      }
      if (used > 0) {
        await send('$action:$offset', 'crypto2.migration.blob.chunk', {
          ...base,
          'offset': offset,
          'dataBase64': base64Encode(Uint8List.sublistView(buffer, 0, used)),
        });
        offset += used;
      }
      if (offset != segment.size) {
        throw const FormatException('crypto_migration_witness_size');
      }
      await send('$action:complete', 'crypto2.migration.blob.complete', base);
    }
  }

  Future<void> download({
    required CryptoMigrationWitness consumer,
    required CryptoMigrationWitnessContext context,
    required Map<String, dynamic> descriptor,
  }) async {
    final segments = await CryptoMigrationWitness.validateDescriptor(
      context,
      descriptor,
    );
    final manifest = CryptoArchiveManifest(
      migrationId: context.value['migrationId'],
      keyId: 'migrationWitness:${context.value['bindingId']}',
      segments: segments,
      cipherManifestHash: descriptor['cipherManifestHash'],
    );
    for (final segment in segments) {
      Stream<List<int>> cipher() async* {
        var offset = 0;
        while (offset < segment.size) {
          final page = await read('crypto2.migration.blob.get', {
            ..._base(context, segment.id),
            'offset': offset,
          });
          final bytes = cryptoBase64(
            page['dataBase64'],
            max: CryptoArchiveStagingStore.chunkSize,
          );
          final expected = (segment.size - offset).clamp(
            0,
            CryptoArchiveStagingStore.chunkSize,
          );
          if (page['id'] != segment.id ||
              page['complete'] != true ||
              page['size'] != segment.size ||
              page['sha256'] != segment.sha256 ||
              page['manifestBase64'] != descriptor['manifestBase64'] ||
              page['offset'] != offset ||
              page['nextOffset'] != offset + bytes.length ||
              bytes.length != expected) {
            throw const FormatException('crypto_migration_witness_transport');
          }
          offset += bytes.length;
          yield bytes;
        }
      }

      await consumer.staging.importSegment(
        manifest: manifest,
        segment: segment,
        ciphertext: cipher(),
      );
    }
  }
}
