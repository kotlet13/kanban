import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/linked_payments_provider.dart';
import '../organizer_widgets.dart';
import '../inbox/notification_target_view.dart' show organizerDateTime;
import '../shared/sharing_errors.dart';
import 'finance_money.dart';
import 'linked_payment_forms.dart';

class LinkedPaymentsSection extends ConsumerStatefulWidget {
  const LinkedPaymentsSection({
    super.key,
    required this.space,
    required this.snapshot,
  });
  final PaymentSpaceRef space;
  final PaymentSnapshot snapshot;
  @override
  ConsumerState<LinkedPaymentsSection> createState() =>
      _LinkedPaymentsSectionState();
}

class _LinkedPaymentsSectionState extends ConsumerState<LinkedPaymentsSection> {
  bool _busy = false;
  String? _error;
  Future<void> _run({bool refresh = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final repo = await container.read(
        linkedPaymentsRepositoryProvider.future,
      );
      if (refresh) {
        await repo.refresh(widget.space);
      } else {
        await repo.resumePending();
      }
      container.invalidate(
        linkedPaymentsProvider(paymentSpaceKey(widget.space)),
      );
    } catch (error) {
      if (mounted) setState(() => _error = sharingErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _title(PaymentEvent event) {
    if (event.sourcePartition == null) {
      return ref
              .read(localSpacesProvider)
              .valueOrNull
              ?.snapshots[event.sourceScopeId]
              ?.financeEntries
              .where((e) => e.id == event.sourceEntryId)
              .firstOrNull
              ?.title ??
          context.l10n.paymentLinkedExpense;
    }
    final state = ref.read(collaborationProvider).valueOrNull;
    if (state?.session?.partition == event.sourcePartition &&
        state?.financePolicyForScope(event.sourceScopeId).canRead == true &&
        state?.financeSnapshotComplete[event.sourceScopeId] == true) {
      return state
              ?.dataForScope(event.sourceScopeId)
              .financeEntries
              .where((e) => e.id == event.sourceEntryId)
              .firstOrNull
              ?.title ??
          context.l10n.paymentLinkedExpense;
    }
    return context.l10n.paymentLinkedExpense;
  }

  String? _account(PaymentProjection projection) {
    if (projection.privateAccountId == null) return null;
    final personal = ref
        .read(localSpacesProvider)
        .valueOrNull
        ?.snapshots['local'];
    final shared = ref.read(collaborationProvider).valueOrNull;
    final id = projection.privateAccountId!;
    return personal?.financeAccounts
        .where((a) => a.id == id || a.id == shared?.personalRecordId(id))
        .firstOrNull
        ?.name;
  }

  Widget _card(PaymentEvent event, {PaymentProjection? projection}) {
    final l = context.l10n;
    final blocked = projection?.state == PaymentProjectionState.blocked;
    final removed = projection?.state == PaymentProjectionState.sourceRemoved;
    final waitingSource =
        event.sourcePartition == null &&
        (projection?.state == PaymentProjectionState.pending ||
            widget.space.isLocal && widget.snapshot.pendingCount > 0);
    final pending =
        widget.snapshot.pendingCount > 0 ||
        projection != null &&
            projection.state != PaymentProjectionState.complete;
    final account = projection == null ? null : _account(projection);
    final state = ref.read(collaborationProvider).valueOrNull;
    final payer = state
        ?.membersForScope(event.sourceScopeId)
        .where((m) => m.accountId == event.payerAccountId)
        .firstOrNull;
    return Card(
      key: ValueKey('linked-payment-${event.eventId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              removed ? l.paymentSourceRemoved : _title(event),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${l.paymentPersonalDisplay} · ${sharedMoneyLabel(context, BigInt.from(event.amountMinor), event.currency)}',
            ),
            Text(organizerDateTime(context, event.paidAt)),
            if (payer != null)
              Text(
                '${l.financePayer}: ${payer.displayName.isEmpty ? payer.username : payer.displayName}',
              ),
            if (account != null) Text('${l.paymentMyAccount}: $account'),
            if (blocked)
              Text(l.paymentBlocked)
            else if (removed)
              Text(l.paymentSourceRemovedDescription)
            else ...[
              Text(
                event.expectReimbursement
                    ? '${l.paymentRemaining}: ${sharedMoneyLabel(context, BigInt.from(event.receivableMinor), event.currency)}'
                    : l.paymentNoRefundExpected,
              ),
              if (projection != null)
                Text(
                  '${l.paymentCashBurden}: ${sharedMoneyLabel(context, BigInt.from(event.cashBurdenMinor), event.currency)}',
                ),
            ],
            if (pending && !blocked && !removed)
              Text(waitingSource ? l.paymentWaitingSource : l.paymentPending),
            for (final refund in event.reimbursements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.undo_outlined),
                title: Text(
                  '${l.paymentRefundReceived} · ${sharedMoneyLabel(context, BigInt.from(refund.amountMinor), event.currency)}',
                ),
                subtitle: Text(organizerDateTime(context, refund.paidAt)),
              ),
            if (projection == null &&
                event.expectReimbursement &&
                event.receivableMinor > 0 &&
                canWritePaymentSource(ref, widget.space) &&
                (widget.snapshot.pendingCount == 0 || widget.space.isLocal))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('refund-payment-${event.eventId}'),
                  onPressed: _busy
                      ? null
                      : () => showPaymentRefundForm(
                          context,
                          ref,
                          source: widget.space,
                          event: event,
                        ),
                  icon: const Icon(Icons.undo_outlined),
                  label: Text(l.paymentRefundAction),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(collaborationProvider);
    ref.watch(localSpacesProvider);
    final l = context.l10n, snapshot = widget.snapshot;
    if (snapshot.events.isEmpty &&
        snapshot.projections.isEmpty &&
        snapshot.pendingCount == 0 &&
        snapshot.fresh) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.paymentLinkedPayments,
          subtitle: snapshot.projections.isEmpty
              ? null
              : l.paymentProjectionDescription,
        ),
        if (snapshot.pendingCount > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('resume-linked-payments'),
              onPressed: _busy ? null : () => _run(),
              icon: const Icon(Icons.sync_outlined),
              label: Text(l.paymentRetry),
            ),
          ),
        if (!snapshot.fresh)
          TextButton.icon(
            onPressed: _busy ? null : () => _run(refresh: true),
            icon: const Icon(Icons.refresh),
            label: Text(l.paymentRefresh),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_busy) const LinearProgressIndicator(),
        for (final event in snapshot.events) _card(event),
        for (final projection in snapshot.projections)
          _card(projection.event, projection: projection),
        const SizedBox(height: 16),
      ],
    );
  }
}
