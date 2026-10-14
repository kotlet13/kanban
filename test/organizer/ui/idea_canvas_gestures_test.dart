import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/presentation/ideas/idea_canvas.dart';

class GestureBoard extends StatefulWidget {
  const GestureBoard({super.key, this.editable = true});
  final bool editable;
  @override
  State<GestureBoard> createState() => GestureBoardState();
}

class GestureBoardState extends State<GestureBoard> {
  IdeaTool tool = IdeaTool.pan;
  bool visible = true;
  int writes = 0;
  late bool editable = widget.editable;
  String? selected;
  IdeaBoard board = IdeaBoard(
    id: '11111111-1111-4111-8111-111111111111',
    title: 'Gesture board',
    createdAt: DateTime.utc(2026, 10, 12),
    updatedAt: DateTime.utc(2026, 10, 12),
  );
  void seed(IdeaElement element, IdeaTool value) => setState(() {
    board = board.copyWith(elements: [element]);
    selected = element.id;
    tool = value;
  });
  void use(IdeaTool value) => setState(() => tool = value);
  void changeAccess(bool value) => setState(() => editable = value);
  void show(bool value) => setState(() => visible = value);
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        SizedBox(height: 48, child: Text(tool.name)),
        Expanded(
          child: visible
              ? IdeaCanvas(
                  board: board,
                  images: const {},
                  editable: editable,
                  selectedId: selected,
                  tool: tool,
                  onSelected: (value) => setState(() => selected = value),
                  onChanged: (value) => setState(() {
                    board = value;
                    writes++;
                  }),
                )
              : const SizedBox.shrink(),
        ),
      ],
    ),
  );
}

Matrix4 transform(WidgetTester tester) => Matrix4.copy(
  tester
      .widget<InteractiveViewer>(find.byKey(const ValueKey('idea-viewport')))
      .transformationController!
      .value,
);
Offset boardPoint(WidgetTester tester, Offset point) =>
    tester.getTopLeft(find.byKey(const ValueKey('idea-viewport'))) +
    MatrixUtils.transformPoint(transform(tester), point);
Future<void> pan(
  WidgetTester tester,
  Offset start,
  Offset delta, {
  int pointer = 1,
}) async {
  final gesture = await tester.startGesture(start, pointer: pointer);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveBy(delta / 2);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveBy(delta / 2);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> pinch(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(const ValueKey('idea-viewport')));
  final center = boardPoint(tester, const Offset(800, 600));
  expect(rect.contains(center - const Offset(45, 0)), true);
  expect(rect.contains(center + const Offset(45, 0)), true);
  final first = await tester.startGesture(
    center - const Offset(45, 0),
    pointer: 5,
  );
  final second = await tester.startGesture(
    center + const Offset(45, 0),
    pointer: 6,
  );
  await tester.pump(const Duration(milliseconds: 16));
  await first.moveBy(const Offset(-30, -10));
  await second.moveBy(const Offset(30, 10));
  await tester.pump(const Duration(milliseconds: 16));
  await first.moveBy(const Offset(-15, -5));
  await second.moveBy(const Offset(15, 5));
  await tester.pump(const Duration(milliseconds: 16));
  // Lifting one pointer must leave a usable one-finger pan recognizer.
  await second.up();
  await tester.pump(const Duration(milliseconds: 16));
  await first.moveBy(const Offset(25, 20));
  await tester.pump(const Duration(milliseconds: 16));
  await first.up();
  await tester.pumpAndSettle();
}

