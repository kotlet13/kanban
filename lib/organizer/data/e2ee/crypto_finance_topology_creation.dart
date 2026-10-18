import 'dart:convert';

import 'crypto_business_json.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_business_router.dart';
import 'crypto_finance_topology_successor.dart';
import 'crypto_json.dart';

/// An immutable parent batch carried by the child's signed final activation.
/// It is never queued or delivered as a standalone business request.
abstract final class CryptoFinanceTopologyCreation {
  static Future<String> hash(Map<String, dynamic> bundle) => cryptoSha256([
    ...utf8.encode('JivieFinanceTopologyCreationBatch/v3\n'),
    ...CryptoJson.encode(bundle),
  ]);
  static Future<void> finish(
    CryptoBusinessSession runtime,
    Map<String, dynamic> bundle,
  ) async {
    final parent = bundle['parentScopeId'] as String,
        child = bundle['childScopeId'] as String;
    await runtime.access.currentHead(child, online: true);
    await runtime.pullVerified(parent, 'content');
    final command =
        CryptoJson.decode(
              cryptoBase64(bundle['authorization']['commandBase64']),
            )
            as Map;
    final proofs = command['payload']['records'] as List;
    if (proofs.length != 1) {
      throw const FormatException('crypto_topology_activation_context');
    }
    await runtime.requirePreparedRecordProof(
      Map<String, dynamic>.from(proofs.single),
    );
    await runtime.db.execute(
      "UPDATE crypto_membership_intents SET state='scopeTopologyCreationPublished' WHERE partition=? AND scope_id=? AND intent_id=? AND state IN ('scopeTopologyCreation','scopeTopologyCreationPublished')",
      [runtime.partition, parent, 'scopeTopologyCreation:$child'],
    );
  }

  static Future<Map<String, dynamic>> prepare({
    required CryptoBusinessSession runtime,
    required String parentScopeId,
    required String childScopeId,
  }) async {
    final intent = 'scopeTopologyCreation:$childScopeId';
    final saved = await runtime.db.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state IN ('scopeTopologyCreation','scopeTopologyCreationPublished')",
      [runtime.partition, parentScopeId, intent],
    );
    if (saved.isNotEmpty) {
      final value = saved.single['payload'];
      final bundle = Map<String, dynamic>.from(
        jsonDecode(
          value is String ? value : utf8.decode((value as List).cast<int>()),
        ),
      );
      if (bundle['parentScopeId'] != parentScopeId ||
          bundle['childScopeId'] != childScopeId) {
        throw const FormatException('crypto_topology_activation_context');
      }
      return bundle;
    }
    final successor = await CryptoFinanceTopologySuccessor.prepare(
      runtime: runtime,
      parentScopeId: parentScopeId,
      childScopeId: childScopeId,
      remove: false,
    );
    final previous = successor.previous;
    final canonicalId = await runtime.reservedRecordId(
      parentScopeId,
      'scopeMetadata',
    );
    final address = runtime.address(
      parentScopeId,
      'content',
      'scopeMetadata',
      canonicalId,
    );
    final write = await runtime.access.writeContext(
      parentScopeId,
      'content',
      online: true,
    );
    final signing = await runtime.account.signingKey();
    final crypto = runtime.account.directory.reducer.crypto;
    final batch = crypto.randomId(), operation = crypto.randomId();
    final plain = CryptoBusinessJson.encode({
      'format': 2,
      'identity': address.identity,
      'payload': successor.raw,
    });
    try {
      final proof = runtime.codec.sealRecord(
        serverId: runtime.account.directory.session.profile.serverId,
        accountId: runtime.account.directory.accountId,
        deviceId: runtime.account.deviceId,
        batchId: batch,
        scopeId: parentScopeId,
        id: address.wireId,
        type: 'scopeMetadata',
        expectedRevision: previous['crypto_revision'] as int,
        previousRecordHash: previous['record_proof_hash'] as String,
        epoch: write.epoch,
        accessRevision: write.accessRevision,
        membershipHeadHash: write.headHash,
        domain: 'content',
        contentContract: 6,
        operationId: operation,
        deleted: false,
        plaintext: plain,
        metadata: await runtime.businessMetadata(
          scopeId: parentScopeId,
          domain: 'content',
          type: 'scopeMetadata',
          canonicalId: canonicalId,
          expectedRevision: previous['crypto_revision'] as int,
          rawPayload: successor.raw,
        ),
        contentKey: write.key.key,
        signingKey: signing.key,
      );
      final commitment = await runtime.codec.commitBatch(
        serverId: runtime.account.directory.session.profile.serverId,
        accountId: runtime.account.directory.accountId,
        deviceId: runtime.account.deviceId,
        batchId: batch,
        records: [proof],
        signingKey: signing.key,
        projectionToken: (body) async =>
            runtime.codec.projectionGroupToken(body, write.key.key),
      );
      final signed = runtime.codec.signCommand({
        'version': 2,
        'operation': 'crypto2.records.batch',
        'requestId': crypto.randomId(),
        'serverId': runtime.account.directory.session.profile.serverId,
        'accountId': runtime.account.directory.accountId,
        'deviceId': runtime.account.deviceId,
        'signer': 'device',
        'payload': {
          'batchId': batch,
          'records': [proof],
          'commitment': commitment,
        },
      }, signing.key);
      final bundle = <String, dynamic>{
        'parentScopeId': parentScopeId,
        'childScopeId': childScopeId,
        'authorization': signed,
      };
      await runtime.db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          runtime.partition,
          parentScopeId,
          intent,
          'scopeTopologyCreation',
          CryptoJson.encode(bundle),
        ],
      );
      return bundle;
    } finally {
      plain.fillRange(0, plain.length, 0);
      signing.release();
      write.key.release();
    }
  }
}
