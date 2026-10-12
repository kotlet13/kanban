import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/presentation/ideas/idea_canvas.dart';
import 'package:kanban/organizer/presentation/ideas/idea_editor.dart';
import 'package:kanban/organizer/presentation/ideas/idea_conflict_preview.dart';
import 'package:kanban/organizer/presentation/shared/sharing_conflicts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../data/collaboration_moderation_test.dart' show ModerationServer;
import '../data/private_sync_test_support.dart' show PersonalTransport;
import '../data/collaboration_repository_test.dart' show FakeServer;
import 'ideas_ui_test.dart' as harness;

class IdeaUiServer extends ModerationServer {
  late IdeaAsset asset;
  late Uint8List bytes;
  bool missingImage = false;
  @override
  Future<Map<String, dynamic>> call(
    String op,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (op == 'capabilities') {
      return {
        ...await super.call(op, params, token),
        'recordContractVersions': [1, 5],
      };
    }
    if (op.startsWith('sync5.')) {
      return super.call(op.replaceFirst('sync5.', 'sync.'), params, token);
    }
    if (op == 'scopes.members') {
      return {
        'members': [
          for (final m in members[params['scopeId']]!.entries)
            {
              'userId': 1,
              'accountId': accountIds[m.key],
              'username': m.key,
              'displayName': m.key,
              'role': m.value,
              'active': true,
            },
        ],
      };
    }
    if (op.startsWith('ideas.asset.')) {
      calls.add((operation: op, token: token, params: params));
      if (missingImage) throw const CollaborationException('network');
      return {
        ...asset.toJson(),
        'offset': params['offset'] ?? asset.size,
        'complete': true,
        'data': base64Encode(bytes.sublist(params['offset'] as int? ?? 0)),
      };
    }
    final result = await super.call(op, params, token);
    if (op == 'moderation.reportPreview') {
      final board =
          (records[params['scopeId']]![params['targetId']]!['payload'] as Map)
              .cast<String, dynamic>();
      return {
        ...result,
        'subject': {'title': board['title'], 'type': 'idea'},
        'evidence': {
          'board': board,
          'assets': [asset.toJson()],
        },
      };
    }
    return result;
  }
}

Future<(harness.Fixture, IdeaUiServer, String)> sharedFixture(
  WidgetTester tester, {
  bool viewer = false,
}) async {
  final server = IdeaUiServer();
  final f = await harness.fixture(tester, server: server);
  return (await tester.runAsync(() async {
    server.bytes = Uint8List.fromList(
      img.encodePng(
        img.Image(width: 500, height: 350)..clear(img.ColorRgb8(145, 184, 225)),
      ),
    );
    server.asset = await f.ideas.importImage(server.bytes);
    server.bytes = (await f.ideas.readAsset(server.asset))!;
    await f.shared.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    final scope = await f.shared.createScope('Skupni Idejnik');
    await f.shared.selectSpace(scope);
    final board = IdeaBoard(
      id: harness.boardId,
      title: 'Prenova kotička',
      createdAt: harness.now,
      updatedAt: harness.now,
      revision: 1,
      elements: [
        IdeaElement(
          id: harness.imageId,
          kind: IdeaElementKind.image,
          x: 80,
          y: 80,
          width: 800,
          height: 560,
          asset: server.asset,
        ),
        IdeaElement(
          id: harness.strokeId,
          kind: IdeaElementKind.sticky,
          x: 940,
          y: 140,
          width: 390,
          height: 200,
          text: 'Polica nad pisalno mizo',
          color: 0xffffde80,
        ),
      ],
    );
    server.records[scope]![board.id] = {
      'id': board.id,
      'type': 'idea',
      'revision': 1,
      'deleted': false,
      'payload': board.toJson(),
      'sequence': 1,
      'updatedAt': harness.now.toIso8601String(),
    };
    server.sequence[scope] = 1;
    if (viewer) server.members[scope]!['alice'] = 'viewer';
    await f.shared.syncNow();
    expect(
      f.shared.state.lastError,
      isNull,
      reason:
          '${f.shared.state.lastError} ${server.calls.map((c) => c.operation).toList()}',
    );
    expect(f.shared.state.data[scope]?.ideas, isNotEmpty);
    await f.ideas.close();
    final ideas = IdeaRepository(
      SharedIdeaStorage(f.shared, f.shared.state.session!.partition, scope),
    );
    await ideas.initialize();
    await ideas.ensureAssets(board);
    return (harness.Fixture(f.db, ideas, f.organizer, f.shared), server, scope);
  }))!;
}

