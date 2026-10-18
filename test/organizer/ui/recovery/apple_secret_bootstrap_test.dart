import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_files.dart';
import 'package:kanban/organizer/data/local_vault_native.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/local_vault_bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/local_vault_native_test.dart' show MemoryVaultKeys;

class _RecoveryFiles extends RecoveryFileIo {
  @override
  Future<void> cleanup() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MemoryVaultKeys keys;
  late SharedPreferences preferences;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'jivie-secret-bootstrap-test-',
    );
    keys = MemoryVaultKeys();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  tearDown(() async => directory.delete(recursive: true));

  NativeLocalVaultService service({Future<void> Function()? protection}) =>
      NativeLocalVaultService(
        directory,
        keys,
        preferences: preferences,
        legacySecretProtection: protection,
      );

  Future<void> makeComplete() async {
    final vault = service();
    final bytes = await vault.prepareRecoveryFile();
    await vault.verifyRecoveryFile(bytes);
    expect((await vault.migrate()).phase, LocalVaultPhase.ready);
    bytes.fillRange(0, bytes.length, 0);
    final journal =
        jsonDecode(
              await File(
                '${vault.vaultDirectory.path}/state.json',
              ).readAsString(),
            )
            as Map;
    expect(journal['phase'], 'complete');
  }

  test(
    'complete journal still protects secrets under exclusive lease; failure and retry preserve journal',
    () async {
      await makeComplete();
      final journal = File('${directory.path}/jivie_vault_v1/state.json');
      final before = await journal.readAsBytes();
      var calls = 0;
      final failed = service(
        protection: () async {
          calls++;
          await expectLater(
            LocalVaultFiles().lock(
              File('${directory.path}/jivie_vault_v1/installation.lock'),
            ),
            throwsA(
              isA<LocalVaultException>().having(
                (e) => e.code,
                'code',
                'vault_busy',
              ),
            ),
          );
          throw const LocalVaultException('vault_secure_storage');
        },
      );
      await expectLater(
        failed.protectSecretsAtStartup(),
        throwsA(
          isA<LocalVaultException>().having(
            (e) => e.code,
            'code',
            'vault_secure_storage',
          ),
        ),
      );
      expect(calls, 1);
      expect(await journal.readAsBytes(), before);
      final retry = service(
        protection: () async {
          calls++;
        },
      );
      await retry.protectSecretsAtStartup();
      expect(calls, 2);
      expect((await retry.inspect()).phase, LocalVaultPhase.ready);
      expect(await journal.readAsBytes(), before);
    },
  );

  testWidgets(
    'complete-journal bootstrap retries failed protection and mounts child only after second success',
    (tester) async {
      await tester.runAsync(makeComplete);
      var inspected = 0, consumers = 0;
      final openings = <Completer<LocalVaultService>>[];
      var failedProtectionCompleted = false;
      var failProtection = true;
      final vault = service(
        protection: () async {
          if (failProtection) {
            throw const LocalVaultException('vault_secure_storage');
          }
        },
      );
      final consumer = Provider((ref) {
        consumers++;
        return 1;
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localVaultServiceProvider.overrideWith((ref) {
              final opening = Completer<LocalVaultService>();
              openings.add(opening);
              return opening.future;
            }),
            recoveryFileIoProvider.overrideWithValue(_RecoveryFiles()),
          ],
          child: LocalVaultBootstrap(
            child: Consumer(
              builder: (context, ref, _) {
                ref.watch(consumer);
                return const MaterialApp(
                  home: Text('normal app and session router'),
                );
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        try {
          await vault.protectSecretsAtStartup();
          inspected++;
          openings.single.complete(vault);
        } catch (error, stack) {
          failedProtectionCompleted = true;
          openings.single.completeError(error, stack);
        }
      });
      await tester.pumpAndSettle();
      expect(failedProtectionCompleted, isTrue);
      expect(inspected, 0);
      expect(consumers, 0);
      expect(find.text('normal app and session router'), findsNothing);
      expect(find.byKey(const ValueKey('vault_error')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(TextButton),
        200,
        maxScrolls: 20,
      );
      final retry = tester.widgetList<TextButton>(find.byType(TextButton));
      expect(retry.any((button) => button.onPressed != null), isTrue);
      expect(openings, hasLength(1));
      await tester.tap(find.byType(TextButton).first);
      await tester.pump();
      expect(openings, hasLength(2));
      expect(consumers, 0);
      failProtection = false;
      await tester.runAsync(() async {
        await vault.protectSecretsAtStartup();
        inspected++;
        openings.last.complete(vault);
      });
      for (var i = 0; i < 50 && consumers == 0; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await tester.pump();
      }
      expect(inspected, 1);
      expect(consumers, 1);
      expect(find.text('normal app and session router'), findsOneWidget);
      expect(find.byKey(const ValueKey('vault_error')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
