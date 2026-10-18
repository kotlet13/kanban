import 'dart:convert';
import 'dart:typed_data';

import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_inventory_json.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_sync_repository.dart';

/// Read-only predecessor hydration. Historical compound batches never produce
/// separate business effects: their authenticated payloads only validate the
/// semantic transition of the complete current projection group.
class CryptoBusinessHistory {
  CryptoBusinessHistory(this.context);
  final CryptoBusinessSession context;

  Future<void> prepare(List<CryptoProjectionRecord> batch) async {
    final targets =
        <
          ({
            CryptoProjectionRecord value,
            Map<String, dynamic> anchor,
            Map<String, dynamic>? reference,
          })
        >[];
    for (final current in batch) {
      final metadata = current.record['metadata'] as Map;
      for (final ref in (metadata['referenceVersions'] as List? ?? const [])) {
        final staged = batch
            .where(
              (target) =>
                  target.record['scopeId'] == ref['scopeId'] &&
                  target.record['domain'] == ref['domain'] &&
                  target.record['id'] == ref['id'] &&
                  target.wire['revision'] == ref['revision'],
            )
            .firstOrNull;
        if (staged != null &&
            await context.codec.digest(
                  Map<String, dynamic>.from(
                    (staged.wire['authorization'] as Map)['recordProof'] as Map,
                  ),
                ) ==
                ref['recordProofHash']) {
          continue;
        }
        targets.add((
          value: CryptoProjectionRecord(
            const {},
            {
              'scopeId': ref['scopeId'],
              'domain': ref['domain'],
              'id': ref['id'],
              'expectedRevision': ref['revision'],
              'previousRecordHash': ref['recordProofHash'],
            },
            null,
            historyBasis: current.historyBasis,
            batchKey: current.batchKey,
            historicalOnly: current.historicalOnly,
            historicalAnchorWire: current.historicalAnchorWire,
          ),
          anchor: current.wire,
          reference: Map<String, dynamic>.from(ref as Map),
        ));
      }
    }
    targets.addAll(
      batch.map(
        (value) => (
          value: value,
          anchor: value.historicalAnchorWire ?? value.wire,
          reference: null,
        ),
      ),
    );
    // One hydration pass shares its network-work budget across every target.
    // Cached exact predecessors are still rewalked for authority, without
    // spending this fetch budget, so later chains progress on subsequent passes.
    var fetched = 0;
    for (final target in targets) {
      final current = target.value;
      final r = current.record;
      final revision = r['expectedRevision'] as int;
      if (revision == 0) continue;
      final scope = r['scopeId'] as String,
          domain = r['domain'] as String,
          id = r['id'] as String;
      final targetHash = r['previousRecordHash'] as String;
      final db = context.database, p = context.partition;
      final anchor = await context.wireRecord(scope, domain, id);
      final restored = (await db.rows(
        'SELECT revision,proof_hash FROM crypto_restore_record_anchors WHERE partition=? AND scope_id=? AND domain=? AND record_id=?',
        [p, scope, domain, id],
      )).firstOrNull;
      // Older historical references remain readable. A new current candidate
      // at/above a restored floor must intersect its exact authenticated chain.
      final requiredRestore =
          restored != null && revision >= (restored['revision'] as int)
          ? restored
          : null;
      if (requiredRestore == null &&
          anchor != null &&
          anchor['crypto_revision'] == revision) {
        if (anchor['record_proof_hash'] != targetHash) {
          throw const FormatException('crypto_business_predecessor');
        }
        continue;
      }
      final key = [p, scope, domain, id, revision, targetHash];
      await db.execute(
        'INSERT OR IGNORE INTO crypto_business_history_jobs VALUES(?,?,?,?,?,?,?,?,0)',
        [...key, revision, targetHash],
      );
      // A durable cursor is progress metadata, never historical authority.
      // Reopen from the independently authenticated anchor after every restart.
      final referenceAnchor = target.reference == null
          ? null
          : await context.access.referenceAnchorCandidate(target.reference!);
      final chain = await context.access.openHistoryChain(
        target.anchor,
        reference: target.reference,
        referenceAnchorWire: referenceAnchor,
        carrierAnchorWire: target.reference != null && current.historicalOnly
            ? current.historicalAnchorWire
            : null,
      );
      final carrierProof = Map<String, dynamic>.from(
        (target.anchor['authorization'] as Map)['recordProof'] as Map,
      );
      final carrier =
          CryptoJson.decode(cryptoBase64(carrierProof['commandBase64'])) as Map;
      final evidenceFor = <String, dynamic>{
        'scopeId': carrier['scopeId'],
        'id': carrier['id'],
        'revision': (carrier['expectedRevision'] as int) + 1,
        'recordProofHash': await context.codec.digest(carrierProof),
      };
      var next = chain.nextRevision, hash = chain.nextHash;
      if (next < revision || next == revision && hash != targetHash) {
        throw const FormatException('crypto_history_anchor_binding');
      }
      var complete = false;
      var goalReached = false;
      while (true) {
        if (next == revision) {
          if (hash != targetHash) {
            throw const FormatException('crypto_history_reference_fork');
          }
          goalReached = true;
        }
        if (goalReached &&
            requiredRestore != null &&
            next <= (requiredRestore['revision'] as int)) {
          if (next != requiredRestore['revision'] ||
              hash != requiredRestore['proof_hash']) {
            throw const FormatException('crypto_restore_record_fork');
          }
          complete = true;
          break;
        }
        if (next == 0) {
          if (!goalReached || hash != '0' * 64) {
            throw const FormatException('crypto_business_genesis_chain');
          }
          complete = true;
          break;
        }
        if (goalReached &&
            requiredRestore == null &&
            anchor != null &&
            anchor['crypto_revision'] == next) {
          if (anchor['record_proof_hash'] != hash) {
            throw const FormatException('crypto_business_predecessor');
          }
          complete = true;
          break;
        }
        var rows = await db.rows(
          'SELECT * FROM crypto_business_history_payloads WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?',
          [p, scope, domain, id, next, hash],
        );
        final cached = await db.rows(
          'SELECT wire FROM crypto_business_history_proofs WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?',
          [p, scope, domain, id, next, hash],
        );
        if (rows.isNotEmpty && cached.length == 1) {
          final wire = Map<String, dynamic>.from(
            jsonDecode(cached.single['wire'] as String) as Map,
          );
          await chain.authority(wire);
        } else {
          if (fetched >= 32) break;
          fetched++;
          final read = await context.access.readContext(scope, domain);
          final response = await context.account.directory
              .call('crypto2.records.historyGet', {
                'scopeId': scope,
                'domain': domain,
                'accessRevision': read.accessRevision,
                'id': id,
                'revision': next,
                'recordProofHash': hash,
                'evidenceFor': evidenceFor,
              });
          final wire = Map<String, dynamic>.from(response['record'] as Map);
          final auth = wire['authorization'] as Map;
          final proof = Map<String, dynamic>.from(auth['recordProof'] as Map);
          final body = Map<String, dynamic>.from(
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
          );
          context.codec.validateUntrustedRecord(body);
          if (body['scopeId'] != scope ||
              body['domain'] != domain ||
              body['id'] != id ||
              (r['type'] != null && body['type'] != r['type']) ||
              wire['revision'] != next ||
              await context.codec.digest(proof) != hash) {
            throw const FormatException('crypto_history_binding');
          }
          final authority = await chain.authority(wire);
          final verified = await context.codec.verifyWire(
            serverId: context.account.directory.session.profile.serverId,
            wire: wire,
            trustedSigningKey: authority.signingKey,
            currentEpoch: authority.currentEpoch,
            closedRecordProofHash: authority.closedRecordProofHash,
          );
          final lease = await context.access.recordKey(verified);
          late final Uint8List? bytes;
          try {
            bytes = context.codec.openVerified(verified, lease.key);
          } finally {
            lease.release();
          }
          try {
            Map<String, dynamic>? payload;
            Map<String, dynamic>? decodedEnvelope;
            if (bytes != null) {
              final envelope = jsonDecode(utf8.decode(bytes));
              if (envelope is! Map ||
                  !const [1, 2].contains(envelope['format']) ||
                  (envelope['format'] == 2 &&
                      envelope.length !=
                          (authority.migrationOrigin == null ||
                                  authority.migrationOrigin!['sourceTable'] ==
                                      'familyhub_scopes' ||
                                  authority
                                          .migrationOrigin?['captureVersion'] ==
                                      3
                              ? 3
                              : 4)) ||
                  (envelope['format'] == 2 &&
                      CryptoInventoryJson.canonical(envelope['identity']) !=
                          CryptoInventoryJson.canonical(
                            verified['metadata']['identity'],
                          )) ||
                  envelope['payload'] is! Map) {
                throw const FormatException('crypto_history_payload');
              }
              decodedEnvelope = Map<String, dynamic>.from(envelope);
              payload = Map<String, dynamic>.from(envelope['payload'] as Map);
            }
            if (authority.migrationOrigin != null) {
              payload = await verifyCryptoMigrationWitness(
                record: verified,
                origin: authority.migrationOrigin!,
                recordProofHash: hash,
                envelope: decodedEnvelope,
                detachedWitness: authority.migrationWitness,
                reservedId: context.reservedRecordId,
              );
            }
            final observed = CryptoProjectionRecord(
              wire,
              verified,
              bytes,
              historyBasis: authority.currentEpoch
                  ? 'currentEpoch'
                  : authority.historyBasis ?? 'unconfirmed',
              batchKey: await context.codec.digest(
                Map<String, dynamic>.from(auth['batchCommitment'] as Map),
              ),
              migrationOrigin: authority.migrationOrigin,
              relocationOrigin: authority.relocationOrigin,
              migrationWitness: authority.migrationWitness,
            );
            if (![
              'currentEpoch',
              'verifiedCheckpoint',
              'reviewedRecoveryBaseline',
              'migrationCapturedSource',
              'inlineProjectDeletion',
              'managerAttestedProjectRelocation',
            ].contains(observed.historyBasis)) {
              throw const CryptoAuthorityPending(
                'crypto_history_basis_required',
              );
            }
            await context.prepareHistoricalPayload?.call([observed]);
            if (payload != null && context.expandPayload != null) {
              payload = await context.expandPayload!(observed, payload);
            }
            if (payload != null) {
              await context.validateHistoricalPayload?.call(observed, payload);
            }
            // Store ciphertext/proof separately from this vault-only plaintext
            // cache. Generic backup exports only the reconstructible evidence.
            await db.transaction(() async {
              if (!context.account.directory.isCurrent()) {
                throw const FormatException('crypto_stale_identity');
              }
              await db.execute(
                'INSERT OR IGNORE INTO crypto_business_history_proofs VALUES(?,?,?,?,?,?,?,?)',
                [
                  p,
                  scope,
                  domain,
                  id,
                  next,
                  hash,
                  jsonEncode(wire),
                  observed.historyBasis,
                ],
              );
              await db.execute(
                'INSERT OR IGNORE INTO crypto_business_history_payloads VALUES(?,?,?,?,?,?,?,?,?)',
                [
                  p,
                  scope,
                  domain,
                  id,
                  next,
                  hash,
                  body['previousRecordHash'],
                  payload == null ? null : jsonEncode(payload),
                  jsonEncode(body),
                ],
              );
            });
          } finally {
            bytes?.fillRange(0, bytes.length, 0);
          }
          rows = await db.rows(
            'SELECT * FROM crypto_business_history_payloads WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?',
            [p, scope, domain, id, next, hash],
          );
        }
        if (rows.single['previous_hash'] != chain.nextHash ||
            chain.nextRevision != next - 1) {
          throw const FormatException('crypto_history_cache_binding');
        }
        hash = chain.nextHash;
        next = chain.nextRevision;
        await db.execute(
          'UPDATE crypto_business_history_jobs SET next_revision=?,next_hash=? WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND target_revision=? AND target_hash=?',
          [next, hash, ...key],
        );
      }
      if (!complete &&
          goalReached &&
          next == 0 &&
          hash == '0' * 64 &&
          requiredRestore == null) {
        complete = true;
      }
      if (!complete) throw const CryptoProjectionPending();
      await db.execute(
        'UPDATE crypto_business_history_jobs SET complete=1 WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND target_revision=? AND target_hash=?',
        key,
      );
      if (requiredRestore != null) {
        await db.execute(
          'INSERT OR IGNORE INTO crypto_business_history_restore_links VALUES(?,?,?,?,?,?,?,?)',
          [...key, requiredRestore['revision'], requiredRestore['proof_hash']],
        );
      }
    }
  }

