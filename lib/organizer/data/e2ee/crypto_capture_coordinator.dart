import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show KeyPair;

import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart' show cryptoSha256, VerifiedAccountDirectory;
import 'crypto_capture_keys.dart';
import 'crypto_capture_v3.dart';
import 'crypto_inventory_json.dart';
import 'crypto_migration_commitments_v3.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'crypto_sync_store.dart';
import 'session_crypto_access.dart';

/// Blinded source capture, before canonical materialization. It does not claim
/// cutover or finance completeness. The complete source selection remains on
/// the server until later archive/cold-business parity and atomic commit.
class CryptoCaptureCoordinator {
  CryptoCaptureCoordinator(this.account, {this.checkpoint})
    : access = SessionCryptoAccess(account: account);
  final AccountCryptoV2Workflow account;
  final SessionCryptoAccess access;
  final Future<void> Function(String phase)? checkpoint;
  String get partition => account.store.partition;
  String get serverId => account.directory.session.profile.serverId;
  CryptoCaptureKeyService get keys => CryptoCaptureKeyService(account);
  CryptoSyncRepository get queue => _queue();
  CryptoSyncRepository _queue({
    Future<KeyPair?> Function(String publicKeyBase64)? recoveryKey,
    bool recoveryOnly = false,
  }) => CryptoSyncRepository(
    crypto: account.directory.reducer.crypto,
    session: account.directory.session,
    transport: account.directory.transport,
    store: CryptoSyncStore(account.store.database, partition),
    signingKey: access.signingKey,
    authorKey: access.recordAuthority,
    contentKey: access.recordKey,
    readContext: access.readContext,
    project: (_) async => throw const CryptoProjectionPending(),
    isCurrent: account.directory.isCurrent,
    beforeDelivery: access.beforeDelivery,
    deliverySidecar: (signed) => deliverySidecar(
      signed,
      recoveryKey: recoveryKey,
      recoveryOnly: recoveryOnly,
    ),
  );

