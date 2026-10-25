import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/shared_record_merge.dart';

void main() {
  final base = <String, dynamic>{
    'title': 'Title',
    'notes': 'Base',
    'createdAt': '2026-10-01',
    'updatedAt': '2026-10-01',
  };
  Map<String, dynamic> merge(
    Map<String, dynamic> l,
    Map<String, dynamic> r, {
    SharedRecordType type = SharedRecordType.task,
    Map<String, dynamic>? b,
  }) => mergeSharedRecordPayloads(
    type: type,
    base: b ?? base,
    local: l,
    remote: r,
  );
  test('independent fields merge and timestamp does not conflict', () {
    final result = merge(
      {...base, 'notes': 'Local', 'updatedAt': '2026-10-02'},
      {...base, 'title': 'Remote', 'updatedAt': '2026-10-03'},
    );
    expect(result['notes'], 'Local');
    expect(result['title'], 'Remote');
  });
  test('equal field edits converge without conflict', () {
    final result = merge(
      {...base, 'notes': 'Same'},
      {...base, 'notes': 'Same'},
    );
    expect(
      equivalentSharedRecordPayloads(result, {
        ...base,
        'notes': 'Same',
        'updatedAt': 'later',
      }),
      isTrue,
    );
  });
  test('opposing field edits preserve manual conflict', () {
    expect(
      () => merge({...base, 'notes': 'Local'}, {...base, 'notes': 'Remote'}),
      throwsA(isA<SharedRecordMergeConflict>()),
    );
  });
  test('event interval is coupled even when separate endpoints changed', () {
    final b = {
      ...base,
      'startAt': '2026-10-01T10:00:00Z',
      'endAt': '2026-10-01T11:00:00Z',
    };
    expect(
      () => merge(
        {...b, 'startAt': '2026-10-01T09:00:00Z'},
        {...b, 'endAt': '2026-10-01T12:00:00Z'},
        b: b,
        type: SharedRecordType.event,
      ),
      throwsA(isA<SharedRecordMergeConflict>()),
    );
  });
  test('task project and phase cannot silently cross during merge', () {
    final b = {...base, 'projectId': 'one', 'phaseId': 'old'};
    expect(
      () => merge({...b, 'projectId': 'two'}, {...b, 'phaseId': 'new'}, b: b),
      throwsA(isA<SharedRecordMergeConflict>()),
    );
  });
  test('timer object has one conflict decision', () {
    final b = {
      ...base,
      'timer': {'elapsed': 1, 'running': false},
    };
    expect(
      () => merge(
        {
          ...b,
          'timer': {'elapsed': 2, 'running': false},
        },
        {
          ...b,
          'timer': {'elapsed': 1, 'running': true},
        },
        b: b,
      ),
      throwsA(isA<SharedRecordMergeConflict>()),
    );
  });
  test('older missing field preserves newer accepted extension', () {
    final b = {...base, 'dueAt': null};
    final result = merge(
      {...base, 'notes': 'Local'},
      {...b, 'dueAt': '2026-11-01'},
      b: b,
    );
    expect(result['dueAt'], '2026-11-01');
    expect(result['notes'], 'Local');
  });
  test('creation timestamp mutation never auto merges', () {
    expect(
      () => merge({...base, 'createdAt': '2026-10-02'}, base),
      throwsA(isA<SharedRecordMergeConflict>()),
    );
  });
  test('garden stays a specialized whole document conflict', () {
    expect(
      () => merge(base, base, type: SharedRecordType.garden),
      throwsA(isA<SharedRecordMergeConflict>()),
    );
  });
  test(
    'new older remote serializer omission preserves unchanged base field',
    () {
      final remote = Map<String, dynamic>.from(base)..remove('notes');
      final result = merge({...base, 'title': 'Local'}, remote);
      expect(result['notes'], 'Base');
      expect(result['title'], 'Local');
    },
  );
}