  /// SQL-only final projection CAS. A newer anchor imported during network
  /// hydration invalidates the old intersection and keeps the candidate pending.
  Future<void> requireRestoredIntersection(CryptoProjectionRecord value) async {
    final r = value.record, wire = value.wire;
    final anchor = (await context.database.rows(
      'SELECT revision,proof_hash FROM crypto_restore_record_anchors WHERE partition=? AND scope_id=? AND domain=? AND record_id=?',
      [context.partition, r['scopeId'], r['domain'], r['id']],
    )).firstOrNull;
    if (anchor == null) return;
    final revision = wire['revision'] as int;
    if (revision < (anchor['revision'] as int)) {
      throw const CryptoProjectionPending();
    }
    if (revision == anchor['revision']) {
      final hash = await context.codec.digest(
        Map<String, dynamic>.from(
          (wire['authorization'] as Map)['recordProof'] as Map,
        ),
      );
      if (hash != anchor['proof_hash']) {
        throw const FormatException('crypto_restore_record_fork');
      }
      return;
    }
    if (r['expectedRevision'] == anchor['revision']) {
      if (r['previousRecordHash'] != anchor['proof_hash']) {
        throw const FormatException('crypto_restore_record_fork');
      }
      return;
    }
    final intersected = await context.database.rows(
      'SELECT 1 FROM crypto_business_history_restore_links WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND target_revision=? AND target_hash=? AND anchor_revision=? AND anchor_hash=?',
      [
        context.partition,
        r['scopeId'],
        r['domain'],
        r['id'],
        r['expectedRevision'],
        r['previousRecordHash'],
        anchor['revision'],
        anchor['proof_hash'],
      ],
    );
    if (intersected.isEmpty) throw const CryptoProjectionPending();
  }
}
