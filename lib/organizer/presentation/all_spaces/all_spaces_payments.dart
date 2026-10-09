import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../domain/all_spaces_projection.dart';
import '../../state/linked_payments_provider.dart';
import '../finance/finance_money.dart';
import '../organizer_widgets.dart';
import 'all_spaces_area.dart';

typedef VisiblePaymentSource = ({
  PaymentSnapshot payments,
  String name,
  AllSpacesSource? source,
});

class VisiblePaymentReceipt {
  const VisiblePaymentReceipt(
    this.key,
    this.event,
    this.projection,
    this.name,
    this.source,
  );
  final String key, name;
  final PaymentEvent event;
  final PaymentProjection? projection;
  final AllSpacesSource? source;
}

class VisiblePayments {
  const VisiblePayments(this.receipts, this.totals, this.incomplete);
  final List<VisiblePaymentReceipt> receipts;
  final PaymentSnapshot totals;
  final bool incomplete;
}

/// A newer canonical event updates the same receipt, including older downloaded
/// personal/household views. Equal revisions retain restrictive recovery states.
VisiblePayments mergeVisiblePayments(Iterable<VisiblePaymentSource> sources) {
  final events = <String, PaymentEvent>{},
      projections = <String, PaymentProjection>{};
  final origins = <String, VisiblePaymentSource>{};
  var incomplete = false;
  String key(PaymentEvent e) =>
      '${e.sourcePartition ?? 'local'}:${e.sourceScopeId}:${e.eventId}';
  int rank(PaymentProjectionState state) => switch (state) {
    PaymentProjectionState.sourceRemoved => 4,
    PaymentProjectionState.blocked => 3,
    PaymentProjectionState.pending => 2,
    PaymentProjectionState.sourceConfirmed => 1,
    PaymentProjectionState.complete => 0,
  };
  for (final source in sources) {
    final snapshot = source.payments;
    incomplete = incomplete || !snapshot.fresh || !snapshot.complete;
    for (final projection in snapshot.projections) {
      final k = key(projection.event), previous = projections[k];
      if (previous == null ||
          projection.event.revision > previous.event.revision ||
          projection.event.revision == previous.event.revision &&
              rank(projection.state) > rank(previous.state)) {
        projections[k] = projection;
      }
      if (events[k] == null ||
          projection.event.revision > events[k]!.revision) {
        events[k] = projection.event;
        origins[k] = source;
      }
    }
    for (final event in snapshot.events) {
      final k = key(event);
      if (events[k] == null || event.revision >= events[k]!.revision) {
        events[k] = event;
        origins[k] = source;
      }
    }
  }
  final receipts = <VisiblePaymentReceipt>[];
  final mergedProjections = <PaymentProjection>[];
  for (final row in events.entries) {
    final projection = projections[row.key], origin = origins[row.key]!;
    PaymentProjection? merged;
    if (projection != null) {
      if (projection.event.revision != row.value.revision) incomplete = true;
      merged = PaymentProjection(
        event: row.value,
        state: projection.state,
        privateAccountId: projection.privateAccountId,
      );
      mergedProjections.add(merged);
    }
    receipts.add(
      VisiblePaymentReceipt(
        row.key,
        row.value,
        merged,
        origin.name,
        origin.source,
      ),
    );
  }
  receipts.sort((a, b) => b.event.paidAt.compareTo(a.event.paidAt));
  return VisiblePayments(
    List.unmodifiable(receipts),
    PaymentSnapshot(projections: mergedProjections),
    incomplete,
  );
}

/// Aggregate receipts never become a second expense or a write target.
class AllSpacesPayments extends ConsumerWidget {
  const AllSpacesPayments({super.key, required this.snapshot, this.onSource});
  final AllSpacesSnapshot snapshot;
  final Future<void> Function(
    AllSpacesSource source,
    AllSpacesArea area,
    String? id,
  )?
  onSource;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = <VisiblePaymentSource>[];
    var loading = false;
    for (final source in snapshot.sources.where(
      (s) =>
          s.canReadFinance && s.localSpace?.financeRecoveryIncomplete != true,
    )) {
      final space = source.isPersonal
          ? source.privateScopeId != null && source.session != null
                ? PaymentSpaceRef(
                    source.privateScopeId!,
                    partition: source.session!.partition,
                  )
                : PaymentSpaceRef(source.workspaceKey!)
          : PaymentSpaceRef(
              source.scopeId!,
              partition: source.session!.partition,
            );
      final state = ref.watch(linkedPaymentsProvider(paymentSpaceKey(space)));
      if (state.isLoading || state.hasError) {
        loading = true;
        continue;
      }
      if (state.asData?.value != null) {
        sources.add((
          payments: state.asData!.value,
          name: source.name ?? context.l10n.organizerPersonal,
          source: source,
        ));
      }
    }
    final merged = mergeVisiblePayments(sources);
    if (merged.receipts.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(title: l.paymentLinkedPayments),
        if (loading || merged.incomplete) Text(l.paymentPending),
        for (final total in merged.totals.receivableByCurrency.entries)
          Text(
            '${l.paymentRemaining}: ${sharedMoneyLabel(context, total.value, total.key)}',
          ),
        for (final receipt in merged.receipts)
          Card(
            key: ValueKey('all-linked-payment-${receipt.key}'),
            child: ListTile(
              leading: const Icon(Icons.credit_card_outlined),
              title: Text(
                '${l.paymentPersonalDisplay} · ${sharedMoneyLabel(context, BigInt.from(receipt.event.amountMinor), receipt.event.currency)}',
              ),
              subtitle: Text(
                '${receipt.name} · ${organizerDate(context, receipt.event.paidAt)}\n${receipt.projection?.state == PaymentProjectionState.sourceRemoved
                    ? l.paymentSourceRemovedDescription
                    : receipt.projection?.state == PaymentProjectionState.blocked
                    ? l.paymentBlocked
                    : receipt.event.expectReimbursement
                    ? '${l.paymentRemaining}: ${sharedMoneyLabel(context, BigInt.from(receipt.event.receivableMinor), receipt.event.currency)}'
                    : l.paymentNoRefundExpected}',
              ),
              onTap: receipt.source == null || onSource == null
                  ? null
                  : () => onSource!(
                      receipt.source!,
                      AllSpacesArea.finances,
                      receipt.event.sourceEntryId,
                    ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
