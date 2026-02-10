import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../kanboard/kanboard_api.dart';
import '../models/kanboard_models.dart';
import '../storage/cache_store.dart';
import '../storage/credentials_store.dart';

final credentialsStoreProvider = Provider<CredentialsStore>(
  (ref) => const CredentialsStore(),
);

final savedCredentialsProvider = FutureProvider<KanboardCredentials?>((ref) {
  return ref.read(credentialsStoreProvider).read();
});

final sessionCredentialsProvider =
    StateProvider<KanboardCredentials?>((ref) => null);

final kanboardApiProvider = Provider<KanboardApi?>((ref) {
  final credentials = ref.watch(sessionCredentialsProvider);
  if (credentials == null) return null;
  return KanboardApi.fromCredentials(credentials);
});

final cacheStoreProvider = FutureProvider<CacheStore>((ref) async {
  return CacheStore.create();
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