  void _current() {
    if (!account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
  }

  /// Signed capture evidence only. A historical seal is not latest-history
  /// authority; final migration acceptance separately anchors its exact root.
  Future<Map<String, dynamic>> verifiedStatus(
    CryptoCaptureKeyDescriptor descriptor,
  ) async {
    final result = await account.directory.call(
      'crypto2.migration.capture.status',
      {'migrationId': descriptor.migrationId},
    );
    if (result['captureVersion'] != 3 ||
        result['captureId'] != descriptor.captureId ||
        result['keyId'] != descriptor.keyId ||
        result['captureState'] != 'sealed' ||
        result['sourceCount'] is! int ||
        result['sourceCount'] < 0 ||
        result['inventoryRoot'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(result['inventoryRoot']) ||
        result['prepareAuthorization'] is! Map<String, dynamic> ||
        result['sealAuthorization'] is! Map<String, dynamic>) {
      throw const CryptoAuthorityPending('crypto_capture_inventory_pending');
    }
    await _verifyPrepare(
      descriptor.rootScopeId,
      descriptor.componentId,
      descriptor,
      result['prepareAuthorization'],
    );
    await _verifySeal(
      descriptor.rootScopeId,
      descriptor,
      result['inventoryRoot'],
      result['sourceCount'],
      result['sealAuthorization'],
    );
    return Map.unmodifiable(result);
  }

  /// Complete bounded opaque candidate set. It becomes authority only when
  /// the exact final manager certificate and own directory event anchor it.
  Future<Map<String, dynamic>> componentCandidate(
    CryptoCaptureKeyDescriptor capture,
  ) async {
    final own = await verifiedStatus(capture);
    final portions = <Map<String, dynamic>>[];
    String? after;
    Map<String, dynamic>? header;
    while (true) {
      final page = await account.directory
          .call('crypto2.migration.capture.commitments', {
            'migrationId': capture.migrationId,
            if (after != null) 'afterToken': after,
            'limit': 50,
          });
      final candidate = <String, dynamic>{
        for (final key in [
          'serverId',
          'migrationId',
          'componentId',
          'portionCount',
          'inventoryCommitment',
          'componentCommitment',
        ])
          key: page[key],
      };
      if (page['captureVersion'] != 3 ||
          page['candidate'] != true ||
          candidate['serverId'] != serverId ||
          candidate['migrationId'] != capture.migrationId ||
          candidate['componentId'] != capture.componentId ||
          candidate['portionCount'] is! int ||
          candidate['portionCount'] < 1 ||
          candidate['portionCount'] > 1000 ||
          page['portions'] is! List ||
          page['portions'].length > 50 ||
          page['hasMore'] is! bool ||
          header != null &&
              CryptoInventoryJson.canonical(header) !=
                  CryptoInventoryJson.canonical(candidate)) {
        throw const FormatException('crypto_capture_commitment_context');
      }
      header ??= candidate;
      for (final raw in page['portions']) {
        if (raw is! Map<String, dynamic> ||
            raw['portionToken'] is! String ||
            after != null && after.compareTo(raw['portionToken']) >= 0 ||
            portions.length >= candidate['portionCount']) {
          throw const FormatException('crypto_capture_commitment_portions');
        }
        after = raw['portionToken'];
        portions.add(Map<String, dynamic>.from(raw));
      }
      if (page['hasMore'] == false) break;
      if (page['portions'].isEmpty || page['nextAfterToken'] != after) {
        throw const FormatException('crypto_capture_commitment_incomplete');
      }
    }
    final inventory = await CryptoMigrationCommitmentsV3.inventoryCommitment(
      serverId: serverId,
      migrationId: capture.migrationId,
      componentId: capture.componentId,
      portionCount: header['portionCount'],
      portions: Stream.fromIterable(portions),
    );
    final component = await CryptoMigrationCommitmentsV3.componentCommitment(
      serverId: serverId,
      migrationId: capture.migrationId,
      componentId: capture.componentId,
      inventoryCommitment: inventory,
    );
    final ownPortions = portions
        .where((p) => p['captureId'] == capture.captureId)
        .toList();
    if (inventory != header['inventoryCommitment'] ||
        component != header['componentCommitment'] ||
        ownPortions.length != 1 ||
        ownPortions.single['sourceInventoryRoot'] != own['inventoryRoot']) {
      throw const FormatException('crypto_capture_commitment_context');
    }
    _current();
    return Map.unmodifiable({
      ...header,
      'portions': List.unmodifiable(portions),
    });
  }

  Future<Map<String, dynamic>> fence(
    CryptoCaptureKeyDescriptor capture, {
    required String reviewedInventoryRoot,
  }) async {
    await account.directory.requireFresh();
    final status = await verifiedStatus(capture);
    if (status['inventoryRoot'] != reviewedInventoryRoot) {
      throw const CryptoAuthorityPending('crypto_capture_review_changed');
    }
    {
      String? after;
      while (true) {
        final rows = await account.store.database.rows(
          'SELECT binding_id,context,typed_row FROM crypto_capture_sources WHERE partition=? AND capture_id=? ${after == null ? '' : 'AND binding_id>?'} ORDER BY binding_id LIMIT 20',
          [partition, capture.captureId, if (after != null) after],
        );
        for (final row in rows) {
          after = row['binding_id'] as String;
          final source = jsonDecode(row['context'] as String) as Map;
          if (![
            'familyhub_attachments',
            'familyhub_idea_assets',
          ].contains(source['sourceTable'])) {
            continue;
          }
          final typed = jsonDecode(row['typed_row'] as String) as Map;
          String? value(String field) {
            final cell = typed[field];
            return cell is Map && cell['valueBase64'] is String
                ? utf8.decode(cryptoBase64(cell['valueBase64']))
                : null;
          }

          if (value('complete') != '1' && value('deleted') != '1') {
            // Keep the legacy upload and all exact local intent bytes intact;
            // an unfinished upload must not first be discovered after fencing.
            throw const CryptoAuthorityPending(
              'crypto_migration_pending_upload',
            );
          }
        }
        if (rows.length < 20) break;
      }
    }
    final action = 'capture3:fence:${capture.captureId}';
    final intent = <String, dynamic>{
      'captureVersion': 3,
      'migrationId': capture.migrationId,
      'captureId': capture.captureId,
      'inventoryRoot': reviewedInventoryRoot,
      'consentVersion': 1,
    };
    final saved = await account.store.database.rows(
      'SELECT o.request_id,o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
      [partition, action],
    );
    late String request;
    if (saved.isNotEmpty) {
      final proof = jsonDecode(saved.single['signed_body'] as String) as Map;
      final body =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final prior = Map<String, dynamic>.from(body['payload'] as Map)
        ..remove('authorDirectoryHeadHash');
      if (body['operation'] != 'crypto2.migration.capture.fence' ||
          CryptoInventoryJson.canonical(prior) !=
              CryptoInventoryJson.canonical(intent)) {
        throw const FormatException('crypto_immutable_command');
      }
      request = saved.single['request_id'] as String;
    } else {
      request = await queue.enqueueCommand(
        actionKey: action,
        operation: 'crypto2.migration.capture.fence',
        payload: {
          ...intent,
          'authorDirectoryHeadHash':
              (await account.directory.cachedVerifiedDirectory()).headHash,
        },
      );
    }
    await queue.resumeUnresolved(requestIds: {request});
    final result = await queue.commandResult(request);
    if (result['captureId'] != capture.captureId ||
        result['inventoryRoot'] != reviewedInventoryRoot) {
      throw const FormatException('crypto_capture_fence_binding');
    }
    return result;
  }

  /// Read-only recovery of an already sealed capture. FILE identity authenticates
  /// the account prefix and envelopes, not latest history. This path neither
  /// promotes freshness nor creates device secrets, commands or projections.
  Future<Map<String, dynamic>> resumeFromFile(
    String scopeId,
    Uint8List file,
  ) async {
    final inspected = account.files.inspect(
      file,
      serverId: serverId,
      accountId: account.directory.accountId,
    );
    final directory = await account.directory.refresh(
      externalFingerprint: inspected['fingerprint'] as String,
    );
    if (directory == null) {
      throw const CryptoAuthorityPending('crypto_capture_identity_pending');
    }
    final status = await account.status();
    final cipher = cryptoBase64(status['keyringCiphertextBase64']);
    if (await cryptoSha256(cipher) !=
        directory.snapshot['recoveryRootCiphertextHash']) {
      throw const FormatException('crypto_capture_recovery_bundle');
    }
    final recovered = account.files.open(
      file: file,
      encryptedRoot: CryptoJson.decode(cipher) as Map<String, dynamic>,
      serverId: serverId,
      accountId: account.directory.accountId,
      expectedFingerprint: inspected['fingerprint'] as String,
    );
    try {
      Future<KeyPair?> recoveryKey(String public) async {
        for (final pair in [
          recovered.encryption,
          ...recovered.historicalEncryption,
        ]) {
          if (base64Encode(pair.publicKey) == public) {
            final raw = pair.secretKey.extractBytes();
            try {
              return KeyPair(
                publicKey: Uint8List.fromList(pair.publicKey),
                secretKey: account.directory.reducer.crypto.sodium.secureCopy(
                  raw,
                ),
              );
            } finally {
              raw.fillRange(0, raw.length, 0);
            }
          }
        }
        return null;
      }

      final descriptor = await prepare(
        scopeId,
        recoveryKey: recoveryKey,
        recoveryOnly: true,
        recoveryDirectory: directory,
      );
      final result = await captureSources(
        descriptor,
        recoveryKey: recoveryKey,
        recoveryOnly: true,
        recoveryDirectory: directory,
      );
      return {...result, 'historicalFreshness': 'unconfirmedCapturedSource'};
    } finally {
      recovered.dispose();
    }
  }

  /// Also the cold-resume entrypoint. A remote existing capture must recover its
  /// original key; no new key or source salt is generated for that capture ID.
  Future<CryptoCaptureKeyDescriptor> prepare(
    String scopeId, {
    Future<KeyPair?> Function(String publicKeyBase64)? recoveryKey,
    bool recoveryOnly = false,
    VerifiedAccountDirectory? recoveryDirectory,
  }) async {
    if (!isCryptoCanonicalUuid(scopeId)) {
      throw const FormatException('crypto_capture_context');
    }
    if (recoveryDirectory == null) {
      await account.directory.requireFresh();
    } else if (!recoveryOnly ||
        recoveryKey == null ||
        recoveryDirectory.accountId != account.directory.accountId ||
        recoveryDirectory.serverId != serverId) {
      throw const FormatException('crypto_capture_recovery_context');
    }
    final found = await account.directory.call(
      'crypto2.migration.capture.discover',
      {'scopeId': scopeId},
    );
    _current();
    if (found['captureVersion'] != 3 ||
        !isCryptoCanonicalUuid(found['componentId']) ||
        found['receiptSelections'] is! List ||
        found['ownedScopeIds'] is! List ||
        (found['ownedScopeIds'] as List).any(
          (id) => !isCryptoCanonicalUuid(id),
        )) {
      throw const FormatException('crypto_capture_discovery');
    }
    final ownedScopeIds = (found['ownedScopeIds'] as List).cast<String>();
    final receiptSelections = (found['receiptSelections'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    for (var i = 1; i < ownedScopeIds.length; i++) {
      if (ownedScopeIds[i - 1].compareTo(ownedScopeIds[i]) >= 0) {
        throw const FormatException('crypto_capture_discovery');
      }
    }
    final existing = found['ownCapture'];
    if (existing != null) {
      if (existing is! Map || !isCryptoCanonicalUuid(found['migrationId'])) {
        throw const FormatException('crypto_capture_descriptor');
      }
      final proof = Map<String, dynamic>.from(existing['authorization'] as Map);
      final prepared =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final descriptor = CryptoCaptureKeyDescriptor.fromJson(
        prepared['payload'] as Map,
      );
      if (descriptor.captureId != existing['captureId'] ||
          descriptor.keyId != existing['keyId'] ||
          descriptor.migrationId != found['migrationId']) {
        throw const FormatException('crypto_capture_descriptor');
      }
      await _verifyPrepare(
        scopeId,
        found['componentId'] as String,
        descriptor,
        Map<String, dynamic>.from(existing['authorization'] as Map),
      );
      final recovered = await keys.open(
        descriptor,
        recoveryKey: recoveryKey,
        recoveryOnly: recoveryOnly,
        recoveryDirectory: recoveryDirectory,
      );
      recovered.release();
      await _saveRun(scopeId, found['componentId'] as String, descriptor);
      return descriptor;
    }
    if (recoveryOnly) {
      throw const CryptoAuthorityPending(
        'crypto_capture_original_key_required',
      );
    }
    final local = await account.store.database.rows(
      'SELECT * FROM crypto_capture_runs WHERE partition=? AND root_scope_id=?',
      [partition, scopeId],
    );
    late CryptoCaptureKeyDescriptor descriptor;
    if (local.isNotEmpty) {
      final row = local.single;
      if (row['component_id'] != found['componentId'] ||
          found['migrationId'] != null &&
              found['migrationId'] != row['migration_id']) {
        throw const CryptoAuthorityPending(
          'crypto_capture_generation_conflict',
        );
      }
      descriptor = await keys.ensure(
        captureId: row['capture_id'] as String,
        migrationId: row['migration_id'] as String,
      );
      if (descriptor.componentId != found['componentId'] ||
          descriptor.rootScopeId != scopeId ||
          CryptoInventoryJson.canonical(descriptor.scopeIds) !=
              CryptoInventoryJson.canonical(ownedScopeIds) ||
          CryptoInventoryJson.canonical(descriptor.receiptSelections) !=
              CryptoInventoryJson.canonical(receiptSelections)) {
        throw const CryptoAuthorityPending('crypto_capture_context_changed');
      }
    } else {
      final migrationId =
          found['migrationId'] ?? account.directory.reducer.crypto.randomId();
      if (!isCryptoCanonicalUuid(migrationId)) {
        throw const FormatException('crypto_capture_descriptor');
      }
      descriptor = await keys.create(
        migrationId: migrationId as String,
        rootScopeId: scopeId,
        componentId: found['componentId'] as String,
        scopeIds: (found['ownedScopeIds'] as List).cast<String>(),
        receiptSelections: receiptSelections,
      );
      await _saveRun(scopeId, found['componentId'] as String, descriptor);
      await checkpoint?.call('capture_key_wrapped');
    }
    final payload = {
      ...descriptor.toJson(),
      'authorDirectoryHeadHash':
          (await account.directory.cachedVerifiedDirectory()).headHash,
    };
    final q = queue;
    final id = await q.enqueueCommand(
      actionKey: 'capture:${descriptor.captureId}:prepare',
      operation: 'crypto2.migration.capture.prepare',
      payload: payload,
    );
    await q.resumeUnresolved(requestIds: {id});
    final result = await q.commandResult(id);
    if (result['captureVersion'] != 3 ||
        result['captureId'] != descriptor.captureId ||
        result['migrationId'] != descriptor.migrationId ||
        result['keyId'] != descriptor.keyId) {
      throw const FormatException('crypto_capture_descriptor');
    }
    return descriptor;
  }

  Future<void> _verifyPrepare(
    String scopeId,
    String componentId,
    CryptoCaptureKeyDescriptor descriptor,
    Map<String, dynamic> proof,
  ) async {
    final untrusted = CryptoJson.decode(cryptoBase64(proof['commandBase64']));
    if (untrusted is! Map<String, dynamic> ||
        untrusted.length != 8 ||
        untrusted['version'] != 2 ||
        !isCryptoCanonicalUuid(untrusted['deviceId']) ||
        !isCryptoCanonicalUuid(untrusted['requestId']) ||
        untrusted['payload'] is! Map ||
        untrusted['operation'] != 'crypto2.migration.capture.prepare' ||
        untrusted['accountId'] != account.directory.accountId ||
        untrusted['serverId'] != serverId ||
        untrusted['signer'] != 'device') {
      throw const FormatException('crypto_capture_prepare_proof');
    }
    final p = untrusted['payload'] as Map;
    if (p.length != 9 ||
        p['captureVersion'] != 3 ||
        p['captureId'] != descriptor.captureId ||
        p['migrationId'] != descriptor.migrationId ||
        p['keyId'] != descriptor.keyId ||
        p['authorDirectoryHeadHash'] is! String ||
        p['componentId'] != componentId ||
        p['receiptSelections'] is! List ||
        CryptoInventoryJson.canonical(p['receiptSelections']) !=
            CryptoInventoryJson.canonical(descriptor.receiptSelections) ||
        p['scopeIds'] is! List ||
        (p['scopeIds'] as List).any((id) => !isCryptoCanonicalUuid(id)) ||
        (p['rootScopeId'] != scopeId &&
            !(p['scopeIds'] as List).contains(scopeId) &&
            !descriptor.receiptSelections.any(
              (v) => v['scopeId'] == scopeId,
            ))) {
      throw const FormatException('crypto_capture_prepare_proof');
    }
    final owned = (p['scopeIds'] as List).cast<String>();
    for (var i = 1; i < owned.length; i++) {
      if (owned[i - 1].compareTo(owned[i]) >= 0) {
        throw const FormatException('crypto_capture_prepare_proof');
      }
    }
    final directory = await access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: '0' * 64,
      accountId: account.directory.accountId,
      directoryHeadHash: p['authorDirectoryHeadHash'] as String,
    );
    final device = directory.activeDevice(untrusted['deviceId'] as String);
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      'JivieE2EE/v2\n',
    );
  }

  Future<void> _saveRun(
    String scopeId,
    String componentId,
    CryptoCaptureKeyDescriptor value,
  ) async {
    _current();
    final rows = await account.store.database.rows(
      'SELECT capture_id,migration_id,key_id,component_id FROM crypto_capture_runs WHERE partition=? AND root_scope_id=?',
      [partition, scopeId],
    );
    if (rows.isNotEmpty) {
      final old = rows.single;
      if (old['capture_id'] != value.captureId ||
          old['migration_id'] != value.migrationId ||
          old['key_id'] != value.keyId ||
          old['component_id'] != componentId) {
        throw const FormatException('crypto_capture_generation_conflict');
      }
      return;
    }
    await account.store.database
        .execute('INSERT INTO crypto_capture_runs VALUES(?,?,?,?,?,?,?)', [
          partition,
          scopeId,
          value.captureId,
          value.migrationId,
          value.keyId,
          componentId,
          jsonEncode(value.toJson()),
        ]);
  }

  /// Bounded pages and at most 32 bindings per immutable signed command. All
  /// exact typed fields are retained in the installation vault; no model codec
  /// can drop unknown columns while deriving a capture commitment.
  Future<Map<String, dynamic>> captureSources(
    CryptoCaptureKeyDescriptor value, {
    Future<KeyPair?> Function(String publicKeyBase64)? recoveryKey,
    bool recoveryOnly = false,
    VerifiedAccountDirectory? recoveryDirectory,
  }) async {
    final key = await keys.open(
      value,
      recoveryKey: recoveryKey,
      recoveryOnly: recoveryOnly,
      recoveryDirectory: recoveryDirectory,
    );
    try {
      final sources = await account.directory.call(
        'crypto2.migration.capture.sources',
        {'migrationId': value.migrationId},
      );
      if (sources['captureVersion'] != 3 || sources['tables'] is! List) {
        throw const FormatException('crypto_capture_sources');
      }
      final seen = <String>{};
      for (final raw in sources['tables'] as List) {
        if (raw is! Map ||
            raw['table'] is! String ||
            raw['domain'] is! String ||
            raw['rows'] is! int ||
            raw['rows'] < 0 ||
            !seen.add('${raw['table']}:${raw['domain']}')) {
          throw const FormatException('crypto_capture_sources');
        }
        var cursor = 0;
        while (cursor < raw['rows']) {
          final page = await account.directory
              .call('crypto2.migration.capture.sourcePage', {
                'migrationId': value.migrationId,
                'table': raw['table'],
                'domain': raw['domain'],
                'cursor': cursor,
                'limit': 20,
              });
          if (page['captureVersion'] != 3 ||
              page['rows'] is! List ||
              (page['rows'] as List).isEmpty ||
              (page['rows'] as List).length > 20 ||
              page['cursor'] != cursor + (page['rows'] as List).length ||
              page['cursor'] > raw['rows']) {
            throw const FormatException('crypto_capture_cursor');
          }
          for (final item in page['rows'] as List) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('crypto_capture_source');
            }
            final row = await _hydrate(
              value.migrationId,
              raw['table'] as String,
              raw['domain'] as String,
              cursor,
              item,
            );
            final column = raw['table'] == 'familyhub_scopes'
                ? 'id'
                : 'scope_id';
            final scope = raw['domain'] == 'private'
                ? null
                : utf8.decode(
                    cryptoBase64((row[column] as Map)['valueBase64']),
                  );
            final context = CryptoCaptureSourceContext(
              serverId: serverId,
              captureId: value.captureId,
              migrationId: value.migrationId,
              accountId: account.directory.accountId,
              scopeId: scope,
              domain: raw['domain'] as String,
              sourceTable: raw['table'] as String,
              sourceId: 'row:$cursor',
            );
            final salt = await CryptoCaptureV3.salt(key.key, context);
            try {
              final binding = CryptoCaptureBinding(
                bindingId: await CryptoCaptureV3.bindingId(key.key, context),
                scopeId: scope,
                domain: context.domain,
                sourceCommitment: await CryptoCaptureV3.sourceCommitment(
                  context: context,
                  salt: salt,
                  typedRow: row,
                ),
              );
              await _saveSource(value, context, row, binding);
            } finally {
              salt.fillRange(0, salt.length, 0);
            }
            cursor++;
          }
        }
      }
      final count =
          (await account.store.database.rows(
                'SELECT COUNT(*) AS n FROM crypto_capture_sources WHERE partition=? AND capture_id=?',
                [partition, value.captureId],
              )).single['n']
              as int;
      final root = await CryptoCaptureV3.inventoryRoot(
        serverId: serverId,
        captureId: value.captureId,
        migrationId: value.migrationId,
        accountId: account.directory.accountId,
        sourceCount: count,
        bindings: _bindings(value),
      );
      final status = await account.directory.call(
        'crypto2.migration.capture.status',
        {'migrationId': value.migrationId},
      );
      if (status['captureState'] == 'sealed') {
        if (status['inventoryRoot'] != root ||
            status['sourceCount'] != count ||
            status['sealAuthorization'] is! Map) {
          throw const FormatException('crypto_capture_inventory');
        }
        final runs = await account.store.database.rows(
          'SELECT root_scope_id FROM crypto_capture_runs WHERE partition=? AND capture_id=?',
          [partition, value.captureId],
        );
        await _verifySeal(
          runs.single['root_scope_id'] as String,
          value,
          root,
          count,
          Map<String, dynamic>.from(status['sealAuthorization'] as Map),
        );
        return status;
      }
      if (recoveryDirectory != null) {
        // Unknown/unsealed outcomes need newly approved device authority or an
        // explicit safe abort. A recovery file alone is no freshness grant.
        throw const CryptoAuthorityPending(
          'crypto_capture_resume_approval_required',
        );
      }
      await _uploadBindings(
        value,
        recoveryKey: recoveryKey,
        recoveryOnly: recoveryOnly,
      );
      final q = _queue(recoveryKey: recoveryKey, recoveryOnly: recoveryOnly);
      final request = await q.enqueueCommand(
        actionKey: 'capture:${value.captureId}:seal',
        operation: 'crypto2.migration.capture.seal',
        payload: {
          'captureVersion': 3,
          'captureId': value.captureId,
          'migrationId': value.migrationId,
          'sourceCount': count,
          'inventoryRoot': root,
          'authorDirectoryHeadHash':
              (await account.directory.cachedVerifiedDirectory()).headHash,
        },
      );
      await q.resumeUnresolved(requestIds: {request});
      final result = await q.commandResult(request);
      if (result['inventoryRoot'] != root || result['sourceCount'] != count) {
        throw const FormatException('crypto_capture_inventory');
      }
      return result;
    } finally {
      key.release();
    }
  }

