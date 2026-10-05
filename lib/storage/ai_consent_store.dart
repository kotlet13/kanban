import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Consent is specific to a server, user, and project. Old unscoped consent
/// keys remain unread; consent cannot be inferred for a different identity.
class AiConsentStore {
  AiConsentStore({this.scope}) : _generation = _generations[scope] ?? 0;
  final String? scope;
  final int _generation;
  static final Map<String?, int> _generations = {};
  static final Map<String, Future<void>> _pending = {};
  String get _prefix => 'ai_cost_consent_v2_${scope}_';
  bool get _active =>
      scope != null && _generation == (_generations[scope] ?? 0);

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final key = scope ?? '';
    final result = Completer<T>();
    _pending[key] = (_pending[key] ?? Future<void>.value()).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  // username remains in this API for existing task-assistant callers. The
  // immutable scope supplied by the session provider is the identity authority.
  Future<bool> hasAcceptedProjectCostWarning({
    required int projectId,
    required String username,
  }) => _enqueue(() async {
    if (!_active) return false;
    final prefs = await SharedPreferences.getInstance();
    return _active && (prefs.getBool('$_prefix$projectId') ?? false);
  });

  Future<void> setAcceptedProjectCostWarning({
    required int projectId,
    required String username,
    required bool accepted,
  }) => _enqueue(() async {
    if (!_active) {
      throw StateError('AI consent requires an active account scope');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!_active) throw StateError('AI consent account scope expired');
    final saved = accepted
        ? await prefs.setBool('$_prefix$projectId', true)
        : await prefs.remove('$_prefix$projectId');
    if (!saved) throw StateError('AI consent could not be saved');
  });

  Future<void> clearScope() {
    if (scope == null) return Future.value();
    _generations[scope] = (_generations[scope] ?? 0) + 1;
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
        if (!await prefs.remove(key)) {
          throw StateError('AI consent could not be cleared');
        }
      }
    });
  }
}
