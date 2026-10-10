import '../../domain/collaboration_models.dart';

enum SharingSyncStatus {
  local,
  unknown,
  synced,
  pending,
  syncing,
  offline,
  problem,
  paused,
  disabled,
}

/// Evidence owned by a contextual local view, separate from account totals.
class SharingStatusSupplement {
  const SharingStatusSupplement({
    this.pendingCount = 0,
    this.blockedCount = 0,
    this.hasProblem = false,
    this.isOffline = false,
    this.requiresRefresh = false,
    this.label,
  });
  final int pendingCount, blockedCount;
  final bool hasProblem, requiresRefresh, isOffline;
  final String? label;
}

/// Account-wide refresh evidence; a scope label does not imply a separate sync.
class SharingStatusProjection {
  const SharingStatusProjection({
    required this.status,
    required this.pending,
    required this.conflicts,
    required this.blocked,
    required this.sessionValid,
  });
  final SharingSyncStatus status;
  final int pending, conflicts, blocked;
  final bool sessionValid;

  factory SharingStatusProjection.fromState(
    CollaborationState state, {
    required DateTime now,
    bool privateSync = false,
    bool busy = false,
    String? scopeId,
    Object? backgroundError,
    SharingStatusSupplement supplement = const SharingStatusSupplement(),
  }) {
    final session = state.session;
    final scope = state.scopes
        .where((scope) => scope.id == scopeId)
        .firstOrNull;
    final scopeBlocked = scope?.revoked == true || scope?.blocked == true;
    final valid =
        session != null &&
        !state.sessionInvalid &&
        session.expiresAt.isAfter(now) &&
        !state.deletionPending;
    // pendingCount already includes finance; older test/client projections may
    // expose its separate count before the aggregate is rebuilt.
    final pending = state.pendingCount >= state.financePendingCount
        ? state.pendingCount
        : state.financePendingCount;
    final conflicts = state.conflicts.length + state.financeConflicts.length;
    final blocked = state.blockedCount + state.financeBlockedCount;
    final status = session == null
        ? SharingSyncStatus.local
        : !valid || !state.localAccessAllowed || scopeBlocked
        ? SharingSyncStatus.problem
        : state.isSyncing || busy
        ? SharingSyncStatus.syncing
        : state.lastError?.code == 'network' ||
              backgroundError is CollaborationException &&
                  backgroundError.code == 'network'
        ? SharingSyncStatus.offline
        : state.lastError != null ||
              backgroundError != null ||
              conflicts > 0 ||
              blocked > 0
        ? SharingSyncStatus.problem
        : privateSync && !state.privateSync.enabled
        ? SharingSyncStatus.disabled
        : privateSync && state.privateSync.paused
        ? SharingSyncStatus.paused
        : pending > 0 || privateSync && state.privateSync.localPendingCount > 0
        ? SharingSyncStatus.pending
        : state.lastSuccessfulSyncAt != null
        ? SharingSyncStatus.synced
        : SharingSyncStatus.unknown;
    final contextualStatus =
        status == SharingSyncStatus.syncing ||
            status == SharingSyncStatus.offline ||
            status == SharingSyncStatus.problem
        ? status
        : supplement.isOffline
        ? SharingSyncStatus.offline
        : supplement.hasProblem || supplement.blockedCount > 0
        ? SharingSyncStatus.problem
        : supplement.pendingCount > 0
        ? SharingSyncStatus.pending
        : supplement.requiresRefresh
        ? SharingSyncStatus.unknown
        : status;
    return SharingStatusProjection(
      status: contextualStatus,
      pending: pending,
      conflicts: conflicts,
      blocked: blocked,
      sessionValid: valid,
    );
  }
}
