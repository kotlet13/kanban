import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

import '../collaboration_repository_test.dart' show MemorySessionStore;

class _Secure implements AccountCryptoStore {
  final rows = <String, String>{};
  @override
  Future<String?> read(String key) async => rows[key];
  @override
  Future<void> write(String key, String value) async {
    rows[key] = value;
  }
}

class _Transport implements CollaborationTransport {
  final http = HttpCollaborationTransport();
  final operations = <String>[];
  final failures = <String>[];
  bool withhold = false;
  bool loseReportAck = false, forbidEvidenceReads = false;
  int rateRetries = 0;
  Future<void> Function()? afterCheckpoint;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    if (forbidEvidenceReads &&
        const {
          'crypto2.records.pull',
          'crypto2.blob.get',
        }.contains(operation)) {
      throw const CollaborationException('permission_revoked');
    }
    late Map<String, dynamic> reply;
    try {
      reply = await http.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
    } on CollaborationException catch (error) {
      failures.add('$operation:${error.code}');
      if (error.code == 'rate_limited') {
        final retry = error is CollaborationApiException
            ? error.details['retryAfter']
            : null;
        if (Platform.environment['JIVIE_TEST_RETRY_RATE_LIMITS'] == '1' &&
            retry is int &&
            retry > 0 &&
            retry <= 60 &&
            rateRetries++ < 3) {
          // Synthetic opt-in only: retry identical parameters after the server's
          // bounded delay. Production policies and server counters stay intact.
          await Future<void>.delayed(Duration(seconds: retry));
          return call(
            serverUrl: serverUrl,
            operation: operation,
            params: params,
            token: token,
            allowLocalHttp: allowLocalHttp,
          );
        }
        final counts = <String, int>{};
        for (final op in operations) {
          counts[op] = (counts[op] ?? 0) + 1;
        }
        fail(
          'Synthetic HTTP rate limit after ${operations.length} requests: $counts',
        );
      }
      rethrow;
    }
    if (operation == 'crypto2.moderation.report' && loseReportAck) {
      loseReportAck = false;
      throw const CollaborationException('synthetic_lost_ack');
    }
    if (operation == 'crypto2.domain.checkpoint') {
      await afterCheckpoint?.call();
    }
    if (withhold && operation == 'crypto2.records.pull') {
      return {
        ...reply,
        'records': <Object>[],
        'cursor': params['cursor'],
        'hasMore': false,
      };
    }
    return reply;
  }

  @override
  void close() => http.close();
}

