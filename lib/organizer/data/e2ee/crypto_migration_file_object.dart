import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:sodium/sodium.dart';

import '../collaboration_database.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_account_archive.dart';
import 'crypto_codec.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_witness.dart';
import 'crypto_migration_witness_transport.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart' show CryptoAuthorityPending;

/// Capture-authorized physical bytes, encoded in the ordinary document-object
/// format. Source SHA stays inside the domain-encrypted manifest and witness.
/// This helper neither installs a live blob nor confers ordinary WRITE rights.
class CryptoMigrationFileObject {
  CryptoMigrationFileObject({
    required this.database,
    required this.partition,
    required this.crypto,
  });
  final CollaborationDatabase database;
  final String partition;
  final CryptoCodec crypto;
  static const maxSize = 20 * 1024 * 1024;
  static const _prefix = 'JivieObject/v2\n';
  CryptoArchiveStagingStore get staging => CryptoArchiveStagingStore(
    database: database,
    partition: partition,
    crypto: crypto,
  );

  Map<String, dynamic> _aead(Map d, String serverId) => {
    'version': 2,
    'purpose': 'documentObject',
    'serverId': serverId,
    for (final k in ['scopeId', 'id', 'domain', 'epoch', 'membershipHeadHash'])
      k: d[k],
  };

  Future<String> _artifactId(String binding) async {
    final h = await cryptoSha256(
      utf8.encode('JivieMigrationFileArtifact/v3\n$binding'),
    );
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-a${h.substring(17, 20)}-${h.substring(20, 32)}';
  }

  void _source(int size, String sha256) {
    if (size < 0 ||
        size > maxSize ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('crypto_migration_file_source');
    }
  }

  Future<Map<String, dynamic>> stage({
    required CryptoMigrationWitnessContext context,
    required int plainSize,
    required String plainSha256,
    required Stream<List<int>> plaintext,
    required SecureKey domainKey,
  }) async {
    _source(plainSize, plainSha256);
    if (!const {'attachment', 'idea'}.contains(context.value['type'])) {
      throw const FormatException('crypto_migration_file_source');
    }
    final binding = context.value['bindingId'] as String;
    final savedContext = CryptoInventoryJson.canonical(context.value);
    await database.transaction(() async {
      final rows = await database.rows(
        'SELECT context FROM crypto_migration_file_objects WHERE partition=? AND binding_id=?',
        [partition, binding],
      );
      if (rows.isNotEmpty && rows.single['context'] != savedContext) {
        throw const FormatException('crypto_migration_file_immutable');
      }
      await database.execute(
        'INSERT OR IGNORE INTO crypto_migration_file_objects(partition,binding_id,context) VALUES(?,?,?)',
        [partition, binding, savedContext],
      );
    });
    final prior = (await database.rows(
      'SELECT descriptor FROM crypto_migration_file_objects WHERE partition=? AND binding_id=?',
      [partition, binding],
    )).single['descriptor'];
    if (prior != null) {
      final object = Map<String, dynamic>.from(jsonDecode(prior as String));
      final key = _manifestKey(
        context,
        object,
        domainKey,
        plainSize,
        plainSha256,
      );
      key.dispose();
      return object;
    }
    final artifact = await _artifactId(binding);
    await staging.restartUnpublishedDraft(
      migrationId: context.value['migrationId'],
      artifactId: artifact,
      artifactKind: 'migrationDocumentV3',
    );
    Stream<List<int>> checked() async* {
      yield utf8.encode(_prefix);
      var size = 0;
      final hash = Sha256().newHashSink();
      await for (final bytes in plaintext) {
        size += bytes.length;
        if (size > plainSize) {
          throw const FormatException('crypto_migration_file_size');
        }
        hash.add(bytes);
        yield bytes;
      }
      hash.close();
      final digest = (await hash.hash()).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      if (size != plainSize || digest != plainSha256) {
        throw const FormatException('crypto_migration_file_integrity');
      }
    }

    final manifest = await staging.stage(
      migrationId: context.value['migrationId'],
      artifactId: artifact,
      artifactKind: 'migrationDocumentV3',
      plaintext: checked(),
    );
    if (manifest.segments.length != 1) {
      throw const FormatException('crypto_migration_file_segments');
    }
    final segment = manifest.segments.single;
    final rows = await database.rows(
      'SELECT key_bytes FROM crypto_archive_secrets WHERE partition=? AND key_id=?',
      [partition, manifest.keyId],
    );
    if (rows.length != 1 || rows.single['key_bytes'] == null) {
      throw const CryptoAuthorityPending('crypto_migration_file_key_pending');
    }
    final rawKey = Uint8List.fromList(
      (rows.single['key_bytes'] as List).cast<int>(),
    );
    Uint8List? secret;
    try {
      secret = CryptoJson.encode({
        'version': 2,
        'objectKeyBase64': base64Encode(rawKey),
        'plainSize': plainSize,
        'plainSha256': plainSha256,
        'streamChunkBytes': CryptoArchiveStagingStore.streamChunkSize,
      });
      final d = <String, dynamic>{
        'version': 2,
        'id': segment.id,
        'scopeId': context.value['scopeId'],
        'domain': context.value['domain'],
        'epoch': context.value['epoch'],
        'accessRevision': context.value['accessRevision'],
        'membershipHeadHash': context.value['membershipHeadHash'],
        'cipherSize': segment.size,
        'cipherSha256': segment.sha256,
      };
      d['manifestBase64'] = base64Encode(
        CryptoJson.encode(
          crypto.encrypt(
            plaintext: secret,
            key: domainKey,
            context: _aead(d, context.value['serverId']),
          ),
        ),
      );
      final object = <String, dynamic>{
        'version': 3,
        'kind': context.value['type'] == 'idea' ? 'ideaAsset' : 'attachment',
        'canonicalId': context.value['canonicalId'],
        'sourceBindingId': binding,
        'plainSize': plainSize,
        'blob': d,
      };
      await database.transaction(() async {
        await database.execute(
          'UPDATE crypto_migration_file_objects SET descriptor=? WHERE partition=? AND binding_id=? AND descriptor IS NULL',
          [jsonEncode(object), partition, binding],
        );
        final exact = (await database.rows(
          'SELECT descriptor FROM crypto_migration_file_objects WHERE partition=? AND binding_id=?',
          [partition, binding],
        )).single['descriptor'];
        if (exact != jsonEncode(object)) {
          throw const FormatException('crypto_migration_file_immutable');
        }
        await database.execute(
          "UPDATE crypto_archive_secrets SET key_bytes=NULL,state='wrapped' WHERE partition=? AND key_id=?",
          [partition, manifest.keyId],
        );
      });
      return object;
    } finally {
      rawKey.fillRange(0, rawKey.length, 0);
      secret?.fillRange(0, secret.length, 0);
    }
  }

