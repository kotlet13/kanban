import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/presentation/ideas/idea_canvas.dart';
import 'package:kanban/organizer/presentation/ideas/ideas_page.dart';

import 'ideas_ui_test.dart' as fixture;

Future<void> expectVisibleInk(
  WidgetTester tester,
  IdeaBoardPainter painter,
) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(300, 200));
  final picture = recorder.endRecording();
  final image = (await tester.runAsync(() => picture.toImage(300, 200)))!;
  final bytes = (await tester.runAsync(() => image.toByteData()))!;
  final background = painter.surface.computeLuminance();
  for (final top in [20, 110]) {
    var visiblePixels = 0;
    for (var y = top; y < top + 60; y++) {
      for (var x = 20; x < 270; x++) {
        final i = (y * 300 + x) * 4;
        final pixel = Color.fromARGB(
          255,
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        ).computeLuminance();
        final ratio =
            (math.max(pixel, background) + .05) /
            (math.min(pixel, background) + .05);
        if (ratio >= 4.5) visiblePixels++;
      }
    }
    expect(
      visiblePixels,
      greaterThan(100),
      reason:
          'Stored dark and white text must each retain a visible silhouette',
    );
  }
  image.dispose();
  picture.dispose();
}

IdeaBoard board() {
  final now = DateTime.utc(2026, 10, 23);
  return IdeaBoard(
    id: fixture.boardId,
    title: 'Contrast',
    width: 300,
    height: 200,
    createdAt: now,
    updatedAt: now,
    elements: [
      IdeaElement(
        id: fixture.strokeId,
        kind: IdeaElementKind.text,
        x: 10,
        y: 10,
        width: 280,
        height: 70,
        text: 'Default dark text',
      ),
      IdeaElement(
        id: fixture.imageId,
        kind: IdeaElementKind.text,
        x: 10,
        y: 100,
        width: 280,
        height: 70,
        color: 0xffffffff,
        text: 'Existing white text',
      ),
    ],
  );
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'render-only contrast halo preserves dark and legacy white text in editor/card dark=$dark',
      (tester) async {
        final f = await fixture.fixture(tester);
        final document = board();
        final original = document.toJson();
        await tester.runAsync(() => f.ideas.saveBoard(document, isNew: true));
        final paper = dark ? const Color(0xff22242a) : Colors.white;
        final theme = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: dark ? Brightness.dark : Brightness.light,
          ).copyWith(surface: paper),
        );
        for (final card in [false, true]) {
          await fixture.pumpIdeas(
            tester,
            f,
            width: 390,
            body: Theme(
              data: theme,
              child: card
                  ? const IdeasPage()
                  : SizedBox(
                      height: 400,
                      child: IdeaCanvas(
                        board: document,
                        onChanged: (_) {},
                        tool: IdeaTool.select,
                        images: const {},
                        editable: false,
                        onSelected: (_) {},
                      ),
                    ),
            ),
          );
          final paint = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<IdeaBoardPainter>()
              .single;
          expect(paint.surface, paper);
          expect(paint.elements.first.color, 0xff263238);
          expect(paint.elements.last.color, 0xffffffff);
          await expectVisibleInk(tester, paint);
          expect(tester.takeException(), isNull);
        }
        expect(document.toJson(), original);
        expect(f.ideas.snapshot.boards.single.elements.map((e) => e.color), [
          0xff263238,
          0xffffffff,
        ]);
        await fixture.close(tester, f);
      },
    );
  }
  testWidgets(
    'white export paper retains legacy white text through render-only halo',
    (tester) async {
      final document = board();
      final original = document.toJson();
      await expectVisibleInk(
        tester,
        IdeaBoardPainter(elements: document.elements, images: const {}),
      );
      expect(document.toJson(), original);
    },
  );
}
