import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/editor_actions.dart';
import 'package:kanban/organizer/presentation/organizer_editors.dart';
import 'package:kanban/organizer/presentation/shared/sharing_forms.dart';
import 'all_spaces_ui_test.dart' show loadQaFonts;

final captureKey = GlobalKey();
Future<BuildContext> host(
  WidgetTester tester, {
  double width = 360,
  double scale = 1,
  String language = 'sl',
  bool keyboard = false,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadQaFonts(tester);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2865b3)),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard ? 220 : 0),
          ),
          child: child!,
        ),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.element(find.byType(Scaffold));
}

Finder get save => find.byKey(const ValueKey('organizer-save'));
void sameRow(WidgetTester tester, Iterable<Finder> finders) {
  final rects = finders.map(tester.getRect).toList();
  for (final rect in rects) {
    expect(rect.height, greaterThanOrEqualTo(48));
    expect((rect.center.dy - rects.first.center.dy).abs(), lessThan(0.5));
  }
  expect(rects.last.width, greaterThanOrEqualTo(48));
}

void main() {
  for (final scene in [
    (360.0, 1.0, 'sl', false),
    (320.0, 2.0, 'sl', true),
    (800.0, 1.0, 'en', false),
    (1280.0, 1.0, 'sl', false),
  ]) {
    testWidgets(
      'report sits beside title, CRUD footer stays one row ${scene.$1}/${scene.$2}/${scene.$3}',
      (tester) async {
        final context = await host(
          tester,
          width: scene.$1,
          scale: scene.$2,
          language: scene.$3,
          keyboard: scene.$4,
        );
        var reports = 0, saved = 0;
        showOrganizerEditor(
          context,
          heading: scene.$3 == 'sl' ? 'Uredi opravilo' : 'Edit task',
          kind: OrganizerEditorKind.task,
          draft: OrganizerDraft(title: 'Opravilo za skupni vrt'),
          onSave: (_) async {
            saved++;
          },
          onDelete: () async {},
          onReport: () async {
            reports++;
          },
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(tester.element(save))!;
        final report = find.byKey(const ValueKey('editor-report'));
        final heading = find.text(
          scene.$3 == 'sl' ? 'Uredi opravilo' : 'Edit task',
        );
        expect(
          tester.getRect(report).left,
          greaterThan(tester.getRect(heading).right),
        );
        expect(
          tester.getRect(report).bottom,
          lessThan(
            tester
                .getRect(find.byKey(const ValueKey('organizer-editor-scroll')))
                .top,
          ),
        );
        expect(find.text(l.save), findsNothing);
        expect(find.byTooltip(l.save), findsOneWidget);
        sameRow(tester, [
          find.byTooltip(l.delete),
          find.widgetWithText(TextButton, l.cancel),
          save,
        ]);
        final row = tester.getRect(
          find.byKey(const ValueKey('editor-actions-row')),
        );
        expect(row.bottom, lessThanOrEqualTo(800 - (scene.$4 ? 220 : 0)));
        expect(tester.takeException(), isNull);
        if (scene.$1 == 360) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(captureKey),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('build/qa/editor-actions/editor-360-sl.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(report);
        await tester.pumpAndSettle();
        expect(reports, 1);
        expect(saved, 0);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved, 1);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }
  testWidgets(
    'busy save disables every CRUD action and header report, then finishes once',
    (tester) async {
      final context = await host(tester);
      final pending = Completer<void>();
      var saved = 0, reports = 0;
      showOrganizerEditor(
        context,
        heading: 'Uredi opravilo',
        kind: OrganizerEditorKind.task,
        draft: OrganizerDraft(title: 'Opravilo'),
        onSave: (_) async {
          saved++;
          await pending.future;
        },
        onDelete: () async {},
        onReport: () async {
          reports++;
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();
      final report = tester.widget<TextButton>(
        find.byKey(const ValueKey('editor-report')),
      );
      expect(report.onPressed, isNull);
      final icon = tester.widget<IconButton>(
        find.descendant(of: save, matching: find.byType(IconButton)),
      );
      expect(icon.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(save);
      await tester.pump();
      expect(saved, 1);
      expect(reports, 0);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'plain personal editor never gains reporting and cancel remains text',
    (tester) async {
      final context = await host(tester, width: 320, scale: 1.8);
      showOrganizerEditor(
        context,
        heading: 'Nov nakup',
        kind: OrganizerEditorKind.shoppingItem,
        draft: OrganizerDraft(),
        onSave: (_) async {},
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-report')), findsNothing);
      expect(find.widgetWithText(TextButton, 'Prekliči'), findsOneWidget);
      expect(find.byTooltip('Shrani'), findsOneWidget);
      await tester.tap(find.text('Prekliči'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('generic forms use icon row only after explicit CRUD opt-in', (
    tester,
  ) async {
    final context = await host(tester, width: 320, scale: 1.8, keyboard: true);
    showSharingForm(
      context,
      title: 'Uredi račun',
      fields: const [],
      submitLabel: 'Shrani',
      compactSaveActions: true,
      onSubmit: (_) async {},
      onDelete: () async {},
      errorMessage: (_) => 'Napaka',
    );
    await tester.pumpAndSettle();
    sameRow(
      tester,
      [
        find.byTooltip('Delete'),
        find.widgetWithText(TextButton, 'Prekliči'),
        find.byKey(const ValueKey('sharing-submit')),
      ].where((f) => f.evaluate().isNotEmpty),
    );
    expect(find.byType(EditorActionsRow), findsOneWidget);
    await tester.tap(find.text('Prekliči'));
    await tester.pumpAndSettle();
    showSharingForm(
      context,
      title: 'Povabilo',
      fields: const [],
      submitLabel: 'Pošlji povabilo',
      onSubmit: (_) async {},
      errorMessage: (_) => 'Napaka',
    );
    await tester.pumpAndSettle();
    expect(find.byType(EditorActionsRow), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Pošlji povabilo'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('editor-report')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
