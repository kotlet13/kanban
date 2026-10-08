import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../data/organizer_repository.dart' show newLocalId;
import '../../domain/organizer_models.dart';
import '../shared/sharing_errors.dart';
import '../../domain/collaboration_models.dart' show CollaborationException;
import '../shared/sharing_forms.dart';

int parseOpeningBalanceMinor(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(text)) {
    throw const FormatException('Invalid opening balance');
  }
  final negative = text.startsWith('-');
  final unsigned = negative ? text.substring(1) : text;
  if (RegExp(r'^0+(\.0{1,2})?$').hasMatch(unsigned)) return 0;
  final amount = parseMoneyMinor(unsigned);
  return negative ? -amount : amount;
}

Future<LocalFinanceAccount?> showFinanceAccountForm(
  BuildContext context, {
  LocalFinanceAccount? account,
  Widget Function(Widget)? wrap,
}) async {
  final l = context.l10n;
  final id = account?.id ?? newLocalId();
  final created = account?.createdAt ?? DateTime.now().toUtc();
  LocalFinanceAccount? result;
  await showSharingForm(
    context,
    title: account == null ? l.financeAddAccount : l.financeEditAccount,
    description: l.financePlanSymbolicAccount,
    fields: [
      SharingField(
        id: 'finance-account-name',
        label: l.financePlanAccountName,
        initialValue: account?.name ?? '',
      ),
      SharingField(
        id: 'currency',
        label: l.organizerCurrency,
        readOnly: account != null,
        initialValue: account?.currency ?? 'EUR',
        options: {for (final c in supportedCurrencies) c: c},
      ),
      SharingField(
        id: 'opening',
        label: l.financePlanOpeningBalance,
        required: false,
        initialValue: account?.openingBalanceMinor == null
            ? ''
            : formatMoneyMinor(account!.openingBalanceMinor!),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        validator: (v, _) {
          if (v.trim().isEmpty) return null;
          try {
            parseOpeningBalanceMinor(v);
            return null;
          } on FormatException {
            return l.amountMustBeAValidNumber;
          }
        },
      ),
      SharingField(
        id: 'opening-date',
        label: l.financePlanOpeningDate,
        dateTime: true,
        required: false,
        initialValue:
            account != null &&
                account.openingBalanceMinor != null &&
                account.openingBalanceAt == null
            ? ''
            : (account?.openingBalanceAt ??
                      DateTime(
                        DateTime.now().year,
                        DateTime.now().month,
                        DateTime.now().day,
                      ))
                  .toUtc()
                  .toIso8601String(),
      ),
      if (account != null)
        SharingField(
          id: 'archived',
          label: l.financePlanAccountArchived,
          initialValue: account.archived ? 'true' : 'false',
          options: {'false': l.financePlanNo, 'true': l.financePlanYes},
        ),
    ],
    submitLabel: l.save,
    errorMessage: (e) => financePlanningErrorMessage(context, e),
    wrap: wrap,
    onSubmit: (v) async {
      final opening = v['opening']!.trim();
      final date = opening.isEmpty
          ? null
          : DateTime.tryParse(v['opening-date']!);
      if (opening.isNotEmpty &&
          date == null &&
          !(account != null &&
              account.openingBalanceMinor != null &&
              account.openingBalanceAt == null &&
              v['opening-date']!.isEmpty)) {
        throw const FormatException('Opening date required');
      }
      result = LocalFinanceAccount(
        id: id,
        name: v['finance-account-name']!.trim(),
        currency: v['currency']!,
        openingBalanceMinor: opening.isEmpty
            ? null
            : parseOpeningBalanceMinor(opening),
        openingBalanceAt: date,
        archived: v['archived'] == 'true',
        revision: account?.revision ?? 0,
        createdAt: created,
        updatedAt: created,
      );
      result!.validate();
    },
  );
  return result;
}

String financeRuleKindLabel(BuildContext context, FinanceRecurrenceKind kind) =>
    switch (kind) {
      FinanceRecurrenceKind.salary => context.l10n.financePlanSalaryLabel,
      FinanceRecurrenceKind.loanInstallment =>
        context.l10n.financePlanLoanLabel,
      FinanceRecurrenceKind.cardSettlement => context.l10n.financePlanCardLabel,
      FinanceRecurrenceKind.income => context.l10n.organizerIncome,
      FinanceRecurrenceKind.expense => context.l10n.organizerExpense,
    };
