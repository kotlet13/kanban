import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_keys.dart';
import 'package:kanban/organizer/data/local_vault_files.dart';
import 'package:kanban/organizer/data/local_vault_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  test(
    'recovery export works while the fresh encrypted database stays open',
    () async {
      final dir = await Directory.systemTemp.createTemp('jivie-export-open-');
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      final vault = NativeLocalVaultService(
        dir,
        keys,
        preferences: await SharedPreferences.getInstance(),
      );
      try {
        expect(
          (await vault.initializeFreshInstallation()).phase,
          LocalVaultPhase.ready,
        );
        final db = await vault.openDatabase();
        try {
          await db.execute(
            "INSERT INTO local_meta VALUES('export_sentinel','preserved')",
          );
          final journal = await File(
            '${vault.vaultDirectory.path}/state.json',
          ).readAsBytes();
          final originalKey = keys.value;
          final file = await vault.prepareRecoveryFile();
          try {
            expect(
              LocalVaultKey.decode(utf8.decode(file)).encode(),
              originalKey,
            );
            expect(keys.writes, 1);
            expect(
              await File(
                '${vault.vaultDirectory.path}/state.json',
              ).readAsBytes(),
              journal,
            );
            expect(
              (await db.rows(
                "SELECT value FROM local_meta WHERE name='export_sentinel'",
              )).single['value'],
              'preserved',
            );
            await db.execute(
              "UPDATE local_meta SET value='still writable' WHERE name='export_sentinel'",
            );
          } finally {
            file.fillRange(0, file.length, 0);
          }
        } finally {
          await db.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('export cannot bypass an exclusive installation operation', () async {
    final dir = await Directory.systemTemp.createTemp('jivie-export-guard-');
    SharedPreferences.setMockInitialValues({});
    final keys = _Keys();
    final vault = NativeLocalVaultService(
      dir,
      keys,
      preferences: await SharedPreferences.getInstance(),
    );
    try {
      await vault.initializeFreshInstallation();
      final before = keys.value;
      final lease = await LocalVaultFiles().lock(
        File('${vault.vaultDirectory.path}/installation.lock'),
      );
      try {
        await expectLater(
          vault.prepareRecoveryFile(),
          throwsA(
            isA<LocalVaultException>().having(
              (e) => e.code,
              'code',
              'vault_busy',
            ),
          ),
        );
        expect(keys.value, before);
        expect(keys.writes, 1);
      } finally {
        await lease.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'open-vault export with missing secure key never creates replacement',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'jivie-export-missing-',
      );
      SharedPreferences.setMockInitialValues({});
      final keys = _Keys();
      final vault = NativeLocalVaultService(
        dir,
        keys,
        preferences: await SharedPreferences.getInstance(),
      );
      try {
        await vault.initializeFreshInstallation();
        final db = await vault.openDatabase();
        try {
          final journal = await File(
            '${vault.vaultDirectory.path}/state.json',
          ).readAsBytes();
          keys.value = null;
          await expectLater(
            vault.prepareRecoveryFile(),
            throwsA(
              isA<LocalVaultException>().having(
                (e) => e.code,
                'code',
                'vault_recovery_required',
              ),
            ),
          );
          expect(keys.value, isNull);
          expect(keys.writes, 1);
          expect(
            await File('${vault.vaultDirectory.path}/state.json').readAsBytes(),
            journal,
          );
        } finally {
          await db.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
