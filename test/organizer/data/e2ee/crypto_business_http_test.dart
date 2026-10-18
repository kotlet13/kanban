import 'dart:convert';
import 'dart:io';

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
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inventory_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/shared_finance_models.dart';
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
  final path = Platform.environment['JIVIE_MIGRATION_HTTP_FIXTURE'];
  test(
    'actual repository content route preserves original outbox until exact new proof is projected',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback required');
      final w = fixture['session'] as Map,
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
        title: 'First authenticated title',
      );
      await repository.syncNow();
      final initialRows = await db.rows(
        "SELECT * FROM crypto_business_records WHERE json_extract(projection,'\$.id')=?",
        [task],
      );
      expect(
        initialRows,
        isNotEmpty,
        reason:
            '${repository.state.lastError}; operations=${transport.operations}',
      );
      var current = initialRows.single;
      expect(current['crypto_revision'], 1);
      final draft = repository.state
          .dataForScope(scope)
          .tasks
          .singleWhere((t) => t.id == task);
      transport.withhold = true;
      await repository.updateTask(
        scope,
        draft.copyWith(title: 'Second authenticated title'),
      );
      final original = (await db.rows(
        'SELECT request FROM outbox WHERE record_id=?',
        [task],
      )).single['request'];
      await repository.syncNow();
      current = (await db.rows(
        "SELECT * FROM crypto_business_records WHERE json_extract(projection,'\$.id')=?",
        [task],
      )).single;
      expect(current['crypto_revision'], 1);
      expect(
        (await db.rows('SELECT request FROM outbox WHERE record_id=?', [
          task,
        ])).single['request'],
        original,
      );
      expect(
        await db.rows("SELECT * FROM crypto_outbox WHERE state='applied'"),
        isNotEmpty,
      );
      transport.withhold = false;
      await repository.syncNow();
      current = (await db.rows(
        "SELECT * FROM crypto_business_records WHERE json_extract(projection,'\$.id')=?",
        [task],
      )).single;
      expect(current['crypto_revision'], 2);
      expect(
        jsonDecode(current['raw_payload'] as String)['title'],
        'Second authenticated title',
      );
      expect(
        await db.rows('SELECT * FROM outbox WHERE record_id=?', [task]),
        isEmpty,
      );
      final policy = await repository.refreshFinancePolicy(scope);
      expect(policy.canWrite, isTrue);
      final ledger = await repository.createFinanceAccount(
        scopeId: scope,
        name: 'PRIVATE_LEDGER',
        currency: 'EUR',
      );
      await repository.syncNow();
      expect(
        (await db.rows(
          "SELECT * FROM crypto_business_records WHERE json_extract(projection,'\$.id')=?",
          [ledger],
        )).single['crypto_revision'],
        1,
      );
      final expense = await repository.createFinanceEntry(
        scopeId: scope,
        accountId: ledger,
        kind: FinanceEntryKind.expense,
        amountMinor: 12345,
        currency: 'EUR',
        title: 'PRIVATE_EXPENSE',
        occurredAt: DateTime.utc(2026, 10, 17),
      );
      await repository.syncNow();
      final expenseRows = await db.rows(
        "SELECT * FROM crypto_business_records WHERE json_extract(projection,'\$.id')=?",
        [expense],
      );
      expect(
        expenseRows,
        isNotEmpty,
        reason:
            '${repository.state.lastError}; '
            '${await db.rows("SELECT json_extract(wire,'\$.type') AS type,verdict,error FROM crypto_received WHERE domain=\'finance\'")}',
      );
      expect(expenseRows.single['crypto_revision'], 1);
      expect(
        await db.rows('SELECT * FROM finance_outbox WHERE record_id=?', [
          expense,
        ]),
        isEmpty,
      );
      expect(
        (await db.rows('SELECT finance_complete FROM scopes WHERE id=?', [
          scope,
        ])).single['finance_complete'],
        0,
      );
      final runtime = CryptoBusinessSession(
        account,
        SessionCryptoAccess(account: account),
        db,
      );
      // A concurrent sync advancing coordinates between inventory and checkpoint
      // ACK must not make the older signed observed snapshot complete.
      var raced = false;
      transport.afterCheckpoint = () async {
        transport.afterCheckpoint = null;
        raced = true;
        await db.execute(
          "UPDATE crypto_scope_state SET scope_sequence=scope_sequence+1,complete=0 WHERE partition=? AND scope_id=? AND domain='finance'",
          [session.profile.partition, scope],
        );
      };
      final secondLedger = crypto.randomId();
      final bankTime = DateTime.utc(2026, 10, 17);
      final bankRaw = SharedFinanceAccount(
        id: secondLedger,
        name: 'Concurrent account',
        currency: 'EUR',
        createdAt: bankTime,
        updatedAt: bankTime,
      ).toPayload(contractVersion: 3);
      await runtime.publishRaw(
        scopeId: scope,
        domain: 'finance',
        id: secondLedger,
        type: 'financeAccount',
        operationId: crypto.randomId(),
        expectedRevision: 0,
        rawPayload: bankRaw,
        localHash: await cryptoSha256(CryptoInventoryJson.encode(bankRaw)),
      );
      await runtime.pullVerified(scope, 'finance');
      expect(raced, isTrue);
      expect(
        (await db.rows(
          "SELECT complete FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain='finance'",
          [session.profile.partition, scope],
        )).single['complete'],
        0,
      );
      await runtime.pullVerified(scope, 'finance');
      expect(
        (await db.rows(
          "SELECT complete FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain='finance'",
          [session.profile.partition, scope],
        )).single['complete'],
        1,
      );
      final linkedExpense = crypto.randomId();
      final linkedRaw = SharedFinanceEntry(
        id: linkedExpense,
        accountId: ledger,
        taskId: task,
        kind: FinanceEntryKind.expense,
        status: SharedFinanceStatus.planned,
        amountMinor: 500,
        currency: 'EUR',
        title: 'Bound task cost',
        occurredAt: bankTime,
        createdAt: bankTime,
        updatedAt: bankTime,
      ).toPayload(contractVersion: 3);
      try {
        await runtime.publishRaw(
          scopeId: scope,
          domain: 'finance',
          id: linkedExpense,
          type: 'financeEntry',
          operationId: crypto.randomId(),
          expectedRevision: 0,
          rawPayload: linkedRaw,
          localHash: await cryptoSha256(CryptoInventoryJson.encode(linkedRaw)),
        );
      } catch (error) {
        final outcomes = await db.rows(
          "SELECT json_extract(wire,'\$.type') AS type,verdict,error FROM crypto_received WHERE domain='finance'",
        );
        fail('Synthetic linked expense failed: $error; $outcomes');
      }
      final resolutionId = await runtime.reservedRecordId(
        scope,
        'taskResolution:$task',
      );
      expect(
        (await runtime.record(
          scope,
          'finance',
          resolutionId,
          type: 'taskDerivationResolution',
        ))!['crypto_revision'],
        1,
      );
      final oldFact = (await runtime.record(
        scope,
        'finance',
        linkedExpense,
        type: 'financeEntry',
      ))!;
      final moved = DateTime.utc(2026, 10, 19, 12);
      final taskDraft = repository.state
          .dataForScope(scope)
          .tasks
          .singleWhere((t) => t.id == task);
      await repository.updateTask(scope, taskDraft.copyWith(dueAt: moved));
      await repository.syncNow();
      final derived = (await runtime.record(
        scope,
        'finance',
        linkedExpense,
        type: 'financeEntry',
      ))!;
      expect(
        derived['crypto_revision'],
        2,
        reason: '${repository.state.lastError}',
      );
      expect(
        jsonDecode(derived['raw_payload'] as String)['plannedAt'],
        moved.toIso8601String(),
      );
      expect(
        jsonDecode(derived['raw_payload'] as String)['amountMinor'],
        jsonDecode(oldFact['raw_payload'] as String)['amountMinor'],
      );
      expect(
        (await runtime.record(
          scope,
          'finance',
          resolutionId,
          type: 'taskDerivationResolution',
        ))!['crypto_revision'],
        2,
      );
      expect(
        await db.rows(
          "SELECT * FROM crypto_received WHERE verdict='quarantined'",
        ),
        isEmpty,
      );
      final projectId = crypto.randomId(),
          phaseA = crypto.randomId(),
          phaseB = crypto.randomId();
      final now = DateTime.utc(2026, 10, 17);
      final payload =
          Map<String, dynamic>.from(
              LocalProject(
                id: projectId,
                title: 'Nested extensions',
                description: '',
                createdAt: now,
                updatedAt: now,
                area: ProjectArea.home,
                phases: [
                  ProjectPhase(id: phaseA, title: 'A'),
                  ProjectPhase(id: phaseB, title: 'B'),
                ],
              ).toJson(),
            )
            ..remove('id')
            ..remove('revision')
            ..remove('createdByAccountId')
            ..remove('updatedByAccountId');
      (payload['phases'][0] as Map)['futureNested'] = {
        'opaque': ['Čebelica', 7, true, 0.1, -0.0, 1e20],
      };
      (payload['phases'][1] as Map)['futureNested'] = {
        'mustDisappearOnDelete': true,
      };
      await runtime.publishRaw(
        scopeId: scope,
        id: projectId,
        type: 'project',
        operationId: crypto.randomId(),
        expectedRevision: 0,
        rawPayload: payload,
        localHash: await CryptoBusinessJson.hash(payload),
      );
      await repository.syncNow();
      var project = repository.state
          .dataForScope(scope)
          .projects
          .singleWhere((p) => p.id == projectId);
      await repository.updateProject(
        scope,
        project.copyWith(
          phases: [
            project.phases[1],
            project.phases[0].copyWith(title: 'A edited'),
          ],
        ),
      );
      await repository.syncNow();
      project = repository.state
          .dataForScope(scope)
          .projects
          .singleWhere((p) => p.id == projectId);
      await repository.updateProject(
        scope,
        project.copyWith(
          phases: [project.phases.singleWhere((p) => p.id == phaseA)],
        ),
      );
      await repository.syncNow();
      final retained = jsonDecode(
        (await runtime.record(scope, 'content', projectId))!['raw_payload']
            as String,
      );
      expect(
        (retained['phases'] as List),
        hasLength(1),
        reason:
            '${repository.state.lastError}; ${transport.failures}; ${transport.operations.length} HTTP requests',
      );
      expect(retained['phases'][0]['futureNested'], {
        'opaque': ['Čebelica', 7, true, 0.1, -0.0, 1e20],
      });
      final gardenId = crypto.randomId(), ideaId = crypto.randomId();
      final fractional = <String, Map<String, dynamic>>{
        'garden': Map<String, dynamic>.from(
          Garden(
            id: gardenId,
            name: 'Fractional garden',
            createdAt: now,
            updatedAt: now,
            widthMeters: 2.75,
            heightMeters: 4.125,
            areas: [
              GardenArea(
                id: crypto.randomId(),
                label: 'Bed',
                x: 0.1,
                y: -0.0,
                width: 0.25,
                height: 0.375,
              ),
            ],
          ).toJson(),
        ),
        'idea': Map<String, dynamic>.from(
          IdeaBoard(
            id: ideaId,
            title: 'Fractional idea',
            createdAt: now,
            updatedAt: now,
            width: 1600.5,
            height: 1200.25,
            elements: [
              IdeaElement(
                id: crypto.randomId(),
                kind: IdeaElementKind.stroke,
                x: 0.1,
                y: -0.0,
                width: 100.5,
                height: 200.25,
                rotation: 0.125,
                points: [
                  const IdeaPoint(0.1, -0.0),
                  const IdeaPoint(10.25, 20.5),
                ],
              ),
            ],
          ).toJson(),
        ),
      };
      for (final entry in fractional.entries) {
        await runtime.publishRaw(
          scopeId: scope,
          id: entry.value['id'],
          type: entry.key,
          operationId: crypto.randomId(),
          expectedRevision: 0,
          rawPayload: entry.value,
          localHash: await CryptoBusinessJson.hash(entry.value),
        );
      }
      final cold = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(cold.close);
      final rebuilt = CryptoBusinessSession(
        account,
        SessionCryptoAccess(account: account),
        cold,
      );
      await rebuilt.pullVerified(scope, 'content');
      final coldTask = await rebuilt.record(scope, 'content', task);
      expect(coldTask!['crypto_revision'], 3);
      expect(
        jsonDecode(coldTask['raw_payload'] as String)['title'],
        'Second authenticated title',
      );
      await rebuilt.pullVerified(scope, 'finance');
      final coldExpense = (await rebuilt.record(
        scope,
        'finance',
        linkedExpense,
        type: 'financeEntry',
      ))!;
      expect(coldExpense['crypto_revision'], 2);
      expect(
        jsonDecode(coldExpense['raw_payload'] as String)['plannedAt'],
        moved.toIso8601String(),
      );
      expect(
        await cold.rows(
          "SELECT * FROM crypto_received WHERE verdict='quarantined'",
        ),
        isEmpty,
      );
      final coldProject = await rebuilt.record(scope, 'content', projectId);
      expect(coldProject!['crypto_revision'], 3);
      expect(jsonDecode(coldProject['raw_payload'] as String), retained);
      for (final entry in fractional.entries) {
        final projected = await rebuilt.record(
          scope,
          'content',
          entry.value['id'],
          type: entry.key,
        );
        expect(
          projected,
          isNotNull,
          reason:
              '${entry.key}: ${await cold.rows("SELECT record_id,verdict,error FROM crypto_received")}; histories=${await cold.rows("SELECT * FROM crypto_business_history_jobs")}',
        );
        expect(
          CryptoBusinessJson.canonical(
            jsonDecode(projected!['raw_payload'] as String),
          ),
          CryptoBusinessJson.canonical(entry.value),
        );
      }
      expect(
        await cold.rows('SELECT * FROM crypto_business_history_proofs'),
        isNotEmpty,
      );
      expect(
        transport.operations.where(
          (op) => RegExp(r'^sync[2-6]?\.(push|pull)$').hasMatch(op),
        ),
        isEmpty,
      );
    },
    skip: path == null ? 'Synthetic loopback fixture not requested' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
