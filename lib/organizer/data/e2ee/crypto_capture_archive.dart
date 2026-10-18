import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show KeyPair;

import 'account_crypto_store.dart';
import 'account_crypto_v2_workflow.dart';
import 'account_directory_repository.dart';
import 'account_directory_v2.dart';
import 'crypto_account_archive.dart';
import 'crypto_archive_cold_database.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_legacy.dart';
import 'crypto_capture_v3.dart';
import 'crypto_identity_store.dart';
import 'crypto_inventory_json.dart';
import 'crypto_migration_idea_files.dart';
import 'crypto_migration_topology.dart';
import 'crypto_finance_topology.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_file_object.dart';
import 'crypto_migration_witness.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';

class _ColdSecure implements AccountCryptoStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

/// The captured SQL source archive is account-private. This source witness
/// proof does not replace required files or cold canonical BUSINESS parity.
class CryptoCaptureArchive {
  CryptoCaptureArchive(
    this.account, {
    Future<CryptoArchiveColdDatabase> Function()? coldDatabase,
  }) : _coldDatabase = coldDatabase ?? CryptoArchiveColdDatabase.create;
  final AccountCryptoV2Workflow account;
  final Future<CryptoArchiveColdDatabase> Function() _coldDatabase;
  String get partition => account.store.partition;
  CryptoArchiveStagingStore _staging(AccountCryptoV2Workflow value) =>
      CryptoArchiveStagingStore(
        database: value.store.database,
        partition: partition,
        crypto: value.directory.reducer.crypto,
      );
  Map<String, dynamic> _header(
    CryptoCaptureKeyDescriptor capture,
    String root,
    int count,
  ) => {
    'kind': 'capture3SourceHeader',
    'captureVersion': 3,
    'serverId': account.directory.session.profile.serverId,
    'accountId': account.directory.accountId,
    'capture': capture.toJson(),
    'sourceInventoryRoot': root,
    'sourceCount': count,
  };

  Future<CryptoArchiveManifest> stageAndUpload(
    CryptoCaptureKeyDescriptor capture,
  ) async {
    final coordinator = CryptoCaptureCoordinator(account);
    final status = await coordinator.verifiedStatus(capture);
    Stream<List<int>> plaintext() async* {
      List<int> frame(Map value) =>
          utf8.encode('${CryptoInventoryJson.canonical(value)}\n');
      yield frame(
        _header(capture, status['inventoryRoot'], status['sourceCount']),
      );
      var after = '', count = 0;
      while (true) {
        final rows = await account.store.database.rows(
          'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? ORDER BY binding_id LIMIT 1',
          [partition, capture.captureId, after],
        );
        if (rows.isEmpty) break;
        final row = rows.single;
        after = row['binding_id'] as String;
        final sourceContext = jsonDecode(row['context'] as String) as Map;
        Map<String, dynamic>? fileObject;
        Map<String, dynamic>? scopeTopology;
        final typedSource = Map<String, dynamic>.from(
          jsonDecode(row['typed_row'] as String),
        );
        if (sourceContext['sourceTable'] == 'familyhub_scopes' &&
            const ['household', 'organization'].contains(
              CryptoMigrationColdEvidence.cells(typedSource)['kind'],
            )) {
          scopeTopology = await CryptoMigrationTopology.load(
            account.store.database,
            partition,
            capture.captureId,
            sourceContext['scopeId'],
            sourceContext['serverId'],
          );
        }
        if (sourceContext['sourceTable'] == 'familyhub_idea_assets') {
          final sidecar = await account.store.database
              .rows('SELECT value FROM local_meta WHERE name=?', [
                CryptoMigrationIdeaFiles.sidecarName(
                  partition,
                  capture.captureId,
                  after,
                ),
              ]);
          if (sidecar.length != 1) {
            throw const CryptoAuthorityPending(
              'crypto_migration_idea_files_pending',
            );
          }
          fileObject = Map<String, dynamic>.from(
            jsonDecode(sidecar.single['value'] as String),
          );
        }
        yield frame({
          'kind': 'source',
          'context': sourceContext,
          if (fileObject != null) 'fileObject': fileObject,
          if (scopeTopology != null) 'scopeTopology': scopeTopology,
          'binding': jsonDecode(row['binding'] as String),
          'typedRow': jsonDecode(row['typed_row'] as String),
        });
        count++;
      }
      if (count != status['sourceCount']) {
        throw const CryptoAuthorityPending('crypto_capture_source_incomplete');
      }
      yield frame({'kind': 'capture3SourceFooter', 'sourceCount': count});
    }

    final staging = _staging(account);
    await staging.restartUnpublishedDraft(
      migrationId: capture.migrationId,
      artifactId: capture.captureId,
      artifactKind: 'capture3SourceWitness',
    );
    final manifest = await staging.stage(
      migrationId: capture.migrationId,
      artifactId: capture.captureId,
      artifactKind: 'capture3SourceWitness',
      plaintext: plaintext(),
    );
    await CryptoAccountArchiveKeyService(account).publish(manifest);
    final queue = coordinator.queue;
    Future<void> send(
      String action,
      String operation,
      Map<String, dynamic> payload,
    ) async {
      final request = await queue.enqueueCommand(
        actionKey: action,
        operation: operation,
        payload: payload,
      );
      await queue.resumeUnresolved(requestIds: {request});
      await queue.commandResult(request);
    }

    for (final segment in manifest.segments) {
      final base = 'capture3:archive:${capture.captureId}:${segment.id}';
      await send('$base:begin', 'crypto2.migration.archiveBegin', {
        'migrationId': capture.migrationId,
        'id': segment.id,
        'size': segment.size,
        'sha256': segment.sha256,
        'manifestBase64': base64Encode(
          CryptoJson.encode({
            'version': 3,
            'keyId': manifest.keyId,
            'index': segment.index,
            'cipherManifestHash': manifest.cipherManifestHash,
          }),
        ),
      });
      var offset = 0;
      await for (final bytes in staging.cipher(segment)) {
        await send('$base:$offset', 'crypto2.migration.archiveChunk', {
          'migrationId': capture.migrationId,
          'id': segment.id,
          'offset': offset,
          'dataBase64': base64Encode(bytes),
        });
        offset += bytes.length;
      }
      await send('$base:complete', 'crypto2.migration.archiveComplete', {
        'migrationId': capture.migrationId,
        'id': segment.id,
      });
    }
    return manifest;
  }

