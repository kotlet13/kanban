/// Server supplied terms and a deliberately session-bound explicit consent.
class SharedContentPolicy {
  const SharedContentPolicy({
    required this.serverId,
    required this.partition,
    required this.deviceId,
    required this.policyVersion,
    required this.title,
    required this.textSl,
    required this.textEn,
    required this.recipientName,
    required this.accepted,
    this.acceptedAt,
  });
  final String serverId,
      partition,
      deviceId,
      title,
      textSl,
      textEn,
      recipientName;
  final int policyVersion;
  final bool accepted;
  final DateTime? acceptedAt;
}

/// One online preview. It is never persisted or placed in a background queue.
/// Its request ID remains unchanged when the user explicitly retries submission.
class ContentReportPreview {
  ContentReportPreview({
    required this.serverId,
    required this.partition,
    required this.deviceId,
    required this.requestId,
    required this.scopeId,
    required this.targetType,
    required this.targetId,
    required this.previewHash,
    required this.targetRevision,
    required this.title,
    required this.type,
    required this.recipientName,
    required Map<String, dynamic> evidence,
  }) : evidence = Map.unmodifiable({
         for (final entry in evidence.entries)
           entry.key: _freezeReportValue(entry.value),
       });
  final String serverId,
      partition,
      deviceId,
      requestId,
      scopeId,
      targetType,
      targetId,
      previewHash,
      title,
      type,
      recipientName;
  final int targetRevision;
  final Map<String, dynamic> evidence;
}

class ContentReportReceipt {
  const ContentReportReceipt({
    required this.reportId,
    required this.status,
    required this.createdAt,
  });
  final String reportId, status;
  final DateTime createdAt;
}

Object? _freezeReportValue(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freezeReportValue(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeReportValue));
  }
  return value;
}
