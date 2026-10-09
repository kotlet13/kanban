import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/finance_forecast.dart';
import '../../domain/linked_payment_models.dart';
import '../../state/local_spaces_provider.dart';
import '../../domain/organizer_models.dart';
import '../../state/organizer_provider.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import '../personal_workspace_boundary.dart';
import 'finance_access_guard.dart';
import 'finance_money.dart';
import 'finance_plan_forms.dart';
import 'finance_plan_wizard.dart';

OrganizerSnapshot sharedFinancePlanningSnapshot(
  CollaborationState state,
  String scopeId,
) {
  final data = state.dataForScope(scopeId);
  return OrganizerSnapshot(
    workspaceKey: 'shared:${state.session?.partition}:$scopeId',
    projects: data.projects,
    tasks: data.tasks,
    people: data.people,
    financeAccounts: [
      for (final a in data.financeAccounts)
        LocalFinanceAccount(
          id: a.id,
          name: a.name,
          currency: a.currency,
          openingBalanceMinor: a.openingBalanceMinor,
          openingBalanceAt: a.openingBalanceAt,
          archived: a.archived,
          revision: a.revision,
          createdAt: a.createdAt,
          updatedAt: a.updatedAt,
        ),
    ],
    financeRecurrenceRules: data.financeRecurrenceRules,
    financeEntries: [
      for (final e in data.financeEntries)
        FinanceEntry(
          id: e.id,
          title: e.title,
          amountMinor: e.amountMinor,
          currency: e.currency,
          kind: e.kind,
          status: e.status == SharedFinanceStatus.planned
              ? FinanceEntryStatus.planned
              : FinanceEntryStatus.posted,
          occurredAt: e.occurredAt,
          plannedAt:
              e.plannedAt ??
              (e.status == SharedFinanceStatus.planned && !e.hasPlanningMetadata
                  ? e.occurredAt
                  : null),
          paidAt: e.paidAt,
          projectId: null,
          notes: e.notes,
          taskId: e.taskId,
          ledgerAccountId: e.ledgerAccountId ?? e.accountId,
          payerPersonId: e.payerPersonId,
          recipientPersonId: e.recipientPersonId,
          recurrenceRuleId: e.recurrenceRuleId,
          occurrenceKey: e.occurrenceKey,
          revision: e.revision,
          createdAt: e.createdAt,
          updatedAt: e.updatedAt,
        ),
    ],
  );
}

class FinancePlanningPanel extends ConsumerStatefulWidget {
  const FinancePlanningPanel({
    super.key,
    required this.snapshot,
    this.sharedScopeId,
    this.forecastAvailable = true,
    this.accountFilter,
    this.payments,
  });
  final OrganizerSnapshot snapshot;
  final String? sharedScopeId;
  final bool forecastAvailable;
  final PaymentSnapshot? payments;

  /// External ledger selection: * all, _none unassigned, otherwise account ID.
  final String? accountFilter;
  @override
  ConsumerState<FinancePlanningPanel> createState() =>
      _FinancePlanningPanelState();
}

