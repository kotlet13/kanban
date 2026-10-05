// Immutable records in the personal local workspace. No remote identity is implied.
export 'organizer_snapshot.dart';

const _unset = Object();

enum FinanceEntryKind { income, expense }

enum ProjectArea { personal, home }

class LocalProject {
  const LocalProject({
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
  });

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
    int? revision,
    Object? startAt = _unset,
    Object? endAt = _unset,
    ProjectArea? area,
    String? title,
    String? description,
    DateTime? updatedAt,
  }) => LocalProject(
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
  }) : assigneeAccountIds = List.unmodifiable(assigneeAccountIds);

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
