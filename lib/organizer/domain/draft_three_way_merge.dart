import 'dart:convert';

/// Presentation-only three-way comparison. Applying a result never writes data
/// or advances a repository revision; the editor must separately accept its
/// captured current replacement and keep the ordinary save guards.
class DraftThreeWayMerge {
  DraftThreeWayMerge({
    required this.base,
    required this.mine,
    required this.latest,
  });
  final Map<String, Object?> base, mine, latest;
  static bool equal(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
  Iterable<String> get changed => base.keys.where(
    (key) => !equal(base[key], mine[key]) || !equal(base[key], latest[key]),
  );
  Set<String> get conflicts => {
    for (final key in changed)
      if (!equal(base[key], mine[key]) &&
          !equal(base[key], latest[key]) &&
          !equal(mine[key], latest[key]))
        key,
  };
  Map<String, Object?>? resolve(Map<String, bool> keepMine) {
    if (!conflicts.every(keepMine.containsKey)) return null;
    return {
      for (final key in base.keys)
        key: conflicts.contains(key)
            ? (keepMine[key]! ? mine[key] : latest[key])
            : !equal(base[key], mine[key])
            ? mine[key]
            : latest[key],
    };
  }
}
