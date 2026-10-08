part of 'organizer_models.dart';

enum AvailabilityPeriod { day, week }

enum FinanceEntryStatus { planned, posted }

class ProjectPhase {
  const ProjectPhase({
    required this.id,
    required this.title,
    this.milestone = '',
    this.startAt,
    this.endAt,
  });
  final String id, title, milestone;
  final DateTime? startAt, endAt;
  ProjectPhase copyWith({
    String? title,
    String? milestone,
    Object? startAt = _unset,
    Object? endAt = _unset,
  }) => ProjectPhase(
    id: id,
    title: title ?? this.title,
    milestone: milestone ?? this.milestone,
    startAt: identical(startAt, _unset) ? this.startAt : startAt as DateTime?,
    endAt: identical(endAt, _unset) ? this.endAt : endAt as DateTime?,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'milestone': milestone,
    'startAt': startAt?.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
  };
  factory ProjectPhase.fromJson(Map<String, dynamic> j) => ProjectPhase(
    id: readString(j, 'id'),
    title: readString(j, 'title'),
    milestone: j['milestone'] as String? ?? '',
    startAt: readNullableDate(j, 'startAt'),
    endAt: readNullableDate(j, 'endAt'),
  );
  void validate() {
    if (id.isEmpty ||
        id.length > 200 ||
        title.trim().isEmpty ||
        title.length > 300 ||
        milestone.length > 4096 ||
        (startAt != null && endAt != null && endAt!.isBefore(startAt!))) {
      throw const FormatException('Invalid project phase');
    }
  }
}

class TaskTimerState {
  const TaskTimerState({
    this.elapsedSeconds = 0,
    this.runningSince,
    this.runId,
  });
  final int elapsedSeconds;
  final DateTime? runningSince;
  final String? runId;
  bool get running => runningSince != null;
  int elapsedAt(DateTime now) =>
      elapsedSeconds +
      (runningSince == null
          ? 0
          : max(0, now.toUtc().difference(runningSince!).inSeconds));
  int remainingAt(int? estimateMinutes, DateTime now) =>
      max(0, (estimateMinutes ?? 0) * 60 - elapsedAt(now));
  TaskTimerState pausedAt(DateTime now) =>
      TaskTimerState(elapsedSeconds: elapsedAt(now));
  Map<String, Object?> toJson() => {
    'elapsedSeconds': elapsedSeconds,
    'runningSince': runningSince?.toUtc().toIso8601String(),
    'runId': runId,
  };
  factory TaskTimerState.fromJson(Map<String, dynamic> j) => TaskTimerState(
    elapsedSeconds: readInt(j, 'elapsedSeconds'),
    runningSince: readNullableDate(j, 'runningSince'),
    runId: readNullableString(j, 'runId'),
  );
  void validate() {
    if (elapsedSeconds < 0 ||
        elapsedSeconds > 315360000 ||
        (runningSince == null) != (runId == null) ||
        (runId != null && (runId!.isEmpty || runId!.length > 200))) {
      throw const FormatException('Invalid task timer');
    }
  }
}

void validateAvailability(int? minutes, AvailabilityPeriod? period) {
  if ((minutes == null) != (period == null) ||
      (minutes != null &&
          (minutes <= 0 ||
              minutes > (period == AvailabilityPeriod.day ? 1440 : 10080)))) {
    throw const FormatException('Invalid availability');
  }
}

class TaskCostDraft {
  const TaskCostDraft({
    required this.amountMinor,
    this.currency = 'EUR',
    this.ledgerAccountId,
    this.payerPersonId,
    this.recipientPersonId,
    this.createdByPersonId,
    this.paid = false,
    this.paidAt,
  });
  final int amountMinor;
  final String currency;
  final String? ledgerAccountId,
      payerPersonId,
      recipientPersonId,
      createdByPersonId;
  final bool paid;
  final DateTime? paidAt;
}
