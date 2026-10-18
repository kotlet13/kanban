import 'dart:convert';
import 'dart:typed_data';

import '../collaboration_database.dart';
import 'account_crypto_store.dart';
import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_anchor_lock.dart';

/// The encrypted physical database holds growing journals and device material.
/// The secure store holds a small monotonic anchor, never an unbounded keyring.
class CryptoIdentityStore {
  CryptoIdentityStore(this.database, this.secure, this.partition);
  final CollaborationDatabase database;
  final AccountCryptoStore secure;
  final String partition;
  String _anchor(String account) => 'directory2:$partition:$account';
  Future<Map<String, dynamic>?> anchor(String account) async {
    final bytes = await secure.read(_anchor(account));
    if (bytes == null) return null;
    return CryptoJson.decode(Uint8List.fromList(utf8.encode(bytes)))
        as Map<String, dynamic>;
  }

  Future<void> remember(
    VerifiedAccountDirectory directory,
    String trustState, {
    String? handoffRequestId,
    String? handoffCommandHash,
  }) async {
    final s = directory.snapshot;
    late String effectiveTrust;
    await withCryptoAnchorLock(partition, () async {
      final old = await anchor(directory.accountId);
      if (old != null &&
          !directory.includesAnchor(
            old['generation'] as int,
            old['headHash'] as String,
          ))
        throw const CryptoDirectoryException('directory_anchor_fork');

      if (old != null &&
          ((old['generation'] as int) > directory.generation ||
              (old['generation'] == directory.generation &&
                  old['headHash'] != directory.headHash))) {
        throw const CryptoDirectoryException('directory_rollback');
      }
      final pending = old?['pendingRootTransition'];
      final completingHandoff = handoffRequestId != null;
      if (completingHandoff &&
          (pending is! Map ||
              pending['requestId'] != handoffRequestId ||
              pending['commandHash'] != handoffCommandHash ||
              pending['newFingerprint'] != directory.rootFingerprint)) {
        throw const CryptoDirectoryException('directory_handoff_conflict');
      }
      if (old != null &&
          old['fingerprint'] != null &&
          old['fingerprint'] != directory.rootFingerprint &&
          !completingHandoff) {
        throw const CryptoDirectoryException('directory_root_changed');
      }
      effectiveTrust = old?['trustState'] == 'verified'
          ? 'verified'
          : trustState;
      await secure.write(
        _anchor(directory.accountId),
        utf8.decode(
          CryptoJson.encode({
            'serverId': directory.serverId,
            'accountId': directory.accountId,
            'generation': directory.generation,
            'headHash': directory.headHash,
            'snapshotHash': directory.snapshotHash,
            'deviceSnapshotHash': directory.deviceSnapshotHash,
            'rootSigningKeyBase64': s['rootSigningKeyBase64'],
            'rootEncryptionKeyBase64': s['rootEncryptionKeyBase64'],
            'identityEpochId': directory.identityEpochId,
            'trustState': effectiveTrust,
            if (completingHandoff)
              'fingerprint': directory.rootFingerprint
            else if (old?['fingerprint'] != null)
              'fingerprint': old!['fingerprint'],
            if (!completingHandoff && old?['pendingRootTransition'] != null)
              'pendingRootTransition': old!['pendingRootTransition'],
            if (old?['genesisFingerprint'] != null)
              'genesisFingerprint': old!['genesisFingerprint'],
          }),
        ),
      );
    });
    await database.transaction(() async {
      await database.execute(
        'INSERT INTO crypto_directory_pins VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,account_id) DO UPDATE SET root_signing_public=excluded.root_signing_public,root_encryption_public=excluded.root_encryption_public,fingerprint=excluded.fingerprint,min_generation=excluded.min_generation,head_hash=excluded.head_hash,snapshot_hash=excluded.snapshot_hash,device_snapshot_hash=excluded.device_snapshot_hash,identity_epoch_id=excluded.identity_epoch_id,trust_state=excluded.trust_state WHERE excluded.min_generation>=crypto_directory_pins.min_generation',
        [
          partition,
          directory.serverId,
          directory.accountId,
          s['rootSigningKeyBase64'],
          s['rootEncryptionKeyBase64'],
          directory.rootFingerprint,
          directory.generation,
          directory.headHash,
          directory.snapshotHash,
          directory.deviceSnapshotHash,
          directory.identityEpochId,
          effectiveTrust,
        ],
      );
      // Only the latest complete state is cached; immutable commands keep history.
      final currentPin = (await database.rows(
        'SELECT head_hash FROM crypto_directory_pins WHERE partition=? AND account_id=?',
        [partition, directory.accountId],
      )).single;
      if (currentPin['head_hash'] != directory.headHash) return;
      await database.execute(
        'DELETE FROM crypto_directory_snapshots WHERE partition=? AND account_id=?',
        [partition, directory.accountId],
      );
      await database.execute(
        'INSERT INTO crypto_directory_snapshots VALUES(?,?,?,?,?,?,?)',
        [
          partition,
          directory.accountId,
          directory.headHash,
          directory.generation,
          directory.snapshotHash,
          directory.deviceSnapshotHash,
          CryptoJson.encodeDerivedState(s),
        ],
      );
    });
  }

