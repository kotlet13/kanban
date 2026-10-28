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
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/recovery_file_codec.dart';
import 'package:kanban/organizer/data/local_vault_keys.dart';
import 'package:kanban/organizer/data/recovery_bundle.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Transport implements CollaborationTransport {
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.account.status') return {'initialized': false};
    throw StateError('No external transport: $operation');
  }

  @override
  void close() {}
}

/// Uses real SQLite and the production cryptographic reducer. Only delivery is
/// synthetic: failures can occur before staging or after the immutable commit.
class _Directory extends AccountDirectoryRepository {
  _Directory({
    required super.reducer,
    required super.session,
    required super.store,
    required super.isCurrent,
  }) : super(transport: _Transport());

  bool failBeforeStage = false, failAfterStage = false;
  PreparedDirectoryMutation? staged;
  int preparations = 0, resumes = 0;

  @override
  Future<void> stageAndSend(
    Future<PreparedDirectoryMutation> Function(VerifiedAccountDirectory?)
    prepare, {
    String? externalFingerprint,
    bool establishesFreshness = false,
    Future<void> Function()? beforeSendTransaction,
    String? verifiedNewRootFingerprint,
  }) async {
    if (failBeforeStage) throw StateError('synthetic offline before staging');
    preparations++;
    staged = await prepare(null);
    expect(externalFingerprint, staged!.result.rootFingerprint);
    expect(establishesFreshness, true);
    await store.database.transaction(() async {
      await store.stage(staged!.authorization, 'pending');
      await beforeSendTransaction?.call();
    });
    if (failAfterStage) throw StateError('synthetic lost ACK');
    await resume();
  }

  @override
  Future<void> resume() async {
    resumes++;
    await store.database.execute(
      "UPDATE crypto_identity_requests SET stage='confirmed' WHERE partition=?",
      [store.partition],
    );
  }

  @override
  Future<VerifiedAccountDirectory> requireFresh() async => staged!.result;
  @override
  Future<VerifiedAccountDirectory> cachedVerifiedDirectory() async =>
      staged!.result;
}

