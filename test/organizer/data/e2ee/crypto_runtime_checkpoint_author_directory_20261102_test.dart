import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Head implements VerifiedScopeHead {
  _Head(this.body, this.headHash);
  @override
  final Map<String, dynamic> body;
  @override
  final String headHash;
  @override
  final authorization = <String, dynamic>{};
  @override
  bool get active => true;
  @override
  String get scopeId => body['scopeId'];
  @override
  int get epoch => 2;
  @override
  int get accessRevision => 0;
  @override
  List<Map<String, dynamic>> get members =>
      (body['members'] as List).cast<Map<String, dynamic>>();
  @override
  Map<String, dynamic> member(String id) =>
      members.singleWhere((m) => m['accountId'] == id);
  @override
  String? commitment(String domain) => null;
  @override
  List<Map<String, dynamic>> get invitationPreauthorizations => const [];
}

class _Transport implements CollaborationTransport {
  List<Map<String, dynamic>> entries = [];
  final reads = <Map<String, Object?>>[];
  late Map<String, dynamic> inventory;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.domain.inventory') return inventory;
    if (operation != 'crypto2.directory.read') {
      throw StateError('Unexpected operation $operation');
    }
    reads.add(Map.of(params));
    return {
      'entries': entries
          .where(
            (e) =>
                (e['generation'] as int) > (params['afterGeneration'] as int),
          )
          .toList(),
      'hasMore': false,
    };
  }

  @override
  void close() {}
}

// The real runtime checkpoint-reader callback, signed attestation, directory
// replay, descriptor hashing, role checks and persistence are exercised. The
// fixture supplies only the already authenticated scope-head boundary and scoped
// invitation context; this is not a full sync or native-session test.
class _Access extends SessionCryptoAccess {
  _Access({required super.account, required this.head});
  final _Head head;
  int verifiedCheckpoints = 0;
  final headModes = <bool>[];
  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async {
    headModes.add(online);
    return head;
  }

  @override
  Future<VerifiedScopeHead> headAt(
    String scopeId,
    String hash, {
    bool online = false,
  }) async {
    headModes.add(online);
    return head;
  }

  @override
  Future<VerifiedAccountDirectory> directoryAt({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    bool online = false,
    bool allowUnverifiedContact = false,
  }) => super.directoryAt(
    scopeId: scopeId,
    scopeHeadHash: scopeHeadHash,
    accountId: accountId,
    directoryHeadHash: directoryHeadHash,
    online: online,
    allowUnverifiedContact: true,
  );
  @override
  Future<CryptoCheckpointAuthority> verifyDomainCheckpoint(
    Map<String, dynamic> proof, {
    bool onlineAuthorDirectory = false,
  }) async {
    final result = await super.verifyDomainCheckpoint(
      proof,
      onlineAuthorDirectory: onlineAuthorDirectory,
    );
    verifiedCheckpoints++;
    return result;
  }
}

