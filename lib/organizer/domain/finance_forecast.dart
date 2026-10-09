import 'organizer_models.dart';
import 'shared_finance_models.dart';
import 'linked_payment_models.dart';

class FinanceForecastPoint {
  const FinanceForecastPoint({
    this.entry,
    this.paymentMovement,
    required this.title,
    required this.date,
    required this.changeMinor,
    required this.runningMinor,
  });
  final FinanceEntry? entry;
  final PaymentCashMovement? paymentMovement;
  final String title;
  final DateTime date;
  final BigInt changeMinor, runningMinor;
}

class FinanceForecast {
  FinanceForecast({
    required this.currency,
    required this.hasOpeningBalance,
    required this.startMinor,
    required Iterable<FinanceForecastPoint> points,
    this.undatedCount = 0,
  }) : points = List.unmodifiable(points);
  final String currency;
  final bool hasOpeningBalance;
  final BigInt startMinor;
  final List<FinanceForecastPoint> points;
  final int undatedCount;
  BigInt get endMinor => points.isEmpty ? startMinor : points.last.runningMinor;
}

/// A projected cash flow per currency; no exchange rate or sample balance.
FinanceForecast forecastFinance(
  OrganizerSnapshot snapshot, {
  required String currency,
  required DateTime through,
  LocalFinanceAccount? account,
  bool unassignedOnly = false,
  Iterable<SharedFinanceTransfer> transfers = const [],
  PaymentSnapshot? payments,
}) {
  final excluded = {
    for (final event in payments?.events ?? const <PaymentEvent>[])
      event.sourceEntryId,
  };
  final entries = snapshot.financeEntries
      .where(
        (e) =>
            e.currency == currency &&
            !excluded.contains(e.id) &&
            (account == null || e.ledgerAccountId == account.id) &&
            (!unassignedOnly || e.ledgerAccountId == null),
      )
      .toList();
  // A canonical posted occurrence suppresses a stale planned duplicate in any
  // recovered projection. Validation still rejects newly created duplicates.
  String? occurrence(FinanceEntry e) =>
      e.recurrenceRuleId == null || e.occurrenceKey == null
      ? null
      : '${e.recurrenceRuleId}:${e.occurrenceKey}';
  final posted = entries
      .where((e) => e.status == FinanceEntryStatus.posted)
      .map(occurrence)
      .whereType<String>()
      .toSet();
  final opening = account?.openingBalanceAt;
  DateTime? date(FinanceEntry e) {
    final date = e.status == FinanceEntryStatus.planned
        ? e.plannedAt
        : (e.paidAt ?? e.occurredAt);
    return date != null &&
            opening != null &&
            e.status == FinanceEntryStatus.planned &&
            date.isBefore(opening)
        ? opening
        : date;
  }

  final included =
      entries.where((e) {
        final when = date(e);
        return when != null &&
            !when.isAfter(through) &&
            (opening == null ||
                e.status == FinanceEntryStatus.planned ||
                !when.isBefore(opening)) &&
            !(e.status == FinanceEntryStatus.planned &&
                posted.contains(occurrence(e)));
      }).toList()..sort((a, b) {
        final order = date(a)!.compareTo(date(b)!);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
  final start = BigInt.from(account?.openingBalanceMinor ?? 0);
  final events =
      <
          ({
            FinanceEntry? entry,
            PaymentCashMovement? movement,
            String title,
            DateTime date,
            BigInt change,
            String id,
          })
        >[
          for (final e in included)
            (
              entry: e,
              movement: null,
              title: e.title,
              date: date(e)!,
              change:
                  BigInt.from(e.amountMinor) *
                  BigInt.from(e.kind == FinanceEntryKind.income ? 1 : -1),
              id: e.id,
            ),
          if (account != null)
            for (final t in transfers.where(
              (t) =>
                  t.currency == currency &&
                  (t.fromAccountId == account.id ||
                      t.toAccountId == account.id),
            ))
              if (!t.occurredAt.isAfter(through) &&
                  (t.status == SharedFinanceStatus.planned ||
                      opening == null ||
                      !t.occurredAt.isBefore(opening)))
                (
                  entry: null,
                  movement: null,
                  title: t.title,
                  date:
                      opening != null &&
                          t.status == SharedFinanceStatus.planned &&
                          t.occurredAt.isBefore(opening)
                      ? opening
                      : t.occurredAt,
                  change:
                      BigInt.from(t.amountMinor) *
                      BigInt.from(t.toAccountId == account.id ? 1 : -1),
                  id: t.id,
                ),
          if (!unassignedOnly)
            for (final movement
                in payments?.cashMovements ?? const <PaymentCashMovement>[])
              if (movement.currency == currency &&
                  (account == null || movement.accountId == account.id) &&
                  !movement.paidAt.isAfter(through) &&
                  (opening == null || !movement.paidAt.isBefore(opening)))
                (
                  entry: null,
                  movement: movement,
                  title: '',
                  date: movement.paidAt,
                  change: BigInt.from(movement.amountMinor),
                  id: movement.id,
                ),
        ]
        ..sort(
          (a, b) => a.date.compareTo(b.date) == 0
              ? a.id.compareTo(b.id)
              : a.date.compareTo(b.date),
        );
  var running = start;
  return FinanceForecast(
    currency: currency,
    hasOpeningBalance: account?.openingBalanceMinor != null,
    startMinor: start,
    undatedCount: entries.where((e) => date(e) == null).length,
    points: events.map((event) {
      running += event.change;
      return FinanceForecastPoint(
        entry: event.entry,
        paymentMovement: event.movement,
        title: event.title,
        date: event.date,
        changeMinor: event.change,
        runningMinor: running,
      );
    }).toList(),
  );
}

/// Calendar-based weekend checks for ONE salary occurrence. Holidays need a
/// configured calendar; this deliberately adjusts Saturdays/Sundays only.
List<DateTime> salaryCheckDates(FinanceRecurrenceRule rule, DateTime nominal) {
  final date = nominal.toLocal();
  DateTime at(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
    rule.reminderMinuteOfDay ~/ 60,
    rule.reminderMinuteOfDay % 60,
  );
  final day = DateTime(date.year, date.month, date.day);
  if (day.weekday == DateTime.saturday) {
    return [
      at(DateTime(day.year, day.month, day.day - 1)),
      at(DateTime(day.year, day.month, day.day + 2)),
    ];
  }
  if (day.weekday == DateTime.sunday) {
    return [
      at(DateTime(day.year, day.month, day.day - 2)),
      at(DateTime(day.year, day.month, day.day + 1)),
    ];
  }
  return [at(day)];
}
