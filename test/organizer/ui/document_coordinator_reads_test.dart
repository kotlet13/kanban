import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';
import 'package:kanban/organizer/presentation/tables/spreadsheet_tables_page.dart';
import 'spreadsheet_ui_test.dart' show MemorySheets;

class _Sheets extends MemorySheets {
  final db = CollaborationDatabase(NativeDatabase.memory());
  final listOrigin = Object(), readOrigin = Object();
  int lists = 0, reads = 0;
  Stream<void> changes([String? id]) => db.documentChanges(
    'a',
    scopeId,
    type: 'table',
    id: id,
    ignoreOrigin: id == null ? listOrigin : readOrigin,
  );
  void changed(String type, String id) =>
      db.documentsChanged('a', scopeId, type: type, id: id);
  @override
  Future<List<SpreadsheetDocument>> list() =>
      db.withDocumentRead(listOrigin, () async {
        lists++;
        changed('table', document.id);
        return [document];
      });
  @override
  Future<SpreadsheetRead> read(String id) =>
      db.withDocumentRead(readOrigin, () async {
        reads++;
        changed('table', id);
        return SpreadsheetRead(document: document);
      });
}

void main() {
  testWidgets(
    'document coordinator avoids self rereads but refreshes matching remote detail',
    (tester) async {
      final sheets = _Sheets();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: SpreadsheetTablesPage(
            gateway: sheets,
            changes: sheets.changes(),
            changesForTable: sheets.changes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sheets.lists, 1);
      await tester.tap(find.text('Project budget'));
      await tester.pumpAndSettle();
      expect(sheets.reads, 1);
      sheets.changed('table', 'another-table');
      sheets.changed('attachment', 'another-file');
      await tester.pumpAndSettle();
      expect(sheets.reads, 1);
      sheets.document = SpreadsheetDocument(
        id: sheets.document.id,
        scopeId: sheets.scopeId,
        title: 'Remote revision',
        cells: {'A1': 'remote'},
        revision: 2,
        updatedAt: 2,
      );
      sheets.changed('table', sheets.document.id);
      await tester.pumpAndSettle();
      expect(sheets.reads, 2);
      expect(find.text('Remote revision'), findsOneWidget);
      expect(
        sheets.lists,
        1,
      ); // Covered list waits for normal return navigation.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await sheets.db.close();
    },
  );
}
