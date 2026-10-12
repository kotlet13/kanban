import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/linked_payments_repository.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/linked_payment_models.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/private_sync_models.dart';
import 'package:kanban/organizer/presentation/backup/backup_content_preview.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;
import 'linked_payments_repository_test.dart' show PaymentTransport;

const _password = 'a strong preview password';

class _Fixture {
  _Fixture(this.db, this.backup, this.bytes, this.preview, this.document);
  final CollaborationDatabase db;
  final PortableBackupRepository backup;
  final Uint8List bytes;
  final BackupPreview preview;
  final Map<String, dynamic> document;

  static Future<_Fixture> create({
    bool withPayment = true,
    bool withRetainedSpace = false,
  }) async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final storage = SqliteOrganizerStorage(db);
    await storage.initialize();
    final personal = OrganizerRepository(storage);
    await personal.initialize();
    addTearDown(personal.close);
    final shared = CollaborationRepository(
      db,
      PaymentTransport(),
      MemorySessionStore(),
      ownsDatabase: false,
    );
    await shared.initialize();
    addTearDown(shared.close);
    await shared.login(
      serverUrl: 'https://example.test',
      username: 'alice',
      password: 'test',
    );
    await shared.enablePrivateSync(
      expectedRevision: (await storage.read()).revision,
    );
    await personal.reload();
    await personal.createTask(title: 'Downloaded private task');
    final now = DateTime.now().toUtc(), privateAccount = newSharedId();
    await personal.saveFinancePlan(
      accounts: [
        LocalFinanceAccount(
          id: privateAccount,
          name: 'Private account',
          currency: 'EUR',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      rules: [],
      expectedRevision: personal.snapshot.revision,
      expectedWorkspaceKey: personal.snapshot.workspaceKey,
    );
    final home = await shared.createScope('Downloaded home');
    await shared.refreshFinancePolicy(home);
    await shared.createTask(scopeId: home, title: 'Downloaded shared task');
    final account = await shared.createFinanceAccount(
      scopeId: home,
      name: 'Home account',
      currency: 'EUR',
    );
    final second = await shared.createFinanceAccount(
      scopeId: home,
      name: 'Home second account',
      currency: 'EUR',
    );
    await shared.createFinanceEntry(
      scopeId: home,
      accountId: account,
      kind: FinanceEntryKind.expense,
      amountMinor: 1200,
      currency: 'EUR',
      title: 'Shared expense',
      occurredAt: now,
    );
    await shared.createFinanceTransfer(
      scopeId: home,
      fromAccountId: account,
      toAccountId: second,
      amountMinor: 250,
      currency: 'EUR',
      title: 'Transfer',
      occurredAt: now,
    );
    await shared.syncNow();
    final spaces = LocalSpacesRepository(db);
    final localHome = await spaces.createSpace(
      kind: LocalSpaceKind.household,
      name: 'Local home',
    );
    final local = OrganizerRepository(
      SqliteOrganizerStorage(db, workspaceId: localHome.id),
    );
    await local.initialize();
    addTearDown(local.close);
    await local.createTask(title: 'Local home task');
    await local.createFinanceEntry(
      title: 'Local home expense',
      amountMinor: 750,
      kind: FinanceEntryKind.expense,
      occurredAt: now,
    );
    final gardens = GardenRepository(GardenStorage(db));
    await gardens.initialize();
    final garden = await gardens.createGarden(name: 'Local home garden');
    await spaces.assignGardenToHousehold(
      garden,
      localHome.id,
      expectedRevision: 0,
    );
    await gardens.close();
    if (withRetainedSpace) {
      final original = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Published local home',
      );
      final source = OrganizerRepository(
        SqliteOrganizerStorage(db, workspaceId: original.id),
      );
      await source.initialize();
      await source.createTask(title: 'One published task');
      await source.close();
      await shared.publishLocalSpaces(
        await shared.previewLocalSpacesPublication([original.id]),
      );
    }
    if (withPayment) {
      final org = await spaces.createSpace(
        kind: LocalSpaceKind.organization,
        name: 'Local organization',
      );
      final source = OrganizerRepository(
        SqliteOrganizerStorage(db, workspaceId: org.id),
      );
      await source.initialize();
      await source.createFinanceEntry(
        title: 'One canonical source expense',
        amountMinor: 3000,
        kind: FinanceEntryKind.expense,
        occurredAt: now,
      );
      final entry = source.snapshot.financeEntries.single;
      await source.close();
      await LinkedPaymentsRepository(
        db,
        collaboration: shared,
      ).recordPersonalPayment(
        PaymentSourceRef(
          space: PaymentSpaceRef(org.id),
          entryId: entry.id,
          expectedRevision: entry.revision,
        ),
        personal: const PaymentSpaceRef('local'),
        personalAccountId: privateAccount,
        household: PaymentSpaceRef(localHome.id),
        paidAt: now,
        expectReimbursement: true,
      );
    }
    final backup = PortableBackupRepository(
      db,
      storage,
      MemoryBackupUiPreferencesStore(),
      collaboration: () => shared,
    );
    final bytes = await backup.exportEncryptedBackup(_password);
    final document = await PortableBackupCrypto().decrypt(bytes, _password);
    return _Fixture(
      db,
      backup,
      bytes,
      await backup.inspectEncryptedBackup(bytes, _password),
      document,
    );
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'real encrypted copy counts local and downloaded content when personal is empty',
    () async {
      final f = await _Fixture.create();
      final p = f.preview, s = p.contentSummary!;
      expect(p.personalCounts.values, everyElement(0));
      expect(p.scopeCount, 2);
      expect(s.personalScopeCount, 1);
      expect(s.downloadedCounts['task'], 2);
      expect(s.downloadedCounts['personalFinanceAccount'], 1);
      expect(s.downloadedCounts['financeAccount'], 2);
      expect(s.downloadedCounts['financeEntry'], 1);
      expect(s.downloadedCounts['financeTransfer'], 1);
      expect(s.localSpaceCount, 2);
      expect(s.localCounts['tasks'], 1);
      expect(s.localCounts['financeEntries'], 2);
      expect(s.localCounts['gardens'], 1);
      expect(s.linkedPaymentCounts, {
        'events': 1,
        'projections': 2,
        'cashMovements': 0,
      });
      expect(s.linkedPendingCount, 1);
      expect(p.pendingCount, 1);
      expect(s.standaloneFinanceLimited, true);
      // UI counters come from the expanded authenticated content5 document.
      // They describe this
      // exact authenticated document, not from the currently selected workspace.
      expect(f.document['version'], 5);
      expect(f.document['databaseVersion'], 9);
      expect(f.document.keys.toSet(), {
        'format',
        'version',
        'databaseVersion',
        'linkedPayments',
        'localSpaces',
        'gardenSpaceLinks',
        'operationPairs',
        'financeInboxReads',
        'gardens',
        'ideas',
        'ideaSpaceLinks',
        'ideaAssets',
        'ideaDrafts',
        'ideaOperationHistory',
        'id',
        'createdAt',
        'source',
        'privateData',
        'personal',
        'tables',
        'uiPreferences',
        'completeness',
        'exclusions',
      });
      expect((f.document['privateData'] as Map)['maps'], isNotEmpty);
      // Private mapping metadata must not be counted as extra task/account copies.
      expect(
        s.downloadedCounts.values.fold<int>(0, (a, b) => a + b),
        ((f.document['tables'] as Map)['records'] as List).length +
            ((f.document['tables'] as Map)['finance_records'] as List).length,
      );
      expect(await f.db.rows('SELECT * FROM restored_backups'), isEmpty);
    },
  );

