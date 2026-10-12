import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/organizer_actions.dart';
import 'package:kanban/organizer/presentation/planning/utrip_overview.dart';
import 'package:kanban/organizer/presentation/today_page.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'organizer_ui_test.dart' show MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart' show SharingUiController, sharingSession;
import 'all_spaces_ui_test.dart' show AllSpacesController;

final now = DateTime(2026, 10, 12, 12);
LocalEvent event(String id, {int day = 12}) => LocalEvent(
  id: id,
  title: id,
  notes: '',
  startsAt: DateTime(2026, 10, day, 17),
  endsAt: DateTime(2026, 10, day, 18),
  projectId: null,
  createdAt: now,
  updatedAt: now,
);
LocalProject project(String id) => LocalProject(
  id: id,
  title: id,
  description: 'Real project description',
  createdAt: now,
  updatedAt: now,
);
AllSpacesSnapshot projection(OrganizerSnapshot snapshot) => AllSpacesSnapshot([
  AllSpacesSource(
    key: 'local',
    personal: snapshot,
    canReadFinance: true,
    financeComplete: true,
  ),
]);

class _LocalCatalog extends LocalSpacesController {
  _LocalCatalog(this.snapshot);
  final OrganizerSnapshot snapshot;
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    snapshots: {'local': snapshot},
    spaces: [
      const LocalSpace(id: 'local', name: '', kind: LocalSpaceKind.personal),
    ],
  );
}

