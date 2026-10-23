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
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:sodium/sodium.dart';

import '../collaboration_repository_test.dart' show MemorySessionStore;

// New isolated v5 invitation cases; no prior test main or retained QA is invoked.
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
    if (state['passed'] == true || state['inheritedPassed'] == true) return;
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
  bool offline = false, dropAcceptAck = false, blockPublication = false;
  Map<String, dynamic>? forgedInvitationStatus;
  int offlineAttempts = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest base) async {
    if (offline) {
      offlineAttempts++;
      throw http.ClientException('synthetic_owner_offline');
    }
    final request = base as http.Request;
    final body = jsonDecode(request.body) as Map;
    final operation = body['op'] as String;
    final params = body['params'] as Map;
    final command = params['commandBase64'] is String
        ? CryptoJson.decode(cryptoBase64(params['commandBase64'])) as Map
        : null;
    final metric = <String, Object?>{
      'actor': client.actor,
      'operation': operation,
      'status': null,
      if (command != null) 'requestId': command['requestId'],
      if (command != null)
        'requestHash': await cryptoSha256(CryptoJson.encode(params)),
    };
    client.lab.calls.add(metric);
    if (blockPublication &&
        operation == 'crypto2.invitations.publishPreauthorization') {
      blockPublication = false;
      offline = true;
      metric['fault'] = 'publication_blocked_before_http';
      client.lab.ledger['blockedPublication'] = {
        'requestId': metric['requestId'],
        'requestHash': metric['requestHash'],
        'invitationId': command!['payload']['invitationId'],
        'preauthorizationHeadHash':
            command['payload']['preauthorizationHeadHash'],
        'childHeads': command['payload']['childHeads'],
      };
      await client.lab.save();
      throw http.ClientException('synthetic_publication_outage');
    }
    final response = await delegate.send(request);
    var bytes = await response.stream.toBytes();
    var deliveredStatus = response.statusCode;
    metric['status'] = response.statusCode;
    if (response.statusCode >= 400) {
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        final code = decoded is Map && decoded['error'] is Map
            ? decoded['error']['code']
            : null;
        if (code is String && RegExp(r'^[a-z0-9_]+$').hasMatch(code)) {
          metric['code'] = code;
        }
      } on FormatException {
        // Keep only bounded error codes; response bodies stay private.
      }
    }
    if (operation == 'crypto2.invitations.status' &&
        forgedInvitationStatus != null) {
      bytes = utf8.encode(jsonEncode({'v': 1, 'data': forgedInvitationStatus}));
      deliveredStatus = 200;
      metric['fault'] = 'false_consumed_without_own_consent';
      metric['injectedClientVisibleStatus'] = deliveredStatus;
    }
    if (dropAcceptAck &&
        operation == 'crypto2.invitations.accept' &&
        response.statusCode == 200) {
      dropAcceptAck = false;
      offline = true;
      metric['fault'] = 'lost_real_accept_ack';
      client.lab.ledger['lostAccept'] = {
        'requestId': metric['requestId'],
        'requestHash': metric['requestHash'],
        'actualHttp200': true,
      };
      await client.lab.save();
      throw http.ClientException('synthetic_accept_ack_lost');
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      deliveredStatus,
      headers: response.headers,
      request: response.request,
      contentLength: bytes.length,
    );
  }

  @override
  void close() => delegate.close();
}

Future<void> _initialize(_Lab lab) async {
  for (final actor in ['owner', 'member']) {
    await lab.step('account_$actor', () async {
      final client = await lab.open(actor);
      final path = '${lab.fixture['clientStateDirs'][actor]}/recovery.private';
      final file = File(path);
      final rows = await client.db.rows(
        'SELECT phase FROM crypto_identity_secrets WHERE partition=?',
        [client.partition],
      );
      if (rows.isEmpty) {
        final bytes = await client.account.prepareRecoveryFile();
        await file.writeAsBytes(bytes, flush: true);
        await client.account.verifyAndInitialize(bytes);
        bytes.fillRange(0, bytes.length, 0);
      } else if (rows.single['phase'] == 'prepared') {
        final bytes = await file.readAsBytes();
        await client.account.verifyAndInitialize(bytes);
        bytes.fillRange(0, bytes.length, 0);
      } else if (await client.account.localPhase() == 'pending') {
        await client.account.resume();
      }
      check(await client.account.localPhase() == 'ready', 'account_not_ready');
    });
  }
}

