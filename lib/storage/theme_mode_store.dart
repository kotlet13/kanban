import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeStore {
  const ThemeModeStore();

  static const String _themeModeKey = 'app_theme_mode';

  Future<ThemeMode> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeModeKey)?.trim().toLowerCase();
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_themeModeKey, value);
  }
}
