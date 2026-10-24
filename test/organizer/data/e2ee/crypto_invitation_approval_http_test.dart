import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

// NEW owner-only/new-account HTTP fixture. Shared fixture mechanics copied; no old test entrypoint is run.
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
  bool get continuation => scenario == 'continuation-20261024';
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
    if (continuation) ledger['checkpoint'] = name;
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
      if (continuation && state['passed'] == true) {
        ledger['checkpoint'] = '$name:passed';
      }
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
  String? dropActivationAckScope;
  int offlineAttempts = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest base) async {
    if (offline) {
      offlineAttempts++;
      throw http.ClientException('synthetic_actor_offline');
    }
    final request = base as http.Request;
    final body = jsonDecode(request.body) as Map;
    final params = body['params'] as Map;
    final command = params['commandBase64'] is String
        ? CryptoJson.decode(cryptoBase64(params['commandBase64'])) as Map
        : null;
    if (client.lab.continuation) {
      const forbidden = {
        'crypto2.invitations.create',
        'crypto2.invitations.resend',
        'crypto2.invitations.accept',
        'crypto2.invitations.revoke',
        'crypto2.invitations.publishPreauthorization',
        'auth.registerInvitation4',
        'auth.register',
      };
      const parentMutations = {
        'crypto2.scope.prepare',
        'crypto2.scope.headPut',
        'crypto2.scope.activate',
        'crypto2.scope.cancel',
        'crypto2.scope.closeDomain',
        'crypto2.grants.put',
      };
      if (forbidden.contains(body['op']) ||
          parentMutations.contains(body['op']) &&
              command?['payload']['scopeId'] == client.lab.scope) {
        client.lab.calls.add({
          'actor': client.actor,
          'operation': body['op'],
          'status': null,
          'fault': 'forbidden_continuation_mutation_blocked',
        });
        throw StateError('forbidden_continuation_mutation');
      }
    }
    final metric = <String, Object?>{
      'actor': client.actor,
      'operation': body['op'],
      'status': null,
      if (command != null) 'requestId': command['requestId'],
      if (command == null && body['op'] == 'crypto2.receipt.get')
        'requestId': params['requestId'],
      if (command == null && body['op'] == 'crypto2.receipt.get')
        'receiptRequestHash': params['requestHash'],
      if (command != null)
        'requestHash': await cryptoSha256(CryptoJson.encode(params)),
    };
    client.lab.calls.add(metric);
    final response = await delegate.send(request);
    final bytes = await response.stream.toBytes();
    metric['status'] = response.statusCode;
    if (dropActivationAckScope != null &&
        body['op'] == 'crypto2.scope.activate' &&
        command?['payload']['scopeId'] == dropActivationAckScope &&
        response.statusCode == 200) {
      dropActivationAckScope = null;
      offline = true;
      metric['fault'] = 'lost_real_activation_ack';
      client.lab.ledger['lostActivation'] = {
        'requestId': metric['requestId'],
        'requestHash': metric['requestHash'],
        'commandHash': await cryptoSha256(
          cryptoBase64(params['commandBase64']),
        ),
        'scopeId': command!['payload']['scopeId'],
        'actualHttp200': true,
      };
      await client.lab.save();
      throw http.ClientException('synthetic_activation_ack_lost');
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
      'name': 'Synthetic approval $key',
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

Future<Map<String, dynamic>> _fixtureRead(
  String action,
  String id, [
  List<String> extra = const [],
]) async {
  final result = await Process.run('docker', [
    'exec',
    'jivie-invitation-approval-lab-20261023',
    'php',
    '/familyhub-tests/invitation-approval-fixture.php',
    action,
    id,
    ...extra,
  ]);
  if (result.exitCode != 0) {
    final root = File(
      Platform.environment['JIVIE_INVITATION_APPROVAL_FIXTURE']!,
    ).parent;
    await File(
      '${root.path}/fixture-$action-$id-error-private.json',
    ).writeAsString(
      jsonEncode({
        'exitCode': result.exitCode,
        'stdout': result.stdout.toString().substring(
          0,
          result.stdout.toString().length.clamp(0, 16384),
        ),
        'stderr': result.stderr.toString().substring(
          0,
          result.stderr.toString().length.clamp(0, 16384),
        ),
      }),
      flush: true,
    );
  }
  check(result.exitCode == 0, 'owned_private_fixture_read_failed');
  return Map<String, dynamic>.from(jsonDecode(result.stdout as String) as Map);
}

class _RegistrationWire extends http.BaseClient {
  _RegistrationWire(this.lab);
  final _Lab lab;
  final delegate = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest base) async {
    final request = base as http.Request;
    final operation = (jsonDecode(request.body) as Map)['op'];
    final metric = <String, Object?>{
      'actor': 'registration',
      'operation': operation,
      'status': null,
    };
    lab.calls.add(metric);
    final response = await delegate.send(request);
    metric['status'] = response.statusCode;
    return response;
  }

  @override
  void close() => delegate.close();
}

Future<Map<String, dynamic>> _registrationCall(
  _Lab lab,
  String operation,
  Map<String, Object?> params, {
  String? token,
}) async {
  await lab.quota();
  final transport = HttpCollaborationTransport(client: _RegistrationWire(lab));
  try {
    return await transport.call(
      serverUrl: lab.fixture['serverUrl'],
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: true,
    );
  } finally {
    transport.close();
  }
}

Future<void> _initializeActor(_Lab lab, String actor) async {
  await lab.step('account_$actor', () async {
    final client = await lab.open(actor);
    final file = File(
      '${lab.fixture['clientStateDirs'][actor]}/recovery.private',
    );
    final phase = await client.account.localPhase();
    if (phase == 'ready') return;
    if (!file.existsSync()) {
      final bytes = await client.account.prepareRecoveryFile();
      await file.writeAsBytes(bytes, flush: true);
      bytes.fillRange(0, bytes.length, 0);
    }
    final bytes = await file.readAsBytes();
    if (await client.account.localPhase() == 'pending') {
      await client.account.resume();
    } else {
      await client.account.verifyAndInitialize(bytes);
    }
    bytes.fillRange(0, bytes.length, 0);
    check(await client.account.localPhase() == 'ready', 'account_not_ready');
  });
}

Future<void> _runApproval(_Lab lab) async {
  await _initializeActor(lab, 'owner');
  await _createScope(lab, 'owner', 'scope', kind: 'organization');
  await _publishHistory(lab, 'owner', 'scope');
  await _createScope(lab, 'owner', 'childScope', parentKey: 'scope');
  await _publishHistory(lab, 'owner', 'childScope');
  var owner = await lab.open('owner');
  await lab.step('send_new_account', () async {
    check(
      lab.fixture['accounts']['member'] == null,
      'recipient_must_not_exist_at_send',
    );
    lab.ledger['sendRequest'] ??= owner.account.directory.reducer.crypto
        .randomId();
    await lab.save();
    if (lab.ledger['invitationId'] == null) {
      final sent = await owner.repo.createRecipientInvitation(
        scopeId: lab.scope,
        recipient: lab.fixture['newRecipient']['email'],
        role: SharedRole.member,
        requestId: lab.ledger['sendRequest'],
        language: 'en',
        accessScope: 'space',
      );
      lab.ledger['invitationId'] = sent.id;
    } else {
      // Attempt1 already received the exact Send200. Its v4 public model omits
      // the v5-only deliveryQueued flag: resume by proof/mail reads, never Send.
      lab.ledger['sendAssertionRecovery'] = 'read-only original confirmed Send';
    }
    await lab.save();
    final rows = await owner.db.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='invitationForegroundApproval'",
      [owner.partition, lab.scope],
    );
    check(rows.length == 1, 'new_send_auto_intent_missing');
    final saved =
        CryptoJson.decode(
              Uint8List.fromList((rows.single['payload'] as List).cast<int>()),
            )
            as Map;
    check(
      saved['payload']['invitationId'] == lab.ledger['invitationId'] &&
          saved['payload']['recipient']['accountId'] == null &&
          saved['payload']['preauthorization'] == null,
      'send_not_exact_new_account_fallback',
    );
    lab.ledger['sendIntentHash'] = await cryptoSha256(
      (rows.single['payload'] as List).cast<int>(),
    );
    final commands = await owner.db.rows(
      'SELECT i.authorization,i.state FROM crypto_membership_action_keys a JOIN crypto_membership_intents i ON i.partition=a.partition AND i.scope_id=a.scope_id AND i.intent_id=a.request_id WHERE a.partition=? AND a.scope_id=? AND a.action_key=?',
      [owner.partition, lab.scope, 'invite:${saved['action']}'],
    );
    check(
      commands.length == 1 && commands.single['state'] == 'confirmed',
      'original_send_not_confirmed',
    );
    final proof =
        CryptoJson.decode(
              Uint8List.fromList(
                (commands.single['authorization'] as List).cast<int>(),
              ),
            )
            as Map;
    final original =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    check(
      original['operation'] == 'crypto2.invitations.create' &&
          original['accountId'] == owner.session.profile.accountId &&
          CryptoJson.encode(original['payload']).toString() ==
              CryptoJson.encode(saved['payload']).toString(),
      'original_send_proof_changed',
    );
    lab.ledger['originalSendRequestId'] = original['requestId'];
    lab.ledger['originalSendProofHash'] = await cryptoSha256(
      (commands.single['authorization'] as List).cast<int>(),
    );
    final metadata = await _fixtureRead('metadata', lab.ledger['invitationId']);
    check(
      metadata['invitationState'] == 'pending' &&
          metadata['mail']['state'] == 'pending' &&
          metadata['mail']['hasCipher'] == 1,
      'exact_new_account_mail_not_queued',
    );
  });
  await lab.step('capture_test_invitation_mail', () async {
    final mail = await _fixtureRead(
      'capture-invitation',
      lab.ledger['invitationId'],
    );
    check(
      mail['id'] == lab.ledger['invitationId'] &&
          mail['to'] == lab.fixture['newRecipient']['email'],
      'captured_wrong_testmail',
    );
    final fragment = Uri.parse(mail['url'] as String).fragment;
    check(fragment.startsWith('token=fhi4_'), 'captured_mail_lacks_v4_link');
    lab.ledger['invitationToken'] = Uri.decodeComponent(fragment.substring(6));
  });
  await lab.step('register_after_send', () async {
    if (lab.fixture['accounts']['member'] != null) return;
    final planned = lab.fixture['newRecipient'] as Map;
    final response = await _registrationCall(lab, 'auth.registerInvitation4', {
      'token': lab.ledger['invitationToken'],
      'username': planned['username'],
      'password': planned['password'],
      'displayName': 'Synthetic new recipient',
      'deviceName': 'New-account approval lab',
    });
    check(
      response['emailVerificationRequired'] == true &&
          response['serverId'] == lab.fixture['serverId'],
      'registration_identity_mismatch',
    );
    lab.fixture['accounts']['member'] = {...planned, 'session': response};
    await File(
      '${lab.root.path}/fixture.json',
    ).writeAsString(jsonEncode(lab.fixture), flush: true);
    lab.ledger['recipientAccountId'] = response['user']['accountId'];
    await lab.save();
  });
  await lab.step('confirm_recipient_email', () async {
    final member = lab.fixture['accounts']['member'] as Map;
    final session = member['session'] as Map;
    final mail = await _fixtureRead(
      'verification',
      session['user']['accountId'],
    );
    final confirmed = await _registrationCall(lab, 'account.email.confirm', {
      'token': mail['token'],
    }, token: session['token']);
    check(confirmed['verified'] == true, 'recipient_email_not_verified');
    await _registrationCall(lab, 'moderation.acceptPolicy', {
      'policyVersion': 1,
    }, token: session['token']);
  });
  await _initializeActor(lab, 'member');
  var member = await lab.open('member');
  owner.wire.offline = true;
  final beforeOwner = lab.calls.where((c) => c['actor'] == 'owner').length;
  await lab.step('explicit_accept_owner_offline', () async {
    final receiver = InviteCryptoRepository(member.access);
    final invitation = await receiver.inspect(
      token: lab.ledger['invitationToken'],
    );
    final creation =
        CryptoJson.decode(
              cryptoBase64(invitation.authorization['commandBase64']),
            )
            as Map;
    check(
      creation['payload']['recipient']['accountId'] == null &&
          creation['payload']['preauthorization'] == null,
      'not_original_new_account_send',
    );
    final accepted = await receiver.accept(
      invitation,
      actionId: lab.ledger['invitationId'],
    );
    check(
      accepted['state'] == 'pendingKeys',
      'new_account_should_wait_for_inviter_keys',
    );
    lab.ledger['acceptanceProofHash'] = accepted['acceptanceProofHash'];
    lab.ledger['creatorProofHash'] = await cryptoSha256(
      CryptoJson.encode(invitation.authorization),
    );
    lab.ledger['tokenHash'] = creation['payload']['tokenHash'];
    check(
      owner.wire.offlineAttempts == 0 &&
          lab.calls.where((c) => c['actor'] == 'owner').length == beforeOwner,
      'owner_used_during_recipient_accept',
    );
  });
  owner.wire.offline = false;
  await lab.step('exact_inviter_notification', () async {
    final inbox = await owner.account.directory.call('crypto2.inbox.list', {
      'limit': 50,
    });
    final items = (inbox['items'] as List)
        .cast<Map>()
        .where(
          (v) =>
              v['kind'] == 'invitation.accepted' &&
              v['targetId'] == lab.ledger['invitationId'],
        )
        .toList();
    check(items.length == 1, 'exact_inviter_notice_missing');
    final item = items.single;
    check(
      item['invitationAcceptance']['scopeId'] == lab.scope &&
          item['invitationAcceptance']['invitationId'] ==
              lab.ledger['invitationId'] &&
          item['invitationAcceptance']['acceptanceProofHash'] ==
              lab.ledger['acceptanceProofHash'] &&
          item['invitationAcceptance']['creatorProofHash'] ==
              lab.ledger['creatorProofHash'] &&
          item['invitationAcceptance']['tokenHash'] == lab.ledger['tokenHash'],
      'notice_exact_proof_binding_missing',
    );
    lab.ledger['notificationId'] = item['id'];
    final opened = await owner.account.directory.call('crypto2.inbox.open', {
      'id': item['id'],
    });
    check(
      CryptoJson.encode(opened['item']['invitationAcceptance']).toString() ==
          CryptoJson.encode(item['invitationAcceptance']).toString(),
      'open_rebound_invitation',
    );
    var denied = false;
    try {
      await member.account.directory.call('crypto2.inbox.open', {
        'id': item['id'],
      });
    } on CollaborationApiException catch (e) {
      denied = e.code == 'permission_revoked';
    }
    check(denied, 'recipient_opened_inviter_notification');
  });
  await lab.step('background_cannot_grant', () async {
    final before = lab.calls.length;
    var blocked = false;
    try {
      await InviteCryptoRepository(
        owner.access,
      ).processForegroundAutoApprovals(isForegroundCurrent: () => false);
    } on CryptoAuthorityPending catch (e) {
      blocked = e.reason == 'crypto_invitation_foreground_required';
    }
    check(
      blocked && lab.calls.length == before,
      'background_autoapproval_used_network',
    );
    final metadata = await _fixtureRead('metadata', lab.ledger['invitationId']);
    check(
      metadata['invitationState'] == 'accepted',
      'background_autoapproval_activated_invitation',
    );
  });
  await lab.step('synthetic_unsent_push_reference', () async {
    final metadata = await _fixtureRead(
      'arm-unsent-reference',
      lab.ledger['invitationId'],
    );
    check(
      (metadata['pushReferences'] as List).single['state'] == 'pending' &&
          metadata['externalDeliveryAttempted'] == false,
      'synthetic_unsent_reference_missing',
    );
  });
  await lab.step('foreground_lost_activation_ack', () async {
    member.wire.offline = true;
    owner.wire.dropActivationAckScope = lab.scope;
    final summary = await InviteCryptoRepository(
      owner.access,
    ).processForegroundAutoApprovals(isForegroundCurrent: () => true);
    lab.ledger['firstForegroundSummary'] = {
      'completed': summary.completed,
      'pending': summary.pending,
      'codes': [
        for (final item in summary.invitations)
          RegExp(r'^[a-z0-9_]{1,160}$').hasMatch(item.errorCode)
              ? item.errorCode
              : 'unclassified_error',
      ],
    };
    await lab.save();
    check(
      summary.completed == 0 &&
          summary.pending == 1 &&
          lab.ledger['lostActivation']?['actualHttp200'] == true,
      'expected_real_activation_ack_loss_missing',
    );
    final metadata = await _fixtureRead('metadata', lab.ledger['invitationId']);
    check(
      metadata['invitationState'] == 'consumed',
      'dropped_activation_was_not_applied',
    );
  });
  await lab.step('restart_owner_foreground_autoapproval', () async {
    member.wire.offline = true;
    final beforeMember = lab.calls.where((c) => c['actor'] == 'member').length;
    await lab.restart('owner');
    owner = await lab.open('owner');
    final summary = await InviteCryptoRepository(
      owner.access,
    ).processForegroundAutoApprovals(isForegroundCurrent: () => true);
    lab.ledger['recoveredForegroundSummary'] = {
      'completed': summary.completed,
      'pending': summary.pending,
      'codes': [
        for (final item in summary.invitations)
          RegExp(r'^[a-z0-9_]{1,160}$').hasMatch(item.errorCode)
              ? item.errorCode
              : 'unclassified_error',
      ],
    };
    await lab.save();
    check(
      summary.completed == 1 && summary.pending == 0,
      'foreground_autoapproval_did_not_complete',
    );
    check(
      member.wire.offlineAttempts == 0 &&
          lab.calls.where((c) => c['actor'] == 'member').length == beforeMember,
      'recipient_used_during_owner_autoapproval',
    );
    final metadata = await _fixtureRead('metadata', lab.ledger['invitationId']);
    check(
      metadata['invitationState'] == 'consumed' &&
          (metadata['pushReferences'] as List).single['state'] == 'cancelled',
      'consumed_admission_left_unsent_notification',
    );
  });
  member.wire.offline = false;
  await lab.step('recipient_reads_parent_child', () async {
    final receiver = InviteCryptoRepository(member.access);
    check(
      await receiver.resumeAccepted(lab.ledger['invitationId']) == lab.scope,
      'recipient_did_not_resume_same_invitation',
    );
    await member.sync();
    for (final key in ['scope', 'childScope']) {
      await member.runtime.pullVerified(lab.ledger[key], 'content');
      final actual = await member.runtime.record(
        lab.ledger[key],
        'content',
        lab.ledger['${key}Record'],
        type: 'project',
      );
      check(actual != null, 'admitted_recipient_cannot_read_$key');
      final original = await owner.runtime.record(
        lab.ledger[key],
        'content',
        lab.ledger['${key}Record'],
        type: 'project',
      );
      check(
        actual!['record_proof_hash'] == original!['record_proof_hash'] &&
            actual['raw_payload'] == original['raw_payload'],
        'admission_changed_preserved_$key',
      );
    }
    check(
      ((lab.ledger['steps'] as Map)['explicit_accept_owner_offline']['calls']
                  as List)
              .cast<Map>()
              .where(
                (c) =>
                    c['operation'] == 'crypto2.invitations.accept' &&
                    c['status'] == 200,
              )
              .length ==
          1,
      'recipient_accepted_more_than_once',
    );
  });
  await lab.step('stale_notice_hidden', () async {
    var blocked = false;
    try {
      await owner.account.directory.call('crypto2.inbox.open', {
        'id': lab.ledger['notificationId'],
      });
    } on CollaborationApiException catch (e) {
      blocked = e.code == 'permission_revoked';
    }
    check(blocked, 'consumed_notification_still_actionable');
    final list = await owner.account.directory.call('crypto2.inbox.list', {
      'limit': 50,
    });
    check(
      !(list['items'] as List).cast<Map>().any(
        (v) => v['id'] == lab.ledger['notificationId'],
      ),
      'consumed_event_still_visible',
    );
  });
  await lab.step('lost_activation_exact_receipt_only', () async {
    final lost = lab.ledger['lostActivation'] as Map;
    final calls = (lab.ledger['steps'] as Map).values
        .cast<Map>()
        .expand((step) => (step['calls'] as List? ?? const []).cast<Map>())
        .where((call) => call['requestId'] == lost['requestId'])
        .toList();
    final activations = calls
        .where((call) => call['operation'] == 'crypto2.scope.activate')
        .toList();
    check(
      activations.length == 1 &&
          activations.single['status'] == 200 &&
          activations.single['requestHash'] == lost['requestHash'] &&
          activations.single['fault'] == 'lost_real_activation_ack',
      'lost_activation_was_resent',
    );
    check(
      calls.any(
        (call) =>
            call['operation'] == 'crypto2.receipt.get' &&
            call['receiptRequestHash'] == lost['commandHash'] &&
            call['status'] == 200,
      ),
      'lost_activation_exact_receipt_missing',
    );
    final originals = await owner.db.rows(
      'SELECT authorization,state FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [owner.partition, lab.scope, lost['requestId']],
    );
    check(
      originals.length == 1 &&
          originals.single['state'] == 'confirmed' &&
          await cryptoSha256(
                (originals.single['authorization'] as List).cast<int>(),
              ) ==
              lost['requestHash'],
      'lost_activation_original_signature_changed',
    );
  });
}

