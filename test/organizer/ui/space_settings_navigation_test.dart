import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/presentation/shared/sharing_account_page.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/presentation/shared/space_settings_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';

const organizationId = '10000000-0000-4000-8000-000000000002';
const projectId = '10000000-0000-4000-8000-000000000003';
const organization = SharedScope(
  id: organizationId,
  name: 'Moja organizacija',
  kind: SharedScopeKind.organization,
  role: SharedRole.owner,
);
const project = SharedScope(
  id: projectId,
  name: 'Moj deljeni projekt',
  kind: SharedScopeKind.project,
  role: SharedRole.owner,
);
List<SharedScope> get scopes => [sharingScope(), organization, project];
CollaborationState selection({String? id, bool all = false}) =>
    CollaborationState(
      session: sharingSession(),
      scopes: scopes,
      selectedSpaceId: id,
      allSpacesSelected: all,
      organizationsSupported: true,
      emailInvitationsSupported: true,
    );

Future<void> openSettings(WidgetTester tester, double width) async {
  if (width < 600) {
    await mobileTab(tester, 'Nastavitve prostora');
  } else {
    if (width < 900) await mobileTab(tester, 'Več');
    final entry = find.widgetWithText(ListTile, 'Nastavitve prostora').first;
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

class DeferredSettingsController extends SharingUiController {
  DeferredSettingsController({super.initial});
  Completer<List<SharedMember>>? memberGate;
  Completer<void>? selectionGate;
  @override
  Future<List<SharedMember>> members(String scopeId) =>
      memberGate?.future ?? super.members(scopeId);
  @override
  Future<void> selectSpace(String? id) async {
    final account = state.requireValue.session;
    await selectionGate?.future;
    if (state.requireValue.session != account) return;
    await super.selectSpace(id);
  }
}

class InboxSettingsController extends SharingUiController {
  InboxSettingsController()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          selectedSpaceId: sharingScopeId,
          scopes: scopes,
          inboxSupported: true,
          organizationsSupported: true,
          inbox: [
            SharedInboxEntry(
              id: 1,
              scopeId: organizationId,
              kind: 'member.joined',
              category: 'membership',
              audience: InboxAudience.scope,
              targetType: 'membership',
              targetId: 'second',
              groupKey: 'joined',
              createdAt: sharingTestNow,
            ),
          ],
        ),
      );
  @override
  Future<NotificationOpenResult> openNotificationTarget(
    NotificationTarget target,
  ) async => NotificationOpenResult(
    status: NotificationOpenStatus.available,
    target: target,
  );
}

