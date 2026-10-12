import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_ledger.dart';
import 'package:kanban/organizer/presentation/garden/garden_page.dart';
import 'package:kanban/organizer/presentation/garden/garden_editor.dart';
import 'package:kanban/organizer/presentation/people/people_page.dart';
import 'package:kanban/organizer/presentation/projects_page.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/presentation/shared/content_actions_menu.dart';
import 'package:kanban/organizer/presentation/shared/content_moderation.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/garden_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'sharing_ui_fixture.dart';

class MenuController extends SharingUiController {
  MenuController({SharedRole role = SharedRole.owner})
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          selectedSpaceId: sharingScopeId,
          scopes: [sharingScope(role: role)],
          data: {sharingScopeId: sharingData()},
        ),
      );
  int previews = 0, reports = 0;
  @override
  Future<ContentReportPreview> previewContentReport({
    required String scopeId,
    required String targetType,
    required String targetId,
  }) async {
    previews++;
    final session = state.requireValue.session!;
    return ContentReportPreview(
      serverId: session.serverId,
      partition: session.partition,
      deviceId: session.deviceId,
      requestId: 'report-$previews',
      scopeId: scopeId,
      targetType: targetType,
      targetId: targetId,
      previewHash: 'a' * 64,
      targetRevision: 1,
      title: 'Selected shared record',
      type: 'task',
      recipientName: 'Server administrator',
      evidence: {'title': 'Selected shared record'},
    );
  }

  @override
  Future<ContentReportReceipt> submitContentReport({
    required ContentReportPreview preview,
    required String reason,
    String details = '',
  }) async {
    reports++;
    return ContentReportReceipt(
      reportId: 'report',
      status: 'submitted',
      createdAt: sharingTestNow,
    );
  }

  @override
  Future<List<SharedMember>> members(String scopeId) async => [
    SharedMember(
      userId: 1,
      accountId: sharingSession().accountId,
      username: 'first',
      displayName: 'Owner',
      role: SharedRole.owner,
      active: true,
    ),
    SharedMember(
      userId: 2,
      accountId: sharingSession(second: true).accountId,
      username: 'second',
      displayName: 'Visible member',
      role: SharedRole.member,
      active: true,
    ),
  ];
}

final _garden = Garden(
  id: 'garden',
  name: 'Shared garden',
  createdAt: sharingTestNow,
  updatedAt: sharingTestNow,
);

class _Gardens extends GardenController {
  @override
  Future<GardenSnapshot> build() async => GardenSnapshot(gardens: [_garden]);
}

class _LocalSpaces extends LocalSpacesController {
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState();
}

class _Organizer extends OrganizerController {
  @override
  Future<OrganizerSnapshot> build() async =>
      sharedPresentationSnapshot(sharingData());
}

