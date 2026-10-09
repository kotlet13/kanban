import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/app_router.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/presentation/all_spaces/all_spaces_page.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/presentation/projects_page.dart';
import 'package:kanban/organizer/presentation/shopping_page.dart';
import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';
import 'all_spaces_ui_test.dart'
    show AllSpacesController, sharedData, localData;

const exitPrompt = 'Pritisni še enkrat za izhod';

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void expectArea(String area) =>
    expect(find.byKey(ValueKey('content-_Area.$area')), findsOneWidget);

class DelayedSpaceController extends AllSpacesController {
  Completer<void>? allGate, spaceGate;
  int spaceCalls = 0;
  @override
  Future<void> selectAllSpaces() async {
    final identity = state.valueOrNull?.session;
    await allGate?.future;
    if (state.valueOrNull?.session != identity) return;
    await super.selectAllSpaces();
  }

  @override
  Future<void> selectSpace(String? id) async {
    spaceCalls++;
    final identity = state.valueOrNull?.session;
    await spaceGate?.future;
    if (state.valueOrNull?.session != identity) return;
    await super.selectSpace(id);
  }
}

Future<void> predictiveBack(WidgetTester tester) async {
  for (final call in [
    const MethodCall('startBackGesture', {
      'touchOffset': [5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    }),
    const MethodCall('commitBackGesture'),
  ]) {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(call),
      (_) {},
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  final platformCalls = <MethodCall>[];
  setUp(() {
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  int exits() =>
      platformCalls.where((c) => c.method == 'SystemNavigator.pop').length;

  testWidgets(
    'predictive gesture commit uses root PopScope and explicit exit policy',
    (tester) async {
      await pumpOrganizer(tester, MemoryOrganizerStorage());
      final context = tester.element(
        find.byKey(const ValueKey('content-_Area.today')),
      );
      expect(
        ModalRoute.of(context)!.popDisposition,
        RoutePopDisposition.doNotPop,
      );
      await predictiveBack(tester);
      expect(find.text(exitPrompt), findsOneWidget);
      expect(exits(), 0);
      await predictiveBack(tester);
      expect(exits(), 1);
    },
  );

  testWidgets('router root requires two backs within two seconds', (
    tester,
  ) async {
    await pumpOrganizer(tester, MemoryOrganizerStorage());
    expect(appRouter.canPop(), false);
    await back(tester);
    expect(find.text(exitPrompt), findsOneWidget);
    expect(exits(), 0);
    await back(tester);
    expect(exits(), 1);
  });

  testWidgets(
    'expired exit window and background each require fresh first back',
    (tester) async {
      await pumpOrganizer(tester, MemoryOrganizerStorage());
      await back(tester);
      await tester.pump(const Duration(seconds: 3));
      await back(tester);
      expect(exits(), 0);
      expect(find.text(exitPrompt), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await back(tester);
      expect(exits(), 0);
      await back(tester);
      expect(exits(), 1);
    },
  );

  testWidgets('router Back closes drawer first and clears earlier exit press', (
    tester,
  ) async {
    await pumpOrganizer(tester, MemoryOrganizerStorage());
    await back(tester);
    await tester.tap(find.byKey(const ValueKey('organizer-menu-open')));
    await tester.pumpAndSettle();
    await back(tester);
    expectArea('today');
    expect(
      find.byKey(const ValueKey('organizer-menu-close')).hitTestable(),
      findsNothing,
    );
    expect(exits(), 0);
    expect(find.text(exitPrompt), findsNothing);
    await back(tester);
    expect(find.text(exitPrompt), findsOneWidget);
    expect(exits(), 0);
  });

  testWidgets('sequential modules reverse actual navigation before any exit', (
    tester,
  ) async {
    await pumpOrganizer(tester, MemoryOrganizerStorage());
    await mobileTab(tester, 'Projekti');
    await mobileTab(tester, 'Nastavitve');
    await tester.tap(find.byTooltip('Obvestila'));
    await tester.pumpAndSettle();
    expectArea('inbox');
    await back(tester);
    expectArea('settings');
    await back(tester);
    expectArea('projects');
    await back(tester);
    expectArea('today');
    expect(exits(), 0);
    expect(find.text(exitPrompt), findsNothing);
    await back(tester);
    expect(find.text(exitPrompt), findsOneWidget);
  });

  testWidgets(
    'project and list drilldowns return to collection, then previous area',
    (tester) async {
      final now = DateTime(2026);
      final storage = MemoryOrganizerStorage()
        ..snapshot = OrganizerSnapshot(
          projects: [
            LocalProject(
              id: 'p',
              title: 'Moj projekt',
              description: '',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          shoppingLists: [
            LocalShoppingList(
              id: 'a',
              title: 'Prvi seznam',
              createdAt: now,
              updatedAt: now,
            ),
            LocalShoppingList(
              id: 'b',
              title: 'Drugi seznam',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
      await pumpOrganizer(tester, storage);
      await mobileTab(tester, 'Projekti');
      await tester.tap(find.text('Moj projekt'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OrganizerProjectsPage>(find.byType(OrganizerProjectsPage))
            .selectedId,
        'p',
      );
      await mobileTab(tester, 'Nakupi');
      await tester.tap(find.text('Prvi seznam'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OrganizerShoppingPage>(find.byType(OrganizerShoppingPage))
            .selectedId,
        'a',
      );
      await back(tester);
      expect(
        tester
            .widget<OrganizerShoppingPage>(find.byType(OrganizerShoppingPage))
            .selectedId,
        isNull,
      );
      await back(tester);
      expectArea('projects');
      expect(
        tester
            .widget<OrganizerProjectsPage>(find.byType(OrganizerProjectsPage))
            .selectedId,
        'p',
      );
      await back(tester);
      expect(
        tester
            .widget<OrganizerProjectsPage>(find.byType(OrganizerProjectsPage))
            .selectedId,
        isNull,
      );
      await back(tester);
      expectArea('today');
      expect(exits(), 0);
    },
  );

  testWidgets('dialogs and pushed router pages close before shell history', (
    tester,
  ) async {
    await pumpOrganizer(tester, MemoryOrganizerStorage());
    await mobileTab(tester, 'Nastavitve');
    final context = tester.element(
      find.byKey(const ValueKey('content-_Area.settings')),
    );
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Dialog')),
    );
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('Dialog'), findsNothing);
    expectArea('settings');
    appRouter.push('/settings/ai');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(appRouter.canPop(), true);
    await back(tester);
    expectArea('settings');
    await back(tester);
    expectArea('today');
    expect(exits(), 0);
  });

  testWidgets('opening and closing modal invalidates earlier root exit press', (
    tester,
  ) async {
    await pumpOrganizer(tester, MemoryOrganizerStorage());
    await back(tester);
    final context = tester.element(
      find.byKey(const ValueKey('content-_Area.today')),
    );
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Root dialog')),
    );
    await tester.pumpAndSettle();
    await back(tester);
    await back(tester);
    expect(exits(), 0);
    expect(find.text(exitPrompt), findsOneWidget);
  });

  testWidgets(
    'changing account clears collection IDs and previous account history',
    (tester) async {
      final shared = SharingUiController();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: shared,
      );
      await mobileTab(tester, 'Opravila');
      await mobileTab(tester, 'Projekti');
      await mobileTab(tester, 'Nastavitve');
      shared.switchAccount();
      await tester.pumpAndSettle();
      await back(tester);
      expectArea('today');
      expect(exits(), 0);
      await back(tester);
      expect(find.text(exitPrompt), findsOneWidget);
    },
  );

  testWidgets('account and space settings reverse without embedding content', (
    tester,
  ) async {
    final shared = SharingUiController(
      initial: CollaborationState(
        session: sharingSession(),
        selectedSpaceId: sharingScopeId,
        scopes: [sharingScope()],
        data: {sharingScopeId: sharingData()},
      ),
    );
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      collaborationController: shared,
    );
    await mobileTab(tester, 'Projekti');
    await mobileTab(tester, 'Račun in deljenje');
    expect(find.byType(SharingWorkspace), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Nastavitve prostora'));
    await tester.pumpAndSettle();
    expectArea('spaceSettings');
    await back(tester);
    expectArea('sharing');
    await back(tester);
    expectArea('projects');
    await back(tester);
    expectArea('today');
    expect(exits(), 0);
  });

  testWidgets(
    'all spaces row Back restores aggregate workspace before earlier module',
    (tester) async {
      final shared = AllSpacesController(initial: sharedData());
      final storage = MemoryOrganizerStorage()..snapshot = localData();
      await pumpOrganizer(tester, storage, collaborationController: shared);
      await mobileTab(tester, 'Projekti');
      await tester.tap(find.text('QA skupna ureditev vrta'));
      await tester.pumpAndSettle();
      expect(shared.state.valueOrNull!.selectedSpaceId, sharingScopeId);
      expect(shared.state.valueOrNull!.allSpacesSelected, false);
      await back(tester);
      expect(shared.state.valueOrNull!.allSpacesSelected, true);
      expect(shared.state.valueOrNull!.selectedSpaceId, isNull);
      expectArea('projects');
      expect(find.text('QA skupna ureditev vrta'), findsOneWidget);
      await back(tester);
      expectArea('today');
      expect(exits(), 0);
    },
  );

  testWidgets('late workspace restoration cannot overwrite a newer module', (
    tester,
  ) async {
    final shared = DelayedSpaceController();
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage()..snapshot = localData(),
      collaborationController: shared,
    );
    await mobileTab(tester, 'Projekti');
    await tester.tap(find.text('QA skupna ureditev vrta'));
    await tester.pumpAndSettle();
    shared.allGate = Completer<void>();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await mobileTab(tester, 'Nakupi');
    shared.allGate!.complete();
    await tester.pumpAndSettle();
    expectArea('shopping');
    expect(exits(), 0);
  });

  testWidgets(
    'account change during pending restoration cannot restore old history',
    (tester) async {
      final shared = DelayedSpaceController();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage()..snapshot = localData(),
        collaborationController: shared,
      );
      await mobileTab(tester, 'Projekti');
      await tester.tap(find.text('QA skupna ureditev vrta'));
      await tester.pumpAndSettle();
      shared.allGate = Completer<void>();
      await tester.binding.handlePopRoute();
      await tester.pump();
      shared.switchAccount();
      await tester.pump();
      await mobileTab(tester, 'Nastavitve');
      shared.allGate!.complete();
      await tester.pumpAndSettle();
      expectArea('settings');
      expect(
        shared.state.valueOrNull!.session!.accountId,
        sharingSession(second: true).accountId,
      );
      await back(tester);
      expectArea('projects');
      expect(
        tester
            .widget<OrganizerProjectsPage>(find.byType(OrganizerProjectsPage))
            .selectedId,
        isNull,
      );
      await back(tester);
      expectArea('today');
      expect(exits(), 0);
    },
  );

  testWidgets(
    'duplicate source taps do not start overlapping workspace selections',
    (tester) async {
      final shared = DelayedSpaceController()..spaceGate = Completer<void>();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage()..snapshot = localData(),
        collaborationController: shared,
      );
      await mobileTab(tester, 'Projekti');
      final page = tester.widget<AllSpacesPage>(find.byType(AllSpacesPage));
      final source = AllSpacesSource(
        key: 'shared-test',
        scope: sharingScope(),
        session: sharingSession(),
        canReadFinance: false,
        financeComplete: false,
      );
      final first = page.onSource(
        source,
        AllSpacesArea.projects,
        'same-project',
      );
      final second = page.onSource(
        source,
        AllSpacesArea.projects,
        'same-project',
      );
      await tester.pump();
      expect(shared.spaceCalls, 1);
      shared.spaceGate!.complete();
      await Future.wait([first, second]);
      await tester.pumpAndSettle();
      expectArea('projects');
      await back(tester);
      expect(shared.state.valueOrNull!.allSpacesSelected, true);
      expect(exits(), 0);
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
    testWidgets('$platform never uses Android exit prompt', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        width: platform == TargetPlatform.iOS ? 390 : 1280,
      );
      await back(tester);
      expect(find.text(exitPrompt), findsNothing);
      // Binding fallback may forward a platform pop; the shell does not intercept
      // the root with the Android two-press policy on these platforms.
      if (platform == TargetPlatform.iOS) {
        await mobileTab(tester, 'Projekti');
      } else {
        await tester.tap(find.widgetWithText(ListTile, 'Projekti'));
        await tester.pumpAndSettle();
      }
      await back(tester);
      expectArea('today');
      expect(find.text(exitPrompt), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
