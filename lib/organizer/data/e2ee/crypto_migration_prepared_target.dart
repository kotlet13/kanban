import 'dart:convert';

import 'crypto_business_router.dart';
import 'crypto_capture_v3.dart';
import 'crypto_json.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_migration_witness.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// Local preparation dependency only. It grants no current projection, consent,
/// historical timing or migration provenance. Cold parity rechecks the retained
/// outer stage/capture proof and the entire typed witness independently.
class CryptoPreparedMigrationTarget {
  CryptoPreparedMigrationTarget._(
    this.record,
    this.raw,
    this.proofHash,
    this.canonicalId,
    this.recordProof,
    this.sourceBinding,
  );
  final Map<String, dynamic> record, recordProof, sourceBinding;
  final Map<String, dynamic>? raw;
  final String proofHash, canonicalId;
}

Future<CryptoPreparedMigrationTarget> prepareCryptoMigrationTarget({
  required CryptoBusinessSession context,
  required String migrationId,
  required String scopeId,
  required String domain,
  required String wireId,
  String? expectedProofHash,
}) async {
  final rows = await context.db.rows(
    'SELECT * FROM crypto_migration_staged_records WHERE partition=? AND migration_id=? AND scope_id=? AND domain=? AND record_id=?',
    [context.partition, migrationId, scopeId, domain, wireId],
  );
  if (rows.length != 1) throw const CryptoProjectionPending();
  final row = rows.single;
  final proof = Map<String, dynamic>.from(
    jsonDecode(row['record_proof'] as String),
  );
  final body = Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  context.codec.validateUntrustedRecord(body);
  final hash = await context.codec.digest(proof);
  final address = cryptoRecordAddressFromMetadata(body);
  if (hash != row['record_proof_hash'] ||
      expectedProofHash != null && hash != expectedProofHash ||
      body['scopeId'] != scopeId ||
      body['domain'] != domain ||
      body['id'] != wireId ||
      body['expectedRevision'] != 0 ||
      body['previousRecordHash'] != '0' * 64) {
    throw const FormatException('crypto_migration_prepared_target');
  }
  final candidate = await context.access.migrationCandidate(
    scopeId: scopeId,
    migrationId: migrationId,
    // The caller's own selected capture grants preparation READ. A verified
    // foreign task proof retains its original capture tag unchanged.
    headHash: body['membershipHeadHash'],
  );
  final head = candidate.head;
  final member = head.member(body['accountId']);
  if (body['membershipHeadHash'] != head.headHash ||
      body['epoch'] != head.epoch ||
      body['accessRevision'] != head.accessRevision ||
      domain == 'finance' && member['financeRole'] == 'none') {
    throw const CryptoAuthorityPending('crypto_migration_authority_changed');
  }
  final author = await context.access.currentMemberDirectory(
    scopeId,
    head.headHash,
    body['accountId'],
  );
  if (author.deviceSnapshotHash != member['deviceSnapshotHash']) {
    throw const CryptoAuthorityPending('crypto_migration_authority_changed');
  }
  final record = await context.codec.verifyWire(
    serverId: context.account.directory.session.profile.serverId,
    wire: {
      ...body,
      'revision': 1,
      'sequence': 1,
      'authorization': {
        'recordProof': proof,
        'batchCommitment': jsonDecode(row['batch_commitment'] as String),
      },
    },
    trustedSigningKey: cryptoBase64(
      author.activeDevice(body['deviceId'])['signingKeyBase64'],
      length: 32,
    ),
    currentEpoch: true,
  );
  final binding = Map<String, dynamic>.from(
    jsonDecode(row['source_binding'] as String),
  );
  final key = await candidate.key(domain);
  try {
    final bytes = context.codec.openVerified(record, key.key);
    if (bytes == null) {
      if (body['deleted'] != true) {
        throw const FormatException('crypto_migration_prepared_target');
      }
      return CryptoPreparedMigrationTarget._(
        body,
        null,
        hash,
        address.canonicalId,
        proof,
        binding,
      );
    }
    try {
      final envelope = jsonDecode(utf8.decode(bytes));
      if (envelope is! Map ||
          envelope['format'] != 2 ||
          envelope['payload'] is! Map) {
        throw const FormatException('crypto_migration_prepared_target');
      }
      var raw = Map<String, dynamic>.from(envelope['payload'] as Map);
      if (raw.length == 2 && raw['migrationPayload'] == 3) {
        if (raw['bindingId'] != binding['bindingId'] ||
            binding['recordProofHash'] != hash ||
            binding['witness'] is! Map) {
          throw const FormatException('crypto_migration_prepared_target');
        }
        final descriptor = Map<String, dynamic>.from(binding['witness'] as Map);
        final c = CryptoMigrationWitnessContext(
          Map<String, dynamic>.from(descriptor['context'] as Map),
        );
        if (c.value['wireId'] != wireId ||
            c.value['membershipHeadHash'] != head.headHash ||
            c.value['type'] != body['type']) {
          throw const FormatException('crypto_migration_prepared_target');
        }
        final witness = await CryptoMigrationWitness(
          database: context.db,
          partition: context.partition,
          crypto: context.codec.crypto,
        ).open(context: c, descriptor: descriptor, domainKey: key.key);
        final sourceContext = CryptoCaptureSourceContext.fromJson(
          Map<String, dynamic>.from(witness['context'] as Map),
        );
        final source = await CryptoMigrationRecordSource.decode(
          table: sourceContext.sourceTable,
          domain: sourceContext.domain,
          row: Map<String, dynamic>.from(witness['typedRow'] as Map),
          serverId: body['serverId'],
          reservedId: context.reservedRecordId,
        );
        if (source.scopeId != scopeId ||
            source.type != body['type'] ||
            source.canonicalId != address.canonicalId ||
            source.deleted ||
            source.rawPayload == null) {
          throw const FormatException('crypto_migration_prepared_target');
        }
        raw = {
          ...source.rawPayload!,
          if (source.type == 'attachment' &&
              (binding['objects'] as List).length == 1)
            'cryptoBlob': binding['objects'][0]['blob'],
        };
      }
      return CryptoPreparedMigrationTarget._(
        body,
        raw,
        hash,
        address.canonicalId,
        proof,
        binding,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  } finally {
    key.release();
  }
}
