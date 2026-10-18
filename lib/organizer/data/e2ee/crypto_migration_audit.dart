import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_v3.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_witness.dart';
import 'crypto_migration_witness_transport.dart';
import 'crypto_record_address.dart';

/// Original audit revision and author-claimed legacy timestamp remain distinct
/// from the later crypto revision namespace. JSON strings/unknown cells are not
/// reserialized through a current financial model.
class CryptoMigrationAuditSource {
  CryptoMigrationAuditSource._(this.facts, this.typedRow);
  final Map<String, dynamic> facts, typedRow;
  String get recordId => facts['recordId'];
  int get legacyRevision => facts['revision'];

  static CryptoMigrationAuditSource decode(
    CryptoCaptureSourceContext context,
    Map<String, dynamic> row,
  ) {
    String? text(String key) {
      final cell = row[key];
      if (cell is! Map ||
          cell.length != 2 ||
          !cell.containsKey('valueBase64') ||
          cell['type'] is! String) {
        throw const FormatException('crypto_migration_audit_source');
      }
      return cell['valueBase64'] == null
          ? null
          : utf8.decode(cryptoBase64(cell['valueBase64']));
    }

    final scope = text('scope_id'), id = text('record_id');
    final revision = int.tryParse(text('revision') ?? '');
    if (context.sourceTable != 'familyhub_finance_audit' ||
        context.domain != 'finance' ||
        context.scopeId != scope ||
        !isCryptoCanonicalUuid(id) ||
        revision == null ||
        revision < 1 ||
        revision > 9007199254740991) {
      throw const FormatException('crypto_migration_audit_source');
    }
    return CryptoMigrationAuditSource._(
      Map.unmodifiable({
        'scopeId': scope,
        'recordId': id,
        'revision': revision,
        'revisionNamespace': 'legacy',
        'actorAccountId': text('actor_account_id'),
        'changedAt': text('changed_at'),
        'beforeJson': text('before_json'),
        'afterJson': text('after_json'),
        'opId': text('op_id'),
      }),
      Map.unmodifiable(row),
    );
  }
}

/// Durable producer. Uploading this evidence cannot change an entry or balance.
class CryptoMigrationAudit {
  CryptoMigrationAudit(this.runtime);
  final CryptoBusinessSession runtime;

