/// Native contracts accept validated UTC timestamps with optional microseconds;
/// personal backup dates retain their stricter canonical representation.
DateTime readSharedDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$',
      ).hasMatch(value)) {
    throw FormatException('Invalid UTC date: $key');
  }
  final date = DateTime.tryParse(value);
  if (date == null ||
      date.toUtc().toIso8601String().substring(0, 19) !=
          value.substring(0, 19)) {
    throw FormatException('Invalid UTC date: $key');
  }
  return date.toUtc();
}

DateTime? readNullableSharedDate(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : readSharedDate(json, key);
Map<String, dynamic> normalizeSharedPayloadDates(Map<String, dynamic> payload) {
  final json = Map<String, dynamic>.of(payload);
  for (final key in [
    'createdAt',
    'updatedAt',
    'startAt',
    'endAt',
    'dueAt',
    'occurredAt',
  ]) {
    if (json[key] != null) {
      json[key] = readSharedDate(json, key).toIso8601String();
    }
  }
  return json;
}
