import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local_spaces_repository.dart';
import '../domain/local_space_models.dart';
import 'local_database_provider.dart';
import 'organizer_provider.dart';
export '../domain/local_space_models.dart';

final localSpacesRepositoryProvider = FutureProvider<LocalSpacesRepository>((
  ref,
) async {
  await ref.watch(organizerRepositoryProvider.future);
  return LocalSpacesRepository(await ref.watch(localDatabaseProvider.future));
});
final localSpacesProvider =
    AsyncNotifierProvider<LocalSpacesController, LocalSpacesState>(
      LocalSpacesController.new,
    );

class LocalSpacesController extends AsyncNotifier<LocalSpacesState> {
  LocalSpacesRepository? _repository;
  @override
  Future<LocalSpacesState> build() async {
    var active = true;
    StreamSubscription<void>? subscription;
    ref.onDispose(() {
      active = false;
      unawaited(subscription?.cancel());
    });
    final repo = await ref.watch(localSpacesRepositoryProvider.future);
    _repository = repo;
    subscription = repo.changes.listen((_) {
      unawaited(
        repo.read().then(
          (value) {
            if (active) state = AsyncData(value);
          },
          onError: (Object e, StackTrace s) {
            if (active) state = AsyncError(e, s);
          },
        ),
      );
    });
    return repo.read();
  }

  LocalSpacesRepository get _repo =>
      _repository ?? (throw StateError('Local spaces are loading'));
  Future<LocalSpace> createSpace({
    required LocalSpaceKind kind,
    required String name,
    String address = '',
  }) => _repo.createSpace(kind: kind, name: name, address: address);
  Future<void> selectSpace(String id) => _repo.selectSpace(id);
  Future<void> materializeFinanceOccurrences(
    String localSpaceId, {
    required String expectedWorkspaceKey,
    DateTime? through,
    Set<String>? ruleIds,
  }) => _repo.materializeFinanceOccurrences(
    localSpaceId,
    expectedWorkspaceKey: expectedWorkspaceKey,
    through: through,
    ruleIds: ruleIds,
  );
  Future<void> markReminderRead(
    String localSpaceId,
    String reminderId, {
    required String expectedWorkspaceKey,
  }) => _repo.markReminderRead(
    localSpaceId,
    reminderId,
    expectedWorkspaceKey: expectedWorkspaceKey,
  );
  Future<void> renameSpace(
    String id, {
    required String name,
    String address = '',
  }) => _repo.renameSpace(id, name: name, address: address);
  Future<void> assignGardenToHousehold(
    String gardenId,
    String spaceId, {
    required int expectedRevision,
  }) => _repo.assignGardenToHousehold(
    gardenId,
    spaceId,
    expectedRevision: expectedRevision,
  );
  Future<void> moveShoppingListToHousehold(
    String listId,
    String spaceId, {
    required int expectedRevision,
  }) => _repo.moveShoppingListToHousehold(
    listId,
    spaceId,
    expectedRevision: expectedRevision,
  );
}