  test(
    'default personal snapshot is not counted again as another local space',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final personal = OrganizerRepository(storage);
      await personal.initialize();
      addTearDown(personal.close);
      await personal.createTask(title: 'One personal task');
      final backup = PortableBackupRepository(
        db,
        storage,
        MemoryBackupUiPreferencesStore(),
      );
      final bytes = await backup.exportEncryptedBackup(_password);
      final p = await backup.inspectEncryptedBackup(bytes, _password);
      expect(p.personalCounts['tasks'], 1);
      expect(p.contentSummary!.localSpaceCount, 0);
      expect(p.contentSummary!.localCounts, isEmpty);
      expect(p.contentSummary!.downloadedCounts, isEmpty);
      expect(p.scopeCount, 0);
      expect(p.hasRemoteRecovery, false);
      expect(p.pendingCount, 0);
      expect(p.contentSummary!.standaloneFinanceLimited, false);
    },
  );
  test(
    'published local originals stay separate from current downloaded content',
    () async {
      final f = await _Fixture.create(
        withPayment: false,
        withRetainedSpace: true,
      );
      final s = f.preview.contentSummary!;
      expect(f.preview.scopeCount, 3);
      expect(s.localSpaceCount, 1);
      expect(s.localCounts['tasks'], 1);
      expect(s.retainedLocalSpaceCount, 1);
      expect(s.retainedLocalCounts['tasks'], 1);
      expect(s.downloadedCounts['task'], 3);
      expect(s.linkedPendingCount, 0);
    },
  );
  test(
    'terminal payment intents are excluded; quarantined work remains counted',
    () async {
      final f = await _Fixture.create();
      final crypto = PortableBackupCrypto();
      final intent =
          ((f.document['linkedPayments'] as Map)['intents'] as List).single
              as Map;
      for (final state in ['complete', 'local_only', 'quarantine']) {
        intent['state'] = state;
        final bytes = await crypto.encrypt(f.document, _password);
        final p = await f.backup.inspectEncryptedBackup(bytes, _password);
        expect(p.pendingCount, state == 'quarantine' ? 1 : 0);
        expect(p.contentSummary!.blockedCount, state == 'quarantine' ? 1 : 0);
      }
    },
  );

  for (final (width, language) in [(390.0, 'sl'), (1280.0, 'en')]) {
    testWidgets(
      'real decoded preview shows personal zero and shared content $width $language',
      (tester) async {
        final f = (await tester.runAsync(_Fixture.create))!;
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: BackupContentPreview(preview: f.preview),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final personal = find.byKey(const ValueKey('backup-personal-content'));
        expect(
          find.descendant(
            of: personal,
            matching: find.text(language == 'sl' ? 'Zapisi: 0' : 'Records: 0'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('backup-local-content')),
          findsOneWidget,
        );
        final downloaded = find.byKey(
          const ValueKey('backup-downloaded-content'),
        );
        expect(downloaded, findsOneWidget);
        expect(
          find.descendant(of: downloaded, matching: find.text('2')),
          findsNWidgets(2),
        );
        expect(
          find.text(
            language == 'sl'
                ? 'Zasebni osebni prostori: 1'
                : 'Private personal spaces: 1',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            language == 'sl' ? 'Skupni prostori: 1' : 'Shared spaces: 1',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            language == 'sl'
                ? 'Neusklajene operacije v kopiji: 1'
                : 'Unsent operations in backup: 1',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('backup-payment-content')),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            language == 'sl'
                ? 'Pri samostojnem nadaljevanju'
                : 'When continuing locally',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
      },
    );
  }
}
