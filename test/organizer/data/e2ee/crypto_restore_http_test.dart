import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_documents.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inventory_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_backup_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_document_backup_drafts.dart';
import 'package:kanban/organizer/data/e2ee/crypto_restore_reconciler.dart';

class _MemorySecure implements AccountCryptoStore {
  final rows = <String, String>{};
  Future<void> Function(String)? onRead;
  @override
  Future<String?> read(String partition) async {
    final callback = onRead;
    onRead = null;
    await callback?.call(partition);
    return rows[partition];
  }

  @override
  Future<void> write(String partition, String value) async {
    rows[partition] = value;
  }
}

DeviceSession _session(String url, Map<String, dynamic> wire) {
  final user = wire['user'] as Map, device = wire['device'] as Map;
  return DeviceSession(
    AccountSession(
      serverUrl: url,
      serverId: wire['serverId'],
      accountId: user['accountId'],
      userId: user['id'],
      username: user['username'],
      displayName: user['displayName'],
      deviceId: device['id'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        device['expiresAt'] * 1000,
      ),
      allowLocalHttp: true,
    ),
    wire['token'],
  );
}

class _DocumentHttp extends HttpCollaborationTransport {
  bool loseBatch = false, blockReceipts = false;
  int batches = 0;
  final counts = <String, int>{};
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    counts.update(operation, (v) => v + 1, ifAbsent: () => 1);
    if (blockReceipts && operation == 'crypto2.receipt.get')
      throw const CollaborationException('network');
    late Map<String, dynamic> result;
    for (var attempt = 0; ; attempt++) {
      try {
        result = await super.call(
          serverUrl: serverUrl,
          operation: operation,
          params: params,
          token: token,
          allowLocalHttp: allowLocalHttp,
        );
        break;
      } on CollaborationApiException catch (error) {
        if (error.code != 'rate_limited' || attempt >= 4) rethrow;
        final retry = error.details['retryAfter'];
        await Future<void>.delayed(
          Duration(seconds: retry is int ? retry.clamp(1, 60) : 15),
        );
      }
    }

