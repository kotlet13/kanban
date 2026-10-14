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
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/notification_local_spaces_provider.dart';
import 'package:kanban/organizer/state/local_notification_preferences_provider.dart';
import 'package:kanban/organizer/platform/notification_providers.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import '../platform/local_notification_adapter_test.dart' as local;

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
  bool defaults = false,
}) => CollaborationState(
  session: sharingSession(second: secondAccount),
  selectedSpaceId: selected,
  externalPushSupported: true,
  inboxSupported: true,
  recordContractVersion: 5,
  smtpSupported: true,
  pushProjectId: lifecycle.config.projectId,
  scopes: [sharingScope(), secondScope],
  notificationPreferences: {
    sharingScopeId: SharedNotificationPreferences(
      scopeId: sharingScopeId,
      categories: defaults
          ? const {}
          : {
              for (final category in [
                'reminders',
                'tasks',
                'events',
                'shopping',
                'membership',
                'finance',
                'ideas',
              ])
                category: const SharedNotificationSettings(push: false),
            },
    ),
    secondScopeId: SharedNotificationPreferences(
      scopeId: secondScopeId,
      categories: {
        for (final category in [
          'reminders',
          'tasks',
          'events',
          'shopping',
          'membership',
          'finance',
          'ideas',
        ])
          category: SharedNotificationSettings(
            push: secondPush && ['reminders', 'tasks'].contains(category),
          ),
      },
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
  Future<void> setNotificationChannel({
    required Iterable<String> scopeIds,
    required String channel,
    required bool enabled,
    required String expectedPartition,
    String? category,
  }) async {
    final current = state.requireValue;
    expect(expectedPartition, current.session!.partition);
    for (final id in scopeIds) {
      for (final kind
          in category == null ? sharedNotificationCategories : [category]) {
        final settings =
            (current.notificationPreferences[id]?.forCategory(kind) ??
                    const SharedNotificationSettings())
                .withChannel(channel, enabled);
        writes.add((scopeId: id, category: kind, settings: settings));
      }
    }
    await saveGate?.future;
  }
}

class LocalCatalog extends LocalSpacesController {
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    spaces: const [
      LocalSpace(id: 'local', name: 'Osebno', kind: LocalSpaceKind.personal),
    ],
    snapshots: {'local': OrganizerSnapshot()},
  );
}

Widget settingsHost(
  PreferencesController controller,
  lifecycle.FakeSdk sdk, {
  String? initialScopeId,
  double textScale = 1,
}) => push.host(
  controller,
  sdk,
  child: ProviderScope(
    overrides: [
      localSpacesProvider.overrideWith(LocalCatalog.new),
      notificationLocalSnapshotsProvider.overrideWith(
        (ref) async => [OrganizerSnapshot()],
      ),
      localNotificationSchedulerProvider.overrideWithValue(
        local.FakeScheduler(),
      ),
    ],
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: InboxPreferences(initialScopeId: initialScopeId),
      ),
    ),
  ),
);
Finder toggle(String id, String channel) =>
    find.byKey(ValueKey('notification-setting-$id-$channel'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'missing settings preserve notification defaults and explicit optout',
    () {
      expect(SharedNotificationSettings.fromJson({}).push, isTrue);
      expect(
        SharedNotificationSettings.fromJson({'push': false}).push,
        isFalse,
      );
      expect(
        const SharedNotificationSettings(
          sound: true,
        ).withChannel('push', false).sound,
        isTrue,
      );
      expect(sharedNotificationCategories, contains('ideas'));
    },
  );

  testWidgets(
    'bulk sound updates every category and scope without changing other channels',
    (tester) async {
      final controller = PreferencesController(preferencesState());
      final sdk = lifecycle.FakeSdk();
      await tester.pumpWidget(settingsHost(controller, sdk));
      await tester.pumpAndSettle();
      expect(controller.writes, isEmpty);
      expect(sdk.calls, isEmpty);
      await tester.tap(toggle('all', 'sound'));
      await tester.pumpAndSettle();
      expect(controller.writes, hasLength(14));
      expect(
        controller.writes.every(
          (w) =>
              w.settings.sound &&
              !w.settings.push &&
              w.settings.inApp &&
              !w.settings.email,
        ),
        isTrue,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxPreferences)),
      );
      expect(
        (await container.read(
          localNotificationPreferencesProvider.future,
        )).defaults.sound,
        isTrue,
      );
      expect(controller.state.requireValue.selectedSpaceId, sharingScopeId);
      expect(sdk.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scope push optout is available before device registration and affects one scope',
    (tester) async {
      final controller = PreferencesController(
        preferencesState(defaults: true),
      );
      final sdk = lifecycle.FakeSdk();
      await tester.pumpWidget(
        settingsHost(controller, sdk, initialScopeId: sharingScopeId),
      );
      await tester.pumpAndSettle();
      final target = toggle(sharingScopeId, 'push');
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(controller.writes, hasLength(7));
      expect(
        controller.writes.every(
          (w) => w.scopeId == sharingScopeId && !w.settings.push,
        ),
        isTrue,
      );
      expect(sdk.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'device optin leaves stored category optouts and local settings unchanged',
    (tester) async {
      final controller = PreferencesController(preferencesState());
      final sdk = lifecycle.FakeSdk();
      await tester.pumpWidget(settingsHost(controller, sdk));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dostava na tej napravi'));
      await tester.tap(find.text('Dostava na tej napravi'));
      await tester.pumpAndSettle();
      final target = find.descendant(
        of: find.byType(RemotePushDeviceSettings),
        matching: find.byType(SwitchListTile),
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(controller.registered, 1);
      expect(controller.writes, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(LocalNotificationPreferencesController.storageKey),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'one page fits $width at $scale text scale without changing selection or settings',
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
            settingsHost(
              controller,
              sdk,
              initialScopeId: secondScopeId,
              textScale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<CheckboxListTile>(toggle('all', 'push')).value,
            isNull,
          );
          await tester.ensureVisible(toggle(secondScopeId, 'sound'));
          expect(controller.writes, isEmpty);
          expect(controller.state.requireValue.selectedSpaceId, secondScopeId);
          expect(sdk.calls, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'late save after account switch cannot apply device settings or show errors to new account',
    (tester) async {
      final controller = PreferencesController(preferencesState());
      final sdk = lifecycle.FakeSdk();
      final gate = Completer<void>();
      controller.saveGate = gate;
      await tester.pumpWidget(settingsHost(controller, sdk));
      await tester.pumpAndSettle();
      await tester.tap(toggle('all', 'sound'));
      await tester.pump();
      controller.replace(preferencesState(secondAccount: true));
      gate.completeError(const CollaborationException('session_changed'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(LocalNotificationPreferencesController.storageKey),
        isNull,
      );
      expect(sdk.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scope push optin also registers the device and overrides the old local master optout',
    (tester) async {
      final controller = PreferencesController(preferencesState());
      final sdk = lifecycle.FakeSdk();
      await tester.pumpWidget(
        settingsHost(controller, sdk, initialScopeId: sharingScopeId),
      );
      await tester.pumpAndSettle();
      final target = toggle(sharingScopeId, 'push');
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(controller.registered, 1);
      expect(controller.writes.every((w) => w.settings.push), isTrue);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(InboxPreferences)),
      );
      final policy = await c.read(localNotificationPreferencesProvider.future);
      expect(policy.defaults.push, isFalse);
      expect(
        policy
            .resolve(
              sharedDeviceNotificationWorkspace(
                sharingSession().partition,
                sharingScopeId,
              ),
            )
            .push,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