Future<FinanceRecurrenceRule?> showFinanceRuleForm(
  BuildContext context, {
  required OrganizerSnapshot snapshot,
  FinanceRecurrenceRule? rule,
  Widget Function(Widget)? wrap,
}) async {
  final l = context.l10n, id = rule?.id ?? newLocalId();
  final created = rule?.createdAt ?? DateTime.now().toUtc();
  FinanceRecurrenceRule? result;
  await showSharingForm(
    context,
    title: rule == null ? l.financePlanAddRule : l.financePlanEditRule,
    description:
        '${l.financePlanMonthEnd}\n${l.financePlanWeekend}\n${l.financePlanReminderOptIn}',
    fields: [
      SharingField(
        id: 'rule-title',
        label: l.organizerTitle,
        initialValue: rule?.title ?? '',
      ),
      SharingField(
        id: 'rule-kind',
        label: l.financePlanRuleType,
        readOnly: rule != null,
        initialValue: rule?.kind.name ?? 'expense',
        options: {
          for (final k in FinanceRecurrenceKind.values)
            k.name: financeRuleKindLabel(context, k),
        },
      ),
      SharingField(
        id: 'rule-amount',
        label: l.financePlanEstimatedAmount,
        initialValue: rule == null
            ? ''
            : formatMoneyMinor(rule.estimatedAmountMinor),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v, _) {
          try {
            parseMoneyMinor(v);
            return null;
          } on FormatException {
            return l.amountMustBeAValidNumber;
          }
        },
      ),
      SharingField(
        id: 'currency',
        label: l.organizerCurrency,
        readOnly: rule != null,
        initialValue: rule?.currency ?? 'EUR',
        options: {for (final c in supportedCurrencies) c: c},
      ),
      SharingField(
        id: 'ledger-account',
        label: l.financeAccount,
        initialValue: rule?.ledgerAccountId ?? '',
        options: {
          '': l.taskCostUnassignedAccount,
          for (final a in snapshot.financeAccounts.where(
            (a) => !a.archived || a.id == rule?.ledgerAccountId,
          ))
            a.id: '${a.name} · ${a.currency}',
        },
      ),
      SharingField(
        id: 'rule-date',
        label: l.financePlanFirstDate,
        dateTime: true,
        initialValue:
            (rule == null
                    ? DateTime.now()
                    : rule.dateForMonth(rule.startYear, rule.startMonth))
                .toUtc()
                .toIso8601String(),
      ),
      SharingField(
        id: 'rule-day',
        label: l.financePlanDay,
        initialValue:
            rule?.monthDay.toString() ?? DateTime.now().day.toString(),
        keyboardType: TextInputType.number,
        validator: (v, _) {
          final day = int.tryParse(v);
          return day == null || day < 1 || day > 31
              ? l.sharingValidationError
              : null;
        },
      ),
      if (rule == null || rule.kind == FinanceRecurrenceKind.loanInstallment)
        SharingField(
          id: 'rule-principal',
          label: l.financePlanLoanPrincipal,
          required: false,
          initialValue: rule?.loanPrincipalMinor == null
              ? ''
              : formatMoneyMinor(rule!.loanPrincipalMinor!),
          validator: (v, all) {
            if (v.trim().isEmpty) return null;
            if (all['rule-kind'] != 'loanInstallment') {
              return l.financePlanPrincipalOnlyLoan;
            }
            try {
              parseMoneyMinor(v);
              return null;
            } on FormatException {
              return l.amountMustBeAValidNumber;
            }
          },
        ),
      SharingField(
        id: 'rule-active',
        label: l.financePlanRuleActive,
        initialValue: rule?.active == false ? 'false' : 'true',
        options: {'true': l.financePlanYes, 'false': l.financePlanNo},
      ),
      SharingField(
        id: 'rule-reminders',
        label: l.financePlanReminders,
        initialValue: rule?.remindersEnabled == true ? 'true' : 'false',
        options: {'false': l.financePlanNo, 'true': l.financePlanYes},
      ),
      SharingField(
        id: 'rule-time',
        label: l.financePlanReminderTime,
        initialValue:
            '${((rule?.reminderMinuteOfDay ?? 540) ~/ 60).toString().padLeft(2, '0')}:${((rule?.reminderMinuteOfDay ?? 540) % 60).toString().padLeft(2, '0')}',
        keyboardType: TextInputType.datetime,
        validator: (v, _) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)
            ? null
            : l.sharingValidationError,
      ),
    ],
    submitLabel: l.save,
    errorMessage: (e) => financePlanningErrorMessage(context, e),
    wrap: wrap,
    onSubmit: (v) async {
      final date = DateTime.parse(v['rule-date']!).toLocal();
      final kind = FinanceRecurrenceKind.values.byName(v['rule-kind']!);
      final time = v['rule-time']!.split(':');
      final accountId = v['ledger-account']!.isEmpty
          ? null
          : v['ledger-account'];
      if (accountId != null &&
          snapshot.financeAccounts
                  .firstWhere((a) => a.id == accountId)
                  .currency !=
              v['currency']) {
        throw const FormatException('Currency differs from account');
      }
      result = FinanceRecurrenceRule(
        id: id,
        title: v['rule-title']!.trim(),
        kind: kind,
        ledgerAccountId: accountId,
        currency: v['currency']!,
        estimatedAmountMinor: parseMoneyMinor(v['rule-amount']!),
        loanPrincipalMinor:
            kind != FinanceRecurrenceKind.loanInstallment ||
                v['rule-principal']!.trim().isEmpty
            ? null
            : parseMoneyMinor(v['rule-principal']!),
        startYear: date.year,
        startMonth: date.month,
        monthDay: int.parse(v['rule-day']!),
        endYear: rule?.endYear,
        endMonth: rule?.endMonth,
        active: v['rule-active'] == 'true',
        remindersEnabled: v['rule-reminders'] == 'true',
        reminderMinuteOfDay: int.parse(time[0]) * 60 + int.parse(time[1]),
        revision: rule?.revision ?? 0,
        createdAt: created,
        updatedAt: rule?.updatedAt ?? created,
      );
      result!.validate();
    },
  );
  return result;
}

