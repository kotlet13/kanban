import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/local_vault_bootstrap.dart';
import 'package:kanban/widgets/jivie_startup_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements LocalVaultService {
  final inspection = Completer<LocalVaultStatus>();
  @override
  Future<LocalVaultStatus> inspect() => inspection.future;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No mutation');
}

class _Files extends RecoveryFileIo {
  @override
  Future<void> cleanup() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No file action');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final entry in <String, LocalVaultStatus>{
    'ready': const LocalVaultStatus(LocalVaultPhase.ready),
    'retained copies': const LocalVaultStatus(
      LocalVaultPhase.cleanupPending,
      retainedCopiesOnly: true,
      errorCode: 'vault_historical_exports_retained',
    ),
    'real recovery': const LocalVaultStatus(LocalVaultPhase.recoveryRequired),
    'first setup': const LocalVaultStatus(LocalVaultPhase.needsSetup),
    'real cleanup': const LocalVaultStatus(LocalVaultPhase.cleanupPending),
  }.entries) {
    testWidgets('initial logo then ${entry.key} without premature consumers', (
      tester,
    ) async {
      final vault = _Vault();
      var mounts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localVaultServiceProvider.overrideWith((ref) async => vault),
            recoveryFileIoProvider.overrideWithValue(_Files()),
          ],
          child: LocalVaultBootstrap(
            child: Builder(
              builder: (_) {
                mounts++;
                return const MaterialApp(home: Text('saved workspace Pulse'));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(JivieStartupLogo), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(mounts, 0);
      vault.inspection.complete(entry.value);
      await tester.pumpAndSettle();
      expect(find.byType(JivieStartupLogo), findsNothing);
      final opens =
          entry.value.phase == LocalVaultPhase.ready ||
          entry.value.canContinueWithRetainedCopies;
      expect(mounts, opens ? greaterThan(0) : 0);
      expect(
        find.text('saved workspace Pulse'),
        opens ? findsOneWidget : findsNothing,
      );
      if (!opens) expect(find.byType(AppBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('inspection error never becomes a loading loop or opens data', (
    tester,
  ) async {
    final vault = _Vault();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localVaultServiceProvider.overrideWith((ref) async => vault),
          recoveryFileIoProvider.overrideWithValue(_Files()),
        ],
        child: const LocalVaultBootstrap(
          child: MaterialApp(home: Text('must stay closed')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(JivieStartupLogo), findsOneWidget);
    vault.inspection.completeError(const LocalVaultException('vault_io'));
    await tester.pumpAndSettle();
    expect(find.byType(JivieStartupLogo), findsNothing);
    expect(find.text('must stay closed'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vault_error')),
      150,
    );
    expect(find.byKey(const ValueKey('vault_error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
