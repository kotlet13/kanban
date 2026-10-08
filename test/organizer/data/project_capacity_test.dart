import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/project_capacity.dart';

final now = DateTime.utc(2026, 10, 8);
LocalProject project({
  int? capacity = 60,
  AvailabilityPeriod period = AvailabilityPeriod.day,
}) => LocalProject(
  id: 'p',
  title: 'Project',
  description: '',
  createdAt: now,
  updatedAt: now,
  availabilityMinutes: capacity,
  availabilityPeriod: capacity == null ? null : period,
);
LocalTask task(
  String id, {
  int? estimate = 60,
  int elapsed = 0,
  int? capacity,
  AvailabilityPeriod? period,
  bool complete = false,
  String projectId = 'p',
  String? phase = 'one',
  DateTime? runningSince,
}) => LocalTask(
  id: id,
  title: id,
  notes: '',
  projectId: projectId,
  phaseId: phase,
  dueAt: null,
  isCompleted: complete,
  createdAt: now,
  updatedAt: now,
  estimateMinutes: estimate,
  availabilityMinutes: capacity,
  availabilityPeriod: period,
  timer: TaskTimerState(
    elapsedSeconds: elapsed,
    runningSince: runningSince,
    runId: runningSince == null ? null : 'run',
  ),
);

void main() {
  test(
    'inherited project capacity is shared and completed work is excluded',
    () {
      final estimate = estimateProjectCapacity(project(), [
        task('a', estimate: 90, elapsed: 1800),
        task('b'),
        task('completed', estimate: 300, complete: true),
        task('foreign', projectId: 'other'),
      ], now: now);
      expect(estimate.remainingSeconds, 7200);
      expect(estimate.estimatedDays, 2);
      expect(estimate.openTaskCount, 2);
    },
  );
  test(
    'task capacity overrides project capacity and weekly capacity is averaged',
    () {
      final estimate = estimateProjectCapacity(project(), [
        task('daily', capacity: 30, period: AvailabilityPeriod.day),
        task('weekly', capacity: 210, period: AvailabilityPeriod.week),
        task('inherited'),
      ], now: now);
      expect(estimate.estimatedDays, 5);
      expect(estimate.missingAvailability, 0);
    },
  );
  test('phase excludes other phase and preserves dates and records', () {
    final p = project().copyWith(
      startAt: now,
      endAt: now.add(const Duration(days: 1)),
    );
    final a = task('phase-one');
    final estimate = estimateProjectCapacity(
      p,
      [a, task('phase-two', phase: 'two')],
      phaseId: 'one',
      now: now,
    );
    expect(estimate.estimatedDays, 1);
    expect(p.endAt, now.add(const Duration(days: 1)));
    expect(a.timer.elapsedSeconds, 0);
  });
  test('missing values never produce a misleading complete duration', () {
    final estimate = estimateProjectCapacity(project(capacity: null), [
      task('unknown-effort', estimate: null),
      task('unknown-capacity'),
    ], now: now);
    expect(estimate.missingEstimates, 1);
    expect(estimate.missingAvailability, 2);
    expect(estimate.estimatedDays, isNull);
  });
  test(
    'running time reduces remainder; exhausted timer does not complete task',
    () {
      final running = task(
        'running',
        runningSince: now.subtract(const Duration(minutes: 30)),
      );
      final estimate = estimateProjectCapacity(project(), [running], now: now);
      expect(estimate.remainingSeconds, 1800);
      expect(estimate.estimatedDays, .5);
      final expired = estimateProjectCapacity(project(capacity: null), [
        running,
      ], now: now.add(const Duration(hours: 1)));
      expect(expired.remainingSeconds, 0);
      expect(expired.estimatedDays, 0);
      expect(expired.openTaskCount, 1);
      expect(running.isCompleted, isFalse);
    },
  );
  test('empty phase and completed phase are distinct', () {
    expect(estimateProjectCapacity(project(), [], now: now).taskCount, 0);
    final done = estimateProjectCapacity(project(), [
      task('done', complete: true),
    ], now: now);
    expect(done.taskCount, 1);
    expect(done.openTaskCount, 0);
  });
}
