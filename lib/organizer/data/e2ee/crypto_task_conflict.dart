import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_record_proof_codec.dart';

/// A rejected atomic task write is a conflict of the retained draft, even when
/// its reserved derivation sibling caused the CAS rejection. This grants no
/// read/write access and deliberately never returns the server's raw remote.
Future<bool> isBoundOrdinaryTaskConflict({
  required CryptoRecordProofCodec codec,
  required Uint8List signingPublicKey,
  required String partition,
  required String serverId,
  required String accountId,
  required String deviceId,
  required String scopeId,
  required String taskId,
  required String operationId,
  required String localHash,
  required Map<String, dynamic> business,
  required Map<String, dynamic> outgoing,
  required List<Map<String, dynamic>> claims,
}) async {
  if (outgoing['state'] != 'rejected') return false;
  final receipt = jsonDecode(outgoing['response'] as String) as Map;
  if (receipt['status'] != 409 ||
      receipt['response'] is! Map ||
      receipt['response']['errorCode'] != 'conflict') {
    return false;
  }
  void require(bool condition) {
    if (!condition) throw const FormatException('crypto_task_conflict_binding');
  }

  require(
    business['scope_id'] == scopeId &&
        business['domain'] == 'content' &&
        business['record_id'] == taskId &&
        business['operation_id'] == operationId &&
        business['request_hash'] == localHash &&
        business['request_id'] == outgoing['request_id'] &&
        outgoing['operation'] == 'crypto2.records.batch',
  );
  final signed = Map<String, dynamic>.from(
    jsonDecode(outgoing['signed_body'] as String) as Map,
  );
  require(
    receipt['requestId'] == outgoing['request_id'] &&
        receipt['requestHash'] == outgoing['request_hash'] &&
        base64Encode(CryptoJson.encode(receipt['authorization'])) ==
            base64Encode(CryptoJson.encode(signed)) &&
        (!receipt.containsKey('outcome') || receipt['outcome'] == 'rejected') &&
        await cryptoSha256(cryptoBase64(signed['commandBase64'])) ==
            outgoing['request_hash'],
  );
  final command = codec.crypto.verifyDomain(
    signed,
    signingPublicKey,
    cryptoDirectoryDomain,
  );
  final payload = command['payload'];
  require(
    command['version'] == 2 &&
        command['operation'] == 'crypto2.records.batch' &&
        command['signer'] == 'device' &&
        command['serverId'] == serverId &&
        command['accountId'] == accountId &&
        command['deviceId'] == deviceId &&
        command['requestId'] == outgoing['request_id'] &&
        payload is Map &&
        payload['records'] is List &&
        payload['records'].length == 2 &&
        claims.length == 2,
  );
  final reservedHash = await cryptoSha256(
    utf8.encode(
      'JivieReservedRecord/v2\n$serverId:$scopeId:taskDerivation:$taskId',
    ),
  );
  final intentId =
      '${reservedHash.substring(0, 8)}-${reservedHash.substring(8, 12)}-4${reservedHash.substring(13, 16)}-a${reservedHash.substring(17, 20)}-${reservedHash.substring(20, 32)}';
  final records = <String, Map<String, dynamic>>{};
  for (final value in payload['records'] as List) {
    final record = codec.crypto.verifyDomain(
      Map<String, dynamic>.from(value as Map),
      signingPublicKey,
      'JivieE2EE/record/v2\n',
    );
    codec.validateUntrustedRecord(record);
    final type = record['type'];
    require(
      (type == 'task' || type == 'taskDerivationIntent') &&
          !records.containsKey(type),
    );
    final address = CryptoRecordAddress.forType(
      serverId: serverId,
      scopeId: scopeId,
      domain: 'content',
      type: type,
      canonicalId: type == 'task' ? taskId : intentId,
    );
    require(
      record['serverId'] == serverId &&
          record['accountId'] == accountId &&
          record['deviceId'] == deviceId &&
          record['scopeId'] == scopeId &&
          record['domain'] == 'content' &&
          record['operationId'] == operationId &&
          record['batchId'] == payload['batchId'] &&
          record['id'] == address.wireId &&
          base64Encode(CryptoJson.encode(record['metadata']['identity'])) ==
              base64Encode(CryptoJson.encode(address.identity)),
    );
    final matching = claims.where(
      (claim) =>
          claim['partition'] == partition &&
          claim['scope_id'] == scopeId &&
          claim['domain'] == 'content' &&
          claim['record_id'] == address.wireId &&
          claim['expected_revision'] == record['expectedRevision'] &&
          claim['request_id'] == outgoing['request_id'],
    );
    require(matching.length == 1);
    records[type] = record;
  }
  final task = records['task']!, intent = records['taskDerivationIntent']!;
  require(
    task['membershipHeadHash'] == intent['membershipHeadHash'] &&
        task['epoch'] == intent['epoch'] &&
        task['accessRevision'] == intent['accessRevision'] &&
        intent['deleted'] == false,
  );
  return true;
}
