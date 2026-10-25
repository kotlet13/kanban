import 'crypto_record_blob_target.dart';
import 'crypto_migration_idea_payload.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:sodium/sodium.dart';
import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_project_relocation_target.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';
import 'crypto_codec.dart';
import '../../domain/collaboration_models.dart' show CollaborationException;
import 'crypto_record_address.dart';
import 'crypto_migration_record_source.dart';

/// Standard libsodium secretstream with a fresh object key. The authenticated
/// manifest contains the plaintext digest and object key, encrypted under the
/// verified scope/domain DEK; the server sees only ciphertext size and digest.
class CryptoDocumentBlob {
  CryptoDocumentBlob(this.context);
  final CryptoBusinessSession context;
  static const chunkBytes = 196608,
      streamChunkBytes = 65536,
      maxPlainBytes = 20 * 1024 * 1024;
  get crypto => context.account.directory.reducer.crypto;
  String get p => context.partition;
  Map<String, dynamic> _binding(
    String scope,
    String id,
    String domain,
    int epoch,
    String head,
  ) => {
    'version': 2,
    'purpose': 'documentObject',
    'serverId': context.account.directory.session.profile.serverId,
    'scopeId': scope,
    'id': id,
    'domain': domain,
    'epoch': epoch,
    'membershipHeadHash': head,
  };
  Future<Map<String, dynamic>> stage({
    required String scopeId,
    required String recordId,
    required String operationId,
    required String kind,
    required Uint8List plaintext,
    String domain = 'content',
    PreparedProjectRelocationTarget? relocationTarget,
  }) async {
    if (plaintext.length > maxPlainBytes) {
      throw const FormatException('crypto_document_size');
    }
    final sourceHash = await CryptoInventoryJson.hash({
      'scopeId': scopeId,
      'recordId': recordId,
      'operationId': operationId,
      'kind': kind,
      'domain': domain,
      'plainSha256': await cryptoSha256(plaintext),
    });
    final previous = await context.database.rows(
      'SELECT descriptor,source_hash FROM crypto_document_jobs WHERE partition=? AND scope_id=? AND record_id=? AND operation_id=? AND state<>?',
      [p, scopeId, recordId, operationId, 'writing'],
    );
    if (previous.isNotEmpty) {
      if (previous.single['source_hash'] != sourceHash) {
        throw const FormatException('crypto_document_immutable_intent');
      }
      return Map<String, dynamic>.from(
        jsonDecode(previous.single['descriptor'] as String) as Map,
      );
    }
    if (relocationTarget != null && relocationTarget.head.scopeId != scopeId)
      throw const FormatException('crypto_relocation_blob_scope');
    Map<String, dynamic>? recordPolicyTarget;
    final type = CryptoRecordBlobTarget.typeForKind(kind);
    if (relocationTarget == null &&
        domain == 'content' &&
        type != null &&
        await context.recordPolicies.active(scopeId)) {
      final existing = await context.record(
        scopeId,
        'content',
        recordId,
        type: type,
      );
      if (existing != null && existing['deleted'] != 1) {
        final head = await context.access.currentHead(scopeId);
        if (await context.supportsRecordPolicyBlobTargets()) {
          recordPolicyTarget = {
            'type': type,
            'wireId': context
                .address(scopeId, 'content', type, recordId)
                .wireId,
            'currentRecordProofHash': existing['record_proof_hash'],
          };
          await context.authorizeBlobPolicyTarget(scopeId, recordPolicyTarget);
        } else if (head.member(context.account.directory.accountId)['role'] ==
            'viewer') {
          throw const CryptoAuthorityPending(
            'crypto_record_policy_blob_target_upgrade_pending',
          );
        }
      }
    }
    final write = relocationTarget == null
        ? await context.access.writeContext(
            scopeId,
            domain,
            allowRecordPolicy: recordPolicyTarget != null,
          )
        : null;
    final relocationKey = relocationTarget == null
        ? null
        : await relocationTarget.key(domain);
    final epoch = relocationTarget?.head.epoch ?? write!.epoch;
    final headHash = relocationTarget?.head.headHash ?? write!.headHash;
    final revision =
        relocationTarget?.head.accessRevision ?? write!.accessRevision;
    final contentKey = relocationKey ?? write!.key.key;
    final id = crypto.randomId();
    final key = crypto.sodium.crypto.secretStream.keygen();
    final raw = key.extractBytes();
    try {
      final manifestPlain = CryptoJson.encode({
        'version': 2,
        'objectKeyBase64': base64Encode(raw),
        'plainSize': plaintext.length,
        'plainSha256': await cryptoSha256(plaintext),
        'streamChunkBytes': streamChunkBytes,
      });
      late Map<String, dynamic> encrypted;
      try {
        encrypted = crypto.encrypt(
          plaintext: manifestPlain,
          key: contentKey,
          context: _binding(scopeId, id, domain, epoch, headHash),
        );
      } finally {
        manifestPlain.fillRange(0, manifestPlain.length, 0);
      }
      final manifest = base64Encode(CryptoJson.encode(encrypted));
      // No publication until the complete immutable cipher and manifest exist.
      final builder = BytesBuilder(copy: false);
      await for (final bytes in crypto.sodium.crypto.secretStream.pushChunked(
        messageStream: (() async* {
          yield utf8.encode('JivieObject/v2\n');
          yield plaintext;
        })().cast<List<int>>(),
        key: key,
        chunkSize: streamChunkBytes,
      )) {
        builder.add(bytes);
      }
      final cipher = builder.takeBytes();
      final descriptor = <String, dynamic>{
        'version': 2,
        'id': id,
        'scopeId': scopeId,
        'domain': domain,
        'epoch': epoch,
        'accessRevision': revision,
        'membershipHeadHash': headHash,
        'cipherSize': cipher.length,
        'cipherSha256': await cryptoSha256(cipher),
        'manifestBase64': manifest,
        if (recordPolicyTarget != null)
          'recordPolicyTarget': recordPolicyTarget,
      };
      await context.database.transaction(() async {
        await context.database.execute(
          'INSERT INTO crypto_document_jobs VALUES(?,?,?,?,?,?,?,?,?)',
          [
            p,
            scopeId,
            id,
            recordId,
            operationId,
            kind,
            jsonEncode(descriptor),
            'staged',
            sourceHash,
          ],
        );
        for (var offset = 0; offset < cipher.length; offset += chunkBytes) {
          await context.database
              .execute('INSERT INTO crypto_document_chunks VALUES(?,?,?,?)', [
                p,
                id,
                offset,
                Uint8List.sublistView(
                  cipher,
                  offset,
                  (offset + chunkBytes).clamp(0, cipher.length),
                ),
              ]);
        }
        await context.database.execute(
          'INSERT INTO crypto_document_cache VALUES(?,?,?,?) ON CONFLICT(partition,id) DO UPDATE SET descriptor_hash=excluded.descriptor_hash,bytes=excluded.bytes',
          [p, id, await CryptoInventoryJson.hash(descriptor), plaintext],
        );
      });
      return descriptor;
    } finally {
      raw.fillRange(0, raw.length, 0);
      key.dispose();
      write?.key.release();
      relocationKey?.dispose();
    }
  }

