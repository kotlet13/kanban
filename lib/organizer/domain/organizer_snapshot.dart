import 'organizer_models.dart';

/// A committed, immutable view of the personal local workspace.
class OrganizerSnapshot {
  OrganizerSnapshot({
    this.revision = 0,
    this.workspaceKey = 'local',
    Iterable<HouseholdPerson> people = const [],
    Iterable<LocalFinanceAccount> financeAccounts = const [],
    Iterable<FinanceRecurrenceRule> financeRecurrenceRules = const [],
    Iterable<LocalProject> projects = const [],
    Iterable<LocalTask> tasks = const [],
    Iterable<LocalShoppingList> shoppingLists = const [],
    Iterable<LocalShoppingItem> shoppingItems = const [],
    Iterable<LocalEvent> events = const [],
    Iterable<FinanceEntry> financeEntries = const [],
    Iterable<LocalReminder> reminders = const [],
  }) : people = List.unmodifiable(people),
       financeAccounts = List.unmodifiable(financeAccounts),
       financeRecurrenceRules = List.unmodifiable(financeRecurrenceRules),
       projects = List.unmodifiable(projects),
       tasks = List.unmodifiable(tasks),
       shoppingLists = List.unmodifiable(shoppingLists),
       shoppingItems = List.unmodifiable(shoppingItems),
       events = List.unmodifiable(events),
       financeEntries = List.unmodifiable(financeEntries),
       reminders = List.unmodifiable(reminders);

  final int revision;
  final String workspaceKey;
  final List<HouseholdPerson> people;
  final List<LocalFinanceAccount> financeAccounts;
  final List<FinanceRecurrenceRule> financeRecurrenceRules;
  final List<LocalProject> projects;
  final List<LocalTask> tasks;
  final List<LocalShoppingList> shoppingLists;
  final List<LocalShoppingItem> shoppingItems;
  final List<LocalEvent> events;
  final List<FinanceEntry> financeEntries;
  final List<LocalReminder> reminders;

  OrganizerSnapshot copyWith({
    int? revision,
    String? workspaceKey,
    Iterable<HouseholdPerson>? people,
    Iterable<LocalFinanceAccount>? financeAccounts,
    Iterable<FinanceRecurrenceRule>? financeRecurrenceRules,
    Iterable<LocalProject>? projects,
    Iterable<LocalTask>? tasks,
    Iterable<LocalShoppingList>? shoppingLists,
    Iterable<LocalShoppingItem>? shoppingItems,
    Iterable<LocalEvent>? events,
    Iterable<FinanceEntry>? financeEntries,
    Iterable<LocalReminder>? reminders,
  }) => OrganizerSnapshot(
    revision: revision ?? this.revision,
    workspaceKey: workspaceKey ?? this.workspaceKey,
    people: people ?? this.people,
    financeAccounts: financeAccounts ?? this.financeAccounts,
    financeRecurrenceRules:
        financeRecurrenceRules ?? this.financeRecurrenceRules,
    projects: projects ?? this.projects,
    tasks: tasks ?? this.tasks,
    shoppingLists: shoppingLists ?? this.shoppingLists,
    shoppingItems: shoppingItems ?? this.shoppingItems,
    events: events ?? this.events,
    financeEntries: financeEntries ?? this.financeEntries,
    reminders: reminders ?? this.reminders,
  );

  BigInt exactBalanceForCurrency(String currency) => financeEntries
      .where(
        (e) => e.currency == currency && e.status == FinanceEntryStatus.posted,
      )
      .fold(
        BigInt.zero,
        (sum, e) =>
            sum +
            (e.kind == FinanceEntryKind.income
                ? BigInt.from(e.amountMinor)
                : -BigInt.from(e.amountMinor)),
      );

  int balanceForCurrency(String currency) => financeEntries
      .where(
        (entry) =>
            entry.currency == currency &&
            entry.status == FinanceEntryStatus.posted,
      )
      .fold(
        0,
        (total, entry) =>
            total +
            (entry.kind == FinanceEntryKind.income
                ? entry.amountMinor
                : -entry.amountMinor),
      );

