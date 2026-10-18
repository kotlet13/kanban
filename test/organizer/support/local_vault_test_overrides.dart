import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/data/local_vault_preferences.dart';
import 'package:kanban/organizer/state/local_vault_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synthetic preference fixtures explicitly opt out of the native key store.
/// Production defaults remain strict; real encrypted storage has its own tests.
Override localVaultTestPreferencesOverride() =>
    localVaultPreferencesProvider.overrideWith(
      (ref) async =>
          LegacyLocalVaultPreferences(await SharedPreferences.getInstance()),
    );
