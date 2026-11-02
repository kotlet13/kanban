/// The exact local checkpoint publisher exit. Diagnostic only; never authority.
enum PaymentCheckpointStep {
  scopeStateMissing,
  inventorySequenceChanged,
  projectedRecordMissing,
  projectedRevisionMismatch,
  projectedProofMismatch,
  projectedHistoryUnverified,
  receivedInventoryUncovered,
  restoreAnchorUncovered,
  businessRecordOmitted,
  commandAuthorityPending,
  commandCheckpointChanged,
  commandCheckpointImmutable,
  checkpointVerificationPending,
  completionStateMissing,
  completionFloorChanged,
  completionAccessRevisionChanged,
  completionScopeSequenceChanged,
  completionScanGenerationChanged,
  completionProjectionCursorBehind,
  completionSessionChanged,
  completionCheckpointMissing,
  completionBusinessRecordStale,
  completionRestoreAnchorUncovered,
  completionReceivedUnverified,
  completionReceivedProofUnmatched,
  completionCountMismatch,
  reusableCheckpoint,
  complete,
}

/// Fixed unresolved record states, with no record identity or content.
enum PaymentRecordVerdict { received, quarantined }

/// Safe, bounded local context. The reason sanitizer is mandatory at every
/// serialization boundary so this type does not depend on sync failure models.
class PaymentCompletionDiagnostics {
  const PaymentCompletionDiagnostics({
    required this.checkpointStep,
    this.recordReason,
    this.recordVerdict,
  });

  final PaymentCheckpointStep checkpointStep;
  final String? recordReason;
  final PaymentRecordVerdict? recordVerdict;

  static PaymentCompletionDiagnostics? fromJson(
    Object? value, {
    required String Function(String?) sanitizeReason,
  }) {
    if (value is! Map) return null;
    final step = PaymentCheckpointStep.values
        .where((v) => v.name == value['checkpointStep'])
        .firstOrNull;
    if (step == null) return null;
    final verdict = PaymentRecordVerdict.values
        .where((v) => v.name == value['recordVerdict'])
        .firstOrNull;
    final reason = value['recordReason'];
    return PaymentCompletionDiagnostics(
      checkpointStep: step,
      recordVerdict: verdict,
      recordReason: reason is String ? sanitizeReason(reason) : null,
    );
  }

  Map<String, Object> toSafeDiagnosticJson({
    required String Function(String?) sanitizeReason,
  }) => {
    'checkpointStep': checkpointStep.name,
    if (recordVerdict != null) 'recordVerdict': recordVerdict!.name,
    if (recordReason != null) 'recordReason': sanitizeReason(recordReason),
  };
}
