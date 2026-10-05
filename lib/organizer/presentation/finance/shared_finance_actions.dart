import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../state/collaboration_provider.dart';
import '../inbox/notification_target_view.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_forms.dart';
import 'finance_access_guard.dart';
import 'finance_snapshot_view.dart';

class SharedFinanceActions {
  SharedFinanceActions(this.context, this.ref, this.scope, this.state);
  final BuildContext context;
  final WidgetRef ref;
  final SharedScope scope;
  final CollaborationState state;
  SharedScopeData get data => state.dataForScope(scope.id);
  Map<String, String> get _people => {
    '': context.l10n.financeUnspecifiedPerson,
    for (final member
        in state
            .membersForScope(scope.id)
            .where((m) => m.active && m.accountId.isNotEmpty))
      member.accountId: member.displayName.isEmpty
          ? member.username
          : member.displayName,
  };
  Map<String, String> get _accounts => {
    for (final account in data.financeAccounts)
      account.id: '${account.name} · ${account.currency}',
  };
  String? _nullable(String value) => value.isEmpty ? null : value;
  String? _money(String value, {bool opening = false}) {
    try {
      parseSharedMoneyMinor(value, allowSigned: opening, allowZero: opening);
      return null;
    } catch (_) {
      return context.l10n.organizerInvalidMoney;
    }
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    }
  }

  Future<void> account([SharedFinanceAccount? account]) {
    final l = context.l10n;
    final guard = FinanceAccessGuard(context, ref, scope.id, write: true);
    return showSharingForm(
      context,
      title: account == null ? l.financeAddAccount : l.financeEditAccount,
      description: l.financeSharedAccountsDescription,
      fields: [
        SharingField(
          id: 'name',
          label: l.organizerTitle,
          initialValue: account?.name ?? '',
        ),
        SharingField(
          id: 'currency',
          label: l.organizerCurrency,
          initialValue: account?.currency ?? 'EUR',
          readOnly: account != null,
          options: {
            for (final currency in {
              ...supportedCurrencies,
              if (account != null) account.currency,
            })
              currency: currency,
          },
        ),
        SharingField(
          id: 'opening',
          label:
              account != null && !supportedCurrencies.contains(account.currency)
              ? '${l.financeOpeningBalance} (${l.financeMinorUnits})'
              : l.financeOpeningBalance,
          initialValue: account == null
              ? '0.00'
              : !supportedCurrencies.contains(account.currency)
              ? account.openingBalanceMinor.toString()
              : formatSharedMoneyMinor(
                  BigInt.from(account.openingBalanceMinor),
                ),
          readOnly: account != null,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          validator: (value, _) =>
              account != null ? null : _money(value, opening: true),
        ),
        SharingField(
          id: 'owner',
          label: l.financeHolder,
          initialValue: account?.ownerAccountId ?? '',
          required: false,
          options: {
            ..._people,
            '': l.financeJointAccount,
            if (account?.ownerAccountId != null &&
                !_people.containsKey(account!.ownerAccountId))
              account.ownerAccountId!: l.planningFormerMember,
          },
        ),
      ],
      submitLabel: l.save,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: guard.wrap,
      onSubmit: (values) async {
        final controller = guard.controller;
        if (account == null) {
          await controller.createFinanceAccount(
            scopeId: scope.id,
            name: values['name']!.trim(),
            currency: values['currency']!,
            openingBalanceMinor: parseSharedMoneyMinor(
              values['opening']!,
              allowSigned: true,
              allowZero: true,
            ),
            ownerAccountId: _nullable(values['owner']!),
          );
        } else {
          await controller.updateFinanceAccount(
            scope.id,
            account.copyWith(
              name: values['name']!.trim(),
              ownerAccountId: _nullable(values['owner']!),
            ),
          );
        }
        if (!guard.isCurrent) {
          throw const CollaborationException('finance_forbidden');
        }
      },
      onDelete: account == null
          ? null
          : () => guard.controller.deleteFinanceAccount(scope.id, account.id),
      deleteDescription: l.financeDeleteAccountDescription,
    );
  }

  Future<void> entry([SharedFinanceEntry? entry]) {
    if (entry != null && !supportedCurrencies.contains(entry.currency)) {
      return run(() async {
        throw const CollaborationException('unsupported_currency');
      });
    }
    final l = context.l10n;
    final guard = FinanceAccessGuard(context, ref, scope.id, write: true);
    return showSharingForm(
      context,
      title: entry == null ? l.organizerAddFinance : l.financeEditEntry,
      fields: [
        SharingField(
          id: 'title',
          label: l.organizerTitle,
          initialValue: entry?.title ?? '',
        ),
        SharingField(
          id: 'account',
          label: l.financeAccount,
          initialValue: entry?.accountId ?? data.financeAccounts.first.id,
          options: _accounts,
        ),
        SharingField(
          id: 'kind',
          label: l.type,
          initialValue: entry?.kind.name ?? 'expense',
          options: {'expense': l.organizerExpense, 'income': l.organizerIncome},
        ),
        SharingField(
          id: 'amount',
          label: l.financeAccountCurrencyAmount,
          initialValue: entry == null
              ? ''
              : formatSharedMoneyMinor(BigInt.from(entry.amountMinor)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value, _) => _money(value),
        ),
        SharingField(
          id: 'status',
          label: l.financeStatus,
          initialValue: entry?.status.name ?? 'posted',
          options: {'posted': l.financePosted, 'planned': l.financePlanned},
        ),
        SharingField(
          id: 'occurred',
          label: l.financeDate,
          initialValue: (entry?.occurredAt ?? DateTime.now())
              .toUtc()
              .toIso8601String(),
          dateTime: true,
        ),
        SharingField(
          id: 'payer',
          label: l.financePayer,
          initialValue: entry?.payerAccountId ?? '',
          required: false,
          options: {
            ..._people,
            if (entry?.payerAccountId != null &&
                !_people.containsKey(entry!.payerAccountId))
              entry.payerAccountId!: l.planningFormerMember,
          },
        ),
        SharingField(
          id: 'recipient',
          label: l.financeRecipient,
          initialValue: entry?.recipientAccountId ?? '',
          required: false,
          options: {
            ..._people,
            if (entry?.recipientAccountId != null &&
                !_people.containsKey(entry!.recipientAccountId))
              entry.recipientAccountId!: l.planningFormerMember,
          },
        ),
        SharingField(
          id: 'category',
          label: l.financeCategory,
          initialValue: entry?.category ?? '',
          required: false,
        ),
        SharingField(
          id: 'notes',
          label: l.organizerNotes,
          initialValue: entry?.notes ?? '',
          required: false,
          maxLines: 3,
        ),
      ],
      submitLabel: l.save,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: guard.wrap,
      onSubmit: (values) async {
        final selected = data.financeAccounts.firstWhere(
          (a) => a.id == values['account'],
        );
        if (!supportedCurrencies.contains(selected.currency)) {
          throw const CollaborationException('unsupported_currency');
        }
        final controller = guard.controller;
        final amount = parseSharedMoneyMinor(values['amount']!),
            kind = FinanceEntryKind.values.byName(values['kind']!),
            status = SharedFinanceStatus.values.byName(values['status']!),
            occurred = DateTime.parse(values['occurred']!),
            payer = _nullable(values['payer']!),
            recipient = _nullable(values['recipient']!);
        if (entry == null) {
          await controller.createFinanceEntry(
            scopeId: scope.id,
            accountId: selected.id,
            kind: kind,
            status: status,
            amountMinor: amount,
            currency: selected.currency,
            title: values['title']!.trim(),
            notes: values['notes']!.trim(),
            category: values['category']!.trim(),
            payerAccountId: payer,
            recipientAccountId: recipient,
            occurredAt: occurred,
          );
        } else {
          await controller.updateFinanceEntry(
            scope.id,
            entry.copyWith(
              accountId: selected.id,
              kind: kind,
              status: status,
              amountMinor: amount,
              currency: selected.currency,
              title: values['title']!.trim(),
              notes: values['notes']!.trim(),
              category: values['category']!.trim(),
              payerAccountId: payer,
              recipientAccountId: recipient,
              occurredAt: occurred,
            ),
          );
        }
        if (!guard.isCurrent) {
          throw const CollaborationException('finance_forbidden');
        }
      },
      onDelete: entry == null
          ? null
          : () => guard.controller.deleteFinanceEntry(scope.id, entry.id),
    );
  }

  Future<void> transfer([SharedFinanceTransfer? transfer]) {
    if (transfer != null && !supportedCurrencies.contains(transfer.currency)) {
      return run(() async {
        throw const CollaborationException('unsupported_currency');
      });
    }
    final l = context.l10n,
        guard = FinanceAccessGuard(context, ref, scope.id, write: true);
    return showSharingForm(
      context,
      title: transfer == null ? l.financeAddTransfer : l.financeEditTransfer,
      description: l.financeTransferDescription,
      fields: [
        SharingField(
          id: 'title',
          label: l.organizerTitle,
          initialValue: transfer?.title ?? '',
        ),
        SharingField(
          id: 'from',
          label: l.financeFromAccount,
          initialValue:
              transfer?.fromAccountId ?? data.financeAccounts.first.id,
          options: _accounts,
        ),
        SharingField(
          id: 'to',
          label: l.financeToAccount,
          initialValue: transfer?.toAccountId ?? data.financeAccounts.last.id,
          options: _accounts,
          validator: (value, values) {
            final from = data.financeAccounts.firstWhere(
              (a) => a.id == values['from'],
            );
            final to = data.financeAccounts.firstWhere((a) => a.id == value);
            return from.id == to.id || from.currency != to.currency
                ? l.financeInvalidTransfer
                : null;
          },
        ),
        SharingField(
          id: 'amount',
          label: l.financeAccountCurrencyAmount,
          initialValue: transfer == null
              ? ''
              : formatSharedMoneyMinor(BigInt.from(transfer.amountMinor)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value, _) => _money(value),
        ),
        SharingField(
          id: 'status',
          label: l.financeStatus,
          initialValue: transfer?.status.name ?? 'posted',
          options: {'posted': l.financePosted, 'planned': l.financePlanned},
        ),
        SharingField(
          id: 'occurred',
          label: l.financeDate,
          initialValue: (transfer?.occurredAt ?? DateTime.now())
              .toUtc()
              .toIso8601String(),
          dateTime: true,
        ),
        SharingField(
          id: 'notes',
          label: l.organizerNotes,
          initialValue: transfer?.notes ?? '',
          required: false,
          maxLines: 3,
        ),
      ],
      submitLabel: l.save,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: guard.wrap,
      onSubmit: (values) async {
        final from = data.financeAccounts.firstWhere(
          (a) => a.id == values['from'],
        );
        if (!supportedCurrencies.contains(from.currency)) {
          throw const CollaborationException('unsupported_currency');
        }
        final controller = guard.controller,
            amount = parseSharedMoneyMinor(values['amount']!),
            status = SharedFinanceStatus.values.byName(values['status']!),
            occurred = DateTime.parse(values['occurred']!);
        if (transfer == null) {
          await controller.createFinanceTransfer(
            scopeId: scope.id,
            fromAccountId: from.id,
            toAccountId: values['to']!,
            amountMinor: amount,
            currency: from.currency,
            status: status,
            title: values['title']!.trim(),
            notes: values['notes']!.trim(),
            occurredAt: occurred,
          );
        } else {
          await controller.updateFinanceTransfer(
            scope.id,
            transfer.copyWith(
              fromAccountId: from.id,
              toAccountId: values['to']!,
              amountMinor: amount,
              currency: from.currency,
              status: status,
              title: values['title']!.trim(),
              notes: values['notes']!.trim(),
              occurredAt: occurred,
            ),
          );
        }
        if (!guard.isCurrent) {
          throw const CollaborationException('finance_forbidden');
        }
      },
      onDelete: transfer == null
          ? null
          : () => guard.controller.deleteFinanceTransfer(scope.id, transfer.id),
    );
  }

  Future<void> audit(String recordId) => run(() async {
    final guard = FinanceAccessGuard(context, ref, scope.id);
    final future = guard.controller.financeAudit(
      scopeId: scope.id,
      recordId: recordId,
    );
    await showDialog<void>(
      context: context,
      builder: (context) => guard.wrap(
        AlertDialog(
          title: Text(context.l10n.financeAudit),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: FutureBuilder<List<SharedFinanceAuditEntry>>(
                future: future,
                builder: (context, result) {
                  if (!guard.isCurrent) return const SizedBox.shrink();
                  if (result.hasError) {
                    return Text(sharingErrorMessage(context, result.error!));
                  }
                  if (!result.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (result.data!.isEmpty)
                        Text(context.l10n.financeNoAudit),
                      for (final change in result.data!)
                        ExpansionTile(
                          title: Text(
                            '${organizerDateTime(context, change.changedAt)} · ${state.membersForScope(scope.id).where((m) => m.accountId == change.actorAccountId).firstOrNull?.displayName ?? context.l10n.planningFormerMember}',
                          ),
                          subtitle: Text(
                            '${context.l10n.financeRevision}: ${change.revision}',
                          ),
                          children: [
                            Text(context.l10n.financeBefore),
                            FinanceSnapshotView(
                              scopeId: scope.id,
                              value: change.before,
                            ),
                            Text(context.l10n.financeAfter),
                            FinanceSnapshotView(
                              scopeId: scope.id,
                              value: change.after,
                            ),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.close),
            ),
          ],
        ),
      ),
    );
  });
}