Future<void> _createScope(
  _Lab lab,
  String actor,
  String key, {
  String kind = 'project',
  String? parentKey,
}) async {
  await lab.step('create_$key', () async {
    final client = await lab.open(actor);
    final codec = client.account.directory.reducer.crypto;
    lab.ledger[key] ??= codec.randomId();
    lab.ledger['${key}Request'] ??= codec.randomId();
    await lab.save();
    final metadata = await client.db.rows(
      'SELECT record_proof_hash FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND type=?',
      [client.partition, lab.ledger[key], 'content', 'scopeMetadata'],
    );
    // Ordinary fresh sync establishes the same precondition as the real app.
    // A partial previous create resumes its derived root, never a second scope.
    await client.sync();
    if (metadata.isNotEmpty) {
      await client.runtime.ensureNativeProjectRoot(
        lab.ledger[key],
        parentKey == null ? null : lab.ledger[parentKey],
      );
      final resumed = await client.db.rows(
        'SELECT record_proof_hash FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND type=?',
        [client.partition, lab.ledger[key], 'content', 'scopeMetadata'],
      );
      check(
        resumed.length == 1 &&
            resumed.single['record_proof_hash'] ==
                metadata.single['record_proof_hash'],
        'scope_resume_changed_original_metadata',
      );
      return;
    }
    await client.runtime.createScope({
      'id': lab.ledger[key],
      'kind': kind,
      if (parentKey != null) 'parentScopeId': lab.ledger[parentKey],
      'name': 'Synthetic preauthorized $key',
      'requestId': lab.ledger['${key}Request'],
    });
  });
}

Future<void> _publishHistory(_Lab lab, String actor, String scopeKey) async {
  await lab.step('history_$scopeKey', () async {
    final client = await lab.open(actor);
    final codec = client.account.directory.reducer.crypto;
    lab.ledger['${scopeKey}Record'] ??= codec.randomId();
    lab.ledger['${scopeKey}Operation'] ??= codec.randomId();
    await lab.save();
    final raw =
        Map<String, dynamic>.from(
            LocalProject(
              id: lab.ledger['${scopeKey}Record'],
              title: 'Preserved $scopeKey content',
              description: 'Synthetic local invitation test',
              createdAt: DateTime.utc(2026, 10, 23),
              updatedAt: DateTime.utc(2026, 10, 23),
              area: ProjectArea.home,
            ).toJson(),
          )
          ..remove('id')
          ..remove('revision')
          ..remove('createdByAccountId')
          ..remove('updatedByAccountId');
    await client.runtime.publishRaw(
      scopeId: lab.ledger[scopeKey],
      id: lab.ledger['${scopeKey}Record'],
      type: 'project',
      operationId: lab.ledger['${scopeKey}Operation'],
      expectedRevision: 0,
      rawPayload: raw,
      localHash: await CryptoBusinessJson.hash(raw),
    );
  });
}

