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
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
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

// New isolated gap tests; no old harness main or retained scenario is invoked.
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

  Future<void> sync({bool clean = true}) async {
    final prior = repo.lastSyncCompletion?.sequence ?? 0;
    await repo.syncNow(manual: true);
    final completion = repo.lastSyncCompletion;
    check(
      completion != null && completion.sequence > prior,
      'new_sync_completion_required',
    );
    if (clean) {
      check(completion!.error == null, _code(completion.error) ?? 'sync_error');
      check(!completion.work.unresolved, 'unresolved_sync_work');
    }
  }

  LocalTask task(String id) =>
      repo.state.dataForScope(lab.scope).tasks.singleWhere((t) => t.id == id);
  Future<Map<String, dynamic>> canonical(String id, String type) async {
    final table = type == 'task' ? 'records' : 'finance_records';
    final app = (await db.rows(
      'SELECT server_revision,payload,deleted FROM $table WHERE partition=? AND scope_id=? AND id=?',
      [partition, lab.scope, id],
    )).single;
    final crypto = await runtime.record(
      lab.scope,
      type == 'task' ? 'content' : 'finance',
      id,
      type: type,
    );
    check(crypto != null, 'verified_crypto_record_required');
    return {
      'serverRevision': app['server_revision'],
      'payload': jsonDecode(app['payload'] as String),
      'deleted': app['deleted'],
      'cryptoRevision': crypto!['crypto_revision'],
      'proofHash': crypto['record_proof_hash'],
      'rawSha256': await cryptoSha256(
        utf8.encode(crypto['raw_payload'] as String),
      ),
    };
  }
}

void check(bool condition, String code) {
  if (!condition) throw StateError(code);
}

class _Lab {
  _Lab(this.root, this.fixture, this.ledger, this.scenario);
  final Directory root;
  final Map fixture;
  final Map<String, dynamic> ledger;
  final String scenario;
  final clients = <String, _Client>{};
  final calls = <Map<String, Object?>>[];
  String get scope => ledger['scope'] as String;
  Future<void> _tail = Future.value();
  Future<void> save() {
    final next = _tail.then((_) async {
      final tmp = File('${root.path}/$scenario-ledger.tmp');
      await tmp.writeAsString(jsonEncode(ledger), flush: true);
      await tmp.rename('${root.path}/$scenario-ledger-private.json');
    });
    _tail = next;
    return next;
  }

  Future<void> quota() async {
    final times = ledger.putIfAbsent('requestTimes', () => <dynamic>[]) as List;
    var now = DateTime.now().millisecondsSinceEpoch;
    times.removeWhere((v) => now - (v as int) >= 61000);
    if (times.length >= 300) {
      var ms = 61010 - (now - (times.first as int));
      debugPrint(
        'GAP_EVENT ${jsonEncode({'stage': 'pacing', 'milliseconds': ms})}',
      );
      while (ms > 0) {
        final n = ms > 30000 ? 30000 : ms;
        await Future<void>.delayed(Duration(milliseconds: n));
        ms -= n;
      }
      now = DateTime.now().millisecondsSinceEpoch;
      times.removeWhere((v) => now - (v as int) >= 61000);
    }
    times.add(now);
    await save();
  }

  Future<_Client> open(String actor) async =>
      clients[actor] ??= await _Client.open(this, actor);
  Future<void> restart(String actor) async {
    await clients.remove(actor)?.close();
    await open(actor);
  }

  Future<void> close() async {
    for (final c in clients.values) {
      await c.close();
    }
  }

