import 'package:shared_preferences/shared_preferences.dart';

class ProjectDefaults {
  const ProjectDefaults({
    this.columnNames = const <String>[],
    this.defaultSwimlaneName,
    this.defaultCurrencyCode,
  });

  final List<String> columnNames;
  final String? defaultSwimlaneName;
  final String? defaultCurrencyCode;

  bool get hasAnyValue =>
      columnNames.isNotEmpty ||
      (defaultSwimlaneName != null && defaultSwimlaneName!.isNotEmpty) ||
      (defaultCurrencyCode != null && defaultCurrencyCode!.isNotEmpty);
}

class ProjectDefaultsStore {
  const ProjectDefaultsStore();

  static const _columnsKey = 'project_defaults_columns';
  static const _swimlaneKey = 'project_defaults_swimlane';
  static const _currencyKey = 'project_defaults_currency';

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

    final currencyRaw = prefs.getString(_currencyKey);
    final currency = _normalizeCurrencyCode(currencyRaw);

    return ProjectDefaults(
      columnNames: columns,
      defaultSwimlaneName: swimlane,
      defaultCurrencyCode: currency,
    );
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

    final currency = _normalizeCurrencyCode(defaults.defaultCurrencyCode);
    if (currency == null) {
      await prefs.remove(_currencyKey);
    } else {
      await prefs.setString(_currencyKey, currency);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_columnsKey);
    await prefs.remove(_swimlaneKey);
    await prefs.remove(_currencyKey);
  }

  String? _normalizeCurrencyCode(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) return null;
    return normalized;
  }
}
