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

// Opt-in paired measurement on frozen postedit synthetic loopback state.
// No business edit, setup, scheduler, quota override or timed pacing.
class _Wire extends http.BaseClient {
  final http.Client delegate = http.Client();
  final calls = <Map<String, Object?>>[];
  int active = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final operation = request is http.Request
        ? (jsonDecode(request.body) as Map)['op'] as String
        : 'unknown';
    final metric = <String, Object?>{
      'operation': operation,
      'requestBodyBytes': request.contentLength ?? 0,
      'responseBodyBytes': 0,
      'status': null,
      'transportError': null,
    };
    calls.add(metric);
    final watch = Stopwatch()..start();
    active++;
    try {
      final response = await delegate.send(request);
      metric['status'] = response.statusCode;
      final bytes = await response.stream.toBytes();
      metric['responseBodyBytes'] = bytes.length;
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
    } catch (error) {
      metric['transportError'] = error.runtimeType.toString();
      rethrow;
    } finally {
      watch.stop();
      metric['elapsedMicroseconds'] = watch.elapsedMicroseconds;
      active--;
    }
  }

  @override
  void close() => delegate.close();
}

class _Transport extends HttpCollaborationTransport {
  _Transport(this.wire) : super(client: wire);
  final _Wire wire;
  final calls = <Map<String, Object?>>[];
  final scopeLabels = <String, String>{};
  String? dispatchLabel;
  int? dispatchSequence;
  String? directoryRead;
  List<String>? directoryParamNames;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    final metric = <String, Object?>{
      'operation': operation,
      'errorCode': null,
      'dispatch': dispatchLabel,
      'dispatchSequence': dispatchSequence,
      // Only fixture-relative labels and public request-shape counts leave the
      // transport. Do not log scope/account IDs, tokens, hashes or payloads.
      if (operation == 'crypto2.authority.snapshot')
        'snapshotSelector': {
          'triggerOperation': directoryRead,
          'triggerParamNames': directoryParamNames,
          'scope': params['scopeId'] == null
              ? 'account_catalog'
              : scopeLabels[params['scopeId']] ?? 'other',
          'includeChildren': params['includeChildren'] == true,
          'accountAfterGeneration': params['accountAfterGeneration'],
          'directoryHintCount': params['directoryAfterGenerations'] is Map
              ? (params['directoryAfterGenerations'] as Map).length
              : 0,
        },
    };
    calls.add(metric);
    final watch = Stopwatch()..start();
    try {
      return await super.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
    } catch (error) {
      metric['errorCode'] = error is CollaborationException
          ? error.code
          : error.runtimeType.toString();
      rethrow;
    } finally {
      watch.stop();
      metric['elapsedMicroseconds'] = watch.elapsedMicroseconds;
    }
  }
}

class _Directory extends AccountDirectoryRepository {
  _Directory({
    required super.reducer,
    required super.session,
    required _Transport transport,
    required super.store,
    required super.isCurrent,
  }) : traceTransport = transport,
       super(transport: transport);

  final _Transport traceTransport;

  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    final previousRead = traceTransport.directoryRead;
    final previousNames = traceTransport.directoryParamNames;
    traceTransport.directoryRead = operation;
    traceTransport.directoryParamNames = params.keys.toList()..sort();
    try {
      return await super.call(operation, params);
    } finally {
      traceTransport.directoryRead = previousRead;
      traceTransport.directoryParamNames = previousNames;
    }
  }
}

class _Router extends CryptoBusinessRouter {
  _Router({
    required super.database,
    required super.accountFor,
    required this.transport,
  });
  final _Transport transport;
  final segments = <Map<String, Object?>>[];
  int _dispatchSequence = 0;
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    final start = transport.wire.calls.length;
    final previousLabel = transport.dispatchLabel;
    final previousSequence = transport.dispatchSequence;
    final sequence = ++_dispatchSequence;
    transport.dispatchLabel = operation;
    transport.dispatchSequence = sequence;
    final watch = Stopwatch()..start();
    try {
      return await super.dispatch(
        session: session,
        operation: operation,
        params: params,
        protectedScopeIds: protectedScopeIds,
      );
    } finally {
      watch.stop();
      segments.add({
        'dispatch': operation,
        'dispatchSequence': sequence,
        'httpRequests': transport.wire.calls.length - start,
        'elapsedMicroseconds': watch.elapsedMicroseconds,
      });
      transport.dispatchLabel = previousLabel;
      transport.dispatchSequence = previousSequence;
    }
  }
}

List<Map<String, Object?>> _aggregate(List<Map<String, Object?>> calls) {
  final groups = <String, Map<String, Object?>>{};
  for (final call in calls) {
    final op = call['operation']! as String;
    final group = groups.putIfAbsent(
      op,
      () => <String, Object?>{
        'operation': op,
        'count': 0,
        'elapsedMicroseconds': 0,
        'requestBodyBytes': 0,
        'responseBodyBytes': 0,
      },
    );
    for (final key in [
      'count',
      'elapsedMicroseconds',
      'requestBodyBytes',
      'responseBodyBytes',
    ]) {
      group[key] =
          (group[key]! as int) +
          (key == 'count' ? 1 : (call[key] as int? ?? 0));
    }
  }
  return groups.values.toList()..sort(
    (a, b) => (b['elapsedMicroseconds']! as int).compareTo(
      a['elapsedMicroseconds']! as int,
    ),
  );
}