  Future<Map<String, dynamic>> stageCaptured({
    required CryptoCaptureKeyDescriptor capture,
    required String sourceInventoryRoot,
    required CryptoCaptureBinding binding,
    required Map<String, dynamic> witness,
  }) async {
    final source = CryptoCaptureSourceContext.fromJson(
      Map<String, dynamic>.from(witness['context'] as Map),
    );
    await CryptoCaptureV3.verifyWitness(
      binding: binding,
      context: source,
      witness: witness,
    );
    final audit = CryptoMigrationAuditSource.decode(
      source,
      Map<String, dynamic>.from(witness['typedRow'] as Map),
    );
    final action = 'migrationAudit:${capture.captureId}:${binding.bindingId}';
    final saved = await runtime.db.rows(
      'SELECT o.request_id,o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
      [runtime.partition, action],
    );
    if (saved.isNotEmpty) {
      final proof = jsonDecode(saved.single['signed_body'] as String) as Map;
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final p = command['payload'] as Map;
      if (command['operation'] != 'crypto2.migration.audit.stage' ||
          p['migrationId'] != capture.migrationId ||
          p['captureId'] != capture.captureId ||
          p['sourceInventoryRoot'] != sourceInventoryRoot ||
          p['bindingId'] != binding.bindingId ||
          p['descriptor']['context']['sourceCommitment'] !=
              binding.sourceCommitment) {
        throw const FormatException('crypto_migration_audit_immutable');
      }
      final request = saved.single['request_id'] as String;
      await runtime.queue.resumeUnresolved(requestIds: {request});
      return runtime.queue.commandResult(request);
    }
    if (capture.migrationId != source.migrationId ||
        capture.captureId != source.captureId ||
        runtime.account.directory.accountId != source.accountId) {
      throw const FormatException('crypto_migration_audit_context');
    }
    final candidate = await runtime.access.migrationCandidate(
      scopeId: source.scopeId!,
      migrationId: capture.migrationId,
      captureId: capture.captureId,
    );
    final head = candidate.head;
    final context = CryptoMigrationWitnessContext({
      'version': 3,
      'purpose': 'migrationAudit',
      'serverId': source.serverId,
      'accountId': source.accountId,
      'captureId': source.captureId,
      'migrationId': source.migrationId,
      'bindingId': binding.bindingId,
      'sourceInventoryRoot': sourceInventoryRoot,
      'sourceCommitment': binding.sourceCommitment,
      'scopeId': source.scopeId,
      'domain': 'finance',
      'epoch': head.epoch,
      'accessRevision': head.accessRevision,
      'membershipHeadHash': head.headHash,
      'recordId': audit.recordId,
      'legacyRevision': audit.legacyRevision,
    });
    final key = await candidate.key('finance');
    late Map<String, dynamic> descriptor;
    try {
      final producer = CryptoMigrationWitness(
        database: runtime.db,
        partition: runtime.partition,
        crypto: runtime.codec.crypto,
      );
      descriptor = await producer.stage(
        context: context,
        witness: witness,
        domainKey: key.key,
      );
      await CryptoMigrationWitnessTransport(
        queue: runtime.queue,
        read: runtime.account.directory.call,
      ).upload(producer: producer, context: context, descriptor: descriptor);
    } finally {
      key.release();
    }
    final request = await runtime.queue.enqueueCommand(
      actionKey: action,
      operation: 'crypto2.migration.audit.stage',
      payload: {
        'migrationId': capture.migrationId,
        'captureId': capture.captureId,
        'sourceInventoryRoot': sourceInventoryRoot,
        'bindingId': binding.bindingId,
        'descriptor': descriptor,
        'authorDirectoryHeadHash':
            (await runtime.account.directory.cachedVerifiedDirectory())
                .headHash,
      },
    );
    await runtime.queue.resumeUnresolved(requestIds: {request});
    return runtime.queue.commandResult(request);
  }
}

/// Full audit section of the isolated FILE cold comparison. It cannot be used
/// as the ordinary audit reader before committed domain provenance is verified.
class CryptoMigrationAuditColdControl implements CryptoMigrationColdControl {
  CryptoMigrationAuditColdControl(this.runtime, this.source, this.recoveryFile);
  final CryptoBusinessSession runtime;
  final VerifiedCryptoCaptureArchive source;
  final Uint8List recoveryFile;
  bool _created = false;
  bool _finished = false;
  int _verifiedCount = 0;
  String? _lastVerifiedBinding;
  Map<String, dynamic>? _finishedSection;
  final _scopeSinks = <String, dynamic>{};
  final _scopeCounts = <String, int>{};
  final _scopeSections = <String, Map<String, dynamic>>{};
  dynamic _verifiedGlobal;
  VerifiedAccountDirectory? _prefix;
  Map<String, dynamic> get common => {
    'version': 3,
    'serverId': runtime.account.directory.session.profile.serverId,
    'migrationId': source.capture.migrationId,
    'captureId': source.capture.captureId,
    'accountId': runtime.account.directory.accountId,
    'sourceInventoryRoot': source.sourceInventoryRoot,
  };
  Future<void> _init() async {
    if (_created) return;
    await runtime.db.execute(
      'CREATE TABLE cold_migration_audit(binding_id TEXT PRIMARY KEY,artifact_hash TEXT NOT NULL)',
    );
    final info = runtime.account.files.inspect(
      recoveryFile,
      serverId: common['serverId'],
      accountId: common['accountId'],
    );
    _prefix = await runtime.account.directory.replayFileAnchoredCandidate(
      info['fingerprint'],
    );
    _verifiedGlobal = Sha256().newHashSink();
    _verifiedGlobal.add(utf8.encode('JivieMigrationAuditSelection/v3\n'));
    _verifiedGlobal.add(CryptoInventoryJson.encode(common));
    _verifiedGlobal.add([10]);
    _created = true;
  }

