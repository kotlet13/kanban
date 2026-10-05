import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/platform/remote_push/firebase_mobile_config.dart';

Map<String, String> values() => {
  'FIREBASE_PROJECT_ID': 'fixture-project',
  'FIREBASE_SENDER_ID': '123456789',
  'FIREBASE_ANDROID_API_KEY': 'AIza${List.filled(35, 'A').join()}',
  'FIREBASE_ANDROID_APP_ID': '1:123456789:android:abcdef1234567890',
  'FIREBASE_ANDROID_PACKAGE': 'com.takndev.kanbanconnect',
};
void main() {
  test('no mobile config and unsupported platforms remain optional', () {
    expect(FirebaseMobileConfig.fromDefines('android', values: {}), isNull);
    expect(FirebaseMobileConfig.fromDefines('ios', values: values()), isNull);
    expect(FirebaseMobileConfig.fromDefines('web', values: values()), isNull);
  });
  test('valid identifiers are explicit options; no SDK initialization', () {
    final result = FirebaseMobileConfig.fromDefines(
      'android',
      values: values(),
    )!;
    expect(result.options.projectId, 'fixture-project');
    expect(result.options.messagingSenderId, '123456789');
  });
  test(
    'partial values, mismatched sender/platform and invalid project rejected',
    () {
      for (final data in [
        {...values(), 'FIREBASE_ANDROID_API_KEY': ''},
        {...values(), 'FIREBASE_PROJECT_ID': 'invalid-'},
        {
          ...values(),
          'FIREBASE_ANDROID_APP_ID': '1:999999:android:abcdef1234567890',
        },
        {
          ...values(),
          'FIREBASE_ANDROID_APP_ID': '1:123456789:ios:abcdef1234567890',
        },
        {...values(), 'FIREBASE_ANDROID_PACKAGE': 'unresolved\$(ID)'},
      ]) {
        expect(
          () => FirebaseMobileConfig.fromDefines('android', values: data),
          throwsFormatException,
        );
      }
    },
  );
}
