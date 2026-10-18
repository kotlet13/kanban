import 'crypto_anchor_lock.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart';
import 'crypto_backup_evidence.dart';
import 'crypto_backup_command_codec.dart';
import 'crypto_document_backup_drafts.dart';
import 'crypto_document_backup_recovery.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_restore_evidence_store.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';
import 'crypto_record_address.dart';
import 'crypto_document_blob.dart';
import 'recovery_file_codec.dart';
import 'package:sodium/sodium.dart' show SecureKey;

class RecoveredCryptoDocumentDraft {
  RecoveredCryptoDocumentDraft(
    this.backupId,
    this.objectId,
    this.kind,
    this.bytes,
  );
  final String backupId, objectId, kind;
  final Uint8List bytes;
  void dispose() => bytes.fillRange(0, bytes.length, 0);
}

class CryptoRestoreReport {
  const CryptoRestoreReport({
    required this.backupCount,
    required this.directoryCount,
    required this.scopeCount,
    required this.recordCount,
    required this.unconfirmedHistoryCount,
    required this.identityReviewAccounts,
    required this.historyReviewScopes,
  });
  final int backupCount,
      directoryCount,
      scopeCount,
      recordCount,
      unconfirmedHistoryCount;
  final List<String> identityReviewAccounts, historyReviewScopes;
  bool get canReconcile =>
      identityReviewAccounts.isEmpty && historyReviewScopes.isEmpty;
}

/// Import order and unsigned backup flags never determine trust. Verification
/// uses a detached graph of every retained candidate, with independently pinned
/// account identities. Imported requests remain quarantined and never deliver.
class CryptoRestoreReconciler {
  CryptoRestoreReconciler(this.account);
  final AccountCryptoV2Workflow account;
  CryptoRestoreEvidenceStore get store => CryptoRestoreEvidenceStore(
    account.store.database,
    account.store.partition,
  );
  final _rows = <String, List<Map<String, dynamic>>>{};
  final _directories = <String, Map<String, VerifiedAccountDirectory>>{};
  final _directoryEntries = <String, List<Map<String, dynamic>>>{};
  final _heads = <String, VerifiedScopeHead>{};
  final _wires = <String, Map<String, dynamic>>{};
  final _trustedAccounts = <String>{};
  final _trustedScopes = <String>{};
  final _trustedHeadHashes = <String>{};
  final _historyPending = <String>{};
  final _codecs = <String, CryptoBackupCommandCodec>{};
  final _privateSets = <String, Map<String, dynamic>>{};
  final _scopeFloors = <String, VerifiedScopeHead>{};
  final _closures = <String, Map<String, dynamic>>{};
  final _recordAnchors = <String, Map<String, dynamic>>{};
  final _checkpoints = <Map<String, dynamic>>[];
  int _unconfirmedHistory = 0;
  final _priorAnchors = <String, String?>{};
  CryptoRestoreEvidenceSnapshot? _snapshot;
  String? _identity;
  Object? _cell(Object? value) =>
      value is Map && value.length == 1 && value['blobBase64'] is String
      ? Uint8List.fromList(base64Decode(value['blobBase64']))
      : value;
  Map<String, dynamic> _json(Object? value) {
    final text = value is List
        ? utf8.decode(value.cast<int>())
        : value as String;
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('restore_proof_shape');
    return Map<String, dynamic>.from(decoded);
  }

  String _fingerprint(VerifiedAccountDirectory state) =>
      account.directory.reducer.crypto.fingerprint(
        cryptoBase64(state.snapshot['rootSigningKeyBase64'], length: 32),
        cryptoBase64(state.snapshot['rootEncryptionKeyBase64'], length: 32),
      );
  void _current() {
    if (!account.directory.isCurrent() ||
        _identity != '${account.store.partition}:${account.deviceId}')
      throw const CryptoAuthorityPending('restore_identity_changed');
  }

  void _addEvidence(
    Object? evidence,
    Set<String> seen,
    String backupId, [
    int depth = 0,
  ]) {
    if (depth > 16) throw const FormatException('restore_evidence_depth');
    validateCryptoEvidence(evidence, account.store.partition);
    final key = CryptoInventoryJson.canonical(evidence);
    if (!seen.add(key)) return;
    final tables = (evidence as Map)['tables'] as Map;
    for (final table in cryptoEvidenceTables.keys) {
      for (final raw in tables[table] as List) {
        final row = <String, dynamic>{
          for (final cell in (raw as Map).entries)
            cell.key as String: _cell(cell.value),
        };
        if (table == 'crypto_restore_evidence') {
          _addEvidence(
            jsonDecode(row['evidence'] as String),
            seen,
            row['backup_id'],
            depth + 1,
          );
        } else {
          row['_backupId'] = backupId;
          (_rows[table] ??= []).add(row);
        }
      }
    }
  }

