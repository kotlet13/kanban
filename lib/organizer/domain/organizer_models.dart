import 'dart:math';
import 'organizer_snapshot.dart' show supportedCurrencies, maxMoneyMinor;
export 'household_person.dart';

// Immutable records in the personal local workspace. No remote identity is implied.
export 'organizer_snapshot.dart';

part 'planning_models.dart';
part 'finance_planning_models.dart';

const _unset = Object();

enum FinanceEntryKind { income, expense }

enum ProjectArea { personal, home }

class LocalProject {
  LocalProject({
    Iterable<ProjectPhase> phases = const [],
    this.availabilityMinutes,
    this.availabilityPeriod,
    this.revision = 0,
    this.startAt,
    this.endAt,
    this.createdByAccountId,
    this.updatedByAccountId,
    this.area = ProjectArea.personal,
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  }) : phases = List.unmodifiable(phases);

  final List<ProjectPhase> phases;
  final int? availabilityMinutes;
  final AvailabilityPeriod? availabilityPeriod;
  final String id;
  final String title;
  final String description;
  final ProjectArea area;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int revision;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? createdByAccountId;
  final String? updatedByAccountId;

  LocalProject copyWith({
    Iterable<ProjectPhase>? phases,
    Object? availabilityMinutes = _unset,
    Object? availabilityPeriod = _unset,
    int? revision,
    Object? startAt = _unset,
    Object? endAt = _unset,
    ProjectArea? area,
    String? title,
    String? description,
    DateTime? updatedAt,
  }) => LocalProject(
    phases: phases ?? this.phases,
    availabilityMinutes: identical(availabilityMinutes, _unset)
        ? this.availabilityMinutes
        : availabilityMinutes as int?,
    availabilityPeriod: identical(availabilityPeriod, _unset)
        ? this.availabilityPeriod
        : availabilityPeriod as AvailabilityPeriod?,
    area: area ?? this.area,
    revision: revision ?? this.revision,
    startAt: identical(startAt, _unset) ? this.startAt : startAt as DateTime?,
    endAt: identical(endAt, _unset) ? this.endAt : endAt as DateTime?,
    createdByAccountId: createdByAccountId,
    updatedByAccountId: updatedByAccountId,
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'phases': phases.map((p) => p.toJson()).toList(),
    'availabilityMinutes': availabilityMinutes,
    'availabilityPeriod': availabilityPeriod?.name,
    'startAt': startAt?.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
    'createdByAccountId': createdByAccountId,
    'updatedByAccountId': updatedByAccountId,
    'revision': revision,
    'id': id,
    'title': title,
    'description': description,
    'area': area.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory LocalProject.fromJson(Map<String, dynamic> json) => LocalProject(
    phases: (json['phases'] as List? ?? const []).map(
      (p) => ProjectPhase.fromJson(Map<String, dynamic>.from(p as Map)),
    ),
    availabilityMinutes: json['availabilityMinutes'] as int?,
    availabilityPeriod: json['availabilityPeriod'] == null
        ? null
        : AvailabilityPeriod.values.byName(
            json['availabilityPeriod'] as String,
          ),
    area: switch (readString(json, 'area')) {
      'personal' => ProjectArea.personal,
      'home' => ProjectArea.home,
      _ => throw const FormatException('Invalid project area'),
    },
    startAt: readNullableDate(json, 'startAt'),
    endAt: readNullableDate(json, 'endAt'),
    createdByAccountId: readNullableString(json, 'createdByAccountId'),
    updatedByAccountId: readNullableString(json, 'updatedByAccountId'),
    revision: readInt(json, 'revision'),
    id: readString(json, 'id'),
    title: readString(json, 'title'),
    description: readString(json, 'description'),
    createdAt: readDate(json, 'createdAt'),
    updatedAt: readDate(json, 'updatedAt'),
  );
}

class LocalTask {
  LocalTask({
    this.phaseId,
    this.estimateMinutes,
    this.availabilityMinutes,
    this.availabilityPeriod,
    this.timer = const TaskTimerState(),
    this.assigneePersonId,
    Iterable<String> subjectPersonIds = const [],
    Iterable<String> assigneeAccountIds = const [],
    this.revision = 0,
    this.startAt,
    this.endAt,
    this.createdByAccountId,
    this.updatedByAccountId,
    required this.id,
    required this.title,
    required this.notes,
    required this.projectId,
    required this.dueAt,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
  }) : assigneeAccountIds = List.unmodifiable(assigneeAccountIds),
       subjectPersonIds = List.unmodifiable(subjectPersonIds);

