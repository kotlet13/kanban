import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_coordinator.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const store = SecurePendingInvitationStore();
  final values = <String, String>{};
  var loseWrites = false, loseDeletes = false, failReads = false;
  setUp(() {
    values.clear();
    loseWrites = false;
    loseDeletes = false;
    failReads = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              if (failReads) throw PlatformException(code: 'unavailable');
              return values[key];
            case 'write':
              if (!loseWrites) values[key] = args['value'] as String;
              return null;
            case 'delete':
              if (!loseDeletes) values.remove(key);
              return null;
            default:
              throw StateError('Unexpected secure storage operation');
          }
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  PendingInvitation session() => PendingInvitation(
    serverUrl: 'https://synthetic.invalid/',
    serverId: newSharedId(),
    token: 'fhi2_${'a' * 64}',
    accountPartition: 'synthetic-partition',
    expiresAt: DateTime.utc(2030),
  );
  final failure = throwsA(
    isA<CollaborationException>().having(
      (e) => e.code,
      'code',
      'secure_storage',
    ),
  );
  testWidgets(
    'v4 native link survives secure persistence and startup restore',
    (tester) async {
      const server = 'https://synthetic.invalid/kanboard/';
      final token = 'fhi4_${'a' * 64}';
      await store.receiveLink(
        serverUrl: server,
        token: token,
        isCurrent: () => true,
      );
      expect(values.length, 1);
      final persisted = values.values.single;
      const restartedStore = SecurePendingInvitationStore();
      final restored = await restartedStore.read();
      expect(restored!.token, token);
      expect(restored.serverUrl, server);
      final container = ProviderContainer(
        overrides: [
          pendingInvitationStoreProvider.overrideWithValue(restartedStore),
          invitationLinkSourceProvider.overrideWithValue(null),
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
      await tester.pumpAndSettle();
      final incoming = container.read(pendingInvitationLinkProvider);
      expect(incoming!.token, token);
      expect(incoming.serverUrl, server);
      expect(container.read(invitationLinkErrorProvider), isFalse);
      expect(values.values.single, persisted);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'previous token versions retain their exact persisted bindings',
    () async {
      for (final version in [1, 2, 3]) {
        final original = session().toJson()
          ..['token'] = 'fhi${version}_${'a' * 64}';
        values['jivie_pending_invitation_v1'] = jsonEncode(original);
        expect((await store.read())!.toJson(), original);
      }
    },
  );
  test(
    'malformed persisted tokens fail closed without deleting evidence',
    () async {
      for (final token in [
        'fhi0_${'a' * 64}',
        'fhi5_${'a' * 64}',
        'fhi4_${'a' * 63}',
        'fhi4_${'a' * 65}',
        'fhi4_${'A' * 64}',
        'fhi4_${'g' * 64}',
      ]) {
        final raw = jsonEncode(session().toJson()..['token'] = token);
        values['jivie_pending_invitation_v1'] = raw;
        await expectLater(store.read(), failure);
        expect(values['jivie_pending_invitation_v1'], raw);
      }
    },
  );
  test(
    'pending invitation survives a separate secure store instance',
    () async {
      final original = session();
      await store.write(original);
      expect(values.length, 1);
      expect(
        (await const SecurePendingInvitationStore().read())!.accountPartition,
        original.accountPartition,
      );
      expect((await store.read())!.serverId, original.serverId);
      expect((await store.read())!.token, original.token);
      await store.write(null);
      expect(await store.read(), isNull);
    },
  );
  test('silently lost secure write never claims success', () async {
    loseWrites = true;
    await expectLater(store.write(session()), failure);
    expect(values, isEmpty);
  });
  test(
    'silently failed delete reports failure instead of durable logout',
    () async {
      await store.write(session());
      loseDeletes = true;
      await expectLater(store.write(null), failure);
      expect(values.containsKey('jivie_pending_invitation_v1'), isTrue);
      // Retirement is durable before deletion, so failed deletion must retain
      // both the recoverable capability and its automatic-replay suppression.
      expect(values.containsKey('jivie_retired_invitation_links_v1'), isTrue);
    },
  );
  test('secure read unavailable never falls back to plaintext', () async {
    failReads = true;
    await expectLater(store.read(), failure);
  });
}