  Future<void> pinRoot(
    String account,
    String server,
    String fingerprint, {
    String? genesisFingerprint,
  }) async {
    return withCryptoAnchorLock(partition, () async {
      final old = await anchor(account);
      if (old != null && old['fingerprint'] != fingerprint) {
        throw const CryptoDirectoryException('directory_root_changed');
      }
      if (old == null ||
          (old['generation'] == 0 && old['genesisFingerprint'] == null)) {
        await secure.write(
          _anchor(account),
          utf8.decode(
            CryptoJson.encode({
              'serverId': server,
              'accountId': account,
              'fingerprint': fingerprint,
              if (genesisFingerprint != null)
                'genesisFingerprint': genesisFingerprint,
              'generation': 0,
              'headHash': cryptoZeroHash,
              'trustState': 'freshnessPending',
            }),
          ),
        );
      }
    });
  }

  Future<Map<String, Object?>?> pin(
    String account,
  ) async => (await database.rows(
    'SELECT * FROM crypto_directory_pins WHERE partition=? AND account_id=?',
    [partition, account],
  )).firstOrNull;
  Future<List<Map<String, dynamic>>> entries(String account) async => [
    for (final row in await database.rows(
      'SELECT * FROM crypto_directory_entries WHERE partition=? AND account_id=? ORDER BY generation',
      [partition, account],
    ))
      {
        'generation': row['generation'],
        'headHash': row['head_hash'],
        'previousHeadHash': row['previous_head_hash'],
        'commandHash': row['command_hash'],
        'authorization': _decode(row['authorization']),
      },
  ];
  Stream<Map<String, dynamic>> streamEntries(
    String account, {
    String? runId,
  }) async* {
    var after = 0;
    while (true) {
      final rows = await database.rows(
        runId == null
            ? 'SELECT * FROM crypto_directory_entries WHERE partition=? AND account_id=? AND generation>? ORDER BY generation LIMIT 50'
            : 'SELECT * FROM crypto_directory_replay_staging WHERE partition=? AND run_id=? AND account_id=? AND generation>? ORDER BY generation LIMIT 50',
        runId == null
            ? [partition, account, after]
            : [partition, runId, account, after],
      );
      for (final row in rows) {
        yield {
          'generation': row['generation'],
          'headHash': row['head_hash'],
          'previousHeadHash': row['previous_head_hash'],
          'commandHash': row['command_hash'],
          'authorization': _decode(row['authorization']),
        };
      }
      if (rows.length < 50) return;
      after = rows.last['generation'] as int;
    }
  }

  Future<Map<String, dynamic>?> entryByHash(
    String account,
    String hash, {
    String? runId,
  }) async {
    final rows = await database.rows(
      runId == null
          ? 'SELECT * FROM crypto_directory_entries WHERE partition=? AND account_id=? AND command_hash=?'
          : 'SELECT * FROM crypto_directory_replay_staging WHERE partition=? AND run_id=? AND account_id=? AND command_hash=?',
      runId == null
          ? [partition, account, hash]
          : [partition, runId, account, hash],
    );
    if (rows.length > 1)
      throw const CryptoDirectoryException('directory_duplicate_command');
    if (rows.isEmpty) return null;
    final row = rows.single;
    return {
      'generation': row['generation'],
      'headHash': row['head_hash'],
      'previousHeadHash': row['previous_head_hash'],
      'commandHash': row['command_hash'],
      'authorization': _decode(row['authorization']),
    };
  }

