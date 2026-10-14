import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/inbox/inbox_preferences.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'organizer_ui_test.dart';
import 'sharing_ui_fixture.dart';

void main() {
  testWidgets('settings keep scroll and expansion during organizer reload', (
    tester,
  ) async {
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      collaborationController: SharingUiController(),
    );
    await mobileTab(tester, 'Nastavitve opomnikov');
    await tester.pumpAndSettle();
    final preferences = find.byType(InboxPreferences);
    final container = ProviderScope.containerOf(tester.element(preferences));
    final scroller = find
        .ancestor(of: preferences, matching: find.byType(SingleChildScrollView))
        .first;
    final scrollable = find
        .descendant(of: scroller, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final local = find.byKey(const ValueKey('notification-local-space-local'));
    await tester.ensureVisible(local);
    await tester.tap(local);
    await tester.pumpAndSettle();
    position.jumpTo(position.maxScrollExtent.clamp(0, 300));
    await tester.pump();
    final offset = position.pixels;
    final controller = container.read(organizerProvider.notifier);
    final snapshot = container.read(organizerProvider).requireValue;
    for (var i = 0; i < 3; i++) {
      // Exercise a dependency reload, which previously removed the whole page.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      controller.state = const AsyncLoading<OrganizerSnapshot>()
          .copyWithPrevious(AsyncData(snapshot), isRefresh: false);
      await tester.pump();
      expect(preferences, findsOneWidget);
      expect(position.pixels, offset);
      expect(
        find.byKey(const ValueKey('notification-setting-local-5:local:-push')),
        findsOneWidget,
      );
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      controller.state = AsyncData(snapshot);
      await tester.pump();
      expect(position.pixels, offset);
    }
    expect(tester.takeException(), isNull);
  });
}
