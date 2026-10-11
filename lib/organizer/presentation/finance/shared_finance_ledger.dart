import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../domain/shared_finance_models.dart';
import '../../domain/linked_payment_models.dart';
import '../organizer_widgets.dart';
import '../inbox/remote_reminder_editor.dart';
import '../planning/task_plan_fields.dart';
import 'finance_money.dart';
import 'finance_source_link.dart';

class SharedFinanceLedger extends StatefulWidget {
  const SharedFinanceLedger({
    super.key,
    required this.scopeName,
    this.scopeId,
    this.partition,
    required this.accounts,
    required this.entries,
    required this.transfers,
    required this.people,
    required this.canWrite,
    required this.onAccount,
    required this.onEntry,
    required this.onTransfer,
    required this.onAudit,
    this.payments,
    this.cashAvailable = true,
    this.onPersonalPayment,
    this.showHeading = true,
  });
  final String scopeName;
  final String? scopeId, partition;
  final List<SharedFinanceAccount> accounts;
  final List<SharedFinanceEntry> entries;
  final List<SharedFinanceTransfer> transfers;
  final List<OrganizerPersonOption> people;
  final bool canWrite;
  final bool cashAvailable;
  final bool showHeading;
  final PaymentSnapshot? payments;
  final ValueChanged<SharedFinanceEntry>? onPersonalPayment;
  final ValueChanged<SharedFinanceAccount?> onAccount;
  final ValueChanged<SharedFinanceEntry?> onEntry;
  final ValueChanged<SharedFinanceTransfer?> onTransfer;
  final ValueChanged<String> onAudit;
  @override
  State<SharedFinanceLedger> createState() => _SharedFinanceLedgerState();
}

