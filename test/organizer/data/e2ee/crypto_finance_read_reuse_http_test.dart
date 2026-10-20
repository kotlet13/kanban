import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
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
import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

import 'package:sodium/sodium.dart';

import '../collaboration_repository_test.dart' show MemorySessionStore;

class _Secure implements AccountCryptoStore {
  _Secure(this.file) {
    if (file?.existsSync() == true) {
      values.addAll(
        (jsonDecode(file!.readAsStringSync()) as Map).cast<String, String>(),
      );
    }
  }
  final File? file;
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    await file?.writeAsString(jsonEncode(values), flush: true);
  }
}

class _Router extends CryptoBusinessRouter {
  _Router({
    required super.database,
    required super.accountFor,
    required this.transport,
  });
  final _Transport transport;
  bool reuse = false;
  @override
  Future<T> withFinanceRead<T>({
    required DeviceSession session,
    required Future<T> Function() read,
  }) => reuse ? super.withFinanceRead(session: session, read: read) : read();
  final segments = <Map<String, Object>>[];
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    final start = transport.operations.length;
    try {
      return await super.dispatch(
        session: session,
        operation: operation,
        params: params,
        protectedScopeIds: protectedScopeIds,
      );
    } finally {
      if (!transport.setup) {
        final calls = transport.operations.skip(start).toList();
        segments.add({
          'dispatch': operation,
          'requests': calls.length,
          'pulls': calls.where((op) => op == 'crypto2.records.pull').length,
        });
      }
    }
  }
}

class _Wire extends http.BaseClient {
  final http.Client delegate = http.Client();
  int requestBytes = 0, responseBytes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestBytes += request.contentLength ?? 0;
    final response = await delegate.send(request);
    final bytes = await response.stream.toBytes();
    responseBytes += bytes.length;
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => delegate.close();
}

class _Transport extends HttpCollaborationTransport {
  _Transport(this.wire) : super(client: wire);
  final _Wire wire;
  final operations = <String>[];
  final issued = <DateTime>[];
  bool setup = true;
  int rateLimits = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    // Setup pacing keeps a synthetic fixture below the unchanged server quota.
    // The measured ordinary sync is neither paced nor retried here.
    final now = DateTime.now();
    issued.removeWhere((t) => now.difference(t).inSeconds > 60);
    if (setup && issued.length >= 450) {
      await Future<void>.delayed(
        const Duration(seconds: 61) - now.difference(issued.first),
      );
      issued.clear();
    }
    issued.add(DateTime.now());
    operations.add(operation);
    try {
      return await super.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
    } on CollaborationException catch (error) {
      if (error.code == 'rate_limited') rateLimits++;
      rethrow;
    }
  }
}

