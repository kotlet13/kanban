import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/attachment_models.dart';
import 'package:kanban/organizer/presentation/attachments/attachment_file_io.dart';
import 'package:kanban/organizer/presentation/attachments/attachments_panel.dart';

import '../domain/attachment_models_test.dart' show fixtureAttachment;

class FakeGateway implements AttachmentGateway {
  @override
  final target = const AttachmentTarget(
    scopeId: 'scope-1',
    targetType: 'scope',
    targetId: 'scope-1',
  );
  @override
  bool isCurrent = true;
  @override
  bool isOnline = true;
  List<AttachmentMetadata> items = [fixtureAttachment()];
  bool cached = false, uploadFails = false, listFails = false, denyList = false;
  int uploads = 0, downloads = 0, deletes = 0;
  Completer<Uint8List>? pendingDownload;
  Completer<void>? pendingUpload;
  @override
  Future<List<AttachmentMetadata>> list() async {
    if (denyList) {
      isCurrent = false;
      throw StateError('denied');
    }
    if (listFails) throw StateError('failed');
    return items;
  }

  @override
  Uint8List? localBytes(AttachmentMetadata attachment) =>
      cached ? Uint8List(4) : null;
  @override
  Future<void> upload({
    required String name,
    required String mime,
    required Uint8List bytes,
    void Function(double)? onProgress,
  }) async {
    uploads++;
    onProgress?.call(.5);
    if (uploadFails) throw StateError('failed');
    if (pendingUpload != null) await pendingUpload!.future;
  }

  @override
  Future<Uint8List> download(
    AttachmentMetadata attachment, {
    void Function(double)? onProgress,
  }) async {
    downloads++;
    return pendingDownload == null ? Uint8List(4) : pendingDownload!.future;
  }

  @override
  Future<void> delete(AttachmentMetadata attachment) async {
    deletes++;
    items = [];
  }
}

class FakePicker extends AttachmentFilePicker {
  int calls = 0;
  PickedAttachmentFile? picked = PickedAttachmentFile(
    name: 'scan.pdf',
    bytes: Uint8List(4),
  );
  Completer<PickedAttachmentFile?>? pending;
  @override
  Future<PickedAttachmentFile?> pick() async {
    calls++;
    return pending == null ? picked : pending!.future;
  }
}

class FakeExporter extends AttachmentFileExporter {
  int calls = 0;
  @override
  Future<AttachmentExportStatus> save({
    required AttachmentMetadata attachment,
    required Uint8List bytes,
    required String title,
  }) async {
    calls++;
    return AttachmentExportStatus.saved;
  }
}

Future<void> showPanel(
  WidgetTester tester,
  FakeGateway gateway, {
  bool canEdit = true,
  FakePicker? picker,
  FakeExporter? exporter,
  Future<void> Function(AttachmentMetadata)? onReport,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('sl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: AttachmentsPanel(
          gateway: gateway,
          canEdit: canEdit,
          filePicker: picker,
          fileExporter: exporter,
          onReport: onReport,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('attachment-menu-attachment-1')));
  await tester.pumpAndSettle();
}

Future<void> chooseAction(WidgetTester tester, String action) async {
  await openMenu(tester);
  await tester.tap(find.byKey(ValueKey('attachment-$action-attachment-1')));
}

