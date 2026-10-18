import 'dart:convert';

import '../collaboration_database.dart';
import 'account_directory_v2.dart' show cryptoSha256;

/// Installation work bookkeeping only. This never supplies record authority,
/// current access, a projection, or a recoverable live queue after FILE restore.
class CryptoBusinessSettlement {
  static String _name(String partition, String requestId) =>
      'crypto_business_settled:$partition:$requestId';

  /// Call only after every exact signed batch leg passed normal projection or
  /// retained-ancestor verification. A bare delivery receipt is insufficient.
  static Future<void> record({
    required CollaborationDatabase database,
    required String partition,
    required String requestId,
  }) async {
    await database.transaction(() async {
      final rows = await database.rows(
        "SELECT request_hash,signed_body FROM crypto_outbox WHERE partition=? AND request_id=? AND operation='crypto2.records.batch' AND state='applied'",
        [partition, requestId],
      );
      if (rows.length != 1) {
        throw const FormatException('crypto_business_settlement_request');
      }
      final row = rows.single;
      final marker = {
        'version': 1,
        'requestId': requestId,
        'requestHash': row['request_hash'],
        'signedBodyHash': await cryptoSha256(
          utf8.encode(row['signed_body'] as String),
        ),
      };
      await database.execute(
        'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
        [_name(partition, requestId), jsonEncode(marker)],
      );
    });
  }

  static Future<bool> contains({
    required CollaborationDatabase database,
    required String partition,
    required String requestId,
  }) async {
    final rows = await database.rows(
      "SELECT o.request_hash,o.signed_body,m.value FROM crypto_outbox o JOIN local_meta m ON m.name=? WHERE o.partition=? AND o.request_id=? AND o.operation='crypto2.records.batch' AND o.state='applied'",
      [_name(partition, requestId), partition, requestId],
    );
    if (rows.length != 1) return false;
    final row = rows.single;
    final marker = jsonDecode(row['value'] as String);
    return marker is Map &&
        marker.length == 4 &&
        marker['version'] == 1 &&
        marker['requestId'] == requestId &&
        marker['requestHash'] == row['request_hash'] &&
        marker['signedBodyHash'] ==
            await cryptoSha256(utf8.encode(row['signed_body'] as String));
  }
}
