import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';
import 'package:kanban/organizer/presentation/tables/spreadsheet_grid.dart';
import 'package:kanban/organizer/presentation/tables/spreadsheet_tables_page.dart';

import 'spreadsheet_ui_test.dart' show MemorySheets;

class _Sheets extends MemorySheets implements SpreadsheetDraftIdentity {
  @override
  bool isDraftIdentityCurrent = true;
  bool rejectSharedSave = false;
  int saveAttempts = 0;
  @override
  Future<SpreadsheetDocument> save(
    String id,
    String token,
    int revision,
    String title,
    Map<String, String> cells,
  ) async {
    saveAttempts++;
    if (rejectSharedSave) {
      isCurrent = false;
      canEdit = false;
      throw const CollaborationApiException('permission_revoked');
    }
    return super.save(id, token, revision, title, cells);
  }
}

const _input = ValueKey('spreadsheet-formula-input');

Future<void> _open(WidgetTester tester, MemorySheets sheets) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('sl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open existing table'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => SpreadsheetDetailPage(
                  gateway: sheets,
                  document: sheets.document,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open existing table'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Edit table'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(_input), 'First local change');
  await tester.pumpAndSettle();
}

void main() {
  for (final revoked in [false, true]) {
    testWidgets(
      'mid-edit rights change retains editable draft and restores it revoked=$revoked',
      (tester) async {
        final sheets = _Sheets();
        await _open(tester, sheets);
        sheets.canEdit = false;
        if (revoked) sheets.isCurrent = false;
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.byType(SpreadsheetGrid), findsOneWidget);
        expect(tester.widget<TextField>(find.byKey(_input)).readOnly, isFalse);
        expect(
          find.textContaining('Shared changes cannot be saved now'),
          findsOneWidget,
        );
        expect(find.byTooltip('Save'), findsNothing);
        expect(find.byTooltip('Save and finish editing'), findsNothing);
        await tester.enterText(
          find.byKey(_input),
          'Finished locally after rights changed',
        );
        await tester.pumpAndSettle();
        expect(
          sheets.draft!.cells['A1'],
          'Finished locally after rights changed',
        );
        expect(sheets.document.cells['A1'], 'Item');
        expect(sheets.saveAttempts, 0);
        await tester.tap(find.byTooltip('Keep draft and close'));
        await tester.pumpAndSettle();
        expect(find.text('Open existing table'), findsOneWidget);
        expect(
          sheets.draft!.cells['A1'],
          'Finished locally after rights changed',
        );

        sheets.isCurrent = true;
        sheets.canEdit = true;
        await tester.tap(find.text('Open existing table'));
        await tester.pumpAndSettle();
        expect(
          find.text('A draft from this device is available.'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Edit table'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore draft'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byKey(_input)).controller!.text,
          'Finished locally after rights changed',
        );
        expect(sheets.saveAttempts, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'server rejection retains local editing without claiming shared save',
    (tester) async {
      final sheets = _Sheets();
      await _open(tester, sheets);
      sheets.rejectSharedSave = true;
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      expect(sheets.saveAttempts, 1);
      expect(sheets.saves, 0);
      expect(sheets.document.revision, 1);
      expect(find.text('Saved'), findsNothing);
      expect(tester.widget<TextField>(find.byKey(_input)).readOnly, isFalse);
      await tester.enterText(
        find.byKey(_input),
        'Local continuation after denial',
      );
      await tester.pumpAndSettle();
      expect(sheets.draft!.cells['A1'], 'Local continuation after denial');
      expect(find.byTooltip('Keep draft and close'), findsOneWidget);
      expect(sheets.saveAttempts, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account boundary hides old draft immediately and blocks later edits',
    (tester) async {
      final sheets = _Sheets();
      await _open(tester, sheets);
      sheets.isDraftIdentityCurrent = false;
      sheets.isCurrent = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SpreadsheetGrid), findsNothing);
      expect(find.byKey(_input), findsNothing);
      expect(find.text('Project budget'), findsNothing);
      expect(find.byTooltip('Keep draft and close'), findsNothing);
      expect(sheets.draft!.cells['A1'], 'First local change');
      expect(sheets.saveAttempts, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('local draft stays editable across background and resume', (
    tester,
  ) async {
    final sheets = _Sheets();
    await _open(tester, sheets);
    sheets.canEdit = false;
    sheets.isCurrent = false;
    await tester.pump(const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(_input)).readOnly, isFalse);
    await tester.enterText(find.byKey(_input), 'Local after resume');
    await tester.pumpAndSettle();
    expect(sheets.draft!.cells['A1'], 'Local after resume');
    expect(sheets.saveAttempts, 0);
    expect(find.byTooltip('Keep draft and close'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'gateway without separate identity remains conservative on lost access',
    (tester) async {
      final sheets = MemorySheets();
      await _open(tester, sheets);
      sheets.isCurrent = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SpreadsheetGrid), findsNothing);
      expect(find.byKey(_input), findsNothing);
      expect(sheets.draft!.cells['A1'], 'First local change');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
