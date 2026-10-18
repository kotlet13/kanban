import 'crypto_migration_task_dependency.dart';
import 'crypto_migration_idea_files.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../collaboration_database.dart';
import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart';
import 'crypto_account_archive.dart';
import 'crypto_archive_cold_database.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_v3.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_business_parity_v3.dart';
import 'crypto_migration_audit.dart';
import 'crypto_migration_invitation_control.dart';
import 'crypto_migration_notification_control.dart';
import 'crypto_migration_structure_control.dart';
import 'crypto_migration_receipt_control.dart';
import 'crypto_migration_local_artifact.dart';
import 'crypto_migration_local_artifact_cold.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_migration_stage_verifier.dart';
import 'crypto_migration_witness.dart';
import 'crypto_migration_witness_transport.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// A source from the complete FILE-authenticated archive, never a server's
/// unverified selected list. Raw SQL cells remain private to this cold process.
class CryptoMigrationColdSource {
  CryptoMigrationColdSource._(this.context, this.binding, this.typedRow);
  final CryptoCaptureSourceContext context;
  final CryptoCaptureBinding binding;
  final Map<String, dynamic> typedRow;

  /// Read only within withVerifiedSourceFromFile's isolated database callback.
  /// This is not independent source authority: the consuming closed adapter
  /// still authenticates its exact artifact/witness, and final parity refolds
  /// the COMPLETE source inventory before any signed verification is produced.
  static Future<CryptoMigrationColdSource> load(
    CryptoBusinessSession runtime,
    VerifiedCryptoCaptureArchive archive,
    String bindingId,
  ) async {
    final rows = await runtime.db.rows(
      'SELECT context,binding,typed_row FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id=?',
      [runtime.partition, archive.capture.captureId, bindingId],
    );
    if (rows.length != 1) {
      throw const FormatException('crypto_business_parity_coverage');
    }
    final row = rows.single;
    final context = CryptoCaptureSourceContext.fromJson(
      jsonDecode(row['context'] as String),
    );
    final binding = CryptoCaptureBinding.fromJson(
      jsonDecode(row['binding'] as String),
    );
    if (context.captureId != archive.capture.captureId ||
        context.migrationId != archive.capture.migrationId ||
        context.accountId != runtime.account.directory.accountId ||
        context.serverId !=
            runtime.account.directory.session.profile.serverId ||
        binding.bindingId != bindingId ||
        binding.scopeId != context.scopeId ||
        binding.domain != context.domain) {
      throw const FormatException('crypto_business_parity_context');
    }
    return CryptoMigrationColdSource._(
      context,
      binding,
      Map<String, dynamic>.from(jsonDecode(row['typed_row'] as String) as Map),
    );
  }
}

/// Closed control modules verify their actual transformation and finish with a
/// complete pre-certificate selection root. No module receives WRITE authority.
abstract interface class CryptoMigrationColdControl {
  Future<String> verify(CryptoMigrationColdSource source);
  Future<Map<String, dynamic>> finish();
}

/// This capability is minted only after a new encrypted database has decrypted
/// the account archive, projected all canonical candidates, checked actual file
/// bytes, and compared every captured binding through its closed adapter.
class VerifiedCryptoMigrationColdBusiness {
  VerifiedCryptoMigrationColdBusiness._(
    this.header,
    this.summary,
    this.controlSections,
    this.scopedAuditSections,
  );
  final Map<String, dynamic> header, summary;
  final Map<String, Map<String, dynamic>> controlSections;
  final Map<String, Map<String, dynamic>> scopedAuditSections;
}

/// Production cold comparison, deliberately separate from account recovery and
/// live projection. It never calls recoverEpoch, installs commands in the live
/// queue, or promotes a candidate scope/foreign identity to an authority floor.
class CryptoMigrationColdBusiness {
  CryptoMigrationColdBusiness(this.account, {this.coldDatabase});
  final AccountCryptoV2Workflow account;
  final Future<CryptoArchiveColdDatabase> Function()? coldDatabase;

  /// Independent owner-content source prerequisite. It cannot produce a
  /// full business parity token or depend on a child/finance contributor's
  /// future verification. Only the selected metadata proof is materialized;
  /// all original structural cells still come from the complete FILE archive.
  Future<VerifiedCryptoMigrationStructureSource> verifyStructureSource({
    CryptoCaptureArchive? archive,
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required Uint8List externalFile,
    required String scopeId,
  }) => _isolatedStructure(
    archive: archive,
    capture: capture,
    manifest: manifest,
    externalFile: externalFile,
    scopeId: scopeId,
    sourceOnly: true,
    use: (runtime, source) => CryptoMigrationStructureControl(
      runtime,
      source,
      recoveryFile: externalFile,
    ).contentSource(scopeId),
  );

