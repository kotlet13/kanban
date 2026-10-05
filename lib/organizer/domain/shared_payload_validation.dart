import 'dart:convert';
import 'collaboration_models.dart';

bool isSharedUuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value);

void validateSharedText(Object? value, int bytes, {bool empty = false}) {
  if (value is! String ||
      value.contains('\u0000') ||
      utf8.encode(value).length > bytes ||
      (!empty && value.trim().isEmpty)) {
    throw const CollaborationException('validation_error');
  }
}

void validateSharedPayload(
  SharedRecordType type,
  Map<String, dynamic> payload, {
  int? contractVersion,
  bool personal = false,
}) {
  final version = contractVersion ?? (payload.containsKey('startAt') ? 2 : 1);
  final keys = <String>{
    'title',
    'createdAt',
    'updatedAt',
    ...switch (type) {
      SharedRecordType.project => [
        'description',
        'area',
        if (version >= 2) ...['startAt', 'endAt'],
      ],
      SharedRecordType.task => [
        'notes',
        'projectId',
        'dueAt',
        'isCompleted',
        if (version >= 2) ...['startAt', 'endAt', 'assigneeAccountIds'],
      ],
      SharedRecordType.shoppingList => <String>[],
      SharedRecordType.shoppingItem => ['listId', 'quantity', 'isChecked'],
      SharedRecordType.event => [
        'notes',
        'projectId',
        'startAt',
        'endAt',
        'assigneeAccountIds',
      ],
    },
  };
  if (payload.length != keys.length ||
      !payload.keys.every(keys.contains) ||
      utf8
              .encode(
                jsonEncode(payload)
                    .replaceAll('/', r'\/')
                    .replaceAll('\u2028', r'\u2028')
                    .replaceAll('\u2029', r'\u2029'),
              )
              .length >
          (personal ? 524288 : 8192)) {
    throw const CollaborationException('validation_error');
  }
  validateSharedText(payload['title'], personal ? 2000 : 300);
  if (personal && (payload['title'] as String).length > 500) {
    throw const CollaborationException('validation_error');
  }
  void date(Object? value, {bool nullable = false}) {
    if (nullable && value == null) return;
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$',
        ).hasMatch(value)) {
      throw const CollaborationException('validation_error');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year != int.parse(value.substring(0, 4)) ||
        parsed.month != int.parse(value.substring(5, 7)) ||
        parsed.day != int.parse(value.substring(8, 10)) ||
        parsed.toUtc().toIso8601String().substring(0, 19) !=
            value.substring(0, 19)) {
      throw const CollaborationException('validation_error');
    }
  }

  date(payload['createdAt']);
  date(payload['updatedAt']);
  if (version >= 2 &&
      (type == SharedRecordType.task ||
          type == SharedRecordType.project ||
          type == SharedRecordType.event)) {
    date(payload['startAt'], nullable: type != SharedRecordType.event);
    date(payload['endAt'], nullable: true);
    if (payload['startAt'] != null &&
        payload['endAt'] != null &&
        DateTime.parse(
          payload['endAt'] as String,
        ).isBefore(DateTime.parse(payload['startAt'] as String))) {
      throw const CollaborationException('validation_error');
    }
    if (type != SharedRecordType.project) {
      final a = payload['assigneeAccountIds'];
      if (a is! List ||
          a.length > 20 ||
          !a.every(isSharedUuid) ||
          a.toSet().length != a.length) {
        throw const CollaborationException('validation_error');
      }
    }
  }
  switch (type) {
    case SharedRecordType.event:
      validateSharedText(
        payload['notes'],
        personal ? 200000 : 4096,
        empty: true,
      );
      if (personal && (payload['notes'] as String).length > 50000) {
        throw const CollaborationException('validation_error');
      }
      if (payload['projectId'] != null && !isSharedUuid(payload['projectId'])) {
        throw const CollaborationException('validation_error');
      }
    case SharedRecordType.project:
      validateSharedText(
        payload['description'],
        personal ? 200000 : 4096,
        empty: true,
      );
      if (personal && (payload['description'] as String).length > 50000) {
        throw const CollaborationException('validation_error');
      }
      if (!['personal', 'home'].contains(payload['area'])) {
        throw const CollaborationException('validation_error');
      }
    case SharedRecordType.task:
      validateSharedText(
        payload['notes'],
        personal ? 200000 : 4096,
        empty: true,
      );
      if (personal && (payload['notes'] as String).length > 50000) {
        throw const CollaborationException('validation_error');
      }
      if (payload['projectId'] != null && !isSharedUuid(payload['projectId'])) {
        throw const CollaborationException('validation_error');
      }
      date(payload['dueAt'], nullable: true);
      if (payload['isCompleted'] is! bool) {
        throw const CollaborationException('validation_error');
      }
    case SharedRecordType.shoppingList:
      break;
    case SharedRecordType.shoppingItem:
      validateSharedText(
        payload['quantity'],
        personal ? 400 : 100,
        empty: true,
      );
      if (personal && (payload['quantity'] as String).length > 100) {
        throw const CollaborationException('validation_error');
      }
      if (!isSharedUuid(payload['listId']) || payload['isChecked'] is! bool) {
        throw const CollaborationException('validation_error');
      }
  }
}
