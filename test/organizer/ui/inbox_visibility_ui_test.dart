import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/inbox_projection.dart';
import 'package:kanban/organizer/data/finance_inbox_store.dart';
import 'package:kanban/organizer/state/finance_inbox_provider.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/inbox/inbox_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/inbox_projection_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/reminder_snooze_provider.dart';
import 'sharing_ui_fixture.dart';

final now = DateTime.utc(2026, 10, 9, 12);
SharedInboxEntry entry({
  int id = 1,
  bool read = false,
  String kind = 'reminder.due',
  String type = 'task',
}) => SharedInboxEntry(
  id: id,
  scopeId: sharingScopeId,
  kind: kind,
  category: kind == 'reminder.due' ? 'reminders' : 'tasks',
  audience: InboxAudience.personal,
  targetType: type,
  targetId: 'task',
  groupKey: 'delivered-$id',
  createdAt: now.subtract(Duration(minutes: id)),
  readAt: read ? now : null,
);
SharedScheduledReminder schedule(String state) => SharedScheduledReminder(
  id: 'alarm',
  scopeId: sharingScopeId,
  targetType: 'task',
  targetId: 'task',
  remindAt: state == 'pending'
      ? now.add(const Duration(hours: 2))
      : now.subtract(const Duration(hours: 2)),
  revision: 1,
  state: state,
);
CollaborationState shared({
  Iterable<SharedInboxEntry>? inbox,
  String? reminderState = 'delivered',
  bool completed = false,
  bool missing = false,
  bool invalid = false,
  bool revoked = false,
  bool blocked = false,
  bool archived = false,
  bool disabled = false,
  bool signedIn = true,
  String? selected,
}) => CollaborationState(
  session: signedIn ? sharingSession() : null,
  sessionInvalid: invalid,
  selectedSpaceId: selected,
  inboxSupported: true,
  scopes: [
    SharedScope(
      id: sharingScopeId,
      name: 'Pravi dom',
      kind: SharedScopeKind.household,
      role: SharedRole.owner,
      revoked: revoked,
      blocked: blocked,
      archived: archived,
    ),
  ],
  data: {
    sharingScopeId: SharedScopeData(
      tasks: missing
          ? []
          : sharingData().tasks.map((t) => t.copyWith(isCompleted: completed)),
    ),
  },
  inbox: inbox ?? [entry()],
  scheduledReminders: reminderState == null ? [] : [schedule(reminderState)],
  notificationPreferences: disabled
      ? {
          sharingScopeId: SharedNotificationPreferences(
            scopeId: sharingScopeId,
            categories: {
              'reminders': const SharedNotificationSettings(inApp: false),
            },
          ),
        }
      : {},
);
OrganizerInboxProjection project(
  CollaborationState state, {
  List<ReminderPlan>? plans = const [],
}) => projectOrganizerInbox(
  personal: OrganizerSnapshot(),
  shared: state,
  effectivePlans: plans,
  now: now,
);
ReminderPlan alarm({bool future = false}) => ReminderPlan(
  stableKey: 'local-auto',
  scheduledAt: future
      ? now.add(const Duration(hours: 1))
      : now.subtract(const Duration(hours: 1)),
  target: NotificationTarget(
    serverUrl: sharingSession().serverUrl,
    serverId: sharingSession().serverId,
    accountId: sharingSession().accountId,
    scopeId: sharingScopeId,
    records: const [NotificationRecordTarget(type: 'task', recordId: 'task')],
  ),
  reason: 'task_due',
);

class EmptyPersonal extends OrganizerController {
  void refreshWith(OrganizerSnapshot previous) =>
      state = const AsyncLoading<OrganizerSnapshot>().copyWithPrevious(
        AsyncData(previous),
      );
  @override
  Future<OrganizerSnapshot> build() async => OrganizerSnapshot();
}

class InboxController extends SharingUiController {
  InboxController() : super(initial: shared());
  List<int> readIds = [];
  void beginSwitch() => state = const AsyncLoading<CollaborationState>()
      .copyWithPrevious(AsyncData(shared()));
  void failSwitch() => state = AsyncError<CollaborationState>(
    const CollaborationException('network'),
    StackTrace.current,
  ).copyWithPrevious(AsyncData(shared()));
  @override
  Future<void> markInboxRead(Iterable<int> ids, {bool read = true}) async {
    readIds = ids.toList();
    replace(shared(inbox: [entry(read: read)]));
  }
}

