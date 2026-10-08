import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/organizer_editors.dart';

import 'organizer_ui_test.dart' show MemoryOrganizerStorage, pumpOrganizer;

Rect paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Finder get editorScroll =>
    find.byKey(const ValueKey('organizer-editor-scroll'));
Finder get saveButton => find.byKey(const ValueKey('organizer-save'));

void expectInside(Rect inner, Rect outer) {
  expect(inner.top, greaterThanOrEqualTo(outer.top - 0.1));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + 0.1));
}

Future<void> openEditor(
  WidgetTester tester, {
  required double width,
  required double scale,
  OrganizerEditorKind kind = OrganizerEditorKind.event,
  bool keyboard = true,
  Future<void> Function(OrganizerDraft)? onSave,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetViewInsets);
  await pumpOrganizer(
    tester,
    MemoryOrganizerStorage(),
    width: width,
    height: 780,
  );
  showOrganizerEditor(
    tester.element(find.byType(Scaffold).first),
    heading: 'Dodaj dogodek',
    kind: kind,
    draft: OrganizerDraft(date: DateTime(2026, 10, 8, 15), amount: '12.50'),
    onSave: onSave ?? (_) async {},
  );
  await tester.pumpAndSettle();
  if (keyboard) {
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final width in [320.0, 360.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'floating title and actions fit $width at scale $scale with keyboard',
        (tester) async {
          await openEditor(tester, width: width, scale: scale);
          final viewport = tester.getRect(editorScroll);
          final titleLabel = find.descendant(
            of: find.byKey(const ValueKey('organizer-title-field')),
            matching: find.text('Naslov'),
          );
          expectInside(paintedRect(tester, titleLabel), viewport);
          expect(
            tester.getRect(saveButton).top,
            greaterThanOrEqualTo(viewport.bottom),
          );
          expect(tester.getRect(saveButton).bottom, lessThan(780 - 340));
          expect(saveButton.hitTestable(), findsOneWidget);
          expect(
            find.widgetWithText(TextButton, 'Prekliči').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          // Expanding the schedule must still allow the last field to be reached.
          await tester.ensureVisible(find.text('Načrtovani termin'));
          await tester.tap(find.text('Načrtovani termin'));
          await tester.pumpAndSettle();
          final end = find.byKey(const ValueKey('task-end-date'));
          await tester.ensureVisible(end);
          await tester.pumpAndSettle();
          expectInside(tester.getRect(end), tester.getRect(editorScroll));
          expect(saveButton.hitTestable(), findsOneWidget);

          // Saving from the bottom reveals the invalid title and its error line.
          await tester.tap(saveButton);
          await tester.pumpAndSettle();
          expectInside(
            paintedRect(tester, titleLabel),
            tester.getRect(editorScroll),
          );
          expectInside(
            paintedRect(tester, find.text('Vpiši naslov.')),
            tester.getRect(editorScroll),
          );
          expect(tester.takeException(), isNull);

          await tester.enterText(
            find.byKey(const ValueKey('organizer-title-field')),
            'Dogodek z dolgim naslovom',
          );
          await tester.tap(saveButton);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        },
      );
    }
  }

  for (final kind in OrganizerEditorKind.values) {
    testWidgets(
      'all shared record editor kinds remain usable at 320px: ${kind.name}',
      (tester) async {
        OrganizerDraft? saved;
        await openEditor(
          tester,
          width: 320,
          scale: 2,
          kind: kind,
          onSave: (draft) async => saved = draft,
        );
        await tester.enterText(
          find.byKey(const ValueKey('organizer-title-field')),
          'Vnos',
        );
        await tester.tap(saveButton);
        await tester.pumpAndSettle();
        expect(saved?.title, 'Vnos');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'desktop keeps roomy editor and three-line notes without keyboard',
    (tester) async {
      await openEditor(tester, width: 1280, scale: 1, keyboard: false);
      expect(tester.getSize(editorScroll).width, 440);
      final notes = tester.widget<TextFormField>(
        find.byKey(const ValueKey('organizer-notes-field')),
      );
      // The editable child expresses the desktop line count after FormField build.
      final textField = tester.widget<TextField>(
        find.descendant(
          of: find.byWidget(notes),
          matching: find.byType(TextField),
        ),
      );
      expect(textField.minLines, 3);
      expect(textField.maxLines, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
