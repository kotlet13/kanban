import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/kanboard_models.dart';
import 'account_scope.dart';

class CacheStore {
  CacheStore._(this._box, [this._scope, this._generation = 0]);

  final Box<String> _box;
  final String? _scope;
  final int _generation;
  static final Map<String, int> _generations = {};
  static const _boxName = 'kanboard_cache_box';

  static Future<CacheStore> create({String? directory}) async {
    if (directory == null) {
      await Hive.initFlutter();
    } else {
      Hive.init(directory);
    }
    return CacheStore._(await Hive.openBox<String>(_boxName));
  }

  /// Immutable handle: account changes cannot redirect an in-flight write.
  CacheStore forAccount(KanboardCredentials credentials) {
    final scope = accountScopeKey(credentials);
    return CacheStore._(_box, scope, _generations[scope] ?? 0);
  }

  bool get _active =>
      _scope != null && (_generations[_scope] ?? 0) == _generation;
  String _key(String suffix) {
    if (_scope == null) throw StateError('An account scope is required.');
    return 'account_v2:$_scope:$suffix';
  }

  Future<void> saveProjects(List<KanboardProject> projects) async {
    if (!_active) return;
    await _box.put(
      _key('projects'),
      jsonEncode(projects.map((p) => p.toJson()).toList()),
    );
  }

  List<KanboardProject> readProjects() {
    if (!_active) return [];
    final payload = _box.get(_key('projects'));
    if (payload == null || payload.isEmpty) return [];
    final decoded = jsonDecode(payload) as List<dynamic>;
    return decoded
        .map((e) => KanboardProject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveBoard(KanboardBoard board) async {
    if (!_active) return;
    await _box.put(
      _key('board_${board.projectId}'),
      jsonEncode(board.toJson()),
    );
  }

  KanboardBoard? readBoard(int projectId) {
    if (!_active) return null;
    final payload = _box.get(_key('board_$projectId'));
    if (payload == null || payload.isEmpty) return null;
    return KanboardBoard.fromCachedJson(
      jsonDecode(payload) as Map<String, dynamic>,
    );
  }

  Future<void> clearScope() async {
    final scope = _scope;
    if (scope == null) return;
    // Invalidate old handles before the first await, including pending network replies.
    _generations[scope] = (_generations[scope] ?? 0) + 1;
    final prefix = 'account_v2:$scope:';
    final keys = _box.keys
        .where((key) => key is String && key.startsWith(prefix))
        .toList();
    await _box.deleteAll(keys);
  }
}