Future<void> _prepare(_Lab lab) async {
  if (const {'tamper', 'graph_send_restart'}.contains(lab.scenario) &&
      lab.ledger['preparationSource'] == null) {
    final sourceBytes = await File(
      '${lab.root.path}/revoke-ledger-private.json',
    ).readAsBytes();
    final source = jsonDecode(utf8.decode(sourceBytes)) as Map;
    const inherited = [
      'account_owner',
      'account_member',
      'create_otherSpace',
      'history_otherSpace',
      'existing_recipient_workspace',
    ];
    check(
      inherited.every((step) => source['steps'][step]?['passed'] == true),
      'case_requires_existing_l2_workspace',
    );
    for (final key in [
      'otherSpace',
      'otherSpaceRecord',
      'otherSpaceOperation',
      'otherSpaceRequest',
      'otherSpaceHash',
      'recipientDeviceId',
    ]) {
      check(source[key] != null, 'l2_preparation_reference_missing');
      lab.ledger[key] = source[key];
    }
    lab.ledger['steps'] = <String, dynamic>{
      for (final step in inherited)
        step: <String, dynamic>{
          'inheritedPassed': true,
          'sourceScenario': 'revoke',
          'sourceStep': step,
        },
    };
    lab.ledger['preparationSource'] = {
      'scenario': 'revoke',
      'sha256': await cryptoSha256(sourceBytes),
      'scopeAndInvitationInherited': false,
    };
    await lab.save();
  }
  if (lab.scenario == 'ack' && lab.ledger['preparationSource'] == null) {
    final sourceFile = File('${lab.root.path}/main-ledger-private.json');
    final sourceBytes = await sourceFile.readAsBytes();
    final source = jsonDecode(utf8.decode(sourceBytes)) as Map;
    const inherited = [
      'account_owner',
      'account_member',
      'create_otherSpace',
      'history_otherSpace',
      'existing_recipient_workspace',
      'create_scope',
      'history_scope',
      'send_verified_email',
    ];
    check(
      inherited.every((step) => source['steps'][step]?['passed'] == true),
      'ack_requires_existing_prepared_main_invitation',
    );
    for (final key in [
      'scope',
      'scopeRecord',
      'scopeOperation',
      'scopeRequest',
      'otherSpace',
      'otherSpaceRecord',
      'otherSpaceOperation',
      'otherSpaceRequest',
      'otherSpaceHash',
      'recipientDeviceId',
      'sendRequest',
      'mailAtSend',
      'invitationId',
      'publishedHeadHash',
    ]) {
      check(source[key] != null, 'ack_preparation_reference_missing');
      lab.ledger[key] = source[key];
    }
    lab.ledger['steps'] = <String, dynamic>{
      for (final step in inherited)
        step: <String, dynamic>{
          'inheritedPassed': true,
          'sourceScenario': 'main',
          'sourceStep': step,
        },
    };
    lab.ledger['preparationSource'] = {
      'scenario': 'main',
      'sha256': await cryptoSha256(sourceBytes),
      'acceptancePreviouslyAttempted': false,
    };
    await lab.save();
  }
  await _initialize(lab);
  await _createScope(lab, 'member', 'otherSpace');
  await _publishHistory(lab, 'member', 'otherSpace');
  await lab.step('existing_recipient_workspace', () async {
    final member = await lab.open('member');
    await member.sync();
    await member.repo.selectSpace(lab.ledger['otherSpace']);
    final existing = await member.runtime.record(
      lab.ledger['otherSpace'],
      'content',
      lab.ledger['otherSpaceRecord'],
    );
    check(existing != null, 'existing_recipient_content_missing');
    lab.ledger['otherSpaceHash'] = await cryptoSha256(
      utf8.encode(existing!['raw_payload'] as String),
    );
    lab.ledger['recipientDeviceId'] = member.session.profile.deviceId;
    check(
      await member.account.localPhase() == 'ready',
      'existing_account_not_ready',
    );
  });
  await _createScope(
    lab,
    'owner',
    'scope',
    kind: lab.scenario == 'graph_send_restart' ? 'organization' : 'project',
  );
  await _publishHistory(lab, 'owner', 'scope');
  if (lab.scenario == 'graph_send_restart') {
    await _createScope(lab, 'owner', 'childScope', parentKey: 'scope');
    await _publishHistory(lab, 'owner', 'childScope');
    return;
  }
  await lab.step('send_verified_email', () async {
    final owner = await lab.open('owner');
    lab.ledger['sendRequest'] ??= owner.account.directory.reducer.crypto
        .randomId();
    await lab.save();
    final sent = await owner.repo.createRecipientInvitation(
      scopeId: lab.scope,
      recipient: lab.fixture['accounts']['member']['email'],
      role: SharedRole.member,
      requestId: lab.ledger['sendRequest'],
      language: 'en',
      accessScope: 'project',
    );
    check(sent.deliveryQueued, 'prepared_email_missing_confirmed_queue_state');
    final queue = await Process.run('docker', [
      'exec',
      'jivie-invitation-preauth-lab-20261023',
      'php',
      '-r',
      r'''
if (!preg_match('/^[a-f0-9-]{36}$/D', $argv[1])) exit(2);
$pdo = new PDO('sqlite:/var/www/app/data/db.sqlite', null, null, [PDO::ATTR_TIMEOUT => 5]);
$pdo->exec('PRAGMA query_only=ON');
$q = $pdo->prepare('SELECT state,token_cipher IS NOT NULL AS hasCipher FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?');
$q->execute([$argv[1]]);
echo json_encode($q->fetch(PDO::FETCH_ASSOC), JSON_THROW_ON_ERROR);
''',
      '--',
      sent.id,
    ]).timeout(const Duration(seconds: 15));
    check(queue.exitCode == 0, 'owned_mail_metadata_read_failed');
    final mail = jsonDecode(queue.stdout as String) as Map;
    check(
      mail['state'] == 'pending' && mail['hasCipher'] == 1,
      'published_mail_not_queued',
    );
    lab.ledger['mailAtSend'] = mail;
    lab.ledger['invitationId'] = sent.id;
    final member = await lab.open('member');
    final displayed = await owner.runtime.members(lab.scope);
    check(
      !(displayed['members'] as List).cast<Map>().any(
        (row) => row['accountId'] == member.session.profile.accountId,
      ),
      'unaccepted_recipient_displayed_as_current_member',
    );
    final invite = await InviteCryptoRepository(
      member.access,
    ).inspect(invitationId: sent.id);
    final command =
        CryptoJson.decode(cryptoBase64(invite.authorization['commandBase64']))
            as Map;
    check(
      command['payload']['preauthorization'] is Map,
      'send_did_not_preauthorize_existing_email',
    );
    check(
      invite.response['preauthorizationHeadHash'] is String,
      'send_not_fully_published',
    );
    check(
      command['payload']['recipient']['accountId'] ==
          member.session.profile.accountId,
      'verified_email_account_binding',
    );
    lab.ledger['publishedHeadHash'] =
        invite.response['preauthorizationHeadHash'];
  });
}