Future<GestureBoardState> open(
  WidgetTester tester, {
  double width = 360,
  bool editable = true,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('sl'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GestureBoard(editable: editable),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<GestureBoardState>(find.byType(GestureBoard));
}

void main() {
  for (final width in [360.0, 800.0, 1280.0]) {
    testWidgets(
      'hand recognizer survives draw/select, pinch lift and reentry at $width',
      (tester) async {
        final state = await open(tester, width: width);
        final initial = transform(tester);
        await pan(
          tester,
          boardPoint(tester, const Offset(300, 200)),
          const Offset(30, 25),
        );
        expect(transform(tester).storage, isNot(initial.storage));
        expect(state.writes, 0);
        state.use(IdeaTool.pen);
        await tester.pumpAndSettle();
        final drawingViewport = transform(tester);
        await pan(
          tester,
          boardPoint(tester, const Offset(180, 150)),
          const Offset(90, 60),
        );
        expect(state.board.elements.single.kind, IdeaElementKind.stroke);
        expect(state.writes, 1);
        expect(transform(tester).storage, drawingViewport.storage);
        state.use(IdeaTool.select);
        await tester.pumpAndSettle();
        final e = state.board.elements.single;
        await pan(
          tester,
          boardPoint(tester, Offset(e.x, e.y)),
          const Offset(35, 25),
        );
        expect(state.writes, 2);
        expect(state.selected, isNotNull);
        state.use(IdeaTool.pan);
        await tester.pumpAndSettle();
        final serialized = jsonEncode(state.board.toJson());
        final beforePan = transform(tester);
        final selected = state.board.elements.single;
        await pan(
          tester,
          boardPoint(
            tester,
            Offset(
              selected.x + selected.width / 2,
              selected.y + selected.height / 2,
            ),
          ),
          const Offset(-45, -30),
        );
        expect(transform(tester).storage, isNot(beforePan.storage));
        final beforePinch = transform(tester).entry(0, 0);
        await pinch(tester);
        expect(transform(tester).entry(0, 0), greaterThan(beforePinch * 1.3));
        final afterPinch = transform(tester);
        await pan(
          tester,
          tester.getRect(find.byKey(const ValueKey('idea-viewport'))).center,
          const Offset(30, 30),
        );
        expect(transform(tester).storage, isNot(afterPinch.storage));
        expect(jsonEncode(state.board.toJson()), serialized);
        expect(state.writes, 2);
        state.show(false);
        await tester.pumpAndSettle();
        state.show(true);
        await tester.pumpAndSettle();
        final reopened = transform(tester);
        await pinch(tester);
        expect(
          transform(tester).entry(0, 0),
          greaterThan(reopened.entry(0, 0) * 1.3),
        );
        final reopenedPinch = transform(tester);
        await pan(
          tester,
          tester.getRect(find.byKey(const ValueKey('idea-viewport'))).center,
          const Offset(-35, -25),
        );
        expect(transform(tester).storage, isNot(reopenedPinch.storage));
        expect(jsonEncode(state.board.toJson()), serialized);
        expect(state.writes, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final tool in [IdeaTool.select, IdeaTool.pen, IdeaTool.eraser]) {
    testWidgets('two fingers zoom with $tool selected without content edits', (
      tester,
    ) async {
      final state = await open(tester);
      final text = IdeaElement(
        id: '22222222-2222-4222-8222-222222222222',
        kind: IdeaElementKind.text,
        x: 650,
        y: 450,
        width: 300,
        height: 200,
        text: 'Selected text',
        fontSize: 44,
      );
      state.seed(text, tool);
      await tester.pumpAndSettle();
      final before = jsonEncode(state.board.toJson());
      final scale = transform(tester).entry(0, 0);
      await pinch(tester);
      expect(transform(tester).entry(0, 0), greaterThan(scale * 1.3));
      expect(jsonEncode(state.board.toJson()), before);
      expect(state.writes, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'second finger cancels unfinished stroke then single finger draws again',
    (tester) async {
      final state = await open(tester);
      state.use(IdeaTool.pen);
      await tester.pumpAndSettle();
      final center = boardPoint(tester, const Offset(800, 600));
      final first = await tester.startGesture(
        center - const Offset(45, 0),
        pointer: 7,
      );
      await first.moveBy(const Offset(20, 10));
      await tester.pump();
      final second = await tester.startGesture(
        center + const Offset(45, 0),
        pointer: 8,
      );
      await first.moveBy(const Offset(-35, -10));
      await second.moveBy(const Offset(35, 10));
      await tester.pump();
      await second.up();
      await first.up();
      await tester.pumpAndSettle();
      expect(state.board.elements, isEmpty);
      expect(state.writes, 0);
      await pan(
        tester,
        tester.getRect(find.byKey(const ValueKey('idea-viewport'))).center,
        const Offset(60, 30),
      );
      expect(state.board.elements.single.kind, IdeaElementKind.stroke);
      expect(state.writes, 1);
    },
  );
  testWidgets(
    'read-only canvas pans and pinches without board or selection writes',
    (tester) async {
      final state = await open(tester, editable: false);
      final before = transform(tester);
      await pan(
        tester,
        boardPoint(tester, const Offset(300, 200)),
        const Offset(-30, -25),
      );
      expect(transform(tester).storage, isNot(before.storage));
      final scale = transform(tester).entry(0, 0);
      await pinch(tester);
      expect(transform(tester).entry(0, 0), greaterThan(scale * 1.3));
      expect(state.writes, 0);
      expect(state.selected, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching to hand during a stroke cancels the edit and releases future pan/pinch',
    (tester) async {
      final state = await open(tester);
      state.use(IdeaTool.pen);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        boardPoint(tester, const Offset(200, 200)),
      );
      await gesture.moveBy(const Offset(90, 60));
      await tester.pump();
      state.use(IdeaTool.pan);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(state.board.elements, isEmpty);
      expect(state.writes, 0);
      final before = transform(tester);
      await pan(
        tester,
        boardPoint(tester, const Offset(300, 200)),
        const Offset(30, 25),
      );
      expect(transform(tester).storage, isNot(before.storage));
      await pinch(tester);
      expect(state.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'losing edit access during a stroke discards preview and keeps read-only viewport usable',
    (tester) async {
      final state = await open(tester);
      state.use(IdeaTool.pen);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        boardPoint(tester, const Offset(200, 200)),
      );
      await gesture.moveBy(const Offset(90, 60));
      await tester.pump();
      state.changeAccess(false);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(state.board.elements, isEmpty);
      expect(state.writes, 0);
      final before = transform(tester);
      await pan(
        tester,
        boardPoint(tester, const Offset(300, 200)),
        const Offset(30, 25),
      );
      expect(transform(tester).storage, isNot(before.storage));
      await pinch(tester);
      expect(state.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