Future<void> showFinanceOccurrenceConfirmation(
  BuildContext context, {
  required FinanceEntry entry,
  required Future<void> Function(int amountMinor, DateTime paidAt) onConfirm,
  Widget Function(Widget)? wrap,
  bool Function()? isCurrent,
  DateTime? initialPaidAt,
}) async {
  final l = context.l10n;
  bool confirmed = false;
  await showSharingForm(
    context,
    title: l.financePlanConfirm,
    description: entry.title,
    fields: [
      SharingField(
        id: 'actual-amount',
        label: l.financePlanActualAmount,
        initialValue: formatMoneyMinor(entry.amountMinor),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v, _) {
          try {
            parseMoneyMinor(v);
            return null;
          } on FormatException {
            return l.amountMustBeAValidNumber;
          }
        },
      ),
      SharingField(
        id: 'actual-date',
        label: l.financePlanActualDate,
        dateTime: true,
        initialValue: (initialPaidAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
      ),
    ],
    submitLabel: l.financePlanConfirm,
    errorMessage: (e) => financePlanningErrorMessage(context, e),
    wrap: wrap,
    onSubmit: (v) async {
      await onConfirm(
        parseMoneyMinor(v['actual-amount']!),
        DateTime.parse(v['actual-date']!),
      );
      confirmed = true;
    },
  );
  if (confirmed && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.financePlanConfirmed)));
  }
}

String financePlanningErrorMessage(BuildContext context, Object error) =>
    error is CollaborationException && error.code == 'unsupported_version'
    ? context.l10n.financePlanUpgrade
    : sharingErrorMessage(context, error);

Future<void> showRecordedFinanceOccurrenceEditor(
  BuildContext context, {
  required FinanceEntry entry,
  required Future<void> Function(FinanceEntry) onSave,
  Widget Function(Widget)? wrap,
}) => showSharingForm(
  context,
  title: context.l10n.organizerEditFinance,
  description: context.l10n.financePlanManageRule,
  fields: [
    SharingField(
      id: 'recorded-title',
      label: context.l10n.organizerTitle,
      initialValue: entry.title,
    ),
    SharingField(
      id: 'actual-amount',
      label: context.l10n.financePlanActualAmount,
      initialValue: formatMoneyMinor(entry.amountMinor),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v, _) {
        try {
          parseMoneyMinor(v);
          return null;
        } on FormatException {
          return context.l10n.amountMustBeAValidNumber;
        }
      },
    ),
    SharingField(
      id: 'actual-date',
      label: context.l10n.financePlanActualDate,
      dateTime: true,
      initialValue: (entry.paidAt ?? entry.occurredAt)
          .toUtc()
          .toIso8601String(),
    ),
    SharingField(
      id: 'recorded-notes',
      label: context.l10n.peopleNotes,
      initialValue: entry.notes,
      required: false,
      maxLines: 3,
    ),
  ],
  submitLabel: context.l10n.save,
  errorMessage: (e) => financePlanningErrorMessage(context, e),
  wrap: wrap,
  onSubmit: (v) => onSave(
    entry.copyWith(
      title: v['recorded-title']!.trim(),
      amountMinor: parseMoneyMinor(v['actual-amount']!),
      paidAt: DateTime.parse(v['actual-date']!),
      occurredAt: DateTime.parse(v['actual-date']!),
      notes: v['recorded-notes']!,
    ),
  ),
);
