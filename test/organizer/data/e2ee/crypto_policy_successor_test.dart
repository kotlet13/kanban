import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_policy.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Receipts implements CollaborationTransport {
  late Future<Map<String, dynamic>> Function(Map<String, Object?>) read;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) {
    if (operation != 'crypto2.receipt.get')
      throw StateError('No test mutation delivery');
    return read(params);
  }

  @override
  void close() {}
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
  late DeviceSession session;
  late CryptoRecordProofCodec codec;
  late KeyPair signer;
  late SecureKey key;
  late String scope, task, finance, operation;
  var applies = 0, validations = 0;
  setUp(() {
    db = CollaborationDatabase(NativeDatabase.memory());
    session = DeviceSession(
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
    store = CryptoSyncStore(db, session.profile.partition);
    codec = CryptoRecordProofCodec(crypto);
    signer = crypto.sodium.crypto.sign.keyPair();
    key = crypto.sodium.secureRandom(32);
    scope = crypto.randomId();
    task = crypto.randomId();
    finance = crypto.randomId();
    operation = crypto.randomId();
    applies = validations = 0;
    final transport = _Receipts();
    transport.read = (params) async {
      final old = (await store.outgoing(params['requestId'] as String))!;
      return {
        'requestId': old['request_id'],
        'requestHash': old['request_hash'],
        'status': 409,
        'response': {'errorCode': 'crypto_upgrade_required'},
        'authorization': jsonDecode(old['signed_body'] as String),
      };
    };
    queue = CryptoSyncRepository(
      crypto: crypto,
      session: session,
      transport: transport,
      store: store,
      signingKey: () async => CryptoKeyLease.borrowed(signer.secretKey),
      authorKey: (r) async => CryptoRecordAuthority(
        signingKey: signer.publicKey,
        currentEpoch: true,
      ),
      contentKey: (r) async => CryptoKeyLease.borrowed(key),
      project: (_) async {},
      isCurrent: () => true,
      beforeDelivery: (_) async {},
    );
  });
  tearDown(() async {
    signer.secretKey.dispose();
    key.dispose();
    await db.close();
  });

  Future<
    ({
      String id,
      List<Map<String, dynamic>> proofs,
      Map<String, dynamic> commitment,
    })
  >
  batch({
    required bool policy,
    bool paired = false,
    String title = 'retained',
    String? fixedId,
  }) async {
    final id = fixedId ?? crypto.randomId();
    final proofs = <Map<String, dynamic>>[];
    for (final domain in ['content', if (paired) 'finance']) {
      final type = domain == 'content' ? 'task' : 'financeAccount',
          canonical = domain == 'content' ? task : finance;
      final address = CryptoRecordAddress.forType(
        serverId: session.profile.serverId,
        scopeId: scope,
        domain: domain,
        type: type,
        canonicalId: canonical,
      );
      final raw = <String, dynamic>{
        if (domain == 'content') 'title': title,
        if (domain == 'finance') 'name': 'Shared',
        if (domain == 'content') 'assigneeAccountIds': <String>[],
      };
      Map<String, dynamic>? policyMetadata;
      if (policy) {
        raw[CryptoRecordPolicy.secretField] = {
          'version': 1,
          'keyBase64': base64Encode(List<int>.filled(32, 8)),
        };
        policyMetadata = await CryptoRecordPolicy.prepare(
          serverId: session.profile.serverId,
          scopeId: scope,
          domain: domain,
          wireId: address.wireId,
          type: type,
          creator: session.profile.accountId,
          operation: 'create',
          payload: raw,
        );
      }
      proofs.add(
        codec.sealRecord(
          serverId: session.profile.serverId,
          accountId: session.profile.accountId,
          deviceId: session.profile.deviceId,
          batchId: id,
          scopeId: scope,
          id: address.wireId,
          type: type,
          expectedRevision: 0,
          epoch: 1,
          accessRevision: 2,
          membershipHeadHash: 'a' * 64,
          domain: domain,
          contentContract: domain == 'content'
              ? (policy ? 7 : 6)
              : (policy ? 4 : 3),
          operationId: operation,
          previousRecordHash: '0' * 64,
          deleted: false,
          plaintext: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'format': 2,
                'identity': address.identity,
                'payload': raw,
              }),
            ),
          ),
          metadata: {
            'identity': address.identity,
            'references': <Object>[],
            'uniqueRefs': <Object>[],
            'blobIds': <Object>[],
            'notificationState': {
              'version': 1,
              'kind': 'created',
              'assigneeAccountIds': <String>[],
              'groupTargetId': null,
            },
            if (domain == 'content')
              'reminderState': {
                'version': 1,
                'dueAtEpoch': null,
                'closed': false,
                'scheduleRevision': session.profile.deviceId,
              },
            if (policyMetadata != null) 'recordPolicy': policyMetadata,
          },
          contentKey: key,
          signingKey: signer.secretKey,
        ),
      );
    }
    final commitment = await codec.commitBatch(
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
      deviceId: session.profile.deviceId,
      batchId: id,
      records: proofs,
      signingKey: signer.secretKey,
      projectionToken: (r) async => codec.projectionGroupToken(r, key),
    );
    return (id: id, proofs: proofs, commitment: commitment);
  }

  Future<String> enqueue(
    ({
      String id,
      List<Map<String, dynamic>> proofs,
      Map<String, dynamic> commitment,
    })
    value,
  ) => queue.enqueueBatch(
    batchId: value.id,
    recordProofs: value.proofs,
    commitment: value.commitment,
    applyLocal: () async {
      applies++;
    },
  );
  Future<void> authority(
    Map<String, dynamic> previous,
    Map<String, dynamic> next,
    Map<String, dynamic>? oldPayload,
    Map<String, dynamic>? nextPayload,
  ) async {
    validations++;
    expect(
      next['metadata']['recordPolicy']['createdByAccountId'],
      session.profile.accountId,
    );
    await CryptoRecordPolicy.verifyPayload(record: next, payload: nextPayload);
  }

  test(
    'policy successor requires exact terminal rejection before replacing claims',
    () async {
      final oldId = await enqueue(await batch(policy: false));
      final next = await batch(policy: true);
      await expectLater(
        queue.reauthorizeRejectedPolicyBatch(
          rejectedRequestId: oldId,
          batchId: next.id,
          recordProofs: next.proofs,
          commitment: next.commitment,
          validateAuthority: authority,
          onStaged: (_) async {},
        ),
        throwsFormatException,
      );
      expect((await store.outgoing(oldId))!['state'], 'pending');
      expect(
        (await db.rows(
          'SELECT request_id FROM crypto_outbox_records',
        )).single['request_id'],
        oldId,
      );
      expect(validations, 0);
    },
  );

  test(
    'policy successor rejects semantic user edits and retains original signed request',
    () async {
      final oldId = await enqueue(await batch(policy: false));
      await queue.deliver();
      final original = await store.outgoing(oldId);
      final next = await batch(policy: true, title: 'changed');
      await expectLater(
        queue.reauthorizeRejectedPolicyBatch(
          rejectedRequestId: oldId,
          batchId: next.id,
          recordProofs: next.proofs,
          commitment: next.commitment,
          validateAuthority: authority,
          onStaged: (_) async {},
        ),
        throwsFormatException,
      );
      expect(await store.outgoing(oldId), original);
      expect(
        (await db.rows(
          'SELECT request_id FROM crypto_outbox_records',
        )).single['request_id'],
        oldId,
      );
      expect(applies, 1);
    },
  );

  test(
    'whole-group successor claim and pointer transaction rolls back then retries once',
    () async {
      final oldId = await enqueue(await batch(policy: false, paired: true));
      await queue.deliver();
      final original = await store.outgoing(oldId);
      final next = await batch(policy: true, paired: true);
      await db.execute(
        "INSERT INTO local_meta(name,value) VALUES('business-pointer',?)",
        [oldId],
      );
      await expectLater(
        queue.reauthorizeRejectedPolicyBatch(
          rejectedRequestId: oldId,
          batchId: next.id,
          recordProofs: next.proofs,
          commitment: next.commitment,
          validateAuthority: authority,
          onStaged: (id) async {
            await db.execute(
              "UPDATE local_meta SET value=? WHERE name='business-pointer'",
              [id],
            );
            throw StateError('synthetic pointer failure');
          },
        ),
        throwsStateError,
      );
      expect(
        (await db.rows(
          'SELECT * FROM crypto_outbox_records',
        )).map((r) => r['request_id']).toSet(),
        {oldId},
      );
      expect(
        (await db.rows(
          "SELECT value FROM local_meta WHERE name='business-pointer'",
        )).single['value'],
        oldId,
      );
      expect(
        await db.rows('SELECT * FROM crypto_outbox_reconciliations'),
        isEmpty,
      );
      var bindings = 0;
      Future<void> bind(String id) async {
        bindings++;
        await db.execute(
          "UPDATE local_meta SET value=? WHERE name='business-pointer'",
          [id],
        );
      }

      final successor = await queue.reauthorizeRejectedPolicyBatch(
        rejectedRequestId: oldId,
        batchId: next.id,
        recordProofs: next.proofs,
        commitment: next.commitment,
        validateAuthority: authority,
        onStaged: bind,
      );
      expect(await store.outgoing(oldId), original);
      expect(
        (await db.rows(
          'SELECT * FROM crypto_outbox_records',
        )).map((r) => r['request_id']).toSet(),
        {successor},
      );
      expect(
        (await db.rows(
          'SELECT reason FROM crypto_outbox_reconciliations',
        )).single['reason'],
        'record_policy_upgrade',
      );
      expect(applies, 1);
      expect(
        await queue.reauthorizeRejectedPolicyBatch(
          rejectedRequestId: oldId,
          batchId: next.id,
          recordProofs: next.proofs,
          commitment: next.commitment,
          validateAuthority: authority,
          onStaged: bind,
        ),
        successor,
      );
      expect(bindings, 1);
    },
  );
}
