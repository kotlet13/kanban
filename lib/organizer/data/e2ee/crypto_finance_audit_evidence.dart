import 'dart:convert';
import 'dart:typed_data';

import 'crypto_business_json.dart';
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_migration_audit_read.dart';
import 'crypto_project_relocation_audit.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// One audit format for the UI and relocation. Legacy captures remain original
/// historical facts; a migration/relocation baseline never invents a new edit.
class CryptoFinanceAuditEvidence {
  CryptoFinanceAuditEvidence(this.context);
  final CryptoBusinessSession context;
  final _legacy = <String, VerifiedCryptoMigrationAudit>{};
  static const types = {
    'financeAccount',
    'personalFinanceAccount',
    'financeEntry',
    'personalFinanceEntry',
    'financeTransfer',
    'financeRecurrenceRule',
  };
  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('crypto_finance_audit_shape');
    }
    return Map<String, dynamic>.from(value);
  }

  Map<String, dynamic> _body(Map proof) =>
      _map(CryptoJson.decode(cryptoBase64(proof['commandBase64'])));
  Future<void> close() async {
    for (final v in _legacy.values) {
      await v.close();
    }
    _legacy.clear();
  }

  /// Exact current payload for a source derivation. Cached plaintext and SQL
  /// verdicts cannot substitute for the signed wire and decrypted witness.
  Future<Map<String, dynamic>> currentPayload(
    String scope,
    String canonicalId, {
    required String type,
  }) async {
    final own = await context.account.directory.requireFresh(),
        read = await context.access.readContext(scope, 'finance');
    final row = await context.record(scope, 'finance', canonicalId, type: type);
    if (row == null || row['deleted'] == 1) {
      throw const CryptoAuthorityPending('crypto_finance_audit_record_pending');
    }
    final rows = await context.db.rows(
      'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
      [context.partition, scope, 'finance', row['id'], row['crypto_revision']],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_finance_audit_history_pending',
      );
    }
    final wire = _map(jsonDecode(rows.single['wire'] as String)),
        proof = _map(wire['authorization']['recordProof']),
        body = _body(proof);
    if (body['scopeId'] != scope ||
        body['domain'] != 'finance' ||
        body['type'] != type ||
        body['metadata']['identity']['canonicalId'] != canonicalId ||
        await context.codec.digest(proof) != row['record_proof_hash']) {
      throw const FormatException('crypto_finance_audit_identity');
    }
    final authority = await context.access.recordAuthority(body),
        raw = await _raw(wire, body, authority);
    if (raw == null) {
      throw const CryptoAuthorityPending('crypto_finance_audit_record_pending');
    }
    await _guard(
      scope,
      read.headHash,
      own.identityEpochId,
      own.deviceSnapshotHash,
    );
    return {
      'raw': raw,
      'row': row,
      'record': body,
      'wire': wire,
      'authority': authority,
    };
  }

  /// The caller supplies authority from an independently authenticated opaque
  /// history chain. Signature/closed hash are checked again before decryption.
  Future<Map<String, dynamic>> openSnapshotPayload(
    Map<String, dynamic> wire,
    CryptoRecordAuthority authority,
  ) async {
    final body = await context.codec.verifyWire(
      serverId: context.account.directory.session.profile.serverId,
      wire: wire,
      trustedSigningKey: authority.signingKey,
      currentEpoch: authority.currentEpoch,
      closedRecordProofHash: authority.closedRecordProofHash,
    );
    final raw = await _raw(wire, body, authority);
    if (raw == null) {
      throw const FormatException('crypto_finance_audit_deleted_payload');
    }
    return raw;
  }

  Future<List<Map<String, dynamic>>> history({
    required String scopeId,
    required String recordId,
    int? beforeRevision,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 50) {
      throw const FormatException('crypto_finance_audit_limit');
    }
    final result = <Map<String, dynamic>>[];
    await for (final page in historyPages(
      scopeId,
      recordId,
      beforeRevision: beforeRevision,
      pageSize: limit,
    )) {
      result.addAll(page.take(limit - result.length));
      if (result.length == limit) break;
    }
    return result;
  }

  Stream<List<Map<String, dynamic>>> historyPages(
    String scopeId,
    String recordId, {
    int? beforeRevision,
    int pageSize = 50,
  }) async* {
    if (!isCryptoCanonicalUuid(scopeId) ||
        !isCryptoCanonicalUuid(recordId) ||
        pageSize < 1 ||
        pageSize > 50 ||
        beforeRevision != null && beforeRevision < 1) {
      throw const FormatException('crypto_finance_audit_target');
    }
    final own = await context.account.directory.requireFresh();
    final read = await context.access.readContext(scopeId, 'finance');
    await context.pullVerified(scopeId, 'finance', attest: false);
    final current = await context.record(scopeId, 'finance', recordId);
    if (current == null || !types.contains(current['type'])) {
      throw const CryptoAuthorityPending('crypto_finance_audit_record_pending');
    }
    final roots = await context.db.rows(
      'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
      [
        context.partition,
        scopeId,
        'finance',
        current['id'],
        current['crypto_revision'],
      ],
    );
    if (roots.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_finance_audit_history_pending',
      );
    }
    final wire = _map(jsonDecode(roots.single['wire'] as String)),
        proof = _map(wire['authorization']['recordProof']),
        body = _body(proof);
    if (body['metadata']['identity']['canonicalId'] != recordId ||
        await context.codec.digest(proof) != current['record_proof_hash']) {
      throw const FormatException('crypto_finance_audit_identity');
    }
    final initial = await context.account.directory.call(
      'crypto2.scope.lifecycle.baseline',
      {'scopeId': scopeId},
    );
    final origin = _body(_map(initial['originAuthorization']));
    final head = await context.access.currentHead(scopeId, online: true);
    if (head.headHash != read.headHash ||
        await context.access.verifyInitialLifecycle(
              scopeId,
              initial,
              scopeHeadHash: head.headHash,
            ) !=
            head.body['initialLifecycleHash']) {
      throw const FormatException('crypto_finance_audit_origin');
    }
    final relocated =
        origin['operation'] == 'crypto2.scope.origin' &&
        origin.containsKey('projectRelocation');
    final legacy = relocated
        ? null
        : (_legacy[scopeId] ??= await CryptoCommittedMigrationAudit(
            context,
          ).open(scopeId));
    final relocatedEntries = relocated
        ? await CryptoProjectRelocationAudit(
            context,
          ).history(scopeId, recordId, beforeRevision: beforeRevision)
        : const <Map<String, dynamic>>[];
    final run = context.account.directory.reducer.crypto.randomId();
    await context.db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_finance_audit_frames(partition TEXT NOT NULL,run_id TEXT NOT NULL,revision INTEGER NOT NULL,proof_hash TEXT NOT NULL,body TEXT NOT NULL,raw TEXT,PRIMARY KEY(partition,run_id,revision))',
    );
    final chain = await context.access.openHistoryChain(wire),
        evidenceFor = <String, dynamic>{
          'scopeId': scopeId,
          'id': body['id'],
          'revision': wire['revision'],
          'recordProofHash': await context.codec.digest(proof),
        };
    var newFetches = 0, legacyOffset = 0;
    var currentFrame = true;
    try {
      while (currentFrame || !chain.complete) {
        Map<String, dynamic> item;
        final isCurrent = currentFrame;
        currentFrame = false;
        if (isCurrent) {
          item = wire;
        } else {
          List<Map<String, Object?>> found = [];
          for (final table in [
            'crypto_received',
            'crypto_business_history_proofs',
            'crypto_business_ack_history',
          ]) {
            final exists = await context.db.rows(
              "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
              [table],
            );
            if (exists.isEmpty) continue;
            found = await context.db.rows(
              'SELECT wire FROM $table WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
              [
                context.partition,
                scopeId,
                'finance',
                body['id'],
                chain.nextRevision,
              ],
            );
            if (found.isNotEmpty) break;
          }
          if (found.length == 1) {
            item = _map(jsonDecode(found.single['wire'] as String));
          } else {
            if (++newFetches > 32) {
              throw const CryptoAuthorityPending(
                'crypto_finance_audit_history_pending',
              );
            }
            final now = await context.access.readContext(scopeId, 'finance');
            final page = await context.account.directory
                .call('crypto2.records.historyGet', {
                  'scopeId': scopeId,
                  'domain': 'finance',
                  'accessRevision': now.accessRevision,
                  'id': body['id'],
                  'revision': chain.nextRevision,
                  'recordProofHash': chain.nextHash,
                  'evidenceFor': evidenceFor,
                });
            item = _map(page['record']);
          }
        }
        final p = _map(item['authorization']['recordProof']),
            r = _body(p),
            hash = await context.codec.digest(p);
        if (r['metadata']['identity']['canonicalId'] != recordId ||
            r['type'] != body['type']) {
          throw const FormatException('crypto_finance_audit_identity');
        }
        final authority = isCurrent
            ? await context.access.recordAuthority(r)
            : await chain.authority(item);
        final raw = await _raw(item, r, authority);
        await context.db.execute(
          'CREATE TABLE IF NOT EXISTS crypto_business_history_proofs(partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,record_id TEXT NOT NULL,revision INTEGER NOT NULL,proof_hash TEXT NOT NULL,wire TEXT NOT NULL,history_basis TEXT NOT NULL,PRIMARY KEY(partition,scope_id,domain,record_id,revision,proof_hash))',
        );
        await context.db.execute(
          'INSERT OR IGNORE INTO crypto_business_history_proofs(partition,scope_id,domain,record_id,revision,proof_hash,wire,history_basis) VALUES(?,?,?,?,?,?,?,?)',
          [
            context.partition,
            scopeId,
            'finance',
            r['id'],
            item['revision'],
            hash,
            jsonEncode(item),
            authority.historyBasis ?? 'currentEpoch',
          ],
        );
        await context.db.execute(
          'INSERT INTO crypto_finance_audit_frames VALUES(?,?,?,?,?,?)',
          [
            context.partition,
            run,
            item['revision'],
            hash,
            jsonEncode(r),
            raw == null ? null : CryptoBusinessJson.canonical(raw),
          ],
        );
        if (item['revision'] == 1 && authority.relocationOrigin != null) {
          final origin = authority.relocationOrigin!;
          if (origin['side'] != 'target' ||
              origin['logicalRevision'] is! int ||
              origin['physicalRevision'] != 1 ||
              origin['logicalRevision'] < 1) {
            throw const FormatException(
              'crypto_finance_audit_relocation_baseline',
            );
          }
          legacyOffset = (origin['logicalRevision'] as int) - 1;
        }
        if (item['revision'] == 1 && authority.migrationOrigin != null) {
          final revision = authority.migrationOrigin!['legacyRevision'];
          if (revision is! int || revision < 1) {
            throw const FormatException('crypto_finance_audit_baseline');
          }
          legacyOffset = revision - 1;
        }
      }
      // Each before snapshot is an independently authenticated predecessor of
      // this exact current chain, never an imported SQL completion flag.
      final result = <Map<String, dynamic>>[];
      int? after;
      while (true) {
        await _guard(
          scopeId,
          read.headHash,
          own.identityEpochId,
          own.deviceSnapshotHash,
        );
        final rows = await context.db.rows(
          'SELECT * FROM crypto_finance_audit_frames WHERE partition=? AND run_id=?${after == null ? '' : ' AND revision<?'} ORDER BY revision DESC LIMIT 50',
          [context.partition, run, if (after != null) after],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          final revision = row['revision'] as int;
          rCheck:
          {
            final r = _map(jsonDecode(row['body'] as String)),
                m = r['metadata'] as Map;
            if (revision == 1 &&
                (m.containsKey('migrationOrigin') ||
                    (m['projectRelocation'] as Map?)?['side'] == 'target')) {
              break rCheck;
            }
            final logical = revision + legacyOffset;
            if (beforeRevision != null && logical >= beforeRevision) {
              break rCheck;
            }
            final previous = revision == 1
                ? <Map<String, Object?>>[]
                : await context.db.rows(
                    'SELECT raw FROM crypto_finance_audit_frames WHERE partition=? AND run_id=? AND revision=?',
                    [context.partition, run, revision - 1],
                  );
            if (revision > 1 && previous.length != 1) {
              throw const FormatException('crypto_finance_audit_chain_missing');
            }
            final before = previous.isEmpty || previous.single['raw'] == null
                ? null
                : _map(jsonDecode(previous.single['raw'] as String));
            final raw = row['raw'] == null
                ? null
                : _map(jsonDecode(row['raw'] as String));
            result.add({
              'scopeId': scopeId,
              'recordId': recordId,
              'revision': logical,
              'cryptoRevision': revision,
              'revisionNamespace': 'crypto',
              'actorAccountId': r['accountId'],
              'changedAt': m['auditState']?['changedAt'],
              'timeBasis': 'authorClaimed',
              'opId': r['operationId'],
              'before': before,
              'after': raw,
              'beforeJson': previous.isEmpty ? null : previous.single['raw'],
              'afterJson': row['raw'],
              'sourceEvidenceHash': row['proof_hash'],
            });
            if (result.length == pageSize) {
              await _guard(
                scopeId,
                read.headHash,
                own.identityEpochId,
                own.deviceSnapshotHash,
              );
              yield List.unmodifiable(result);
              result.clear();
            }
          }
          after = revision;
        }
      }
      final preserved = legacy != null
          ? legacy.records(
              recordId,
              beforeRevision: beforeRevision,
              pageSize: pageSize,
            )
          : Stream<List<Map<String, dynamic>>>.fromIterable([
              for (var i = 0; i < relocatedEntries.length; i += pageSize)
                relocatedEntries.skip(i).take(pageSize).toList(),
            ]);
      await for (final page in preserved) {
        await _guard(
          scopeId,
          read.headHash,
          own.identityEpochId,
          own.deviceSnapshotHash,
        );
        for (final original in page) {
          final value = {
            ...original,
            'before': original['beforeJson'] == null
                ? null
                : _map(jsonDecode(original['beforeJson'] as String)),
            'after': original['afterJson'] == null
                ? null
                : _map(jsonDecode(original['afterJson'] as String)),
          };
          result.add(value);
          if (result.length == pageSize) {
            await _guard(
              scopeId,
              read.headHash,
              own.identityEpochId,
              own.deviceSnapshotHash,
            );
            yield List.unmodifiable(result);
            result.clear();
          }
        }
      }
      if (result.isNotEmpty) {
        await _guard(
          scopeId,
          read.headHash,
          own.identityEpochId,
          own.deviceSnapshotHash,
        );
        yield List.unmodifiable(result);
      }
    } finally {
      await context.db.execute(
        'DELETE FROM crypto_finance_audit_frames WHERE partition=? AND run_id=?',
        [context.partition, run],
      );
    }
  }

  Future<void> _guard(
    String scope,
    String head,
    String identityEpochId,
    String deviceSnapshotHash,
  ) async {
    final own = await context.account.directory.cachedVerifiedDirectory();
    if (own.identityEpochId != identityEpochId ||
        own.deviceSnapshotHash != deviceSnapshotHash ||
        !context.account.directory.isCurrent() ||
        (await context.access.readContext(scope, 'finance')).headHash != head) {
      throw const CryptoAuthorityPending('crypto_finance_audit_read_changed');
    }
  }

  Future<Map<String, dynamic>?> _raw(
    Map<String, dynamic> wire,
    Map<String, dynamic> r,
    CryptoRecordAuthority authority,
  ) async {
    r = await context.codec.verifyWire(
      serverId: context.account.directory.session.profile.serverId,
      wire: wire,
      trustedSigningKey: authority.signingKey,
      currentEpoch: authority.currentEpoch,
      closedRecordProofHash: authority.closedRecordProofHash,
    );
    final key = await context.access.recordKey(r);
    Uint8List? bytes;
    try {
      bytes = context.codec.openVerified(r, key.key);
    } finally {
      key.release();
    }
    try {
      Map<String, dynamic>? envelope, raw;
      if (bytes != null) {
        envelope = _map(jsonDecode(utf8.decode(bytes)));
        if (envelope['format'] != 2 ||
            CryptoBusinessJson.canonical(envelope['identity']) !=
                CryptoBusinessJson.canonical(r['metadata']['identity'])) {
          throw const FormatException('crypto_finance_audit_envelope');
        }
        raw = _map(envelope['payload']);
      }
      if (authority.migrationOrigin != null) {
        raw = await verifyCryptoMigrationWitness(
          record: r,
          origin: authority.migrationOrigin!,
          recordProofHash: await context.codec.digest(
            _map(wire['authorization']['recordProof']),
          ),
          envelope: envelope,
          detachedWitness: authority.migrationWitness,
          reservedId: context.reservedRecordId,
        );
      }
      if (raw != null && context.expandPayload != null) {
        final value = CryptoProjectionRecord(
          wire,
          r,
          bytes,
          historyBasis: authority.historyBasis ?? 'currentEpoch',
          batchKey: 'financeAudit',
          migrationOrigin: authority.migrationOrigin,
          relocationOrigin: authority.relocationOrigin,
          migrationWitness: authority.migrationWitness,
        );
        await context.prepareHistoricalPayload?.call([value]);
        raw = await context.expandPayload!(value, raw);
      }
      return raw;
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }
}
