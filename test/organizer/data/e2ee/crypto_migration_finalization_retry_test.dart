import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_generation.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:sodium/sodium.dart';

class _Transport implements CollaborationTransport {
  final receipts = <String, Map<String, dynamic>>{};
  final sent = <Map<String, dynamic>>[];
  bool withholdReceipt = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.receipt.get') {
      return receipts[params['requestId']] ?? {'outcome': 'unknown'};
    }
    if (operation != 'crypto2.migration.commit3') throw StateError(operation);
    final signed = Map<String, dynamic>.from(params);
    sent.add(signed);
    final body =
        CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
    final result = {
      'requestId': body['requestId'],
      'requestHash': await cryptoSha256(cryptoBase64(signed['commandBase64'])),
      'authorization': signed,
      'status': 200,
      'response': {'state': 'committed'},
    };
    if (!withholdReceipt) receipts[body['requestId']] = result;
    return result;
  }

  @override
  void close() {}
}

class _Directory implements AccountDirectoryRepository {
  _Directory(this.session, this.reducer, this.own, this.transport);
  @override
  final DeviceSession session;
  @override
  final AccountDirectoryV2 reducer;
  final VerifiedAccountDirectory own;
  @override
  final _Transport transport;
  late Map<String, dynamic> state, publications;
  int statusReads = 0;
  bool statusUnavailable = false;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => own;
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (operation == 'crypto2.migration.generation.status') {
      statusReads++;
      if (statusUnavailable) {
        throw StateError('status deliberately unavailable');
      }
      return state;
    }
    if (operation == 'crypto2.migration.activation.refs') return publications;
    return transport.call(
      serverUrl: session.profile.serverUrl,
      operation: operation,
      params: payload,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.directory);
  @override
  final _Directory directory;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime implements CryptoBusinessSession {
  _Runtime(this.database, this.partition, this.account, this.queue);
  @override
  final CollaborationDatabase database;
  @override
  final String partition;
  @override
  final _Account account;
  @override
  final CryptoSyncRepository queue;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    crypto = CryptoCodec(await SodiumInit.init());
  });
  late CollaborationDatabase db;
  late CryptoSyncStore store;
  late CryptoSyncRepository queue;
  late _Directory directory;
  late _Runtime runtime;
  late _Transport transport;
  late KeyPair root, box, signing, deviceBox;
  late String generation, migration, original;
  late Map<String, dynamic> payload, initialRow;
  var signatures = 0, freshDeliveryChecks = 0;
  Future<void> terminal(String state, {int status = 409}) async {
    final row = (await store.outgoing(original))!;
    final receipt = {
      'requestId': original,
      'requestHash': row['request_hash'],
      'authorization': jsonDecode(row['signed_body'] as String),
      'status': status,
      'response': status == 200
          ? {'state': 'committed'}
          : {
              'errorCode': 'crypto_member_directory_changed',
              'details': <String, dynamic>{},
            },
    };
    // Select a starting outcome for this isolated refusal fixture only.
    await db.execute(
      "UPDATE crypto_outbox SET state='pending',response=NULL WHERE request_id=?",
      [original],
    );
    if (state != 'pending') await store.outcome(original, state, receipt);
    transport.receipts[original] = receipt;
  }

  Future<int> rows() async =>
      (await db.rows('SELECT * FROM crypto_outbox')).length;
  setUp(() async {
    signatures = 0;
    freshDeliveryChecks = 0;
    db = CollaborationDatabase(NativeDatabase.memory());
    root = crypto.sodium.crypto.sign.keyPair();
    box = crypto.sodium.crypto.box.keyPair();
    signing = crypto.sodium.crypto.sign.keyPair();
    deviceBox = crypto.sodium.crypto.box.keyPair();
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: crypto.randomId(),
        accountId: crypto.randomId(),
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        deviceId: crypto.randomId(),
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic',
    );
    final reducer = AccountDirectoryV2(crypto);
    final initialized = await reducer.prepare(
      previous: null,
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
      deviceId: session.profile.deviceId,
      identityEpochId: crypto.randomId(),
      operation: 'crypto2.account.initialize',
      signer: 'root',
      pinnedRootFingerprint: crypto.fingerprint(root.publicKey, box.publicKey),
      signingKey: root.secretKey,
      payload: {
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(box.publicKey),
        'deviceSigningKeyBase64': base64Encode(signing.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
        'keyringCiphertextBase64': base64Encode(Uint8List(48)),
      },
    );
    transport = _Transport();
    directory = _Directory(session, reducer, initialized.result, transport);
    store = CryptoSyncStore(db, session.profile.partition);
    queue = CryptoSyncRepository(
      crypto: crypto,
      session: session,
      transport: transport,
      store: store,
      signingKey: () async {
        signatures++;
        return CryptoKeyLease.borrowed(signing.secretKey);
      },
      authorKey: (_) async => CryptoRecordAuthority(
        signingKey: signing.publicKey,
        currentEpoch: true,
      ),
      contentKey: (_) async => throw StateError('no records'),
      project: (_) async {},
      isCurrent: () => true,
      beforeDelivery: (_) async {
        freshDeliveryChecks++;
      },
    );
    runtime = _Runtime(db, store.partition, _Account(directory), queue);
    generation = crypto.randomId();
    migration = crypto.randomId();
    final token = '1' * 64, activation = '2' * 64;
    final context = {
      'version': 3,
      'generationId': generation,
      'serverId': session.profile.serverId,
      'migrationId': migration,
      'mode': 'continue',
      'componentId': crypto.randomId(),
      'scopes': [
        {'scopeToken': token},
      ],
      'published': [
        {'scopeToken': token, 'activationHash': activation},
      ],
    };
    final hash = await cryptoSha256([
      ...utf8.encode('JivieMigrationGenerationContext/v3\n'),
      ...CryptoJson.encode(context),
    ]);
    final approval = crypto.signDomain(
      {
        'version': 3,
        'generationId': generation,
        'migrationId': migration,
        'mode': 'continue',
        'serverId': session.profile.serverId,
        'accountId': session.profile.accountId,
        'deviceId': session.profile.deviceId,
        'deviceSnapshotHash': initialized.result.deviceSnapshotHash,
        'authorDirectoryHeadHash': initialized.result.headHash,
        'contextHash': hash,
      },
      signing.secretKey,
      CryptoMigrationGeneration.approvalDomain,
    );
    directory.state = {
      'state': 'review',
      'context': context,
      'contextHash': hash,
      'approvals': [
        {'authorization': approval},
      ],
    };
    directory.publications = {
      'version': 3,
      'migrationId': migration,
      'componentCommitment': '3' * 64,
      'inventoryCommitment': '4' * 64,
      'scopeActivations': [
        {'scopeToken': token, 'activationHash': activation},
      ],
      'hasMore': false,
    };
    await db.execute(
      'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
      [
        store.partition,
        migration,
        generation,
        'migrationGenerationApproval',
        CryptoJson.encode(approval),
      ],
    );
    payload = {
      'version': 3,
      'migrationId': migration,
      'componentId': context['componentId'],
      'componentCommitment': '3' * 64,
      'inventoryCommitment': '4' * 64,
      'scopeActivations': [
        {'scopeToken': token, 'activationHash': activation},
      ],
    };
    original = await queue.enqueueCommand(
      actionKey: 'generationCommit:$generation',
      operation: 'crypto2.migration.commit3',
      payload: payload,
    );
    await terminal('rejected');
    initialRow = Map<String, dynamic>.from((await store.outgoing(original))!);
  });
  tearDown(() async {
    await db.close();
    root.secretKey.dispose();
    box.secretKey.dispose();
    signing.secretKey.dispose();
    deviceBox.secretKey.dispose();
  });

  test(
    'explicit retry retains original and repeat/reopen reconciles exact success',
    () async {
      final api = CryptoMigrationGeneration(runtime);
      expect(await api.rejectedCommitRequest(generation), original);
      expect(
        (await api.retryRejectedCommit(
          generation,
          rejectedRequestId: original,
        ))['state'],
        'committed',
      );
      expect(await rows(), 2);
      expect(signatures, 2);
      expect(freshDeliveryChecks, 1);
      final saved = await store.outgoing(original);
      expect(saved!['signed_body'], initialRow['signed_body']);
      expect(saved['response'], initialRow['response']);
      final delivered = transport.sent.single;
      expect(
        (CryptoJson.decode(cryptoBase64(delivered['commandBase64']))
            as Map)['payload'],
        payload,
      );
      directory.statusUnavailable = true;
      final reopened = CryptoMigrationGeneration(
        _Runtime(db, store.partition, runtime.account, queue),
      );
      expect(
        (await reopened.retryRejectedCommit(
          generation,
          rejectedRequestId: original,
        ))['state'],
        'committed',
      );
      expect(
        (await reopened.resumeAcceptedCommit(generation))['state'],
        'committed',
      );
      expect(await rows(), 2);
      expect(signatures, 2);
      expect(transport.sent.length, 1);
      // Pointer missing after an enqueue interruption is recovered from immutable keys.
      await db.execute(
        "DELETE FROM local_meta WHERE name LIKE 'migration_generation_commit_attempt:%'",
      );
      expect(
        (await reopened.resumeAcceptedCommit(generation))['state'],
        'committed',
      );
      expect(await rows(), 2);
      expect(signatures, 2);
    },
  );

  test(
    'pending blocked success and unknown receipt cannot mint another request',
    () async {
      final api = CryptoMigrationGeneration(runtime);
      for (final state in ['pending', 'blocked', 'applied']) {
        await terminal(state, status: state == 'applied' ? 200 : 409);
        await expectLater(
          api.retryRejectedCommit(generation, rejectedRequestId: original),
          throwsFormatException,
        );
        expect(await rows(), 1);
      }
      await terminal('rejected', status: 403);
      await expectLater(
        api.retryRejectedCommit(generation, rejectedRequestId: original),
        throwsFormatException,
      );
      await terminal('rejected');
      transport.receipts.remove(original);
      await expectLater(
        api.retryRejectedCommit(generation, rejectedRequestId: original),
        throwsFormatException,
      );
      expect(await rows(), 1);
      expect(signatures, 1);
    },
  );

  test(
    'changed activation or approved context refuses same-intent retry',
    () async {
      final api = CryptoMigrationGeneration(runtime);
      final scopes = directory.publications['scopeActivations'] as List;
      final old = scopes.single['activationHash'];
      scopes.single['activationHash'] = '5' * 64;
      await expectLater(
        api.retryRejectedCommit(generation, rejectedRequestId: original),
        throwsFormatException,
      );
      scopes.single['activationHash'] = old;
      final context = directory.state['context'] as Map<String, dynamic>;
      context['requiredAccountTokens'] = ['6' * 64];
      directory.state['contextHash'] = await cryptoSha256([
        ...utf8.encode('JivieMigrationGenerationContext/v3\n'),
        ...CryptoJson.encode(context),
      ]);
      await expectLater(
        api.retryRejectedCommit(generation, rejectedRequestId: original),
        throwsFormatException,
      );
      expect(await rows(), 1);
      expect(signatures, 1);
    },
  );

  test(
    'unknown new attempt resumes before unavailable status and never resigns',
    () async {
      final api = CryptoMigrationGeneration(runtime);
      transport.withholdReceipt = true;
      await expectLater(
        api.retryRejectedCommit(generation, rejectedRequestId: original),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'crypto_command_receipt_pending',
          ),
        ),
      );
      final child = (await db.rows(
        'SELECT * FROM crypto_outbox WHERE request_id<>?',
        [original],
      )).single;
      expect(child['state'], 'pending');
      expect(signatures, 2);
      final signed = Map<String, dynamic>.from(
        jsonDecode(child['signed_body'] as String) as Map,
      );
      transport.receipts[child['request_id'] as String] = {
        'requestId': child['request_id'],
        'requestHash': child['request_hash'],
        'authorization': signed,
        'status': 200,
        'response': {'state': 'committed'},
      };
      directory.statusUnavailable = true;
      expect(
        (await CryptoMigrationGeneration(
          runtime,
        ).resumeAcceptedCommit(generation))['state'],
        'committed',
      );
      expect(signatures, 2);
      expect(transport.sent.length, 1);
      expect(freshDeliveryChecks, 1);
      final after = (await store.outgoing(child['request_id'] as String))!;
      expect(after['signed_body'], child['signed_body']);
      expect(after['request_hash'], child['request_hash']);
    },
  );

  test(
    'reopen rejects a pointer outside the exact linked request chain',
    () async {
      final api = CryptoMigrationGeneration(runtime);
      await api.retryRejectedCommit(generation, rejectedRequestId: original);
      final row = (await db.rows(
        "SELECT * FROM local_meta WHERE name LIKE 'migration_generation_commit_attempt:%'",
      )).single;
      final pointer =
          jsonDecode(row['value'] as String) as Map<String, dynamic>;
      pointer['requestId'] = crypto.randomId();
      await db.execute('UPDATE local_meta SET value=? WHERE name=?', [
        jsonEncode(pointer),
        row['name'],
      ]);
      await expectLater(
        CryptoMigrationGeneration(runtime).resumeAcceptedCommit(generation),
        throwsFormatException,
      );
      expect(await rows(), 2);
      expect(signatures, 2);
    },
  );
}