  /// Newest first, from the immutable verified lineage. No mutable operation
  /// index or row count can hide a required signed event. Missing retained
  /// bytes remain pending instead of becoming an empty successful result.
  Stream<Map<String, dynamic>> verifiedOperationEntries(
    VerifiedAccountDirectory directory,
    String operation,
  ) async* {
    final headers = directory.verifiedHeadersFor(operation).iterator;
    var exhausted = false;
    while (!exhausted) {
      final page = <({int generation, String headHash})>[];
      while (page.length < 50) {
        if (!headers.moveNext()) {
          exhausted = true;
          break;
        }
        page.add(headers.current);
      }
      if (page.isEmpty) return;
      final rows = await database.rows(
        'SELECT * FROM crypto_directory_entries WHERE partition=? AND account_id=? AND generation IN (${List.filled(page.length, '?').join(',')})',
        [partition, directory.accountId, ...page.map((h) => h.generation)],
      );
      if (rows.length != page.length) {
        throw const CryptoDirectoryException(
          'directory_operation_bytes_pending',
        );
      }
      final by = {for (final row in rows) row['generation']: row};
      for (final header in page) {
        final row = by[header.generation];
        if (row == null || row['head_hash'] != header.headHash) {
          throw const CryptoDirectoryException(
            'directory_operation_substitution',
          );
        }
        final proof = _decode(row['authorization']),
            commandBytes = cryptoBase64(proof['commandBase64']);
        final command = CryptoJson.decode(commandBytes) as Map;
        final commandHash = await cryptoSha256(commandBytes);
        final headHash = await cryptoSha256([
          ...utf8.encode(cryptoDirectoryLogDomain),
          ...CryptoJson.encode({
            'serverId': directory.serverId,
            'accountId': directory.accountId,
            'generation': header.generation,
            'previousHeadHash': row['previous_head_hash'],
            'commandHash': commandHash,
            'signatureBase64': proof['signatureBase64'],
          }),
        ]);
        if (command['operation'] != operation ||
            command['accountId'] != directory.accountId ||
            command['serverId'] != directory.serverId ||
            row['command_hash'] != commandHash ||
            headHash != header.headHash) {
          throw const CryptoDirectoryException(
            'directory_operation_substitution',
          );
        }
        yield {
          'generation': header.generation,
          'headHash': header.headHash,
          'previousHeadHash': row['previous_head_hash'],
          'commandHash': commandHash,
          'authorization': proof,
        };
      }
    }
  }

  /// Discovery acceleration only. Completeness callers must use the verified
  /// lineage overload above; a same-sized SQL index is not an absence proof.
  Stream<Map<String, dynamic>> operationEntries(
    String account,
    String operation,
    int through, {
    bool descending = false,
  }) async* {
    final count =
        (await database.rows(
              'SELECT COUNT(*) AS n FROM crypto_directory_event_index WHERE partition=? AND account_id=? AND generation<=?',
              [partition, account, through],
            )).single['n']
            as int;
    if (count != through) {
      // Derived and excluded from backups. Rebuild missing rows in bounded pages;
      // callers still bind each returned command to their verified own prefix.
      await for (final e in streamEntries(account)) {
        if (e['generation'] > through) break;
        final c =
            CryptoJson.decode(
                  cryptoBase64((e['authorization'] as Map)['commandBase64']),
                )
                as Map;
        await database.execute(
          'INSERT INTO crypto_directory_event_index VALUES(?,?,?,?) ON CONFLICT(partition,account_id,generation) DO UPDATE SET operation=excluded.operation',
          [partition, account, e['generation'], c['operation']],
        );
      }
    }
    var after = descending ? through + 1 : 0;
    while (true) {
      final rows = await database.rows(
        'SELECT e.* FROM crypto_directory_entries e JOIN crypto_directory_event_index i ON i.partition=e.partition AND i.account_id=e.account_id AND i.generation=e.generation WHERE e.partition=? AND e.account_id=? AND i.operation=? AND e.generation${descending ? '<' : '>'}? AND e.generation<=? ORDER BY e.generation ${descending ? 'DESC' : 'ASC'} LIMIT 50',
        [partition, account, operation, after, through],
      );
      for (final row in rows) {
        yield {
          'generation': row['generation'],
          'headHash': row['head_hash'],
          'previousHeadHash': row['previous_head_hash'],
          'commandHash': row['command_hash'],
          'authorization': _decode(row['authorization']),
        };
      }
      if (rows.length < 50) return;
      after = rows.last['generation'] as int;
    }
  }

  Future<void> stageReplay(
    String run,
    String account,
    Map<String, dynamic> e,
  ) => database.execute(
    'INSERT INTO crypto_directory_replay_staging VALUES(?,?,?,?,?,?,?,?)',
    [
      partition,
      run,
      account,
      e['generation'],
      e['headHash'],
      e['previousHeadHash'],
      e['commandHash'],
      CryptoJson.encode(e['authorization']),
    ],
  );

