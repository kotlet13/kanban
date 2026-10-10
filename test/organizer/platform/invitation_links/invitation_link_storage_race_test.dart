import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_coordinator.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../../data/collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore;
import '../../data/email_invitation_repository_test.dart' show EmailServer;

class ControlledInvitationStore extends MemoryPendingInvitationStore {
  bool Function(PendingInvitation?)? blockNext;
  Completer<void> started = Completer<void>(), release = Completer<void>();
  final writes = <String?>[];
  void gate(bool Function(PendingInvitation?) predicate) {
    blockNext = predicate;
    started = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<void> write(PendingInvitation? invitation) async {
    if (blockNext?.call(invitation) == true) {
      blockNext = null;
      started.complete();
      await release.future;
    }
    writes.add(invitation?.token);
    await super.write(invitation);
  }
}

class RaceLinks implements InvitationLinkSource {
  final stream = StreamController<Uri>.broadcast();
  @override
  Future<Uri?> initialLink() async => null;
  @override
  Stream<Uri> get links => stream.stream;
}

void main() {
  const serverUrl = 'https://synthetic.invalid/kanboard/';
  final newer = InvitationLink(serverUrl: serverUrl, token: 'fhi2_${'b' * 64}');
  Future<ProviderContainer> coordinator(
    WidgetTester tester,
    ControlledInvitationStore store,
    RaceLinks source,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pendingInvitationStoreProvider.overrideWithValue(store),
        invitationLinkSourceProvider.overrideWithValue(source),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(source.stream.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: InvitationLinkCoordinator(child: SizedBox()),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  Future<CollaborationRepository> repository(
    ControlledInvitationStore store,
    EmailServer server,
  ) async {
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      FakeTransport(server),
      MemorySessionStore(),
      invitationStore: store,
    );
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: serverUrl,
      username: 'alice',
      password: 'synthetic-password',
    );
    server.scopeId = await repo.createScope('Synthetic race household');
    server.recipient = 'bob';
    await repo.login(
      serverUrl: serverUrl,
      username: 'bob',
      password: 'synthetic-password',
    );
    return repo;
  }

  test('new native link survives an in-flight acceptance clear', () async {
    final store = ControlledInvitationStore(), server = EmailServer();
    final repo = await repository(store, server);
    await repo.previewInvitation(serverUrl: serverUrl, token: server.token);
    store.gate((invitation) => invitation == null);
    final acceptance = repo.acceptInvitation(server.token);
    await store.started.future;
    final delivery = store.receiveLink(
      serverUrl: newer.serverUrl,
      token: newer.token,
      isCurrent: () => true,
    );
    expect(store.value!.token, server.token);
    store.release.complete();
    await acceptance;
    await delivery;
    expect(store.value!.token, newer.token);
    expect(store.writes.take(store.writes.length - 1).last, isNull);
    expect(store.writes.last, newer.token);
  });
  testWidgets('new native link survives an in-flight preview identity pin', (
    tester,
  ) async {
    final store = ControlledInvitationStore(),
        source = RaceLinks(),
        server = EmailServer();
    final repo = (await tester.runAsync(() => repository(store, server)))!;
    await repo.rememberInvitation(serverUrl: serverUrl, token: server.token);
    final container = await coordinator(tester, store, source);
    store.gate((invitation) => invitation?.serverId != null);
    final preview = repo.previewInvitation(
      serverUrl: serverUrl,
      token: server.token,
    );
    final failedPreview = expectLater(
      preview,
      throwsA(
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'session_changed',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.started.isCompleted, true);
    source.stream.add(newer.toUri());
    await tester.pump();
    store.release.complete();
    await failedPreview;
    await tester.pumpAndSettle();
    expect(store.value!.token, newer.token);
    expect(store.value!.serverId, isNull);
    expect(container.read(pendingInvitationLinkProvider)?.token, newer.token);
    expect(store.writes.last, newer.token);
  });
  testWidgets(
    'two rapid links serialize storage and retain only the newest UI delivery',
    (tester) async {
      final store = ControlledInvitationStore(), source = RaceLinks();
      final container = await coordinator(tester, store, source);
      final older = InvitationLink(
        serverUrl: serverUrl,
        token: 'fhi2_${'a' * 64}',
      );
      store.gate((invitation) => invitation?.token == older.token);
      source.stream.add(older.toUri());
      await tester.pump();
      expect(store.started.isCompleted, true);
      source.stream.add(newer.toUri());
      await tester.pump();
      expect(store.value, isNull);
      expect(store.writes, isEmpty);
      store.release.complete();
      await tester.pumpAndSettle();
      expect(store.writes, [older.token, newer.token]);
      expect(store.value!.token, newer.token);
      expect(container.read(pendingInvitationLinkProvider)?.token, newer.token);
      expect(container.read(invitationLinkErrorProvider), false);
    },
  );
}