  /// Control-only test/production prerequisite; never a substitute for the
  /// complete mandatory five-module FILE business comparison before verify3.
  Future<Map<String, dynamic>> verifyStructureControl({
    CryptoCaptureArchive? archive,
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required Uint8List externalFile,
    required String scopeId,
  }) => _isolatedStructure(
    archive: archive,
    capture: capture,
    manifest: manifest,
    externalFile: externalFile,
    scopeId: scopeId,
    sourceOnly: false,
    use: (runtime, source) => CryptoMigrationStructureControl(
      runtime,
      source,
      recoveryFile: externalFile,
    ).finish(),
  );

  Future<T> _isolatedStructure<T>({
    required CryptoCaptureArchive? archive,
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required Uint8List externalFile,
    required String scopeId,
    required bool sourceOnly,
    required Future<T> Function(
      CryptoBusinessSession,
      VerifiedCryptoCaptureArchive,
    )
    use,
  }) => (archive ?? CryptoCaptureArchive(account, coldDatabase: coldDatabase))
      .withVerifiedSourceFromFile(
        capture: capture,
        manifest: manifest,
        externalFile: externalFile,
        use: (cold, coldAccount, source) async {
          final runtime = CryptoBusinessSession(
            coldAccount,
            SessionCryptoAccess(account: coldAccount),
            cold.database,
          );
          _configure(runtime);
          await _schema(runtime.db);
          final info = coldAccount.files.inspect(
            externalFile,
            serverId: coldAccount.directory.session.profile.serverId,
            accountId: coldAccount.directory.accountId,
          );
          final own = await coldAccount.directory.replayFileAnchoredCandidate(
            info['fingerprint'],
          );
          final verifier = CryptoMigrationStageVerifier(runtime);
          await _plan(
            runtime,
            source,
            verifier,
            own,
            scopeOnly: sourceOnly ? null : scopeId,
            domainOnly: sourceOnly ? 'content' : null,
            metadataOnly: sourceOnly,
          );
          await _canonical(runtime, source, verifier, own, externalFile);
          final result = await use(runtime, source);
          if ((await runtime.db.rows(
                'SELECT 1 FROM crypto_outbox LIMIT 1',
              )).isNotEmpty ||
              (await runtime.db.rows(
                'SELECT 1 FROM crypto_identity_secrets LIMIT 1',
              )).isNotEmpty ||
              (await runtime.db.rows(
                'SELECT 1 FROM crypto_scope_keys WHERE write_ready<>0 LIMIT 1',
              )).isNotEmpty) {
            throw const FormatException('crypto_migration_cold_effect');
          }
          return result;
        },
      );

  /// Production modules are closed and mandatory, including empty selections.
  /// The artifact argument is still a candidate: FILE verification below opens
  /// actual SERVER bytes in the same fresh isolated database first.
  Future<VerifiedCryptoMigrationColdBusiness> verifyProduction({
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required Uint8List recoveryFile,
    required CryptoStagedMigrationLocalArtifact localArtifact,
  }) => verify(
    capture: capture,
    manifest: manifest,
    recoveryFile: recoveryFile,
    controls: (runtime, source) async {
      final local = await verifyCryptoMigrationLocalArtifact(
        runtime: runtime,
        source: source,
        recoveryFile: recoveryFile,
        descriptor: localArtifact.descriptor,
        ownEvent: localArtifact.event,
      );
      return {
        'audit': CryptoMigrationAuditColdControl(runtime, source, recoveryFile),
        'invitations': CryptoMigrationInvitationControl(
          runtime,
          source,
          recoveryFile: recoveryFile,
        ),
        'notifications': CryptoMigrationNotificationControl(
          runtime,
          source,
          recoveryFile: recoveryFile,
        ),
        'structure': CryptoMigrationStructureControl(
          runtime,
          source,
          recoveryFile: recoveryFile,
        ),
        'receipts': CryptoMigrationReceiptControl(runtime, source, local),
      };
    },
  );

  /// Only a capability from the fresh FILE comparison reaches this producer.
  /// The server independently reconstructs its entire captured artifact stream.
  Future<Map<String, dynamic>> publishVerification(
    VerifiedCryptoMigrationColdBusiness verified,
    CryptoStagedMigrationLocalArtifact localArtifact,
  ) async {
    final h = verified.header, c = localArtifact.descriptor['context'] as Map;
    for (final k in [
      'serverId',
      'migrationId',
      'captureId',
      'accountId',
      'sourceInventoryRoot',
    ]) {
      if (h[k] != c[k]) {
        throw const FormatException('crypto_business_parity_context');
      }
    }
    final queue = CryptoCaptureCoordinator(account).queue;
    final request = await queue.enqueueCommand(
      actionKey: 'migrationVerify3:${h['captureId']}',
      operation: 'crypto2.migration.verify3',
      payload: {
        'header': h,
        'summary': verified.summary,
        'localIntent': {
          'descriptor': localArtifact.descriptor,
          'eventAuthorization': localArtifact.event,
        },
      },
    );
    await queue.resumeUnresolved(requestIds: {request});
    return queue.commandResult(request);
  }

