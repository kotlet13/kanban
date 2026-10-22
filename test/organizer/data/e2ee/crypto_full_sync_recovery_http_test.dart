import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_structure.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:sodium/sodium.dart';

import '../collaboration_repository_test.dart' show MemorySessionStore;

// Entirely opt-in. Every response before an injected network outage is from
// the real local server. No verifier, receipt, projection, or publication stub.
class _DiskSecure implements AccountCryptoStore {
  _DiskSecure(this.file);
  final File file;
  Future<void> _tail = Future.value();
  Future<Map<String, dynamic>> _read() async => file.existsSync()
      ? Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map)
      : {};
  @override
  Future<String?> read(String key) async {
    await _tail;
    return (await _read())[key] as String?;
  }

  @override
  Future<void> write(String key, String value) {
    final next = _tail.then((_) async {
      final data = await _read();
      data[key] = value;
      await file.writeAsString(jsonEncode(data), flush: true);
    });
    _tail = next;
    return next;
  }
}

String? _code(Object? error) => switch (error) {
  CryptoAuthorityPending() => error.reason,
  CollaborationException() => error.code,
  FormatException() =>
    RegExp(r'^[a-z0-9_]+$').hasMatch(error.message)
        ? error.message
        : 'format_exception',
  StateError() =>
    RegExp(r'^[a-z0-9_]+$').hasMatch(error.message)
        ? error.message
        : 'state_error',
  null => null,
  _ => error.runtimeType.toString(),
};

List<Map<String, Object?>> _frames(StackTrace stack) {
  final output = <Map<String, Object?>>[];
  final regex = RegExp(
    r'((?:package:|dart:)[A-Za-z0-9_./-]+\.dart|(?:lib|test)/[A-Za-z0-9_./-]+\.dart)(?::|\s+)(\d+):(\d+)',
  );
  for (final line in stack.toString().split('\n')) {
    final match = regex.firstMatch(line);
    if (match != null) {
      output.add({
        'source': match[1],
        'line': int.parse(match[2]!),
        'column': int.parse(match[3]!),
      });
    }
  }
  return output.take(40).toList();
}

class _Lab {
  _Lab(this.root, this.fixture, this.ledger, {Directory? evidenceRoot})
    : evidenceRoot = evidenceRoot ?? root;
  final Directory root;
  final Directory evidenceRoot;
  final Map fixture;
  final Map<String, dynamic> ledger;
  final clients = <String, _Client>{};
  final calls = <Map<String, Object?>>[];
  int activeCalls = 0;
  final aliases = <String, String>{};
  String alias(String id) =>
      aliases.putIfAbsent(id, () => 'request_${aliases.length + 1}');
  Future<void> _saveTail = Future.value();
  Future<void> save() {
    final next = _saveTail.then((_) async {
      ledger['aliases'] = aliases;
      final tmp = File('${evidenceRoot.path}/ledger-private.tmp');
      await tmp.writeAsString(jsonEncode(ledger), flush: true);
      await tmp.rename('${evidenceRoot.path}/ledger-private.json');
    });
    _saveTail = next;
    return next;
  }

  Future<void> quota() async {
    // Durable timestamps span selected-phase processes; never reset server
    // quota state or change the request scheduling inside production code.
    final times = ledger.putIfAbsent('requestTimes', () => <dynamic>[]) as List;
    var now = DateTime.now().millisecondsSinceEpoch;
    times.removeWhere((t) => now - (t as int) >= 61000);
    if (times.length >= 320) {
      var remaining = 61010 - (now - (times.first as int));
      debugPrint(
        'FULLSYNC_EVENT ${jsonEncode({'stage': 'quota_pause', 'milliseconds': remaining})}',
      );
      while (remaining > 0) {
        final chunk = remaining > 30000 ? 30000 : remaining;
        await Future<void>.delayed(Duration(milliseconds: chunk));
        remaining -= chunk;
      }
      now = DateTime.now().millisecondsSinceEpoch;
      times.removeWhere((t) => now - (t as int) >= 61000);
    }
    times.add(now);
    await save();
  }

  Future<void> reserveQuota(int requiredSlots) async {
    check(activeCalls == 0, 'quota_reservation_during_active_http');
    final times = ledger.putIfAbsent('requestTimes', () => <dynamic>[]) as List;
    final now = DateTime.now().millisecondsSinceEpoch;
    times.removeWhere((t) => now - (t as int) >= 61000);
    if (times.length + requiredSlots <= 320) return;
    var remaining = 61010 - (now - (times.last as int));
    debugPrint(
      'FULLSYNC_EVENT ${jsonEncode({'stage': 'quota_reservation', 'milliseconds': remaining})}',
    );
    while (remaining > 0) {
      final chunk = remaining > 30000 ? 30000 : remaining;
      await Future<void>.delayed(Duration(milliseconds: chunk));
      remaining -= chunk;
    }
    // Natural expiry only; quota() prunes these timestamps before the next call.
  }

  Future<_Client> open(String actor) async {
    final old = clients[actor];
    if (old != null) return old;
    final client = await _Client.open(this, actor);
    clients[actor] = client;
    return client;
  }

  Future<void> restart(String actor) async {
    final old = clients.remove(actor);
    await old?.close();
    await open(actor);
  }

  Future<void> stage(String name, Future<void> Function() action) async {
    final phases =
        ledger.putIfAbsent('phases', () => <String, dynamic>{}) as Map;
    final phase = phases.putIfAbsent(name, () => <String, dynamic>{}) as Map;
    if (phase['passed'] == true) return;
    if (phase['elapsedMicroseconds'] != null) {
      final runs = phase.putIfAbsent('previousRuns', () => <dynamic>[]) as List;
      runs.add({
        for (final key in [
          'attempts',
          'startedAtUtc',
          'elapsedMicroseconds',
          'code',
          'errorType',
          'stack',
          'calls',
        ])
          if (phase.containsKey(key)) key: phase[key],
      });
      for (final key in [
        'elapsedMicroseconds',
        'code',
        'errorType',
        'stack',
        'calls',
      ]) {
        phase.remove(key);
      }
    }
    final attempt = (phase['attempts'] as int? ?? 0) + 1;
    if (attempt > 3) throw StateError('phase_attempts_exhausted');
    phase['attempts'] = attempt;
    phase['startedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    await save();
    final start = calls.length;
    final clock = Stopwatch()..start();
    debugPrint(
      'FULLSYNC_EVENT ${jsonEncode({'stage': name, 'outcome': 'entered', 'attempt': attempt})}',
    );
    try {
      await action();
      phase['passed'] = true;
    } catch (error, stack) {
      phase['code'] = _code(error);
      phase['errorType'] = error.runtimeType.toString();
      phase['stack'] = _frames(stack);
      rethrow;
    } finally {
      clock.stop();
      phase['elapsedMicroseconds'] = clock.elapsedMicroseconds;
      phase['calls'] = calls.skip(start).toList();
      await save();
      // Safe evidence is a whitelist; private ledger also retains exact IDs and
      // full original SQL rows, but never appears in stdout or repo artifacts.
      final safe = {
        'synthetic': true,
        'purpose': fixture['purpose'],
        'phases': {for (final entry in phases.entries) entry.key: entry.value},
      };
      await File(
        '${evidenceRoot.path}/result.json',
      ).writeAsString(jsonEncode(safe), flush: true);
      debugPrint(
        'FULLSYNC_EVENT ${jsonEncode({'stage': name, 'outcome': phase['passed'] == true ? 'passed' : 'failed', 'code': phase['code']})}',
      );
    }
  }

  Future<void> close() async {
    for (final client in clients.values) {
      await client.close();
    }
    clients.clear();
  }
}

class _Wire extends http.BaseClient {
  _Wire(this.client);
  final _Client client;
  final delegate = http.Client();
  bool armLostChoice = false;
  bool readOnly = false;
  bool correctionReadsOnly = false;
  String? controlDirectoryTarget;
  String? controlDirectoryAccount;
  bool offline = false;
  Future<void> Function(Map command)? beforeChoice;
  Future<void> Function(Map command)? beforeTask;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw http.ClientException('synthetic_network_outage');
    final body = jsonDecode((request as http.Request).body) as Map;
    final operation = body['op'] as String;
    check(client.lab.calls.length < 1500, 'phase_http_budget_exhausted');
    final params = body['params'] as Map;
    Map? command;
    if (params['commandBase64'] is String) {
      command = CryptoJson.decode(cryptoBase64(params['commandBase64'])) as Map;
    }
    if (correctionReadsOnly) {
      check(
        command == null &&
            const {
              'capabilities',
              'moderation.policyStatus',
              'crypto2.authority.snapshot',
              'crypto2.scopes.catalog',
              'crypto2.scope.headGet',
              'crypto2.scope.lifecycle.baseline',
              'crypto2.scope.lifecycle.list',
              'crypto2.account.scopeObservations',
              'crypto2.directory.read',
              'crypto2.inbox.sync',
              'crypto2.account.status',
              'crypto2.account.directory',
              'scopes.list',
            }.contains(operation),
        'correction_mutation_forbidden',
      );
    }
    if (readOnly) {
      check(
        command == null &&
            const {
              'crypto2.account.status',
              'crypto2.account.directory',
              'crypto2.directory.status',
              'crypto2.directory.read',
              'crypto2.scope.headGet',
              'crypto2.authority.snapshot',
              'crypto2.scopes.catalog',
              'crypto2.account.scopeObservations',
              'crypto2.scope.lifecycle.baseline',
              'crypto2.scope.lifecycle.list',
            }.contains(operation),
        'control_mutation_forbidden',
      );
    }
    final choice =
        operation == 'crypto2.records.batch' &&
        (command?['payload']['records'] as List).any(
          (p) =>
              (CryptoJson.decode(cryptoBase64(p['commandBase64']))
                  as Map)['type'] ==
              'financeAccountChoice',
        );
    final task =
        operation == 'crypto2.records.batch' &&
        (command?['payload']['records'] as List).any(
          (p) =>
              (CryptoJson.decode(cryptoBase64(p['commandBase64']))
                  as Map)['type'] ==
              'task',
        );
    final metric = <String, Object?>{
      'actor': client.actor,
      'operation': operation,
      'status': null,
      'requestBytes': request.contentLength,
      'responseBytes': 0,
    };
    if (operation == 'scopes.list' && params['accessChangesOnly'] == true) {
      metric['accessChangesOnly'] = true;
      metric['requestedScopeCount'] = (params['scopeIds'] as List).length;
    }
    if (command != null) {
      metric['requestAlias'] = client.lab.alias(command['requestId']);
      metric['requestHash'] = await cryptoSha256(
        cryptoBase64(params['commandBase64']),
      );
      metric['proofEnvelopeSha256'] = await cryptoSha256(
        CryptoJson.encode(params),
      );
      metric['choice'] = choice;
      metric['task'] = task;
    }
    if (readOnly && operation == 'crypto2.directory.read') {
      metric['controlTargetDirectory'] =
          params['directoryHeadHash'] == controlDirectoryTarget &&
          params['accountId'] == controlDirectoryAccount;
    }
    if (operation == 'crypto2.receipt.get') {
      metric['requestAlias'] = client.lab.alias(params['requestId']);
    }
    client.lab.calls.add(metric);
    if (choice && beforeChoice != null) {
      final callback = beforeChoice!;
      beforeChoice = null;
      await callback(command!);
    }
    if (task && beforeTask != null) {
      final callback = beforeTask!;
      beforeTask = null;
      await callback(command!);
    }
    client.lab.activeCalls++;
    try {
      final response = await delegate.send(request);
      final bytes = await response.stream.toBytes();
      metric['status'] = response.statusCode;
      metric['responseBytes'] = bytes.length;
      if (operation == 'crypto2.receipt.get' ||
          operation == 'crypto2.records.batch') {
        final envelope = jsonDecode(utf8.decode(bytes)) as Map;
        final data = envelope['data'];
        if (data is Map && operation == 'crypto2.receipt.get') {
          metric['receiptOutcome'] = data['outcome'] == 'unknown'
              ? 'unknown'
              : data['status'] == 200
              ? 'terminal_200'
              : data['status'] == 409
              ? 'terminal_409'
              : 'other';
          if (params['requestId'] == client.lab.ledger['beforeSendRequestId'] &&
              client.lab.ledger['beforeSendResumeStarted'] == true &&
              data['outcome'] == 'unknown') {
            check(
              response.statusCode == 200 &&
                  params['requestHash'] ==
                      client.lab.ledger['beforeSendRequestHash'],
              'before_send_unknown_receipt_binding',
            );
            client.lab.ledger['beforeSendUnknownReceiptCount'] =
                (client.lab.ledger['beforeSendUnknownReceiptCount'] as int? ??
                    0) +
                1;
            await client.lab.save();
          }
        }
        if (data is Map && operation == 'crypto2.records.batch') {
          metric['appliedAck'] =
              response.statusCode == 200 && data['status'] == 'applied';
          if (command?['requestId'] ==
                  client.lab.ledger['beforeSendRequestId'] &&
              metric['appliedAck'] == true) {
            client.lab.ledger['beforeSendExactBatchSendCount'] =
                (client.lab.ledger['beforeSendExactBatchSendCount'] as int? ??
                    0) +
                1;
            client.lab.ledger['beforeSendAppliedAck'] = true;
            client.lab.ledger['beforeSendAckRequestHash'] =
                metric['requestHash'];
            await client.lab.save();
          }
        }
      }
      if (choice && armLostChoice && response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(bytes)) as Map;
        final data = decoded['data'];
        if (decoded['v'] != 1 || data is! Map || data['status'] != 'applied') {
          throw StateError('lost_fault_requires_genuine_applied_ack');
        }
        armLostChoice = false;
        offline = true;
        client.lab.ledger['lostRequestId'] = command!['requestId'];
        client.lab.ledger['lostRequestHash'] = metric['requestHash'];
        client.lab.ledger['lostActor'] = client.actor;
        client.lab.ledger['lostHttpResponseSha256'] = await cryptoSha256(bytes);
        metric['fault'] = 'drop_after_real_applied_ack';
        await client.lab.save();
        throw http.ClientException('synthetic_lost_applied_response');
      }
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
    } finally {
      client.lab.activeCalls--;
    }
  }

  @override
  void close() => delegate.close();
}