  Map<String, Object?> toJson() => {
    'revision': revision,
    'workspaceKey': workspaceKey,
    'people': people.map((v) => v.toJson()).toList(),
    'financeAccounts': financeAccounts.map((v) => v.toJson()).toList(),
    'financeRecurrenceRules': financeRecurrenceRules
        .map((v) => v.toJson())
        .toList(),
    'projects': projects.map((v) => v.toJson()).toList(),
    'tasks': tasks.map((v) => v.toJson()).toList(),
    'shoppingLists': shoppingLists.map((v) => v.toJson()).toList(),
    'shoppingItems': shoppingItems.map((v) => v.toJson()).toList(),
    'events': events.map((v) => v.toJson()).toList(),
    'financeEntries': financeEntries.map((v) => v.toJson()).toList(),
    'reminders': reminders.map((v) => v.toJson()).toList(),
  };

  factory OrganizerSnapshot.fromJson(Map<String, dynamic> json) {
    final snapshot = OrganizerSnapshot(
      revision: readInt(json, 'revision'),
      workspaceKey: json['workspaceKey'] as String? ?? 'local',
      people: json.containsKey('people')
          ? _records(json, 'people', HouseholdPerson.fromJson)
          : const [],
      financeAccounts: json.containsKey('financeAccounts')
          ? _records(json, 'financeAccounts', LocalFinanceAccount.fromJson)
          : const [],
      financeRecurrenceRules: json.containsKey('financeRecurrenceRules')
          ? _records(
              json,
              'financeRecurrenceRules',
              FinanceRecurrenceRule.fromJson,
            )
          : const [],
      projects: _records(json, 'projects', LocalProject.fromJson),
      tasks: _records(json, 'tasks', LocalTask.fromJson),
      shoppingLists: _records(
        json,
        'shoppingLists',
        LocalShoppingList.fromJson,
      ),
      shoppingItems: _records(
        json,
        'shoppingItems',
        LocalShoppingItem.fromJson,
      ),
      events: _records(json, 'events', LocalEvent.fromJson),
      financeEntries: _records(json, 'financeEntries', FinanceEntry.fromJson),
      reminders: _records(json, 'reminders', LocalReminder.fromJson),
    );
    snapshot.validate();
    return snapshot;
  }

  Set<String> get recordIds => {
    ...people.map((v) => v.id),
    ...financeAccounts.map((v) => v.id),
    ...financeRecurrenceRules.map((v) => v.id),
    ...projects.map((v) => v.id),
    ...tasks.map((v) => v.id),
    ...shoppingLists.map((v) => v.id),
    ...shoppingItems.map((v) => v.id),
    ...events.map((v) => v.id),
    ...financeEntries.map((v) => v.id),
    ...reminders.map((v) => v.id),
  };