  Future<void> step(String name, Future<void> Function() body) async {
    final steps = ledger.putIfAbsent('steps', () => <String, dynamic>{}) as Map;
    final state = steps.putIfAbsent(name, () => <String, dynamic>{}) as Map;
    if (state['passed'] == true) return;
    state['attempts'] = (state['attempts'] as int? ?? 0) + 1;
    check(state['attempts'] <= 3, 'substep_budget_exhausted');
    await save();
    final start = calls.length;
    final watch = Stopwatch()..start();
    try {
      await body();
      state['passed'] = true;
      state.remove('code');
    } catch (e, s) {
      state['code'] = _code(e);
      state['errorType'] = e.runtimeType.toString();
      state['frames'] = _frames(s);
      rethrow;
    } finally {
      state['elapsedMicroseconds'] = watch.elapsedMicroseconds;
      state['calls'] = calls.skip(start).toList();
      await save();
    }
  }
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
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

class _Wire extends http.BaseClient {
  _Wire(this.client);
  final _Client client;
  final delegate = http.Client();
  bool offline = false;
  bool dropPairAck = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest base) async {
    if (offline) throw http.ClientException('synthetic_pair_outage');
    check(client.lab.calls.length < 2400, 'scenario_http_budget_exhausted');
    final req = base as http.Request;
    final body = jsonDecode(req.body) as Map;
    final op = body['op'] as String;
    final params = body['params'] as Map;
    final command = params['commandBase64'] is String
        ? CryptoJson.decode(cryptoBase64(params['commandBase64'])) as Map
        : null;
    final types = command != null && op == 'crypto2.records.batch'
        ? (command['payload']['records'] as List)
              .map(
                (p) =>
                    (CryptoJson.decode(cryptoBase64(p['commandBase64']))
                        as Map)['type'],
              )
              .toSet()
        : <dynamic>{};
    final metric = <String, Object?>{
      'actor': client.actor,
      'operation': op,
      'status': null,
      'requestBytes': req.contentLength,
      'responseBytes': 0,
    };
    if (command != null) {
      metric['requestHash'] = await cryptoSha256(
        cryptoBase64(params['commandBase64']),
      );
      metric['requestId'] = command['requestId'];
    }
    if (op == 'crypto2.receipt.get') metric['requestId'] = params['requestId'];
    client.lab.calls.add(metric);
    final response = await delegate.send(req);
    final bytes = await response.stream.toBytes();
    metric['status'] = response.statusCode;
    metric['responseBytes'] = bytes.length;
    if (dropPairAck &&
        op == 'crypto2.records.batch' &&
        types.contains('task') &&
        types.contains('financeEntry') &&
        response.statusCode == 200) {
      final data = (jsonDecode(utf8.decode(bytes)) as Map)['data'];
      check(
        data is Map && data['status'] == 'applied',
        'pair_fault_requires_real_applied_ack',
      );
      final row = (await client.db.rows(
        'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox WHERE partition=? AND request_id=?',
        [client.partition, command!['requestId']],
      )).single;
      final claims = await client.db.rows(
        'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=? ORDER BY scope_id,domain,record_id',
        [client.partition, command['requestId']],
      );
      final records = (command['payload']['records'] as List)
          .map(
            (p) => CryptoJson.decode(cryptoBase64(p['commandBase64'])) as Map,
          )
          .toList();
      check(
        records.every((r) => r['scopeId'] == client.lab.scope),
        'pair_fault_scope_binding',
      );
      check(
        records.any(
              (r) =>
                  r['type'] == 'task' &&
                  r['metadata']['identity']['canonicalId'] ==
                      client.lab.ledger['taskId'],
            ) &&
            records.any(
              (r) =>
                  r['type'] == 'financeEntry' &&
                  r['metadata']['identity']['canonicalId'] ==
                      client.lab.ledger['entryId'],
            ),
        'pair_fault_record_binding',
      );
      check(
        claims.isNotEmpty &&
            claims.length == records.length &&
            records.every(
              (r) => claims.any(
                (c) =>
                    c['scope_id'] == r['scopeId'] &&
                    c['domain'] == r['domain'] &&
                    c['record_id'] == r['id'] &&
                    c['expected_revision'] == r['expectedRevision'],
              ),
            ),
        'pair_fault_claim_binding',
      );
      check(
        row['state'] == 'pending' &&
            row['response'] == null &&
            row['request_hash'] == metric['requestHash'] &&
            row['signed_body'] == utf8.decode(CryptoJson.encode(params)),
        'pair_fault_exact_pending_binding',
      );
      dropPairAck = false;
      offline = true;
      client.lab.ledger['lostPair'] = {
        'requestId': command['requestId'],
        'requestHash': metric['requestHash'],
        'originalRow': row,
        'claims': claims,
        'realAppliedAck': true,
      };
      metric['fault'] = 'drop_pair_applied_ack';
      await client.lab.save();
      throw http.ClientException('synthetic_pair_ack_lost');
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      request: response.request,
      contentLength: bytes.length,
    );
  }

