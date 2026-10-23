import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organization_finance_projection.dart';
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

final _financeChoicesRefreshProvider = FutureProvider.autoDispose
    .family<void, (String, String)>(
      (ref, key) => ref
          .read(collaborationProvider.notifier)
          .refreshFinanceAccountChoices(key.$2),
    );

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
    final isProject = scope.kind == SharedScopeKind.project;
    if (isProject &&
        scope.parentSpaceId != null &&
        state.organizationFinanceSupported &&
        state.session != null &&
        !scope.revoked &&
        policy.canRead) {
      ref.watch(
        _financeChoicesRefreshProvider((state.session!.partition, scope.id)),
      );
    }
    final children = state.scopes
        .where(
          (s) =>
              s.kind == SharedScopeKind.project &&
              s.parentSpaceId == scope.id &&
              !s.deleted &&
              !s.revoked &&
              s.canRead,
        )
        .toList();
    final projectPayments = <String, PaymentSnapshot>{
      if (payments != null) scope.id: payments,
    };
    if (!isProject) {
      for (final child in children) {
        if (!state.financePolicyForScope(child.id).canRead) continue;
        final childPayment = ref
            .watch(
              linkedPaymentsProvider(
                paymentSpaceKey(
                  PaymentSpaceRef(
                    child.id,
                    partition: state.session?.partition,
                  ),
                ),
              ),
            )
            .valueOrNull;
        if (childPayment != null) projectPayments[child.id] = childPayment;
      }
    }
    final projection = !isProject
        ? projectOrganizationFinance(
            state: state,
            scopeId: scope.id,
            paymentsByScope: projectPayments,
          )
        : null;
    final cashAvailable =
        (!policy.linkedPaymentsRequired ||
            payments?.fresh == true && payments?.complete == true) &&
        (projection?.complete ?? true);
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
    final safeChoices =
        state.financeAccountChoices[scope.id] ?? <SharedFinanceAccountChoice>[];
    final accounts = projection?.accounts ?? data.financeAccounts;
    final originalEntries =
        projection?.originalEntries ??
        {for (final e in data.financeEntries) e.id: e};
    final entries =
        projection?.entries ??
        [
          for (final e in data.financeEntries)
            e.accountScopeId == null
                ? e
                : e.copyWith(accountId: '${e.accountScopeId}:${e.accountId}'),
        ];
    final accountNames = <String, String>{
      for (final a in safeChoices)
        '${a.scopeId}:${a.id}': '${a.name} · ${a.currency}',
    };
    final projectOptions = projection?.projectOptions ?? <String, String>{};
    SharedFinanceActions sourceActions(String? sourceId) {
      final id = sourceId ?? scope.id;
      final target = state.scopes.where((s) => s.id == id).firstOrNull ?? scope;
      return SharedFinanceActions(context, ref, target, state);
    }

    bool writable(String? id) =>
        state.financePolicyForScope(id ?? scope.id).canWrite &&
        state.financeSnapshotComplete[id ?? scope.id] == true &&
        state.scopes.any(
          (s) =>
              s.id == (id ?? scope.id) &&
              !s.archived &&
              !s.blocked &&
              !s.revoked &&
              !s.deleted,
        );
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
          if (!isProject && children.isEmpty)
            FinancePlanningPanel(
              key: ValueKey(
                'shared-planning-${state.session!.partition}-${scope.id}',
              ),
              snapshot: sharedFinancePlanningSnapshot(state, scope.id),
              sharedScopeId: scope.id,
              payments: payments,
              forecastAvailable: cashAvailable,
            ),
          if ((isProject || children.isNotEmpty) &&
              (data.financeAccounts.isNotEmpty ||
                  data.financeRecurrenceRules.isNotEmpty))
            ExpansionTile(
              title: Text(
                isProject
                    ? '${l.financeLegacyProjectAccount} · ${l.financePlanTitle}'
                    : l.financePlanTitle,
              ),
              children: [
                FinancePlanningPanel(
                  key: ValueKey(
                    'legacy-planning-${state.session!.partition}-${scope.id}',
                  ),
                  snapshot: sharedFinancePlanningSnapshot(state, scope.id),
                  sharedScopeId: scope.id,
                  forecastAvailable: false,
                  allowAccountCreation:
                      !isProject || scope.parentSpaceId == null,
                ),
              ],
            ),
          if (payments != null &&
              (policy.linkedPaymentsRequired ||
                  payments.events.isNotEmpty ||
                  payments.projections.isNotEmpty ||
                  payments.pendingCount > 0))
            LinkedPaymentsSection(space: paymentSpace, snapshot: payments),
          if (isProject) ...[
            Text(
              scope.parentSpaceId != null
                  ? l.financeProjectMovementDescription
                  : l.financeSharedAccountsDescription,
            ),
            if (!state.organizationFinanceSupported &&
                scope.parentSpaceId != null)
              Text(l.financeParentUpgradeRequired),
            if (state.organizationFinanceSupported &&
                safeChoices.isEmpty &&
                data.financeAccounts.isEmpty)
              Text(l.financeAccountChoicesUnavailable),
            if (scope.parentSpaceId != null)
              TextButton.icon(
                onPressed: () => actions.account(),
                icon: const Icon(Icons.account_balance_outlined),
                label: Text(l.financeManageParentAccounts),
              ),
          ],
          if (!cashAvailable && !isProject)
            Text(
              projection?.complete == false
                  ? l.financeParentSnapshotsIncomplete
                  : l.paymentIncompleteBalance,
            ),
          SharedFinanceLedger(
            showHeading: false,
            key: ValueKey('finance-${state.session!.partition}-${scope.id}'),
            scopeName: scope.name,
            payments: projection?.payments ?? payments,
            cashAvailable: cashAvailable,
            accountsAvailable: isProject
                ? !(state.organizationFinanceSupported &&
                      safeChoices.isEmpty &&
                      data.financeAccounts.isEmpty)
                : projection?.complete != false,
            showBalances: !isProject,
            allowNewAccounts:
                (!isProject || scope.parentSpaceId == null) &&
                writable(scope.id),
            allowTransfers:
                (!isProject || scope.parentSpaceId == null) &&
                writable(scope.id),
            description: isProject
                ? l.financeProjectOverview
                : l.financeSharedAccountsDescription,
            additionalAccountNames: accountNames,
            accountLabels: isProject
                ? {
                    for (final a in accounts)
                      a.id: l.financeLegacyProjectAccount,
                  }
                : {
                    for (final a in accounts)
                      if (projection?.accountScopeIds[a.id] != scope.id)
                        a.id: l.financeLegacyProjectAccount,
                  },
            projectOptions: projectOptions,
            entryProjectKeys: projection?.entryProjectKeys ?? {},
            entryScopeIds: {
              ...?projection?.entryScopeIds,
              ...?projection?.transferScopeIds,
            },
            recordIds: {
              for (final e in originalEntries.entries) e.key: e.value.id,
              for (final t
                  in projection?.originalTransfers.entries ??
                      <MapEntry<String, SharedFinanceTransfer>>[])
                t.key: t.value.id,
            },
            canEditEntry: (e) => writable(projection?.entryScopeIds[e.id]),
            canEditAccount: (a) => writable(projection?.accountScopeIds[a.id]),
            canPersonalPayment: (entry) {
              final original = originalEntries[entry.id] ?? entry;
              final origin = projection?.entryScopeIds[entry.id] ?? scope.id;
              return original.accountScopeId == null &&
                  canWritePaymentSource(
                    ref,
                    PaymentSpaceRef(
                      origin,
                      partition: state.session?.partition,
                    ),
                  );
            },
            onPersonalPayment: (entry) {
              final original = originalEntries[entry.id] ?? entry;
              final origin = projection?.entryScopeIds[entry.id] ?? scope.id;
              if (original.accountScopeId != null) return;
              showPersonalPaymentForm(
                context,
                ref,
                source: PaymentSourceRef(
                  space: PaymentSpaceRef(
                    origin,
                    partition: state.session?.partition,
                  ),
                  entryId: original.id,
                  expectedRevision: original.revision,
                ),
                title: original.title,
                amountMinor: original.amountMinor,
                currency: original.currency,
                paidAt: original.paidAt,
              );
            },
            scopeId: scope.id,
            partition: state.session!.partition,
            accounts: accounts,
            entries: entries,
            transfers: projection?.transfers ?? data.financeTransfers,
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
                (writable(scope.id) ||
                    !isProject &&
                        children.any((child) => writable(child.id))) &&
                !scope.blocked &&
                !scope.archived &&
                !state.deletionPending,
            onAccount: (account) => account == null
                ? actions.account()
                : sourceActions(
                    projection?.accountScopeIds[account.id],
                  ).account(
                    projection?.originalAccounts[account.id] ?? account,
                  ),
            onEntry: (entry) => entry == null
                ? actions.entry()
                : sourceActions(
                    projection?.entryScopeIds[entry.id],
                  ).entry(originalEntries[entry.id] ?? entry),
            onTransfer: (transfer) => transfer == null
                ? actions.transfer()
                : sourceActions(
                    projection?.transferScopeIds[transfer.id],
                  ).transfer(
                    projection?.originalTransfers[transfer.id] ?? transfer,
                  ),
            onAudit: (id) {
              final sourceId =
                  projection?.entryScopeIds[id] ??
                  projection?.accountScopeIds[id] ??
                  projection?.transferScopeIds[id];
              final originalId =
                  projection?.originalEntries[id]?.id ??
                  projection?.originalAccounts[id]?.id ??
                  projection?.originalTransfers[id]?.id ??
                  id;
              sourceActions(sourceId).audit(originalId);
            },
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
