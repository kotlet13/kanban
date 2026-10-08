import 'dart:async';
import '../domain/garden_models.dart';
import 'garden_storage.dart';
import 'organizer_repository.dart' show newLocalId, OrganizerConflictException;

class GardenRepository {
  GardenRepository(
    this.storage, {
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? newLocalId {
    _subscription = storage.changes.listen((_) {
      if (!_closed) {
        unawaited(reload().catchError((Object _) {}));
      }
    });
  }
  final GardenStorage storage;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  final _changes = StreamController<GardenSnapshot>.broadcast();
  late final StreamSubscription<void> _subscription;
  Future<void> _tail = Future.value();
  bool _closed = false;
  GardenSnapshot? _snapshot;
  Stream<GardenSnapshot> get changes => _changes.stream;
  GardenSnapshot get snapshot =>
      _snapshot ?? (throw StateError('Garden is still loading'));
  Future<T> _queue<T>(Future<T> Function() action) {
    if (_closed) {
      return Future.error(StateError('Garden repository closed'));
    }
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    return result.future;
  }

  Future<GardenSnapshot> initialize() =>
      _queue(() async => _snapshot = await storage.read());
  Future<void> reload() => _queue(() async {
    try {
      _snapshot = await storage.read();
      _changes.add(snapshot);
    } catch (e, s) {
      _snapshot = null;
      _changes.addError(e, s);
      rethrow;
    }
  });
  Future<T> _change<T>((GardenSnapshot, T) Function(GardenSnapshot) change) =>
      _queue(() async {
        final previous = await storage.read();
        final (candidate, result) = change(previous);
        await storage.write(candidate, expectedRevision: previous.revision);
        _snapshot = await storage.read();
        _changes.add(snapshot);
        storage.database.personalChanged();
        return result;
      });
  Future<String> createGarden({
    required String name,
    String notes = '',
    Iterable<GardenArea> areas = const [],
    Iterable<GardenSeason> seasons = const [],
  }) => _change((s) {
    final now = _clock().toUtc(), id = _idGenerator();
    final garden = Garden(
      id: id,
      name: name.trim(),
      notes: notes,
      areas: areas,
      seasons: seasons,
      createdAt: now,
      updatedAt: now,
    );
    return (
      GardenSnapshot(revision: s.revision, gardens: [...s.gardens, garden]),
      id,
    );
  });
  Garden _current(GardenSnapshot s, Garden record) {
    final current = s.gardens.where((g) => g.id == record.id).firstOrNull;
    if (current == null ||
        current.revision != record.revision ||
        current.createdAt != record.createdAt) {
      throw const OrganizerConflictException(
        'Garden changed; reload before editing',
      );
    }
    return current;
  }

  Future<void> updateGarden(Garden garden) => _change<void>((s) {
    final current = _current(s, garden), now = _clock().toUtc();
    final updated = garden.copyWith(
      name: garden.name.trim(),
      revision: current.revision + 1,
      updatedAt: now.isBefore(current.updatedAt) ? current.updatedAt : now,
    );
    return (
      GardenSnapshot(
        revision: s.revision,
        gardens: s.gardens.map((g) => g.id == garden.id ? updated : g),
      ),
      null,
    );
  });
  Future<void> deleteGarden(Garden garden) => _change<void>((s) {
    _current(s, garden);
    return (
      GardenSnapshot(
        revision: s.revision,
        gardens: s.gardens.where((g) => g.id != garden.id),
      ),
      null,
    );
  });
  Future<void> saveSeason(Garden garden, GardenSeason season) => updateGarden(
    garden.copyWith(
      seasons: [...garden.seasons.where((s) => s.year != season.year), season],
    ),
  );
  Future<void> deleteSeason(Garden garden, int year) => updateGarden(
    garden.copyWith(seasons: garden.seasons.where((s) => s.year != year)),
  );
  Future<void> savePlanting(Garden garden, int year, GardenPlanting planting) {
    final season = garden.seasonForYear(year) ?? GardenSeason(year: year);
    return saveSeason(
      garden,
      season.copyWith(
        plantings: [
          ...season.plantings.where((p) => p.id != planting.id),
          planting,
        ],
      ),
    );
  }

  Future<void> deletePlanting(Garden garden, int year, String plantingId) {
    final season = garden.seasonForYear(year);
    if (season == null || !season.plantings.any((p) => p.id == plantingId)) {
      throw const OrganizerConflictException('Planting no longer exists');
    }
    return saveSeason(
      garden,
      season.copyWith(
        plantings: season.plantings.where((p) => p.id != plantingId),
      ),
    );
  }

  Future<void> close() async {
    _closed = true;
    await _subscription.cancel();
    await _tail;
    await _changes.close();
  }
}
