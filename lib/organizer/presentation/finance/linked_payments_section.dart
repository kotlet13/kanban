import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/linked_payments_provider.dart';
import '../organizer_widgets.dart';
import '../inbox/notification_target_view.dart' show organizerDateTime;
import '../shared/sharing_errors.dart';
import '../shared/sharing_status.dart';
import '../shared/sharing_session_boundary.dart';
import '../shared/sharing_sync_conflicts.dart';
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
  final _busyStatus = ValueNotifier<bool>(false);
  late final ValueNotifier<SharingStatusSupplement> _paymentStatus;
  @override
  void initState() {
    super.initState();
    _paymentStatus = ValueNotifier(_supplement());
  }

  SharingStatusSupplement _supplement() => SharingStatusSupplement(
    pendingCount: widget.snapshot.pendingCount,
    blockedCount: widget.snapshot.projections
        .where((p) => p.state == PaymentProjectionState.blocked)
        .length,
    hasProblem: _error != null,
    isOffline: _offline,
    label: _statusLabel,
    requiresRefresh: !widget.snapshot.fresh || !widget.snapshot.complete,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _statusLabel = context.l10n.paymentLinkedPayments;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishStatus();
    });
  }

  void _publishStatus() {
    if (mounted) _paymentStatus.value = _supplement();
  }

  @override
  void didUpdateWidget(covariant LinkedPaymentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space.key != widget.space.key) {
      _error = null;
      _offline = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishStatus();
    });
  }

  bool get _busy => _busyStatus.value;
  @override
  void dispose() {
    _busyStatus.dispose();
    _paymentStatus.dispose();
    super.dispose();
  }

  String? _error;
  bool _offline = false;
  String? _statusLabel;
  Future<void> _run({
    bool refresh = false,
    PaymentSpaceRef? expectedSpace,
  }) async {
    if (!mounted || _busy) return;
    final space = expectedSpace ?? widget.space;
    if (widget.space.key != space.key) return;
    final guard = SharingSessionGuard(context, ref, allowSignedOut: true);
    bool current() =>
        mounted && widget.space.key == space.key && guard.isCurrent;
    setState(() {
      _busyStatus.value = true;
      _error = null;
      _offline = false;
    });
    _publishStatus();
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final repo = await container.read(
        linkedPaymentsRepositoryProvider.future,
      );
      if (!current()) return;
      if (refresh) {
        await repo.refresh(space);
      } else {
        await repo.resumePending();
      }
      if (current()) {
        container.invalidate(linkedPaymentsProvider(paymentSpaceKey(space)));
      }
    } catch (error) {
      if (current()) {
        setState(() {
          _error = sharingErrorMessage(context, error);
          _offline = error is CollaborationException && error.code == 'network';
        });
        _publishStatus();
      }
    } finally {
      if (mounted) setState(() => _busyStatus.value = false);
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
    final shared = ref.watch(collaborationProvider).valueOrNull;
    ref.watch(localSpacesProvider);
    final l = context.l10n, snapshot = widget.snapshot;
    final originSpace = widget.space;
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
          titleAccessory: SharingStatus(
            key: ValueKey('linked-payments-sync-status-${originSpace.key}'),
            state: shared ?? CollaborationState(),
            scopeId: widget.space.partition == null ? null : widget.space.id,
            allowLocalActions: widget.space.partition == null,
            busyListenable: _busyStatus,
            supplementListenable: _paymentStatus,
            onSync: () => _run(
              refresh: widget.snapshot.pendingCount == 0,
              expectedSpace: originSpace,
            ),
            onConflicts: () => showSharingSyncConflicts(context, ref),
            detailsBuilder: (dialogContext, current, actionsEnabled) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.snapshot.pendingCount > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('resume-linked-payments'),
                      onPressed: !actionsEnabled
                          ? null
                          : () => _run(expectedSpace: originSpace),
                      icon: const Icon(Icons.sync_outlined),
                      label: Text(l.paymentRetry),
                    ),
                  ),
                if (!widget.snapshot.fresh)
                  TextButton.icon(
                    onPressed: !actionsEnabled
                        ? null
                        : () => _run(refresh: true, expectedSpace: originSpace),
                    icon: const Icon(Icons.refresh),
                    label: Text(l.paymentRefresh),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          subtitle: snapshot.projections.isEmpty
              ? null
              : l.paymentProjectionDescription,
        ),
        for (final event in snapshot.events) _card(event),
        for (final projection in snapshot.projections)
          _card(projection.event, projection: projection),
        const SizedBox(height: 16),
      ],
    );
  }
}