Future<Map<String, dynamic>> _continuationState(_Lab lab) => _fixtureRead(
  'continuation-state',
  lab.ledger['invitationId'],
  [lab.ledger['childScope'], lab.ledger['lostActivation']['requestId']],
);

Future<void> _checkOriginalAuthorizations(_Lab lab, Map baseline) async {
  for (final key in ['send', 'parentActivation', 'accept']) {
    final actor = key == 'accept' ? 'member' : 'owner';
    final client = await lab.open(actor);
    final expected = baseline['originalAuthorizations'][key] as Map;
    final rows = await client.db.rows(
      'SELECT state,authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [client.partition, lab.scope, expected['requestId']],
    );
    check(
      rows.length == 1 &&
          rows.single['state'] == 'confirmed' &&
          await cryptoSha256(
                (rows.single['authorization'] as List).cast<int>(),
              ) ==
              expected['proofHash'],
      'original_${key}_authorization_changed',
    );
  }
}

Future<void> _runContinuation(_Lab lab, Map baseline) async {
  final owner = await lab.open('owner');
  final member = await lab.open('member');
  await lab.step('retained_pending_child_baseline', () async {
    await _checkOriginalAuthorizations(lab, baseline);
    final actual = await _continuationState(lab);
    final expected = baseline['serverBaseline'] as Map;
    check(
      actual['invitationState'] == 'consumed' &&
          actual['parent']['headHash'] == expected['parent']['headHash'] &&
          actual['parent']['hasRecipient'] == true &&
          actual['child']['headHash'] == expected['child']['headHash'] &&
          actual['child']['hasRecipient'] == false,
      'retained_pending_child_baseline_changed',
    );
    check(
      actual['parentActivationReceipt']['status'] == 200 &&
          actual['parentActivationReceipt']['commandHash'] ==
              lab.ledger['lostActivation']['commandHash'] &&
          actual['parentActivationReceipt']['proofHash'] ==
              lab.ledger['lostActivation']['requestHash'],
      'original_parent_receipt_changed',
    );
    check(
      actual['creationProofHash'] == lab.ledger['originalSendProofHash'] &&
          (actual['acceptances'] as List).length == 1 &&
          actual['acceptances'][0]['proofHash'] ==
              lab.ledger['acceptanceProofHash'],
      'original_server_invitation_proofs_changed',
    );
    lab.ledger['baselineState'] = actual;
  });
  await lab.step('continue_same_pending_child_foreground', () async {
    member.wire.offline = true;
    final beforeMember = lab.calls.where((c) => c['actor'] == 'member').length;
    final summary = await InviteCryptoRepository(owner.access)
        .processForegroundAutoApprovals(
          isForegroundCurrent: () => true,
          invitationIds: {lab.ledger['invitationId']},
        );
    lab.ledger['continuationSummary'] = {
      'completed': summary.completed,
      'pending': summary.pending,
      'codes': [
        for (final item in summary.invitations)
          RegExp(r'^[a-z0-9_]{1,160}$').hasMatch(item.errorCode)
              ? item.errorCode
              : 'unclassified_error',
      ],
      'lastOperations': [
        for (final call in lab.calls.skip(
          lab.calls.length > 8 ? lab.calls.length - 8 : 0,
        ))
          {'operation': call['operation'], 'status': call['status']},
      ],
    };
    await lab.save();
    check(
      summary.completed == 1 && summary.pending == 0,
      'same_pending_child_foreground_incomplete',
    );
    check(
      member.wire.offlineAttempts == 0 &&
          lab.calls.where((c) => c['actor'] == 'member').length == beforeMember,
      'recipient_used_during_child_continuation',
    );
    final after = await _continuationState(lab);
    check(
      after['parent']['headHash'] ==
              baseline['serverBaseline']['parent']['headHash'] &&
          after['child']['hasRecipient'] == true &&
          after['child']['epoch'] == 2,
      'child_not_completed_with_same_parent',
    );
    lab.ledger['afterChildState'] = after;
  });
  member.wire.offline = false;
  await lab.step('recipient_resume_same_acceptance', () async {
    final receiver = InviteCryptoRepository(member.access);
    check(
      await receiver.resumeAccepted(lab.ledger['invitationId']) == lab.scope,
      'recipient_same_acceptance_resume_failed',
    );
  });
  await lab.step('recipient_first_ordinary_sync_and_read_both', () async {
    await member.sync();
    for (final key in ['scope', 'childScope']) {
      await member.runtime.pullVerified(lab.ledger[key], 'content');
      final actual = await member.runtime.record(
        lab.ledger[key],
        'content',
        lab.ledger['${key}Record'],
        type: 'project',
      );
      final original = await owner.runtime.record(
        lab.ledger[key],
        'content',
        lab.ledger['${key}Record'],
        type: 'project',
      );
      check(
        actual != null &&
            original != null &&
            actual['record_proof_hash'] == original['record_proof_hash'] &&
            actual['raw_payload'] == original['raw_payload'],
        'recipient_preserved_${key}_record_mismatch',
      );
      final visible = member.repo.state
          .dataForScope(lab.ledger[key])
          .projects
          .where((p) => p.id == lab.ledger['${key}Record'])
          .toList();
      check(
        visible.length == 1 && visible.single.title == 'Preserved $key content',
        'recipient_${key}_not_visible_in_repository',
      );
    }
    lab.ledger['recipientOrdinarySync'] = {
      'error': null,
      'unresolved': false,
      'parentAndChildVisible': true,
    };
  });
  await lab.step('previously_unrun_stale_notice_hidden', () async {
    var denied = false;
    try {
      await owner.account.directory.call('crypto2.inbox.open', {
        'id': lab.ledger['notificationId'],
      });
    } on CollaborationApiException catch (error) {
      denied = error.code == 'permission_revoked';
    }
    check(denied, 'consumed_notice_still_actionable');
    final inbox = await owner.account.directory.call('crypto2.inbox.list', {
      'limit': 50,
    });
    check(
      !(inbox['items'] as List).cast<Map>().any(
        (v) => v['id'] == lab.ledger['notificationId'],
      ),
      'consumed_notice_still_visible',
    );
  });
  await lab.step('original_parent_and_all_signed_actions_preserved', () async {
    await _checkOriginalAuthorizations(lab, baseline);
    final finalState = await _continuationState(lab);
    check(
      finalState['parent']['headHash'] ==
              baseline['serverBaseline']['parent']['headHash'] &&
          finalState['parentActivationReceipt']['status'] == 200 &&
          finalState['parentActivationReceipt']['commandHash'] ==
              lab.ledger['lostActivation']['commandHash'] &&
          finalState['parentActivationReceipt']['proofHash'] ==
              lab.ledger['lostActivation']['requestHash'] &&
          finalState['creationProofHash'] ==
              lab.ledger['originalSendProofHash'] &&
          finalState['acceptances'][0]['proofHash'] ==
              lab.ledger['acceptanceProofHash'],
      'original_parent_or_signed_proofs_changed',
    );
    check(
      (finalState['pushReferences'] as List).every(
        (j) => j['state'] == 'cancelled' && j['attempts'] == 0,
      ),
      'retired_push_reference_changed',
    );
    check(
      !lab.calls.any(
        (call) => call['fault'] == 'forbidden_continuation_mutation_blocked',
      ),
      'continuation_attempted_forbidden_repetition',
    );
    lab.ledger['finalState'] = finalState;
    lab.ledger['newSendRegisterAcceptParentMutationHttp'] = 0;
  });
}