void main() {
  for (final width in [390.0, 700.0, 1280.0]) {
    for (final scope in scopes) {
      testWidgets('settings opens selected ${scope.kind.name} at $width', (
        tester,
      ) async {
        final controller = SharingUiController(
          initial: selection(id: scope.id),
        );
        await pumpOrganizer(
          tester,
          MemoryOrganizerStorage(),
          width: width,
          collaborationController: controller,
        );
        await openSettings(tester, width);
        expect(find.byType(SpaceSettingsPage), findsOneWidget);
        final members = tester.widget<SharingMembersPage>(
          find.byType(SharingMembersPage),
        );
        expect(members.scope.id, scope.id);
        expect(controller.memberLoads, 1);
        expect(find.text('Member Alpha'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Člani'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final all in [false, true]) {
    testWidgets(
      '${all ? 'All' : 'personal'} requires an explicit space and Back restores chooser',
      (tester) async {
        final controller = SharingUiController(initial: selection(all: all));
        await pumpOrganizer(
          tester,
          MemoryOrganizerStorage(),
          collaborationController: controller,
        );
        await openSettings(tester, 390);
        expect(find.byType(SharingMembersPage), findsNothing);
        expect(controller.memberLoads, 0);
        expect(
          find.byKey(ValueKey('space-settings-scope-$sharingScopeId')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('space-settings-scope-$organizationId')),
        );
        await tester.pumpAndSettle();
        expect(controller.state.requireValue.selectedSpaceId, organizationId);
        expect(controller.state.requireValue.allSpacesSelected, false);
        expect(
          tester
              .widget<SharingMembersPage>(find.byType(SharingMembersPage))
              .scope
              .id,
          organizationId,
        );
        await back(tester);
        expect(find.byType(SpaceSettingsPage), findsOneWidget);
        expect(find.byType(SharingMembersPage), findsNothing);
        expect(controller.state.requireValue.selectedSpaceId, isNull);
        expect(controller.state.requireValue.allSpacesSelected, all);
        await back(tester);
        expect(
          find.byKey(const ValueKey('content-_Area.today')),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'account scope shortcut selects that scope before showing members',
    (tester) async {
      final controller = SharingUiController(
        initial: selection(id: sharingScopeId),
      );
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: controller,
      );
      await mobileTab(tester, 'Račun in deljenje');
      tester
          .widget<SharingAccountPage>(find.byType(SharingAccountPage))
          .onScopeSelected(organizationId);
      await tester.pumpAndSettle();
      final shortcut = find.widgetWithText(ListTile, 'Nastavitve prostora');
      await tester.ensureVisible(shortcut);
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(controller.state.requireValue.selectedSpaceId, organizationId);
      expect(
        tester
            .widget<SharingMembersPage>(find.byType(SharingMembersPage))
            .scope
            .id,
        organizationId,
      );
      await back(tester);
      expect(controller.state.requireValue.selectedSpaceId, sharingScopeId);
      expect(
        tester
            .widget<SharingAccountPage>(find.byType(SharingAccountPage))
            .selectedScopeId,
        organizationId,
      );
    },
  );
  testWidgets('without account or spaces settings keeps useful empty state', (
    tester,
  ) async {
    final controller = SharingUiController(initial: CollaborationState());
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      collaborationController: controller,
    );
    await openSettings(tester, 390);
    expect(
      find.text('Za upravljanje skupnih prostorov poveži račun.'),
      findsOneWidget,
    );
    expect(find.byType(SharingMembersPage), findsNothing);
    controller.replace(CollaborationState(session: sharingSession()));
    await tester.pumpAndSettle();
    expect(find.text('Še ni skupnih prostorov.'), findsOneWidget);
    expect(controller.memberLoads, 0);
  });
  testWidgets('revoked or invalid account cannot expose cached members', (
    tester,
  ) async {
    final controller = SharingUiController(
      initial: selection(id: sharingScopeId),
    );
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      collaborationController: controller,
    );
    await openSettings(tester, 390);
    expect(find.text('Member Alpha'), findsOneWidget);
    controller.replace(
      CollaborationState(
        session: sharingSession(),
        selectedSpaceId: sharingScopeId,
        scopes: [sharingScope(revoked: true), organization],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SharingMembersPage), findsNothing);
    expect(find.text('Member Alpha'), findsNothing);
    expect(
      find.byKey(ValueKey('space-settings-scope-$sharingScopeId')),
      findsNothing,
    );
    controller.replace(
      CollaborationState(
        session: sharingSession(),
        sessionInvalid: true,
        selectedSpaceId: organizationId,
        scopes: scopes,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SharingMembersPage), findsNothing);
    expect(controller.memberLoads, 1);
  });
  testWidgets(
    'scope change closes open invitation and remounts guarded members',
    (tester) async {
      final controller = SharingUiController(
        initial: selection(id: sharingScopeId),
      );
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: controller,
      );
      await openSettings(tester, 390);
      final invite = find.text('Povabi osebo');
      await tester.ensureVisible(invite);
      await tester.tap(invite);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sharing-recipient')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('sharing-recipient')),
        'recipient@capture.invalid',
      );
      await controller.selectSpace(organizationId);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sharing-recipient')), findsNothing);
      expect(
        tester
            .widget<SharingMembersPage>(find.byType(SharingMembersPage))
            .scope
            .id,
        organizationId,
      );
      expect(
        controller.calls.where(
          (call) => call == 'invite' || call.startsWith('emailInvite:'),
        ),
        isEmpty,
      );
    },
  );
  testWidgets('archiving the space closes an already open invitation', (
    tester,
  ) async {
    final controller = SharingUiController(
      initial: selection(id: sharingScopeId),
    );
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      collaborationController: controller,
    );
    await openSettings(tester, 390);
    await tester.tap(find.text('Povabi osebo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sharing-recipient')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sharing-recipient')),
      'recipient@capture.invalid',
    );
    controller.replace(
      CollaborationState(
        session: sharingSession(),
        selectedSpaceId: sharingScopeId,
        emailInvitationsSupported: true,
        scopes: [
          SharedScope(
            id: sharingScopeId,
            name: sharingScope().name,
            kind: SharedScopeKind.household,
            role: SharedRole.owner,
            archived: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sharing-recipient')), findsNothing);
    expect(find.text('Povabi osebo'), findsNothing);
    expect(find.byType(SharingMembersPage), findsOneWidget);
    expect(
      controller.calls.where(
        (call) => call == 'invite' || call.startsWith('emailInvite:'),
      ),
      isEmpty,
    );
  });

  testWidgets(
    'late selection after account change cannot open previous account settings',
    (tester) async {
      final gate = Completer<void>();
      final controller = DeferredSettingsController(initial: selection())
        ..selectionGate = gate;
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: controller,
      );
      await openSettings(tester, 390);
      await tester.tap(
        find.byKey(const ValueKey('space-settings-scope-$organizationId')),
      );
      await tester.pump();
      controller.switchAccount();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SharingMembersPage), findsNothing);
      expect(controller.state.requireValue.selectedSpaceId, isNull);
      await back(tester);
      expect(find.byKey(const ValueKey('content-_Area.today')), findsOneWidget);
    },
  );
  testWidgets('late member response cannot appear after account switch', (
    tester,
  ) async {
    final gate = Completer<List<SharedMember>>();
    final controller = DeferredSettingsController(
      initial: selection(id: sharingScopeId),
    )..memberGate = gate;
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      collaborationController: controller,
    );
    // Use bounded pumps while the deliberately unfinished member request loads.
    await tester.tap(find.byKey(const ValueKey('organizer-menu-open')));
    await tester.pumpAndSettle();
    final entry = find.widgetWithText(ListTile, 'Nastavitve prostora');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pump(const Duration(milliseconds: 400));
    controller.switchAccount();
    gate.complete([
      const SharedMember(
        userId: 1,
        username: 'old',
        displayName: 'Old account member',
        role: SharedRole.owner,
        active: true,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Old account member'), findsNothing);
    expect(find.byType(SharingMembersPage), findsNothing);
  });
  testWidgets(
    'membership inbox link opens the same settings destination in its source space',
    (tester) async {
      final controller = InboxSettingsController();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: controller,
      );
      await tester.tap(find.byTooltip('Obvestila'));
      await tester.pumpAndSettle();
      final card = find.widgetWithText(ListTile, 'Pridružil/a si se prostoru');
      await tester.ensureVisible(card);
      await tester.tap(card);
      // Inbox keeps a progress indicator while its target dialog is open.
      await tester.pump(const Duration(milliseconds: 400));
      final members = find.widgetWithText(TextButton, 'Člani');
      expect(members, findsOneWidget);
      await tester.tap(members);
      await tester.pumpAndSettle();
      expect(find.byType(SpaceSettingsPage), findsOneWidget);
      expect(controller.state.requireValue.selectedSpaceId, organizationId);
      expect(
        tester
            .widget<SharingMembersPage>(find.byType(SharingMembersPage))
            .scope
            .id,
        organizationId,
      );
      await back(tester);
      expect(find.byKey(const ValueKey('content-_Area.inbox')), findsOneWidget);
      expect(controller.state.requireValue.selectedSpaceId, sharingScopeId);
    },
  );

  testWidgets('render phone settings and drawer for review', (tester) async {
    if (!const bool.fromEnvironment('SPACE_SETTINGS_QA')) return;
    await tester.runAsync(() async {
      final flutterRoot = Platform.resolvedExecutable
          .split('/bin/cache/')
          .first;
      final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
      final systemFont = File('/System/Library/Fonts/SFNS.ttf');
      final bytes =
          await (await systemFont.exists()
                  ? systemFont
                  : File('$fonts/Roboto-Regular.ttf'))
              .readAsBytes();
      for (final family in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      final icons = await File(
        '$fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    });
    final capture = GlobalKey();
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      width: 390,
      height: 844,
      collaborationController: SharingUiController(
        initial: selection(id: organizationId),
      ),
      repaintBoundaryKey: capture,
    );
    await openSettings(tester, 390);
    Future<void> snapshot(String name) => tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/qa/space-settings/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await snapshot('phone-settings');
    await tester.tap(find.byKey(const ValueKey('organizer-menu-open')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ListTile, 'Nastavitve prostora'),
    );
    await snapshot('phone-menu');
  });
}
