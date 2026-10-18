import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:kanban/organizer/domain/organizer_models.dart'
    show FinanceEntryKind;
import 'package:kanban/organizer/data/e2ee/crypto_business_payments.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_documents.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';

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
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
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
  bool dropCertificate = false;
  bool dropOffer = false;
  bool dropBatch = false;
  bool withholdHistory = false;
  bool substituteHistory = false;
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
    if (operation == 'crypto2.records.historyGet' && withholdHistory) {
      return {...reply, 'record': null};
    }
    if (operation == 'crypto2.records.historyGet' && substituteHistory) {
      return {
        ...reply,
        'record': {...reply['record'] as Map, 'revision': 999},
      };
    }
    if (operation == 'crypto2.records.batch' && dropBatch) {
      dropBatch = false;
      throw const SocketException('Synthetic accepted payment batch ACK loss');
    }
    if (operation == 'crypto2.exports.propose' && dropOffer) {
      dropOffer = false;
      throw const SocketException('Synthetic accepted offer ACK loss');
    }
    if (operation == 'crypto2.exports.certify' && dropCertificate) {
      dropCertificate = false;
      throw const SocketException('Synthetic accepted ACK loss');
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
    'payment private catchup converges exact intents',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback required');
      }
      final w =
              (fixture['session'] ?? fixture['accounts']['owner']['session'])
                  as Map,
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
      final coldRecoveryFile = Uint8List.fromList(file);
      addTearDown(
        () => coldRecoveryFile.fillRange(0, coldRecoveryFile.length, 0),
      );
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
      final source = await repository.createScope('PRIVATE_SOURCE_NAME');
      await repository.refreshFinancePolicy(source);
      final ledger = await repository.createFinanceAccount(
        scopeId: source,
        name: 'PRIVATE_ACCOUNT_SENTINEL',
        currency: 'EUR',
      );
      await repository.syncNow();
      final access = SessionCryptoAccess(account: account);
      final context = CryptoBusinessSession(account, access, db);

      final entryId = await repository.createFinanceEntry(
        scopeId: source,
        accountId: ledger,
        kind: FinanceEntryKind.expense,
        amountMinor: 1000,
        currency: 'EUR',
        title: 'PRIVATE_PAYMENT',
        occurredAt: DateTime.utc(2026, 10, 17),
      );
      await repository.syncNow();
      final payments = CryptoBusinessPayments(context);
      context.prepareHistoricalPayload = CryptoBusinessDocuments(
        context,
      ).prepareRecords;
      context.validateHistoricalPayload = payments.validateHistoryPayload;
      context.prepareRecords = (records) async {
        try {
          await payments.prepareRecords(records);
        } on CryptoProjectionPending catch (_, stack) {
          fail('Payment prepare missing evidence at $stack');
        }
      };
      context.references = payments.references;
      context.validateRaw = payments.validateRaw;
      context.projectExtension = payments.projectRecord;
      context.supportsFinanceExtension = payments.supportsType;
      context.validateFinanceExtension =
          (records, {required bool forWrite}) async {
            try {
              await payments.validateFinanceGroup(records, forWrite: forWrite);
            } on CryptoProjectionPending catch (_, stack) {
              fail('Payment semantic missing evidence at $stack');
            }
          };
      final eventId = crypto.randomId();
      await payments.dispatch('finance3.paymentCommit', {
        'scopeId': source,
        'entryId': entryId,
        'expectedEntryRevision': 1,
        'eventId': eventId,
        'paidAt': DateTime.utc(2026, 10, 17).toIso8601String(),
        'expectReimbursement': true,
        'requestId': crypto.randomId(),
      });
      final personal =
          (await context.ensurePersonal({
                'id': crypto.randomId(),
              }))['scope']['id']
              as String;
      final privateAccount = crypto.randomId();
      final accountRaw = SharedFinanceAccount(
        id: privateAccount,
        name: 'PRIVATE_PAYER_BANK',
        currency: 'EUR',
        createdAt: DateTime.utc(2026, 10, 17),
        updatedAt: DateTime.utc(2026, 10, 17),
      ).toPayload(contractVersion: 3);
      await context.publishRaw(
        scopeId: personal,
        domain: 'finance',
        id: privateAccount,
        type: 'personalFinanceAccount',
        operationId: crypto.randomId(),
        expectedRevision: 0,
        rawPayload: accountRaw,
        localHash: await CryptoBusinessJson.hash(accountRaw),
      );
      final params = <String, Object?>{
        'scopeId': source,
        'eventId': eventId,
        'expectedRevision': 1,
        'personalTarget': {'scopeId': personal, 'accountId': privateAccount},
        'requestId': crypto.randomId(),
      };
      final result = await payments.dispatch('finance3.paymentProject', params);
      expect(
        result['projectionPending'],
        false,
        reason:
            '${payments.lastPendingCode} ${jsonEncode({'received': await db.rows("SELECT record_id,revision,verdict,error FROM crypto_received"), 'business': await db.rows("SELECT id,type,crypto_revision FROM crypto_business_records"), 'state': await db.rows("SELECT scope_id,domain,transport_cursor,projection_cursor FROM crypto_scope_state")})}',
      );
      expect(
        (await context.record(
          personal,
          'finance',
          eventId,
          type: 'cashMovement',
        ))!['crypto_revision'],
        1,
      );
      Future<Map<String, dynamic>> refund(
        int revision,
        int amount,
        String leg,
      ) => payments.dispatch('finance3.paymentReimburse', {
        'scopeId': source,
        'eventId': eventId,
        'expectedRevision': revision,
        'legId': leg,
        'amountMinor': amount,
        'paidAt': DateTime.utc(2026, 10, 17).toIso8601String(),
        'organizationAccountId': ledger,
        'requestId': crypto.randomId(),
      });
      final leg1 = crypto.randomId(), leg2 = crypto.randomId();
      await refund(1, 200, leg1);
      transport.dropBatch = true;
      await expectLater(
        payments.dispatch('finance3.paymentProject', params),
        throwsA(isA<SocketException>()),
      );
      await refund(2, 100, leg2);
      final restarted = CryptoBusinessPayments(context);
      context.prepareRecords = (records) async {
        try {
          await restarted.prepareRecords(records);
        } on CryptoProjectionPending catch (_, stack) {
          fail('Restart payment prepare missing evidence at $stack');
        }
      };
      context.validateFinanceExtension =
          (records, {required bool forWrite}) async {
            try {
              await restarted.validateFinanceGroup(records, forWrite: forWrite);
            } on CryptoProjectionPending catch (_, stack) {
              fail('Restart payment semantic missing evidence at $stack');
            }
          };
      final resumed = await restarted.dispatch(
        'finance3.paymentProject',
        params,
      );
      expect(
        resumed['projectionPending'],
        false,
        reason: '${restarted.lastPendingCode} ${restarted.lastPendingTrace}',
      );
      expect(resumed['event']['revision'], 3);
      final projection = (await context.record(
        personal,
        'finance',
        eventId,
        type: 'paymentProjection',
      ))!;
      final projected = jsonDecode(projection['raw_payload'] as String) as Map;
      expect(projected['state'], 'complete');
      expect(projected['cashManifest']['count'], 3);
      for (final id in [eventId, leg1, leg2]) {
        expect(
          (await context.record(
            personal,
            'finance',
            id,
            type: 'cashMovement',
          ))!['crypto_revision'],
          1,
        );
      }
      expect(
        (await db.rows(
          "SELECT id FROM crypto_business_records WHERE partition=? AND scope_id=? AND type='cashMovement'",
          [context.partition, personal],
        )).length,
        3,
      );
      final repeated = await restarted.dispatch(
        'finance3.paymentProject',
        params,
      );
      expect(
        repeated['projectionPending'],
        false,
        reason: '${restarted.lastPendingCode} ${restarted.lastPendingTrace}',
      );
      expect(
        (await context.record(
          personal,
          'finance',
          eventId,
          type: 'paymentProjection',
        ))!['crypto_revision'],
        projection['crypto_revision'],
      );
      final originalCount = (await db.rows(
        "SELECT COUNT(*) AS n FROM crypto_business_records WHERE partition=? AND scope_id=? AND type='cashMovement'",
        [context.partition, personal],
      )).single['n'];
      final projectionWire =
          jsonDecode(
                (await db.rows(
                      'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
                      [
                        context.partition,
                        personal,
                        'finance',
                        projection['id'],
                        projection['crypto_revision'],
                      ],
                    )).single['wire']
                    as String,
              )
              as Map;
      final projectionBody = Map<String, dynamic>.from(
        CryptoJson.decode(
              cryptoBase64(
                projectionWire['authorization']['recordProof']['commandBase64'],
              ),
            )
            as Map,
      );
      final omitted = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(projected)) as Map,
      );
      final omittedRecords = (omitted['cashManifest']['records'] as List)
        ..removeLast();
      omitted['cashManifest']['count'] = omittedRecords.length;
      omitted['cashManifest']['manifestHash'] = await cryptoSha256(
        CryptoJson.encode(omittedRecords),
      );
      await expectLater(
        restarted.validateFinanceGroup([
          CryptoBusinessProjection(
            record: projectionBody,
            raw: omitted,
            previousRaw: Map<String, dynamic>.from(projected),
          ),
        ], forWrite: true),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'crypto_payment_cash_manifest',
          ),
        ),
      );
      final substituted = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(projected)) as Map,
      );
      substituted['cashManifest']['records'][0]['recordProofHash'] = '0' * 64;
      substituted['cashManifest']['manifestHash'] = await cryptoSha256(
        CryptoJson.encode(substituted['cashManifest']['records']),
      );
      await expectLater(
        restarted.validateFinanceGroup([
          CryptoBusinessProjection(
            record: projectionBody,
            raw: substituted,
            previousRaw: Map<String, dynamic>.from(projected),
          ),
        ], forWrite: true),
        throwsA(isA<CryptoProjectionPending>()),
      );
      expect(
        (await db.rows(
          "SELECT COUNT(*) AS n FROM crypto_business_records WHERE partition=? AND scope_id=? AND type='cashMovement'",
          [context.partition, personal],
        )).single['n'],
        originalCount,
      );
      await context.pullVerified(personal, 'finance');
      final person = fixture['accounts']['owner'] as Map;
      final login = await transport.call(
        serverUrl: url,
        operation: 'auth.login',
        params: {
          'username': person['username'],
          'password': person['password'],
          'deviceName': 'Payment blank FILE recovery',
        },
        allowLocalHttp: true,
      );
      final loginUser = login['user'] as Map,
          loginDevice = login['device'] as Map;
      final coldSession = DeviceSession(
        AccountSession(
          serverUrl: url,
          serverId: login['serverId'],
          accountId: loginUser['accountId'],
          userId: loginUser['id'],
          username: loginUser['username'],
          displayName: loginUser['displayName'],
          deviceId: loginDevice['id'],
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            loginDevice['expiresAt'] * 1000,
          ),
          allowLocalHttp: true,
        ),
        login['token'],
      );
      final blank = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(blank.close);
      final recovered = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: coldSession,
          transport: transport,
          store: CryptoIdentityStore(
            blank,
            _Secure(),
            coldSession.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      await recovered.recover(coldRecoveryFile);
      await CryptoScopeObservations(
        recovered,
      ).hydrateObservedScopes(coldRecoveryFile);
      final coldAccess = SessionCryptoAccess(account: recovered);
      final coldContext = CryptoBusinessSession(recovered, coldAccess, blank);
      final coldPayments = CryptoBusinessPayments(coldContext);
      coldContext.prepareHistoricalPayload = CryptoBusinessDocuments(
        coldContext,
      ).prepareRecords;
      coldContext.validateHistoricalPayload =
          coldPayments.validateHistoryPayload;
      final coldPreparation = <String>[];
      coldContext.prepareRecords = (batch) async {
        try {
          await coldPayments.prepareRecords(batch);
          coldPreparation.add(
            'prepared:${batch.map((v) => v.record['type']).join(',')}',
          );
        } catch (error, trace) {
          coldPreparation.add('$error\n$trace');
          rethrow;
        }
      };
      coldContext.references = coldPayments.references;
      coldContext.validateRaw = coldPayments.validateRaw;
      coldContext.projectExtension = coldPayments.projectRecord;
      coldContext.supportsFinanceExtension = coldPayments.supportsType;
      coldContext.validateFinanceExtension = (batch, {required forWrite}) async {
        try {
          await coldPayments.validateFinanceGroup(batch, forWrite: forWrite);
          coldPreparation.add('validated:${batch.map((v) => '${v.record['type']}:${v.historicalOnly}').join(',')}');
        } catch (error, trace) {
          coldPreparation.add('VALIDATE:$error\n$trace');
          rethrow;
        }
      };
      Map<String, Object?>? restored;
      for (var pass = 0; pass < 8; pass++) {
        await coldContext.pullVerified(personal, 'finance', attest: false);
        restored = await coldContext.record(
          personal,
          'finance',
          eventId,
          type: 'paymentProjection',
        );
        if (restored != null &&
            (await blank.rows(
                  "SELECT COUNT(*) AS n FROM crypto_business_records WHERE partition=? AND scope_id=? AND type='cashMovement'",
                  [coldContext.partition, personal],
                )).single['n'] ==
                3) {
          break;
        }
      }
      expect(
        restored,
        isNotNull,
        reason: jsonEncode({
          'preparation': coldPreparation,
          'received': await blank.rows(
            'SELECT verdict,error,revision,batch_key FROM crypto_received',
          ),
          'history': await blank.rows(
            'SELECT complete,target_revision,next_revision FROM crypto_business_history_jobs',
          ),
        }),
      );
      expect(
        (jsonDecode(restored!['raw_payload'] as String) as Map)['state'],
        'complete',
      );
      for (final id in [eventId, leg1, leg2]) {
        expect(
          (await coldContext.record(
            personal,
            'finance',
            id,
            type: 'cashMovement',
          ))!['crypto_revision'],
          1,
        );
      }
      final ancestorRows = await blank.rows(
        'SELECT wire FROM crypto_business_history_proofs WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision<? ORDER BY revision DESC LIMIT 1',
        [
          coldContext.partition,
          personal,
          'finance',
          restored['id'],
          restored['crypto_revision'],
        ],
      );
      expect(ancestorRows, hasLength(1));
      final oldWire = Map<String, dynamic>.from(
        jsonDecode(ancestorRows.single['wire'] as String) as Map,
      );
      final oldProof = Map<String, dynamic>.from(
        (oldWire['authorization'] as Map)['recordProof'] as Map,
      );
      final oldBody = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(oldProof['commandBase64'])) as Map,
      );
      final oldRaw = Map<String, dynamic>.from(
        jsonDecode(
              (await blank.rows(
                    'SELECT raw_payload FROM crypto_business_history_payloads WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?',
                    [
                      coldContext.partition,
                      personal,
                      'finance',
                      restored['id'],
                      oldWire['revision'],
                      await coldContext.codec.digest(oldProof),
                    ],
                  )).single['raw_payload']
                  as String,
            )
            as Map,
      );
      await coldPayments.validateHistoryPayload(
        CryptoProjectionRecord(
          oldWire,
          oldBody,
          null,
          historyBasis: 'verifiedCheckpoint',
          batchKey: oldBody['batchId'],
        ),
        oldRaw,
      );
      await expectLater(
        coldPayments.validateFinanceGroup([
          CryptoBusinessProjection(
            record: oldBody,
            raw: oldRaw,
            previousRaw: null,
            wire: oldWire,
          ),
        ], forWrite: false),
        throwsA(isA<CryptoProjectionPending>()),
      );
      expect(
        (await coldContext.record(
          personal,
          'finance',
          eventId,
          type: 'paymentProjection',
        ))!['crypto_revision'],
        restored['crypto_revision'],
      );
      await expectLater(
        coldAccess.writeContext(personal, 'finance', online: true),
        throwsA(isA<CryptoAuthorityPending>()),
      );
    },
    skip: path == null ? 'Synthetic fixture not requested' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
