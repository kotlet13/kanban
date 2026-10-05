import 'shared_dates.dart';
import 'organizer_models.dart';

const _unsetEvent = Object();

class SharedEvent {
  SharedEvent({
    required this.id,
    this.revision = 0,
    required this.title,
    this.notes = '',
    required this.startAt,
    this.endAt,
    this.projectId,
    Iterable<String> assigneeAccountIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.createdByAccountId,
    this.updatedByAccountId,
  }) : assigneeAccountIds = List.unmodifiable(assigneeAccountIds);
  final String id, title, notes;
  final int revision;
  final DateTime startAt, createdAt, updatedAt;
  final DateTime? endAt;
  final String? projectId, createdByAccountId, updatedByAccountId;
  final List<String> assigneeAccountIds;
  SharedEvent copyWith({
    int? revision,
    String? title,
    String? notes,
    DateTime? startAt,
    Object? endAt = _unsetEvent,
    Object? projectId = _unsetEvent,
    Iterable<String>? assigneeAccountIds,
    DateTime? updatedAt,
  }) => SharedEvent(
    id: id,
    revision: revision ?? this.revision,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    startAt: startAt ?? this.startAt,
    endAt: identical(endAt, _unsetEvent) ? this.endAt : endAt as DateTime?,
    projectId: identical(projectId, _unsetEvent)
        ? this.projectId
        : projectId as String?,
    assigneeAccountIds: assigneeAccountIds ?? this.assigneeAccountIds,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdByAccountId: createdByAccountId,
    updatedByAccountId: updatedByAccountId,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'revision': revision,
    'title': title,
    'notes': notes,
    'startAt': startAt.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
    'projectId': projectId,
    'assigneeAccountIds': assigneeAccountIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'createdByAccountId': createdByAccountId,
    'updatedByAccountId': updatedByAccountId,
  };
  factory SharedEvent.fromJson(Map<String, dynamic> j) => SharedEvent(
    id: readString(j, 'id'),
    revision: readInt(j, 'revision'),
    title: readString(j, 'title'),
    notes: readString(j, 'notes'),
    startAt: readSharedDate(j, 'startAt'),
    endAt: readNullableSharedDate(j, 'endAt'),
    projectId: readNullableString(j, 'projectId'),
    assigneeAccountIds: (j['assigneeAccountIds'] as List).cast<String>(),
    createdAt: readSharedDate(j, 'createdAt'),
    updatedAt: readSharedDate(j, 'updatedAt'),
    createdByAccountId: readNullableString(j, 'createdByAccountId'),
    updatedByAccountId: readNullableString(j, 'updatedByAccountId'),
  );
}