  Future<CryptoRestoreReport> inspect() async {
    _identity = '${account.store.partition}:${account.deviceId}';
    _current();
    final own = await account.directory.requireFresh();
    _current();
    _snapshot = await store.snapshot();
    _rows.clear();
    _directories.clear();
    _directoryEntries.clear();
    _heads.clear();
    _wires.clear();
    _trustedAccounts.clear();
    _trustedScopes.clear();
    _trustedHeadHashes.clear();
    _historyPending.clear();
    _scopeFloors.clear();
    _closures.clear();
    _recordAnchors.clear();
    _checkpoints.clear();
    _unconfirmedHistory = 0;
    _priorAnchors.clear();
    _codecs.clear();
    _privateSets.clear();
    final seen = <String>{};
    for (final retained in await account.store.database.rows(
      'SELECT id,data FROM restored_backups',
    )) {
      final data = jsonDecode(retained['data'] as String) as Map;
      final drafts = data['cryptoPrivateDrafts'];
      if (drafts is Map) {
        validateCryptoDocumentDrafts(drafts, drafts['partition'] as String?);
        final codec = CryptoBackupCommandCodec(
          Map<String, dynamic>.from(drafts),
          drafts['partition'] as String?,
        );
        _codecs[retained['id'] as String] = codec;
        _privateSets[retained['id'] as String] = Map<String, dynamic>.from(
          drafts['tables'] as Map,
        );
        for (final child in drafts['restoredCandidates'] as List? ?? const []) {
          _codecs[child['backupId']] = codec.forRestoredBackup(
            child['backupId'],
          );
          _privateSets[child['backupId']] = Map<String, dynamic>.from(
            child['tables'] as Map,
          );
        }
      }
    }
    for (final candidate in _snapshot!.candidates) {
      _addEvidence(candidate['evidence'], seen, candidate['backupId']);
    }
    final accountIds = <String>{
      own.accountId,
      for (final r in _rows['crypto_directory_entries'] ?? [])
        r['account_id'] as String,
      for (final r in _rows['crypto_restore_scoped_directories'] ?? [])
        r['account_id'] as String,
    };
    final reviewAccounts = <String>{};
    for (final id in accountIds) {
      final union = <int, Map<String, dynamic>>{};
      void add(Map<String, dynamic> entry) {
        final old = union[entry['generation']];
        if (old != null &&
            CryptoInventoryJson.canonical(old) !=
                CryptoInventoryJson.canonical(entry))
          throw const FormatException('restore_directory_fork');
        union[entry['generation']] = entry;
      }

      for (final entry in await account.store.entries(id)) {
        add(entry);
      }
      for (final row in _rows['crypto_directory_entries'] ?? []) {
        if (row['account_id'] != id) continue;
        add({
          'generation': row['generation'],
          'headHash': row['head_hash'],
          'previousHeadHash': row['previous_head_hash'],
          'commandHash': row['command_hash'],
          'authorization': _json(row['authorization']),
        });
      }
      for (final scoped in _rows['crypto_restore_scoped_directories'] ?? []) {
        if (scoped['account_id'] != id) continue;
        final prefix =
            CryptoJson.decode(
                  Uint8List.fromList((scoped['entries'] as List).cast<int>()),
                  limit: (scoped['entries'] as List).length,
                )
                as List;
        for (final entry in prefix) {
          add(Map<String, dynamic>.from(entry as Map));
        }
      }
      if (union.isEmpty)
        throw const FormatException('restore_directory_missing');
      final entries = union.values.toList()
        ..sort(
          (a, b) => (a['generation'] as int).compareTo(b['generation'] as int),
        );
      final first =
          CryptoJson.decode(
                cryptoBase64(entries.first['authorization']['commandBase64']),
              )
              as Map;
      final genesis = account.directory.reducer.crypto.fingerprint(
        cryptoBase64(first['payload']['rootSigningKeyBase64'], length: 32),
        cryptoBase64(first['payload']['rootEncryptionKeyBase64'], length: 32),
      );
      VerifiedAccountDirectory? state;
      final states = <String, VerifiedAccountDirectory>{};
      for (final entry in entries) {
        state = await account.directory.reducer.apply(
          previous: state,
          entry: entry,
          serverId: own.serverId,
          accountId: id,
          pinnedRootFingerprint: genesis,
        );
        states[state.headHash] = state;
      }
      _directories[id] = states;
      _directoryEntries[id] = entries;
      final prior = await account.store.secure.read(
        'directory2:${account.store.partition}:$id',
      );
      _priorAnchors['directory2:${account.store.partition}:$id'] = prior;
      final anchor = prior == null ? null : jsonDecode(prior) as Map;
      if (anchor != null &&
          anchor['generation'] is int &&
          (anchor['generation'] as int) > 0) {
        final exact = states[anchor['headHash']];
        if (exact == null ||
            exact.generation != anchor['generation'] ||
            exact.snapshotHash != anchor['snapshotHash'])
          throw const FormatException('restore_known_directory_fork');
        if (_fingerprint(state!) == anchor['fingerprint']) {
          _trustedAccounts.add(id);
        } else {
          reviewAccounts.add(id);
        }
      } else {
        reviewAccounts.add(id);
      }
      for (final pin in _rows['crypto_directory_pins'] ?? []) {
        if (pin['account_id'] != id) continue;
        final exact = states[pin['head_hash']];
        if (exact == null ||
            exact.generation != pin['min_generation'] ||
            exact.snapshotHash != pin['snapshot_hash'] ||
            exact.deviceSnapshotHash != pin['device_snapshot_hash'] ||
            exact.identityEpochId != pin['identity_epoch_id'])
          throw const FormatException('restore_unsigned_directory_floor');
      }
      for (final snapshot in _rows['crypto_directory_snapshots'] ?? []) {
        if (snapshot['account_id'] != id) continue;
        final exact = states[snapshot['head_hash']];
        if (exact == null ||
            CryptoInventoryJson.canonical(_json(snapshot['snapshot'])) !=
                CryptoInventoryJson.canonical(exact.snapshot))
          throw const FormatException('restore_directory_snapshot');
      }
    }
    for (final row in _rows['crypto_scope_heads'] ?? []) {
      final wire = _json(row['authorization']);
      if (wire['scopeId'] != row['scope_id'] ||
          wire['headHash'] != row['head_hash'] ||
          CryptoInventoryJson.canonical(wire['payload']) !=
              CryptoInventoryJson.canonical(_json(row['body'])))
        throw const FormatException('restore_scope_row');
      final old = _wires[row['head_hash']];
      if (old != null &&
          CryptoInventoryJson.canonical(old) !=
              CryptoInventoryJson.canonical(wire))
        throw const FormatException('restore_scope_fork');
      _wires[row['head_hash']] = wire;
    }
    final codec = ScopeCryptoCodec(account.directory.reducer.crypto);
    final visiting = <String>{};
    final policyVersions = <String, int?>{};
    Future<VerifiedScopeHead> verifyHead(String hash) async {
      if (_heads.containsKey(hash)) return _heads[hash]!;
      final wire = _wires[hash];
      if (wire == null || !visiting.add(hash))
        throw const FormatException('restore_scope_prefix');
      final body = Map<String, dynamic>.from(wire['payload'] as Map);
      final baseline = wire['initialLifecycleBaseline'];
      final origin = wire['originAuthorization'];
      if (baseline is! Map ||
          baseline.length != 6 ||
          baseline['version'] != 2 ||
          baseline['scopeId'] != body['scopeId'] ||
          origin is! Map ||
          await cryptoSha256(
                utf8.encode('JivieLifecycleBaseline/v2\n') +
                    CryptoJson.encode(baseline),
              ) !=
              body['initialLifecycleHash'] ||
          await cryptoSha256(CryptoJson.encode(origin)) !=
              baseline['originProofHash'])
        throw const FormatException('restore_lifecycle_baseline');
      final originRaw =
          CryptoJson.decode(cryptoBase64(origin['commandBase64'])) as Map;
      final isNew = originRaw['operation'] == 'crypto2.scope.origin';
      final originPayload = isNew ? originRaw : originRaw['payload'] as Map;
      if (originRaw['serverId'] != own.serverId ||
          originRaw['version'] != 2 ||
          (!isNew && originRaw['signer'] != 'device') ||
          originPayload['scopeId'] != body['scopeId'] ||
          (isNew ? 'new' : 'legacy') != baseline['originKind'] ||
          (!isNew && originRaw['operation'] != 'crypto2.scope.prepare') ||
          (isNew &&
              (baseline['ownArchived'] != false ||
                  baseline['inheritedArchived'] != false)))
        throw const FormatException('restore_lifecycle_origin');
      if (isNew) {
        const fields = {
          'version',
          'operation',
          'serverId',
          'scopeId',
          'kind',
          'accessPolicyVersion',
          'parentScopeToken',
          'requestId',
          'accountId',
          'deviceId',
          'authorDirectoryHeadHash',
        };
        if (originRaw.length != fields.length ||
            originRaw.keys.any((k) => !fields.contains(k)) ||
            !const [
              'personal',
              'household',
              'organization',
              'project',
            ].contains(originRaw['kind']) ||
            originRaw['accessPolicyVersion'] !=
                (originRaw['kind'] == 'personal' ? 1 : 3) ||
            originRaw['authorDirectoryHeadHash'] !=
                wire['originAuthorDirectoryHeadHash'] ||
            originRaw['parentScopeToken'] != null &&
                (originRaw['kind'] != 'project' ||
                    originRaw['parentScopeToken'] is! String ||
                    !RegExp(
                      r'^[a-f0-9]{64}$',
                    ).hasMatch(originRaw['parentScopeToken']))) {
          throw const FormatException('restore_public_scope_origin');
        }
      }
      final originDirectory = _directory(
        originRaw['accountId'],
        wire['originAuthorDirectoryHeadHash'],
      );
      account.directory.reducer.crypto.verifyDomain(
        Map<String, dynamic>.from(origin),
        cryptoBase64(
          originDirectory.activeDevice(
            originRaw['deviceId'],
          )['signingKeyBase64'],
          length: 32,
        ),
        isNew ? 'JivieE2EE/scopeOrigin/v2\n' : cryptoDirectoryDomain,
      );

      final previous = body['epoch'] == 1
          ? null
          : await verifyHead(body['previousHeadHash']);
      final command =
          CryptoJson.decode(
                cryptoBase64(wire['authorization']['commandBase64']),
              )
              as Map;
      final author = _directory(
        command['accountId'],
        body['authorDirectoryHeadHash'],
      );
      final pending = await codec.verifyProposal(
        accessPolicyVersion: previous == null
            ? (isNew ? originRaw['accessPolicyVersion'] as int : null)
            : policyVersions[previous.headHash],
        serverId: own.serverId,
        authorization: Map<String, dynamic>.from(wire['authorization'] as Map),
        previous: previous,
        authorDirectory: author,
        directoryAtHead: (id, head) async => _directory(id, head),
        checkIdentity: (id, fp) async {},
      );
      if (pending.headHash != hash)
        throw const FormatException('restore_scope_hash');
      VerifiedScopeHead result = pending;
      if (wire['state'] == 'active' || wire['state'] == 'historical') {
        final proof = Map<String, dynamic>.from(
          wire['activationAuthorization'] as Map,
        );
        final activation =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        final activationAuthor = _directory(
          activation['accountId'],
          activation['payload']['authorDirectoryHeadHash'],
        );
        result = await codec.verifyActivation(
          pending: pending,
          previous: previous,
          authorization: proof,
          authorDirectory: activationAuthor,
          grantManifestHash: activation['payload']['grantManifestHash'],
          directoryAtHead: (id, head) async => _directory(id, head),
        );
        if (_currentDevice(activationAuthor, activation['deviceId'])) {
          _trustedScopes.add(result.scopeId);
          _trustedHeadHashes.add(result.headHash);
        }
      }
      if (_currentDevice(author, command['deviceId'])) {
        _trustedScopes.add(result.scopeId);
        _trustedHeadHashes.add(result.headHash);
      }
      _heads[hash] = result;
      final accessConsent = body['accessIntentProof'];
      policyVersions[hash] = accessConsent is Map
          ? (CryptoJson.decode(cryptoBase64(accessConsent['commandBase64']))
                    as Map)['resultingDescriptor']['accessPolicyVersion']
                as int
          : (previous == null
                ? (isNew ? originRaw['accessPolicyVersion'] as int : null)
                : policyVersions[previous.headHash]);
      visiting.remove(hash);
      return result;
    }

    for (final hash in _wires.keys) {
      await verifyHead(hash);
    }
    for (final scope in _heads.values.map((h) => h.scopeId).toSet()) {
      final active =
          _heads.values.where((h) => h.scopeId == scope && h.active).toList()
            ..sort((a, b) => a.epoch.compareTo(b.epoch));
      if (active.isEmpty) continue;
      final newest = active.last;
      for (final candidate in active) {
        var cursor = newest;
        while (cursor.epoch > candidate.epoch) {
          cursor = _heads[cursor.body['previousHeadHash']]!;
        }
        if (cursor.headHash != candidate.headHash)
          throw const FormatException('restore_scope_fork');
      }
      final key = 'scope2:${account.store.partition}:$scope';
      final old = await account.store.secure.read(key);
      _priorAnchors[key] = old;
      if (old != null) {
        final floor = jsonDecode(old) as Map;
        final exact = _heads[floor['headHash']];
        if (exact == null ||
            exact.scopeId != scope ||
            exact.epoch != floor['epoch'])
          throw const FormatException('restore_known_scope_fork');
        _trustedScopes.add(scope);
        _trustedHeadHashes.add(exact.headHash);
      }
      if (_trustedScopes.contains(scope) &&
          _trustedHeadHashes.contains(newest.headHash)) {
        _scopeFloors[scope] = newest;
      } else {
        _historyPending.add(scope);
      }
    }
    final reviewScopes = _heads.values
        .map((h) => h.scopeId)
        .where((id) => !_trustedScopes.contains(id))
        .toSet();
    // Unpinned identities inside an exact authenticated scoped chain remain
    // scoped historical evidence; they never become global contact pins.
    reviewAccounts.removeWhere(
      (id) => _heads.values.any(
        (h) =>
            _trustedScopes.contains(h.scopeId) &&
            h.members.any((m) => m['accountId'] == id),
      ),
    );
    for (final row
        in _rows['crypto_business_addresses'] ??
            const <Map<String, dynamic>>[]) {
      final address = CryptoRecordAddress.forType(
        serverId: own.serverId,
        scopeId: row['scope_id'],
        domain: row['domain'],
        type: row['type'],
        canonicalId: row['canonical_id'],
      );
      if (address.sourceKind != row['source_kind'] ||
          address.wireId != row['wire_id'])
        throw const FormatException('restore_record_address');
    }
    await _verifyClosures();
    final records = await _verifyRecords();
    await _verifyCheckpoints();
    await _verifyRequests();
    reviewScopes.addAll(_historyPending);
    _current();
    return CryptoRestoreReport(
      backupCount: _snapshot!.candidates.length,
      directoryCount: _directories.length,
      scopeCount: _heads.values.map((h) => h.scopeId).toSet().length,
      recordCount: records,
      unconfirmedHistoryCount: _unconfirmedHistory,
      identityReviewAccounts: List.unmodifiable(
        reviewAccounts.toList()..sort(),
      ),
      historyReviewScopes: List.unmodifiable(reviewScopes.toList()..sort()),
    );
  }

