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
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final rows = <String, String>{};
  @override
  Future<String?> read(String key) async => rows[key];
  @override
  Future<void> write(String key, String value) async => rows[key] = value;
}

/// The existing current-head verifier is a separate boundary. These tests start
/// after that boundary and exercise the actual signed grant/manifest/open-key
/// verifier reached by normal read admission, without an HTTP fixture.
class _Head implements VerifiedScopeHead {
  _Head(this.body, this.authorization, this.headHash);
  @override
  final Map<String, dynamic> body, authorization;
  @override
  final String headHash;
  @override
  bool get active => true;
  @override
  String get scopeId => body['scopeId'];
  @override
  int get epoch => 1;
  @override
  int get accessRevision => 1;
  @override
  List<Map<String, dynamic>> get members =>
      (body['members'] as List).cast<Map<String, dynamic>>();
  @override
  Map<String, dynamic> member(String account) =>
      members.singleWhere((m) => m['accountId'] == account);
  @override
  String? commitment(String domain) => body['keyCommitments'][domain];
}

class _Transport implements CollaborationTransport {
  Map<String, dynamic> group = {}, manifest = {}, descriptor = {};
  bool missing = false, alteredRecipient = false;
  int grantReads = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.grants.list') {
      grantReads++;
      if (missing) return {'grants': <Object>[]};
      final value = jsonDecode(jsonEncode(group)) as Map<String, dynamic>;
      if (alteredRecipient)
        value['recipients'][0]['sealedEnvelopeBase64'] = base64Encode(
          Uint8List(80),
        );
      return {
        'grants': [value],
      };
    }
    if (operation == 'crypto2.grants.manifest') {
      return params['domain'] == null
          ? manifest
          : {
              'descriptors': [descriptor],
              'hasMore': false,
            };
    }
    throw StateError(operation);
  }

  @override
  void close() {}
}

