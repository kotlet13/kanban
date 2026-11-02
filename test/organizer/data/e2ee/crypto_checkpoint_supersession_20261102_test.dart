import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_checkpoint_supersession.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_checkpoint_publisher.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/payment_completion_diagnostics.dart';
import 'package:sodium/sodium.dart';

const scope = '10000000-0000-4000-8000-000000000001';

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Directory extends AccountDirectoryRepository {
  _Directory({
    required super.reducer,
    required super.session,
    required super.transport,
    required super.store,
  }) : super(isCurrent: () => true);
  late VerifiedAccountDirectory verified;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => verified;
}

class _Head implements VerifiedScopeHead {
  _Head(this.headHash, this.epoch, this.accessRevision, String previous)
    : body = {'previousHeadHash': previous};
  @override
  final String headHash;
  @override
  final int epoch, accessRevision;
  @override
  final Map<String, dynamic> body;
  @override
  String get scopeId => scope;
  @override
  bool get active => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access extends SessionCryptoAccess {
  _Access({required super.account, required this.signing});
  final KeyPair signing;
  late VerifiedScopeHead old, head;
  VerifiedAccountDirectory get verified =>
      (account.directory as _Directory).verified;
  bool historyMissing = false;
  @override
  Future<VerifiedScopeHead> currentHead(
    String id, {
    bool online = false,
  }) async => head;
  @override
  Future<VerifiedScopeHead> headAt(
    String id,
    String hash, {
    bool online = false,
  }) async {
    if ((historyMissing && hash == old.headHash) ||
        (hash != old.headHash && hash != head.headHash)) {
      throw const CryptoAuthorityPending('scope_history_pending');
    }
    return hash == old.headHash ? old : head;
  }

  @override
  Future<CryptoReadContext> readContext(String id, String domain) async =>
      CryptoReadContext(
        epoch: head.epoch,
        accessRevision: head.accessRevision,
        headHash: head.headHash,
      );
  // Transport acquisition is synthetic; directory reducers, signed scope
  // proposal/activation chains and checkpoint verification are production code.
  @override
  Future<VerifiedAccountDirectory> directoryAt({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    bool online = false,
    bool allowUnverifiedContact = false,
  }) async {
    if (directoryHeadHash != verified.headHash ||
        accountId != verified.accountId) {
      throw const CryptoAuthorityPending('directory_proof_pending');
    }
    return verified;
  }
}

class _Wire implements CollaborationTransport {
  int lookups = 0;
  bool denied = false;
  String outcome = 'unknown';
  Future<void> Function()? afterLookup;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    expect(operation, 'crypto2.receipt.get');
    lookups++;
    await afterLookup?.call();
    if (denied) throw const CollaborationApiException('permission_revoked');
    return {'outcome': outcome};
  }

  @override
  void close() {}
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(super.account, super.access, super.db);
  late CryptoSyncRepository commands;
  @override
  CryptoSyncRepository get queue => commands;
}

Future<
  ({_Runtime runtime, _Access access, _Wire wire, String old, String next})
