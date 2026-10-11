import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/locale_store.dart';
import '../../storage/theme_mode_store.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final themeModeStoreProvider = Provider<ThemeModeStore>(
  (ref) => const ThemeModeStore(),
);
final localeStoreProvider = Provider<LocaleStore>((ref) => const LocaleStore());
final appLocaleProvider = StateProvider<Locale?>((ref) => null);
