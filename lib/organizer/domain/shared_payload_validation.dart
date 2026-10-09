import 'dart:convert';
import 'collaboration_models.dart';
import 'garden_models.dart';

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
  final version =
      contractVersion ?? sharedPayloadContractVersion(type.name, payload);
  if (type == SharedRecordType.garden) {
    if (version != 4 ||
        personal ||
        utf8.encode(jsonEncode(payload)).length > 524288) {
      throw const CollaborationException('validation_error');
    }
    try {
      final garden = Garden.fromJson(payload);
      GardenSnapshot(gardens: [garden]).validate();
    } on Object {
      throw const CollaborationException('validation_error');
    }
    return;
  }
  final keys = <String>{
    if (type != SharedRecordType.householdPerson) 'title',
    'createdAt',
    'updatedAt',
    ...switch (type) {
      SharedRecordType.garden => <String>[],
      SharedRecordType.project => [
        'description',
        'area',
        if (version >= 2) ...['startAt', 'endAt'],
        if (version >= 3) ...[
          'phases',
          'availabilityMinutes',
          'availabilityPeriod',
        ],
      ],
      SharedRecordType.task => [
        'notes',
        'projectId',
        'dueAt',
        'isCompleted',
        if (version >= 2) ...['startAt', 'endAt', 'assigneeAccountIds'],
        if (version >= 3) ...[
          'phaseId',
          'estimateMinutes',
          'availabilityMinutes',
          'availabilityPeriod',
          'timer',
          'assigneePersonId',
          'subjectPersonIds',
        ],
      ],
      SharedRecordType.householdPerson => ['name', 'notes', 'archived'],
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
  if (type == SharedRecordType.householdPerson && version < 3) {
    throw const CollaborationException('client_upgrade_required');
  }
  final title =
      payload[type == SharedRecordType.householdPerson ? 'name' : 'title'];
  validateSharedText(title, personal ? 2000 : 300);
  if (personal && (title as String).length > 500) {
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
  if (version >= 3 &&
      (type == SharedRecordType.project || type == SharedRecordType.task)) {
    final minutes = payload['availabilityMinutes'],
        period = payload['availabilityPeriod'];
    if ((minutes == null) != (period == null) ||
        (minutes != null &&
            (minutes is! int ||
                minutes < 1 ||
                minutes > (period == 'day' ? 1440 : 10080) ||
                !const ['day', 'week'].contains(period)))) {
      throw const CollaborationException('validation_error');
    }
    if (type == SharedRecordType.project) {
      final phases = payload['phases'];
      if (phases is! List || phases.length > 200) {
        throw const CollaborationException('validation_error');
      }
      final ids = <String>{};
      for (final phase in phases) {
        if (phase is! Map ||
            phase.length != 5 ||
            !const {
              'id',
              'title',
              'milestone',
              'startAt',
              'endAt',
            }.containsAll(phase.keys) ||
            phase['id'] is! String ||
            !ids.add(phase['id'] as String)) {
          throw const CollaborationException('validation_error');
        }
        validateSharedText(phase['id'], 200);
        validateSharedText(phase['title'], 300);
        validateSharedText(phase['milestone'], 4096, empty: true);
        date(phase['startAt'], nullable: true);
        date(phase['endAt'], nullable: true);
        if (phase['startAt'] != null &&
            phase['endAt'] != null &&
            DateTime.parse(
              phase['endAt'] as String,
            ).isBefore(DateTime.parse(phase['startAt'] as String))) {
          throw const CollaborationException('validation_error');
        }
      }
    } else {
      for (final key in ['assigneePersonId']) {
        if (payload[key] != null && !isSharedUuid(payload[key])) {
          throw const CollaborationException('validation_error');
        }
      }
      if (payload['phaseId'] != null) {
        validateSharedText(payload['phaseId'], 200);
      }
      final estimate = payload['estimateMinutes'],
          people = payload['subjectPersonIds'];
      if ((estimate != null &&
              (estimate is! int || estimate < 1 || estimate > 10000000)) ||
          people is! List ||
          people.length > 20 ||
          !people.every(isSharedUuid) ||
          people.toSet().length != people.length) {
        throw const CollaborationException('validation_error');
      }
      final timer = payload['timer'];
      if (timer is! Map ||
          timer.length != 3 ||
          !const {
            'elapsedSeconds',
            'runningSince',
            'runId',
          }.containsAll(timer.keys)) {
        throw const CollaborationException('validation_error');
      }
      final elapsed = timer['elapsedSeconds'];
      if (elapsed is! int ||
          elapsed < 0 ||
          elapsed > 315360000 ||
          (timer['runningSince'] == null) != (timer['runId'] == null)) {
        throw const CollaborationException('validation_error');
      }
      if (timer['runningSince'] != null) {
        date(timer['runningSince']);
        validateSharedText(timer['runId'], 200);
      }
    }
  }
  switch (type) {
    case SharedRecordType.garden:
      return;
    case SharedRecordType.householdPerson:
      validateSharedText(
        payload['notes'],
        personal ? 200000 : 4096,
        empty: true,
      );
      if (payload['archived'] is! bool ||
          (personal && (payload['notes'] as String).length > 50000)) {
        throw const CollaborationException('validation_error');
      }
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

int sharedPayloadContractVersion(String type, Map payload) => type == 'garden'
    ? 4
    : type == 'householdPerson' ||
          payload.containsKey('phases') ||
          payload.containsKey('timer')
    ? 3
    : (payload.containsKey('startAt') ? 2 : 1);

void addRichPlanningDefaults(Map<String, dynamic> payload, String type) {
  if (type != 'project' && type != 'task') return;
  payload.putIfAbsent('availabilityMinutes', () => null);
  payload.putIfAbsent('availabilityPeriod', () => null);
  if (type == 'project') {
    payload.putIfAbsent('phases', () => <Object>[]);
  } else {
    payload.putIfAbsent('phaseId', () => null);
    payload.putIfAbsent('estimateMinutes', () => null);
    payload.putIfAbsent(
      'timer',
      () => <String, Object?>{
        'elapsedSeconds': 0,
        'runningSince': null,
        'runId': null,
      },
    );
    payload.putIfAbsent('assigneePersonId', () => null);
    payload.putIfAbsent('subjectPersonIds', () => <String>[]);
  }
}
