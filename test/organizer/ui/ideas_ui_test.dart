import '../support/synthetic_content_route_guard.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/data/idea_storage.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/presentation/ideas/idea_canvas.dart';
import 'package:kanban/organizer/presentation/ideas/idea_editor.dart';
import 'package:kanban/organizer/presentation/ideas/ideas_page.dart';
import 'package:kanban/organizer/presentation/ideas/ideas_all_spaces_page.dart';
import 'package:kanban/organizer/state/idea_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../data/collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;
import 'all_spaces_ui_test.dart' show loadQaFonts;

const boardId = '11111111-1111-4111-8111-111111111111';
const imageId = '22222222-2222-4222-8222-222222222222';
const strokeId = '33333333-3333-4333-8333-333333333333';
final now = DateTime.utc(2026, 10, 12);
final captureKey = GlobalKey();

class Fixture {
  Fixture(this.db, this.ideas, this.organizer, this.shared);
  final CollaborationDatabase db;
  final IdeaRepository ideas;
  final OrganizerRepository organizer;
  final CollaborationRepository shared;
}

Future<Fixture> fixture(
  WidgetTester tester, {
  FakeServer? server,
  CollaborationTransport? transport,
}) async => (await tester.runAsync(() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = CollaborationDatabase(NativeDatabase.memory());
  final organizer = OrganizerRepository(SqliteOrganizerStorage(db));
  await organizer.initialize();
  await LocalSpacesRepository(db).read();
  final shared = CollaborationRepository(
    db,
    transport ?? FakeTransport(server ?? FakeServer()),
    MemorySessionStore(),
    contentRouteGuard: const SyntheticContentRouteGuard(),
  );
  await shared.initialize();
  final ideas = IdeaRepository(IdeaStorage(db));
  await ideas.initialize();
  return Fixture(db, ideas, organizer, shared);
}))!;
Future<void> pumpIdeas(
  WidgetTester tester,
  Fixture f, {
  double width = 360,
  String language = 'sl',
  Widget? body,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadQaFonts(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localDatabaseProvider.overrideWith((ref) async => f.db),
        ideaRepositoryProvider.overrideWith((ref) async => f.ideas),
        organizerRepositoryProvider.overrideWith((ref) async => f.organizer),
        collaborationRepositoryProvider.overrideWith((ref) async => f.shared),
      ],
      child: RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            fontFamily: 'Roboto',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff2865b3),
            ),
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(collaborationProvider);
                return SingleChildScrollView(child: body ?? const IdeasPage());
              },
            ),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}

Future<void> close(WidgetTester tester, Fixture f) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final closing = Future.wait([
    f.ideas.close(),
    f.organizer.close(),
    f.shared.close(),
  ]);
  await settle(tester);
  await tester.runAsync(() async {
    await closing;
    await f.db.close();
  });
}

