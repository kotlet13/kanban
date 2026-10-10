import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_coordinator.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';

class FakeLinks implements InvitationLinkSource {
  final stream = StreamController<Uri>.broadcast();
  final initial = Completer<Uri?>();
  @override
  Stream<Uri> get links => stream.stream;
  @override
  Future<Uri?> initialLink() => initial.future;
}

void main() {
  final valid = Uri(
    scheme: 'vsakdan',
    host: 'invite',
    queryParameters: {
      'server': 'https://example.test',
      'token': 'fhi1_${'a' * 64}',
    },
  );
  testWidgets(
    'duplicates stay pending once; consuming permits same link retry',
    (tester) async {
      final source = FakeLinks(),
          container = ProviderContainer(
            overrides: [
              invitationLinkSourceProvider.overrideWithValue(source),
              pendingInvitationStoreProvider.overrideWithValue(
                MemoryPendingInvitationStore(),
              ),
            ],
          );
      addTearDown(container.dispose);
      addTearDown(source.stream.close);
      var deliveries = 0;
      container.listen(pendingInvitationLinkProvider, (before, after) {
        if (after != null) deliveries++;
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: InvitationLinkCoordinator(child: SizedBox()),
          ),
        ),
      );
      await tester.pump();
      source.stream.add(valid);
      await tester.pump();
      source.initial.complete(valid);
      await tester.pump();
      expect(deliveries, 1);
      container.read(pendingInvitationLinkProvider.notifier).state = null;
      source.stream.add(valid);
      await tester.pump();
      expect(deliveries, 2);
      expect(container.read(invitationLinkErrorProvider), false);
    },
  );
  testWidgets(
    'secure pending invitation restores after restart without a link source',
    (tester) async {
      final store = MemoryPendingInvitationStore();
      await store.write(
        PendingInvitation(
          serverUrl: 'https://example.test/',
          token: 'fhi2_${'b' * 64}',
          serverId: 'synthetic-server',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          invitationLinkSourceProvider.overrideWithValue(null),
          pendingInvitationStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: InvitationLinkCoordinator(child: SizedBox()),
          ),
        ),
      );
      await tester.pump();
      expect(
        container.read(pendingInvitationLinkProvider)?.token,
        store.value!.token,
      );
      expect(container.read(invitationLinkErrorProvider), false);
    },
  );
  testWidgets('late initial link after dispose cannot publish a secret', (
    tester,
  ) async {
    final source = FakeLinks(),
        container = ProviderContainer(
          overrides: [
            invitationLinkSourceProvider.overrideWithValue(source),
            pendingInvitationStoreProvider.overrideWithValue(
              MemoryPendingInvitationStore(),
            ),
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
    await tester.pumpWidget(const SizedBox());
    source.initial.complete(valid);
    await tester.pump();
    expect(container.read(pendingInvitationLinkProvider), null);
  });
}
