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
import 'package:kanban/organizer/domain/collaboration_models.dart';

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
  final failures = <Map<String, Object>>[];
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
    } on CollaborationException catch (error, stack) {
      final failure = <String, Object>{
        'operation': operation,
        'code': error.code,
        'stack': stack.toString(),
      };
      failures.add(failure);
      debugPrint('STALE_CHOICE_RPC_FAILURE ${jsonEncode(failure)}');
      if (error.code == 'rate_limited') rateLimits++;
      rethrow;
    }
  }
}

void main() {
  final fixturePath = Platform.environment['JIVIE_FINANCE_REUSE_HTTP_FIXTURE'];
  test(
    'ordinary sync automatically refreshes a newly stale existing choice',
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
      expect(initialized, isTrue);
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

      // Only the already prepared private synthetic parent and child are used.
      final setup =
          jsonDecode(await File('$statePath/setup-plan.json').readAsString())
              as Map;
      final parent = setup['parent'] as String,
          child = setup['child'] as String;
      final planFile = File('$statePath/stale-choice-transition.json');
      final phase = Platform.environment['JIVIE_STALE_CHOICE_PHASE'];
      expect(const {'baseline', 'fixed'}, contains(phase));
      final partition = session.profile.partition;
      Future<List<Map<String, dynamic>>> finance() => db.rows(
        'SELECT scope_id,id,type,server_revision,payload FROM finance_records WHERE partition=? ORDER BY scope_id,id',
        [partition],
      );
      Future<List<Map<String, dynamic>>> signed() => db.rows(
        'SELECT request_id,operation,signed_body,request_hash FROM crypto_outbox WHERE partition=? ORDER BY sequence',
        [partition],
      );
      Map<String, dynamic> plan;
      if (!planFile.existsSync()) {
        expect(phase, 'baseline');
        final before = await finance();
        expect(
          before.where((r) => r['type'] == 'financeAccount'),
          hasLength(1),
        );
        expect(before.where((r) => r['type'] == 'financeEntry'), hasLength(1));
        plan = {
          'synthetic': true,
          'parent': parent,
          'child': child,
          'originalFinance': before,
          'originalSignedRequests': await signed(),
          'attempts': <String, int>{},
        };
        // Intent is durable before local creation; its generated exact ID and
        // immutable queued request are persisted before any server submission.
        await planFile.writeAsString(jsonEncode(plan), flush: true);
        final added = await repository.createFinanceAccount(
          scopeId: parent,
          name: 'Synthetic stale choice zero ledger',
          currency: 'EUR',
          openingBalanceMinor: 0,
        );
        plan['addedAccountId'] = added;
        plan['addedQueuedRequests'] = await db.rows(
          'SELECT op_id,record_id,request FROM finance_outbox WHERE partition=? AND record_id=? ORDER BY sequence',
          [partition, added],
        );
        expect(plan['addedQueuedRequests'], hasLength(1));
        await planFile.writeAsString(jsonEncode(plan), flush: true);
      } else {
        plan = (jsonDecode(await planFile.readAsString()) as Map)
            .cast<String, dynamic>();
      }
      expect(plan['parent'], parent);
      expect(plan['child'], child);
      expect(plan['addedAccountId'], isA<String>());
      final attempts = (plan['attempts'] as Map).cast<String, dynamic>();
      attempts[phase!] = (attempts[phase] as int? ?? 0) + 1;
      expect(attempts[phase] as int, lessThanOrEqualTo(3));
      plan['attempts'] = attempts;
      await planFile.writeAsString(jsonEncode(plan), flush: true);
      // The unchanged quota and an ordinary sync are used. This is a regression
      // result, not a repeated cost benchmark or explicit choice wizard.
      final phaseFinance = await finance();
      final phaseSigned = await signed();
      plan['${phase}StartFinance'] = phaseFinance;
      plan['${phase}StartSignedRequests'] = phaseSigned;
      await planFile.writeAsString(jsonEncode(plan), flush: true);
      transport.setup = false;
      router.reuse = true;
      await repository.syncNow();
      final completion = repository.lastSyncCompletion!;
      final errorCode = completion.error is CollaborationException
          ? (completion.error as CollaborationException).code
          : completion.error?.runtimeType.toString();
      final after = await finance();
      final originals = (plan['originalFinance'] as List).cast<Map>();
      for (final row in originals) {
        expect(
          after.singleWhere(
            (r) => r['scope_id'] == row['scope_id'] && r['id'] == row['id'],
          ),
          row,
        );
      }
      expect(after.where((r) => r['type'] == 'financeAccount'), hasLength(2));
      expect(after.where((r) => r['type'] == 'financeEntry'), hasLength(1));
      expect(
        after.singleWhere(
          (r) => r['id'] == plan['addedAccountId'],
        )['server_revision'],
        greaterThan(0),
      );
      final currentSigned = await signed();
      for (final row in (plan['originalSignedRequests'] as List).cast<Map>()) {
        expect(
          currentSigned.singleWhere(
            (r) => r['request_id'] == row['request_id'],
          ),
          row,
        );
      }
      if (phase == 'fixed') {
        expect(after, phaseFinance);
        for (final row in phaseSigned) {
          expect(
            currentSigned.singleWhere(
              (r) => r['request_id'] == row['request_id'],
            ),
            row,
          );
        }
      }
      final data = repository.state.dataForScope(parent);
      final totals = summarizeSharedFinance(
        accounts: data.financeAccounts,
        entries: data.financeEntries,
        transfers: data.financeTransfers,
      )['EUR']!;
      expect(totals.balanceMinor, BigInt.from(3333));
      expect(totals.expenseMinor, BigInt.from(1234));
      final choiceRows = await db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['finance_account_choices:$partition:$child'],
      );
      final result = <String, Object?>{
        'synthetic': true,
        'phase': phase,
        'attempt': attempts[phase],
        'errorCode': errorCode,
        'lastErrorCode': repository.state.lastError?.code,
        'unresolved': completion.work.unresolved,
        'addedAccountId': plan['addedAccountId'],
        'originalFinancePreserved': originals.length,
        'originalSignedRequestsPreserved':
            (plan['originalSignedRequests'] as List).length,
        'balanceMinor': totals.balanceMinor.toString(),
        'expenseMinor': totals.expenseMinor.toString(),
        'rateLimits': transport.rateLimits,
        'phaseStartSignedRequestsPreserved': phaseSigned.length,
        'failedOperations': transport.failures,
        'dispatches': router.segments,
        'choiceCount': choiceRows.isEmpty
            ? null
            : (jsonDecode(choiceRows.single['value'] as String)['accounts']
                      as List)
                  .length,
      };
      await File(
        '${File(fixturePath).parent.path}/stale-choice-$phase-result.json',
      ).writeAsString(jsonEncode(result), flush: true);
      debugPrint('STALE_CHOICE_REGRESSION ${jsonEncode(result)}');
      expect(transport.rateLimits, 0);
      if (phase == 'baseline') {
        expect(errorCode, 'crypto_account_choices_source_set_changed');
      } else {
        expect(completion.error, isNull);
        expect(repository.state.lastError, isNull);
        expect(completion.work.unresolved, isFalse);
        expect(choiceRows, hasLength(1));
        final choices =
            jsonDecode(choiceRows.single['value'] as String)['accounts']
                as List;
        expect(choices, hasLength(2));
        expect(choices.map((a) => a['id']), contains(plan['addedAccountId']));
      }
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