class DeferredReadStore implements FinanceInboxStore {
  final pending = <String, Completer<Set<String>>>{};
  final started = <String, Completer<void>>{};
  @override
  Future<Set<String>> readKeys(Iterable<ReminderPlan> plans) {
    final key = plans.single.stableKey;
    started[key]!.complete();
    return pending[key]!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('delivered server reminder needs no automatic local plan', () {
    final inbox = project(shared());
    expect(inbox.shared, hasLength(1));
    expect(inbox.shared.single.plan, isNull);
    expect(inbox.hasUnread({}), isTrue);
    expect(project(shared(), plans: null).shared, hasLength(1));
    expect(project(shared(reminderState: null)).shared, hasLength(1));
    expect(project(shared(inbox: [entry(read: true)])).hasUnread({}), isFalse);
  });
  test('account-wide inbox is independent of selected workspace', () {
    expect(
      project(shared(selected: 'unrelated-workspace')).hasUnread({}),
      isTrue,
    );
    expect(project(shared(selected: 'local')).shared, hasLength(1));
  });
  test(
    'known cancelled, future, completed, or deleted alarms are ineligible',
    () {
      for (final state in [
        shared(reminderState: 'cancelled'),
        shared(reminderState: 'pending'),
        shared(completed: true),
        shared(missing: true),
      ]) {
        expect(project(state).shared, isEmpty);
        expect(project(state).hasUnread({}), isFalse);
      }
      // A normal historical change remains useful after completing its target.
      expect(
        project(
          shared(completed: true, inbox: [entry(kind: 'task.created')]),
        ).shared,
        hasLength(1),
      );
    },
  );
  test(
    'snoozed automatic alarm hides old inbox event until its effective time',
    () {
      expect(
        project(
          shared(reminderState: null),
          plans: [alarm(future: true)],
        ).hasUnread({}),
        isFalse,
      );
      expect(
        project(shared(reminderState: null), plans: [alarm()]).hasUnread({}),
        isTrue,
      );
    },
  );
  test(
    'revoked blocked archived invalid session and disabled category cannot leave badge',
    () {
      for (final state in [
        shared(revoked: true),
        shared(blocked: true),
        shared(archived: true),
        shared(invalid: true),
        shared(signedIn: false),
        shared(disabled: true),
      ]) {
        expect(project(state).shared, isEmpty);
        expect(project(state).hasUnread({}), isFalse);
      }
    },
  );
  test(
    'same target is one card with every captured read id and unread state',
    () {
      final inbox = project(
        shared(inbox: [entry(id: 2), entry(id: 1, read: true)]),
      );
      expect(inbox.shared, hasLength(1));
      expect(inbox.shared.single.group.ids, [1, 2]);
      expect(inbox.hasUnread({}), isTrue);
      expect(
        project(
          shared(inbox: [entry(id: 2, read: true), entry(id: 1, read: true)]),
        ).hasUnread({}),
        isFalse,
      );
    },
  );
  test(
    'financial inbox rejects missing permission even for non-entry target types',
    () {
      final state = shared(
        inbox: [entry(kind: 'finance.updated', type: 'financeTransfer')],
      );
      expect(project(state).shared, isEmpty);
      expect(project(state).hasUnread({}), isFalse);
    },
  );
  test(
    'local stale due history does not set badge and current snooze is respected',
    () {
      final task = sharingData().tasks.single.copyWith(
        dueAt: now.subtract(const Duration(hours: 1)),
      );
      final reminder = LocalReminder(
        id: 'reminder',
        taskId: task.id,
        dueAt: task.dueAt!,
        createdAt: now,
        isRead: false,
      );
      ReminderPlan localAlarm(DateTime at) => ReminderPlan(
        stableKey: 'personal:task:task:due',
        scheduledAt: at,
        target: NotificationTarget(
          records: const [
            NotificationRecordTarget(type: 'task', recordId: 'task'),
          ],
        ),
        reason: 'task_due',
      );
      OrganizerInboxProjection local(OrganizerSnapshot personal, DateTime at) =>
          projectOrganizerInbox(
            personal: personal,
            shared: CollaborationState(),
            effectivePlans: [localAlarm(at)],
            now: now,
          );
      final personal = OrganizerSnapshot(tasks: [task], reminders: [reminder]);
      expect(local(personal, task.dueAt!).hasUnread({}), isTrue);
      expect(
        local(personal, now.add(const Duration(hours: 1))).hasUnread({}),
        isFalse,
      );
      expect(
        local(
          personal.copyWith(
            tasks: [
              task.copyWith(dueAt: now.subtract(const Duration(hours: 2))),
            ],
          ),
          now,
        ).hasUnread({}),
        isFalse,
      );
    },
  );
  test(
    'private mapped local and remote mirrors form one card with combined read state',
    () {
      final session = sharingSession();
      final due = now.subtract(const Duration(hours: 1));
      final localTask = LocalTask.fromJson({
        ...sharingData().tasks.single.copyWith(dueAt: due).toJson(),
        'id': 'local-task',
      });
      final remoteTask = LocalTask.fromJson({
        ...localTask.toJson(),
        'id': 'task',
      });
      final reminder = LocalReminder(
        id: 'alarm',
        taskId: localTask.id,
        dueAt: due,
        createdAt: due,
        isRead: true,
      );
      final state = CollaborationState(
        session: session,
        scopes: [
          SharedScope(
            id: sharingScopeId,
            name: 'Zasebni',
            kind: SharedScopeKind.personal,
            role: SharedRole.owner,
          ),
        ],
        privateSync: const PrivateSyncState(
          enabled: true,
          scopeId: sharingScopeId,
        ),
        privateRecordIds: const {'task': 'local-task'},
        data: {
          sharingScopeId: SharedScopeData(tasks: [remoteTask]),
        },
        inbox: [entry()],
      );
      final inbox = projectOrganizerInbox(
        personal: OrganizerSnapshot(
          workspaceKey: 'private:${session.partition}',
          tasks: [localTask],
          reminders: [reminder],
        ),
        shared: state,
        effectivePlans: [alarm()],
        now: now,
      );
      expect(inbox.local, hasLength(1));
      expect(inbox.shared, isEmpty);
      expect(inbox.local.single.remoteEntries.single.id, 1);
      expect(inbox.local.single.isRead, isFalse);
      expect(inbox.hasUnread({}), isTrue);
    },
  );
  test(
    'loading/error with retained old account never retains inbox eligibility',
    () async {
      final controller = InboxController();
      final container = ProviderContainer(
        overrides: [
          organizerProvider.overrideWith(EmptyPersonal.new),
          collaborationProvider.overrideWith(() => controller),
          effectiveReminderPlansProvider.overrideWith((ref) async => []),
          organizerClockProvider.overrideWithValue(() => now),
          organizerReminderSchedulerProvider.overrideWithValue((_) => () {}),
        ],
      );
      addTearDown(container.dispose);
      await container.read(organizerProvider.future);
      await container.read(collaborationProvider.future);
      expect(container.read(organizerInboxHasUnreadProvider), isTrue);
      controller.beginSwitch();
      expect(
        container.read(collaborationProvider).valueOrNull?.inbox,
        isNotEmpty,
      );
      expect(container.read(organizerInboxProjectionProvider).shared, isEmpty);
      expect(container.read(organizerInboxHasUnreadProvider), isFalse);
      controller.failSwitch();
      expect(container.read(organizerInboxProjectionProvider).shared, isEmpty);
      expect(container.read(organizerInboxHasUnreadProvider), isFalse);
    },
  );
  test(
    'personal refresh carrying AsyncData cannot reuse previous inbox rows',
    () async {
      final personal = EmptyPersonal();
      final task = sharingData().tasks.single.copyWith(
        dueAt: now.subtract(const Duration(hours: 1)),
      );
      final previous = OrganizerSnapshot(
        tasks: [task],
        reminders: [
          LocalReminder(
            id: 'alarm',
            taskId: task.id,
            dueAt: task.dueAt!,
            createdAt: now,
            isRead: false,
          ),
        ],
      );
      final plan = ReminderPlan(
        stableKey: 'local:task',
        scheduledAt: task.dueAt!,
        target: NotificationTarget(
          records: [NotificationRecordTarget(type: 'task', recordId: task.id)],
        ),
        reason: 'task_due',
      );
      final container = ProviderContainer(
        overrides: [
          organizerProvider.overrideWith(() => personal),
          collaborationProvider.overrideWith(
            () => SharingUiController(initial: CollaborationState()),
          ),
          effectiveReminderPlansProvider.overrideWith((ref) async => [plan]),
          organizerClockProvider.overrideWithValue(() => now),
          organizerReminderSchedulerProvider.overrideWithValue((_) => () {}),
        ],
      );
      addTearDown(container.dispose);
      await container.read(organizerProvider.future);
      await container.read(collaborationProvider.future);
      await container.read(effectiveReminderPlansProvider.future);
      personal.refreshWith(previous);
      expect(container.read(organizerProvider).isLoading, isTrue);
      expect(
        container.read(organizerProvider).asData,
        isNotNull,
      ); // Riverpod refresh retains AsyncData
      expect(container.read(organizerInboxProjectionProvider).local, isEmpty);
      expect(container.read(organizerInboxHasUnreadProvider), isFalse);
    },
  );
  test(
    'finance receipt refresh carrying old AsyncData is unknown until its own read finishes',
    () async {
      var gate = Completer<Set<String>>()..complete({});
      final plan = ReminderPlan(
        stableKey: 'key',
        scheduledAt: now,
        target: NotificationTarget(records: const []),
        reason: 'salary_check',
      );
      final container = ProviderContainer(
        overrides: [
          organizerInboxProjectionProvider.overrideWith(
            (ref) => OrganizerInboxProjection(finance: [plan]),
          ),
          financeInboxReadKeysProvider.overrideWith((ref) => gate.future),
        ],
      );
      addTearDown(container.dispose);
      container.listen(organizerInboxHasUnreadProvider, (_, _) {});
      await container.read(financeInboxReadKeysProvider.future);
      expect(container.read(organizerInboxHasUnreadProvider), isTrue);
      gate = Completer<Set<String>>();
      container.invalidate(financeInboxReadKeysProvider);
      final refreshing = container.read(financeInboxReadKeysProvider);
      expect(refreshing.isLoading, isTrue);
      expect(
        refreshing.asData,
        isNotNull,
      ); // asData alone does not mean a fresh receipt
      expect(container.read(organizerInboxHasUnreadProvider), isFalse);
      gate.complete({'key'});
      await container.read(financeInboxReadKeysProvider.future);
      expect(container.read(organizerInboxHasUnreadProvider), isFalse);
    },
  );
  test(
    'late finance read receipt from previous partition cannot alter new badge',
    () async {
      final controller = InboxController();
      final store = DeferredReadStore();
      final first = sharingSession().partition;
      final second = sharingSession(second: true).partition;
      for (final key in [first, second]) {
        store.pending[key] = Completer<Set<String>>();
        store.started[key] = Completer<void>();
      }
      final container = ProviderContainer(
        overrides: [
          collaborationProvider.overrideWith(() => controller),
          financeInboxStoreProvider.overrideWith((ref) async => store),
          organizerInboxProjectionProvider.overrideWith((ref) {
            final session = ref
                .watch(collaborationProvider)
                .asData
                ?.value
                .session;
            return OrganizerInboxProjection(
              finance: session == null
                  ? []
                  : [
                      ReminderPlan(
                        stableKey: session.partition,
                        scheduledAt: now,
                        target: NotificationTarget(records: const []),
                        reason: 'salary_check',
                      ),
                    ],
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(collaborationProvider.future);
      container.listen(organizerInboxHasUnreadProvider, (_, _) {});
      await store.started[first]!.future;
      expect(
        container.read(organizerInboxHasUnreadProvider),
        isFalse,
      ); // receipt unknown
      controller.switchAccount();
      container.read(organizerInboxHasUnreadProvider);
      await store.started[second]!.future;
      expect(container.read(financeInboxReadKeysProvider).asData, isNull);
      store.pending[second]!.complete({});
      await container.read(financeInboxReadKeysProvider.future);
      expect(container.read(organizerInboxHasUnreadProvider), isTrue);
      store.pending[first]!.complete({
        second,
      }); // stale reply would falsely pre-read second
      await Future<void>.delayed(Duration.zero);
      expect(container.read(organizerInboxHasUnreadProvider), isTrue);
      expect(
        container.read(financeInboxReadKeysProvider).asData!.value,
        isEmpty,
      );
    },
  );
  testWidgets(
    'empty-All screenshot regression: delivered server event is visible and reading clears common badge provider',
    (tester) async {
      final controller = InboxController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            organizerProvider.overrideWith(EmptyPersonal.new),
            collaborationProvider.overrideWith(() => controller),
            effectiveReminderPlansProvider.overrideWith((ref) async => []),
            organizerClockProvider.overrideWithValue(() => now),
            organizerReminderSchedulerProvider.overrideWithValue((_) => () {}),
          ],
          child: MaterialApp(
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: OrganizerInboxPage(onSettings: () {}, onAccount: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrganizerInboxPage)),
      );
      expect(find.text('Vsa'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(container.read(organizerInboxHasUnreadProvider), isTrue);
      // No invalid null-plan snooze action is exposed for a server-only alarm.
      expect(find.byIcon(Icons.snooze_outlined), findsNothing);
      await tester.tap(find.byTooltip('Označi kot prebrano'));
      await tester.pumpAndSettle();
      expect(controller.readIds, [1]);
      expect(container.read(organizerInboxHasUnreadProvider), isFalse);
      expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
