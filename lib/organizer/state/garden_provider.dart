import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/garden_repository.dart';
import '../data/garden_storage.dart';
import '../domain/garden_models.dart';
import 'local_database_provider.dart';

final gardenRepositoryProvider = FutureProvider<GardenRepository>((ref) async {
  final db = await ref.watch(localDatabaseProvider.future);
  final repository = GardenRepository(GardenStorage(db));
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
    Iterable<GardenArea> areas = const [],
  }) => _repo.createGarden(name: name, notes: notes, areas: areas);
  Future<void> updateGarden(Garden garden) => _repo.updateGarden(garden);
  Future<void> deleteGarden(Garden garden) => _repo.deleteGarden(garden);
  Future<void> reload() => _repo.reload();
}
