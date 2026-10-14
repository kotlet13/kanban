import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:cryptography/cryptography.dart' show Sha256;

import '../domain/organizer_models.dart';
import 'organizer_storage.dart';

part 'organizer_person_actions.dart';
part 'organizer_finance_plan_actions.dart';
part 'organizer_planning_actions.dart';

class OrganizerConflictException implements Exception {
  const OrganizerConflictException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Serializes read-modify-write operations in the single personal workspace.
/// Account binding and atomic outbox writes are owned by its injected storage.
class OrganizerRepository {
  OrganizerRepository(
    this.storage, {
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? newLocalId {
    if (storage is ObservableOrganizerStorage) {
      _storageSubscription = (storage as ObservableOrganizerStorage).changes
          .listen((_) {
            if (_accepting) unawaited(reload().catchError((Object _) {}));
          });
    }
  }
  StreamSubscription<void>? _storageSubscription;
  Future<void> reload() => _enqueue(() async {
    try {
      _snapshot = await storage.read();
      await _stampLegacyReadReminders();
      _changes.add(snapshot);
    } catch (error, stack) {
      _snapshot = null;
      _changes.addError(error, stack);
      rethrow;
    }
  });

  final OrganizerStorage storage;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  final _changes = StreamController<OrganizerSnapshot>.broadcast();
  Future<void> _tail = Future.value();
  OrganizerSnapshot? _snapshot;
  bool _closed = false;
  bool _accepting = true;
  Future<void>? _closing;

  Stream<OrganizerSnapshot> get changes => _changes.stream;
  OrganizerSnapshot get snapshot =>
      _snapshot ?? (throw StateError('Repository not initialized'));

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (!_accepting) return Future.error(StateError('Repository closing'));
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        if (_closed) throw StateError('Repository closed');
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<OrganizerSnapshot> initialize() => _enqueue(() async {
    _snapshot ??= await storage.read();
    await _stampLegacyReadReminders();
    return snapshot;
  });

  Future<void> _stampLegacyReadReminders() async {
    if (!snapshot.reminders.any((r) => r.isRead && r.readAt == null)) return;
    final now = _now();
    await _persist(
      snapshot.copyWith(
        revision: snapshot.revision + 1,
        reminders: snapshot.reminders.map(
          (r) => r.isRead && r.readAt == null ? r.copyWith(readAt: now) : r,
        ),
      ),
    );
  }

  Future<void> _change(OrganizerSnapshot Function(OrganizerSnapshot) change) =>
      _enqueue(() async {
        _snapshot ??= await storage.read();
        final previous = snapshot;
        final candidate = _withReminders(
          change(previous),
          _clock().toUtc(),
        ).copyWith(revision: previous.revision + 1);
        guardArchivedProjectWrites(previous, candidate);
        await _persist(candidate);
      });

  Future<void> _persist(
    OrganizerSnapshot candidate, {
    Future<void> Function(OrganizerSnapshot)? writer,
  }) async {
    candidate.validate();
    try {
      await (writer ?? storage.write)(candidate);
      _snapshot = await storage.read();
    } catch (error, stack) {
      // A flush error can follow a successful frame write. Reconcile with
      // readable storage before a later mutation; never overwrite it with
      // stale memory. If reading also fails, the next mutation must load again.
      _snapshot = null;
      _snapshot = await storage.read();
      _changes.add(snapshot);
      Error.throwWithStackTrace(error, stack);
    }
    _changes.add(snapshot);
  }

  DateTime _now() => _clock().toUtc();
  DateTime _updatedAt(DateTime previous) {
    final now = _now();
    return now.isBefore(previous) ? previous : now;
  }

  Future<Set<String>> deviceLocalRecordIds() => _enqueue(() async {
    if (storage is OrganizerOwnershipStorage) {
      return (storage as OrganizerOwnershipStorage).deviceLocalRecordIds();
    }
    return snapshot.workspaceKey == 'local' ? snapshot.recordIds : <String>{};
  });

  Future<void> createProject({
    required String title,
    Iterable<ProjectPhase> phases = const [],
    int? availabilityMinutes,
    AvailabilityPeriod? availabilityPeriod,
    String description = '',
    DateTime? startAt,
    DateTime? endAt,
    ProjectArea area = ProjectArea.personal,
  }) => _change((s) {
    final now = _now();
    return s.copyWith(
      projects: [
        ...s.projects,
        LocalProject(
          phases: phases,
          availabilityMinutes: availabilityMinutes,
          availabilityPeriod: availabilityPeriod,
          startAt: startAt?.toUtc(),
          endAt: endAt?.toUtc(),
          area: area,
          id: _idGenerator(),
          title: title.trim(),
          description: description,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  });

  Future<void> updateProject(LocalProject record) => _change((s) {
    final current = _find(s.projects, record.id, (v) => v.id);
    if (current.revision != record.revision ||
        current.createdAt != record.createdAt) {
      throw const OrganizerConflictException(
        'This record changed; reload before editing',
      );
    }
    final updated = record.copyWith(
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    return s.copyWith(
      projects: s.projects.map((v) => v.id == record.id ? updated : v),
      tasks: s.tasks.map(
        (t) =>
            t.projectId == record.id &&
                t.phaseId != null &&
                !updated.phases.any((p) => p.id == t.phaseId)
            ? t.copyWith(
                phaseId: null,
                revision: t.revision + 1,
                updatedAt: _updatedAt(t.updatedAt),
              )
            : t,
      ),
    );
  });

  Future<Map<String, dynamic>> previewProjectDeletion(String id) =>
      _enqueue(() async {
        if (storage is OrganizerProjectDeletionStorage) {
          return (storage as OrganizerProjectDeletionStorage)
              .previewProjectDeletion(id);
        }
        final current = await storage.read();
        final project = _find(current.projects, id, (v) => v.id);
        final tasks = current.tasks
            .where((v) => v.projectId == id)
            .map((v) => v.id)
            .toSet();
        final digest = await Sha256().hash(
          utf8.encode(jsonEncode(current.toJson())),
        );
        return {
          'scopeId': current.workspaceKey,
          'projectId': id,
          'name': project.title,
          'scopeNames': [project.title],
          'counts': {
            'projects': 1,
            'tasks': tasks.length,
            'events': current.events.where((v) => v.projectId == id).length,
            'ideas': 0,
            'photos': 0,
            'finance': current.financeEntries
                .where((v) => v.projectId == id || tasks.contains(v.taskId))
                .length,
            'other': 0,
            'gardens': 0,
            'drafts': 0,
          },
          'canDelete': true,
          'previewHash': digest.bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(),
        };
      });

  Future<void> deleteProject(String id, {String? previewHash}) =>
      _enqueue(() async {
        _snapshot ??= await storage.read();
        final previous = snapshot;
        _find(previous.projects, id, (v) => v.id);
        final tasks = previous.tasks
            .where((v) => v.projectId == id)
            .map((v) => v.id)
            .toSet();
        final candidate = _withReminders(
          previous.copyWith(
            projects: previous.projects.where((v) => v.id != id),
            tasks: previous.tasks.where((v) => !tasks.contains(v.id)),
            events: previous.events.where((v) => v.projectId != id),
            financeEntries: previous.financeEntries.where(
              (v) => v.projectId != id && !tasks.contains(v.taskId),
            ),
          ),
          _clock().toUtc(),
        ).copyWith(revision: previous.revision + 1);
        if (previewHash != null && storage is OrganizerProjectDeletionStorage) {
          await _persist(
            candidate,
            writer: (candidate) => (storage as OrganizerProjectDeletionStorage)
                .writeProjectDeletion(candidate, id, previewHash),
          );
        } else {
          if (previewHash != null) {
            final digest = await Sha256().hash(
              utf8.encode(jsonEncode((await storage.read()).toJson())),
            );
            if (digest.bytes
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join() !=
                previewHash) {
              throw const OrganizerConflictException(
                'scope_deletion_preview_changed',
              );
            }
          }
          await _persist(candidate);
        }
      });

  Future<void> createTask({
    required String title,
    String notes = '',
    String? projectId,
    DateTime? dueAt,
    DateTime? startAt,
    DateTime? endAt,
  }) => _change((s) {
    final now = _now();
    return s.copyWith(
      tasks: [
        ...s.tasks,
        LocalTask(
          id: _idGenerator(),
          title: title.trim(),
          notes: notes,
          projectId: projectId,
          startAt: startAt?.toUtc(),
          endAt: endAt?.toUtc(),
          dueAt: dueAt?.toUtc(),
          isCompleted: false,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  });

  Future<void> updateTask(LocalTask record) => _change((s) {
    final current = _find(s.tasks, record.id, (v) => v.id);
    if (current.revision != record.revision ||
        current.createdAt != record.createdAt) {
      throw const OrganizerConflictException(
        'This record changed; reload before editing',
      );
    }
    final updated = record.copyWith(
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    return s.copyWith(
      tasks: s.tasks.map((v) => v.id == record.id ? updated : v),
      financeEntries: s.financeEntries.map(
        (e) => e.taskId == record.id
            ? e.copyWith(
                plannedAt: updated.dueAt,
                projectId: updated.projectId,
                revision: e.revision + 1,
                updatedAt: _updatedAt(e.updatedAt),
              )
            : e,
      ),
    );
  });

  Future<void> deleteTask(String id) => _change((s) {
    _find(s.tasks, id, (v) => v.id);
    return s.copyWith(
      tasks: s.tasks.where((v) => v.id != id),
      financeEntries: s.financeEntries.map(
        (e) => e.taskId == id
            ? e.copyWith(
                taskId: null,
                revision: e.revision + 1,
                updatedAt: _updatedAt(e.updatedAt),
              )
            : e,
      ),
    );
  });

  Future<void> createShoppingList({required String title}) => _change((s) {
    final now = _now();
    return s.copyWith(
      shoppingLists: [
        ...s.shoppingLists,
        LocalShoppingList(
          id: _idGenerator(),
          title: title.trim(),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  });

  Future<void> updateShoppingList(LocalShoppingList record) => _change((s) {
    final current = _find(s.shoppingLists, record.id, (v) => v.id);
    if (current.revision != record.revision ||
        current.createdAt != record.createdAt) {
      throw const OrganizerConflictException(
        'This record changed; reload before editing',
      );
    }
    final updated = record.copyWith(
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    return s.copyWith(
      shoppingLists: s.shoppingLists.map(
        (v) => v.id == record.id ? updated : v,
      ),
    );
  });

  Future<void> deleteShoppingList(String id) => _change((s) {
    _find(s.shoppingLists, id, (v) => v.id);
    return s.copyWith(
      shoppingLists: s.shoppingLists.where((v) => v.id != id),
      shoppingItems: s.shoppingItems.where((v) => v.listId != id),
    );
  });

  Future<void> createShoppingItem({
    required String listId,
    required String title,
    String quantity = '1',
  }) => _change((s) {
    final now = _now();
    return s.copyWith(
      shoppingItems: [
        ...s.shoppingItems,
        LocalShoppingItem(
          id: _idGenerator(),
          listId: listId,
          title: title.trim(),
          quantity: quantity.trim(),
          isChecked: false,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  });

  Future<void> updateShoppingItem(LocalShoppingItem record) => _change((s) {
    final current = _find(s.shoppingItems, record.id, (v) => v.id);
    if (current.revision != record.revision ||
        current.createdAt != record.createdAt) {
      throw const OrganizerConflictException(
        'This record changed; reload before editing',
      );
    }
    final updated = record.copyWith(
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    return s.copyWith(
      shoppingItems: s.shoppingItems.map(
        (v) => v.id == record.id ? updated : v,
      ),
    );
  });

  Future<void> deleteShoppingItem(String id) => _change((s) {
    _find(s.shoppingItems, id, (v) => v.id);
    return s.copyWith(shoppingItems: s.shoppingItems.where((v) => v.id != id));
  });

  Future<void> createEvent({
    required String title,
    required DateTime startsAt,
    DateTime? endsAt,
    String notes = '',
    String? projectId,
  }) => _change((s) {
    final now = _now();
    return s.copyWith(
      events: [
        ...s.events,
        LocalEvent(
          id: _idGenerator(),
          title: title.trim(),
          notes: notes,
          startsAt: startsAt.toUtc(),
          endsAt: endsAt?.toUtc(),
          projectId: projectId,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  });

  Future<void> updateEvent(LocalEvent record) => _change((s) {
    final current = _find(s.events, record.id, (v) => v.id);
    if (current.revision != record.revision ||
        current.createdAt != record.createdAt) {
      throw const OrganizerConflictException(
        'This record changed; reload before editing',
      );
    }
    final updated = record.copyWith(
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    return s.copyWith(
      events: s.events.map((v) => v.id == record.id ? updated : v),
    );
  });

  Future<void> deleteEvent(String id) => _change((s) {
    _find(s.events, id, (v) => v.id);
    return s.copyWith(events: s.events.where((v) => v.id != id));
  });

  Future<void> createFinanceEntry({
    required String title,
    required int amountMinor,
    required FinanceEntryKind kind,
    required DateTime occurredAt,
    String currency = 'EUR',
    String notes = '',
    String? projectId,
    String? ledgerAccountId,
    String? expectedWorkspaceKey,
  }) => _change((s) {
    if (expectedWorkspaceKey != null) {
      _checkFinanceWorkspace(s, expectedWorkspaceKey);
    }
    if (ledgerAccountId != null &&
        !s.financeAccounts.any(
          (a) =>
              a.id == ledgerAccountId &&
              !a.archived &&
              a.currency == currency.trim().toUpperCase(),
        )) {
      throw const FormatException('Invalid active finance account');
    }
    final now = _now();
    return s.copyWith(
      financeEntries: [
        ...s.financeEntries,
        FinanceEntry(
          id: _idGenerator(),
          title: title.trim(),
          amountMinor: amountMinor,
          kind: kind,
          occurredAt: occurredAt.toUtc(),
          currency: currency.trim().toUpperCase(),
          notes: notes,
          projectId: projectId,
          ledgerAccountId: ledgerAccountId,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  });

  Future<void> updateFinanceEntry(
    FinanceEntry record, {
    String? expectedWorkspaceKey,
  }) => _change((s) {
    if (expectedWorkspaceKey != null) {
      _checkFinanceWorkspace(s, expectedWorkspaceKey);
    }
    final current = _find(s.financeEntries, record.id, (v) => v.id);
    if (current.revision != record.revision ||
        current.createdAt != record.createdAt) {
      throw const OrganizerConflictException(
        'This record changed; reload before editing',
      );
    }
    if (record.ledgerAccountId != current.ledgerAccountId &&
        record.ledgerAccountId != null &&
        !s.financeAccounts.any(
          (a) =>
              a.id == record.ledgerAccountId &&
              !a.archived &&
              a.currency == record.currency,
        )) {
      throw const FormatException('Invalid active finance account');
    }
    if (record.taskId != current.taskId ||
        record.recurrenceRuleId != current.recurrenceRuleId ||
        record.occurrenceKey != current.occurrenceKey ||
        ((current.taskId != null || current.recurrenceRuleId != null) &&
            (record.ledgerAccountId != current.ledgerAccountId ||
                record.currency != current.currency ||
                record.kind != current.kind))) {
      throw const FormatException('Linked financial identity is immutable');
    }
    if (current.recurrenceRuleId != null &&
        (record.currency != current.currency || record.kind != current.kind)) {
      throw const OrganizerConflictException(
        'Monthly rule kind and currency are immutable',
      );
    }
    if (record.paidAt != null && record.occurredAt != record.paidAt) {
      throw const FormatException('Actual date must equal payment date');
    }
    final updated = record.copyWith(
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    return s.copyWith(
      financeEntries: s.financeEntries.map(
        (v) => v.id == record.id ? updated : v,
      ),
    );
  });

  Future<void> deleteFinanceEntry(String id) => _change((s) {
    final current = _find(s.financeEntries, id, (v) => v.id);
    if (current.recurrenceRuleId != null) {
      throw const OrganizerConflictException('Manage the monthly rule');
    }
    return s.copyWith(
      financeEntries: s.financeEntries.where((v) => v.id != id),
    );
  });

  Future<void> setTaskCompleted(String id, bool completed) => _change((s) {
    final task = _find(s.tasks, id, (v) => v.id);
    return s.copyWith(
      tasks: s.tasks.map(
        (v) => v.id == id
            ? task.copyWith(
                isCompleted: completed,
                revision: task.revision + 1,
                updatedAt: _updatedAt(task.updatedAt),
              )
            : v,
      ),
    );
  });

  Future<void> setShoppingItemChecked(String id, bool checked) => _change((s) {
    final item = _find(s.shoppingItems, id, (v) => v.id);
    return s.copyWith(
      shoppingItems: s.shoppingItems.map(
        (v) => v.id == id
            ? item.copyWith(
                isChecked: checked,
                revision: item.revision + 1,
                updatedAt: _updatedAt(item.updatedAt),
              )
            : v,
      ),
    );
  });

  Future<void> markReminderRead(
    String id, {
    bool read = true,
    bool Function()? stillVisible,
  }) => _change((s) {
    if (stillVisible != null && !stillVisible()) {
      throw const OrganizerConflictException('Reminder is no longer visible');
    }
    _find(s.reminders, id, (v) => v.id);
    return s.copyWith(
      reminders: s.reminders.map(
        (v) => v.id == id
            ? v.copyWith(isRead: read, readAt: read ? v.readAt ?? _now() : null)
            : v,
      ),
    );
  });

  Future<void> refreshReminders() => _enqueue(() async {
    _snapshot ??= await storage.read();
    final next = _withReminders(snapshot, _now());
    if (next.reminders.length == snapshot.reminders.length &&
        next.reminders.every(
          (v) => snapshot.reminders.any((old) => identical(v, old)),
        )) {
      return;
    }
    final candidate = next.copyWith(revision: snapshot.revision + 1);
    await _persist(candidate);
  });

  Future<String> exportBackup() => _enqueue(() async {
    _snapshot = await storage.read();
    if (storage is PersonalJsonBackupStorage) {
      return (storage as PersonalJsonBackupStorage).exportPersonalJsonBackup();
    }
    return OrganizerBackupCodec.encode(snapshot);
  });

  /// Validates every imported record before writing. Existing records are
  /// never overwritten; any ID collision explicitly rejects the entire import.
  Future<void> importBackup(String json) async {
    final document = OrganizerBackupCodec.decodeDocument(json);
    if (storage is PersonalJsonBackupStorage) {
      return _enqueue(() async {
        await (storage as PersonalJsonBackupStorage).importPersonalJsonBackup(
          json,
        );
        _snapshot = await storage.read();
        _changes.add(snapshot);
      });
    }
    if (document.gardens != null) {
      throw const FormatException('This storage cannot restore garden data');
    }
    final imported = document.personal;
    return _change((s) {
      if (s.recordIds.intersection(imported.recordIds).isNotEmpty) {
        throw const OrganizerConflictException(
          'Backup IDs already exist in this workspace',
        );
      }
      return s.copyWith(
        people: [...s.people, ...imported.people],
        financeAccounts: [...s.financeAccounts, ...imported.financeAccounts],
        financeRecurrenceRules: [
          ...s.financeRecurrenceRules,
          ...imported.financeRecurrenceRules,
        ],
        projects: [...s.projects, ...imported.projects],
        tasks: [...s.tasks, ...imported.tasks],
        shoppingLists: [...s.shoppingLists, ...imported.shoppingLists],
        shoppingItems: [...s.shoppingItems, ...imported.shoppingItems],
        events: [...s.events, ...imported.events],
        financeEntries: [...s.financeEntries, ...imported.financeEntries],
        reminders: [...s.reminders, ...imported.reminders],
      );
    });
  }

  Future<void> close() {
    _accepting = false;
    return _closing ??= () async {
      await _tail;
      _closed = true;
      await _changes.close();
      await _storageSubscription?.cancel();
      await storage.close();
    }();
  }
}

T _find<T>(Iterable<T> records, String id, String Function(T) getId) =>
    records.firstWhere(
      (v) => getId(v) == id,
      orElse: () =>
          throw const OrganizerConflictException('Record no longer exists'),
    );

OrganizerSnapshot _withReminders(OrganizerSnapshot snapshot, DateTime now) {
  final previous = {
    for (final reminder in snapshot.reminders) reminder.id: reminder,
  };
  final reminders = <LocalReminder>[];
  for (final task in snapshot.tasks) {
    if (!task.isCompleted &&
        task.dueAt != null &&
        (!task.dueAt!.isAfter(now) || previous.containsKey(reminderId(task)))) {
      final id = reminderId(task);
      reminders.add(
        (previous[id]?.isRead == true && previous[id]?.readAt == null
                ? previous[id]!.copyWith(readAt: now)
                : previous[id]) ??
            LocalReminder(
              id: id,
              taskId: task.id,
              dueAt: task.dueAt!,
              createdAt: now,
              isRead: false,
            ),
      );
    }
  }
  return snapshot.copyWith(reminders: reminders);
}

/// UUID v4 identity generated without a server, clock, or account.
String newLocalId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Archive protects every descendant mutation, including an editor opened before
/// archiving. Restoring or deleting the whole closed project remains possible.
void guardArchivedProjectWrites(
  OrganizerSnapshot before,
  OrganizerSnapshot after,
) {
  final archived = before.projects
      .where((p) => p.archived)
      .map((p) => p.id)
      .toSet();
  final afterProjects = {for (final p in after.projects) p.id: p};
  final locked = {
    ...archived,
    ...after.projects.where((p) => p.archived).map((p) => p.id),
  };
  for (final project in before.projects.where((p) => p.archived)) {
    final next = afterProjects[project.id];
    if (next == null) continue;
    Map<String, Object?> fields(LocalProject p) =>
        Map<String, Object?>.from(p.toJson())
          ..remove('archived')
          ..remove('revision')
          ..remove('updatedAt');
    if (jsonEncode(fields(project)) != jsonEncode(fields(next))) {
      throw const OrganizerConflictException('Project is archived');
    }
  }
  final lockedTasks = {
    ...before.tasks.where((t) => locked.contains(t.projectId)).map((t) => t.id),
    ...after.tasks.where((t) => locked.contains(t.projectId)).map((t) => t.id),
  };
  for (final pair in [
    (before.tasks.map((r) => r.toJson()), after.tasks.map((r) => r.toJson())),
    (before.events.map((r) => r.toJson()), after.events.map((r) => r.toJson())),
    (
      before.financeEntries.map((r) => r.toJson()),
      after.financeEntries.map((r) => r.toJson()),
    ),
  ]) {
    final old = {for (final row in pair.$1) row['id']: row},
        next = {for (final row in pair.$2) row['id']: row};
    for (final id in {...old.keys, ...next.keys}) {
      final prior = old[id], candidate = next[id];
      final wasLocked =
              locked.contains(prior?['projectId']) ||
              lockedTasks.contains(prior?['taskId']),
          isLocked =
              locked.contains(candidate?['projectId']) ||
              lockedTasks.contains(candidate?['taskId']);
      if (!wasLocked && !isLocked ||
          jsonEncode(prior) == jsonEncode(candidate)) {
        continue;
      }
      final deletedParent =
          prior?['projectId'] ??
          before.tasks
              .where((t) => t.id == prior?['taskId'])
              .firstOrNull
              ?.projectId;
      if (prior != null &&
          candidate == null &&
          deletedParent is String &&
          !afterProjects.containsKey(deletedParent)) {
        continue;
      }
      throw const OrganizerConflictException('Project is archived');
    }
  }
}