  @override
  void close() => delegate.close();
}

Future<void> _setup(_Lab lab) async {
  for (final actor in ['owner', 'member']) {
    await lab.step('crypto_$actor', () async {
      final c = await lab.open(actor);
      final rows = await c.db.rows(
        'SELECT phase FROM crypto_identity_secrets WHERE partition=?',
        [c.partition],
      );
      final f = File(
        '${lab.fixture['clientStateDirs'][actor]}/recovery.private',
      );
      if (rows.isEmpty) {
        final bytes = await c.account.prepareRecoveryFile();
        await f.writeAsBytes(bytes, flush: true);
        await c.account.verifyAndInitialize(bytes);
        bytes.fillRange(0, bytes.length, 0);
      } else if (rows.single['phase'] == 'prepared') {
        final bytes = await f.readAsBytes();
        await c.account.verifyAndInitialize(bytes);
        bytes.fillRange(0, bytes.length, 0);
      } else if (await c.account.localPhase() == 'pending') {
        await c.account.resume();
      }
      check(await c.account.localPhase() == 'ready', 'crypto_setup_not_ready');
    });
  }
  await lab.step('scope', () async {
    final a = await lab.open('owner');
    await a.sync();
    final codec = CryptoCodec(await SodiumInit.init());
    lab.ledger['scope'] ??= codec.randomId();
    lab.ledger['scopeRequest'] ??= codec.randomId();
    await lab.save();
    await a.repo.createScope(
      'Synthetic ${lab.scenario} project',
      kind: SharedScopeKind.project,
      id: lab.scope,
      requestId: lab.ledger['scopeRequest'],
    );
  });
  await lab.step('sharing', () async {
    final a = await lab.open('owner'), b = await lab.open('member');
    final sender = InviteCryptoRepository(a.access),
        receiver = InviteCryptoRepository(b.access);
    final codec = CryptoCodec(await SodiumInit.init());
    lab.ledger['inviteRequest'] ??= codec.randomId();
    await lab.save();
    lab.ledger['invitation'] ??= await sender.dispatch('invitations3.create', {
      'scopeId': lab.scope,
      'recipient':
          lab.fixture['accounts']['member']['session']['user']['username'],
      'role': 'member',
      'language': 'en',
      'requestId': lab.ledger['inviteRequest'],
    });
    await lab.save();
    final inv = lab.ledger['invitation'] as Map;
    final id = inv['invitation']['id'] as String;
    if (lab.ledger['accepted'] != true) {
      await receiver.accept(
        await receiver.inspect(token: inv['localToken']),
        actionId: id,
      );
      lab.ledger['accepted'] = true;
      await lab.save();
    }
    if (lab.ledger['admitted'] != true) {
      await sender.admit(
        await sender.acceptedRecipient(lab.scope, id),
        await ScopeCryptoManager(a.access).reviewRotation(lab.scope),
      );
      lab.ledger['admitted'] = true;
      await lab.save();
    }
    if (lab.ledger['resumed'] != true) {
      await receiver.resumeAccepted(id);
      lab.ledger['resumed'] = true;
      await lab.save();
    }
    await a.sync();
    await b.sync();
  });
}

Future<Map<String, Object?>> _signedEvidence(_Client c) async => {
  'requests': await c.db.rows(
    'SELECT * FROM crypto_business_requests WHERE partition=? AND scope_id=? ORDER BY operation_id',
    [c.partition, c.lab.scope],
  ),
  'claims': await c.db.rows(
    'SELECT * FROM crypto_outbox_records WHERE partition=? AND scope_id=? ORDER BY domain,record_id,expected_revision',
    [c.partition, c.lab.scope],
  ),
  'signed': await c.db.rows(
    'SELECT request_id,operation,signed_body,request_hash FROM crypto_outbox WHERE partition=? ORDER BY request_id',
    [c.partition],
  ),
};