void main() {
  final fixturePath = Platform.environment['JIVIE_METADATA_COMPARE_FIXTURE'];
  final arm = Platform.environment['JIVIE_METADATA_COMPARE_ARM'];
  test(
    'bounded metadata optimization comparison on frozen synthetic state',
    () async {
      if (arm != 'baseline' && arm != 'optimized') {
        throw StateError('Explicit baseline or optimized arm required');
      }
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true ||
          Uri.parse(url).host != '127.0.0.1' ||
          Uri.parse(url).port != 59776) {
        throw StateError('Existing synthetic loopback59776 required');
      }
      // A new comparison can reuse this harness with its own frozen seed and
      // result directory, leaving completed comparisons untouched.
      final comparisonRoot =
          Platform.environment['JIVIE_METADATA_COMPARE_ROOT'];
      final root =
          comparisonRoot ??
          '${File(fixturePath).parent.path}/metadata-comparison';
      if (comparisonRoot != null &&
          (!Directory(comparisonRoot).isAbsolute ||
              Directory(comparisonRoot).parent.resolveSymbolicLinksSync() !=
                  File(fixturePath).parent.resolveSymbolicLinksSync() ||
              Directory(comparisonRoot).resolveSymbolicLinksSync() ==
                  Directory(
                    '${File(fixturePath).parent.path}/metadata-comparison',
                  ).resolveSymbolicLinksSync())) {
        throw StateError('A separate absolute comparison directory required');
      }
      final statePath = '$root/$arm/client';
      final baseline =
          jsonDecode(
                await File(
                  '$root/postedit-baseline-private.json',
                ).readAsString(),
              )
              as Map;
      final originalFinance = (baseline['finance'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final originalSigned = (baseline['signed'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final output = File('$root/$arm/result.json');
      final attemptsFile = File('$root/$arm/attempts.json');
      final attempts = attemptsFile.existsSync()
          ? jsonDecode(await attemptsFile.readAsString()) as Map
          : <String, dynamic>{};
      final attempt = (attempts['attempts'] as int? ?? 0) + 1;
      if (attempt > 3) throw StateError('Three arm attempts exhausted');
      attempts['attempts'] = attempt;
      await attemptsFile.writeAsString(jsonEncode(attempts), flush: true);
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
      final db = CollaborationDatabase(
        NativeDatabase(File('$statePath/client.sqlite')),
      );
      final transport = _Transport(_Wire());
      final codec = CryptoCodec(await SodiumInit.init());
      final account = AccountCryptoV2Workflow(
        _Directory(
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
      final partition = session.profile.partition;
      Future<List<Map<String, dynamic>>> finance() => db.rows(
        'SELECT scope_id,id,type,server_revision,payload FROM finance_records WHERE partition=? ORDER BY scope_id,id',
        [partition],
      );
      Future<List<Map<String, dynamic>>> signed() => db.rows(
        'SELECT request_id,operation,signed_body,request_hash FROM crypto_outbox WHERE partition=? ORDER BY request_id',
        [partition],
      );
      // Never create/rebase this snapshot in a running arm. Both arm databases
      // were copied from the same immutable postedit seed before any HTTP.
      expect(originalFinance, hasLength(3));
      expect(originalSigned, hasLength(62));
      if (!output.existsSync()) {
        expect(await finance(), originalFinance);
        expect(await signed(), originalSigned);
      }
      final setup =
          jsonDecode(await File('$statePath/setup-plan.json').readAsString())
              as Map;
      final parent = setup['parent'] as String,
          child = setup['child'] as String;
      transport.scopeLabels.addAll({parent: 'parent', child: 'child'});
      final result = output.existsSync()
          ? Map<String, Object?>.from(
              jsonDecode(await output.readAsString()) as Map,
            )
          : <String, Object?>{
              'synthetic': true,
              'arm': arm,
              'protocol':
                  'identical postedit seed; 1 warmup + 2 measured unchanged syncNow cycles per arm',
              'bodyBytesOnly': true,
              'timedPacingOrQuotaOverride': false,
              'priorSignedRequests': originalSigned.length,
              'samples': <Map<String, Object?>>[],
            };
      result['latestAttempt'] = attempt;
      Future<void> save() =>
          output.writeAsString(jsonEncode(result), flush: true);
      await repository.initialize();
      result['initializationHttpRequests'] = transport.wire.calls.length;
      await save();
      expect(
        repository.state.scopes.map((s) => s.id),
        containsAll([parent, child]),
      );
      Future<Map<String, Object?>> health() async {
        final data = repository.state.dataForScope(parent);
        final totals = summarizeSharedFinance(
          accounts: data.financeAccounts,
          entries: data.financeEntries,
          transfers: data.financeTransfers,
        )['EUR'];
        final choice = await db.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['finance_account_choices:$partition:$child'],
        );
        final currentSigned = await signed();
        final preserved = originalSigned
            .where(
              (original) => currentSigned.any(
                (row) => jsonEncode(row) == jsonEncode(original),
              ),
            )
            .length;
        return {
          'balanceMinor': totals?.balanceMinor.toString(),
          'expenseMinor': totals?.expenseMinor.toString(),
          'accounts': data.financeAccounts.length,
          'entries': data.financeEntries.length,
          'choices': choice.isEmpty
              ? null
              : (jsonDecode(choice.single['value'] as String)['accounts']
                        as List)
                    .length,
          'pending': repository.state.pendingCount,
          'conflicting': repository.state.conflicts.length,
          'blocked': repository.state.blockedCount,
          'unresolved': (await repository.syncWork()).unresolved,
          'lastErrorCode': repository.state.lastError?.code,
          'preservedPriorSignedRequests': preserved,
          'totalSignedRequests': currentSigned.length,
          'financeRowsExact':
              jsonEncode(await finance()) == jsonEncode(originalFinance),
        };
      }

      Future<void> sample(String label) async {
        if ((result['samples'] as List).any(
          (m) => m['label'] == label && m['passed'] == true,
        )) {
          return; // A successful sample is never repeated for a prettier number.
        }
        expect(transport.wire.active, 0);
        final httpStart = transport.wire.calls.length,
            rpcStart = transport.calls.length,
            dispatchStart = router.segments.length;
        final previousSequence = repository.lastSyncCompletion?.sequence ?? 0;
        final before = await health();
        final started = DateTime.now().toUtc().toIso8601String();
        String? thrown;
        final watch = Stopwatch()..start();
        try {
          await repository.syncNow();
        } catch (error) {
          thrown = error is CollaborationException
              ? error.code
              : error.runtimeType.toString();
        } finally {
          watch.stop();
        }
        final httpCalls = transport.wire.calls.skip(httpStart).toList();
        final rpcCalls = transport.calls.skip(rpcStart).toList();
        final completion = repository.lastSyncCompletion;
        final statuses = <String, int>{};
        for (final call in httpCalls) {
          final status = call['status']?.toString() ?? 'no_response';
          statuses[status] = (statuses[status] ?? 0) + 1;
        }
        final after = await health();
        final metric = <String, Object?>{
          'label': label,
          'measured': label != 'warmup',
          'attempt': attempt,
          'startedAtUtc': started,
          'elapsedMicroseconds': watch.elapsedMicroseconds,
          'httpRequests': httpCalls.length,
          'rpcCalls': rpcCalls.length,
          'httpRequestBodyBytes': httpCalls.fold<int>(
            0,
            (n, c) => n + (c['requestBodyBytes']! as int),
          ),
          'httpResponseBodyBytes': httpCalls.fold<int>(
            0,
            (n, c) => n + (c['responseBodyBytes']! as int),
          ),
          'httpStatuses': statuses,
          'rateLimits': httpCalls.where((c) => c['status'] == 429).length,
          'rpcFailures': rpcCalls.where((c) => c['errorCode'] != null).toList(),
          'transportFailures': httpCalls
              .where((c) => c['transportError'] != null)
              .toList(),
          'thrownCode': thrown,
          'completionErrorCode': completion?.error is CollaborationException
              ? (completion!.error! as CollaborationException).code
              : completion?.error?.runtimeType.toString(),
          'freshCompletion':
              completion != null && completion.sequence > previousSequence,
          'before': before,
          'after': after,
          'httpOperations': _aggregate(httpCalls),
          'rpcOperations': _aggregate(rpcCalls),
          'authoritySnapshotCalls': rpcCalls
              .where((c) => c['operation'] == 'crypto2.authority.snapshot')
              .toList(),
          'businessDispatches': router.segments.skip(dispatchStart).toList(),
        };
        (result['samples'] as List).add(metric);
        await save();
        debugPrint('METADATA_COMPARE_SAMPLE ${jsonEncode(metric)}');
        expect(transport.wire.active, 0);
        expect(thrown, isNull);
        expect(metric['freshCompletion'], isTrue);
        expect(httpCalls, isNotEmpty);
        expect(completion!.identity, repository.backgroundSyncIdentity);
        expect(completion.error, isNull);
        expect(metric['rateLimits'], 0);
        expect(metric['rpcFailures'], isEmpty);
        expect(metric['transportFailures'], isEmpty);
        expect(after['balanceMinor'], '3333');
        expect(after['expenseMinor'], '1234');
        expect(after['accounts'], 2);
        expect(after['entries'], 1);
        expect(after['choices'], 2);
        expect(after['pending'], 0);
        expect(after['conflicting'], 0);
        expect(after['blocked'], 0);
        expect(after['unresolved'], isFalse);
        expect(after['lastErrorCode'], isNull);
        expect(after['financeRowsExact'], isTrue);
        expect(after['preservedPriorSignedRequests'], originalSigned.length);
        metric['passed'] = true;
        await save();
      }

      await sample('warmup');
      await sample('unchanged_1');
      await sample('unchanged_2');
      result['complete'] = true;
      await save();
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
