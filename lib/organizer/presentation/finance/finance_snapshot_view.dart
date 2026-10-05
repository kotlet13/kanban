import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../inbox/notification_target_view.dart';
import 'finance_money.dart';

/// Human-readable immutable audit/conflict version. Audit records wrap payload;
/// conflicts already contain payload. Unknown identity stays a former member.
class FinanceSnapshotView extends ConsumerWidget {
  const FinanceSnapshotView({
    super.key,
    required this.scopeId,
    required this.value,
  });
  final String scopeId;
  final Map<String, dynamic>? value;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n,
        state = ref.watch(collaborationProvider).valueOrNull;
    if (value == null || value!['deleted'] == true) {
      return Text(l.sharingDeletedVersion);
    }
    final nested = value!['payload'];
    final payload = nested is Map ? Map<String, dynamic>.from(nested) : value!;
    final data = state?.dataForScope(scopeId);
    String person(Object? id) => id == null
        ? l.financeUnspecifiedPerson
        : state
                  ?.membersForScope(scopeId)
                  .where((m) => m.accountId == id)
                  .firstOrNull
                  ?.displayName ??
              l.planningFormerMember;
    String account(Object? id) =>
        data?.financeAccounts.where((a) => a.id == id).firstOrNull?.name ??
        l.financeUnavailableAccount;
    final amount = payload['amountMinor'] ?? payload['openingBalanceMinor'];
    final date = DateTime.tryParse('${payload['occurredAt'] ?? ''}');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (payload['title'] is String || payload['name'] is String)
            Text(
              '${payload['title'] ?? payload['name']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          if (payload['accountId'] != null)
            Text('${l.financeAccount}: ${account(payload['accountId'])}'),
          if (payload['fromAccountId'] != null)
            Text(
              '${l.financeFromAccount}: ${account(payload['fromAccountId'])}',
            ),
          if (payload['toAccountId'] != null)
            Text('${l.financeToAccount}: ${account(payload['toAccountId'])}'),
          if (payload['kind'] == 'income' || payload['kind'] == 'expense')
            Text(
              payload['kind'] == 'income'
                  ? l.organizerIncome
                  : l.organizerExpense,
            ),
          if (amount is int && payload['currency'] is String)
            Text(
              sharedMoneyLabel(
                context,
                BigInt.from(amount),
                payload['currency'] as String,
              ),
            ),
          if (payload['status'] == 'planned' || payload['status'] == 'posted')
            Text(
              payload['status'] == 'planned'
                  ? l.financePlanned
                  : l.financePosted,
            ),
          if (payload.containsKey('ownerAccountId'))
            Text(
              '${l.financeHolder}: ${payload['ownerAccountId'] == null ? l.financeJointAccount : person(payload['ownerAccountId'])}',
            ),
          if (payload.containsKey('payerAccountId'))
            Text('${l.financePayer}: ${person(payload['payerAccountId'])}'),
          if (payload.containsKey('recipientAccountId'))
            Text(
              '${l.financeRecipient}: ${person(payload['recipientAccountId'])}',
            ),
          if (date != null)
            Text('${l.financeDate}: ${organizerDateTime(context, date)}'),
          if (payload['category'] is String &&
              (payload['category'] as String).isNotEmpty)
            Text('${l.financeCategory}: ${payload['category']}'),
          if (payload['notes'] is String &&
              (payload['notes'] as String).isNotEmpty)
            Text('${payload['notes']}'),
        ],
      ),
    );
  }
}
