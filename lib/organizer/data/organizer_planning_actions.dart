part of 'organizer_repository.dart';

extension OrganizerPlanningActions on OrganizerRepository {
  Future<void> saveTaskWithCost({
    required LocalTask task,
    bool isNew = false,
    TaskCostDraft? cost,
    bool removeCost = false,
    int? expectedFinanceRevision,
    required String expectedWorkspaceKey,
  }) => _change((s) {
    if (s.workspaceKey != expectedWorkspaceKey) {
      throw const OrganizerConflictException('Personal workspace changed');
    }
    final current = s.tasks.where((t) => t.id == task.id).firstOrNull;
    if (isNew
        ? current != null
        : current == null ||
              current.revision != task.revision ||
              current.createdAt != task.createdAt) {
      throw const OrganizerConflictException(
        'Task changed; reload before editing',
      );
    }
    for (final personId in [task.assigneePersonId, ...task.subjectPersonIds]) {
      if (personId != null &&
          s.people.any((p) => p.id == personId && p.archived) &&
          personId != current?.assigneePersonId &&
          !(current?.subjectPersonIds.contains(personId) ?? false)) {
        throw const FormatException(
          'Archived person cannot receive new assignments',
        );
      }
    }
    final previous = s.financeEntries
        .where((e) => e.taskId == task.id)
        .firstOrNull;
    if ((cost != null || removeCost) &&
        previous == null &&
        expectedFinanceRevision != null) {
      throw const OrganizerConflictException(
        'Task cost was removed; reload before editing',
      );
    }
    if ((cost != null || removeCost) &&
        previous != null &&
        previous.revision != expectedFinanceRevision) {
      throw const OrganizerConflictException(
        'Task cost changed; reload before editing',
      );
    }
    final now = _now();
    final saved = task.copyWith(
      title: task.title.trim(),
      notes: task.notes,
      revision: (current?.revision ?? -1) + 1,
      updatedAt: current == null
          ? task.createdAt
          : _updatedAt(current.updatedAt),
    );
    FinanceEntry? entry;
    if (previous != null && removeCost) {
      entry = previous.copyWith(
        taskId: null,
        revision: previous.revision + 1,
        updatedAt: _updatedAt(previous.updatedAt),
      );
    } else if (cost != null) {
      final paidAt =
          previous?.paidAt ?? (cost.paid ? (cost.paidAt ?? now).toUtc() : null);
      final posted = previous?.status == FinanceEntryStatus.posted || cost.paid;
      entry = FinanceEntry(
        createdByAccountId: previous?.createdByAccountId,
        updatedByAccountId: previous?.updatedByAccountId,
        id: previous?.id ?? _idGenerator(),
        revision: (previous?.revision ?? -1) + 1,
        title: saved.title,
        amountMinor: cost.amountMinor,
        currency: cost.currency,
        kind: FinanceEntryKind.expense,
        status: posted ? FinanceEntryStatus.posted : FinanceEntryStatus.planned,
        taskId: saved.id,
        projectId: saved.projectId,
        plannedAt: saved.dueAt,
        paidAt: paidAt,
        occurredAt: previous?.status == FinanceEntryStatus.posted
            ? previous!.occurredAt
            : paidAt ?? saved.dueAt ?? now,
        ledgerAccountId: cost.ledgerAccountId,
        payerPersonId: cost.payerPersonId,
        recipientPersonId: cost.recipientPersonId,
        createdByPersonId:
            previous?.createdByPersonId ?? cost.createdByPersonId,
        notes: previous?.notes ?? '',
        createdAt: previous?.createdAt ?? now,
        updatedAt: previous == null ? now : _updatedAt(previous.updatedAt),
      );
    } else if (previous != null) {
      entry = previous.copyWith(
        plannedAt: saved.dueAt,
        projectId: saved.projectId,
        revision: previous.revision + 1,
        updatedAt: _updatedAt(previous.updatedAt),
      );
    }
    return s.copyWith(
      tasks: isNew
          ? [...s.tasks, saved]
          : s.tasks.map((t) => t.id == saved.id ? saved : t),
      financeEntries: [
        for (final e in s.financeEntries)
          if (e.id != previous?.id) e,
        if (entry != null) entry,
      ],
    );
  });

  Future<void> startTaskTimer(
    String id, {
    required int expectedRevision,
    required String expectedWorkspaceKey,
  }) => _enqueue(() async {
    _snapshot ??= await storage.read();
    final s = snapshot, task = _find(s.tasks, id, (t) => t.id);
    if (s.workspaceKey != expectedWorkspaceKey) {
      throw const OrganizerConflictException('Personal workspace changed');
    }
    if (task.timer.running) return;
    if (task.revision != expectedRevision) {
      throw const OrganizerConflictException(
        'Task changed; reload before starting timer',
      );
    }
    final now = _now();
    final tasks = s.tasks.map((t) {
      if (t.id == id) {
        return t.copyWith(
          timer: TaskTimerState(
            elapsedSeconds: t.timer.elapsedSeconds,
            runningSince: now,
            runId: _idGenerator(),
          ),
          revision: t.revision + 1,
          updatedAt: _updatedAt(t.updatedAt),
        );
      }
      if (t.timer.running) {
        return t.copyWith(
          timer: t.timer.pausedAt(now),
          revision: t.revision + 1,
          updatedAt: _updatedAt(t.updatedAt),
        );
      }
      return t;
    });
    await _persist(s.copyWith(tasks: tasks, revision: s.revision + 1));
  });

  Future<void> pauseTaskTimer(
    String id, {
    required String runId,
    required String expectedWorkspaceKey,
  }) => _enqueue(() async {
    _snapshot ??= await storage.read();
    final s = snapshot, task = _find(s.tasks, id, (t) => t.id);
    if (s.workspaceKey != expectedWorkspaceKey) {
      throw const OrganizerConflictException('Personal workspace changed');
    }
    if (!task.timer.running) return;
    if (task.timer.runId != runId) {
      throw const OrganizerConflictException(
        'Timer run changed; reload before pausing',
      );
    }
    final changed = task.copyWith(
      timer: task.timer.pausedAt(_now()),
      revision: task.revision + 1,
      updatedAt: _updatedAt(task.updatedAt),
    );
    await _persist(
      s.copyWith(
        tasks: s.tasks.map((t) => t.id == id ? changed : t),
        revision: s.revision + 1,
      ),
    );
  });
}
