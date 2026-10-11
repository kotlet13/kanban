import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const store = SecureDeviceSessionStore();
  final values = <String, String>{};
  var loseWrites = false, loseDeletes = false, failReads = false;
  final accessedKeys = <String>[];
  setUp(() {
    values.clear();
    accessedKeys.clear();
    loseWrites = false;
    loseDeletes = false;
    failReads = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          accessedKeys.add(key);
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
  DeviceSession session() => DeviceSession(
    AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: newSharedId(),
      accountId: newSharedId(),
      userId: 1,
      username: 'synthetic',
      displayName: 'Synthetic',
      deviceId: newSharedId(),
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
    ),
    'synthetic-token',
  );
  final failure = throwsA(
    isA<CollaborationException>().having(
      (e) => e.code,
      'code',
      'secure_storage',
    ),
  );
  test('complete session is one verified secure record', () async {
    final original = session();
    await store.write(original);
    expect(values.length, 1);
    expect((await store.read())!.profile.partition, original.profile.partition);
    await store.clear();
    expect(await store.read(), isNull);
  });
  test(
    'new session lifecycle never loads or clears retired credentials or AI data',
    () async {
      const retired = <String, String>{
        'kanboard_credentials_v2': 'unparsed old secure connection',
        'kanboard_server_url': 'https://retired.invalid',
        'kanboard_username': 'old-user',
        'kanboard_token': 'old-token',
        'ai_api_key': 'old-secure-key',
      };
      values.addAll(retired);
      SharedPreferences.setMockInitialValues({
        ...retired,
        'ai_chat_threads_v1': 'old history',
        'ai_enabled': true,
      });
      expect(await store.read(), isNull);
      final first = session();
      await store.write(first);
      expect((await store.read())!.profile.partition, first.profile.partition);
      final second = session();
      await store.write(second);
      expect((await store.read())!.profile.partition, second.profile.partition);
      expect(second.profile.partition, isNot(first.profile.partition));
      await store.clear();
      expect(await store.read(), isNull);
      expect(values, retired);
      expect(accessedKeys.toSet(), {'organizer_device_session_v1'});
      final preferences = await SharedPreferences.getInstance();
      for (final item in retired.entries) {
        expect(preferences.getString(item.key), item.value);
      }
      expect(preferences.getString('ai_chat_threads_v1'), 'old history');
      expect(preferences.getBool('ai_enabled'), true);
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
      await expectLater(store.clear(), failure);
      expect(values.length, 1);
    },
  );
  test('secure read unavailable never falls back to plaintext', () async {
    failReads = true;
    await expectLater(store.read(), failure);
  });
}