void main() {
  final path = Platform.environment['JIVIE_CRYPTO_MODERATION_HTTP_FIXTURE'];
  test(
    'actual reviewed moderation repository route survives accepted lost ACK without duplicate disclosure',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback required');
      }
      final w =
              (fixture['session'] ?? fixture['accounts']['owner']['session'])
                  as Map,
          u = w['user'] as Map,
          d = w['device'] as Map;
      final session = DeviceSession(
        AccountSession(
          serverUrl: url,
          serverId: w['serverId'],
          accountId: u['accountId'],
          userId: u['id'],
          username: u['username'],
          displayName: u['displayName'],
          deviceId: d['id'],
          expiresAt: DateTime.fromMillisecondsSinceEpoch(d['expiresAt'] * 1000),
          allowLocalHttp: true,
        ),
        w['token'],
      );
      final db = CollaborationDatabase(NativeDatabase.memory()),
          transport = _Transport();
      final crypto = CryptoCodec(await SodiumInit.init());
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: transport,
          store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
          isCurrent: () => true,
        ),
      );
      final file = await account.prepareRecoveryFile();
      try {
        await account.verifyAndInitialize(file);
      } finally {
        file.fillRange(0, file.length, 0);
      }
      final sessions = MemorySessionStore()..value = session;
      final repository = CollaborationRepository(
        db,
        transport,
        sessions,
        cryptoRouter: CryptoBusinessRouter(
          database: db,
          accountFor: (_) async => account,
        ),
      );
      addTearDown(repository.close);
      await repository.initialize();
      late final String scope;
      try {
        scope = await repository.createScope('PRIVATE_BUSINESS_SENTINEL');
      } catch (error) {
        fail('Synthetic scope creation failed: $error; ${transport.failures}');
      }
      final task = await repository.createTask(
        scopeId: scope,
        title: 'EXPLICITLY_REVIEWED_REPORT_TITLE',
        notes: 'EXPLICITLY_REVIEWED_REPORT_NOTES',
      );
      await repository.syncNow();
      final preview = await repository.previewContentReport(
        scopeId: scope,
        targetType: 'record',
        targetId: task,
      );
      expect(preview.targetId, task);
      expect(preview.title, 'EXPLICITLY_REVIEWED_REPORT_TITLE');
      expect(preview.evidence['notes'], 'EXPLICITLY_REVIEWED_REPORT_NOTES');
      expect(
        jsonEncode(preview.evidence),
        isNot(contains('cryptoPayloadBlob')),
      );
      transport.loseReportAck = true;
      Object? failure;
      try {
        await repository.submitContentReport(
          preview: preview,
          reason: 'privacy',
          details: 'SYNTHETIC_SELECTED_DISCLOSURE',
        );
      } catch (error) {
        failure = error;
      }
      expect(
        failure,
        isNotNull,
        reason: 'Lost accepted response must remain unresolved',
      );
      final before = await db.rows(
        "SELECT request_id,request_hash,signed_body FROM crypto_outbox WHERE operation='crypto2.moderation.report'",
      );
      expect(before, hasLength(1));
      final receipt = await repository.submitContentReport(
        preview: preview,
        reason: 'privacy',
        details: 'SYNTHETIC_SELECTED_DISCLOSURE',
      );
      expect(receipt.status, 'submitted');
      expect(receipt.reportId, preview.requestId);
      final after = await db.rows(
        "SELECT request_id,request_hash,signed_body FROM crypto_outbox WHERE operation='crypto2.moderation.report'",
      );
      expect(
        after,
        before,
        reason: 'Retry retains exact signed original request',
      );
      final again = await repository.submitContentReport(
        preview: preview,
        reason: 'privacy',
        details: 'SYNTHETIC_SELECTED_DISCLOSURE',
      );
      expect(again.reportId, receipt.reportId);
      expect(again.createdAt, receipt.createdAt);
      expect(
        transport.operations.where((op) => op == 'moderation.report'),
        isEmpty,
      );
      expect(
        await db.rows(
          "SELECT * FROM crypto_outbox WHERE operation='crypto2.moderation.report' AND state='applied'",
        ),
        hasLength(1),
      );
      // A board may use one image in several elements; the explicit report
      // must retain a single exact selected asset and settle before reopening it.
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 1, height: 1)),
      );
      final hash = await cryptoSha256(png);
      final asset = IdeaAsset(
        sha256: hash,
        mime: 'image/png',
        size: png.length,
        width: 1,
        height: 1,
      );
      final now = DateTime.now().toUtc();
      final board = IdeaBoard(
        id: crypto.randomId(),
        title: 'EXPLICIT_IMAGE_REVIEW',
        createdAt: now,
        updatedAt: now,
        elements: [
          for (var i = 0; i < 2; i++)
            IdeaElement(
              id: crypto.randomId(),
              kind: IdeaElementKind.image,
              x: i * 10.0,
              y: 0,
              width: 100,
              height: 100,
              asset: asset,
            ),
        ],
      );
      await db.execute(
        'INSERT INTO idea_assets(workspace,sha256,metadata,bytes) VALUES(?,?,?,?)',
        [
          'shared:${session.profile.partition}:$scope',
          hash,
          jsonEncode(asset.toJson()),
          png,
        ],
      );
      await repository.saveIdea(scope, board, isNew: true);
      await repository.syncNow();
      expect(
        await db.rows(
          "SELECT * FROM crypto_business_records WHERE json_extract(projection,'\$.id')=?",
          [board.id],
        ),
        isNotEmpty,
        reason:
            '${repository.state.lastError}; ${transport.failures}; ${transport.operations}; ${await db.rows("SELECT record_id,verdict,error FROM crypto_received")}',
      );
      final imagePreview = await repository.previewContentReport(
        scopeId: scope,
        targetType: 'record',
        targetId: board.id,
      );
      expect(imagePreview.evidence['assets'], hasLength(1));
      expect((imagePreview.evidence['board'] as Map)['elements'], hasLength(2));
      transport.loseReportAck = true;
      Object? imageFailure;
      try {
        await repository.submitContentReport(
          preview: imagePreview,
          reason: 'privacy',
        );
      } catch (error) {
        imageFailure = error;
      }
      expect(
        transport.loseReportAck,
        isFalse,
        reason:
            'Only accepted lost ACK is the retry fixture: $imageFailure; ${await db.rows("SELECT operation,state,json_extract(response,'\$.reason') AS reason,json_extract(response,'\$.response.errorCode') AS error FROM crypto_outbox WHERE state<>\'applied\'")}',
      );
      expect(imageFailure, isNotNull);
      final uploadCount = transport.operations
          .where((op) => op.startsWith('crypto2.moderation.disclosure.'))
          .length;
      final readCount = transport.operations
          .where(
            (op) =>
                const {'crypto2.records.pull', 'crypto2.blob.get'}.contains(op),
          )
          .length;
      await db.execute('DELETE FROM crypto_document_cache WHERE partition=?', [
        session.profile.partition,
      ]);
      transport.forbidEvidenceReads = true;
      final imageReceipt = await repository.submitContentReport(
        preview: imagePreview,
        reason: 'privacy',
      );
      expect(imageReceipt.reportId, imagePreview.requestId);
      expect(
        transport.operations
            .where((op) => op.startsWith('crypto2.moderation.disclosure.'))
            .length,
        uploadCount,
        reason: 'Accepted report retry never uploads another copy',
      );
      expect(
        transport.operations
            .where(
              (op) => const {
                'crypto2.records.pull',
                'crypto2.blob.get',
              }.contains(op),
            )
            .length,
        readCount,
        reason:
            'Own accepted report outcome does not reopen inaccessible board or image',
      );
    },
    skip: path == null ? 'Synthetic loopback fixture not requested' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