  VerifiedAccountDirectory _directory(String id, String hash) {
    final found = _directories[id]?[hash];
    if (found == null)
      throw const FormatException('restore_author_directory_missing');
    return found;
  }

  bool _currentDevice(VerifiedAccountDirectory reference, String device) {
    if (!_trustedAccounts.contains(reference.accountId)) return false;
    final current = _directories[reference.accountId]!.values.last;
    try {
      current.activeDevice(device);
    } catch (_) {
      return false;
    }
    return current.deviceSnapshotHash == reference.deviceSnapshotHash;
  }

  Future<void> _verifyClosures() async {
    for (final row in _rows['crypto_scope_closures'] ?? []) {
      final proof = _json(row['authorization']);
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final p = command['payload'] as Map;
      final candidate = _heads[row['candidate_head_hash']];
      if (candidate == null ||
          command['operation'] != 'crypto2.scope.closeDomain' ||
          p['scopeId'] != row['scope_id'] ||
          p['candidateHeadHash'] != candidate.headHash ||
          p['domain'] != row['domain'] ||
          p['epoch'] != row['epoch'] ||
          p['manifestHash'] != row['manifest_hash'] ||
          p['historyBasis'] != row['history_basis'])
        throw const FormatException('restore_closure_binding');
      final source = _heads[p['membershipHeadHash']];
      if (source == null ||
          source.scopeId != candidate.scopeId ||
          source.epoch != p['epoch'] ||
          candidate.body['previousHeadHash'] != source.headHash ||
          candidate.body['closures'][p['domain']] != p['manifestHash'])
        throw const FormatException('restore_closure_head');
      final author = _directory(
        command['accountId'],
        p['authorDirectoryHeadHash'],
      );
      final member = source.member(author.accountId);
      if (p['domain'] == 'finance'
          ? member['financeRole'] == 'none'
          : member['manageKeys'] != true)
        throw const FormatException('restore_closure_role');
      final device = author.activeDevice(command['deviceId']);
      account.directory.reducer.crypto.verifyDomain(
        proof,
        cryptoBase64(device['signingKeyBase64'], length: 32),
        cryptoDirectoryDomain,
      );
      final descriptors =
          (jsonDecode(utf8.decode((row['descriptors'] as List).cast<int>()))
                  as List)
              .cast<Map<String, dynamic>>();
      if (descriptors.length != p['recordCount'] ||
          descriptors.any(
            (d) =>
                d['sequence'] is! int ||
                (d['sequence'] as int) > p['expectedSequence'],
          ) ||
          await ScopeCryptoCodec(
                account.directory.reducer.crypto,
              ).closureManifestHash(descriptors) !=
              p['manifestHash']) {
        throw const FormatException('restore_closure_manifest');
      }
      if (_trustedHeadHashes.contains(candidate.headHash)) {
        for (final descriptor in descriptors) {
          _closures['${candidate.scopeId}:${p['domain']}:${descriptor['id']}:${descriptor['revision']}:${descriptor['recordProofHash']}'] =
              {...descriptor, 'historyBasis': p['historyBasis']};
        }
      }
    }
  }

