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
import 'package:kanban/organizer/data/e2ee/recovery_file_codec.dart';
import 'package:kanban/organizer/data/recovery_bundle.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  bool frozen = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (frozen) throw StateError('Recovery check attempted secure-store write');
    values[key] = value;
  }
}

class _Database extends CollaborationDatabase {
  _Database() : super(NativeDatabase.memory());
  bool frozen = false;
  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) {
    if (frozen) throw StateError('Recovery check attempted database write');
    return super.execute(sql, args);
  }
}

class _Transport implements CollaborationTransport {
  Map<String, dynamic> status = {};
  final calls = <String>[];
  Future<void> Function()? duringRead;
  Object? failure;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    if (operation != 'crypto2.account.status' || params.isNotEmpty) {
      throw StateError('Only unsigned account status reads allowed');
    }
    await duringRead?.call();
    if (failure != null) throw failure!;
    return Map<String, dynamic>.from(status);
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CryptoCodec crypto;
  late _Database db;
  late _Secure secure;
  late _Transport transport;
  late AccountCryptoV2Workflow workflow;
  late AccountRecoveryMaterial material;
  late Map<String, String> secureBefore;
  late String dbBefore;
  late bool current;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));

  Future<String> databaseSnapshot() async {
    final tables = await db.rows(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    return jsonEncode({
      for (final table in tables)
        table['name'] as String: await db.rows(
          'SELECT * FROM "${table['name']}" ORDER BY rowid',
        ),
    });
  }

  Future<void> fixture({bool brokenEnvelope = false}) async {
    current = true;
    db = _Database();
    secure = _Secure();
    transport = _Transport();
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://recovery-check.invalid/',
        serverId: crypto.randomId(),
        accountId: crypto.randomId(),
        deviceId: crypto.randomId(),
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic-session-token',
    );
    final codec = RecoveryFileCodec(crypto);
    material = codec.create(
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
    );
    final root = codec.open(
      file: material.file,
      encryptedRoot: material.encryptedRoot,
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
      expectedFingerprint: material.fingerprint,
    );
    final device = crypto.sodium.crypto.sign.keyPair();
    final box = crypto.sodium.crypto.box.keyPair();
    final reducer = AccountDirectoryV2(crypto);
    final store = CryptoIdentityStore(db, secure, session.profile.partition);
    final envelope = Map<String, dynamic>.from(material.encryptedRoot);
    if (brokenEnvelope) {
      final bytes = cryptoBase64(envelope['ciphertextBase64']);
      bytes[0] ^= 1;
      envelope['ciphertextBase64'] = base64Encode(bytes);
      bytes.fillRange(0, bytes.length, 0);
    }
    late PreparedDirectoryMutation genesis;
    try {
      genesis = await reducer.prepare(
        previous: null,
        serverId: session.profile.serverId,
        accountId: session.profile.accountId,
        deviceId: session.profile.deviceId,
        identityEpochId: crypto.randomId(),
        operation: 'crypto2.account.initialize',
        signer: 'root',
        pinnedRootFingerprint: material.fingerprint,
        signingKey: root.signing.secretKey,
        payload: {
          'rootSigningKeyBase64': base64Encode(material.signingPublicKey),
          'rootEncryptionKeyBase64': base64Encode(material.encryptionPublicKey),
          'deviceSigningKeyBase64': base64Encode(device.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
          'keyringCiphertextBase64': base64Encode(CryptoJson.encode(envelope)),
        },
      );
    } finally {
      root.dispose();
      device.secretKey.dispose();
      box.secretKey.dispose();
    }
    await store.pinRoot(
      session.profile.accountId,
      session.profile.serverId,
      material.fingerprint,
      genesisFingerprint: material.fingerprint,
    );
    await store.append(session.profile.accountId, genesis.entry);
    await store.remember(genesis.result, 'verified');
    // Sentinels cover unrelated local data and an existing pending journal.
    await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
      'recovery-check-preserve',
      'draft-and-queue-sentinel',
    ]);
    transport.status = {
      'initialized': true,
      'serverId': session.profile.serverId,
      'accountId': session.profile.accountId,
      'generation': genesis.result.generation,
      'headHash': genesis.result.headHash,
      'snapshotHash': genesis.result.snapshotHash,
      'deviceSnapshotHash': genesis.result.deviceSnapshotHash,
      'keyringCiphertextBase64': base64Encode(CryptoJson.encode(envelope)),
    };
    workflow = AccountCryptoV2Workflow(
      AccountDirectoryRepository(
        reducer: reducer,
        session: session,
        transport: transport,
        store: store,
        isCurrent: () => current,
      ),
    );
    secureBefore = Map.from(secure.values);
    dbBefore = await databaseSnapshot();
    secure.frozen = db.frozen = true;
  }

  Future<void> unchanged() async {
    expect(await databaseSnapshot(), dbBefore);
    expect(secure.values, secureBefore);
    expect(transport.calls.every((c) => c == 'crypto2.account.status'), true);
  }

  tearDown(() async {
    material.dispose();
    await db.close();
  });
  Matcher code(String expected) => throwsA(
    isA<CryptoDirectoryException>().having((e) => e.code, 'code', expected),
  );

  test(
    'account file decrypts the signed current root without any writes',
    () async {
      await fixture();
      final original = Uint8List.fromList(material.file);
      await workflow.checkRecoveryFile(material.file);
      expect(material.file, original);
      expect(transport.calls, ['crypto2.account.status']);
      await unchanged();
    },
  );

  test(
    'combined file checks account keys without using installation key',
    () async {
      await fixture();
      final installation = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'jivie-installation-recovery',
            'version': 1,
            'vaultId': 'deliberately-not-this-installation',
            'key': 'deliberately-not-an-installation-key',
          }),
        ),
      );
      final combined = RecoveryBundleCodec.wrap(installation, material.file);
      try {
        await workflow.checkRecoveryFile(combined);
        await unchanged();
      } finally {
        combined.fillRange(0, combined.length, 0);
        installation.fillRange(0, installation.length, 0);
      }
    },
  );

  for (final field in ['accountId', 'serverId', 'secretBase64']) {
    test(
      'changed $field rejects file without changing account or device',
      () async {
        await fixture();
        final changed = CryptoJson.decode(material.file) as Map;
        changed[field] = field == 'secretBase64'
            ? base64Encode(Uint8List(32))
            : crypto.randomId();
        final bytes = CryptoJson.encode(changed);
        try {
          await expectLater(
            workflow.checkRecoveryFile(bytes),
            code('directory_recovery_file_invalid'),
          );
          await unchanged();
        } finally {
          bytes.fillRange(0, bytes.length, 0);
          changed.clear();
        }
      },
    );
  }

  test('truncated file is rejected before any server read', () async {
    await fixture();
    await expectLater(
      workflow.checkRecoveryFile(Uint8List.fromList([123])),
      code('directory_recovery_file_invalid'),
    );
    expect(transport.calls, isEmpty);
    await unchanged();
  });

  test(
    'different account root for same account is not accepted as current',
    () async {
      await fixture();
      final replacement = workflow.files.create(
        serverId: workflow.directory.session.profile.serverId,
        accountId: workflow.directory.accountId,
      );
      try {
        await expectLater(
          workflow.checkRecoveryFile(replacement.file),
          code('directory_recovery_identity'),
        );
        expect(transport.calls, isEmpty);
        await unchanged();
      } finally {
        replacement.dispose();
      }
    },
  );

  for (final field in [
    'generation',
    'headHash',
    'snapshotHash',
    'deviceSnapshotHash',
    'serverId',
    'accountId',
  ]) {
    test(
      'changed live $field cannot produce success or update anchor',
      () async {
        await fixture();
        transport.status[field] = field == 'generation' ? 2 : 'changed';
        await expectLater(
          workflow.checkRecoveryFile(material.file),
          code('directory_recovery_status_changed'),
        );
        await unchanged();
      },
    );
  }

  test('ciphertext must match the signed directory hash', () async {
    await fixture();
    transport.status['keyringCiphertextBase64'] = base64Encode(Uint8List(32));
    await expectLater(
      workflow.checkRecoveryFile(material.file),
      code('directory_recovery_ciphertext'),
    );
    await unchanged();
  });

  test('signed hash alone does not bypass real root AEAD decryption', () async {
    await fixture(brokenEnvelope: true);
    await expectLater(
      workflow.checkRecoveryFile(material.file),
      code('directory_recovery_file_invalid'),
    );
    await unchanged();
  });

  test('session replaced while status is in flight fails closed', () async {
    await fixture();
    transport.duringRead = () async => current = false;
    await expectLater(
      workflow.checkRecoveryFile(material.file),
      code('directory_stale_identity'),
    );
    await unchanged();
  });

  test(
    'server read failure leaves file and all persistence unchanged',
    () async {
      await fixture();
      transport.failure = const CollaborationApiException('session_expired');
      await expectLater(
        workflow.checkRecoveryFile(material.file),
        throwsA(isA<CollaborationApiException>()),
      );
      await unchanged();
    },
  );

  test(
    'race: anchor changed during status cannot produce stale success',
    () async {
      await fixture();
      transport.duringRead = () async {
        final key = secure.values.keys.single;
        final value =
            CryptoJson.decode(
                  Uint8List.fromList(utf8.encode(secure.values[key]!)),
                )
                as Map;
        value['trustState'] = 'freshnessPending';
        secure.values[key] = utf8.decode(CryptoJson.encode(value));
        // This is the injected external change, not a checker-owned write.
        secureBefore = Map.from(secure.values);
      };
      await expectLater(
        workflow.checkRecoveryFile(material.file),
        code('directory_recovery_status_changed'),
      );
      await unchanged();
    },
  );

  test(
    'race: checker owns a copy before caller overwrites selected bytes',
    () async {
      await fixture();
      final selected = Uint8List.fromList(material.file);
      transport.duringRead = () async =>
          selected.fillRange(0, selected.length, 0);
      await workflow.checkRecoveryFile(selected);
      expect(selected.every((byte) => byte == 0), true);
      await unchanged();
    },
  );

  test(
    'race: corrupted local signed directory cannot become trusted evidence',
    () async {
      await fixture();
      final row = (await db.rows(
        'SELECT authorization FROM crypto_directory_entries',
      )).single;
      final authorization =
          CryptoJson.decode(
                Uint8List.fromList((row['authorization'] as List).cast<int>()),
              )
              as Map;
      final signature = cryptoBase64(authorization['signatureBase64']);
      signature[0] ^= 1;
      authorization['signatureBase64'] = base64Encode(signature);
      signature.fillRange(0, signature.length, 0);
      db.frozen = false;
      await db.execute('UPDATE crypto_directory_entries SET authorization=?', [
        CryptoJson.encode(authorization),
      ]);
      db.frozen = true;
      dbBefore = await databaseSnapshot();
      await expectLater(
        workflow.checkRecoveryFile(material.file),
        throwsA(isA<CryptoDirectoryException>()),
      );
      expect(transport.calls, isEmpty);
      await unchanged();
    },
  );

  for (final change in ['trustState', 'pendingRootTransition']) {
    test('anchor $change blocks check without promoting trust', () async {
      await fixture();
      final key = secure.values.keys.single;
      final value =
          CryptoJson.decode(
                Uint8List.fromList(utf8.encode(secure.values[key]!)),
              )
              as Map;
      value[change] = change == 'trustState'
          ? 'freshnessPending'
          : {'newFingerprint': material.fingerprint};
      secure.values[key] = utf8.decode(CryptoJson.encode(value));
      secureBefore = Map.from(secure.values);
      await expectLater(
        workflow.checkRecoveryFile(material.file),
        code('directory_recovery_identity'),
      );
      expect(transport.calls, isEmpty);
      await unchanged();
    });
  }
}
