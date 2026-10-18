import '../support/synthetic_content_route_guard.dart';
// Opt-in synthetic loopback only; no live accounts or user photographs.
// JIVIE_IDEAS_HTTP_FIXTURE=/private/fixture.json flutter test --no-pub this-file
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/data/idea_storage.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;

class _IdeaHttp extends HttpCollaborationTransport {
  bool offline = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) {
    if (offline) throw const CollaborationException('network');
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

IdeaElement _note(String id, String text) => IdeaElement(
  id: id,
  kind: IdeaElementKind.sticky,
  x: 240,
  y: 40,
  width: 200,
  height: 120,
  text: text,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['JIVIE_IDEAS_HTTP_FIXTURE'];
  test(
    'real Dart/PHP: image boards, member notifications, element rebase, offline restart and standalone encrypted restore',
    () async {
      final fixture =
          jsonDecode(await File(path!).readAsString()) as Map<String, dynamic>;
      final server = fixture['server'] as String;
      if (fixture['synthetic'] != true ||
          server != 'http://127.0.0.1:18383' ||
          fixture['container'] !=
              'kanban-familyhub-account-ideas-20261012-kanboard-1') {
        throw StateError('Dedicated synthetic loopback fixture required');
      }
      // Each run gets its own accounts/policy state; prior interrupted runs may
      // remain in this deliberately persistent synthetic fixture.
      final seeded = await Process.run('docker', [
        'exec',
        fixture['container'] as String,
        'php',
        '/familyhub-tests/ideas-client-http-fixture.php',
        'seed',
      ]);
      expect(seeded.exitCode, 0, reason: 'Fresh synthetic client accounts');
      fixture.addAll(
        jsonDecode(seeded.stdout as String) as Map<String, dynamic>,
      );
      final dir = await Directory.systemTemp.createTemp('ideas-http-');
      final repos = <CollaborationRepository>[];
      final ideas = <IdeaRepository>[];
      final stores = <String, MemorySessionStore>{};
      Future<CollaborationRepository> open(
        String role,
        String file,
        _IdeaHttp transport, {
        bool login = true,
      }) async {
        final repo = CollaborationRepository(
          CollaborationDatabase(
            NativeDatabase(File('${dir.path}/$file.sqlite')),
          ),
          transport,
          stores.putIfAbsent(file, MemorySessionStore.new),
          contentRouteGuard: const SyntheticContentRouteGuard(),
        );
        repos.add(repo);
        await repo.initialize();
        if (login) {
          final user = fixture[role] as Map;
          await repo.login(
            serverUrl: server,
            username: user['username'] as String,
            password: user['password'] as String,
            allowLocalHttp: true,
          );
        }
        return repo;
      }

      Future<IdeaRepository> boardRepo(
        CollaborationRepository repo,
        String scope,
      ) async {
        final result = IdeaRepository(
          SharedIdeaStorage(repo, repo.state.session!.partition, scope),
        );
        ideas.add(result);
        await result.initialize();
        return result;
      }

      Future<void> sync(CollaborationRepository repo) async {
        await repo.syncNow();
        expect(repo.state.lastError, isNull, reason: 'Complete real HTTP sync');
      }

      Matcher error(String code) => throwsA(
        isA<CollaborationException>().having((e) => e.code, 'code', code),
      );
      try {
        final a = await open('owner', 'a', _IdeaHttp());
        var bTransport = _IdeaHttp();
        var b = await open('member', 'b', bTransport);
        final outsider = await open('outsider', 'c', _IdeaHttp());
        await a.acceptSharedContentPolicy(await a.sharedContentPolicy());
        final scope = await a.createScope(
          'Synthetic idea collaboration ${newSharedId()}',
        );
        final joined = await Process.run('docker', [
          'exec',
          fixture['container'] as String,
          'php',
          '/familyhub-tests/ideas-client-http-fixture.php',
          'join',
          scope,
          b.state.session!.accountId,
        ]);
        expect(
          joined.exitCode,
          0,
          reason:
              'Synthetic policy3 membership setup, not an SMTP invitation proof',
        );
        await sync(b);
        final ia = await boardRepo(a, scope);
        final asset = await ia.importImage(
          Uint8List.fromList(image.encodePng(image.Image(width: 8, height: 6))),
        );
        final originalBytes = await ia.readAsset(asset);
        final id = newSharedId(),
            photoId = newSharedId(),
            left = newSharedId(),
            right = newSharedId();
        final now = DateTime.now().toUtc();
        final board = IdeaBoard(
          id: id,
          title: 'Synthetic photo and annotations',
          createdAt: now,
          updatedAt: now,
          elements: [
            IdeaElement(
              id: photoId,
              kind: IdeaElementKind.image,
              x: 10,
              y: 10,
              width: 160,
              height: 120,
              asset: asset,
            ),
            IdeaElement(
              id: newSharedId(),
              kind: IdeaElementKind.stroke,
              parentImageId: photoId,
              x: 0,
              y: 0,
              width: 1,
              height: 1,
              strokeWidth: .015,
              points: const [IdeaPoint(.1, .1), IdeaPoint(.8, .8)],
            ),
            _note(left, 'left'),
            _note(right, 'right'),
          ],
        );
        await ia.saveBoard(board, isNew: true);
        await sync(a);
        await sync(b);
        expect(a.state.pendingCount, 0);
        var ib = await boardRepo(b, scope);
        expect(ib.snapshot.boards.single.id, id);
        expect(await ib.readAsset(asset), originalBytes);
        final events = b.state.inbox
            .where((e) => e.targetType == 'idea' && e.targetId == id)
            .toList();
        expect(events.length, 1);
        expect(events.single.category, 'ideas');
        final target = NotificationTarget(
          serverUrl: b.state.session!.serverUrl,
          serverId: b.state.session!.serverId,
          accountId: b.state.session!.accountId,
          scopeId: scope,
          records: [NotificationRecordTarget(type: 'idea', recordId: id)],
          inboxIds: [events.single.id],
        );
        expect(
          (await b.openNotificationTarget(target)).status,
          NotificationOpenStatus.available,
        );
        final preview = await b.previewContentReport(
          scopeId: scope,
          targetType: 'record',
          targetId: id,
        );
        expect((preview.evidence['board'] as Map)['id'], id);
        expect(await b.loadReportIdeaAsset(preview, asset), originalBytes);
        await expectLater(
          a.loadReportIdeaAsset(preview, asset),
          error('session_changed'),
        );
        await expectLater(
          outsider.previewContentReport(
            scopeId: scope,
            targetType: 'record',
            targetId: id,
          ),
          error('permission_revoked'),
        );
        expect((await b.sharedContentPolicy()).accepted, false);
        await b.acceptSharedContentPolicy(await b.sharedContentPolicy());

        // Explicit personal opt-in imports anonymous boards and their actual
        // images without requiring shared-content acceptance or corrupting the
        // ordinary organizer projection.
        final personalText = SqliteOrganizerStorage(outsider.database);
        await personalText.initialize();
        final personal = IdeaRepository(IdeaStorage(outsider.database));
        ideas.add(personal);
        await personal.initialize();
        final personalAsset = await personal.importImage(
          Uint8List.fromList(image.encodePng(image.Image(width: 4, height: 3))),
        );
        final personalBoard = IdeaBoard(
          id: newSharedId(),
          title: 'Anonymous idea before explicit private opt-in',
          createdAt: now,
          updatedAt: now,
          elements: [
            IdeaElement(
              id: newSharedId(),
              kind: IdeaElementKind.image,
              x: 0,
              y: 0,
              width: 80,
              height: 60,
              asset: personalAsset,
            ),
          ],
        );
        await personal.saveBoard(personalBoard, isNew: true);
        final privateDraft = personalBoard.copyWith(
          id: newSharedId(),
          title: 'Unsaved private photo draft',
        );
        await personal.saveDraft(privateDraft);
        final personalOriginalBytes = await personal.readAsset(personalAsset);
        final privatePreview = await outsider.previewPrivateSync();
        expect(privatePreview.recordCounts['ideas'], 1);
        expect(privatePreview.recordCounts['ideaDrafts'], 1);
        expect(privatePreview.canEnable, true);
        await outsider.enablePrivateSync(
          expectedRevision: privatePreview.revision,
        );
        expect((await outsider.sharedContentPolicy()).accepted, false);
        final privateScope = outsider.state.privateSync.scopeId!;
        final privateIdeas = await boardRepo(outsider, privateScope);
        expect(privateIdeas.snapshot.boards.single.id, personalBoard.id);
        expect((await privateIdeas.listDrafts()).single.id, privateDraft.id);
        expect(
          (await IdeaStorage(outsider.database).readAll()).boards,
          isEmpty,
        );
        expect(
          await privateIdeas.readAsset(personalAsset),
          personalOriginalBytes,
        );
        expect((await personalText.read()).projects, isEmpty);

        // Publish both a direct local organization board and a project board.
        // The root's mapping must copy image bytes to each exact shared scope.
        await outsider.acceptSharedContentPolicy(
          await outsider.sharedContentPolicy(),
        );
        final localSpaces = LocalSpacesRepository(outsider.database);
        final localOrg = await localSpaces.createSpace(
          kind: LocalSpaceKind.organization,
          name: 'Synthetic local idea organization',
        );
        await localSpaces.selectSpace(localOrg.id);
        final organizer = OrganizerRepository(
          SqliteOrganizerStorage(outsider.database),
        );
        await organizer.initialize();
        try {
          await organizer.createProject(title: 'Synthetic idea project');
        } finally {
          await organizer.close();
        }
        final project = (await SqliteOrganizerStorage(
          outsider.database,
        ).read()).projects.single;
        final localOrgIdeas = IdeaRepository(IdeaStorage(outsider.database));
        ideas.add(localOrgIdeas);
        await localOrgIdeas.initialize();
        final orgAsset = await localOrgIdeas.importImage(
          Uint8List.fromList(image.encodePng(image.Image(width: 4, height: 3))),
        );
        final rootBoard = IdeaBoard(
          id: newSharedId(),
          title: 'Direct organization board',
          createdAt: now,
          updatedAt: now,
          elements: [
            IdeaElement(
              id: newSharedId(),
              kind: IdeaElementKind.image,
              x: 0,
              y: 0,
              width: 80,
              height: 60,
              asset: orgAsset,
            ),
          ],
        );
        final projectBoard = rootBoard.copyWith(
          id: newSharedId(),
          title: 'Scoped project board',
          projectId: project.id,
        );
        await localOrgIdeas.saveBoard(rootBoard, isNew: true);
        await localOrgIdeas.saveBoard(projectBoard, isNew: true);
        final projectDraft = projectBoard.copyWith(
          id: newSharedId(),
          title: 'Unsaved project photo draft',
        );
        await localOrgIdeas.saveDraft(projectDraft);
        final publication = await outsider.previewLocalSpacesPublication([
          localOrg.id,
        ]);
        expect(publication.canPublish, true);
        expect(publication.spaces.single.ideaCount, 2);
        expect(publication.spaces.single.ideaDraftCount, 1);
        expect(publication.spaces.single.projects.single.ideaCount, 1);
        expect(publication.spaces.single.projects.single.ideaDraftCount, 1);
        await outsider.publishLocalSpaces(publication);
        expect(outsider.state.lastError, isNull);
        expect(outsider.state.pendingCount, 0);
        final linked = (await localSpaces.read()).spaces
            .singleWhere((s) => s.id == localOrg.id)
            .binding!;
        expect(
          outsider.state.dataForScope(linked.scopeId).ideas.single.id,
          rootBoard.id,
        );
        expect(
          outsider.state.dataForScope(project.id).ideas.single.id,
          projectBoard.id,
        );
        final publishedRoot = await boardRepo(outsider, linked.scopeId);
        final publishedChild = await boardRepo(outsider, project.id);
        expect((await publishedChild.listDrafts()).single.id, projectDraft.id);
        expect(publishedChild.snapshot.boards, hasLength(1));
        expect(
          await publishedRoot.readAsset(orgAsset),
          await localOrgIdeas.readAsset(orgAsset),
        );
        expect(
          await publishedChild.readAsset(orgAsset),
          await localOrgIdeas.readAsset(orgAsset),
        );

        // Independent edits share a base. The stale immutable operation becomes
        // an archived request and a new operation rather than a rewritten retry.
        await ia.reload();
        await ib.reload();
        final baseA = ia.snapshot.boards.single,
            baseB = ib.snapshot.boards.single;
        await ia.saveBoard(
          baseA.copyWith(
            elements: baseA.elements.map(
              (e) => e.id == left ? e.copyWith(text: 'owner edit') : e,
            ),
          ),
          base: baseA,
        );
        await sync(a);
        await ib.saveBoard(
          baseB.copyWith(
            elements: baseB.elements.map(
              (e) => e.id == right ? e.copyWith(text: 'member edit') : e,
            ),
          ),
          base: baseB,
        );
        await sync(b);
        await sync(b);
        await sync(a);
        await ia.reload();
        final merged = ia.snapshot.boards.single;
        expect(
          merged.elements.singleWhere((e) => e.id == left).text,
          'owner edit',
        );
        expect(
          merged.elements.singleWhere((e) => e.id == right).text,
          'member edit',
        );
        expect(
          await b.database.rows(
            "SELECT name FROM local_meta WHERE name LIKE 'idea_rebased_op:%'",
          ),
          isNotEmpty,
        );

        // Editing the same element preserves an explicit conflict and both bodies.
        await ib.reload();
        final sameA = ia.snapshot.boards.single,
            sameB = ib.snapshot.boards.single;
        await ia.saveBoard(
          sameA.copyWith(
            elements: sameA.elements.map(
              (e) => e.id == left ? e.copyWith(text: 'owner conflict') : e,
            ),
          ),
          base: sameA,
        );
        await sync(a);
        await ib.saveBoard(
          sameB.copyWith(
            elements: sameB.elements.map(
              (e) => e.id == left ? e.copyWith(text: 'member conflict') : e,
            ),
          ),
          base: sameB,
        );
        await b.syncNow();
        expect(b.state.conflicts.any((c) => c.recordId == id), true);
        final local = (await b.database.rows(
          'SELECT payload FROM records WHERE partition=? AND scope_id=? AND id=?',
          [b.state.session!.partition, scope, id],
        )).single;
        expect((local['payload'] as String).contains('member conflict'), true);
        final conflict = await b.database.rows(
          'SELECT remote FROM conflicts WHERE partition=? AND scope_id=? AND record_id=?',
          [b.state.session!.partition, scope, id],
        );
        expect(
          (conflict.single['remote'] as String).contains('owner conflict'),
          true,
        );

        bTransport.offline = true;
        await ib.close();
        ideas.remove(ib);
        await b.close();
        repos.remove(b);
        bTransport = _IdeaHttp()..offline = true;
        b = await open('member', 'b', bTransport, login: false);
        ib = await boardRepo(b, scope);
        expect(await ib.readAsset(asset), originalBytes);
        expect(
          ib.snapshot.boards.single.elements
              .singleWhere((e) => e.id == left)
              .text,
          'member conflict',
        );
        final localStorage = SqliteOrganizerStorage(b.database);
        await localStorage.initialize();
        final backup = PortableBackupRepository(
          b.database,
          localStorage,
          MemoryBackupUiPreferencesStore(),
          collaboration: () => b,
        );
        const password = 'synthetic idea backup password';
        final encrypted = await backup.exportEncryptedBackup(password);
        final fresh = CollaborationDatabase(NativeDatabase.memory());
        try {
          final freshStorage = SqliteOrganizerStorage(fresh);
          await freshStorage.initialize();
          final restored = PortableBackupRepository(
            fresh,
            freshStorage,
            MemoryBackupUiPreferencesStore(),
          );
          final result = await restored.restoreEncryptedBackup(
            encrypted,
            password,
            mode: BackupRestoreMode.replace,
            expectedPersonalRevision: (await freshStorage.read()).revision,
          );
          final review = await restored.reviewRestoredSpacesAsLocal(
            result.backupId,
            password,
          );
          final spaces = await restored.recoverRestoredSpacesAsLocal(
            review,
            password: password,
          );
          expect(spaces, isNotEmpty);
          final restoredSpace = spaces.singleWhere(
            (s) =>
                s.name == b.state.scopes.singleWhere((s) => s.id == scope).name,
          );
          fresh.activateLocalWorkspace(restoredSpace.id);
          final converted = await IdeaStorage(fresh).read();
          expect(converted.boards.single.id, isNot(id));
          expect(
            converted.boards.single.elements
                .where((e) => e.kind == IdeaElementKind.image)
                .single
                .asset!
                .sha256,
            asset.sha256,
          );
          final recovered = IdeaRepository(IdeaStorage(fresh));
          try {
            await recovered.initialize();
            expect(await recovered.readAsset(asset), originalBytes);
          } finally {
            await recovered.close();
          }
        } finally {
          await fresh.close();
        }
      } finally {
        for (final repo in ideas) {
          await repo.close();
        }
        for (final repo in repos) {
          await repo.close();
        }
        await dir.delete(recursive: true);
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