  Future<Map<String, dynamic>> _write(
    String action,
    String op,
    Map<String, dynamic> payload,
  ) async {
    final id = await context.queue.enqueueCommand(
      actionKey: action,
      operation: op,
      payload: payload,
    );
    for (var attempt = 0; ; attempt++) {
      try {
        await context.queue.resumeUnresolved(requestIds: {id});
        return await context.queue.commandResult(id);
      } on CollaborationException catch (error) {
        context.access.invalidateBlobDelivery();
        if (error.code != 'rate_limited' || attempt >= 6) rethrow;
        await Future<void>.delayed(
          Duration(seconds: (2 << attempt).clamp(2, 30)),
        );
        if (!context.account.directory.isCurrent()) {
          throw const CryptoAuthorityPending('crypto_identity_changed');
        }
      }
    }
  }

  Future<void> upload(Map<String, dynamic> d) async {
    validate(d);
    await context.access.currentHead(d['scopeId'], online: true);
    // Unknown requests retain their bytes across rotations; they are never
    // rebound to a fresh epoch. Exact applied receipts reconcile first.
    final common = <String, dynamic>{
      'scopeId': d['scopeId'],
      'id': d['id'],
      'domain': d['domain'],
      'epoch': d['epoch'],
      'accessRevision': d['accessRevision'],
      'membershipHeadHash': d['membershipHeadHash'],
      if (d['recordPolicyTarget'] != null)
        'recordPolicyTarget': d['recordPolicyTarget'],
    };
    final begin = await _write('blob:${d['id']}:begin', 'crypto2.blob.begin', {
      ...common,
      'size': d['cipherSize'],
      'sha256': d['cipherSha256'],
      'manifestBase64': d['manifestBase64'],
    });
    if (begin['id'] != d['id'] || begin['offset'] is! int) {
      throw const FormatException('crypto_blob_ack');
    }
    final rows = await context.database.rows(
      'SELECT offset,cipher FROM crypto_document_chunks WHERE partition=? AND id=? ORDER BY offset',
      [p, d['id']],
    );
    var size = 0;
    for (final row in rows) {
      final bytes = Uint8List.fromList((row['cipher'] as List).cast<int>());
      if (row['offset'] != size) {
        throw const FormatException('crypto_blob_stage');
      }
      // Reconcile every immutable command, including chunks whose ACK was lost.
      final ack = await _write('blob:${d['id']}:$size', 'crypto2.blob.chunk', {
        ...common,
        'offset': size,
        'dataBase64': base64Encode(bytes),
      });
      size += bytes.length;
      if (ack['id'] != d['id'] ||
          ack['offset'] is! int ||
          (ack['offset'] as int) < size) {
        throw const FormatException('crypto_blob_ack');
      }
    }
    if (size != d['cipherSize']) {
      throw const FormatException('crypto_blob_stage');
    }
    final complete = await _write(
      'blob:${d['id']}:complete',
      'crypto2.blob.complete',
      common,
    );
    if (complete['id'] != d['id'] ||
        complete['offset'] != size ||
        complete['complete'] != true) {
      throw const FormatException('crypto_blob_ack');
    }
    await context.database.execute(
      "UPDATE crypto_document_jobs SET state='complete' WHERE partition=? AND id=?",
      [p, d['id']],
    );
  }