  final String? phaseId, assigneePersonId;
  final int? estimateMinutes, availabilityMinutes;
  final AvailabilityPeriod? availabilityPeriod;
  final TaskTimerState timer;
  final List<String> subjectPersonIds;
  final List<String> assigneeAccountIds;
  final String id;
  final String title;
  final String notes;
  final String? projectId;
  final DateTime? dueAt;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int revision;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? createdByAccountId;
  final String? updatedByAccountId;

  LocalTask copyWith({
    Object? phaseId = _unset,
    Object? estimateMinutes = _unset,
    Object? availabilityMinutes = _unset,
    Object? availabilityPeriod = _unset,
    Object? assigneePersonId = _unset,
    Iterable<String>? subjectPersonIds,
    TaskTimerState? timer,
    Iterable<String>? assigneeAccountIds,
    int? revision,
    Object? startAt = _unset,
    Object? endAt = _unset,
    String? title,
    String? notes,
    Object? projectId = _unset,
    Object? dueAt = _unset,
    bool? isCompleted,
    DateTime? updatedAt,
  }) => LocalTask(
    phaseId: identical(phaseId, _unset) ? this.phaseId : phaseId as String?,
    estimateMinutes: identical(estimateMinutes, _unset)
        ? this.estimateMinutes
        : estimateMinutes as int?,
    availabilityMinutes: identical(availabilityMinutes, _unset)
        ? this.availabilityMinutes
        : availabilityMinutes as int?,
    availabilityPeriod: identical(availabilityPeriod, _unset)
        ? this.availabilityPeriod
        : availabilityPeriod as AvailabilityPeriod?,
    assigneePersonId: identical(assigneePersonId, _unset)
        ? this.assigneePersonId
        : assigneePersonId as String?,
    subjectPersonIds: subjectPersonIds ?? this.subjectPersonIds,
    timer: timer ?? this.timer,
    assigneeAccountIds: assigneeAccountIds ?? this.assigneeAccountIds,
    revision: revision ?? this.revision,
    startAt: identical(startAt, _unset) ? this.startAt : startAt as DateTime?,
    endAt: identical(endAt, _unset) ? this.endAt : endAt as DateTime?,
    createdByAccountId: createdByAccountId,
    updatedByAccountId: updatedByAccountId,
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    projectId: identical(projectId, _unset)
        ? this.projectId
        : projectId as String?,
    dueAt: identical(dueAt, _unset) ? this.dueAt : dueAt as DateTime?,
    isCompleted: isCompleted ?? this.isCompleted,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'phaseId': phaseId,
    'estimateMinutes': estimateMinutes,
    'availabilityMinutes': availabilityMinutes,
    'availabilityPeriod': availabilityPeriod?.name,
    'timer': timer.toJson(),
    'assigneePersonId': assigneePersonId,
    'subjectPersonIds': subjectPersonIds,
    'assigneeAccountIds': assigneeAccountIds,
    'startAt': startAt?.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
    'createdByAccountId': createdByAccountId,
    'updatedByAccountId': updatedByAccountId,
    'revision': revision,
    'id': id,
    'title': title,
    'notes': notes,
    'projectId': projectId,
    'dueAt': dueAt?.toUtc().toIso8601String(),
    'isCompleted': isCompleted,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory LocalTask.fromJson(Map<String, dynamic> json) => LocalTask(
    phaseId: json['phaseId'] as String?,
    estimateMinutes: json['estimateMinutes'] as int?,
    availabilityMinutes: json['availabilityMinutes'] as int?,
    availabilityPeriod: json['availabilityPeriod'] == null
        ? null
        : AvailabilityPeriod.values.byName(
            json['availabilityPeriod'] as String,
          ),
    assigneePersonId: json['assigneePersonId'] as String?,
    subjectPersonIds: (json['subjectPersonIds'] as List? ?? const [])
        .cast<String>(),
    timer: json['timer'] == null
        ? const TaskTimerState()
        : TaskTimerState.fromJson(
            Map<String, dynamic>.from(json['timer'] as Map),
          ),
    assigneeAccountIds: json.containsKey('assigneeAccountIds')
        ? (json['assigneeAccountIds'] as List).cast<String>()
        : const [],
    startAt: readNullableDate(json, 'startAt'),
    endAt: readNullableDate(json, 'endAt'),
    createdByAccountId: readNullableString(json, 'createdByAccountId'),
    updatedByAccountId: readNullableString(json, 'updatedByAccountId'),
    revision: readInt(json, 'revision'),
    id: readString(json, 'id'),
    title: readString(json, 'title'),
    notes: readString(json, 'notes'),
    projectId: readNullableString(json, 'projectId'),
    dueAt: readNullableDate(json, 'dueAt'),
    isCompleted: readBool(json, 'isCompleted'),
    createdAt: readDate(json, 'createdAt'),
    updatedAt: readDate(json, 'updatedAt'),
  );
}

class LocalShoppingList {
  const LocalShoppingList({
    this.revision = 0,
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int revision;

  LocalShoppingList copyWith({
    int? revision,
    String? title,
    DateTime? updatedAt,
  }) => LocalShoppingList(
    revision: revision ?? this.revision,
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'revision': revision,
    'id': id,
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory LocalShoppingList.fromJson(Map<String, dynamic> json) =>
      LocalShoppingList(
        revision: readInt(json, 'revision'),
        id: readString(json, 'id'),
        title: readString(json, 'title'),
        createdAt: readDate(json, 'createdAt'),
        updatedAt: readDate(json, 'updatedAt'),
      );
}

class LocalShoppingItem {
  const LocalShoppingItem({
    this.revision = 0,
    required this.id,
    required this.listId,
    required this.title,
    required this.quantity,
    required this.isChecked,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String listId;
  final String title;
  final String quantity;
  final bool isChecked;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int revision;

  LocalShoppingItem copyWith({
    int? revision,
    String? listId,
    String? title,
    String? quantity,
    bool? isChecked,
    DateTime? updatedAt,
  }) => LocalShoppingItem(
    revision: revision ?? this.revision,
    id: id,
    listId: listId ?? this.listId,
    title: title ?? this.title,
    quantity: quantity ?? this.quantity,
    isChecked: isChecked ?? this.isChecked,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'revision': revision,
    'id': id,
    'listId': listId,
    'title': title,
    'quantity': quantity,
    'isChecked': isChecked,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory LocalShoppingItem.fromJson(Map<String, dynamic> json) =>
      LocalShoppingItem(
        revision: readInt(json, 'revision'),
        id: readString(json, 'id'),
        listId: readString(json, 'listId'),
        title: readString(json, 'title'),
        quantity: readString(json, 'quantity'),
        isChecked: readBool(json, 'isChecked'),
        createdAt: readDate(json, 'createdAt'),
        updatedAt: readDate(json, 'updatedAt'),
      );
}

class LocalEvent {
  const LocalEvent({
    this.revision = 0,
    required this.id,
    required this.title,
    required this.notes,
    required this.startsAt,
    required this.endsAt,
    required this.projectId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String notes;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? projectId;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int revision;

  LocalEvent copyWith({
    int? revision,
    String? title,
    String? notes,
    DateTime? startsAt,
    Object? endsAt = _unset,
    Object? projectId = _unset,
    DateTime? updatedAt,
  }) => LocalEvent(
    revision: revision ?? this.revision,
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    startsAt: startsAt ?? this.startsAt,
    endsAt: identical(endsAt, _unset) ? this.endsAt : endsAt as DateTime?,
    projectId: identical(projectId, _unset)
        ? this.projectId
        : projectId as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'revision': revision,
    'id': id,
    'title': title,
    'notes': notes,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt?.toUtc().toIso8601String(),
    'projectId': projectId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory LocalEvent.fromJson(Map<String, dynamic> json) => LocalEvent(
    revision: readInt(json, 'revision'),
    id: readString(json, 'id'),
    title: readString(json, 'title'),
    notes: readString(json, 'notes'),
    startsAt: readDate(json, 'startsAt'),
    endsAt: readNullableDate(json, 'endsAt'),
    projectId: readNullableString(json, 'projectId'),
    createdAt: readDate(json, 'createdAt'),
    updatedAt: readDate(json, 'updatedAt'),
  );
}

class FinanceEntry {
  const FinanceEntry({
    this.status = FinanceEntryStatus.posted,
    this.plannedAt,
    this.paidAt,
    this.taskId,
    this.ledgerAccountId,
    this.payerPersonId,
    this.recipientPersonId,
    this.createdByPersonId,
    this.recurrenceRuleId,
    this.occurrenceKey,
    this.createdByAccountId,
    this.updatedByAccountId,
    this.revision = 0,
    required this.id,
    required this.title,
    required this.amountMinor,
    required this.currency,
    required this.kind,
    required this.occurredAt,
    required this.projectId,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final FinanceEntryStatus status;
  final DateTime? plannedAt, paidAt;
  final String? taskId,
      ledgerAccountId,
      payerPersonId,
      recipientPersonId,
      createdByPersonId,
      recurrenceRuleId,
      occurrenceKey;
  final String? createdByAccountId, updatedByAccountId;
  final String id;
  final String title;
  final int amountMinor;
  final String currency;
  final FinanceEntryKind kind;
  final DateTime occurredAt;
  final String? projectId;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int revision;

  FinanceEntry copyWith({
    FinanceEntryStatus? status,
    Object? plannedAt = _unset,
    Object? paidAt = _unset,
    Object? taskId = _unset,
    Object? ledgerAccountId = _unset,
    Object? payerPersonId = _unset,
    Object? recipientPersonId = _unset,
    Object? createdByPersonId = _unset,
    Object? recurrenceRuleId = _unset,
    Object? occurrenceKey = _unset,
    int? revision,
    String? title,
    int? amountMinor,
    String? currency,
    FinanceEntryKind? kind,
    DateTime? occurredAt,
    Object? projectId = _unset,
    String? notes,
    DateTime? updatedAt,
  }) => FinanceEntry(
    status: status ?? this.status,
    plannedAt: identical(plannedAt, _unset)
        ? this.plannedAt
        : plannedAt as DateTime?,
    paidAt: identical(paidAt, _unset) ? this.paidAt : paidAt as DateTime?,
    taskId: identical(taskId, _unset) ? this.taskId : taskId as String?,
    ledgerAccountId: identical(ledgerAccountId, _unset)
        ? this.ledgerAccountId
        : ledgerAccountId as String?,
    payerPersonId: identical(payerPersonId, _unset)
        ? this.payerPersonId
        : payerPersonId as String?,
    recipientPersonId: identical(recipientPersonId, _unset)
        ? this.recipientPersonId
        : recipientPersonId as String?,
    createdByPersonId: identical(createdByPersonId, _unset)
        ? this.createdByPersonId
        : createdByPersonId as String?,
    recurrenceRuleId: identical(recurrenceRuleId, _unset)
        ? this.recurrenceRuleId
        : recurrenceRuleId as String?,
    occurrenceKey: identical(occurrenceKey, _unset)
        ? this.occurrenceKey
        : occurrenceKey as String?,
    createdByAccountId: createdByAccountId,
    updatedByAccountId: updatedByAccountId,
    revision: revision ?? this.revision,
    id: id,
    title: title ?? this.title,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    kind: kind ?? this.kind,
    occurredAt: occurredAt ?? this.occurredAt,
    projectId: identical(projectId, _unset)
        ? this.projectId
        : projectId as String?,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'status': status.name,
    'plannedAt': plannedAt?.toUtc().toIso8601String(),
    'paidAt': paidAt?.toUtc().toIso8601String(),
    'taskId': taskId,
    'ledgerAccountId': ledgerAccountId,
    'payerPersonId': payerPersonId,
    'recipientPersonId': recipientPersonId,
    'createdByPersonId': createdByPersonId,
    'recurrenceRuleId': recurrenceRuleId,
    'occurrenceKey': occurrenceKey,
    'createdByAccountId': createdByAccountId,
    'updatedByAccountId': updatedByAccountId,
    'revision': revision,
    'id': id,
    'title': title,
    'amountMinor': amountMinor,
    'currency': currency,
    'kind': kind.name,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'projectId': projectId,
    'notes': notes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory FinanceEntry.fromJson(Map<String, dynamic> json) => FinanceEntry(
    status: json['status'] == null
        ? FinanceEntryStatus.posted
        : FinanceEntryStatus.values.byName(json['status'] as String),
    plannedAt: readNullableDate(json, 'plannedAt'),
    paidAt: readNullableDate(json, 'paidAt'),
    taskId: readNullableString(json, 'taskId'),
    ledgerAccountId: readNullableString(json, 'ledgerAccountId'),
    payerPersonId: readNullableString(json, 'payerPersonId'),
    recipientPersonId: readNullableString(json, 'recipientPersonId'),
    createdByPersonId: readNullableString(json, 'createdByPersonId'),
    recurrenceRuleId: readNullableString(json, 'recurrenceRuleId'),
    occurrenceKey: readNullableString(json, 'occurrenceKey'),
    createdByAccountId: readNullableString(json, 'createdByAccountId'),
    updatedByAccountId: readNullableString(json, 'updatedByAccountId'),
    revision: readInt(json, 'revision'),
    id: readString(json, 'id'),
    title: readString(json, 'title'),
    amountMinor: readInt(json, 'amountMinor'),
    currency: readString(json, 'currency'),
    kind: readFinanceKind(json, 'kind'),
    occurredAt: readDate(json, 'occurredAt'),
    projectId: readNullableString(json, 'projectId'),
    notes: readString(json, 'notes'),
    createdAt: readDate(json, 'createdAt'),
    updatedAt: readDate(json, 'updatedAt'),
  );
}

class LocalReminder {
  const LocalReminder({
    required this.id,
    required this.taskId,
    required this.dueAt,
    required this.createdAt,
    required this.isRead,
  });

  final String id;
  final String taskId;
  final DateTime dueAt;
  final DateTime createdAt;
  final bool isRead;

  LocalReminder copyWith({String? taskId, DateTime? dueAt, bool? isRead}) =>
      LocalReminder(
        id: id,
        taskId: taskId ?? this.taskId,
        dueAt: dueAt ?? this.dueAt,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'taskId': taskId,
    'dueAt': dueAt.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'isRead': isRead,
  };

  factory LocalReminder.fromJson(Map<String, dynamic> json) => LocalReminder(
    id: readString(json, 'id'),
    taskId: readString(json, 'taskId'),
    dueAt: readDate(json, 'dueAt'),
    createdAt: readDate(json, 'createdAt'),
    isRead: readBool(json, 'isRead'),
  );
}

String readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid string: $key');
  return value;
}

String? readNullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  return readString(json, key);
}

int readInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Invalid integer: $key');
  return value;
}

bool readBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Invalid boolean: $key');
  return value;
}

DateTime readDate(Map<String, dynamic> json, String key) {
  final value = readString(json, key);
  // Backups carry explicit UTC timestamps; locale-dependent dates are rejected.
  if (!value.endsWith('Z')) throw FormatException('UTC date required: $key');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toUtc().toIso8601String() != value) {
    throw FormatException('Invalid date: $key');
  }
  return parsed.toUtc();
}

DateTime? readNullableDate(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : readDate(json, key);

FinanceEntryKind readFinanceKind(Map<String, dynamic> json, String key) =>
    switch (readString(json, key)) {
      'income' => FinanceEntryKind.income,
      'expense' => FinanceEntryKind.expense,
      _ => throw FormatException('Invalid finance kind'),
    };