void main() {
  for (final mode in [
    'cold',
    'fork',
    'bad_signature',
    'missing_target',
    'viewer',
  ]) {
    test(
      'runtime checkpoint reader exact absent author reference $mode',
      () async {
        final crypto = CryptoCodec(await SodiumInit.init()),
            reducer = AccountDirectoryV2(crypto);
        final root = crypto.sodium.crypto.sign.keyPair(),
            device = crypto.sodium.crypto.sign.keyPair(),
            ownRoot = crypto.sodium.crypto.sign.keyPair(),
            ownDevice = crypto.sodium.crypto.sign.keyPair(),
            box = crypto.sodium.crypto.box.keyPair(),
            ownBox = crypto.sodium.crypto.box.keyPair();
        addTearDown(() {
          for (final p in [root, device, ownRoot, ownDevice, box, ownBox]) {
            p.secretKey.dispose();
          }
        });
        final server = crypto.randomId(),
            author = crypto.randomId(),
            recipient = crypto.randomId(),
            deviceId = crypto.randomId(),
            ownDeviceId = crypto.randomId(),
            epoch = crypto.randomId(),
            scope = crypto.randomId();
        Future<PreparedDirectoryMutation> init(
          String id,
          String dev,
          KeyPair r,
          KeyPair b,
          KeyPair d,
        ) => reducer.prepare(
          previous: null,
          serverId: server,
          accountId: id,
          deviceId: dev,
          identityEpochId: epoch,
          operation: 'crypto2.account.initialize',
          signer: 'root',
          pinnedRootFingerprint: crypto.fingerprint(r.publicKey, b.publicKey),
          signingKey: r.secretKey,
          payload: {
            'rootSigningKeyBase64': base64Encode(r.publicKey),
            'rootEncryptionKeyBase64': base64Encode(b.publicKey),
            'deviceSigningKeyBase64': base64Encode(d.publicKey),
            'deviceEncryptionKeyBase64': base64Encode(b.publicKey),
            'keyringCiphertextBase64': base64Encode(Uint8List(48)),
          },
        );
        final first = await init(author, deviceId, root, box, device),
            own = await init(
              recipient,
              ownDeviceId,
              ownRoot,
              ownBox,
              ownDevice,
            );
        Future<PreparedDirectoryMutation> advance(
          VerifiedAccountDirectory previous,
          String digest,
        ) => reducer.prepare(
          previous: previous,
          serverId: server,
          accountId: author,
          deviceId: deviceId,
          identityEpochId: epoch,
          operation: 'crypto2.account.projectRelocation',
          signer: 'device',
          pinnedRootFingerprint: first.result.rootFingerprint,
          signingKey: device.secretKey,
          payload: {'actionId': crypto.randomId(), 'publicationRoot': digest},
        );
        final floor = await advance(first.result, '1' * 64),
            requested = await advance(floor.result, '2' * 64),
            fork = await advance(first.result, '3' * 64);
        final session = DeviceSession(
          AccountSession(
            serverUrl: 'https://synthetic.invalid/',
            serverId: server,
            accountId: recipient,
            userId: 1,
            username: 'synthetic',
            displayName: 'Synthetic',
            deviceId: ownDeviceId,
            expiresAt: DateTime.utc(2030),
          ),
          'synthetic',
        );
        final db = CollaborationDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final secure = _Secure(),
            store = CryptoIdentityStore(db, secure, session.profile.partition),
            transport = _Transport();
        await store.pinRoot(recipient, server, own.result.rootFingerprint);
        await store.append(recipient, own.entry);
        await store.remember(own.result, 'verified');
        await store.pinRoot(author, server, floor.result.rootFingerprint);
        await store.append(author, first.entry);
        await store.append(author, floor.entry);
        await store.remember(floor.result, 'verified');
        final before = Map.of(secure.values),
            localBefore = await store.entries(author);
        transport.entries = mode == 'fork'
            ? [first.entry, fork.entry]
            : mode == 'missing_target'
            ? [first.entry, floor.entry]
            : [first.entry, floor.entry, requested.entry];
        final head = _Head({
          'scopeId': scope,
          'members': [
            {
              'accountId': author,
              'role': mode == 'viewer' ? 'viewer' : 'member',
              'financeRole': 'read',
              'deviceSnapshotHash': floor.result.deviceSnapshotHash,
              'directoryHeadHash': floor.result.headHash,
            },
            {
              'accountId': recipient,
              'role': 'member',
              'financeRole': 'read',
              'deviceSnapshotHash': own.result.deviceSnapshotHash,
              'directoryHeadHash': own.result.headHash,
            },
          ],
        }, 'a' * 64);
        final proof = crypto.signDomain(
          {
            'version': 2,
            'operation': 'crypto2.domain.checkpoint',
            'requestId': crypto.randomId(),
            'serverId': server,
            'accountId': author,
            'deviceId': deviceId,
            'signer': 'device',
            'payload': {
              'scopeId': scope,
              'domain': 'finance',
              'epoch': 2,
              'membershipHeadHash': head.headHash,
              'accessRevision': 0,
              'expectedSequence': 0,
              'recordCount': 0,
              'manifestHash': await cryptoSha256(Uint8List(0)),
              'historyBasis': 'verifiedCheckpoint',
              'authorDirectoryHeadHash': requested.result.headHash,
            },
          },
          device.secretKey,
          cryptoDirectoryDomain,
        );
        if (mode == 'bad_signature') {
          proof['signatureBase64'] = base64Encode(Uint8List(64));
        }
        transport.inventory = {
          'scopeId': scope,
          'domain': 'finance',
          'epoch': 2,
          'membershipHeadHash': head.headHash,
          'scopeSequence': 0,
          'hasMore': false,
          'descriptors': <Map<String, dynamic>>[],
          'checkpoint': {
            'manifestHash': await cryptoSha256(Uint8List(0)),
            'recordCount': 0,
            'membershipHeadHash': head.headHash,
            'domainSequence': 0,
            'attestations': [
              {'authorization': proof},
            ],
            'hasMore': false,
          },
        };
        final account = AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: reducer,
            session: session,
            transport: transport,
            store: store,
            isCurrent: () => true,
          ),
        );
        final access = _Access(account: account, head: head);
        final runtime = CryptoBusinessSession(account, access, db);
        final retained = await runtime.checkpoints.reconcile(
          scope,
          'finance',
          CryptoReadContext(
            epoch: 2,
            accessRevision: 0,
            headHash: head.headHash,
          ),
        );
        if (mode == 'cold') {
          expect(
            retained,
            isNotNull,
            reason:
                'Live runtime reader must replay the exact author directory '
                'before accepting the signed empty finance inventory',
          );
          expect(access.verifiedCheckpoints, 1);
          final checkpoints = await db.rows(
            'SELECT * FROM crypto_domain_checkpoints',
          );
          expect(checkpoints, hasLength(1));
          expect(checkpoints.single['record_count'], 0);
          expect(checkpoints.single['snapshot_id'], retained);
        } else {
          expect(retained, isNull);
          expect(access.verifiedCheckpoints, 0);
          expect(
            await db.rows('SELECT * FROM crypto_domain_checkpoints'),
            isEmpty,
          );
          expect(
            await db.rows('SELECT * FROM crypto_domain_inventory_rows'),
            isEmpty,
          );
        }
        expect(transport.reads, hasLength(1));
        expect(transport.reads.single, {
          'scopeId': scope,
          'headHash': head.headHash,
          'accountId': author,
          'directoryHeadHash': requested.result.headHash,
          'afterGeneration': 0,
          'limit': 50,
        });
        expect(secure.values, before);
        expect(await store.entries(author), localBefore);
        expect(
          await db.rows(
            "SELECT intent_id FROM crypto_membership_intents WHERE state='scopeObservationIncluded'",
          ),
          isEmpty,
        );
      },
    );
  }
}