Future<void> _assertPreservedAndReadable(_Lab lab, _Client member) async {
  await member.runtime.pullVerified(lab.scope, 'content');
  final received = await member.runtime.record(
    lab.scope,
    'content',
    lab.ledger['scopeRecord'],
  );
  check(received != null, 'target_content_not_decrypted');
  check(
    (jsonDecode(received!['raw_payload'] as String) as Map)['title'] ==
        'Preserved scope content',
    'target_content_changed',
  );
  final existing = await member.runtime.record(
    lab.ledger['otherSpace'],
    'content',
    lab.ledger['otherSpaceRecord'],
  );
  check(
    existing != null &&
        await cryptoSha256(utf8.encode(existing['raw_payload'] as String)) ==
            lab.ledger['otherSpaceHash'],
    'other_space_content_changed',
  );
  check(
    member.session.profile.deviceId == lab.ledger['recipientDeviceId'],
    'recipient_session_changed',
  );
  check(
    await member.account.localPhase() == 'ready',
    'recipient_account_setup_changed',
  );
  await member.sync();
  await member.repo.selectSpace(lab.scope);
  check(member.repo.state.selectedSpaceId == lab.scope, 'target_not_selected');
  check(
    member.repo.state.scopes.any(
      (s) => s.id == lab.ledger['otherSpace'] && s.canRead,
    ),
    'other_space_removed',
  );
}

Future<Map<String, dynamic>> _mailMetadata(String invitationId) async {
  final result = await Process.run('docker', [
    'exec',
    'jivie-invitation-preauth-lab-20261023',
    'php',
    '-r',
    r'''
if (!preg_match('/^[a-f0-9-]{36}$/D', $argv[1])) exit(2);
$pdo = new PDO('sqlite:/var/www/app/data/db.sqlite', null, null, [PDO::ATTR_TIMEOUT => 5]);
$pdo->exec('PRAGMA query_only=ON');
$q = $pdo->prepare('SELECT state,token_cipher IS NOT NULL AS hasCipher FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?');
$q->execute([$argv[1]]);
echo json_encode($q->fetch(PDO::FETCH_ASSOC), JSON_THROW_ON_ERROR);
''',
    '--',
    invitationId,
  ]).timeout(const Duration(seconds: 15));
  check(result.exitCode == 0, 'owned_graph_mail_metadata_read_failed');
  return Map<String, dynamic>.from(jsonDecode(result.stdout as String) as Map);
}

Future<Map<String, dynamic>> _ownerPreparationFingerprint(
  _Lab lab,
  _Client owner,
) async {
  final params = [owner.partition, lab.scope, lab.ledger['childScope']];
  final heads = await owner.db.rows(
    'SELECT scope_id,head_hash,generation,epoch,body,authorization FROM crypto_scope_heads WHERE partition=? AND scope_id IN (?,?) ORDER BY scope_id,generation,head_hash',
    params,
  );
  final keys = await owner.db.rows(
    'SELECT scope_id,domain,epoch_id,key_id,key_bytes,grant,scope_head_hash FROM crypto_scope_keys WHERE partition=? AND scope_id IN (?,?) ORDER BY scope_id,domain,epoch_id,key_id',
    params,
  );
  final requests = await owner.db.rows(
    'SELECT scope_id,intent_id,authorization FROM crypto_membership_intents WHERE partition=? AND scope_id IN (?,?) AND authorization IS NOT NULL ORDER BY scope_id,intent_id',
    params,
  );
  final drafts = await owner.db.rows(
    'SELECT action_id,payload,token FROM crypto_invitation_drafts WHERE partition=? ORDER BY action_id',
    [owner.partition],
  );
  check(
    heads.isNotEmpty &&
        keys.length >= 4 &&
        requests.isNotEmpty &&
        drafts.isNotEmpty,
    'prepared_graph_evidence_missing',
  );
  // Key bytes and delivery secrets remain in the private database. Only their
  // complete canonical digests leave this function.
  return {
    'heads': await cryptoSha256(CryptoJson.encode(heads)),
    'keys': await cryptoSha256(CryptoJson.encode(keys)),
    'requests': await cryptoSha256(CryptoJson.encode(requests)),
    'drafts': await cryptoSha256(CryptoJson.encode(drafts)),
    'headCount': heads.length,
    'keyCount': keys.length,
    'requestCount': requests.length,
    'draftCount': drafts.length,
  };
}

