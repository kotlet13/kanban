import 'dart:convert';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart';
import 'crypto_business_json.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_v3.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_audit.dart';
import 'crypto_migration_committed_origin.dart';
import 'crypto_migration_witness.dart';
import 'crypto_migration_witness_transport.dart';
import 'crypto_sync_repository.dart';

/// A fully checked scope audit snapshot, not a projection, balance or authority
/// floor. Its transient run token cannot be supplied by an imported SQL row.
class VerifiedCryptoMigrationAudit {
  VerifiedCryptoMigrationAudit._(
    this.runtime,
    this.scopeId,
    this.headHash,
    this.runId,
    this.identityEpochId,
    this.deviceSnapshotHash,
  );
  final CryptoBusinessSession runtime;
  final String scopeId, headHash, runId, identityEpochId, deviceSnapshotHash;
  bool _closed = false;
  Future<void> _guard() async {
    final own = await runtime.account.directory.cachedVerifiedDirectory();
    if (own.identityEpochId != identityEpochId ||
        own.deviceSnapshotHash != deviceSnapshotHash ||
        _closed ||
        !runtime.account.directory.isCurrent() ||
        (await runtime.access.readContext(scopeId, 'finance')).headHash !=
            headHash) {
      throw const CryptoAuthorityPending('crypto_migration_audit_read_changed');
    }
  }