class _FinancePlanningPanelState extends ConsumerState<FinancePlanningPanel> {
  String? _accountId;
  String _currency = 'EUR';
  bool _busy = false;
  String? _materializedMonth;
  bool get _isShared => widget.sharedScopeId != null;
  _PlanGuard _guard({String? existingId}) => _PlanGuard(
    context,
    ref,
    widget.snapshot,
    widget.sharedScopeId,
    existingId: existingId,
  );
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(financePlanningErrorMessage(context, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _privateOwned(String id) =>
      widget.snapshot.workspaceKey.startsWith('private:') &&
      ref
              .read(collaborationProvider)
              .valueOrNull
              ?.privateRecordIds
              .values
              .contains(id) ==
          true;
  bool _canEdit(String id) =>
      !_busy &&
      _guard(existingId: id).isCurrent &&
      (!_isShared && !_privateOwned(id) ||
          ref.read(collaborationProvider).valueOrNull?.financeContractVersion ==
              2);
  OrganizerSnapshot _formSnapshot({String? existingId}) {
    final private =
        widget.snapshot.workspaceKey.startsWith('private:') &&
        (existingId == null || _privateOwned(existingId));
    return widget.snapshot.copyWith(
      financeAccounts: widget.snapshot.financeAccounts.where(
        (a) => _isShared || _privateOwned(a.id) == private,
      ),
    );
  }

  Future<void> _wizard() async {
    final guard = _guard();
    final snapshot = widget.snapshot;
    await showFinancePlanWizard(
      context,
      snapshot: _formSnapshot(),
      wrap: guard.wrap,
      scopeDescription: _isShared
          ? ref
                .read(collaborationProvider)
                .valueOrNull!
                .scopes
                .firstWhere((s) => s.id == widget.sharedScopeId)
                .name
          : !snapshot.workspaceKey.startsWith('private:')
          ? context.l10n.financePlanLocal
          : context.l10n.financePlanPrivate,
      requireAccount: _isShared,
      onSave: (accounts, rules) async {
        guard.check();
        if (_isShared) {
          await ref
              .read(collaborationProvider.notifier)
              .saveFinancePlanForScope(
                scopeId: widget.sharedScopeId!,
                accounts: accounts,
                rules: rules,
              );
        } else {
          await ref
              .read(organizerProvider.notifier)
              .saveFinancePlan(
                accounts: accounts,
                rules: rules,
                expectedRevision: snapshot.revision,
                expectedWorkspaceKey: snapshot.workspaceKey,
              );
        }
      },
    );
  }

  Future<void> _account([LocalFinanceAccount? account]) async {
    final guard = _guard(existingId: account?.id), snapshot = widget.snapshot;
    final draft = await showFinanceAccountForm(
      context,
      account: account,
      wrap: guard.wrap,
    );
    if (draft == null) return;
    guard.check();
    if (_isShared) {
      if (account == null) {
        await ref
            .read(collaborationProvider.notifier)
            .saveFinancePlanForScope(
              scopeId: widget.sharedScopeId!,
              accounts: [draft],
              rules: [],
            );
      } else {
        final previous = ref
            .read(collaborationProvider)
            .valueOrNull!
            .dataForScope(widget.sharedScopeId!)
            .financeAccounts
            .firstWhere((a) => a.id == draft.id);
        await ref
            .read(collaborationProvider.notifier)
            .updateFinanceAccount(
              widget.sharedScopeId!,
              previous.copyWith(
                name: draft.name,
                currency: draft.currency,
                openingBalanceMinor: draft.openingBalanceMinor,
                openingBalanceAt: draft.openingBalanceAt,
                archived: draft.archived,
              ),
            );
      }
    } else if (account == null) {
      await ref
          .read(organizerProvider.notifier)
          .saveFinancePlan(
            accounts: [draft],
            rules: [],
            expectedRevision: snapshot.revision,
            expectedWorkspaceKey: snapshot.workspaceKey,
          );
    } else {
      await ref
          .read(organizerProvider.notifier)
          .updateFinanceAccount(
            draft,
            expectedWorkspaceKey: snapshot.workspaceKey,
          );
    }
  }

  Future<void> _rule([FinanceRecurrenceRule? rule]) async {
    final guard = _guard(existingId: rule?.id), snapshot = widget.snapshot;
    final draft = await showFinanceRuleForm(
      context,
      snapshot: _formSnapshot(existingId: rule?.id),
      rule: rule,
      wrap: guard.wrap,
    );
    if (draft == null) return;
    guard.check();
    if (_isShared) {
      if (rule == null) {
        await ref
            .read(collaborationProvider.notifier)
            .saveFinancePlanForScope(
              scopeId: widget.sharedScopeId!,
              accounts: [],
              rules: [draft],
            );
      } else {
        await ref
            .read(collaborationProvider.notifier)
            .updateFinanceRecurrenceRule(widget.sharedScopeId!, draft);
      }
    } else if (rule == null) {
      await ref
          .read(organizerProvider.notifier)
          .saveFinancePlan(
            accounts: [],
            rules: [draft],
            expectedRevision: snapshot.revision,
            expectedWorkspaceKey: snapshot.workspaceKey,
          );
    } else {
      await ref
          .read(organizerProvider.notifier)
          .updateFinanceRecurrenceRule(
            draft,
            expectedWorkspaceKey: snapshot.workspaceKey,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, snapshot = widget.snapshot;
    final state = ref.watch(collaborationProvider).valueOrNull;
    final synced = _isShared || snapshot.workspaceKey.startsWith('private:');
    final available = !synced || state?.financeContractVersion == 2;
    final guard = _guard();
    final canWrite = available && guard.isCurrent;
    final now = DateTime.now();
    final key = '${snapshot.workspaceKey}:${now.year}-${now.month}';
    final localRules = snapshot.financeRecurrenceRules
        .where((r) => r.active && !_privateOwned(r.id))
        .map((r) => r.id)
        .toSet();
    final materializationGuard = canWrite
        ? guard
        : localRules.isEmpty
        ? null
        : _guard(existingId: localRules.first);
    if ((canWrite ||
            !_isShared &&
                localRules.isNotEmpty &&
                materializationGuard!.isCurrent) &&
        snapshot.financeRecurrenceRules.any((r) => r.active) &&
        _materializedMonth != key) {
      _materializedMonth = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !materializationGuard!.isCurrent) return;
        _run(() async {
          materializationGuard.check();
          if (_isShared) {
            await ref
                .read(collaborationProvider.notifier)
                .materializeFinanceOccurrencesForScope(widget.sharedScopeId!);
          } else {
            await ref
                .read(organizerProvider.notifier)
                .materializeFinanceOccurrences(
                  expectedWorkspaceKey: snapshot.workspaceKey,
                  ruleIds: canWrite ? null : localRules,
                );
          }
        });
      });
    }
    final selectedAccount = widget.accountFilter ?? _accountId;
    final account = snapshot.financeAccounts
        .where((a) => a.id == selectedAccount)
        .firstOrNull;
    final currencies = {
      ...supportedCurrencies,
      ...snapshot.financeEntries.map((e) => e.currency),
    }.toList()..sort();
    final currency = account?.currency ?? _currency;
    final through = DateTime(now.year, now.month + 4, 0, 23, 59, 59);
    final forecast = forecastFinance(
      snapshot,
      currency: currency,
      account: account,
      unassignedOnly: widget.accountFilter == '_none',
      through: through,
      payments: widget.payments,
      transfers: _isShared
          ? (state?.dataForScope(widget.sharedScopeId!).financeTransfers ?? [])
          : [],
    );
    final dailyPoints = <DateTime, FinanceForecastPoint>{};
    for (final point in forecast.points) {
      final date = point.date.toLocal();
      dailyPoints[DateTime(date.year, date.month, date.day)] = point;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.financePlanTitle,
          subtitle: l.financePlanDescription,
        ),
        Text(
          _isShared
              ? state?.scopes
                        .where((s) => s.id == widget.sharedScopeId)
                        .firstOrNull
                        ?.name ??
                    ''
              : synced
              ? l.financePlanPrivate
              : l.financePlanLocal,
        ),
        if (!available) Text(l.financePlanUpgrade),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: canWrite && !_busy ? () => _run(_wizard) : null,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: Text(l.financePlanWizard),
            ),
            TextButton.icon(
              onPressed: canWrite && !_busy ? () => _run(() => _rule()) : null,
              icon: const Icon(Icons.repeat),
              label: Text(l.financePlanAddRule),
            ),
            TextButton.icon(
              onPressed: canWrite && !_busy
                  ? () => _run(() => _account())
                  : null,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(l.financeAddAccount),
            ),
          ],
        ),
        if (_busy && ModalRoute.of(context)?.isCurrent != false)
          const LinearProgressIndicator(),
        const SizedBox(height: 12),
        for (final a in snapshot.financeAccounts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: _canEdit(a.id) ? () => _run(() => _account(a)) : null,
            title: Text(a.name),
            subtitle: Text(
              a.archived
                  ? l.financePlanAccountArchived
                  : a.openingBalanceMinor == null
                  ? l.financePlanNoOpening
                  : '${sharedMoneyLabel(context, BigInt.from(a.openingBalanceMinor!), a.currency)} · ${a.openingBalanceAt == null ? l.financePlanOpeningUndated : organizerDate(context, a.openingBalanceAt!)}',
            ),
          ),
        if (snapshot.financeRecurrenceRules.isNotEmpty)
          Text(
            l.financePlanRules,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        for (final r in snapshot.financeRecurrenceRules)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: _canEdit(r.id) ? () => _run(() => _rule(r)) : null,
            title: Text(r.title),
            subtitle: Text(
              '${financeRuleKindLabel(context, r.kind)} · ${l.financePlanDay} ${r.monthDay} · ${formatMoneyMinor(r.estimatedAmountMinor)} ${r.currency}',
            ),
            trailing: Icon(
              r.active ? Icons.repeat : Icons.pause_circle_outline,
            ),
          ),
        const SizedBox(height: 16),
        if (widget.forecastAvailable) ...[
          Text(
            l.financePlanForecast,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(l.financePlanForecastPeriod(organizerDate(context, through))),
          const SizedBox(height: 12),
          if (widget.accountFilter == null)
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.financeAccount),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(l.financeAllAccounts),
                ),
                for (final a in snapshot.financeAccounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text('${a.name} · ${a.currency}'),
                  ),
              ],
              onChanged: (id) => setState(() => _accountId = id),
            ),
          const SizedBox(height: 12),
          if (account == null)
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: InputDecoration(labelText: l.organizerCurrency),
              items: [
                for (final c in currencies)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (c) => setState(() => _currency = c!),
            ),
          const SizedBox(height: 12),
          Text(
            forecast.hasOpeningBalance
                ? l.financePlanProjectedBalance
                : l.financePlanNetChange,
          ),
          Text(
            sharedMoneyLabel(context, forecast.endMinor, currency),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (!forecast.hasOpeningBalance) Text(l.financePlanNoOpening),
          if (forecast.undatedCount > 0) Text(l.financePlanUndated),
          if (forecast.points.isEmpty) Text(l.financePlanEmpty),
          for (final day in dailyPoints.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(organizerDate(context, day.key)),
              subtitle: day.value.paymentMovement == null
                  ? null
                  : Text(
                      day.value.paymentMovement!.amountMinor > 0
                          ? l.paymentRefundReceived
                          : (_isShared &&
                                    const {
                                      SharedScopeKind.project,
                                      SharedScopeKind.organization,
                                    }.contains(
                                      state?.scopes
                                          .where(
                                            (s) => s.id == widget.sharedScopeId,
                                          )
                                          .firstOrNull
                                          ?.kind,
                                    ) ||
                                !_isShared &&
                                    ref
                                            .read(localSpacesProvider)
                                            .valueOrNull
                                            ?.spaces
                                            .where(
                                              (s) =>
                                                  s.id == snapshot.workspaceKey,
                                            )
                                            .firstOrNull
                                            ?.kind ==
                                        LocalSpaceKind.organization)
                          ? l.paymentRefundPaid
                          : l.paymentPersonalDisplay,
                    ),
              trailing: Text(
                sharedMoneyLabel(context, day.value.runningMinor, currency),
              ),
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PlanGuard {
  _PlanGuard(
    BuildContext context,
    WidgetRef ref,
    OrganizerSnapshot snapshot,
    String? sharedScopeId, {
    String? existingId,
  }) : personal = sharedScopeId == null
           ? PersonalWorkspaceGuard(context, ref, snapshot.workspaceKey)
           : null,
       finance = sharedScopeId != null
           ? FinanceAccessGuard(context, ref, sharedScopeId, write: true)
           : !snapshot.workspaceKey.startsWith('private:') ||
                 (existingId != null &&
                     ref
                             .read(collaborationProvider)
                             .valueOrNull
                             ?.privateRecordIds
                             .values
                             .contains(existingId) !=
                         true)
           ? null
           : FinanceAccessGuard(
               context,
               ref,
               ref
                       .read(collaborationProvider)
                       .valueOrNull
                       ?.privateSync
                       .scopeId ??
                   '',
               write: true,
             );
  final PersonalWorkspaceGuard? personal;
  final FinanceAccessGuard? finance;
  bool get isCurrent =>
      (personal?.isCurrent ?? true) && (finance?.isCurrent ?? true);
  void check() {
    if (!isCurrent) throw const CollaborationException('finance_forbidden');
  }

  Widget wrap(Widget child) =>
      personal?.wrap(finance?.wrap(child) ?? child) ??
      finance?.wrap(child) ??
      child;
}