  static Map<String, dynamic> descriptor(
    CryptoMigrationWitnessContext context,
    Map object,
  ) {
    if (object.length != 6 ||
        object['version'] != 3 ||
        object['kind'] !=
            (context.value['type'] == 'idea' ? 'ideaAsset' : 'attachment') ||
        object['canonicalId'] != context.value['canonicalId'] ||
        object['sourceBindingId'] != context.value['bindingId'] ||
        object['plainSize'] is! int ||
        object['plainSize'] < 0 ||
        object['plainSize'] > maxSize ||
        object['blob'] is! Map) {
      throw const FormatException('crypto_migration_file_object');
    }
    final d = Map<String, dynamic>.from(object['blob'] as Map);
    if (d.length != 10 ||
        d['version'] != 2 ||
        !isCryptoCanonicalUuid(d['id']) ||
        d['scopeId'] != context.value['scopeId'] ||
        d['domain'] != context.value['domain'] ||
        d['epoch'] != context.value['epoch'] ||
        d['accessRevision'] != context.value['accessRevision'] ||
        d['membershipHeadHash'] != context.value['membershipHeadHash'] ||
        d['cipherSize'] is! int ||
        d['cipherSize'] < 41 ||
        d['cipherSize'] > CryptoArchiveStagingStore.cipherSegmentLimit ||
        d['cipherSha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(d['cipherSha256'])) {
      throw const FormatException('crypto_migration_file_object');
    }
    cryptoBase64(d['manifestBase64'], max: 16384);
    return d;
  }

  SecureKey _manifestKey(
    CryptoMigrationWitnessContext context,
    Map object,
    SecureKey domainKey,
    int size,
    String sha,
  ) {
    final d = descriptor(context, object);
    final plain = crypto.decrypt(
      envelope: Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(d['manifestBase64'])) as Map,
      ),
      key: domainKey,
      context: _aead(d, context.value['serverId']),
    );
    try {
      final m = CryptoJson.decode(plain);
      if (m is! Map ||
          m.length != 5 ||
          m['version'] != 2 ||
          m['plainSize'] != size ||
          object['plainSize'] != size ||
          m['plainSha256'] != sha ||
          m['streamChunkBytes'] != 65536) {
        throw const FormatException('crypto_migration_file_manifest');
      }
      final raw = cryptoBase64(m['objectKeyBase64'], length: 32);
      try {
        return crypto.sodium.secureCopy(raw);
      } finally {
        raw.fillRange(0, raw.length, 0);
      }
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  Future<void> upload({
    required CryptoMigrationWitnessTransport transport,
    required CryptoMigrationWitnessContext context,
    required Map<String, dynamic> object,
  }) async {
    final d = descriptor(context, object);
    await transport.uploadCipher(
      staging: staging,
      context: context,
      purpose: object['kind'] == 'ideaAsset' ? 'ideaAsset' : 'canonicalPayload',
      segments: [
        CryptoArchiveSegment(
          id: d['id'],
          index: 0,
          size: d['cipherSize'],
          sha256: d['cipherSha256'],
        ),
      ],
      manifestBase64: d['manifestBase64'],
    );
  }

  Future<Uint8List> open({
    required CryptoMigrationWitnessTransport transport,
    required CryptoMigrationWitnessContext context,
    required Map<String, dynamic> object,
    required SecureKey domainKey,
    required int plainSize,
    required String plainSha256,
  }) async {
    _source(plainSize, plainSha256);
    final d = descriptor(context, object);
    final key = _manifestKey(
      context,
      object,
      domainKey,
      plainSize,
      plainSha256,
    );
    try {
      final segment = CryptoArchiveSegment(
        id: d['id'],
        index: 0,
        size: d['cipherSize'],
        sha256: d['cipherSha256'],
      );
      final manifest = CryptoArchiveManifest(
        migrationId: context.value['migrationId'],
        keyId: 'migrationFile:${context.value['bindingId']}',
        segments: [segment],
        cipherManifestHash: await CryptoInventoryJson.hash([segment.toJson()]),
      );
      Stream<List<int>> download() async* {
        var offset = 0;
        while (offset < segment.size) {
          final page = await transport.read('crypto2.migration.blob.get', {
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
            'id': segment.id,
            'purpose': object['kind'] == 'ideaAsset'
                ? 'ideaAsset'
                : 'canonicalPayload',
            'offset': offset,
          });
          final bytes = cryptoBase64(
            page['dataBase64'],
            max: CryptoArchiveStagingStore.chunkSize,
          );
          if (page['id'] != segment.id ||
              page['complete'] != true ||
              page['size'] != segment.size ||
              page['sha256'] != segment.sha256 ||
              page['manifestBase64'] != d['manifestBase64'] ||
              page['offset'] != offset ||
              page['nextOffset'] != offset + bytes.length ||
              bytes.length !=
                  (segment.size - offset).clamp(
                    0,
                    CryptoArchiveStagingStore.chunkSize,
                  )) {
            throw const FormatException('crypto_migration_file_transport');
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
      final builder = BytesBuilder(copy: false);
      await for (final bytes in staging.open(manifest, key)) {
        if (builder.length + bytes.length > plainSize + _prefix.length) {
          throw const FormatException('crypto_migration_file_size');
        }
        builder.add(bytes);
      }
      final all = builder.takeBytes();
      try {
        if (all.length != plainSize + _prefix.length ||
            utf8.decode(Uint8List.sublistView(all, 0, _prefix.length)) !=
                _prefix ||
            await cryptoSha256(Uint8List.sublistView(all, _prefix.length)) !=
                plainSha256) {
          throw const FormatException('crypto_migration_file_integrity');
        }
        final result = Uint8List.fromList(
          Uint8List.sublistView(all, _prefix.length),
        );
        await database.execute(
          'INSERT INTO crypto_document_cache VALUES(?,?,?,?) ON CONFLICT(partition,id) DO UPDATE SET descriptor_hash=excluded.descriptor_hash,bytes=excluded.bytes',
          [partition, d['id'], await CryptoInventoryJson.hash(d), result],
        );
        return result;
      } finally {
        all.fillRange(0, all.length, 0);
      }
    } finally {
      key.dispose();
    }
  }
}