class _Transport extends HttpCollaborationTransport {
  _Transport(this.lab, this.wire) : super(client: wire);
  final _Lab lab;
  final _Wire wire;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    await lab.quota();
    try {
      return await super.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
    } catch (error, stack) {
      lab.calls.add({
        'actor': wire.client.actor,
        'operation': operation,
        'origin': 'transport_error',
        'code': _code(error),
        'errorType': error.runtimeType.toString(),
        'stack': _frames(stack),
      });
      rethrow;
    }
  }
}

class _Router extends CryptoBusinessRouter {
  _Router(this.client)
    : super(database: client.db, accountFor: (_) async => client.account);
  final _Client client;
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    try {
      return await super.dispatch(
        session: session,
        operation: operation,
        params: params,
        protectedScopeIds: protectedScopeIds,
      );
    } catch (error, stack) {
      client.lab.calls.add({
        'actor': client.actor,
        'operation': operation,
        'origin': 'business_dispatch_error',
        'code': _code(error),
        'errorType': error.runtimeType.toString(),
        'stack': _frames(stack),
      });
      rethrow;
    }
  }
}

class _TracingAccess extends SessionCryptoAccess {
  _TracingAccess({required super.account, required this.lab});
  final _Lab lab;
  @override
  Future<VerifiedAccountDirectory> directoryAt({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    bool online = false,
    bool allowUnverifiedContact = false,
  }) async {
    try {
      return await super.directoryAt(
        scopeId: scopeId,
        scopeHeadHash: scopeHeadHash,
        accountId: accountId,
        directoryHeadHash: directoryHeadHash,
        online: online,
        allowUnverifiedContact: allowUnverifiedContact,
      );
    } catch (error, stack) {
      final rows = await account.store.database.rows(
        'SELECT 1 FROM crypto_directory_entries WHERE partition=? AND account_id=? AND head_hash=? LIMIT 1',
        [account.store.partition, accountId, directoryHeadHash],
      );
      lab.calls.add({
        'actor': 'member',
        'operation': 'diagnostic_projection_directoryAt',
        'origin': 'original_projection_error',
        'code': _code(error),
        'errorType': error.runtimeType.toString(),
        'online': online,
        'targetPrefixPresent': rows.isNotEmpty,
        'stack': _frames(stack),
      });
      rethrow;
    }
  }
}

