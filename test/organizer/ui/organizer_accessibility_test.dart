import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/editor_actions.dart';
import 'package:kanban/organizer/presentation/organizer_widgets.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 320,
  double scale = 2,
  TargetPlatform platform = TargetPlatform.android,
  String language = 'sl',
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        platform: platform,
        visualDensity: VisualDensity.compact,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

LocalTask _task() => LocalTask(
  id: 'task',
  title: 'Pripravi skupni vrt',
  notes: '',
  projectId: null,
  dueAt: null,
  isCompleted: false,
  createdAt: DateTime.utc(2026, 10, 12),
  updatedAt: DateTime.utc(2026, 10, 12),
);

LocalEvent _event() => LocalEvent(
  id: 'event',
  title: 'Dogovor o načrtovanih opravilih in skupnem vrtu',
  notes: 'Dolg opis dogodka, ki ostane dostopen v podrobnostih dogodka.',
  startsAt: DateTime(2026, 10, 12, 14, 30),
  endsAt: null,
  projectId: null,
  createdAt: DateTime.utc(2026, 10, 12),
  updatedAt: DateTime.utc(2026, 10, 12),
);

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('named task controls and heading semantics on $platform', (
      tester,
    ) async {
      var edited = 0;
      bool? completed;
      await _pump(
        tester,
        Column(
          children: [
            const OrganizerHeading(title: 'Planer'),
            OrganizerSection(
              title: 'Opravila',
              child: OrganizerTaskRow(
                task: _task(),
                snapshot: OrganizerSnapshot(),
                onEdit: () => edited++,
                onCompleted: (value) => completed = value,
              ),
            ),
          ],
        ),
        platform: platform,
      );
      final checkbox = tester.getSemantics(find.byType(Checkbox));
      expect(checkbox.label, _task().title);
      expect(checkbox.flagsCollection.isChecked, CheckedState.isFalse);
      expect(tester.getSize(find.byType(Checkbox)), const Size(48, 48));
      expect(
        tester.getSemantics(find.text('Planer')).flagsCollection.isHeader,
        isTrue,
      );
      expect(
        tester.getSemantics(find.text('Opravila')).flagsCollection.isHeader,
        isTrue,
      );
      expect(
        tester.getSemantics(find.text(_task().title)).flagsCollection.isButton,
        isTrue,
      );
      await tester.tap(find.byType(Checkbox));
      expect(completed, isTrue);
      expect(edited, 0);
      await tester.tap(find.text(_task().title));
      expect(edited, 1);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 360.0]) {
      testWidgets(
        'large event text wraps with separate time at $width on $platform',
        (tester) async {
          var opened = 0;
          await _pump(
            tester,
            OrganizerEventCard(event: _event(), onTap: () => opened++),
            width: width,
            platform: platform,
          );
          expect(tester.takeException(), isNull);
          final time = find.text('14:30');
          expect(time, findsOneWidget);
          expect(
            tester.getRect(time).bottom,
            lessThan(tester.getRect(find.text(_event().title)).top),
          );
          expect(
            tester
                .getSemantics(find.text(_event().title))
                .flagsCollection
                .isButton,
            isTrue,
          );
          await tester.tap(find.text(_event().title));
          expect(opened, 1);
        },
      );
    }

    for (final language in ['sl', 'en']) {
      testWidgets(
        'CRUD remains horizontal with 2x text and keyboard on $platform/$language',
        (tester) async {
          var cancelled = 0, saved = 0, deleted = 0;
          await _pump(
            tester,
            EditorActionsRow(
              onCancel: () => cancelled++,
              onSave: () => saved++,
              onDelete: () => deleted++,
            ),
            platform: platform,
            language: language,
          );
          final context = tester.element(find.byType(EditorActionsRow));
          final l = AppLocalizations.of(context)!;
          final controls = [
            find.byTooltip(l.delete),
            find.widgetWithText(TextButton, l.cancel),
            find.byTooltip(l.save),
          ];
          final rects = controls.map(tester.getRect).toList();
          for (final rect in rects) {
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.center.dy, rects.first.center.dy);
          }
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(deleted, 1);
          expect(cancelled, 0);
          expect(saved, 0);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(cancelled, 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(saved, 1);
        },
      );
    }
  }
}