  /// Fresh encrypted SQL and original FILE only. Neither the staging DEK nor
  /// caller-supplied plaintext/complete flags can manufacture this capability.
  Future<VerifiedCryptoCaptureArchive> verifyFromFile({
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required Uint8List externalFile,
  }) => _verifyFromFile(
    capture: capture,
    manifest: manifest,
    externalFile: externalFile,
  );

  /// One full authenticated source scan serves an entire reconciliation/parity
  /// operation. The isolated encrypted cache stays open only for this callback;
  /// no imported command or UI projection is installed into the live database.
  Future<T> withVerifiedSourceFromFile<T>({
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required Uint8List externalFile,
    required Future<T> Function(
      CryptoArchiveColdDatabase cold,
      AccountCryptoV2Workflow coldAccount,
      VerifiedCryptoCaptureArchive verified,
    )
    use,
  }) async {
    late T result;
    await _verifyFromFile(
      capture: capture,
      manifest: manifest,
      externalFile: externalFile,
      use: (cold, coldAccount, verified) async {
        result = await use(cold, coldAccount, verified);
      },
    );
    return result;
  }

  Future<CryptoCapturedLegacyReceipt> readReceiptFromFile({
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required Uint8List externalFile,
    required CryptoLegacyReceiptDescriptor receipt,
  }) async {
    final verified = await _verifyFromFile(
      capture: capture,
      manifest: manifest,
      externalFile: externalFile,
      selected: receipt,
    );
    final value = verified._receipt;
    if (value == null) {
      throw const CryptoAuthorityPending(
        'crypto_legacy_receipt_evidence_pending',
      );
    }
    return value;
  }

