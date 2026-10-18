import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:sodium/sodium.dart';

import '../collaboration_database.dart';
import '../../domain/shared_payload_validation.dart' show isSharedUuid;
import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart';
import 'crypto_codec.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart'
    show CryptoKeyLease, CryptoAuthorityPending;

class CryptoArchiveSegment {
  const CryptoArchiveSegment({
    required this.id,
    required this.index,
    required this.size,
    required this.sha256,
  });
  final String id, sha256;
  final int index, size;
  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'size': size,
    'sha256': sha256,
  };
}

class CryptoArchiveManifest {
  const CryptoArchiveManifest({
    required this.migrationId,
    required this.keyId,
    required this.segments,
    required this.cipherManifestHash,
    this.artifactId,
    this.artifactKind,
    this.artifactContext,
  });
  final String migrationId, keyId, cipherManifestHash;
  final List<CryptoArchiveSegment> segments;
  final String? artifactId, artifactKind;
  final Map<String, dynamic>? artifactContext;
  Map<String, dynamic> toJson() => {
    'migrationId': migrationId,
    'keyId': keyId,
    'cipherManifestHash': cipherManifestHash,
    'segments': segments.map((s) => s.toJson()).toList(),
    if (artifactId != null) 'artifactId': artifactId,
    if (artifactKind != null) 'artifactKind': artifactKind,
    if (artifactContext != null) 'artifactContext': artifactContext,
  };
  factory CryptoArchiveManifest.fromJson(Map<String, dynamic> value) =>
      CryptoArchiveManifest(
        migrationId: value['migrationId'] as String,
        keyId: value['keyId'] as String,
        cipherManifestHash: value['cipherManifestHash'] as String,
        artifactId: value['artifactId'] as String?,
        artifactKind: value['artifactKind'] as String?,
        artifactContext: value['artifactContext'] == null
            ? null
            : Map<String, dynamic>.from(value['artifactContext'] as Map),
        segments: List.unmodifiable(
          (value['segments'] as List).map((raw) {
            final s = raw as Map;
            return CryptoArchiveSegment(
              id: s['id'] as String,
              index: s['index'] as int,
              size: s['size'] as int,
              sha256: s['sha256'] as String,
            );
          }),
        ),
      );
}

/// Ciphertext-only staging inside the installation vault. No plaintext file,
/// portable JSON secret, or shared-scope DEK is used for private account history.
class CryptoArchiveStagingStore {
  CryptoArchiveStagingStore({
    required this.database,
    required this.partition,
    required this.crypto,
  });
  final CollaborationDatabase database;
  final String partition;
  final CryptoCodec crypto;
  static const plaintextSegmentSize = 20 * 1024 * 1024;
  static const cipherSegmentLimit = 22 * 1024 * 1024;
  static const chunkSize = 192 * 1024;
  static const streamChunkSize = 64 * 1024;

  /// A draft cannot have been uploaded: no complete manifest exists yet. Only
  /// this unpublished state, with no wrapped/published key, may be restarted.
  Map<String, dynamic> _draftContext(
    String migrationId,
    String? artifactId,
    String? artifactKind,
    Map<String, dynamic>? artifactContext,
  ) => {
    'version': 3,
    'kind': 'archiveDraft',
    'migrationId': migrationId,
    'artifactId': artifactId,
    'artifactKind': artifactKind,
    if (artifactContext != null) 'artifactContext': artifactContext,
  };

  Future<void> restartUnpublishedDraft({
    required String migrationId,
    String? artifactId,
    String? artifactKind,
    Map<String, dynamic>? artifactContext,
  }) async {
    final storageId = artifactId ?? migrationId;
    final rows = await database.rows(
      'SELECT state,manifest FROM crypto_archive_jobs WHERE partition=? AND migration_id=?',
      [partition, storageId],
    );
    if (rows.length == 1 && rows.single['state'] == 'draft') {
      final expected = jsonEncode(
        _draftContext(migrationId, artifactId, artifactKind, artifactContext),
      );
      if (rows.single['manifest'] != expected &&
          !(artifactId == null && rows.single['manifest'] == null)) {
        throw const FormatException('crypto_archive_artifact_context');
      }
      await abandonUnpublished(storageId);
    }
  }

