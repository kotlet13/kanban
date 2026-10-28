import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/local_vault_bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FreshVault implements LocalVaultService, LocalVaultFreshSetup {
  final result = Completer<LocalVaultStatus>();
  int starts = 0;
  @override
  Future<LocalVaultStatus> initializeFreshInstallation() {
    starts++;
    return result.future;
  }

  @override
  Future<LocalVaultStatus> inspect() async =>
      const LocalVaultStatus(LocalVaultPhase.needsSetup);
  @override
  Future<Uint8List> prepareRecoveryFile() async =>
      throw StateError('no export');
  @override
  Future<LocalVaultStatus> verifyRecoveryFile(Uint8List bytes) async =>
      throw StateError('no verification');
  @override
  Future<LocalVaultStatus> recover(Uint8List bytes) async =>
      throw StateError('no recovery');
  @override
  Future<LocalVaultStatus> migrate() async =>
      throw StateError('no manual migration');
}

class _Files extends RecoveryFileIo {
  @override
  Future<void> cleanup() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'fresh initialization mounts app only after encrypted setup succeeds',
    (tester) async {
      final vault = _FreshVault();
      var consumers = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localVaultServiceProvider.overrideWith((ref) async => vault),
            recoveryFileIoProvider.overrideWithValue(_Files()),
          ],
          child: LocalVaultBootstrap(
            child: Builder(
              builder: (context) {
                consumers++;
                return const MaterialApp(home: Text('fresh offline app'));
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(vault.starts, 1);
      expect(consumers, 0);
      expect(find.byKey(const ValueKey('vault_save')), findsNothing);
      vault.result.complete(const LocalVaultStatus(LocalVaultPhase.ready));
      await tester.pumpAndSettle();
      expect(consumers, 1);
      expect(find.text('fresh offline app'), findsOneWidget);
    },
  );
}
