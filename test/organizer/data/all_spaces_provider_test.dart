import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/all_spaces_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

class PersonalFixture extends OrganizerController {
  PersonalFixture(this.snapshot);
  final OrganizerSnapshot snapshot;
  @override
  Future<OrganizerSnapshot> build() async => snapshot;
  void replace(AsyncValue<OrganizerSnapshot> value) => state = value;
}

class SharedFixture extends CollaborationController {
  SharedFixture(this.snapshot);
  final CollaborationState snapshot;
  @override
  Future<CollaborationState> build() async => snapshot;
  void replace(AsyncValue<CollaborationState> value) => state = value;
}

void main() {
  test('personal refresh/error drops retained prior workspace rows', () async {
    final personal = PersonalFixture(OrganizerSnapshot());
    final shared = SharedFixture(CollaborationState());
    final container = ProviderContainer(
      overrides: [
        organizerProvider.overrideWith(() => personal),
        collaborationProvider.overrideWith(() => shared),
      ],
    );
    addTearDown(container.dispose);
    await container.read(organizerProvider.future);
    await container.read(collaborationProvider.future);
    final previous = container.read(organizerProvider);
    expect(container.read(allSpacesProvider).requireValue.sources.length, 1);
    personal.replace(
      const AsyncLoading<OrganizerSnapshot>().copyWithPrevious(previous),
    );
    final loading = container.read(allSpacesProvider);
    expect(loading.isLoading, true);
    expect(loading.hasValue, false);
    personal.replace(
      AsyncError<OrganizerSnapshot>(
        StateError('reload'),
        StackTrace.current,
      ).copyWithPrevious(previous),
    );
    final failure = container.read(allSpacesProvider);
    expect(failure.hasError, true);
    expect(failure.hasValue, false);
  });

  test('collaboration refresh/error drops old account scopes', () async {
    final now = DateTime.utc(2026, 10, 9);
    final personal = PersonalFixture(OrganizerSnapshot());
    final shared = SharedFixture(
      CollaborationState(
        session: AccountSession(
          serverUrl: 'https://synthetic.invalid/',
          serverId: 'server',
          accountId: 'alice',
          userId: 1,
          username: 'alice',
          displayName: 'alice',
          deviceId: 'device',
          expiresAt: now.add(const Duration(days: 1)),
        ),
        scopes: const [
          SharedScope(
            id: 'home',
            name: 'Home',
            kind: SharedScopeKind.household,
            role: SharedRole.member,
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        organizerProvider.overrideWith(() => personal),
        collaborationProvider.overrideWith(() => shared),
      ],
    );
    addTearDown(container.dispose);
    await container.read(organizerProvider.future);
    await container.read(collaborationProvider.future);
    final previous = container.read(collaborationProvider);
    expect(container.read(allSpacesProvider).requireValue.sources.length, 2);
    shared.replace(
      const AsyncLoading<CollaborationState>().copyWithPrevious(previous),
    );
    expect(
      container.read(allSpacesProvider).requireValue.sources.single.isPersonal,
      true,
    );
    shared.replace(
      AsyncError<CollaborationState>(
        StateError('account'),
        StackTrace.current,
      ).copyWithPrevious(previous),
    );
    expect(
      container.read(allSpacesProvider).requireValue.sources.single.isPersonal,
      true,
    );
  });
}