  Future<void> append(String account, Map<String, dynamic> entry) async {
    final old = (await database.rows(
      'SELECT authorization,head_hash FROM crypto_directory_entries WHERE partition=? AND account_id=? AND generation=?',
      [partition, account, entry['generation']],
    )).firstOrNull;
    final bytes = CryptoJson.encode(entry['authorization']);
    if (old != null) {
      if (old['head_hash'] != entry['headHash'] ||
          base64Encode(_bytes(old['authorization'])) != base64Encode(bytes)) {
        throw const CryptoDirectoryException('directory_fork');
      }
      return;
    }
    await database
        .execute('INSERT INTO crypto_directory_entries VALUES(?,?,?,?,?,?,?)', [
          partition,
          account,
          entry['generation'],
          entry['headHash'],
          entry['previousHeadHash'],
          entry['commandHash'],
          bytes,
        ]);
  }

  Future<void> pinComparedIdentity(
    VerifiedAccountDirectory directory,
    String fingerprint,
  ) async {
    return withCryptoAnchorLock(partition, () async {
      if (directory.rootFingerprint != fingerprint)
        throw const CryptoDirectoryException('directory_root_changed');
      final old = await anchor(directory.accountId);
      if (old != null &&
          !directory.includesAnchor(
            old['generation'] as int,
            old['headHash'] as String,
          ))
        throw const CryptoDirectoryException('directory_anchor_fork');

      if (old != null && (old['generation'] as int) > directory.generation) {
        throw const CryptoDirectoryException('directory_rollback');
      }
      if (old != null &&
          old['generation'] == directory.generation &&
          old['headHash'] != directory.headHash) {
        throw const CryptoDirectoryException('directory_fork');
      }
      await secure.write(
        _anchor(directory.accountId),
        utf8.decode(
          CryptoJson.encode({
            ...?old,
            'serverId': directory.serverId,
            'accountId': directory.accountId,
            'fingerprint': fingerprint,
            'rootSigningKeyBase64': directory.snapshot['rootSigningKeyBase64'],
            'rootEncryptionKeyBase64':
                directory.snapshot['rootEncryptionKeyBase64'],
            'generation': directory.generation,
            'headHash': directory.headHash,
            'snapshotHash': directory.snapshotHash,
            'deviceSnapshotHash': directory.deviceSnapshotHash,
            'identityEpochId': directory.identityEpochId,
            'trustState': 'verified',
          }),
        ),
      );
    });
  }

  Future<void> authorizeRootHandoff(
    Map<String, dynamic> proof,
    String newFingerprint,
  ) async {
    final pendingProofs = await pending();
    return withCryptoAnchorLock(partition, () async {
      final c =
          CryptoJson.decode(cryptoBase64(proof['commandBase64']))
              as Map<String, dynamic>;
      final p = c['payload'] as Map;
      final old = await anchor(c['accountId']);
      var matches =
          old != null &&
          old['headHash'] == p['previousHeadHash'] &&
          old['generation'] == p['expectedGeneration'];
      if (!matches &&
          old != null &&
          p['expectedGeneration'] == (old['generation'] as int) + 1) {
        for (final startProof in pendingProofs) {
          final start =
              CryptoJson.decode(cryptoBase64(startProof['commandBase64']))
                  as Map;
          final sp = start['payload'] as Map;
          if (start['operation'] != 'crypto2.account.recoveryStart' ||
              start['signer'] != 'root' ||
              sp['previousHeadHash'] != old['headHash'] ||
              sp['expectedGeneration'] != old['generation']) {
            continue;
          }
          final hash = await cryptoSha256([
            ...utf8.encode(cryptoDirectoryLogDomain),
            ...CryptoJson.encode({
              'serverId': start['serverId'],
              'accountId': start['accountId'],
              'generation': (sp['expectedGeneration'] as int) + 1,
              'previousHeadHash': sp['previousHeadHash'],
              'commandHash': await cryptoSha256(
                cryptoBase64(startProof['commandBase64']),
              ),
              'signatureBase64': startProof['signatureBase64'],
            }),
          ]);
          if (hash == p['previousHeadHash']) matches = true;
        }
      }
      if (old == null || !matches) {
        throw const CryptoDirectoryException('directory_handoff_conflict');
      }
      final marker = {
        'requestId': c['requestId'],
        'commandHash': await cryptoSha256(cryptoBase64(proof['commandBase64'])),
        'newFingerprint': newFingerprint,
        'previousHeadHash': p['previousHeadHash'],
      };
      if (old['pendingRootTransition'] != null &&
          jsonEncode(old['pendingRootTransition']) != jsonEncode(marker)) {
        throw const CryptoDirectoryException('directory_handoff_conflict');
      }
      await secure.write(
        _anchor(c['accountId']),
        utf8.decode(
          CryptoJson.encode({...old, 'pendingRootTransition': marker}),
        ),
      );
    });
  }

