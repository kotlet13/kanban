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

// Opt-in speed measurement against the existing private loopback fixture only.
// No scheduler, setup mutations, quota overrides or alternate router behavior.
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
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    final metric = <String, Object?>{'operation': operation, 'errorCode': null};
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

class _Router extends CryptoBusinessRouter {
  _Router({
    required super.database,
    required super.accountFor,
    required this.transport,
  });
  final _Transport transport;
  final segments = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    final start = transport.wire.calls.length;
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
        'httpRequests': transport.wire.calls.length - start,
        'elapsedMicroseconds': watch.elapsedMicroseconds,
      });
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
  final fixturePath = Platform.environment['JIVIE_SYNC_SPEED_FIXTURE'];
  test(
    'bounded current-code sync speed on preserved synthetic state',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true ||
          Uri.parse(url).host != '127.0.0.1' ||
          Uri.parse(url).port != 59776) {
        throw StateError('Existing synthetic loopback59776 required');
      }
      final root = File(fixturePath).parent.path;
      final statePath = '$root/client';
      final output = File('$root/sync-speed-result.json');
      final journal = File('$root/sync-speed-edit-journal.json');
      final attemptsFile = File('$root/sync-speed-attempts.json');
      final attempts = attemptsFile.existsSync()
          ? jsonDecode(await attemptsFile.readAsString()) as Map
          : <String, dynamic>{};
      final attempt = (attempts['attempts'] as int? ?? 0) + 1;
      if (attempt > 3) throw StateError('Three harness attempts exhausted');
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
      expect(
        await db.rows(
          'SELECT 1 FROM crypto_identity_secrets WHERE partition=?',
          [partition],
        ),
        isNotEmpty,
      );
      final setup =
          jsonDecode(await File('$statePath/setup-plan.json').readAsString())
              as Map;
      final parent = setup['parent'] as String,
          child = setup['child'] as String;
      expect(
        await db.rows('SELECT value FROM local_meta WHERE name=?', [
          'synthetic_finance_reuse_setup',
        ]),
        hasLength(1),
      );
      await repository.initialize();
      expect(
        repository.state.scopes.map((s) => s.id),
        containsAll([parent, child]),
      );
      if (!journal.existsSync()) {
        expect((await repository.syncWork()).unresolved, isFalse);
      }
      Future<List<Map<String, dynamic>>> finance() => db.rows(
        'SELECT scope_id,id,type,server_revision,payload FROM finance_records WHERE partition=? ORDER BY scope_id,id',
        [partition],
      );
      Future<List<Map<String, dynamic>>> signed() => db.rows(
        'SELECT request_id,operation,signed_body,request_hash FROM crypto_outbox WHERE partition=? ORDER BY request_id',
        [partition],
      );
      final baselineFile = File('$root/sync-speed-baseline-private.json');
      if (!baselineFile.existsSync()) {
        if (journal.existsSync() || output.existsSync()) {
          throw StateError('Missing original speed baseline; do not rebase');
        }
        await baselineFile.writeAsString(
          jsonEncode({'finance': await finance(), 'signed': await signed()}),
          flush: true,
        );
      }
      final baseline = jsonDecode(await baselineFile.readAsString()) as Map;
      final originalFinance = (baseline['finance'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final originalSigned = (baseline['signed'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      expect(originalFinance, hasLength(3));
      expect(originalSigned.length, greaterThanOrEqualTo(48));
      final result = output.existsSync()
          ? Map<String, Object?>.from(
              jsonDecode(await output.readAsString()) as Map,
            )
          : <String, Object?>{
              'synthetic': true,
              'protocol':
                  'warmup + 3 sequential no-new-business-edit samples + 1 existing expense title edit',
              'bodyBytesOnly': true,
              'reuse': 'current production default',
              'samples': <Map<String, Object?>>[],
              'quotaPauses': <Map<String, Object?>>[],
              'initializationHttpRequests': transport.wire.calls.length,
              'priorSignedRequests': originalSigned.length,
            };
      result['latestAttempt'] = attempt;
      var quotaWindowStart = 0;
      Future<void> save() async {
        await output.writeAsString(jsonEncode(result), flush: true);
      }

      Future<void> freshQuota(String before) async {
        expect(transport.wire.active, 0);
        final pause = Stopwatch()..start();
        final started = DateTime.now().toUtc().toIso8601String();
        await Future<void>.delayed(const Duration(seconds: 30));
        await Future<void>.delayed(const Duration(seconds: 31));
        pause.stop();
        (result['quotaPauses'] as List).add({
          'before': before,
          'startedAtUtc': started,
          'elapsedMicroseconds': pause.elapsedMicroseconds,
          'excludedFromSyncTimings': true,
        });
        quotaWindowStart = transport.wire.calls.length;
        await save();
      }

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
        var preserved = 0;
        for (final original in originalSigned) {
          if (currentSigned.any(
            (row) => jsonEncode(row) == jsonEncode(original),
          )) {
            preserved++;
          }
        }
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
          'financeIdsPreserved':
              (await finance()).map((r) => r['id']).join(',') ==
              originalFinance.map((r) => r['id']).join(','),
        };
      }

      Future<void> sample(String label, {bool unchanged = true}) async {
        if ((result['samples'] as List).any(
          (m) => m['label'] == label && m['passed'] == true,
        )) {
          return; // Already successful stage; never rerun for a prettier number.
        }
        if (transport.wire.calls.length - quotaWindowStart + 200 > 500) {
          await freshQuota(label);
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
          'businessDispatches': router.segments.skip(dispatchStart).toList(),
        };
        (result['samples'] as List).add(metric);
        await save();
        debugPrint('SYNC_SPEED_SAMPLE ${jsonEncode(metric)}');
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
        expect(after['financeIdsPreserved'], isTrue);
        expect(after['preservedPriorSignedRequests'], originalSigned.length);
        if (unchanged) expect(await finance(), originalFinance);
        metric['passed'] = true;
        await save();
      }

      // A resumed process has no safe knowledge of the prior quota window.
      if (attempt > 1) await freshQuota('resume');
      await sample('warmup');
      for (var i = 1; i <= 3; i++) {
        await sample('no_new_business_edit_$i');
      }
      if (result['complete'] == true) return;
      await freshQuota('existing_expense_title_edit');
      // Durable journal before the one normal repository edit. A retry must
      // resume this same mutation; it must never create a second edit/action.
      final beforeEdit = repository.state
          .dataForScope(parent)
          .financeEntries
          .single;
      final editedTitle = 'Synthetic measured expense speed 20261020';
      final editHttpStart = transport.wire.calls.length;
      final editWatch = Stopwatch()..start();
      if (!journal.existsSync()) {
        await journal.writeAsString(
          jsonEncode({
            'synthetic': true,
            'scopeId': parent,
            'recordId': beforeEdit.id,
            'originalFinance': originalFinance,
            'originalPayload': beforeEdit.toPayload(contractVersion: 3),
            'originalRevision': beforeEdit.revision,
            'newTitle': editedTitle,
            'state': 'planned',
          }),
          flush: true,
        );
        await repository.updateFinanceEntry(
          parent,
          beforeEdit.copyWith(title: editedTitle),
        );
        final saved = jsonDecode(await journal.readAsString()) as Map;
        saved['state'] = 'queued';
        await journal.writeAsString(jsonEncode(saved), flush: true);
      } else {
        final saved = jsonDecode(await journal.readAsString()) as Map;
        if (saved['state'] == 'planned') {
          throw StateError(
            'Ambiguous planned edit; preserve state without requeue',
          );
        }
        expect(saved['recordId'], beforeEdit.id);
        expect(beforeEdit.title, editedTitle);
      }
      editWatch.stop();
      final editHealth = await health();
      result.putIfAbsent(
        'editPreparation',
        () => {
          'elapsedMicroseconds': editWatch.elapsedMicroseconds,
          'httpRequests': transport.wire.calls.length - editHttpStart,
          'excludedFromSyncTimings': true,
          'beforeSync': editHealth,
        },
      );
      await save();
      await sample('existing_expense_title_edit', unchanged: false);
      final afterEdit = repository.state
          .dataForScope(parent)
          .financeEntries
          .single;
      expect(afterEdit.id, beforeEdit.id);
      expect(afterEdit.title, editedTitle);
      final editJournal = jsonDecode(await journal.readAsString()) as Map;
      expect(
        afterEdit.revision,
        greaterThan(editJournal['originalRevision'] as int),
      );
      final finalFinance = await finance();
      for (final original in originalFinance) {
        final current = finalFinance.singleWhere(
          (r) => r['id'] == original['id'],
        );
        if (original['id'] != beforeEdit.id) {
          expect(current, original);
          continue;
        }
        final oldPayload = Map<String, dynamic>.from(
          jsonDecode(original['payload'] as String) as Map,
        );
        final newPayload = Map<String, dynamic>.from(
          jsonDecode(current['payload'] as String) as Map,
        );
        for (final key in ['title', 'updatedAt']) {
          oldPayload.remove(key);
          newPayload.remove(key);
        }
        expect(newPayload, oldPayload);
        expect(
          current['server_revision'] as int,
          greaterThan(original['server_revision'] as int),
        );
      }
      result['unchangedExpenseFactsAndOtherRecords'] = true;
      final latest = jsonDecode(await journal.readAsString()) as Map;
      latest['state'] = 'synced';
      latest['newRevision'] = afterEdit.revision;
      await journal.writeAsString(jsonEncode(latest), flush: true);
      result['complete'] = true;
      await save();
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