>
_fixture() async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final crypto = CryptoCodec(await SodiumInit.init());
  final signing = crypto.sodium.crypto.sign.keyPair();
  addTearDown(signing.secretKey.dispose);
  final session = DeviceSession(
    AccountSession(
      serverUrl: 'https://synthetic.invalid',
      serverId: crypto.randomId(),
      accountId: crypto.randomId(),
      userId: 1,
      username: 'Synthetic',
      displayName: 'Synthetic',
      deviceId: crypto.randomId(),
      expiresAt: DateTime.utc(2030),
    ),
    'synthetic-token',
  );
  final wire = _Wire();
  final directory = _Directory(
    reducer: AccountDirectoryV2(crypto),
    session: session,
    transport: wire,
    store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
  );
  final root = crypto.sodium.crypto.sign.keyPair(),
      box = crypto.sodium.crypto.box.keyPair(),
      deviceBox = crypto.sodium.crypto.box.keyPair();
  addTearDown(root.secretKey.dispose);
  addTearDown(box.secretKey.dispose);
  addTearDown(deviceBox.secretKey.dispose);
  final epoch = crypto.randomId();
  directory.verified = (await AccountDirectoryV2(crypto).prepare(
    previous: null,
    serverId: session.profile.serverId,
    accountId: session.profile.accountId,
    deviceId: session.profile.deviceId,
    identityEpochId: epoch,
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
  )).result;
  final account = AccountCryptoV2Workflow(directory);
  final access = _Access(account: account, signing: signing);
  final codec = ScopeCryptoCodec(crypto);
  final member = {
    'accountId': directory.verified.accountId,
    'rootSigningKeyBase64': base64Encode(root.publicKey),
    'rootEncryptionKeyBase64': base64Encode(box.publicKey),
    'recoveryRootEpochId': epoch,
    'identityEpochId': epoch,
    'directoryHeadHash': directory.verified.headHash,
    'deviceSnapshotHash': directory.verified.deviceSnapshotHash,
    'role': 'owner',
    'financeRole': 'none',
    'manageKeys': true,
  };
  Map<String, dynamic> command(
    String operation,
    Map<String, dynamic> payload,
  ) => {
    'version': 2,
    'operation': operation,
    'requestId': crypto.randomId(),
    'serverId': session.profile.serverId,
    'accountId': session.profile.accountId,
    'deviceId': session.profile.deviceId,
    'signer': 'device',
    'payload': payload,
  };
  Future<VerifiedScopeHead> makeHead(VerifiedScopeHead? previous) async {
    final body = <String, dynamic>{
      'scopeId': scope,
      'epoch': (previous?.epoch ?? 0) + 1,
      'previousHeadHash': previous?.headHash ?? cryptoZeroHash,
      'initialLifecycleHash': '1' * 64,
      'previousLifecycleHash': previous == null ? null : cryptoZeroHash,
      'accessRevision': 0,
      'expectedAccessRevision': 0,
      'accessBasis': [
        {'scopeToken': '2' * 64, 'accessRevision': 0},
      ],
      'authorDirectoryHeadHash': directory.verified.headHash,
      'members': [member],
      'membershipIntents': [],
      'closures': {
        'content': previous == null ? null : '7' * 64,
        'finance': null,
      },
      'keyIds': {'content': crypto.randomId(), 'finance': null},
      'keyCommitments': {
        'content': previous == null ? '3' * 64 : '6' * 64,
        'finance': null,
      },
      'contentKeyProposalProof': null,
      'financeKeyProposalProof': null,
      'financePolicyIntentProof': null,
    };
    final pending = await codec.verifyProposal(
      serverId: session.profile.serverId,
      authorization: crypto.signDomain(
        command('crypto2.scope.headPut', body),
        signing.secretKey,
        cryptoDirectoryDomain,
      ),
      previous: previous,
      authorDirectory: directory.verified,
      directoryAtHead: (a, h) async => directory.verified,
      checkIdentity: (a, f) async {},
    );
    return codec.verifyActivation(
      pending: pending,
      previous: previous,
      authorization: crypto.signDomain(
        command('crypto2.scope.activate', {
          'scopeId': scope,
          'headHash': pending.headHash,
          'grantManifestHash': '8' * 64,
          'authorDirectoryHeadHash': directory.verified.headHash,
        }),
        signing.secretKey,
        cryptoDirectoryDomain,
      ),
      authorDirectory: directory.verified,
      grantManifestHash: '8' * 64,
      directoryAtHead: (a, h) async => directory.verified,
    );
  }

  access.old = await makeHead(null);
  access.head = await makeHead(access.old);
  final runtime = _Runtime(account, access, db);
  final queue = runtime.commands = CryptoSyncRepository(
    crypto: crypto,
    session: session,
    transport: wire,
    store: CryptoSyncStore(db, runtime.partition),
    signingKey: () async => CryptoKeyLease.borrowed(signing.secretKey),
    authorKey: (_) async => throw StateError('unexpected author'),
    contentKey: (_) async => throw StateError('unexpected key'),
    project: (_) async => throw StateError('unexpected projection'),
    isCurrent: () => true,
  );
  final payload = {
    'scopeId': scope,
    'domain': 'content',
    'epoch': 1,
    'accessRevision': 0,
    'membershipHeadHash': access.old.headHash,
    'authorDirectoryHeadHash': directory.verified.headHash,
    'expectedSequence': 0,
    'recordCount': 0,
    'manifestHash': 'd' * 64,
    'historyBasis': 'verifiedCheckpoint',
  };
  final old = await queue.enqueueCommand(
    actionKey: 'old',
    operation: 'crypto2.domain.checkpoint',
    payload: payload,
  );
  await queue.store.outcome(old, 'blocked', {
    'outcome': 'unresolved',
    'reason': 'authority_pending',
    'code': 'scope_rotation_required',
  });
  final next = await queue.enqueueCommand(
    actionKey: 'new',
    operation: 'crypto2.domain.checkpoint',
    payload: {
      ...payload,
      'epoch': 2,
      'membershipHeadHash': access.head.headHash,
    },
  );
  final nextRow = (await queue.store.outgoing(next))!;
  final signed = jsonDecode(nextRow['signed_body'] as String);
  await queue.store.outcome(next, 'applied', {
    'requestId': next,
    'requestHash': nextRow['request_hash'],
    'authorization': signed,
    'status': 200,
    'response': {},
  });
  await queue.store.checkpoint(
    scopeId: scope,
    domain: 'content',
    epoch: 2,
    accessRevision: 0,
    transportCursor: 0,
    projectionCursor: 0,
    scopeSequence: 0,
    complete: true,
  );
  await db.execute(
    'INSERT INTO crypto_domain_checkpoints VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
    [
      runtime.partition,
      scope,
      'content',
      access.head.headHash,
      2,
      0,
      0,
      payload['manifestHash'],
      0,
      'current-snapshot',
      jsonEncode(signed),
      'verifiedCheckpoint',
    ],
  );
  return (runtime: runtime, access: access, wire: wire, old: old, next: next);
}

