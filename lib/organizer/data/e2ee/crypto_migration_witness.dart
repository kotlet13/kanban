import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import '../collaboration_database.dart';
import 'crypto_account_archive.dart';
import 'crypto_capture_v3.dart';
import 'crypto_codec.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart' show CryptoAuthorityPending;

/// Public ciphertext context. Raw SQL identifiers, comparison salts and hashes
/// are deliberately confined to the encrypted witness. There is no record proof
/// hash here: the later signed source binding commits to both without a cycle.
class CryptoMigrationWitnessContext {
  CryptoMigrationWitnessContext(Map<String, dynamic> value)
    : value = Map.unmodifiable(value) {
    final audit = value['purpose'] == 'migrationAudit';
    final fields = {
      'version',
      'purpose',
      'serverId',
      'accountId',
      'captureId',
      'migrationId',
      'bindingId',
      'sourceInventoryRoot',
      'sourceCommitment',
      'scopeId',
      'domain',
      'epoch',
      'accessRevision',
      'membershipHeadHash',
      if (audit) ...[
        'recordId',
        'legacyRevision',
      ] else ...[
        'type',
        'sourceKind',
        'canonicalId',
        'wireId',
      ],
    };
    if (value.length != fields.length ||
        !value.keys.every(fields.contains) ||
        value['version'] != 3 ||
        !const {
          'migrationWitness',
          'migrationAudit',
        }.contains(value['purpose']) ||
        ![
          'serverId',
          'accountId',
          'captureId',
          'migrationId',
          'bindingId',
          'scopeId',
          if (audit) 'recordId' else 'canonicalId',
        ].every((k) => isCryptoCanonicalUuid(value[k])) ||
        ![
          'sourceInventoryRoot',
          'sourceCommitment',
          'membershipHeadHash',
        ].every(
          (k) =>
              value[k] is String &&
              RegExp(r'^[a-f0-9]{64}$').hasMatch(value[k]),
        ) ||
        value['epoch'] is! int ||
        value['epoch'] < 1 ||
        value['accessRevision'] is! int ||
        value['accessRevision'] < 0 ||
        (audit
            ? value['domain'] != 'finance' ||
                  value['legacyRevision'] is! int ||
                  value['legacyRevision'] < 1 ||
                  value['legacyRevision'] > 9007199254740991
            : value['type'] is! String ||
                  value['type'] == 'scopeMetadata' ||
                  value['sourceKind'] is! String ||
                  value['domain'] is! String)) {
      throw const FormatException('crypto_migration_witness_context');
    }
    if (audit) return;
    final address = CryptoRecordAddress(
      serverId: value['serverId'],
      scopeId: value['scopeId'],
      domain: value['domain'],
      sourceKind: value['sourceKind'],
      canonicalId: value['canonicalId'],
      type: value['type'],
    );
    if (address.wireId != value['wireId']) {
      throw const FormatException('crypto_migration_witness_address');
    }
  }
  final Map<String, dynamic> value;

  void requireSource(CryptoCaptureSourceContext source) {
    for (final key in [
      'serverId',
      'accountId',
      'captureId',
      'migrationId',
      'scopeId',
      'domain',
    ]) {
      if (value[key] != source.toJson()[key]) {
        throw const FormatException('crypto_migration_witness_source');
      }
    }
    // The complete private scope row has a separate, manager-only sanitized
    // transformation. It must never enter a child-domain witness blob.
    if (source.sourceTable == 'familyhub_scopes') {
      throw const FormatException('crypto_migration_witness_private_scope');
    }
    if ((value['purpose'] == 'migrationAudit') !=
        (source.sourceTable == 'familyhub_finance_audit')) {
      throw const FormatException('crypto_migration_witness_source');
    }
  }

  CryptoCaptureBinding get binding => CryptoCaptureBinding(
    bindingId: value['bindingId'],
    scopeId: value['scopeId'],
    domain: value['domain'],
    sourceCommitment: value['sourceCommitment'],
  );
}

/// One durable secretstream representation for every source, including a
/// tombstone. Domain authority and the final migration certificate are checked
/// by the caller; decrypting this object alone grants no write/read exception.
class CryptoMigrationWitness {
  CryptoMigrationWitness({
    required this.database,
    required this.partition,
    required this.crypto,
    this.checkpoint,
  });
  final CollaborationDatabase database;
  final String partition;
  final CryptoCodec crypto;
  final Future<void> Function(String phase)? checkpoint;
  static const maxWitnessBytes = 64 * 1024 * 1024;
  static const _prefix = 'JivieMigrationWitness/v3\n';
  CryptoArchiveStagingStore get staging => CryptoArchiveStagingStore(
    database: database,
    partition: partition,
    crypto: crypto,
  );