class _Client {
  _Client(this.lab, this.actor);
  final _Lab lab;
  final String actor;
  late DeviceSession session;
  late CollaborationDatabase db;
  late _Wire wire;
  late _Transport transport;
  late AccountCryptoV2Workflow account;
  late CollaborationRepository repo;
  late CryptoBusinessSession runtime;
  late SessionCryptoAccess access;
  String get partition => session.profile.partition;
  CryptoFinanceAccountChoices get choices =>
      CryptoFinanceAccountChoices(runtime);
  static Future<_Client> open(_Lab lab, String actor) async {
    final self = _Client(lab, actor);
    final data = lab.fixture['accounts'][actor]['session'] as Map;
    final user = data['user'] as Map, device = data['device'] as Map;
    self.session = DeviceSession(
      AccountSession(
        serverUrl: lab.fixture['serverUrl'],
        serverId: data['serverId'],
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
      data['token'],
    );
    final dir = Directory(lab.fixture['clientStateDirs'][actor] as String);
    check(
      dir.parent.absolute.path == lab.root.absolute.path,
      'private_client_dir_required',
    );
    await dir.create(recursive: true);
    self.db = CollaborationDatabase(
      NativeDatabase(File('${dir.path}/client.sqlite')),
    );
    self.wire = _Wire(self);
    self.transport = _Transport(lab, self.wire);
    final codec = CryptoCodec(await SodiumInit.init());
    self.account = AccountCryptoV2Workflow(
      AccountDirectoryRepository(
        reducer: AccountDirectoryV2(codec),
        session: self.session,
        transport: self.transport,
        store: CryptoIdentityStore(
          self.db,
          _DiskSecure(File('${dir.path}/secure.json')),
          self.partition,
        ),
        isCurrent: () => true,
      ),
    );
    self.access = SessionCryptoAccess(account: self.account);
    self.runtime = CryptoBusinessSession(self.account, self.access, self.db);
    CryptoBusinessRouter.configurePayloads(self.runtime);
    self.repo = CollaborationRepository(
      self.db,
      self.transport,
      MemorySessionStore()..value = self.session,
      ownsDatabase: false,
      cryptoRouter: _Router(self),
    );
    await self.repo.initialize();
    return self;
  }

  Future<void> close() async {
    await repo.close();
    await db.close();
  }

  Future<List<Map<String, dynamic>>> signed() => db.rows(
    'SELECT request_id,operation,signed_body,request_hash FROM crypto_outbox WHERE partition=? ORDER BY sequence',
    [partition],
  );
  Future<List<Map<String, dynamic>>> finance() => db.rows(
    'SELECT scope_id,id,type,server_revision,payload FROM finance_records WHERE partition=? ORDER BY scope_id,id',
    [partition],
  );
  Future<Map<String, dynamic>> manifest(String child) async {
    final id = await choices.manifestId(child);
    final row = await runtime.record(
      child,
      'finance',
      id,
      type: 'financeAccountChoice',
    );
    check(row != null, 'physical_choice_manifest_missing');
    final raw = jsonDecode(row!['raw_payload'] as String) as Map;
    final offer =
        CryptoJson.decode(
              cryptoBase64(raw['offerAuthorization']['commandBase64']),
            )
            as Map;
    return {
      'revision': row['crypto_revision'],
      'recordProofHash': row['record_proof_hash'],
      'targetHeadHash': offer['targetHeadHash'],
    };
  }

  Future<void> assertBaseline() async {
    final now = await finance();
    check(
      now.length == (lab.ledger['baselineFinance'] as List).length,
      'finance_record_count_changed',
    );
    for (final row in lab.ledger['baselineFinance'] as List) {
      check(
        now.any((current) => jsonEncode(current) == jsonEncode(row)),
        'original_finance_record_changed',
      );
    }
  }

  Future<void> sync({bool success = true}) async {
    final previous = repo.lastSyncCompletion?.sequence ?? 0;
    await repo.syncNow(manual: true);
    final completion = repo.lastSyncCompletion;
    check(
      completion != null && completion.sequence > previous,
      'fresh_sync_completion',
    );
    check(completion!.identity == repo.backgroundSyncIdentity, 'sync_identity');
    if (success) {
      check(completion.error == null, _code(completion.error) ?? 'sync_error');
      check(
        repo.state.lastError == null,
        repo.state.lastError?.code ?? 'last_error',
      );
      check(!completion.work.unresolved, 'unresolved_sync_work');
    }
  }

  Future<Map<String, Object?>> health(String parent, String child) async {
    await repo.refreshLocal();
    final data = repo.state.dataForScope(parent);
    final totals = summarizeSharedFinance(
      accounts: data.financeAccounts,
      entries: data.financeEntries,
      transfers: data.financeTransfers,
    )['EUR'];
    final rows = await db.rows('SELECT value FROM local_meta WHERE name=?', [
      'finance_account_choices:$partition:$child',
    ]);
    return {
      'balanceMinor': totals?.balanceMinor.toString(),
      'expenseMinor': totals?.expenseMinor.toString(),
      'accounts': data.financeAccounts.length,
      'entries': data.financeEntries.length,
      'choices': rows.isEmpty
          ? null
          : (jsonDecode(rows.single['value'] as String)['accounts'] as List)
                .length,
      'pending': repo.state.pendingCount,
      'blocked': repo.state.blockedCount,
      'conflicts': repo.state.conflicts.length,
      'unresolved': (await repo.syncWork()).unresolved,
      'lastError': repo.state.lastError?.code,
    };
  }
}

void check(bool condition, String code) {
  if (!condition) throw StateError(code);
}

/// New explicit 22 October correction scope; old phase ledgers are read-only.
Future<void> runRetainedTaskConflictCorrection(
  String fixturePath,
  String correctionRoot,
) async {
  final fixtureFile = File(fixturePath);
  final fixture = jsonDecode(await fixtureFile.readAsString()) as Map;
  check(
    fixture['synthetic'] == true &&
        fixture['serverUrl'] == 'http://127.0.0.1:59777',
    'correction_fixture_target',
  );
  final legacyFile = File('${fixtureFile.parent.path}/ledger-private.json');
  final legacyBytes = await legacyFile.readAsBytes();
  final legacyHash = await cryptoSha256(legacyBytes);
  final old = jsonDecode(utf8.decode(legacyBytes)) as Map;
  final output = Directory(correctionRoot);
  check(
    output.parent.path == fixtureFile.parent.path &&
        output.path.endsWith('/corrections-20261022'),
    'correction_private_root',
  );
  await output.create(recursive: true);
  final result = File('${output.path}/ledger-private.json');
  final ledger = result.existsSync()
      ? Map<String, dynamic>.from(
          jsonDecode(await result.readAsString()) as Map,
        )
      : <String, dynamic>{
          'explicitScope': '2026-10-22-H4-H7-corrections',
          'legacyLedgerSha256': legacyHash,
          'parent': old['parent'],
          'child': old['child'],
          'baselineFinance': old['baselineFinance'],
        };
  check(ledger['legacyLedgerSha256'] == legacyHash, 'legacy_evidence_changed');
  final lab = _Lab(fixtureFile.parent, fixture, ledger, evidenceRoot: output);
  try {
    await lab.stage('H4_task_conflict_correction', () async {
      final b = await lab.open('member');
      b.wire.correctionReadsOnly = true;
      final h4 = old['h4'] as Map;
      final task = h4['taskId'] as String;
      Future<Map<String, dynamic>> appRow() async => (await b.db.rows(
        'SELECT * FROM outbox WHERE partition=? AND op_id=?',
        [b.partition, h4['memberOriginalQueue']['op_id']],
      )).single;
      Future<List<Map<String, dynamic>>> journals() => b.db.rows(
        'SELECT * FROM crypto_outbox WHERE partition=? ORDER BY sequence',
        [b.partition],
      );
      Future<List<Map<String, dynamic>>> claims() => b.db.rows(
        'SELECT * FROM crypto_outbox_records WHERE partition=? ORDER BY scope_id,domain,record_id,expected_revision',
        [b.partition],
      );
      Future<Map<String, dynamic>> draft() async => (await b.db.rows(
        'SELECT * FROM records WHERE partition=? AND scope_id=? AND id=?',
        [b.partition, old['child'], task],
      )).single;
      Future<List<Map<String, dynamic>>> missing() => b.db.rows(
        "SELECT name,value FROM local_meta WHERE name LIKE ? ORDER BY name",
        ['scope_reconciliation:${b.partition}:%'],
      );
      final state =
          ledger.putIfAbsent('h4Correction', () => <String, dynamic>{}) as Map;
      if (state['before'] == null) {
        final original = await appRow();
        check(
          original['state'] == 'pending' &&
              original['request'] == h4['memberOriginalQueue']['request'],
          'correction_original_pending_required',
        );
        state['before'] = {
          'app': original,
          'journals': await journals(),
          'claims': await claims(),
          'draft': await draft(),
          'missing': await missing(),
        };
        await lab.save();
      }
      final before = state['before'] as Map;
      if (state['syncCompleted'] != true) {
        check(
          state['syncStarted'] != true,
          'correction_ambiguous_sync_preserve',
        );
        state['syncStarted'] = true;
        await lab.save();
        final start = lab.calls.length;
        await b.sync(success: false);
        final completion = b.repo.lastSyncCompletion!;
        state['syncCompleted'] = true;
        state['completionError'] = _code(completion.error);
        state['workUnresolved'] = completion.work.unresolved;
        state['syncCalls'] = lab.calls.skip(start).toList();
        await lab.save();
      }
      final after = await appRow();
      check(after['state'] == 'conflict', 'correction_task_not_surfaced');
      for (final key in (before['app'] as Map).keys) {
        if (key != 'state') {
          check(
            after[key] == before['app'][key],
            'correction_original_app_work_changed',
          );
        }
      }
      final conflict = (await b.db.rows(
        'SELECT * FROM conflicts WHERE partition=? AND id=?',
        [b.partition, after['op_id']],
      )).single;
      check(
        conflict['record_id'] == task &&
            conflict['scope_id'] == old['child'] &&
            conflict['type'] == 'task' &&
            conflict['reason'] == 'conflict' &&
            conflict['remote'] == null,
        'correction_conflict_identity_or_remote',
      );
      check(
        jsonEncode(await journals()) == jsonEncode(before['journals']) &&
            jsonEncode(await claims()) == jsonEncode(before['claims']),
        'correction_signed_work_changed',
      );
      check(
        jsonEncode(await draft()) == jsonEncode(before['draft']),
        'correction_losing_draft_changed',
      );
      check(
        jsonEncode(await missing()) == jsonEncode(before['missing']),
        'correction_missing_marker_changed',
      );
      check(
        !(state['syncCalls'] as List).cast<Map>().any(
          (call) => call['operation'] == 'crypto2.records.batch',
        ),
        'correction_sent_business_batch',
      );
      await b.assertBaseline();
      (ledger['phases'] as Map)['H4_task_conflict_correction'].addAll({
        'retainedOriginalTaskConflictSurfaced': true,
        'remoteUnverifiedDataUsed': false,
        'originalDraftAndSignedWorkPreserved': true,
        'noBusinessBatch': true,
        'missingScopeMarkersPreserved': true,
        'completionError': state['completionError'],
        'workUnresolved': state['workUnresolved'],
        'globalCleanSyncClaimed': false,
      });
    });
  } finally {
    await lab.close();
    check(
      await cryptoSha256(await legacyFile.readAsBytes()) == legacyHash,
      'legacy_evidence_changed',
    );
  }
}

Future<void> runRetainedRevokedAccessCorrection(
  String fixturePath,
  String correctionRoot,
) async {
  final file = File(fixturePath);
  final fixture = jsonDecode(await file.readAsString()) as Map;
  check(
    fixture['synthetic'] == true &&
        fixture['serverUrl'] == 'http://127.0.0.1:59777',
    'correction_fixture_target',
  );
  final legacy = File('${file.parent.path}/ledger-private.json');
  final oldBytes = await legacy.readAsBytes();
  final oldHash = await cryptoSha256(oldBytes);
  final old = jsonDecode(utf8.decode(oldBytes)) as Map;
  final output = Directory(correctionRoot);
  check(
    output.parent.path == file.parent.path &&
        output.path.endsWith('/corrections-20261022'),
    'correction_private_root',
  );
  final ledger = Map<String, dynamic>.from(
    jsonDecode(await File('${output.path}/ledger-private.json').readAsString())
        as Map,
  );
  check(
    ledger['legacyLedgerSha256'] == oldHash &&
        ledger['phases']['H4_task_conflict_correction']['passed'] == true,
    'correction_prior_evidence_required',
  );
  final lab = _Lab(file.parent, fixture, ledger, evidenceRoot: output);
  try {
    await lab.stage('H7_revoked_access_correction', () async {
      final b = await lab.open('member');
      b.wire.correctionReadsOnly = true;
      final state =
          ledger.putIfAbsent('h7Correction', () => <String, dynamic>{}) as Map;
      Future<String> tableHash(String table) async => cryptoSha256(
        utf8.encode(
          jsonEncode(
            await b.db.rows(
              'SELECT * FROM $table WHERE partition=? ORDER BY rowid',
              [b.partition],
            ),
          ),
        ),
      );
      Future<Map<String, dynamic>> taskDraft() async => (await b.db.rows(
        'SELECT * FROM records WHERE partition=? AND scope_id=? AND id=?',
        [b.partition, old['child'], old['h4']['taskId']],
      )).single;
      Future<Map<String, dynamic>> conflict() async => (await b.db.rows(
        'SELECT * FROM conflicts WHERE partition=? AND id=?',
        [b.partition, old['h4']['memberOriginalQueue']['op_id']],
      )).single;
      Future<List<Map<String, dynamic>>> taskQueue() => b.db.rows(
        'SELECT * FROM outbox WHERE partition=? AND op_id=?',
        [b.partition, old['h4']['memberOriginalQueue']['op_id']],
      );
      const immutableTables = [
        'crypto_outbox',
        'crypto_outbox_records',
        'crypto_business_records',
        'crypto_received',
        'crypto_domain_checkpoints',
      ];
      if (state['before'] == null) {
        final hashes = <String, String>{};
        for (final table in immutableTables) {
          hashes[table] = await tableHash(table);
        }
        state['before'] = {
          'hashes': hashes,
          'draft': await taskDraft(),
          'conflict': await conflict(),
          'queue': await taskQueue(),
        };
        await lab.save();
      }
      if (state['syncCompleted'] != true) {
        check(
          state['syncStarted'] != true,
          'correction_ambiguous_revoked_sync_preserve',
        );
        state['syncStarted'] = true;
        await lab.save();
        final start = lab.calls.length;
        await b.sync(success: false);
        state['syncCompleted'] = true;
        state['completionError'] = _code(b.repo.lastSyncCompletion!.error);
        state['workUnresolved'] = b.repo.lastSyncCompletion!.work.unresolved;
        state['syncCalls'] = lab.calls.skip(start).toList();
        await lab.save();
      }
      final before = state['before'] as Map;
      for (final table in immutableTables) {
        check(
          await tableHash(table) == before['hashes'][table],
          'correction_crypto_evidence_changed',
        );
      }
      check(
        jsonEncode(await taskDraft()) == jsonEncode(before['draft']) &&
            jsonEncode(await conflict()) == jsonEncode(before['conflict']) &&
            jsonEncode(await taskQueue()) == jsonEncode(before['queue']),
        'correction_task_conflict_or_draft_changed',
      );
      for (final scopeId in [old['parent'], old['child']]) {
        final row = (await b.db.rows(
          'SELECT data,blocked,finance_policy FROM scopes WHERE partition=? AND id=?',
          [b.partition, scopeId],
        )).single;
        check(
          jsonDecode(row['data'] as String)['revoked'] == true &&
              row['blocked'] == 1,
          'correction_scope_not_revoked',
        );
        check(
          jsonDecode(row['finance_policy'] as String)['enabled'] == false,
          'correction_finance_policy_still_enabled',
        );
        check(
          (await b.db.rows('SELECT 1 FROM local_meta WHERE name IN (?,?)', [
            'scope_reconciliation:${b.partition}:$scopeId',
            'finance_account_choices:${b.partition}:$scopeId',
          ])).isEmpty,
          'correction_stale_selector_or_missing_marker',
        );
      }
      final calls = (state['syncCalls'] as List).cast<Map>();
      check(
        !calls.any(
          (call) =>
              call['operation'] == 'crypto2.records.batch' ||
              call['operation'] == 'crypto2.receipt.get',
        ),
        'correction_replayed_old_work',
      );
      final notices = calls
          .where((call) => call['accessChangesOnly'] == true)
          .toList();
      check(
        notices.length == 1 &&
            notices.single['status'] == 200 &&
            notices.single['requestedScopeCount'] == 2,
        'correction_one_batched_notice_required',
      );
      final a = await lab.open('owner');
      await a.assertBaseline();
      (ledger['phases'] as Map)['H7_revoked_access_correction'].addAll({
        'explicitBatchedDenialNotice': true,
        'bothCachedScopesRevoked': true,
        'staleSelectorAndMissingMarkersRemoved': true,
        'originalSignedWorkAndClaimsPreserved': true,
        'taskConflictAndDraftPreserved': true,
        'noOldBatchOrReceiptReplay': true,
        'ownerFinanceBaselinePreserved': true,
        'completionError': state['completionError'],
        'workUnresolved': state['workUnresolved'],
        'globalCleanSyncClaimed': false,
      });
    });
  } finally {
    await lab.close();
    check(
      await cryptoSha256(await legacy.readAsBytes()) == oldHash,
      'legacy_evidence_changed',
    );
  }
}

void main() {
  final path = Platform.environment['JIVIE_FULLSYNC_HTTP_FIXTURE'];
  final selected = Platform.environment['JIVIE_FULLSYNC_PHASE'];
  test(
    'bounded real server two client full sync recovery',
    () async {
      check(selected != null, 'explicit_single_phase_required');
      final fixtureFile = File(path!);
      final fixture = jsonDecode(await fixtureFile.readAsString()) as Map;
      final url = Uri.parse(fixture['serverUrl']);
      check(
        fixture['synthetic'] == true &&
            fixture['purpose'] == 'local-fullsync-recovery-20261021' &&
            url.host == '127.0.0.1' &&
            url.port == 59777 &&
            fixture['serverId'] ==
                fixture['accounts']['owner']['session']['serverId'] &&
            fixture['serverId'] ==
                fixture['accounts']['member']['session']['serverId'],
        'isolated_fixture_required',
      );
      final ledgerFile = File('${fixtureFile.parent.path}/ledger-private.json');
      final ledger = ledgerFile.existsSync()
          ? Map<String, dynamic>.from(
              jsonDecode(await ledgerFile.readAsString()) as Map,
            )
          : <String, dynamic>{};
      final lab = _Lab(fixtureFile.parent, fixture, ledger);
      if (ledger['aliases'] is Map) {
        lab.aliases.addAll((ledger['aliases'] as Map).cast<String, String>());
      }
      final codec = CryptoCodec(await SodiumInit.init());
      Future<void> phase(String name, Future<void> Function() body) async {
        if (selected == null || selected == name) await lab.stage(name, body);
      }

      try {
        await phase('bootstrap_crypto', () async {
          for (final actor in ['owner', 'member']) {
            final client = await lab.open(actor);
            final existing = await client.db.rows(
              'SELECT phase FROM crypto_identity_secrets WHERE partition=?',
              [client.partition],
            );
            if (existing.isEmpty) {
              final file = await client.account.prepareRecoveryFile();
              await File(
                '${fixture['clientStateDirs'][actor]}/recovery.private',
              ).writeAsBytes(file, flush: true);
              try {
                await client.account.verifyAndInitialize(file);
              } finally {
                file.fillRange(0, file.length, 0);
              }
            } else if (existing.single['phase'] == 'prepared') {
              final file = await File(
                '${fixture['clientStateDirs'][actor]}/recovery.private',
              ).readAsBytes();
              try {
                await client.account.verifyAndInitialize(file);
              } finally {
                file.fillRange(0, file.length, 0);
              }
            } else if (await client.account.localPhase() == 'pending') {
              await client.account.resume();
            }
            check(
              (await client.account.status())['initialized'] == true,
              'account_not_initialized',
            );
            check(
              await client.account.localPhase() == 'ready',
              'account_not_ready',
            );
            final directory = await client.account.directory.requireFresh();
            check(
              directory.accountId == client.session.profile.accountId &&
                  directory.serverId == fixture['serverId'],
              'initialized_directory_identity',
            );
            directory.activeDevice(client.session.profile.deviceId);
          }
        });
        await phase('bootstrap_scopes_finance', () async {
          final a = await lab.open('owner');
          if (ledger['negotiated'] != true) {
            await a.sync();
            ledger['negotiated'] = true;
            await lab.save();
          }
          for (final name in ['parent', 'child']) {
            ledger[name] ??= codec.randomId();
            ledger['${name}Request'] ??= codec.randomId();
            await lab.save();
            if (ledger['${name}Created'] != true) {
              await a.repo.createScope(
                'Local fullsync $name',
                kind: name == 'parent'
                    ? SharedScopeKind.organization
                    : SharedScopeKind.project,
                parentScopeId: name == 'child' ? ledger['parent'] : null,
                id: ledger[name],
                requestId: ledger['${name}Request'],
              );
              ledger['${name}Created'] = true;
              await lab.save();
            }
          }
          final parent = ledger['parent'] as String;
          await a.repo.refreshFinancePolicy(parent);
          if (ledger['accountId'] == null) {
            check(
              ledger['accountCreationIntent'] != true,
              'ambiguous_account_creation_preserve_state',
            );
            ledger['accountCreationIntent'] = true;
            await lab.save();
            ledger['accountId'] = await a.repo.createFinanceAccount(
              scopeId: parent,
              name: 'Local synthetic ledger',
              currency: 'EUR',
              openingBalanceMinor: 4567,
            );
            await lab.save();
          }
          await a.sync();
          if (ledger['entryId'] == null) {
            check(
              ledger['entryCreationIntent'] != true,
              'ambiguous_entry_creation_preserve_state',
            );
            ledger['entryCreationIntent'] = true;
            await lab.save();
            ledger['entryId'] = await a.repo.createFinanceEntry(
              scopeId: parent,
              accountId: ledger['accountId'],
              kind: FinanceEntryKind.expense,
              amountMinor: 1234,
              currency: 'EUR',
              title: 'Local synthetic expense',
              occurredAt: DateTime.utc(2026, 10, 21),
            );
            await lab.save();
          }
          await a.sync();
          ledger['baselineFinance'] = await a.finance();
          ledger['baselineSigned'] = await a.signed();
          ledger['baselineHead'] = (await a.access.currentHead(
            ledger['child'],
            online: true,
          )).headHash;
          ledger['phases']['bootstrap_scopes_finance']['health'] = await a
              .health(parent, ledger['child']);
        });
        await phase('bootstrap_share_admission', () async {
          final a = await lab.open('owner'), b = await lab.open('member');
          ledger['baselineManifest'] ??= await a.manifest(ledger['child']);
          await lab.save();
          final sender = InviteCryptoRepository(a.access),
              receiver = InviteCryptoRepository(b.access);
          ledger['inviteRequest'] ??= codec.randomId();
          await lab.save();
          ledger['invitation'] ??= await sender.dispatch(
            'invitations3.create',
            {
              'scopeId': ledger['parent'],
              'recipient':
                  fixture['accounts']['member']['session']['user']['username'],
              'role': 'member',
              'language': 'en',
              'requestId': ledger['inviteRequest'],
            },
          );
          await lab.save();
          final invitation = ledger['invitation'] as Map;
          final id = invitation['invitation']['id'] as String;
          if (ledger['invitationAccepted'] != true) {
            final preview = await receiver.inspect(
              token: invitation['localToken'],
            );
            await receiver.accept(preview, actionId: id);
            ledger['invitationAccepted'] = true;
            await lab.save();
          }
          if (ledger['invitationAdmitted'] != true) {
            await sender.admit(
              await sender.acceptedRecipient(ledger['parent'], id),
              await ScopeCryptoManager(
                a.access,
              ).reviewRotation(ledger['parent']),
            );
            ledger['invitationAdmitted'] = true;
            await lab.save();
          }
          if (ledger['invitationResumed'] != true) {
            await receiver.resumeAccepted(id);
            ledger['invitationResumed'] = true;
            await lab.save();
          }
          ledger['admittedHead'] = (await a.access.currentHead(
            ledger['child'],
            online: true,
          )).headHash;
          check(
            ledger['admittedHead'] != ledger['baselineHead'],
            'admission_must_advance_child_head',
          );
        });
        await phase('H1_stale_fullsync', () async {
          final a = await lab.open('owner'), b = await lab.open('member');
          await a.sync();
          await b.sync();
          final health = await a.health(ledger['parent'], ledger['child']);
          check(
            health['balanceMinor'] == '3333' &&
                health['expenseMinor'] == '1234',
            'finance_invariants',
          );
          check(
            health['accounts'] == 1 && health['entries'] == 1,
            'finance_count_invariants',
          );
          await a.assertBaseline();
          final verifiedChoice = await a.choices.read(ledger['child']);
          check(
            (verifiedChoice['accounts'] as List).length == 1,
            'verified_choice_count',
          );
          final manifest = await a.manifest(ledger['child']);
          final currentHead = await a.access.currentHead(
            ledger['child'],
            online: true,
          );
          check(
            manifest['targetHeadHash'] == currentHead.headHash,
            'choice_manifest_target_head_stale',
          );
          check(
            (manifest['revision'] as int) >
                ledger['baselineManifest']['revision'],
            'choice_manifest_not_republished',
          );
          ledger['phases']['H1_stale_fullsync']['manifest'] = manifest;
          check(health['choices'] == 1, 'stale_choice_republished');
          for (final original in ledger['baselineSigned'] as List) {
            check(
              (await a.signed()).any(
                (r) => jsonEncode(r) == jsonEncode(original),
              ),
              'original_signed_request_changed',
            );
          }
          ledger['phases']['H1_stale_fullsync']['health'] = health;
          ledger['phases']['H1_stale_fullsync']['exactHelperCoverage'] =
              'unverified_fullsync_may_pull_advanced_base_first';
        });
        await phase('H2_lost_applied_response', () async {
          final a = await lab.open('owner');
          if (ledger['lostRequestId'] == null) {
            final manager = ScopeCryptoManager(a.access);
            if (ledger['lostRotationHead'] == null) {
              final next = await manager.confirmRotation(
                await manager.reviewRotation(ledger['child']),
                acceptedCandidateHistory: true,
              );
              ledger['lostRotationHead'] = next.headHash;
              await lab.save();
            }
            a.wire.armLostChoice = true;
            await a.sync(success: false);
          }
          check(ledger['lostRequestId'] != null, 'choice_fault_not_reached');
          final row = (await a.db.rows(
            'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox WHERE partition=? AND request_id=?',
            [a.partition, ledger['lostRequestId']],
          )).single;
          check(row['state'] == 'pending', 'lost_request_must_remain_pending');
          check(
            row['request_hash'] == ledger['lostRequestHash'],
            'lost_request_hash_binding',
          );
          ledger['lostOriginalRow'] = row;
          ledger['lostOriginalClaims'] = await a.db.rows(
            'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=?',
            [a.partition, ledger['lostRequestId']],
          );
          check(
            (ledger['lostOriginalClaims'] as List).isNotEmpty,
            'lost_revision_claim_missing',
          );
          ledger['phases']['H2_lost_applied_response']['requestAlias'] = lab
              .alias(ledger['lostRequestId']);
          ledger['phases']['H2_lost_applied_response']['pendingExactRequest'] =
              true;
          await lab.save();
        });
        await phase('H2_restart_receipt_resume', () async {
          await lab.restart('owner');
          final a = await lab.open('owner');
          final before = (await a.db.rows(
            'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox WHERE partition=? AND request_id=?',
            [a.partition, ledger['lostRequestId']],
          )).single;
          check(
            jsonEncode(before) == jsonEncode(ledger['lostOriginalRow']),
            'restart_changed_exact_pending_request',
          );
          final callStart = lab.calls.length;
          await a.sync();
          final resumedCalls = lab.calls
              .skip(callStart)
              .where(
                (c) => c['requestAlias'] == lab.alias(ledger['lostRequestId']),
              )
              .toList();
          check(
            resumedCalls.any(
              (c) =>
                  c['operation'] == 'crypto2.receipt.get' && c['status'] == 200,
            ),
            'resume_requires_real_receipt_read',
          );
          check(
            !resumedCalls.any((c) => c['operation'] == 'crypto2.records.batch'),
            'applied_request_must_not_resend',
          );
          await a.assertBaseline();
          final after = (await a.db.rows(
            'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox WHERE partition=? AND request_id=?',
            [a.partition, ledger['lostRequestId']],
          )).single;
          for (final key in ['request_id', 'request_hash', 'signed_body']) {
            check(after[key] == before[key], 'resumed_request_bytes_changed');
          }
          check(after['state'] == 'applied', 'real_receipt_not_applied');
          final receipt = jsonDecode(after['response'] as String) as Map;
          check(
            receipt['status'] == 200 &&
                receipt['response']['status'] == 'applied',
            'real_receipt_invalid',
          );
          final claims = await a.db.rows(
            'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=?',
            [a.partition, ledger['lostRequestId']],
          );
          check(claims.isNotEmpty, 'resumed_revision_claim_missing');
          check(
            jsonEncode(claims) == jsonEncode(ledger['lostOriginalClaims']),
            'resumed_claim_changed',
          );
          ledger['phases']['H2_restart_receipt_resume']['health'] = await a
              .health(ledger['parent'], ledger['child']);
          ledger['phases']['H2_restart_receipt_resume']['exactRequestAndClaimsPreserved'] =
              true;
        });
        await phase('control_choice_directory_fetch', () async {
          final clone =
              jsonDecode(
                    await File(
                      '${lab.root.path}/control-clone.json',
                    ).readAsString(),
                  )
                  as Map;
          Future<void> originalUnchanged() async {
            for (final item in (clone['originalBefore'] as Map).entries) {
              check(
                await cryptoSha256(
                      await File(item.key as String).readAsBytes(),
                    ) ==
                    item.value,
                'control_original_client_changed',
              );
            }
          }

          await originalUnchanged();
          final clonedFixture = Map<String, dynamic>.from(fixture);
          clonedFixture['clientStateDirs'] = {
            ...(fixture['clientStateDirs'] as Map),
            'member': clone['destination'],
          };
          final controlLab = _Lab(lab.root, clonedFixture, ledger);
          controlLab.aliases.addAll(lab.aliases);
          final client = await controlLab.open('member');
          client.wire.readOnly = true;
          final rows = await client.db.rows(
            "SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain='finance' AND verdict='received' AND json_extract(wire,'\$.type')='financeAccountChoice' ORDER BY revision DESC LIMIT 1",
            [client.partition, ledger['child']],
          );
          check(rows.length == 1, 'control_exact_pending_wire_required');
          final wire = Map<String, dynamic>.from(
            jsonDecode(rows.single['wire'] as String) as Map,
          );
          final before = await client.db.rows(
            'SELECT crypto_revision,record_proof_hash FROM crypto_business_records WHERE partition=? AND scope_id=? AND type=?',
            [client.partition, ledger['child'], 'financeAccountChoice'],
          );
          var projectionStart = 0;
          Future<void> verify({
            required bool online,
            bool historical = false,
          }) async {
            final access = _TracingAccess(
              account: client.account,
              lab: controlLab,
            );
            final runtime = CryptoBusinessSession(
              client.account,
              access,
              client.db,
              onlineAccountChoiceDirectories: online,
            );
            CryptoBusinessRouter.configurePayloads(runtime);
            final body = Map<String, dynamic>.from(
              CryptoJson.decode(
                    cryptoBase64(
                      wire['authorization']['recordProof']['commandBase64'],
                    ),
                  )
                  as Map,
            );
            final authority = await access.recordAuthority(body);
            final record = await runtime.codec.verifyWire(
              serverId: client.session.profile.serverId,
              wire: wire,
              trustedSigningKey: authority.signingKey,
              currentEpoch: authority.currentEpoch,
              closedRecordProofHash: authority.closedRecordProofHash,
            );
            final key = await access.recordKey(record);
            final bytes = () {
              try {
                return runtime.codec.openVerified(record, key.key);
              } finally {
                key.release();
              }
            }();
            check(bytes != null, 'control_plaintext_required');
            try {
              final envelope = jsonDecode(utf8.decode(bytes!)) as Map;
              check(
                envelope['format'] == 2 &&
                    CryptoBusinessJson.canonical(envelope['identity']) ==
                        CryptoBusinessJson.canonical(
                          record['metadata']['identity'],
                        ),
                'control_envelope_identity',
              );
              final raw = Map<String, dynamic>.from(envelope['payload'] as Map);
              final offer =
                  CryptoJson.decode(
                        cryptoBase64(
                          raw['offerAuthorization']['commandBase64'],
                        ),
                      )
                      as Map;
              client.wire.controlDirectoryTarget =
                  offer['authorDirectoryHeadHash'] as String;
              client.wire.controlDirectoryAccount =
                  offer['accountId'] as String;
              projectionStart = controlLab.calls.length;
              final projected = await CryptoFinanceAccountChoices(runtime)
                  .projectRecord(
                    CryptoProjectionRecord(
                      wire,
                      record,
                      bytes,
                      historyBasis: authority.historyBasis ?? 'currentEpoch',
                      batchKey: await runtime.codec.digest(
                        Map<String, dynamic>.from(
                          wire['authorization']['batchCommitment'] as Map,
                        ),
                      ),
                      historicalOnly: historical,
                    ),
                    raw,
                  );
              check(
                CryptoBusinessJson.canonical(projected) ==
                    CryptoBusinessJson.canonical(raw),
                'control_projected_raw_changed',
              );
            } finally {
              bytes?.fillRange(0, bytes.length, 0);
            }
          }

          try {
            for (final mode in ['default_offline', 'historical_only']) {
              var rejected = false;
              try {
                await verify(
                  online: mode == 'historical_only',
                  historical: mode == 'historical_only',
                );
              } on CryptoAuthorityPending catch (error) {
                rejected = error.reason == 'directory_proof_pending';
              }
              check(
                rejected,
                'control_restricted_projection_must_remain_pending',
              );
              check(
                controlLab.calls
                    .skip(projectionStart)
                    .any(
                      (c) =>
                          c['operation'] ==
                              'diagnostic_projection_directoryAt' &&
                          c['online'] == false &&
                          c['targetPrefixPresent'] == false,
                    ),
                'control_exact_inner_offline_rejection_missing',
              );
              check(
                !controlLab.calls
                    .skip(projectionStart)
                    .any(
                      (c) =>
                          c['operation'] == 'crypto2.directory.read' &&
                          c['controlTargetDirectory'] == true,
                    ),
                'control_restricted_projection_fetched_directory',
              );
            }
            await verify(online: true);
            check(
              controlLab.calls
                  .skip(projectionStart)
                  .any(
                    (c) =>
                        c['operation'] == 'crypto2.directory.read' &&
                        c['controlTargetDirectory'] == true &&
                        c['status'] == 200,
                  ),
              'control_optin_directory_fetch_missing',
            );
            final retainedTarget = await client.db.rows(
              'SELECT entries FROM crypto_restore_scoped_directories WHERE partition=? AND scope_id=? AND account_id=? AND directory_head_hash=?',
              [
                client.partition,
                ledger['child'],
                client.wire.controlDirectoryAccount,
                client.wire.controlDirectoryTarget,
              ],
            );
            check(
              retainedTarget.isNotEmpty,
              'control_verified_target_prefix_not_retained',
            );
            final after = await client.db.rows(
              'SELECT crypto_revision,record_proof_hash FROM crypto_business_records WHERE partition=? AND scope_id=? AND type=?',
              [client.partition, ledger['child'], 'financeAccountChoice'],
            );
            check(
              jsonEncode(before) == jsonEncode(after),
              'control_must_not_install_projection',
            );
            await originalUnchanged();
            ledger['phases']['control_choice_directory_fetch'].addAll({
              'defaultOfflineGuard': true,
              'historicalOnlyGuard': true,
              'realOnlineAnchoredFetchAndVerification': true,
              'noBusinessProjectionOrMutation': true,
              'originalMemberFilesUnchanged': true,
            });
          } finally {
            lab.calls.addAll(controlLab.calls);
            await controlLab.close();
          }
        });
        await phase('H3_following_nochange', () async {
          final a = await lab.open('owner'), b = await lab.open('member');
          final finance = await a.finance(), signed = await a.signed();
          final phaseState = ledger['phases']['H3_following_nochange'] as Map;
          final previous = (phaseState['previousRuns'] as List? ?? [])
              .cast<Map>();
          final ownerAlreadyCompleted = previous.any(
            (r) => (r['calls'] as List).any((c) => c['actor'] == 'member'),
          );
          if (!ownerAlreadyCompleted) await a.sync();
          if (phaseState['attempts'] == 2 &&
              ledger['h3ProjectionDiagnostic'] != true) {
            final access = _TracingAccess(account: b.account, lab: lab);
            final runtime = CryptoBusinessSession(b.account, access, b.db);
            CryptoBusinessRouter.configurePayloads(runtime);
            final rows = await b.db.rows(
              "SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain='finance' AND verdict='received' AND json_extract(wire,'\$.type')='financeAccountChoice' ORDER BY revision DESC LIMIT 1",
              [b.partition, ledger['child']],
            );
            check(rows.length == 1, 'diagnostic_pending_wire_required');
            final wire = Map<String, dynamic>.from(
              jsonDecode(rows.single['wire'] as String) as Map,
            );
            final body = Map<String, dynamic>.from(
              CryptoJson.decode(
                    cryptoBase64(
                      wire['authorization']['recordProof']['commandBase64'],
                    ),
                  )
                  as Map,
            );
            final authority = await access.recordAuthority(body);
            final record = await runtime.codec.verifyWire(
              serverId: b.session.profile.serverId,
              wire: wire,
              trustedSigningKey: authority.signingKey,
              currentEpoch: authority.currentEpoch,
              closedRecordProofHash: authority.closedRecordProofHash,
            );
            final key = await access.recordKey(record);
            final plaintext = () {
              try {
                return runtime.codec.openVerified(record, key.key);
              } finally {
                key.release();
              }
            }();
            check(plaintext != null, 'diagnostic_plaintext_required');
            try {
              final envelope = jsonDecode(utf8.decode(plaintext!)) as Map;
              check(
                envelope['format'] == 2 &&
                    CryptoBusinessJson.canonical(envelope['identity']) ==
                        CryptoBusinessJson.canonical(
                          record['metadata']['identity'],
                        ),
                'diagnostic_envelope_identity',
              );
              final raw = Map<String, dynamic>.from(envelope['payload'] as Map);
              try {
                await CryptoFinanceAccountChoices(runtime).projectRecord(
                  CryptoProjectionRecord(
                    wire,
                    record,
                    plaintext,
                    historyBasis: authority.historyBasis ?? 'currentEpoch',
                    batchKey: await runtime.codec.digest(
                      Map<String, dynamic>.from(
                        wire['authorization']['batchCommitment'] as Map,
                      ),
                    ),
                  ),
                  raw,
                );
                throw StateError('diagnostic_expected_original_pending');
              } on CryptoAuthorityPending catch (error, stack) {
                lab.calls.add({
                  'actor': 'member',
                  'operation': 'diagnostic_actual_projection_verifier',
                  'origin': 'original_projection_error',
                  'code': error.reason,
                  'errorType': error.runtimeType.toString(),
                  'stack': _frames(stack),
                });
                check(
                  error.reason == 'directory_proof_pending',
                  'diagnostic_original_reason_changed',
                );
                ledger['h3ProjectionDiagnostic'] = true;
                await lab.save();
              }
            } finally {
              plaintext?.fillRange(0, plaintext.length, 0);
            }
          }
          await b.sync();
          check(
            jsonEncode(await a.finance()) == jsonEncode(finance),
            'nochange_finance_changed',
          );
          for (final old in signed) {
            check(
              (await a.signed()).any((r) => jsonEncode(old) == jsonEncode(r)),
              'nochange_signed_request_changed',
            );
          }
          final health = await a.health(ledger['parent'], ledger['child']);
          check(
            health['balanceMinor'] == '3333' &&
                health['expenseMinor'] == '1234' &&
                health['choices'] == 1,
            'nochange_finance_invariants',
          );
          ledger['phases']['H3_following_nochange']['health'] = health;
        });
        await phase('H5_before_send_outage', () async {
          final a = await lab.open('owner');
          // Retrying this stage may inspect its durable completed fault; never reinject it.
          if (ledger['beforeSendRequestId'] == null) {
            check(
              ledger['beforeSendFaultStarted'] != true,
              'before_send_ambiguous_fault_state',
            );
            if (ledger['beforeSendRotationHead'] == null) {
              check(
                ledger['beforeSendRotationStarted'] != true,
                'before_send_ambiguous_rotation_preserve_state',
              );
              ledger['beforeSendManifestBaseline'] = await a.manifest(
                ledger['child'],
              );
              ledger['beforeSendRotationStarted'] = true;
              await lab.save();
              final manager = ScopeCryptoManager(a.access);
              final next = await manager.confirmRotation(
                await manager.reviewRotation(ledger['child']),
                acceptedCandidateHistory: true,
              );
              ledger['beforeSendRotationHead'] = next.headHash;
              await lab.save();
            }
            a.wire.beforeChoice = (command) async {
              check(
                ledger['beforeSendRequestId'] == null,
                'before_send_fault_repeated',
              );
              final requestId = command['requestId'] as String;
              final row = (await a.db.rows(
                'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox WHERE partition=? AND request_id=?',
                [a.partition, requestId],
              )).single;
              final claims = await a.db.rows(
                'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=? ORDER BY scope_id,domain,record_id',
                [a.partition, requestId],
              );
              check(
                row['state'] == 'pending' && row['response'] == null,
                'before_send_requires_unacknowledged_pending',
              );
              check(claims.isNotEmpty, 'before_send_revision_claim_missing');
              final metric = lab.calls.last;
              check(
                metric['operation'] == 'crypto2.records.batch' &&
                    metric['choice'] == true &&
                    metric['requestHash'] == row['request_hash'],
                'before_send_wire_binding',
              );
              ledger['beforeSendFaultStarted'] = true;
              ledger['beforeSendRequestId'] = requestId;
              ledger['beforeSendRequestHash'] = row['request_hash'];
              ledger['beforeSendOriginalRow'] = row;
              ledger['beforeSendOriginalClaims'] = claims;
              ledger['beforeSendFaultCount'] = 1;
              // Persist exact immutable request and original claim BEFORE interruption.
              await lab.save();
              metric['fault'] = 'drop_before_delegate_send';
              a.wire.offline = true;
              throw http.ClientException('synthetic_before_send_outage');
            };
            await a.sync(success: false);
          }
          check(
            ledger['beforeSendRequestId'] != null,
            'before_send_fault_not_reached',
          );
          final row = (await a.db.rows(
            'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox WHERE partition=? AND request_id=?',
            [a.partition, ledger['beforeSendRequestId']],
          )).single;
          check(
            jsonEncode(row) == jsonEncode(ledger['beforeSendOriginalRow']),
            'before_send_pending_request_changed',
          );
          check(
            ledger['beforeSendFaultCount'] == 1,
            'before_send_injected_more_than_once',
          );
          ledger['phases']['H5_before_send_outage']['pendingExactRequest'] =
              true;
          await lab.save();
        });

        await phase('H5_before_send_restart', () async {
          await lab.restart('owner');
          final a = await lab.open('owner');
          final id = ledger['beforeSendRequestId'] as String;
          final original = ledger['beforeSendOriginalRow'] as Map;
          final before = (await a.db.rows(
            'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox WHERE partition=? AND request_id=?',
            [a.partition, id],
          )).single;
          // If a prior resume attempt already received a terminal ACK, do not demand its
          // row is still pending and do not call syncNow again. Persist/validate durable
          // substep after ACK before remaining assertions. See integration note below.
          if (ledger['beforeSendResumeApplied'] != true) {
            for (final key in ['request_id', 'request_hash', 'signed_body']) {
              check(
                before[key] == original[key],
                'before_send_restart_request_changed',
              );
            }
            ledger['beforeSendResumeStarted'] = true;
            await lab.save();
            await a.sync();
            check(
              ledger['beforeSendUnknownReceiptCount'] == 1,
              'before_send_requires_one_real_unknown_receipt',
            );
            check(
              ledger['beforeSendExactBatchSendCount'] == 1 &&
                  ledger['beforeSendAppliedAck'] == true &&
                  ledger['beforeSendAckRequestHash'] ==
                      original['request_hash'],
              'before_send_requires_one_exact_applied_batch',
            );
            ledger['beforeSendResumeApplied'] = true;
            ledger['beforeSendResumeEvidence'] = {
              'unknownReceiptCount': 1,
              'exactBatchCount': 1,
              'appliedAck': true,
            };
            await lab.save();
          }
          final after = (await a.db.rows(
            'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox WHERE partition=? AND request_id=?',
            [a.partition, id],
          )).single;
          for (final key in ['request_id', 'request_hash', 'signed_body']) {
            check(
              after[key] == original[key],
              'before_send_original_signed_request_changed',
            );
          }
          // Bind terminal state to the exact queue state's existing spelling during integration.
          check(
            after['state'] == 'applied' && after['response'] != null,
            'before_send_missing_terminal_response',
          );
          final receipt = jsonDecode(after['response'] as String) as Map;
          check(
            receipt['status'] == 200 &&
                receipt['response']['status'] == 'applied',
            'before_send_exact_receipt_invalid',
          );
          final claims = await a.db.rows(
            'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=? ORDER BY scope_id,domain,record_id',
            [a.partition, id],
          );
          check(
            jsonEncode(claims) ==
                jsonEncode(ledger['beforeSendOriginalClaims']),
            'before_send_claims_changed',
          );
          await a.assertBaseline();
          final manifest = await a.manifest(ledger['child']);
          check(
            manifest['revision'] ==
                (ledger['beforeSendManifestBaseline']['revision'] as int) + 1,
            'before_send_manifest_revision_duplicated',
          );
          check(
            manifest['targetHeadHash'] == ledger['beforeSendRotationHead'],
            'before_send_manifest_head_mismatch',
          );
          if (ledger['beforeSendMemberCatchupCompleted'] != true) {
            final b = await lab.open('member');
            await b.sync();
            final peer = await b.manifest(ledger['child']);
            check(
              jsonEncode(peer) == jsonEncode(manifest),
              'before_send_member_manifest_not_current',
            );
            ledger['beforeSendMemberCatchupCompleted'] = true;
            await lab.save();
          }
          ledger['phases']['H5_before_send_restart']['health'] = await a.health(
            ledger['parent'],
            ledger['child'],
          );
          ledger['phases']['H5_before_send_restart']['exactRequestAndClaimsPreserved'] =
              true;
          await lab.save();
        });

        await phase('H6_choice_cas', () async {
          final a = await lab.open('owner'), b = await lab.open('member');
          final child = ledger['child'] as String;
          final state =
              ledger.putIfAbsent('h6', () => <String, dynamic>{}) as Map;
          check(a.partition != b.partition, 'h6_distinct_partitions_required');
          check(
            state['raceStarted'] != true || state['raceCompleted'] == true,
            'h6_ambiguous_race_preserve_state',
          );

          Future<Map<String, dynamic>> certified(_Client client) async {
            final actor = client.actor;
            if (state['${actor}Proof'] is Map) {
              return Map<String, dynamic>.from(state['${actor}Proof'] as Map);
            }
            state['${actor}Select'] ??= codec.randomId();
            state['${actor}Approve'] ??= codec.randomId();
            state['${actor}Certify'] ??= codec.randomId();
            await lab.save();
            final prepared = await client.choices.prepare(
              child,
              actionId: state['${actor}Select'],
            );
            final offer = Map<String, dynamic>.from(
              prepared['offerAuthorization'] as Map,
            );
            final approved = await client.choices.approve(
              child,
              offer,
              actionId: state['${actor}Approve'],
              recipientAccountId: client.account.directory.accountId,
              recipientDeviceId: client.account.deviceId,
            );
            final delegation = Map<String, dynamic>.from(
              approved['delegationAuthorization'] as Map,
            );
            final certified = await client.choices.certify(
              child,
              selectionActionId: state['${actor}Select'],
              offerAuthorization: offer,
              delegationAuthorization: delegation,
              actionId: state['${actor}Certify'],
            );
            final certificate = Map<String, dynamic>.from(
              certified['certificateAuthorization'] as Map,
            );
            final hash = await cryptoSha256(CryptoJson.encode(certificate));
            final value = <String, dynamic>{
              'offer': offer,
              'delegation': delegation,
              'certificate': certificate,
              'operationId': await client.runtime.reservedRecordId(
                child,
                'accountChoiceSelection:materialize:$hash',
              ),
            };
            state['${actor}Proof'] = value;
            await lab.save();
            return value;
          }

          if (state['raceCompleted'] != true) {
            // If H5 advanced the head only on owner, this is member's first ordinary
            // catch-up for that new state. The real router owns the narrow online
            // directory opt-in; direct helper sessions deliberately remain offline.
            final beforeMember = await b.manifest(child);
            final liveHead = await a.access.currentHead(child, online: true);
            if (beforeMember['targetHeadHash'] != liveHead.headHash) {
              await b.sync();
            }
            // Nonpublishing authenticated reads establish an identical physical base.
            await a.repo.refreshFinanceAccountChoices(child);
            await b.repo.refreshFinanceAccountChoices(child);
            final am = await a.manifest(child), bm = await b.manifest(child);
            check(
              jsonEncode(am) == jsonEncode(bm),
              'h6_base_manifest_mismatch',
            );
            final ah = await a.access.currentHead(child, online: true);
            final bh = await b.access.currentHead(child, online: true);
            check(
              ah.headHash == bh.headHash && am['targetHeadHash'] == ah.headHash,
              'h6_base_head_mismatch',
            );
            final awire = a.runtime
                .address(
                  child,
                  'finance',
                  CryptoFinanceAccountChoices.type,
                  await a.choices.manifestId(child),
                )
                .wireId;
            final bwire = b.runtime
                .address(
                  child,
                  'finance',
                  CryptoFinanceAccountChoices.type,
                  await b.choices.manifestId(child),
                )
                .wireId;
            check(awire == bwire, 'h6_same_wire_record_required');
            state['base'] = am;
            final ap = await certified(a), bp = await certified(b);
            check(
              ap['operationId'] != bp['operationId'],
              'h6_distinct_intents_required',
            );

            await lab.reserveQuota(250);
            final gate = Completer<void>();
            // Even a failure before either actor parks must not leave an unhandled
            // error on the cancellation gate; parked actors still see its own error.
            gate.future.then<void>(
              (_) {},
              onError: (Object _, StackTrace __) {},
            );
            final arrivedA = Completer<void>(), arrivedB = Completer<void>();
            final earlyFailure = Completer<void>();
            Future<void> park(
              _Client client,
              Map command,
              Completer<void> arrived,
            ) async {
              final proofs = (command['payload'] as Map)['records'] as List;
              check(proofs.length == 1, 'h6_single_manifest_batch_required');
              final record =
                  CryptoJson.decode(
                        cryptoBase64((proofs.single as Map)['commandBase64']),
                      )
                      as Map;
              check(
                record['type'] == 'financeAccountChoice' &&
                    record['scopeId'] == child &&
                    record['id'] == awire &&
                    record['expectedRevision'] == am['revision'] &&
                    record['previousRecordHash'] == am['recordProofHash'] &&
                    record['membershipHeadHash'] == ah.headHash,
                'h6_signed_base_mismatch',
              );
              final requestId = command['requestId'] as String;
              final row = (await client.db.rows(
                'SELECT request_id,operation,signed_body,request_hash,state,response '
                'FROM crypto_outbox WHERE partition=? AND request_id=?',
                [client.partition, requestId],
              )).single;
              final claims = await client.db.rows(
                'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=?',
                [client.partition, requestId],
              );
              check(
                row['state'] == 'pending' && claims.length == 1,
                'h6_durable_pre_send_work_missing',
              );
              state['${client.actor}Original'] = row;
              state['${client.actor}Claims'] = claims;
              await lab.save();
              arrived.complete();
              // At most the normal unchanged quota window can delay the other actor.
              await gate.future;
            }

            a.wire.beforeChoice = (command) => park(a, command, arrivedA);
            b.wire.beforeChoice = (command) => park(b, command, arrivedB);
            state['raceStarted'] = true;
            await lab.save();
            final raceStart = lab.calls.length;
            Future<Map<String, dynamic>> run(_Client client, Map proof) async {
              try {
                await client.choices.materialize(
                  child,
                  offerAuthorization: Map<String, dynamic>.from(
                    proof['offer'] as Map,
                  ),
                  delegationAuthorization: Map<String, dynamic>.from(
                    proof['delegation'] as Map,
                  ),
                  certificateAuthorization: Map<String, dynamic>.from(
                    proof['certificate'] as Map,
                  ),
                  operationId: proof['operationId'],
                );
                return {'actor': client.actor, 'ok': true};
              } catch (error) {
                if (!gate.isCompleted && !earlyFailure.isCompleted) {
                  earlyFailure.completeError(
                    StateError('h6_actor_failed_before_gate'),
                  );
                }
                return {
                  'actor': client.actor,
                  'ok': false,
                  'code': _code(error),
                };
              }
            }

            final running = [run(a, ap), run(b, bp)];
            late List<Map<String, dynamic>> results;
            try {
              await Future.any<void>([
                Future.wait<void>([
                  arrivedA.future,
                  arrivedB.future,
                ]).then((_) {}),
                earlyFailure.future,
              ]).timeout(const Duration(seconds: 90));
              gate.complete();
              results = await Future.wait(
                running,
              ).timeout(const Duration(seconds: 180));
            } catch (_) {
              // Complete waiting callbacks with an error before they can touch HTTP.
              if (!gate.isCompleted) {
                gate.completeError(StateError('h6_barrier_aborted'));
              }
              await Future.wait(running).timeout(const Duration(seconds: 180));
              rethrow;
            } finally {
              a.wire.beforeChoice = null;
              b.wire.beforeChoice = null;
            }
            state['results'] = results;
            state['raceCalls'] = lab.calls.skip(raceStart).toList();
            state['raceCompleted'] = true;
            await lab.save();
          }

          final raceCalls = (state['raceCalls'] as List).cast<Map>();
          final batches = raceCalls
              .where(
                (c) =>
                    c['operation'] == 'crypto2.records.batch' &&
                    c['choice'] == true &&
                    c['origin'] == null,
              )
              .toList();
          check(
            batches.length == 2,
            'h6_exact_two_signed_choice_sends_required',
          );
          check(
            batches.where((c) => c['status'] == 200).length == 1 &&
                batches.where((c) => c['status'] == 409).length == 1,
            'h6_real_one_applied_one_conflict_required',
          );
          final loserActor = batches.singleWhere(
            (c) => c['status'] == 409,
          )['actor'];
          final winnerActor = batches.singleWhere(
            (c) => c['status'] == 200,
          )['actor'];
          final results = (state['results'] as List).cast<Map>();
          check(
            results.singleWhere((r) => r['actor'] == winnerActor)['ok'] == true,
            'h6_winning_materializer_must_verify_own_publication',
          );
          final loserResult = results.singleWhere(
            (r) => r['actor'] == loserActor,
          );
          check(
            loserResult['ok'] == true ||
                loserResult['code'] == 'crypto_business_delivery_pending',
            'h6_unexpected_loser_outcome',
          );
          for (final client in [a, b]) {
            final original = state['${client.actor}Original'] as Map;
            final after = (await client.db.rows(
              'SELECT request_id,operation,signed_body,request_hash,state,response '
              'FROM crypto_outbox WHERE partition=? AND request_id=?',
              [client.partition, original['request_id']],
            )).single;
            for (final key in [
              'request_id',
              'operation',
              'signed_body',
              'request_hash',
            ]) {
              check(after[key] == original[key], 'h6_signed_request_changed');
            }
            final claims = await client.db.rows(
              'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=?',
              [client.partition, original['request_id']],
            );
            check(
              claims.isNotEmpty &&
                  jsonEncode(claims) ==
                      jsonEncode(state['${client.actor}Claims']),
              'h6_original_claim_changed',
            );
            final receipt = jsonDecode(after['response'] as String) as Map;
            if (client.actor == loserActor) {
              check(
                after['state'] == 'rejected' &&
                    receipt['status'] == 409 &&
                    receipt['response']['errorCode'] == 'conflict',
                'h6_loser_exact_conflict_not_retained',
              );
            } else {
              check(
                after['state'] == 'applied' &&
                    receipt['status'] == 200 &&
                    receipt['response']['status'] == 'applied',
                'h6_winner_exact_applied_not_retained',
              );
            }
          }

          // These are the one integration/convergence syncs for the newly raced intents.
          if (state['ownerConverged'] != true) {
            await lab.reserveQuota(220);
            await a.sync();
            state['ownerConverged'] = true;
            await lab.save();
          }
          if (state['memberConverged'] != true) {
            await lab.reserveQuota(220);
            await b.sync();
            state['memberConverged'] = true;
            await lab.save();
          }
          await a.repo.refreshFinanceAccountChoices(child);
          await b.repo.refreshFinanceAccountChoices(child);
          final am = await a.manifest(child), bm = await b.manifest(child);
          check(
            jsonEncode(am) == jsonEncode(bm),
            'h6_clients_did_not_converge',
          );
          check(
            am['revision'] == state['base']['revision'] + 1 &&
                am['targetHeadHash'] == state['base']['targetHeadHash'],
            'h6_cas_must_advance_exactly_once',
          );
          await a.assertBaseline();
          await b.assertBaseline();
          final healthA = await a.health(ledger['parent'], child);
          final healthB = await b.health(ledger['parent'], child);
          for (final health in [healthA, healthB]) {
            check(
              health['balanceMinor'] == '3333' &&
                  health['expenseMinor'] == '1234' &&
                  health['accounts'] == 1 &&
                  health['entries'] == 1 &&
                  health['choices'] == 1,
              'h6_finance_invariants',
            );
          }
          ledger['phases']['H6_choice_cas'].addAll({
            'signedSends': 2,
            'applied': 1,
            'conflict': 1,
            'winnerActor': winnerActor,
            'loserActor': loserActor,
            'loserImmediateOutcome': loserResult['ok'] == true
                ? 'verified_winner_immediately'
                : 'pending_until_ordinary_sync',
            'sameExpectedRevision': state['base']['revision'],
            'manifest': am,
            'healthOwner': healthA,
            'healthMember': healthB,
            'originalSignedRequestsAndClaimsPreserved': true,
            'exactStaleClaimHelperCoverage': 'not_claimed_same_head_cas_only',
          });
        });

        await phase('H4_concurrent_task_edits', () async {
          final a = await lab.open('owner'), b = await lab.open('member');
          final child = ledger['child'] as String;
          final state =
              ledger.putIfAbsent('h4', () => <String, dynamic>{}) as Map;
          check(a.partition != b.partition, 'h4_distinct_partitions_required');
          check(
            state['raceStarted'] != true || state['raceCompleted'] == true,
            'h4_ambiguous_race_preserve_state',
          );

          if (state['taskId'] == null) {
            check(
              state['taskCreationIntent'] != true,
              'h4_ambiguous_task_creation_preserve_state',
            );
            state['taskCreationIntent'] = true;
            await lab.save();
            state['taskId'] = await a.repo.createTask(
              scopeId: child,
              title: 'Synthetic concurrent base',
            );
            await lab.save();
          }
          final taskId = state['taskId'] as String;
          ledger['taskId'] = taskId;
          await lab.save();
          if (state['baseSynchronized'] != true) {
            if (state['ownerBaseSynced'] != true) {
              await lab.reserveQuota(220);
              await a.sync();
              state['ownerBaseSynced'] = true;
              await lab.save();
            }
            if (state['memberBaseSynced'] != true) {
              await lab.reserveQuota(220);
              await b.sync();
              state['memberBaseSynced'] = true;
              await lab.save();
            }
            final ta = a.repo.state
                .dataForScope(child)
                .tasks
                .singleWhere((t) => t.id == taskId);
            final tb = b.repo.state
                .dataForScope(child)
                .tasks
                .singleWhere((t) => t.id == taskId);
            final ar = await a.runtime.record(
              child,
              'content',
              taskId,
              type: 'task',
            );
            final br = await b.runtime.record(
              child,
              'content',
              taskId,
              type: 'task',
            );
            Future<Map<String, dynamic>> plainBase(
              _Client client,
            ) async => (await client.db.rows(
              'SELECT server_revision,payload FROM records WHERE partition=? AND scope_id=? AND id=?',
              [client.partition, child, taskId],
            )).single;
            final plainA = await plainBase(a), plainB = await plainBase(b);
            check(
              plainA['server_revision'] == plainB['server_revision'] &&
                  plainA['payload'] == plainB['payload'] &&
                  ar != null &&
                  br != null &&
                  ar['crypto_revision'] == br['crypto_revision'] &&
                  ar['record_proof_hash'] == br['record_proof_hash'],
              'h4_initial_task_bases_differ',
            );
            state['baseCryptoRevision'] = ar!['crypto_revision'];
            state['baseRecordProofHash'] = ar['record_proof_hash'];
            state['ownerDraftBase'] = ta.toJson();
            state['memberDraftBase'] = tb.toJson();
            state['baseSynchronized'] = true;
            await lab.save();
          }

          Future<List<Map<String, dynamic>>> queued(
            _Client client,
          ) => client.db.rows(
            'SELECT sequence,op_id,partition,scope_id,record_id,request,state,wire_version '
            'FROM outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence',
            [client.partition, child, taskId],
          );
          final titles = {
            'owner': 'Synthetic actor A edit',
            'member': 'Synthetic actor B edit',
          };
          for (final client in [a, b]) {
            final actor = client.actor;
            if (state['${actor}OriginalQueue'] != null) continue;
            if (state['${actor}EditIntent'] == true) {
              // A crash between the atomic local edit and ledger save must not create
              // another operation. Recover the exact sole original queue row.
              final recovered = await queued(client);
              check(
                recovered.length == 1,
                'h4_ambiguous_local_edit_preserve_state',
              );
              final request =
                  jsonDecode(recovered.single['request'] as String) as Map;
              check(
                request['payload']['title'] == titles[actor],
                'h4_recovered_edit_identity_mismatch',
              );
              state['${actor}OriginalQueue'] = recovered.single;
              await lab.save();
              continue;
            }
            state['${actor}EditIntent'] = true;
            await lab.save();
            final base = LocalTask.fromJson(
              Map<String, dynamic>.from(state['${actor}DraftBase'] as Map),
            );
            await client.repo.updateTask(
              child,
              base.copyWith(title: titles[actor]),
            );
            final rows = await queued(client);
            check(
              rows.length == 1 && rows.single['state'] == 'pending',
              'h4_exact_one_local_edit_required',
            );
            state['${actor}OriginalQueue'] = rows.single;
            await lab.save();
          }
          final qa = state['ownerOriginalQueue'] as Map;
          final qb = state['memberOriginalQueue'] as Map;
          check(
            (jsonDecode(qa['request'] as String) as Map)['expectedRevision'] ==
                (jsonDecode(qb['request'] as String)
                    as Map)['expectedRevision'],
            'h4_plain_expected_revisions_differ',
          );

          if (state['raceCompleted'] != true) {
            await lab.reserveQuota(250);
            final gate = Completer<void>();
            gate.future.then<void>(
              (_) {},
              onError: (Object _, StackTrace __) {},
            );
            final arrivedA = Completer<void>(), arrivedB = Completer<void>();
            final earlyFailure = Completer<void>();
            Future<void> park(
              _Client client,
              Map command,
              Completer<void> arrived,
            ) async {
              final records = (command['payload'] as Map)['records'] as List;
              final record = records
                  .map(
                    (p) =>
                        CryptoJson.decode(
                              cryptoBase64((p as Map)['commandBase64']),
                            )
                            as Map,
                  )
                  .singleWhere((r) => r['type'] == 'task');
              final original = state['${client.actor}OriginalQueue'] as Map;
              check(
                record['operationId'] == original['op_id'] &&
                    record['expectedRevision'] == state['baseCryptoRevision'] &&
                    record['previousRecordHash'] ==
                        state['baseRecordProofHash'],
                'h4_signed_task_base_mismatch',
              );
              final signed = (await client.db.rows(
                'SELECT request_id,operation,signed_body,request_hash,state,response FROM crypto_outbox '
                'WHERE partition=? AND request_id=?',
                [client.partition, command['requestId']],
              )).single;
              final claims = await client.db.rows(
                'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=?',
                [client.partition, command['requestId']],
              );
              check(
                signed['state'] == 'pending' && claims.isNotEmpty,
                'h4_pre_send_signed_work_missing',
              );
              state['${client.actor}OriginalSigned'] = signed;
              state['${client.actor}OriginalClaims'] = claims;
              await lab.save();
              arrived.complete();
              await gate.future;
            }

            a.wire.beforeTask = (command) => park(a, command, arrivedA);
            b.wire.beforeTask = (command) => park(b, command, arrivedB);
            state['raceStarted'] = true;
            await lab.save();
            final start = lab.calls.length;
            Future<Map<String, dynamic>> run(_Client client) async {
              try {
                await client.sync(success: false);
                return {'actor': client.actor, 'ok': true};
              } catch (error) {
                if (!gate.isCompleted && !earlyFailure.isCompleted) {
                  earlyFailure.completeError(
                    StateError('h4_actor_failed_before_gate'),
                  );
                }
                return {
                  'actor': client.actor,
                  'ok': false,
                  'code': _code(error),
                };
              }
            }

            final running = [run(a), run(b)];
            try {
              await Future.any<void>([
                Future.wait<void>([
                  arrivedA.future,
                  arrivedB.future,
                ]).then((_) {}),
                earlyFailure.future,
              ]).timeout(const Duration(seconds: 90));
              gate.complete();
              state['syncResults'] = await Future.wait(
                running,
              ).timeout(const Duration(seconds: 180));
            } catch (_) {
              if (!gate.isCompleted) {
                gate.completeError(StateError('h4_barrier_aborted'));
              }
              await Future.wait(running).timeout(const Duration(seconds: 180));
              rethrow;
            } finally {
              a.wire.beforeTask = null;
              b.wire.beforeTask = null;
            }
            state['raceCalls'] = lab.calls.skip(start).toList();
            state['raceCompleted'] = true;
            await lab.save();
          }

          final states = <String, String>{};
          for (final client in [a, b]) {
            final original = state['${client.actor}OriginalSigned'] as Map;
            final current = (await client.db.rows(
              'SELECT request_id,signed_body,request_hash,state,response FROM crypto_outbox '
              'WHERE partition=? AND request_id=?',
              [client.partition, original['request_id']],
            )).single;
            for (final key in ['request_id', 'signed_body', 'request_hash']) {
              check(
                current[key] == original[key],
                'h4_original_signed_work_changed',
              );
            }
            final claims = await client.db.rows(
              'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=?',
              [client.partition, original['request_id']],
            );
            check(
              jsonEncode(claims) ==
                  jsonEncode(state['${client.actor}OriginalClaims']),
              'h4_original_claims_changed',
            );
            final receipt = jsonDecode(current['response'] as String) as Map;
            check(
              (current['state'] == 'applied' && receipt['status'] == 200) ||
                  (current['state'] == 'rejected' &&
                      receipt['status'] == 409 &&
                      receipt['response']['errorCode'] == 'conflict'),
              'h4_exact_terminal_receipt_required',
            );
            states[client.actor] = current['state'] as String;
          }
          check(
            states.values.where((s) => s == 'applied').length == 1 &&
                states.values.where((s) => s == 'rejected').length == 1,
            'h4_exact_one_winner_one_loser_required',
          );
          final winnerActor = states.entries
              .singleWhere((e) => e.value == 'applied')
              .key;
          final loserActor = states.entries
              .singleWhere((e) => e.value == 'rejected')
              .key;
          final originalAliases = <String>{
            lab.alias(state['ownerOriginalSigned']['request_id']),
            lab.alias(state['memberOriginalSigned']['request_id']),
          };
          final actualSends = (state['raceCalls'] as List)
              .cast<Map>()
              .where(
                (c) =>
                    c['operation'] == 'crypto2.records.batch' &&
                    c['origin'] == null &&
                    originalAliases.contains(c['requestAlias']),
              )
              .toList();
          check(
            actualSends.length == 2 &&
                actualSends.where((c) => c['status'] == 200).length == 1 &&
                actualSends.where((c) => c['status'] == 409).length == 1,
            'h4_actual_one_applied_one_conflict_send_required',
          );
          final winner = winnerActor == 'owner' ? a : b;
          final loser = loserActor == 'owner' ? a : b;
          final loserOriginal = state['${loserActor}OriginalQueue'] as Map;
          final winnerOriginal = state['${winnerActor}OriginalQueue'] as Map;
          final loserRows = await queued(loser),
              winnerRows = await queued(winner);
          check(
            winnerRows.isEmpty &&
                loserRows.length == 1 &&
                loserRows.single['state'] == 'conflict',
            'h4_losing_queue_not_retained',
          );
          for (final key in [
            'sequence',
            'op_id',
            'partition',
            'scope_id',
            'record_id',
            'request',
            'wire_version',
          ]) {
            check(
              loserRows.single[key] == loserOriginal[key],
              'h4_original_losing_draft_changed',
            );
          }
          final conflict = (await loser.db.rows(
            'SELECT * FROM conflicts WHERE partition=? AND scope_id=? AND record_id=?',
            [loser.partition, child, taskId],
          )).single;
          check(
            conflict['id'] == loserOriginal['op_id'] &&
                conflict['reason'] == 'conflict',
            'h4_conflict_not_bound_to_losing_operation',
          );
          final remote = jsonDecode(conflict['remote'] as String) as Map;
          check(
            remote['payload']['title'] == titles[winnerActor],
            'h4_conflict_remote_not_actual_winner',
          );
          final canonicalA = await a.runtime.record(
            child,
            'content',
            taskId,
            type: 'task',
          );
          final canonicalB = await b.runtime.record(
            child,
            'content',
            taskId,
            type: 'task',
          );
          final winningSigned =
              jsonDecode(
                    state['${winnerActor}OriginalSigned']['signed_body']
                        as String,
                  )
                  as Map;
          final winningCommand =
              CryptoJson.decode(cryptoBase64(winningSigned['commandBase64']))
                  as Map;
          final winningTaskProof =
              ((winningCommand['payload'] as Map)['records'] as List)
                  .cast<Map>()
                  .singleWhere(
                    (p) =>
                        (CryptoJson.decode(cryptoBase64(p['commandBase64']))
                            as Map)['type'] ==
                        'task',
                  );
          final winningProofHash = await winner.runtime.codec.digest(
            Map<String, dynamic>.from(winningTaskProof),
          );
          check(
            canonicalA != null &&
                canonicalB != null &&
                canonicalA['crypto_revision'] ==
                    state['baseCryptoRevision'] + 1 &&
                canonicalB['crypto_revision'] ==
                    canonicalA['crypto_revision'] &&
                canonicalB['record_proof_hash'] ==
                    canonicalA['record_proof_hash'] &&
                canonicalA['record_proof_hash'] == winningProofHash &&
                jsonDecode(canonicalA['raw_payload'] as String)['title'] ==
                    titles[winnerActor] &&
                jsonDecode(canonicalB['raw_payload'] as String)['title'] ==
                    titles[winnerActor],
            'h4_authenticated_canonical_winner_mismatch',
          );
          for (final client in [a, b]) {
            check(
              client.repo.lastSyncCompletion?.error == null &&
                  client.repo.state.lastError == null,
              'h4_unexpected_fullsync_error',
            );
          }
          final winnerRequest =
              jsonDecode(winnerOriginal['request'] as String) as Map;
          final loserRequest =
              jsonDecode(loserOriginal['request'] as String) as Map;
          check(
            winnerRequest['payload']['title'] !=
                    loserRequest['payload']['title'] &&
                loser.repo.state
                        .dataForScope(child)
                        .tasks
                        .singleWhere((t) => t.id == taskId)
                        .title ==
                    loserRequest['payload']['title'],
            'h4_local_losing_edit_silently_overwritten',
          );
          await a.assertBaseline();
          await b.assertBaseline();
          ledger['phases']['H4_concurrent_task_edits'].addAll({
            'winnerActor': winnerActor,
            'loserActor': loserActor,
            'acceptedTaskRevisions': 1,
            'retainedLosingDrafts': 1,
            'conflictsBoundToOriginalLosingDraft': true,
            'originalSignedRequestsAndClaimsPreserved': true,
            'bothAuthenticatedCanonicalProjectionsAgree': true,
            'financeBaselineUnchanged': true,
            'financeTaskDerivationCoverage': 'not_claimed_unlinked_title_edits',
          });
        });

        await phase('H7_revocation_recovery', () async {
          final a = await lab.open('owner'), b = await lab.open('member');
          final parent = ledger['parent'] as String,
              child = ledger['child'] as String;
          final state =
              ledger.putIfAbsent('h7', () => <String, dynamic>{}) as Map;
          if (state['pendingRequestId'] == null) {
            check(
              state['pendingFaultStarted'] != true,
              'h7_ambiguous_pending_fault',
            );
            if (state['rotationHead'] == null) {
              check(
                state['rotationStarted'] != true,
                'h7_ambiguous_rotation_preserve_state',
              );
              state['manifestBefore'] = await a.manifest(child);
              state['rotationStarted'] = true;
              await lab.save();
              await lab.reserveQuota(300);
              final manager = ScopeCryptoManager(a.access);
              final head = await manager.confirmRotation(
                await manager.reviewRotation(child),
                acceptedCandidateHistory: true,
              );
              state['rotationHead'] = head.headHash;
              await lab.save();
            }
            b.wire.beforeChoice = (command) async {
              final proofs = (command['payload'] as Map)['records'] as List;
              check(proofs.length == 1, 'h7_single_manifest_request_required');
              final record =
                  CryptoJson.decode(
                        cryptoBase64((proofs.single as Map)['commandBase64']),
                      )
                      as Map;
              check(
                record['type'] == 'financeAccountChoice' &&
                    record['scopeId'] == child &&
                    record['membershipHeadHash'] == state['rotationHead'] &&
                    record['expectedRevision'] ==
                        state['manifestBefore']['revision'],
                'h7_authorized_pending_request_binding',
              );
              final id = command['requestId'] as String;
              final row = (await b.db.rows(
                'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox '
                'WHERE partition=? AND request_id=?',
                [b.partition, id],
              )).single;
              final claims = await b.db.rows(
                'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=? '
                'ORDER BY scope_id,domain,record_id',
                [b.partition, id],
              );
              check(
                row['state'] == 'pending' &&
                    row['response'] == null &&
                    claims.isNotEmpty &&
                    lab.calls.last['requestHash'] == row['request_hash'],
                'h7_exact_unacknowledged_work_required',
              );
              state['pendingFaultStarted'] = true;
              state['pendingRequestId'] = id;
              state['originalRow'] = row;
              state['originalClaims'] = claims;
              // Explicit aliases for the read-only evidence helper; keep private.
              ledger['h7RequestId'] = id;
              ledger['h7RequestHash'] = row['request_hash'];
              ledger['h7Actor'] = 'member';
              await lab.save();
              lab.calls.last['fault'] = 'h7_before_send_pending_then_revoke';
              b.wire.offline = true;
              throw http.ClientException('synthetic_h7_before_send_outage');
            };
            await lab.reserveQuota(250);
            // The preserved H4 task pending work aborts its full sync before
            // finance. Prepare through the application's scoped refresh API.
            try {
              await b.repo.refreshFinanceAccountChoices(child);
            } catch (error) {
              if (!const {
                    'crypto_business_delivery_pending',
                    'network',
                  }.contains(_code(error)) ||
                  state['pendingRequestId'] == null ||
                  !b.wire.offline) {
                rethrow;
              }
              state['stagingRoute'] = 'scoped_account_choices_refresh';
              await lab.save();
            }
            check(
              state['pendingRequestId'] != null,
              'h7_pending_fault_not_reached',
            );
          }

          state['removeRequestId'] ??= codec.randomId();
          await lab.save();
          if (state['revoked'] != true) {
            check(
              state['removalStarted'] != true,
              'h7_ambiguous_removal_preserve_state',
            );
            await lab.reserveQuota(300);
            state['removalStarted'] = true;
            await lab.save();
            final removal =
                await CryptoBusinessStructure(
                  a.runtime,
                  reviewRecovery: (_) async => true,
                ).dispatch('scopes.removeMember', {
                  'scopeId': parent,
                  'accountId': b.account.directory.accountId,
                  'requestId': state['removeRequestId'],
                });
            check(removal['removed'] == true, 'h7_signed_removal_not_complete');
            // The existing coordinator reviews/rotates affected inherited children.
            final ph = await a.access.currentHead(parent, online: true);
            final ch = await a.access.currentHead(child, online: true);
            check(
              !ph.members.any(
                    (m) => m['accountId'] == b.account.directory.accountId,
                  ) &&
                  !ch.members.any(
                    (m) => m['accountId'] == b.account.directory.accountId,
                  ) &&
                  ch.headHash != state['rotationHead'],
              'h7_revocation_not_confirmed_do_not_deliver',
            );
            state['revoked'] = true;
            state['revokedChildHead'] = ch.headHash;
            await lab.save();
          }

          // Observe the physical record without creating a fresh derived manifest.
          await a.runtime.pullVerified(child, 'finance', attest: false);
          final beforeDenied = await a.manifest(child);
          final original = state['originalRow'] as Map;
          if (state['freshServerDenial'] != true) {
            check(
              state['directDeliveryStarted'] != true,
              'h7_ambiguous_direct_delivery_preserve_state',
            );
            // Revalidate exclusion immediately before the ONE explicitly requested send.
            final head = await a.access.currentHead(child, online: true);
            final parentHead = await a.access.currentHead(parent, online: true);
            check(
              !parentHead.members.any(
                    (m) => m['accountId'] == b.account.directory.accountId,
                  ) &&
                  !head.members.any(
                    (m) => m['accountId'] == b.account.directory.accountId,
                  ),
              'h7_revocation_not_confirmed_do_not_deliver',
            );
            state['directDeliveryStarted'] = true;
            await lab.save();
            final signed = Map<String, Object?>.from(
              jsonDecode(original['signed_body'] as String) as Map,
            );
            final directWire = _Wire(
              b,
            ); // Fresh transport only, no queue/preflight bypass in runtime.
            final direct = _Transport(lab, directWire);
            final start = lab.calls.length;
            String? deniedCode;
            try {
              await direct.call(
                serverUrl: b.session.profile.serverUrl,
                operation: 'crypto2.records.batch',
                params: signed,
                token: b.session.token,
                allowLocalHttp: b.session.profile.allowLocalHttp,
              );
            } on CollaborationApiException catch (error) {
              deniedCode = error.code;
            } finally {
              direct.close();
            }
            final actual = lab.calls
                .skip(start)
                .where(
                  (c) =>
                      c['operation'] == 'crypto2.records.batch' &&
                      c['origin'] == null,
                )
                .toList();
            check(
              actual.length == 1 &&
                  actual.single['status'] == 403 &&
                  actual.single['requestHash'] == original['request_hash'] &&
                  const {
                    'permission_revoked',
                    'finance_forbidden',
                    'forbidden',
                  }.contains(deniedCode),
              'h7_fresh_server_acl_denial_not_proven',
            );
            state['freshServerDenial'] = true;
            state['denialCode'] = deniedCode;
            await lab.save();
          }
          await a.runtime.pullVerified(child, 'finance', attest: false);
          check(
            jsonEncode(await a.manifest(child)) == jsonEncode(beforeDenied),
            'h7_denied_request_changed_physical_manifest',
          );

          if (state['memberRecoveryCompleted'] != true) {
            await lab.restart('member');
            final member = await lab.open('member');
            await lab.reserveQuota(250);
            final start = lab.calls.length;
            await member.sync(success: false);
            check(
              !lab.calls
                  .skip(start)
                  .any(
                    (c) =>
                        c['actor'] == 'member' &&
                        c['operation'] == 'crypto2.records.batch',
                  ),
              'h7_revoked_normal_recovery_sent_mutation',
            );
            state['memberRecoveryCompleted'] = true;
            await lab.save();
          }
          final member = await lab.open('member');
          final after = (await member.db.rows(
            'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox '
            'WHERE partition=? AND request_id=?',
            [member.partition, state['pendingRequestId']],
          )).single;
          for (final key in ['request_id', 'request_hash', 'signed_body']) {
            check(
              after[key] == original[key],
              'h7_original_pending_signed_work_changed',
            );
          }
          check(
            const {'pending', 'blocked'}.contains(after['state']),
            'h7_revoked_work_not_retained',
          );
          final claims = await member.db.rows(
            'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=? '
            'ORDER BY scope_id,domain,record_id',
            [member.partition, state['pendingRequestId']],
          );
          check(
            jsonEncode(claims) == jsonEncode(state['originalClaims']),
            'h7_claims_changed',
          );
          final scope = (await member.db.rows(
            'SELECT data FROM scopes WHERE partition=? AND id=?',
            [member.partition, child],
          )).single;
          check(
            jsonDecode(scope['data'] as String)['revoked'] == true,
            'h7_client_scope_not_revoked',
          );
          check(
            (await member.db.rows('SELECT 1 FROM local_meta WHERE name=?', [
              'finance_account_choices:${member.partition}:$child',
            ])).isEmpty,
            'h7_revoked_selector_restored',
          );
          await a.assertBaseline();
          ledger['phases']['H7_revocation_recovery'].addAll({
            'signedParentAndChildRevocationVerified': true,
            'oneExactFreshServerDenial': true,
            'denialCode': state['denialCode'],
            'noNormalRecoveryMutation': true, 'revokedSelectorHidden': true,
            'pendingSignedRequestAndClaimsPreserved': true,
            'physicalManifestUnchangedByDeniedRequest': true,
            'ownerFinanceBaselinePreserved': true,
            'globalCleanWorkClaimed':
                false, // H4 conflict and revoked pending work are intentional.
          });
        });
      } finally {
        await lab.close();
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
