import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/models/kanboard_models.dart';
import 'package:kanban/storage/ai_settings_store.dart';
import 'package:kanban/storage/credentials_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const credentials = KanboardCredentials(
    serverUrl: 'https://example.test',
    username: 'alice',
    token: 'private-secret',
  );
  const store = CredentialsStore();
  late Map<String, String> secure;
  var failWrites = false;
  var failReads = false;
  var silentlyLoseWrites = false;

  setUp(() {
    secure = {};
    failWrites = false;
    failReads = false;
    silentlyLoseWrites = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              if (failReads) throw PlatformException(code: '-34018');
              return secure[key];
            case 'write':
              if (failWrites) throw PlatformException(code: '-34018');
              if (!silentlyLoseWrites) secure[key] = args['value'] as String;
              return null;
            case 'delete':
              secure.remove(key);
              return null;
            default:
              throw StateError('Unexpected secure storage operation');
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void legacyPrefs() => SharedPreferences.setMockInitialValues({
    'kanboard_server_url': credentials.serverUrl,
    'kanboard_username': credentials.username,
    'kanboard_token': credentials.token,
    'kanboard_auth_mode': 'apiToken',
  });

  test(
    'new credentials are one verified secure record and never preferences',
    () async {
      await store.save(credentials);
      expect(secure.keys, ['kanboard_credentials_v2']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('kanboard_token'), isNull);
      expect((await store.read())!.token, credentials.token);
    },
  );

  test('legacy preferences migrate only after verified secure write', () async {
    legacyPrefs();
    expect((await store.read())!.username, 'alice');
    expect(
      jsonDecode(secure['kanboard_credentials_v2']!)['token'],
      'private-secret',
    );
    expect(
      (await SharedPreferences.getInstance()).getString('kanboard_token'),
      isNull,
    );
  });

  test(
    'failed migration preserves legacy credentials and reports secure error',
    () async {
      legacyPrefs();
      failWrites = true;
      await expectLater(
        store.read(),
        throwsA(isA<CredentialsStorageException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString('kanboard_token'),
        credentials.token,
      );
      expect(secure, isEmpty);
    },
  );

  test('unconfirmed write never deletes original legacy credentials', () async {
    legacyPrefs();
    silentlyLoseWrites = true;
    await expectLater(
      store.read(),
      throwsA(isA<CredentialsStorageException>()),
    );
    expect(
      (await SharedPreferences.getInstance()).getString('kanboard_token'),
      credentials.token,
    );
  });

  test('failed save preserves existing secure credential record', () async {
    await store.save(credentials);
    final original = secure['kanboard_credentials_v2'];
    failWrites = true;
    await expectLater(
      store.save(
        const KanboardCredentials(
          serverUrl: 'https://other.test',
          username: 'bob',
          token: 'new-secret',
        ),
      ),
      throwsA(isA<CredentialsStorageException>()),
    );
    expect(secure['kanboard_credentials_v2'], original);
    expect(
      (await SharedPreferences.getInstance()).getString('kanboard_token'),
      isNull,
    );
  });

  test('secure read failure does not fall back to plaintext', () async {
    legacyPrefs();
    failReads = true;
    await expectLater(
      store.read(),
      throwsA(isA<CredentialsStorageException>()),
    );
    expect(
      (await SharedPreferences.getInstance()).getString('kanboard_token'),
      credentials.token,
    );
  });

  test(
    'legacy split secure items migrate to a complete single record',
    () async {
      secure.addAll({
        'kanboard_server_url': credentials.serverUrl,
        'kanboard_username': credentials.username,
        'kanboard_token': credentials.token,
      });
      expect((await store.read())!.token, credentials.token);
      expect(secure.keys, ['kanboard_credentials_v2']);
    },
  );

  test('AI key migration writes only secure storage', () async {
    SharedPreferences.setMockInitialValues({'ai_api_key': 'private-ai-key'});
    expect((await const AiSettingsStore().read()).apiKey, 'private-ai-key');
    expect(secure['ai_api_key'], 'private-ai-key');
    expect(
      (await SharedPreferences.getInstance()).getString('ai_api_key'),
      isNull,
    );
  });

  test('AI key write failure preserves legacy key and old settings', () async {
    SharedPreferences.setMockInitialValues({
      'ai_api_key': 'old-ai-key',
      'ai_enabled': false,
    });
    failWrites = true;
    await expectLater(
      const AiSettingsStore().save(
        const AiSettings(apiKey: 'new-ai-key', enabled: true),
      ),
      throwsA(isA<CredentialsStorageException>()),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_api_key'), 'old-ai-key');
    expect(prefs.getBool('ai_enabled'), isFalse);
  });

  test('local development opt-in survives secure storage', () async {
    await store.save(
      const KanboardCredentials(
        serverUrl: 'http://127.0.0.1:18380',
        username: 'alice',
        token: 'local',
        allowLocalHttp: true,
      ),
    );
    expect((await store.read())!.allowLocalHttp, isTrue);
  });
}