final screenshotKey = GlobalKey();
bool _fontsLoaded = false;
Future<void> pumpMenu(
  WidgetTester tester,
  MenuController controller,
  Widget panel, {
  double width = 360,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  if (!_fontsLoaded) {
    await tester.runAsync(() async {
      final root = Platform.resolvedExecutable.split('/bin/cache/').first;
      final fonts = '$root/bin/cache/artifacts/material_fonts';
      final bytes = await File('$fonts/Roboto-Regular.ttf').readAsBytes();
      for (final family in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
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
      _fontsLoaded = true;
    });
  }
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        gardenProvider.overrideWith(_Gardens.new),
        localSpacesProvider.overrideWith(_LocalSpaces.new),
        organizerProvider.overrideWith(_Organizer.new),
      ],
      child: RepaintBoundary(
        key: screenshotKey,
        child: MaterialApp(
          locale: const Locale('en'),
          theme: ThemeData(fontFamily: 'Roboto'),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: panel)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openMenu(
  WidgetTester tester,
  String id, {
  String type = 'record',
}) async {
  final finder = find.byKey(
    ValueKey('content-actions-$type-$sharingScopeId-$id'),
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> screenshot(WidgetTester tester, String file) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(screenshotKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final target = File('build/qa/report-menu-declutter/$file.png');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final width in [360.0, 800.0, 1280.0]) {
    testWidgets(
      'project overview has no extra report button; existing detail menu keeps edit $width',
      (tester) async {
        final controller = MenuController();
        String? selected;
        await pumpMenu(
          tester,
          controller,
          StatefulBuilder(
            builder: (context, setState) => Consumer(
              builder: (context, ref, _) {
                ref.watch(collaborationProvider);
                return OrganizerProjectsPage(
                  snapshot: sharedPresentationSnapshot(sharingData()),
                  actions: CollaborationActions(
                    context,
                    ref,
                    sharingScope(),
                    sharingData(),
                  ),
                  reportScopeId: sharingScopeId,
                  selectedId: selected,
                  onSelection: (id) => setState(() => selected = id),
                );
              },
            ),
          ),
          width: width,
        );
        expect(find.byType(SharedContentActionsMenu), findsNothing);
        expect(find.byIcon(Icons.flag_outlined), findsNothing);
        await tester.tap(find.text('Skupni vrt'));
        await tester.pumpAndSettle();
        expect(selected, 'project');
        expect(find.byType(SharedContentActionsMenu), findsOneWidget);
        await openMenu(tester, 'project');
        expect(controller.previews, 0);
        expect(controller.reports, 0);
        expect(find.text('Report content'), findsOneWidget);
        await tester.tap(find.text('Edit project'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('organizer-save')), findsOneWidget);
        expect(controller.previews, 0);
        expect(controller.reports, 0);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'read-only tasks report through More; no send until explicit confirmation $width',
      (tester) async {
        final controller = MenuController(role: SharedRole.viewer);
        await pumpMenu(
          tester,
          controller,
          Consumer(
            builder: (context, ref, _) => OrganizerTasksPage(
              snapshot: sharedPresentationSnapshot(sharingData()),
              actions: CollaborationActions(
                context,
                ref,
                sharingScope(role: SharedRole.viewer),
                sharingData(),
              ),
              reportScopeId: sharingScopeId,
              readOnly: true,
            ),
          ),
          width: width,
        );
        expect(find.byIcon(Icons.flag_outlined), findsNothing);
        expect(find.byType(ContentReportButton), findsNothing);
        if (width == 360) await screenshot(tester, 'tasks-360');
        await openMenu(tester, 'task');
        expect(controller.previews, 0);
        expect(controller.reports, 0);
        if (width == 360) await screenshot(tester, 'tasks-more-360');
        await tester.tap(find.text('Report content'));
        await tester.pumpAndSettle();
        expect(controller.previews, 1);
        expect(controller.reports, 0);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(controller.reports, 0);
        await openMenu(tester, 'task');
        await tester.tap(find.text('Report content'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('report-reason')));
        await tester.tap(find.byKey(const ValueKey('report-reason')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Other').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('report-send')));
        await tester.pumpAndSettle();
        expect(controller.reports, 1);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'shared finance single More action keeps audit/edit; no Report table column $width',
      (tester) async {
        final controller = MenuController();
        var edits = 0, audits = 0;
        final entry = SharedFinanceEntry(
          id: 'entry',
          accountId: 'account',
          title: 'Shared expense',
          amountMinor: 100,
          currency: 'EUR',
          kind: FinanceEntryKind.expense,
          occurredAt: sharingTestNow,
          createdAt: sharingTestNow,
          updatedAt: sharingTestNow,
        );
        await pumpMenu(
          tester,
          controller,
          SharedFinanceLedger(
            scopeName: 'Shared home',
            scopeId: sharingScopeId,
            accounts: [
              SharedFinanceAccount(
                id: 'account',
                name: 'Joint account',
                currency: 'EUR',
                createdAt: sharingTestNow,
                updatedAt: sharingTestNow,
              ),
            ],
            entries: [entry],
            transfers: const [],
            people: const [],
            canWrite: true,
            onAccount: (_) {},
            onEntry: (_) => edits++,
            onTransfer: (_) {},
            onAudit: (_) => audits++,
          ),
          width: width,
        );
        expect(find.byIcon(Icons.flag_outlined), findsNothing);
        expect(find.text('Report content'), findsNothing);
        for (final table in tester.widgetList<DataTable>(
          find.byType(DataTable),
        )) {
          expect(
            table.columns.where(
              (c) =>
                  c.label is Text && (c.label as Text).data == 'Report content',
            ),
            isEmpty,
          );
        }
        await openMenu(tester, 'entry', type: 'finance');
        await tester.tap(find.text('Change history'));
        await tester.pumpAndSettle();
        expect(audits, 1);
        await openMenu(tester, 'entry', type: 'finance');
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(edits, 1);
        expect(controller.previews, 0);
        expect(controller.reports, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'open menu keeps same-account refresh but blocks previous-account callback',
    (tester) async {
      final controller = MenuController();
      await pumpMenu(
        tester,
        controller,
        const SharedContentActionsMenu(
          scopeId: sharingScopeId,
          targetId: 'task',
          reminderType: 'task',
        ),
      );
      await openMenu(tester, 'task');
      final before = controller.state.requireValue;
      controller.replace(
        CollaborationState(
          session: before.session,
          selectedSpaceId: sharingScopeId,
          scopes: before.scopes,
          data: before.data,
          lastError: const CollaborationException('network'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report content'));
      await tester.pumpAndSettle();
      expect(controller.previews, 1);
      expect(controller.reports, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await openMenu(tester, 'task');
      controller.replace(
        CollaborationState(
          session: sharingSession(second: true),
          selectedSpaceId: sharingScopeId,
          scopes: before.scopes,
          data: before.data,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report content'));
      await tester.pumpAndSettle();
      expect(controller.previews, 1);
      expect(controller.reports, 0);
      expect(find.byType(ContentReportDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'garden overview and collapsed people show no reporting buttons; details remain reportable read-only',
    (tester) async {
      final controller = MenuController(role: SharedRole.viewer);
      await pumpMenu(tester, controller, const GardenPage());
      expect(find.byType(SharedContentActionsMenu), findsNothing);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      await tester.tap(find.text('Shared garden'));
      await tester.pumpAndSettle();
      expect(find.byType(GardenEditor), findsOneWidget);
      await openMenu(tester, 'garden');
      expect(find.text('Report content'), findsOneWidget);
      expect(controller.previews, 0);
      await tester.tap(find.text('Report content'));
      await tester.pumpAndSettle();
      expect(controller.previews, 1);
      expect(controller.reports, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final peopleController = MenuController(role: SharedRole.viewer);
      await pumpMenu(
        tester,
        peopleController,
        OrganizerPeoplePage(
          people: [
            HouseholdPerson(
              id: 'person',
              name: 'Household person',
              createdAt: sharingTestNow,
              updatedAt: sharingTestNow,
            ),
          ],
          tasks: const [],
          scope: sharingScope(role: SharedRole.viewer),
          readOnly: true,
        ),
      );
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      await tester.tap(find.text('Household person'));
      await tester.pumpAndSettle();
      await openMenu(tester, 'person');
      expect(find.text('Report content'), findsOneWidget);
      expect(controller.reports, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('member More combines reporting and remove; owner protected', (
    tester,
  ) async {
    final controller = MenuController();
    await pumpMenu(
      tester,
      controller,
      SharingMembersPage(scope: sharingScope(), session: sharingSession()),
    );
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
    expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
    await openMenu(
      tester,
      sharingSession(second: true).accountId,
      type: 'user',
    );
    expect(find.text('Report user'), findsOneWidget);
    expect(find.text('Remove member'), findsOneWidget);
    expect(controller.previews, 0);
    await tester.tap(find.text('Remove member'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(controller.reports, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'personal project detail preserves direct edit and has no report menu',
    (tester) async {
      final controller = MenuController();
      await pumpMenu(
        tester,
        controller,
        Consumer(
          builder: (context, ref, _) {
            ref.watch(collaborationProvider);
            return OrganizerProjectsPage(
              snapshot: sharedPresentationSnapshot(sharingData()),
              actions: CollaborationActions(
                context,
                ref,
                sharingScope(),
                sharingData(),
              ),
              selectedId: 'project',
              onSelection: (_) {},
            );
          },
        ),
      );
      expect(find.byType(SharedContentActionsMenu), findsNothing);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      await tester.tap(find.byTooltip('Edit project'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('organizer-save')), findsOneWidget);
      expect(controller.previews, 0);
    },
  );
  testWidgets(
    'legacy member without account UUID still has protected Remove in More',
    (tester) async {
      final controller = MenuController();
      await pumpMenu(
        tester,
        controller,
        SharingMembersPage(scope: sharingScope(), session: sharingSession()),
      );
      // Replacing only the test member loader exercises the old transport shape.
      await tester.pumpWidget(const SizedBox.shrink());
      final legacy = LegacyMenuController();
      await pumpMenu(
        tester,
        legacy,
        SharingMembersPage(scope: sharingScope(), session: sharingSession()),
      );
      await openMenu(tester, 'member-2', type: 'user');
      expect(find.text('Remove member'), findsOneWidget);
      expect(find.text('Report user'), findsNothing);
      await tester.tap(find.text('Remove member'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(legacy.previews, 0);
      expect(legacy.reports, 0);
    },
  );
  testWidgets(
    'read-only task existing reminder cancellation remains in More without sending on open',
    (tester) async {
      final controller = MenuController(role: SharedRole.viewer);
      await pumpMenu(
        tester,
        controller,
        const SharedContentActionsMenu(
          scopeId: sharingScopeId,
          targetId: 'task',
          reminderType: 'task',
        ),
      );
      final before = controller.state.requireValue;
      controller.replace(
        CollaborationState(
          session: before.session,
          selectedSpaceId: sharingScopeId,
          scopes: before.scopes,
          data: before.data,
          inboxSupported: true,
          scheduledReminders: [
            SharedScheduledReminder(
              id: 'reminder',
              scopeId: sharingScopeId,
              targetType: 'task',
              targetId: 'task',
              remindAt: DateTime.now().add(const Duration(hours: 1)),
              revision: 1,
              state: 'pending',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await openMenu(tester, 'task');
      expect(find.text('Cancel reminder'), findsOneWidget);
      expect(find.text('Report content'), findsOneWidget);
      await tester.tap(find.text('Cancel reminder'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(controller.previews, 0);
      expect(controller.reports, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'archiving scope after menu opened blocks its stale report callback',
    (tester) async {
      final controller = MenuController();
      await pumpMenu(
        tester,
        controller,
        const SharedContentActionsMenu(
          scopeId: sharingScopeId,
          targetId: 'task',
        ),
      );
      await openMenu(tester, 'task');
      final before = controller.state.requireValue;
      controller.replace(
        CollaborationState(
          session: before.session,
          scopes: [
            SharedScope.fromJson({
              ...before.scopes.single.toJson(),
              'archived': true,
            }),
          ],
          data: before.data,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report content'));
      await tester.pumpAndSettle();
      expect(controller.previews, 0);
      expect(controller.reports, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

class LegacyMenuController extends MenuController {
  @override
  Future<List<SharedMember>> members(String scopeId) async => [
    const SharedMember(
      userId: 1,
      username: 'first',
      displayName: 'Legacy owner',
      role: SharedRole.owner,
      active: true,
    ),
    const SharedMember(
      userId: 2,
      username: 'second',
      displayName: 'Legacy member',
      role: SharedRole.member,
      active: true,
    ),
  ];
}
