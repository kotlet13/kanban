import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../data/collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore;
import '../data/email_invitation_repository_test.dart' show EmailServer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const serverUrl = 'https://synthetic.invalid/kanboard/';
  late EmailServer server;
  late MemoryPendingInvitationStore store;
  late CollaborationRepository repository;
  late ProviderContainer container;
  late CollaborationController controller;
  setUp(() async {
    server = EmailServer();
    store = MemoryPendingInvitationStore();
    repository = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      FakeTransport(server),
      MemorySessionStore(),
      invitationStore: store,
    );
    await repository.initialize();
    await repository.login(
      serverUrl: serverUrl,
      username: 'alice',
      password: 'synthetic-password',
    );
    server.scopeId = await repository.createScope(
      'Synthetic provider household',
    );
    await repository.signOut();
    container = ProviderContainer(
      overrides: [
        collaborationRepositoryProvider.overrideWith((ref) async => repository),
        pendingInvitationStoreProvider.overrideWithValue(store),
      ],
    );
    // Keep the real dependent projection alive. A fake controller or an overridden
    // pending provider would hide the CircularDependencyError observed on macOS.
    container.listen(collaborationProvider, (_, __) {}, fireImmediately: true);
    container.listen(
      securePendingInvitationProvider,
      (_, __) {},
      fireImmediately: true,
    );
    await container.read(collaborationProvider.future);
    await container.read(securePendingInvitationProvider.future);
    controller = container.read(collaborationProvider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await repository.close();
  });
  Future<void> rememberAndPreview() async {
    await controller.rememberInvitation(
      serverUrl: serverUrl,
      token: server.token,
    );
    await controller.previewInvitation(
      serverUrl: serverUrl,
      token: server.token,
    );
  }

  Future<PendingInvitation?> pending() =>
      container.read(securePendingInvitationProvider.future);
  Future<void> login(String username) => controller.login(
    serverUrl: serverUrl,
    username: username,
    password: 'synthetic-password',
  );
  Matcher failure(String code) => throwsA(
    isA<CollaborationException>().having((e) => e.code, 'code', code),
  );

  test(
    'real controller remember and preview refresh the live pending projection without a dependency cycle',
    () async {
      expect(await pending(), isNull);
      await controller.rememberInvitation(
        serverUrl: serverUrl,
        token: server.token,
      );
      expect((await pending())?.token, server.token);
      final preview = await controller.previewInvitation(
        serverUrl: serverUrl,
        token: server.token,
      );
      expect(preview.invitationId, server.invitationId);
      expect((await pending())?.serverId, server.serverId);
      expect((await pending())?.invitationId, server.invitationId);
      final newer = 'fhi2_${'b' * 64}';
      await controller.rememberInvitation(serverUrl: serverUrl, token: newer);
      await controller.clearPendingInvitation(expectedToken: server.token);
      expect((await pending())?.token, newer);
      await controller.clearPendingInvitation(expectedToken: newer);
      expect(await pending(), isNull);
    },
  );
  test(
    'real registration leaves membership pending and token acceptance refreshes its removal',
    () async {
      await rememberAndPreview();
      await controller.registerWithInvitation(
        serverUrl: serverUrl,
        invitationToken: server.token,
        username: 'charlie',
        name: 'Synthetic recipient',
        password: 'synthetic-password',
      );
      expect(repository.state.scopes, isEmpty);
      expect((await pending())?.token, server.token);
      await controller.acceptInvitation(server.token);
      expect(repository.state.scopes.single.id, server.scopeId);
      expect(await pending(), isNull);
    },
  );
  test(
    'ID acceptance also reactively removes the matching saved link',
    () async {
      server.recipient = 'bob';
      await rememberAndPreview();
      await login('bob');
      expect((await pending())?.invitationId, server.invitationId);
      await controller.acceptPendingInvitation(server.invitationId);
      expect(repository.state.scopes.single.id, server.scopeId);
      expect(await pending(), isNull);
    },
  );
  test(
    'lost acceptance refreshes its durable binding and account switching filters it',
    () async {
      server.recipient = 'bob';
      await rememberAndPreview();
      await login('bob');
      server.loseAccept = true;
      await expectLater(
        controller.acceptInvitation(server.token),
        failure('network'),
      );
      expect(
        (await pending())?.accountPartition,
        repository.state.session!.partition,
      );
      await login('alice');
      expect(await pending(), isNull);
      await login('bob');
      expect((await pending())?.token, server.token);
      await controller.previewInvitation(
        serverUrl: serverUrl,
        token: server.token,
      );
      expect(server.tokens[server.lastPreviewBearer], 'bob');
      await controller.acceptInvitation(server.token);
      expect(await pending(), isNull);
    },
  );
}