  Future<int> _verifyRecords() async {
    var count = 0;
    final codec = CryptoRecordProofCodec(account.directory.reducer.crypto);
    for (final table in [
      'crypto_received',
      'crypto_business_history_proofs',
      'crypto_restore_record_anchors',
    ]) {
      for (final row in _rows[table] ?? const <Map<String, dynamic>>[]) {
        final wire = _json(row['wire']);
        final record = Map<String, dynamic>.from(
          CryptoJson.decode(
                cryptoBase64(
                  wire['authorization']['recordProof']['commandBase64'],
                ),
              )
              as Map,
        );
        codec.validateUntrustedRecord(record);
        if (row['scope_id'] != record['scopeId'] ||
            row['domain'] != record['domain'] ||
            row['record_id'] != record['id'] ||
            row['revision'] != wire['revision'])
          throw const FormatException('restore_record_coordinate');

        final head = _heads[record['membershipHeadHash']];
        if (head == null ||
            head.scopeId != record['scopeId'] ||
            head.epoch != record['epoch'] ||
            head.accessRevision != record['accessRevision'])
          throw const FormatException('restore_record_head');
        final member = head.member(record['accountId']);
        if (member['role'] == 'viewer' ||
            record['domain'] == 'finance' && member['financeRole'] != 'write')
          throw const FormatException('restore_record_role');
        final author = _directory(
          record['accountId'],
          member['directoryHeadHash'],
        );
        final device = author.activeDevice(record['deviceId']);
        // Signature validity preserves the candidate; timing/current authority
        // additionally requires a current authenticated head or exact closure.
        await codec.verifyWire(
          serverId: account.directory.session.profile.serverId,
          wire: wire,
          trustedSigningKey: cryptoBase64(
            device['signingKeyBase64'],
            length: 32,
          ),
          currentEpoch: true,
        );
        final digest = await codec.digest(
          Map<String, dynamic>.from(
            wire['authorization']['recordProof'] as Map,
          ),
        );
        if (row['proof_hash'] != null && row['proof_hash'] != digest)
          throw const FormatException('restore_record_hash');
        var current = _scopeFloors[head.scopeId]?.headHash == head.headHash;
        for (final m in head.members) {
          final known = _directories[m['accountId']]?.values.last;
          if (known == null ||
              known.deviceSnapshotHash != m['deviceSnapshotHash'])
            current = false;
        }
        final closure =
            _closures['${head.scopeId}:${record['domain']}:${record['id']}:${wire['revision']}:$digest'];
        if (current || closure != null) {
          final key = '${head.scopeId}:${record['domain']}:${record['id']}';
          final old = _recordAnchors[key];
          if (old != null &&
              old['revision'] == wire['revision'] &&
              old['proof_hash'] != digest)
            throw const FormatException('restore_record_equivocation');
          if (old == null || old['revision'] < wire['revision'])
            _recordAnchors[key] = {
              'partition': account.store.partition,
              'scope_id': head.scopeId,
              'domain': record['domain'],
              'record_id': record['id'],
              'revision': wire['revision'],
              'proof_hash': digest,
              'wire': jsonEncode(wire),
            };
        }
        if (!current && closure == null) {
          _unconfirmedHistory++;
          if (table == 'crypto_received' &&
              row['verdict'] != 'quarantined' &&
              row['verdict'] != 'superseded')
            _historyPending.add(head.scopeId);
        }
        count++;
      }
    }
    for (final floor
        in _rows['crypto_scope_state'] ?? const <Map<String, dynamic>>[]) {
      final proven = _scopeFloors[floor['scope_id']];
      if (proven == null ||
          (floor['epoch'] as int) > proven.epoch ||
          (floor['floor'] as int) > proven.epoch ||
          (floor['access_revision'] as int) > proven.accessRevision) {
        _historyPending.add(floor['scope_id']);
      }
    }
    return count;
  }