Future<void> _preservedSigned(_Client c, Map before) async {
  for (final prior in before['signed'] as List) {
    final rows = await c.db.rows(
      'SELECT request_id,operation,signed_body,request_hash FROM crypto_outbox WHERE partition=? AND request_id=?',
      [c.partition, prior['request_id']],
    );
    check(
      rows.length == 1 && jsonEncode(rows.single) == jsonEncode(prior),
      'original_signed_request_changed',
    );
  }
  for (final prior in before['requests'] as List) {
    final rows = await c.db.rows(
      'SELECT * FROM crypto_business_requests WHERE partition=? AND operation_id=?',
      [c.partition, prior['operation_id']],
    );
    check(
      rows.length == 1 && jsonEncode(rows.single) == jsonEncode(prior),
      'original_reserved_intent_changed',
    );
  }
}

Future<void> _converged(
  _Lab lab,
  String id,
  String type, {
  String? title,
  int? amount,
}) async {
  final a = await lab.open('owner'), b = await lab.open('member');
  await a.sync(clean: false);
  await b.sync(clean: false);
  await a.sync(clean: false);
  final x = await a.canonical(id, type), y = await b.canonical(id, type);
  check(jsonEncode(x) == jsonEncode(y), 'canonical_clients_not_converged');
  if (title != null) {
    check((x['payload'] as Map)['title'] == title, 'resolved_title_wrong');
  }
  if (amount != null) {
    check(
      (x['payload'] as Map)['amountMinor'] == amount,
      'resolved_amount_wrong',
    );
  }
  check(x['deleted'] == 0, 'resolved_record_deleted');
}

Future<void> _l1Case(_Lab lab, bool local) async {
  final tag = local ? 'keep_local' : 'keep_remote';
  final state = lab.ledger.putIfAbsent(tag, () => <String, dynamic>{}) as Map;
  final a = await lab.open('owner'), b = await lab.open('member');
  await lab.step('$tag.prepare', () async {
    if (state['taskId'] == null) {
      check(state['createIntent'] != true, 'ambiguous_task_creation');
      state['createIntent'] = true;
      await lab.save();
      state['taskId'] = await a.repo.createTask(
        scopeId: lab.scope,
        title: 'Synthetic $tag base',
      );
      await lab.save();
    }
    await a.sync(clean: false);
    await b.sync(clean: false);
    final id = state['taskId'] as String;
    check(
      jsonEncode(await a.canonical(id, 'task')) ==
          jsonEncode(await b.canonical(id, 'task')),
      'initial_canonical_base_differs',
    );
  });
  final id = state['taskId'] as String;
  final winner = 'Synthetic $tag winner';
  final draft = 'Synthetic $tag draft';
  await lab.step('$tag.conflict', () async {
    if (state['draftsQueued'] != true) {
      await a.repo.updateTask(lab.scope, a.task(id).copyWith(title: winner));
      await b.repo.updateTask(lab.scope, b.task(id).copyWith(title: draft));
      state['draftsQueued'] = true;
      await lab.save();
    }
    if (state['winnerSynced'] != true) {
      await a.sync(clean: false);
      state['winnerSynced'] = true;
      await lab.save();
    }
    await b.sync(clean: false);
    final c = b.repo.state.conflicts.singleWhere((c) => c.recordId == id);
    state['conflictId'] = c.id;
    state['winnerCanonical'] = await a.canonical(id, 'task');
    state['losingDraft'] = {'id': id, 'title': b.task(id).title};
    state['beforeResolution'] = await _signedEvidence(b);
    state['conflictCalls'] = lab.calls
        .where((c) => c['actor'] == 'member')
        .toList();
    await lab.save();
    check(b.task(id).title == draft, 'losing_draft_not_retained');
  });
  await lab.step('$tag.resolve', () async {
    if (state['resolutionReturned'] != true) {
      check(
        state['resolutionStarted'] != true,
        'ambiguous_resolution_preserve_state',
      );
      state['resolutionStarted'] = true;
      await lab.save();
      await b.repo.resolveConflict(
        conflictId: state['conflictId'],
        keepLocal: local,
      );
      state['resolutionReturned'] = true;
      await lab.save();
    }
    try {
      await _converged(lab, id, 'task', title: local ? draft : winner);
    } finally {
      state['afterResolution'] = await _signedEvidence(b);
      await _preservedSigned(b, state['beforeResolution'] as Map);
      await lab.save();
    }
    final canon = await a.canonical(id, 'task');
    check(
      local
          ? (canon['cryptoRevision'] as int) >
                (state['winnerCanonical']['cryptoRevision'] as int)
          : canon['cryptoRevision'] ==
                state['winnerCanonical']['cryptoRevision'],
      'resolution_revision_wrong',
    );
    check(
      (await b.db.rows(
        'SELECT 1 FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
        [b.partition, lab.scope, id],
      )).isEmpty,
      'resolved_task_queue_not_empty',
    );
    check(
      !b.repo.state.conflicts.any((c) => c.recordId == id),
      'resolved_task_conflict_remains',
    );
  });
}

