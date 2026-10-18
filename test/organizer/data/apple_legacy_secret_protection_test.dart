import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('jivie/local_vault');
  const plugin = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(plugin, null);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    test(
      '$platform uses only native migration with configured service/group',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        var nativeCalls = 0, pluginCalls = 0;
        const isolated = FlutterSecureStorage(
          mOptions: MacOsOptions(
            accountName: 'synthetic.service',
            groupId: 'synthetic.group',
          ),
          iOptions: IOSOptions(
            accountName: 'synthetic.service',
            groupId: 'synthetic.group',
          ),
        );
        messenger.setMockMethodCallHandler(plugin, (_) async {
          pluginCalls++;
          throw StateError('plugin forbidden');
        });
        messenger.setMockMethodCallHandler(native, (call) async {
          nativeCalls++;
          expect(call.method, 'protectLegacySecrets');
          expect(call.arguments, {
            'service': 'synthetic.service',
            'accessGroup': 'synthetic.group',
          });
          return true;
        });
        await protectExistingLocalVaultSecrets(storage: isolated);
        expect(nativeCalls, 1);
        expect(pluginCalls, 0);
      },
    );
  }
  test('default nil group preserves configured default service', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(native, (call) async {
      expect(call.arguments, {
        'service': 'flutter_secure_storage_service',
        'accessGroup': null,
      });
      return true;
    });
    await protectExistingLocalVaultSecrets();
  });
  for (final result in ['false', 'platform_error', 'missing_handler']) {
    test('Apple $result fails closed without plugin migration', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var pluginCalls = 0;
      messenger.setMockMethodCallHandler(plugin, (_) async {
        pluginCalls++;
        return null;
      });
      if (result != 'missing_handler') {
        messenger.setMockMethodCallHandler(native, (_) async {
          if (result == 'platform_error') {
            throw PlatformException(code: 'synthetic');
          }
          return false;
        });
      }
      await expectLater(
        protectExistingLocalVaultSecrets(),
        throwsA(
          isA<LocalVaultException>().having(
            (e) => e.code,
            'code',
            'vault_secure_storage',
          ),
        ),
      );
      expect(pluginCalls, 0);
    });
  }
  test(
    'non-Apple roundtrip retains configured Android resetOnError false',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(localVaultSecureStorage.aOptions.toMap()['resetOnError'], 'false');
      var nativeCalls = 0, writes = 0;
      final values = {'organizer_device_session_v1': 'synthetic-value'};
      messenger.setMockMethodCallHandler(native, (_) async {
        nativeCalls++;
        return true;
      });
      messenger.setMockMethodCallHandler(plugin, (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        if (call.method == 'read') return values[args['key']];
        if (call.method == 'write') {
          writes++;
          values[args['key'] as String] = args['value'] as String;
          return null;
        }
        fail('Unexpected secret operation');
      });
      await protectExistingLocalVaultSecrets();
      expect(nativeCalls, 0);
      expect(writes, 1);
      expect(values['organizer_device_session_v1'], 'synthetic-value');
    },
  );
}
