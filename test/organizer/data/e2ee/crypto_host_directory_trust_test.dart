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
import 'package:kanban/organizer/data/e2ee/crypto_identity_verification.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Identity {
  _Identity(this.crypto, this.server, this.account)
    : root = crypto.sodium.crypto.sign.keyPair(),
      box = crypto.sodium.crypto.box.keyPair(),
      device = crypto.sodium.crypto.sign.keyPair(),
      deviceId = crypto.randomId(),
      epoch = crypto.randomId();
  final CryptoCodec crypto;
  final String server, account, deviceId, epoch;
  final KeyPair root, box, device;
  final entries = <Map<String, dynamic>>[];
  late VerifiedAccountDirectory directory;
  String get fingerprint => crypto.fingerprint(root.publicKey, box.publicKey);
  Future<void> initialize() async {
    final mutation = await AccountDirectoryV2(crypto).prepare(
      previous: null,
      serverId: server,
      accountId: account,
      deviceId: deviceId,
      identityEpochId: epoch,
      operation: 'crypto2.account.initialize',
      signer: 'root',
      pinnedRootFingerprint: fingerprint,
      signingKey: root.secretKey,
      payload: {
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(box.publicKey),
        'deviceSigningKeyBase64': base64Encode(device.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
        'keyringCiphertextBase64': base64Encode(Uint8List(48)),
      },
    );
    directory = mutation.result;
    entries.add(mutation.entry);
  }

  Future<void> addDevice() async {
    final added = crypto.sodium.crypto.sign.keyPair();
    try {
      final mutation = await AccountDirectoryV2(crypto).prepare(
        previous: directory,
        serverId: server,
        accountId: account,
        deviceId: deviceId,
        identityEpochId: epoch,
        operation: 'crypto2.device.add',
        signer: 'device',
        pinnedRootFingerprint: fingerprint,
        signingKey: device.secretKey,
        payload: {
          'deviceId': crypto.randomId(),
          'signingKeyBase64': base64Encode(added.publicKey),
          'encryptionKeyBase64': base64Encode(box.publicKey),
          'keyringWrite': false,
          'manageDevices': false,
        },
      );
      directory = mutation.result;
      entries.add(mutation.entry);
    } finally {
      added.secretKey.dispose();
    }
  }

  Map<String, dynamic> page([int after = 0]) => {
    'generation': directory.generation,
    'headHash': directory.headHash,
    'snapshotHash': directory.snapshotHash,
    'entries': entries.where((e) => e['generation'] > after).toList(),
    'hasMore': false,
    'nextGeneration': directory.generation,
  };
  void dispose() {
    for (final key in [root, box, device]) {
      key.secretKey.dispose();
    }
  }
}

class _Transport implements CollaborationTransport {
  final identities = <String, _Identity>{};
  Map<String, dynamic>? preview, acceptance;
  String? scopeId;
  bool corrupt = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.invitations.preview') return preview!;
    if (operation == 'crypto2.invitations.acceptance') return acceptance!;
    if (operation == 'crypto2.directory.status') {
      return {'headHash': identities[params['accountId']]!.directory.headHash};
    }
    if (operation == 'crypto2.scopes.catalog') {
      return {
        'scopes': [
          {'id': scopeId, 'headHash': '3' * 64},
        ],
        'hasMore': false,
      };
    }
    if (operation == 'crypto2.directory.read') {
      final result = identities[params['accountId']]!.page(
        params['afterGeneration'] as int,
      );
      if (corrupt) {
        final changed = jsonDecode(jsonEncode(result)) as Map<String, dynamic>;
        changed['entries'][0]['authorization']['signatureBase64'] =
            base64Encode(Uint8List(64));
        return changed;
      }
      return result;
    }
    throw StateError('Unexpected synthetic operation $operation');
  }

  @override
  void close() {}
}