void main() {
  final fixturePath = Platform.environment['JIVIE_FINANCE_REUSE_HTTP_FIXTURE'];
  test(
    'normal finance sync counts complete HTTP reads before and after reuse',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Isolated synthetic loopback fixture required');
      }
      final actor =
          Platform.environment['JIVIE_FINANCE_REUSE_ACTOR'] ?? 'owner';
      final wire = fixture['accounts'][actor]['session'] as Map;
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
      final statePath = Platform.environment['JIVIE_FINANCE_REUSE_STATE_DIR'];
      if (statePath != null &&
          !statePath.startsWith('${File(fixturePath).parent.path}/')) {
        throw StateError(
          'Persistent synthetic state must stay beside the private fixture',
        );
      }
      if (statePath != null) await Directory(statePath).create(recursive: true);
      final db = CollaborationDatabase(
        statePath == null
            ? throw StateError('Persistent synthetic client state required')
            : NativeDatabase(File('$statePath/client.sqlite')),
      );
      final transport = _Transport(_Wire());
      final codec = CryptoCodec(await SodiumInit.init());
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(codec),
          session: session,
          transport: transport,
          store: CryptoIdentityStore(
            db,
            _Secure(File('$statePath/secure.json')),
            session.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      final initialized = (await db.rows(
        'SELECT 1 FROM crypto_identity_secrets WHERE partition=?',
        [session.profile.partition],
      )).isNotEmpty;
      if (!initialized) {
        final file = await account.prepareRecoveryFile();
        try {
          await account.verifyAndInitialize(file);
        } finally {
          file.fillRange(0, file.length, 0);
        }
      }
      final router = _Router(
        database: db,
        accountFor: (_) async => account,
        transport: transport,
      );
      final repository = CollaborationRepository(
        db,
        transport,
        MemorySessionStore()..value = session,
        cryptoRouter: router,
      );
      addTearDown(repository.close);
      await repository.initialize();
      // Persist scope and exact creation request IDs before the first mutation.
      final planFile = File('$statePath/setup-plan.json');
      final plan = planFile.existsSync()
          ? (jsonDecode(await planFile.readAsString()) as Map)
                .cast<String, String>()
          : <String, String>{
              'parent': codec.randomId(),
              'child': codec.randomId(),
              'parentRequest': codec.randomId(),
              'childRequest': codec.randomId(),
            };
      if (!planFile.existsSync()) {
        await planFile.writeAsString(jsonEncode(plan), flush: true);
      }
      final parent = plan['parent']!, child = plan['child']!;
      final done = await db.rows('SELECT value FROM local_meta WHERE name=?', [
        'synthetic_finance_reuse_setup',
      ]);
      if (done.isEmpty) {
        await repository.syncNow();
        final policy = await repository.sharedContentPolicy();
        if (!policy.accepted) {
          await repository.acceptSharedContentPolicy(policy);
        }
        if (!repository.state.scopes.any((s) => s.id == parent)) {
          await repository.createScope(
            'Synthetic finance parent',
            kind: SharedScopeKind.organization,
            id: parent,
            requestId: plan['parentRequest'],
          );
        }
        await repository.syncNow();
        final ledgers = await db.rows(
          "SELECT id FROM finance_records WHERE partition=? AND scope_id=? AND type='financeAccount' AND json_extract(payload,'\$.name')=?",
          [session.profile.partition, parent, 'Synthetic measured ledger'],
        );
        final ledger = ledgers.isNotEmpty
            ? ledgers.single['id'] as String
            : await repository.createFinanceAccount(
                scopeId: parent,
                name: 'Synthetic measured ledger',
                currency: 'EUR',
                openingBalanceMinor: 4567,
              );
        await repository.syncNow();
        final entries = await db.rows(
          "SELECT id FROM finance_records WHERE partition=? AND scope_id=? AND type='financeEntry' AND json_extract(payload,'\$.title')=?",
          [session.profile.partition, parent, 'Synthetic measured expense'],
        );
        if (entries.isEmpty) {
          await repository.createFinanceEntry(
            scopeId: parent,
            accountId: ledger,
            kind: FinanceEntryKind.expense,
            amountMinor: 1234,
            currency: 'EUR',
            title: 'Synthetic measured expense',
            occurredAt: DateTime.utc(2026, 10, 20),
          );
        }
        await repository.syncNow();
        if (!repository.state.scopes.any((s) => s.id == child)) {
          await repository.createScope(
            'Synthetic finance child',
            kind: SharedScopeKind.project,
            parentScopeId: parent,
            organizationId: parent,
            id: child,
            requestId: plan['childRequest'],
          );
        }
        await repository.syncNow();
        await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
          'synthetic_finance_reuse_setup',
          'complete',
        ]);
      }
      if (Platform.environment['JIVIE_FINANCE_REUSE_FINISH_SELECTION'] == '1') {
        final finished = await db.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['synthetic_finance_reuse_refreshed_choice'],
        );
        if (finished.isEmpty) {
          plan.putIfAbsent('choiceRefresh', codec.randomId);
          plan.putIfAbsent('choiceApprove', codec.randomId);
          await planFile.writeAsString(jsonEncode(plan), flush: true);
          final runtime = CryptoBusinessSession(
            account,
            SessionCryptoAccess(account: account),
            db,
          );
          CryptoBusinessRouter.configurePayloads(runtime);
          final choices = CryptoFinanceAccountChoices(runtime);
          final prepared = await choices.prepare(
            child,
            actionId: plan['choiceRefresh']!,
          );
          await choices.approve(
            child,
            Map<String, dynamic>.from(prepared['offerAuthorization'] as Map),
            actionId: plan['choiceApprove']!,
            recipientAccountId: session.profile.accountId,
            recipientDeviceId: session.profile.deviceId,
          );
          await choices.finish(child, plan['choiceRefresh']!);
          await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
            'synthetic_finance_reuse_refreshed_choice',
            'complete',
          ]);
        }
      }
      expect(repository.state.lastError, isNull);
      expect(
        repository.state.scopes.map((s) => s.id),
        containsAll([parent, child]),
      );
      expect(repository.state.dataForScope(child).projects, hasLength(1));
      final financeBefore = await db.rows(
        'SELECT scope_id,id,type,server_revision,payload FROM finance_records WHERE partition=? ORDER BY scope_id,id',
        [session.profile.partition],
      );
      expect(
        financeBefore.where((r) => r['type'] == 'financeAccount'),
        isNotEmpty,
      );
      expect(
        financeBefore.where((r) => r['type'] == 'financeEntry'),
        isNotEmpty,
      );
      // Give the unchanged, separate fixture a fully fresh standard quota window.
      await Future<void>.delayed(const Duration(seconds: 61));
      transport.setup = false;
      router.reuse = Platform.environment['JIVIE_FINANCE_REUSE_ENABLED'] == '1';
      final paired = Platform.environment['JIVIE_FINANCE_REUSE_PAIRED'] == '1';
      final cycles = paired
          ? 2
          : int.parse(
              Platform.environment['JIVIE_FINANCE_REUSE_CYCLES'] ?? '1',
            );
      if (cycles < 1 || cycles > 3) {
        throw StateError('Bounded synthetic cycles required');
      }
      final measured = <Map<String, Object?>>[];
      for (var cycle = 0; cycle < cycles; cycle++) {
        if (paired) router.reuse = cycle == 0;
        if (cycle > 0 && measured.last['operationCount']! as int > 300) {
          await Future<void>.delayed(const Duration(seconds: 61));
        }
        transport.operations.clear();
        router.segments.clear();
        final requestBytesBefore = transport.wire.requestBytes;
        final responseBytesBefore = transport.wire.responseBytes;
        final watch = Stopwatch()..start();
        await repository.syncNow();
        watch.stop();
        final counts = <String, int>{};
        for (final operation in transport.operations) {
          counts[operation] = (counts[operation] ?? 0) + 1;
        }
        final completion = repository.lastSyncCompletion!;
        expect(completion.identity, repository.backgroundSyncIdentity);
        expect(completion.error, isNull);
        expect(completion.work.unresolved, isFalse);
        final data = repository.state.dataForScope(parent);
        final totals = summarizeSharedFinance(
          accounts: data.financeAccounts,
          entries: data.financeEntries,
          transfers: data.financeTransfers,
        )['EUR']!;
        expect(totals.balanceMinor, BigInt.from(3333));
        expect(totals.expenseMinor, BigInt.from(1234));
        final choices = await db.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['finance_account_choices:${session.profile.partition}:$child'],
        );
        expect(choices, hasLength(1));
        final choicePayload =
            jsonDecode(choices.single['value'] as String) as Map;
        expect(choicePayload['accounts'], hasLength(1));
        expect(
          (choicePayload['accounts'] as List).single['id'],
          data.financeAccounts.single.id,
        );
        final linked = await db.rows(
          "SELECT name,value FROM local_meta WHERE name LIKE 'linked_payment_complete:%' ORDER BY name",
        );
        expect(linked, hasLength(2));
        final metrics = <String, Object?>{
          'synthetic': true,
          'financeReadReuse': router.reuse,
          'balanceMinor': totals.balanceMinor.toString(),
          'expenseMinor': totals.expenseMinor.toString(),
          'nonzeroAccounts': data.financeAccounts.length,
          'nonzeroEntries': data.financeEntries.length,
          'endorsedAccountChoices': (choicePayload['accounts'] as List).length,
          'completePaymentSnapshots': linked.length,
          'actor': actor,
          'operationCount': transport.operations.length,
          'requestBodyBytes': transport.wire.requestBytes - requestBytesBefore,
          'responseBodyBytes':
              transport.wire.responseBytes - responseBytesBefore,
          'elapsedMilliseconds': watch.elapsedMilliseconds,
          'operations': counts,
          'rateLimits': transport.rateLimits,
          'lastErrorCode': repository.state.lastError?.code,
          'reusedClientState': initialized,
          'cycle': cycle + 1,
          'dispatches': List<Map<String, Object>>.of(router.segments),
        };
        measured.add(metrics);
        debugPrint('FINANCE_REUSE_COST ${jsonEncode(metrics)}');
        expect(repository.state.lastError, isNull);
        expect(
          await db.rows(
            'SELECT scope_id,id,type,server_revision,payload FROM finance_records WHERE partition=? ORDER BY scope_id,id',
            [session.profile.partition],
          ),
          financeBefore,
        );
        expect(transport.rateLimits, 0);
        expect(repository.state.dataForScope(child).projects, hasLength(1));
      }
      if (paired) {
        expect(measured.first['financeReadReuse'], isTrue);
        expect(measured.last['financeReadReuse'], isFalse);
        expect(
          measured.first['operationCount'] as int,
          lessThan(measured.last['operationCount'] as int),
        );
        expect(
          (measured.first['operations'] as Map)['crypto2.records.pull'] as int,
          lessThan(
            (measured.last['operations'] as Map)['crypto2.records.pull'] as int,
          ),
        );
      }
      final output = Platform.environment['JIVIE_FINANCE_REUSE_OUTPUT'];
      if (output != null) {
        await File(
          output,
        ).writeAsString(jsonEncode({'synthetic': true, 'cycles': measured}));
      }
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