  Future<void> abort(Map<String, dynamic> d) async {
    validate(d);
    final response =
        await _write('blob:${d['id']}:abort', 'crypto2.blob.abort', {
          'scopeId': d['scopeId'],
          'id': d['id'],
          'domain': d['domain'],
          'epoch': d['epoch'],
          'accessRevision': d['accessRevision'],
          'membershipHeadHash': d['membershipHeadHash'],
          'sha256': d['cipherSha256'],
        });
    if (response['id'] != d['id'] ||
        response['state'] != 'aborted' ||
        response['sha256'] != d['cipherSha256']) {
      throw const FormatException('crypto_blob_abort_receipt');
    }
    await context.database.execute(
      "UPDATE crypto_document_jobs SET state='aborted' WHERE partition=? AND id=?",
      [p, d['id']],
    );
  }

  void validate(Map d) {
    if (d.length != 10 + (d.containsKey('recordPolicyTarget') ? 1 : 0) ||
        d['version'] != 2 ||
        !isCryptoCanonicalUuid(d['id']) ||
        !isCryptoCanonicalUuid(d['scopeId']) ||
        d['accessRevision'] is! int ||
        d['accessRevision'] < 0 ||
        !['content', 'finance'].contains(d['domain']) ||
        d['epoch'] is! int ||
        d['epoch'] < 1 ||
        d['cipherSize'] is! int ||
        d['cipherSize'] < 41 ||
        d['cipherSize'] > 23068672 ||
        d['cipherSha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(d['cipherSha256']) ||
        d['membershipHeadHash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(d['membershipHeadHash'])) {
      throw const FormatException('crypto_blob_descriptor');
    }
    if (d.containsKey('recordPolicyTarget')) {
      if (d['domain'] != 'content' || d['recordPolicyTarget'] is! Map)
        throw const FormatException('crypto_record_policy_blob_target');
      CryptoRecordBlobTarget.validate(
        Map<String, dynamic>.from(d['recordPolicyTarget'] as Map),
      );
    }
    cryptoBase64(d['manifestBase64'], max: 16384);
  }

  Future<Uint8List> open(Map<String, dynamic> d, {bool online = true}) async {
    validate(d);
    final authorized = await context.access.currentHead(d['scopeId']);
    final member = authorized.member(context.account.directory.accountId);
    if (d['domain'] == 'finance' && member['financeRole'] == 'none') {
      throw const CryptoAuthorityPending('scope_read_forbidden');
    }
    final knownSource = await context.access.headAt(
      d['scopeId'],
      d['membershipHeadHash'],
    );
    if (knownSource.epoch != d['epoch']) {
      throw const FormatException('crypto_blob_source');
    }
    final hash = await CryptoInventoryJson.hash(d);
    final cached = await context.database.rows(
      'SELECT descriptor_hash,bytes FROM crypto_document_cache WHERE partition=? AND id=?',
      [p, d['id']],
    );
    if (cached.length == 1 && cached.single['descriptor_hash'] == hash) {
      return Uint8List.fromList((cached.single['bytes'] as List).cast<int>());
    }
    if (!online) {
      throw const CryptoAuthorityPending('crypto_document_offline_missing');
    }
    final current = await context.access.currentHead(
          d['scopeId'],
          online: true,
        ),
        source = await context.access.headAt(
          d['scopeId'],
          d['membershipHeadHash'],
        );
    Map<String, dynamic>? migrationFacts, migrationBegin;
    final builder = BytesBuilder(copy: false);
    while (builder.length < d['cipherSize']) {
      final page = await context.account.directory.call('crypto2.blob.get', {
        'scopeId': d['scopeId'],
        'id': d['id'],
        'domain': d['domain'],
        'accessRevision': current.accessRevision,
        'offset': builder.length,
      });
      if (page['scopeId'] != d['scopeId'] ||
          page['id'] != d['id'] ||
          page['domain'] != d['domain'] ||
          page['membershipHeadHash'] != d['membershipHeadHash'] ||
          page['epoch'] != d['epoch'] ||
          page['size'] != d['cipherSize'] ||
          page['sha256'] != d['cipherSha256'] ||
          page['manifestBase64'] != d['manifestBase64'] ||
          page['offset'] != builder.length) {
        throw const FormatException('crypto_blob_substitution');
      }
      final proof = Map<String, dynamic>.from(page['authorization'] as Map),
          raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      if (raw['operation'] == 'crypto2.migration.blob.begin') {
        if (migrationBegin == null) {
          migrationFacts = await _migrationBlob(d, proof);
          migrationBegin = proof;
        } else if (CryptoInventoryJson.canonical(migrationBegin) !=
            CryptoInventoryJson.canonical(proof)) {
          throw const FormatException('crypto_blob_begin_proof');
        }
      } else {
        final member = source.member(raw['accountId']);
        if ((member['role'] == 'viewer' && d['recordPolicyTarget'] == null) ||
            d['domain'] == 'finance' && member['financeRole'] != 'write') {
          throw const FormatException('crypto_blob_author');
        }
        final author = await context.access.directoryAt(
          scopeId: d['scopeId'],
          scopeHeadHash: source.headHash,
          accountId: raw['accountId'],
          directoryHeadHash: member['directoryHeadHash'],
        );
        final device = author.activeDevice(raw['deviceId']),
            command = crypto.verifyDomain(
              proof,
              cryptoBase64(device['signingKeyBase64'], length: 32),
              cryptoDirectoryDomain,
            ),
            payload = command['payload'] as Map;
        if (command.length != 8 ||
            !isCryptoCanonicalUuid(command['requestId']) ||
            command['version'] != 2 ||
            command['operation'] != 'crypto2.blob.begin' ||
            command['signer'] != 'device' ||
            command['serverId'] != author.serverId ||
            payload.length !=
                9 + (d.containsKey('recordPolicyTarget') ? 1 : 0) ||
            CryptoInventoryJson.canonical(payload['recordPolicyTarget']) !=
                CryptoInventoryJson.canonical(d['recordPolicyTarget']) ||
            payload['scopeId'] != d['scopeId'] ||
            payload['id'] != d['id'] ||
            payload['domain'] != d['domain'] ||
            payload['epoch'] != d['epoch'] ||
            payload['membershipHeadHash'] != d['membershipHeadHash'] ||
            payload['accessRevision'] != source.accessRevision ||
            payload['size'] != d['cipherSize'] ||
            payload['sha256'] != d['cipherSha256'] ||
            payload['manifestBase64'] != d['manifestBase64']) {
          throw const FormatException('crypto_blob_begin_proof');
        }
      }
      final chunk = cryptoBase64(page['dataBase64'], max: chunkBytes);
      if (chunk.isEmpty ||
          builder.length + chunk.length > d['cipherSize'] ||
          (builder.length + chunk.length < d['cipherSize'] &&
              chunk.length != chunkBytes) ||
          page['done'] != (builder.length + chunk.length == d['cipherSize'])) {
        throw const FormatException('crypto_blob_chunk');
      }
      builder.add(chunk);
    }
    final cipher = builder.takeBytes();
    if (await cryptoSha256(cipher) != d['cipherSha256']) {
      throw const FormatException('crypto_blob_cipher_hash');
    }
    final dek = await context.access.getScopeKey(
      d['scopeId'],
      d['domain'],
      d['epoch'],
    );
    try {
      final result = await decryptCryptoDocumentCipher(
        context.account.directory.reducer.crypto,
        d,
        dek.key,
        cipher,
        serverId: context.account.directory.session.profile.serverId,
      );
      if (migrationFacts != null &&
          (result.length != migrationFacts['plainSize'] ||
              await cryptoSha256(result) != migrationFacts['plainSha256'])) {
        result.fillRange(0, result.length, 0);
        throw const FormatException('crypto_migration_file_source_mismatch');
      }
      await context.database.execute(
        'INSERT INTO crypto_document_cache VALUES(?,?,?,?) ON CONFLICT(partition,id) DO UPDATE SET descriptor_hash=excluded.descriptor_hash,bytes=excluded.bytes',
        [p, d['id'], hash, result],
      );
      return result;
    } finally {
      dek.release();
    }
  }

  /// Exact finalized source provenance for a migrated physical attachment.
  /// Local proof rows are discovery candidates only, reverified through the
  /// signed tag/certificate/witness path before granting the READ exception.
  Future<Map<String, dynamic>> _migrationBlob(
    Map<String, dynamic> descriptor,
    Map<String, dynamic> proof, {
    bool hydrated = false,
  }) async {
    final begin = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    final payload = Map<String, dynamic>.from(begin['payload'] as Map);
    final fields = {
      'captureVersion',
      'migrationId',
      'captureId',
      'sourceInventoryRoot',
      'bindingId',
      'scopeId',
      'domain',
      'epoch',
      'membershipHeadHash',
      'accessRevision',
      'id',
      'purpose',
      'size',
      'sha256',
      'manifestBase64',
    };
    if (payload.length != fields.length ||
        !payload.keys.every(fields.contains) ||
        payload['captureVersion'] != 3 ||
        !const {'canonicalPayload', 'ideaAsset'}.contains(payload['purpose']) ||
        begin.length != 8 ||
        begin['version'] != 2 ||
        begin['signer'] != 'device' ||
        begin['serverId'] !=
            context.account.directory.session.profile.serverId ||
        ![
          'scopeId',
          'domain',
          'epoch',
          'membershipHeadHash',
          'accessRevision',
          'id',
          'manifestBase64',
        ].every((k) => payload[k] == descriptor[k]) ||
        payload['size'] != descriptor['cipherSize'] ||
        payload['sha256'] != descriptor['cipherSha256']) {
      throw const FormatException('crypto_blob_migration_begin');
    }
    for (final table in ['crypto_received', 'crypto_business_history_proofs']) {
      var cursor = 0;
      while (true) {
        final rows = await context.database.rows(
          'SELECT rowid AS local_row,wire FROM $table WHERE partition=? AND scope_id=? AND domain=? AND revision=1 AND rowid>? ORDER BY rowid LIMIT 20',
          [p, descriptor['scopeId'], descriptor['domain'], cursor],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          cursor = row['local_row'] as int;
          final wire = Map<String, dynamic>.from(
            jsonDecode(row['wire'] as String) as Map,
          );
          final authorization = wire['authorization'];
          if (authorization is! Map || authorization['recordProof'] is! Map) {
            continue;
          }
          final recordProof = Map<String, dynamic>.from(
            authorization['recordProof'] as Map,
          );
          final record = Map<String, dynamic>.from(
            CryptoJson.decode(cryptoBase64(recordProof['commandBase64']))
                as Map,
          );
          final tag = (record['metadata'] as Map?)?['migrationOrigin'];
          if (tag is! Map ||
              payload['purpose'] == 'canonicalPayload' &&
                  tag['bindingId'] != payload['bindingId'] ||
              !(record['metadata']['blobIds'] as List).contains(
                descriptor['id'],
              )) {
            continue;
          }
          final authority = await context.access.recordAuthority(record);
          final origin = authority.migrationOrigin,
              witness = authority.migrationWitness;
          if (origin == null ||
              witness == null ||
              authority.closedRecordProofHash !=
                  await context.codec.digest(recordProof) ||
              begin['accountId'] != record['accountId'] ||
              begin['deviceId'] != record['deviceId'] ||
              ![
                'migrationId',
                'captureId',
                if (payload['purpose'] == 'canonicalPayload') 'bindingId',
                'sourceInventoryRoot',
              ].every((k) => tag[k] == payload[k])) {
            throw const FormatException('crypto_blob_migration_source');
          }
          final objects = origin['objects'];
          if (objects is! List || objects.length > 20) {
            throw const FormatException('crypto_blob_migration_object');
          }
          final matching = objects
              .where(
                (o) =>
                    o is Map &&
                    o['sourceBindingId'] == payload['bindingId'] &&
                    o['kind'] ==
                        (payload['purpose'] == 'ideaAsset'
                            ? 'ideaAsset'
                            : 'attachment') &&
                    CryptoInventoryJson.canonical(o['blob']) ==
                        CryptoInventoryJson.canonical(descriptor),
              )
              .toList();
          if (matching.length != 1) {
            throw const FormatException('crypto_blob_migration_object');
          }
          crypto.verifyDomain(
            proof,
            authority.signingKey,
            cryptoDirectoryDomain,
          );
          final source = await CryptoMigrationRecordSource.decode(
            table: origin['sourceTable'],
            domain: descriptor['domain'],
            row: Map<String, dynamic>.from(witness['typedRow'] as Map),
            serverId: begin['serverId'],
            reservedId: context.reservedRecordId,
          );
          if (payload['purpose'] == 'ideaAsset') {
            if (source.type != 'idea' ||
                source.deleted ||
                source.rawPayload == null) {
              throw const FormatException('crypto_blob_migration_source');
            }
            final hashes = cryptoMigrationIdeaAssets(
              source.rawPayload!,
            ).keys.toList()..sort();
            if (hashes.length != objects.length) {
              throw const FormatException('crypto_blob_migration_object');
            }
            final position = objects.indexOf(matching.single);
            final asset = cryptoMigrationIdeaAssets(
              source.rawPayload!,
            )[hashes[position]]!;
            return {'plainSize': asset.size, 'plainSha256': asset.sha256};
          }
          if (source.type != 'attachment' ||
              source.deleted ||
              source.rawPayload == null) {
            throw const FormatException('crypto_blob_migration_source');
          }
          return {
            'plainSize': source.rawPayload!['size'],
            'plainSha256': source.rawPayload!['sha256'],
          };
        }
      }
    }
    if (!hydrated) {
      await _retainMigrationBlobGenesis(descriptor);
      return _migrationBlob(descriptor, proof, hydrated: true);
    }
    throw const CryptoAuthorityPending(
      'crypto_migration_blob_provenance_pending',
    );
  }

  /// A later ordinary metadata edit may still reference the original object.
  /// Rewalk its independently authenticated current chain; retained ancestors
  /// are evidence only and never replace the current business projection.
  Future<void> _retainMigrationBlobGenesis(Map<String, dynamic> d) async {
    var cursor = 0, budget = 32;
    while (true) {
      final roots = await context.database.rows(
        'SELECT r.rowid AS local_row,r.wire FROM crypto_received r WHERE r.partition=? '
        'AND r.scope_id=? AND r.domain=? AND r.revision>1 AND r.rowid>? '
        'AND NOT EXISTS(SELECT 1 FROM crypto_received n WHERE n.partition=r.partition '
        'AND n.scope_id=r.scope_id AND n.domain=r.domain AND n.record_id=r.record_id '
        'AND n.revision>r.revision) ORDER BY r.rowid LIMIT 20',
        [p, d['scopeId'], d['domain'], cursor],
      );
      if (roots.isEmpty) return;
      for (final row in roots) {
        cursor = row['local_row'] as int;
        final root = Map<String, dynamic>.from(
          jsonDecode(row['wire'] as String),
        );
        final rootProof = Map<String, dynamic>.from(
          root['authorization']['recordProof'],
        );
        final body = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(rootProof['commandBase64'])) as Map,
        );
        if (!(body['metadata']['blobIds'] as List).contains(d['id'])) continue;
        final chain = await context.access.openHistoryChain(root);
        final evidence = {
          'scopeId': d['scopeId'],
          'id': body['id'],
          'revision': root['revision'],
          'recordProofHash': await context.codec.digest(rootProof),
        };
        while (chain.nextRevision > 0) {
          final revision = chain.nextRevision, hash = chain.nextHash;
          final cached = await context.database.rows(
            'SELECT wire FROM crypto_business_history_proofs WHERE partition=? '
            'AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?',
            [p, d['scopeId'], d['domain'], body['id'], revision, hash],
          );
          Map<String, dynamic> wire;
          if (cached.length == 1) {
            wire = Map<String, dynamic>.from(
              jsonDecode(cached.single['wire'] as String),
            );
          } else {
            if (cached.isNotEmpty) {
              throw const FormatException('crypto_blob_history_ambiguous');
            }
            if (budget-- <= 0) {
              throw const CryptoAuthorityPending(
                'crypto_migration_blob_history_pending',
              );
            }
            final head = await context.access.currentHead(d['scopeId']);
            final page = await context.account.directory
                .call('crypto2.records.historyGet', {
                  'scopeId': d['scopeId'],
                  'domain': d['domain'],
                  'accessRevision': head.accessRevision,
                  'id': body['id'],
                  'revision': revision,
                  'recordProofHash': hash,
                  'evidenceFor': evidence,
                });
            wire = Map<String, dynamic>.from(page['record'] as Map);
          }
          final authority = await chain.authority(wire);
          if (!context.account.directory.isCurrent()) {
            throw const CryptoAuthorityPending('crypto_identity_changed');
          }
          await context.database.execute(
            'INSERT OR IGNORE INTO crypto_business_history_proofs VALUES(?,?,?,?,?,?,?,?)',
            [
              p,
              d['scopeId'],
              d['domain'],
              body['id'],
              revision,
              hash,
              jsonEncode(wire),
              authority.historyBasis ?? 'currentEpoch',
            ],
          );
        }
      }
    }
  }
}