Future<void> _runGraphSendRestart(_Lab lab) async {
  var owner = await lab.open('owner');
  final member = await lab.open('member');
  await lab.step('graph_policy3_descriptors', () async {
    final parent = await owner.access.verifiedScopeDescriptor(
      lab.scope,
      online: true,
    );
    final child = await owner.access.verifiedScopeDescriptor(
      lab.ledger['childScope'],
      online: true,
    );
    check(
      parent['kind'] == 'organization' &&
          parent['accessPolicyVersion'] == 3 &&
          child['kind'] == 'project' &&
          child['accessPolicyVersion'] == 3 &&
          child['parentScopeToken'] is String,
      'graph_policy3_descriptors_not_verified',
    );
  });
  await lab.step('graph_prepared_publication_outage', () async {
    lab.ledger['sendRequest'] ??= owner.account.directory.reducer.crypto
        .randomId();
    await lab.save();
    if (lab.ledger['blockedPublication'] == null) {
      owner.wire.blockPublication = true;
      try {
        await owner.repo.createRecipientInvitation(
          scopeId: lab.scope,
          recipient: lab.fixture['accounts']['member']['email'],
          role: SharedRole.member,
          requestId: lab.ledger['sendRequest'],
          language: 'en',
          accessScope: 'space',
        );
        throw StateError('publication_outage_not_injected');
      } catch (error) {
        if (lab.ledger['blockedPublication'] == null) rethrow;
      }
    }
    final blocked = lab.ledger['blockedPublication'] as Map;
    lab.ledger['invitationId'] = blocked['invitationId'];
    lab.ledger['publishedHeadHash'] = blocked['preauthorizationHeadHash'];
    final children = (blocked['childHeads'] as List).cast<Map>();
    check(
      children.length == 1 &&
          children.single['scopeId'] == lab.ledger['childScope'],
      'publication_did_not_prepare_exact_child',
    );
    for (final target in [
      {'scopeId': lab.scope, 'headHash': blocked['preauthorizationHeadHash']},
      children.single,
    ]) {
      final heads = await owner.db.rows(
        'SELECT body FROM crypto_scope_heads WHERE partition=? AND scope_id=? AND head_hash=?',
        [owner.partition, target['scopeId'], target['headHash']],
      );
      check(heads.length == 1, 'publication_prepared_head_not_retained');
      final body =
          jsonDecode(utf8.decode((heads.single['body'] as List).cast<int>()))
              as Map;
      check(
        (body['invitationPreauthorizations'] as List).cast<Map>().any(
          (m) => m['invitationId'] == blocked['invitationId'],
        ),
        'publication_head_missing_invitation_marker',
      );
    }
    final mail = await _mailMetadata(lab.ledger['invitationId']);
    check(
      mail['state'] == 'held' && mail['hasCipher'] == 1,
      'graph_mail_released_before_publication',
    );
    lab.ledger['heldMail'] = mail;
    lab.ledger['preRestartPreparation'] = await _ownerPreparationFingerprint(
      lab,
      owner,
    );
  });
  await lab.step('graph_explicit_same_send_after_restart', () async {
    await lab.restart('owner');
    owner = await lab.open('owner');
    check(
      await owner.account.localPhase() == 'ready',
      'owner_restart_required_setup',
    );
    lab.ledger['retrySendRequest'] ??= owner.account.directory.reducer.crypto
        .randomId();
    check(
      lab.ledger['retrySendRequest'] != lab.ledger['sendRequest'],
      'retry_must_use_new_ui_request_id',
    );
    await lab.save();
    final start = lab.calls.length;
    final sent = await owner.repo.createRecipientInvitation(
      scopeId: lab.scope,
      recipient: lab.fixture['accounts']['member']['email'],
      role: SharedRole.member,
      requestId: lab.ledger['retrySendRequest'],
      language: 'en',
      accessScope: 'space',
    );
    check(
      sent.id == lab.ledger['invitationId'] && sent.deliveryQueued,
      'explicit_retry_replaced_invitation_or_did_not_queue_mail',
    );
    final after = await _ownerPreparationFingerprint(lab, owner);
    check(
      jsonEncode(after) == jsonEncode(lab.ledger['preRestartPreparation']),
      'explicit_retry_changed_prepared_keys_heads_drafts_or_requests',
    );
    check(
      !lab.calls
          .skip(start)
          .any(
            (call) => const {
              'crypto2.invitations.create',
              'crypto2.invitations.resend',
              'crypto2.scope.headPut',
              'crypto2.grants.put',
            }.contains(call['operation']),
          ),
      'explicit_retry_recreated_preparation',
    );
    final publications = lab.calls
        .skip(start)
        .where(
          (call) =>
              call['operation'] ==
                  'crypto2.invitations.publishPreauthorization' &&
              call['status'] == 200,
        )
        .toList();
    check(
      publications.length == 1 &&
          publications.single['requestId'] ==
              lab.ledger['blockedPublication']['requestId'] &&
          publications.single['requestHash'] ==
              lab.ledger['blockedPublication']['requestHash'],
      'explicit_retry_changed_original_publication_request',
    );
    final mail = await _mailMetadata(sent.id);
    check(
      mail['state'] == 'pending' && mail['hasCipher'] == 1,
      'graph_mail_not_queued_after_publication',
    );
    lab.ledger['publishedMail'] = mail;
  });
  await lab.step('graph_preaccept_parent_and_child_denied', () async {
    for (final scope in [lab.scope, lab.ledger['childScope']]) {
      var denied = false;
      try {
        await member.account.directory.call('crypto2.records.pull', {
          'scopeId': scope,
          'domain': 'content',
          'accessRevision': 0,
          'cursor': 0,
          'limit': 20,
        });
      } on CollaborationApiException catch (error) {
        denied =
            error.code == 'permission_revoked' &&
            lab.calls.last['status'] == 403;
      }
      check(denied, 'unaccepted_graph_content_not_denied');
    }
  });
  final beforeOwner = lab.calls
      .where((call) => call['actor'] == 'owner')
      .length;
  owner.wire.offline = true;
  await lab.step('graph_accept_and_read_child_owner_offline', () async {
    final receiver = InviteCryptoRepository(member.access);
    final invite = await receiver.inspect(
      invitationId: lab.ledger['invitationId'],
    );
    await receiver.accept(invite, actionId: lab.ledger['invitationId']);
    check(
      await receiver.resumeAccepted(lab.ledger['invitationId']) == lab.scope,
      'graph_accepted_scope_not_active',
    );
    await _assertPreservedAndReadable(lab, member);
    await member.runtime.pullVerified(lab.ledger['childScope'], 'content');
    final child = await member.runtime.record(
      lab.ledger['childScope'],
      'content',
      lab.ledger['childScopeRecord'],
    );
    check(
      child != null &&
          (jsonDecode(child['raw_payload'] as String) as Map)['title'] ==
              'Preserved childScope content',
      'inherited_child_content_not_decrypted',
    );
    check(
      owner.wire.offlineAttempts == 0 &&
          lab.calls.where((call) => call['actor'] == 'owner').length ==
              beforeOwner,
      'owner_work_after_graph_send',
    );
  });
}