  @override
  Future<String> verify(CryptoMigrationColdSource item) async {
    await _init();
    final original = CryptoMigrationAuditSource.decode(
      item.context,
      item.typedRow,
    );
    final response = await runtime.account.directory
        .call('crypto2.migration.audit.artifact', {
          'migrationId': source.capture.migrationId,
          'captureId': source.capture.captureId,
          'sourceInventoryRoot': source.sourceInventoryRoot,
          'bindingId': item.binding.bindingId,
        });
    final proof = Map<String, dynamic>.from(response['authorization'] as Map);
    final untrusted =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final device = _prefix!.activeDevice(untrusted['deviceId']);
    final command = runtime.codec.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      'JivieE2EE/v2\n',
    );
    final p = command['payload'];
    if (command['version'] != 2 ||
        command['operation'] != 'crypto2.migration.audit.stage' ||
        command['signer'] != 'device' ||
        command['serverId'] != common['serverId'] ||
        command['accountId'] != common['accountId'] ||
        p is! Map ||
        p.length != 6 ||
        p['migrationId'] != common['migrationId'] ||
        p['captureId'] != common['captureId'] ||
        p['sourceInventoryRoot'] != common['sourceInventoryRoot'] ||
        p['bindingId'] != item.binding.bindingId) {
      throw const FormatException('crypto_migration_audit_authorization');
    }
    final descriptor = Map<String, dynamic>.from(p['descriptor'] as Map);
    if (CryptoInventoryJson.canonical(descriptor) !=
        CryptoInventoryJson.canonical(response['descriptor'])) {
      throw const FormatException('crypto_migration_audit_descriptor');
    }
    final context = CryptoMigrationWitnessContext(
      Map<String, dynamic>.from(descriptor['context'] as Map),
    );
    context.requireSource(item.context);
    if (context.value['purpose'] != 'migrationAudit' ||
        context.value['recordId'] != original.recordId ||
        context.value['legacyRevision'] != original.legacyRevision ||
        context.value['sourceInventoryRoot'] != source.sourceInventoryRoot ||
        CryptoInventoryJson.canonical(context.binding.toJson()) !=
            CryptoInventoryJson.canonical(item.binding.toJson())) {
      throw const FormatException('crypto_migration_audit_context');
    }
    // The head coordinate is taken only from the FILE-prefix verified own
    // signature above. It is never accepted from an unsigned status response.
    await runtime.access.withReadOnlyFrozenScope<void>(
      scopeId: item.context.scopeId!,
      candidateHeadHash: context.value['membershipHeadHash'],
      recoveryFile: recoveryFile,
      body: () async {
        await runtime.access.recoverScopeCandidateKeys(
          item.context.scopeId!,
          recoveryFile,
        );
        final producer = CryptoMigrationWitness(
          database: runtime.db,
          partition: runtime.partition,
          crypto: runtime.codec.crypto,
        );
        await CryptoMigrationWitnessTransport(
          queue: runtime.queue,
          read: runtime.account.directory.call,
        ).download(
          consumer: producer,
          context: context,
          descriptor: descriptor,
        );
        final key = await runtime.access.getScopeKey(
          item.context.scopeId!,
          'finance',
          context.value['epoch'],
        );
        try {
          final witness = await producer.open(
            context: context,
            descriptor: descriptor,
            domainKey: key.key,
          );
          if (CryptoInventoryJson.canonical(witness['typedRow']) !=
              CryptoInventoryJson.canonical(item.typedRow)) {
            throw const FormatException('crypto_migration_audit_parity');
          }
          final recovered = CryptoMigrationAuditSource.decode(
            item.context,
            Map<String, dynamic>.from(witness['typedRow'] as Map),
          );
          if (CryptoInventoryJson.canonical(recovered.facts) !=
              CryptoInventoryJson.canonical(original.facts)) {
            throw const FormatException('crypto_migration_audit_parity');
          }
        } finally {
          key.release();
        }
      },
    );
    final hash = await cryptoSha256([
      ...utf8.encode('JivieMigrationAuditArtifact/v3\n'),
      ...CryptoInventoryJson.encode(proof),
    ]);
    if (response['artifactHash'] != hash) {
      throw const FormatException('crypto_migration_audit_artifact');
    }
    if (_finished ||
        _lastVerifiedBinding != null &&
            _lastVerifiedBinding!.compareTo(item.binding.bindingId) >= 0) {
      throw const FormatException('crypto_migration_audit_order');
    }
    await runtime.db.execute(
      'INSERT INTO cold_migration_audit(binding_id,artifact_hash) VALUES(?,?)',
      [item.binding.bindingId, hash],
    );
    final scope = item.context.scopeId!;
    final scoped = _scopeSinks.putIfAbsent(scope, () {
      final sink = Sha256().newHashSink();
      sink.add(utf8.encode('JivieMigrationAuditScopeSelection/v3\n'));
      sink.add(
        CryptoInventoryJson.encode({
          ...common,
          'scopeId': scope,
          'domain': 'finance',
        }),
      );
      sink.add([10]);
      return sink;
    });
    final leaf = CryptoInventoryJson.encode({
      'bindingId': item.binding.bindingId,
      'artifactHash': hash,
    });
    _verifiedGlobal.add(leaf);
    _verifiedGlobal.add([10]);
    scoped.add(leaf);
    scoped.add([10]);
    _scopeCounts[scope] = (_scopeCounts[scope] ?? 0) + 1;
    _lastVerifiedBinding = item.binding.bindingId;
    _verifiedCount++;
    return hash;
  }

  @override
  Future<Map<String, dynamic>> finish() async {
    await _init();
    if (_finishedSection != null) return _finishedSection!;
    final expected =
        (await runtime.db.rows(
              "SELECT COUNT(*) n FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND json_extract(context,'\$.sourceTable')='familyhub_finance_audit'",
              [runtime.partition, source.capture.captureId],
            )).single['n']
            as int;
    final actual =
        (await runtime.db.rows(
              'SELECT COUNT(*) n FROM cold_migration_audit',
            )).single['n']
            as int;
    if (actual != expected || actual != _verifiedCount) {
      throw const FormatException('crypto_migration_audit_coverage');
    }
    final sink = Sha256().newHashSink();
    sink.add(utf8.encode('JivieMigrationAuditSelection/v3\n'));
    sink.add(CryptoInventoryJson.encode(common));
    sink.add([10]);
    String? after;
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT * FROM cold_migration_audit ${after == null ? '' : 'WHERE binding_id>?'} ORDER BY binding_id LIMIT 20',
        [if (after != null) after],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        after = row['binding_id'] as String;
        sink.add(
          CryptoInventoryJson.encode({
            'bindingId': after,
            'artifactHash': row['artifact_hash'],
          }),
        );
        sink.add([10]);
      }
    }
    sink.close();
    final root = (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _verifiedGlobal.close();
    final verifiedRoot = (await _verifiedGlobal.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (root != verifiedRoot)
      throw const FormatException('crypto_migration_audit_coverage');
    for (final entry in _scopeSinks.entries) {
      entry.value.close();
      final digest = (await entry.value.hash()).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      _scopeSections[entry.key] = Map.unmodifiable({
        'kind': 'audit',
        'count': _scopeCounts[entry.key],
        'root': digest,
      });
    }
    _scopeSinks.clear();
    _finished = true;
    return _finishedSection = Map.unmodifiable({
      'kind': 'audit',
      'count': actual,
      'root': root,
    });
  }

  /// Domain is always finance, independently of the carrier contribution.
  /// Empty is established only after the complete FILE source scan finishes.
  Future<Map<String, dynamic>> scopedSection(String scopeId) async {
    if (!_finished ||
        !(source.capture.scopeIds.contains(scopeId) ||
            source.capture.receiptSelections.any(
              (r) => r['scopeId'] == scopeId,
            ))) {
      throw const FormatException('crypto_migration_audit_scope_coverage');
    }
    final known = _scopeSections[scopeId];
    if (known != null) return known;
    final root = await cryptoSha256(
      utf8.encode('JivieMigrationAuditScopeSelection/v3\n') +
          CryptoInventoryJson.encode({
            ...common,
            'scopeId': scopeId,
            'domain': 'finance',
          }) +
          [10],
    );
    return Map.unmodifiable({'kind': 'audit', 'count': 0, 'root': root});
  }
}
