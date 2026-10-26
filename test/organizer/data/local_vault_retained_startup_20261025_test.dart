import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_native.dart';
import 'package:kanban/organizer/data/local_vault_legacy_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_vault_native_test.dart' show MemoryVaultKeys;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'new native retained-only startup requires complete verified installation',
    () async {
      final root = await Directory.systemTemp.createTemp('retained-startup-');
      addTearDown(() => root.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final keys = MemoryVaultKeys();
      final diagnostic = File('${root.path}/jivie_qa_old/diagnostic.json');
      await diagnostic.parent.create();
      final original = utf8.encode('{"private-synthetic-sentinel":true}');
      await diagnostic.writeAsBytes(original, flush: true);
      final vault = NativeLocalVaultService(
        root,
        keys,
        preferences: preferences,
        pickerRoots: [LegacyPickerCacheRoot(root, 'iosDocuments')],
      );
      final recovery = await vault.prepareRecoveryFile();
      try {
        await vault.verifyRecoveryFile(recovery);
      } finally {
        recovery.fillRange(0, recovery.length, 0);
      }
      await vault.migrate();
      final status = await vault.inspect();
      expect(status.phase, LocalVaultPhase.cleanupPending);
      expect(status.retainedCopiesOnly, isTrue);
      expect(status.canContinueWithRetainedCopies, isTrue);
      expect(await diagnostic.readAsBytes(), original);
      final journal = File('${vault.vaultDirectory.path}/state.json');
      final complete = jsonDecode(await journal.readAsString()) as Map;
      expect(complete['phase'], 'complete');
      expect(complete['pickerCleanupPending'], isFalse);
      expect(complete['pickerResidualFiles'], 1);
      for (final override in [
        {'phase': 'switched'},
        {'pickerCleanupPending': true},
        {'pickerResidualFiles': null},
        {'pickerResidualFiles': -1},
      ]) {
        await journal.writeAsString(
          jsonEncode({...complete, ...override}),
          flush: true,
        );
        expect((await vault.inspect()).canContinueWithRetainedCopies, isFalse);
      }
      await journal.writeAsString(jsonEncode(complete), flush: true);
      final legacy = File('${root.path}/organizer_personal_v1.hive');
      await legacy.writeAsString('new unprotected synthetic legacy writer');
      expect((await vault.inspect()).canContinueWithRetainedCopies, isFalse);
      expect(
        await legacy.readAsString(),
        'new unprotected synthetic legacy writer',
      );
      await legacy.delete();
      await preferences.setString(
        'organizer_notification_ids_v1',
        'private sentinel',
      );
      expect((await vault.inspect()).canContinueWithRetainedCopies, isFalse);
      await preferences.remove('organizer_notification_ids_v1');
      keys.unavailable = true;
      final missingKey = await vault.inspect();
      expect(missingKey.phase, LocalVaultPhase.recoveryRequired);
      expect(missingKey.canContinueWithRetainedCopies, isFalse);
      expect(await diagnostic.readAsBytes(), original);
    },
  );
}