  Future<void> recordReceipt(
    String id,
    Map<String, dynamic> receipt,
    String state,
  ) => database.execute(
    'UPDATE crypto_identity_requests SET stage=?,receipt=? WHERE partition=? AND request_id=? AND retired=0',
    [state, CryptoJson.encode(receipt), partition, id],
  );
  Future<List<Map<String, Object?>>> rejected() => database.rows(
    "SELECT * FROM crypto_identity_requests WHERE partition=? AND stage='rejected' AND retired=0",
    [partition],
  );
  Future<void> markSending(String id) => database.execute(
    "UPDATE crypto_identity_requests SET stage='sending' WHERE partition=? AND request_id=? AND stage='pending'",
    [partition, id],
  );

  /// External-file reimport is checked by the workflow before this operation.
  /// Only server-confirmed rejected requests and their unsent successors retire.
  Future<void> retireRejectedRecovery() async {
    final rejectedRows = await rejected();
    if (rejectedRows.isEmpty) return;
    for (final row in rejectedRows) {
      final receipt = _decode(row['receipt']);
      final c =
          CryptoJson.decode(
                cryptoBase64(_decode(row['authorization'])['commandBase64']),
              )
              as Map;
      if (receipt['status'] != 409 ||
          (receipt['response'] as Map)['errorCode'] !=
              'crypto_generation_conflict' ||
          c['signer'] != 'root' ||
          ![
            'crypto2.account.recoveryStart',
            'crypto2.account.recoverEpoch',
            'crypto2.account.rotateRoot',
          ].contains(c['operation'])) {
        throw const CryptoDirectoryException(
          'directory_rejected_request_not_rebasable',
        );
      }
    }
    final unknown = await database.rows(
      "SELECT request_id FROM crypto_identity_requests WHERE partition=? AND stage='sending' AND retired=0",
      [partition],
    );
    if (unknown.isNotEmpty) {
      throw const CryptoDirectoryException('directory_receipt_unknown');
    }
    // Only conclusively rejected, never-sent successors have been retired.
    // Their handoff marker cannot authorize a new root without a new external
    // file verification and a newly signed transition against the current head.
    for (final row in rejectedRows) {
      final c =
          CryptoJson.decode(
                cryptoBase64(_decode(row['authorization'])['commandBase64']),
              )
              as Map;
      await withCryptoAnchorLock(partition, () async {
        final old = await anchor(c['accountId']);
        if (old?['pendingRootTransition'] != null) {
          final next = {...old!}..remove('pendingRootTransition');
          await secure.write(
            _anchor(c['accountId']),
            utf8.decode(CryptoJson.encode(next)),
          );
        }
      });
    }
    await database.execute(
      "UPDATE crypto_identity_requests SET retired=1 WHERE partition=? AND stage IN ('pending','rejected') AND retired=0",
      [partition],
    );
  }

  Future<void> stage(Map<String, dynamic> proof, String stage) async {
    final c =
        CryptoJson.decode(cryptoBase64(proof['commandBase64']))
            as Map<String, dynamic>;
    final bytes = CryptoJson.encode(proof);
    final old = (await database.rows(
      'SELECT authorization FROM crypto_identity_requests WHERE partition=? AND request_id=?',
      [partition, c['requestId']],
    )).firstOrNull;
    if (old != null) {
      if (base64Encode(_bytes(old['authorization'])) != base64Encode(bytes)) {
        throw const CryptoDirectoryException('directory_immutable_request');
      }
      return;
    }
    await database.execute(
      'INSERT INTO crypto_identity_requests(partition,request_id,operation,stage,authorization) VALUES(?,?,?,?,?)',
      [partition, c['requestId'], c['operation'], stage, bytes],
    );
  }

  Future<List<Map<String, dynamic>>> pending() async => [
    for (final row in await database.rows(
      "SELECT authorization FROM crypto_identity_requests WHERE partition=? AND stage IN ('pending','sending') AND retired=0 ORDER BY rowid",
      [partition],
    ))
      _decode(row['authorization']),
  ];
  Future<void> receipt(
    String id,
    Map<String, dynamic> receipt,
  ) => database.execute(
    "UPDATE crypto_identity_requests SET stage='confirmed',receipt=? WHERE partition=? AND request_id=? AND retired=0",
    [CryptoJson.encode(receipt), partition, id],
  );
  static Uint8List _bytes(Object? value) => value is Uint8List
      ? value
      : Uint8List.fromList((value as List).cast<int>());
  static Map<String, dynamic> _decode(Object? value) =>
      CryptoJson.decode(_bytes(value)) as Map<String, dynamic>;
}
