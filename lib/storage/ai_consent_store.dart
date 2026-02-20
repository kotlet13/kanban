import 'package:shared_preferences/shared_preferences.dart';

class AiConsentStore {
  const AiConsentStore();

  String _keyFor(int projectId, String username) =>
      'ai_cost_consent_${projectId}_${username.toLowerCase()}';

  Future<bool> hasAcceptedProjectCostWarning({
    required int projectId,
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFor(projectId, username)) ?? false;
  }

  Future<void> setAcceptedProjectCostWarning({
    required int projectId,
    required String username,
    required bool accepted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(projectId, username);
    if (accepted) {
      await prefs.setBool(key, true);
    } else {
      await prefs.remove(key);
    }
  }
}