Future<void> tapTool(WidgetTester tester, String tooltip) async {
  final finder = find.byTooltip(tooltip);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Offset point(WidgetTester tester, Offset p) {
  final viewer = tester.widget<InteractiveViewer>(
    find.byKey(const ValueKey('idea-viewport')),
  );
  return tester.getRect(find.byKey(const ValueKey('idea-viewport'))).topLeft +
      MatrixUtils.transformPoint(viewer.transformationController!.value, p);
}

Future<void> draw(WidgetTester tester, Offset start, Offset end) async {
  final gesture = await tester.startGesture(point(tester, start));
  await gesture.moveTo(point(tester, start + const Offset(24, 8)));
  await tester.pump();
  await gesture.moveTo(point(tester, end));
  await tester.pump();
  await gesture.up();
  await settle(tester);
}

IdeaBoard current(WidgetTester tester) =>
    tester.widget<IdeaCanvas>(find.byType(IdeaCanvas)).board;
void main() {
  for (final width in [360.0, 800.0, 1280.0]) {
    testWidgets(
      'real idea provider creates stroke, undo/redo and explicitly saves complete board $width',
      (tester) async {
        final f = await fixture(tester);
        await pumpIdeas(tester, f, width: width);
        await tester.tap(find.byKey(const ValueKey('idea-add')));
        await settle(tester);
        await tester.enterText(
          find.byKey(const ValueKey('idea-title')),
          'Moja tabla',
        );
        tester.testTextInput.hide();
        await tapTool(tester, 'Pisalo');
        await draw(tester, const Offset(80, 80), const Offset(480, 310));
        final created = current(tester);
        expect(created.elements.single.kind, IdeaElementKind.stroke);
        expect(created.elements.single.points.length, greaterThan(1));
        expect(created.elements.single.x, closeTo(80, 2));
        expect(f.ideas.snapshot.boards, isEmpty);
        await tapTool(tester, 'Razveljavi');
        expect(current(tester).elements, isEmpty);
        await tapTool(tester, 'Uveljavi');
        expect(current(tester).elements.single.id, created.elements.single.id);
        await tester.tap(find.byKey(const ValueKey('idea-save')));
        await settle(tester);
        expect(find.byType(IdeaEditor), findsNothing);
        expect(f.ideas.snapshot.boards.single.title, 'Moja tabla');
        expect(
          f.ideas.snapshot.boards.single.elements.single.kind,
          IdeaElementKind.stroke,
        );
        expect(tester.takeException(), isNull);
        await close(tester, f);
      },
    );
  }
  testWidgets(
    'new local draft survives cancel and resumes without prepublishing',
    (tester) async {
      final f = await fixture(tester);
      await pumpIdeas(tester, f);
      await tester.tap(find.byKey(const ValueKey('idea-add')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('idea-title')),
        'Osnutek',
      );
      tester.testTextInput.hide();
      final id = current(tester).id;
      await tester.tap(find.byTooltip('Zapri'));
      await settle(tester);
      expect(f.ideas.snapshot.boards, isEmpty);
      expect(find.byKey(ValueKey('idea-draft-$id')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('idea-draft-$id')));
      await settle(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('idea-title')))
            .controller!
            .text,
        'Osnutek',
      );
      await tester.tap(find.byKey(const ValueKey('idea-save')));
      await settle(tester);
      expect(f.ideas.snapshot.boards.single.id, id);
      expect(f.ideas.snapshot.boards.single.title, 'Osnutek');
      expect(tester.takeException(), isNull);
      await close(tester, f);
    },
  );
  testWidgets(
    'real cached photo and attached marks transform together, persist editable and render readable preview',
    (tester) async {
      final f = await fixture(tester);
      late IdeaAsset asset;
      final bytes = Uint8List.fromList(
        img.encodePng(
          img.Image(width: 160, height: 100)
            ..clear(img.ColorRgb8(133, 188, 223)),
        ),
      );
      await tester.runAsync(() async {
        asset = await f.ideas.importImage(bytes);
        await f.ideas.saveBoard(
          IdeaBoard(
            id: boardId,
            title: 'Skupni kotiček',
            createdAt: now,
            updatedAt: now,
            elements: [
              IdeaElement(
                id: imageId,
                kind: IdeaElementKind.image,
                x: 120,
                y: 100,
                width: 500,
                height: 310,
                asset: asset,
              ),
              IdeaElement(
                id: strokeId,
                kind: IdeaElementKind.arrow,
                x: .2,
                y: .2,
                width: .4,
                height: .3,
                strokeWidth: .008,
                color: 0xffda3545,
                parentImageId: imageId,
                points: const [IdeaPoint(0, 0), IdeaPoint(.4, .3)],
              ),
            ],
          ),
          isNew: true,
        );
      });
      await pumpIdeas(tester, f, width: 1280);
      await tester.tap(find.byKey(const ValueKey('idea-card-$boardId')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('idea-elements')));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
      await tester.tap(find.byKey(const ValueKey('idea-element-$imageId')));
      await settle(tester);
      await tapTool(tester, 'Zavrti izbrani element');
      final rotated = current(tester);
      expect(rotated.elements.first.rotation, greaterThan(0));
      expect(rotated.elements.last.parentImageId, imageId);
      expect(rotated.elements.last.points.last.x, .4);
      await tester.tap(find.byKey(const ValueKey('idea-save')));
      await settle(tester);
      expect(
        f.ideas.snapshot.boards.single.elements.first.rotation,
        greaterThan(0),
      );
      expect(await tester.runAsync(() => f.ideas.readAsset(asset)), isNotNull);
      await tester.tap(find.byKey(const ValueKey('idea-card-$boardId')));
      await settle(tester);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/qa/ideas/idea-desktop.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      tester.view.physicalSize = const Size(360, 900);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/qa/ideas/idea-phone-editable.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await close(tester, f);
    },
  );

  for (final format in ['png', 'jpeg']) {
    testWidgets(
      'native picker $format imports verified bytes and drawing remains anchored to photo until explicit Save',
      (tester) async {
        final f = await fixture(tester);
        late Directory dir;
        late File photo;
        final bytes = Uint8List.fromList(
          format == 'png'
              ? img.encodePng(
                  img.Image(width: 160, height: 100)
                    ..clear(img.ColorRgb8(130, 180, 220)),
                )
              : img.encodeJpg(
                  img.Image(width: 160, height: 100)
                    ..clear(img.ColorRgb8(130, 180, 220)),
                ),
        );
        await tester.runAsync(() async {
          dir = await Directory.systemTemp.createTemp('idea-picker-');
          photo = File('${dir.path}/photo.$format');
          await photo.writeAsBytes(bytes);
        });
        FilePickerIO.registerWith();
        var picks = 0;
        final channel = MethodChannel(
          'miguelruivo.flutter.plugins.filepicker',
          Platform.isMacOS || Platform.isLinux || Platform.isWindows
              ? const JSONMethodCodec()
              : const StandardMethodCodec(),
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            picks++;
            expect(call.method, 'custom');
            expect((call.arguments as Map)['allowedExtensions'], [
              'jpg',
              'jpeg',
              'png',
            ]);
            return [
              {
                'path': photo.path,
                'name': 'photo.$format',
                'size': bytes.length,
              },
            ];
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await pumpIdeas(tester, f, width: 1280);
        await tester.tap(find.byKey(const ValueKey('idea-add')));
        await settle(tester);
        await tapTool(tester, 'Dodaj fotografijo');
        final image = current(tester).elements.single;
        expect(image.kind, IdeaElementKind.image);
        expect(picks, 1);
        expect(f.ideas.snapshot.boards, isEmpty);
        await tapTool(tester, 'Puščica');
        await draw(tester, const Offset(100, 100), const Offset(210, 160));
        final arrow = current(tester).elements.last;
        expect(arrow.kind, IdeaElementKind.arrow);
        expect(arrow.parentImageId, image.id);
        expect(arrow.points.length, 2);
        await tester.tap(find.byKey(const ValueKey('idea-elements')));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 3),
        );
        await tester.tap(find.byKey(ValueKey('idea-element-${image.id}')));
        await settle(tester);
        await tapTool(tester, 'Zavrti izbrani element');
        expect(current(tester).elements.first.rotation, greaterThan(0));
        expect(current(tester).elements.last.parentImageId, image.id);
        await tester.tap(find.byKey(const ValueKey('idea-save')));
        await settle(tester);
        final saved = f.ideas.snapshot.boards.single;
        expect(saved.elements.length, 2);
        expect(saved.elements.last.parentImageId, saved.elements.first.id);
        expect(
          await tester.runAsync(() => f.ideas.readAsset(saved.assets.first)),
          isNotNull,
        );
        expect(tester.takeException(), isNull);
        await close(tester, f);
        await tester.runAsync(() => dir.delete(recursive: true));
      },
    );
  }
  testWidgets(
    'actual canvas supports line, rectangle, ellipse, marker and erasing with undo',
    (tester) async {
      final f = await fixture(tester);
      await pumpIdeas(tester, f, width: 1280);
      await tester.tap(find.byKey(const ValueKey('idea-add')));
      await settle(tester);
      for (final tool in [
        ('Črta', IdeaElementKind.line),
        ('Pravokotnik', IdeaElementKind.rectangle),
        ('Elipsa', IdeaElementKind.ellipse),
        ('Označevalnik', IdeaElementKind.stroke),
      ]) {
        await tapTool(tester, tool.$1);
        await draw(tester, const Offset(100, 100), const Offset(430, 250));
        expect(current(tester).elements.last.kind, tool.$2);
      }
      expect(current(tester).elements.last.color >> 24, 0x66);
      await tapTool(tester, 'Radirka');
      await draw(tester, const Offset(100, 100), const Offset(430, 250));
      expect(current(tester).elements.length, lessThan(4));
      await tapTool(tester, 'Razveljavi');
      expect(current(tester).elements.length, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
      await close(tester, f);
    },
  );
  testWidgets(
    'All reads actual local entries and asks explicit creation space',
    (tester) async {
      final f = await fixture(tester);
      await tester.runAsync(
        () => f.ideas.saveBoard(
          IdeaBoard(
            id: boardId,
            title: 'Vsi zapis',
            createdAt: now,
            updatedAt: now,
          ),
          isNew: true,
        ),
      );
      (bool, String, String?)? chosen;
      await pumpIdeas(
        tester,
        f,
        body: IdeasAllSpacesPage(
          onOpenSource:
              ({
                required bool shared,
                required String spaceId,
                String? boardId,
              }) async {
                chosen = (shared, spaceId, boardId);
              },
        ),
      );
      expect(find.byKey(const ValueKey('idea-card-$boardId')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('idea-all-add')));
      await settle(tester);
      expect(chosen, isNull);
      expect(find.byType(SimpleDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('idea-target-local-local')));
      await settle(tester);
      expect(chosen, (false, 'local', null));
      expect(f.ideas.snapshot.boards.length, 1);
      expect(tester.takeException(), isNull);
      await close(tester, f);
    },
  );
  testWidgets(
    'read-only board uses actual provider without edit/save controls',
    (tester) async {
      final f = await fixture(tester);
      final b = IdeaBoard(
        id: boardId,
        title: 'Bralni pogled',
        createdAt: now,
        updatedAt: now,
      );
      await tester.runAsync(() => f.ideas.saveBoard(b, isNew: true));
      await pumpIdeas(
        tester,
        f,
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => IdeaEditor(
                  board: b,
                  base: b,
                  workspaceKey: 'local',
                  canEdit: false,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(find.byKey(const ValueKey('idea-save')), findsNothing);
      expect(find.byKey(const ValueKey('idea-tool-pen')), findsNothing);
      expect(find.byKey(const ValueKey('editor-report')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('idea-title')))
            .readOnly,
        true,
      );
      expect(tester.takeException(), isNull);
      await close(tester, f);
    },
  );
}
