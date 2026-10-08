part of 'organizer_repository.dart';

extension OrganizerFinancePlanActions on OrganizerRepository {
  void _checkFinanceWorkspace(
    OrganizerSnapshot s,
    String expectedWorkspaceKey,
  ) {
    if (s.workspaceKey != expectedWorkspaceKey) {
      throw const OrganizerConflictException(
        'Financial workspace changed; reload',
      );
    }
  }

  Future<void> saveFinancePlan({
    required List<LocalFinanceAccount> accounts,
    required List<FinanceRecurrenceRule> rules,
    required int expectedRevision,
    required String expectedWorkspaceKey,
  }) => _change((s) {
    _checkFinanceWorkspace(s, expectedWorkspaceKey);
    if (s.revision != expectedRevision) {
      throw const OrganizerConflictException('Financial plan changed; reload');
    }
    for (final account in accounts) {
      account.validate();
      if (s.financeAccounts.any((v) => v.id == account.id)) {
        throw const OrganizerConflictException('Account already exists');
      }
    }
    for (final rule in rules) {
      rule.validate();
      if (s.financeRecurrenceRules.any((v) => v.id == rule.id)) {
        throw const OrganizerConflictException('Rule already exists');
      }
    }
    return _financeOccurrences(
      s.copyWith(
        financeAccounts: [...s.financeAccounts, ...accounts],
        financeRecurrenceRules: [...s.financeRecurrenceRules, ...rules],
      ),
    );
  });

  Future<void> updateFinanceAccount(
    LocalFinanceAccount account, {
    required String expectedWorkspaceKey,
  }) => _change((s) {
    _checkFinanceWorkspace(s, expectedWorkspaceKey);
    final current = _find(s.financeAccounts, account.id, (v) => v.id);
    if (current.revision != account.revision ||
        current.createdAt != account.createdAt) {
      throw const OrganizerConflictException(
        'Financial account changed; reload',
      );
    }
    if (current.currency != account.currency) {
      throw const FormatException('Account currency is immutable');
    }
    final updated = account.copyWith(
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    updated.validate();
    return s.copyWith(
      financeAccounts: s.financeAccounts.map(
        (a) => a.id == account.id ? updated : a,
      ),
    );
  });

  Future<void> updateFinanceRecurrenceRule(
    FinanceRecurrenceRule rule, {
    required String expectedWorkspaceKey,
  }) => _change((s) {
    _checkFinanceWorkspace(s, expectedWorkspaceKey);
    final current = _find(s.financeRecurrenceRules, rule.id, (v) => v.id);
    if (current.revision != rule.revision ||
        current.createdAt != rule.createdAt) {
      throw const OrganizerConflictException('Monthly rule changed; reload');
    }
    if (current.currency != rule.currency || current.kind != rule.kind) {
      throw const FormatException(
        'Rule currency and kind are immutable; create a new rule',
      );
    }
    final updated = rule.copyWith(
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    updated.validate();
    final now = _now();
    final entries = <FinanceEntry>[];
    for (final e in s.financeEntries) {
      if (e.recurrenceRuleId != rule.id ||
          e.status == FinanceEntryStatus.posted ||
          e.plannedAt == null ||
          e.plannedAt!.isBefore(now)) {
        entries.add(e);
        continue;
      }
      final month = e.plannedAt!.toLocal();
      if (!updated.includesMonth(month.year, month.month)) continue;
      entries.add(
        e.copyWith(
          title: updated.title,
          kind: updated.entryKind,
          amountMinor: updated.estimatedAmountMinor,
          currency: updated.currency,
          ledgerAccountId: updated.ledgerAccountId,
          plannedAt: updated.dateForMonth(month.year, month.month).toUtc(),
          revision: e.revision + 1,
          updatedAt: _updatedAt(e.updatedAt),
        ),
      );
    }
    return _financeOccurrences(
      s.copyWith(
        financeEntries: entries,
        financeRecurrenceRules: s.financeRecurrenceRules.map(
          (r) => r.id == rule.id ? updated : r,
        ),
      ),
    );
  });

  Future<void> materializeFinanceOccurrences({
    DateTime? through,
    Set<String>? ruleIds,
    required String expectedWorkspaceKey,
  }) => _change((s) {
    _checkFinanceWorkspace(s, expectedWorkspaceKey);
    return _financeOccurrences(s, through: through, ruleIds: ruleIds);
  });

  OrganizerSnapshot _financeOccurrences(
    OrganizerSnapshot s, {
    DateTime? through,
    Set<String>? ruleIds,
  }) {
    final now = _now(), localNow = _clock().toLocal();
    final end = (through ?? DateTime(localNow.year, localNow.month + 12, 0))
        .toLocal();
    if (end.year * 12 + end.month - (localNow.year * 12 + localNow.month) >
        60) {
      throw const FormatException('Forecast horizon exceeds five years');
    }
    final entries = [...s.financeEntries];
    final seen = {
      for (final e in entries)
        if (e.recurrenceRuleId != null)
          '${e.recurrenceRuleId}:${e.occurrenceKey}',
    };
    for (final rule in s.financeRecurrenceRules.where(
      (r) => r.active && (ruleIds == null || ruleIds.contains(r.id)),
    )) {
      if (rule.ledgerAccountId != null &&
          s.financeAccounts.any(
            (a) => a.id == rule.ledgerAccountId && a.archived,
          )) {
        continue;
      }
      for (
        var month = DateTime(localNow.year, localNow.month);
        !month.isAfter(DateTime(end.year, end.month));
        month = DateTime(month.year, month.month + 1)
      ) {
        if (!rule.includesMonth(month.year, month.month)) continue;
        final key = rule.keyForMonth(month.year, month.month);
        if (!seen.add('${rule.id}:$key')) continue;
        final date = rule.dateForMonth(month.year, month.month).toUtc();
        entries.add(
          FinanceEntry(
            id: _idGenerator(),
            title: rule.title,
            status: FinanceEntryStatus.planned,
            plannedAt: date,
            amountMinor: rule.estimatedAmountMinor,
            currency: rule.currency,
            kind: rule.entryKind,
            occurredAt: date,
            projectId: null,
            notes: '',
            ledgerAccountId: rule.ledgerAccountId,
            recurrenceRuleId: rule.id,
            occurrenceKey: key,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }
    return s.copyWith(financeEntries: entries);
  }

  Future<void> confirmFinanceOccurrence({
    required FinanceEntry entry,
    required int amountMinor,
    required DateTime paidAt,
    required String expectedWorkspaceKey,
  }) => _change((s) {
    _checkFinanceWorkspace(s, expectedWorkspaceKey);
    final current = _find(s.financeEntries, entry.id, (v) => v.id);
    if (amountMinor <= 0 || amountMinor > maxMoneyMinor) {
      throw const FormatException('Invalid actual amount');
    }
    final actual = paidAt.toUtc();
    if (current.status == FinanceEntryStatus.posted &&
        current.amountMinor == amountMinor &&
        current.paidAt == actual) {
      return s;
    }
    if (current.status != FinanceEntryStatus.planned ||
        current.revision != entry.revision ||
        current.createdAt != entry.createdAt) {
      throw const OrganizerConflictException('Occurrence changed; reload');
    }
    final updated = current.copyWith(
      status: FinanceEntryStatus.posted,
      amountMinor: amountMinor,
      paidAt: actual,
      occurredAt: actual,
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    return s.copyWith(
      financeEntries: s.financeEntries.map(
        (e) => e.id == entry.id ? updated : e,
      ),
    );
  });
}
