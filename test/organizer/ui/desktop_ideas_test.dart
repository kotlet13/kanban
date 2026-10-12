import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/ideas/idea_editor.dart';

import 'ideas_ui_test.dart'
    show fixture, pumpIdeas, settle, tapTool, draw, current, close;

void main() {
  testWidgets(
    'desktop Ideas wraps tools beside full-height canvas, preserves pan and draft across resize',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final f = await fixture(tester);
      await pumpIdeas(tester, f, width: 1280);
      await tester.tap(find.byKey(const ValueKey('idea-add')));
      await settle(tester);
      final workspace = find.byKey(const ValueKey('idea-desktop-workspace'));
      final viewport = find.byKey(const ValueKey('idea-viewport'));
      expect(workspace, findsOneWidget);
      expect(tester.getRect(viewport).left, greaterThanOrEqualTo(320));
      expect(tester.getRect(viewport).height, greaterThan(780));
      expect(
        find.byKey(const ValueKey('idea-tool-ellipse')).hitTestable(),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('idea-title')),
        'Desktop canvas draft',
      );
      tester.testTextInput.hide();
      await tapTool(tester, 'Pisalo');
      await draw(tester, const Offset(80, 80), const Offset(480, 310));
      final board = current(tester);
      expect(board.elements, hasLength(1));
      expect(f.ideas.snapshot.boards, isEmpty);
      await tapTool(tester, 'Razveljavi');
      expect(current(tester).elements, isEmpty);
      await tapTool(tester, 'Uveljavi');
      expect(current(tester).elements.single.id, board.elements.single.id);
      await tester.tap(find.byKey(const ValueKey('idea-tool-pan')));
      await settle(tester);
      final viewer = tester.widget<InteractiveViewer>(viewport);
      final beforePan = viewer.transformationController!.value.clone();
      final gesture = await tester.startGesture(tester.getCenter(viewport));
      await gesture.moveBy(const Offset(90, 50));
      await tester.pump();
      await gesture.up();
      await settle(tester);
      final panned = viewer.transformationController!.value.clone();
      expect(listEquals(beforePan.storage, panned.storage), isFalse);
      tester.view.physicalSize = const Size(680, 900);
      await settle(tester);
      expect(workspace, findsNothing);
      expect(current(tester).id, board.id);
      expect(current(tester).elements.single.id, board.elements.single.id);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('idea-title')))
            .controller!
            .text,
        'Desktop canvas draft',
      );
      expect(
        tester
            .widget<InteractiveViewer>(viewport)
            .transformationController!
            .value
            .storage,
        orderedEquals(panned.storage),
      );
      tester.view.physicalSize = const Size(1280, 900);
      await settle(tester);
      expect(workspace, findsOneWidget);
      expect(
        tester
            .widget<InteractiveViewer>(viewport)
            .transformationController!
            .value
            .storage,
        orderedEquals(panned.storage),
      );
      await tester.tap(find.byKey(const ValueKey('idea-save')));
      await settle(tester);
      expect(find.byType(IdeaEditor), findsNothing);
      expect(f.ideas.snapshot.boards.single.title, 'Desktop canvas draft');
      expect(
        f.ideas.snapshot.boards.single.elements.single.id,
        board.elements.single.id,
      );
      expect(tester.takeException(), isNull);
      await close(tester, f);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'desktop Ideas Cancel keeps private draft without publishing and resumes it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final f = await fixture(tester);
      await pumpIdeas(tester, f, width: 1280, textScale: 2);
      await tester.tap(find.byKey(const ValueKey('idea-add')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('idea-title')),
        'Unpublished desktop draft',
      );
      tester.testTextInput.hide();
      final id = current(tester).id;
      expect(
        find.byKey(const ValueKey('idea-save')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Zapri'));
      await settle(tester);
      expect(f.ideas.snapshot.boards, isEmpty);
      await tester.tap(find.byKey(ValueKey('idea-draft-$id')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('idea-desktop-workspace')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('idea-title')))
            .controller!
            .text,
        'Unpublished desktop draft',
      );
      expect(tester.takeException(), isNull);
      await close(tester, f);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('wide Android Ideas keeps mobile canvas toolbar arrangement', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final f = await fixture(tester);
    await pumpIdeas(tester, f, width: 1280);
    await tester.tap(find.byKey(const ValueKey('idea-add')));
    await settle(tester);
    expect(find.byKey(const ValueKey('idea-desktop-workspace')), findsNothing);
    expect(tester.getRect(find.byKey(const ValueKey('idea-viewport'))).left, 0);
    expect(tester.takeException(), isNull);
    await close(tester, f);
    debugDefaultTargetPlatformOverride = null;
  });
}