    if (operation == 'crypto2.records.batch') {
      batches++;
      if (loseBatch) {
        loseBatch = false;
        blockReceipts = true;
        throw const CollaborationException('network');
      }
    }
    return result;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  // This opt-in synthetic loopback integration uses real HTTP, not widget mocks.
  HttpOverrides.global = null;
  final path = Platform.environment['JIVIE_CRYPTO2_RESTORE_HTTP_FIXTURE'];
  test(
    'blank SQL restore verifies all evidence and file-only draft decryption without activating imported commands',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map,
          url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback only');
      final crypto = CryptoCodec(await SodiumInit.init()),
          http = _DocumentHttp(),
          db = CollaborationDatabase(NativeDatabase.memory());
      final session = _session(url, fixture['accounts']['owner']['session']);
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: http,
          store: CryptoIdentityStore(
            db,
            _MemorySecure(),
            session.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      late Uint8List externalFile;
      try {
        final file = await account.prepareRecoveryFile();
        try {
          externalFile = Uint8List.fromList(file);
          await account.verifyAndInitialize(file);
        } finally {
          file.fillRange(0, file.length, 0);
        }
        final access = SessionCryptoAccess(account: account),
            scope = crypto.randomId(),
            manager = ScopeCryptoManager(access);
        await manager.createScope(id: scope, kind: 'organization');
        final catalog = await account.directory.call('crypto2.scopes.catalog'),
            metadata =
                (catalog['scopes'] as List).singleWhere((r) => r['id'] == scope)
                    as Map;
        await manager.initializeEmptyScope(
          scopeId: scope,
          accessRevision: metadata['accessRevision'],
          members: (metadata['members'] as List).cast<Map<String, dynamic>>(),
        );
        final countBefore = http.counts['crypto2.scope.headGet'] ?? 0;
        await access.withVerifiedOperation(() async {
          for (var i = 0; i < 100; i++) {
            await access.currentHead(scope, online: true);
          }
          expect((http.counts['crypto2.scope.headGet'] ?? 0) - countBefore, 1);
          final key =
                  'directory2:${session.profile.partition}:${session.profile.accountId}',
              old = await account.store.secure.read(
                'directory2:${session.profile.partition}:${session.profile.accountId}',
              );
          final changed = Map<String, dynamic>.from(
            CryptoJson.decode(Uint8List.fromList(utf8.encode(old!))) as Map,
          )..['cacheProbe'] = 1;
          try {
            await account.store.secure.write(
              key,
              utf8.decode(CryptoJson.encode(changed)),
            );
            await access.currentHead(scope, online: true);
            expect(
              (http.counts['crypto2.scope.headGet'] ?? 0) - countBefore,
              2,
            );
          } finally {
            await account.store.secure.write(key, old);
          }
          await access.currentHead(scope, online: true);
          expect((http.counts['crypto2.scope.headGet'] ?? 0) - countBefore, 3);
        });
        await access.withVerifiedOperation(() async {
          await access.currentHead(scope, online: true);
          final before = http.counts['crypto2.scope.headGet'] ?? 0;
          (account.store.secure as _MemorySecure).onRead = (_) async {
            await Future<void>.value();
            binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
            binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          };
          await access.currentHead(scope, online: true);
          expect((http.counts['crypto2.scope.headGet'] ?? 0) - before, 1);
        });
        final runtime = CryptoBusinessSession(account, access, db),
            docs = CryptoBusinessDocuments(
              CryptoBusinessSession(account, access, db),
            );
        runtime.prepareRecords = docs.prepareRecords;
        runtime.expandPayload = docs.expandPayload;
        runtime.validateRaw = docs.validateRaw;
        runtime.projectExtension = docs.projectRecord;
        runtime.blobIds = docs.blobIds;
        runtime.references = docs.references;
        runtime.prepareOutgoing = docs.prepareOutgoing;
        runtime.encodePayload = docs.encodePayload;
        final id = crypto.randomId(), now = DateTime.utc(2026, 10, 17);
        final raw =
            Map<String, dynamic>.from(
                LocalProject(
                  id: id,
                  title: 'Recovered encrypted draft',
                  description: '',
                  createdAt: now,
                  updatedAt: now,
                  area: ProjectArea.home,
                ).toJson(),
              )
              ..remove('id')
              ..remove('revision')
              ..remove('createdByAccountId')
              ..remove('updatedByAccountId');
        raw['futureOpaque'] = {'body': 'R' * 400000};
        await runtime.publishRaw(
          scopeId: scope,
          id: id,
          type: 'project',
          operationId: crypto.randomId(),
          expectedRevision: 0,
          rawPayload: raw,
          localHash: await CryptoInventoryJson.hash(raw),
        );
        final evidence = await exportCryptoEvidence(
              db,
              session.profile.partition,
            ),
            private = await exportCryptoDocumentDrafts(
              db,
              session.profile.partition,
            );
        final blank = CollaborationDatabase(NativeDatabase.memory()),
            secure = _MemorySecure();
        try {
          final cold = AccountCryptoV2Workflow(
            AccountDirectoryRepository(
              reducer: AccountDirectoryV2(crypto),
              session: session,
              transport: http,
              store: CryptoIdentityStore(
                blank,
                secure,
                session.profile.partition,
              ),
              isCurrent: () => true,
            ),
          );
          final info = cold.files.inspect(
            externalFile,
            serverId: session.profile.serverId,
            accountId: session.profile.accountId,
          );
          final current = await account.directory.requireFresh();
          // The file pins identity; this explicit approved-device comparison
          // establishes the exact prefix independently of the backup contents.
          await cold.directory.refresh(
            externalFingerprint: info['fingerprint'],
          );
          await cold.directory.compareTrustedPeer(
            fingerprint: info['fingerprint'],
            generation: current.generation,
            headHash: current.headHash,
          );
          expect(
            await blank.rows('SELECT * FROM crypto_identity_secrets'),
            isEmpty,
          );
          expect(await blank.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
          final backupId = crypto.randomId();
          await blank.execute('INSERT INTO restored_backups VALUES(?,?,?,?)', [
            backupId,
            now.toIso8601String(),
            session.profile.partition,
            jsonEncode({'cryptoPrivateDrafts': private}),
          ]);
          await fenceRestoredCryptoEvidence(
            blank,
            evidence,
            session.profile.partition,
            backupId,
          );
          final service = CryptoRestoreReconciler(cold),
              report = await CryptoRestoreReconciler(cold).inspect();
          expect(report.recordCount, greaterThan(0));
          expect(report.canReconcile, true);
          await service.reconcile();
          expect(await blank.rows('SELECT * FROM crypto_outbox'), isEmpty);
          expect(await blank.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
          final recovered = await service.recoverDocumentDrafts(externalFile);
          try {
            expect(recovered, hasLength(1));
            expect(jsonDecode(utf8.decode(recovered.single.bytes)), raw);
          } finally {
            for (final value in recovered) {
              value.dispose();
            }
          }
          expect(await blank.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
          final changed =
              jsonDecode(jsonEncode(evidence)) as Map<String, dynamic>;
          (changed['tables']['crypto_received'] as List).first['record_id'] =
              crypto.randomId();
          await fenceRestoredCryptoEvidence(
            blank,
            changed,
            session.profile.partition,
            crypto.randomId(),
          );
          await expectLater(
            CryptoRestoreReconciler(cold).reconcile(),
            throwsFormatException,
          );
          expect(
            (await blank.rows(
              'SELECT state FROM crypto_restore_fences',
            )).single['state'],
            isNot('verified'),
          );
        } finally {
          await blank.close();
        }
      } catch (_) {
        // Synthetic verdict codes only; no plaintext, keys or signed commands.
        print(await db.rows('SELECT verdict,error FROM crypto_received'));
        rethrow;
      } finally {
        externalFile.fillRange(0, externalFile.length, 0);
        await db.close();
        http.close();
      }
    },
    skip: path == null
        ? 'Synthetic HTTP documents fixture not supplied'
        : false,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
