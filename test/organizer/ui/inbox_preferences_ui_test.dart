import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/organizer/presentation/inbox/inbox_preferences.dart';
import 'package:kanban/organizer/presentation/planning/remote_push_device_settings.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import '../platform/remote_push/remote_push_lifecycle_test.dart' as lifecycle;
import '../platform/remote_push/remote_push_ui_test.dart' as push;
import 'sharing_ui_fixture.dart';

const secondScopeId = '10000000-0000-4000-8000-000000000002';
const secondScope = SharedScope(
  id: secondScopeId,
  name: 'Drugi prostor',
  kind: SharedScopeKind.household,
  role: SharedRole.owner,
);

CollaborationState preferencesState({
  bool secondAccount = false,
  String selected = sharingScopeId,
  bool secondPush = false,
}) => CollaborationState(
  session: sharingSession(second: secondAccount),
  selectedSpaceId: selected,
  externalPushSupported: true,
  inboxSupported: true,
  smtpSupported: true,
  pushProjectId: lifecycle.config.projectId,
  scopes: [sharingScope(), secondScope],
  notificationPreferences: {
    sharingScopeId: SharedNotificationPreferences(scopeId: sharingScopeId),
    secondScopeId: SharedNotificationPreferences(
      scopeId: secondScopeId,
      categories: secondPush
          ? const {
              'reminders': SharedNotificationSettings(push: true),
              'tasks': SharedNotificationSettings(push: true),
            }
          : const {},
    ),
  },
);

class PreferencesController extends push.PushController {
  PreferencesController(this.preferences);
  final CollaborationState preferences;
  final writes =
      <
        ({String scopeId, String category, SharedNotificationSettings settings})
      >[];
  Completer<void>? saveGate;

  @override
  Future<CollaborationState> build() async => preferences;

  @override
  Future<void> setNotificationPreferences({
    required String scopeId,
    required String category,
    required SharedNotificationSettings settings,
  }) async {
    writes.add((scopeId: scopeId, category: category, settings: settings));
    await saveGate?.future;
  }
}

Finder get summary => find.byKey(const ValueKey('inbox-push-category-summary'));
String summaryText(WidgetTester tester) => tester.widget<Text>(summary).data!;
Finder reminderSwitch(String label) =>
    find.widgetWithText(SwitchListTile, label);

Future<void> selectScope(WidgetTester tester, String name) async {
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'device registration leaves scope categories and local reminders unchanged',
    (tester) async {
      final controller = PreferencesController(preferencesState());
      final sdk = lifecycle.FakeSdk();
      await tester.pumpWidget(
        push.host(controller, sdk, child: const InboxPreferences()),
      );
      await tester.pumpAndSettle();
      expect(sdk.calls, isEmpty);
      expect(controller.writes, isEmpty);
      expect(summaryText(tester), contains('ni izbranih vrst'));

      final deviceSwitch = find.descendant(
        of: find.byType(RemotePushDeviceSettings),
        matching: find.byType(SwitchListTile),
      );
      await tester.ensureVisible(deviceSwitch);
      await tester.tap(deviceSwitch);
      await tester.pumpAndSettle();
      expect(controller.registered, 1);
      expect(sdk.calls, contains('token'));
      expect(controller.writes, isEmpty);
      expect(summaryText(tester), contains('ni izbranih vrst'));
      final reminderPush = tester.widget<SwitchListTile>(
        reminderSwitch('Oddaljena sistemska obvestila'),
      );
      expect(reminderPush.value, isFalse);
      expect(reminderPush.onChanged, isNotNull);
      expect(
        controller
            .state
            .requireValue
            .notificationPreferences[sharingScopeId]!
            .categories,
        isEmpty,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('organizer_local_reminders_enabled_v1'), isNull);
      expect(prefs.getBool('organizer_local_reminders_sound_v1'), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'selected space summary and expanded reminders fit $width without writes',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = PreferencesController(
          preferencesState(selected: secondScopeId, secondPush: true),
        );
        final sdk = lifecycle.FakeSdk();
        await tester.pumpWidget(
          push.host(controller, sdk, child: const InboxPreferences()),
        );
        await tester.pumpAndSettle();
        expect(summaryText(tester), contains('Drugi prostor'));
        expect(summaryText(tester), contains('2 izbrani vrsti'));
        expect(find.text('Opomniki, Opravila in načrti'), findsOneWidget);
        expect(
          tester
              .widget<SwitchListTile>(
                reminderSwitch('Oddaljena sistemska obvestila'),
              )
              .value,
          isTrue,
        );
        await selectScope(tester, sharingScope().name);
        expect(summaryText(tester), contains(sharingScope().name));
        expect(summaryText(tester), contains('ni izbranih vrst'));
        expect(
          tester
              .widget<SwitchListTile>(
                reminderSwitch('Oddaljena sistemska obvestila'),
              )
              .value,
          isFalse,
        );
        expect(controller.writes, isEmpty);
        expect(controller.state.requireValue.selectedSpaceId, secondScopeId);
        expect(sdk.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('explicit target scope is ignored after changing accounts', (
    tester,
  ) async {
    final controller = PreferencesController(
      preferencesState(secondPush: true),
    );
    await tester.pumpWidget(
      push.host(
        controller,
        lifecycle.FakeSdk(),
        child: const InboxPreferences(initialScopeId: secondScopeId),
      ),
    );
    await tester.pumpAndSettle();
    expect(summaryText(tester), contains('Drugi prostor'));
    controller.replace(preferencesState(secondAccount: true));
    await tester.pumpAndSettle();
    expect(summaryText(tester), contains(sharingScope().name));
    expect(summaryText(tester), contains('ni izbranih vrst'));
    expect(controller.writes, isEmpty);
  });

  testWidgets(
    'late preference error after account switch is not shown to new account',
    (tester) async {
      final controller = PreferencesController(
        preferencesState(selected: secondScopeId),
      );
      final gate = Completer<void>();
      controller.saveGate = gate;
      await tester.pumpWidget(
        push.host(
          controller,
          lifecycle.FakeSdk(),
          child: const InboxPreferences(),
        ),
      );
      await tester.pumpAndSettle();
      final inApp = reminderSwitch('V centru obvestil');
      await tester.ensureVisible(inApp);
      await tester.tap(inApp);
      await tester.pump();
      expect(controller.writes.single.scopeId, secondScopeId);
      expect(controller.writes.single.category, 'reminders');
      expect(controller.writes.single.settings.inApp, isFalse);
      controller.replace(preferencesState(secondAccount: true));
      gate.completeError(const CollaborationException('session_changed'));
      await tester.pumpAndSettle();
      expect(summaryText(tester), contains(sharingScope().name));
      expect(find.byType(SnackBar), findsNothing);
      expect(controller.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
