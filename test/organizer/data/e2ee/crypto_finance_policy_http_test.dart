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
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
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
  bool omitGrant = false;
  bool loseActivation = false;
  String? hiddenActivation;
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
    if (operation == 'crypto2.receipt.get' &&
        params['requestId'] == hiddenActivation) {
      return {'outcome': 'unknown'};
    }
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
    if (loseActivation && operation == 'crypto2.scope.activate') {
      loseActivation = false;
      final command =
          CryptoJson.decode(cryptoBase64(params['commandBase64'])) as Map;
      hiddenActivation = command['requestId'];
      throw const CollaborationException('synthetic_activation_ack_lost');
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
    if (omitGrant && operation == 'crypto2.scope.financePolicy.current') {
      return {...reply, 'grants': <Object>[], 'hasMore': false};
    }
    return reply;
  }

  @override
  void close() => http.close();
}

void main() {
  final path = Platform.environment['JIVIE_FINANCE_POLICY_HTTP_FIXTURE'];
  test(
    'production factory finance policy actions verify grants and settle old activation after successor',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback required');
      final w = fixture['accounts']['owner']['session'] as Map,
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
      final scope = await repository.createScope('Finance policy synthetic');
      final initial = await repository.refreshFinancePolicy(scope);
      expect(initial.enabled, true);
      expect(initial.grant, SharedFinanceGrant.write);
      final original = await repository.financeGrants(scope);
      expect(original[session.profile.accountId], SharedFinanceGrant.write);
      transport.loseActivation = true;
      await expectLater(
        repository.enableFinance(scope, true),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'synthetic_activation_ack_lost',
          ),
        ),
      );
      expect(transport.hiddenActivation, isNotNull);
      final commands = await db.rows(
        "SELECT signed_body FROM crypto_outbox WHERE partition=? AND operation='crypto2.scope.financePolicy.propose'",
        [session.profile.partition],
      );
      expect(commands.length, 1);
      final proof = jsonDecode(commands.single['signed_body'] as String) as Map;
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final requestId = command['requestId'] as String;
      final prior = await SessionCryptoAccess(
        account: account,
      ).currentHead(scope, online: true);
      await repository.grantFinance(
        scopeId: scope,
        accountId: session.profile.accountId,
        grant: SharedFinanceGrant.read,
      );
      final latest = await SessionCryptoAccess(
        account: account,
      ).currentHead(scope, online: true);
      expect(latest.epoch, prior.epoch + 1);
      expect(latest.member(session.profile.accountId)['financeRole'], 'write');
      expect(
        (await repository.financeGrants(scope))[session.profile.accountId],
        SharedFinanceGrant.read,
      );
      transport.hiddenActivation = null;
      final router = CryptoBusinessRouter(
        database: db,
        accountFor: (_) async => account,
      );
      final result = await router.dispatch(
        session: session,
        operation: 'finance.enable',
        params: {'scopeId': scope, 'enabled': true, 'requestId': requestId},
        protectedScopeIds: {scope},
      );
      expect(result['grant'], 'write');
      expect(
        (await SessionCryptoAccess(
          account: account,
        ).currentHead(scope, online: true)).headHash,
        latest.headHash,
      );
      expect(
        (await db.rows(
          "SELECT COUNT(*) AS n FROM crypto_outbox WHERE partition=? AND operation='crypto2.scope.financePolicy.propose'",
          [session.profile.partition],
        )).single['n'],
        2,
      );
      transport.omitGrant = true;
      await expectLater(
        repository.financeGrants(scope),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'crypto_finance_policy_anchor_mismatch',
          ),
        ),
      );
      transport.omitGrant = false;
      expect(
        (await repository.financeGrants(scope))[session.profile.accountId],
        SharedFinanceGrant.read,
      );
      expect(
        transport.operations.where(
          (op) => RegExp(r'^finance[24]?\.').hasMatch(op),
        ),
        isEmpty,
      );
    },
    skip: path == null ? 'Synthetic loopback fixture not requested' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