Future<void> _runCase(_Lab lab) async {
  await _prepare(lab);
  if (lab.scenario == 'graph_send_restart') return _runGraphSendRestart(lab);
  final owner = await lab.open('owner');
  var member = await lab.open('member');
  var receiver = InviteCryptoRepository(member.access);
  if (lab.scenario == 'main') {
    await lab.step('preaccept_denied', () async {
      var denied = false;
      try {
        await member.account.directory.call('crypto2.records.pull', {
          'scopeId': lab.scope,
          'domain': 'content',
          'accessRevision': 0,
          'cursor': 0,
          'limit': 20,
        });
      } on CollaborationApiException catch (error) {
        denied =
            error.code == 'permission_revoked' &&
            lab.calls.last['status'] == 403;
      }
      check(denied, 'preaccept_exact_permission_denial_missing');
    });
  }
  if (lab.scenario == 'revoke') {
    await lab.step('revoke_before_accept', () async {
      await owner.repo.revokeInvitation(lab.scope, lab.ledger['invitationId']);
    });
  }
  final beforeOwner = lab.calls.where((c) => c['actor'] == 'owner').length;
  owner.wire.offline = true;
  await lab.step('owner_offline_${lab.scenario}', () async {
    if (lab.scenario == 'revoke') {
      var rejected = false;
      try {
        await receiver.inspect(invitationId: lab.ledger['invitationId']);
      } on CollaborationApiException catch (error) {
        rejected = error.code == 'invitation_invalid';
      }
      check(rejected, 'revoked_invitation_still_usable');
    } else {
      if (lab.scenario == 'tamper') {
        if (lab.ledger['tamperedAcceptReceiptHash'] == null) {
          final invite = await receiver.inspect(
            invitationId: lab.ledger['invitationId'],
          );
          invite.response['preauthorizationHeadHash'] = 'f' * 64;
          Future<List<Map<String, dynamic>>>
          rejectedRequest() => member.db.rows(
            'SELECT i.intent_id,i.authorization,i.payload,i.state FROM crypto_membership_intents i JOIN crypto_membership_action_keys a ON a.partition=i.partition AND a.scope_id=i.scope_id AND a.request_id=i.intent_id WHERE i.partition=? AND i.scope_id=? AND a.action_key=?',
            [
              member.partition,
              lab.scope,
              'accept:${lab.ledger['invitationId']}',
            ],
          );
          var requests = await rejectedRequest();
          if (requests.isEmpty) {
            try {
              await receiver.accept(
                invite,
                actionId: lab.ledger['invitationId'],
              );
            } on CryptoAuthorityPending catch (error) {
              if (error.reason != 'scope_reauthorization_required') rethrow;
            } on CollaborationException catch (error) {
              if (error.code != 'crypto_invitation_preparation_pending') {
                rethrow;
              }
            }
            requests = await rejectedRequest();
          }
          check(requests.length == 1, 'tampered_accept_journal_missing');
          final rejected = requests.single;
          final proof =
              jsonDecode(
                    utf8.decode(
                      (rejected['authorization'] as List).cast<int>(),
                    ),
                  )
                  as Map;
          final command =
              CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
          final receipt =
              (jsonDecode(
                        utf8.decode((rejected['payload'] as List).cast<int>()),
                      )
                      as Map)['receipt']
                  as Map;
          check(
            rejected['state'] == 'rejected' &&
                receipt['status'] == 409 &&
                receipt['response']['errorCode'] ==
                    'crypto_invitation_preparation_pending' &&
                receipt['requestId'] == rejected['intent_id'] &&
                receipt['requestHash'] ==
                    await cryptoSha256(cryptoBase64(proof['commandBase64'])) &&
                base64Encode(CryptoJson.encode(receipt['authorization'])) ==
                    base64Encode(
                      (rejected['authorization'] as List).cast<int>(),
                    ) &&
                command['payload']['invitationId'] ==
                    lab.ledger['invitationId'] &&
                command['payload']['scopeId'] == lab.scope &&
                command['payload']['preauthorizationHeadHash'] == 'f' * 64,
            'tampered_published_head_not_exactly_rejected',
          );
          lab.ledger['tamperedAcceptReceiptHash'] = await cryptoSha256(
            CryptoJson.encode(receipt),
          );
          check(
            await receiver.resumeAccepted(lab.ledger['invitationId']) == null,
            'tampered_consent_activated_scope',
          );
        }
        final anchors = await member.db.rows(
          'SELECT state FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
          [member.partition, lab.scope, lab.ledger['invitationId']],
        );
        check(
          anchors.length == 1 &&
              anchors.single['state'] == 'invitationPendingAnchor',
          'tamper_pending_anchor_missing',
        );
        final start = lab.calls.length;
        member.wire.forgedInvitationStatus = {
          'state': 'consumed',
          'admissionMode': 'preauthorized',
          'scope': {'id': lab.scope},
          'activatedHeadHash': lab.ledger['publishedHeadHash'],
        };
        var consentRequired = false;
        try {
          await receiver.resumeAccepted(lab.ledger['invitationId']);
        } on CryptoAuthorityPending catch (error) {
          consentRequired = error.reason == 'invitation_acceptance_pending';
        } finally {
          member.wire.forgedInvitationStatus = null;
        }
        check(consentRequired, 'false_consumed_status_bypassed_own_consent');
        check(
          lab.calls
              .skip(start)
              .every(
                (call) => call['operation'] == 'crypto2.invitations.status',
              ),
          'false_consumed_status_reached_scope_or_keys',
        );
      } else {
        final recoveringLostAck =
            lab.scenario == 'ack' && lab.ledger['lostAccept'] != null;
        if (!recoveringLostAck) {
          final invite = await receiver.inspect(
            invitationId: lab.ledger['invitationId'],
          );
          if (lab.scenario == 'ack') member.wire.dropAcceptAck = true;
          try {
            await receiver.accept(invite, actionId: lab.ledger['invitationId']);
          } catch (_) {
            if (lab.scenario != 'ack' || lab.ledger['lostAccept'] == null) {
              rethrow;
            }
          }
        }
        if (lab.scenario == 'ack') {
          check(
            lab.ledger['lostAccept']?['actualHttp200'] == true,
            'actual_accept_ack_not_lost',
          );
          final original = await member.db.rows(
            'SELECT i.authorization,a.action_key FROM crypto_membership_intents i JOIN crypto_membership_action_keys a ON a.partition=i.partition AND a.scope_id=i.scope_id AND a.request_id=i.intent_id WHERE i.partition=? AND i.scope_id=? AND i.intent_id=?',
            [
              member.partition,
              lab.scope,
              lab.ledger['lostAccept']['requestId'],
            ],
          );
          check(original.length == 1, 'lost_accept_original_request_missing');
          final bytes = (original.single['authorization'] as List).cast<int>();
          check(
            await cryptoSha256(bytes) ==
                    lab.ledger['lostAccept']['requestHash'] &&
                original.single['action_key'] ==
                    'accept:${lab.ledger['invitationId']}',
            'lost_accept_original_authorization_substituted',
          );
          lab.ledger['lostAcceptOriginal'] ??= {
            'authorizationBase64': base64Encode(bytes),
            'actionKey': original.single['action_key'],
            'requestId': lab.ledger['lostAccept']['requestId'],
            'commandHash': await cryptoSha256(
              cryptoBase64(
                (jsonDecode(utf8.decode(bytes)) as Map)['commandBase64'],
              ),
            ),
          };
          await lab.save();
          await lab.restart('member');
          member = await lab.open('member');
          receiver = InviteCryptoRepository(member.access);
          check(
            await member.account.localPhase() == 'ready',
            'restart_required_new_account_setup',
          );
        }
        final target = await receiver.resumeAccepted(
          lab.ledger['invitationId'],
        );
        check(
          target == lab.scope,
          'accepted_scope_not_cryptographically_active',
        );
        await _assertPreservedAndReadable(lab, member);
        if (lab.scenario == 'ack') {
          final continued = await member.db.rows(
            'SELECT i.authorization,i.payload,i.state,a.action_key FROM crypto_membership_intents i JOIN crypto_membership_action_keys a ON a.partition=i.partition AND a.scope_id=i.scope_id AND a.request_id=i.intent_id WHERE i.partition=? AND i.scope_id=? AND i.intent_id=?',
            [
              member.partition,
              lab.scope,
              lab.ledger['lostAccept']['requestId'],
            ],
          );
          check(continued.length == 1, 'accept_restart_journal_missing');
          final row = continued.single;
          final original = lab.ledger['lostAcceptOriginal'] as Map;
          final receipt =
              (jsonDecode(utf8.decode((row['payload'] as List).cast<int>()))
                      as Map)['receipt']
                  as Map;
          check(
            row['state'] == 'confirmed' &&
                base64Encode((row['authorization'] as List).cast<int>()) ==
                    original['authorizationBase64'] &&
                row['action_key'] == original['actionKey'] &&
                receipt['requestId'] == original['requestId'] &&
                receipt['requestHash'] == original['commandHash'] &&
                receipt['status'] == 200 &&
                base64Encode(CryptoJson.encode(receipt['authorization'])) ==
                    original['authorizationBase64'],
            'accept_restart_changed_original_request_or_receipt',
          );
          lab.ledger['recoveredAcceptReceiptHash'] = await cryptoSha256(
            CryptoJson.encode(receipt),
          );
          final sends = lab.calls
              .where(
                (c) =>
                    c['actor'] == 'member' &&
                    c['operation'] == 'crypto2.invitations.accept' &&
                    c['status'] == 200,
              )
              .toList();
          check(
            sends.length == (recoveringLostAck ? 0 : 1),
            'lost_accept_ack_resent_signed_request',
          );
        }
      }
    }
    check(owner.wire.offlineAttempts == 0, 'owner_work_attempted_after_send');
    check(
      lab.calls.where((c) => c['actor'] == 'owner').length == beforeOwner,
      'owner_http_after_send',
    );
  });
}

