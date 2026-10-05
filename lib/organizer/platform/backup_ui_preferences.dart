import 'package:shared_preferences/shared_preferences.dart';
import '../data/portable_backup_repository.dart';

/// Portable UI choices only. Device delivery permissions, push consent, session
/// secrets and OS notification identifiers intentionally never enter this map.
class PlatformBackupUiPreferencesStore implements BackupUiPreferencesStore {
  static const _locale = 'app_locale_code',
      _theme = 'app_theme_mode',
      _intro = 'organizer_getting_started_seen_v1';
  @override
  Future<Map<String, Object?>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString(_locale), theme = prefs.getString(_theme);
    return {
      _locale: {'sl', 'en'}.contains(locale) ? locale : null,
      _theme: {'system', 'light', 'dark'}.contains(theme) ? theme : 'system',
      _intro: prefs.getBool(_intro) ?? false,
    };
  }

  @override
  Future<void> restore(Map<String, Object?> values) async {
    for (final entry in values.entries) {
      final valid = switch (entry.key) {
        _locale => {null, 'sl', 'en'}.contains(entry.value),
        _theme => {'system', 'light', 'dark'}.contains(entry.value),
        _intro => entry.value is bool,
        _ => false,
      };
      if (!valid) {
        throw const FormatException('Unsupported portable UI preference');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      final key = entry.key, value = entry.value;
      bool saved;
      if (key == _locale && {null, 'sl', 'en'}.contains(value)) {
        saved = value == null
            ? await prefs.remove(key)
            : await prefs.setString(key, value as String);
      } else if (key == _theme && {'system', 'light', 'dark'}.contains(value)) {
        saved = await prefs.setString(key, value as String);
      } else if (key == _intro && value is bool) {
        saved = await prefs.setBool(key, value);
      } else {
        throw const FormatException('Unsupported portable UI preference');
      }
      if (!saved) throw StateError('UI preference save failed');
    }
  }
}
