import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_keys.dart';
import 'package:kanban/organizer/data/local_vault_native.dart';
import 'package:kanban/organizer/data/local_vault_legacy_cache.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/recovery_bundle.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

class _Keys implements LocalVaultKeyStore {
  String? value;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SharedPreferences preferences;
  late _Keys keys;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('jivie-fresh-vault-');
    SharedPreferences.setMockInitialValues({'app_locale_code': 'sl'});
    preferences = await SharedPreferences.getInstance();
    keys = _Keys();
  });
  tearDown(() => directory.delete(recursive: true));
  NativeLocalVaultService service({
    void Function(String)? checkpoint,
    bool retainedSecrets = false,
    List<LegacyPickerCacheRoot> pickerRoots = const [],
  }) => NativeLocalVaultService(
    directory,
    keys,
    preferences: preferences,
    checkpoint: checkpoint,
    hasRetainedSecrets: () async => retainedSecrets,
    pickerRoots: pickerRoots,
  );

  test(
    'fresh protection supports local writes/reopen without account or export',
    () async {
      final stages = <String>[];
      final vault = service(checkpoint: stages.add);
      expect(
        (await vault.initializeFreshInstallation()).phase,
        LocalVaultPhase.ready,
      );
      expect(stages, contains('freshPrepared'));
      expect(stages, isNot(contains('recoveryVerified')));
      final journal = jsonDecode(
        await File('${vault.vaultDirectory.path}/state.json').readAsString(),
      );
      expect(journal['setupMode'], 'fresh');
      expect(journal['phase'], 'complete');
      final db = await vault.openDatabase();
      await db.execute(
        "INSERT INTO local_meta VALUES('fresh_test','offline preserved sentinel')",
      );
      await db.close();
      expect(await vault.sourceFile.exists(), false);
      expect(
        String.fromCharCodes(await vault.databaseFile.readAsBytes()),
        isNot(contains('offline preserved sentinel')),
      );
      final plain = sqlite3.open(
        vault.databaseFile.path,
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          () => plain.select('SELECT * FROM sqlite_schema'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        plain.close();
      }
      final reopened = service();
      expect(
        (await reopened.initializeFreshInstallation()).phase,
        LocalVaultPhase.ready,
      );
      final data = await reopened.openDatabase();
      expect(
        (await data.rows(
          "SELECT value FROM local_meta WHERE name='fresh_test'",
        )).single['value'],
        'offline preserved sentinel',
      );
      await data.close();
      expect(keys.writes, 1);
    },
  );

  test(
    'cosmetic desktop window sizes do not block fresh encrypted startup',
    () async {
      await preferences.setDouble('window_width', 1280);
      await preferences.setDouble('window_height', 800);
      expect(
        (await service().initializeFreshInstallation()).phase,
        LocalVaultPhase.ready,
      );
      expect(preferences.getDouble('window_width'), 1280);
      expect(preferences.getDouble('window_height'), 800);
      expect(keys.writes, 1);
    },
  );

  test(
    'invalid desktop window preferences keep explicit setup without key writes',
    () async {
      await preferences.setString('window_width', 'retained');
      expect(
        (await service().initializeFreshInstallation()).phase,
        LocalVaultPhase.needsSetup,
      );
      await preferences.setDouble('window_width', double.infinity);
      expect(
        (await service().initializeFreshInstallation()).phase,
        LocalVaultPhase.needsSetup,
      );
      await preferences.setDouble('window_width', -1);
      expect(
        (await service().initializeFreshInstallation()).phase,
        LocalVaultPhase.needsSetup,
      );
      expect(keys.writes, 0);
    },
  );

  test(
    'any source file and legacy setup keep explicit recovery flow',
    () async {
      await File(
        '${directory.path}/organizer_shared_v1.sqlite',
      ).writeAsBytes([1, 2, 3]);
      final vault = service();
      expect(
        (await vault.initializeFreshInstallation()).phase,
        LocalVaultPhase.needsSetup,
      );
      expect(keys.writes, 0);
      final recovery = await vault.prepareRecoveryFile();
      expect(
        (await vault.initializeFreshInstallation()).phase,
        LocalVaultPhase.recoveryUnverified,
      );
      expect(
        await File(
          '${directory.path}/organizer_shared_v1.sqlite',
        ).readAsBytes(),
        [1, 2, 3],
      );
      recovery.fillRange(0, recovery.length, 0);
    },
  );

  test(
    'preferences, secure remnants and picker exports each prevent automatic setup',
    () async {
      await preferences.setBool('organizer_local_reminders_enabled_v1', true);
      expect(
        (await service().initializeFreshInstallation()).phase,
        LocalVaultPhase.needsSetup,
      );
      await preferences.remove('organizer_local_reminders_enabled_v1');
      expect(
        (await service(
          retainedSecrets: true,
        ).initializeFreshInstallation()).phase,
        LocalVaultPhase.needsSetup,
      );
      final picker = await Directory.systemTemp.createTemp(
        'jivie-fresh-picker-',
      );
      try {
        await File('${picker.path}/retained.json').writeAsString('retained');
        expect(
          (await service(
            pickerRoots: [LegacyPickerCacheRoot(picker, 'androidPicker')],
          ).initializeFreshInstallation()).phase,
          LocalVaultPhase.needsSetup,
        );
        expect(
          await File('${picker.path}/retained.json').readAsString(),
          'retained',
        );
      } finally {
        await picker.delete(recursive: true);
      }
      expect(keys.writes, 0);
    },
  );

  test(
    'fresh prepared interruption resumes exact key and never calls recovery verification',
    () async {
      final vault = service(
        checkpoint: (stage) {
          if (stage == 'freshPrepared') {
            throw const LocalVaultException('injected_stop');
          }
        },
      );
      await expectLater(
        vault.initializeFreshInstallation(),
        throwsA(isA<LocalVaultException>()),
      );
      final original = keys.value;
      expect(
        (await service().initializeFreshInstallation()).phase,
        LocalVaultPhase.ready,
      );
      expect(keys.value, original);
      expect(keys.writes, 1);
    },
  );

  test(
    'new source after fresh prepare is retained and stops completion',
    () async {
      await expectLater(
        service(
          checkpoint: (stage) {
            if (stage == 'freshPrepared') {
              throw const LocalVaultException('injected_stop');
            }
          },
        ).initializeFreshInstallation(),
        throwsA(isA<LocalVaultException>()),
      );
      await File('${directory.path}/new-retained.bin').writeAsBytes([4, 5, 6]);
      await expectLater(
        service().initializeFreshInstallation(),
        throwsA(
          isA<LocalVaultException>().having(
            (e) => e.code,
            'code',
            'vault_source_changed',
          ),
        ),
      );
      expect(await File('${directory.path}/new-retained.bin').readAsBytes(), [
        4,
        5,
        6,
      ]);
      expect(await service().databaseFile.exists(), false);
    },
  );

  test('fresh journal phase without fresh setup marker is rejected', () async {
    await expectLater(
      service(
        checkpoint: (stage) {
          if (stage == 'freshPrepared') {
            throw const LocalVaultException('injected_stop');
          }
        },
      ).initializeFreshInstallation(),
      throwsA(isA<LocalVaultException>()),
    );
    final journal = File('${service().vaultDirectory.path}/state.json');
    final state =
        jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    state.remove('setupMode');
    await journal.writeAsString(jsonEncode(state));
    await expectLater(
      service().initializeFreshInstallation(),
      throwsA(
        isA<LocalVaultException>().having(
          (e) => e.code,
          'code',
          'vault_journal_invalid',
        ),
      ),
    );
    expect(await service().databaseFile.exists(), false);
    expect(keys.writes, 1);
  });

  test(
    'post-key-store interruption resumes the durable intent and exact key',
    () async {
      await expectLater(
        service(
          checkpoint: (stage) {
            if (stage == 'freshKeyStored') {
              throw const LocalVaultException('injected_stop');
            }
          },
        ).initializeFreshInstallation(),
        throwsA(isA<LocalVaultException>()),
      );
      final original = keys.value;
      final journal = File('${service().vaultDirectory.path}/state.json');
      expect(
        jsonDecode(await journal.readAsString())['phase'],
        'freshKeyIntent',
      );
      expect(
        (await service().initializeFreshInstallation()).phase,
        LocalVaultPhase.ready,
      );
      expect(keys.value, original);
      expect(keys.writes, 1);
    },
  );

  test(
    'pre-key-store interruption regenerates only the empty intent',
    () async {
      await expectLater(
        service(
          checkpoint: (stage) {
            if (stage == 'freshKeyIntent') {
              throw const LocalVaultException('injected_stop');
            }
          },
        ).initializeFreshInstallation(),
        throwsA(isA<LocalVaultException>()),
      );
      expect(keys.value, isNull);
      expect(keys.writes, 0);
      expect(
        (await service().initializeFreshInstallation()).phase,
        LocalVaultPhase.ready,
      );
      expect(keys.writes, 1);
    },
  );

  test('unrelated retained key is never adopted by a fresh intent', () async {
    await expectLater(
      service(
        checkpoint: (stage) {
          if (stage == 'freshKeyIntent') {
            throw const LocalVaultException('injected_stop');
          }
        },
      ).initializeFreshInstallation(),
      throwsA(isA<LocalVaultException>()),
    );
    final unrelated = LocalVaultKey.generate();
    keys.value = unrelated.encode();
    await expectLater(
      service().initializeFreshInstallation(),
      throwsA(isA<LocalVaultException>()),
    );
    expect(keys.value, unrelated.encode());
    expect(keys.writes, 0);
    expect(await service().databaseFile.exists(), false);
    unrelated.bytes.fillRange(0, unrelated.bytes.length, 0);
  });

  test(
    'combined envelope rejects duplicate account keys before normalization',
    () {
      final key = LocalVaultKey.generate();
      final installation = Uint8List.fromList(utf8.encode(key.encode()));
      final account = CryptoJson.encode({
        'accountId': 'account',
        'encryptionPublicKeyBase64': 'enc',
        'fingerprint': 'fingerprint',
        'recoveryId': 'recovery',
        'scope': 'account',
        'secretBase64': 'secret',
        'serverId': 'server',
        'signingPublicKeyBase64': 'sign',
        'suite': 'suite',
        'version': 1,
      });
      final bundle = RecoveryBundleCodec.wrap(installation, account);
      expect(
        utf8.decode(bundle),
        startsWith('{"format":"jivie-recovery","version":1,"installation":'),
      );
      expect(RecoveryBundleCodec.accountBytes(bundle), account);
      expect(LocalVaultKey.decode(utf8.decode(bundle)).id, key.id);
      final duplicateBundle = Uint8List.fromList(
        utf8.encode(
          utf8
              .decode(bundle)
              .replaceFirst(
                '"accountId":"account"',
                '"accountId":"account","accountId":"account"',
              ),
        ),
      );
      expect(
        () => RecoveryBundleCodec.accountBytes(duplicateBundle),
        throwsFormatException,
      );
      expect(
        () => RecoveryBundleCodec.installationBytes(duplicateBundle),
        throwsFormatException,
      );
      final duplicateAccount = Uint8List.fromList(
        utf8.encode(
          utf8
              .decode(account)
              .replaceFirst(
                '"accountId":"account"',
                '"accountId":"account","accountId":"account"',
              ),
        ),
      );
      expect(
        () => RecoveryBundleCodec.wrap(installation, duplicateAccount),
        throwsFormatException,
      );
      final reordered = jsonDecode(utf8.decode(bundle)) as Map<String, dynamic>;
      final originalAccount = reordered['account'] as Map<String, dynamic>;
      reordered['account'] = {
        for (final key in originalAccount.keys.toList().reversed)
          key: originalAccount[key],
      };
      expect(
        () => RecoveryBundleCodec.accountBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(reordered))),
        ),
        throwsFormatException,
      );
      key.bytes.fillRange(0, key.bytes.length, 0);
    },
  );

  test(
    'combined file recovers exact installation while missing key never auto-resets',
    () async {
      final vault = service();
      await vault.initializeFreshInstallation();
      final installation = await vault.prepareRecoveryFile();
      final account = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'accountId': 'account',
            'encryptionPublicKeyBase64': 'enc',
            'fingerprint': 'fingerprint',
            'recoveryId': 'recovery',
            'scope': 'account',
            'secretBase64': 'secret',
            'serverId': 'server',
            'signingPublicKeyBase64': 'sign',
            'suite': 'suite',
            'version': 1,
          }),
        ),
      );
      final bundle = RecoveryBundleCodec.wrap(installation, account);
      expect(
        jsonDecode(utf8.decode(RecoveryBundleCodec.accountBytes(bundle))),
        jsonDecode(utf8.decode(account)),
      );
      expect(
        LocalVaultKey.decode(utf8.decode(bundle)).id,
        LocalVaultKey.decode(utf8.decode(installation)).id,
      );
      keys.value = null;
      expect(
        (await vault.initializeFreshInstallation()).phase,
        LocalVaultPhase.recoveryRequired,
      );
      expect(keys.writes, 1);
      expect((await vault.recover(bundle)).phase, LocalVaultPhase.ready);
      expect(jsonDecode(utf8.decode(bundle))['format'], 'jivie-recovery');
      final malformed = jsonDecode(utf8.decode(bundle)) as Map<String, dynamic>;
      malformed['extra'] = true;
      expect(
        () => RecoveryBundleCodec.accountBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(malformed))),
        ),
        throwsFormatException,
      );
      expect(
        () => RecoveryBundleCodec.installationBytes(
          Uint8List(RecoveryBundleCodec.maxBytes + 1),
        ),
        throwsFormatException,
      );
      expect(
        () => LocalVaultKey.decode(utf8.decode(account)),
        throwsA(isA<LocalVaultException>()),
      );
    },
  );
}