Future<void> _l1(_Lab lab) async {
  await _setup(lab);
  for (final local in [false, true]) {
    try {
      await _l1Case(lab, local);
    } catch (_) {
      if (!local) {
        lab.ledger['keep_local_blocked'] = 'earlier_partition_work_unresolved';
        await lab.save();
      }
      rethrow;
    }
  }
  lab.ledger.remove('keep_local_blocked');
  await (await lab.open('owner')).sync();
  await (await lab.open('member')).sync();
}

Future<void> _l2(_Lab lab) async {
  await _setup(lab);
  var a = await lab.open('owner');
  final b = await lab.open('member');
  await lab.step('finance_account', () async {
    await a.repo.refreshFinancePolicy(lab.scope);
    check(
      lab.ledger['accountIntent'] != true || lab.ledger['accountId'] != null,
      'ambiguous_account_creation',
    );
    if (lab.ledger['accountId'] == null) {
      lab.ledger['accountIntent'] = true;
      await lab.save();
      lab.ledger['accountId'] = await a.repo.createFinanceAccount(
        scopeId: lab.scope,
        name: 'Synthetic cost ledger',
        currency: 'EUR',
        openingBalanceMinor: 10000,
      );
      await lab.save();
    }
    await a.sync();
    await b.sync();
  });
  await lab.step('pair_applied_ack_interruption', () async {
    if (lab.ledger['lostPair'] == null) {
      if (lab.ledger['taskId'] == null) {
        check(
          lab.ledger['pairCreateIntent'] != true,
          'ambiguous_pair_creation',
        );
        lab.ledger['pairCreateIntent'] = true;
        final codec = CryptoCodec(await SodiumInit.init());
        lab.ledger['taskId'] = codec.randomId();
        await lab.save();
        final now = DateTime.now().toUtc();
        await a.repo.saveTaskWithCost(
          lab.scope,
          LocalTask(
            id: lab.ledger['taskId'],
            title: 'Synthetic paid task',
            projectId: null,
            notes: '',
            dueAt: now.add(const Duration(days: 2)),
            isCompleted: false,
            createdAt: now,
            updatedAt: now,
          ),
          isNew: true,
          cost: TaskCostDraft(
            amountMinor: 1000,
            ledgerAccountId: lab.ledger['accountId'],
            accountScopeSpecified: true,
            paid: true,
          ),
        );
        lab.ledger['entryId'] = a.repo.state
            .dataForScope(lab.scope)
            .financeEntries
            .single
            .id;
        await lab.save();
      }
      a.wire.dropPairAck = true;
      await a.sync(clean: false);
    }
    check(lab.ledger['lostPair'] != null, 'atomic_pair_fault_not_reached');
    final saved = lab.ledger['lostPair'] as Map;
    final row = (await a.db.rows(
      'SELECT request_id,request_hash,signed_body,state,response FROM crypto_outbox WHERE partition=? AND request_id=?',
      [a.partition, saved['requestId']],
    )).single;
    check(
      jsonEncode(row) == jsonEncode(saved['originalRow']),
      'interrupted_pair_request_changed',
    );
    check(row['state'] == 'pending', 'interrupted_pair_not_pending');
  });
  await lab.step('pair_restart_recovery', () async {
    await lab.restart('owner');
    a = await lab.open('owner');
    final lost = lab.ledger['lostPair'] as Map;
    final start = lab.calls.length;
    await a.sync();
    final exact = lab.calls
        .skip(start)
        .where((c) => c['requestId'] == lost['requestId'])
        .toList();
    check(
      exact.any(
        (c) => c['operation'] == 'crypto2.receipt.get' && c['status'] == 200,
      ),
      'pair_restart_real_receipt_required',
    );
    check(
      !exact.any((c) => c['operation'] == 'crypto2.records.batch'),
      'pair_restart_resent_applied_batch',
    );
    final row = (await a.db.rows(
      'SELECT request_hash,signed_body,state FROM crypto_outbox WHERE partition=? AND request_id=?',
      [a.partition, lost['requestId']],
    )).single;
    check(
      row['request_hash'] == lost['requestHash'] &&
          row['signed_body'] == lost['originalRow']['signed_body'],
      'original_pair_signature_changed',
    );
    final claims = await a.db.rows(
      'SELECT * FROM crypto_outbox_records WHERE partition=? AND request_id=? ORDER BY scope_id,domain,record_id',
      [a.partition, lost['requestId']],
    );
    check(
      jsonEncode(claims) == jsonEncode(lost['claims']),
      'original_pair_claims_changed',
    );
    await b.sync();
    await _converged(
      lab,
      lab.ledger['taskId'],
      'task',
      title: 'Synthetic paid task',
    );
    await _converged(lab, lab.ledger['entryId'], 'financeEntry', amount: 1000);
  });
  await lab.step('paired_conflict', () async {
    final task = lab.ledger['taskId'] as String;
    final entry = lab.ledger['entryId'] as String;
    if (lab.ledger['pairDraftsQueued'] != true) {
      for (final c in [a, b]) {
        final e = c.repo.state
            .dataForScope(lab.scope)
            .financeEntries
            .singleWhere((v) => v.id == entry);
        await c.repo.saveTaskWithCost(
          lab.scope,
          c
              .task(task)
              .copyWith(
                title: c.actor == 'owner'
                    ? 'Synthetic winning cost'
                    : 'Synthetic local cost',
              ),
          expectedFinanceRevision: e.revision,
          cost: TaskCostDraft(
            amountMinor: c.actor == 'owner' ? 2000 : 1500,
            ledgerAccountId: lab.ledger['accountId'],
            accountScopeSpecified: true,
            paid: true,
          ),
        );
      }
      lab.ledger['pairDraftsQueued'] = true;
      await lab.save();
    }
    if (lab.ledger['pairWinnerSynced'] != true) {
      await a.sync();
      lab.ledger['pairWinnerSynced'] = true;
      await lab.save();
    }
    await b.sync(clean: false);
    final f = b.repo.state.financeConflicts.singleWhere(
      (c) => c.recordId == entry,
    );
    final t = b.repo.state.conflicts.singleWhere((c) => c.recordId == task);
    lab.ledger['financeConflictId'] = f.id;
    lab.ledger['taskConflictId'] = t.id;
    await lab.save();
  });
  await lab.step('explicit_financial_review', () async {
    bool rejected = false;
    try {
      await b.repo.resolveConflict(
        conflictId: lab.ledger['taskConflictId'],
        keepLocal: true,
      );
    } on CollaborationException catch (e) {
      rejected = e.code == 'requires_finance_resolution';
    }
    check(rejected, 'ordinary_task_resolution_bypassed_financial_review');
    if (lab.ledger['financialResolutionReturned'] != true) {
      check(
        lab.ledger['financialResolutionStarted'] != true,
        'ambiguous_financial_resolution',
      );
      lab.ledger['financialResolutionStarted'] = true;
      await lab.save();
      await b.repo.resolveFinanceConflict(
        conflictId: lab.ledger['financeConflictId'],
        keepLocal: true,
      );
      lab.ledger['financialResolutionReturned'] = true;
      await lab.save();
    }
    await _converged(
      lab,
      lab.ledger['taskId'],
      'task',
      title: 'Synthetic local cost',
    );
    await _converged(lab, lab.ledger['entryId'], 'financeEntry', amount: 1500);
    for (final c in [a, b]) {
      await c.sync();
      final data = c.repo.state.dataForScope(lab.scope);
      check(
        data.financeEntries.length == 1 &&
            data.financeEntries.single.id == lab.ledger['entryId'] &&
            data.financeEntries.single.taskId == lab.ledger['taskId'],
        'duplicate_or_detached_task_cost',
      );
      final total = summarizeSharedFinance(
        accounts: data.financeAccounts,
        entries: data.financeEntries,
        transfers: data.financeTransfers,
      )['EUR'];
      check(
        total?.balanceMinor == BigInt.from(8500),
        'task_cost_balance_wrong',
      );
      check(
        total?.expenseMinor == BigInt.from(1500),
        'task_cost_expense_wrong',
      );
      check(
        (await c.db.rows('SELECT 1 FROM local_meta WHERE name LIKE ?', [
          'task_cost_pair:${c.partition}:%',
        ])).isEmpty,
        'orphan_pair_marker',
      );
      check(
        (await c.db.rows('SELECT 1 FROM outbox WHERE partition=?', [
          c.partition,
        ])).isEmpty,
        'orphan_task_half',
      );
      check(
        (await c.db.rows('SELECT 1 FROM finance_outbox WHERE partition=?', [
          c.partition,
        ])).isEmpty,
        'orphan_finance_half',
      );
    }
  });
}

