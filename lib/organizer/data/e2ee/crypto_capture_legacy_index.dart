import 'dart:async';
import 'dart:convert';
import 'package:sodium/sodium.dart' show KeyPair;

import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_capture_v3.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_legacy.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

String _canonical(Object? value) => utf8.decode(CryptoJson.encode(value));

/// Complete own-account legacy receipt inventory. It never activates imported
/// requests, trusts unsigned lookup outcomes, or reconstructs new money effects.
class CryptoCaptureLegacyIndex {
  CryptoCaptureLegacyIndex(this.account)
    : access = SessionCryptoAccess(account: account);
  final AccountCryptoV2Workflow account;
  final SessionCryptoAccess access;
  String get partition => account.store.partition;
  static final _pending = <String, Future<void>>{};

  /// Certify only after the private archive is uploaded and independently cold
  /// checked by the migration coordinator. This builds descriptors from the
  /// captured typed rows, not from a server-provided guessed outcome list.
  Future<VerifiedCryptoLegacyInventory> certify({
    required VerifiedCryptoCaptureArchive coldArchive,
    required String domain,
    Future<KeyPair?> Function(String publicKeyBase64)? recoveryKey,
  }) async {
    final capture = coldArchive.capture, archive = coldArchive.manifest;
    final sourceInventoryRoot = coldArchive.sourceInventoryRoot;
    await account.directory.requireFresh();
    if (archive.migrationId != capture.migrationId ||
        !const ['content', 'finance'].contains(domain)) {
      throw const FormatException('crypto_legacy_inventory_context');
    }
    final db = account.store.database;
    final scratch = 'draft:${account.directory.reducer.crypto.randomId()}';
    final key = await CryptoCaptureKeyService(
      account,
    ).open(capture, recoveryKey: recoveryKey);
    late Map<String, dynamic> header;
    late String root;
    try {
      var after = '';
      while (true) {
        // One potentially large private response at a time, never a full
        // response history in memory. IDs/order metadata remain in SQL.
        final rows = await db.rows(
          'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? ORDER BY binding_id LIMIT 1',
          [partition, capture.captureId, after],
        );
        if (rows.isEmpty) break;
        final row = rows.single;
        after = row['binding_id'] as String;
        final context = CryptoCaptureSourceContext.fromJson(
          jsonDecode(row['context'] as String) as Map<String, dynamic>,
        );
        final kind = switch (context.sourceTable) {
          'familyhub_operations' => 'records',
          'familyhub_finance_operations' => 'finance',
          'familyhub_document_requests' => 'documents',
          _ => null,
        };
        if (kind == null ||
            (kind == 'finance' ? 'finance' : 'content') != domain) {
          continue;
        }
        if (context.accountId != account.directory.accountId ||
            context.captureId != capture.captureId ||
            context.migrationId != capture.migrationId ||
            context.serverId != account.directory.session.profile.serverId) {
          throw const FormatException('crypto_legacy_inventory_context');
        }
        final typed =
            jsonDecode(row['typed_row'] as String) as Map<String, dynamic>;
        final binding = CryptoCaptureBinding.fromJson(
          jsonDecode(row['binding'] as String) as Map<String, dynamic>,
        );
        String text(String column) {
          final cell = typed[column];
          if (cell is! Map || cell['valueBase64'] is! String) {
            throw const FormatException('crypto_legacy_receipt_source');
          }
          return utf8.decode(cryptoBase64(cell['valueBase64']));
        }

        final descriptor = CryptoLegacyReceiptDescriptor(
          tuple: CryptoLegacyReceiptTuple(
            scopeId: text('scope_id'),
            kind: kind,
            legacyId: text(kind == 'documents' ? 'request_id' : 'id'),
            documentDeviceId: kind == 'documents' ? text('device_id') : null,
          ),
          bindingId: binding.bindingId,
          sourceCommitment: binding.sourceCommitment,
        );
        final salt = await CryptoCaptureV3.salt(key.key, context);
        try {
          final receipt = await CryptoCapturedLegacyReceipt.fromWitness(
            descriptor: descriptor,
            context: context,
            witness: {
              'version': 3,
              'context': context.toJson(),
              'typedRow': typed,
              'saltBase64': base64Encode(salt),
            },
          );
          receipt.responseBytes.fillRange(0, receipt.responseBytes.length, 0);
        } finally {
          salt.fillRange(0, salt.length, 0);
        }
        final tuple = descriptor.tuple;
        await db.execute(
          'INSERT INTO crypto_legacy_inventory_rows VALUES(?,?,?,?,?,?,?,?)',
          [
            partition,
            scratch,
            tuple.scopeId,
            tuple.kind,
            tuple.legacyId,
            tuple.documentDeviceId ?? '',
            binding.bindingId,
            binding.sourceCommitment,
          ],
        );
      }
      final count =
          (await db.rows(
                'SELECT COUNT(*) AS n FROM crypto_legacy_inventory_rows WHERE partition=? AND certificate_hash=?',
                [partition, scratch],
              )).single['n']
              as int;
      header = CryptoLegacyReceiptInventory.header(
        serverId: account.directory.session.profile.serverId,
        accountId: account.directory.accountId,
        captureId: capture.captureId,
        migrationId: capture.migrationId,
        domain: domain,
        sourceInventoryRoot: sourceInventoryRoot,
        archiveManifestHash: archive.cipherManifestHash,
        receiptCount: count,
        receiptSelectionHash: await CryptoLegacyReceiptInventory.selectionHash(
          serverId: account.directory.session.profile.serverId,
          accountId: account.directory.accountId,
          captureId: capture.captureId,
          migrationId: capture.migrationId,
          receiptSelections: capture.receiptSelections,
        ),
      );
      root = await CryptoLegacyReceiptInventory.root(
        header,
        _storedDescriptors(scratch),
        // UNIQUE(partition,certificate_hash,binding_id) already enforces this
        // without a growing in-memory set of historical receipt IDs.
        claimBinding: (_) async => true,
      );
      if (count != coldArchive.receiptCounts[domain] ||
          root != coldArchive.receiptRoots[domain]) {
        throw const FormatException('crypto_legacy_archive_cold_parity');
      }
    } finally {
      key.release();
      await db.execute(
        'DELETE FROM crypto_legacy_inventory_rows WHERE partition=? AND certificate_hash=?',
        [partition, scratch],
      );
    }
    final coordinator = CryptoCaptureCoordinator(account);
    final q = coordinator.queue;
    final action = 'capture3:legacy:${capture.captureId}:$domain';
    final saved = await db.rows(
      'SELECT o.request_id,o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
      [partition, action],
    );
    final intent = {
      'header': header,
      'manifestRoot': root,
      'archiveSegments': archive.segments.map((s) => s.toJson()).toList(),
    };
    late String request;
    if (saved.isNotEmpty) {
      final body = jsonDecode(saved.single['signed_body'] as String) as Map;
      final command = _body(Map<String, dynamic>.from(body));
      final prior = Map<String, dynamic>.from(command['payload'] as Map)
        ..remove('authorDirectoryHeadHash');
      if (command['operation'] != 'crypto2.migration.legacy.certify' ||
          _canonical(prior) != _canonical(intent)) {
        throw const FormatException('crypto_legacy_inventory_immutable');
      }
      request = saved.single['request_id'] as String;
    } else {
      request = await q.enqueueCommand(
        actionKey: action,
        operation: 'crypto2.migration.legacy.certify',
        payload: {
          ...intent,
          'authorDirectoryHeadHash':
              (await account.directory.cachedVerifiedDirectory()).headHash,
        },
      );
    }
    await q.resumeUnresolved(requestIds: {request});
    final result = await q.commandResult(request);
    final cert = result['certificateAuthorization'];
    final original = await db.rows(
      'SELECT signed_body FROM crypto_outbox WHERE partition=? AND request_id=?',
      [partition, request],
    );
    if (cert is! Map<String, dynamic> ||
        original.length != 1 ||
        _canonical(jsonDecode(original.single['signed_body'] as String)) !=
            _canonical(cert) ||
        _canonical((_body(cert)['payload'] as Map)['header']) !=
            _canonical(header) ||
        (_body(cert)['payload'] as Map)['manifestRoot'] != root) {
      throw const FormatException('crypto_legacy_inventory_authorization');
    }
    final entry = await account.attestMigration(
      migrationId: capture.migrationId,
      scopeToken: await CryptoLegacyReceiptInventory.scopeToken(header),
      domain: domain,
      attestationHash: await cryptoSha256(CryptoJson.encode(cert)),
    );
    final anchor = await q.enqueueCommand(
      actionKey: '$action:anchor',
      operation: 'crypto2.migration.legacy.anchor',
      payload: {
        'migrationId': capture.migrationId,
        'domain': domain,
        'eventAuthorization': entry['authorization'],
      },
    );
    await q.resumeUnresolved(requestIds: {anchor});
    await q.commandResult(anchor);
    return verify(
      capture: capture,
      domain: domain,
      sourceInventoryRoot: sourceInventoryRoot,
    );
  }

