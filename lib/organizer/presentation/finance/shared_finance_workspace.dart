import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_forms.dart';
import '../organizer_widgets.dart';
import '../shared/sharing_recovery.dart';
import '../shared/sharing_session_boundary.dart';
import '../planning/task_plan_fields.dart';
import 'shared_finance_actions.dart';
import 'finance_planning_panel.dart';
import 'finance_permissions_dialog.dart';
import 'shared_finance_ledger.dart';
import 'shared_finance_conflicts.dart';
import '../../state/linked_payments_provider.dart';
import 'linked_payment_forms.dart';
import 'linked_payments_section.dart';

class SharedFinanceWorkspace extends ConsumerWidget {
  const SharedFinanceWorkspace({
    super.key,
    required this.scope,
    required this.state,
    this.titleAccessory,
  });
  final SharedScope scope;
  final CollaborationState state;
  final Widget? titleAccessory;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n, policy = state.financePolicyForScope(scope.id);
    final actions = SharedFinanceActions(context, ref, scope, state);
    final paymentSpace = PaymentSpaceRef(
      scope.id,
      partition: state.session?.partition,
    );
    final paymentsAsync = ref.watch(
      linkedPaymentsProvider(paymentSpaceKey(paymentSpace)),
    );
    final payments = paymentsAsync.isLoading
        ? null
        : paymentsAsync.asData?.value;
    final cashAvailable =
        !policy.linkedPaymentsRequired ||
        payments?.fresh == true && payments?.complete == true;
    if (!state.financeSupported) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrganizerHeading(
            title: l.organizerFinances,
            titleAccessory: titleAccessory,
          ),
          Text(l.financeUnsupported),
        ],
      );
    }
    final data = state.dataForScope(scope.id);
    final managed =
        policy.managedByOrganizationPolicy ||
        scope.accessPolicyVersion >= 2 &&
            (scope.kind == SharedScopeKind.organization ||
                scope.kind == SharedScopeKind.project);
    final online =
        !state.sessionInvalid &&
        !state.deletionPending &&
        state.session?.expiresAt.isAfter(DateTime.now()) == true;
    final owner =
        scope.role == SharedRole.owner && !scope.revoked && !scope.archived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.organizerFinances,
          titleAccessory: titleAccessory,
        ),
        if (owner && online)
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => showFinancePermissions(context, ref, scope.id),
                icon: const Icon(Icons.manage_accounts_outlined),
                label: Text(l.financePermissions),
              ),
              if (!managed)
                TextButton(
                  onPressed: () => actions.run(() async {
                    final guard = SharingSessionGuard(context, ref);
                    if (policy.enabled) {
                      final confirmed = await confirmSharingAction(
                        context,
                        title: l.financeDisable,
                        description: l.financeDisableDescription,
                        confirmLabel: l.financeDisable,
                        wrap: (child) =>
                            SharingSessionBoundary(guard: guard, child: child),
                      );
                      if (!confirmed) return;
                    }
                    await guard.controller.enableFinance(
                      scope.id,
                      !policy.enabled,
                    );
                  }),
                  child: Text(
                    policy.enabled ? l.financeDisable : l.financeEnable,
                  ),
                ),
            ],
          ),
        if (!policy.enabled)
          Text(l.financeDisabled)
        else if (!policy.canRead)
          Text(l.financeNoAccess)
        else if (state.financeSnapshotComplete[scope.id] != true) ...[
          Text(l.financeLoadingSnapshot),
        ] else ...[
          FinancePlanningPanel(
            key: ValueKey(
              'shared-planning-${state.session!.partition}-${scope.id}',
            ),
            snapshot: sharedFinancePlanningSnapshot(state, scope.id),
            sharedScopeId: scope.id,
            payments: payments,
            forecastAvailable: cashAvailable,
          ),
          if (payments != null &&
              (policy.linkedPaymentsRequired ||
                  payments.events.isNotEmpty ||
                  payments.projections.isNotEmpty ||
                  payments.pendingCount > 0))
            LinkedPaymentsSection(space: paymentSpace, snapshot: payments),
          if (!cashAvailable) Text(l.paymentIncompleteBalance),
          SharedFinanceLedger(
            showHeading: false,
            key: ValueKey('finance-${state.session!.partition}-${scope.id}'),
            scopeName: scope.name,
            payments: payments,
            cashAvailable: cashAvailable,
            onPersonalPayment: canWritePaymentSource(ref, paymentSpace)
                ? (entry) => showPersonalPaymentForm(
                    context,
                    ref,
                    source: PaymentSourceRef(
                      space: paymentSpace,
                      entryId: entry.id,
                      expectedRevision: entry.revision,
                    ),
                    title: entry.title,
                    amountMinor: entry.amountMinor,
                    currency: entry.currency,
                    paidAt: entry.paidAt,
                  )
                : null,
            scopeId: scope.id,
            partition: state.session!.partition,
            accounts: data.financeAccounts,
            entries: data.financeEntries,
            transfers: data.financeTransfers,
            people: [
              for (final m
                  in state
                      .membersForScope(scope.id)
                      .where((m) => m.accountId.isNotEmpty))
                OrganizerPersonOption(
                  id: m.accountId,
                  label: m.displayName.isEmpty ? m.username : m.displayName,
                  active: m.active,
                ),
            ],
            canWrite:
                policy.canWrite &&
                !scope.blocked &&
                !scope.archived &&
                !state.deletionPending,
            onAccount: actions.account,
            onEntry: actions.entry,
            onTransfer: actions.transfer,
            onAudit: actions.audit,
          ),
        ],
      ],
    );
  }
}

/// Sync recovery actions live with the cloud, while financial facts stay on the page.
class SharedFinanceSyncDetails extends ConsumerWidget {
  const SharedFinanceSyncDetails({
    super.key,
    required this.state,
    required this.scopeId,
    required this.actionsEnabled,
  });
  final CollaborationState state;
  final String scopeId;
  final bool actionsEnabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = state.scopes.where((s) => s.id == scopeId).firstOrNull;
    if (scope == null) return const SizedBox.shrink();
    final l = context.l10n, policy = state.financePolicyForScope(scopeId);
    final actions = SharedFinanceActions(context, ref, scope, state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.financePendingCount > 0 ||
            state.financeBlockedCount > 0 ||
            state.financeConflicts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.financePendingCount > 0) Text(l.financePending),
                if (state.financeBlockedCount > 0) Text(l.financeBlocked),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => exportSharingDrafts(context, ref),
                      child: Text(l.sharingSaveDrafts),
                    ),
                    if (state.financeConflicts.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            showFinanceConflicts(context, ref, scope.id),
                        child: Text(l.financeConflicts),
                      ),
                    if (state.financeBlockedCount > 0 &&
                        policy.canWrite &&
                        actionsEnabled)
                      TextButton(
                        onPressed: () => actions.run(() async {
                          final guard = SharingSessionGuard(context, ref);
                          final confirmed = await confirmSharingAction(
                            context,
                            title: l.sharingResumeBlocked,
                            description: l.sharingResumeBlockedDescription,
                            confirmLabel: l.sharingResumeBlocked,
                            wrap: (child) => SharingSessionBoundary(
                              guard: guard,
                              child: child,
                            ),
                          );
                          if (confirmed) {
                            await guard.controller.resumeBlockedFinanceChanges(
                              scope.id,
                            );
                          }
                        }),
                        child: Text(l.sharingResumeBlocked),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