void main() {
  testWidgets(
    'explicit local source stays readable while private provider shadows local; review never silently imports',
    (tester) async {
      late Directory legacy;
      await tester.runAsync(() async {
        legacy = await Directory.systemTemp.createTemp('ideas-empty-legacy-');
      });
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        paths,
        (call) async => legacy.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          paths,
          null,
        ),
      );
      final f = await harness.fixture(
        tester,
        transport: PersonalTransport(FakeServer()),
      );
      late IdeaRepository privateIdeas;
      await tester.runAsync(() async {
        await f.shared.login(
          serverUrl: 'https://test.invalid',
          username: 'alice',
          password: 'test',
        );
        await f.shared.enablePrivateSync(
          expectedRevision: (await f.shared.previewPrivateSync()).revision,
        );
        await f.shared.signOut();
        await f.ideas.saveBoard(
          IdeaBoard(
            id: harness.boardId,
            title: 'Lokalna tabla po odjavi',
            createdAt: harness.now,
            updatedAt: harness.now,
          ),
          isNew: true,
        );
        await f.shared.login(
          serverUrl: 'https://test.invalid',
          username: 'alice',
          password: 'test',
        );
        privateIdeas = IdeaRepository(
          SharedIdeaStorage(
            f.shared,
            f.shared.state.session!.partition,
            f.shared.state.privateSync.scopeId!,
          ),
        );
        await privateIdeas.initialize();
      });
      final active = harness.Fixture(f.db, privateIdeas, f.organizer, f.shared);
      var reviewed = 0;
      await harness.pumpIdeas(
        tester,
        active,
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => openLocalIdeaViewer(
              context,
              ref,
              spaceId: 'local',
              boardId: harness.boardId,
              onReviewPrivate: () => reviewed++,
            ),
            child: const Text('Local source'),
          ),
        ),
      );
      expect(privateIdeas.snapshot.boards, isEmpty);
      await tester.tap(find.text('Local source'));
      await harness.settle(tester);
      expect(find.byType(IdeaEditor), findsOneWidget);
      expect(
        tester.widget<IdeaEditor>(find.byType(IdeaEditor)).board.title,
        'Lokalna tabla po odjavi',
      );
      expect(find.byKey(const ValueKey('idea-save')), findsNothing);
      expect(find.byKey(const ValueKey('editor-report')), findsNothing);
      expect(find.textContaining('Ta tabla ostane lokalna'), findsOneWidget);
      expect(reviewed, 0);
      await tester.tap(find.byKey(const ValueKey('idea-review-private')));
      await harness.settle(tester);
      expect(reviewed, 1);
      expect(privateIdeas.snapshot.boards, isEmpty);
      expect(
        (await tester.runAsync(
          () => f.ideas.storage.readAll(),
        ))!.boards.single.id,
        harness.boardId,
      );
      expect(tester.takeException(), isNull);
      final extraClose = f.ideas.close();
      await harness.settle(tester);
      await tester.runAsync(() => extraClose);
      await harness.close(tester, active);
    },
  );

  testWidgets(
    'read-only shared editor reports full immutable photo board only on explicit Send',
    (tester) async {
      final (f, server, _) = await sharedFixture(tester, viewer: true);
      await harness.pumpIdeas(tester, f);
      await tester.tap(
        find.byKey(const ValueKey('idea-card-${harness.boardId}')),
      );
      await harness.settle(tester);
      expect(
        find.byType(IdeaEditor),
        findsOneWidget,
        reason:
            '${f.shared.state.scopes.map((s) => (s.kind, s.role, s.blocked)).toList()} ${f.ideas.snapshot.sharedScopeId}',
      );
      expect(find.byKey(const ValueKey('idea-save')), findsNothing);
      expect(find.byKey(const ValueKey('editor-report')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(harness.captureKey),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/qa/ideas/idea-phone-shared.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byKey(const ValueKey('editor-report')));
      await harness.settle(tester);
      expect(server.reports, 0);
      final canvas = tester.widget<IdeaCanvas>(find.byType(IdeaCanvas).last);
      expect(canvas.editable, false);
      expect(canvas.images, hasLength(1));
      expect(canvas.board.elements.last.text, 'Polica nad pisalno mizo');
      await tester.ensureVisible(find.byKey(const ValueKey('report-reason')));
      await tester.tap(find.byKey(const ValueKey('report-reason')));
      await harness.settle(tester);
      await tester.tap(find.text('Drugo').last);
      await harness.settle(tester);
      expect(server.reports, 0);
      await tester.ensureVisible(find.byKey(const ValueKey('report-send')));
      await tester.tap(find.byKey(const ValueKey('report-send')));
      await harness.settle(tester);
      expect(server.reports, 1);
      expect(tester.takeException(), isNull);
      await harness.close(tester, f);
    },
  );

  testWidgets(
    'same-element conflict shows both actual boards and photos before explicit resolution',
    (tester) async {
      final (f, server, scope) = await sharedFixture(tester);
      final base = f.ideas.snapshot.boards.single;
      await tester.runAsync(() async {
        await f.ideas.updateBoard(
          base.copyWith(
            elements: [
              base.elements.first,
              base.elements.last.copyWith(text: 'Moja polica'),
            ],
          ),
          base: base,
        );
        final record = server.records[scope]![base.id]!;
        record['revision'] = 2;
        record['sequence'] = 2;
        record['payload'] = base
            .copyWith(
              revision: 2,
              elements: [
                base.elements.first,
                base.elements.last.copyWith(text: 'Druga polica'),
              ],
            )
            .toJson();
        server.sequence[scope] = 2;
        await f.shared.syncNow();
      });
      expect(f.shared.state.conflicts, hasLength(1));
      await harness.pumpIdeas(
        tester,
        f,
        width: 800,
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showSharingConflicts(context, ref),
            child: const Text('Compare'),
          ),
        ),
      );
      await tester.tap(find.text('Compare'));
      await harness.settle(tester);
      expect(find.byType(IdeaConflictPreview), findsNWidgets(2));
      final boards = tester
          .widgetList<IdeaCanvas>(find.byType(IdeaCanvas))
          .toList();
      expect(boards, hasLength(2));
      expect(boards.every((b) => b.images.length == 1 && !b.editable), true);
      expect(find.text('Moja polica'), findsOneWidget);
      expect(find.text('Druga polica'), findsOneWidget);
      expect(f.shared.state.conflicts, hasLength(1));
      await tester.ensureVisible(find.text('Obdrži strežniško različico'));
      await tester.tap(find.text('Obdrži strežniško različico'));
      await harness.settle(tester);
      expect(f.shared.state.conflicts, isEmpty);
      expect(tester.takeException(), isNull);
      await harness.close(tester, f);
    },
  );

  testWidgets(
    '320 large text keyboard keeps shared editor Save and report accessible',
    (tester) async {
      final (f, _, _) = await sharedFixture(tester);
      await harness.pumpIdeas(tester, f, width: 320, textScale: 1.3);
      await tester.tap(
        find.byKey(const ValueKey('idea-card-${harness.boardId}')),
      );
      await harness.settle(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.tap(find.byKey(const ValueKey('idea-title')));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('idea-save'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(find.byKey(const ValueKey('editor-report')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.close(tester, f);
    },
  );
}
