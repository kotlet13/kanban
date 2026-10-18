import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_documents.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_payload.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String partition) async => values[partition];
  @override
  Future<void> write(String partition, String value) async {
    values[partition] = value;
  }
}

class _Http extends HttpCollaborationTransport {
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await super.call(
          serverUrl: serverUrl,
          operation: operation,
          params: params,
          token: token,
          allowLocalHttp: allowLocalHttp,
        );
      } on CollaborationApiException catch (error) {
        if (error.code != 'rate_limited' || attempt >= 4) rethrow;
        final retry = error.details['retryAfter'];
        await Future<void>.delayed(
          Duration(seconds: retry is int ? retry.clamp(1, 60) : 15),
        );
      }
    }
  }
}

void _documents(CryptoBusinessSession runtime) {
  final documents = CryptoBusinessDocuments(runtime);
  runtime.prepareRecords = documents.prepareRecords;
  runtime.prepareHistoricalPayload = documents.prepareRecords;
  runtime.expandPayload = documents.expandPayload;
  runtime.validateRaw = documents.validateRaw;
  runtime.blobIds = documents.blobIds;
  runtime.prepareOutgoing = documents.prepareOutgoing;
  runtime.encodePayload = documents.encodePayload;
}

void main() {
  final path = Platform.environment['JIVIE_PAYLOAD_ARRAY_HTTP_FIXTURE'];
  test(
    'large Idea future point fields survive ordinary title edit and cold pull',
    () async {
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic only');
      final wire = fixture['accounts']['owner']['session'] as Map;
      final user = wire['user'] as Map, device = wire['device'] as Map;
      final session = DeviceSession(
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
      final db = CollaborationDatabase(NativeDatabase.memory());
      final cold = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(cold.close);
      final crypto = CryptoCodec(await SodiumInit.init());
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: _Http(),
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
      final access = SessionCryptoAccess(account: account),
          manager = ScopeCryptoManager(SessionCryptoAccess(account: account));
      final scope = crypto.randomId();
      final created = await manager.createScope(id: scope, kind: 'household');
      final descriptor = created['scope'] as Map;
      await manager.initializeEmptyScope(
        scopeId: scope,
        accessRevision: descriptor['accessRevision'],
        members: (descriptor['members'] as List).cast<Map<String, dynamic>>(),
      );
      final runtime = CryptoBusinessSession(account, access, db);
      _documents(runtime);
      final id = crypto.randomId(), now = DateTime.utc(2026, 10, 17);
      final raw = Map<String, dynamic>.from(
        IdeaBoard(
          id: id,
          title: 'Before',
          createdAt: now,
          updatedAt: now,
          elements: [
            IdeaElement(
              id: crypto.randomId(),
              kind: IdeaElementKind.stroke,
              x: 1.25,
              y: 2.75,
              width: 40.5,
              height: 70.5,
              points: const [IdeaPoint(0.25, 1.5), IdeaPoint(2.5, 3.75)],
            ),
          ],
        ).toJson(),
      );
      final point = ((raw['elements'] as List).single as Map)['points'] as List;
      (point.first as Map)['futurePoint'] = {
        'pressure': 0.625,
        'opaqueFuture': 'Z' * 112640,
      };
      raw['futureTop'] = {'fraction': 0.125};
      await runtime.publishRaw(
        scopeId: scope,
        id: id,
        type: 'idea',
        operationId: crypto.randomId(),
        expectedRevision: 0,
        rawPayload: raw,
        localHash: await CryptoBusinessJson.hash(raw),
      );
      final known = CryptoBusinessPayload.projection('content', 'idea', raw)
        ..['title'] = 'After';
      final router = CryptoBusinessRouter(
        database: db,
        accountFor: (_) async => account,
      );
      await router.dispatch(
        session: session,
        operation: 'sync6.push',
        params: {
          'scopeId': scope,
          'operation': {
            'recordId': id,
            'type': 'idea',
            'opId': crypto.randomId(),
            'expectedRevision': 1,
            'deleted': false,
            'payload': known,
          },
        },
        protectedScopeIds: {scope},
      );
      final rebuilt = CryptoBusinessSession(
        account,
        SessionCryptoAccess(account: account),
        cold,
      );
      _documents(rebuilt);
      await rebuilt.pullVerified(scope, 'content', attest: false);
      final restored = await rebuilt.record(scope, 'content', id, type: 'idea');
      expect(restored, isNotNull);
      final decoded = jsonDecode(restored!['raw_payload'] as String) as Map;
      expect(decoded['title'], 'After');
      expect(decoded['futureTop'], raw['futureTop']);
      expect(
        (((decoded['elements'] as List).single as Map)['points'] as List).first,
        point.first,
      );
      expect(
        (decoded['elements'] as List).single['id'],
        (raw['elements'] as List).single['id'],
      );
      expect(
        await cold.rows(
          "SELECT * FROM crypto_received WHERE verdict='quarantined'",
        ),
        isEmpty,
      );
      expect(await cold.rows('SELECT * FROM crypto_outbox'), isEmpty);
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
