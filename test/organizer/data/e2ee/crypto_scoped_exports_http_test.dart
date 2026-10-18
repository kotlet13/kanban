import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:kanban/organizer/domain/linked_payment_models.dart';
import 'package:kanban/organizer/domain/shared_finance_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart'
    show FinanceEntryKind;
import 'package:kanban/organizer/data/e2ee/crypto_scoped_exports.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_payments.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_documents.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_ack_history.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scoped_export_workflow.dart';

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
    'actual scoped export uses encrypted salted account disclosure and exact durable retries',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback required');
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
      final target = crypto.randomId();
      await context.createScope({
        'id': target,
        'kind': 'project',
        'name': 'PRIVATE_TARGET_NAME',
        'address': '',
        'parentScopeId': source,
        'requestId': crypto.randomId(),
      });
      final workflow = CryptoScopedExportWorkflow(context);
      final targetHead = await access.currentHead(target, online: true);
      await access.withVerifiedOperation(() async {
        await access.currentHead(target, online: true);
        int gets() => transport.operations
            .where((op) => op == 'crypto2.scope.headGet')
            .length;
        final before = gets();
        await access.currentHead(target, online: true);
        expect(gets(), before);
        access.invalidateAuthorityOperation();
        await access.currentHead(target, online: true);
        expect(gets(), greaterThan(before));
      });
      final offerId = crypto.randomId(), nonce = crypto.randomId();
      final offer = await workflow.propose(
        actionId: offerId,
        purpose: 'financeAccountChoice',
        sourceScopeId: source,
        sourceCanonicalId: ledger,
        sourceType: 'financeAccount',
        targetScopeId: target,
        targetHeadHash: targetHead.headHash,
        subjectNonce: nonce,
      );
      // A future source reserves a sealed event without publishing money.
      final entryId = await repository.createFinanceEntry(
        scopeId: source,
        accountId: ledger,
        kind: FinanceEntryKind.expense,
        amountMinor: 715,
        currency: 'EUR',
        title: 'PRIVATE_FUTURE_PAYMENT',
        occurredAt: DateTime.utc(2026, 10, 17),
      );
      await repository.syncNow();
      final futureId = crypto.randomId(),
          futureAction = crypto.randomId(),
          futureNonce = crypto.randomId(),
          batchId = crypto.randomId(),
          operationId = crypto.randomId();
      final event = {
        ...PaymentEvent(
          eventId: futureId,
          sourceScopeId: source,
          sourceEntryId: entryId,
          sourceRevision: 2,
          payerAccountId: account.directory.accountId,
          amountMinor: 715,
          currency: 'EUR',
          paidAt: DateTime.utc(2026, 10, 17),
          expectReimbursement: true,
          revision: 1,
        ).toJson(),
        'paymentFormat': 2,
        'sourceState': 'active',
      };
      final write = await access.writeContext(source, 'finance', online: true);
      final signer = await account.signingKey();
      final address = context.address(
        source,
        'finance',
        'paymentEvent',
        futureId,
      );
      late Map<String, dynamic> futureProof;
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 2,
            'identity': address.identity,
            'payload': event,
          }),
        ),
      );
      try {
        futureProof = context.codec.sealRecord(
          serverId: session.profile.serverId,
          accountId: account.directory.accountId,
          deviceId: account.deviceId,
          batchId: batchId,
          scopeId: source,
          id: address.wireId,
          type: 'paymentEvent',
          expectedRevision: 0,
          epoch: write.epoch,
          accessRevision: write.accessRevision,
          membershipHeadHash: write.headHash,
          domain: 'finance',
          contentContract: 3,
          operationId: operationId,
          previousRecordHash: cryptoZeroHash,
          deleted: false,
          plaintext: bytes,
          metadata: await context.businessMetadata(
            scopeId: source,
            domain: 'finance',
            type: 'paymentEvent',
            canonicalId: futureId,
            expectedRevision: 0,
            rawPayload: event,
          ),
          contentKey: write.key.key,
          signingKey: signer.key,
        );
      } finally {
        bytes.fillRange(0, bytes.length, 0);
        write.key.release();
        signer.release();
      }
      transport.dropOffer = true;
      Future<Map<String, dynamic>> prepareFuture() => workflow.propose(
        actionId: futureAction,
        purpose: 'paymentSource',
        sourceScopeId: source,
        sourceCanonicalId: futureId,
        sourceType: 'paymentEvent',
        targetScopeId: target,
        targetHeadHash: targetHead.headHash,
        subjectNonce: futureNonce,
        sourceProof: futureProof,
      );
      await expectLater(prepareFuture(), throwsA(isA<SocketException>()));
      final futureOffer = await prepareFuture();
      expect(
        (CryptoJson.decode(
              cryptoBase64(futureOffer['offerProof']['commandBase64']),
            )
            as Map)['sourceRecordProofHash'],
        await context.codec.digest(futureProof),
      );
      expect(
        await context.record(source, 'finance', futureId, type: 'paymentEvent'),
        isNull,
      );
      await expectLater(
        workflow.propose(
          actionId: futureAction,
          purpose: 'paymentSource',
          sourceScopeId: source,
          sourceCanonicalId: futureId,
          sourceType: 'paymentEvent',
          targetScopeId: target,
          targetHeadHash: targetHead.headHash,
          subjectNonce: crypto.randomId(),
          sourceProof: futureProof,
        ),
        throwsFormatException,
      );
      final futureDelegation = await workflow.delegate(
        actionId: crypto.randomId(),
        targetScopeId: target,
        offerProof: futureOffer['offerProof'],
      );
      final projectionAddress = context.address(
        target,
        'finance',
        'paymentProjection',
        futureId,
      );
      final targetRecord = <String, dynamic>{
        'scopeId': target,
        'domain': 'finance',
        'type': 'paymentProjection',
        'id': projectionAddress.wireId,
        'batchId': batchId,
        'operationId': operationId,
        'expectedRevision': 0,
        'membershipHeadHash': targetHead.headHash,
        'accountId': account.directory.accountId,
        'deviceId': account.deviceId,
        'metadata': {'identity': projectionAddress.identity},
      };
      final bindingAction = crypto.randomId();
      Future<Map<String, dynamic>> prepareBinding(
        CryptoScopedExportWorkflow service,
      ) => service.prepareBatchCertificate(
        actionId: bindingAction,
        targetScopeId: target,
        offerActionId: futureAction,
        delegationProof: futureDelegation['delegationProof'],
        sourceProof: futureProof,
        sourceRaw: event,
        targetRecord: targetRecord,
      );
      final prepared = await prepareBinding(workflow);
      final recreated = await prepareBinding(
        CryptoScopedExportWorkflow(context),
      );
      expect(prepared, recreated);
      final certBody =
          CryptoJson.decode(
                cryptoBase64(
                  prepared['binding']['certificateProof']['commandBase64'],
                ),
              )
              as Map;
      expect(certBody['batchContext']['batchId'], batchId);
      expect(certBody['batchContext']['targetId'], projectionAddress.wireId);
      expect(jsonEncode(certBody), isNot(contains('"amountMinor":715')));
      expect(
        jsonEncode(certBody),
        isNot(contains(prepared['witness']['disclosureSaltBase64'] as String)),
      );
      expect(
        await account.store.secure.read(
          'scopedExport2:${context.partition}:$target:paymentSource:${certBody['subjectToken']}',
        ),
        isNull,
      );
      expect(
        await context.record(source, 'finance', futureId, type: 'paymentEvent'),
        isNull,
      );
      await expectLater(
        workflow.prepareBatchCertificate(
          actionId: bindingAction,
          targetScopeId: target,
          offerActionId: futureAction,
          delegationProof: futureDelegation['delegationProof'],
          sourceProof: futureProof,
          sourceRaw: event,
          targetRecord: {...targetRecord, 'expectedRevision': 1},
        ),
        throwsFormatException,
      );
      final current = await account.directory.requireFresh();
      final device = current.activeDevice(account.deviceId);
      final recipient = <String, dynamic>{
        'accountId': current.accountId,
        'deviceId': account.deviceId,
        'directoryHeadHash': current.headHash,
        'deviceSnapshotHash': current.deviceSnapshotHash,
        'encryptionPublicKeyBase64': device['encryptionKeyBase64'],
      };
      final delegationId = crypto.randomId();
      final delegation = await workflow.delegate(
        actionId: delegationId,
        targetScopeId: target,
        offerProof: offer['offerProof'],
        bridgeRecipient: recipient,
      );
      final certificateId = crypto.randomId();
      transport.dropCertificate = true;
      await expectLater(
        workflow.certify(
          actionId: certificateId,
          offerActionId: offerId,
          targetScopeId: target,
          delegationProof: delegation['delegationProof'],
        ),
        throwsA(isA<SocketException>()),
      );
      final reopened = CryptoScopedExportWorkflow(
        CryptoBusinessSession(
          account,
          SessionCryptoAccess(account: account),
          db,
        ),
      );
      final certificate = await reopened.certify(
        actionId: certificateId,
        offerActionId: offerId,
        targetScopeId: target,
        delegationProof: delegation['delegationProof'],
      );
      final opened = await CryptoScopedExports(access).openBridge(
        targetScopeId: target,
        purpose: 'financeAccountChoice',
        delegationProof: delegation['delegationProof'],
        certificateProof: certificate['certificateProof'],
      );
      expect(opened.disclosure['name'], 'PRIVATE_ACCOUNT_SENTINEL');
      expect(opened.disclosure['accountId'], ledger);
      final publicBody =
          CryptoJson.decode(
                cryptoBase64(certificate['certificateProof']['commandBase64']),
              )
              as Map;
      expect(
        jsonEncode(publicBody),
        isNot(contains('PRIVATE_ACCOUNT_SENTINEL')),
      );
      expect(
        jsonEncode(publicBody),
        isNot(contains(offer['disclosureSaltBase64'] as String)),
      );
      expect(
        publicBody['disclosureHash'],
        isNot(await CryptoBusinessJson.hash(opened.disclosure)),
      );
      final repeated =
          await CryptoScopedExportWorkflow(
            CryptoBusinessSession(
              account,
              SessionCryptoAccess(account: account),
              db,
            ),
          ).certify(
            actionId: certificateId,
            offerActionId: offerId,
            targetScopeId: target,
            delegationProof: delegation['delegationProof'],
          );
      expect(repeated['requestId'], certificate['requestId']);
      expect(repeated['certificateProof'], certificate['certificateProof']);
      await expectLater(
        workflow.propose(
          actionId: offerId,
          purpose: 'financeAccountChoice',
          sourceScopeId: source,
          sourceCanonicalId: ledger,
          sourceType: 'financeAccount',
          targetScopeId: target,
          targetHeadHash: targetHead.headHash,
          subjectNonce: crypto.randomId(),
        ),
        throwsFormatException,
      );
      final payments = CryptoBusinessPayments(context);
      context.prepareHistoricalPayload = CryptoBusinessDocuments(
        context,
      ).prepareRecords;
      context.validateHistoricalPayload = payments.validateHistoryPayload;
      context.prepareRecords = payments.prepareRecords;
      context.references = payments.references;
      context.validateRaw = payments.validateRaw;
      context.projectExtension = payments.projectRecord;
      context.supportsFinanceExtension = payments.supportsType;
      context.validateFinanceExtension = payments.validateFinanceGroup;
      final actualEventId = crypto.randomId();
      final committed = await payments.dispatch('finance3.paymentCommit', {
        'scopeId': source,
        'entryId': entryId,
        'expectedEntryRevision': 1,
        'eventId': actualEventId,
        'paidAt': DateTime.utc(2026, 10, 17).toIso8601String(),
        'expectReimbursement': true,
        'requestId': crypto.randomId(),
      });
      expect(committed['event']['sourceRevision'], 2);
      expect(committed['event']['reimbursements'], isEmpty);
      final refundParams = <String, Object?>{
        'scopeId': source,
        'eventId': actualEventId,
        'expectedRevision': 1,
        'legId': crypto.randomId(),
        'amountMinor': 200,
        'paidAt': DateTime.utc(2026, 10, 17).toIso8601String(),
        'organizationAccountId': ledger,
        'requestId': crypto.randomId(),
      };
      transport.dropBatch = true;
      await expectLater(
        payments.dispatch('finance3.paymentReimburse', refundParams),
        throwsA(isA<SocketException>()),
      );
      final refunded = await payments.dispatch(
        'finance3.paymentReimburse',
        refundParams,
      );
      expect(refunded['event']['revision'], 2);
      expect(refunded['event']['reimbursements'], hasLength(1));
      final cash = await context.record(
        source,
        'finance',
        refundParams['legId'] as String,
        type: 'cashMovement',
      );
      expect(jsonDecode(cash!['raw_payload'] as String)['amountMinor'], -200);
      final replay = await payments.dispatch(
        'finance3.paymentReimburse',
        refundParams,
      );
      expect(replay['event'], refunded['event']);
      expect(
        (await context.record(
          source,
          'finance',
          refundParams['legId'] as String,
          type: 'cashMovement',
        ))!['crypto_revision'],
        1,
      );
      final eventWireId = context
          .address(source, 'finance', 'paymentEvent', actualEventId)
          .wireId;
      Future<Map<String, dynamic>> eventWire(
        int revision,
      ) async => Map<String, dynamic>.from(
        jsonDecode(
              (await db.rows(
                    'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
                    [
                      context.partition,
                      source,
                      'finance',
                      eventWireId,
                      revision,
                    ],
                  )).single['wire']
                  as String,
            )
            as Map,
      );
      final event1 = await eventWire(1), event2 = await eventWire(2);
      final originalEventProof = Map<String, dynamic>.from(
        (event1['authorization'] as Map)['recordProof'] as Map,
      );
      final currentEvent = (await context.record(
        source,
        'finance',
        actualEventId,
        type: 'paymentEvent',
      ))!;
      await requireAuthenticatedBusinessAckAncestor(
        access: access,
        database: db,
        currentRecord: currentEvent,
        stagedProof: originalEventProof,
      );
      final retainedEvent1 = (await db.rows(
        'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=1',
        [context.partition, source, 'finance', eventWireId],
      )).single['wire'];
      await db.execute(
        'DELETE FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=1',
        [context.partition, source, 'finance', eventWireId],
      );
      for (final table in [
        'crypto_business_ack_history',
        'crypto_business_history_proofs',
      ]) {
        if ((await db.rows(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [table],
        )).isNotEmpty) {
          await db.execute(
            'DELETE FROM $table WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=1',
            [context.partition, source, 'finance', eventWireId],
          );
        }
      }
      transport.withholdHistory = true;
      await expectLater(
        requireAuthenticatedBusinessAckAncestor(
          access: access,
          database: db,
          currentRecord: currentEvent,
          stagedProof: originalEventProof,
        ),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      transport.withholdHistory = false;
      transport.substituteHistory = true;
      await expectLater(
        requireAuthenticatedBusinessAckAncestor(
          access: access,
          database: db,
          currentRecord: currentEvent,
          stagedProof: originalEventProof,
        ),
        throwsFormatException,
      );
      transport.substituteHistory = false;
      await db.execute(
        'INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict,error) VALUES(?,?,?,?,?,?,?,?,NULL)',
        [
          context.partition,
          source,
          'finance',
          eventWireId,
          1,
          event1['sequence'],
          retainedEvent1,
          'verified',
        ],
      );
      expect(
        (await context.record(
          source,
          'finance',
          refundParams['legId'] as String,
          type: 'cashMovement',
        ))!['crypto_revision'],
        1,
      );

      final manager = ScopeCryptoManager(access);
      final rotation = await manager.reviewRotation(source);
      final successor = await manager.confirmRotation(
        rotation,
        acceptedCandidateHistory: true,
      );
      expect(successor.epoch, 2);
      final chain = await access.openHistoryChain(event2);
      expect(chain.nextRevision, 1);
      await expectLater(
        chain.authority({...event1, 'revision': 99}),
        throwsFormatException,
      );
      expect(
        chain.nextRevision,
        1,
        reason: 'rejected predecessor cannot advance the token',
      );
      final oldAuthority = await chain.authority(event1);
      expect(oldAuthority.currentEpoch, false);
      expect(chain.complete, true);
      final invalidated = await access.openHistoryChain(event2);
      access.invalidateAuthorityOperation();
      await expectLater(
        invalidated.authority(event1),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(invalidated.nextRevision, 1);
      final event2Body =
          CryptoJson.decode(
                cryptoBase64(
                  event2['authorization']['recordProof']['commandBase64'],
                ),
              )
              as Map;
      final reference = Map<String, dynamic>.from(
        (event2Body['metadata']['referenceVersions'] as List).single as Map,
      );
      final dependency = await access.openHistoryChain(
        event2,
        reference: reference,
      );
      expect(dependency.nextRevision, 2);
      await expectLater(
        access.openHistoryChain(
          event2,
          reference: {...reference, 'revision': 1},
        ),
        throwsFormatException,
      );
      // A currently approved content signature cannot make an unanchored
      // old finance reference a historical authority capability.
      final financeWire = context
          .address(source, 'finance', 'financeEntry', entryId)
          .wireId;
      final finance1 = Map<String, dynamic>.from(
        jsonDecode(
              (await db.rows(
                    'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=1',
                    [context.partition, source, 'finance', financeWire],
                  )).single['wire']
                  as String,
            )
            as Map,
      );
      final finance1Hash = await context.codec.digest(
        Map<String, dynamic>.from(
          finance1['authorization']['recordProof'] as Map,
        ),
      );
      final forgedReference = <String, dynamic>{
        'scopeId': source,
        'domain': 'finance',
        'id': financeWire,
        'revision': 1,
        'recordProofHash': finance1Hash,
      };
      final content = await access.writeContext(
        source,
        'content',
        online: true,
      );
      final contentSigner = await account.signingKey();
      final carrierId = crypto.randomId(), carrierBatch = crypto.randomId();
      final carrierAddress = context.address(
        source,
        'content',
        'householdPerson',
        carrierId,
      );
      final carrierMetadata = <String, dynamic>{
        'identity': carrierAddress.identity,
        'references': [
          {'scopeId': source, 'id': financeWire},
        ],
        'referenceVersions': [forgedReference],
        'blobIds': <String>[],
        'uniqueRefs': <String>[],
      };
      final carrierBytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 2,
            'identity': carrierAddress.identity,
            'payload': {'name': 'Signed current carrier'},
          }),
        ),
      );
      late Map<String, dynamic> carrierProof, carrierCommitment;
      try {
        carrierProof = context.codec.sealRecord(
          serverId: session.profile.serverId,
          accountId: account.directory.accountId,
          deviceId: account.deviceId,
          batchId: carrierBatch,
          scopeId: source,
          id: carrierAddress.wireId,
          type: 'householdPerson',
          expectedRevision: 0,
          epoch: content.epoch,
          accessRevision: content.accessRevision,
          membershipHeadHash: content.headHash,
          domain: 'content',
          contentContract: 6,
          operationId: crypto.randomId(),
          previousRecordHash: cryptoZeroHash,
          deleted: false,
          plaintext: carrierBytes,
          metadata: carrierMetadata,
          contentKey: content.key.key,
          signingKey: contentSigner.key,
        );
        carrierCommitment = await context.codec.commitBatch(
          serverId: session.profile.serverId,
          accountId: account.directory.accountId,
          deviceId: account.deviceId,
          batchId: carrierBatch,
          records: [carrierProof],
          signingKey: contentSigner.key,
          projectionToken: (record) async =>
              context.codec.projectionGroupToken(record, content.key.key),
        );
      } finally {
        carrierBytes.fillRange(0, carrierBytes.length, 0);
        content.key.release();
        contentSigner.release();
      }
      final carrierBody =
          CryptoJson.decode(cryptoBase64(carrierProof['commandBase64'])) as Map;
      final carrierWire = <String, dynamic>{
        'scopeId': source,
        'id': carrierAddress.wireId,
        'type': 'householdPerson',
        'revision': 1,
        'sequence': 1,
        'deleted': false,
        'epoch': carrierBody['epoch'],
        'envelopeBase64': carrierBody['envelopeBase64'],
        'metadata': carrierMetadata,
        'authorization': {
          'recordProof': carrierProof,
          'batchCommitment': carrierCommitment,
        },
      };
      final unsafeJump = await access.openHistoryChain(
        carrierWire,
        reference: forgedReference,
      );
      await expectLater(unsafeJump.authority(finance1), throwsFormatException);
      expect(
        unsafeJump.nextRevision,
        1,
        reason:
            'a foreign/domain signed reference is not a target history anchor',
      );
      final independentTarget = await access.referenceAnchorCandidate(
        forgedReference,
      );
      expect(independentTarget!['revision'], 2);
      final safeDescent = await access.openHistoryChain(
        carrierWire,
        reference: forgedReference,
        referenceAnchorWire: independentTarget,
      );
      expect(safeDescent.nextRevision, 1);
      await safeDescent.authority(finance1);
      expect(safeDescent.complete, true);
      // Retain an immutable refund fact with its actual encrypted issuer
      // witness, then rotate. This transport slice tests historical witness
      // authority; the existing payment UI dispatch above produced the money.
      final historicalOfferAction = crypto.randomId();
      final historicalOffer = await workflow.propose(
        actionId: historicalOfferAction,
        purpose: 'paymentSource',
        sourceScopeId: source,
        sourceCanonicalId: actualEventId,
        sourceType: 'paymentEvent',
        targetScopeId: source,
        targetHeadHash: successor.headHash,
        subjectNonce: crypto.randomId(),
      );
      final historicalDelegation = await workflow.delegate(
        actionId: crypto.randomId(),
        targetScopeId: source,
        offerProof: historicalOffer['offerProof'],
      );
      final historicalCertificate = await workflow.certify(
        actionId: crypto.randomId(),
        offerActionId: historicalOfferAction,
        targetScopeId: source,
        delegationProof: historicalDelegation['delegationProof'],
      );
      final cashId = refundParams['legId'] as String;
      final cashBefore = (await context.record(
        source,
        'finance',
        cashId,
        type: 'cashMovement',
      ))!;
      final cashRaw = Map<String, dynamic>.from(
        jsonDecode(cashBefore['raw_payload'] as String) as Map,
      );
      final witness = <String, dynamic>{
        'version': 2,
        'delegationProof': historicalDelegation['delegationProof'],
        'certificateProof': historicalCertificate['certificateProof'],
        'disclosureSaltBase64': historicalCertificate['disclosureSaltBase64'],
        'disclosure': historicalCertificate['disclosure'],
      };
      final cashAddress = context.address(
        source,
        'finance',
        'cashMovement',
        cashId,
      );
      final cashWrite = await access.writeContext(
        source,
        'finance',
        online: true,
      );
      final cashSigner = await account.signingKey();
      final cashBatch = crypto.randomId();
      late Map<String, dynamic> cashProof, cashCommitment;
      final witnessBytes = CryptoBusinessJson.encode({
        'format': 2,
        'identity': cashAddress.identity,
        'payload': {...cashRaw, 'paymentSourceWitness': witness},
      });
      try {
        cashProof = context.codec.sealRecord(
          serverId: session.profile.serverId,
          accountId: account.directory.accountId,
          deviceId: account.deviceId,
          batchId: cashBatch,
          scopeId: source,
          id: cashAddress.wireId,
          type: 'cashMovement',
          expectedRevision: 1,
          epoch: cashWrite.epoch,
          accessRevision: cashWrite.accessRevision,
          membershipHeadHash: cashWrite.headHash,
          domain: 'finance',
          contentContract: 3,
          operationId: crypto.randomId(),
          previousRecordHash: cashBefore['record_proof_hash'] as String,
          deleted: false,
          plaintext: witnessBytes,
          metadata: await context.businessMetadata(
            scopeId: source,
            domain: 'finance',
            type: 'cashMovement',
            canonicalId: cashId,
            expectedRevision: 1,
            rawPayload: cashRaw,
            uniqueRefs:
                ((jsonDecode(
                              (await db.rows(
                                    'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=1',
                                    [
                                      context.partition,
                                      source,
                                      'finance',
                                      cashAddress.wireId,
                                    ],
                                  )).single['wire']
                                  as String,
                            )
                            as Map)['metadata']['uniqueRefs']
                        as List)
                    .cast<String>(),
          ),
          contentKey: cashWrite.key.key,
          signingKey: cashSigner.key,
        );
        cashCommitment = await context.codec.commitBatch(
          serverId: session.profile.serverId,
          accountId: account.directory.accountId,
          deviceId: account.deviceId,
          batchId: cashBatch,
          records: [cashProof],
          signingKey: cashSigner.key,
          projectionToken: (record) async =>
              context.codec.projectionGroupToken(record, cashWrite.key.key),
        );
      } finally {
        witnessBytes.fillRange(0, witnessBytes.length, 0);
        cashWrite.key.release();
        cashSigner.release();
      }
      final witnessRequest = await context.queue.enqueueBatch(
        batchId: cashBatch,
        recordProofs: [cashProof],
        commitment: cashCommitment,
        applyLocal: () async {},
      );
      await context.queue.resumeUnresolved(requestIds: {witnessRequest});
      final cashHead = await access.currentHead(source, online: true);
      final cashResponse = await account.directory
          .call('crypto2.records.historyGet', {
            'scopeId': source,
            'domain': 'finance',
            'accessRevision': cashHead.accessRevision,
            'id': cashAddress.wireId,
            'revision': 2,
            'recordProofHash': await context.codec.digest(cashProof),
          });
      final historicalCashWire = Map<String, dynamic>.from(
        cashResponse['record'] as Map,
      );
      await expectLater(
        CryptoScopedExports(access).verifyHistoricalTarget(historicalCashWire),
        throwsA(isA<CryptoAuthorityPending>()),
        reason: 'a current carrier alone cannot establish historical timing',
      );
      final nextRotation = await manager.reviewRotation(source);
      await manager.confirmRotation(
        nextRotation,
        acceptedCandidateHistory: true,
      );
      final sourceFloorKey =
          'scopedExport2:${context.partition}:$source:paymentSource:${historicalCertificate['disclosure'] == null ? '' : (CryptoJson.decode(cryptoBase64(historicalCertificate['certificateProof']['commandBase64'])) as Map)['subjectToken']}';
      final retainedFloor = await account.store.secure.read(sourceFloorKey);
      final historicalResult = await CryptoScopedExports(
        SessionCryptoAccess(account: account),
      ).verifyHistoricalTarget(historicalCashWire);
      expect(historicalResult.historicalEvidence, true);
      expect(historicalResult.disclosure['eventId'], actualEventId);
      final historicalBody = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(cashProof['commandBase64'])) as Map,
      );
      final historicalKey = await access.getScopeKey(
        source,
        'finance',
        historicalBody['epoch'],
      );
      Uint8List? historicalPlain;
      try {
        historicalPlain = context.codec.openVerified(
          historicalBody,
          historicalKey.key,
        );
        final incoming = CryptoProjectionRecord(
          historicalCashWire,
          historicalBody,
          historicalPlain,
          historyBasis: 'verifiedCheckpoint',
          batchKey: cashBatch,
        );
        await payments.prepareRecords([incoming]);
        final historicalRaw = Map<String, dynamic>.from(
          (jsonDecode(utf8.decode(historicalPlain!)) as Map)['payload'] as Map,
        );
        await payments.validateFinanceGroup([
          CryptoBusinessProjection(
            record: historicalBody,
            raw: historicalRaw,
            previousRaw: cashRaw,
            wire: historicalCashWire,
          ),
        ], forWrite: false);
      } finally {
        historicalPlain?.fillRange(0, historicalPlain.length, 0);
        historicalKey.release();
      }
      expect(await account.store.secure.read(sourceFloorKey), retainedFloor);
      await expectLater(
        CryptoScopedExports(
          access,
        ).verifyHistoricalTarget({...historicalCashWire, 'revision': 3}),
        throwsFormatException,
      );
      final personalReply = await context.ensurePersonal({
        'id': crypto.randomId(),
      });
      final personal = personalReply['scope']['id'] as String;
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
      final projectParams = <String, Object?>{
        'scopeId': source,
        'eventId': actualEventId,
        'expectedRevision': 2,
        'personalTarget': {'scopeId': personal, 'accountId': privateAccount},
        'requestId': crypto.randomId(),
      };
      final caughtUp = await payments.dispatch(
        'finance3.paymentProject',
        projectParams,
      );
      expect(
        caughtUp['projectionPending'],
        false,
        reason:
            payments.lastPendingCode ??
            jsonEncode(
              await db.rows(
                "SELECT verdict,error FROM crypto_received WHERE error IS NOT NULL",
              ),
            ),
      );
      final projection = (await context.record(
        personal,
        'finance',
        actualEventId,
        type: 'paymentProjection',
      ))!;
      final projectionRaw =
          jsonDecode(projection['raw_payload'] as String) as Map;
      expect(projectionRaw['state'], 'complete');
      expect(projectionRaw['cashManifest']['count'], 2);
      expect(
        (await db.rows(
          "SELECT id FROM crypto_business_records WHERE partition=? AND scope_id=? AND type='cashMovement'",
          [context.partition, personal],
        )).length,
        2,
      );
      final projectionRevision = projection['crypto_revision'];
      final retryPayments = CryptoBusinessPayments(context);
      context.prepareRecords = retryPayments.prepareRecords;
      context.validateFinanceExtension = retryPayments.validateFinanceGroup;
      final repeatedCatchup = await retryPayments.dispatch(
        'finance3.paymentProject',
        projectParams,
      );
      expect(repeatedCatchup['projectionPending'], false);
      expect(
        (await context.record(
          personal,
          'finance',
          actualEventId,
          type: 'paymentProjection',
        ))!['crypto_revision'],
        projectionRevision,
      );
      final secondRefund = <String, Object?>{
        ...refundParams,
        'expectedRevision': 2,
        'legId': crypto.randomId(),
        'amountMinor': 100,
        'requestId': crypto.randomId(),
      };
      await retryPayments.dispatch('finance3.paymentReimburse', secondRefund);
      transport.dropBatch = true;
      await expectLater(
        retryPayments.dispatch('finance3.paymentProject', projectParams),
        throwsA(isA<SocketException>()),
      );
      final thirdRefund = <String, Object?>{
        ...refundParams,
        'expectedRevision': 3,
        'legId': crypto.randomId(),
        'amountMinor': 50,
        'requestId': crypto.randomId(),
      };
      await retryPayments.dispatch('finance3.paymentReimburse', thirdRefund);
      final afterRestart = CryptoBusinessPayments(context);
      context.prepareRecords = afterRestart.prepareRecords;
      context.validateFinanceExtension = afterRestart.validateFinanceGroup;
      final converged = await afterRestart.dispatch(
        'finance3.paymentProject',
        projectParams,
      );
      expect(converged['projectionPending'], false);
      expect(converged['event']['revision'], 4);
      final caughtUpLatest = (await context.record(
        personal,
        'finance',
        actualEventId,
        type: 'paymentProjection',
      ))!;
      final latestRaw =
          jsonDecode(caughtUpLatest['raw_payload'] as String) as Map;
      expect(latestRaw['state'], 'complete');
      expect(latestRaw['cashManifest']['count'], 4);
      for (final id in [
        actualEventId,
        refundParams['legId'],
        secondRefund['legId'],
        thirdRefund['legId'],
      ]) {
        expect(
          (await context.record(
            personal,
            'finance',
            id as String,
            type: 'cashMovement',
          ))!['crypto_revision'],
          1,
        );
      }
      final convergedAgain = await afterRestart.dispatch(
        'finance3.paymentProject',
        projectParams,
      );
      expect(convergedAgain['projectionPending'], false);
      expect(
        (await context.record(
          personal,
          'finance',
          actualEventId,
          type: 'paymentProjection',
        ))!['crypto_revision'],
        caughtUpLatest['crypto_revision'],
      );
      final lastGroups = await db.rows(
        "SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain='finance'",
        [context.partition, personal],
      );
      for (final row in lastGroups) {
        final public = jsonDecode(row['wire'] as String) as Map;
        final metadata = public['metadata'] as Map;
        expect(
          (metadata['references'] as List).every(
            (r) => r['scopeId'] == personal,
          ),
          true,
        );
        expect(jsonEncode(metadata), isNot(contains(entryId)));
        expect(jsonEncode(metadata), isNot(contains('PRIVATE_PAYER_BANK')));
      }
      await expectLater(
        CryptoScopedExports(access).verify(
          targetScopeId: source,
          purpose: 'paymentSource',
          disclosure: Map<String, dynamic>.from(witness['disclosure'] as Map),
          disclosureSaltBase64: witness['disclosureSaltBase64'],
          delegationProof: Map<String, dynamic>.from(
            witness['delegationProof'] as Map,
          ),
          certificateProof: Map<String, dynamic>.from(
            witness['certificateProof'] as Map,
          ),
        ),
        throwsFormatException,
      );
      await expectLater(
        CryptoScopedExports(access).verify(
          targetScopeId: target,
          purpose: 'financeAccountChoice',
          disclosure: {...opened.disclosure, 'name': 'SUBSTITUTED'},
          disclosureSaltBase64: offer['disclosureSaltBase64'],
          delegationProof: delegation['delegationProof'],
          certificateProof: certificate['certificateProof'],
        ),
        throwsFormatException,
      );
    },
    skip: path == null ? 'Synthetic loopback fixture not requested' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