void main() {
  final path = Platform.environment['JIVIE_INVITATION_APPROVAL_FIXTURE'];
  final continuation =
      Platform.environment['JIVIE_INVITATION_APPROVAL_CONTINUATION'] ==
      '20261024';
  test(
    'new-account invitation explicit acceptance and foreground owner admission',
    () async {
      final file = File(path!);
      final fixture = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      check(
        fixture['synthetic'] == true &&
            fixture['purpose'] == 'local-invitation-approval-20261023' &&
            fixture['serverUrl'] == 'http://127.0.0.1:59780',
        'exact_new_approval_fixture_required',
      );
      final ledgerFile = File(
        '${file.parent.path}/${continuation ? 'continuation-20261024' : 'approval'}-ledger-private.json',
      );
      final ledger = ledgerFile.existsSync()
          ? Map<String, dynamic>.from(
              jsonDecode(await ledgerFile.readAsString()) as Map,
            )
          : <String, dynamic>{};
      Map<String, dynamic>? baseline;
      if (continuation) {
        baseline = Map<String, dynamic>.from(
          jsonDecode(
                await File(
                  '${file.parent.path}/continuation-baseline-20261024-private.json',
                ).readAsString(),
              )
              as Map,
        );
        final history = Map<String, dynamic>.from(
          jsonDecode(
                await File(
                  '${file.parent.path}/approval-ledger-private.json',
                ).readAsString(),
              )
              as Map,
        );
        check(
          await cryptoSha256(
                await File(
                  '${file.parent.path}/approval-ledger-private.json',
                ).readAsBytes(),
              ) ==
              baseline['historicalLedgerSha256'],
          'historical_stop_ledger_changed',
        );
        if (ledger.isEmpty) {
          for (final key in [
            'scope',
            'childScope',
            'scopeRecord',
            'childScopeRecord',
            'invitationId',
            'notificationId',
            'lostActivation',
            'originalSendRequestId',
            'originalSendProofHash',
            'acceptanceProofHash',
            'creatorProofHash',
            'tokenHash',
          ]) {
            ledger[key] = history[key];
          }
          ledger['renewedAuthorizationDate'] = '20261024';
          ledger['sourceHistorySha256'] = baseline['historicalLedgerSha256'];
        }
      }
      check(ledger['passed'] != true, 'passed_scenario_must_not_rerun');
      final lab = _Lab(
        file.parent,
        fixture,
        ledger,
        continuation ? 'continuation-20261024' : 'approval',
      );
      final priorPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message?.startsWith('GAP_EVENT ') == true) {
          priorPrint(message, wrapWidth: wrapWidth);
        }
      };
      try {
        if (continuation) {
          await _runContinuation(lab, baseline!);
        } else {
          await _runApproval(lab);
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