  Future<CryptoArchiveManifest> stage({
    required String migrationId,
    String? artifactId,
    String? artifactKind,
    Map<String, dynamic>? artifactContext,
    required Stream<List<int>> plaintext,
    bool Function()? cancelled,
  }) async {
    if (!isSharedUuid(migrationId)) {
      throw const FormatException('crypto_archive_context');
    }
    if ((artifactId == null) != (artifactKind == null) ||
        artifactId != null &&
            (!isSharedUuid(artifactId) ||
                !const {
                  'capture3SourceWitness',
                  'migrationWitnessV3',
                  'migrationDocumentV3',
                  'migrationLocalIntentsV3',
                }.contains(artifactKind))) {
      throw const FormatException('crypto_archive_artifact_context');
    }
    if (artifactKind == 'migrationLocalIntentsV3') {
      final c = artifactContext;
      const fields = {
        'version',
        'serverId',
        'migrationId',
        'captureId',
        'accountId',
        'sourceInventoryRoot',
        'artifactId',
        'purpose',
      };
      if (c == null ||
          c.length != fields.length ||
          c.keys.any((k) => !fields.contains(k)) ||
          c['version'] != 3 ||
          c['migrationId'] != migrationId ||
          c['artifactId'] != artifactId ||
          c['purpose'] != 'migrationLocalIntents' ||
          ![
            'serverId',
            'captureId',
            'accountId',
          ].every((k) => c[k] is String && isSharedUuid(c[k])) ||
          c['sourceInventoryRoot'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(c['sourceInventoryRoot'])) {
        throw const FormatException('crypto_archive_artifact_context');
      }
    } else if (artifactContext != null) {
      throw const FormatException('crypto_archive_artifact_context');
    }
    final storageId = artifactId ?? migrationId;
    final prior = await database.rows(
      'SELECT * FROM crypto_archive_jobs WHERE partition=? AND migration_id=?',
      [partition, storageId],
    );
    if (prior.isNotEmpty) {
      if (prior.single['state'] == 'draft' ||
          prior.single['manifest'] == null) {
        throw const CryptoAuthorityPending('crypto_archive_stage_interrupted');
      }
      final existing = CryptoArchiveManifest.fromJson(
        jsonDecode(prior.single['manifest'] as String) as Map<String, dynamic>,
      );
      if (existing.migrationId != migrationId ||
          existing.artifactId != artifactId ||
          existing.artifactKind != artifactKind ||
          CryptoInventoryJson.canonical(existing.artifactContext) !=
              CryptoInventoryJson.canonical(artifactContext)) {
        throw const FormatException('crypto_archive_artifact_context');
      }
      return existing;
    }
    final keyId = crypto.randomId();
    final key = crypto.sodium.crypto.secretStream.keygen();
    final raw = key.extractBytes();
    try {
      await database.transaction(() async {
        await database.execute(
          "INSERT INTO crypto_archive_jobs(partition,migration_id,key_id,state,manifest) VALUES(?,?,?,'draft',?)",
          [
            partition,
            storageId,
            keyId,
            jsonEncode(
              _draftContext(
                migrationId,
                artifactId,
                artifactKind,
                artifactContext,
              ),
            ),
          ],
        );
        await database.execute(
          "INSERT INTO crypto_archive_secrets(partition,migration_id,key_id,key_bytes,state) VALUES(?,?,?,?,'draft')",
          [partition, storageId, keyId, raw],
        );
      });
    } catch (_) {
      key.dispose();
      rethrow;
    } finally {
      raw.fillRange(0, raw.length, 0);
    }
    final reader = _ArchiveInput(plaintext, cancelled);
    final descriptors = <CryptoArchiveSegment>[];
    try {
      // Even an empty inventory receives a final authenticated secretstream.
      do {
        final id = crypto.randomId(), index = descriptors.length;
        await database.execute(
          "INSERT INTO crypto_archive_segments(partition,migration_id,key_id,id,segment_index,state) VALUES(?,?,?,?,?,'writing')",
          [partition, storageId, keyId, id, index],
        );
        var size = 0;
        final hash = Sha256().newHashSink();
        await for (final bytes in crypto.sodium.crypto.secretStream.pushChunked(
          // A maximum-size existing document still fits one normal object
          // stream when its short authenticated format prefix is included.
          messageStream: reader.segment(
            plaintextSegmentSize +
                (artifactKind == 'migrationDocumentV3' ? 1024 : 0),
          ),
          key: key,
          chunkSize: streamChunkSize,
        )) {
          if (cancelled?.call() == true) {
            throw const CryptoAuthorityPending('crypto_archive_cancelled');
          }
          if (bytes.length > chunkSize ||
              size + bytes.length > cipherSegmentLimit) {
            throw const FormatException('crypto_archive_size');
          }
          hash.add(bytes);
          await database.execute(
            'INSERT INTO crypto_archive_chunks VALUES(?,?,?,?)',
            [partition, id, size, Uint8List.fromList(bytes)],
          );
          size += bytes.length;
        }
        hash.close();
        final digest = (await hash.hash()).bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        await database.execute(
          "UPDATE crypto_archive_segments SET size=?,sha256=?,state='complete' WHERE partition=? AND id=? AND state='writing'",
          [size, digest, partition, id],
        );
        descriptors.add(
          CryptoArchiveSegment(
            id: id,
            index: index,
            size: size,
            sha256: digest,
          ),
        );
      } while (await reader.hasMore());
      final manifest = CryptoArchiveManifest(
        migrationId: migrationId,
        artifactId: artifactId,
        artifactKind: artifactKind,
        artifactContext: artifactContext == null
            ? null
            : Map.unmodifiable(artifactContext),
        keyId: keyId,
        segments: List.unmodifiable(descriptors),
        cipherManifestHash: await CryptoInventoryJson.hash(
          descriptors.map((d) => d.toJson()).toList(),
        ),
      );
      await database.execute(
        "UPDATE crypto_archive_jobs SET state='staged',manifest=? WHERE partition=? AND migration_id=? AND key_id=? AND state='draft'",
        [jsonEncode(manifest.toJson()), partition, storageId, keyId],
      );
      return manifest;
    } finally {
      await reader.close();
      key.dispose();
    }
  }

  /// Only an unpublished interrupted generation may be explicitly restarted.
  /// Complete/published generations retain their exact IDs, key and ciphertext.
  Future<void> abandonUnpublished(
    String migrationId,
  ) => database.transaction(() async {
    final jobs = await database.rows(
      "SELECT j.*,s.context,s.envelopes FROM crypto_archive_jobs j JOIN crypto_archive_secrets s ON s.partition=j.partition AND s.key_id=j.key_id WHERE j.partition=? AND j.migration_id=?",
      [partition, migrationId],
    );
    if (jobs.length != 1 ||
        jobs.single['state'] != 'draft' ||
        jobs.single['context'] != null ||
        jobs.single['envelopes'] != null) {
      throw const FormatException('crypto_archive_generation_immutable');
    }
    final keyId = jobs.single['key_id'];
    await database.execute(
      'DELETE FROM crypto_archive_chunks WHERE partition=? AND segment_id IN (SELECT id FROM crypto_archive_segments WHERE partition=? AND key_id=?)',
      [partition, partition, keyId],
    );
    await database.execute(
      'DELETE FROM crypto_archive_segments WHERE partition=? AND key_id=?',
      [partition, keyId],
    );
    await database.execute(
      'DELETE FROM crypto_archive_secrets WHERE partition=? AND key_id=?',
      [partition, keyId],
    );
    await database.execute(
      'DELETE FROM crypto_archive_jobs WHERE partition=? AND migration_id=?',
      [partition, migrationId],
    );
  });

  /// Fresh readers verify the durable SQL bytes, not the producer's buffers.
  Future<void> importSegment({
    required CryptoArchiveManifest manifest,
    required CryptoArchiveSegment segment,
    required Stream<List<int>> ciphertext,
  }) async {
    final prior = await database.rows(
      'SELECT * FROM crypto_archive_segments WHERE partition=? AND id=?',
      [partition, segment.id],
    );
    if (prior.isNotEmpty) {
      final row = prior.single;
      if (row['migration_id'] != manifest.migrationId ||
          row['key_id'] != manifest.keyId ||
          row['segment_index'] != segment.index) {
        throw const FormatException('crypto_archive_segment_context');
      }
      if (row['state'] == 'complete') {
        if (row['size'] != segment.size || row['sha256'] != segment.sha256)
          throw const FormatException('crypto_archive_segment_context');
        // Cached complete is not authority: reopen and hash every retained byte.
        await for (final _ in cipher(segment)) {}
        return;
      }
      if (row['state'] != 'writing' ||
          (await database.rows(
            'SELECT 1 FROM crypto_archive_jobs WHERE partition=? AND key_id=? LIMIT 1',
            [partition, manifest.keyId],
          )).isNotEmpty) {
        throw const FormatException('crypto_archive_stage_interrupted');
      }
      // Only an imported, unpublished candidate can be retried from its exact
      // independently authenticated manifest. Never discard a producer journal.
      await database.execute(
        'DELETE FROM crypto_archive_chunks WHERE partition=? AND segment_id=?',
        [partition, segment.id],
      );
      await database.execute(
        'DELETE FROM crypto_archive_segments WHERE partition=? AND id=?',
        [partition, segment.id],
      );
    }
    await database.execute(
      "INSERT INTO crypto_archive_segments(partition,migration_id,key_id,id,segment_index,state) VALUES(?,?,?,?,?,'writing')",
      [
        partition,
        manifest.migrationId,
        manifest.keyId,
        segment.id,
        segment.index,
      ],
    );
    final hash = Sha256().newHashSink();
    var offset = 0;
    await for (final bytes in ciphertext) {
      if (bytes.isEmpty ||
          bytes.length > chunkSize ||
          offset + bytes.length > segment.size) {
        throw const FormatException('crypto_archive_size');
      }
      hash.add(bytes);
      await database.execute(
        'INSERT INTO crypto_archive_chunks VALUES(?,?,?,?)',
        [partition, segment.id, offset, Uint8List.fromList(bytes)],
      );
      offset += bytes.length;
    }
    hash.close();
    final digest = (await hash.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (offset != segment.size || digest != segment.sha256)
      throw const FormatException('crypto_archive_integrity');
    await database.execute(
      "UPDATE crypto_archive_segments SET state='complete',size=?,sha256=? WHERE partition=? AND id=?",
      [offset, digest, partition, segment.id],
    );
  }

  /// Fresh readers verify the durable SQL bytes, not the producer's buffers.
  Stream<List<int>> cipher(CryptoArchiveSegment segment) async* {
    var offset = 0;
    final hash = Sha256().newHashSink();
    while (offset < segment.size) {
      final rows = await database.rows(
        'SELECT bytes FROM crypto_archive_chunks WHERE partition=? AND segment_id=? AND chunk_offset=?',
        [partition, segment.id, offset],
      );
      if (rows.length != 1)
        throw const FormatException('crypto_archive_incomplete');
      final bytes = Uint8List.fromList(
        (rows.single['bytes'] as List).cast<int>(),
      );
      if (bytes.isEmpty ||
          bytes.length > chunkSize ||
          offset + bytes.length > segment.size) {
        throw const FormatException('crypto_archive_size');
      }
      hash.add(bytes);
      offset += bytes.length;
      yield bytes;
    }
    hash.close();
    final digest = (await hash.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (digest != segment.sha256)
      throw const FormatException('crypto_archive_integrity');
  }

  /// Each segment final tag and the ordered cipher manifest are mandatory.
  Stream<List<int>> open(CryptoArchiveManifest manifest, SecureKey key) async* {
    if (manifest.segments.isEmpty ||
        await CryptoInventoryJson.hash(
              manifest.segments.map((d) => d.toJson()).toList(),
            ) !=
            manifest.cipherManifestHash) {
      throw const FormatException('crypto_archive_manifest');
    }
    for (var index = 0; index < manifest.segments.length; index++) {
      final segment = manifest.segments[index];
      if (segment.index != index || !isSharedUuid(segment.id)) {
        throw const FormatException('crypto_archive_manifest');
      }
      try {
        yield* crypto.sodium.crypto.secretStream.pullChunked(
          cipherStream: cipher(segment),
          key: key,
          chunkSize: streamChunkSize,
        );
      } on SodiumException {
        throw const FormatException('crypto_archive_authentication');
      } on StreamClosedEarlyException {
        throw const FormatException('crypto_archive_incomplete');
      } on InvalidHeaderException {
        throw const FormatException('crypto_archive_header');
      }
    }
  }
}

class _ArchiveInput {
  _ArchiveInput(Stream<List<int>> stream, this.cancelled)
    : iterator = StreamIterator(stream);
  final StreamIterator<List<int>> iterator;
  final bool Function()? cancelled;
  List<int>? pending;
  var position = 0, ended = false;
  Future<bool> hasMore() async {
    if (cancelled?.call() == true) {
      throw const CryptoAuthorityPending('crypto_archive_cancelled');
    }
    while (!ended && (pending == null || position == pending!.length)) {
      ended = !await iterator.moveNext();
      pending = ended ? null : iterator.current;
      position = 0;
    }
    return !ended;
  }

  Stream<List<int>> segment(int limit) async* {
    var emitted = 0;
    while (emitted < limit && await hasMore()) {
      final count = (pending!.length - position).clamp(
        0,
        (limit - emitted).clamp(0, CryptoArchiveStagingStore.streamChunkSize),
      );
      // The source may zero/reuse its buffer after requesting the next item.
      final part = Uint8List.fromList(
        pending!.sublist(position, position + count),
      );
      position += count;
      emitted += count;
      try {
        yield part;
      } finally {
        part.fillRange(0, part.length, 0);
      }
    }
  }

  Future<void> close() => iterator.cancel();
}

/// Device and recovery envelopes are immutable signed account-keyring entries.
/// The raw draft key is removed only after the complete verified entry chain
/// contains both saved envelopes. Root rotation retains old encryption roots.
class CryptoAccountArchiveKeyService {
  CryptoAccountArchiveKeyService(this.account);
  final AccountCryptoV2Workflow account;
  CryptoCodec get crypto => account.directory.reducer.crypto;
  CollaborationDatabase get database => account.store.database;
  String get partition => account.store.partition;

  Map<String, dynamic> context(CryptoArchiveManifest manifest) => {
    'version': 2,
    'kind': 'accountArchiveKey',
    'serverId': account.directory.session.profile.serverId,
    'accountId': account.directory.accountId,
    'migrationId': manifest.migrationId,
    'domain': 'accountPrivate',
    'keyId': manifest.keyId,
    'cipherManifestHash': manifest.cipherManifestHash,
    if (manifest.artifactId != null) 'artifactId': manifest.artifactId,
    if (manifest.artifactKind != null) 'artifactKind': manifest.artifactKind,
    if (manifest.artifactContext != null)
      'artifactContext': manifest.artifactContext,
  };

  Future<void> publish(CryptoArchiveManifest manifest) async {
    final directory = await account.directory.requireFresh();
    await database.execute(
      "UPDATE crypto_archive_jobs SET state='published' WHERE partition=? AND migration_id=? AND key_id=? AND state='staged'",
      [partition, manifest.artifactId ?? manifest.migrationId, manifest.keyId],
    );
    final rows = await database.rows(
      'SELECT * FROM crypto_archive_secrets WHERE partition=? AND key_id=? AND migration_id=?',
      [partition, manifest.keyId, manifest.artifactId ?? manifest.migrationId],
    );
    if (rows.length != 1)
      throw const FormatException('crypto_archive_key_missing');
    final row = rows.single;
    final expected = context(manifest);
    if (row['context'] != null &&
        row['context'] != CryptoInventoryJson.canonical(expected)) {
      throw const FormatException('crypto_archive_context');
    }
    late List<Map<String, dynamic>> entries;
    if (row['envelopes'] != null) {
      entries = (jsonDecode(row['envelopes'] as String) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } else {
      if (row['key_bytes'] == null)
        throw const FormatException('crypto_archive_key_missing');
      final raw = Uint8List.fromList((row['key_bytes'] as List).cast<int>());
      final key = crypto.sodium.secureCopy(raw);
      raw.fillRange(0, raw.length, 0);
      try {
        entries = [
          for (final recipient in [
            {
              'kind': 'device',
              'id': account.deviceId,
              'public': directory.activeDevice(
                account.deviceId,
              )['encryptionKeyBase64'],
            },
            {
              'kind': 'recovery',
              'id': directory.snapshot['recoveryRootEpochId'],
              'public': directory.snapshot['rootEncryptionKeyBase64'],
            },
          ])
            {
              'id': manifest.keyId,
              'recipientKind': recipient['kind'],
              'recipientId': recipient['id'],
              'recipientPublicKeyBase64': recipient['public'],
              'sealedEnvelopeBase64': crypto.sealKey(
                key: key,
                recipientPublicKey: cryptoBase64(
                  recipient['public'],
                  length: 32,
                ),
                context: expected,
              ),
            },
        ];
        await database.execute(
          'UPDATE crypto_archive_secrets SET context=?,envelopes=? WHERE partition=? AND key_id=?',
          [
            CryptoInventoryJson.canonical(expected),
            jsonEncode(entries),
            partition,
            manifest.keyId,
          ],
        );
      } finally {
        key.dispose();
      }
    }
    final envelopeHashes = <String, String>{};
    bool included(VerifiedAccountDirectory value) => entries.every(
      (entry) => value.keyringEntries.any(
        (known) =>
            known['id'] == entry['id'] &&
            known['recipientKind'] == entry['recipientKind'] &&
            known['recipientId'] == entry['recipientId'] &&
            known['recipientPublicKeyBase64'] ==
                entry['recipientPublicKeyBase64'] &&
            known['envelopeHash'] ==
                envelopeHashes[entry['sealedEnvelopeBase64']],
      ),
    );
    // Compute once; directory snapshots authenticate every envelope digest.
    for (final entry in entries) {
      envelopeHashes[entry['sealedEnvelopeBase64'] as String] =
          await cryptoSha256(cryptoBase64(entry['sealedEnvelopeBase64']));
    }
    if (!included(directory)) await account.appendKeyringEntries(entries);
    final verified = await account.directory.cachedVerifiedDirectory();
    if (!included(verified))
      throw const CryptoAuthorityPending('crypto_archive_keyring_pending');
    await database.execute(
      "UPDATE crypto_archive_secrets SET key_bytes=NULL,state='wrapped' WHERE partition=? AND key_id=?",
      [partition, manifest.keyId],
    );
  }

  /// The callback returns an OWNED transient historical recovery key pair, if
  /// available from the newly opened recovery file's authenticated root bundle.
  /// No recovery root is stored by this service.
  Future<CryptoKeyLease> open(
    CryptoArchiveManifest manifest, {
    Future<KeyPair?> Function(String publicKeyBase64)? recoveryKey,
    bool recoveryOnly = false,
  }) async {
    final local = await database.rows(
      'SELECT envelopes FROM crypto_archive_secrets WHERE partition=? AND key_id=? AND migration_id=?',
      [partition, manifest.keyId, manifest.artifactId ?? manifest.migrationId],
    );
    final entries = <Map<String, dynamic>>[
      if (local.isNotEmpty && local.single['envelopes'] != null)
        ...(jsonDecode(local.single['envelopes'] as String) as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
    ];
    return openBoundKey(
      keyId: manifest.keyId,
      expectedContext: context(manifest),
      localEnvelopes: entries,
      recoveryKey: recoveryKey,
      recoveryOnly: recoveryOnly,
    );
  }

  /// Shared authenticated account-keyring reader for purpose-bound capture
  /// keys. This does not install keys, trust server rows, or persist roots.
  Future<CryptoKeyLease> openBoundKey({
    required String keyId,
    required Map<String, dynamic> expectedContext,
    List<Map<String, dynamic>> localEnvelopes = const [],
    Future<KeyPair?> Function(String publicKeyBase64)? recoveryKey,
    bool recoveryOnly = false,
    VerifiedAccountDirectory? recoveryDirectory,
  }) async {
    if (recoveryDirectory != null &&
        (!recoveryOnly ||
            recoveryKey == null ||
            recoveryDirectory.accountId != account.directory.accountId ||
            recoveryDirectory.serverId !=
                account.directory.session.profile.serverId)) {
      throw const FormatException('crypto_archive_recovery_context');
    }
    // A FILE-authenticated prefix may open historical ciphertext without
    // asserting that this is the latest directory or authorizing any write.
    final directory =
        recoveryDirectory ?? await account.directory.cachedVerifiedDirectory();
    final keyEntries = directory.keyringEntries
        .where((e) => e['id'] == keyId)
        .toList();
    if (keyEntries.isEmpty) {
      throw const CryptoAuthorityPending('crypto_archive_keyring_pending');
    }
    Future<CryptoKeyLease?> tryOpen(
      List<Map<String, dynamic>> candidates,
    ) async {
      for (final entry in candidates) {
        if (entry['id'] != keyId) {
          throw const FormatException('crypto_archive_keyring_proof');
        }
        final matches = keyEntries.where(
          (e) =>
              e['recipientKind'] == entry['recipientKind'] &&
              e['recipientId'] == entry['recipientId'] &&
              e['recipientPublicKeyBase64'] ==
                  entry['recipientPublicKeyBase64'],
        );
        if (matches.length != 1 ||
            matches.single['envelopeHash'] !=
                await cryptoSha256(
                  cryptoBase64(entry['sealedEnvelopeBase64']),
                )) {
          throw const FormatException('crypto_archive_keyring_proof');
        }
        KeyPair? recipient;
        if (!recoveryOnly &&
            entry['recipientKind'] == 'device' &&
            entry['recipientId'] == account.deviceId) {
          directory.activeDevice(account.deviceId);
          recipient = await account.encryptionKey();
        } else if (entry['recipientKind'] == 'recovery' &&
            recoveryKey != null) {
          recipient = await recoveryKey(
            entry['recipientPublicKeyBase64'] as String,
          );
        }
        if (recipient == null) continue;
        try {
          if (base64Encode(recipient.publicKey) !=
              entry['recipientPublicKeyBase64']) {
            throw const FormatException('crypto_archive_recipient');
          }
          return CryptoKeyLease.owned(
            crypto.openKey(
              sealed: entry['sealedEnvelopeBase64'] as String,
              recipient: recipient,
              context: expectedContext,
            ),
          );
        } finally {
          recipient.secretKey.dispose();
        }
      }
      return null;
    }

    final cached = await tryOpen(localEnvelopes);
    if (cached != null) return cached;
    String? after;
    while (true) {
      final page = await account.directory.call('crypto2.account.entries', {
        if (after != null) 'afterId': after,
        'limit': 20,
      });
      final raw = page['entries'];
      if (raw is! List || raw.length > 20 * 129 || raw.any((e) => e is! Map)) {
        throw const FormatException('crypto_archive_keyring_page');
      }
      final candidates = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['id'] == keyId)
          .toList();
      final opened = await tryOpen(candidates);
      if (opened != null) return opened;
      if (page['hasMore'] != true || candidates.isNotEmpty) break;
      final next = page['nextAfterId'];
      if (next is! String || next == after)
        throw const FormatException('crypto_archive_keyring_cursor');
      after = next;
    }
    throw const CryptoAuthorityPending('crypto_archive_recovery_file_required');
  }
}