class _Protection extends AccountProtectionReady {
  _Protection(super.account, this.scopes);
  final List<Map<String, dynamic>> scopes;
  int completions = 0;
  @override
  Future<List<Map<String, dynamic>>> catalog() async => scopes;
  @override
  Future<void> complete({
    Map<String, dynamic>? reviewedUnavailable,
    void Function(int)? onPause,
  }) async {
    completions++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CryptoCodec crypto;
  late CollaborationDatabase database;
  late _Directory directory;
  late AccountCryptoV2Workflow workflow;
  late bool current;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  setUp(() {
    current = true;
    database = CollaborationDatabase(NativeDatabase.memory());
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://saved-setup.invalid/',
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
    directory = _Directory(
      reducer: AccountDirectoryV2(crypto),
      session: session,
      store: CryptoIdentityStore(
        database,
        _Secure(),
        session.profile.partition,
      ),
      isCurrent: () => current,
    );
    workflow = AccountCryptoV2Workflow(directory);
  });
  tearDown(() => database.close());

  Future<Uint8List> bundle() async {
    final installation = LocalVaultKey.generate();
    final local = Uint8List.fromList(utf8.encode(installation.encode()));
    final account = await workflow.prepareRecoveryFile();
    try {
      return RecoveryBundleCodec.wrap(local, account);
    } finally {
      installation.bytes.fillRange(0, installation.bytes.length, 0);
      local.fillRange(0, local.length, 0);
      account.fillRange(0, account.length, 0);
    }
  }

  test(
    'prepared file without completed save cannot automatically initialize',
    () async {
      await workflow.prepareRecoveryFile();
      await expectLater(
        workflow.resumeSavedSetup(),
        throwsA(isA<CryptoDirectoryException>()),
      );
      expect(await workflow.localPhase(), 'prepared');
      expect(await workflow.hasSavedSetup(), false);
      expect(directory.preparations, 0);
    },
  );

  test(
    'wrong account or changed file cannot create a saved setup marker',
    () async {
      final saved = await bundle();
      final changed = jsonDecode(utf8.decode(saved)) as Map;
      (changed['account'] as Map)['accountId'] = crypto.randomId();
      await expectLater(
        workflow.confirmSavedRecoveryFile(CryptoJson.encode(changed)),
        throwsA(isA<CryptoDirectoryException>()),
      );
      expect(await workflow.hasSavedSetup(), false);
      expect(await workflow.localPhase(), 'prepared');
    },
  );

  test('saved bundle resumes after failure before immutable staging', () async {
    final saved = await bundle();
    await workflow.confirmSavedRecoveryFile(saved);
    directory.failBeforeStage = true;
    await expectLater(workflow.resumeSavedSetup(), throwsStateError);
    expect(await workflow.localPhase(), 'saved');
    expect(await workflow.hasSavedSetup(), true);
    directory.failBeforeStage = false;
    final restarted = AccountCryptoV2Workflow(directory);
    await restarted.resumeSavedSetup();
    expect(await restarted.localPhase(), 'ready');
    expect(directory.preparations, 1);
    final row = (await database.rows(
      'SELECT * FROM crypto_identity_secrets',
    )).single;
    expect(row['prepared_recovery'], isNull);
    expect(await restarted.hasSavedSetup(), true);
    await restarted.finishSavedSetup();
    expect(await restarted.hasSavedSetup(), false);
  });

  test(
    'lost ACK resumes same signed request without retaining recovery secret',
    () async {
      final saved = await bundle();
      await workflow.confirmSavedRecoveryFile(saved);
      directory.failAfterStage = true;
      await expectLater(workflow.resumeSavedSetup(), throwsStateError);
      final before = await workflow.store.pending();
      expect(before, hasLength(1));
      expect(await workflow.localPhase(), 'pending');
      final row = (await database.rows(
        'SELECT * FROM crypto_identity_secrets',
      )).single;
      expect(row['prepared_recovery'], isNull);
      final restarted = AccountCryptoV2Workflow(directory);
      await restarted.resumeSavedSetup();
      expect(await restarted.localPhase(), 'ready');
      expect(directory.preparations, 1);
      expect(directory.resumes, 1);
      final after = (await database.rows(
        'SELECT authorization FROM crypto_identity_requests',
      )).single;
      expect(
        after['authorization'],
        orderedEquals(CryptoJson.encode(before.single)),
      );
    },
  );

  test(
    'session change while export is open cannot acknowledge its file',
    () async {
      final saved = await bundle();
      current = false;
      await expectLater(
        workflow.confirmSavedRecoveryFile(saved),
        throwsA(isA<CryptoDirectoryException>()),
      );
      expect(await workflow.hasSavedSetup(), false);
      expect(await workflow.localPhase(), 'prepared');
    },
  );

  test(
    'real directory lock can finish a ready saved setup without deadlock',
    () async {
      final saved = await bundle();
      await workflow.confirmSavedRecoveryFile(saved);
      await database.execute(
        "UPDATE crypto_identity_secrets SET phase='ready'",
      );
      final real = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: directory.reducer,
          session: directory.session,
          store: directory.store,
          transport: _Transport(),
          isCurrent: () => current,
        ),
      );
      await real.finishSavedSetup().timeout(const Duration(seconds: 2));
      expect(await real.hasSavedSetup(), false);
    },
  );

  test('saved setup marker cannot follow changed device keys', () async {
    final saved = await bundle();
    await workflow.confirmSavedRecoveryFile(saved);
    await database.execute(
      "UPDATE crypto_identity_secrets SET signing_public='changed'",
    );
    expect(await workflow.hasSavedSetup(), false);
    await expectLater(
      workflow.resumeSavedSetup(),
      throwsA(isA<CryptoDirectoryException>()),
    );
    expect(directory.preparations, 0);
  });

  test('changed secure root pin refuses a prior saved setup marker', () async {
    final saved = await bundle();
    await workflow.confirmSavedRecoveryFile(saved);
    await workflow.resumeSavedSetup();
    expect(await workflow.hasSavedSetup(), true);
    await workflow.store.secure.write(
      'directory2:${workflow.store.partition}:${directory.accountId}',
      jsonEncode({'fingerprint': 'changed'}),
    );
    expect(await workflow.hasSavedSetup(), false);
    await expectLater(
      workflow.resumeSavedSetup(),
      throwsA(isA<CryptoDirectoryException>()),
    );
    expect(directory.preparations, 1);
  });

  test(
    'automatic completion leaves legacy catalog on its existing review path',
    () async {
      final legacy = _Protection(workflow, [
        {'id': crypto.randomId(), 'cryptoOrigin': false},
      ]);
      expect(await legacy.completeFreshSetup(), false);
      expect(legacy.completions, 0);
      legacy.close();
      final fresh = _Protection(workflow, []);
      expect(await fresh.completeFreshSetup(), true);
      expect(fresh.completions, 1);
      fresh.close();
    },
  );

  test(
    'legacy account formats and combined file unlock the same bound root',
    () {
      final codec = RecoveryFileCodec(crypto),
          installation = LocalVaultKey.generate();
      final local = Uint8List.fromList(utf8.encode(installation.encode()));
      final server = crypto.randomId(), account = crypto.randomId();
      try {
        for (final replacement in [false, true]) {
          final material = codec.create(
            serverId: server,
            accountId: account,
            replacement: replacement,
          );
          final combined = RecoveryBundleCodec.wrap(local, material.file);
          try {
            for (final file in [material.file, combined]) {
              final root = codec.open(
                file: file,
                encryptedRoot: material.encryptedRoot,
                serverId: server,
                accountId: account,
                expectedFingerprint: material.fingerprint,
              );
              expect(
                root.signing.publicKey,
                orderedEquals(material.signingPublicKey),
              );
              expect(
                root.encryption.publicKey,
                orderedEquals(material.encryptionPublicKey),
              );
              root.dispose();
              expect(
                () => codec.inspect(
                  file,
                  serverId: crypto.randomId(),
                  accountId: account,
                ),
                throwsFormatException,
              );
              expect(
                () => codec.open(
                  file: file,
                  encryptedRoot: material.encryptedRoot,
                  serverId: server,
                  accountId: account,
                  expectedFingerprint: '0' * 64,
                ),
                throwsFormatException,
              );
            }
          } finally {
            combined.fillRange(0, combined.length, 0);
            material.dispose();
          }
        }
      } finally {
        local.fillRange(0, local.length, 0);
        installation.bytes.fillRange(0, installation.bytes.length, 0);
      }
    },
  );
}
