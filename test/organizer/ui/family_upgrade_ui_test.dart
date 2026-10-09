import 'package:kanban/organizer/state/portable_backup_provider.dart';
import 'backup_ui_fixture.dart';
import 'package:kanban/organizer/platform/backup_preferences_replay.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/app.dart';
import 'package:kanban/app_router.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/platform/notification_providers.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_ledger.dart';
import 'package:kanban/organizer/presentation/inbox/notification_target_view.dart';
import 'organizer_ui_test.dart' as personal;
import 'sharing_ui_test.dart' as sharing;
import 'sharing_ui_fixture.dart';
import '../platform/local_notification_adapter_test.dart' as fake;

final firstId = sharingSession().accountId;
List<SharedMember> upgradeMembers() => [
  SharedMember(
    accountId: firstId,
    userId: 1,
    username: 'first',
    displayName: 'Prva oseba',
    role: SharedRole.owner,
    active: true,
  ),
  SharedMember(
    accountId: sharingSession(second: true).accountId,
    userId: 2,
    username: 'second',
    displayName: 'Druga oseba',
    role: SharedRole.member,
    active: true,
  ),
];
SharedScopeData upgradeData() => SharedScopeData(
  tasks: [
    for (var i = 1; i <= 4; i++)
      LocalTask(
        id: 'task$i',
        title: 'Zajeto opravilo $i',
        notes: '',
        projectId: null,
        isCompleted: false,
        createdAt: sharingTestNow,
        updatedAt: sharingTestNow,
        dueAt: DateTime.now().add(const Duration(hours: 1)),
        startAt: DateTime.now(),
        assigneeAccountIds: i == 1 ? [firstId] : [],
        createdByAccountId: firstId,
      ),
  ],
  financeAccounts: [
    SharedFinanceAccount(
      id: 'account1',
      name: 'Skupni račun',
      currency: 'EUR',
      openingBalanceMinor: 10000,
      createdAt: sharingTestNow,
      updatedAt: sharingTestNow,
    ),
    SharedFinanceAccount(
      id: 'account2',
      name: 'Račun člana',
      ownerAccountId: firstId,
      currency: 'EUR',
      createdAt: sharingTestNow,
      updatedAt: sharingTestNow,
    ),
  ],
  financeEntries: [
    SharedFinanceEntry(
      id: 'entry',
      accountId: 'account1',
      kind: FinanceEntryKind.expense,
      amountMinor: 1234,
      currency: 'EUR',
      title: 'Plačilo za skupni dom',
      payerAccountId: firstId,
      recipientAccountId: sharingSession(second: true).accountId,
      createdByAccountId: firstId,
      occurredAt: sharingTestNow,
      createdAt: sharingTestNow,
      updatedAt: sharingTestNow,
    ),
  ],
  financeTransfers: [
    SharedFinanceTransfer(
      id: 'transfer',
      fromAccountId: 'account1',
      toAccountId: 'account2',
      amountMinor: 2000,
      currency: 'EUR',
      title: 'Interni prenos',
      occurredAt: sharingTestNow,
      createdAt: sharingTestNow,
      updatedAt: sharingTestNow,
    ),
  ],
);
CollaborationState upgradeState({
  SharedFinanceGrant grant = SharedFinanceGrant.write,
  int revision = 1,
  bool complete = true,
  bool revoked = false,
  SharedRole role = SharedRole.owner,
  String? selectedSpaceId,
}) => CollaborationState(
  session: sharingSession(),
  selectedSpaceId: selectedSpaceId,
  scopes: [sharingScope(role: role, revoked: revoked)],
  data: {sharingScopeId: upgradeData()},
  members: {sharingScopeId: upgradeMembers()},
  financeSupported: true,
  inboxSupported: true,
  financeSnapshotComplete: {sharingScopeId: complete},
  financePolicies: {
    sharingScopeId: SharedFinancePolicy(
      enabled: true,
      grant: grant,
      revision: revision,
    ),
  },
  inbox: [
    for (var i = 1; i <= 3; i++)
      SharedInboxEntry(
        id: i,
        revision: 1,
        scopeId: sharingScopeId,
        kind: 'task.assigned',
        category: 'tasks',
        audience: InboxAudience.personal,
        targetType: 'task',
        targetId: 'task$i',
        groupKey: 'exact3',
        createdAt: sharingTestNow,
      ),
  ],
);

class UpgradeController extends SharingUiController {
  UpgradeController({CollaborationState? initial})
    : super(initial: initial ?? upgradeState());
  LocalTask? savedTask;
  SharedNotificationSettings? savedSettings;
  String? savedCategory, savedScope;
  @override
  Future<void> updateTask(String scopeId, LocalTask draft) async {
    savedTask = draft;
  }

