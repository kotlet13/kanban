import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show Sha256;
import '../collaboration_database.dart';
import 'crypto_inventory_json.dart';
import 'account_directory_v2.dart' show cryptoSha256;

const cryptoDocumentRecoverySourceTable = 'crypto_document_recovery_sources';
const cryptoDocumentRecoverySourceColumns = [
  'partition',
  'id',
  'scope_id',
  'job_id',
  'source_hash',
  'size',
  'sha256',
];
typedef CryptoDraftCipherDecryptor =
    Future<Uint8List> Function(
      Map<String, dynamic> descriptor,
      Uint8List cipher,
    );

/// Constructed only after decrypting the exact durable staged object and
/// comparing all plaintext bytes to the original contiguous upload.
class VerifiedCryptoUploadRecovery {
  VerifiedCryptoUploadRecovery._(
    this.row,
    this.metadataHash,
    this.descriptorHash,
  );
  final Map<String, dynamic> row;
  final String metadataHash, descriptorHash;
}

Future<String> _uploadHash(
  CollaborationDatabase db,
  String partition,
  String id,
  int size,
) async {
  final sink = Sha256().newHashSink();
  var offset = 0, count = 0;
  while (offset < size) {
    final chunks = await db.rows(
      'SELECT bytes FROM crypto_document_upload_chunks WHERE partition=? AND id=? AND offset=?',
      [partition, id, offset],
    );
    if (chunks.length != 1) {
      throw const FormatException('crypto_backup_upload_chunks');
    }
    final bytes = (chunks.single['bytes'] as List).cast<int>();
    if (bytes.isEmpty ||
        bytes.length > 262144 ||
        offset + bytes.length > size) {
      throw const FormatException('crypto_backup_upload_chunks');
    }
    offset += bytes.length;
    count++;
    sink.add(bytes);
  }
  if ((await db.rows(
        'SELECT COUNT(*) n FROM crypto_document_upload_chunks WHERE partition=? AND id=?',
        [partition, id],
      )).single['n'] !=
      count) {
    throw const FormatException('crypto_backup_upload_chunks');
  }
  sink.close();
  return (await sink.hash()).bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

Future<Map<String, VerifiedCryptoUploadRecovery>> verifyCryptoUploadRecoveries(
  CollaborationDatabase db,
  String? partition,
  CryptoDraftCipherDecryptor? decrypt,
) async {
  if (partition == null || decrypt == null) return {};
  final result = <String, VerifiedCryptoUploadRecovery>{};
  for (final upload in await db.rows(
    "SELECT * FROM crypto_document_uploads WHERE partition=? AND state<>'complete'",
    [partition],
  )) {
    Uint8List? plain;
    try {
      final metadata = jsonDecode(upload['metadata'] as String) as Map;
      final size = metadata['size'];
      if (size is! int ||
          size < 0 ||
          size > 20 * 1024 * 1024 ||
          upload['received'] != size) {
        continue;
      }
      final jobs = await db.rows(
        "SELECT * FROM crypto_document_jobs WHERE partition=? AND scope_id=? AND record_id=? AND operation_id=? AND kind='attachment' AND state<>'writing'",
        [partition, upload['scope_id'], upload['id'], upload['id']],
      );
      if (jobs.length != 1) continue;
      final job = jobs.single;
      final descriptor = Map<String, dynamic>.from(
        jsonDecode(job['descriptor'] as String) as Map,
      );
      if (descriptor['scopeId'] != upload['scope_id'] ||
          descriptor['id'] != job['id'] ||
          descriptor['domain'] != 'content') {
        continue;
      }
      final hash = await _uploadHash(
        db,
        partition,
        upload['id'] as String,
        size,
      );
      final sourceHash = await CryptoInventoryJson.hash({
        'scopeId': upload['scope_id'],
        'recordId': upload['id'],
        'operationId': upload['id'],
        'kind': 'attachment',
        'domain': 'content',
        'plainSha256': hash,
      });
      if (hash != metadata['sha256'] || sourceHash != job['source_hash']) {
        continue;
      }
      if (descriptor['cipherSize'] is! int ||
          descriptor['cipherSize'] < 1 ||
          descriptor['cipherSize'] > 20 * 1024 * 1024 + 32768) {
        continue;
      }
      final builder = BytesBuilder(copy: false);
      for (final chunk in await db.rows(
        'SELECT offset,cipher FROM crypto_document_chunks WHERE partition=? AND id=? ORDER BY offset',
        [partition, job['id']],
      )) {
        if (chunk['offset'] != builder.length) {
          throw const FormatException('crypto_backup_cipher_chunks');
        }
        final bytes = (chunk['cipher'] as List).cast<int>();
        if (bytes.length > 196608 ||
            builder.length + bytes.length > descriptor['cipherSize']) {
          throw const FormatException('crypto_backup_cipher_chunks');
        }
        builder.add(bytes);
      }
      final cipher = builder.takeBytes();
      if (cipher.length != descriptor['cipherSize'] ||
          await cryptoSha256(cipher) != descriptor['cipherSha256']) {
        continue;
      }
      plain = await decrypt(descriptor, cipher);
      if (plain.length != size || await cryptoSha256(plain) != hash) continue;
      result[upload['id'] as String] = VerifiedCryptoUploadRecovery._(
        {
          'partition': partition,
          'id': upload['id'],
          'scope_id': upload['scope_id'],
          'job_id': job['id'],
          'source_hash': sourceHash,
          'size': size,
          'sha256': hash,
        },
        await CryptoInventoryJson.hash(metadata),
        await CryptoInventoryJson.hash(descriptor),
      );
    } catch (_) {
      // Missing keys, corrupted cipher or changed input preserves original bytes.
      // This optimization never prevents an ordinary local-only backup.
    } finally {
      plain?.fillRange(0, plain.length, 0);
    }
  }
  return result;
}

Future<bool> cryptoUploadRecoveryStillMatches(
  CollaborationDatabase db,
  VerifiedCryptoUploadRecovery proof,
) async {
  final r = proof.row, p = r['partition'] as String, id = r['id'] as String;
  final upload = await db.rows(
    'SELECT metadata,received FROM crypto_document_uploads WHERE partition=? AND id=?',
    [p, id],
  );
  final jobs = await db.rows(
    'SELECT descriptor,source_hash FROM crypto_document_jobs WHERE partition=? AND id=? AND scope_id=? AND record_id=? AND operation_id=?',
    [p, r['job_id'], r['scope_id'], id, id],
  );
  if (upload.length != 1 ||
      jobs.length != 1 ||
      upload.single['received'] != r['size'] ||
      jobs.single['source_hash'] != r['source_hash']) {
    return false;
  }
  if (await CryptoInventoryJson.hash(
            jsonDecode(upload.single['metadata'] as String),
          ) !=
          proof.metadataHash ||
      await CryptoInventoryJson.hash(
            jsonDecode(jobs.single['descriptor'] as String),
          ) !=
          proof.descriptorHash) {
    return false;
  }
  // The exact descriptor binds every ciphertext byte; rehash below before omission.
  final sink = Sha256().newHashSink();
  var offset = 0;
  for (final chunk in await db.rows(
    'SELECT offset,cipher FROM crypto_document_chunks WHERE partition=? AND id=? ORDER BY offset',
    [p, r['job_id']],
  )) {
    if (chunk['offset'] != offset) return false;
    final bytes = (chunk['cipher'] as List).cast<int>();
    offset += bytes.length;
    sink.add(bytes);
  }
  sink.close();
  final hash = (await sink.hash()).bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final descriptor = jsonDecode(jobs.single['descriptor'] as String) as Map;
  return offset == descriptor['cipherSize'] &&
      hash == descriptor['cipherSha256'] &&
      await _uploadHash(db, p, id, r['size'] as int) == r['sha256'];
}

/// Called only after fresh authority/key recovery has decrypted this exact
/// candidate-local job. This verifies recovery references; it acknowledges or
/// installs nothing and never substitutes another candidate's same-named job.
Future<void> validateRecoveredCryptoUploadSources(
  Map tables,
  Map job,
  Uint8List plaintext,
) async {
  for (final ref
      in tables[cryptoDocumentRecoverySourceTable] as List? ?? const []) {
    if (ref['job_id'] != job['id']) continue;
    final uploads = (tables['crypto_document_uploads'] as List)
        .where((r) => r['id'] == ref['id'])
        .toList();
    if (uploads.length != 1 ||
        job['partition'] != ref['partition'] ||
        job['scope_id'] != ref['scope_id'] ||
        job['record_id'] != ref['id'] ||
        job['operation_id'] != ref['id'] ||
        job['kind'] != 'attachment' ||
        plaintext.length != ref['size']) {
      throw const FormatException('crypto_backup_upload_recovery');
    }
    final metadata = jsonDecode(uploads.single['metadata'] as String) as Map;
    final hash = await cryptoSha256(plaintext);
    final sourceHash = await CryptoInventoryJson.hash({
      'scopeId': ref['scope_id'],
      'recordId': ref['id'],
      'operationId': ref['id'],
      'kind': 'attachment',
      'domain': 'content',
      'plainSha256': hash,
    });
    if (hash != ref['sha256'] ||
        hash != metadata['sha256'] ||
        plaintext.length != metadata['size'] ||
        sourceHash != ref['source_hash'] ||
        sourceHash != job['source_hash']) {
      throw const FormatException('crypto_backup_upload_recovery');
    }
  }
}