Future<void> pumpOverview(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
  MemoryOrganizerStorage? storage,
  SharingUiController? shared,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        organizerClockProvider.overrideWithValue(() => now),
        localSpacesProvider.overrideWith(
          () => _LocalCatalog(storage?.snapshot ?? OrganizerSnapshot()),
        ),
        collaborationProvider.overrideWith(
          () => shared ?? SharingUiController(initial: CollaborationState()),
        ),
        if (storage != null)
          organizerStorageProvider.overrideWithValue(() async => storage),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget localOverview() => Consumer(
  builder: (context, ref, _) {
    final data = ref.watch(organizerProvider).valueOrNull;
    if (data == null) return const SizedBox();
    return OrganizerTodayPage(
      snapshot: data,
      actions: OrganizerActions(context, ref, data),
      onShopping: () {},
      onPlans: () {},
      onSharedAgenda: (_) {},
      onCalendar: () {},
      onProjects: () {},
    );
  },
);

void main() {
  testWidgets(
    'today and week events have compact honest times and a bounded overview',
    (tester) async {
      await pumpOverview(
        tester,
        OrganizerUtripOverview(
          snapshot: projection(
            OrganizerSnapshot(
              events: [
                for (var i = 0; i < 5; i++) event('Today $i'),
                event('Tomorrow', day: 13),
              ],
              projects: [project('Active project')],
            ),
          ),
          now: now,
        ),
      );
      expect(find.text('Today 0'), findsOneWidget);
      expect(find.text('Today 2'), findsOneWidget);
      expect(find.text('Today 3'), findsNothing);
      expect(find.text('17:00–18:00'), findsNWidgets(3));
      expect(find.textContaining('17:00–18:00'), findsNWidgets(4));
      expect(find.text('Osebno'), findsNothing);
      expect(find.text('Active project'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty overview keeps meaningful routes at 2x text on a small phone',
    (tester) async {
      final calls = <String>[];
      await pumpOverview(
        tester,
        OrganizerUtripOverview(
          snapshot: projection(OrganizerSnapshot()),
          now: now,
          onCalendar: () => calls.add('calendar'),
          onProjects: () => calls.add('projects'),
          onTasks: () => calls.add('tasks'),
        ),
        width: 360,
        scale: 2,
      );
      for (final title in [
        'Današnji dogodki',
        'V naslednjih 7 dneh',
        'Projekti v teku',
        'Na vrsti',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      await tester.ensureVisible(find.text('Koledar').first);
      await tester.tap(find.text('Koledar').first);
      await tester.ensureVisible(find.text('Projekti'));
      await tester.tap(find.text('Projekti'));
      await tester.ensureVisible(find.text('Vsa opravila'));
      await tester.tap(find.text('Vsa opravila'));
      expect(calls, ['calendar', 'projects', 'tasks']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'event row opens and saves exact real local event without changing IDs',
    (tester) async {
      final storage = MemoryOrganizerStorage()
        ..snapshot = OrganizerSnapshot(events: [event('Meeting')]);
      await pumpOverview(tester, localOverview(), storage: storage);
      await tester.tap(find.byKey(const ValueKey('utrip-local-event-Meeting')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('organizer-title-field')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Updated meeting',
      );
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(storage.snapshot.events.single.id, 'Meeting');
      expect(storage.snapshot.events.single.title, 'Updated meeting');
      expect(
        storage.snapshot.events.single.startsAt,
        DateTime(2026, 10, 12, 17),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('undated project row opens and saves exact real project', (
    tester,
  ) async {
    final storage = MemoryOrganizerStorage()
      ..snapshot = OrganizerSnapshot(projects: [project('Garden plan')]);
    await pumpOverview(tester, localOverview(), storage: storage);
    await tester.ensureVisible(
      find.byKey(const ValueKey('utrip-local-project-Garden plan')),
    );
    await tester.tap(
      find.byKey(const ValueKey('utrip-local-project-Garden plan')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organizer-title-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('organizer-title-field')),
      'Updated garden',
    );
    await tester.tap(find.byKey(const ValueKey('organizer-save')));
    await tester.pumpAndSettle();
    expect(storage.snapshot.projects.single.id, 'Garden plan');
    expect(storage.snapshot.projects.single.title, 'Updated garden');
    expect(storage.snapshot.projects.single.startAt, isNull);
    expect(
      storage.snapshot.projects.single.description,
      'Real project description',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'write-blocked selected space stays readable/reportable without creation',
    (tester) async {
      final shared = AllSpacesController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [
            const SharedScope(
              id: 'blocked',
              name: 'Shared home',
              kind: SharedScopeKind.household,
              role: SharedRole.owner,
              blocked: true,
            ),
          ],
          data: {
            'blocked': SharedScopeData(
              events: [
                SharedEvent(
                  id: 'readable-event',
                  title: 'Readable event',
                  startAt: now,
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
            ),
          },
        ),
      );
      await pumpOverview(
        tester,
        SharingWorkspace(
          view: SharingView.agenda,
          selectedScopeId: 'blocked',
          showScopePicker: false,
          onScopeSelected: (_) {},
          onConnect: () {},
        ),
        shared: shared,
        storage: MemoryOrganizerStorage(),
      );
      expect(find.text('Readable event'), findsOneWidget);
      expect(find.byTooltip('Dodaj dogodek'), findsNothing);
      expect(find.byTooltip('Dodaj opravilo'), findsNothing);
      await tester.tap(find.text('Readable event'));
      await tester.pumpAndSettle();
      expect(shared.opened.single.scopeId, 'blocked');
      expect(shared.opened.single.records.single.recordId, 'readable-event');
      await tester.tap(
        find.byKey(
          const ValueKey('content-actions-record-blocked-readable-event'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('report-action-record-blocked-readable-event'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'revoked selected scope does not expose cached overview content',
    (tester) async {
      final shared = AllSpacesController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [
            const SharedScope(
              id: 'revoked',
              name: 'Old home',
              kind: SharedScopeKind.household,
              role: SharedRole.owner,
              revoked: true,
            ),
          ],
          data: {
            'revoked': SharedScopeData(
              events: [
                SharedEvent(
                  id: 'hidden',
                  title: 'Hidden event',
                  startAt: now,
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
            ),
          },
        ),
      );
      await pumpOverview(
        tester,
        SharingWorkspace(
          view: SharingView.agenda,
          selectedScopeId: 'revoked',
          showScopePicker: false,
          onScopeSelected: (_) {},
          onConnect: () {},
        ),
        shared: shared,
        storage: MemoryOrganizerStorage(),
      );
      expect(find.text('Hidden event'), findsNothing);
      expect(shared.opened, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