  Future<void> _verifyCheckpoints() async {
    final coordinates = <String, String>{};
    for (final row
        in _rows['crypto_domain_checkpoints'] ??
            const <Map<String, dynamic>>[]) {
      final proof = _json(row['authorization']);
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final p = command['payload'] as Map;
      const fields = {
        'scopeId',
        'domain',
        'epoch',
        'membershipHeadHash',
        'accessRevision',
        'expectedSequence',
        'recordCount',
        'manifestHash',
        'historyBasis',
        'authorDirectoryHeadHash',
      };
      if (command.length != 8 ||
          command['version'] != 2 ||
          command['signer'] != 'device' ||
          command['operation'] != 'crypto2.domain.checkpoint' ||
          command['serverId'] != account.directory.session.profile.serverId ||
          p.length != fields.length ||
          p.keys.any((k) => !fields.contains(k)) ||
          p['scopeId'] != row['scope_id'] ||
          p['domain'] != row['domain'] ||
          p['epoch'] != row['epoch'] ||
          p['membershipHeadHash'] != row['head_hash'] ||
          p['accessRevision'] != row['access_revision'] ||
          p['expectedSequence'] != row['sequence'] ||
          p['recordCount'] != row['record_count'] ||
          p['manifestHash'] != row['manifest_hash'] ||
          p['historyBasis'] != row['history_basis'] ||
          ![
            'verifiedCheckpoint',
            'reviewedRecoveryBaseline',
          ].contains(p['historyBasis']))
        throw const FormatException('restore_checkpoint_binding');
      final head = _heads[row['head_hash']];
      if (head == null ||
          head.scopeId != row['scope_id'] ||
          head.epoch != row['epoch'] ||
          head.accessRevision != row['access_revision'])
        throw const FormatException('restore_checkpoint_head');
      final author = _directory(
        command['accountId'],
        p['authorDirectoryHeadHash'],
      );
      final member = head.member(author.accountId);
      if (member['role'] == 'viewer' ||
          row['domain'] == 'finance' && member['financeRole'] == 'none')
        throw const FormatException('restore_checkpoint_role');
      account.directory.reducer.crypto.verifyDomain(
        proof,
        cryptoBase64(
          author.activeDevice(command['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        cryptoDirectoryDomain,
      );
      final descriptors = [
        for (final d in _rows['crypto_domain_inventory_rows'] ?? [])
          if (d['snapshot_id'] == row['snapshot_id'])
            {
              'id': d['record_id'],
              'revision': d['revision'],
              'recordProofHash': d['proof_hash'],
              'sequence': d['sequence'],
              'recordEpoch': d['record_epoch'],
            },
      ]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      if (descriptors.length != row['record_count'] ||
          await ScopeCryptoCodec(
                account.directory.reducer.crypto,
              ).closureManifestHash(descriptors) !=
              row['manifest_hash'] ||
          descriptors.any(
            (d) =>
                (d['sequence'] as int) > row['sequence'] ||
                (d['recordEpoch'] as int) > head.epoch,
          ))
        throw const FormatException('restore_checkpoint_inventory');
      final coordinate =
          '${head.scopeId}:${row['domain']}:${head.headHash}:${row['sequence']}';
      final root = '${row['manifest_hash']}:${row['record_count']}';
      if (coordinates.containsKey(coordinate) &&
          coordinates[coordinate] != root)
        throw const FormatException('restore_checkpoint_fork');
      coordinates[coordinate] = root;
      if (!_trustedHeadHashes.contains(head.headHash) ||
          !_currentDevice(author, command['deviceId'])) {
        _historyPending.add(head.scopeId);
      } else {
        _checkpoints.add(row);
      }
    }
    for (final job in _rows['crypto_business_history_jobs'] ?? []) {
      final exact = (_rows['crypto_business_history_proofs'] ?? []).any(
        (r) =>
            r['scope_id'] == job['scope_id'] &&
            r['domain'] == job['domain'] &&
            r['record_id'] == job['record_id'] &&
            r['revision'] == job['target_revision'] &&
            r['proof_hash'] == job['target_hash'],
      );
      if (!exact) _historyPending.add(job['scope_id']);
    }
  }

  Future<void> _verifyRequests() async {
    for (final row in _rows['crypto_identity_requests'] ?? []) {
      final proof = _json(row['authorization']);
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final p = command['payload'] as Map;
      if (command['accountId'] != account.directory.accountId ||
          command['serverId'] != account.directory.session.profile.serverId ||
          command['requestId'] != row['request_id'] ||
          command['operation'] != row['operation'])
        throw const FormatException('restore_request_identity');
      final hash = await cryptoSha256(cryptoBase64(proof['commandBase64']));
      final included = _directoryEntries[command['accountId']]!.any(
        (e) =>
            e['commandHash'] == hash &&
            CryptoInventoryJson.canonical(e['authorization']) ==
                CryptoInventoryJson.canonical(proof),
      );
      if (row['stage'] == 'confirmed' && !included)
        throw const FormatException('restore_request_receipt_missing');
      if (!included) {
        final previous = p['previousHeadHash'] == cryptoZeroHash
            ? null
            : _directory(command['accountId'], p['previousHeadHash']);
        final head = await cryptoSha256(
          utf8.encode(cryptoDirectoryLogDomain) +
              CryptoJson.encode({
                'serverId': command['serverId'],
                'accountId': command['accountId'],
                'generation': p['expectedGeneration'] + 1,
                'previousHeadHash': p['previousHeadHash'],
                'commandHash': hash,
                'signatureBase64': proof['signatureBase64'],
              }),
        );
        final first =
            CryptoJson.decode(
                  cryptoBase64(
                    _directoryEntries[command['accountId']]!
                        .first['authorization']['commandBase64'],
                  ),
                )
                as Map;
        final genesis = account.directory.reducer.crypto.fingerprint(
          cryptoBase64(first['payload']['rootSigningKeyBase64'], length: 32),
          cryptoBase64(first['payload']['rootEncryptionKeyBase64'], length: 32),
        );
        await account.directory.reducer.apply(
          previous: previous,
          entry: {
            'generation': p['expectedGeneration'] + 1,
            'previousHeadHash': p['previousHeadHash'],
            'commandHash': hash,
            'headHash': head,
            'authorization': proof,
          },
          serverId: command['serverId'],
          accountId: command['accountId'],
          pinnedRootFingerprint: genesis,
        );
      }
      if (row['receipt'] != null)
        _receipt(_json(row['receipt']), proof, hash, row['request_id']);
    }
    for (final row in _rows['crypto_outbox'] ?? []) {
      final codec = _codecs[row['_backupId']];
      var body = row['signed_body'] as String;
      var response = row['response'] as String?;
      if (codec != null) {
        body = await codec.expandSigned(body, requestHash: row['request_hash']);
        response = await codec.expandReceipt(
          response,
          requestHash: row['request_hash'],
        );
      } else if (body.startsWith('JIVIE_BACKUP_') ||
          response?.startsWith('JIVIE_BACKUP_') == true) {
        throw const CryptoAuthorityPending(
          'restore_original_container_required',
        );
      }
      final proof = _json(body);
      await _verifyIntent(proof);
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final hash = await cryptoSha256(cryptoBase64(proof['commandBase64']));
      if (command['requestId'] != row['request_id'] ||
          command['operation'] != row['operation'] ||
          hash != row['request_hash'])
        throw const FormatException('restore_outbox_identity');
      if (response != null)
        _receipt(_json(response), proof, hash, row['request_id']);
    }
    for (final row in _rows['crypto_scope_key_grants'] ?? []) {
      final grant = _json(row['grant']);
      if (grant['commandBase64'] != null) {
        await _verifyIntent(grant);
        final command =
            CryptoJson.decode(cryptoBase64(grant['commandBase64'])) as Map;
        final context = command['context'];
        if (command['operation'] != 'crypto2.localScopeKeyIntent' ||
            context is! Map ||
            context['scopeId'] != row['scope_id'] ||
            context['domain'] != row['domain'] ||
            context['keyId'] != row['key_id'] ||
            context['serverId'] != account.directory.session.profile.serverId ||
            context['accountId'] != account.directory.accountId)
          throw const FormatException('restore_local_key_binding');
      }
    }
    for (final row in _rows['crypto_membership_intents'] ?? []) {
      if (row['authorization'] == null) continue;
      final proof = _json(row['authorization']);
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      if (command['purpose'] == 'unavailableRetainedScopes') {
        final current = _directories[command['accountId']]?.values.last;
        if (current == null)
          throw const FormatException('restore_review_identity');
        final device = current.devices.singleWhere(
          (d) => d['deviceId'] == command['deviceId'],
        );
        account.directory.reducer.crypto.verifyDomain(
          proof,
          cryptoBase64(device['signingKeyBase64'], length: 32),
          'JivieE2EE/unavailableScopes/v2\n',
        );
      } else {
        await _verifyIntent(proof);
      }
    }
  }

  void _receipt(Map receipt, Map proof, String hash, String requestId) {
    if (receipt['requestId'] != requestId ||
        receipt['requestHash'] != hash ||
        receipt['status'] is! int ||
        CryptoInventoryJson.canonical(receipt['authorization']) !=
            CryptoInventoryJson.canonical(proof))
      throw const FormatException('restore_receipt_binding');
  }

  Future<void> _verifyIntent(Map<String, dynamic> proof) async {
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    if (command['version'] != 2 ||
        command['serverId'] != account.directory.session.profile.serverId ||
        command['accountId'] != account.directory.accountId ||
        command['deviceId'] is! String)
      throw const FormatException('restore_intent_identity');
    final directory = _directories[command['accountId']]?.values.last;
    if (directory == null)
      throw const FormatException('restore_intent_directory');
    final devices = directory.devices
        .where((d) => d['deviceId'] == command['deviceId'])
        .toList();
    if (devices.length != 1)
      throw const FormatException('restore_intent_device');
    final operation = command['operation'] as String?;
    if (operation == null || !operation.startsWith('crypto2.'))
      throw const FormatException('restore_intent_operation');
    final domain = operation == 'crypto2.localScopeKeyIntent'
        ? 'JivieE2EE/localKeyIntent/v2\n'
        : cryptoDirectoryDomain;
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(devices.single['signingKeyBase64'], length: 32),
      domain,
    );
    if (operation == 'crypto2.records.batch') {
      final payload = command['payload'];
      if (payload is! Map ||
          payload['records'] is! List ||
          payload['commitment'] is! Map)
        throw const FormatException('restore_batch_shape');
      final codec = CryptoRecordProofCodec(account.directory.reducer.crypto);
      for (final item in payload['records'] as List) {
        final recordProof = Map<String, dynamic>.from(item as Map);
        final body = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(recordProof['commandBase64'])) as Map,
        );
        codec.validateUntrustedRecord(body);
        if (body['serverId'] != command['serverId'] ||
            body['accountId'] != command['accountId'] ||
            body['deviceId'] != command['deviceId'] ||
            body['batchId'] != payload['batchId'])
          throw const FormatException('restore_batch_identity');
        await codec.verifyWire(
          serverId: command['serverId'],
          wire: {
            ...body,
            'revision': body['expectedRevision'] + 1,
            'authorization': {
              'recordProof': recordProof,
              'batchCommitment': payload['commitment'],
            },
          },
          trustedSigningKey: cryptoBase64(
            devices.single['signingKeyBase64'],
            length: 32,
          ),
          currentEpoch: true,
        );
      }
    }
  }

