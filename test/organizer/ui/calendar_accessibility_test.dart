import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/organizer_widgets.dart';

import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scene in [
      (320.0, 2.0),
      (360.0, 1.0),
      (390.0, 1.0),
      (800.0, 1.0),
      (800.0, 2.0),
    ]) {
      testWidgets(
        'calendar dates/agenda remain accessible at $scene on $platform',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.platformDispatcher.textScaleFactorTestValue = scene.$2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final now = DateTime.now();
          final last = DateTime(now.year, now.month + 1, 0);
          final date = DateTime(last.year, last.month, last.day, 14, 30);
          final storage = MemoryOrganizerStorage();
          storage.snapshot = OrganizerSnapshot(
            events: [
              LocalEvent(
                id: 'last-day',
                title: 'Dogodek zadnji dan meseca',
                notes: '',
                startsAt: date,
                endsAt: null,
                projectId: null,
                createdAt: now,
                updatedAt: now,
              ),
            ],
          );
          await pumpOrganizer(tester, storage, width: scene.$1, height: 1000);
          await mobileTab(tester, 'Koledar');
          expect(tester.takeException(), isNull);
          final picker = find.byKey(const ValueKey('calendar-date-selection'));
          final context = tester.element(find.byType(OrganizerHeading).last);
          final label = organizerDate(context, date, full: true);
          final l = AppLocalizations.of(context)!;
          if (scene.$1 >= 360 && scene.$2 == 1) {
            expect(picker, findsNothing);
            final day = find.bySemanticsLabel(RegExp(RegExp.escape(label)));
            expect(day, findsOneWidget);
            final node = tester.getSemantics(day);
            expect(node.flagsCollection.isButton, isTrue);
            expect(node.label, contains(label));
            expect(node.label, contains(l.organizerCalendarScheduledCount(1)));
            expect(tester.getSize(day).width, greaterThanOrEqualTo(48));
            expect(tester.getSize(day).height, greaterThanOrEqualTo(48));
            await tester.ensureVisible(day);
            await tester.tap(day);
          } else {
            expect(picker, findsOneWidget);
            final widget = tester.widget<DropdownButton<DateTime>>(picker);
            expect(widget.items!.length, last.day);
            expect(tester.getSize(picker).height, greaterThanOrEqualTo(48));
            await tester.ensureVisible(picker);
            await tester.tap(picker);
            await tester.pumpAndSettle();
            final option = find.text(label);
            await tester.scrollUntilVisible(
              option,
              300,
              scrollable: find.byType(Scrollable).last,
              maxScrolls: 50,
            );
            await tester.pumpAndSettle();
            await tester.tap(option);
          }
          await tester.pumpAndSettle();
          expect(find.text('Dogodek zadnji dan meseca'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byTooltip(l.organizerUpcoming));
          await tester.tap(find.byTooltip(l.organizerUpcoming));
          await tester.pumpAndSettle();
          expect(find.text(l.organizerUpcoming), findsOneWidget);
          final next = find.byTooltip(
            MaterialLocalizations.of(context).nextMonthTooltip,
          );
          await tester.ensureVisible(next);
          await tester.tap(next);
          await tester.pumpAndSettle();
          if (picker.evaluate().isNotEmpty) {
            final nextPicker = tester.widget<DropdownButton<DateTime>>(picker);
            expect(nextPicker.value, isNull);
            expect(
              nextPicker.items!.first.value,
              DateTime(now.year, now.month + 1),
            );
          }
          expect(storage.writes, 0);
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
