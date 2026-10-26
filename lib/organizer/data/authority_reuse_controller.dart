/// In-memory invalidation only. Change hints can retire verified evidence;
/// they never create proof or grant access themselves.
class AuthorityReuseController {
  int _generation = 0;
  bool _enabled = false;
  Object _globalToken = Object();
  final _scopeTokens = <String, Object>{};

  int get generation => _generation;
  bool get enabled => _enabled;

  /// A late probe cannot undo a mutation, denial or identity transition.
  bool allowIfCurrent(int observedGeneration) {
    if (observedGeneration != _generation) return false;
    _enabled = true;
    return true;
  }

  void invalidate({bool disable = true}) {
    _generation++;
    _globalToken = Object();
    _scopeTokens.clear();
    if (disable) _enabled = false;
  }

  void invalidateScopes(Set<String> scopeIds) {
    if (scopeIds.isEmpty) return;
    _generation++;
    for (final scope in scopeIds) {
      _scopeTokens.remove(scope);
    }
  }

  Object tokenForScope(String? scopeId) {
    if (scopeId == null) return _globalToken;
    final existing = _scopeTokens[scopeId];
    if (existing != null) return existing;
    // Eviction only forces proof reconstruction; it cannot admit authority.
    if (_scopeTokens.length >= 2048) {
      _scopeTokens.remove(_scopeTokens.keys.first);
    }
    return _scopeTokens[scopeId] = Object();
  }
}
