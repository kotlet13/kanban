import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/finance_inbox_store.dart';
import 'package:kanban/organizer/domain/inbox_projection.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/inbox/inbox_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/finance_inbox_provider.dart';
import 'package:kanban/organizer/state/inbox_projection_provider.dart';
import 'package:kanban/organizer/state/inbox_read_action_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'sharing_ui_fixture.dart';

final view = StateProvider<OrganizerInboxProjection>(
  (ref) => const OrganizerInboxProjection(),
);
final at = DateTime.utc(2026, 10, 11, 12);
SharedInboxEntry event(
  int id, {
  InboxAudience audience = InboxAudience.scope,
  bool read = false,
}) => SharedInboxEntry(
  id: id,
  revision: 1,
  sequence: id,
  scopeId: sharingScopeId,
  kind: 'task.created',
  category: 'tasks',
  audience: audience,
  actorAccountId: sharingSession().accountId,
  targetType: 'task',
  targetId: 'task',
  targetRevision: 1,
  groupKey: 'group',
  createdAt: at,
  readAt: read ? at : null,
);
SharedInboxReminder group(Iterable<SharedInboxEntry> entries) =>
    SharedInboxReminder(SharedInboxGroup(entries), null);
ReminderPlan plan(String key) => ReminderPlan(
  stableKey: key,
  scheduledAt: at,
  reason: 'salary_check',
  target: NotificationTarget(
    records: const [
      NotificationRecordTarget(type: 'financeEntry', recordId: 'money'),
    ],
  ),
);
LocalInboxReminder local({
  bool read = false,
  List<SharedInboxEntry> mirrors = const [],
}) => LocalInboxReminder(
  LocalReminder(
    id: 'reminder',
    taskId: 'task',
    dueAt: at,
    createdAt: at,
    isRead: read,
  ),
  ReminderPlan(
    stableKey: 'task-reminder',
    scheduledAt: at,
    reason: 'task_due',
    target: NotificationTarget(
      records: const [NotificationRecordTarget(type: 'task', recordId: 'task')],
    ),
  ),
  mirrors,
);

class Personal extends OrganizerController {
  @override
  Future<OrganizerSnapshot> build() async => OrganizerSnapshot();
}

class BulkShared extends SharingUiController {
  final batches = <List<int>>[];
  @override
  Future<void> markVisibleInboxRead(
    Iterable<int> ids, {
    required String expectedPartition,
    required bool Function(int) stillEligible,
  }) async {
    expect(state.requireValue.session!.partition, expectedPartition);
    batches.add(ids.where(stillEligible).toList());
  }
}

class BulkLocal extends LocalSpacesController {
  final ids = <String>[];
  Completer<void>? gate;
  VoidCallback? afterRead;
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState();
  @override
  Future<void> markReminderRead(
    String space,
    String id, {
    required String expectedWorkspaceKey,
    bool Function()? stillVisible,
  }) async {
    await gate?.future;
    if (stillVisible != null && !stillVisible()) {
      throw const CollaborationException('session_changed');
    }
    ids.add(id);
    afterRead?.call();
  }
}

class BulkFinance implements FinanceInboxStore {
  final receipts = <String>{};
  Completer<void>? readGate;
  @override
  Future<Set<String>> readKeys(Iterable<ReminderPlan> plans) async {
    await readGate?.future;
    return {...receipts};
  }

