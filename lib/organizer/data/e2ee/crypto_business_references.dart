import 'dart:convert';

import 'crypto_business_router.dart';
import 'crypto_business_payload.dart';
import '../../domain/collaboration_models.dart' show CollaborationException;
import 'crypto_sync_repository.dart';

/// Resolves semantic dependencies at their signed historical version. The
/// current projection remains independently authoritative for new-write CAS.
class CryptoBusinessReferences {
  CryptoBusinessReferences(this.context);
  final CryptoBusinessSession context;

  Future<Map<String, Object?>> resolve(
    Map<String, dynamic> source,
    String scope,
    String domain,
    String id,
  ) async {
    final metadata = source['metadata'] as Map;
    final versions = metadata['referenceVersions'];
    if (versions is! List) throw const CryptoProjectionPending();
    final matches = versions.cast<Map>().where(
      (ref) =>
          ref['scopeId'] == scope && ref['domain'] == domain && ref['id'] == id,
    );
    if (matches.length != 1) throw const CryptoProjectionPending();
    final ref = matches.single;
    final current = await context.wireRecord(scope, domain, id);
    if (current != null &&
        current['crypto_revision'] == ref['revision'] &&
        current['record_proof_hash'] == ref['recordProofHash']) {
      return current;
    }
    final rows = await context.database.rows(
      'SELECT h.raw_payload,h.record_body FROM crypto_business_history_payloads h JOIN crypto_business_history_jobs j ON j.partition=h.partition AND j.scope_id=h.scope_id AND j.domain=h.domain AND j.record_id=h.record_id AND j.target_revision=h.revision AND j.target_hash=h.proof_hash AND j.complete=1 WHERE h.partition=? AND h.scope_id=? AND h.domain=? AND h.record_id=? AND h.revision=? AND h.proof_hash=?',
      [
        context.partition,
        scope,
        domain,
        id,
        ref['revision'],
        ref['recordProofHash'],
      ],
    );
    if (rows.length != 1) throw const CryptoProjectionPending();
    final row = rows.single;
    final body = jsonDecode(row['record_body'] as String) as Map;
    if (row['raw_payload'] != null) {
      final raw = Map<String, dynamic>.from(
        jsonDecode(row['raw_payload'] as String) as Map,
      );
      try {
        if (body['type'] == 'taskDerivationIntent') {
          if (raw['version'] != 1 ||
              raw['taskId'] is! String ||
              raw['targetCryptoRevision'] is! int ||
              raw['completed'] is! bool ||
              raw['deleted'] is! bool) {
            throw const FormatException('crypto_reference_payload');
          }
        } else if (context.validateRaw?.call(domain, body['type'], raw) ==
            null) {
          CryptoBusinessPayload.projection(
            domain,
            body['type'],
            raw,
            personal:
                body['type'] == 'personalFinanceAccount' ||
                body['type'] == 'personalFinanceEntry',
          );
        }
      } on CollaborationException {
        throw const FormatException('crypto_reference_payload');
      }
    }
    return {
      'id': id,
      'scope_id': scope,
      'domain': domain,
      'type': body['type'],
      'deleted': body['deleted'] == true ? 1 : 0,
      'raw_payload': row['raw_payload'],
      'crypto_revision': ref['revision'],
      'record_proof_hash': ref['recordProofHash'],
    };
  }
}
