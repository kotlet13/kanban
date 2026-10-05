import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/organizer/platform/backup_ui_preferences.dart';

void main() {
  test(
    'only portable display preferences are read, never device delivery consent or secrets',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_locale_code': 'sl',
        'app_theme_mode': 'dark',
        'organizer_getting_started_seen_v1': true,
        'remote_push_opt_in': true,
        'token': 'secret',
      });
      expect(await PlatformBackupUiPreferencesStore().read(), {
        'app_locale_code': 'sl',
        'app_theme_mode': 'dark',
        'organizer_getting_started_seen_v1': true,
      });
    },
  );
  test('unknown preference prevents any partial write', () async {
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'light'});
    await expectLater(
      PlatformBackupUiPreferencesStore().restore({
        'app_theme_mode': 'dark',
        'remote_push_opt_in': true,
      }),
      throwsFormatException,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('app_theme_mode'),
      'light',
    );
  });
  test(
    'validated display choices restore without changing device push consent',
    () async {
      SharedPreferences.setMockInitialValues({
        'remote_push_opt_in': false,
        'app_locale_code': 'sl',
      });
      await PlatformBackupUiPreferencesStore().restore({
        'app_locale_code': null,
        'app_theme_mode': 'dark',
        'organizer_getting_started_seen_v1': true,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_locale_code'), null);
      expect(prefs.getString('app_theme_mode'), 'dark');
      expect(prefs.getBool('remote_push_opt_in'), false);
    },
  );
}
