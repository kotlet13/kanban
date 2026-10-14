import 'sharing_ui_fixture.dart';
import 'package:kanban/organizer/state/idea_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/navigation/organizer_navigation.dart';
import 'package:kanban/organizer/presentation/navigation/organizer_destination_widgets.dart';
import 'package:kanban/organizer/presentation/backup/backup_wizard.dart';
import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;

class NavigationIdeaController extends IdeaController {
  @override
  Future<IdeaSnapshot> build() async => IdeaSnapshot();
}

void main() {
  test('all existing leaves retain a stable primary destination', () {
    expect(OrganizerDestination.values.length, 4);
    for (final area in [
      OrganizerArea.plans,
      OrganizerArea.calendar,
      OrganizerArea.ideas,
    ]) {
      expect(organizerDestinationFor(area), OrganizerDestination.planner);
    }
    for (final area in [
      OrganizerArea.projects,
      OrganizerArea.finances,
      OrganizerArea.shopping,
      OrganizerArea.garden,
      OrganizerArea.people,
    ]) {
      expect(organizerDestinationFor(area), OrganizerDestination.space);
    }
    for (final area in [
      OrganizerArea.sharing,
      OrganizerArea.spaceSettings,
      OrganizerArea.settings,
      OrganizerArea.reminderSettings,
      OrganizerArea.backups,
    ]) {
      expect(organizerDestinationFor(area), OrganizerDestination.more);
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0, 800.0]) {
      testWidgets('$platform $width fixed four destinations and real leaves', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final storage = MemoryOrganizerStorage();
        await pumpOrganizer(
          tester,
          storage,
          width: width,
          height: 1000,
          ideaController: NavigationIdeaController(),
          collaborationController: SharingUiController(),
        );
        final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(nav.destinations.length, 4);
        for (final label in ['Utrip', 'Planer', 'Prostor', 'Več']) {
          expect(
            find.widgetWithText(NavigationDestination, label),
            findsOneWidget,
          );
        }
        expect(find.byType(Drawer), findsNothing);
        await mobileTab(tester, 'Koledar');
        expect(
          find.byKey(const ValueKey('content-_Area.calendar')),
          findsOneWidget,
        );
        expect(find.byType(OrganizerPlannerViews), findsOneWidget);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('planner-view-ideas')),
        );
        await tester.tap(find.byKey(const ValueKey('planner-view-ideas')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('content-_Area.ideas')),
          findsOneWidget,
        );
        await mobileTab(tester, 'Projekti');
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2,
        );
        await tester.tap(find.byKey(const ValueKey('organizer-shell-back')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('content-_Area.space')),
          findsOneWidget,
        );
        await mobileTab(tester, 'Finance');
        expect(
          find.byKey(const ValueKey('content-_Area.finances')),
          findsOneWidget,
        );
        await mobileTab(tester, 'Nastavitve opomnikov');
        expect(
          find.byKey(const ValueKey('content-_Area.reminderSettings')),
          findsOneWidget,
        );
        expect(find.text('Vsi prostori'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('organizer-shell-back')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('content-_Area.more')),
          findsOneWidget,
        );
        await mobileTab(tester, 'Varnostne kopije');
        expect(
          find.byKey(const ValueKey('content-_Area.backups')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          3,
        );
        await tester.tap(find.text('Ustvari kopijo'));
        await tester.pumpAndSettle();
        expect(find.byType(BackupWizard), findsOneWidget);
        expect(storage.writes, 0);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets(
    'primary changes discard previous tab history and remember planner view',
    (tester) async {
      await pumpOrganizer(tester, MemoryOrganizerStorage());
      await mobileTab(tester, 'Koledar');
      await mobileTab(tester, 'Prostor');
      await mobileTab(tester, 'Več');
      await mobileTab(tester, 'Planer');
      expect(
        find.byKey(const ValueKey('content-_Area.calendar')),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('content-_Area.today')), findsOneWidget);
      expect(find.text('Pritisni še enkrat za izhod'), findsNothing);
    },
  );

  testWidgets(
    'desktop uses the same four primary groups and leaf destinations',
    (tester) async {
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        width: 1280,
        height: 1000,
        ideaController: NavigationIdeaController(),
        collaborationController: SharingUiController(),
      );
      expect(find.byType(NavigationBar), findsNothing);
      for (final destination in OrganizerDestination.values) {
        expect(
          find.byKey(ValueKey('organizer-destination-${destination.name}')),
          findsOneWidget,
        );
      }
      await mobileTab(tester, 'Koledar');
      expect(
        find.byKey(const ValueKey('content-_Area.calendar')),
        findsOneWidget,
      );
      await mobileTab(tester, 'Projekti');
      expect(
        find.byKey(const ValueKey('content-_Area.projects')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('organizer-shell-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('content-_Area.space')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
