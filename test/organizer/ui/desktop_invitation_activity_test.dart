import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/state/application_sync_activity.dart';

import 'invitation_approval_notification_test.dart'
    show coordinator, shared, event;
import 'sharing_ui_fixture.dart';

void main() {
  test(
    'visible desktop participates; hidden mobile and unfocused web do not',
    () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(
          collaborationAppActive(
            AppLifecycleState.inactive,
            platform: platform,
            isWeb: false,
          ),
          isTrue,
        );
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.detached,
          AppLifecycleState.paused,
        ]) {
          expect(
            collaborationAppActive(state, platform: platform, isWeb: false),
            isFalse,
          );
        }
      }
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        expect(
          collaborationAppActive(
            AppLifecycleState.inactive,
            platform: platform,
            isWeb: false,
          ),
          isFalse,
        );
        expect(
          collaborationAppActive(
            AppLifecycleState.resumed,
            platform: platform,
            isWeb: false,
          ),
          isTrue,
        );
      }
      expect(
        collaborationAppActive(
          AppLifecycleState.inactive,
          platform: TargetPlatform.macOS,
          isWeb: true,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'visible unfocused Mac accepts new hint once without focus churn',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final controller = SharingUiController(initial: shared());
      var calls = 0;
      await tester.pumpWidget(
        coordinator(controller, (current, ids) async {
          expect(current(), isTrue);
          calls++;
        }),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      controller.replace(shared(inbox: [event(1)]));
      await tester.pumpAndSettle();
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('hiding Mac invalidates a running automatic approval guard', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final gate = Completer<void>();
    bool Function()? guard;
    await tester.pumpWidget(
      coordinator(SharingUiController(initial: shared()), (current, ids) async {
        guard = current;
        await gate.future;
      }),
    );
    await tester.pump();
    expect(guard, isNotNull);
    expect(guard!(), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(guard!(), isFalse);
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
