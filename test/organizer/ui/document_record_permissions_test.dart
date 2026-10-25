import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';
import 'package:kanban/organizer/presentation/attachments/attachments_panel.dart';
import 'package:kanban/organizer/presentation/tables/spreadsheet_tables_page.dart';
import 'attachments_panel_test.dart' show FakeGateway;
import 'spreadsheet_ui_test.dart' show MemorySheets;

class _Sheets extends MemorySheets implements SpreadsheetRecordPermissions {
  bool allowed = true;
  int reads = 0;
  @override
  Future<SpreadsheetRead> read(String id) {
    reads++;
    return super.read(id);
  }

  @override
  bool canEditDocument(SpreadsheetDocument document) => allowed;
  @override
  bool canDeleteDocument(SpreadsheetDocument document) => allowed;
}

void main() {
  testWidgets(
    'read-only table refresh follows change signal instead of ten-second timer',
    (tester) async {
      final gateway = _Sheets();
      final changes = StreamController<void>.broadcast();
      await tester.pumpWidget(
        MaterialApp(
          home: SpreadsheetDetailPage(
            gateway: gateway,
            document: gateway.document,
            changes: changes.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initial = gateway.reads;
      expect(initial, 1);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(gateway.reads, initial);
      changes.add(null);
      await tester.pumpAndSettle();
      expect(gateway.reads, initial + 1);
      await tester.tap(find.byTooltip('Edit table'));
      await tester.pumpAndSettle();
      final editing = gateway.reads;
      changes.add(null);
      await tester.pumpAndSettle();
      expect(gateway.reads, editing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      await changes.close();
    },
  );

  testWidgets(
    'attachment author can delete existing file without new upload permission',
    (tester) async {
      final gateway = FakeGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentsPanel(
              gateway: gateway,
              canEdit: false,
              canDelete: (file) => file.id == 'attachment-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attachment-add')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('attachment-menu-attachment-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('attachment-delete-attachment-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(gateway.deletes, 1);
      expect(gateway.uploads, 0);
    },
  );
  testWidgets('scope writer cannot delete foreign attachment through menu', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentsPanel(
            gateway: gateway,
            canEdit: true,
            canDelete: (_) => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attachment-add')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('attachment-menu-attachment-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('attachment-delete-attachment-1')),
      findsNothing,
    );
    expect(gateway.deletes, 0);
  });
  testWidgets(
    'table author can acquire existing document while create stays unavailable',
    (tester) async {
      final gateway = _Sheets()..canEdit = false;
      await tester.pumpWidget(
        MaterialApp(home: SpreadsheetTablesPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.text('Project budget'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit table'));
      await tester.pumpAndSettle();
      expect(gateway.lease?.token, isNotNull);
      gateway.allowed = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byTooltip('Save'), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
    },
  );
}