  Future<Map<String, dynamic>> verificationAuthorization(
    VerifiedCryptoMigrationColdBusiness verified,
  ) async {
    final rows = await account.store.database.rows(
      "SELECT o.signed_body,o.response FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=? AND o.state='applied'",
      [
        account.store.partition,
        'migrationVerify3:${verified.header['captureId']}',
      ],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_business_parity_receipt_pending',
      );
    }
    final proof = Map<String, dynamic>.from(
      jsonDecode(rows.single['signed_body'] as String) as Map,
    );
    final body = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final receipt = jsonDecode(rows.single['response'] as String) as Map;
    final result = receipt['response'] as Map;
    if (body['operation'] != 'crypto2.migration.verify3' ||
        CryptoInventoryJson.canonical(body['payload']['header']) !=
            CryptoInventoryJson.canonical(verified.header) ||
        CryptoInventoryJson.canonical(body['payload']['summary']) !=
            CryptoInventoryJson.canonical(verified.summary) ||
        result['version'] != 3 ||
        result['coldParityProofHash'] !=
            await cryptoSha256(CryptoJson.encode(proof)) ||
        CryptoInventoryJson.canonical(result['summary']) !=
            CryptoInventoryJson.canonical(verified.summary)) {
      throw const FormatException('crypto_business_parity_receipt');
    }
    return Map.unmodifiable(proof);
  }

  Future<VerifiedCryptoMigrationColdBusiness> verify({
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required Uint8List recoveryFile,
    required FutureOr<Map<String, CryptoMigrationColdControl>> Function(
      CryptoBusinessSession runtime,
      VerifiedCryptoCaptureArchive source,
    )
    controls,
  }) async {
    // Still a candidate aggregate. Final verify/cutover separately binds this
    // exact complete aggregate to manager certificates and directory events.
    final component = await CryptoCaptureCoordinator(
      account,
    ).componentCandidate(capture);
    return CryptoCaptureArchive(
      account,
      coldDatabase: coldDatabase,
    ).withVerifiedSourceFromFile(
      capture: capture,
      manifest: manifest,
      externalFile: recoveryFile,
      use: (cold, coldAccount, source) async {
        final db = cold.database, p = coldAccount.store.partition;
        final access = SessionCryptoAccess(account: coldAccount);
        final runtime = CryptoBusinessSession(coldAccount, access, db);
        _configure(runtime);
        await _schema(db);
        final modules = await controls(runtime, source);
        if (modules.length != 5 ||
            !modules.keys.toSet().containsAll(
              CryptoMigrationBusinessParityV3.requiredSections,
            )) {
          throw const FormatException(
            'crypto_business_parity_controls_pending',
          );
        }
        final fileInfo = coldAccount.files.inspect(
          recoveryFile,
          serverId: coldAccount.directory.session.profile.serverId,
          accountId: coldAccount.directory.accountId,
        );
        final own = await coldAccount.directory.replayFileAnchoredCandidate(
          fileInfo['fingerprint'],
        );
        final verifier = CryptoMigrationStageVerifier(runtime);
        // Bounded pages retain candidate bytes only in the isolated encrypted
        // database; no full record/source array is assembled in memory.
        await _plan(runtime, source, verifier, own);
        await _ideaFiles(runtime, source, recoveryFile);
        await _canonical(runtime, source, verifier, own, recoveryFile);
        String? after;
        var sourceCount = 0;
        while (true) {
          final rows = await db.rows(
            'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=?'
            '${after == null ? '' : ' AND binding_id>?'} ORDER BY binding_id LIMIT 20',
            [p, capture.captureId, if (after != null) after],
          );
          if (rows.isEmpty) break;
          for (final row in rows) {
            final item = _source(row);
            after = item.binding.bindingId;
            sourceCount++;
            final adapter = CryptoMigrationBusinessParityV3.sourceAdapter(
              item.context.sourceTable,
            );
            if (adapter == 'canonical' || adapter == 'canonicalFile') {
              final covered = await db.rows(
                'SELECT 1 FROM cold_migration_frames WHERE tag=? AND sort_key=?',
                ['binding', after],
              );
              if (covered.length != 1) {
                throw const CryptoAuthorityPending(
                  'crypto_migration_canonical_coverage_pending',
                );
              }
              continue;
            }
            late String artifact;
            if (adapter == 'sourceContext' ||
                adapter == 'moderationDisclosure') {
              // Exact original disclosed/context rows were already decrypted
              // and HMAC-compared by the full private source archive verifier.
              artifact = await cryptoSha256([
                ...utf8.encode('JivieMigrationPrivateArtifact/v3\n'),
                ...CryptoInventoryJson.encode({
                  'version': 3,
                  'adapter': adapter,
                  'binding': item.binding.toJson(),
                }),
              ]);
            } else {
              final kind = switch (adapter) {
                'structure' => 'structure',
                'notification' => 'notifications',
                'invitation' => 'invitations',
                'immutableReceipt' => 'receipts',
                'auditHistory' => 'audit',
                _ => throw const FormatException(
                  'crypto_business_parity_adapter_pending',
                ),
              };
              artifact = await modules[kind]!.verify(item);
            }
            await _frame(db, 'binding', after, {
              'binding': item.binding.toJson(),
              'adapter': adapter,
              'primaryRecordProofHash': null,
              'companionProofHashes': <String>[],
              'artifactHash': artifact,
            });
          }
        }
        if (sourceCount != source.sourceCount) {
          throw const FormatException('crypto_business_parity_coverage');
        }
        final controlSections = <String, Map<String, dynamic>>{};
        for (final kind in (modules.keys.toList()..sort())) {
          final section = await modules[kind]!.finish();
          if (section['kind'] != kind) {
            throw const FormatException('crypto_business_parity_section');
          }
          controlSections[kind] = Map.unmodifiable(section);
          await _frame(db, 'section', kind, section);
        }
        final audit = modules['audit'];
        if (audit is! CryptoMigrationAuditColdControl) {
          throw const CryptoAuthorityPending(
            'crypto_migration_scoped_audit_pending',
          );
        }
        final scopes = <String>{
          ...capture.scopeIds,
          for (final selection in capture.receiptSelections)
            selection['scopeId'] as String,
        }.toList()..sort();
        final scopedAuditSections = <String, Map<String, dynamic>>{};
        for (final scope in scopes) {
          final section = await audit.scopedSection(scope);
          CryptoMigrationBusinessParityV3.scopedAudit({'audit': section});
          scopedAuditSections[scope] = Map.unmodifiable(section);
        }
        // The source verifier creates no signing/device keys or queued work;
        // no adapter may turn this read-only comparison into active recovery.
        if ((await db.rows('SELECT 1 FROM crypto_outbox LIMIT 1')).isNotEmpty ||
            (await db.rows(
              'SELECT 1 FROM crypto_identity_secrets LIMIT 1',
            )).isNotEmpty ||
            (await db.rows(
              'SELECT 1 FROM crypto_scope_keys WHERE write_ready<>0 LIMIT 1',
            )).isNotEmpty) {
          throw const FormatException('crypto_migration_cold_effect');
        }
        final header = <String, dynamic>{
          'version': 3,
          'serverId': coldAccount.directory.session.profile.serverId,
          'migrationId': capture.migrationId,
          'captureId': capture.captureId,
          'componentId': capture.componentId,
          'componentCommitment': component['componentCommitment'],
          'accountId': coldAccount.directory.accountId,
          'sourceInventoryRoot': source.sourceInventoryRoot,
          'sourceCount': source.sourceCount,
          'archiveManifestHash': manifest.cipherManifestHash,
        };
        final summary = await CryptoMigrationBusinessParityV3.compute(
          header: header,
          frames: _frames(db),
        );
        // Retain only public/blinded comparison frames in the encrypted live
        // database. The capability's immutable full stream root is rechecked
        // before any later contributor consumes these derived coordinates.
        final live = account.store.database;
        await _verifiedFrameSchema(live);
        final run = await cryptoSha256(
          CryptoInventoryJson.encode({'header': header, 'summary': summary}),
        );
        await live.transaction(() async {
          for (final tag in ['binding', 'file', 'proofBlob', 'section']) {
            String? cursor;
            while (true) {
              final page = await db.rows(
                'SELECT sort_key,value FROM cold_migration_frames WHERE tag=?'
                '${cursor == null ? '' : ' AND sort_key>?'} ORDER BY sort_key LIMIT 20',
                [tag, if (cursor != null) cursor],
              );
              if (page.isEmpty) break;
              for (final row in page) {
                cursor = row['sort_key'] as String;
                await live.execute(
                  'INSERT OR IGNORE INTO crypto_migration_verified_frames(partition,run_hash,tag,sort_key,value) VALUES(?,?,?,?,?)',
                  [account.store.partition, run, tag, cursor, row['value']],
                );
              }
            }
          }
        });
        return VerifiedCryptoMigrationColdBusiness._(
          Map.unmodifiable(header),
          Map.unmodifiable(summary),
          Map.unmodifiable(controlSections),
          Map.unmodifiable(scopedAuditSections),
        );
      },
    );
  }

  Future<void> _verifiedFrameSchema(CollaborationDatabase db) => db.execute(
    'CREATE TABLE IF NOT EXISTS crypto_migration_verified_frames('
    'partition TEXT NOT NULL,run_hash TEXT NOT NULL,tag TEXT NOT NULL,'
    'sort_key TEXT NOT NULL,value TEXT NOT NULL,'
    'PRIMARY KEY(partition,run_hash,tag,sort_key))',
  );

  /// Derived cache rows never mint source authority. Re-fold the entire closed
  /// stream against the already minted FILE capability before yielding facts.
  Stream<Map<String, dynamic>> verifiedFrames(
    VerifiedCryptoMigrationColdBusiness verified,
  ) async* {
    if (verified.header['accountId'] != account.directory.accountId ||
        verified.header['serverId'] !=
            account.directory.session.profile.serverId) {
      throw const FormatException('crypto_business_parity_context');
    }
    final run = await cryptoSha256(
      CryptoInventoryJson.encode({
        'header': verified.header,
        'summary': verified.summary,
      }),
    );
    final db = account.store.database;
    await _verifiedFrameSchema(db);
    Stream<Map<String, dynamic>> frames() async* {
      for (final tag in ['binding', 'file', 'proofBlob', 'section']) {
        String? after;
        while (true) {
          final rows = await db.rows(
            'SELECT sort_key,value FROM crypto_migration_verified_frames WHERE partition=? AND run_hash=? AND tag=?'
            '${after == null ? '' : ' AND sort_key>?'} ORDER BY sort_key LIMIT 20',
            [account.store.partition, run, tag, if (after != null) after],
          );
          if (rows.isEmpty) break;
          for (final row in rows) {
            after = row['sort_key'] as String;
            yield {'tag': tag, 'value': jsonDecode(row['value'] as String)};
          }
        }
      }
    }

    final actual = await CryptoMigrationBusinessParityV3.compute(
      header: verified.header,
      frames: frames(),
    );
    if (CryptoInventoryJson.canonical(actual) !=
        CryptoInventoryJson.canonical(verified.summary)) {
      throw const FormatException('crypto_business_parity_coverage');
    }
    yield* frames();
  }

  void _configure(CryptoBusinessSession runtime) {
    // This runtime exists only in withVerifiedSourceFromFile's fresh encrypted
    // database. Rows are installed solely after exact staged FILE verification
    // or the independently verified scoped descriptor capability.
    runtime.coldScopeDescriptor = (scope) async {
      await runtime.access.requireReadOnlyFrozenScope(scope);
      final rows = await runtime.db.rows(
        'SELECT descriptor FROM crypto_business_scope_descriptors WHERE partition=? AND scope_id=?',
        [runtime.partition, scope],
      );
      if (rows.length != 1) {
        throw const CryptoAuthorityPending(
          'scope_descriptor_migration_pending',
        );
      }
      return Map<String, dynamic>.from(
        jsonDecode(rows.single['descriptor'] as String),
      );
    };
    CryptoBusinessRouter.configurePayloads(runtime);
  }

  Future<void> _schema(CollaborationDatabase db) async {
    await db.execute(
      '''CREATE TABLE cold_migration_stages (
      hash TEXT PRIMARY KEY,rank INTEGER NOT NULL,authorization TEXT NOT NULL,
      verified INTEGER NOT NULL DEFAULT 0,attempted_pass INTEGER NOT NULL DEFAULT 0)''',
    );
    await db.execute('''CREATE TABLE cold_migration_frames (
      tag TEXT NOT NULL,sort_key TEXT NOT NULL,value TEXT NOT NULL,
      PRIMARY KEY(tag,sort_key))''');
    await db.execute('''CREATE TABLE cold_migration_objects (
      id TEXT PRIMARY KEY,binding_id TEXT NOT NULL,kind TEXT NOT NULL)''');
  }

  CryptoMigrationColdSource _source(
    Map<String, Object?> row,
  ) => CryptoMigrationColdSource._(
    CryptoCaptureSourceContext.fromJson(jsonDecode(row['context'] as String)),
    CryptoCaptureBinding.fromJson(jsonDecode(row['binding'] as String)),
    Map<String, dynamic>.from(jsonDecode(row['typed_row'] as String) as Map),
  );

  Future<void> _plan(
    CryptoBusinessSession runtime,
    VerifiedCryptoCaptureArchive source,
    CryptoMigrationStageVerifier verifier,
    VerifiedAccountDirectory own, {
    String? scopeOnly,
    String? domainOnly,
    bool metadataOnly = false,
  }) async {
    final domains = await runtime.db.rows(
      "SELECT DISTINCT json_extract(context,'\$.scopeId') AS scope_id,json_extract(context,'\$.domain') AS domain FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND json_extract(context,'\$.domain') IN ('content','finance') ORDER BY scope_id,domain",
      [runtime.partition, source.capture.captureId],
    );
    for (final domain in domains) {
      if (scopeOnly != null && domain['scope_id'] != scopeOnly ||
          domainOnly != null && domain['domain'] != domainOnly) {
        continue;
      }
      String? after;
      while (true) {
        final page = await runtime.account.directory
            .call('crypto2.migration.stagedRecords', {
              'migrationId': source.capture.migrationId,
              'scopeId': domain['scope_id'],
              'domain': domain['domain'],
              'limit': 20,
              if (after != null) 'afterId': after,
            });
        for (final raw in page['stages'] as List) {
          final authorization = Map<String, dynamic>.from(
            (raw as Map)['authorization'],
          );
          final command =
              CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
                  as Map;
          // Other contributors' rows need their own private source comparison.
          if (command['accountId'] != runtime.account.directory.accountId) {
            continue;
          }
          await verifier.frozenCandidate(
            authorization: authorization,
            coldArchive: source,
            contributor: own,
          );
          final proofs = command['payload']['batch']['records'] as List;
          if (metadataOnly) {
            final types = proofs
                .map(
                  (p) =>
                      (CryptoJson.decode(
                            cryptoBase64((p as Map)['commandBase64']),
                          )
                          as Map)['type'],
                )
                .toSet();
            if (!types.contains('scopeMetadata')) continue;
            if (types.length != 1) {
              throw const CryptoAuthorityPending(
                'crypto_structure_source_batch_pending',
              );
            }
          }

          var rank = 2;
          for (final proof in proofs) {
            final body =
                CryptoJson.decode(cryptoBase64((proof as Map)['commandBase64']))
                    as Map;
            if (body['type'] == 'scopeMetadata') {
              rank = 0;
            }
            if (rank > 1 &&
                const {
                  'financeAccount',
                  'personalFinanceAccount',
                }.contains(body['type'])) {
              rank = 1;
            }
          }
          await runtime.db.execute(
            'INSERT OR IGNORE INTO cold_migration_stages(hash,rank,authorization) VALUES(?,?,?)',
            [
              await runtime.codec.digest(authorization),
              rank,
              CryptoInventoryJson.canonical(authorization),
            ],
          );
        }
        if (page['hasMore'] == false) break;
        final next = page['nextAfterId'];
        if (page['hasMore'] != true ||
            next is! String ||
            after != null && next.compareTo(after) <= 0) {
          throw const FormatException('crypto_migration_stage_cursor');
        }
        after = next;
      }
    }
  }

  Future<void> _canonical(
    CryptoBusinessSession runtime,
    VerifiedCryptoCaptureArchive source,
    CryptoMigrationStageVerifier verifier,
    VerifiedAccountDirectory own,
    Uint8List file,
  ) async {
    var pass = 1, progress = 0;
    Object? lastPending;
    StackTrace? lastPendingStack;
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT * FROM cold_migration_stages WHERE verified=0 AND attempted_pass<? ORDER BY rank,hash LIMIT 1',
        [pass],
      );
      if (rows.isEmpty) {
        if ((await runtime.db.rows(
          'SELECT 1 FROM cold_migration_stages WHERE verified=0 LIMIT 1',
        )).isEmpty) {
          return;
        }
        if (progress == 0) {
          if (lastPending != null && lastPendingStack != null) {
            Error.throwWithStackTrace(lastPending, lastPendingStack);
          }
          throw lastPending ??
              const CryptoAuthorityPending(
                'crypto_migration_dependencies_pending',
              );
        }
        pass++;
        progress = 0;
        continue;
      }
      final row = rows.single;
      final authorization = Map<String, dynamic>.from(
        jsonDecode(row['authorization'] as String) as Map,
      );
      await runtime.db.execute(
        'UPDATE cold_migration_stages SET attempted_pass=? WHERE hash=?',
        [pass, row['hash']],
      );
      try {
        final candidate = await verifier.frozenCandidate(
          authorization: authorization,
          coldArchive: source,
          contributor: own,
        );
        if (candidate.domain == 'finance' &&
            (await runtime.db.rows(
              'SELECT 1 FROM crypto_business_scope_descriptors WHERE partition=? AND scope_id=?',
              [runtime.partition, candidate.scopeId],
            )).isEmpty) {
          // Only the isolated FILE reader consumes this capability. A selected
          // nonowner has no owner's private scope row in its source archive.
          final descriptor = await CryptoMigrationStructureControl(
            runtime,
            source,
            recoveryFile: file,
          ).prepareScopedDescriptor(candidate.scopeId);
          await runtime.db.execute(
            'INSERT INTO crypto_business_scope_descriptors VALUES(?,?,?,?)',
            [
              runtime.partition,
              candidate.scopeId,
              jsonEncode(descriptor.descriptor),
              descriptor.sourceProofHash,
            ],
          );
        }
        await runtime.access.withReadOnlyFrozenScope<void>(
          scopeId: candidate.scopeId,
          candidateHeadHash: candidate.headHash,
          recoveryFile: file,
          body: () async {
            await runtime.access.recoverScopeCandidateKeys(
              candidate.scopeId,
              file,
            );
            Future<Map<String, Object?>> sourceRow(Map binding) async {
              final rows = await runtime.db.rows(
                'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id=?',
                [
                  runtime.partition,
                  source.capture.captureId,
                  binding['bindingId'],
                ],
              );
              if (rows.length != 1) {
                throw const FormatException('crypto_business_parity_coverage');
              }
              return rows.single;
            }

            // Foreign owner CONTENT is a dependency of this exact own FILE
            // finance batch, never a source binding in this account's fold.
            final dependencyCommand =
                CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
                    as Map;
            for (final b
                in dependencyCommand['payload']['sourceBindings'] as List) {
              final ownSource = _source(await sourceRow(b as Map));
              if (ownSource.context.sourceTable !=
                  'familyhub_finance_records') {
                continue;
              }
              final original = await CryptoMigrationRecordSource.decode(
                table: ownSource.context.sourceTable,
                domain: ownSource.context.domain,
                row: ownSource.typedRow,
                serverId: runtime.account.directory.session.profile.serverId,
                reservedId: runtime.reservedRecordId,
              );
              final taskId = original.rawPayload?['taskId'];
              if (original.type != 'financeEntry' ||
                  original.deleted ||
                  taskId is! String) {
                continue;
              }
              final taskWire = runtime
                      .address(candidate.scopeId, 'content', 'task', taskId)
                      .wireId,
                  intentId = await runtime.reservedRecordId(
                    candidate.scopeId,
                    'taskDerivation:$taskId',
                  ),
                  intentWire = runtime
                      .address(
                        candidate.scopeId,
                        'content',
                        'taskDerivationIntent',
                        intentId,
                      )
                      .wireId,
                  hashes = <String, String>{};
              for (final proof
                  in dependencyCommand['payload']['batch']['records'] as List) {
                final body =
                    CryptoJson.decode(
                          cryptoBase64((proof as Map)['commandBase64']),
                        )
                        as Map;
                for (final ref
                    in body['metadata']['referenceVersions'] as List) {
                  if (ref['scopeId'] != candidate.scopeId ||
                      ref['domain'] != 'content' ||
                      ![taskWire, intentWire].contains(ref['id'])) {
                    continue;
                  }
                  if (ref['revision'] != 1 ||
                      hashes.containsKey(ref['id']) &&
                          hashes[ref['id']] != ref['recordProofHash']) {
                    throw const FormatException(
                      'crypto_migration_task_dependency',
                    );
                  }
                  hashes[ref['id']] = ref['recordProofHash'];
                }
              }
              if (hashes.length != 2) {
                throw const FormatException('crypto_migration_task_dependency');
              }
              await projectCapturedTaskDependency(
                context: runtime,
                migrationId: source.capture.migrationId,
                scopeId: candidate.scopeId,
                taskId: taskId,
                taskHash: hashes[taskWire]!,
                intentHash: hashes[intentWire]!,
              );
            }

            final verified = await verifier.verify(
              migrationId: source.capture.migrationId,
              authorization: authorization,
              coldArchive: source,
              frozenCandidate: candidate,
              capturedBinding: (b) async => _source(await sourceRow(b)).binding,
              source: (b) async {
                final s = _source(await sourceRow(b));
                return CryptoMigrationRecordSource.decode(
                  table: s.context.sourceTable,
                  domain: s.context.domain,
                  row: s.typedRow,
                  serverId: runtime.account.directory.session.profile.serverId,
                  reservedId: runtime.reservedRecordId,
                );
              },
              openWitness: (b) async {
                final descriptor = Map<String, dynamic>.from(
                  b['witness'] as Map,
                );
                final c = CryptoMigrationWitnessContext(
                  Map<String, dynamic>.from(descriptor['context'] as Map),
                );
                final consumer = CryptoMigrationWitness(
                  database: runtime.db,
                  partition: runtime.partition,
                  crypto: runtime.codec.crypto,
                );
                await CryptoMigrationWitnessTransport(
                  queue: runtime.queue,
                  read: runtime.account.directory.call,
                ).download(
                  consumer: consumer,
                  context: c,
                  descriptor: descriptor,
                );
                final key = await runtime.access.getScopeKey(
                  c.value['scopeId'],
                  c.value['domain'],
                  c.value['epoch'],
                );
                try {
                  return await consumer.open(
                    context: c,
                    descriptor: descriptor,
                    domainKey: key.key,
                  );
                } finally {
                  key.release();
                }
              },
            );
            try {
              final head = await runtime.access.currentHead(candidate.scopeId);
              runtime.financeAuthorityMembers[head.headHash] = {
                for (final m in head.members) m['accountId'] as String,
              };
              await runtime.prepareRecords?.call(verified);
              await runtime.db.transaction(() async {
                await runtime.project(verified);
                final command =
                    CryptoJson.decode(
                          cryptoBase64(authorization['commandBase64']),
                        )
                        as Map;
                for (final raw
                    in command['payload']['sourceBindings'] as List) {
                  final binding = Map<String, dynamic>.from(raw as Map);
                  final original = _source(await sourceRow(binding));
                  if (CryptoMigrationBusinessParityV3.sourceAdapter(
                        original.context.sourceTable,
                      ) !=
                      'canonical') {
                    throw const FormatException(
                      'crypto_business_parity_adapter_pending',
                    );
                  }
                  await _frame(
                    runtime.db,
                    'binding',
                    original.binding.bindingId,
                    {
                      'binding': original.binding.toJson(),
                      'adapter': 'canonical',
                      'primaryRecordProofHash': binding['recordProofHash'],
                      'companionProofHashes': binding['companionProofHashes'],
                      'artifactHash':
                          await CryptoMigrationBusinessParityV3.canonicalArtifact(
                            binding,
                          ),
                    },
                  );
                  for (final object in binding['objects'] as List) {
                    if (object['kind'] == 'ideaAsset') continue;
                    final d = object['blob'] as Map;
                    await _object(
                      runtime.db,
                      original.binding.bindingId,
                      'file',
                      object['kind'],
                      d,
                      object['plainSize'],
                    );
                  }
                  final witness = binding['witness'];
                  if (witness != null) {
                    final manifestHash = await cryptoSha256(
                      cryptoBase64(witness['manifestBase64']),
                    );
                    for (final segment in witness['segments'] as List) {
                      await _object(
                        runtime.db,
                        original.binding.bindingId,
                        'proofBlob',
                        'typedWitness',
                        {
                          'id': segment['id'],
                          'cipherSize': segment['size'],
                          'cipherSha256': segment['sha256'],
                          'manifestHash': manifestHash,
                        },
                        null,
                      );
                    }
                  }
                }
                await runtime.db.execute(
                  'UPDATE cold_migration_stages SET verified=1 WHERE hash=?',
                  [row['hash']],
                );
                progress++;
              });
            } finally {
              for (final value in verified) {
                value.plaintext?.fillRange(0, value.plaintext!.length, 0);
              }
            }
          },
        );
      } on CryptoProjectionPending catch (error, stack) {
        lastPending = error;
        lastPendingStack = stack;
      } on CryptoAuthorityPending catch (error, stack) {
        lastPending = error;
        lastPendingStack = stack;
      }
    }
  }

  Future<void> _ideaFiles(
    CryptoBusinessSession runtime,
    VerifiedCryptoCaptureArchive source,
    Uint8List recoveryFile,
  ) async {
    var after = '';
    final files = CryptoMigrationIdeaFiles(runtime);
    while (true) {
      final rows = await runtime.db.rows(
        "SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? AND json_extract(context,'\$.sourceTable')='familyhub_idea_assets' ORDER BY binding_id LIMIT 1",
        [runtime.partition, source.capture.captureId, after],
      );
      if (rows.isEmpty) return;
      final item = _source(rows.single);
      after = item.binding.bindingId;
      final result = await files.verifyCold(
        archive: source,
        source: item,
        recoveryFile: recoveryFile,
      );
      final object = result['object'] as Map;
      await _frame(runtime.db, 'binding', after, {
        'binding': item.binding.toJson(),
        'adapter': 'canonicalFile',
        'primaryRecordProofHash': null,
        'companionProofHashes': <String>[],
        'artifactHash': result['artifactHash'],
      });
      await _object(
        runtime.db,
        after,
        'file',
        object['kind'],
        object['blob'],
        object['plainSize'],
      );
    }
  }

  Future<void> _object(
    CollaborationDatabase db,
    String binding,
    String tag,
    String kind,
    Map descriptor,
    int? plainSize,
  ) async {
    // A cipher object cannot be counted again under a fabricated second source.
    await db.execute(
      'INSERT INTO cold_migration_objects(id,binding_id,kind) VALUES(?,?,?)',
      [descriptor['id'], binding, kind],
    );
    await _frame(db, tag, '$binding/$kind/${descriptor['id']}', {
      'bindingId': binding,
      'id': descriptor['id'],
      'kind': kind,
      'plainSize': plainSize,
      'cipherSize': descriptor['cipherSize'],
      'cipherSha256': descriptor['cipherSha256'],
      'manifestHash':
          descriptor['manifestHash'] ??
          await cryptoSha256(cryptoBase64(descriptor['manifestBase64'])),
    });
  }

  Future<void> _frame(
    CollaborationDatabase db,
    String tag,
    String key,
    Map<String, dynamic> value,
  ) => db.execute(
    'INSERT INTO cold_migration_frames(tag,sort_key,value) VALUES(?,?,?)',
    [tag, key, CryptoInventoryJson.canonical(value)],
  );

  Stream<Map<String, dynamic>> _frames(CollaborationDatabase db) async* {
    for (final tag in ['binding', 'file', 'proofBlob', 'section']) {
      String? after;
      while (true) {
        final rows = await db.rows(
          'SELECT sort_key,value FROM cold_migration_frames WHERE tag=?'
          '${after == null ? '' : ' AND sort_key>?'} ORDER BY sort_key LIMIT 20',
          [tag, if (after != null) after],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          after = row['sort_key'] as String;
          yield {'tag': tag, 'value': jsonDecode(row['value'] as String)};
        }
      }
    }
  }
}
