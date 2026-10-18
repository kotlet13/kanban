import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;

import '../collaboration_database.dart';

/// Candidates are retained public proofs, not active rights. Trust verification
/// must examine every candidate and merge only authenticated monotonic anchors.
class CryptoRestoreEvidenceSnapshot {
  const CryptoRestoreEvidenceSnapshot(
    this.partition,
    this.candidates,
    this.digest,
  );
  final String partition, digest;
  final List<Map<String, dynamic>> candidates;
}

class CryptoRestoreEvidenceStore {
  const CryptoRestoreEvidenceStore(this.database, this.partition);
  final CollaborationDatabase database;
  final String partition;

  Future<CryptoRestoreEvidenceSnapshot> snapshot() async {
    final rows = await database.rows(
      'SELECT backup_id,evidence FROM crypto_restore_evidence WHERE partition=? ORDER BY backup_id',
      [partition],
    );
    final bytes = utf8.encode(jsonEncode(rows));
    final digest = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return CryptoRestoreEvidenceSnapshot(
      partition,
      List.unmodifiable(
        rows.map(
          (r) => {
            'backupId': r['backup_id'],
            'evidence': jsonDecode(r['evidence'] as String),
          },
        ),
      ),
      digest,
    );
  }

  /// Caller verifies complete identity logs, scope heads/closures and receipts
  /// outside the transaction, using ALL snapshot candidates. The callback only
  /// merges those verified anchors in SQL; it must perform no network I/O.
  /// Importing another backup while verification waits invalidates this commit.
  Future<void> commitVerified(
    CryptoRestoreEvidenceSnapshot verified, {
    required Future<void> Function() mergeVerifiedAnchors,
    bool deferSecureAnchors = false,
  }) async {
    if (verified.partition != partition) {
      throw const FormatException('crypto_restore_identity');
    }
    await database.transaction(() async {
      final current = await snapshot();
      if (current.digest != verified.digest) {
        throw const FormatException('crypto_restore_evidence_changed');
      }
      await mergeVerifiedAnchors();
      await database.execute(
        'UPDATE crypto_restore_fences SET state=? WHERE partition=?',
        [
          deferSecureAnchors ? 'verified_pending_secure_anchors' : 'verified',
          partition,
        ],
      );
    });
  }
}
