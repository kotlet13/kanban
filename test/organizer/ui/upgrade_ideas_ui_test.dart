import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/presentation/ideas/idea_editor.dart';
import 'ideas_ui_test.dart' as ideas;
import 'package:kanban/organizer/presentation/inbox/local_task_reminder_editor.dart';

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(ideas.captureKey),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  image.dispose();
  await tester.runAsync(() async {
    final file = File('build/qa/upgrade-ideas/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
  });
}

void main() {
  testWidgets(
    'device-only task exposes deadline options and stores offset without changing task date',
    (tester) async {
      final f = await ideas.fixture(tester);
      await tester.runAsync(
        () => f.organizer.createTask(
          title: 'Local task',
          dueAt: DateTime.utc(2026, 10, 20, 12),
        ),
      );
      final task = f.organizer.snapshot.tasks.single;
      await ideas.pumpIdeas(
        tester,
        f,
        width: 390,
        body: LocalTaskReminderButton(task: task, workspaceKey: 'local'),
      );
      await tester.tap(find.byKey(ValueKey('local-task-reminder-${task.id}')));
      await ideas.settle(tester);
      await capture(tester, 'local-relative-reminder-390');
      await tester.tap(find.text('1 uro pred rokom'));
      await ideas.settle(tester);
      final rows = (await tester.runAsync(
        () => f.db.rows(
          "SELECT value FROM local_meta WHERE name LIKE 'local_task_deadline_reminder:%'",
        ),
      ))!;
      expect(rows, hasLength(1));
      expect(rows.single['value'], contains('"offsetMinutes":60'));
      expect(f.organizer.snapshot.tasks.single.dueAt, task.dueAt);
      expect(tester.takeException(), isNull);
      await ideas.close(tester, f);
    },
  );

  testWidgets(
    'per-idea menu archives/restores and confirms delete, archive section starts collapsed',
    (tester) async {
      final f = await ideas.fixture(tester);
      await tester.runAsync(() => f.ideas.createBoard(title: 'My idea'));
      await ideas.pumpIdeas(tester, f, width: 390);
      final id = f.ideas.snapshot.boards.single.id;
      await tester.tap(find.byKey(ValueKey('idea-menu-$id')));
      await ideas.settle(tester);
      await capture(tester, 'idea-menu-390');
      await tester.tap(find.text('Arhiviraj'));
      await ideas.settle(tester);
      expect(f.ideas.snapshot.boards.single.archived, true);
      expect(find.byKey(ValueKey('idea-card-$id')), findsNothing);
      expect(find.text('Arhivirano'), findsOneWidget);
      await capture(tester, 'archived-collapsed-390');
      await tester.tap(find.text('Arhivirano'));
      await ideas.settle(tester);
      expect(find.byKey(ValueKey('idea-card-$id')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('idea-menu-$id')));
      await ideas.settle(tester);
      await tester.tap(find.text('Ponovno aktiviraj'));
      await ideas.settle(tester);
      expect(f.ideas.snapshot.boards.single.archived, false);
      await tester.tap(find.byKey(ValueKey('idea-menu-$id')));
      await ideas.settle(tester);
      await tester.tap(find.text('Izbriši'));
      await ideas.settle(tester);
      expect(f.ideas.snapshot.boards, hasLength(1));
      await tester.tap(find.text('Prekliči'));
      await ideas.settle(tester);
      expect(f.ideas.snapshot.boards, hasLength(1));
      await tester.tap(find.byKey(ValueKey('idea-menu-$id')));
      await ideas.settle(tester);
      await tester.tap(find.text('Izbriši'));
      await ideas.settle(tester);
      await tester.tap(find.text('Izbriši'));
      await ideas.settle(tester);
      expect(f.ideas.snapshot.boards, isEmpty);
      expect(tester.takeException(), isNull);
      await ideas.close(tester, f);
    },
  );
  testWidgets(
    'selected text has persisted font-size increase and undo, independent of viewport',
    (tester) async {
      final f = await ideas.fixture(tester);
      final text = IdeaElement(
        id: ideas.strokeId,
        kind: IdeaElementKind.text,
        x: 100,
        y: 100,
        width: 400,
        height: 200,
        text: 'Larger saved text',
      );
      await tester.runAsync(
        () => f.ideas.saveBoard(
          IdeaBoard(
            id: ideas.boardId,
            title: 'Text board',
            createdAt: ideas.now,
            updatedAt: ideas.now,
            elements: [text],
          ),
          isNew: true,
        ),
      );
      await ideas.pumpIdeas(tester, f, width: 390);
      await tester.tap(
        find.byKey(const ValueKey('idea-card-${ideas.boardId}')),
      );
      await ideas.settle(tester);
      await tester.tapAt(ideas.point(tester, const Offset(200, 150)));
      await ideas.settle(tester);
      final original = ideas.current(tester);
      await ideas.tapTool(tester, 'Povečaj besedilo');
      expect(
        ideas.current(tester).elements.single.fontSize,
        closeTo(26.4, .01),
      );
      expect(ideas.current(tester).elements.single.width, 400);
      expect(ideas.current(tester).elements.single.height, 200);
      expect(f.ideas.snapshot.boards.single.elements.single.fontSize, 22);
      await capture(tester, 'text-size-390');
      await ideas.tapTool(tester, 'Razveljavi');
      expect(ideas.current(tester).elements.single.fontSize, 22);
      await ideas.tapTool(tester, 'Uveljavi');
      await tester.tap(find.byKey(const ValueKey('idea-save')));
      await ideas.settle(tester);
      expect(find.byType(IdeaEditor), findsNothing);
      expect(
        f.ideas.snapshot.boards.single.elements.single.fontSize,
        closeTo(26.4, .01),
      );
      expect(f.ideas.snapshot.boards.single.version, 2);
      expect(original.elements.single.fontSize, 22);
      expect(tester.takeException(), isNull);
      await ideas.close(tester, f);
    },
  );
  testWidgets(
    'archived parent Idea stays readable without lifecycle or editor writes',
    (tester) async {
      final f = await ideas.fixture(tester);
      await tester.runAsync(() async {
        await f.organizer.createProject(title: 'Archived parent');
        final parent = f.organizer.snapshot.projects.single;
        await f.ideas.saveBoard(
          IdeaBoard(
            id: ideas.boardId,
            title: 'Preserved board',
            projectId: parent.id,
            createdAt: ideas.now,
            updatedAt: ideas.now,
          ),
          isNew: true,
        );
        await f.organizer.updateProject(parent.copyWith(archived: true));
      });
      await ideas.pumpIdeas(tester, f, width: 390);
      expect(
        find.byKey(const ValueKey('idea-menu-${ideas.boardId}')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('idea-card-${ideas.boardId}')),
      );
      await ideas.settle(tester);
      expect(find.byType(IdeaEditor), findsOneWidget);
      expect(find.byKey(const ValueKey('idea-save')), findsNothing);
      expect(f.ideas.snapshot.boards.single.title, 'Preserved board');
      expect(tester.takeException(), isNull);
      await ideas.close(tester, f);
    },
  );
}
