import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_json.dart';
import 'crypto_migration_notification_codec.dart';
import 'crypto_sync_repository.dart';

/// Isolated, FILE-anchored evidence only. This helper never creates live trust,
/// signing keys, commands or a complete inventory from server row counts.
class CryptoMigrationColdEvidence {
  CryptoMigrationColdEvidence(this.runtime, this.archive);
  final CryptoBusinessSession runtime;
  final VerifiedCryptoCaptureArchive archive;
  Map<String, dynamic> get common => {
    'version': 3,
    'serverId': runtime.account.directory.session.profile.serverId,
    'migrationId': archive.capture.migrationId,
    'captureId': archive.capture.captureId,
    'accountId': runtime.account.directory.accountId,
    'sourceInventoryRoot': archive.sourceInventoryRoot,
  };

  static bool same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

  static Map<String, String?> cells(Map<String, dynamic> typed) {
    final values = <String, String?>{};
    for (final entry in typed.entries) {
      final cell = entry.value;
      if (cell is! Map ||
          cell.length != 2 ||
          cell['type'] is! String ||
          !cell.containsKey('valueBase64')) {
        throw const FormatException('crypto_control_source_cell');
      }
      final raw = cell['valueBase64'];
      values[entry.key] = raw == null ? null : utf8.decode(cryptoBase64(raw));
    }
    return values;
  }

  static int integer(Object? value) {
    if (value is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
      throw const FormatException('crypto_control_source_integer');
    }
    final n = int.tryParse(value);
    if (n == null || n > 9007199254740991) {
      throw const FormatException('crypto_control_source_integer');
    }
    return n;
  }

  static void compareColumns(
    Map canonical,
    Map<String, String?> source,
    Map<String, String> columns,
  ) {
    for (final entry in columns.entries) {
      final value = canonical[entry.key];
      final text = value is bool
          ? (value ? '1' : '0')
          : value is int
          ? '$value'
          : value;
      if (!source.containsKey(entry.value) || source[entry.value] != text) {
        throw const FormatException('crypto_control_source_changed');
      }
    }
  }

  VerifiedAccountDirectory? _own;
  final _prefixes = <String, VerifiedAccountDirectory>{};
  Future<VerifiedAccountDirectory> own() async {
    if (_own != null) return _own!;
    final pin = await runtime.account.store.anchor(
      runtime.account.directory.accountId,
    );
    if (pin?['fingerprint'] is! String) {
      throw const CryptoAuthorityPending('crypto_control_file_anchor_pending');
    }
    return _own = await runtime.account.directory.replayFileAnchoredCandidate(
      pin!['fingerprint'],
    );
  }

  Future<VerifiedAccountDirectory> ownAt(String hash) async {
    if (_prefixes[hash] != null) return _prefixes[hash]!;
    final current = await own();
    final pin = await runtime.account.store.anchor(current.accountId);
    VerifiedAccountDirectory? state;
    await for (final entry in runtime.account.store.streamEntries(
      current.accountId,
    )) {
      state = await runtime.account.directory.reducer.apply(
        previous: state,
        entry: entry,
        serverId: current.serverId,
        accountId: current.accountId,
        pinnedRootFingerprint: pin!['genesisFingerprint'] ?? pin['fingerprint'],
      );
      if (!current.includesAnchor(state.generation, state.headHash)) {
        throw const FormatException('crypto_control_directory_fork');
      }
      if (state.headHash == hash) return _prefixes[hash] = state;
    }
    throw const CryptoAuthorityPending('crypto_control_directory_pending');
  }

  Future<Map<String, dynamic>> verifyOwn(
    Map<String, dynamic> proof,
    String reference,
    String deviceId,
    String domain,
  ) async {
    final current = await own(), prefix = await ownAt(reference);
    if (prefix.deviceSnapshotHash != current.deviceSnapshotHash ||
        prefix.identityEpochId != current.identityEpochId) {
      throw const CryptoAuthorityPending('crypto_control_signer_changed');
    }
    final device = current.activeDevice(deviceId);
    return runtime.codec.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      domain,
    );
  }

  bool _indexed = false;
  Future<void> indexRecords() async {
    if (_indexed) return;
    await runtime.db.execute(
      'CREATE TABLE IF NOT EXISTS cold_control_records('
      'proof_hash TEXT PRIMARY KEY,scope_id TEXT,id TEXT,domain TEXT,type TEXT,body TEXT)',
    );
    String? after;
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT hash,authorization FROM cold_migration_stages WHERE verified=1'
        '${after == null ? '' : ' AND hash>?'} ORDER BY hash LIMIT 20',
        [if (after != null) after],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        after = row['hash'] as String;
        final outer = jsonDecode(row['authorization'] as String) as Map;
        final command =
            CryptoJson.decode(cryptoBase64(outer['commandBase64'])) as Map;
        for (final proof in command['payload']['batch']['records'] as List) {
          final b = Map<String, dynamic>.from(
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
          );
          final hash = await runtime.codec.digest(
            Map<String, dynamic>.from(proof as Map),
          );
          await runtime.db.execute(
            'INSERT OR IGNORE INTO cold_control_records VALUES(?,?,?,?,?,?)',
            [
              hash,
              b['scopeId'],
              b['id'],
              b['domain'],
              b['type'],
              jsonEncode(b),
            ],
          );
        }
      }
    }
    _indexed = true;
  }

  Future<Map<String, dynamic>> record(
    String scope,
    String wire,
    String hash,
  ) async {
    await indexRecords();
    CryptoMigrationNotificationCodec.digest(hash);
    final rows = await runtime.db.rows(
      'SELECT body FROM cold_control_records WHERE scope_id=? AND id=? AND proof_hash=?',
      [scope, wire, hash],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('crypto_control_target_pending');
    }
    final record = Map<String, dynamic>.from(
      jsonDecode(rows.single['body'] as String) as Map,
    );
    final projected = await runtime.wireRecord(scope, record['domain'], wire);
    if (projected == null ||
        projected['crypto_revision'] != record['expectedRevision'] + 1 ||
        projected['type'] != record['type']) {
      throw const CryptoAuthorityPending('crypto_control_projection_pending');
    }
    return record;
  }
}
