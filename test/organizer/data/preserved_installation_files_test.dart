import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_keys.dart';
import 'package:kanban/organizer/data/local_vault_native.dart';
import 'package:kanban/organizer/data/local_vault_legacy_cache.dart';
import 'package:kanban/organizer/data/preserved_installation_files.dart';

class _Keys implements LocalVaultKeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'production picker hook survives archive interruption, original FILE and explicit encrypted export',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'jivie-picker-production-',
      );
      addTearDown(() => root.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final keys = _Keys();
      final picker = Directory('${root.path}/cache/file_picker');
      final input = File('${picker.path}/100/other-profile.pdf');
      await input.parent.create(recursive: true);
      final original = Uint8List.fromList(
        List.generate(270001, (i) => i % 251),
      );
      await input.writeAsBytes(original, flush: true);
      var fail = true;
      NativeLocalVaultService service() => NativeLocalVaultService(
        root,
        keys,
        preferences: prefs,
        pickerRoots: [LegacyPickerCacheRoot(picker, 'androidPicker')],
        checkpoint: (stage) {
          if (stage == 'pickerArchiveDurable' && fail) {
            fail = false;
            throw StateError('interrupted');
          }
        },
      );
      final first = service();
      final recovery = await first.prepareRecoveryFile();
      await first.verifyRecoveryFile(recovery);
      await expectLater(first.migrate(), throwsA(isA<LocalVaultException>()));
      expect(await input.exists(), true);
      final resumed = service();
      expect((await resumed.migrate()).phase, LocalVaultPhase.ready);
      expect(await input.exists(), false);
      final listed = await resumed.listPreservedFiles();
      expect(listed.single.name, 'other-profile.pdf');
      expect(await resumed.readPreservedFile(listed.single.id), original);
      keys.value = null;
      expect(
        (await service().inspect()).phase,
        LocalVaultPhase.recoveryRequired,
      );
      expect((await service().recover(recovery)).canOpenDatabase, true);
      final recovered = await service().readPreservedFile(listed.single.id);
      final sealed = await PreservedInstallationBundle.encrypt(
        name: listed.single.name,
        bytes: recovered,
        password: 'installation-wide-file-password',
      );
      recovered.fillRange(0, recovered.length, 0);
      final opened = await PreservedInstallationBundle.decrypt(
        sealed,
        'installation-wide-file-password',
      );
      expect(opened.name, 'other-profile.pdf');
      expect(opened.bytes, original);
      expect(
        await input.exists(),
        false,
      ); // Never recreate picker/original path.
      await expectLater(
        PreservedInstallationBundle.decrypt(sealed, 'different-password'),
        throwsA(anything),
      );
      opened.bytes.fillRange(0, opened.bytes.length, 0);
      recovery.fillRange(0, recovery.length, 0);
    },
  );

  test(
    'unidentified iOS Documents export remains explicit cleanup pending',
    () async {
      final root = await Directory.systemTemp.createTemp('jivie-picker-ios-');
      addTearDown(() => root.delete(recursive: true));
      final docs = Directory('${root.path}/documents');
      await docs.create();
      final unknown = File('${docs.path}/user-original.pdf');
      await unknown.writeAsString('user original never owned by classifier');
      SharedPreferences.setMockInitialValues({});
      final service = NativeLocalVaultService(
        root,
        _Keys(),
        preferences: await SharedPreferences.getInstance(),
        pickerRoots: [LegacyPickerCacheRoot(docs, 'iosDocuments')],
      );
      final file = await service.prepareRecoveryFile();
      await service.verifyRecoveryFile(file);
      final status = await service.migrate();
      expect(status.phase, LocalVaultPhase.cleanupPending);
      expect(status.errorCode, 'vault_historical_exports_retained');
      expect(await unknown.exists(), true);
      expect(await service.listPreservedFiles(), isEmpty);
      file.fillRange(0, file.length, 0);
    },
  );
}
