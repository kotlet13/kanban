import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/shared_record_access.dart';
import 'shared_finance_actions.dart';
import 'shared_finance_account_overview.dart';

/// A read destination, with account creation offered as a separate action.
Future<void> showSharedFinanceAccounts(
  BuildContext context,
  CollaborationState state,
  String scopeId, {
  String? projectScopeId,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SharedFinanceAccountsDialog(
    scopeId: scopeId,
    projectScopeId: projectScopeId,
    partition: state.session?.partition,
    deviceId: state.session?.deviceId,
  ),
);

class _SharedFinanceAccountsDialog extends ConsumerWidget {
  const _SharedFinanceAccountsDialog({
    required this.scopeId,
    required this.projectScopeId,
    required this.partition,
    required this.deviceId,
  });
  final String scopeId;
  final String? partition, deviceId, projectScopeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(collaborationProvider);
    final state = value.valueOrNull;
    final current =
        partition != null &&
        deviceId != null &&
        !value.isLoading &&
        !value.hasError &&
        state?.session?.partition == partition &&
        state?.session?.deviceId == deviceId &&
        state?.localAccessAllowed == true &&
        state?.sessionInvalid == false &&
        state?.deletionPending == false;
    final scope = current
        ? state!.scopes.where((s) => s.id == scopeId).firstOrNull
        : null;
    final policy = state?.financePolicyForScope(scopeId);
    final readable =
        scope != null &&
        scope.canRead &&
        !scope.revoked &&
        !scope.deleted &&
        policy?.canRead == true;
    final available =
        readable && state!.financeSnapshotComplete[scopeId] == true;
    final writable =
        available &&
        !state.sessionInvalid &&
        policy!.canWrite &&
        !scope.archived &&
        !scope.blocked &&
        !state.deletionPending;
    final accounts = available
        ? state.dataForScope(scopeId).financeAccounts
        : <SharedFinanceAccount>[];
    // Project-only members may read the sanitized selector projection without
    // gaining the parent's ledger, membership or write permissions.
    final project = current && projectScopeId != null
        ? state!.scopes.where((s) => s.id == projectScopeId).firstOrNull
        : null;
    final choices =
        project != null &&
            project.parentSpaceId == scopeId &&
            project.canRead &&
            !project.revoked &&
            !project.deleted &&
            state!.financePolicyForScope(project.id).canRead
        ? (state.financeAccountChoices[project.id] ??
                  <SharedFinanceAccountChoice>[])
              .where((account) => account.scopeId == scopeId)
              .toList()
        : <SharedFinanceAccountChoice>[];
    final actions = scope == null || state == null
        ? null
        : SharedFinanceActions(context, ref, scope, state);
    return AlertDialog(
      title: Text(l.financeManageParentAccounts),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (scope != null) Text(scope.name),
            const SizedBox(height: 12),
            if (value.isLoading)
              Text(l.financeLoadingSnapshot)
            else if (value.hasError)
              Text(l.organizerLoadError)
            else if (!available && choices.isNotEmpty)
              for (final account in choices)
                ListTile(
                  key: ValueKey('space-finance-choice-${account.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(account.name),
                  subtitle: Text(account.currency),
                )
            else if (current && scope != null && !readable)
              Text(l.financeNoAccess)
            else if (!available)
              Text(l.financeAccountChoicesUnavailable)
            else if (accounts.isEmpty)
              Text(l.financeNoAccounts)
            else
              for (final account in accounts)
                ListTile(
                  key: ValueKey('space-finance-account-${account.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(account.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account.currency),
                      TextButton.icon(
                        key: ValueKey('space-finance-overview-${account.id}'),
                        onPressed: () => showSharedFinanceAccountOverview(
                          context,
                          state,
                          scopeId,
                          account.id,
                        ),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: Text(l.financeAccountOverview),
                      ),
                    ],
                  ),
                  trailing:
                      writable &&
                          canEditSharedRecord(
                            state,
                            scopeId,
                            'financeAccount',
                            account.id,
                            domain: 'finance',
                          )
                      ? IconButton(
                          tooltip: l.financeEditAccount,
                          onPressed: () => actions!.account(account),
                          icon: const Icon(Icons.edit_outlined),
                        )
                      : null,
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
        if (writable)
          FilledButton.icon(
            key: const ValueKey('space-finance-add-account'),
            onPressed: () => actions!.account(),
            icon: const Icon(Icons.add),
            label: Text(l.financeAddAccount),
          ),
      ],
    );
  }
}
