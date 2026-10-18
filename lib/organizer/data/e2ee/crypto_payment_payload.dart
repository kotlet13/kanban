/// Preserve the authenticated canonical payload, including future fields. Model
/// serializers validate known values; they are never the archival representation.
Object? mergeCryptoPaymentPayload(Object? previous, Object? changed) {
  if (previous is Map && changed is Map) {
    return <String, dynamic>{
      for (final e in previous.entries) e.key as String: e.value,
      for (final e in changed.entries)
        e.key as String: mergeCryptoPaymentPayload(previous[e.key], e.value),
    };
  }
  if (previous is List &&
      changed is List &&
      changed.every(
        (v) => v is Map && (v['legId'] is String || v['id'] is String),
      )) {
    String identity(Map value) => (value['legId'] ?? value['id']) as String;
    final old = {
      for (final v in previous)
        if (v is Map && (v['legId'] is String || v['id'] is String))
          identity(v): v,
    };
    return [
      for (final v in changed)
        mergeCryptoPaymentPayload(old[identity(v as Map)], v),
    ];
  }
  return changed;
}

/// One projection revision plus at most 31 cash revisions fits the existing
/// atomic 32-record contract. Every chunk keeps the same source proof identity;
/// only the final inventory acknowledgement may mark the projection complete.
List<List<T>> cryptoPaymentCatchupGroups<T>(
  List<T> values, {
  int capacity = 31,
}) {
  if (capacity < 1 || capacity > 31)
    throw ArgumentError.value(capacity, 'capacity');
  return [
    for (var i = 0; i < values.length; i += capacity)
      values.sublist(i, (i + capacity).clamp(0, values.length)),
  ];
}
