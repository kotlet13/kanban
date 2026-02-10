import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/kanboard_models.dart';

class CacheStore {
  CacheStore._(this._box);

  final Box<String> _box;

  static const _boxName = 'kanboard_cache_box';
  static const _projectsKey = 'projects';
  static const _boardPrefix = 'board_';

  static Future<CacheStore> create() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<String>(_boxName);
    return CacheStore._(box);
  }

  Future<void> saveProjects(List<KanboardProject> projects) async {
    await _box.put(
      _projectsKey,
      jsonEncode(projects.map((p) => p.toJson()).toList()),
    );
  }

  List<KanboardProject> readProjects() {
    final payload = _box.get(_projectsKey);
    if (payload == null || payload.isEmpty) return <KanboardProject>[];
    final decoded = jsonDecode(payload) as List<dynamic>;
    return decoded
        .map((e) => KanboardProject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveBoard(KanboardBoard board) async {
    await _box.put('$_boardPrefix${board.projectId}', jsonEncode(board.toJson()));
  }

  KanboardBoard? readBoard(int projectId) {
    final payload = _box.get('$_boardPrefix$projectId');
    if (payload == null || payload.isEmpty) return null;
    return KanboardBoard.fromCachedJson(
      jsonDecode(payload) as Map<String, dynamic>,
    );
  }
}
