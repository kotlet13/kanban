import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kanban/models/kanboard_models.dart';
import 'package:kanban/storage/account_scope.dart';
import 'package:kanban/storage/cache_store.dart';

void main() {
  const alice = KanboardCredentials(
    serverUrl: 'https://example.test/kanboard',
    username: 'alice',
    token: 'secret',
  );
  const bob = KanboardCredentials(
    serverUrl: 'https://example.test/kanboard',
    username: 'bob',
    token: 'secret',
  );
  late Directory directory;
  late CacheStore storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kanban-cache-test-');
    storage = await CacheStore.create(directory: directory.path);
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('scope normalizes server URL without including credentials', () {
    const equivalent = KanboardCredentials(
      serverUrl: 'HTTPS://EXAMPLE.TEST:443/kanboard/jsonrpc.php',
      username: ' alice ',
      token: 'another-secret',
    );
    expect(accountScopeKey(alice), accountScopeKey(equivalent));
    expect(accountScopeKey(alice), isNot(accountScopeKey(bob)));
    expect(
      accountScopeKey(alice),
      isNot(
        accountScopeKey(
          const KanboardCredentials(
            serverUrl: 'https://other.test/kanboard',
            username: 'alice',
            token: 'secret',
          ),
        ),
      ),
    );
  });

  test('same project ID does not mix accounts or servers', () async {
    final first = storage.forAccount(alice);
    final second = storage.forAccount(bob);
    final otherServer = storage.forAccount(
      const KanboardCredentials(
        serverUrl: 'https://other.test',
        username: 'alice',
        token: 'secret',
      ),
    );
    await first.saveProjects([
      const KanboardProject(id: 1, name: 'Alice private'),
    ]);
    expect(second.readProjects(), isEmpty);
    expect(otherServer.readProjects(), isEmpty);
    await second.saveProjects([
      const KanboardProject(id: 1, name: 'Bob private'),
    ]);
    expect(first.readProjects().single.name, 'Alice private');
    expect(second.readProjects().single.name, 'Bob private');
  });

  test('captured scope cannot write to switched account', () async {
    final captured = storage.forAccount(alice);
    final active = storage.forAccount(bob);
    await captured.saveProjects([
      const KanboardProject(id: 2, name: 'Delayed Alice response'),
    ]);
    expect(active.readProjects(), isEmpty);
    expect(captured.readProjects().single.name, 'Delayed Alice response');
  });

  test(
    'logout clears only its scope and rejects late replies from old handles',
    () async {
      final first = storage.forAccount(alice);
      final second = storage.forAccount(bob);
      await first.saveProjects([const KanboardProject(id: 1, name: 'Alice')]);
      await second.saveProjects([const KanboardProject(id: 1, name: 'Bob')]);
      await first.clearScope();
      await first.saveProjects([
        const KanboardProject(id: 2, name: 'Late private response'),
      ]);
      expect(storage.forAccount(alice).readProjects(), isEmpty);
      expect(second.readProjects().single.name, 'Bob');
    },
  );

  test(
    'scoped cache survives restart and ignores unowned legacy cache',
    () async {
      await Hive.box<String>(
        'kanboard_cache_box',
      ).put('projects', '[{"id":9,"name":"Unowned legacy"}]');
      expect(storage.forAccount(alice).readProjects(), isEmpty);
      await storage.forAccount(alice).saveProjects([
        const KanboardProject(id: 1, name: 'Persisted Alice'),
      ]);
      await Hive.close();
      storage = await CacheStore.create(directory: directory.path);
      expect(
        storage.forAccount(alice).readProjects().single.name,
        'Persisted Alice',
      );
      expect(storage.forAccount(bob).readProjects(), isEmpty);
    },
  );
}
