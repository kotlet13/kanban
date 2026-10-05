import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_store.dart';

class AiSettings {
  const AiSettings({
    this.enabled = false,
    this.model = 'gpt-4.1-mini',
    this.apiKey,
    this.responseMode = 'instant',
    this.thinkingEffort = 'medium',
  });

  final bool enabled;
  final String model;
  final String? apiKey;
  final String responseMode;
  final String thinkingEffort;

  bool get hasApiKey => apiKey != null && apiKey!.trim().isNotEmpty;
  bool get isThinkingMode => responseMode == 'thinking';
  String get normalizedThinkingEffort {
    switch (thinkingEffort) {
      case 'low':
      case 'medium':
      case 'high':
        return thinkingEffort;
      default:
        return 'medium';
    }
  }

  AiSettings copyWith({
    bool? enabled,
    String? model,
    String? apiKey,
    String? responseMode,
    String? thinkingEffort,
  }) {
    return AiSettings(
      enabled: enabled ?? this.enabled,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      responseMode: responseMode ?? this.responseMode,
      thinkingEffort: thinkingEffort ?? this.thinkingEffort,
    );
  }
}

class AiSettingsStore {
  const AiSettingsStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _enabledKey = 'ai_enabled';
  static const String _modelKey = 'ai_model';
  static const String _apiKeyKey = 'ai_api_key';
  static const String _responseModeKey = 'ai_response_mode';
  static const String _thinkingEffortKey = 'ai_thinking_effort';

  Future<AiSettings> read() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    final model = (prefs.getString(_modelKey) ?? 'gpt-4.1-mini').trim();
    final responseMode = (prefs.getString(_responseModeKey) ?? 'instant')
        .trim();
    final thinkingEffort = (prefs.getString(_thinkingEffortKey) ?? 'medium')
        .trim();
    String? apiKey;
    try {
      apiKey = await _storage.read(key: _apiKeyKey);
      final legacyKey = prefs.getString(_apiKeyKey);
      if (apiKey == null && legacyKey != null) {
        await _storage.write(key: _apiKeyKey, value: legacyKey);
        if (await _storage.read(key: _apiKeyKey) != legacyKey) {
          throw const CredentialsStorageException();
        }
        apiKey = legacyKey;
      }
      if (legacyKey != null && !await prefs.remove(_apiKeyKey)) {
        throw const CredentialsStorageException();
      }
    } catch (_) {
      throw const CredentialsStorageException();
    }
    return AiSettings(
      enabled: enabled,
      model: model,
      apiKey: apiKey,
      responseMode: responseMode == 'thinking' ? 'thinking' : 'instant',
      thinkingEffort: switch (thinkingEffort) {
        'low' => 'low',
        'high' => 'high',
        _ => 'medium',
      },
    );
  }

  Future<void> save(AiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedKey = settings.apiKey?.trim();
    // Commit the secret first; failures preserve existing settings and legacy key.
    try {
      if (normalizedKey == null || normalizedKey.isEmpty) {
        await _storage.delete(key: _apiKeyKey);
      } else {
        await _storage.write(key: _apiKeyKey, value: normalizedKey);
        if (await _storage.read(key: _apiKeyKey) != normalizedKey) {
          throw const CredentialsStorageException();
        }
      }
      if (!await prefs.remove(_apiKeyKey)) {
        throw const CredentialsStorageException();
      }
    } catch (_) {
      throw const CredentialsStorageException();
    }
    await prefs.setBool(_enabledKey, settings.enabled);
    await prefs.setString(_modelKey, settings.model.trim());
    await prefs.setString(
      _responseModeKey,
      settings.isThinkingMode ? 'thinking' : 'instant',
    );
    await prefs.setString(
      _thinkingEffortKey,
      settings.normalizedThinkingEffort,
    );
  }
}