  /// Shared validation for both imported and newly edited records.
  void validate() {
    if (revision < 0) throw const FormatException('Invalid revision');
    if ([
      ...projects.map((v) => v.revision),
      ...tasks.map((v) => v.revision),
      ...shoppingLists.map((v) => v.revision),
      ...shoppingItems.map((v) => v.revision),
      ...events.map((v) => v.revision),
      ...financeEntries.map((v) => v.revision),
    ].any((v) => v < 0)) {
      throw const FormatException('Invalid record revision');
    }
    final seen = <String>{};
    void record(
      String id,
      String? title,
      DateTime createdAt,
      DateTime? updatedAt,
    ) {
      if (id.isEmpty || id.length > 200 || !seen.add(id)) {
        throw const FormatException('Invalid or duplicate record ID');
      }
      if (title != null && (title.trim().isEmpty || title.length > 500)) {
        throw const FormatException('Title must contain 1–500 characters');
      }
      if (updatedAt != null && updatedAt.isBefore(createdAt)) {
        throw const FormatException('Invalid record timestamps');
      }
    }

    for (final person in people) {
      record(person.id, person.name, person.createdAt, person.updatedAt);
      person.validate();
    }
    for (final account in financeAccounts) {
      record(account.id, account.name, account.createdAt, account.updatedAt);
      account.validate();
    }
    for (final rule in financeRecurrenceRules) {
      record(rule.id, rule.title, rule.createdAt, rule.updatedAt);
      rule.validate();
    }
    final personIds = people.map((p) => p.id).toSet();
    final accounts = {for (final a in financeAccounts) a.id: a};
    final ruleIds = financeRecurrenceRules.map((r) => r.id).toSet();
    for (final rule in financeRecurrenceRules) {
      if (rule.ledgerAccountId != null &&
          (accounts[rule.ledgerAccountId] == null ||
              accounts[rule.ledgerAccountId]!.currency != rule.currency)) {
        throw const FormatException('Invalid rule account');
      }
    }
    final projectIds = projects.map((v) => v.id).toSet();
    void project(String? id) {
      if (id != null && !projectIds.contains(id)) {
        throw const FormatException('Project does not exist');
      }
    }

    void notes(String value) {
      if (value.length > 50000) throw const FormatException('Notes too long');
    }

    for (final v in projects) {
      record(v.id, v.title, v.createdAt, v.updatedAt);
      notes(v.description);
      validateAvailability(v.availabilityMinutes, v.availabilityPeriod);
      if (v.phases.length > 50 ||
          v.phases.map((p) => p.id).toSet().length != v.phases.length) {
        throw const FormatException('Invalid phase list');
      }
      for (final phase in v.phases) {
        phase.validate();
      }
      if (v.startAt != null &&
          v.endAt != null &&
          v.endAt!.isBefore(v.startAt!)) {
        throw const FormatException('Invalid project date range');
      }
    }
    for (final v in tasks) {
      record(v.id, v.title, v.createdAt, v.updatedAt);
      project(v.projectId);
      notes(v.notes);
      validateAvailability(v.availabilityMinutes, v.availabilityPeriod);
      v.timer.validate();
      if (v.estimateMinutes != null &&
          (v.estimateMinutes! <= 0 || v.estimateMinutes! > 525600)) {
        throw const FormatException('Invalid time estimate');
      }
      if (v.phaseId != null &&
          !projects.any(
            (p) =>
                p.id == v.projectId &&
                p.phases.any((phase) => phase.id == v.phaseId),
          )) {
        throw const FormatException('Invalid task phase');
      }
      if (v.assigneePersonId != null &&
          !personIds.contains(v.assigneePersonId)) {
        throw const FormatException('Invalid task assignee person');
      }
      if (v.subjectPersonIds.length > 20 ||
          v.subjectPersonIds.toSet().length != v.subjectPersonIds.length ||
          !v.subjectPersonIds.every(personIds.contains)) {
        throw const FormatException('Invalid task subject people');
      }
      if (v.startAt != null &&
          v.endAt != null &&
          v.endAt!.isBefore(v.startAt!)) {
        throw const FormatException('Invalid task date range');
      }
    }
    for (final v in shoppingLists) {
      record(v.id, v.title, v.createdAt, v.updatedAt);
    }
    final listIds = shoppingLists.map((v) => v.id).toSet();
    for (final v in shoppingItems) {
      record(v.id, v.title, v.createdAt, v.updatedAt);
      if (!listIds.contains(v.listId)) {
        throw const FormatException('Shopping list does not exist');
      }
      if (v.quantity.trim().isEmpty || v.quantity.length > 100) {
        throw const FormatException('Invalid quantity');
      }
    }
    for (final v in events) {
      record(v.id, v.title, v.createdAt, v.updatedAt);
      project(v.projectId);
      notes(v.notes);
      if (v.endsAt != null && v.endsAt!.isBefore(v.startsAt)) {
        throw const FormatException('Event ends before it starts');
      }
    }
    final linkedTasks = <String>{};
    final occurrences = <String>{};
    for (final v in financeEntries) {
      record(v.id, v.title, v.createdAt, v.updatedAt);
      project(v.projectId);
      notes(v.notes);
      if (v.taskId != null &&
          (!tasks.any((t) => t.id == v.taskId) ||
              !linkedTasks.add(v.taskId!) ||
              v.kind != FinanceEntryKind.expense)) {
        throw const FormatException('Invalid linked task cost');
      }
      if (v.taskId != null &&
          v.plannedAt != tasks.firstWhere((t) => t.id == v.taskId).dueAt) {
        throw const FormatException('Task cost date must follow task due date');
      }
      if (v.ledgerAccountId != null &&
          (accounts[v.ledgerAccountId] == null ||
              accounts[v.ledgerAccountId]!.currency != v.currency)) {
        throw const FormatException('Invalid finance account');
      }
      for (final person in [
        v.payerPersonId,
        v.recipientPersonId,
        v.createdByPersonId,
      ]) {
        if (person != null && !personIds.contains(person)) {
          throw const FormatException('Invalid finance participant');
        }
      }
      if ((v.recurrenceRuleId == null) != (v.occurrenceKey == null) ||
          (v.recurrenceRuleId != null &&
              (!ruleIds.contains(v.recurrenceRuleId) ||
                  !RegExp(r'^\d{4}-\d{2}$').hasMatch(v.occurrenceKey!) ||
                  !occurrences.add(
                    '${v.recurrenceRuleId}:${v.occurrenceKey}',
                  )))) {
        throw const FormatException('Invalid recurrence occurrence');
      }
      if (v.status == FinanceEntryStatus.planned && v.paidAt != null) {
        throw const FormatException('Planned entry cannot have payment date');
      }
      if (v.amountMinor <= 0 ||
          v.amountMinor > maxMoneyMinor ||
          !supportedCurrencies.contains(v.currency)) {
        throw const FormatException('Invalid money amount or currency');
      }
    }
    final taskById = {for (final v in tasks) v.id: v};
    // Dart web integers use JavaScript numbers. Bound absolute totals so every
    // intermediate addition remains exact on that platform too.
    final totals = <String, BigInt>{};
    for (final v in financeEntries) {
      totals[v.currency] =
          (totals[v.currency] ?? BigInt.zero) + BigInt.from(v.amountMinor);
    }
    if (totals.values.any((v) => v > BigInt.from(9007199254740991))) {
      throw const FormatException('Currency total exceeds exact integer range');
    }
    for (final v in reminders) {
      record(v.id, null, v.createdAt, null);
      final task = taskById[v.taskId];
      if (task == null ||
          task.isCompleted ||
          task.dueAt != v.dueAt ||
          v.id != reminderId(task)) {
        throw const FormatException('Invalid reminder');
      }
    }
    if (seen.length > 50000) throw const FormatException('Too many records');
  }
}

List<T> _records<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) decode,
) {
  final values = json[key];
  if (values is! List || values.length > 50000) {
    throw FormatException('Invalid collection: $key');
  }
  return values.map((value) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('Invalid record: $key');
    }
    return decode(value);
  }).toList();
}

String reminderId(LocalTask task) =>
    'due:${task.id}:${task.dueAt!.toUtc().microsecondsSinceEpoch}';

const maxMoneyMinor = 9000000000000;
const supportedCurrencies = {'EUR', 'USD', 'GBP', 'CHF'};

/// Exact decimal input for currencies with two fractional digits (e.g. EUR).
int parseMoneyMinor(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) {
    throw const FormatException(
      'Use a positive amount with at most two decimals',
    );
  }
  final parts = normalized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > maxMoneyMinor ~/ 100) {
    throw const FormatException('Amount too large');
  }
  final amount =
      whole * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  if (amount <= 0 || amount > maxMoneyMinor) {
    throw const FormatException('Amount must be positive');
  }
  return amount;
}

String formatMoneyMinor(int value) {
  final amount = value.abs();
  return '${value < 0 ? '-' : ''}${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';
}
