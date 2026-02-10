import 'package:shared_preferences/shared_preferences.dart';

class ProjectDefaults {
  const ProjectDefaults({
    this.columnNames = const <String>[],
    this.defaultSwimlaneName,
  });

  final List<String> columnNames;
  final String? defaultSwimlaneName;

  bool get hasAnyValue =>
      columnNames.isNotEmpty ||
      (defaultSwimlaneName != null && defaultSwimlaneName!.isNotEmpty);
}

class ProjectDefaultsStore {
  const ProjectDefaultsStore();

  static const _columnsKey = 'project_defaults_columns';
  static const _swimlaneKey = 'project_defaults_swimlane';

  Future<ProjectDefaults> read() async {
    final prefs = await SharedPreferences.getInstance();
    final columns = (prefs.getStringList(_columnsKey) ?? const <String>[])
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final swimlaneRaw = prefs.getString(_swimlaneKey);
    final swimlane = swimlaneRaw == null || swimlaneRaw.trim().isEmpty
        ? null
        : swimlaneRaw.trim();

    return ProjectDefaults(columnNames: columns, defaultSwimlaneName: swimlane);
  }

  Future<void> save(ProjectDefaults defaults) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _columnsKey,
      defaults.columnNames
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList(),
    );

    final swimlane = defaults.defaultSwimlaneName?.trim();
    if (swimlane == null || swimlane.isEmpty) {
      await prefs.remove(_swimlaneKey);
    } else {
      await prefs.setString(_swimlaneKey, swimlane);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_columnsKey);
    await prefs.remove(_swimlaneKey);
  }
}
