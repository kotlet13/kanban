import 'collaboration_models.dart';

class SharedRecordMergeConflict implements Exception {
  const SharedRecordMergeConflict(this.fields);
  final Set<String> fields;
}

/// Field merge for ordinary records only. Coupled values stay one decision;
/// domain-specific finance, gardens, documents and idea merges remain separate.
Map<String, dynamic> mergeSharedRecordPayloads({
  required SharedRecordType type,
  required Map<String, dynamic> base,
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
}) {
  if (type == SharedRecordType.garden || type == SharedRecordType.idea) {
    throw const SharedRecordMergeConflict({'record'});
  }
  final conflicts = <String>{};
  for (final field in ['id', 'createdAt']) {
    if (!_sameSharedMergeValue(base[field], local[field]) ||
        !_sameSharedMergeValue(base[field], remote[field])) {
      conflicts.add(field);
    }
  }
  final ignored = {
    'updatedAt',
    'revision',
    'createdByAccountId',
    'updatedByAccountId',
  };
  final keys = {...base.keys, ...local.keys, ...remote.keys}
    ..removeAll(ignored);
  final groups = <Set<String>>[
    if (type == SharedRecordType.task ||
        type == SharedRecordType.event ||
        type == SharedRecordType.project)
      {'startAt', 'endAt'},
    if (type == SharedRecordType.task) ...[
      {'projectId', 'phaseId'},
      {'assigneeAccountIds', 'assigneePersonId'},
      {'availabilityMinutes', 'availabilityPeriod'},
    ],
    if (type == SharedRecordType.project)
      {'availabilityMinutes', 'availabilityPeriod'},
  ];
  final grouped = groups.expand((g) => g).toSet();
  groups.addAll(keys.difference(grouped).map((key) => {key}));
  final merged = <String, dynamic>{...base, ...remote};
  Map<String, dynamic> values(
    Map<String, dynamic> source,
    Set<String> group,
  ) => {
    for (final field in group)
      if (source.containsKey(field))
        field: source[field]
      // An older serializer omitting a known field cannot erase a newer value.
      else if (base.containsKey(field))
        field: base[field],
  };
  for (final group in groups) {
    final b = values(base, group),
        l = values(local, group),
        r = values(remote, group);
    final localChanged = !_sameSharedMergeValue(b, l),
        remoteChanged = !_sameSharedMergeValue(b, r);
    if (localChanged && remoteChanged && !_sameSharedMergeValue(l, r)) {
      conflicts.addAll(group);
    } else if (localChanged) {
      for (final entry in l.entries) {
        merged[entry.key] = entry.value;
      }
    }
  }
  if (conflicts.isNotEmpty) {
    throw SharedRecordMergeConflict(Set.unmodifiable(conflicts));
  }
  return merged;
}

bool _sameSharedMergeValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.entries.every(
          (entry) =>
              b.containsKey(entry.key) &&
              _sameSharedMergeValue(entry.value, b[entry.key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => i,
        ).every((i) => _sameSharedMergeValue(a[i], b[i]));
  }
  return a == b;
}

bool equivalentSharedRecordPayloads(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  Map<String, dynamic> semantic(Map<String, dynamic> value) => Map.of(value)
    ..remove('updatedAt')
    ..remove('revision')
    ..remove('createdByAccountId')
    ..remove('updatedByAccountId');
  return _sameSharedMergeValue(semantic(a), semantic(b));
}
