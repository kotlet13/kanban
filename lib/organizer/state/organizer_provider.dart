import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/organizer_repository.dart';
import '../data/organizer_storage.dart';
import '../data/sqlite_organizer_storage.dart';
import 'local_database_provider.dart';
import '../domain/organizer_models.dart';

typedef OrganizerStorageFactory = Future<OrganizerStorage> Function();
typedef OrganizerReminderScheduler = void Function() Function(void Function());

final organizerClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Injectable timer scheduling makes deadline refresh deterministic in tests.
final organizerReminderSchedulerProvider = Provider<OrganizerReminderScheduler>(
  (ref) => (callback) {
    final timer = Timer.periodic(const Duration(minutes: 1), (_) => callback());
    return timer.cancel;
  },
);

/// A background refresh failure preserves the last committed data. Consumers
/// may display this error; explicit refresh and CRUD still throw to their caller.
final organizerReminderRefreshErrorProvider = StateProvider<Object?>(
  (ref) => null,
);

/// Each repository owns a newly opened storage handle. A factory (rather than
/// a cached Future of an open box) allows failed opens and closed boxes to retry.
final organizerStorageProvider = Provider<OrganizerStorageFactory>(
  (ref) => () async {
    final db = await ref.read(localDatabaseProvider.future);
    final storage = SqliteOrganizerStorage(
      db,
      legacyFactory: HiveOrganizerStorage.open,
    );
    await storage.initialize();
    return storage;
  },
);

class _RepositoryLifecycle {
  Future<void> closing = Future.value();
}

final _repositoryLifecycleProvider = Provider((ref) => _RepositoryLifecycle());

final organizerRepositoryProvider = FutureProvider<OrganizerRepository>((
  ref,
) async {
  final factory = ref.watch(organizerStorageProvider);
  final clock = ref.watch(organizerClockProvider);
  final lifecycle = ref.watch(_repositoryLifecycleProvider);
  final opening = () async {
    // Hive returns the existing box while it is open. Wait for the previous
    // owner's queued mutations and close before opening a replacement handle.
    await lifecycle.closing;
    final storage = await factory();
    final repository = OrganizerRepository(storage, clock: clock);
    try {
      await repository.initialize();
      return repository;
    } catch (_) {
      await repository.close();
      rethrow;
    }
  }();
  ref.onDispose(() {
    lifecycle.closing = opening.then<void>(
      (repository) => repository.close(),
      onError: (Object error, StackTrace stack) {},
    );
  });
  return opening;
});

final organizerProvider =
    AsyncNotifierProvider<OrganizerController, OrganizerSnapshot>(
      OrganizerController.new,
    );

class OrganizerController extends AsyncNotifier<OrganizerSnapshot> {
  OrganizerRepository? _repository;

  @override
  Future<OrganizerSnapshot> build() async {
    var active = true;
    StreamSubscription<OrganizerSnapshot>? subscription;
    void Function()? cancelTimer;
    void Function()? cancelLifecycle;
    ref.onDispose(() {
      active = false;
      unawaited(subscription?.cancel());
      cancelTimer?.call();
      cancelLifecycle?.call();
    });
    final repository = await ref.watch(organizerRepositoryProvider.future);
    if (!active) return repository.snapshot;
    _repository = repository;
    subscription = repository.changes.listen(
      (snapshot) {
        if (active) state = AsyncData(snapshot);
      },
      onError: (Object error, StackTrace stack) {
        if (active) state = AsyncError(error, stack);
      },
    );
    await repository.refreshReminders();
    if (!active) return repository.snapshot;
    var refreshing = false;
    void refreshInBackground() {
      if (!active || refreshing) return;
      refreshing = true;
      unawaited(() async {
        try {
          await repository.refreshReminders();
          if (active) {
            ref.read(organizerReminderRefreshErrorProvider.notifier).state =
                null;
          }
        } catch (error) {
          if (active) {
            ref.read(organizerReminderRefreshErrorProvider.notifier).state =
                error;
          }
        } finally {
          refreshing = false;
        }
      }());
    }

    cancelTimer = ref.read(organizerReminderSchedulerProvider)(
      refreshInBackground,
    );
    final binding = WidgetsBinding.instance;
    final observer = _ReminderLifecycleObserver(refreshInBackground);
    binding.addObserver(observer);
    cancelLifecycle = () => binding.removeObserver(observer);
    return repository.snapshot;
  }