  @override
  Future<void> setNotificationPreferences({
    required String scopeId,
    required String category,
    required SharedNotificationSettings settings,
  }) async {
    savedScope = scopeId;
    savedCategory = category;
    savedSettings = settings;
  }

  final opened = <NotificationTarget>[];
  final readIds = <int>[];
  final auditGate = Completer<List<SharedFinanceAuditEntry>>();
  final grants = <String, SharedFinanceGrant>{};
  int grantLoads = 0;
  @override
  Future<NotificationOpenResult> openNotificationTarget(
    NotificationTarget target,
  ) async {
    opened.add(target);
    return NotificationOpenResult(
      status:
          target.isPersonal ||
              (state.value?.session != null &&
                  target.matches(state.value!.session!))
          ? NotificationOpenStatus.available
          : NotificationOpenStatus.wrongAccount,
      target: target,
    );
  }

  @override
  Future<void> markInboxRead(Iterable<int> ids, {bool read = true}) async {
    readIds.addAll(ids);
  }

  @override
  Future<List<SharedFinanceAuditEntry>> financeAudit({
    required String scopeId,
    required String recordId,
    int? beforeRevision,
    int limit = 50,
  }) => auditGate.future;
  @override
  Future<List<SharedMember>> members(String scopeId) async => upgradeMembers();
  @override
  Future<Map<String, SharedFinanceGrant>> financeGrants(String scopeId) async {
    grantLoads++;
    return Map.of(grants);
  }

  @override
  Future<void> grantFinance({
    required String scopeId,
    required String accountId,
    required SharedFinanceGrant grant,
  }) async {
    grants[accountId] = grant;
  }
}

