import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organization_finance_projection.dart';
import '../../state/collaboration_provider.dart';
import 'shared_finance_workspace.dart';

/// Uses the existing parent ledger and completeness rules, with a selected
/// account. Sanitized project account choices alone never authorize this route.
Future<void> showSharedFinanceAccountOverview(
  BuildContext context,
  CollaborationState state,
  String scopeId,
  String accountId,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => _SharedFinanceAccountOverview(
      scopeId: scopeId,
      accountId: accountId,
      partition: state.session?.partition,
      deviceId: state.session?.deviceId,
    ),
  ),
);

class _SharedFinanceAccountOverview extends ConsumerWidget {
  const _SharedFinanceAccountOverview({
    required this.scopeId,
    required this.accountId,
    required this.partition,
    required this.deviceId,
  });
  final String scopeId, accountId;
  final String? partition, deviceId;

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
    final readable =
        scope != null &&
        scope.canRead &&
        !scope.revoked &&
        !scope.deleted &&
        state!.financePolicyForScope(scopeId).canRead;
    final accountAvailable =
        readable &&
        state
            .dataForScope(scopeId)
            .financeAccounts
            .any((a) => a.id == accountId);
    return Scaffold(
      appBar: AppBar(title: Text(l.financeAccountOverview)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: !current || !readable
            ? Text(l.financeNoAccess)
            : !accountAvailable
            ? Text(l.financeAccountUnavailable)
            : SharedFinanceWorkspace(
                scope: scope,
                state: state,
                readOnly: true,
                initialAccountId: scopedFinanceDisplayId(scopeId, accountId),
              ),
      ),
    );
  }
}