  Stream<CryptoLegacyReceiptDescriptor> _storedDescriptors(
    String certificate,
  ) async* {
    var cursor = ['', '', '', ''];
    while (true) {
      final rows = await account.store.database.rows(
        'SELECT * FROM crypto_legacy_inventory_rows WHERE partition=? AND certificate_hash=? AND (scope_id,receipt_kind,legacy_id,legacy_device_id)>(?,?,?,?) ORDER BY scope_id,receipt_kind,legacy_id,legacy_device_id LIMIT 128',
        [partition, certificate, ...cursor],
      );
      if (rows.isEmpty) return;
      for (final row in rows) {
        cursor = [
          row['scope_id'] as String,
          row['receipt_kind'] as String,
          row['legacy_id'] as String,
          row['legacy_device_id'] as String,
        ];
        yield CryptoLegacyReceiptDescriptor(
          tuple: CryptoLegacyReceiptTuple(
            scopeId: cursor[0],
            kind: cursor[1],
            legacyId: cursor[2],
            documentDeviceId: cursor[3].isEmpty ? null : cursor[3],
          ),
          bindingId: row['binding_id'] as String,
          sourceCommitment: row['source_commitment'] as String,
        );
      }
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final prior = _pending[partition] ?? Future<void>.value();
    final done = Completer<void>();
    _pending[partition] = done.future;
    await prior;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_pending[partition], done.future)) {
        _pending.remove(partition);
      }
    }
  }

  /// Uses an externally authenticated capture descriptor and source root. The
  /// full candidate stream is independently checked against the signed cert and
  /// its exact event in the current locally verified own-account directory.
  Future<VerifiedCryptoLegacyInventory> verify({
    required CryptoCaptureKeyDescriptor capture,
    required String domain,
    required String sourceInventoryRoot,
  }) => _exclusive(() async {
    final result = await account.directory.call(
      'crypto2.migration.legacy.status',
      {'migrationId': capture.migrationId, 'domain': domain},
    );
    final verified = await _certificate(
      result,
      capture,
      domain,
      sourceInventoryRoot,
    );
    final header = verified.$1;
    final cert = verified.$2;
    final event = verified.$3;
    final certHash = await cryptoSha256(CryptoJson.encode(cert));
    final body = _body(cert);
    final manifestRoot = (body['payload'] as Map)['manifestRoot'] as String;
    final db = account.store.database;
    final known = await db.rows(
      'SELECT * FROM crypto_legacy_inventory_certificates WHERE partition=? AND certificate_hash=?',
      [partition, certHash],
    );
    if (known.isNotEmpty) {
      final row = known.single;
      if (row['header'] != CryptoInventoryJson.canonical(header) ||
          row['manifest_root'] != manifestRoot ||
          row['authorization'] != _canonical(cert) ||
          row['event_authorization'] != _canonical(event)) {
        throw const FormatException('crypto_legacy_inventory_immutable');
      }
      if (row['complete'] == 1) {
        final restoredRoot = await CryptoLegacyReceiptInventory.root(
          header,
          _storedDescriptors(certHash),
          // UNIQUE binding_id and tuple constraints are checked by SQLite.
          claimBinding: (_) async => true,
        );
        if (restoredRoot != manifestRoot) {
          throw const CryptoAuthorityPending('crypto_legacy_inventory_pending');
        }
        return VerifiedCryptoLegacyInventory._(
          this,
          capture,
          header,
          certHash,
          event,
          manifestRoot,
        );
      }
    } else {
      await db.execute(
        'INSERT INTO crypto_legacy_inventory_certificates VALUES(?,?,?,?,?,?,0)',
        [
          partition,
          certHash,
          CryptoInventoryJson.canonical(header),
          manifestRoot,
          _canonical(cert),
          _canonical(event),
        ],
      );
    }
    await db.execute(
      'DELETE FROM crypto_legacy_inventory_rows WHERE partition=? AND certificate_hash=?',
      [partition, certHash],
    );
    var complete = false;
    try {
      Stream<CryptoLegacyReceiptDescriptor> stream() async* {
        Map<String, dynamic>? after;
        var count = 0;
        while (true) {
          final page = await account.directory
              .call('crypto2.migration.legacy.inventory', {
                'migrationId': capture.migrationId,
                'domain': domain,
                'limit': 128,
                if (after != null) 'after': after,
              });
          if (_canonical(page['certificateAuthorization']) !=
                  _canonical(cert) ||
              _canonical(page['eventAuthorization']) != _canonical(event) ||
              page['descriptors'] is! List ||
              page['hasMore'] is! bool ||
              (page['descriptors'] as List).length > 128) {
            throw const FormatException('crypto_legacy_inventory_page');
          }
          final entries = page['descriptors'] as List;
          CryptoLegacyReceiptDescriptor? last;
          for (final raw in entries) {
            if (raw is! Map<String, dynamic>) {
              throw const FormatException('crypto_legacy_inventory_page');
            }
            last = CryptoLegacyReceiptDescriptor.fromJson(raw);
            if (++count > header['receiptCount']) {
              throw const FormatException('crypto_legacy_inventory_incomplete');
            }
            yield last;
          }
          if (page['hasMore'] == false) break;
          if (last == null ||
              _canonical(page['nextAfter']) !=
                  _canonical(last.tuple.toJson()) ||
              after != null &&
                  CryptoLegacyReceiptTuple.fromJson(
                        after,
                      ).orderKey.compareTo(last.tuple.orderKey) >=
                      0) {
            throw const FormatException('crypto_legacy_inventory_cursor');
          }
          after = last.tuple.toJson();
        }
      }

      CryptoLegacyReceiptDescriptor? current;
      Stream<CryptoLegacyReceiptDescriptor> staged() async* {
        await for (final descriptor in stream()) {
          current = descriptor;
          yield descriptor;
        }
      }

      final root = await CryptoLegacyReceiptInventory.root(
        header,
        staged(),
        claimBinding: (bindingId) async {
          final descriptor = current!;
          final tuple = descriptor.tuple;
          final prior = await db.rows(
            'SELECT 1 FROM crypto_legacy_inventory_rows WHERE partition=? AND certificate_hash=? AND (binding_id=? OR (scope_id=? AND receipt_kind=? AND legacy_id=? AND legacy_device_id=?))',
            [
              partition,
              certHash,
              bindingId,
              tuple.scopeId,
              tuple.kind,
              tuple.legacyId,
              tuple.documentDeviceId ?? '',
            ],
          );
          if (prior.isNotEmpty) return false;
          await db.execute(
            'INSERT INTO crypto_legacy_inventory_rows VALUES(?,?,?,?,?,?,?,?)',
            [
              partition,
              certHash,
              tuple.scopeId,
              tuple.kind,
              tuple.legacyId,
              tuple.documentDeviceId ?? '',
              bindingId,
              descriptor.sourceCommitment,
            ],
          );
          return true;
        },
      );
      if (root != manifestRoot) {
        throw const FormatException('crypto_legacy_inventory_incomplete');
      }
      await _included(event);
      if (!account.directory.isCurrent()) {
        throw const CryptoAuthorityPending('crypto_stale_identity');
      }
      await db.execute(
        'UPDATE crypto_legacy_inventory_certificates SET complete=1 WHERE partition=? AND certificate_hash=? AND manifest_root=?',
        [partition, certHash, root],
      );
      complete = true;
      return VerifiedCryptoLegacyInventory._(
        this,
        capture,
        header,
        certHash,
        event,
        manifestRoot,
      );
    } finally {
      if (!complete) {
        // Keep signed certificates as evidence, drop only incomplete scan rows.
        await db.execute(
          'DELETE FROM crypto_legacy_inventory_rows WHERE partition=? AND certificate_hash=? AND NOT EXISTS(SELECT 1 FROM crypto_legacy_inventory_certificates c WHERE c.partition=? AND c.certificate_hash=? AND c.complete=1)',
          [partition, certHash, partition, certHash],
        );
      }
    }
  });

  Map<String, dynamic> _body(Map<String, dynamic> proof) {
    if (proof.length != 2 || proof['signatureBase64'] is! String) {
      throw const FormatException('crypto_legacy_inventory_authorization');
    }
    final body = CryptoJson.decode(cryptoBase64(proof['commandBase64']));
    if (body is! Map<String, dynamic> ||
        body.length != 8 ||
        body['version'] != 2 ||
        body['signer'] != 'device' ||
        !isCryptoCanonicalUuid(body['deviceId']) ||
        !isCryptoCanonicalUuid(body['requestId']) ||
        body['serverId'] != account.directory.session.profile.serverId ||
        body['accountId'] != account.directory.accountId ||
        body['payload'] is! Map<String, dynamic>) {
      throw const FormatException('crypto_legacy_inventory_authorization');
    }
    return body;
  }

  Future<(Map<String, dynamic>, Map<String, dynamic>, Map<String, dynamic>)>
  _certificate(
    Map<String, dynamic> result,
    CryptoCaptureKeyDescriptor capture,
    String domain,
    String sourceRoot,
  ) async {
    if (result['captureVersion'] != 3 ||
        result['captureId'] != capture.captureId ||
        result['certificateAuthorization'] is! Map<String, dynamic> ||
        result['eventAuthorization'] is! Map<String, dynamic>) {
      throw const CryptoAuthorityPending('crypto_legacy_inventory_pending');
    }
    final proof = result['certificateAuthorization'] as Map<String, dynamic>;
    final event = result['eventAuthorization'] as Map<String, dynamic>;
    final command = _body(proof);
    final payload = command['payload'] as Map<String, dynamic>;
    final rawHeader = payload['header'];
    if (command['operation'] != 'crypto2.migration.legacy.certify' ||
        payload.length != 4 ||
        rawHeader is! Map<String, dynamic> ||
        rawHeader['serverId'] != account.directory.session.profile.serverId ||
        rawHeader['accountId'] != account.directory.accountId ||
        rawHeader['captureId'] != capture.captureId ||
        rawHeader['migrationId'] != capture.migrationId ||
        rawHeader['domain'] != domain ||
        rawHeader['sourceInventoryRoot'] != sourceRoot ||
        payload['manifestRoot'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload['manifestRoot']) ||
        payload['authorDirectoryHeadHash'] is! String) {
      throw const FormatException('crypto_legacy_inventory_context');
    }
    // Validate every header field even for an empty manifest.
    final header = CryptoLegacyReceiptInventory.header(
      serverId: rawHeader['serverId'],
      accountId: rawHeader['accountId'],
      captureId: rawHeader['captureId'],
      migrationId: rawHeader['migrationId'],
      domain: rawHeader['domain'],
      sourceInventoryRoot: rawHeader['sourceInventoryRoot'],
      archiveManifestHash: rawHeader['archiveManifestHash'],
      receiptCount: rawHeader['receiptCount'],
      receiptSelectionHash: rawHeader['receiptSelectionHash'],
    );
    if (CryptoInventoryJson.canonical(header) !=
        CryptoInventoryJson.canonical(rawHeader)) {
      throw const FormatException('crypto_legacy_inventory_context');
    }
    final directory = await access.directoryAt(
      scopeId: capture.rootScopeId,
      scopeHeadHash: '0' * 64,
      accountId: account.directory.accountId,
      directoryHeadHash: payload['authorDirectoryHeadHash'],
    );
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(
        directory.activeDevice(command['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      'JivieE2EE/v2\n',
    );
    final entry = _body(event);
    final p = entry['payload'] as Map;
    if (entry['operation'] != 'crypto2.account.migrationAttest' ||
        p['migrationId'] != capture.migrationId ||
        p['domain'] != domain ||
        p['scopeToken'] !=
            await CryptoLegacyReceiptInventory.scopeToken(header) ||
        p['attestationHash'] != await cryptoSha256(CryptoJson.encode(proof))) {
      throw const FormatException('crypto_legacy_inventory_anchor');
    }
    if (header['receiptSelectionHash'] !=
        await CryptoLegacyReceiptInventory.selectionHash(
          serverId: account.directory.session.profile.serverId,
          accountId: account.directory.accountId,
          captureId: capture.captureId,
          migrationId: capture.migrationId,
          receiptSelections: capture.receiptSelections,
        )) {
      throw const FormatException('crypto_legacy_receipt_selection');
    }
    await _included(event);
    return (header, proof, event);
  }

  Future<void> _included(Map<String, dynamic> proof) async {
    final verified = await account.directory.cachedVerifiedDirectory();
    final row = await account.store.entryByHash(
      account.directory.accountId,
      await cryptoSha256(cryptoBase64(proof['commandBase64'])),
    );
    if (row == null ||
        row['generation'] > verified.generation ||
        _canonical(row['authorization']) != _canonical(proof)) {
      throw const CryptoAuthorityPending(
        'crypto_legacy_inventory_anchor_pending',
      );
    }
  }
}

/// Constructible only after complete root/count and directory inclusion checks.
class VerifiedCryptoLegacyInventory {
  VerifiedCryptoLegacyInventory._(
    this._owner,
    this.capture,
    Map<String, dynamic> header,
    this.certificateHash,
    Map<String, dynamic> event,
    this._manifestRoot,
  ) : header = Map.unmodifiable(header),
      _event = Map.unmodifiable(event);
  final CryptoCaptureLegacyIndex _owner;
  final CryptoCaptureKeyDescriptor capture;
  final Map<String, dynamic> header;
  final String certificateHash, _manifestRoot;
  final Map<String, dynamic> _event;

  /// NULL means proven absent only inside the captured selection. Receipt
  /// evidence is still opened and compared locally before applied/rejected.
  Future<CryptoLegacyReceiptDescriptor?> descriptor(
    CryptoLegacyReceiptTuple tuple,
  ) async {
    if (!_owner.account.directory.isCurrent() ||
        !capture.receiptSelections.any(
          (v) => v['scopeId'] == tuple.scopeId && v['domain'] == tuple.domain,
        ) ||
        tuple.domain != header['domain']) {
      throw const CryptoAuthorityPending(
        'crypto_legacy_receipt_selection_pending',
      );
    }
    await _owner._included(_event);
    // Imported/corrupt partial caches must not manufacture absence even after
    // a handle was created. SQLCipher protects storage, but a complete flag is
    // never a substitute for the signed complete tuple inventory.
    return _owner.account.store.database.transaction(() async {
      final state = await _owner.account.store.database.rows(
        'SELECT manifest_root,header FROM crypto_legacy_inventory_certificates WHERE partition=? AND certificate_hash=? AND complete=1',
        [_owner.partition, certificateHash],
      );
      if (state.length != 1 ||
          state.single['header'] != CryptoInventoryJson.canonical(header) ||
          state.single['manifest_root'] != _manifestRoot ||
          await CryptoLegacyReceiptInventory.root(
                header,
                _owner._storedDescriptors(certificateHash),
                claimBinding: (_) async => true,
              ) !=
              _manifestRoot) {
        throw const CryptoAuthorityPending('crypto_legacy_inventory_pending');
      }
      final rows = await _owner.account.store.database.rows(
        'SELECT r.* FROM crypto_legacy_inventory_rows r JOIN crypto_legacy_inventory_certificates c ON c.partition=r.partition AND c.certificate_hash=r.certificate_hash WHERE r.partition=? AND r.certificate_hash=? AND c.complete=1 AND r.scope_id=? AND r.receipt_kind=? AND r.legacy_id=? AND r.legacy_device_id=?',
        [
          _owner.partition,
          certificateHash,
          tuple.scopeId,
          tuple.kind,
          tuple.legacyId,
          tuple.documentDeviceId ?? '',
        ],
      );
      final complete = await _owner.account.store.database.rows(
        'SELECT 1 FROM crypto_legacy_inventory_certificates WHERE partition=? AND certificate_hash=? AND complete=1',
        [_owner.partition, certificateHash],
      );
      if (complete.length != 1) {
        throw const CryptoAuthorityPending('crypto_legacy_inventory_pending');
      }
      if (rows.isEmpty) return null;
      final row = rows.single;
      return CryptoLegacyReceiptDescriptor(
        tuple: tuple,
        bindingId: row['binding_id'] as String,
        sourceCommitment: row['source_commitment'] as String,
      );
    });
  }
}