  Future<Map<String, dynamic>> stage({
    required CryptoMigrationWitnessContext context,
    required Map<String, dynamic> witness,
    required SecureKey domainKey,
  }) async {
    final source = CryptoCaptureSourceContext.fromJson(
      Map<String, dynamic>.from(witness['context'] as Map),
    );
    context.requireSource(source);
    await CryptoCaptureV3.verifyWitness(
      binding: context.binding,
      context: source,
      witness: witness,
    );
    final id = context.value['bindingId'] as String;
    final canonical = CryptoInventoryJson.canonical(context.value);
    await database.transaction(() async {
      final rows = await database.rows(
        'SELECT context FROM crypto_migration_witnesses WHERE partition=? AND binding_id=?',
        [partition, id],
      );
      if (rows.isNotEmpty && rows.single['context'] != canonical) {
        throw const FormatException('crypto_migration_witness_immutable');
      }
      await database.execute(
        'INSERT OR IGNORE INTO crypto_migration_witnesses(partition,binding_id,context) VALUES(?,?,?)',
        [partition, id, canonical],
      );
    });
    final saved = (await database.rows(
      'SELECT descriptor FROM crypto_migration_witnesses WHERE partition=? AND binding_id=?',
      [partition, id],
    )).single['descriptor'];
    if (saved != null) {
      final descriptor = Map<String, dynamic>.from(jsonDecode(saved as String));
      await validateDescriptor(context, descriptor);
      // Reopen the durable AEAD manifest rather than trusting a local status bit.
      final key = _openManifest(context, descriptor, domainKey);
      key.dispose();
      return descriptor;
    }
    final plain = CryptoInventoryJson.encode(witness);
    if (plain.length + utf8.encode(_prefix).length > maxWitnessBytes) {
      plain.fillRange(0, plain.length, 0);
      throw const CryptoAuthorityPending('crypto_migration_witness_size');
    }
    late CryptoArchiveManifest manifest;
    try {
      await staging.restartUnpublishedDraft(
        migrationId: context.value['migrationId'],
        artifactId: id,
        artifactKind: 'migrationWitnessV3',
      );
      manifest = await staging.stage(
        migrationId: context.value['migrationId'],
        artifactId: id,
        artifactKind: 'migrationWitnessV3',
        plaintext: (() async* {
          yield utf8.encode(_prefix);
          await checkpoint?.call('witness_streaming');
          for (var offset = 0; offset < plain.length; offset += 65536) {
            yield Uint8List.sublistView(
              plain,
              offset,
              (offset + 65536).clamp(0, plain.length),
            );
          }
        })(),
      );
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
    await checkpoint?.call('witness_staged');
    final rows = await database.rows(
      'SELECT key_bytes FROM crypto_archive_secrets WHERE partition=? AND key_id=?',
      [partition, manifest.keyId],
    );
    if (rows.length != 1 || rows.single['key_bytes'] == null) {
      throw const CryptoAuthorityPending(
        'crypto_migration_witness_key_pending',
      );
    }
    final raw = Uint8List.fromList(
      (rows.single['key_bytes'] as List).cast<int>(),
    );
    Uint8List? secret;
    try {
      secret = CryptoInventoryJson.encode({
        'version': 3,
        'objectKeyBase64': base64Encode(raw),
        'manifest': manifest.toJson(),
      });
      final envelope = crypto.encrypt(
        plaintext: secret,
        key: domainKey,
        context: context.value,
      );
      final descriptor = <String, dynamic>{
        'version': 3,
        'purpose': context.value['purpose'],
        'context': context.value,
        'cipherManifestHash': manifest.cipherManifestHash,
        'segments': manifest.segments.map((s) => s.toJson()).toList(),
        'manifestBase64': base64Encode(CryptoJson.encode(envelope)),
      };
      if (cryptoBase64(descriptor['manifestBase64']).length > 16384) {
        throw const FormatException('crypto_migration_witness_manifest_size');
      }
      await database.transaction(() async {
        await database.execute(
          'UPDATE crypto_migration_witnesses SET descriptor=? WHERE partition=? AND binding_id=? AND descriptor IS NULL',
          [jsonEncode(descriptor), partition, id],
        );
        final exact = (await database.rows(
          'SELECT descriptor FROM crypto_migration_witnesses WHERE partition=? AND binding_id=?',
          [partition, id],
        )).single['descriptor'];
        if (exact != jsonEncode(descriptor)) {
          throw const FormatException('crypto_migration_witness_immutable');
        }
        await database.execute(
          "UPDATE crypto_archive_secrets SET key_bytes=NULL,state='wrapped' WHERE partition=? AND key_id=?",
          [partition, manifest.keyId],
        );
      });
      await checkpoint?.call('witness_wrapped');
      return descriptor;
    } finally {
      raw.fillRange(0, raw.length, 0);
      secret?.fillRange(0, secret.length, 0);
    }
  }

  /// Read a completed witness produced by this installation without importing
  /// it under the transport-only cache namespace. Local rows are routing only:
  /// the domain AEAD authenticates the exact producer manifest, then every
  /// ciphertext byte is rehashed before the unchanged source verifier runs.
  Future<Map<String, dynamic>?> openProduced({
    required CryptoMigrationWitnessContext context,
    required Map<String, dynamic> descriptor,
    required SecureKey domainKey,
  }) async {
    if (context.value['purpose'] != 'migrationWitness') return null;
    await validateDescriptor(context, descriptor);
    final binding = context.value['bindingId'];
    final produced = await database.rows(
      'SELECT context,descriptor FROM crypto_migration_witnesses WHERE partition=? AND binding_id=?',
      [partition, binding],
    );
    if (produced.isEmpty) return null;
    if (produced.length != 1 ||
        produced.single['descriptor'] == null ||
        produced.single['context'] !=
            CryptoInventoryJson.canonical(context.value) ||
        CryptoInventoryJson.canonical(
              jsonDecode(produced.single['descriptor'] as String),
            ) !=
            CryptoInventoryJson.canonical(descriptor)) {
      throw const FormatException('crypto_migration_witness_immutable');
    }
    final jobs = await database.rows(
      'SELECT key_id,state,manifest FROM crypto_archive_jobs WHERE partition=? AND migration_id=?',
      [partition, binding],
    );
    if (jobs.length != 1 ||
        jobs.single['state'] != 'staged' ||
        jobs.single['manifest'] == null) {
      throw const FormatException('crypto_archive_segment_context');
    }
    final manifest = CryptoArchiveManifest.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(jobs.single['manifest'] as String) as Map,
      ),
    );
    if (manifest.migrationId != context.value['migrationId'] ||
        manifest.artifactId != binding ||
        manifest.artifactKind != 'migrationWitnessV3' ||
        manifest.keyId != jobs.single['key_id']) {
      throw const FormatException('crypto_archive_segment_context');
    }
    final key = _openManifest(
      context,
      descriptor,
      domainKey,
      expectedManifest: manifest,
    );
    key.dispose();
    for (final segment in manifest.segments) {
      final rows = await database.rows(
        'SELECT migration_id,key_id,segment_index,state,size,sha256 FROM crypto_archive_segments WHERE partition=? AND id=?',
        [partition, segment.id],
      );
      if (rows.length != 1 ||
          rows.single['migration_id'] != binding ||
          rows.single['key_id'] != manifest.keyId ||
          rows.single['segment_index'] != segment.index ||
          rows.single['state'] != 'complete' ||
          rows.single['size'] != segment.size ||
          rows.single['sha256'] != segment.sha256) {
        throw const FormatException('crypto_archive_segment_context');
      }
      await for (final _ in staging.cipher(segment)) {}
    }
    return open(context: context, descriptor: descriptor, domainKey: domainKey);
  }

  SecureKey _openManifest(
    CryptoMigrationWitnessContext context,
    Map<String, dynamic> descriptor,
    SecureKey domainKey, {
    CryptoArchiveManifest? expectedManifest,
  }) {
    if (descriptor.length != 6 ||
        descriptor['version'] != 3 ||
        descriptor['purpose'] != context.value['purpose'] ||
        CryptoInventoryJson.canonical(descriptor['context']) !=
            CryptoInventoryJson.canonical(context.value)) {
      throw const FormatException('crypto_migration_witness_descriptor');
    }
    final bytes = crypto.decrypt(
      envelope: Map<String, dynamic>.from(
        CryptoJson.decode(
              cryptoBase64(descriptor['manifestBase64'], max: 16384),
            )
            as Map,
      ),
      key: domainKey,
      context: context.value,
    );
    try {
      final plain = jsonDecode(utf8.decode(bytes)) as Map;
      final manifest = CryptoArchiveManifest.fromJson(
        Map<String, dynamic>.from(plain['manifest'] as Map),
      );
      if (plain.length != 3 ||
          plain['version'] != 3 ||
          (expectedManifest != null &&
              CryptoInventoryJson.canonical(manifest.toJson()) !=
                  CryptoInventoryJson.canonical(expectedManifest.toJson())) ||
          manifest.migrationId != context.value['migrationId'] ||
          manifest.artifactId != context.value['bindingId'] ||
          manifest.artifactKind != 'migrationWitnessV3' ||
          manifest.cipherManifestHash != descriptor['cipherManifestHash'] ||
          manifest.segments.isEmpty ||
          manifest.segments.length > 4 ||
          CryptoInventoryJson.canonical(
                manifest.segments.map((s) => s.toJson()).toList(),
              ) !=
              CryptoInventoryJson.canonical(descriptor['segments'])) {
        throw const FormatException('crypto_migration_witness_manifest');
      }
      final raw = cryptoBase64(plain['objectKeyBase64'], length: 32);
      try {
        return crypto.sodium.secureCopy(raw);
      } finally {
        raw.fillRange(0, raw.length, 0);
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Future<List<CryptoArchiveSegment>> validateDescriptor(
    CryptoMigrationWitnessContext context,
    Map<String, dynamic> descriptor,
  ) async {
    if (descriptor.length != 6 ||
        descriptor['version'] != 3 ||
        descriptor['purpose'] != context.value['purpose'] ||
        CryptoInventoryJson.canonical(descriptor['context']) !=
            CryptoInventoryJson.canonical(context.value) ||
        descriptor['segments'] is! List ||
        (descriptor['segments'] as List).isEmpty ||
        (descriptor['segments'] as List).length > 4) {
      throw const FormatException('crypto_migration_witness_descriptor');
    }
    cryptoBase64(descriptor['manifestBase64'], max: 16384);
    final result = <CryptoArchiveSegment>[], seen = <String>{};
    var total = 0;
    for (final raw in descriptor['segments']) {
      if (raw is! Map ||
          raw.length != 4 ||
          !isCryptoCanonicalUuid(raw['id']) ||
          !seen.add(raw['id']) ||
          raw['index'] != result.length ||
          raw['size'] is! int ||
          raw['size'] < 48 ||
          raw['size'] > CryptoArchiveStagingStore.cipherSegmentLimit ||
          raw['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sha256'])) {
        throw const FormatException('crypto_migration_witness_segments');
      }
      total += raw['size'] as int;
      if (total > maxWitnessBytes + 1024 * 1024) {
        throw const FormatException('crypto_migration_witness_size');
      }
      result.add(
        CryptoArchiveSegment(
          id: raw['id'],
          index: raw['index'],
          size: raw['size'],
          sha256: raw['sha256'],
        ),
      );
    }
    if (await CryptoInventoryJson.hash(
          result.map((s) => s.toJson()).toList(),
        ) !=
        descriptor['cipherManifestHash']) {
      throw const FormatException('crypto_migration_witness_manifest');
    }
    return List.unmodifiable(result);
  }

  /// Call only with ciphertext imported into this isolated staging store. The
  /// full stream/hash/final tags and blinded source comparison finish before a
  /// typed row is returned to a semantic validator, including for deletions.
  Future<Map<String, dynamic>> open({
    required CryptoMigrationWitnessContext context,
    required Map<String, dynamic> descriptor,
    required SecureKey domainKey,
  }) async {
    await validateDescriptor(context, descriptor);
    final key = _openManifest(context, descriptor, domainKey);
    final manifest = CryptoArchiveManifest(
      migrationId: context.value['migrationId'],
      keyId: '',
      cipherManifestHash: descriptor['cipherManifestHash'],
      segments: (descriptor['segments'] as List)
          .map(
            (s) => CryptoArchiveSegment(
              id: s['id'],
              index: s['index'],
              size: s['size'],
              sha256: s['sha256'],
            ),
          )
          .toList(),
    );
    final builder = BytesBuilder(copy: false);
    Uint8List? bytes;
    try {
      await for (final chunk in staging.open(manifest, key)) {
        if (builder.length + chunk.length > maxWitnessBytes) {
          throw const FormatException('crypto_migration_witness_size');
        }
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
      final prefix = utf8.encode(_prefix);
      if (bytes.length < prefix.length ||
          !List.generate(
            prefix.length,
            (i) => bytes![i] == prefix[i],
          ).every((same) => same)) {
        throw const FormatException('crypto_migration_witness_framing');
      }
      final witness = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(Uint8List.sublistView(bytes, prefix.length)))
            as Map,
      );
      final source = CryptoCaptureSourceContext.fromJson(
        Map<String, dynamic>.from(witness['context'] as Map),
      );
      context.requireSource(source);
      await CryptoCaptureV3.verifyWitness(
        binding: context.binding,
        context: source,
        witness: witness,
      );
      return witness;
    } on SodiumException {
      throw const FormatException('crypto_migration_witness_authentication');
    } on StreamClosedEarlyException {
      throw const FormatException('crypto_migration_witness_incomplete');
    } on InvalidHeaderException {
      throw const FormatException('crypto_migration_witness_header');
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      final retained = builder.takeBytes();
      retained.fillRange(0, retained.length, 0);
      key.dispose();
    }
  }
}
