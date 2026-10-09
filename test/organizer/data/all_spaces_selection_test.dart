import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late FakeTransport transport;
  late MemorySessionStore store;
  final repositories = <CollaborationRepository>[];
  Future<CollaborationRepository> open() async {
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase(File('${dir.path}/all.sqlite'))),
      transport,
      store,
      clock: () => DateTime.utc(2026, 10, 9),
    );
    repositories.add(repo);
    await repo.initialize();
    return repo;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('all-spaces-selection-');
    transport = FakeTransport(FakeServer());
    store = MemorySessionStore();
  });
  tearDown(() async {
    for (final repo in repositories) {
      await repo.close();
    }
    repositories.clear();
    await dir.delete(recursive: true);
  });

  test(
    'All and personal persist without login and never create a scope',
    () async {
      final repo = await open();
      expect(repo.state.spaceSelection.kind, SpaceSelectionKind.personal);
      await repo.selectAllSpaces();
      expect(repo.state.allSpacesSelected, true);
      expect(repo.state.selectedSpaceId, isNull);
      expect(await repo.database.rows('SELECT * FROM scopes'), isEmpty);
      await repo.close();
      final restarted = await open();
      expect(restarted.state.spaceSelection.kind, SpaceSelectionKind.all);
      await restarted.selectSpace(null);
      await restarted.close();
      expect(
        (await open()).state.spaceSelection.kind,
        SpaceSelectionKind.personal,
      );
    },
  );

  test(
    'All persists per identity; concrete selection leaves aggregate and signout removes rows',
    () async {
      final repo = await open();
      await repo.login(
        serverUrl: 'https://synthetic.invalid/',
        username: 'alice',
        password: 'synthetic',
      );
      final home = await repo.createScope('Home');
      await repo.selectSpace(home);
      await repo.selectAllSpaces();
      expect(repo.state.spaceSelection.kind, SpaceSelectionKind.all);
      expect(
        repo.state.selectedSpaceId,
        home,
      ); // Last concrete scope remains a real identifier.
      await repo.close();
      final restarted = await open();
      expect(restarted.state.allSpacesSelected, true);
      await restarted.selectSpace(home);
      expect(restarted.state.allSpacesSelected, false);
      await restarted.selectAllSpaces();
      await restarted.signOut();
      expect(restarted.state.spaceSelection.kind, SpaceSelectionKind.personal);
      expect(restarted.state.data, isEmpty);
      await restarted.login(
        serverUrl: 'https://synthetic.invalid/',
        username: 'bob',
        password: 'synthetic',
      );
      expect(restarted.state.allSpacesSelected, false);
      expect(restarted.state.scopes, isEmpty);
      await restarted.signOut();
      await restarted.login(
        serverUrl: 'https://synthetic.invalid/',
        username: 'alice',
        password: 'synthetic',
      );
      expect(restarted.state.allSpacesSelected, true);
      expect(restarted.state.selectedSpaceId, home);
    },
  );
}
