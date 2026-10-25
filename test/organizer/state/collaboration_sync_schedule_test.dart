import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_sync_status.dart';
import 'package:kanban/organizer/state/collaboration_sync_schedule.dart';

void main() {
  final start = DateTime.utc(2026, 10, 19);
  const empty = CollaborationSyncWork('[]', unresolved: false);
  const pending = CollaborationSyncWork('op1:1:pending', unresolved: true);
  CollaborationSyncCompletion result(
    int sequence, {
    DateTime? at,
    CollaborationSyncWork work = empty,
    Object? error,
    DateTime? retryAt,
    String identity = 'A:epoch1',
  }) => CollaborationSyncCompletion(
    sequence: sequence,
    identity: identity,
    at: at ?? start,
    work: work,
    error: error,
    retryAt: retryAt,
  );
  CollaborationSyncSchedule setup() =>
      CollaborationSyncSchedule()..identity('A:epoch1');

  test('first drained completion waits30 seconds without a startup burst', () {
    final s = setup();
    expect(s.due(start, busy: false), isTrue);
    s.beginAttempt();
    s.complete(result(1));
    for (final seconds in [0, 3, 12, 21, 29]) {
      expect(
        s.due(start.add(Duration(seconds: seconds)), busy: false),
        isFalse,
      );
    }
    expect(s.due(start.add(const Duration(seconds: 30)), busy: false), isTrue);
  });
  test('Mac focus burst retains original idle deadline', () {
    final s = setup()
      ..beginAttempt()
      ..complete(result(1));
    for (var second = 1; second < 30; second++) {
      s.resume(start.add(Duration(seconds: second)));
      expect(s.due(start.add(Duration(seconds: second)), busy: false), isFalse);
    }
    expect(s.nextAt, start.add(const Duration(seconds: 30)));
    s.resume(start.add(const Duration(seconds: 30)));
    expect(s.due(start.add(const Duration(seconds: 30)), busy: false), isTrue);
  });
  test('initial busy demand survives skipped attempt', () {
    final s = setup();
    expect(s.due(start, busy: true), isFalse);
    s.resume(start);
    expect(s.due(start, busy: false), isTrue);
  });
  test(
    'new work arriving during busy attempt is not consumed while unresolved',
    () {
      final s = setup()
        ..work(pending)
        ..beginAttempt();
      s.localEdit();
      expect(s.due(start, busy: true), isFalse);
      s.complete(result(1, work: pending));
      expect(s.due(start, busy: false), isTrue);
      s.beginAttempt();
      s.complete(result(2, work: pending));
      expect(s.due(start, busy: false), isFalse);
    },
  );
  test(
    'new demand remains even when current completion drained older work',
    () {
      final s = setup()
        ..beginAttempt()
        ..localEdit();
      s.complete(result(1));
      expect(s.due(start, busy: false), isTrue);
    },
  );
  test(
    'same-count replacement IDs and linked intent transitions wake once',
    () {
      final s = setup()
        ..work(pending)
        ..beginAttempt();
      s.complete(result(1, work: pending));
      s.work(const CollaborationSyncWork('op2:2:pending', unresolved: true));
      expect(s.due(start, busy: false), isTrue);
      s.beginAttempt();
      const retained = CollaborationSyncWork(
        'payment:complete',
        unresolved: false,
      );
      s.complete(result(2, work: retained));
      s.work(retained);
      expect(s.due(start, busy: false), isFalse);
      s.work(
        const CollaborationSyncWork(
          'payment:waiting_source_publication',
          unresolved: true,
        ),
      );
      expect(s.due(start, busy: false), isTrue);
    },
  );
  for (final isError in [true, false]) {
    test(
      'unchanged ${isError ? 'error' : 'pending'} uses15 then30 then60 bound',
      () {
        final s = setup();
        var at = start;
        for (var i = 1; i <= 4; i++) {
          s.beginAttempt();
          s.complete(
            result(
              i,
              at: at,
              work: pending,
              error: isError ? StateError('offline') : null,
            ),
          );
          final seconds = i == 1
              ? 15
              : i == 2
              ? 30
              : 60;
          expect(s.nextAt, at.add(Duration(seconds: seconds)));
          s.resume(at.add(const Duration(seconds: 1)));
          expect(
            s.due(at.add(const Duration(seconds: 1)), busy: false),
            isFalse,
          );
          at = s.nextAt!;
        }
      },
    );
  }
  test('valid retry minimum dominates local edit and scheduled cadence', () {
    final retry = start.add(const Duration(hours: 24));
    final s = setup()
      ..complete(result(1, error: StateError('limited'), retryAt: retry));
    s.localEdit();
    s.resume(start.add(const Duration(seconds: 30)));
    expect(
      s.due(retry.subtract(const Duration(seconds: 1)), busy: false),
      isFalse,
    );
    expect(s.due(retry, busy: false), isTrue);
  });
  test(
    'old identity and late duplicate outcomes cannot overwrite deadlines',
    () {
      final s = setup()..complete(result(2));
      expect(s.complete(result(1, error: StateError('late'))), isFalse);
      expect(s.complete(result(3, identity: 'B:epoch2')), isFalse);
      expect(s.nextAt, start.add(const Duration(seconds: 30)));
      s.identity('B:epoch2');
      expect(s.due(start, busy: false), isTrue);
      expect(s.retryAt, isNull);
    },
  );
  test('local edit immediate but noop ticks do not change deadline', () {
    final s = setup()..complete(result(1));
    s.work(empty);
    s.complete(result(1));
    expect(s.nextAt, start.add(const Duration(seconds: 30)));
    s.localEdit();
    expect(s.due(start, busy: false), isTrue);
  });
  test(
    'unchanged probe sets30s deadline and preserves midflight invalidation',
    () {
      final s = setup()..beginAttempt();
      s.checked(start);
      expect(
        s.due(start.add(const Duration(seconds: 29)), busy: false),
        isFalse,
      );
      expect(
        s.due(start.add(const Duration(seconds: 30)), busy: false),
        isTrue,
      );
      s.beginAttempt();
      s.localEdit();
      s.checked(start.add(const Duration(seconds: 30)));
      expect(
        s.due(start.add(const Duration(seconds: 30)), busy: false),
        isTrue,
      );
    },
  );
}
