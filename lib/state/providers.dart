import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../ai/ai_facade.dart';
import '../ai/ai_provider.dart';
import '../ai/openai_local_ai_provider.dart';
import '../kanboard/kanboard_api.dart';
import '../models/kanboard_models.dart';
import '../storage/ai_consent_store.dart';
import '../storage/ai_chat_store.dart';
import '../storage/ai_settings_store.dart';
import '../storage/cache_store.dart';
import '../storage/credentials_store.dart';
import '../storage/locale_store.dart';
import '../storage/project_defaults_store.dart';
import '../storage/theme_mode_store.dart';

final credentialsStoreProvider = Provider<CredentialsStore>(
  (ref) => const CredentialsStore(),
);

final savedCredentialsProvider = FutureProvider<KanboardCredentials?>((ref) {
  return ref.read(credentialsStoreProvider).read();
});

final sessionCredentialsProvider = StateProvider<KanboardCredentials?>(
  (ref) => null,
);

final kanboardApiProvider = Provider<KanboardApi?>((ref) {
  final credentials = ref.watch(sessionCredentialsProvider);
  if (credentials == null) return null;
  return KanboardApi.fromCredentials(credentials);
});

final cacheStoreProvider = FutureProvider<CacheStore>((ref) async {
  return CacheStore.create();
});

final projectDefaultsStoreProvider = Provider<ProjectDefaultsStore>(
  (ref) => const ProjectDefaultsStore(),
);

final projectDefaultsProvider = FutureProvider<ProjectDefaults>((ref) async {
  return ref.read(projectDefaultsStoreProvider).read();
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final themeModeStoreProvider = Provider<ThemeModeStore>(
  (ref) => const ThemeModeStore(),
);

final localeStoreProvider = Provider<LocaleStore>((ref) => const LocaleStore());

final appLocaleProvider = StateProvider<Locale?>((ref) => null);

final aiSettingsStoreProvider = Provider<AiSettingsStore>(
  (ref) => const AiSettingsStore(),
);

final aiChatStoreProvider = Provider<AiChatStore>((ref) => const AiChatStore());

final aiConsentStoreProvider = Provider<AiConsentStore>(
  (ref) => const AiConsentStore(),
);

final aiSettingsProvider = FutureProvider<AiSettings>((ref) {
  return ref.read(aiSettingsStoreProvider).read();
});

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final aiProvider = Provider<AiProvider>((ref) {
  return OpenAiLocalProvider(
    httpClient: ref.read(httpClientProvider),
    readSettings: () => ref.read(aiSettingsStoreProvider).read(),
  );
});

final aiFacadeProvider = Provider<AiFacade>((ref) {
  return AiFacade(ref.watch(aiProvider));
});
