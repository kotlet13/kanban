import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_forms.dart';
import '../shared/sharing_recovery.dart';
import '../shared/sharing_session_boundary.dart';
import '../planning/task_plan_fields.dart';
import 'shared_finance_actions.dart';
import 'finance_planning_panel.dart';
import 'finance_permissions_dialog.dart';
import 'shared_finance_ledger.dart';
import 'shared_finance_conflicts.dart';

class SharedFinanceWorkspace extends ConsumerWidget {
  const SharedFinanceWorkspace({
    super.key,
    required this.scope,
    required this.state,
  });
  final SharedScope scope;
  final CollaborationState state;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n, policy = state.financePolicyForScope(scope.id);
    final actions = SharedFinanceActions(context, ref, scope, state);
    if (!state.financeSupported) return Text(l.financeUnsupported);
    final data = state.dataForScope(scope.id);
    final owner =
        scope.role == SharedRole.owner && !scope.revoked && !scope.archived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (owner)
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => showFinancePermissions(context, ref, scope.id),
                icon: const Icon(Icons.manage_accounts_outlined),
                label: Text(l.financePermissions),
              ),
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
        if (state.financePendingCount > 0 ||
            state.financeBlockedCount > 0 ||
            state.financeConflicts.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                      if (state.financeBlockedCount > 0 && policy.canWrite)
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
                              await guard.controller
                                  .resumeBlockedFinanceChanges(scope.id);
                            }
                          }),
                          child: Text(l.sharingResumeBlocked),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (!policy.enabled)
          Text(l.financeDisabled)
        else if (!policy.canRead)
          Text(l.financeNoAccess)
        else if (state.financeSnapshotComplete[scope.id] != true) ...[
          const LinearProgressIndicator(),
          Text(l.financeLoadingSnapshot),
        ] else ...[
          FinancePlanningPanel(
            key: ValueKey(
              'shared-planning-${state.session!.partition}-${scope.id}',
            ),
            snapshot: sharedFinancePlanningSnapshot(state, scope.id),
            sharedScopeId: scope.id,
          ),
          SharedFinanceLedger(
            key: ValueKey('finance-${state.session!.partition}-${scope.id}'),
            scopeName: scope.name,
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
                state.session!.expiresAt.isAfter(DateTime.now()) &&
                state.lastError?.code != 'device_revoked' &&
                state.lastError?.code != 'auth_required',
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