void main() {
  final path = Platform.environment['JIVIE_SYNC_GAPS_FIXTURE'];
  final selected = Platform.environment['JIVIE_SYNC_GAPS_SCENARIO'];
  test(
    'isolated task resolution and linked finance recovery gap',
    () async {
      check(selected == 'L1' || selected == 'L2', 'explicit_scenario_required');
      final file = File(path!);
      final full = jsonDecode(await file.readAsString()) as Map;
      check(
        full['synthetic'] == true &&
            full['purpose'] == 'local-sync-resolution-cost-20261022' &&
            full['serverUrl'] == 'http://127.0.0.1:59778',
        'exact_new_gap_fixture_required',
      );
      final actorKeys = ['${selected}_owner', '${selected}_member'];
      check(
        actorKeys.every(
          (k) => full['accounts'][k]['session']['serverId'] == full['serverId'],
        ),
        'gap_server_identity',
      );
      final fixture = {
        ...full,
        'accounts': {
          'owner': full['accounts'][actorKeys[0]],
          'member': full['accounts'][actorKeys[1]],
        },
        'clientStateDirs': {
          'owner': full['clientStateDirs'][actorKeys[0]],
          'member': full['clientStateDirs'][actorKeys[1]],
        },
      };
      final ledgerFile = File(
        '${file.parent.path}/$selected-ledger-private.json',
      );
      final ledger = ledgerFile.existsSync()
          ? Map<String, dynamic>.from(
              jsonDecode(await ledgerFile.readAsString()) as Map,
            )
          : <String, dynamic>{};
      final lab = _Lab(file.parent, fixture, ledger, selected!);
      final priorPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message?.startsWith('GAP_EVENT ') == true) {
          priorPrint(message, wrapWidth: wrapWidth);
        }
      };
      try {
        if (selected == 'L1') {
          await _l1(lab);
        } else {
          await _l2(lab);
        }
        ledger['passed'] = true;
        await lab.save();
      } finally {
        await lab.close();
        debugPrint = priorPrint;
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
