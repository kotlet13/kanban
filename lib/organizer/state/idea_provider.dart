import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/idea_repository.dart';
export '../domain/idea_models.dart';
import 'local_spaces_provider.dart';
import '../data/idea_storage.dart';
import '../domain/idea_models.dart';
import 'local_database_provider.dart';
import 'collaboration_provider.dart';
import '../data/collaboration_repository.dart' show SharedIdeaStorage;

final ideaRepositoryProvider = FutureProvider<IdeaRepository>((ref) async {
  final db = await ref.watch(localDatabaseProvider.future);
  final selected = ref.watch(
    collaborationProvider.select(
      (state) => (
        state.valueOrNull?.session?.partition,
        state.valueOrNull?.selectedSpaceId,
        state.valueOrNull?.privateSync.enabled,
        state.valueOrNull?.privateSync.scopeId,
      ),
    ),
  );
  ref.watch(localSpacesProvider.select((s) => s.valueOrNull?.selectedSpaceId));
  final shared = await ref.watch(collaborationRepositoryProvider.future);
  final scope = shared.state.scopes
      .where(
        (s) =>
            s.id ==
            (selected.$2 ??
                (selected.$3 == true && db.selectedLocalWorkspaceId == 'local'
                    ? selected.$4
                    : null)),
      )
      .firstOrNull;
  final storage = scope == null || selected.$1 == null
      ? IdeaStorage(db)
      : SharedIdeaStorage(shared, selected.$1!, scope.id);
  final repository = IdeaRepository(storage);
  ref.onDispose(() => unawaited(repository.close()));
  await repository.initialize();
  return repository;
});
final ideaProvider = AsyncNotifierProvider<IdeaController, IdeaSnapshot>(
  IdeaController.new,
);

class IdeaController extends AsyncNotifier<IdeaSnapshot> {
  IdeaRepository? _repository;
  @override
  Future<IdeaSnapshot> build() async {
    var active = true;
    StreamSubscription<IdeaSnapshot>? subscription;
    ref.onDispose(() {
      active = false;
      unawaited(subscription?.cancel());
    });
    final repository = await ref.watch(ideaRepositoryProvider.future);
    if (!active) {
      return repository.snapshot;
    }
    _repository = repository;
    subscription = repository.changes.listen(
      (snapshot) {
        if (active) {
          state = AsyncData(snapshot);
        }
      },
      onError: (Object e, StackTrace s) {
        if (active) {
          state = AsyncError(e, s);
        }
      },
    );
    return repository.snapshot;
  }

  IdeaRepository get _repo =>
      _repository ?? (throw StateError('Idea is still loading'));
  Future<String> createBoard({
    required String title,
    String? projectId,
    String? expectedWorkspaceKey,
  }) => _repo.createBoard(
    title: title,
    projectId: projectId,
    expectedWorkspaceKey: expectedWorkspaceKey,
  );
  Future<void> saveBoard(
    IdeaBoard board, {
    bool isNew = false,
    IdeaBoard? base,
    String? expectedWorkspaceKey,
  }) => _repo.saveBoard(
    board,
    isNew: isNew,
    base: base,
    expectedWorkspaceKey: expectedWorkspaceKey,
  );
  Future<void> updateBoard(
    IdeaBoard board, {
    IdeaBoard? base,
    String? expectedWorkspaceKey,
  }) => _repo.updateBoard(
    board,
    base: base,
    expectedWorkspaceKey: expectedWorkspaceKey,
  );
  Future<void> deleteBoard(IdeaBoard board, {String? expectedWorkspaceKey}) =>
      _repo.deleteBoard(board, expectedWorkspaceKey: expectedWorkspaceKey);
  Future<IdeaAsset> importImage(Uint8List bytes) => _repo.importImage(bytes);
  Future<Uint8List?> readAsset(IdeaAsset asset) => _repo.readAsset(asset);
  void _check(String? key) {
    if (key != null && key != _repo.storage.workspaceKey) {
      throw StateError('Idea workspace changed');
    }
  }

  Future<void> saveDraft(
    IdeaBoard board, {
    IdeaBoard? base,
    String? expectedWorkspaceKey,
  }) => _repo.saveDraft(
    board,
    base: base,
    expectedWorkspaceKey: expectedWorkspaceKey,
  );
  Future<List<IdeaBoard>> listDrafts({String? expectedWorkspaceKey}) {
    _check(expectedWorkspaceKey);
    return _repo.listDrafts();
  }

  Future<IdeaBoard?> readDraft(String id, {String? expectedWorkspaceKey}) {
    _check(expectedWorkspaceKey);
    return _repo.readDraft(id);
  }

  Future<IdeaBoard?> readDraftBase(String id, {String? expectedWorkspaceKey}) {
    _check(expectedWorkspaceKey);
    return _repo.readDraftBase(id);
  }

  Future<void> discardDraft(String id, {String? expectedWorkspaceKey}) {
    _check(expectedWorkspaceKey);
    return _repo.discardDraft(id);
  }

  Future<void> ensureAssets(IdeaBoard board, {String? expectedWorkspaceKey}) {
    _check(expectedWorkspaceKey);
    return _repo.ensureAssets(board);
  }

  Future<void> reload() => _repo.reload();
}

