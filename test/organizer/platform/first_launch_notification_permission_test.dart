import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/organizer/data/local_vault_preferences.dart';
import 'package:kanban/organizer/platform/first_launch_notification_permission.dart';
import 'package:kanban/organizer/platform/local_notification_adapter.dart';
import 'package:kanban/organizer/platform/local_notification_scheduler.dart';
import 'package:kanban/organizer/platform/notification_providers.dart';

import 'local_notification_adapter_test.dart' show FakeScheduler;

void main() {
  void mobileTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<(SharedPreferences, LocalNotificationAdapter, FakeScheduler)> setup(
    LocalNotificationPermission permission,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final scheduler = FakeScheduler()..permission = permission;
    final adapter = LocalNotificationAdapter(
      scheduler: scheduler,
      preferences: LegacyLocalVaultPreferences(prefs),
    );
    await adapter.initialize((_) {});
    return (prefs, adapter, scheduler);
  }

  Widget app(
    SharedPreferences prefs,
    Future<LocalNotificationAdapter> adapter,
  ) => ProviderScope(
    overrides: [
      notificationPromptPreferencesProvider.overrideWith((ref) async => prefs),
      localNotificationAdapterProvider.overrideWith((ref) => adapter),
    ],
    child: const MaterialApp(
      home: FirstLaunchNotificationPermission(child: Text('Utrip')),
    ),
  );

  mobileTest('first mobile launch prompts once; denial survives app remount', (
    tester,
  ) async {
    final (prefs, adapter, scheduler) = await setup(
      LocalNotificationPermission.denied,
    );
    await tester.pumpWidget(app(prefs, Future.value(adapter)));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 1);
    expect(find.text('Utrip'), findsOneWidget);
    expect(prefs.getBool(FirstLaunchNotificationPermission.attemptedKey), true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(prefs, Future.value(adapter)));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 1);
    expect(tester.takeException(), isNull);
  });

  mobileTest('already granted permission does not request again', (
    tester,
  ) async {
    final (prefs, adapter, scheduler) = await setup(
      LocalNotificationPermission.granted,
    );
    await tester.pumpWidget(app(prefs, Future.value(adapter)));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 0);
    expect(prefs.getBool(FirstLaunchNotificationPermission.attemptedKey), true);
  });

  mobileTest('background initialization defers prompt until resumed', (
    tester,
  ) async {
    final (prefs, adapter, scheduler) = await setup(
      LocalNotificationPermission.denied,
    );
    final ready = Completer<LocalNotificationAdapter>();
    await tester.pumpWidget(app(prefs, ready.future));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    ready.complete(adapter);
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 0);
    expect(
      prefs.getBool(FirstLaunchNotificationPermission.attemptedKey),
      isNull,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 1);
  });

  mobileTest('permission plugin error does not block app or repeat on resume', (
    tester,
  ) async {
    final (prefs, adapter, _) = await setup(LocalNotificationPermission.denied);
    final broken = _BrokenAdapter(adapter);
    await tester.pumpWidget(app(prefs, Future.value(broken)));
    await tester.pumpAndSettle();
    expect(find.text('Utrip'), findsOneWidget);
    expect(broken.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(broken.calls, 1);
    expect(tester.takeException(), isNull);
  });

  mobileTest('iOS uses the same first-launch request', (tester) async {
    final (prefs, adapter, scheduler) = await setup(
      LocalNotificationPermission.unknown,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(app(prefs, Future.value(adapter)));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 1);
  });

  mobileTest('desktop does not claim mobile first-launch prompt', (
    tester,
  ) async {
    final (prefs, adapter, scheduler) = await setup(
      LocalNotificationPermission.denied,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(app(prefs, Future.value(adapter)));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 0);
    expect(
      prefs.getBool(FirstLaunchNotificationPermission.attemptedKey),
      isNull,
    );
  });
}

class _BrokenAdapter extends LocalNotificationAdapter {
  _BrokenAdapter(LocalNotificationAdapter source)
    : super(scheduler: source.scheduler, preferences: source.preferences);
  int calls = 0;
  @override
  Future<LocalNotificationPermission> requestPermission() async {
    calls++;
    throw StateError('OS request failed');
  }
}
