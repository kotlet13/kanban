import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';
import 'package:kanban/organizer/domain/spreadsheet_tsv.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart'
    show CollaborationException;
import 'package:kanban/organizer/presentation/tables/spreadsheet_grid.dart';
import 'package:kanban/organizer/presentation/tables/spreadsheet_tables_page.dart';

class MemorySheets implements SpreadsheetGateway {
  @override
  final scopeId = 'organization-1';
  @override
  bool canEdit = true, online = true, isCurrent = true;
  SpreadsheetDocument document = SpreadsheetDocument(
    id: 'table-1',
    scopeId: 'organization-1',
    title: 'Project budget',
    cells: {
      'A1': 'Item',
      'B1': 'Cost',
      'A2': 'Seed',
      'B2': '12',
      'A3': 'Soil',
      'B3': '=B2*2',
      'B4': '=SUM(B2:B3)',
    },
    revision: 1,
    updatedAt: 1,
  );
  SpreadsheetLease? lease;
  SpreadsheetDraft? draft;
  int saves = 0, releases = 0;
  bool denyRenew = false, denySave = false, denyDraft = false;
  @override
  Future<List<SpreadsheetDocument>> list() async => [document];
  @override
  Future<SpreadsheetRead> read(String id) async =>
      SpreadsheetRead(document: document, lease: lease);
  @override
  Future<SpreadsheetDocument> create(String title) async => document;
  @override
  Future<SpreadsheetLease> acquire(String id) async {
    if (lease != null && lease!.token == null) throw StateError('locked');
    return lease = SpreadsheetLease(
      token: 'secret',
      holderName: 'Ana',
      holderAccountId: '1',
      holderDeviceId: 'd',
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90,
    );
  }

  @override
  Future<SpreadsheetLease> renew(String id, String token) async {
    if (denyRenew) throw StateError('lost');
    return acquire(id);
  }

  @override
  Future<SpreadsheetDocument> save(
    String id,
    String token,
    int revision,
    String title,
    Map<String, String> cells,
  ) async {
    if (denySave) throw StateError('lost');
    saves++;
    return document = SpreadsheetDocument(
      id: id,
      scopeId: scopeId,
      title: title,
      cells: cells,
      revision: revision + 1,
      updatedAt: 2,
    );
  }

  @override
  Future<void> release(String id, String token) async {
    releases++;
    lease = null;
  }

  @override
  Future<void> delete(String id, String token, int revision) async {}
  @override
  Future<SpreadsheetDraft?> loadDraft(String id) async => draft;
  @override
  Future<void> storeDraft(SpreadsheetDraft value) async {
    if (denyDraft) throw StateError('disk');
    draft = value;
  }

  @override
  Future<void> clearDraft(String id) async {
    draft = null;
  }
}

class MissingSheets extends MemorySheets {
  String? missingOperation;
  void missing(String operation) {
    if (missingOperation == operation) {
      throw const CollaborationException('table_unavailable');
    }
  }

  @override
  Future<SpreadsheetRead> read(String id) async {
    missing('read');
    return super.read(id);
  }

  @override
  Future<SpreadsheetLease> acquire(String id) async {
    missing('acquire');
    return super.acquire(id);
  }

  @override
  Future<SpreadsheetLease> renew(String id, String token) async {
    missing('renew');
    return super.renew(id, token);
  }

  @override
  Future<SpreadsheetDocument> save(
    String id,
    String token,
    int expectedRevision,
    String title,
    Map<String, String> cells,
  ) async {
    missing('save');
    return super.save(id, token, expectedRevision, title, cells);
  }
}