class _Account extends AccountCryptoV2Workflow {
  _Account(super.directory, this.box);
  final KeyPair box;
  @override
  Future<KeyPair> encryptionKey() async {
    final bytes = box.secretKey.extractBytes();
    try {
      return KeyPair(
        publicKey: box.publicKey,
        secretKey: directory.reducer.crypto.sodium.secureCopy(bytes),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

class _Access extends SessionCryptoAccess {
  _Access({required super.account, required this.head, required this.peer});
  final _Head head;
  final VerifiedAccountDirectory peer;
  bool revoked = false;
  final boundaries = <bool>[];
  void Function(bool)? beforeBoundary;
  @override
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) {
    boundaries.add(freshBoundary);
    beforeBoundary?.call(freshBoundary);
    return super.withVerifiedOperation(body, freshBoundary: freshBoundary);
  }

  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async {
    if (revoked)
      throw const CryptoDirectoryException('scope_membership_missing');
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
  }) async => peer;
}

void main() {
  late CryptoCodec crypto;
  late CollaborationDatabase db;
  late _Transport transport;
  late _Access access;
  late KeyPair root, signing, box;
  late Uint8List rawKey;
  late String scope, keyId;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    transport = _Transport();
    root = crypto.sodium.crypto.sign.keyPair();
    signing = crypto.sodium.crypto.sign.keyPair();
    box = crypto.sodium.crypto.box.keyPair();
    final server = crypto.randomId(),
        accountId = crypto.randomId(),
        deviceId = crypto.randomId();
    final profile = AccountSession(
      serverUrl: 'https://synthetic.invalid',
      serverId: server,
      accountId: accountId,
      userId: 1,
      username: 'reader',
      displayName: 'Reader',
      deviceId: deviceId,
      expiresAt: DateTime.utc(2030),
    );
    final store = CryptoIdentityStore(db, _Secure(), profile.partition);
    final account = _Account(
      AccountDirectoryRepository(
        reducer: AccountDirectoryV2(crypto),
        session: DeviceSession(profile, 'synthetic'),
        transport: transport,
        store: store,
        isCurrent: () => true,
      ),
      box,
    );
    final directory = (await AccountDirectoryV2(crypto).prepare(
      previous: null,
      serverId: server,
      accountId: accountId,
      deviceId: deviceId,
      identityEpochId: crypto.randomId(),
      operation: 'crypto2.account.initialize',
      signer: 'root',
      pinnedRootFingerprint: crypto.fingerprint(root.publicKey, box.publicKey),
      signingKey: root.secretKey,
      payload: {
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(box.publicKey),
        'deviceSigningKeyBase64': base64Encode(signing.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
        'keyringCiphertextBase64': base64Encode(Uint8List(48)),
      },
    )).result;
    scope = crypto.randomId();
    keyId = crypto.randomId();
    rawKey = Uint8List.fromList(List<int>.filled(32, 7));
    final head = _Head(
      {
        'scopeId': scope,
        'previousHeadHash': cryptoZeroHash,
        'authorDirectoryHeadHash': directory.headHash,
        'keyIds': {'content': keyId, 'finance': null},
        'keyCommitments': {
          'content': await ScopeCryptoCodec(crypto).keyCommitment(rawKey),
          'finance': null,
        },
        'contentKeyProposalProof': null,
        'financeKeyProposalProof': null,
        'members': [
          {
            'accountId': accountId,
            'manageKeys': true,
            'financeRole': 'none',
            'directoryHeadHash': directory.headHash,
            'recoveryRootEpochId': directory.snapshot['recoveryRootEpochId'],
          },
        ],
      },
      crypto.signDomain(
        {'accountId': accountId},
        signing.secretKey,
        cryptoDirectoryDomain,
      ),
      'a' * 64,
    );
    access = _Access(account: account, head: head, peer: directory);
  });
  tearDown(() async {
    await db.close();
    rawKey.fillRange(0, rawKey.length, 0);
    for (final key in [root, signing, box]) {
      key.secretKey.dispose();
    }
  });

  Future<void> prepareGrant({bool wrongKey = false}) async {
    final head = access.head, account = access.account;
    final directory = access.peer;
    final raw = wrongKey ? Uint8List.fromList(List<int>.filled(32, 8)) : rawKey;
    final key = crypto.sodium.secureCopy(raw);
    final recipients = <Map<String, dynamic>>[];
    try {
      for (final target in [
        {
          'recipientKind': 'device',
          'recipientId': account.deviceId,
          'publicKeyBase64': base64Encode(box.publicKey),
        },
        {
          'recipientKind': 'recovery',
          'recipientId': directory.snapshot['recoveryRootEpochId'],
          'publicKeyBase64': base64Encode(box.publicKey),
        },
      ]) {
        recipients.add({
          ...target,
          'sealedEnvelopeBase64': crypto.sealKey(
            key: key,
            recipientPublicKey: box.publicKey,
            context: access.codec.wrapperContext(
              serverId: directory.serverId,
              head: head,
              keySourceHead: head,
              domain: 'content',
              keyId: keyId,
              recipient: {
                ...target,
                'recoveryRootEpochId':
                    directory.snapshot['recoveryRootEpochId'],
              },
            ),
          ),
        });
      }
    } finally {
      key.dispose();
    }
    final proof = crypto.signDomain(
      {
        'version': 2,
        'operation': 'crypto2.grants.put',
        'signer': 'device',
        'serverId': directory.serverId,
        'accountId': directory.accountId,
        'deviceId': account.deviceId,
        'payload': {
          'scopeId': scope,
          'headHash': head.headHash,
          'accountId': directory.accountId,
          'domain': 'content',
          'epoch': 1,
          'keyId': keyId,
          'keySourceHeadHash': head.headHash,
          'expectedGeneration': 0,
          'recipients': recipients,
        },
      },
      signing.secretKey,
      cryptoDirectoryDomain,
    );
    final hash = await cryptoSha256(CryptoJson.encode(proof));
    transport.group = {
      'scopeId': scope,
      'headHash': head.headHash,
      'domain': 'content',
      'epoch': 1,
      'keyId': keyId,
      'keySourceHeadHash': head.headHash,
      'generation': 1,
      'recipients': [
        for (final r in recipients) {...r, 'authorizationId': 'grant'},
      ],
      'authorizations': {'grant': proof},
    };
    transport.descriptor = {
      'accountId': directory.accountId,
      'epoch': 1,
      'keyId': keyId,
      'keySourceHeadHash': head.headHash,
      'generation': 1,
      'recipientProofHashes': [hash, hash],
    };
    final domains = {
      'content': await cryptoSha256([
        ...CryptoJson.encode(transport.descriptor),
        10,
      ]),
      'finance': await cryptoSha256([]),
    };
    final top = await cryptoSha256(CryptoJson.encode(domains));
    transport.manifest = {'domains': domains, 'grantManifestHash': top};
    await account.store.database.execute(
      'INSERT INTO crypto_scope_heads VALUES(?,?,?,?,?,?,?,?,?)',
      [
        account.store.partition,
        scope,
        head.headHash,
        1,
        1,
        head.headHash,
        cryptoZeroHash,
        CryptoJson.encode(head.body),
        CryptoJson.encode({
          'activationAuthorization': crypto.signDomain(
            {
              'payload': {'grantManifestHash': top},
            },
            signing.secretKey,
            cryptoDirectoryDomain,
          ),
        }),
      ],
    );
  }

  test(
    'caller read operation retains independent fresh missing-key boundaries',
    () async {
      await prepareGrant();
      await access.ensureScopeReadKeys(scope, 'content');
      expect(access.boundaries, [false, true, true]);
      expect(transport.grantReads, 1);
      access.boundaries.clear();
      await access.ensureScopeReadKeys(scope, 'content');
      expect(access.boundaries, [false]);
      expect(transport.grantReads, 1);
    },
  );
  test(
    'caller read operation cannot bypass revocation before fresh grant admission',
    () async {
      await prepareGrant();
      access.beforeBoundary = (fresh) {
        if (fresh) access.revoked = true;
      };
      await expectLater(
        access.ensureScopeReadKeys(scope, 'content'),
        throwsA(isA<CryptoDirectoryException>()),
      );
      expect(access.boundaries, [false, true]);
      expect(transport.grantReads, 0);
      expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
    },
  );
  test(
    'caller read operation rechecks revocation after grant hydration',
    () async {
      await prepareGrant();
      var freshChecks = 0;
      access.beforeBoundary = (fresh) {
        if (fresh && ++freshChecks == 2) access.revoked = true;
      };
      await expectLater(
        access.ensureScopeReadKeys(scope, 'content'),
        throwsA(isA<CryptoDirectoryException>()),
      );
      expect(access.boundaries, [false, true, true]);
      expect(transport.grantReads, 1);
    },
  );
  test(
    'missing active grants remain pending without installing keys',
    () async {
      transport.missing = true;
      await expectLater(
        access.ensureScopeReadKeys(scope, 'content'),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
      expect(transport.grantReads, 1);
    },
  );
  test('altered signed recipient is rejected before key admission', () async {
    await prepareGrant();
    transport.alteredRecipient = true;
    await expectLater(
      access.ensureScopeReadKeys(scope, 'content'),
      throwsA(isA<FormatException>()),
    );
    expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
  });
  test('authentic wrapper with wrong committed key remains rejected', () async {
    await prepareGrant(wrongKey: true);
    await expectLater(
      access.ensureScopeReadKeys(scope, 'content'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'grant_key_commitment',
        ),
      ),
    );
    expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
  });
  test(
    'revoked current membership never requests or installs grants',
    () async {
      access.revoked = true;
      await expectLater(
        access.ensureScopeReadKeys(scope, 'content'),
        throwsA(isA<CryptoDirectoryException>()),
      );
      expect(transport.grantReads, 0);
      expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
    },
  );
  test('content membership never admits a forbidden finance domain', () async {
    await expectLater(
      access.ensureScopeReadKeys(scope, 'finance'),
      throwsA(isA<CryptoAuthorityPending>()),
    );
    expect(transport.grantReads, 0);
    expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
  });
  test(
    'already retained keys avoid grant traffic and stay read-only',
    () async {
      await db.execute(
        'INSERT INTO crypto_scope_keys VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          access.account.store.partition,
          scope,
          'content',
          1,
          access.head.headHash,
          keyId,
          rawKey,
          access.head.headHash,
          Uint8List(0),
          0,
          0,
        ],
      );
      await access.ensureScopeReadKeys(scope, 'content');
      expect(transport.grantReads, 0);
      expect(
        (await db.rows(
          'SELECT write_ready FROM crypto_scope_keys',
        )).single['write_ready'],
        0,
      );
    },
  );
  test(
    'valid active signed manifest admits the existing device content key',
    () async {
      await prepareGrant();
      await access.ensureScopeReadKeys(scope, 'content');
      expect(
        (await db.rows(
          'SELECT key_bytes FROM crypto_scope_keys',
        )).single['key_bytes'],
        rawKey,
      );
      final reads = transport.grantReads;
      await access.ensureScopeReadKeys(scope, 'content');
      expect(transport.grantReads, reads);
    },
  );
}