  Future<void> _verifySeal(
    String scopeId,
    CryptoCaptureKeyDescriptor value,
    String root,
    int count,
    Map<String, dynamic> proof,
  ) async {
    final command = CryptoJson.decode(cryptoBase64(proof['commandBase64']));
    if (command is! Map<String, dynamic> ||
        command.length != 8 ||
        command['version'] != 2 ||
        !isCryptoCanonicalUuid(command['deviceId']) ||
        !isCryptoCanonicalUuid(command['requestId']) ||
        command['payload'] is! Map ||
        command['operation'] != 'crypto2.migration.capture.seal' ||
        command['serverId'] != serverId ||
        command['accountId'] != account.directory.accountId ||
        command['signer'] != 'device') {
      throw const FormatException('crypto_capture_seal_proof');
    }
    final p = command['payload'] as Map;
    if (p.length != 6 ||
        p['captureVersion'] != 3 ||
        p['captureId'] != value.captureId ||
        p['migrationId'] != value.migrationId ||
        p['sourceCount'] != count ||
        p['inventoryRoot'] != root ||
        p['authorDirectoryHeadHash'] is! String) {
      throw const FormatException('crypto_capture_seal_proof');
    }
    final directory = await access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: '0' * 64,
      accountId: account.directory.accountId,
      directoryHeadHash: p['authorDirectoryHeadHash'] as String,
    );
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(
        directory.activeDevice(
          command['deviceId'] as String,
        )['signingKeyBase64'],
        length: 32,
      ),
      'JivieE2EE/v2\n',
    );
  }

  Future<Map<String, dynamic>> _hydrate(
    String migrationId,
    String table,
    String domain,
    int cursor,
    Map<String, dynamic> value,
  ) async {
    final row = Map<String, dynamic>.from(value);
    for (final column in row.keys.toList()) {
      final cell = row[column];
      if (cell is! Map || cell['external'] == null) continue;
      final external = cell['external'];
      if (external is! Map ||
          external['size'] is! int ||
          external['size'] < 0 ||
          external['size'] > 24 * 1024 * 1024) {
        throw const CryptoAuthorityPending(
          'crypto_migration_large_cell_stream_pending',
        );
      }
      final bytes = BytesBuilder(copy: false);
      var offset = 0;
      while (offset < external['size']) {
        final chunk = await account.directory
            .call('crypto2.migration.capture.sourceCell', {
              'migrationId': migrationId,
              'table': table,
              'domain': domain,
              'cursor': cursor,
              'column': column,
              'offset': offset,
              'limit': 192 * 1024,
            });
        final data = cryptoBase64(chunk['dataBase64']);
        if (data.isEmpty ||
            data.length > 192 * 1024 ||
            chunk['offset'] != offset ||
            chunk['size'] != external['size'] ||
            chunk['sha256'] != external['sha256'] ||
            chunk['nextOffset'] != offset + data.length ||
            offset + data.length > external['size']) {
          throw const FormatException('crypto_capture_cell');
        }
        bytes.add(data);
        offset += data.length;
      }
      final data = bytes.takeBytes();
      try {
        // Raw file/cell SHA is a transient authorized transfer check, never
        // copied into a public signed capture command or certificate.
        if (await cryptoSha256(data) != external['sha256']) {
          throw const FormatException('crypto_capture_cell');
        }
        row[column] = {'type': cell['type'], 'valueBase64': base64Encode(data)};
      } finally {
        data.fillRange(0, data.length, 0);
      }
    }
    return row;
  }

  Future<void> _saveSource(
    CryptoCaptureKeyDescriptor value,
    CryptoCaptureSourceContext context,
    Map<String, dynamic> row,
    CryptoCaptureBinding binding,
  ) async {
    final db = account.store.database;
    final encodedContext = CryptoInventoryJson.canonical(context.toJson());
    final encodedRow = CryptoInventoryJson.canonical(row);
    final encodedBinding = CryptoInventoryJson.canonical(binding.toJson());
    final prior = await db.rows(
      'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND (binding_id=? OR context=?)',
      [partition, value.captureId, binding.bindingId, encodedContext],
    );
    if (prior.isNotEmpty) {
      if (prior.length != 1 ||
          prior.single['context'] != encodedContext ||
          prior.single['binding_id'] != binding.bindingId ||
          prior.single['typed_row'] != encodedRow ||
          prior.single['binding'] != encodedBinding) {
        throw const FormatException('crypto_capture_binding_immutable');
      }
      return;
    }
    await db.execute('INSERT INTO crypto_capture_sources VALUES(?,?,?,?,?,?)', [
      partition,
      value.captureId,
      binding.bindingId,
      encodedContext,
      encodedRow,
      encodedBinding,
    ]);
  }

  Stream<CryptoCaptureBinding> _bindings(
    CryptoCaptureKeyDescriptor value,
  ) async* {
    var after = '';
    while (true) {
      final page = await account.store.database.rows(
        'SELECT binding_id,binding FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? ORDER BY binding_id LIMIT 32',
        [partition, value.captureId, after],
      );
      for (final row in page) {
        yield CryptoCaptureBinding.fromJson(
          jsonDecode(row['binding'] as String) as Map<String, dynamic>,
        );
        after = row['binding_id'] as String;
      }
      if (page.length < 32) break;
    }
  }

  Future<void> _uploadBindings(
    CryptoCaptureKeyDescriptor value, {
    Future<KeyPair?> Function(String publicKeyBase64)? recoveryKey,
    bool recoveryOnly = false,
  }) async {
    final batch = <CryptoCaptureBinding>[];
    Future<void> upload() async {
      if (batch.isEmpty) return;
      final q = _queue(recoveryKey: recoveryKey, recoveryOnly: recoveryOnly);
      final request = await q.enqueueCommand(
        actionKey:
            'capture:${value.captureId}:bind:${batch.first.bindingId}:${batch.last.bindingId}',
        operation: 'crypto2.migration.capture.bind',
        payload: {
          'captureVersion': 3,
          'migrationId': value.migrationId,
          'captureId': value.captureId,
          'bindings': batch.map((b) => b.toJson()).toList(),
          'authorDirectoryHeadHash':
              (await account.directory.cachedVerifiedDirectory()).headHash,
        },
      );
      await q.resumeUnresolved(requestIds: {request});
      await q.commandResult(request);
      await checkpoint?.call('capture_bind_ack');
      batch.clear();
    }

    await for (final binding in _bindings(value)) {
      batch.add(binding);
      if (batch.length == 32) await upload();
    }
    await upload();
  }

  Future<Map<String, dynamic>> deliverySidecar(
    Map<String, dynamic> signed, {
    Future<KeyPair?> Function(String publicKeyBase64)? recoveryKey,
    bool recoveryOnly = false,
  }) async {
    final command =
        CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
    if (!const {
      'crypto2.migration.capture.bind',
      'crypto2.migration.recordsStage',
    }.contains(command['operation'])) {
      return const {};
    }
    final payload = command['payload'] as Map;
    final staged = command['operation'] == 'crypto2.migration.recordsStage';
    final bindings = payload[staged ? 'sourceBindings' : 'bindings'];
    if (payload['captureVersion'] != 3 ||
        bindings is! List ||
        bindings.isEmpty ||
        bindings.length > 32) {
      throw const FormatException('crypto_capture_sidecar');
    }
    final rows = await account.store.database.rows(
      'SELECT journal FROM crypto_capture_runs WHERE partition=? AND capture_id=?',
      [partition, payload['captureId']],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_capture_original_key_required',
      );
    }
    final descriptor = CryptoCaptureKeyDescriptor.fromJson(
      jsonDecode(rows.single['journal'] as String) as Map,
    );
    final key = await keys.open(
      descriptor,
      recoveryKey: recoveryKey,
      recoveryOnly: recoveryOnly,
    );
    try {
      final result = <Map<String, dynamic>>[];
      for (final raw in bindings) {
        if (raw is! Map) throw const FormatException('crypto_capture_sidecar');
        final local = await account.store.database.rows(
          'SELECT binding FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id=?',
          [partition, descriptor.captureId, raw['bindingId']],
        );
        if (local.length != 1) {
          throw const FormatException('crypto_capture_sidecar');
        }
        final binding = CryptoCaptureBinding.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(local.single['binding'] as String) as Map,
          ),
        );
        if (raw['scopeId'] != binding.scopeId ||
            raw['domain'] != binding.domain ||
            (!staged &&
                CryptoInventoryJson.canonical(raw) !=
                    CryptoInventoryJson.canonical(binding.toJson()))) {
          throw const FormatException('crypto_capture_sidecar');
        }
        final source = await account.store.database.rows(
          'SELECT context,binding FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id=?',
          [partition, descriptor.captureId, binding.bindingId],
        );
        if (source.length != 1 ||
            source.single['binding'] !=
                CryptoInventoryJson.canonical(binding.toJson())) {
          throw const FormatException('crypto_capture_sidecar');
        }
        final context = CryptoCaptureSourceContext.fromJson(
          jsonDecode(source.single['context'] as String)
              as Map<String, dynamic>,
        );
        final salt = await CryptoCaptureV3.salt(key.key, context);
        try {
          result.add(
            CryptoCaptureV3.sidecar(
              bindingId: binding.bindingId,
              context: context,
              salt: salt,
            ),
          );
        } finally {
          salt.fillRange(0, salt.length, 0);
        }
      }
      return {'captureSecrets': result};
    } finally {
      key.release();
    }
  }
}