  Stream<List<Map<String, dynamic>>> records(
    String recordId, {
    int? beforeRevision,
    int pageSize = 50,
  }) async* {
    if (pageSize < 1 || pageSize > 50) {
      throw const FormatException('crypto_migration_audit_limit');
    }
    int? after;
    while (true) {
      await _guard();
      final rows = await runtime.db.rows(
        'SELECT facts FROM crypto_finance_audit_evidence WHERE partition=? AND run_id=? AND record_id=?'
        '${beforeRevision == null ? '' : ' AND revision<?'}${after == null ? '' : ' AND revision<?'} ORDER BY revision DESC LIMIT $pageSize',
        [
          runtime.partition,
          runId,
          recordId,
          if (beforeRevision != null) beforeRevision,
          if (after != null) after,
        ],
      );
      if (rows.isEmpty) {
        await _guard();
        break;
      }
      final values = [
        for (final r in rows)
          Map<String, dynamic>.from(jsonDecode(r['facts'] as String) as Map),
      ];
      for (final value in values) {
        if (after != null && (value['revision'] as int) >= after) {
          throw const FormatException('crypto_migration_audit_order');
        }
        after = value['revision'];
      }
      await _guard();
      yield values;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await runtime.db.execute(
      'DELETE FROM crypto_finance_audit_evidence WHERE partition=? AND run_id=?',
      [runtime.partition, runId],
    );
  }
}

/// The entire authenticated scoped artifact set is verified before filtering a
/// record. Neither a server-filtered empty list nor a cursor proves absence.
class CryptoCommittedMigrationAudit {
  CryptoCommittedMigrationAudit(this.runtime);
  final CryptoBusinessSession runtime;
  static const maxArtifacts = 10000000;
  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('crypto_migration_audit_read_shape');
    }
    return Map<String, dynamic>.from(value);
  }

  Map<String, dynamic> _body(Map proof) =>
      _map(CryptoJson.decode(cryptoBase64(proof['commandBase64'])));
  bool _same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));
  Future<String> _hash(Object? value) => cryptoSha256(CryptoJson.encode(value));
  Future<String> _artifactHash(Map proof) => cryptoSha256(
    utf8.encode('JivieMigrationAuditArtifact/v3\n') +
        CryptoInventoryJson.encode(proof),
  );

  Future<VerifiedCryptoMigrationAudit> open(String scope) async {
    final own = await runtime.account.directory.requireFresh(),
        read = await runtime.access.readContext(scope, 'finance');
    own.activeDevice(runtime.account.deviceId);
    final run = runtime.account.directory.reducer.crypto.randomId();
    await runtime.db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_finance_audit_evidence(partition TEXT NOT NULL,run_id TEXT NOT NULL,binding_id TEXT NOT NULL,record_id TEXT NOT NULL,revision INTEGER NOT NULL,facts TEXT NOT NULL,PRIMARY KEY(partition,run_id,binding_id),UNIQUE(partition,run_id,record_id,revision))',
    );
    final states =
        <
          String,
          ({
            dynamic sink,
            int count,
            Map<String, dynamic> context,
            VerifiedCryptoMigrationControl verified,
          })
        >{};
    Map<String, dynamic>? first;
    String? after;
    var count = 0;
    var freshOrigin = false;
    try {
      while (true) {
        final page = await runtime.account.directory.call(
          'crypto2.migration.audit.list',
          {
            'scopeId': scope,
            'limit': 20,
            if (after != null) 'afterBindingId': after,
          },
        );
        if (page['version'] != 3 ||
            page['scopeId'] != scope ||
            page['artifacts'] is! List ||
            (page['artifacts'] as List).length > 20) {
          throw const FormatException('crypto_migration_audit_read_shape');
        }
        if (page['migrationId'] == null) {
          if (first != null ||
              (page['artifacts'] as List).isNotEmpty ||
              page['hasMore'] != false) {
            throw const FormatException(
              'crypto_migration_audit_read_substitution',
            );
          }
          await _requireFreshOrigin(scope, read.headHash);
          freshOrigin = true;
          break;
        }
        final base = {
          for (final key in [
            'version',
            'scopeId',
            'migrationId',
            'activationEvidence',
            'certificateAuthorization',
            'certificateEventAuthorization',
            'contexts',
          ])
            key: page[key],
        };
        if (first == null) {
          first = base;
          final certProof = _map(page['certificateAuthorization']),
              cp = _map(_body(certProof)['payload']);
          final contributions = cp['contributions'];
          if (contributions is! List ||
              page['contexts'] is! List ||
              (page['contexts'] as List).length != contributions.length ||
              contributions.isEmpty ||
              contributions.length > 100) {
            throw const FormatException('crypto_migration_audit_contexts');
          }
          final represented = <String>{};
          for (final raw in page['contexts'] as List) {
            final context = _map(raw),
                proof = _map(context['contributionAuthorization']),
                body = _body(proof),
                p = _map(body['payload']),
                h = _map(p['header']);
            final exact = contributions.where(
              (v) =>
                  _same((v as Map)['authorization'], proof) &&
                  _same(
                    v['eventAuthorization'],
                    context['contributionEventAuthorization'],
                  ),
            );
            if (exact.length != 1 ||
                !represented.add(await _hash(proof)) ||
                context['accountId'] != body['accountId'] ||
                context['captureId'] != h['captureId'] ||
                context['sourceInventoryRoot'] != h['sourceInventoryRoot']) {
              throw const FormatException('crypto_migration_audit_contexts');
            }
            final activation = _map(page['activationEvidence']);
            final verified =
                await CryptoMigrationCommittedOrigin(
                  runtime.access,
                ).verifyControlEvidence(
                  evidence: {...activation, 'controls': context['controls']},
                  contributionAuthorization: proof,
                  contributionEventAuthorization: _map(
                    context['contributionEventAuthorization'],
                  ),
                  certificateAuthorization: certProof,
                  certificateEventAuthorization: _map(
                    page['certificateEventAuthorization'],
                  ),
                );
            if (verified.activation['scopeId'] != scope ||
                verified.activation['migrationId'] != page['migrationId'] ||
                verified.contributionHeader['domain'] != 'finance') {
              throw const FormatException('crypto_migration_audit_contexts');
            }
            final common = {
              'version': 3,
              'serverId': own.serverId,
              'migrationId': page['migrationId'],
              'captureId': context['captureId'],
              'accountId': context['accountId'],
              'sourceInventoryRoot': context['sourceInventoryRoot'],
              'scopeId': scope,
              'domain': 'finance',
            };
            final sink = Sha256().newHashSink();
            sink.add(utf8.encode('JivieMigrationAuditScopeSelection/v3\n'));
            sink.add(CryptoInventoryJson.encode(common));
            sink.add([10]);
            final key = '${context['accountId']}/${context['captureId']}';
            if (states.containsKey(key)) {
              throw const FormatException('crypto_migration_audit_contexts');
            }
            states[key] = (
              sink: sink,
              count: 0,
              context: Map.unmodifiable(context),
              verified: verified,
            );
          }
        } else if (!_same(first, base)) {
          throw const FormatException(
            'crypto_migration_audit_read_substitution',
          );
        }
        for (final raw in page['artifacts'] as List) {
          final artifact = _map(raw),
              proof = _map(artifact['authorization']),
              body = _body(proof),
              p = _map(body['payload']),
              descriptor = _map(artifact['descriptor']);
          final context = CryptoMigrationWitnessContext(
                _map(descriptor['context']),
              ),
              c = context.value;
          final id = artifact['bindingId'];
          if (id is! String ||
              after != null && after.compareTo(id) >= 0 ||
              ++count > maxArtifacts ||
              body['version'] != 2 ||
              body['operation'] != 'crypto2.migration.audit.stage' ||
              body['signer'] != 'device' ||
              body['serverId'] != own.serverId ||
              p['migrationId'] != page['migrationId'] ||
              p['bindingId'] != id ||
              !_same(p['descriptor'], descriptor) ||
              c['bindingId'] != id ||
              c['scopeId'] != scope ||
              c['domain'] != 'finance' ||
              c['purpose'] != 'migrationAudit' ||
              body['accountId'] != c['accountId'] ||
              p['captureId'] != c['captureId'] ||
              p['sourceInventoryRoot'] != c['sourceInventoryRoot'] ||
              artifact['artifactHash'] != await _artifactHash(proof)) {
            throw const FormatException('crypto_migration_audit_artifact');
          }
          final key = '${body['accountId']}/${c['captureId']}',
              state = states[key];
          if (state == null ||
              state.context['sourceInventoryRoot'] !=
                  c['sourceInventoryRoot']) {
            throw const FormatException('crypto_migration_audit_unselected');
          }
          final prefix = await runtime.access.directoryAt(
            scopeId: scope,
            scopeHeadHash: state.verified.activation['membershipHeadHash'],
            accountId: body['accountId'],
            directoryHeadHash: p['authorDirectoryHeadHash'],
            online: true,
            allowUnverifiedContact: true,
          );
          runtime.codec.crypto.verifyDomain(
            proof,
            cryptoBase64(
              prefix.activeDevice(body['deviceId'])['signingKeyBase64'],
              length: 32,
            ),
            cryptoDirectoryDomain,
          );
          state.sink.add(
            CryptoInventoryJson.encode({
              'bindingId': id,
              'artifactHash': artifact['artifactHash'],
            }),
          );
          state.sink.add([10]);
          states[key] = (
            sink: state.sink,
            count: state.count + 1,
            context: state.context,
            verified: state.verified,
          );
          final facts = await _openArtifact(
            scope,
            read,
            context,
            descriptor,
            proof,
            artifact['artifactHash'],
          );
          await runtime.db.execute(
            'INSERT INTO crypto_finance_audit_evidence VALUES(?,?,?,?,?,?)',
            [
              runtime.partition,
              run,
              id,
              facts['recordId'],
              facts['revision'],
              CryptoBusinessJson.canonical(facts),
            ],
          );
          after = id;
        }
        if (page['hasMore'] == false) break;
        if (page['hasMore'] != true ||
            (page['artifacts'] as List).isEmpty ||
            page['nextAfterBindingId'] != after) {
          throw const FormatException('crypto_migration_audit_read_cursor');
        }
      }
      if (!freshOrigin && states.isEmpty) {
        throw const FormatException('crypto_migration_audit_contexts');
      }
      for (final state in states.values) {
        state.sink.close();
        final root = (await state.sink.hash()).bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (state.count != state.verified.controlLeaf['selectionCount'] ||
            root != state.verified.controlLeaf['selectionRoot']) {
          throw const FormatException('crypto_migration_audit_coverage');
        }
      }
      final finalOwn = await runtime.account.directory.requireFresh(),
          last = await runtime.access.readContext(scope, 'finance');
      if (!runtime.account.directory.isCurrent() ||
          last.headHash != read.headHash ||
          last.accessRevision != read.accessRevision ||
          finalOwn.accountId != own.accountId ||
          finalOwn.identityEpochId != own.identityEpochId ||
          finalOwn.deviceSnapshotHash != own.deviceSnapshotHash) {
        throw const CryptoAuthorityPending(
          'crypto_migration_audit_read_changed',
        );
      }
      return VerifiedCryptoMigrationAudit._(
        runtime,
        scope,
        read.headHash,
        run,
        own.identityEpochId,
        own.deviceSnapshotHash,
      );
    } catch (_) {
      await runtime.db.execute(
        'DELETE FROM crypto_finance_audit_evidence WHERE partition=? AND run_id=?',
        [runtime.partition, run],
      );
      rethrow;
    }
  }

  Future<void> _requireFreshOrigin(String scope, String headHash) async {
    final initial = await runtime.account.directory.call(
      'crypto2.scope.lifecycle.baseline',
      {'scopeId': scope},
    );
    final head = await runtime.access.currentHead(scope, online: true);
    if (head.headHash != headHash ||
        await runtime.access.verifyInitialLifecycle(
              scope,
              initial,
              scopeHeadHash: headHash,
            ) !=
            head.body['initialLifecycleHash']) {
      throw const FormatException('crypto_migration_audit_origin');
    }
    final baseline = _map(initial['initialLifecycleBaseline']),
        origin = _body(_map(initial['originAuthorization']));
    if (baseline['originKind'] != 'new' ||
        origin['operation'] != 'crypto2.scope.origin' ||
        origin.containsKey('projectRelocation')) {
      throw const CryptoAuthorityPending(
        'crypto_migration_audit_provenance_pending',
      );
    }
  }

  Future<Map<String, dynamic>> _openArtifact(
    String scope,
    CryptoReadContext read,
    CryptoMigrationWitnessContext context,
    Map<String, dynamic> descriptor,
    Map<String, dynamic> proof,
    String artifactHash,
  ) async {
    final consumer = CryptoMigrationWitness(
      database: runtime.db,
      partition: runtime.partition,
      crypto: runtime.codec.crypto,
    );
    await CryptoMigrationWitnessTransport(
      read: (op, p) async {
        final page = await runtime.account.directory.call('crypto2.blob.get', {
          'scopeId': scope,
          'domain': 'finance',
          'accessRevision': read.accessRevision,
          'id': p['id'],
          'offset': p['offset'],
        });
        return {
          ...page,
          'complete': true,
          'nextOffset':
              (p['offset'] as int) + cryptoBase64(page['dataBase64']).length,
        };
      },
    ).download(consumer: consumer, context: context, descriptor: descriptor);
    final key = await runtime.access.getScopeKey(
      scope,
      'finance',
      context.value['epoch'],
    );
    late Map<String, dynamic> witness;
    try {
      witness = await consumer.open(
        context: context,
        descriptor: descriptor,
        domainKey: key.key,
      );
    } finally {
      key.release();
    }
    final sourceContext = CryptoCaptureSourceContext.fromJson(
      _map(witness['context']),
    );
    context.requireSource(sourceContext);
    final source = CryptoMigrationAuditSource.decode(
      sourceContext,
      _map(witness['typedRow']),
    );
    if (source.recordId != context.value['recordId'] ||
        source.legacyRevision != context.value['legacyRevision']) {
      throw const FormatException('crypto_migration_audit_source_identity');
    }
    return {
      ...source.facts,
      'typedRow': source.typedRow,
      'timeBasis': 'legacyServer',
      'sourceEvidenceHash': artifactHash,
      'sourceAuthorization': proof,
      'sourceDescriptor': descriptor,
    };
  }
}
