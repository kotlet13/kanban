import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:kanban/organizer/presentation/backup/backup_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/local_vault_bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements LocalVaultService {
  _Vault(this.phase);
  LocalVaultPhase phase;
  Completer<LocalVaultStatus>? inspection;
  int verifications = 0, migrations = 0, recoveries = 0;
  bool failMigration = false;
  @override
  Future<LocalVaultStatus> inspect() async =>
      inspection == null ? LocalVaultStatus(phase) : inspection!.future;
  @override
  Future<Uint8List> prepareRecoveryFile() async {
    phase = LocalVaultPhase.recoveryUnverified;
    return Uint8List.fromList([7, 8, 9]);
  }

  @override
  Future<LocalVaultStatus> verifyRecoveryFile(Uint8List bytes) async {
    verifications++;
    if (bytes[0] != 7) throw const FormatException('wrong secret/path');
    phase = LocalVaultPhase.migrationPending;
    return LocalVaultStatus(phase);
  }

  @override
  Future<LocalVaultStatus> migrate() async {
    migrations++;
    if (failMigration) throw const LocalVaultException('keep_original');
    phase = LocalVaultPhase.ready;
    return LocalVaultStatus(phase);
  }

  @override
  Future<LocalVaultStatus> recover(Uint8List bytes) async {
    recoveries++;
    if (bytes[0] != 7) throw const FormatException('wrong file');
    phase = LocalVaultPhase.ready;
    return LocalVaultStatus(phase);
  }
}

class _Files extends RecoveryFileIo {
  Uint8List? selected;
  int saved = 0, shared = 0;
  @override
  bool get canShare => true;
  @override
  Future<void> share(
    Uint8List bytes,
    String title, {
    bool accountOnly = false,
  }) async {
    shared++;
  }

  @override
  Future<Uint8List?> pick() async => selected;
  @override
  Future<BackupSaveStatus> save(
    Uint8List bytes,
    String title, {
    bool accountOnly = false,
  }) async {
    saved++;
    return BackupSaveStatus.cancelled;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester,
    _Vault vault,
    _Files files, {
    Widget child = const MaterialApp(home: Text('normal app')),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localVaultServiceProvider.overrideWith((ref) async => vault),
          recoveryFileIoProvider.overrideWithValue(files),
        ],
        child: LocalVaultBootstrap(child: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('system share never verifies or migrates installation recovery', (
    tester,
  ) async {
    final vault = _Vault(LocalVaultPhase.needsSetup), files = _Files();
    await pump(tester, vault, files);
    final share = find.byKey(const ValueKey('vault_share'));
    await tester.scrollUntilVisible(share, 180, maxScrolls: 30);
    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(files.shared, 1);
    expect(vault.phase, LocalVaultPhase.recoveryUnverified);
    expect(vault.verifications, 0);
    expect(vault.migrations, 0);
    expect(find.byKey(const ValueKey('vault_verify')), findsOneWidget);
    expect(find.text('normal app'), findsNothing);
  });
  testWidgets(
    'pending bootstrap never mounts database/router/replay consumers',
    (tester) async {
      var opened = 0;
      final consumer = Provider((ref) {
        opened++;
        return 1;
      });
      final vault = _Vault(LocalVaultPhase.needsSetup);
      await pump(
        tester,
        vault,
        _Files(),
        child: Consumer(
          builder: (context, ref, child) {
            ref.watch(consumer);
            return const MaterialApp(home: Text('router and replay'));
          },
        ),
      );
      expect(opened, 0);
      expect(find.text('router and replay'), findsNothing);
      expect(find.byKey(const ValueKey('vault_save')), findsOneWidget);
    },
  );

  testWidgets('cancelled save and file picker never enable migration', (
    tester,
  ) async {
    final vault = _Vault(LocalVaultPhase.needsSetup);
    final files = _Files();
    await pump(tester, vault, files);
    await tester.tap(find.byKey(const ValueKey('vault_save')));
    await tester.pumpAndSettle();
    expect(files.saved, 1);
    expect(find.byKey(const ValueKey('vault_migrate')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vault_verify')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('vault_verify')));
    await tester.pumpAndSettle();
    expect(vault.verifications, 0);
    expect(vault.migrations, 0);
    expect(find.text('normal app'), findsNothing);
  });

  testWidgets('external reimport then durable migration opens the normal app', (
    tester,
  ) async {
    final vault = _Vault(LocalVaultPhase.recoveryUnverified);
    final files = _Files()..selected = Uint8List.fromList([7, 8, 9]);
    await pump(tester, vault, files);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vault_verify')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('vault_verify')));
    await tester.pumpAndSettle();
    expect(vault.verifications, 1);
    expect(vault.migrations, 0);
    expect(files.selected, [0, 0, 0]);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vault_migrate')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('vault_migrate')));
    await tester.pumpAndSettle();
    expect(vault.migrations, 1);
    expect(find.text('normal app'), findsOneWidget);
  });

  testWidgets('failed migration keeps gate and safe resumable status', (
    tester,
  ) async {
    final vault = _Vault(LocalVaultPhase.migrationPending)
      ..failMigration = true;
    await pump(tester, vault, _Files());
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vault_migrate')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('vault_migrate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vault_error')), findsOneWidget);
    expect(find.text('normal app'), findsNothing);
    expect(find.textContaining('keep_original'), findsNothing);
    vault.failMigration = false;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vault_migrate')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('vault_migrate')));
    await tester.pumpAndSettle();
    expect(find.text('normal app'), findsOneWidget);
  });

  testWidgets('missing key offers existing installation recovery only', (
    tester,
  ) async {
    final vault = _Vault(LocalVaultPhase.recoveryRequired);
    final files = _Files()..selected = Uint8List.fromList([7]);
    await pump(tester, vault, files);
    expect(find.byKey(const ValueKey('vault_save')), findsNothing);
    expect(find.byKey(const ValueKey('vault_migrate')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vault_recover')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('vault_recover')));
    await tester.pumpAndSettle();
    expect(vault.recoveries, 1);
    expect(find.text('normal app'), findsOneWidget);
  });

  testWidgets('cleanup failure does not claim complete local protection', (
    tester,
  ) async {
    final vault = _Vault(LocalVaultPhase.cleanupPending);
    await pump(tester, vault, _Files());
    expect(find.text('normal app'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vault_continue_cleanup')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('vault_continue_cleanup')));
    await tester.pumpAndSettle();
    expect(find.text('normal app'), findsOneWidget);
    final banner = tester.widget<Banner>(
      find.byWidgetPredicate(
        (widget) => widget is Banner && widget.message == 'Cleanup unfinished',
      ),
    );
    expect(banner.message, 'Cleanup unfinished');
  });
}
