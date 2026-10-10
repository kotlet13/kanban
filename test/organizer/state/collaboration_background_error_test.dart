import 'dart:async';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../data/collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class BackgroundRefreshRepository extends CollaborationRepository {
  BackgroundRefreshRepository(
    super.database,
    super.transport,
    super.sessionStore,
  );
  Future<void> Function()? nextRefresh;
  @override
  Future<void> refreshLocal() async {
    final hook = nextRefresh;
    nextRefresh = null;
    await hook?.call();
    await super.refreshLocal();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const serverUrl = 'https://synthetic.invalid/';
  late BackgroundRefreshRepository repository;
  late ProviderContainer container;
  late CollaborationController controller;
  Future<void> open({Future<void> Function()? initialRefresh}) async {
    repository = BackgroundRefreshRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      FakeTransport(FakeServer()),
      MemorySessionStore(),
    );
    await repository.initialize();
    await repository.login(
      serverUrl: serverUrl,
      username: 'alice',
      password: 'synthetic-password',
    );
    repository.nextRefresh = initialRefresh;
    container = ProviderContainer(
      overrides: [
        collaborationRepositoryProvider.overrideWith((ref) async => repository),
      ],
    );
    container.listen(collaborationProvider, (_, __) {}, fireImmediately: true);
    await container.read(collaborationProvider.future);
    controller = container.read(collaborationProvider.notifier);
  }

  tearDown(() async {
    container.dispose();
    await repository.close();
  });
  Future<void> settle() async {
    for (var n = 0; n < 5; n++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> login(String username) => controller.login(
    serverUrl: serverUrl,
    username: username,
    password: 'synthetic-password',
  );

  test(
    'a real background error is reset on account switch and signout without waiting for the timer',
    () async {
      await open(
        initialRefresh: () async {
          throw const CollaborationException('network');
        },
      );
      await settle();
      expect(
        container.read(collaborationBackgroundErrorProvider),
        isA<CollaborationException>(),
      );
      await login('bob');
      await settle();
      expect(repository.state.session?.username, 'bob');
      expect(container.read(collaborationBackgroundErrorProvider), isNull);
      container.read(collaborationBackgroundErrorProvider.notifier).state =
          const CollaborationException('invalid_response');
      await controller.signOut();
      await settle();
      expect(container.read(collaborationBackgroundErrorProvider), isNull);
    },
  );
  test(
    'a delayed error from the prior identity cannot color the next account',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      await open(
        initialRefresh: () async {
          started.complete();
          await release.future;
          throw const CollaborationException('network');
        },
      );
      await started.future;
      await login('bob');
      await settle();
      expect(repository.state.session?.username, 'bob');
      release.complete();
      await settle();
      expect(container.read(collaborationBackgroundErrorProvider), isNull);
    },
  );
  test(
    'a delayed successful refresh from the prior identity cannot clear the new error',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      await open(
        initialRefresh: () async {
          started.complete();
          await release.future;
        },
      );
      await started.future;
      await login('bob');
      await settle();
      final currentError = const CollaborationException('invalid_response');
      container.read(collaborationBackgroundErrorProvider.notifier).state =
          currentError;
      release.complete();
      await settle();
      expect(
        container.read(collaborationBackgroundErrorProvider),
        same(currentError),
      );
    },
  );
  test(
    'manual sync clears background error of its own identity and retains repository errors separately',
    () async {
      await open(
        initialRefresh: () async {
          throw const CollaborationException('invalid_response');
        },
      );
      await settle();
      expect(container.read(collaborationBackgroundErrorProvider), isNotNull);
      await controller.syncNow();
      expect(container.read(collaborationBackgroundErrorProvider), isNull);
      (repository.transport as FakeTransport).offline = true;
      await controller.syncNow();
      expect(repository.state.lastError?.code, 'network');
      expect(container.read(collaborationBackgroundErrorProvider), isNull);
    },
  );
}
