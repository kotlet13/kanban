import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/backup/backup_wizard.dart';
import 'package:kanban/organizer/presentation/backup/backup_recovery.dart';
import 'package:kanban/organizer/presentation/backup/backup_file_io.dart';
import 'package:kanban/organizer/state/portable_backup_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'organizer_ui_test.dart' show MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';

class FakeBackupController extends PortableBackupController {
  bool rejectPrepared = false, wrongPassword = false, canResume = true;
  bool financialReview = false;
  int exports = 0, restores = 0, resumes = 0;
  int? restoreRevision;
  BackupRestoreMode? restoreMode;
  @override
  Future<void> build() async {}
  BackupPreview get preview => BackupPreview(
    backupId: 'backup',
    createdAt: DateTime.utc(2026, 10, 5),
    personalRevision: 99,
    personalCounts: {'tasks': 3, 'financeEntries': 2},
    scopeCount: 1,
    pendingCount: 2,
    hasRemoteRecovery: true,
    sourceAccount: 'Ime izvornega računa',
    sourceServer: 'https://source.example.test',
  );
  @override
  Future<Uint8List> exportEncryptedBackup(String password) async {
    exports++;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<BackupPreview> inspectEncryptedBackup(
    List<int> bytes,
    String password,
  ) async {
    if (wrongPassword) throw const CollaborationException('backup_auth_failed');
    return preview;
  }

  @override
  Future<void> validatePreparedExport(String id) async {
    if (rejectPrepared) throw const CollaborationException('backup_stale');
  }

  @override
  Future<BackupRestoreResult> restoreEncryptedBackup(
    List<int> bytes,
    String password, {
    required BackupRestoreMode mode,
    required int expectedPersonalRevision,
  }) async {
    restores++;
    restoreRevision = expectedPersonalRevision;
    restoreMode = mode;
    return const BackupRestoreResult(
      backupId: 'backup',
      personalRecordCount: 5,
      hasRemoteRecovery: true,
    );
  }

  @override
  Future<List<BackupPreview>> listRestoredBackups() async => [preview];
  @override
  Future<BackupRecoveryReview> reviewRestoredWork(
    String id,
    String password,
  ) async => BackupRecoveryReview(
    backupId: id,
    sourceAccount: preview.sourceAccount,
    sourceServer: preview.sourceServer,
    canResume: canResume,
    items: [
      BackupRecoveryItem(
        scopeId: sharingScopeId,
        scopeName: 'Arhivirani dom',
        recordId: 'one',
        recordType: financialReview ? 'financeEntry' : 'task',
        title: financialReview
            ? 'Zaseben finančni naslov'
            : 'Obnovljeno opravilo',
        state: 'pending',
        isFinancial: financialReview,
      ),
    ],
  );
  @override
  Future<void> resumeRestoredWork(String id, {required String password}) async {
    resumes++;
  }
}

class UnavailableSecureStorageController extends SharingUiController {
  @override
  Future<CollaborationState> build() async =>
      throw const CollaborationException('secure_storage');
}

class FakeBackupIo extends BackupFileIo {
  int saves = 0;
  BackupSaveStatus saveStatus = BackupSaveStatus.cancelled;
  @override
  Future<PickedBackupFile?> pick({required int maxBytes}) async =>
      PickedBackupFile('copy.vsakdan', Uint8List.fromList([1, 2, 3]));
  @override
  Future<BackupSaveStatus> save(
    Uint8List bytes, {
    required String title,
    required String name,
  }) async {
    saves++;
    return saveStatus;
  }
}

Future<void> pumpBackup(
  WidgetTester tester,
  FakeBackupController backup,
  FakeBackupIo io,
  Widget child, {
  SharingUiController? collaboration,
  double width = 390,
  String language = 'sl',
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        portableBackupProvider.overrideWith(() => backup),
        backupFileIoProvider.overrideWithValue(io),
        collaborationProvider.overrideWith(
          () =>
              collaboration ??
              SharingUiController(initial: CollaborationState()),
        ),
        organizerStorageProvider.overrideWithValue(
          () async => MemoryOrganizerStorage(),
        ),
      ],
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> password(WidgetTester tester, {bool restore = false}) async {
  await tester.enterText(
    find.byKey(const ValueKey('backup-password')),
    'a strong password',
  );
  if (!restore) {
    await tester.enterText(
      find.byKey(const ValueKey('backup-confirm')),
      'a strong password',
    );
  }
}

Future<void> click(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final language in ['sl', 'en']) {
      testWidgets('encrypted backup password screen fits $width $language', (
        tester,
      ) async {
        await pumpBackup(
          tester,
          FakeBackupController(),
          FakeBackupIo(),
          const BackupWizard(restore: false),
          width: width,
          language: language,
          dark: language == 'en',
        );
        expect(find.byKey(const ValueKey('backup-password')), findsOneWidget);
        expect(tester.takeException(), null);
      });
    }
  }
  testWidgets(
    'export shows source and cannot hand stale rights to file dialog',
    (tester) async {
      final backup = FakeBackupController(), io = FakeBackupIo();
      await pumpBackup(tester, backup, io, const BackupWizard(restore: false));
      await password(tester);
      await click(tester, 'Pripravi šifrirano kopijo');
      expect(backup.exports, 1);
      expect(
        find.textContaining('https://source.example.test'),
        findsOneWidget,
      );
      backup.rejectPrepared = true;
      await click(tester, 'Shrani datoteko kopije');
      expect(io.saves, 0);
    },
  );
  testWidgets('native cancelled save is clearly reported', (tester) async {
    final backup = FakeBackupController(), io = FakeBackupIo();
    await pumpBackup(tester, backup, io, const BackupWizard(restore: false));
    await password(tester);
    await click(tester, 'Pripravi šifrirano kopijo');
    await click(tester, 'Shrani datoteko kopije');
    expect(io.saves, 1);
    expect(
      find.text('Shranjevanje je preklicano. Datoteka ni bila shranjena.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'restore preview never writes until final confirmation and uses current local revision',
    (tester) async {
      final backup = FakeBackupController(), io = FakeBackupIo();
      await pumpBackup(tester, backup, io, const BackupWizard(restore: true));
      await click(tester, 'Izberi šifrirano kopijo');
      await password(tester, restore: true);
      await click(tester, 'Odpri in preglej kopijo');
      expect(backup.restores, 0);
      await click(tester, 'Potrdi obnovo', settle: false);
      expect(backup.restores, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Potrdi obnovo').last);
      await tester.pumpAndSettle();
      expect(backup.restores, 1);
      expect(backup.restoreMode, BackupRestoreMode.merge);
      expect(backup.restoreRevision, 0);
    },
  );
  testWidgets('wrong password leaves restore untouched', (tester) async {
    final backup = FakeBackupController()..wrongPassword = true;
    await pumpBackup(
      tester,
      backup,
      FakeBackupIo(),
      const BackupWizard(restore: true),
    );
    await click(tester, 'Izberi šifrirano kopijo');
    await password(tester, restore: true);
    await click(tester, 'Odpri in preglej kopijo');
    expect(backup.restores, 0);
    expect(find.textContaining('Geslo ni pravilno'), findsOneWidget);
  });
  testWidgets(
    'recovery stays explicit; wrong identity can review but cannot resume',
    (tester) async {
      final backup = FakeBackupController()..canResume = false;
      await pumpBackup(
        tester,
        backup,
        FakeBackupIo(),
        const BackupRecoveryPanel(),
        collaboration: SharingUiController(),
      );
      await tester.tap(find.text('Ime izvornega računa'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sharing-password')),
        'a strong password',
      );
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Obnovljeno opravilo'), findsOneWidget);
      expect(find.text('Dovoli nadaljevanje obnovljenega dela'), findsNothing);
      expect(backup.resumes, 0);
    },
  );
  testWidgets('finance revoke closes unlocked financial recovery preview', (
    tester,
  ) async {
    final backup = FakeBackupController()..financialReview = true;
    final controller = SharingUiController(
      initial: CollaborationState(
        session: sharingSession(),
        scopes: [sharingScope()],
        financePolicies: {
          sharingScopeId: const SharedFinancePolicy(
            enabled: true,
            grant: SharedFinanceGrant.write,
            revision: 1,
          ),
        },
      ),
    );
    await pumpBackup(
      tester,
      backup,
      FakeBackupIo(),
      const BackupRecoveryPanel(),
      collaboration: controller,
    );
    await tester.tap(find.text('Ime izvornega računa'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sharing-password')),
      'a strong password',
    );
    await tester.tap(find.byKey(const ValueKey('sharing-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Zaseben finančni naslov'), findsOneWidget);
    controller.replace(
      CollaborationState(
        session: sharingSession(),
        scopes: [sharingScope()],
        financePolicies: {
          sharingScopeId: const SharedFinancePolicy(revision: 2),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zaseben finančni naslov'), findsNothing);
    expect(backup.resumes, 0);
  });
  testWidgets(
    'replace is a separate explicit choice and requires final confirmation',
    (tester) async {
      final backup = FakeBackupController();
      await pumpBackup(
        tester,
        backup,
        FakeBackupIo(),
        const BackupWizard(restore: true),
      );
      await click(tester, 'Izberi šifrirano kopijo');
      await password(tester, restore: true);
      await click(tester, 'Odpri in preglej kopijo');
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<BackupRestoreMode>),
      );
      await tester.tap(find.byType(DropdownButtonFormField<BackupRestoreMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zamenjaj osebne zapise').last);
      await tester.pumpAndSettle();
      await click(tester, 'Potrdi obnovo', settle: false);
      expect(backup.restores, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Potrdi obnovo').last);
      await tester.pumpAndSettle();
      expect(backup.restoreMode, BackupRestoreMode.replace);
    },
  );
  testWidgets(
    'account switch clears a prepared export and disables disk handoff',
    (tester) async {
      final backup = FakeBackupController(),
          io = FakeBackupIo(),
          controller = SharingUiController();
      await pumpBackup(
        tester,
        backup,
        io,
        const BackupWizard(restore: false),
        collaboration: controller,
      );
      await password(tester);
      await click(tester, 'Pripravi šifrirano kopijo');
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(find.textContaining('https://source.example.test'), findsNothing);
      expect(find.text('Shrani datoteko kopije'), findsNothing);
      expect(io.saves, 0);
    },
  );
  testWidgets(
    'same-device invalid session clears prepared encrypted bytes from the wizard',
    (tester) async {
      final backup = FakeBackupController(),
          io = FakeBackupIo(),
          controller = SharingUiController();
      await pumpBackup(
        tester,
        backup,
        io,
        const BackupWizard(restore: false),
        collaboration: controller,
      );
      await password(tester);
      await click(tester, 'Pripravi šifrirano kopijo');
      controller.replace(
        CollaborationState(session: sharingSession(), sessionInvalid: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shrani datoteko kopije'), findsNothing);
      expect(io.saves, 0);
    },
  );
  testWidgets(
    'unavailable secure account storage does not block a personal encrypted export',
    (tester) async {
      final backup = FakeBackupController();
      await pumpBackup(
        tester,
        backup,
        FakeBackupIo(),
        const BackupWizard(restore: false),
        collaboration: UnavailableSecureStorageController(),
      );
      await password(tester);
      await click(tester, 'Pripravi šifrirano kopijo');
      expect(backup.exports, 1);
      expect(
        find.textContaining('https://source.example.test'),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
    },
  );
}
