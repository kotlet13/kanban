import '../../domain/organizer_models.dart';
import '../../domain/collaboration_models.dart';
import '../../domain/linked_payment_models.dart';

/// Only account references displayed in the personal projection are mapped.
/// Immutable event, cash-movement and source IDs remain canonical in storage.
PaymentSnapshot? paymentsForPersonalSnapshot(
  OrganizerSnapshot personal,
  CollaborationState? shared,
  PaymentSnapshot? payments,
) {
  if (payments == null || !personal.workspaceKey.startsWith('private:')) {
    return payments;
  }
  if (shared?.session == null ||
      personal.workspaceKey != 'private:${shared!.session!.partition}' ||
      !shared.localAccessAllowed) {
    return null;
  }
  return PaymentSnapshot(
    events: payments.events,
    projections: payments.projections,
    pendingCount: payments.pendingCount,
    fresh: payments.fresh,
    cashMovements: [
      for (final movement in payments.cashMovements)
        PaymentCashMovement(
          id: movement.id,
          accountId: shared.personalRecordId(movement.accountId),
          amountMinor: movement.amountMinor,
          currency: movement.currency,
          paidAt: movement.paidAt,
        ),
    ],
  );
}
