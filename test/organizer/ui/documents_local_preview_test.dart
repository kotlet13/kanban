import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/attachment_models.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';
import 'package:kanban/organizer/presentation/attachments/attachments_panel.dart';
import 'package:kanban/organizer/presentation/tables/spreadsheet_tables_page.dart';
import 'spreadsheet_ui_test.dart' show MemorySheets;
import 'attachments_panel_test.dart' show FakeGateway;

class _Sheets extends MemorySheets implements SpreadsheetLocalPreview {
  Future<List<SpreadsheetDocument>?>? preview;
  final freshList = Completer<List<SpreadsheetDocument>>();
  final firstRead = Completer<SpreadsheetRead>();
  int listCalls = 0, reads = 0, draftReads = 0;
  @override
  Future<List<SpreadsheetDocument>?> cachedList() =>
      preview ?? Future.value([document]);
  @override
  Future<SpreadsheetRead?> cachedRead(String id) async =>
      SpreadsheetRead(document: document);
  @override
  Future<List<SpreadsheetDocument>> list() {
    listCalls++;
    return freshList.future;
  }

  @override
  Future<SpreadsheetRead> read(String id) =>
      ++reads == 1 ? firstRead.future : super.read(id);
  @override
  Future<SpreadsheetDraft?> loadDraft(String id) {
    draftReads++;
    return super.loadDraft(id);
  }
}

class _Files extends FakeGateway implements AttachmentLocalPreview {
  final fresh = Completer<List<AttachmentMetadata>>();
  @override
  Future<List<AttachmentMetadata>?> cachedList() async => items;
  @override
  Future<List<AttachmentMetadata>> list() => fresh.future;
}

Future<void> _pump(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: widget,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets(
    'warm table and attachment metadata paint before fresh reads; cold stays loading',
    (tester) async {
      final tables = _Sheets();
      await _pump(tester, SpreadsheetTablesPage(gateway: tables));
      expect(find.text('Project budget'), findsOneWidget);
      expect(tables.listCalls, 1);
      expect(tables.freshList.isCompleted, isFalse);
      await tester.pumpWidget(const SizedBox());
      tables.freshList.complete([tables.document]);
      await tester.pump();

      final cold = _Sheets()..preview = Future.value(null);
      await _pump(tester, SpreadsheetTablesPage(gateway: cold));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Project budget'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      cold.freshList.complete([]);
      await tester.pump();

      final files = _Files();
      await _pump(
        tester,
        Scaffold(body: AttachmentsPanel(gateway: files, canEdit: true)),
      );
      expect(find.text(files.items.single.name), findsOneWidget);
      expect(files.fresh.isCompleted, isFalse);
      expect(files.downloads, 0);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      files.fresh.complete(files.items);
      await tester.pump();
    },
  );

  testWidgets(
    'full cached table and local draft arrive early; late fresh read never clobbers editing draft',
    (tester) async {
      final tables = _Sheets();
      tables.draft = SpreadsheetDraft(
        tableId: tables.document.id,
        baseRevision: 1,
        title: tables.document.title,
        cells: {'A1': 'saved-local'},
        updatedAt: 1,
      );
      await _pump(
        tester,
        SpreadsheetDetailPage(gateway: tables, document: tables.document),
      );
      expect(tables.firstRead.isCompleted, isFalse);
      expect(tables.draftReads, 1);
      expect(find.text('Restore draft'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit table'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Restore draft'));
      await tester.pump();
      await tester.pump();
      final field = find.byKey(const ValueKey('spreadsheet-formula-input'));
      await tester.enterText(field, 'typed-local');
      await tester.pump();
      await tester.pump();
      tables.firstRead.complete(
        SpreadsheetRead(
          document: SpreadsheetDocument(
            id: tables.document.id,
            scopeId: tables.scopeId,
            title: 'Remote late',
            cells: {'A1': 'remote-late'},
            revision: 2,
            updatedAt: 2,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, 'typed-local');
      expect(tables.draft!.cells['A1'], 'typed-local');
      expect(tables.saves, 0);
      expect(find.text('Remote late'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'late old gateway preview and revoked fresh result never cross the visible binding',
    (tester) async {
      final oldPreview = Completer<List<SpreadsheetDocument>?>();
      final old = _Sheets()..preview = oldPreview.future;
      await _pump(tester, SpreadsheetTablesPage(gateway: old));
      final next = _Sheets()
        ..document = SpreadsheetDocument(
          id: 'new-table',
          scopeId: 'organization-1',
          title: 'Current account table',
          cells: {},
          revision: 1,
          updatedAt: 1,
        );
      await _pump(tester, SpreadsheetTablesPage(gateway: next));
      old.isCurrent = false;
      oldPreview.complete([old.document]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Project budget'), findsNothing);
      expect(find.text('Current account table'), findsOneWidget);
      expect(old.listCalls, 0);
      next.isCurrent = false;
      next.freshList.complete([next.document]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Current account table'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
