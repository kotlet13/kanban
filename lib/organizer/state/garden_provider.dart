import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/garden_repository.dart';
import '../data/garden_storage.dart';
import '../domain/garden_models.dart';
import 'local_database_provider.dart';
import 'collaboration_provider.dart';
import '../data/collaboration_repository.dart' show SharedGardenStorage;

final gardenRepositoryProvider = FutureProvider<GardenRepository>((ref) async {
  final db = await ref.watch(localDatabaseProvider.future);
  final selected = ref.watch(
    collaborationProvider.select(
      (state) => (
        state.valueOrNull?.session?.partition,
        state.valueOrNull?.selectedSpaceId,
      ),
    ),
  );
  final shared = await ref.watch(collaborationRepositoryProvider.future);
  final scope = shared.state.scopes
      .where((s) => s.id == selected.$2 && s.kind == SharedScopeKind.household)
      .firstOrNull;
  final storage = scope == null || selected.$1 == null
      ? GardenStorage(db)
      : SharedGardenStorage(shared, selected.$1!, scope.id);
  final repository = GardenRepository(storage);
  ref.onDispose(() => unawaited(repository.close()));
  await repository.initialize();
  return repository;
});
final gardenProvider = AsyncNotifierProvider<GardenController, GardenSnapshot>(
  GardenController.new,
);

class GardenController extends AsyncNotifier<GardenSnapshot> {
  GardenRepository? _repository;
  @override
  Future<GardenSnapshot> build() async {
    var active = true;
    StreamSubscription<GardenSnapshot>? subscription;
    ref.onDispose(() {
      active = false;
      unawaited(subscription?.cancel());
    });
    final repository = await ref.watch(gardenRepositoryProvider.future);
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

  GardenRepository get _repo =>
      _repository ?? (throw StateError('Garden is still loading'));
  Future<String> createGarden({
    required String name,
    String notes = '',
    String? expectedWorkspaceKey,
    Iterable<GardenArea> areas = const [],
    Iterable<GardenSeason> seasons = const [],
  }) => _repo.createGarden(
    name: name,
    notes: notes,
    expectedWorkspaceKey: expectedWorkspaceKey,
    areas: areas,
    seasons: seasons,
  );
  Future<void> updateGarden(Garden garden, {String? expectedWorkspaceKey}) =>
      _repo.updateGarden(garden, expectedWorkspaceKey: expectedWorkspaceKey);
  Future<void> deleteGarden(Garden garden, {String? expectedWorkspaceKey}) =>
      _repo.deleteGarden(garden, expectedWorkspaceKey: expectedWorkspaceKey);
  Future<void> saveSeason(Garden garden, GardenSeason season) =>
      _repo.saveSeason(garden, season);
  Future<void> deleteSeason(Garden garden, int year) =>
      _repo.deleteSeason(garden, year);
  Future<void> savePlanting(Garden garden, int year, GardenPlanting planting) =>
      _repo.savePlanting(garden, year, planting);
  Future<void> deletePlanting(Garden garden, int year, String plantingId) =>
      _repo.deletePlanting(garden, year, plantingId);
  Future<void> reload() => _repo.reload();
}