Future<int> _reconcile(_Runtime runtime) async =>
    CryptoCheckpointSupersession(runtime).reconcile(
      scope,
      'content',
      await runtime.access.readContext(scope, 'content'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'newer verified checkpoint locally supersedes exact inventory without rewriting old receipt',
    () async {
      final f = await _fixture();
      final before = await f.runtime.queue.store.outgoing(f.old);
      expect(
        await CryptoDomainCheckpointPublisher(
          f.runtime,
        ).publish(scope, 'content'),
        PaymentCheckpointStep.reusableCheckpoint,
      );
      expect(await f.runtime.queue.store.outgoing(f.old), before);
      final markers = await f.runtime.database.rows(
        "SELECT * FROM local_meta WHERE name LIKE 'crypto_checkpoint_superseded_v1:%'",
      );
      expect(markers, hasLength(1));
      final marker = markers.single;
      final details = jsonDecode(marker['value'] as String);
      expect(details['oldRequestHash'], before!['request_hash']);
      expect(details['newRequestId'], f.next);
      expect(
        await f.runtime.database.rows(
          "SELECT * FROM crypto_outbox_attempts WHERE event='checkpoint_superseded_locally' AND details=?",
          [marker['value']],
        ),
        hasLength(1),
      );
      expect(
        await f.runtime.database.rows('SELECT 1 FROM local_meta WHERE name=?', [
          'held_receipt_refresh_v1:${f.runtime.partition}',
        ]),
        hasLength(1),
      );
      expect(f.wire.lookups, 1);
      expect(await _reconcile(f.runtime), 0);
      expect(f.wire.lookups, 1);
    },
  );
  test(
    'new checkpoint supersession advances an existing refresh generation',
    () async {
      final f = await _fixture();
      final db = f.runtime.database;
      final key = 'held_receipt_refresh_v1:${f.runtime.partition}';
      await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        key,
        'old-full-pass-generation',
      ]);
      expect(await _reconcile(f.runtime), 1);
      final value =
          (await db.rows('SELECT value FROM local_meta WHERE name=?', [
                key,
              ])).single['value']
              as String;
      expect(value, startsWith('checkpoint:${f.old}:'));
      expect(value, isNot('old-full-pass-generation'));
      await db.execute('DELETE FROM local_meta WHERE name=? AND value=?', [
        key,
        'old-full-pass-generation',
      ]);
      expect(
        (await db.rows('SELECT value FROM local_meta WHERE name=?', [
          key,
        ])).single['value'],
        value,
      );
    },
  );
  for (final scenario in [
    'changed_inventory',
    'unverified_replacement',
    'missing_history',
    'claimed_record',
    'denied_receipt',
    'terminal_receipt',
    'changed_head',
    'changed_completion',
    'tampered_original',
    'tampered_original_signature',
    'unknown_guard',
    'changed_original_during_lookup',
  ]) {
    test('checkpoint supersession preserves held work for $scenario', () async {
      final f = await _fixture();
      final db = f.runtime.database, p = f.runtime.partition;
      if (scenario == 'changed_inventory') {
        final old = (await f.runtime.queue.store.outgoing(f.old))!;
        final proof = Map<String, dynamic>.from(
          jsonDecode(old['signed_body'] as String) as Map,
        );
        final command = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
        );
        command['payload'] = {
          ...command['payload'] as Map,
          'manifestHash': 'e' * 64,
        };
        final signed = f.runtime.codec.crypto.signDomain(
          command,
          f.access.signing.secretKey,
          cryptoDirectoryDomain,
        );
        await db.execute(
          'UPDATE crypto_outbox SET signed_body=?,request_hash=? WHERE partition=? AND request_id=?',
          [
            utf8.decode(CryptoJson.encode(signed)),
            await cryptoSha256(cryptoBase64(signed['commandBase64'])),
            p,
            f.old,
          ],
        );
      }
      if (scenario == 'unverified_replacement') {
        await db.execute(
          "UPDATE crypto_outbox SET state='pending',response=NULL WHERE partition=? AND request_id=?",
          [p, f.next],
        );
      }
      if (scenario == 'missing_history') f.access.historyMissing = true;
      if (scenario == 'claimed_record') {
        await db.execute(
          'INSERT INTO crypto_outbox_records VALUES(?,?,?,?,?,?)',
          [p, scope, 'content', 'claimed', 0, f.old],
        );
      }
      if (scenario == 'denied_receipt') f.wire.denied = true;
      if (scenario == 'terminal_receipt') f.wire.outcome = 'applied';
      if (scenario == 'changed_head') {
        f.wire.afterLookup = () async {
          f.access.head = _Head('f' * 64, 3, 0, 'b' * 64);
        };
      }
      if (scenario == 'changed_completion') {
        f.wire.afterLookup = () => db.execute(
          'UPDATE crypto_scope_state SET complete=0 WHERE partition=?',
          [p],
        );
      }
      if (scenario == 'tampered_original_signature') {
        final old = (await f.runtime.queue.store.outgoing(f.old))!;
        final proof = Map<String, dynamic>.from(
          jsonDecode(old['signed_body'] as String) as Map,
        );
        proof['signatureBase64'] = base64Encode(List<int>.filled(64, 0));
        await db.execute(
          'UPDATE crypto_outbox SET signed_body=? WHERE partition=? AND request_id=?',
          [utf8.decode(CryptoJson.encode(proof)), p, f.old],
        );
      }
      if (scenario == 'tampered_original') {
        await db.execute(
          'UPDATE crypto_outbox SET request_hash=? WHERE partition=? AND request_id=?',
          ['0' * 64, p, f.old],
        );
      }
      if (scenario == 'unknown_guard') {
        await db.execute(
          'UPDATE crypto_outbox SET response=? WHERE partition=? AND request_id=?',
          [
            jsonEncode({
              'outcome': 'unresolved',
              'reason': 'authority_pending',
              'code': 'scope_write_forbidden',
            }),
            p,
            f.old,
          ],
        );
      }
      if (scenario == 'changed_original_during_lookup') {
        f.wire.afterLookup = () => db.execute(
          'UPDATE crypto_outbox SET response=? WHERE partition=? AND request_id=?',
          [
            jsonEncode({
              'outcome': 'unresolved',
              'reason': 'authority_pending',
              'code': 'scope_write_forbidden',
            }),
            p,
            f.old,
          ],
        );
      }
      final before = await f.runtime.queue.store.outgoing(f.old);
      expect(await _reconcile(f.runtime), 0);
      expect(
        await db.rows(
          "SELECT * FROM local_meta WHERE name LIKE 'crypto_checkpoint_superseded_v1:%'",
        ),
        isEmpty,
      );
      expect(
        (await f.runtime.queue.store.outgoing(f.old))!['signed_body'],
        before!['signed_body'],
      );
      expect(
        (await f.runtime.queue.store.outgoing(f.old))!['state'],
        'blocked',
      );
    });
  }
}