  Future<SecureKey?> _openRetainedGrant(
    Map row,
    Map<String, dynamic> group,
    RecoveredAccountRoot root,
    VerifiedAccountDirectory own,
  ) async {
    final head = _heads[row['scope_head_hash']],
        source = _heads[group['keySourceHeadHash']];
    if (head == null || source == null)
      throw const CryptoAuthorityPending('restore_grant_head_pending');
    final domain = row['domain'];
    if (group['scopeId'] != row['scope_id'] ||
        group['headHash'] != head.headHash ||
        source.scopeId != head.scopeId ||
        group['epoch'] != row['epoch'] ||
        source.epoch != row['epoch'] ||
        group['domain'] != domain ||
        group['keyId'] != row['key_id'] ||
        source.body['keyIds'][domain] != row['key_id'])
      throw const FormatException('restore_grant_binding');
    final recipients = (group['recipients'] as List)
        .cast<Map<String, dynamic>>();
    for (final recipient in recipients.where(
      (r) => r['recipientKind'] == 'recovery',
    )) {
      final pair = [root.encryption, ...root.historicalEncryption]
          .where(
            (k) => base64Encode(k.publicKey) == recipient['publicKeyBase64'],
          )
          .firstOrNull;
      if (pair == null) continue;
      final proof = Map<String, dynamic>.from(
        group['authorizations'][recipient['authorizationId']] as Map,
      );
      if (await cryptoSha256(CryptoJson.encode(proof)) !=
          recipient['authorizationId'])
        throw const FormatException('restore_grant_proof_hash');
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final p = command['payload'] as Map;
      final previous = head.epoch == 1
          ? head
          : _heads[head.body['previousHeadHash']]!;
      final contentCard = head.body['contentKeyProposalProof'] == null
          ? null
          : CryptoJson.decode(
                  cryptoBase64(
                    head.body['contentKeyProposalProof']['commandBase64'],
                  ),
                )
                as Map;
      final financeCard = head.body['financeKeyProposalProof'] == null
          ? null
          : CryptoJson.decode(
                  cryptoBase64(
                    head.body['financeKeyProposalProof']['commandBase64'],
                  ),
                )
                as Map;
      final card = domain == 'finance' ? financeCard : contentCard;
      final selected =
          source.headHash == head.headHash &&
          card != null &&
          card['accountId'] == command['accountId'] &&
          card['deviceId'] == command['deviceId'];
      final authorMember = previous.members
          .where((m) => m['accountId'] == command['accountId'])
          .firstOrNull;
      if (!selected &&
          (authorMember == null ||
              (domain == 'finance'
                  ? authorMember['financeRole'] == 'none'
                  : authorMember['manageKeys'] != true)))
        throw const FormatException('restore_grant_authority');
      final reference = selected
          ? card['authorDirectoryHeadHash']
          : authorMember!['directoryHeadHash'];
      final author = _directory(command['accountId'], reference);
      account.directory.reducer.crypto.verifyDomain(
        proof,
        cryptoBase64(
          author.activeDevice(command['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        cryptoDirectoryDomain,
      );
      if (command['version'] != 2 ||
          command['signer'] != 'device' ||
          command['serverId'] != own.serverId ||
          command['operation'] != 'crypto2.grants.put' ||
          p['scopeId'] != head.scopeId ||
          p['headHash'] != head.headHash ||
          p['keySourceHeadHash'] != source.headHash ||
          p['accountId'] != own.accountId ||
          p['domain'] != domain ||
          p['epoch'] != source.epoch ||
          p['keyId'] != group['keyId'])
        throw const FormatException('restore_grant_proof_binding');
      final covered = (p['recipients'] as List).where(
        (r) =>
            r['recipientKind'] == recipient['recipientKind'] &&
            r['recipientId'] == recipient['recipientId'] &&
            r['publicKeyBase64'] == recipient['publicKeyBase64'] &&
            r['sealedEnvelopeBase64'] == recipient['sealedEnvelopeBase64'],
      );
      if (covered.length != 1 ||
          recipient['recipientId'] !=
              head.member(own.accountId)['recoveryRootEpochId'])
        throw const FormatException('restore_grant_recipient');
      final context = ScopeCryptoCodec(account.directory.reducer.crypto)
          .wrapperContext(
            serverId: own.serverId,
            head: head,
            keySourceHead: source,
            domain: domain,
            keyId: group['keyId'],
            recipient: {
              ...recipient,
              'recoveryRootEpochId': head.member(
                own.accountId,
              )['recoveryRootEpochId'],
            },
          );
      final key = account.directory.reducer.crypto.openKey(
        sealed: recipient['sealedEnvelopeBase64'],
        recipient: pair,
        context: context,
      );
      final bytes = key.extractBytes();
      try {
        if (await ScopeCryptoCodec(
              account.directory.reducer.crypto,
            ).keyCommitment(bytes) !=
            source.commitment(domain))
          throw const FormatException('restore_grant_commitment');
      } catch (_) {
        key.dispose();
        rethrow;
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
      return key;
    }
    return null;
  }

  /// Recover draft bytes to an owned read-only result. No imported command,
  /// write-ready key or active business projection is installed by this method.
  Future<List<RecoveredCryptoDocumentDraft>> recoverDocumentDrafts(
    Uint8List file,
  ) async {
    _current();
    final own = await account.directory.requireFresh();
    final info = account.files.inspect(
      file,
      serverId: own.serverId,
      accountId: own.accountId,
    );
    if (info['fingerprint'] != _fingerprint(own))
      throw const FormatException('restore_recovery_identity');
    final status = await account.status();
    final cipher = cryptoBase64(status['keyringCiphertextBase64']);
    if (await cryptoSha256(cipher) !=
        own.snapshot['recoveryRootCiphertextHash'])
      throw const FormatException('restore_recovery_cipher');
    final root = account.files.open(
      file: file,
      encryptedRoot: Map<String, dynamic>.from(
        CryptoJson.decode(cipher) as Map,
      ),
      serverId: own.serverId,
      accountId: own.accountId,
      expectedFingerprint: info['fingerprint'],
    );
    final keys = <String, SecureKey>{},
        result = <RecoveredCryptoDocumentDraft>[];
    final crypto = account.directory.reducer.crypto;
    try {
      for (final row in _rows['crypto_scope_key_grants'] ?? []) {
        final proof = _json(row['grant']);
        if (proof['commandBase64'] == null) {
          final key = await _openRetainedGrant(row, proof, root, own);
          if (key != null) {
            final coordinate =
                '${row['scope_id']}:${row['domain']}:${row['epoch']}:${row['scope_head_hash']}';
            keys[coordinate]?.dispose();
            keys[coordinate] = key;
          }
          continue;
        }

        final raw =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        if (raw['operation'] != 'crypto2.localScopeKeyIntent') continue;
        await _verifyIntent(proof);
        final ctx = Map<String, dynamic>.from(raw['context'] as Map);
        if (ctx['version'] != 2 ||
            ctx['purpose'] != 'pendingScopeKey' ||
            ctx['serverId'] != own.serverId ||
            ctx['accountId'] != own.accountId ||
            ctx['recipientKind'] != 'recovery' ||
            ctx['scopeId'] != row['scope_id'] ||
            ctx['domain'] != row['domain'] ||
            ctx['keyId'] != row['key_id'])
          throw const FormatException('restore_pending_key_binding');
        final matching = [root.encryption, ...root.historicalEncryption]
            .where(
              (pair) =>
                  base64Encode(pair.publicKey) ==
                  ctx['recipientPublicKeyBase64'],
            )
            .toList();
        if (matching.length != 1)
          throw const CryptoAuthorityPending(
            'restore_historical_file_required',
          );
        final key = crypto.openKey(
          sealed: raw['sealedEnvelopeBase64'],
          recipient: matching.single,
          context: ctx,
        );
        final coordinate =
            '${row['scope_id']}:${row['domain']}:${row['epoch']}:${row['scope_head_hash']}';
        final previous = keys[coordinate];
        if (previous != null) {
          final a = previous.extractBytes(), b = key.extractBytes();
          try {
            if (base64Encode(a) != base64Encode(b))
              throw const FormatException('restore_pending_key_conflict');
          } finally {
            a.fillRange(0, a.length, 0);
            b.fillRange(0, b.length, 0);
            key.dispose();
          }
        } else {
          keys[coordinate] = key;
        }
      }
      for (final candidate in _privateSets.entries) {
        for (final value in candidate.value['crypto_document_jobs'] as List) {
          final job = value as Map;
          if (job['partition'] != account.store.partition)
            throw const FormatException('restore_draft_partition');
          final descriptor = Map<String, dynamic>.from(
            jsonDecode(job['descriptor']) as Map,
          );
          final key =
              keys['${descriptor['scopeId']}:${descriptor['domain']}:${descriptor['epoch']}:${descriptor['membershipHeadHash']}'];
          if (key == null)
            continue; // Original ciphertext remains retained for later authorized key recovery.
          final chunks =
              (candidate.value['crypto_document_chunks'] as List)
                  .where((r) => r['id'] == job['id'])
                  .toList()
                ..sort(
                  (a, b) => (a['offset'] as int).compareTo(b['offset'] as int),
                );
          final builder = BytesBuilder(copy: false);
          for (final chunk in chunks) {
            if (chunk['offset'] != builder.length)
              throw const FormatException('restore_draft_chunks');
            builder.add(base64Decode(chunk['cipher']['blobBase64']));
          }
          final bytes = await decryptCryptoDocumentCipher(
            crypto,
            descriptor,
            key,
            builder.takeBytes(),
            serverId: own.serverId,
          );
          try {
            await validateRecoveredCryptoUploadSources(
              candidate.value,
              job,
              bytes,
            );
            result.add(
              RecoveredCryptoDocumentDraft(
                candidate.key,
                job['id'],
                job['kind'],
                bytes,
              ),
            );
          } catch (_) {
            bytes.fillRange(0, bytes.length, 0);
            rethrow;
          }
          _current();
        }
      }
      return result;
    } catch (_) {
      for (final draft in result) {
        draft.dispose();
      }
      rethrow;
    } finally {
      for (final key in keys.values) {
        key.dispose();
      }
      root.dispose();
    }
  }

  Future<List<String>> verifiedScopes() async {
    _current();
    final fences = await account.store.database.rows(
      "SELECT state FROM crypto_restore_fences WHERE partition=?",
      [account.store.partition],
    );
    if (fences.any((r) => r['state'] != 'verified'))
      throw const CryptoAuthorityPending('restore_review_required');
    return _scopeFloors.keys.toList()..sort();
  }

  /// Only public verified anchors are merged. Original imported command journals
  /// and all private drafts remain quarantined, with no automatic delivery.
  Future<void> reconcile() async {
    final report = await inspect();
    if (!report.canReconcile)
      throw const CryptoAuthorityPending('restore_review_required');
    final snapshot = _snapshot!;
    _current();
    await account.directory.exclusive(() async {
      _current();
      for (final pin in _priorAnchors.entries) {
        if (await account.store.secure.read(pin.key) != pin.value)
          throw const CryptoAuthorityPending('restore_anchor_changed');
      }
      final changes = <Map<String, String?>>[];
      for (final id in _trustedAccounts) {
        final state = _directories[id]!.values.last;
        final key = 'directory2:${account.store.partition}:$id';
        final old = _priorAnchors[key];
        final prior = old == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(old) as Map);
        changes.add({
          'kind': 'directory',
          'identity': id,
          'key': key,
          'previous': old,
          'value': utf8.decode(
            CryptoJson.encode({
              ...prior,
              'serverId': state.serverId,
              'accountId': id,
              'generation': state.generation,
              'headHash': state.headHash,
              'snapshotHash': state.snapshotHash,
              'deviceSnapshotHash': state.deviceSnapshotHash,
              'identityEpochId': state.identityEpochId,
              'rootSigningKeyBase64': state.snapshot['rootSigningKeyBase64'],
              'rootEncryptionKeyBase64':
                  state.snapshot['rootEncryptionKeyBase64'],
            }),
          ),
        });
      }
      for (final head in _scopeFloors.values) {
        final key = 'scope2:${account.store.partition}:${head.scopeId}';
        changes.add({
          'kind': 'scope',
          'identity': head.scopeId,
          'key': key,
          'previous': _priorAnchors[key],
          'value': utf8.decode(
            CryptoJson.encode({'epoch': head.epoch, 'headHash': head.headHash}),
          ),
        });
      }
      await store.commitVerified(
        snapshot,
        deferSecureAnchors: true,
        mergeVerifiedAnchors: () async {
          _current();
          for (final id in _trustedAccounts) {
            for (final entry in _directoryEntries[id]!) {
              await account.store.append(id, entry);
            }
          }
          for (final id in _trustedAccounts) {
            final state = _directories[id]!.values.last;
            await account.store.database.execute(
              'INSERT INTO crypto_directory_pins VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,account_id) DO UPDATE SET root_signing_public=excluded.root_signing_public,root_encryption_public=excluded.root_encryption_public,fingerprint=excluded.fingerprint,min_generation=excluded.min_generation,head_hash=excluded.head_hash,snapshot_hash=excluded.snapshot_hash,device_snapshot_hash=excluded.device_snapshot_hash,identity_epoch_id=excluded.identity_epoch_id,trust_state=excluded.trust_state WHERE crypto_directory_pins.min_generation<=excluded.min_generation',
              [
                account.store.partition,
                state.serverId,
                id,
                state.snapshot['rootSigningKeyBase64'],
                state.snapshot['rootEncryptionKeyBase64'],
                _fingerprint(state),
                state.generation,
                state.headHash,
                state.snapshotHash,
                state.deviceSnapshotHash,
                state.identityEpochId,
                'verified',
              ],
            );
            await account.store.database.execute(
              'INSERT INTO crypto_directory_snapshots VALUES(?,?,?,?,?,?,?) ON CONFLICT(partition,account_id,head_hash) DO NOTHING',
              [
                account.store.partition,
                id,
                state.headHash,
                state.generation,
                state.snapshotHash,
                state.deviceSnapshotHash,
                CryptoJson.encodeDerivedState(state.snapshot),
              ],
            );
          }
          for (final wire in _wires.values) {
            final head = _heads[wire['headHash']]!;
            await account.store.database.execute(
              'INSERT INTO crypto_scope_heads VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,head_hash) DO NOTHING',
              [
                account.store.partition,
                head.scopeId,
                head.headHash,
                head.epoch,
                head.epoch,
                head.headHash,
                head.body['previousHeadHash'],
                CryptoJson.encode(head.body),
                CryptoJson.encode(wire),
              ],
            );
          }
          for (final head in _heads.values.where(
            (h) => _trustedScopes.contains(h.scopeId),
          )) {
            for (final member in head.members.where(
              (m) => !_trustedAccounts.contains(m['accountId']),
            )) {
              final target = _directory(
                member['accountId'],
                member['directoryHeadHash'],
              );
              final prefix = _directoryEntries[member['accountId']]!
                  .where((e) => e['generation'] <= target.generation)
                  .toList();
              await account.store.database.execute(
                'INSERT INTO crypto_restore_scoped_directories VALUES(?,?,?,?,?,?) ON CONFLICT DO NOTHING',
                [
                  account.store.partition,
                  head.scopeId,
                  head.headHash,
                  target.accountId,
                  target.headHash,
                  CryptoJson.encodeDerivedState(prefix),
                ],
              );
            }
          }
          for (final row in _recordAnchors.values) {
            final old = await account.store.database.rows(
              'SELECT revision,proof_hash FROM crypto_restore_record_anchors WHERE partition=? AND scope_id=? AND domain=? AND record_id=?',
              [
                account.store.partition,
                row['scope_id'],
                row['domain'],
                row['record_id'],
              ],
            );
            if (old.isNotEmpty &&
                old.single['revision'] == row['revision'] &&
                old.single['proof_hash'] != row['proof_hash'])
              throw const FormatException('restore_record_equivocation');
            await account.store.database.execute(
              'INSERT INTO crypto_restore_record_anchors VALUES(?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,domain,record_id) DO UPDATE SET revision=excluded.revision,proof_hash=excluded.proof_hash,wire=excluded.wire WHERE crypto_restore_record_anchors.revision<excluded.revision',
              [
                account.store.partition,
                row['scope_id'],
                row['domain'],
                row['record_id'],
                row['revision'],
                row['proof_hash'],
                row['wire'],
              ],
            );
          }
          for (final row in _checkpoints) {
            final old = await account.store.database.rows(
              'SELECT manifest_hash,record_count FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? AND head_hash=? AND sequence=?',
              [
                account.store.partition,
                row['scope_id'],
                row['domain'],
                row['head_hash'],
                row['sequence'],
              ],
            );
            if (old.isNotEmpty &&
                (old.single['manifest_hash'] != row['manifest_hash'] ||
                    old.single['record_count'] != row['record_count']))
              throw const FormatException('restore_checkpoint_fork');
            await account.store.database.execute(
              'INSERT INTO crypto_domain_checkpoints VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO NOTHING',
              [
                account.store.partition,
                row['scope_id'],
                row['domain'],
                row['head_hash'],
                row['epoch'],
                row['access_revision'],
                row['sequence'],
                row['manifest_hash'],
                row['record_count'],
                row['snapshot_id'],
                row['authorization'],
                row['history_basis'],
              ],
            );
            for (final descriptor
                in (_rows['crypto_domain_inventory_rows'] ?? []).where(
                  (d) => d['snapshot_id'] == row['snapshot_id'],
                )) {
              await account.store.database.execute(
                'INSERT INTO crypto_domain_inventory_rows VALUES(?,?,?,?,?,?,?) ON CONFLICT DO NOTHING',
                [
                  account.store.partition,
                  descriptor['snapshot_id'],
                  descriptor['record_id'],
                  descriptor['revision'],
                  descriptor['proof_hash'],
                  descriptor['sequence'],
                  descriptor['record_epoch'],
                ],
              );
            }
          }
          for (final change in changes) {
            final rows = await account.store.database.rows(
              'SELECT value FROM crypto_restore_anchor_journal WHERE partition=? AND evidence_digest=? AND kind=? AND identity=?',
              [
                account.store.partition,
                snapshot.digest,
                change['kind'],
                change['identity'],
              ],
            );
            if (rows.isNotEmpty && rows.single['value'] != change['value'])
              throw const FormatException('restore_anchor_journal_conflict');
            await account.store.database.execute(
              'INSERT INTO crypto_restore_anchor_journal VALUES(?,?,?,?,?,?,?) ON CONFLICT(partition,evidence_digest,kind,identity) DO NOTHING',
              [
                account.store.partition,
                snapshot.digest,
                change['kind'],
                change['identity'],
                change['previous'],
                change['value'],
                'pending',
              ],
            );
          }
        },
      );
      for (final change in changes) {
        _current();
        await withCryptoAnchorLock(account.store.partition, () async {
          final current = await account.store.secure.read(change['key']!);
          if (current != change['previous'] && current != change['value'])
            throw const CryptoAuthorityPending('restore_anchor_changed');
          _current();
          await account.store.secure.write(change['key']!, change['value']!);
        });
        await account.store.database.execute(
          "UPDATE crypto_restore_anchor_journal SET state='applied' WHERE partition=? AND evidence_digest=? AND kind=? AND identity=?",
          [
            account.store.partition,
            snapshot.digest,
            change['kind'],
            change['identity'],
          ],
        );
      }
      await account.store.database.transaction(() async {
        _current();
        if ((await store.snapshot()).digest != snapshot.digest)
          throw const FormatException('crypto_restore_evidence_changed');
        final pending = await account.store.database.rows(
          "SELECT identity FROM crypto_restore_anchor_journal WHERE partition=? AND evidence_digest=? AND state!='applied'",
          [account.store.partition, snapshot.digest],
        );
        if (pending.isNotEmpty)
          throw const CryptoAuthorityPending('restore_anchor_pending');
        await account.store.database.execute(
          "UPDATE crypto_restore_fences SET state='verified' WHERE partition=?",
          [account.store.partition],
        );
      });
    });
  }
}
