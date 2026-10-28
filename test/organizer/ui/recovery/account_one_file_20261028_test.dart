import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/l10n.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/recovery_file_codec.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_keys.dart';
import 'package:kanban/organizer/data/recovery_bundle.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:kanban/organizer/presentation/backup/backup_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_wizard.dart';
import 'package:kanban/organizer/presentation/recovery/local_vault_bootstrap.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:sodium/sodium.dart';

class _Store implements CryptoIdentityStore {
  @override
  String get partition => 'synthetic-partition';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Directory implements AccountDirectoryRepository {
  @override
  bool Function() get isCurrent =>
      () => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Workflow implements AccountCryptoV2Workflow {
  _Workflow(this.file);
  final Uint8List file;
  bool saved = false, initialized = false;
  int acknowledgements = 0, initializations = 0;
  String phase = 'missing';
  @override
  final store = _Store();
  @override
  final directory = _Directory();
  @override
  String get deviceId => 'synthetic-device';
  @override
  Future<Map<String, dynamic>> status() async => {'initialized': initialized};
  @override
  Future<String> localPhase() async => phase;
  @override
  Future<bool> hasSavedSetup() async => saved;
  @override
  Future<bool> canRebindLocalDevice() async => false;
  @override
  Future<bool> hasIncompleteScopeRecovery() async => false;
  @override
  Future<Uint8List> prepareRecoveryFile() async {
    phase = 'prepared';
    return Uint8List.fromList(file);
  }

  @override
  Future<void> confirmSavedRecoveryFile(Uint8List exported) async {
    final extracted = RecoveryBundleCodec.accountBytes(exported);
    expect(extracted, orderedEquals(file));
    extracted.fillRange(0, extracted.length, 0);
    acknowledgements++;
    saved = true;
    phase = 'saved';
  }

  @override
  Future<void> resumeSavedSetup() async {
    expect(saved, true);
    initializations++;
    initialized = true;
    phase = 'ready';
  }

  @override
  Future<void> verifyAndInitialize(Uint8List external) async {
    expect(external, orderedEquals(file));
    initializations++;
    initialized = true;
    phase = 'ready';
  }

  @override
  Future<void> finishSavedSetup() async => saved = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Vault implements LocalVaultService {
  _Vault(this.file);
  final Uint8List file;
  @override
  Future<Uint8List> prepareRecoveryFile() async => Uint8List.fromList(file);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Files extends RecoveryFileIo {
  _Files(this.result);
  final BackupSaveStatus result;
  Uint8List? exported;
  Uint8List? selected;
  int picks = 0, shares = 0;
  bool? accountOnly;
  @override
  bool get canShare => true;
  @override
  Future<BackupSaveStatus> save(
    Uint8List bytes,
    String title, {
    bool accountOnly = false,
  }) async {
    exported = Uint8List.fromList(bytes);
    this.accountOnly = accountOnly;
    return result;
  }

  @override
  Future<Uint8List?> pick() async {
    picks++;
    return selected == null ? null : Uint8List.fromList(selected!);
  }
}

class _Protection extends AccountProtectionReady {
  _Protection(super.account);
  int completions = 0;
  @override
  Future<bool> completeFreshSetup({void Function(int)? onPause}) async {
    completions++;
    return true;
  }
}

class _Collaboration extends CollaborationController {
  @override
  Future<CollaborationState> build() async => CollaborationState();
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));

  for (final result in BackupSaveStatus.values) {
    testWidgets(
      'one combined file: ${result.name} has exact activation outcome',
      (tester) async {
        final material = RecoveryFileCodec(
          crypto,
        ).create(serverId: crypto.randomId(), accountId: crypto.randomId());
        final key = LocalVaultKey.generate();
        final local = Uint8List.fromList(utf8.encode(key.encode()));
        final workflow = _Workflow(material.file), files = _Files(result);
        final protection = _Protection(workflow);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              recoveryFileIoProvider.overrideWithValue(files),
              localVaultServiceProvider.overrideWith(
                (ref) async => _Vault(local),
              ),
              collaborationProvider.overrideWith(_Collaboration.new),
              accountFreshSetupProtectionProvider.overrideWithValue(
                (_) => protection,
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AccountCryptoWizard(workflow: workflow),
                    ),
                  ),
                  child: const Text('Open setup'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open setup'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('account_crypto_share')),
          findsNothing,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('account_crypto_save')),
        );
        await tester.tap(find.byKey(const ValueKey('account_crypto_save')));
        await tester.pumpAndSettle();
        expect(files.exported, isNotNull);
        expect(files.accountOnly, false);
        final recoveredLocal = LocalVaultKey.decode(
          utf8.decode(files.exported!),
        );
        expect(recoveredLocal.id, key.id);
        expect(recoveredLocal.bytes, orderedEquals(key.bytes));
        expect(files.picks, 0);
        final activated = result == BackupSaveStatus.saved;
        expect(workflow.acknowledgements, activated ? 1 : 0);
        expect(workflow.initializations, activated ? 1 : 0);
        expect(protection.completions, activated ? 1 : 0);
        expect(
          find.byKey(const ValueKey('account_crypto_verify')),
          findsNothing,
        );
        expect(
          find.byType(AccountCryptoWizard),
          activated ? findsNothing : findsOneWidget,
        );
        material.dispose();
        key.bytes.fillRange(0, key.bytes.length, 0);
        recoveredLocal.bytes.fillRange(0, recoveredLocal.bytes.length, 0);
        local.fillRange(0, local.length, 0);
        files.exported!.fillRange(0, files.exported!.length, 0);
      },
    );
  }

  testWidgets(
    'download-only capability keeps account export and explicit file verification',
    (tester) async {
      final material = RecoveryFileCodec(
        crypto,
      ).create(serverId: crypto.randomId(), accountId: crypto.randomId());
      final workflow = _Workflow(material.file);
      final files = _Files(BackupSaveStatus.downloadStarted)
        ..selected = material.file;
      final protection = _Protection(workflow);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountCombinedRecoveryAvailableProvider.overrideWithValue(false),
            recoveryFileIoProvider.overrideWithValue(files),
            localVaultServiceProvider.overrideWith(
              (ref) async => throw StateError('No browser installation key'),
            ),
            collaborationProvider.overrideWith(_Collaboration.new),
            accountFreshSetupProtectionProvider.overrideWithValue(
              (_) => protection,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: AccountCryptoWizard(workflow: workflow),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('account_crypto_save')),
      );
      await tester.tap(find.byKey(const ValueKey('account_crypto_save')));
      await tester.pumpAndSettle();
      expect(files.accountOnly, true);
      expect(files.exported, orderedEquals(material.file));
      expect(workflow.initializations, 0);
      expect(workflow.acknowledgements, 0);
      expect(protection.completions, 0);
      expect(find.byKey(const ValueKey('account_crypto_error')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('account_crypto_verify')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account_crypto_verify')));
      await tester.pumpAndSettle();
      expect(files.picks, 1);
      expect(workflow.initializations, 1);
      expect(protection.completions, 1);
      expect(workflow.acknowledgements, 0);
      material.dispose();
      files.exported!.fillRange(0, files.exported!.length, 0);
    },
  );
}