  @override
  Future<void> markRead(
    ReminderPlan plan, {
    required bool Function() stillVisible,
  }) async {
    if (!stillVisible()) throw const CollaborationException('session_changed');
    receipts.add(plan.stableKey);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer container(
  BulkShared shared,
  BulkLocal locals,
  BulkFinance finance,
) {
  final result = ProviderContainer(
    overrides: [
      collaborationProvider.overrideWith(() => shared),
      localSpacesProvider.overrideWith(() => locals),
      financeInboxStoreProvider.overrideWith((ref) async => finance),
      organizerInboxProjectionProvider.overrideWith((ref) => ref.watch(view)),
    ],
  );
  addTearDown(result.dispose);
  return result;
}

Future<void> ready(ProviderContainer c) async {
  await c.read(collaborationProvider.future);
  await c.read(localSpacesProvider.future);
}

Future<void> readAll(ProviderContainer c, OrganizerInboxProjection captured) =>
    c.read(inboxReadActionProvider)(
      captured,
      expectedSession: sharingSession(),
    );

void main() {
  test(
    'bulk receipts cover local, mirrors, shared and finance; IDs deduplicate without 100 limit',
    () async {
      final shared = BulkShared(),
          locals = BulkLocal(),
          finance = BulkFinance();
      final c = container(shared, locals, finance);
      await ready(c);
      final captured = OrganizerInboxProjection(
        local: [
          local(mirrors: [event(1)]),
        ],
        shared: [
          group([
            for (var id = 1; id <= 250; id++) event(id),
            event(251, read: true),
          ]),
        ],
        finance: [plan('salary')],
      );
      c.read(view.notifier).state = captured;
      await readAll(c, captured);
      expect(locals.ids, ['reminder']);
      expect(finance.receipts, {'salary'});
      expect(shared.batches.single.toSet(), {for (var i = 1; i <= 250; i++) i});
      expect(
        shared.state.requireValue
            .dataForScope(sharingScopeId)
            .tasks
            .single
            .isCompleted,
        isFalse,
      );
    },
  );
  test(
    'new arrivals remain unread and no-longer eligible captured entries are skipped',
    () async {
      final shared = BulkShared(),
          locals = BulkLocal(),
          finance = BulkFinance();
      final c = container(shared, locals, finance);
      await ready(c);
      final captured = OrganizerInboxProjection(
        local: [local()],
        shared: [
          group([event(1), event(2)]),
        ],
      );
      c.read(view.notifier).state = captured;
      locals.afterRead = () =>
          c.read(view.notifier).state = OrganizerInboxProjection(
            shared: [
              group([event(1), event(3)]),
            ],
          );
      await readAll(c, captured);
      expect(shared.batches.single, [1]);
      expect(c.read(view).shared.single.group.entries.last.isRead, isFalse);
    },
  );
  test(
    'switch while local operation pending cannot continue to new account or remote batch',
    () async {
      final shared = BulkShared(),
          locals = BulkLocal(),
          finance = BulkFinance();
      final c = container(shared, locals, finance);
      await ready(c);
      final captured = OrganizerInboxProjection(
        local: [local()],
        shared: [
          group([event(1)]),
        ],
      );
      c.read(view.notifier).state = captured;
      locals.gate = Completer<void>();
      final operation = readAll(c, captured);
      final assertion = expectLater(
        operation,
        throwsA(isA<CollaborationException>()),
      );
      shared.switchAccount();
      locals.gate!.complete();
      await assertion;
      expect(locals.ids, isEmpty);
      expect(shared.batches, isEmpty);
    },
  );
  test(
    'switch during financial read lookup rejects later receipt and remote write',
    () async {
      final shared = BulkShared(),
          locals = BulkLocal(),
          finance = BulkFinance();
      final c = container(shared, locals, finance);
      await ready(c);
      final captured = OrganizerInboxProjection(
        finance: [plan('salary')],
        shared: [
          group([event(1)]),
        ],
      );
      c.read(view.notifier).state = captured;
      finance.readGate = Completer<void>();
      final operation = readAll(c, captured);
      final assertion = expectLater(
        operation,
        throwsA(isA<CollaborationException>()),
      );
      await Future<void>.delayed(Duration.zero);
      shared.switchAccount();
      finance.readGate!.complete();
      await assertion;
      expect(finance.receipts, isEmpty);
      expect(shared.batches, isEmpty);
    },
  );
  test(
    'stale rendered callback rejects new account even when inbox IDs collide',
    () async {
      final shared = BulkShared(),
          locals = BulkLocal(),
          finance = BulkFinance();
      final c = container(shared, locals, finance);
      await ready(c);
      final captured = OrganizerInboxProjection(
        shared: [
          group([event(1)]),
        ],
      );
      c.read(view.notifier).state = captured;
      shared.switchAccount();
      await expectLater(
        readAll(c, captured),
        throwsA(isA<CollaborationException>()),
      );
      expect(shared.batches, isEmpty);
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'visible personal filter snapshot and empty disabled action fit $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final captured = <OrganizerInboxProjection>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              organizerProvider.overrideWith(Personal.new),
              collaborationProvider.overrideWith(BulkShared.new),
              organizerInboxProjectionProvider.overrideWith(
                (ref) => ref.watch(view),
              ),
              financeInboxReadKeysProvider.overrideWith(
                (ref) async => <String>{},
              ),
              inboxReadActionProvider.overrideWith(
                (ref) => (visible, {required expectedSession}) async {
                  captured.add(visible);
                },
              ),
            ],
            child: MaterialApp(
              locale: const Locale('sl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: OrganizerInboxPage(
                    onSettings: () {},
                    onAccount: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byKey(const ValueKey('inbox-mark-all-read'));
        expect(tester.widget<TextButton>(button).onPressed, isNull);
        final c = ProviderScope.containerOf(
          tester.element(find.byType(OrganizerInboxPage)),
        );
        c.read(view.notifier).state = OrganizerInboxProjection(
          shared: [
            group([event(1)]),
            group([event(2, audience: InboxAudience.personal)]),
          ],
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zame'));
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(captured.single.shared.single.group.ids, [2]);
        await tester.tap(find.byType(ChoiceChip).at(2));
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(captured[1].shared.single.group.ids, [1]);
        await tester.tap(find.text('Vsa'));
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(captured[2].shared.expand((r) => r.group.ids).toSet(), {1, 2});

        expect(tester.takeException(), isNull);
        c.read(view.notifier).state = OrganizerInboxProjection(
          shared: [
            group([event(2, audience: InboxAudience.personal, read: true)]),
          ],
        );
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(button).onPressed, isNull);
      },
    );
  }
}