  OrganizerRepository get _repo =>
      _repository ?? (throw StateError('Organizer is still loading'));

  Future<void> createProject({
    required String title,
    String description = '',
    DateTime? startAt,
    DateTime? endAt,
    ProjectArea area = ProjectArea.personal,
  }) => _repo.createProject(
    title: title,
    description: description,
    startAt: startAt,
    endAt: endAt,
    area: area,
  );
  Future<void> updateProject(LocalProject record) =>
      _repo.updateProject(record);
  Future<void> deleteProject(String id) => _repo.deleteProject(id);

  Future<void> createTask({
    required String title,
    String notes = '',
    String? projectId,
    DateTime? dueAt,
    DateTime? startAt,
    DateTime? endAt,
  }) => _repo.createTask(
    title: title,
    notes: notes,
    projectId: projectId,
    dueAt: dueAt,
    startAt: startAt,
    endAt: endAt,
  );
  Future<void> updateTask(LocalTask record) => _repo.updateTask(record);
  Future<void> deleteTask(String id) => _repo.deleteTask(id);

  Future<void> createShoppingList({required String title}) =>
      _repo.createShoppingList(title: title);
  Future<void> updateShoppingList(LocalShoppingList record) =>
      _repo.updateShoppingList(record);
  Future<void> deleteShoppingList(String id) => _repo.deleteShoppingList(id);

  Future<void> createShoppingItem({
    required String listId,
    required String title,
    String quantity = '1',
  }) => _repo.createShoppingItem(
    listId: listId,
    title: title,
    quantity: quantity,
  );
  Future<void> updateShoppingItem(LocalShoppingItem record) =>
      _repo.updateShoppingItem(record);
  Future<void> deleteShoppingItem(String id) => _repo.deleteShoppingItem(id);

  Future<void> createEvent({
    required String title,
    required DateTime startsAt,
    DateTime? endsAt,
    String notes = '',
    String? projectId,
  }) => _repo.createEvent(
    title: title,
    startsAt: startsAt,
    endsAt: endsAt,
    notes: notes,
    projectId: projectId,
  );
  Future<void> updateEvent(LocalEvent record) => _repo.updateEvent(record);
  Future<void> deleteEvent(String id) => _repo.deleteEvent(id);

  Future<void> createFinanceEntry({
    required String title,
    required int amountMinor,
    required FinanceEntryKind kind,
    required DateTime occurredAt,
    String currency = 'EUR',
    String notes = '',
    String? projectId,
  }) => _repo.createFinanceEntry(
    title: title,
    amountMinor: amountMinor,
    kind: kind,
    occurredAt: occurredAt,
    currency: currency,
    notes: notes,
    projectId: projectId,
  );
  Future<void> updateFinanceEntry(FinanceEntry record) =>
      _repo.updateFinanceEntry(record);
  Future<void> deleteFinanceEntry(String id) => _repo.deleteFinanceEntry(id);

  Future<void> setTaskCompleted(String id, bool completed) =>
      _repo.setTaskCompleted(id, completed);
  Future<void> setShoppingItemChecked(String id, bool checked) =>
      _repo.setShoppingItemChecked(id, checked);
  Future<void> markReminderRead(String id) => _repo.markReminderRead(id);
  Future<void> refreshReminders() => _repo.refreshReminders();
  Future<String> exportBackup() => _repo.exportBackup();
  Future<void> importBackup(String json) => _repo.importBackup(json);
}

class _ReminderLifecycleObserver extends WidgetsBindingObserver {
  _ReminderLifecycleObserver(this.refresh);
  final void Function() refresh;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
}
