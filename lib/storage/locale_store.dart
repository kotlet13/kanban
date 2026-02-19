import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleStore {
  const LocaleStore();

  static const String _localeKey = 'app_locale_code';

  Future<Locale?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey)?.trim();
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  Future<void> save(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    final code = locale?.languageCode.trim();
    if (code == null || code.isEmpty) {
      await prefs.remove(_localeKey);
      return;
    }
    await prefs.setString(_localeKey, code);
  }
}