  Future<VerifiedCryptoCaptureArchive> _verifyFromFile({
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required Uint8List externalFile,
    CryptoLegacyReceiptDescriptor? selected,
    Future<void> Function(
      CryptoArchiveColdDatabase,
      AccountCryptoV2Workflow,
      VerifiedCryptoCaptureArchive,
    )?
    use,
  }) async {
    if (manifest.migrationId != capture.migrationId ||
        manifest.artifactId != capture.captureId ||
        manifest.artifactKind != 'capture3SourceWitness') {
      throw const FormatException('crypto_capture_archive_context');
    }
    final cold = await _coldDatabase();
    CryptoKeyLease? archiveKey, captureKey;
    CryptoCapturedLegacyReceipt? selectedReceipt;
    var returned = false;
    try {
      final crypto = account.directory.reducer.crypto;
      final coldAccount = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: account.directory.reducer,
          session: account.directory.session,
          transport: account.directory.transport,
          store: CryptoIdentityStore(cold.database, _ColdSecure(), partition),
          isCurrent: account.directory.isCurrent,
        ),
      );
      for (final table in const [
        'crypto_identity_secrets',
        'crypto_archive_secrets',
        'crypto_capture_keys',
        'crypto_outbox',
        'crypto_directory_entries',
      ]) {
        if ((await cold.database.rows(
          'SELECT 1 FROM $table LIMIT 1',
        )).isNotEmpty) {
          throw const FormatException('crypto_capture_cold_database_not_empty');
        }
      }
      final inspected = account.files.inspect(
        externalFile,
        serverId: account.directory.session.profile.serverId,
        accountId: account.directory.accountId,
      );
      final directory = await coldAccount.directory.refresh(
        externalFingerprint: inspected['fingerprint'],
      );
      if (directory == null) {
        throw const CryptoAuthorityPending('crypto_capture_identity_pending');
      }
      final status = await coldAccount.status();
      final cipher = cryptoBase64(status['keyringCiphertextBase64']);
      if (await cryptoSha256(cipher) !=
          directory.snapshot['recoveryRootCiphertextHash']) {
        throw const FormatException('crypto_capture_recovery_bundle');
      }
      final recovered = account.files.open(
        file: externalFile,
        encryptedRoot: CryptoJson.decode(cipher) as Map<String, dynamic>,
        serverId: directory.serverId,
        accountId: directory.accountId,
        expectedFingerprint: inspected['fingerprint'],
      );
      late Map<String, dynamic> captured;
      try {
        Future<KeyPair?> recoveryKey(String public) async {
          for (final pair in [
            recovered.encryption,
            ...recovered.historicalEncryption,
          ]) {
            if (base64Encode(pair.publicKey) != public) continue;
            final raw = pair.secretKey.extractBytes();
            try {
              return KeyPair(
                publicKey: Uint8List.fromList(pair.publicKey),
                secretKey: crypto.sodium.secureCopy(raw),
              );
            } finally {
              raw.fillRange(0, raw.length, 0);
            }
          }
          return null;
        }

        captureKey = await CryptoCaptureKeyService(coldAccount).open(
          capture,
          recoveryOnly: true,
          recoveryDirectory: directory,
          recoveryKey: recoveryKey,
        );
        final keys = CryptoAccountArchiveKeyService(coldAccount);
        archiveKey = await keys.openBoundKey(
          keyId: manifest.keyId,
          expectedContext: keys.context(manifest),
          recoveryOnly: true,
          recoveryDirectory: directory,
          recoveryKey: recoveryKey,
        );
        captured = await CryptoCaptureCoordinator(
          coldAccount,
        ).verifiedStatus(capture);
      } finally {
        recovered.dispose();
      }
      final staging = _staging(coldAccount);
      for (final segment in manifest.segments) {
        Stream<List<int>> download() async* {
          var offset = 0;
          while (offset < segment.size) {
            final page = await account.directory
                .call('crypto2.migration.archiveGet', {
                  'migrationId': capture.migrationId,
                  'id': segment.id,
                  'offset': offset,
                });
            if (page['id'] != segment.id ||
                page['complete'] != true ||
                page['size'] != segment.size ||
                page['sha256'] != segment.sha256 ||
                page['offset'] != offset) {
              throw const FormatException('crypto_capture_archive_remote');
            }
            final description =
                CryptoJson.decode(cryptoBase64(page['manifestBase64'])) as Map;
            if (description['version'] != 3 ||
                description['keyId'] != manifest.keyId ||
                description['cipherManifestHash'] !=
                    manifest.cipherManifestHash ||
                description['index'] != segment.index) {
              throw const FormatException('crypto_capture_archive_manifest');
            }
            final bytes = cryptoBase64(
              page['dataBase64'],
              max: CryptoArchiveStagingStore.chunkSize,
            );
            if (bytes.isEmpty || page['nextOffset'] != offset + bytes.length) {
              throw const FormatException('crypto_capture_archive_cursor');
            }
            offset += bytes.length;
            yield bytes;
          }
        }

        await staging.importSegment(
          manifest: manifest,
          segment: segment,
          ciphertext: download(),
        );
      }
      var count = 0, headerSeen = false, footerSeen = false;
      final receiptCounts = {'content': 0, 'finance': 0};
      await for (final line in _lines(staging.open(manifest, archiveKey.key))) {
        final frame = jsonDecode(line);
        if (frame is! Map<String, dynamic> || footerSeen) {
          throw const FormatException('crypto_capture_archive_frame');
        }
        if (!headerSeen) {
          if (CryptoInventoryJson.canonical(frame) !=
              CryptoInventoryJson.canonical(
                _header(
                  capture,
                  captured['inventoryRoot'],
                  captured['sourceCount'],
                ),
              )) {
            throw const FormatException('crypto_capture_archive_context');
          }
          headerSeen = true;
          continue;
        }
        if (frame['kind'] == 'capture3SourceFooter' &&
            frame.length == 2 &&
            frame['sourceCount'] == count) {
          footerSeen = true;
          continue;
        }
        if (frame['kind'] != 'source' ||
            !const {4, 5}.contains(frame.length) ||
            frame['typedRow'] is! Map<String, dynamic>) {
          throw const FormatException('crypto_capture_archive_frame');
        }
        final context = CryptoCaptureSourceContext.fromJson(
          Map<String, dynamic>.from(frame['context'] as Map),
        );
        final binding = CryptoCaptureBinding.fromJson(
          frame['binding'] as Map<String, dynamic>,
        );
        final asset = context.sourceTable == 'familyhub_idea_assets';
        final topology =
            context.sourceTable == 'familyhub_scopes' &&
            const ['household', 'organization'].contains(
              CryptoMigrationColdEvidence.cells(
                Map<String, dynamic>.from(frame['typedRow']),
              )['kind'],
            );
        if (frame.length != (asset || topology ? 5 : 4) ||
            frame.keys.any(
              (k) => !{
                'kind',
                'context',
                'binding',
                'typedRow',
                if (asset) 'fileObject',
                if (topology) 'scopeTopology',
              }.contains(k),
            ) ||
            asset && frame['fileObject'] is! Map ||
            topology && frame['scopeTopology'] is! Map) {
          throw const FormatException('crypto_capture_archive_file_sidecar');
        }

        if (context.serverId != directory.serverId ||
            context.accountId != directory.accountId ||
            context.captureId != capture.captureId ||
            context.migrationId != capture.migrationId ||
            await CryptoCaptureV3.bindingId(captureKey.key, context) !=
                binding.bindingId ||
            ++count > captured['sourceCount']) {
          throw const FormatException('crypto_capture_archive_source');
        }
        final duplicate = await cold.database.rows(
          'SELECT 1 FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND (binding_id=? OR context=?)',
          [
            partition,
            capture.captureId,
            binding.bindingId,
            CryptoInventoryJson.canonical(context.toJson()),
          ],
        );
        if (duplicate.isNotEmpty) {
          throw const FormatException('crypto_capture_archive_duplicate');
        }
        final salt = await CryptoCaptureV3.salt(captureKey.key, context);
        try {
          final witness = <String, dynamic>{
            'version': 3,
            'context': context.toJson(),
            'typedRow': frame['typedRow'],
            'saltBase64': base64Encode(salt),
          };
          await CryptoCaptureV3.verifyWitness(
            binding: binding,
            context: context,
            witness: witness,
          );
          if (selected != null && binding.bindingId == selected.bindingId) {
            if (selectedReceipt != null) {
              throw const FormatException('crypto_capture_archive_duplicate');
            }
            selectedReceipt = await CryptoCapturedLegacyReceipt.fromWitness(
              descriptor: selected,
              context: context,
              witness: witness,
            );
          }
        } finally {
          salt.fillRange(0, salt.length, 0);
        }
        await cold.database
            .execute('INSERT INTO crypto_capture_sources VALUES(?,?,?,?,?,?)', [
              partition,
              capture.captureId,
              binding.bindingId,
              CryptoInventoryJson.canonical(context.toJson()),
              CryptoInventoryJson.canonical(frame['typedRow']),
              CryptoInventoryJson.canonical(binding.toJson()),
            ]);
        if (asset) {
          final sidecar = Map<String, dynamic>.from(frame['fileObject'] as Map);
          if (sidecar.length != 3 ||
              !sidecar.keys.toSet().containsAll({
                'context',
                'object',
                'authorization',
              })) {
            throw const FormatException('crypto_capture_archive_file_sidecar');
          }
          final fileContext = CryptoMigrationWitnessContext(
            Map<String, dynamic>.from(sidecar['context'] as Map),
          );
          fileContext.requireSource(context);
          if (fileContext.value['bindingId'] != binding.bindingId ||
              fileContext.value['sourceInventoryRoot'] !=
                  captured['inventoryRoot'] ||
              fileContext.value['sourceCommitment'] !=
                  binding.sourceCommitment ||
              fileContext.value['type'] != 'idea' ||
              fileContext.value['canonicalId'] !=
                  CryptoMigrationIdeaFiles.cell(
                    frame['typedRow'] as Map,
                    'board_id',
                  )) {
            throw const FormatException('crypto_capture_archive_file_sidecar');
          }
          CryptoMigrationFileObject.descriptor(
            fileContext,
            sidecar['object'] as Map,
          );
          // Preparatory cache only. Full cold business comparison still checks
          // the original signed begin and the actual decrypted image bytes.
          await cold.database.execute('INSERT INTO local_meta VALUES(?,?)', [
            CryptoMigrationIdeaFiles.sidecarName(
              partition,
              capture.captureId,
              binding.bindingId,
            ),
            CryptoInventoryJson.canonical(sidecar),
          ]);
        }
        if (topology) {
          final value = Map<String, dynamic>.from(
            frame['scopeTopology'] as Map,
          );
          await CryptoFinanceTopology.validate(
            value,
            serverId: context.serverId,
            scopeId: context.scopeId!,
          );
          if (value['generation'] != 0) {
            throw const FormatException('crypto_finance_topology_link');
          }
          await cold.database
              .execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
                CryptoMigrationTopology.name(
                  partition,
                  capture.captureId,
                  context.scopeId!,
                ),
                CryptoInventoryJson.canonical(value),
              ]);
        }
        final kind = switch (context.sourceTable) {
          'familyhub_operations' => 'records',
          'familyhub_finance_operations' => 'finance',
          'familyhub_document_requests' => 'documents',
          _ => null,
        };
        if (kind != null) {
          String text(String column) => utf8.decode(
            cryptoBase64(frame['typedRow'][column]['valueBase64']),
          );
          final tuple = CryptoLegacyReceiptTuple(
            scopeId: text('scope_id'),
            kind: kind,
            legacyId: text(kind == 'documents' ? 'request_id' : 'id'),
            documentDeviceId: kind == 'documents' ? text('device_id') : null,
          );
          receiptCounts[tuple.domain] = receiptCounts[tuple.domain]! + 1;
          await cold.database.execute(
            'INSERT INTO crypto_legacy_inventory_rows VALUES(?,?,?,?,?,?,?,?)',
            [
              partition,
              capture.captureId,
              tuple.scopeId,
              tuple.kind,
              tuple.legacyId,
              tuple.documentDeviceId ?? '',
              binding.bindingId,
              binding.sourceCommitment,
            ],
          );
        }
      }
      Stream<CryptoCaptureBinding> bindings() async* {
        var after = '';
        while (true) {
          final rows = await cold.database.rows(
            'SELECT binding_id,binding FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? ORDER BY binding_id LIMIT 32',
            [partition, capture.captureId, after],
          );
          if (rows.isEmpty) return;
          for (final row in rows) {
            after = row['binding_id'] as String;
            yield CryptoCaptureBinding.fromJson(
              jsonDecode(row['binding'] as String) as Map<String, dynamic>,
            );
          }
        }
      }

      if (!headerSeen ||
          !footerSeen ||
          count != captured['sourceCount'] ||
          await CryptoCaptureV3.inventoryRoot(
                serverId: directory.serverId,
                captureId: capture.captureId,
                migrationId: capture.migrationId,
                accountId: directory.accountId,
                sourceCount: count,
                bindings: bindings(),
              ) !=
              captured['inventoryRoot']) {
        throw const FormatException('crypto_capture_archive_incomplete');
      }
      final roots = <String, String>{};
      for (final domain in const ['content', 'finance']) {
        Stream<CryptoLegacyReceiptDescriptor> descriptors() async* {
          var cursor = ['', '', '', ''];
          while (true) {
            final rows = await cold.database.rows(
              'SELECT * FROM crypto_legacy_inventory_rows WHERE partition=? AND certificate_hash=? AND '
              '${domain == 'finance' ? "receipt_kind='finance'" : "receipt_kind IN ('records','documents')"} '
              'AND (scope_id,receipt_kind,legacy_id,legacy_device_id)>(?,?,?,?) '
              'ORDER BY scope_id,receipt_kind,legacy_id,legacy_device_id LIMIT 128',
              [partition, capture.captureId, ...cursor],
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

        roots[domain] = await CryptoLegacyReceiptInventory.root(
          CryptoLegacyReceiptInventory.header(
            serverId: directory.serverId,
            accountId: directory.accountId,
            captureId: capture.captureId,
            migrationId: capture.migrationId,
            domain: domain,
            sourceInventoryRoot: captured['inventoryRoot'],
            archiveManifestHash: manifest.cipherManifestHash,
            receiptCount: receiptCounts[domain]!,
            receiptSelectionHash:
                await CryptoLegacyReceiptInventory.selectionHash(
                  serverId: directory.serverId,
                  accountId: directory.accountId,
                  captureId: capture.captureId,
                  migrationId: capture.migrationId,
                  receiptSelections: capture.receiptSelections,
                ),
          ),
          descriptors(),
          claimBinding: (_) async => true,
        );
      }
      if (selected != null && selectedReceipt == null) {
        throw const CryptoAuthorityPending(
          'crypto_legacy_receipt_evidence_pending',
        );
      }
      final verified = VerifiedCryptoCaptureArchive._(
        capture,
        manifest,
        captured['inventoryRoot'],
        count,
        Map.unmodifiable(receiptCounts),
        Map.unmodifiable(roots),
        selectedReceipt,
      );
      await use?.call(cold, coldAccount, verified);
      returned = true;
      return verified;
    } finally {
      if (!returned && selectedReceipt != null) {
        selectedReceipt.responseBytes.fillRange(
          0,
          selectedReceipt.responseBytes.length,
          0,
        );
      }
      captureKey?.release();
      archiveKey?.release();
      await cold.close();
    }
  }

  Stream<String> _lines(Stream<List<int>> bytes) async* {
    var line = BytesBuilder(copy: false), length = 0;
    await for (final chunk in bytes) {
      var start = 0;
      for (var index = 0; index < chunk.length; index++) {
        if (chunk[index] != 10) continue;
        final piece = chunk.sublist(start, index);
        if (length + piece.length > 32 * 1024 * 1024) {
          throw const CryptoAuthorityPending(
            'crypto_capture_source_frame_too_large',
          );
        }
        line.add(piece);
        yield utf8.decode(line.takeBytes());
        line = BytesBuilder(copy: false);
        length = 0;
        start = index + 1;
      }
      final tail = chunk.sublist(start);
      length += tail.length;
      if (length > 32 * 1024 * 1024) {
        throw const CryptoAuthorityPending(
          'crypto_capture_source_frame_too_large',
        );
      }
      line.add(tail);
    }
    if (length != 0) {
      throw const FormatException('crypto_capture_archive_truncated');
    }
  }
}

/// In-memory evidence capability. Never recreated from a copied SQL flag.
class VerifiedCryptoCaptureArchive {
  VerifiedCryptoCaptureArchive._(
    this.capture,
    this.manifest,
    this.sourceInventoryRoot,
    this.sourceCount,
    this.receiptCounts,
    this.receiptRoots,
    this._receipt,
  );
  final CryptoCaptureKeyDescriptor capture;
  final CryptoArchiveManifest manifest;
  final String sourceInventoryRoot;
  final int sourceCount;
  final Map<String, int> receiptCounts;
  final Map<String, String> receiptRoots;
  final CryptoCapturedLegacyReceipt? _receipt;
}