final _captureKey = GlobalKey();
Future<void> pumpSheet(
  WidgetTester tester,
  MemorySheets gateway, {
  double width = 390,
  double height = 900,
  Future<void> Function(String)? onReport,
  Widget Function(String)? attachmentsBuilder,
  double scale = 1,
  bool dark = false,
  String locale = 'en',
  TargetPlatform platform = TargetPlatform.android,
}) async {
  if (const bool.fromEnvironment('CAPTURE_SHEETS')) {
    await tester.runAsync(() async {
      final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
      final fonts = '$sdk/bin/cache/artifacts/material_fonts';
      for (final family in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        '.SF UI Text',
        '.SF UI Display',
        '.AppleSystemUIFont',
      ]) {
        final bytes = await File(
          platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
              ? '/System/Library/Fonts/SFNS.ttf'
              : '$fonts/Roboto-Regular.ttf',
        ).readAsBytes();
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      final icons = await File(
        '$fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    });
  }
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('sl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        platform: platform,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: _captureKey, child: child!),
      ),
      home: SpreadsheetDetailPage(
        gateway: gateway,
        document: gateway.document,
        onReport: onReport,
        attachmentsBuilder: attachmentsBuilder,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'lease gates edits; raw formulas save and finish; draft clears on ACK',
    (tester) async {
      final gateway = MemorySheets();
      await pumpSheet(tester, gateway);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('spreadsheet-formula-input')),
            )
            .readOnly,
        isTrue,
      );
      await tester.tap(find.byTooltip('Edit table'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spreadsheet-formula-input')),
        '=SUM(B2:B3)',
      );
      await tester.pumpAndSettle();
      expect(gateway.draft!.cells['A1'], '=SUM(B2:B3)');
      expect(find.text('36'), findsWidgets);
      await tester.tap(find.byTooltip('Save and finish editing'));
      await tester.pumpAndSettle();
      expect(gateway.saves, 1);
      expect(gateway.releases, 1);
      expect(gateway.draft, isNull);
      expect(gateway.document.cells['A1'], '=SUM(B2:B3)');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('other editor banner and denial never enable input', (
    tester,
  ) async {
    final gateway = MemorySheets()
      ..lease = SpreadsheetLease(
        holderName: 'Maja',
        holderAccountId: '2',
        holderDeviceId: 'other',
        expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90,
      );
    await pumpSheet(tester, gateway);
    expect(find.textContaining('Maja is editing'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('spreadsheet-formula-input')),
          )
          .readOnly,
      isTrue,
    );
    expect(gateway.saves, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('lost renewal preserves draft and stops edits', (tester) async {
    final gateway = MemorySheets();
    await pumpSheet(tester, gateway);
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('spreadsheet-formula-input')),
      'unsent',
    );
    await tester.pumpAndSettle();
    gateway.denyRenew = true;
    await tester.pump(const Duration(seconds: 25));
    await tester.pumpAndSettle();
    expect(find.textContaining('Editing stopped.'), findsOneWidget);
    expect(gateway.draft!.cells['A1'], 'unsent');
    expect(gateway.saves, 0);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('spreadsheet-formula-input')),
          )
          .readOnly,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('offline and reader have view only', (tester) async {
    final gateway = MemorySheets()
      ..online = false
      ..canEdit = false;
    await pumpSheet(tester, gateway);
    expect(find.byTooltip('Edit table'), findsNothing);
    expect(find.textContaining('Offline:'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('recovery requires lease and matching base revision', (
    tester,
  ) async {
    final gateway = MemorySheets()
      ..draft = SpreadsheetDraft(
        tableId: 'table-1',
        baseRevision: 1,
        title: 'Recovered',
        cells: {'A1': 'recovered'},
        updatedAt: 3,
      );
    await pumpSheet(tester, gateway);
    expect(gateway.document.title, 'Project budget');
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore draft'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered'), findsOneWidget);
    expect(gateway.saves, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('changed base offers copy rather than stale restore', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final gateway = MemorySheets()
      ..draft = SpreadsheetDraft(
        tableId: 'table-1',
        baseRevision: 0,
        title: 'Old',
        cells: {'A1': 'old\nvalue\twith "quotes"'},
        updatedAt: 3,
      );
    await pumpSheet(tester, gateway);
    expect(find.text('Restore draft'), findsNothing);
    expect(find.text('Copy draft'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    expect(find.text('Project budget'), findsOneWidget);
    await tester.tap(find.text('Copy draft'));
    await tester.pumpAndSettle();
    expect(SpreadsheetTsv.decode(clipboard!), [
      ['A1', 'old\nvalue\twith "quotes"'],
    ]);
    expect(gateway.draft, isNotNull);
    expect(gateway.saves, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('identity change stops edit before next write', (tester) async {
    final gateway = MemorySheets();
    await pumpSheet(tester, gateway);
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    gateway.isCurrent = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(SpreadsheetGrid), findsNothing);
    expect(find.text('Project budget'), findsNothing);
    expect(find.text('Item'), findsNothing);
    expect(
      find.textContaining('This space is no longer available'),
      findsOneWidget,
    );
    expect(gateway.saves, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('list hides cached titles after known access loss', (
    tester,
  ) async {
    final gateway = MemorySheets();
    await tester.pumpWidget(
      MaterialApp(home: SpreadsheetTablesPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Project budget'), findsOneWidget);
    gateway.isCurrent = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Project budget'), findsNothing);
    expect(
      find.textContaining('This space is no longer available'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'access loss masks content, preserves draft and Back still works',
    (tester) async {
      final gateway = MemorySheets();
      await tester.pumpWidget(
        MaterialApp(home: SpreadsheetTablesPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project budget'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit table'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spreadsheet-formula-input')),
        'private draft',
      );
      await tester.pumpAndSettle();
      gateway.isCurrent = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Project budget'), findsNothing);
      expect(find.text('private draft'), findsNothing);
      expect(find.byType(SpreadsheetGrid), findsNothing);
      expect(gateway.draft!.cells['A1'], 'private draft');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SpreadsheetDetailPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('confirmed missing table masks the initially cached content', (
    tester,
  ) async {
    final gateway = MissingSheets()..missingOperation = 'read';
    await pumpSheet(
      tester,
      gateway,
      attachmentsBuilder: (_) => const Text('private attachment'),
    );
    expect(gateway.isCurrent, isTrue);
    expect(find.text('Project budget'), findsNothing);
    expect(find.text('Item'), findsNothing);
    expect(find.byType(SpreadsheetGrid), findsNothing);
    expect(find.text('private attachment'), findsNothing);
    expect(
      find.textContaining('This table is no longer available'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final operation in ['read', 'acquire', 'renew', 'save']) {
    testWidgets(
      'table unavailable in $operation masks content and preserves draft',
      (tester) async {
        final gateway = MissingSheets();
        await pumpSheet(
          tester,
          gateway,
          attachmentsBuilder: (_) => const Text('private attachment'),
        );
        if (operation == 'acquire') {
          gateway.missingOperation = operation;
          await tester.tap(find.byTooltip('Edit table'));
          await tester.pumpAndSettle();
        } else {
          await tester.tap(find.byTooltip('Edit table'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('spreadsheet-formula-input')),
            'private draft',
          );
          await tester.pumpAndSettle();
          gateway.missingOperation = operation;
          if (operation == 'save') {
            await tester.tap(find.byTooltip('Save'));
          }
          if (operation == 'renew') {
            await tester.pump(const Duration(seconds: 25));
          }
          if (operation == 'read') {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await tester.pumpAndSettle();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          }
          await tester.pumpAndSettle();
          expect(gateway.draft!.cells['A1'], 'private draft');
        }
        expect(gateway.isCurrent, isTrue);
        expect(find.text('Project budget'), findsNothing);
        expect(find.byType(SpreadsheetGrid), findsNothing);
        expect(find.text('private attachment'), findsNothing);
        expect(
          find.textContaining('This table is no longer available'),
          findsOneWidget,
        );
        expect(gateway.saves, 0);
        await tester.pump(const Duration(seconds: 30));
        await tester.pumpAndSettle();
        expect(find.byType(SpreadsheetGrid), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('grid virtualizes distant cells and keyboard navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpreadsheetGrid(
            cells: const {'ZZZ100000': 'end'},
            editable: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('end'), findsNothing);
    expect(find.byType(InkWell).evaluate().length, lessThan(300));
    await tester.tap(find.text('A1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'ZZZ100000');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('end'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed save preserves raw draft and stops editing', (
    tester,
  ) async {
    final gateway = MemorySheets();
    await pumpSheet(tester, gateway);
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('spreadsheet-formula-input')),
      '=1/0',
    );
    await tester.pumpAndSettle();
    gateway.denySave = true;
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(gateway.draft!.cells['A1'], '=1/0');
    expect(gateway.document.cells['A1'], 'Item');
    expect(find.byTooltip('Save'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('lifecycle pause preserves draft and releases lease', (
    tester,
  ) async {
    final gateway = MemorySheets();
    await pumpSheet(tester, gateway);
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('spreadsheet-formula-input')),
      'waiting',
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(gateway.draft!.cells['A1'], 'waiting');
    expect(gateway.releases, 1);
    expect(gateway.saves, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('keyboard arrows, shift range and clipboard TSV', (tester) async {
    var cells = <String, String>{'A1': 'one', 'B1': 'two'};
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': '3\t4\n5\t=SUM(A1:B1)'};
        }
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SpreadsheetGrid(
              cells: cells,
              editable: true,
              onChanged: (value) => setState(() => cells = value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('one').last);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy selected cells'));
    await tester.pumpAndSettle();
    expect(clipboard, 'one\ttwo');
    await tester.tap(find.byTooltip('Paste cells'));
    await tester.pumpAndSettle();
    expect(cells['B1'], '3');
    expect(cells['C2'], '=SUM(A1:B1)');
    expect(cells['B2'], '5');
    await tester.pumpWidget(const SizedBox());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  testWidgets('unrecovered draft blocks a new edit until explicit choice', (
    tester,
  ) async {
    final gateway = MemorySheets()
      ..draft = SpreadsheetDraft(
        tableId: 'table-1',
        baseRevision: 0,
        title: 'Old',
        cells: {'A1': 'older work'},
        updatedAt: 3,
      );
    await pumpSheet(tester, gateway);
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('spreadsheet-formula-input')),
          )
          .readOnly,
      isTrue,
    );
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(gateway.draft!.cells['A1'], 'older work');
    expect(gateway.saves, 0);
    await tester.tap(find.text('Use saved version'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.draft, isNotNull);
    await tester.tap(find.text('Use saved version'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use saved version').last);
    await tester.pumpAndSettle();
    expect(gateway.draft, isNull);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('spreadsheet-formula-input')),
          )
          .readOnly,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('reader has one report menu and no writer actions', (
    tester,
  ) async {
    final gateway = MemorySheets()..canEdit = false;
    var reports = 0;
    await pumpSheet(
      tester,
      gateway,
      onReport: (id) async {
        expect(id, 'table-1');
        reports++;
      },
    );
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Rename table'), findsNothing);
    expect(find.text('Delete table'), findsNothing);
    await tester.tap(find.text('Report content'));
    await tester.pumpAndSettle();
    expect(reports, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('short viewport and attachment pane keep a scrollable editor', (
    tester,
  ) async {
    final gateway = MemorySheets()
      ..draft = SpreadsheetDraft(
        tableId: 'table-1',
        baseRevision: 0,
        title: 'Old',
        cells: {'A1': 'older work'},
        updatedAt: 3,
      );
    await pumpSheet(
      tester,
      gateway,
      width: 320,
      height: 400,
      scale: 2,
      attachmentsBuilder: (_) =>
          ListView(children: const [ListTile(title: Text('Example.pdf'))]),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Back preserves unsaved draft and releases the lease', (
    tester,
  ) async {
    final gateway = MemorySheets();
    await tester.pumpWidget(
      MaterialApp(home: SpreadsheetTablesPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project budget'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('spreadsheet-formula-input')),
      'keep me',
    );
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SpreadsheetTablesPage), findsOneWidget);
    expect(gateway.draft!.cells['A1'], 'keep me');
    expect(gateway.releases, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'quoted TSV copy and paste preserves tabs quotes and multiline cells',
    (tester) async {
      const raw = 'first\t"quoted"\r\nlast';
      var cells = <String, String>{
        'A1': raw,
        'B2': 'keep row',
        'C1': 'remove this',
        'C2': 'also keep',
      };
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SpreadsheetGrid(
                cells: cells,
                editable: true,
                onChanged: (value) => setState(() => cells = value),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(raw).last);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Copy selected cells'));
      await tester.pumpAndSettle();
      expect(clipboard, '"first\t""quoted""\r\nlast"\t""');
      await tester.tap(find.byTooltip('Paste cells'));
      await tester.pumpAndSettle();
      expect(cells['B1'], raw);
      expect(cells.containsKey('C1'), isFalse);
      expect(cells['B2'], 'keep row');
      expect(cells['C2'], 'also keep');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('malformed quoted TSV is rejected without a partial paste', (
    tester,
  ) async {
    var cells = <String, String>{'A1': 'original', 'B1': 'unchanged'};
    var writes = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'new\t"broken'} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SpreadsheetGrid(
              cells: cells,
              editable: true,
              onChanged: (value) {
                writes++;
                setState(() => cells = value);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paste cells'));
    await tester.pumpAndSettle();
    expect(cells, {'A1': 'original', 'B1': 'unchanged'});
    expect(writes, 0);
    expect(
      find.text(
        'Clipboard text is not valid tab-separated data. Nothing was pasted.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final locale in ['en', 'sl']) {
      for (final dark in [false, true]) {
        testWidgets('layout $width $locale dark=$dark 2x', (tester) async {
          await pumpSheet(
            tester,
            MemorySheets(),
            width: width,
            scale: 2,
            dark: dark,
            locale: locale,
            platform: width == 1280
                ? TargetPlatform.macOS
                : locale == 'sl'
                ? TargetPlatform.iOS
                : TargetPlatform.android,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.byTooltip(locale == 'sl' ? 'Uredi preglednico' : 'Edit table'),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('CAPTURE_SHEETS')) {
            final boundary =
                _captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/qa/organization-upgrades-20261016/table-${width.toInt()}-$locale-${dark ? 'dark' : 'light'}-2x.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
