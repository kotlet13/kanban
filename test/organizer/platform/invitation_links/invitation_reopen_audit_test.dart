// Startup routing only: no server, membership changes or real credentials.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_coordinator.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

class _Links implements InvitationLinkSource {
  final initial = Completer<Uri?>();
  final stream = StreamController<Uri>.broadcast();
  @override
  Future<Uri?> initialLink() => initial.future;
  @override
  Stream<Uri> get links => stream.stream;
}

class _Sessions implements DeviceSessionStore {
  final result = Completer<DeviceSession?>();
  bool readStarted = false;
  @override
  Future<DeviceSession?> read() {
    readStarted = true;
    return result.future;
  }

  @override
  Future<void> write(DeviceSession session) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  final old = InvitationLink(
    serverUrl: 'https://synthetic.invalid/',
    token: 'fhi2_${'a' * 64}',
  );
  final newer = InvitationLink(
    serverUrl: old.serverUrl,
    token: 'fhi2_${'b' * 64}',
  );
  Future<void> mount(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: InvitationLinkCoordinator(child: SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scenario in ['dismissed', 'cleared_initial', 'late_old_initial']) {
    testWidgets('startup regression: $scenario preserves navigation intent', (
      tester,
    ) async {
      final store = MemoryPendingInvitationStore();
      final source = _Links();
      final container = ProviderContainer(
        overrides: [
          pendingInvitationStoreProvider.overrideWithValue(store),
          invitationLinkSourceProvider.overrideWithValue(source),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(source.stream.close);
      if (scenario == 'dismissed') {
        await store.write(
          PendingInvitation(serverUrl: old.serverUrl, token: old.token),
        );
        source.initial.complete(null);
        await mount(tester, container);
        expect(container.read(pendingInvitationLinkProvider)?.token, old.token);
        // Back persists deferral while retaining the original capability.
        await store.deferLink(serverUrl: old.serverUrl, token: old.token);
        container.read(pendingInvitationLinkProvider.notifier).state = null;
        await tester.pumpWidget(const SizedBox());
        await mount(tester, container);
        expect(container.read(pendingInvitationLinkProvider), isNull);
        expect(store.value?.token, old.token);
        expect(store.value?.autoOpen, false);
      } else if (scenario == 'cleared_initial') {
        source.initial.complete(old.toUri());
        await mount(tester, container);
        expect(store.value?.token, old.token);
        // Model an already completed flow's successful matching-token cleanup.
        await store.write(null);
        container.read(pendingInvitationLinkProvider.notifier).state = null;
        await tester.pumpWidget(const SizedBox());
        await mount(tester, container);
        expect(store.value, isNull);
        expect(container.read(pendingInvitationLinkProvider), isNull);
      } else {
        await mount(tester, container);
        source.stream.add(newer.toUri());
        await tester.pumpAndSettle();
        expect(
          store.value,
          isNull,
        ); // Bootstrap is bounded and coalesces the initial echo.
        source.stream.add(old.toUri().replace(scheme: 'vsakdan'));
        await tester.pump();
        source.initial.complete(old.toUri());
        await tester.pumpAndSettle();
        expect(store.value?.token, newer.token);
        expect(
          container.read(pendingInvitationLinkProvider)?.token,
          newer.token,
        );
      }
      expect(container.read(invitationLinkErrorProvider), false);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'initial stream replay is suppressed; later explicit click still opens',
    (tester) async {
      final store = MemoryPendingInvitationStore();
      await store.write(
        PendingInvitation(serverUrl: old.serverUrl, token: old.token),
      );
      await store.write(null);
      final source = _Links();
      final container = ProviderContainer(
        overrides: [
          pendingInvitationStoreProvider.overrideWithValue(store),
          invitationLinkSourceProvider.overrideWithValue(source),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(source.stream.close);
      await mount(tester, container);
      source.stream.add(old.toUri());
      await tester.pump();
      source.initial.complete(old.toUri());
      await tester.pumpAndSettle();
      expect(store.value, isNull);
      expect(container.read(pendingInvitationLinkProvider), isNull);
      source.stream.add(old.toUri());
      await tester.pumpAndSettle();
      expect(store.value?.token, old.token);
      expect(container.read(pendingInvitationLinkProvider)?.token, old.token);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'initial timeout does not block pending restore or override later live link',
    (tester) async {
      final store = MemoryPendingInvitationStore();
      await store.write(
        PendingInvitation(serverUrl: old.serverUrl, token: old.token),
      );
      final source = _Links();
      final container = ProviderContainer(
        overrides: [
          pendingInvitationStoreProvider.overrideWithValue(store),
          invitationLinkSourceProvider.overrideWithValue(source),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(source.stream.close);
      await mount(tester, container);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(container.read(pendingInvitationLinkProvider)?.token, old.token);
      source.stream.add(newer.toUri());
      await tester.pumpAndSettle();
      source.initial.complete(old.toUri());
      await tester.pumpAndSettle();
      expect(store.value?.token, newer.token);
      expect(container.read(pendingInvitationLinkProvider)?.token, newer.token);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'absent bootstrap echo does not consume the first later explicit click',
    (tester) async {
      final store = MemoryPendingInvitationStore();
      await store.write(
        PendingInvitation(serverUrl: old.serverUrl, token: old.token),
      );
      await store.write(null);
      final source = _Links()..initial.complete(old.toUri());
      final container = ProviderContainer(
        overrides: [
          pendingInvitationStoreProvider.overrideWithValue(store),
          invitationLinkSourceProvider.overrideWithValue(source),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(source.stream.close);
      await mount(tester, container);
      expect(store.value, isNull);
      await tester.pump(const Duration(seconds: 2));
      source.stream.add(old.toUri());
      await tester.pumpAndSettle();
      expect(store.value?.token, old.token);
      expect(container.read(pendingInvitationLinkProvider)?.token, old.token);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final mode in ['bound_initial', 'clear_during_restore']) {
    testWidgets('automatic account and storage revalidation: $mode', (
      tester,
    ) async {
      final session = DeviceSession(
        AccountSession(
          serverUrl: old.serverUrl,
          serverId: 'synthetic-server',
          accountId: 'synthetic-account',
          deviceId: 'synthetic-device',
          userId: 1,
          username: 'synthetic',
          displayName: 'Synthetic',
          expiresAt: DateTime.utc(2099),
        ),
        'synthetic-session',
      );
      final store = MemoryPendingInvitationStore();
      await store.write(
        PendingInvitation(
          serverUrl: old.serverUrl,
          token: old.token,
          accountPartition: mode == 'bound_initial'
              ? 'other-account'
              : session.profile.partition,
        ),
      );
      final sessions = _Sessions();
      final source = _Links()..initial.complete(old.toUri());
      final container = ProviderContainer(
        overrides: [
          pendingInvitationStoreProvider.overrideWithValue(store),
          deviceSessionStoreProvider.overrideWithValue(sessions),
          invitationLinkSourceProvider.overrideWithValue(
            mode == 'bound_initial' ? source : null,
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(source.stream.close);
      await mount(tester, container);
      expect(sessions.readStarted, true);
      if (mode == 'clear_during_restore') {
        await store.serialized(() => store.write(null));
      }
      sessions.result.complete(session);
      await tester.pumpAndSettle();
      expect(container.read(pendingInvitationLinkProvider), isNull);
      expect(container.read(invitationLinkErrorProvider), false);
      if (mode == 'clear_during_restore') expect(store.value, isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
