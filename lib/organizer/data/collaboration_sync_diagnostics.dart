import 'dart:collection';

/// Optional in-memory diagnostics. Values are enums/counts, never identities,
/// selectors, cursors, proof bytes or business payloads.
enum CollaborationSyncDiagnosticKind {
  probe,
  legacyDirectoryHint,
  directoryCoveredByAccess,
  verifiedJournalOnly,
  verifiedDirectoryChanged,
  directoryVerificationFailed,
  unchanged,
  selectedHints,
  selectedWork,
  recoveryFallback,
  cursorAcknowledged,
  cursorInvalidated,
  // Selection origins only, emitted at most once each per probe decision.
  // They distinguish required compatibility/access work from data-only hints.
  selectionLegacyServer,
  selectionMissingCursor,
  selectionRejectedCursor,
  selectionReset,
  selectionAccountAccess,
  selectionAccountMetadata,
  selectionScopeAccess,
  selectionContentHint,
  selectionFinanceHint,
  selectionDocumentsHint,
  selectionUnknownScope,
  selectionLocalContent,
  selectionLocalFinance,
  selectionLocalCommands,
  selectionPendingCrypto,
  selectionParentFinanceDependency,
}

enum CollaborationRecoveryFallback {
  payments,
  inventoryLimit,
  unsupportedCommand,
  invalidEvidence,
  incompleteClaims,
  unreplayableOperation,
  unknownDependency,
}

class CollaborationSyncDiagnostic {
  const CollaborationSyncDiagnostic(
    this.kind,
    this.scopeCount,
    this.contentScopeCount,
    this.financeScopeCount,
    this.recoveryFallback,
  );
  final CollaborationSyncDiagnosticKind kind;
  final int scopeCount;
  final int contentScopeCount, financeScopeCount;
  final CollaborationRecoveryFallback? recoveryFallback;
}

class CollaborationSyncDiagnostics {
  CollaborationSyncDiagnostics({this.onEvent});
  final void Function(CollaborationSyncDiagnostic)? onEvent;
  final _events = Queue<CollaborationSyncDiagnostic>();
  List<CollaborationSyncDiagnostic> get events => List.unmodifiable(_events);

  void record(
    CollaborationSyncDiagnosticKind kind, {
    int scopeCount = 0,
    int contentScopeCount = 0,
    int financeScopeCount = 0,
    CollaborationRecoveryFallback? recoveryFallback,
  }) {
    final event = CollaborationSyncDiagnostic(
      kind,
      scopeCount.clamp(0, 10000).toInt(),
      contentScopeCount.clamp(0, 10000).toInt(),
      financeScopeCount.clamp(0, 10000).toInt(),
      recoveryFallback,
    );
    if (_events.length == 64) _events.removeFirst();
    _events.add(event);
    // Diagnostics cannot alter request delivery or acknowledgement.
    try {
      onEvent?.call(event);
    } catch (_) {}
  }
}