void main() {
  testWidgets('reader can save but cannot add or delete', (tester) async {
    final gateway = FakeGateway(), exporter = FakeExporter();
    await showPanel(tester, gateway, canEdit: false, exporter: exporter);
    expect(find.byKey(const ValueKey('attachment-add')), findsNothing);
    expect(
      find.byKey(const ValueKey('attachment-delete-attachment-1')),
      findsNothing,
    );
    await chooseAction(tester, 'save');
    await tester.pumpAndSettle();
    expect(gateway.downloads, 1);
    expect(exporter.calls, 1);
    expect(gateway.uploads, 0);
    expect(gateway.deletes, 0);
  });

  testWidgets('offline exposes cached download and blocks mutations', (
    tester,
  ) async {
    final gateway = FakeGateway()..isOnline = false;
    await showPanel(tester, gateway);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('attachment-add')))
          .onPressed,
      isNull,
    );
    await openMenu(tester);
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.byKey(const ValueKey('attachment-save-attachment-1')),
          )
          .enabled,
      false,
    );
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.byKey(const ValueKey('attachment-delete-attachment-1')),
          )
          .enabled,
      false,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    gateway.cached = true;
    await showPanel(tester, gateway);
    await openMenu(tester);
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.byKey(const ValueKey('attachment-save-attachment-1')),
          )
          .enabled,
      true,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Available offline'), findsOneWidget);
  });

  testWidgets(
    'cancelled picker uploads nothing; unsupported injected file rejected',
    (tester) async {
      final gateway = FakeGateway(), picker = FakePicker()..picked = null;
      await showPanel(tester, gateway, picker: picker);
      await tester.tap(find.text('Add attachment'));
      await tester.pumpAndSettle();
      expect(gateway.uploads, 0);
      picker.picked = PickedAttachmentFile(
        name: 'run.exe',
        bytes: Uint8List(4),
      );
      await tester.tap(find.text('Add attachment'));
      await tester.pumpAndSettle();
      expect(gateway.uploads, 0);
      expect(find.textContaining('Could not read this file.'), findsOneWidget);
    },
  );

  testWidgets(
    'upload has progress, prevents duplicate actions and retries same file',
    (tester) async {
      final gateway = FakeGateway()..uploadFails = true;
      final picker = FakePicker();
      await showPanel(tester, gateway, picker: picker);
      await tester.tap(find.text('Add attachment'));
      await tester.pumpAndSettle();
      expect(gateway.uploads, 1);
      expect(find.text('Retry'), findsOneWidget);
      gateway.uploadFails = false;
      gateway.pendingUpload = Completer<void>();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(gateway.uploads, 2);
      expect(picker.calls, 1);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('attachment-add')))
            .onPressed,
        isNull,
      );
      gateway.pendingUpload!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('delete requires explicit confirmation and uses selected item', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await showPanel(tester, gateway);
    await chooseAction(tester, 'delete');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.deletes, 0);
    await chooseAction(tester, 'delete');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(gateway.deletes, 1);
    expect(find.text('No attachments yet.'), findsOneWidget);
  });

  testWidgets(
    'account change during file selection never uploads selected bytes',
    (tester) async {
      final gateway = FakeGateway(),
          picker = FakePicker()..pending = Completer<PickedAttachmentFile?>();
      await showPanel(tester, gateway, picker: picker);
      await tester.tap(find.text('Add attachment'));
      await tester.pump();
      gateway.isCurrent = false;
      picker.pending!.complete(
        PickedAttachmentFile(name: 'a.pdf', bytes: Uint8List(4)),
      );
      await tester.pumpAndSettle();
      expect(gateway.uploads, 0);
      expect(find.textContaining('Access or account changed.'), findsOneWidget);
    },
  );

  testWidgets('late download after account change cannot reach exporter', (
    tester,
  ) async {
    final gateway = FakeGateway()..pendingDownload = Completer<Uint8List>();
    final exporter = FakeExporter();
    await showPanel(tester, gateway, exporter: exporter);
    await chooseAction(tester, 'save');
    await tester.pump();
    gateway.isCurrent = false;
    gateway.pendingDownload!.complete(Uint8List(4));
    await tester.pumpAndSettle();
    expect(exporter.calls, 0);
    expect(find.text('Načrt.pdf'), findsNothing);
  });

  testWidgets('lost edit rights while confirmation is open blocks deletion', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await showPanel(tester, gateway);
    await chooseAction(tester, 'delete');
    await tester.pumpAndSettle();
    gateway.isCurrent = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(gateway.deletes, 0);
  });

  testWidgets('rejects foreign target metadata and retries failed list', (
    tester,
  ) async {
    final gateway = FakeGateway()
      ..items = [fixtureAttachment(scopeId: 'other-scope')];
    await showPanel(tester, gateway);
    expect(find.text('Načrt.pdf'), findsNothing);
    expect(find.text('Could not load attachments.'), findsOneWidget);
    gateway.items = [fixtureAttachment()];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Načrt.pdf'), findsOneWidget);
  });

  testWidgets(
    'reader reports selected attachment from one menu without mutation controls',
    (tester) async {
      final gateway = FakeGateway();
      AttachmentMetadata? reported;
      await showPanel(
        tester,
        gateway,
        canEdit: false,
        onReport: (attachment) async {
          reported = attachment;
        },
      );
      await openMenu(tester);
      expect(
        find.byKey(const ValueKey('attachment-delete-attachment-1')),
        findsNothing,
      );
      expect(find.text('Save a copy'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('attachment-report-attachment-1')),
      );
      await tester.pumpAndSettle();
      expect(reported!.id, 'attachment-1');
      expect(reported!.target, gateway.target);
      expect(gateway.deletes, 0);
      expect(gateway.downloads, 0);
    },
  );

  testWidgets('backend denial on refresh hides old rows and all menus', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await showPanel(tester, gateway);
    expect(find.text('Načrt.pdf'), findsOneWidget);
    gateway.denyList = true;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Načrt.pdf'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byKey(const ValueKey('attachment-add')), findsNothing);
    expect(find.textContaining('Access or account changed.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final locale in ['en', 'sl']) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'attachments layout $width $locale $brightness ${scale}x',
            (tester) async {
              tester.view.physicalSize = Size(width, 1100);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              await showPanel(
                tester,
                FakeGateway(),
                locale: Locale(locale),
                brightness: brightness,
                scale: scale,
                onReport: (_) async {},
              );
              expect(find.text('Načrt.pdf'), findsOneWidget);
              await openMenu(tester);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }
}