void main() {
  final path = Platform.environment['JIVIE_PREAUTH_INVITATION_FIXTURE'];
  final scenario = Platform.environment['JIVIE_PREAUTH_INVITATION_CASE'];
  test(
    'isolated preauthorized existing-email invitation',
    () async {
      check(
        const {
          'main',
          'ack',
          'revoke',
          'tamper',
          'graph_send_restart',
        }.contains(scenario),
        'explicit_case_required',
      );
      final file = File(path!);
      final full = jsonDecode(await file.readAsString()) as Map;
      check(
        full['synthetic'] == true &&
            full['purpose'] == 'local-invitation-preauthorization-20261023' &&
            full['serverUrl'] == 'http://127.0.0.1:59779',
        'exact_new_fixture_required',
      );
      final pair = const {'main', 'ack'}.contains(scenario) ? 'L1' : 'L2';
      final fixture = {
        ...full,
        'accounts': {
          'owner': full['accounts']['${pair}_owner'],
          'member': full['accounts']['${pair}_member'],
        },
        'clientStateDirs': {
          'owner': full['clientStateDirs']['${pair}_owner'],
          'member': full['clientStateDirs']['${pair}_member'],
        },
      };
      final ledgerFile = File(
        '${file.parent.path}/$scenario-ledger-private.json',
      );
      final ledger = ledgerFile.existsSync()
          ? Map<String, dynamic>.from(
              jsonDecode(await ledgerFile.readAsString()) as Map,
            )
          : <String, dynamic>{};
      final lab = _Lab(file.parent, fixture, ledger, scenario!);
      final priorPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message?.startsWith('GAP_EVENT ') == true) {
          priorPrint(message, wrapWidth: wrapWidth);
        }
      };
      try {
        await _runCase(lab);
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
