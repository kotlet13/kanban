import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const store = SecurePendingInvitationStore();
  const pendingKey = 'jivie_pending_invitation_v1';
  const retiredKey = 'jivie_retired_invitation_links_v1';
  final values = <String, String>{};
  var dropRetirement = false, dropDelete = false;
  setUp(() {
    values.clear();
    dropRetirement = false;
    dropDelete = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return values[key];
            case 'write':
              if (!(dropRetirement && key == retiredKey)) {
                values[key] = args['value'] as String;
              }
              return null;
            case 'delete':
              if (!dropDelete) values.remove(key);
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
  final invitation = PendingInvitation(
    serverUrl: 'https://synthetic.invalid/',
    token: 'fhi4_${'a' * 64}',
    serverId: 'synthetic-server',
    accountPartition: 'synthetic-account',
    invitationId: 'synthetic-accepted-pending',
    expiresAt: DateTime.utc(2020),
  ); // Expiry does not invalidate accepted continuation.
  final failure = throwsA(
    isA<CollaborationException>().having(
      (e) => e.code,
      'code',
      'secure_storage',
    ),
  );
  test(
    'legacy payload and deferred accepted continuation retain every binding through metadata rewrites',
    () async {
      values[pendingKey] = jsonEncode(invitation.toJson());
      expect((await store.read())!.autoOpen, true);
      await store.deferLink(
        serverUrl: invitation.serverUrl,
        token: invitation.token,
      );
      final expected = {...invitation.toJson(), 'autoOpen': false};
      expect((await store.read())!.toJson(), expected);
      await store.write(invitation); // Stale preview HTTP snapshot.
      expect(
        (await const SecurePendingInvitationStore().read())!.toJson(),
        expected,
      );
      expect(await store.mayAutoOpen((await store.read())!), false);
      expect(
        await store.receiveLink(
          serverUrl: invitation.serverUrl,
          token: invitation.token,
          isCurrent: () => true,
        ),
        true,
      ); // explicit reopen
      expect((await store.read())!.toJson(), expected);
      await store.deferLink(
        serverUrl: 'https://other.invalid/',
        token: invitation.token,
      );
      expect((await store.read())!.toJson(), expected);
    },
  );
  test(
    'completion survives store recreation and automatic initial replay; new invitation still opens',
    () async {
      await store.write(invitation);
      await store.serialized(() => store.write(null));
      expect(values[pendingKey], isNull);
      expect(values[retiredKey], isNot(contains(invitation.token)));
      const restarted = SecurePendingInvitationStore();
      expect(
        await restarted.receiveLink(
          serverUrl: invitation.serverUrl,
          token: invitation.token,
          automatic: true,
          isCurrent: () => true,
        ),
        false,
      );
      expect(await restarted.read(), isNull);
      expect(
        await restarted.receiveLink(
          serverUrl: invitation.serverUrl,
          token: 'fhi4_${'b' * 64}',
          automatic: true,
          isCurrent: () => true,
        ),
        true,
      );
      expect((await restarted.read())!.autoOpen, true);
    },
  );
  test(
    'failed retirement keeps recovery capability and reports storage failure',
    () async {
      await store.write(invitation);
      dropRetirement = true;
      await expectLater(store.serialized(() => store.write(null)), failure);
      expect((await store.read())!.toJson(), invitation.toJson());
    },
  );
  test(
    'failed deletion keeps capability but cannot resurrect automatic route',
    () async {
      await store.write(invitation);
      dropDelete = true;
      await expectLater(store.serialized(() => store.write(null)), failure);
      expect((await store.read())!.toJson(), invitation.toJson());
      expect(await store.mayAutoOpen((await store.read())!), false);
      expect(
        await store.receiveLink(
          serverUrl: invitation.serverUrl,
          token: invitation.token,
          automatic: true,
          isCurrent: () => true,
        ),
        false,
      );
    },
  );
  test(
    'history is bounded, rejects raw secrets, and binds normalized origin',
    () async {
      for (var i = 0; i < 34; i++) {
        await store.retireLink(i.toRadixString(16).padLeft(64, '0'));
      }
      expect((await store.retiredLinks()).length, 32);
      await expectLater(store.retireLink(invitation.token), failure);
      await store.write(invitation);
      await store.serialized(() => store.write(null));
      expect(
        await store.receiveLink(
          serverUrl: 'https://other.invalid/',
          token: invitation.token,
          automatic: true,
          isCurrent: () => true,
        ),
        true,
      );
    },
  );
}
