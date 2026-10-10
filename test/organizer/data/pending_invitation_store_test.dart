import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

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
      expect(values.length, 1);
    },
  );
  test('secure read unavailable never falls back to plaintext', () async {
    failReads = true;
    await expectLater(store.read(), failure);
  });
}