class _SharedFinanceLedgerState extends State<SharedFinanceLedger> {
  String _accountId = '';
  String _personId = '';
  String _authorId = '';
  String _status = '';
  @override
  void didUpdateWidget(covariant SharedFinanceLedger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_accountId.isNotEmpty &&
        !widget.accounts.any((a) => a.id == _accountId)) {
      _accountId = '';
    }
  }

  String _person(String? id) => id == null
      ? context.l10n.financeUnspecifiedPerson
      : widget.people.where((p) => p.id == id).firstOrNull?.label ??
            context.l10n.planningFormerMember;
  Map<String, String> get _historicalPeople => {
    for (final p in widget.people) p.id: p.label,
    for (final id in {
      ...widget.accounts.map((a) => a.ownerAccountId),
      ...widget.accounts.map((a) => a.createdByAccountId),
      ...widget.entries.map((e) => e.payerAccountId),
      ...widget.entries.map((e) => e.recipientAccountId),
      ...widget.entries.map((e) => e.createdByAccountId),
      ...widget.transfers.map((t) => t.createdByAccountId),
    }.whereType<String>())
      if (!widget.people.any((p) => p.id == id))
        id: context.l10n.planningFormerMember,
  };
  String _account(String id) =>
      widget.accounts.where((a) => a.id == id).firstOrNull?.name ??
      context.l10n.financeUnavailableAccount;
  String _kind(SharedFinanceEntry entry) =>
      entry.kind == FinanceEntryKind.income
      ? context.l10n.organizerIncome
      : context.l10n.organizerExpense;
  String _statusLabel(SharedFinanceStatus status) =>
      status == SharedFinanceStatus.posted
      ? context.l10n.financePosted
      : context.l10n.financePlanned;

  Widget _filter(
    String id,
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) => SizedBox(
    width: MediaQuery.sizeOf(context).width < 500 ? double.infinity : 240,
    child: DropdownButtonFormField<String>(
      key: ValueKey('finance-filter-$id-$selected'),
      initialValue: options.containsKey(selected) ? selected : '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in options.entries)
          DropdownMenuItem(
            value: option.key,
            child: Text(option.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value != null) setState(() => onChanged(value));
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final totals = summarizeSharedFinance(
      accounts: widget.accounts,
      entries: widget.entries,
      transfers: widget.transfers,
      payments: widget.payments,
    );
    final entries = widget.entries.where(
      (entry) =>
          (_accountId.isEmpty || entry.accountId == _accountId) &&
          (_personId.isEmpty ||
              entry.payerAccountId == _personId ||
              entry.recipientAccountId == _personId) &&
          (_authorId.isEmpty || entry.createdByAccountId == _authorId) &&
          (_status.isEmpty || entry.status.name == _status),
    );
    final transfers = widget.transfers.where(
      (transfer) =>
          (_accountId.isEmpty ||
              transfer.fromAccountId == _accountId ||
              transfer.toAccountId == _accountId) &&
          (_personId.isEmpty ||
              widget.accounts.any(
                (a) =>
                    (a.id == transfer.fromAccountId ||
                        a.id == transfer.toAccountId) &&
                    a.ownerAccountId == _personId,
              )) &&
          (_authorId.isEmpty || transfer.createdByAccountId == _authorId) &&
          (_status.isEmpty || transfer.status.name == _status),
    );
    final rows = <Object>[...entries, ...transfers]
      ..sort((a, b) => _date(b).compareTo(_date(a)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading)
          OrganizerHeading(
            title: l.organizerFinances,
            subtitle: widget.scopeName,
          ),
        Text(l.financeSharedAccountsDescription),
        const SizedBox(height: 16),
        if (widget.canWrite)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: widget.accounts.isEmpty
                    ? null
                    : () => widget.onEntry(null),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.organizerAddFinance),
              ),
              OutlinedButton.icon(
                onPressed: widget.accounts.length < 2
                    ? null
                    : () => widget.onTransfer(null),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text(l.financeAddTransfer),
              ),
              TextButton.icon(
                onPressed: () => widget.onAccount(null),
                icon: const Icon(Icons.account_balance_outlined, size: 18),
                label: Text(l.financeAddAccount),
              ),
            ],
          )
        else
          Text(l.sharingReadOnly),
        if (widget.accounts.isEmpty)
          OrganizerEmpty(
            icon: Icons.account_balance_outlined,
            title: l.financeNoAccounts,
            action: widget.canWrite ? l.financeAddAccount : null,
            onAction: widget.canWrite ? () => widget.onAccount(null) : null,
          ),
        if (totals.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            l.financeScopeTotals,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            l.financeTransfersExcluded,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final total in totals.values)
                SizedBox(
                  width: 280,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            total.currency,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (widget.cashAvailable)
                            Text(
                              '${widget.accounts.where((a) => a.currency == total.currency).every((a) => a.openingBalanceMinor != null) ? l.financeTotalBalance : l.financePlanRecordedChange}: ${sharedMoneyLabel(context, widget.accounts.where((a) => a.currency == total.currency).every((a) => a.openingBalanceMinor != null) ? total.balanceMinor : total.incomeMinor - total.expenseMinor, total.currency)}',
                            ),
                          Text(
                            '${l.organizerIncome}: ${sharedMoneyLabel(context, total.incomeMinor, total.currency)}',
                          ),
                          Text(
                            '${l.organizerExpense}: ${sharedMoneyLabel(context, total.expenseMinor, total.currency)}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (widget.accounts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            l.financeAccounts,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final account in widget.accounts)
            Card(
              child: ListTile(
                onTap: widget.canWrite ? () => widget.onAccount(account) : null,
                title: Text(account.name),
                subtitle: Text(
                  widget.cashAvailable
                      ? '${account.ownerAccountId == null ? l.financeJointAccount : _person(account.ownerAccountId)} · ${account.openingBalanceMinor == null ? l.financePlanRecordedChange : ''} ${sharedMoneyLabel(context, totals[account.currency]?.accountBalances[account.id] ?? BigInt.from(account.openingBalanceMinor ?? 0), account.currency)}'
                      : l.paymentIncompleteBalance,
                ),
                trailing: IconButton(
                  tooltip: l.financeAudit,
                  onPressed: () => widget.onAudit(account.id),
                  icon: const Icon(Icons.history, size: 20),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _filter('account', l.financeAccount, _accountId, {
                '': l.financeAllAccounts,
                for (final a in widget.accounts) a.id: a.name,
              }, (id) => _accountId = id),
              _filter('person', l.financePayerRecipient, _personId, {
                '': l.planningAllPeople,
                ..._historicalPeople,
              }, (id) => _personId = id),
              _filter('author', l.financeEnteredBy, _authorId, {
                '': l.planningAllPeople,
                ..._historicalPeople,
              }, (id) => _authorId = id),
              _filter('status', l.financeStatus, _status, {
                '': l.financeAllStatuses,
                'posted': l.financePosted,
                'planned': l.financePlanned,
              }, (id) => _status = id),
            ],
          ),
          const SizedBox(height: 24),
          if (rows.isEmpty) Text(l.financeNoMatchingEntries),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 850
                ? _table(rows)
                : Column(children: [for (final row in rows) _card(row)]),
          ),
        ],
      ],
    );
  }

  DateTime _date(Object row) => switch (row) {
    SharedFinanceEntry e => e.occurredAt,
    SharedFinanceTransfer t => t.occurredAt,
    _ => throw StateError('Unknown financial row'),
  };
  String _title(Object row) => switch (row) {
    SharedFinanceEntry e => e.title,
    SharedFinanceTransfer t => t.title,
    _ => '',
  };
  String _amount(Object row) => switch (row) {
    SharedFinanceEntry e => sharedMoneyLabel(
      context,
      BigInt.from(e.amountMinor),
      e.currency,
    ),
    SharedFinanceTransfer t => sharedMoneyLabel(
      context,
      BigInt.from(t.amountMinor),
      t.currency,
    ),
    _ => '',
  };
  String _accountText(Object row) => switch (row) {
    SharedFinanceEntry e => _account(e.accountId),
    SharedFinanceTransfer t =>
      '${_account(t.fromAccountId)} → ${_account(t.toAccountId)}',
    _ => '',
  };
  String _personText(Object row) => switch (row) {
    SharedFinanceEntry e =>
      '${context.l10n.financePayer}: ${_person(e.payerAccountId)} · ${context.l10n.financeRecipient}: ${_person(e.recipientAccountId)}',
    SharedFinanceTransfer _ => context.l10n.financeInternalTransfer,
    _ => '',
  };
  String _author(Object row) => switch (row) {
    SharedFinanceEntry e => _person(e.createdByAccountId),
    SharedFinanceTransfer t => _person(t.createdByAccountId),
    _ => '',
  };
  String _id(Object row) => switch (row) {
    SharedFinanceEntry e => e.id,
    SharedFinanceTransfer t => t.id,
    _ => '',
  };
  String _typeStatus(Object row) => switch (row) {
    SharedFinanceEntry e => '${_kind(e)} · ${_statusLabel(e.status)}',
    SharedFinanceTransfer t =>
      '${context.l10n.financeTransfer} · ${_statusLabel(t.status)}',
    _ => '',
  };
  void _edit(Object row) {
    switch (row) {
      case SharedFinanceEntry e:
        widget.onEntry(e);
      case SharedFinanceTransfer t:
        widget.onTransfer(t);
    }
  }

  Widget _card(Object row) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _title(row),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (row is SharedFinanceEntry &&
                  row.status == SharedFinanceStatus.planned &&
                  widget.scopeId != null)
                RemoteReminderButton(
                  scopeId: widget.scopeId!,
                  targetType: 'financeEntry',
                  targetId: row.id,
                ),
              IconButton(
                tooltip: context.l10n.financeAudit,
                onPressed: () => widget.onAudit(_id(row)),
                icon: const Icon(Icons.history, size: 20),
              ),
            ],
          ),
          if (row case SharedFinanceEntry e)
            if (widget.scopeId != null)
              FinanceSourceLink(
                entryId: e.id,
                scopeId: widget.scopeId,
                partition: widget.partition,
              ),
          Text(_amount(row), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('${organizerDate(context, _date(row))} · ${_typeStatus(row)}'),
          Text(_accountText(row)),
          Text(_personText(row)),
          Text('${context.l10n.financeEnteredBy}: ${_author(row)}'),
          if (row case SharedFinanceEntry e)
            if (e.category.isNotEmpty)
              Text('${context.l10n.financeCategory}: ${e.category}'),
          if (row is SharedFinanceEntry &&
              row.kind == FinanceEntryKind.expense &&
              row.status == SharedFinanceStatus.posted &&
              widget.onPersonalPayment != null &&
              widget.payments?.fresh == true &&
              widget.payments?.events.any((e) => e.sourceEntryId == row.id) !=
                  true &&
              (widget.payments?.pendingCount ?? 0) == 0)
            TextButton.icon(
              key: ValueKey('personal-payment-${row.id}'),
              onPressed: () => widget.onPersonalPayment!(row),
              icon: const Icon(Icons.credit_card_outlined),
              label: Text(context.l10n.paymentPaidPersonally),
            ),
          if (widget.canWrite)
            TextButton(
              onPressed: () => _edit(row),
              child: Text(context.l10n.edit),
            ),
        ],
      ),
    ),
  );

  Widget _table(List<Object> rows) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      dataRowMinHeight: 72,
      dataRowMaxHeight: 140,
      columns: [
        for (final label in [
          context.l10n.financeDate,
          context.l10n.organizerTitle,
          context.l10n.type,
          context.l10n.amount,
          context.l10n.financeAccount,
          context.l10n.financePayerRecipient,
          context.l10n.financeEnteredBy,
          context.l10n.financeAudit,
          context.l10n.organizerTasks,
          context.l10n.remoteReminderTitle,
        ])
          DataColumn(label: Text(label)),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(organizerDate(context, _date(row)))),
              DataCell(
                SizedBox(
                  width: 170,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(row),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (row is SharedFinanceEntry &&
                          row.kind == FinanceEntryKind.expense &&
                          row.status == SharedFinanceStatus.posted &&
                          widget.onPersonalPayment != null &&
                          widget.payments?.fresh == true &&
                          widget.payments?.events.any(
                                (e) => e.sourceEntryId == row.id,
                              ) !=
                              true &&
                          (widget.payments?.pendingCount ?? 0) == 0)
                        TextButton(
                          key: ValueKey('personal-payment-${row.id}'),
                          onPressed: () => widget.onPersonalPayment!(row),
                          child: Text(
                            context.l10n.paymentPaidPersonally,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                onTap: widget.canWrite ? () => _edit(row) : null,
              ),
              DataCell(Text(_typeStatus(row))),
              DataCell(Text(_amount(row))),
              DataCell(SizedBox(width: 160, child: Text(_accountText(row)))),
              DataCell(SizedBox(width: 220, child: Text(_personText(row)))),
              DataCell(Text(_author(row))),
              DataCell(
                IconButton(
                  tooltip: context.l10n.financeAudit,
                  onPressed: () => widget.onAudit(_id(row)),
                  icon: const Icon(Icons.history, size: 18),
                ),
              ),
              DataCell(
                row is SharedFinanceEntry && widget.scopeId != null
                    ? FinanceSourceLink(
                        entryId: row.id,
                        scopeId: widget.scopeId,
                        partition: widget.partition,
                      )
                    : const SizedBox.shrink(),
              ),
              DataCell(
                row is SharedFinanceEntry &&
                        row.status == SharedFinanceStatus.planned &&
                        widget.scopeId != null
                    ? RemoteReminderButton(
                        scopeId: widget.scopeId!,
                        targetType: 'financeEntry',
                        targetId: row.id,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
      ],
    ),
  );
}
