class CollaborationSyncStart {
  const CollaborationSyncStart(this.sequence, this.identity);
  final int sequence;
  final String identity;
}

/// Local delivery bookkeeping only; these values confer no remote authority.
class CollaborationSyncWork {
  const CollaborationSyncWork(this.signature, {required this.unresolved});
  final String signature;
  final bool unresolved;
}

class CollaborationSyncCompletion {
  const CollaborationSyncCompletion({
    required this.sequence,
    required this.identity,
    required this.at,
    required this.work,
    this.error,
    this.retryAt,
  });
  final int sequence;
  final String identity;
  final DateTime at;
  final CollaborationSyncWork work;
  final Object? error;
  final DateTime? retryAt;
}
