import 'dart:async';
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

class _MemorySecure implements AccountCryptoStore {
  final rows = <String, String>{};
  @override
  Future<String?> read(String partition) async => rows[partition];
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
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
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
  final path = Platform.environment['JIVIE_CRYPTO2_DOCUMENT_HTTP_FIXTURE'];
  test(
    'real encrypted table, lease and attachment ciphertext restore preserve private payloads',
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
      try {
        final file = await account.prepareRecoveryFile();
        try {
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
        var runtime = CryptoBusinessSession(account, access, db),
            docs = CryptoBusinessDocuments(runtime);
        runtime.prepareRecords = docs.prepareRecords;
        runtime.expandPayload = docs.expandPayload;
        runtime.validateRaw = docs.validateRaw;
        runtime.projectExtension = docs.projectRecord;
        runtime.blobIds = docs.blobIds;
        runtime.references = docs.references;
        runtime.prepareOutgoing = docs.prepareOutgoing;
        runtime.encodePayload = docs.encodePayload;
        final projectId = crypto.randomId();
        final timestamp = DateTime.utc(2026, 10, 17);
        final largeProject =
            Map<String, dynamic>.from(
                LocalProject(
                  id: projectId,
                  title: 'Large private extension',
                  description: '',
                  createdAt: timestamp,
                  updatedAt: timestamp,
                  area: ProjectArea.home,
                ).toJson(),
              )
              ..remove('id')
              ..remove('revision')
              ..remove('createdByAccountId')
              ..remove('updatedByAccountId');
        largeProject['futureOpaque'] = {
          'unicode': 'Čebela 😀',
          'body': 'Z' * 400000,
        };
        await runtime.publishRaw(
          scopeId: scope,
          id: projectId,
          type: 'project',
          operationId: crypto.randomId(),
          expectedRevision: 0,
          rawPayload: largeProject,
          localHash: await CryptoInventoryJson.hash(largeProject),
        );
        await db.execute(
          'DELETE FROM crypto_document_cache WHERE partition=?',
          [session.profile.partition],
        );
        final genericRows = await db.rows(
          'SELECT descriptor FROM crypto_document_jobs WHERE partition=? AND record_id=?',
          [session.profile.partition, projectId],
        );
        expect(genericRows.length, 1);
        final genericBytes = await docs.blobs.open(
          Map<String, dynamic>.from(
            jsonDecode(genericRows.single['descriptor'] as String) as Map,
          ),
        );
        try {
          expect(jsonDecode(utf8.decode(genericBytes)), largeProject);
        } finally {
          genericBytes.fillRange(0, genericBytes.length, 0);
        }
        final table = crypto.randomId();
        final created = await docs.dispatch('tables.create', {
          'scopeId': scope,
          'id': table,
          'requestId': crypto.randomId(),
          'title': 'Private source table',
        });
        expect(created['sheet']['title'], 'Private source table');
        final lease = await docs.dispatch('tables.acquire', {
          'scopeId': scope,
          'id': table,
          'requestId': crypto.randomId(),
        });
        final token = lease['lease']['token'] as String;
        final cells = {for (var i = 1; i <= 120; i++) 'A$i': 'x' * 4096};
        final saveParams = <String, Object?>{
          'scopeId': scope,
          'id': table,
          'requestId': crypto.randomId(),
          'token': token,
          'expectedRevision': 1,
          'title': 'Private large table',
          'cells': cells,
        };
        http.loseBatch = true;
        await expectLater(
          docs.dispatch('tables.save', saveParams),
          throwsA(isA<CollaborationException>()),
        );
        final beforeRetry = (await db.rows(
          'SELECT id FROM crypto_document_jobs WHERE partition=?',
          [session.profile.partition],
        )).length;
        http.blockReceipts = false;
        await Future<void>.delayed(const Duration(seconds: 2));
        final reopened = AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(crypto),
            session: session,
            transport: http,
            store: account.store,
            isCurrent: () => true,
          ),
        );
        runtime = CryptoBusinessSession(
          reopened,
          SessionCryptoAccess(account: reopened),
          db,
        );
        docs = CryptoBusinessDocuments(runtime);
        runtime.prepareRecords = docs.prepareRecords;
        runtime.expandPayload = docs.expandPayload;
        runtime.validateRaw = docs.validateRaw;
        runtime.projectExtension = docs.projectRecord;
        runtime.blobIds = docs.blobIds;
        runtime.references = docs.references;
        runtime.prepareOutgoing = docs.prepareOutgoing;
        runtime.encodePayload = docs.encodePayload;
        final saved = await docs.dispatch('tables.save', saveParams);
        expect(
          (await db.rows(
            'SELECT id FROM crypto_document_jobs WHERE partition=?',
            [session.profile.partition],
          )).length,
          beforeRetry,
        );
        expect(http.batches, 3);
        expect(saved['sheet']['cells'], cells);
        final rows = await db.rows(
          'SELECT descriptor FROM crypto_document_jobs WHERE partition=? AND record_id=? ORDER BY rowid DESC',
          [session.profile.partition, table],
        );
        final descriptor = Map<String, dynamic>.from(
          jsonDecode(rows.first['descriptor'] as String) as Map,
        );
        await expectLater(
          docs.blobs.stage(
            scopeId: scope,
            recordId: table,
            operationId:
                (await db.rows(
                      'SELECT operation_id FROM crypto_document_jobs WHERE partition=? AND id=?',
                      [session.profile.partition, descriptor['id']],
                    )).single['operation_id']
                    as String,
            kind: 'table',
            plaintext: Uint8List.fromList([1, 2, 3]),
          ),
          throwsFormatException,
        );
        await db.execute(
          'DELETE FROM crypto_document_cache WHERE partition=?',
          [session.profile.partition],
        );
        final restored = await docs.blobs.open(descriptor);
        try {
          expect((jsonDecode(utf8.decode(restored)) as Map)['cells'], cells);
        } finally {
          restored.fillRange(0, restored.length, 0);
        }
        await docs.dispatch('tables.release', {
          'scopeId': scope,
          'id': table,
          'token': token,
        });
        final size =
            Platform.environment['JIVIE_CRYPTO_DOCUMENT_FULL_SIZE'] == '1'
            ? 20 * 1024 * 1024
            : 512 * 1024;
        final bytes = Uint8List.fromList(
              List.generate(size, (i) => (i * 31 + 7) & 255),
            ),
            id = crypto.randomId(),
            target = {
              'scopeId': scope,
              'targetType': 'scope',
              'targetId': scope,
            };
        final hash = await cryptoSha256(bytes);
        await docs.dispatch('attachments.begin', {
          ...target,
          'id': id,
          'requestId': id,
          'name': 'private-file.txt',
          'mime': 'text/plain',
          'size': bytes.length,
          'sha256': hash,
        });
        for (var offset = 0; offset < bytes.length; offset += 262144)
          await docs.dispatch('attachments.chunk', {
            ...target,
            'id': id,
            'offset': offset,
            'dataBase64': base64Encode(
              Uint8List.sublistView(
                bytes,
                offset,
                (offset + 262144).clamp(0, bytes.length),
              ),
            ),
          });
        final complete = crypto.randomId();
        final attachment = await docs.dispatch('attachments.complete', {
          ...target,
          'id': id,
          'requestId': complete,
        });
        expect(attachment['attachment']['size'], size);
        expect(attachment['attachment']['sha256'], hash);
        await docs.dispatch('attachments.complete', {
          ...target,
          'id': id,
          'requestId': complete,
        });
        await db.execute(
          'DELETE FROM crypto_document_cache WHERE partition=?',
          [session.profile.partition],
        );
        final builder = BytesBuilder(copy: false);
        while (builder.length < size) {
          final page = await docs.dispatch('attachments.get', {
            ...target,
            'id': id,
            'offset': builder.length,
            'limit': 262144,
          });
          builder.add(base64Decode(page['dataBase64'] as String));
        }
        expect(await cryptoSha256(builder.takeBytes()), hash);
        bytes.fillRange(0, bytes.length, 0);
      } catch (_) {
        // Synthetic verdict codes only; no plaintext, keys or signed commands.
        print(await db.rows('SELECT verdict,error FROM crypto_received'));
        rethrow;
      } finally {
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
