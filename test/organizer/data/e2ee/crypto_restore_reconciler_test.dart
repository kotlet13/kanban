import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_backup_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_restore_reconciler.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  Future<void> Function()? onRead;
  @override
  Future<String?> read(String p) async {
    final callback = onRead;
    onRead = null;
    await callback?.call();
    return values[p];
  }

  @override
  Future<void> write(String p, String value) async {
    values[p] = value;
  }
}

class _Transport implements CollaborationTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No network in detached verification');
}

class _Directory extends AccountDirectoryRepository {
  _Directory({
    required super.reducer,
    required super.session,
    required super.store,
    required super.isCurrent,
    required this.state,
  }) : super(transport: _Transport());
  final VerifiedAccountDirectory state;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => state;
}

void main() {
  late CryptoCodec crypto;
  late CollaborationDatabase db;
  late AccountCryptoV2Workflow account;
  late _Secure secure;
  late PreparedDirectoryMutation genesis;
  late String partition;
  late bool current;
  late KeyPair deviceSigner;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    secure = _Secure();
    current = true;
    final root = crypto.sodium.crypto.sign.keyPair(),
        box = crypto.sodium.crypto.box.keyPair(),
        signer = crypto.sodium.crypto.sign.keyPair(),
        deviceBox = crypto.sodium.crypto.box.keyPair();
    deviceSigner=signer;
    final server = crypto.randomId(),
        id = crypto.randomId(),
        device = crypto.randomId();
    try {
      genesis = await AccountDirectoryV2(crypto).prepare(
        previous: null,
        serverId: server,
        accountId: id,
        deviceId: device,
        identityEpochId: crypto.randomId(),
        operation: 'crypto2.account.initialize',
        signer: 'root',
        pinnedRootFingerprint: crypto.fingerprint(
          root.publicKey,
          box.publicKey,
        ),
        signingKey: root.secretKey,
        payload: {
          'rootSigningKeyBase64': base64Encode(root.publicKey),
          'rootEncryptionKeyBase64': base64Encode(box.publicKey),
          'deviceSigningKeyBase64': base64Encode(signer.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
          'keyringCiphertextBase64': base64Encode(Uint8List(48)),
        },
      );
    } finally {
      for (final pair in [root, box, deviceBox]) {
        pair.secretKey.dispose();
      }
    }
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid',
        serverId: server,
        accountId: id,
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        deviceId: device,
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic-not-a-token',
    );
    partition = session.profile.partition;
    final store = CryptoIdentityStore(db, secure, partition);
    final fingerprint = crypto.fingerprint(
      cryptoBase64(genesis.result.snapshot['rootSigningKeyBase64']),
      cryptoBase64(genesis.result.snapshot['rootEncryptionKeyBase64']),
    );
    await store.pinRoot(id, server, fingerprint);
    await store.append(id, genesis.entry);
    await store.remember(genesis.result, 'verified');
    account = AccountCryptoV2Workflow(
      _Directory(
        reducer: AccountDirectoryV2(crypto),
        session: session,
        store: store,
        isCurrent: () => current,
        state: genesis.result,
      ),
    );
  });
  tearDown(() async {
    deviceSigner.secretKey.dispose();
    await db.close();
  });
  Future<Map<String, dynamic>> evidence() =>
      exportCryptoEvidence(db, partition);
  Future<void> retain(Map<String, dynamic> doc, String id) =>
      fenceRestoredCryptoEvidence(db, doc, partition, id);
  test(
    'all duplicate candidates verify, merge monotonic anchors, and never install an imported outbox',
    () async {
      final proof = await evidence();
      await retain(proof, 'first');
      await retain(proof, 'second');
      final reconciler = CryptoRestoreReconciler(account),
          report = await CryptoRestoreReconciler(account).inspect();
      expect(report.backupCount, 2);
      expect(report.canReconcile, true);
      await reconciler.reconcile();
      expect(
        (await db.rows(
          'SELECT state FROM crypto_restore_fences',
        )).single['state'],
        'verified',
      );
      expect(await db.rows('SELECT * FROM crypto_outbox'), isEmpty);
      expect(
        (await account.store.anchor(
          account.directory.accountId,
        ))!['generation'],
        1,
      );
      expect(
        await db.rows('SELECT * FROM crypto_restore_evidence'),
        hasLength(2),
      );
    },
  );
  test(
    'conflicting same-generation candidates cannot lower or replace a known directory',
    () async {
      final original = await evidence(),
          bad = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      (bad['tables']['crypto_directory_entries'] as List)
              .single['command_hash'] =
          'f' * 64;
      await retain(original, 'valid');
      await retain(bad, 'conflict');
      await expectLater(
        CryptoRestoreReconciler(account).reconcile(),
        throwsFormatException,
      );
      expect(
        (await account.store.anchor(account.directory.accountId))!['headHash'],
        genesis.result.headHash,
      );
      expect(
        (await db.rows(
          'SELECT state FROM crypto_restore_fences',
        )).single['state'],
        isNot('verified'),
      );
    },
  );
  test('forged imported success is retained but cannot activate or erase an outbox', () async {
    final command={'version':2,'operation':'crypto2.inbox.preferences.set','requestId':crypto.randomId(),'serverId':account.directory.session.profile.serverId,'accountId':account.directory.accountId,'deviceId':account.deviceId,'signer':'device','payload':{'sound':true}};
    final proof=crypto.signDomain(command,deviceSigner.secretKey,cryptoDirectoryDomain),hash=await cryptoSha256(CryptoJson.encode(command));
    final doc=await evidence();
    doc['tables']['crypto_outbox']=[{'sequence':1,'partition':partition,'request_id':command['requestId'],'operation':command['operation'],'signed_body':jsonEncode(proof),'request_hash':hash,'state':'applied','response':jsonEncode({'requestId':command['requestId'],'requestHash':hash,'status':200,'response':{'success':true},'authorization':proof})}];
    await retain(doc,'claimed-success');
    await CryptoRestoreReconciler(account).reconcile();
    expect(await db.rows('SELECT * FROM crypto_outbox'),isEmpty);
    expect((await db.rows('SELECT evidence FROM crypto_restore_evidence')).single['evidence'],contains('applied'));
  });
  test('unverified foreign directory remains quarantined and cannot poison a future contact pin', () async {
    final root=crypto.sodium.crypto.sign.keyPair(),box=crypto.sodium.crypto.box.keyPair(),device=crypto.sodium.crypto.sign.keyPair(),enc=crypto.sodium.crypto.box.keyPair();
    final id=crypto.randomId();
    try {
      final foreign=await AccountDirectoryV2(crypto).prepare(previous:null,serverId:account.directory.session.profile.serverId,accountId:id,deviceId:crypto.randomId(),identityEpochId:crypto.randomId(),operation:'crypto2.account.initialize',signer:'root',pinnedRootFingerprint:crypto.fingerprint(root.publicKey,box.publicKey),signingKey:root.secretKey,payload:{'rootSigningKeyBase64':base64Encode(root.publicKey),'rootEncryptionKeyBase64':base64Encode(box.publicKey),'deviceSigningKeyBase64':base64Encode(device.publicKey),'deviceEncryptionKeyBase64':base64Encode(enc.publicKey),'keyringCiphertextBase64':base64Encode(Uint8List(48))});
      final doc=await evidence(),entry=foreign.entry;
      (doc['tables']['crypto_directory_entries'] as List).add({'partition':partition,'account_id':id,'generation':entry['generation'],'head_hash':entry['headHash'],'previous_head_hash':entry['previousHeadHash'],'command_hash':entry['commandHash'],'authorization':{'blobBase64':base64Encode(CryptoJson.encode(entry['authorization']))}});
      await retain(doc,'foreign');
      expect((await CryptoRestoreReconciler(account).inspect()).identityReviewAccounts,[id]);
      await expectLater(CryptoRestoreReconciler(account).reconcile(),throwsA(anything));
      expect(await account.store.entries(id),isEmpty);expect(await account.store.anchor(id),isNull);
    }finally {for(final pair in [root,box,device,enc]){pair.secretKey.dispose();}}
  });
  test(
    'account switch during verification cannot commit candidate authority',
    () async {
      await retain(await evidence(), 'retained');
      current = false;
      await expectLater(
        CryptoRestoreReconciler(account).reconcile(),
        throwsA(anything),
      );
      expect(
        (await db.rows(
          'SELECT state FROM crypto_restore_fences',
        )).single['state'],
        isNot('verified'),
      );
    },
  );
  test(
    'additional restore invalidates evidence CAS before secure anchor handoff',
    () async {
      final proof = await evidence();
      await retain(proof, 'first');
      secure.onRead = () => retain(proof, 'concurrent');
      await expectLater(
        CryptoRestoreReconciler(account).reconcile(),
        throwsFormatException,
      );
      expect(
        (await db.rows(
          'SELECT state FROM crypto_restore_fences',
        )).single['state'],
        isNot('verified'),
      );
      expect(
        await db.rows('SELECT * FROM crypto_restore_evidence'),
        hasLength(2),
      );
    },
  );
}