class IdeaSpaceEntry {
  const IdeaSpaceEntry({
    required this.board,
    required this.workspaceKey,
    required this.sourceName,
    required this.canEdit,
    this.sharedScopeId,
    this.localSpaceId,
  });
  final IdeaBoard board;
  final String workspaceKey, sourceName;
  final bool canEdit;
  final String? sharedScopeId, localSpaceId;
}

final ideaAllSpacesProvider = FutureProvider<List<IdeaSpaceEntry>>((ref) async {
  ref.watch(ideaProvider);
  final local = ref.watch(localSpacesProvider).valueOrNull;
  final state = ref.watch(collaborationProvider).valueOrNull;
  final db = await ref.watch(localDatabaseProvider.future);
  final snapshot = await IdeaStorage(db).readAll();
  final links = {
    for (final r in await db.rows(
      'SELECT idea_id,space_id FROM idea_space_links',
    ))
      r['idea_id']: r['space_id'],
  };
  final entries = <IdeaSpaceEntry>[];
  final mappedLocal = <String>{};
  if (state != null && state.session != null && state.privateSync.enabled) {
    // Maps use the existing private workspace key from personal_workspaces.
    for (final row in await db.rows(
      "SELECT m.id FROM personal_record_map m JOIN personal_workspaces w ON w.id=m.workspace WHERE m.type='idea' AND w.partition=? AND w.scope_id=?",
      [state.session!.partition, state.privateSync.scopeId],
    )) {
      mappedLocal.add(row['id'] as String);
    }
  }
  for (final b in snapshot.boards) {
    if (mappedLocal.contains(b.id)) continue;
    final spaceId = links[b.id] as String? ?? 'local';
    final space = local?.spaces.where((s) => s.id == spaceId).firstOrNull;
    if (space?.archived == true) continue;
    if (space?.binding != null &&
        space!.binding!.partition == state?.session?.partition &&
        state!.scopes.any(
          (s) => s.id == space.binding!.scopeId && !s.revoked,
        )) {
      continue;
    }
    entries.add(
      IdeaSpaceEntry(
        board: b,
        workspaceKey: spaceId,
        localSpaceId: spaceId,
        sourceName: space?.name ?? '',
        canEdit: !((local?.snapshots[spaceId]?.projects ?? []).any(
          (p) => p.id == b.projectId && p.archived,
        )),
      ),
    );
  }
  if (state != null && state.localAccessAllowed && state.session != null) {
    final repo = await ref.watch(collaborationRepositoryProvider.future);
    for (final scope in state.scopes.where((s) => !s.revoked && !s.archived)) {
      final shared = SharedIdeaStorage(
        repo,
        state.session!.partition,
        scope.id,
      );
      final s = await shared.read();
      for (final b in s.boards) {
        entries.add(
          IdeaSpaceEntry(
            board: b,
            workspaceKey: s.workspaceKey,
            sharedScopeId: scope.id,
            sourceName: scope.name,
            canEdit:
                scope.canEdit &&
                !state
                    .dataForScope(scope.id)
                    .projects
                    .any((p) => p.id == b.projectId && p.archived),
          ),
        );
      }
    }
  }
  return List.unmodifiable(entries);
});

final ideaWorkspaceAssetProvider =
    FutureProvider.family<Uint8List?, (String, IdeaAsset)>((
      ref,
      request,
    ) async {
      final state = ref.watch(collaborationProvider).valueOrNull;
      final db = await ref.watch(localDatabaseProvider.future);
      final workspace = request.$1, generation = db.personalIdentityGeneration;
      if (workspace.startsWith('shared:')) {
        final partition = state?.session?.partition;
        if (partition == null ||
            state?.localAccessAllowed != true ||
            !state!.scopes.any(
              (s) => workspace == 'shared:$partition:${s.id}' && !s.revoked,
            )) {
          throw StateError('Idea workspace access changed');
        }
      } else {
        final local = ref.watch(localSpacesProvider).valueOrNull;
        if (local == null || !local.spaces.any((s) => s.id == workspace)) {
          throw StateError('Idea workspace access changed');
        }
      }
      final rows = await db.rows(
        'SELECT bytes FROM idea_assets WHERE workspace=? AND sha256=?',
        [workspace, request.$2.sha256],
      );
      if (rows.isEmpty) return null;
      final bytes = Uint8List.fromList(rows.single['bytes'] as List<int>);
      await verifyIdeaAsset(request.$2, bytes);
      if (generation != db.personalIdentityGeneration) {
        throw StateError('Idea workspace access changed');
      }
      if (workspace.startsWith('shared:')) {
        final current = ref.read(collaborationProvider).valueOrNull;
        final partition = current?.session?.partition;
        if (partition == null ||
            current?.localAccessAllowed != true ||
            !current!.scopes.any(
              (s) => workspace == 'shared:$partition:${s.id}' && !s.revoked,
            )) {
          throw StateError('Idea workspace access changed');
        }
      }
      return bytes;
    });

final ideaDraftsProvider = FutureProvider<List<IdeaBoard>>((ref) async {
  ref.watch(ideaProvider);
  final repository = await ref.watch(ideaRepositoryProvider.future);
  return repository.listDrafts();
});
