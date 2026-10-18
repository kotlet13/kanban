import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_vault_open.dart';
import '../data/local_vault_preferences.dart';

/// Production never falls back to plaintext if the vault is unavailable. Tests
/// injecting platform preferences explicitly override this provider.
final localVaultPreferencesProvider = FutureProvider<LocalVaultPreferences>(
  (ref) => openLocalVaultPreferences(),
);
