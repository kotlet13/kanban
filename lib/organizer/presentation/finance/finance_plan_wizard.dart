import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../data/organizer_repository.dart' show newLocalId;
import '../../domain/organizer_models.dart';
import '../organizer_widgets.dart';
import 'finance_plan_forms.dart';

typedef FinancePlanSubmit =
    Future<void> Function(
      List<LocalFinanceAccount> accounts,
      List<FinanceRecurrenceRule> rules,
    );

Future<void> showFinancePlanWizard(
  BuildContext context, {
  required OrganizerSnapshot snapshot,
  required FinancePlanSubmit onSave,
  required Widget Function(Widget) wrap,
  required String scopeDescription,
  bool requireAccount = false,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => wrap(
    FinancePlanWizard(
      snapshot: snapshot,
      onSave: onSave,
      scopeDescription: scopeDescription,
      requireAccount: requireAccount,
    ),
  ),
);

class FinancePlanWizard extends StatefulWidget {
  const FinancePlanWizard({
    super.key,
    required this.snapshot,
    required this.onSave,
    required this.scopeDescription,
    this.requireAccount = false,
  });
  final OrganizerSnapshot snapshot;
  final FinancePlanSubmit onSave;
  final String scopeDescription;
  final bool requireAccount;
  @override
  State<FinancePlanWizard> createState() => _FinancePlanWizardState();
}

class _FinancePlanWizardState extends State<FinancePlanWizard> {
  final _form = GlobalKey<FormState>();
  final _enabled = [false, false, false];
  final _fixed = <_RuleDraft>[];
  final _income = <_RuleDraft>[], _expenses = <_RuleDraft>[];
  final _accounts = <LocalFinanceAccount>[];
  String? _accountId, _error;
  int _step = 0;
  bool _busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fixed.isNotEmpty) return;
    final l = context.l10n;
    _fixed.addAll([
      _RuleDraft(FinanceRecurrenceKind.salary, l.financePlanSalaryLabel),
      _RuleDraft(FinanceRecurrenceKind.loanInstallment, l.financePlanLoanLabel),
      _RuleDraft(FinanceRecurrenceKind.cardSettlement, l.financePlanCardLabel),
    ]);
  }

  List<_RuleDraft> get _chosen => [
    for (var i = 0; i < 3; i++)
      if (_enabled[i]) _fixed[i],
    ..._income,
    ..._expenses,
  ];
  List<LocalFinanceAccount> get _availableAccounts => [
    ...widget.snapshot.financeAccounts,
    ..._accounts,
  ].where((a) => !a.archived).toList();
  @override
  void dispose() {
    for (final d in [..._fixed, ..._income, ..._expenses]) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rules = _chosen.map((d) => d.rule(accountId: _accountId)).toList();
      await widget.onSave(_accounts, rules);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = financePlanningErrorMessage(context, error);
        });
      }
    }
  }

  Widget _draftFields(_RuleDraft draft, {bool remove = false}) {
    final l = context.l10n;
    final selected = _availableAccounts
        .where((a) => a.id == _accountId)
        .firstOrNull;
    if (selected != null) draft.currency = selected.currency;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (remove)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: l.delete,
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _income.remove(draft);
                          _expenses.remove(draft);
                          draft.dispose();
                        }),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            TextFormField(
              key: ValueKey('plan-title-${draft.id}'),
              controller: draft.title,
              decoration: InputDecoration(labelText: l.organizerTitle),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l.sharingRequired : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: ValueKey('plan-amount-${draft.id}'),
              controller: draft.amount,
              decoration: InputDecoration(
                labelText: draft.kind == FinanceRecurrenceKind.loanInstallment
                    ? l.financePlanInstallment
                    : draft.kind == FinanceRecurrenceKind.cardSettlement
                    ? l.financePlanCardEstimate
                    : l.financePlanEstimatedAmount,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                try {
                  parseMoneyMinor(v ?? '');
                  return null;
                } on FormatException {
                  return l.amountMustBeAValidNumber;
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: draft.currency,
              decoration: InputDecoration(labelText: l.organizerCurrency),
              items: [
                for (final currency in supportedCurrencies)
                  DropdownMenuItem(value: currency, child: Text(currency)),
              ],
              onChanged: selected != null
                  ? null
                  : (v) => setState(() => draft.currency = v!),
            ),
            const SizedBox(height: 16),
            FormField<DateTime>(
              key: ValueKey('plan-date-${draft.id}'),
              initialValue: draft.date,
              validator: (_) =>
                  draft.date == null ? l.financePlanDateNeeded : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: draft.date ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200, 12, 31),
                      );
                      if (date != null && mounted) {
                        setState(() => draft.date = date);
                      }
                      field.didChange(date ?? draft.date);
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      draft.date == null
                          ? l.financePlanFirstDate
                          : '${l.financePlanFirstDate}: ${organizerDate(context, draft.date!)}',
                    ),
                  ),
                  if (field.hasError)
                    Text(
                      field.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: draft.remindersEnabled,
              title: Text(l.financePlanReminders),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => draft.remindersEnabled = v),
            ),
            Text(l.financePlanReminderOptIn),
            if (draft.kind == FinanceRecurrenceKind.loanInstallment) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: draft.principal,
                decoration: InputDecoration(
                  labelText: l.financePlanLoanPrincipal,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  try {
                    parseMoneyMinor(v);
                    return null;
                  } on FormatException {
                    return l.amountMustBeAValidNumber;
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final titles = [
      l.financePlanSalary,
      l.financePlanLoan,
      l.financePlanCard,
      l.financePlanOtherIncome,
      l.financePlanOtherExpenses,
      l.financePlanReview,
    ];
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 40,
          vertical: 20,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.financePlanWizard,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                titles[_step],
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(widget.scopeDescription),
                            ],
                          ),
                        ),

                        if (_step == 0) ...[
                          DropdownButtonFormField<String>(
                            initialValue: _accountId,
                            validator: (v) => widget.requireAccount && v == null
                                ? l.sharingRequired
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l.financeAccount,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: null,
                                child: Text(l.taskCostUnassignedAccount),
                              ),
                              for (final a in _availableAccounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${a.name} · ${a.currency}'),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (id) => setState(() => _accountId = id),
                          ),
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final account =
                                        await showFinanceAccountForm(context);
                                    if (account != null && mounted) {
                                      setState(() {
                                        _accounts.add(account);
                                        _accountId = account.id;
                                      });
                                    }
                                  },
                            icon: const Icon(Icons.add),
                            label: Text(l.financeAddAccount),
                          ),
                        ],
                        if (_step < 3) ...[
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _enabled[_step],
                            title: Text(titles[_step]),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _enabled[_step] = v),
                          ),
                          if (_enabled[_step])
                            _draftFields(_fixed[_step])
                          else if (_step == 0)
                            Text(l.financePlanNoSalary),
                        ],
                        if (_step == 3 || _step == 4) ...[
                          if ((_step == 3 ? _income : _expenses).isEmpty)
                            Text(l.financePlanNoItems),
                          for (final d in _step == 3 ? _income : _expenses)
                            _draftFields(d, remove: true),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    (_step == 3 ? _income : _expenses).add(
                                      _RuleDraft(
                                        _step == 3
                                            ? FinanceRecurrenceKind.income
                                            : FinanceRecurrenceKind.expense,
                                        '',
                                      ),
                                    );
                                  }),
                            icon: const Icon(Icons.add),
                            label: Text(
                              _step == 3
                                  ? l.financePlanAddIncome
                                  : l.financePlanAddExpense,
                            ),
                          ),
                        ],
                        if (_step == 5) ...[
                          Text(l.financePlanDescription),
                          const SizedBox(height: 12),
                          for (final d in _chosen)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(d.title.text),
                              subtitle: Text(
                                '${organizerDate(context, d.date!)} · ${d.date!.day} · ${formatMoneyMinor(parseMoneyMinor(d.amount.text))} ${d.currency}',
                              ),
                            ),
                          if (_chosen.isEmpty) Text(l.financePlanNoItems),
                          Text(l.financePlanMonthEnd),
                          const SizedBox(height: 8),
                          Text(l.financePlanWeekend),
                          const SizedBox(height: 8),
                          Text(l.financePlanReminderOptIn),
                        ],
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: Text(l.cancel),
                    ),
                    if (_step > 0)
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _step--),
                        child: Text(l.financePlanBack),
                      ),
                    FilledButton(
                      key: const ValueKey('finance-plan-next'),
                      onPressed: _busy
                          ? null
                          : () {
                              if (!_form.currentState!.validate()) return;
                              if (_step == 5) {
                                _save();
                              } else {
                                setState(() => _step++);
                              }
                            },
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _step == 5
                                  ? l.financePlanSave
                                  : l.financePlanNext,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleDraft {
  _RuleDraft(this.kind, String titleText)
    : title = TextEditingController(text: titleText);
  final String id = newLocalId();
  final DateTime createdAt = DateTime.now().toUtc();
  final FinanceRecurrenceKind kind;
  final TextEditingController title,
      amount = TextEditingController(),
      principal = TextEditingController();
  DateTime? date;
  String currency = 'EUR';
  bool remindersEnabled = false;
  FinanceRecurrenceRule rule({String? accountId}) => FinanceRecurrenceRule(
    id: id,
    title: title.text.trim(),
    kind: kind,
    ledgerAccountId: accountId,
    currency: currency,
    estimatedAmountMinor: parseMoneyMinor(amount.text),
    loanPrincipalMinor: principal.text.trim().isEmpty
        ? null
        : parseMoneyMinor(principal.text),
    remindersEnabled: remindersEnabled,
    startYear: date!.year,
    startMonth: date!.month,
    monthDay: date!.day,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
  void dispose() {
    title.dispose();
    amount.dispose();
    principal.dispose();
  }
}