/// Pure recovery of an authenticated local ciphertext copy. It grants no
/// current membership, write permission or transport acknowledgement.
Future<Uint8List> decryptCryptoDocumentCipher(
  CryptoCodec crypto,
  Map<String, dynamic> d,
  SecureKey dek,
  Uint8List cipher, {
  required String serverId,
}) async {
  if (cipher.length != d['cipherSize'] ||
      await cryptoSha256(cipher) != d['cipherSha256']) {
    throw const FormatException('crypto_blob_cipher_hash');
  }
  SecureKey? key;
  Uint8List? manifestBytes;
  try {
    manifestBytes = crypto.decrypt(
      envelope: Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(d['manifestBase64'])) as Map,
      ),
      key: dek,
      context: {
        'version': 2,
        'purpose': 'documentObject',
        'serverId': serverId,
        'scopeId': d['scopeId'],
        'id': d['id'],
        'domain': d['domain'],
        'epoch': d['epoch'],
        'membershipHeadHash': d['membershipHeadHash'],
      },
    );
    final manifest = CryptoJson.decode(manifestBytes) as Map;
    if (manifest.length != 5 ||
        manifest['version'] != 2 ||
        manifest['plainSize'] is! int ||
        manifest['plainSize'] < 0 ||
        manifest['plainSize'] > CryptoDocumentBlob.maxPlainBytes ||
        manifest['streamChunkBytes'] != CryptoDocumentBlob.streamChunkBytes) {
      throw const FormatException('crypto_blob_manifest');
    }
    final raw = cryptoBase64(manifest['objectKeyBase64'], length: 32);
    try {
      key = crypto.sodium.secureCopy(raw);
    } finally {
      raw.fillRange(0, raw.length, 0);
    }
    final plain = BytesBuilder(copy: false);
    await for (final chunk in crypto.sodium.crypto.secretStream.pullChunked(
      cipherStream: Stream<List<int>>.value(cipher),
      key: key,
      chunkSize: CryptoDocumentBlob.streamChunkBytes,
    )) {
      if (plain.length + chunk.length >
          manifest['plainSize'] + utf8.encode('JivieObject/v2\n').length) {
        throw const FormatException('crypto_blob_plain_size');
      }
      plain.add(chunk);
    }
    final framed = plain.takeBytes(), prefix = utf8.encode('JivieObject/v2\n');
    if (framed.length < prefix.length ||
        base64Encode(framed.sublist(0, prefix.length)) !=
            base64Encode(prefix)) {
      framed.fillRange(0, framed.length, 0);
      throw const FormatException('crypto_blob_frame');
    }
    final result = Uint8List.fromList(framed.sublist(prefix.length));
    framed.fillRange(0, framed.length, 0);
    if (result.length != manifest['plainSize'] ||
        await cryptoSha256(result) != manifest['plainSha256']) {
      result.fillRange(0, result.length, 0);
      throw const FormatException('crypto_blob_plain_hash');
    }
    return result;
  } on SodiumException {
    throw const FormatException('crypto_blob_authentication');
  } on StreamClosedEarlyException {
    throw const FormatException('crypto_blob_incomplete');
  } on InvalidHeaderException {
    throw const FormatException('crypto_blob_header');
  } finally {
    manifestBytes?.fillRange(0, manifestBytes.length, 0);
    key?.dispose();
  }
}
