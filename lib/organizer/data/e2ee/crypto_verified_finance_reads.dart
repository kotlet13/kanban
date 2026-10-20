import '../collaboration_database.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';

/// Exact materialized result of a successful, complete, attested financial
/// pull. The guard is an opaque verified-authority lease, never a SQL flag.
class CryptoVerifiedFinanceSnapshot {
  const CryptoVerifiedFinanceSnapshot({
    required this.scopeId,
    required this.read,
    required this.stateDigest,
    required this.isCurrent,
  });
  final String scopeId, stateDigest;
  final CryptoReadContext read;
  final Future<bool> Function() isCurrent;
}

/// Lives only inside one locally initiated combined finance read. Consumers
/// still validate their own manifests, references and completeness. Only the
/// repeated attested finance pull can be omitted, for an exact unchanged view.
class CryptoVerifiedFinanceReads {
  final _snapshots = <String, _FinanceReadResult>{};
  bool _active = true;
  int _generation = 0;

  void invalidate() {
    _generation++;
    _snapshots.clear();
  }

  void close() {
    _active = false;
    invalidate();
  }

  Future<void> read(
    String scope, {
    required Future<void> Function() pull,
    required Future<CryptoVerifiedFinanceSnapshot?> Function() capture,
  }) async {
    final previous = _snapshots.remove(scope);
    final generation = _generation;
    try {
      if (_active &&
          previous != null &&
          previous.fresh &&
          await previous.snapshot.isCurrent()) {
        if (_active && generation == _generation && previous.fresh) {
          _snapshots[scope] = previous;
          return;
        }
      }
      final watch = Stopwatch()..start();
      await pull();
      // Mutations inside pull are allowed; only its final verified state can
      // seed the next consumer. An invalidation racing capture cannot do so.
      final afterPull = _generation;
      if (!_active) return;
      final snapshot = await capture();
      if (_active &&
          afterPull == _generation &&
          snapshot != null &&
          snapshot.scopeId == scope &&
          await snapshot.isCurrent() &&
          _active &&
          afterPull == _generation &&
          watch.elapsed < const Duration(seconds: 5)) {
        _snapshots[scope] = _FinanceReadResult(snapshot, watch);
      }
    } catch (_) {
      invalidate();
      rethrow;
    }
  }
}

class _FinanceReadResult {
  const _FinanceReadResult(this.snapshot, this.watch);
  final CryptoVerifiedFinanceSnapshot snapshot;
  final Stopwatch watch;
  bool get fresh => watch.elapsed < const Duration(seconds: 5);
}

/// Bounded local equality evidence only. SQL state never grants read authority.
class CryptoFinanceReadState {
  const CryptoFinanceReadState(this.db, this.p);
  final CollaborationDatabase db;
  final String p;

  Future<String?> capture(String scope) => db.transaction(() async {
    final budget = (await db.rows(
      '''SELECT COUNT(*) AS n,COALESCE(SUM(bytes),0) AS bytes FROM (
      SELECT length(CAST(COALESCE(raw_payload,'') AS BLOB))+length(CAST(projection AS BLOB))+256 AS bytes
      FROM crypto_business_records WHERE partition=? AND scope_id=? LIMIT 129)''',
      [p, scope],
    )).single;
    if ((budget['n'] as int) > 128 || (budget['bytes'] as int) > 262144) {
      return null;
    }
    final state = await db.rows(
      'SELECT * FROM crypto_scope_state WHERE partition=? AND scope_id=? ORDER BY domain',
      [p, scope],
    );
    final finance = state.where((r) => r['domain'] == 'finance').firstOrNull;
    if (finance == null ||
        finance['complete'] != 1 ||
        (finance['projection_cursor'] as int) <
            (finance['transport_cursor'] as int)) {
      return null;
    }
    final records = await db.rows(
      'SELECT * FROM crypto_business_records WHERE partition=? AND scope_id=? ORDER BY domain,id LIMIT 129',
      [p, scope],
    );
    final received = await db.rows(
      'SELECT domain,record_id,revision,sequence,verdict,error,superseded_by_revision,history_basis,batch_key,last_attempt FROM crypto_received WHERE partition=? AND scope_id=? ORDER BY domain,record_id,revision LIMIT 129',
      [p, scope],
    );
    final checkpoints = await db.rows(
      'SELECT domain,head_hash,epoch,access_revision,sequence,manifest_hash,record_count,history_basis,snapshot_id FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? ORDER BY domain,head_hash,sequence LIMIT 9',
      [p, scope],
    );
    if (records.length > 128 ||
        received.length > 128 ||
        checkpoints.length > 8) {
      return null;
    }
    final generation = await db.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['finance_access_generation:$p:$scope'],
    );
    final encoded = CryptoJson.encode({
      'state': state,
      'records': records,
      'received': received,
      'checkpoints': checkpoints,
      'generation': generation,
    });
    if (encoded.length > 262144) return null;
    return cryptoSha256(encoded);
  });
}