void main() {
  late CryptoCodec crypto;
  late CollaborationDatabase db;
  late _Secure secure;
  late CryptoIdentityStore store;
  late CryptoIdentityVerification verification;
  late _Identity identity;
  late String server;
  final identities = <_Identity>[];
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  Future<_Identity> makeIdentity({String? account, String? serverId}) async {
    final result = _Identity(
      crypto,
      serverId ?? server,
      account ?? crypto.randomId(),
    );
    identities.add(result);
    await result.initialize();
    return result;
  }

  setUp(() async {
    server = crypto.randomId();
    db = CollaborationDatabase(NativeDatabase.memory());
    secure = _Secure();
    store = CryptoIdentityStore(db, secure, 'synthetic-host-trust');
    verification = CryptoIdentityVerification(crypto, store);
    identity = await makeIdentity();
  });
  tearDown(() async {
    await db.close();
    for (final value in identities) {
      value.dispose();
    }
    identities.clear();
  });
  Future<void> trust(VerifiedAccountDirectory value, {bool current = true}) =>
      verification.trustHostDirectory(
        directory: value,
        expectedServerId: server,
        isCurrent: () => current,
      );
  Matcher directoryError(String code) => throwsA(
    isA<CryptoDirectoryException>().having((e) => e.code, 'code', code),
  );
  Future<void> retain(_Identity value) async {
    for (final entry in value.entries) {
      await store.append(value.account, entry);
    }
    await store.remember(value.directory, 'verified');
  }

  test(
    'first signed hosting contact pins a secure root and explicit provenance',
    () async {
      await trust(identity.directory);
      await verification.requireVerified(
        identity.account,
        identity.fingerprint,
      );
      final anchor = (await store.anchor(identity.account))!;
      expect(anchor['verificationMethod'], 'hostDirectory');
      expect(anchor['genesisFingerprint'], identity.fingerprint);
      expect(
        (await db.rows(
          'SELECT verification_method FROM crypto_trusted_identities',
        )).single['verification_method'],
        'hostDirectory',
      );
      expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
      expect(await db.rows('SELECT * FROM crypto_identity_secrets'), isEmpty);
    },
  );
  test('same root with a newly signed device advances automatically', () async {
    await trust(identity.directory);
    await identity.addDevice();
    await trust(identity.directory);
    expect((await store.anchor(identity.account))!['generation'], 2);
    expect(
      (await store.anchor(identity.account))!['verificationMethod'],
      'hostDirectory',
    );
  });
  test(
    'manual comparison provenance survives ordinary hosting continuity',
    () async {
      final comparedHead = identity.directory.headHash;
      await verification.compareAndPin(
        directory: identity.directory,
        externallyComparedSafetyCode: await verification.safetyCode(
          identity.directory,
        ),
        externallyComparedGeneration: identity.directory.generation,
        externallyComparedHeadHash: identity.directory.headHash,
      );
      await identity.addDevice();
      await trust(identity.directory);
      await retain(identity);
      expect(
        (await store.anchor(identity.account))!['verificationMethod'],
        'safetyCode',
      );
      expect(
        (await db.rows(
          'SELECT verification_method FROM crypto_trusted_identities',
        )).single['verification_method'],
        'safetyCode',
      );
      expect(
        (await store.anchor(identity.account))!['comparedHeadHash'],
        comparedHead,
      );
      final projection = (await db.rows(
        'SELECT compared_head_hash,compared_generation FROM crypto_trusted_identities',
      )).single;
      expect(projection['compared_head_hash'], comparedHead);
      expect(projection['compared_generation'], 1);
    },
  );
  test(
    'legacy manual pin retains its original SQL comparison provenance',
    () async {
      for (var i = 0; i < 2; i++) {
        await verification.compareAndPin(
          directory: identity.directory,
          externallyComparedSafetyCode: await verification.safetyCode(
            identity.directory,
          ),
          externallyComparedGeneration: identity.directory.generation,
          externallyComparedHeadHash: identity.directory.headHash,
        );
      }
      final comparedHead = identity.directory.headHash;
      final key = secure.values.keys.single;
      final legacy = jsonDecode(secure.values[key]!) as Map<String, dynamic>
        ..remove('verificationMethod')
        ..remove('comparedHeadHash')
        ..remove('comparedGeneration');
      secure.values[key] = jsonEncode(legacy);
      await identity.addDevice();
      await trust(identity.directory);
      final row = (await db.rows(
        'SELECT verification_method,compared_head_hash,compared_generation FROM crypto_trusted_identities',
      )).single;
      expect(row['verification_method'], 'safetyCodeReverified');
      expect(row['compared_head_hash'], comparedHead);
      expect(row['compared_generation'], 1);
    },
  );
  test(
    'SQL loss or a forged SQL pin cannot replace a securely known root',
    () async {
      await trust(identity.directory);
      final before = Map<String, String>.from(secure.values);
      await db.execute('DELETE FROM crypto_trusted_identities');
      await db.execute('DELETE FROM crypto_directory_pins');
      final attacker = await makeIdentity(account: identity.account);
      await expectLater(
        trust(attacker.directory),
        directoryError('directory_root_changed'),
      );
      await db.execute(
        'INSERT INTO crypto_trusted_identities VALUES(?,?,?,?,?,?,?,?,?)',
        [
          store.partition,
          server,
          identity.account,
          attacker.directory.snapshot['rootSigningKeyBase64'],
          attacker.directory.snapshot['rootEncryptionKeyBase64'],
          attacker.fingerprint,
          'safetyCode',
          attacker.directory.headHash,
          1,
        ],
      );
      await expectLater(
        verification.requireVerified(identity.account, attacker.fingerprint),
        directoryError('directory_root_changed'),
      );
      await verification.requireVerified(
        identity.account,
        identity.fingerprint,
      );
      expect(secure.values, before);
    },
  );
  test(
    'unanchored SQL verified marker alone never authenticates identity',
    () async {
      await db.execute(
        'INSERT INTO crypto_trusted_identities VALUES(?,?,?,?,?,?,?,?,?)',
        [
          store.partition,
          server,
          identity.account,
          identity.directory.snapshot['rootSigningKeyBase64'],
          identity.directory.snapshot['rootEncryptionKeyBase64'],
          identity.fingerprint,
          'safetyCode',
          identity.directory.headHash,
          1,
        ],
      );
      await expectLater(
        verification.requireVerified(identity.account, identity.fingerprint),
        throwsA(isA<CryptoAuthorityPending>()),
      );
    },
  );
  test(
    'rollback and same-root fork leave the secure anchor unchanged',
    () async {
      final initial = identity.directory;
      await identity.addDevice();
      await trust(identity.directory);
      final before = Map<String, String>.from(secure.values);
      await expectLater(trust(initial), directoryError('directory_rollback'));
      final original = identity.directory;
      identity.directory = initial;
      await identity.addDevice();
      await expectLater(
        trust(identity.directory),
        directoryError('directory_anchor_fork'),
      );
      identity.directory = original;
      expect(secure.values, before);
    },
  );
  test(
    'historical signed invitation prefix can reuse a provably newer pin',
    () async {
      final initial = identity.directory;
      await identity.addDevice();
      await trust(identity.directory);
      await retain(identity);
      final before = Map<String, String>.from(secure.values);
      await trust(initial);
      expect(secure.values, before);
      expect((await store.anchor(identity.account))!['generation'], 2);
    },
  );
  test(
    'stale session, cross-server and other partition cannot establish trust',
    () async {
      await expectLater(
        trust(identity.directory, current: false),
        directoryError('directory_stale_identity'),
      );
      expect(secure.values, isEmpty);
      final foreign = await makeIdentity(serverId: crypto.randomId());
      await expectLater(
        trust(foreign.directory),
        directoryError('directory_server_mismatch'),
      );
      await trust(identity.directory);
      final other = CryptoIdentityVerification(
        crypto,
        CryptoIdentityStore(db, secure, 'another-partition'),
      );
      await expectLater(
        other.requireVerified(identity.account, identity.fingerprint),
        throwsA(isA<CryptoAuthorityPending>()),
      );
    },
  );

  SessionCryptoAccess access(_Transport transport) {
    final profile = AccountSession(
      serverUrl: 'https://synthetic.invalid',
      serverId: server,
      accountId: crypto.randomId(),
      userId: 1,
      username: 'synthetic',
      displayName: 'Synthetic',
      deviceId: crypto.randomId(),
      expiresAt: DateTime.utc(2030),
    );
    store = CryptoIdentityStore(db, secure, profile.partition);
    verification = CryptoIdentityVerification(crypto, store);
    return SessionCryptoAccess(
      account: AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: DeviceSession(profile, 'synthetic'),
          transport: transport,
          store: store,
          isCurrent: () => true,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> invitation(
    _Identity author, {
    bool accepted = false,
  }) async {
    final id = crypto.randomId(), scope = crypto.randomId();
    final proof = crypto.signDomain(
      {
        'version': 2,
        'serverId': server,
        'accountId': author.account,
        'deviceId': author.deviceId,
        'operation': accepted
            ? 'crypto2.invitations.accept'
            : 'crypto2.invitations.create',
        'payload': {
          'invitationId': id,
          'scopeId': scope,
          'authorDirectoryHeadHash': author.directory.headHash,
          'membershipHeadHash': '1' * 64,
          'tokenHash': '2' * 64,
          'role': 'member',
        },
      },
      author.device.secretKey,
      cryptoDirectoryDomain,
    );
    return accepted
        ? {
            'authorization': proof,
            'acceptanceProofHash': await cryptoSha256(CryptoJson.encode(proof)),
            'recipientDirectory': author.page(),
            'proposedMember': <String, dynamic>{},
            'syntheticScope': scope,
            'syntheticInvitation': id,
          }
        : {
            'creatorAuthorization': proof,
            'creatorDirectory': author.page(),
            'invitation': {'id': id, 'scopeId': scope, 'tokenHash': '2' * 64},
            'scope': {'id': scope},
          };
  }

  test(
    'creator trust re-fetches verified invitation and retains a newer same-root pin',
    () async {
      final transport = _Transport()..preview = await invitation(identity);
      final session = access(transport);
      final repository = InviteCryptoRepository(session);
      final candidate = await repository.inspect(
        invitationId: transport.preview!['invitation']['id'],
      );
      await identity.addDevice();
      await trust(identity.directory);
      await retain(identity);
      final newer = (await store.anchor(identity.account))!['headHash'];
      await repository.trustCreatorFromDirectory(candidate);
      expect((await store.anchor(identity.account))!['headHash'], newer);
      expect(
        await db.rows('SELECT * FROM crypto_directory_replay_staging'),
        isEmpty,
      );
    },
  );
  test(
    'both creator and accepted recipient use hosting trust without public cards',
    () async {
      final second = await makeIdentity();
      final transport = _Transport()
        ..preview = await invitation(identity)
        ..acceptance = await invitation(second, accepted: true);
      final repository = InviteCryptoRepository(access(transport));
      await repository.trustCreatorFromDirectory(
        await repository.inspect(
          invitationId: transport.preview!['invitation']['id'],
        ),
      );
      await repository.trustCreatorFromDirectory(
        await repository.acceptedRecipient(
          transport.acceptance!['syntheticScope'],
          transport.acceptance!['syntheticInvitation'],
        ),
      );
      await verification.requireVerified(
        identity.account,
        identity.fingerprint,
      );
      await verification.requireVerified(second.account, second.fingerprint);
      expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
    },
  );
  test(
    'explicit scoped contact trust retains latest replay for an older pending invitation',
    () async {
      final transport = _Transport()..preview = await invitation(identity);
      transport.scopeId = transport.preview!['scope']['id'];
      transport.identities[identity.account] = identity;
      final session = access(transport),
          repository = InviteCryptoRepository(session);
      final candidate = await repository.inspect(
        invitationId: transport.preview!['invitation']['id'],
      );
      await repository.trustCreatorFromDirectory(candidate);
      await identity.addDevice();
      await session.trustContactFromDirectory(
        transport.scopeId!,
        identity.account,
      );
      expect(
        (await store.entries(identity.account)).last['headHash'],
        identity.directory.headHash,
      );
      await repository.trustCreatorFromDirectory(candidate);
      expect(
        (await store.anchor(identity.account))!['headHash'],
        identity.directory.headHash,
      );
    },
  );
  test('acceptance must bind its signed author directory prefix', () async {
    final transport = _Transport()
      ..acceptance = await invitation(identity, accepted: true);
    final original =
        transport.acceptance!['authorization'] as Map<String, dynamic>;
    final command =
        CryptoJson.decode(cryptoBase64(original['commandBase64']))
            as Map<String, dynamic>;
    command['payload']['authorDirectoryHeadHash'] = '9' * 64;
    final changed = crypto.signDomain(
      command,
      identity.device.secretKey,
      cryptoDirectoryDomain,
    );
    transport.acceptance!['authorization'] = changed;
    transport.acceptance!['acceptanceProofHash'] = await cryptoSha256(
      CryptoJson.encode(changed),
    );
    final repository = InviteCryptoRepository(access(transport));
    await expectLater(
      repository.acceptedRecipient(
        transport.acceptance!['syntheticScope'],
        transport.acceptance!['syntheticInvitation'],
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'invitation_directory_head',
        ),
      ),
    );
    expect(await store.anchor(identity.account), isNull);
    expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
  });
  test(
    'authorized scoped directory routes establish multiple member roots without cards',
    () async {
      final second = await makeIdentity();
      final transport = _Transport()
        ..identities.addAll({
          identity.account: identity,
          second.account: second,
        });
      final session = access(transport), scope = crypto.randomId();
      for (final member in [identity, second]) {
        final result = await session.directoryAt(
          scopeId: scope,
          scopeHeadHash: '3' * 64,
          accountId: member.account,
          directoryHeadHash: member.directory.headHash,
          online: true,
        );
        expect(result.rootFingerprint, member.fingerprint);
        await verification.requireVerified(member.account, member.fingerprint);
      }
      expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
    },
  );
  test(
    'invalid signed directory and invalid scope proof never yield content keys',
    () async {
      final transport = _Transport()..identities[identity.account] = identity;
      final session = access(transport), scope = crypto.randomId();
      transport.corrupt = true;
      await expectLater(
        session.directoryAt(
          scopeId: scope,
          scopeHeadHash: '4' * 64,
          accountId: identity.account,
          directoryHeadHash: identity.directory.headHash,
          online: true,
        ),
        throwsA(anything),
      );
      expect(await store.anchor(identity.account), isNull);
      transport.corrupt = false;
      await session.directoryAt(
        scopeId: scope,
        scopeHeadHash: '4' * 64,
        accountId: identity.account,
        directoryHeadHash: identity.directory.headHash,
        online: true,
      );
      // Hosting identity trust alone has no scope authorization or key material.
      await expectLater(session.currentHead(scope), throwsA(anything));
      expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
    },
  );
}