Future<void> openFinances(
  WidgetTester tester,
  double width,
  String locale,
) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(KanbanApp)),
  );
  await container
      .read(collaborationProvider.notifier)
      .selectSpace(sharingScopeId);
  await tester.pumpAndSettle();
  if (width < 900) {
    await personal.mobileTab(tester, locale == 'sl' ? 'Več' : 'More');
  }
  final target = find.widgetWithText(
    ListTile,
    locale == 'sl' ? 'Finance' : 'Finances',
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

class DelayedUpgrade extends UpgradeController {
  DelayedUpgrade(this.gate);
  final Completer<void> gate;
  @override
  Future<CollaborationState> build() async {
    await gate.future;
    return initial;
  }
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final locale in ['sl', 'en']) {
      for (final theme in ['light', 'dark']) {
        testWidgets(
          'shared finance ledger + entry editor $width $locale $theme',
          (tester) async {
            final controller = UpgradeController();
            await sharing.pumpSharing(
              tester,
              controller,
              width: width,
              locale: locale,
              theme: theme,
            );
            await openFinances(tester, width, locale);
            expect(find.byType(SharedFinanceLedger), findsOneWidget);
            expect(find.text('Skupni račun'), findsWidgets);
            expect(
              find.textContaining('87.66 EUR'),
              findsWidgets,
            ); // transfer does not change total holdings
            expect(tester.takeException(), isNull);
            final add = find.widgetWithText(
              FilledButton,
              locale == 'sl' ? 'Dodaj zapis' : 'Add entry',
            );
            // Heading action uses FilledButton.icon.
            final actual = add.evaluate().isNotEmpty
                ? add
                : find.text(locale == 'sl' ? 'Dodaj zapis' : 'Add entry');
            await tester.ensureVisible(actual.first);
            await tester.tap(actual.first);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('sharing-payer')), findsOneWidget);
            expect(
              find.byKey(const ValueKey('sharing-recipient')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(
              find.text(locale == 'sl' ? 'Prekliči' : 'Cancel').last,
            );
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
  testWidgets(
    'finance read-only and incomplete backfill never show edit or false balance',
    (tester) async {
      final controller = UpgradeController(
        initial: upgradeState(
          grant: SharedFinanceGrant.read,
          role: SharedRole.viewer,
        ),
      );
      await sharing.pumpSharing(tester, controller);
      await openFinances(tester, 390, 'sl');
      expect(find.text('Dodaj zapis'), findsNothing);
      controller.replace(
        upgradeState(
          grant: SharedFinanceGrant.read,
          complete: false,
          role: SharedRole.viewer,
          selectedSpaceId: sharingScopeId,
        ),
      );
      await tester.pump();
      expect(find.byType(SharedFinanceLedger), findsNothing);
      expect(
        find.text('Pripravljamo celoten finančni pregled.'),
        findsOneWidget,
      );
      expect(find.textContaining('87.66 EUR'), findsNothing);
    },
  );
  testWidgets(
    'finance revoke closes pending audit before late financial result',
    (tester) async {
      final controller = UpgradeController();
      await sharing.pumpSharing(tester, controller);
      await openFinances(tester, 390, 'sl');
      final audit = find.byTooltip('Sled sprememb').first;
      await tester.ensureVisible(audit);
      await tester.tap(audit);
      await tester.pump();
      controller.replace(
        upgradeState(grant: SharedFinanceGrant.none, revision: 2),
      );
      await tester.pumpAndSettle();
      controller.auditGate.complete([
        SharedFinanceAuditEntry(
          scopeId: sharingScopeId,
          recordId: 'account1',
          revision: 2,
          actorAccountId: firstId,
          changedAt: sharingTestNow,
          opId: 'operation',
          before: {'private': 'SECRET LATE FINANCE'},
          after: {},
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('SECRET LATE FINANCE'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SharedFinanceLedger), findsNothing);
    },
  );
  testWidgets(
    'group opens exactly captured three tasks and reading does not complete them',
    (tester) async {
      final controller = UpgradeController();
      await sharing.pumpSharing(tester, controller);
      await tester.tap(find.byTooltip('Obvestila').first);
      await tester.pumpAndSettle();
      final group = find.textContaining('3 opravila');
      await tester.tap(group.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.opened.single.records.map((r) => r.recordId).toSet(), {
        'task1',
        'task2',
        'task3',
      });
      expect(find.text('Zajeto opravilo 4'), findsNothing);
      expect(find.byType(NotificationTargetContent), findsOneWidget);
      expect(
        controller.initial
            .dataForScope(sharingScopeId)
            .tasks
            .every((t) => !t.isCompleted),
        isTrue,
      );
    },
  );
  testWidgets(
    'cold launch queued before shell mount waits for SQLite identity then opens once',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'app_locale_code': 'sl',
        'app_theme_mode': 'light',
      });
      appRouter.go('/');
      final gate = Completer<void>(), controller = DelayedUpgrade(gate);
      final session = sharingSession();
      final target = NotificationTarget(
        serverUrl: session.serverUrl,
        serverId: session.serverId,
        accountId: session.accountId,
        scopeId: sharingScopeId,
        records: [
          const NotificationRecordTarget(type: 'task', recordId: 'task2'),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            portableBackupProvider.overrideWith(EmptyBackupUiController.new),
            backupPreferencesReplayProvider.overrideWith((ref) async => {}),
            organizerStorageProvider.overrideWithValue(
              () async => personal.MemoryOrganizerStorage(),
            ),
            collaborationProvider.overrideWith(() => controller),
            notificationLaunchTargetProvider.overrideWith((ref) => target),
            localNotificationSchedulerProvider.overrideWithValue(
              fake.FakeScheduler(),
            ),
          ],
          child: const KanbanApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.opened, isEmpty);
      gate.complete();
      await tester.pumpAndSettle();
      expect(controller.opened, hasLength(1));
      expect(
        find.descendant(
          of: find.byType(NotificationTargetContent),
          matching: find.text('Zajeto opravilo 2'),
        ),
        findsOneWidget,
      );
      await tester.pump();
      expect(controller.opened, hasLength(1));
    },
  );
  testWidgets(
    'grant dialog refreshes displayed rights after successful change',
    (tester) async {
      final controller = UpgradeController();
      await sharing.pumpSharing(tester, controller);
      await openFinances(tester, 390, 'sl');
      await tester.tap(find.text('Dostop do financ').first);
      await tester.pumpAndSettle();
      final member = find.widgetWithText(ListTile, 'Druga oseba');
      await tester.tap(
        find.descendant(of: member, matching: find.byType(TextButton)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sharing-grant')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ogled').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shrani').last);
      await tester.pumpAndSettle();
      expect(
        controller.grants[sharingSession(second: true).accountId],
        SharedFinanceGrant.read,
      );
      expect(controller.grantLoads, 2);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Druga oseba'),
          matching: find.text('Ogled'),
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'shared task assignment preserves planned dates and canonical creator',
    (tester) async {
      final controller = UpgradeController();
      await sharing.pumpSharing(tester, controller, width: 320);
      await tester.tap(find.byTooltip('Obvestila').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('3 opravila').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final edit = find.widgetWithText(TextButton, 'Uredi opravilo').first;
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final second = find.byKey(
        ValueKey('task-assignee-${sharingSession(second: true).accountId}'),
      );
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pump();
      expect(find.text('Ustvaril/a: Prva oseba'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.savedTask?.assigneeAccountIds.toSet(), {
        firstId,
        sharingSession(second: true).accountId,
      });
      expect(controller.savedTask?.startAt, isNotNull);
      expect(controller.savedTask?.dueAt, isNotNull);
      expect(controller.savedTask?.createdByAccountId, firstId);
      await tester.tap(find.text('Zapri').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Označi kot prebrano').first);
      await tester.pumpAndSettle();
      expect(controller.readIds.toSet(), {1, 2, 3});
      expect(controller.savedTask?.isCompleted, false);
    },
  );
  testWidgets(
    'inbox preferences persist scope/category and disable unavailable delivery channels',
    (tester) async {
      final controller = UpgradeController();
      await sharing.pumpSharing(tester, controller, width: 320);
      await tester.tap(find.byTooltip('Obvestila').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_outlined).last);
      await tester.pumpAndSettle();
      final tasks = find.widgetWithText(ExpansionTile, 'Opravila in načrti');
      await tester.ensureVisible(tasks);
      await tester.tap(tasks);
      await tester.pumpAndSettle();
      final inApp = find.descendant(
        of: tasks,
        matching: find.widgetWithText(SwitchListTile, 'V centru obvestil'),
      );
      await tester.ensureVisible(inApp);
      await tester.tap(inApp);
      await tester.pumpAndSettle();
      expect(controller.savedScope, sharingScopeId);
      expect(controller.savedCategory, 'tasks');
      expect(controller.savedSettings?.inApp, false);
      expect(
        tester
            .widget<SwitchListTile>(
              find.descendant(
                of: tasks,
                matching: find.widgetWithText(
                  SwitchListTile,
                  'Oddaljena sistemska obvestila',
                ),
              ),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.descendant(
                of: tasks,
                matching: find.widgetWithText(SwitchListTile, 'E-pošta'),
              ),
            )
            .onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'personal cold launch opens cached task while shared identity is still loading',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'app_locale_code': 'sl',
        'app_theme_mode': 'light',
      });
      appRouter.go('/');
      final gate = Completer<void>(), controller = DelayedUpgrade(gate);
      final storage = personal.MemoryOrganizerStorage()
        ..snapshot = OrganizerSnapshot(
          tasks: [
            LocalTask(
              id: 'personal-task',
              title: 'Osebni offline target',
              createdByAccountId: firstId,
              notes: '',
              projectId: null,
              dueAt: null,
              isCompleted: false,
              createdAt: sharingTestNow,
              updatedAt: sharingTestNow,
            ),
          ],
        );
      final target = NotificationTarget(
        records: [
          const NotificationRecordTarget(
            type: 'task',
            recordId: 'personal-task',
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            portableBackupProvider.overrideWith(EmptyBackupUiController.new),
            backupPreferencesReplayProvider.overrideWith((ref) async => {}),
            organizerStorageProvider.overrideWithValue(() async => storage),
            collaborationProvider.overrideWith(() => controller),
            notificationLaunchTargetProvider.overrideWith((ref) => target),
            localNotificationSchedulerProvider.overrideWithValue(
              fake.FakeScheduler(),
            ),
          ],
          child: const KanbanApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.opened, hasLength(1));
      expect(find.byType(NotificationTargetContent), findsOneWidget);
      expect(find.text('Osebni offline target'), findsWidgets);
      gate.complete();
      await tester.pumpAndSettle();
      expect(controller.opened, hasLength(1));
    },
  );
  testWidgets(
    'queued shared target resumes after explicit account login without duplicate dialog',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'app_locale_code': 'sl',
        'app_theme_mode': 'light',
      });
      appRouter.go('/');
      final controller = UpgradeController(initial: CollaborationState()),
          session = sharingSession();
      final target = NotificationTarget(
        serverUrl: session.serverUrl,
        serverId: session.serverId,
        accountId: session.accountId,
        scopeId: sharingScopeId,
        records: [
          const NotificationRecordTarget(type: 'task', recordId: 'task2'),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            portableBackupProvider.overrideWith(EmptyBackupUiController.new),
            backupPreferencesReplayProvider.overrideWith((ref) async => {}),
            organizerStorageProvider.overrideWithValue(
              () async => personal.MemoryOrganizerStorage(),
            ),
            collaborationProvider.overrideWith(() => controller),
            notificationLaunchTargetProvider.overrideWith((ref) => target),
            localNotificationSchedulerProvider.overrideWithValue(
              fake.FakeScheduler(),
            ),
          ],
          child: const KanbanApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.opened, hasLength(1));
      await tester.tap(find.text('Odpri račun in deljenje'));
      await tester.pumpAndSettle();
      controller.replace(upgradeState());
      await tester.pumpAndSettle();
      expect(controller.opened, hasLength(2));
      expect(find.byType(NotificationTargetContent), findsOneWidget);
      expect(find.text('Zajeto opravilo 2'), findsWidgets);
    },
  );
}
