import 'dart:convert';
import 'dart:typed_data';
import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_record_proof_codec.dart';

/// Definitive rejection of an exact ordinary single-record batch. A pending,
/// missing or foreign receipt cannot authorize replacement of a signed intent.
Future<bool> isBoundOrdinaryRecordConflict({
  required CryptoRecordProofCodec codec,
  required Uint8List signingPublicKey,
  required String partition,
  required String serverId,
  required String accountId,
  required String deviceId,
  required String scopeId,
  required String recordId,
  required String recordType,
  required String operationId,
  required String localHash,
  required Map<String, dynamic> business,
  required Map<String, dynamic> outgoing,
  required List<Map<String, dynamic>> claims,
}) async {
  if (!const {
        'project',
        'event',
        'shoppingList',
        'shoppingItem',
        'householdPerson',
      }.contains(recordType) ||
      outgoing['state'] != 'rejected') {
    return false;
  }
  final receipt = jsonDecode(outgoing['response'] as String) as Map;
  if (receipt['status'] != 409 ||
      receipt['response'] is! Map ||
      receipt['response']['errorCode'] != 'conflict') {
    return false;
  }
  void require(bool valid) {
    if (!valid) throw const FormatException('crypto_record_conflict_binding');
  }

  require(
    business['scope_id'] == scopeId &&
        business['domain'] == 'content' &&
        business['record_id'] == recordId &&
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
        payload['records'].length == 1 &&
        claims.length == 1,
  );
  final record = codec.crypto.verifyDomain(
    Map<String, dynamic>.from((payload as Map)['records'].single as Map),
    signingPublicKey,
    'JivieE2EE/record/v2\n',
  );
  codec.validateUntrustedRecord(record);
  final address = CryptoRecordAddress.forType(
    serverId: serverId,
    scopeId: scopeId,
    domain: 'content',
    type: recordType,
    canonicalId: recordId,
  );
  require(
    record['serverId'] == serverId &&
        record['accountId'] == accountId &&
        record['deviceId'] == deviceId &&
        record['scopeId'] == scopeId &&
        record['domain'] == 'content' &&
        record['type'] == recordType &&
        record['operationId'] == operationId &&
        record['batchId'] == payload['batchId'] &&
        record['id'] == address.wireId &&
        base64Encode(CryptoJson.encode(record['metadata']['identity'])) ==
            base64Encode(CryptoJson.encode(address.identity)),
  );
  final claim = claims.single;
  require(
    claim['partition'] == partition &&
        claim['scope_id'] == scopeId &&
        claim['domain'] == 'content' &&
        claim['record_id'] == address.wireId &&
        claim['expected_revision'] == record['expectedRevision'] &&
        claim['request_id'] == outgoing['request_id'],
  );
  return true;
}
