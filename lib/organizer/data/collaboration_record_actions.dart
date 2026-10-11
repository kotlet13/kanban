part of 'collaboration_repository.dart';

/// Atomic local record edits, dependency ordering and explicit personal copies.
extension CollaborationRecordActions on CollaborationRepository {
  Future<void> _writable(String partition, String scopeId) async {
    final sharing = await database.rows(
      r"SELECT 1 FROM local_meta WHERE name=? OR (name LIKE ? AND json_extract(value,'$.projectId')=?)",
      [
        'project_sharing_pending:$partition:$scopeId',
        'project_sharing_pending:$partition:%',
        scopeId,
      ],
    );
    if (sharing.isNotEmpty) {
      throw const CollaborationException('project_sharing_pending_changes');
    }
    if (_sessionInvalidReason == 'device_revoked') {
      throw CollaborationException(_sessionInvalidReason!);
    }
    final rows = await database.rows(
      'SELECT data,blocked FROM scopes WHERE partition=? AND id=?',
      [partition, scopeId],
    );
    if (rows.isEmpty) throw const CollaborationException('permission_revoked');
    final scope = SharedScope.fromJson({
      ...CollaborationRepository._map(rows.first['data']),
      'blocked': rows.first['blocked'] == 1,
    });
    if (!scope.canEdit) {
      throw CollaborationException(
        scope.blocked ? 'changes_blocked' : 'permission_revoked',
      );
    }
  }

  Future<void> _edit(
    String scopeId,
    Future<void> Function(String partition) action,
  ) async {
    final profile = _requireSession().profile, epoch = _epoch;
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _writable(profile.partition, scopeId);
      await action(profile.partition);
      _checkEpoch(epoch);
    });
    await refreshLocal();
  }

  Future<Map<String, dynamic>> _record(
    String partition,
    String scope,
    String id,
  ) async {
    final rows = await database.rows(
      'SELECT * FROM records WHERE partition=? AND scope_id=? AND id=?',
      [partition, scope, id],
    );
    if (rows.isEmpty || rows.first['deleted'] == 1) {
      throw const CollaborationException('record_missing');
    }
    return rows.first;
  }

  Future<void> _put(
    String partition,
    String scope,
    SharedRecordType type,
    String id,
    Map<String, Object?>? payload, {
    int? expectedLocalRevision,
    bool deleted = false,
  }) async {
    if (!isSharedUuid(id)) {
      throw const CollaborationException('validation_error');
    }
    final scopeRow = (await database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [partition, scope],
    )).single;
    final scoped = SharedScope.fromJson(
      CollaborationRepository._map(scopeRow['data']),
    );
    if (type == SharedRecordType.garden &&
        (scoped.kind != SharedScopeKind.household ||
            _recordContractVersion < 4)) {
      throw const CollaborationException('client_upgrade_required');
    }
    final root =
        scoped.projectRootId ??
        (scoped.parentSpaceId != null ? scoped.id : null);
    if (root != null && type == SharedRecordType.project && id != root) {
      throw const CollaborationException('project_scope_single_project');
    }
    if (root != null &&
        payload != null &&
        (type == SharedRecordType.task || type == SharedRecordType.event) &&
        payload['projectId'] != root) {
      throw const CollaborationException('parent_missing');
    }
    if (payload != null) {
      validateSharedPayload(
        type,
        Map<String, dynamic>.from(payload),
        contractVersion: _recordContractVersion,
      );
      final parentId = type == SharedRecordType.shoppingItem
          ? payload['listId']
          : (type == SharedRecordType.task || type == SharedRecordType.event)
          ? payload['projectId']
          : null;
      if (parentId != null) {
        final parent = await _record(partition, scope, parentId as String);
        if (parent['type'] !=
            (type == SharedRecordType.shoppingItem
                ? 'shoppingList'
                : 'project')) {
          throw const CollaborationException('validation_error');
        }
      }
    }
    if (payload != null &&
        type == SharedRecordType.task &&
        _recordContractVersion >= 3 &&
        payload['phaseId'] != null) {
      if (payload['projectId'] == null) {
        throw const CollaborationException('parent_missing');
      }
      final project = await _record(
        partition,
        scope,
        payload['projectId'] as String,
      );
      final phases =
          CollaborationRepository._map(project['payload'])['phases'] as List? ??
          [];
      if (!phases.any((phase) => (phase as Map)['id'] == payload['phaseId'])) {
        throw const CollaborationException('parent_missing');
      }
    }
    if (payload != null &&
        type == SharedRecordType.project &&
        _recordContractVersion >= 3) {
      final phaseIds = (payload['phases'] as List)
          .map((phase) => (phase as Map)['id'])
          .toSet();
      final tasks = await database.rows(
        "SELECT payload FROM records WHERE partition=? AND scope_id=? AND type='task' AND deleted=0",
        [partition, scope],
      );
      for (final task in tasks) {
        final body = CollaborationRepository._map(task['payload']);
        if (body['projectId'] == id &&
            body['phaseId'] != null &&
            !phaseIds.contains(body['phaseId'])) {
          throw const CollaborationException('live_children');
        }
      }
    }
    final existing = await database.rows(
      'SELECT * FROM records WHERE partition=? AND scope_id=? AND id=?',
      [partition, scope, id],
    );
    final old = existing.isEmpty ? null : existing.first;
    if (deleted && old == null) {
      throw const CollaborationException('record_missing');
    }
    if (old != null && payload != null && old['payload'] != null) {
      final previous = CollaborationRepository._map(old['payload']);
      if (readSharedDate(previous, 'createdAt') !=
          readSharedDate(Map<String, dynamic>.from(payload), 'createdAt')) {
        throw const CollaborationException('validation_error');
      }
      payload['createdAt'] = previous['createdAt'];
    }
    if (old != null && (old['deleted'] == 1 || old['type'] != type.name)) {
      throw const CollaborationException('record_deleted');
    }
    if (expectedLocalRevision != null &&
        (old == null || old['local_revision'] != expectedLocalRevision)) {
      throw const CollaborationException('stale_edit');
    }
    if (type == SharedRecordType.task &&
        payload != null &&
        _recordContractVersion >= 3) {
      final previousPayload = old?['payload'] == null
          ? <String, dynamic>{}
          : CollaborationRepository._map(old!['payload']);
      Future<void> person(Object? id, bool retained) async {
        if (id == null) return;
        final row = await _record(partition, scope, id as String);
        if (row['type'] != 'householdPerson') {
          throw const CollaborationException('person_missing');
        }
        if (!retained &&
            CollaborationRepository._map(row['payload'])['archived'] == true) {
          throw const CollaborationException('person_archived');
        }
      }

      await person(
        payload['assigneePersonId'],
        payload['assigneePersonId'] == previousPayload['assigneePersonId'],
      );
      for (final id in payload['subjectPersonIds'] as List) {
        await person(
          id,
          (previousPayload['subjectPersonIds'] as List? ?? []).contains(id),
        );
      }
    }
    final queued = await database.rows(
      'SELECT state FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
      [partition, scope, id],
    );
    if (queued.any(
      (r) => r['state'] == 'conflict' || r['state'] == 'blocked',
    )) {
      throw const CollaborationException('changes_blocked');
    }
    await _reconcileLocalReminders(
      partition,
      scope,
      type.name,
      id,
      old?['payload'] == null
          ? null
          : CollaborationRepository._map(old!['payload']),
      payload == null ? null : Map<String, dynamic>.from(payload),
      deleted,
    );
    if (root != null && type == SharedRecordType.project && payload != null) {
      validateSharedText(payload['title'], 200);
      final wire = scoped.toJson()..['name'] = payload['title'];
      await database.execute(
        'UPDATE scopes SET data=? WHERE partition=? AND id=?',
        [jsonEncode(wire), partition, scope],
      );
    }
    final serverRevision = (old?['server_revision'] as int?) ?? 0;
    final request = {
      'opId': newSharedId(),
      'recordId': id,
      'type': type.name,
      'expectedRevision': serverRevision + queued.length,
      'deleted': deleted,
      'payload': payload,
    };
    await database.execute(
      'INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,id) DO UPDATE SET local_revision=excluded.local_revision,payload=excluded.payload,deleted=excluded.deleted',
      [
        partition,
        scope,
        id,
        type.name,
        ((old?['local_revision'] as int?) ?? 0) + 1,
        serverRevision,
        payload == null ? null : jsonEncode(payload),
        deleted ? 1 : 0,
      ],
    );
    await database.execute(
      'INSERT INTO outbox(op_id,partition,scope_id,record_id,request,wire_version) VALUES(?,?,?,?,?,?)',
      [
        request['opId'],
        partition,
        scope,
        id,
        jsonEncode(request),
        type == SharedRecordType.garden
            ? 4
            : (_recordContractVersion > 3 ? 3 : _recordContractVersion),
      ],
    );
  }

  Map<String, Object?> _payload(Map<String, Object?> json) {
    final value = Map<String, Object?>.of(json)
      ..remove('id')
      ..remove('revision')
      ..remove('createdByAccountId')
      ..remove('updatedByAccountId');
    if (_recordContractVersion < 3) {
      final rich = <String, Object?>{
        for (final key in [
          'phases',
          'availabilityMinutes',
          'availabilityPeriod',
          'phaseId',
          'estimateMinutes',
          'timer',
          'assigneePersonId',
          'subjectPersonIds',
        ])
          if (value.containsKey(key)) key: value[key],
      };
      if (rich.entries.any(
        (entry) =>
            entry.value != null &&
            !(entry.value is List && (entry.value as List).isEmpty) &&
            !(entry.key == 'timer' &&
                entry.value is Map &&
                (entry.value as Map)['elapsedSeconds'] == 0 &&
                (entry.value as Map)['runningSince'] == null &&
                (entry.value as Map)['runId'] == null),
      )) {
        throw const CollaborationException('client_upgrade_required');
      }
      for (final key in rich.keys) {
        value.remove(key);
      }
    }
    if (_recordContractVersion < 2) {
      if (value['startAt'] != null ||
          value['endAt'] != null ||
          (value['assigneeAccountIds'] is List &&
              (value['assigneeAccountIds'] as List).isNotEmpty)) {
        throw const CollaborationException('client_upgrade_required');
      }
      value.remove('startAt');
      value.remove('endAt');
      value.remove('assigneeAccountIds');
    }
    return value;
  }

  void _validate(SharedScopeData data) {
    for (final row in data.projects) {
      validateSharedPayload(
        SharedRecordType.project,
        Map<String, dynamic>.from(_payload(row.toJson())),
      );
    }
    for (final row in data.tasks) {
      validateSharedPayload(
        SharedRecordType.task,
        Map<String, dynamic>.from(_payload(row.toJson())),
      );
    }
    for (final row in data.shoppingLists) {
      validateSharedPayload(
        SharedRecordType.shoppingList,
        Map<String, dynamic>.from(_payload(row.toJson())),
      );
    }
    for (final row in data.shoppingItems) {
      validateSharedPayload(
        SharedRecordType.shoppingItem,
        Map<String, dynamic>.from(_payload(row.toJson())),
      );
    }
  }

  DateTime get _now => clock().toUtc();

  Future<String> createShoppingList({
    required String scopeId,
    required String title,
  }) async {
    final id = newSharedId(), now = _now;
    await _edit(scopeId, (p) async {
      final data = await _scopeData(p, scopeId);
      final row = LocalShoppingList(
        id: id,
        title: title.trim(),
        createdAt: now,
        updatedAt: now,
      );
      _validate(
        SharedScopeData(
          projects: data.projects,
          tasks: data.tasks,
          shoppingLists: [...data.shoppingLists, row],
          shoppingItems: data.shoppingItems,
        ),
      );
      await _put(
        p,
        scopeId,
        SharedRecordType.shoppingList,
        id,
        _payload(row.toJson()),
      );
    });
    return id;
  }

  Future<void> updateShoppingList(String scopeId, LocalShoppingList draft) =>
      _edit(scopeId, (p) async {
        final data = await _scopeData(p, scopeId),
            row = draft.copyWith(title: draft.title.trim(), updatedAt: _now);
        _validate(
          SharedScopeData(
            projects: data.projects,
            tasks: data.tasks,
            shoppingLists: data.shoppingLists.map(
              (r) => r.id == row.id ? row : r,
            ),
            shoppingItems: data.shoppingItems,
          ),
        );
        await _put(
          p,
          scopeId,
          SharedRecordType.shoppingList,
          row.id,
          _payload(row.toJson()),
          expectedLocalRevision: draft.revision,
        );
      });
  Future<String> createShoppingItem({
    required String scopeId,
    required String listId,
    required String title,
    String quantity = '',
  }) async {
    final id = newSharedId(), now = _now;
    await _edit(scopeId, (p) async {
      final data = await _scopeData(p, scopeId);
      final row = LocalShoppingItem(
        id: id,
        listId: listId,
        title: title.trim(),
        quantity: quantity.trim(),
        isChecked: false,
        createdAt: now,
        updatedAt: now,
      );
      _validate(
        SharedScopeData(
          projects: data.projects,
          tasks: data.tasks,
          shoppingLists: data.shoppingLists,
          shoppingItems: [...data.shoppingItems, row],
        ),
      );
      await _put(
        p,
        scopeId,
        SharedRecordType.shoppingItem,
        id,
        _payload(row.toJson()),
      );
    });
    return id;
  }

  Future<void> updateShoppingItem(String scopeId, LocalShoppingItem draft) =>
      _edit(scopeId, (p) async {
        final data = await _scopeData(p, scopeId),
            row = draft.copyWith(
              title: draft.title.trim(),
              quantity: draft.quantity.trim(),
              updatedAt: _now,
            );
        _validate(
          SharedScopeData(
            projects: data.projects,
            tasks: data.tasks,
            shoppingLists: data.shoppingLists,
            shoppingItems: data.shoppingItems.map(
              (r) => r.id == row.id ? row : r,
            ),
          ),
        );
        await _put(
          p,
          scopeId,
          SharedRecordType.shoppingItem,
          row.id,
          _payload(row.toJson()),
          expectedLocalRevision: draft.revision,
        );
      });
  Future<void> setShoppingItemChecked(String scopeId, String id, bool value) =>
      _edit(scopeId, (p) async {
        final r = await _record(p, scopeId, id),
            row = LocalShoppingItem.fromJson({
              ...CollaborationRepository._map(r['payload']),
              'id': id,
              'revision': r['local_revision'],
            }).copyWith(isChecked: value, updatedAt: _now);
        await _put(
          p,
          scopeId,
          SharedRecordType.shoppingItem,
          id,
          _payload(row.toJson()),
          expectedLocalRevision: row.revision,
        );
      });
  Future<void> deleteShoppingItem(String scopeId, String id) => _edit(
    scopeId,
    (p) => _put(
      p,
      scopeId,
      SharedRecordType.shoppingItem,
      id,
      null,
      deleted: true,
    ),
  );
  Future<void> deleteShoppingList(String scopeId, String id) =>
      _edit(scopeId, (p) async {
        final data = await _scopeData(p, scopeId);
        for (final item in data.shoppingItems.where((r) => r.listId == id)) {
          await _put(
            p,
            scopeId,
            SharedRecordType.shoppingItem,
            item.id,
            null,
            deleted: true,
          );
        }
        await _put(
          p,
          scopeId,
          SharedRecordType.shoppingList,
          id,
          null,
          deleted: true,
        );
      });
  Future<String> createProject({
    required String scopeId,
    required String title,
    String description = '',
    DateTime? startAt,
    DateTime? endAt,
    ProjectArea area = ProjectArea.home,
    Iterable<ProjectPhase> phases = const [],
    int? availabilityMinutes,
    AvailabilityPeriod? availabilityPeriod,
  }) async {
    final id = newSharedId(), now = _now;
    await _edit(scopeId, (p) async {
      final data = await _scopeData(p, scopeId);
      final row = LocalProject(
        id: id,
        title: title.trim(),
        description: description.trim(),
        startAt: startAt?.toUtc(),
        endAt: endAt?.toUtc(),
        area: area,
        phases: phases,
        availabilityMinutes: availabilityMinutes,
        availabilityPeriod: availabilityPeriod,
        createdAt: now,
        updatedAt: now,
      );
      _validate(
        SharedScopeData(
          projects: [...data.projects, row],
          tasks: data.tasks,
          shoppingLists: data.shoppingLists,
          shoppingItems: data.shoppingItems,
        ),
      );
      await _put(
        p,
        scopeId,
        SharedRecordType.project,
        id,
        _payload(row.toJson()),
      );
    });
    return id;
  }

  Future<void> updateProject(String scopeId, LocalProject draft) =>
      _edit(scopeId, (p) async {
        final data = await _scopeData(p, scopeId),
            row = draft.copyWith(
              title: draft.title.trim(),
              description: draft.description.trim(),
              updatedAt: _now,
            );
        final previous = data.projects.firstWhere(
          (project) => project.id == draft.id,
        );
        if (previous.revision != draft.revision) {
          throw const CollaborationException('stale_edit');
        }
        final remaining = row.phases.map((phase) => phase.id).toSet();
        for (final task in data.tasks.where(
          (task) =>
              task.projectId == row.id &&
              task.phaseId != null &&
              !remaining.contains(task.phaseId),
        )) {
          // The editor explicitly confirms phase removal. Queue dependent task
          // detachment before the project update without touching other fields.
          final detached = task.copyWith(phaseId: null, updatedAt: _now);
          await _put(
            p,
            scopeId,
            SharedRecordType.task,
            task.id,
            _payload(detached.toJson()),
            expectedLocalRevision: task.revision,
          );
        }
        _validate(
          SharedScopeData(
            projects: data.projects.map((r) => r.id == row.id ? row : r),
            tasks: data.tasks,
            shoppingLists: data.shoppingLists,
            shoppingItems: data.shoppingItems,
          ),
        );
        await _put(
          p,
          scopeId,
          SharedRecordType.project,
          row.id,
          _payload(row.toJson()),
          expectedLocalRevision: draft.revision,
        );
      });
  Future<String> createTask({
    required String scopeId,
    required String title,
    String notes = '',
    String? projectId,
    DateTime? dueAt,
    DateTime? startAt,
    DateTime? endAt,
    Iterable<String> assigneeAccountIds = const [],
    String? assigneePersonId,
    Iterable<String> subjectPersonIds = const [],
    String? phaseId,
    int? estimateMinutes,
    int? availabilityMinutes,
    AvailabilityPeriod? availabilityPeriod,
    TaskTimerState timer = const TaskTimerState(),
  }) async {
    final id = newSharedId(), now = _now;
    await _edit(scopeId, (p) async {
      final data = await _scopeData(p, scopeId);
      final scoped = SharedScope.fromJson(
        CollaborationRepository._map(
          (await database.rows(
            'SELECT data FROM scopes WHERE partition=? AND id=?',
            [p, scopeId],
          )).single['data'],
        ),
      );
      projectId ??=
          scoped.projectRootId ??
          (scoped.parentSpaceId != null ? scopeId : null);
      final row = LocalTask(
        id: id,
        title: title.trim(),
        notes: notes.trim(),
        projectId: projectId,
        assigneeAccountIds: assigneeAccountIds,
        assigneePersonId: assigneePersonId,
        subjectPersonIds: subjectPersonIds,
        phaseId: phaseId,
        estimateMinutes: estimateMinutes,
        availabilityMinutes: availabilityMinutes,
        availabilityPeriod: availabilityPeriod,
        timer: timer,
        startAt: startAt?.toUtc(),
        endAt: endAt?.toUtc(),
        dueAt: dueAt?.toUtc(),
        isCompleted: false,
        createdAt: now,
        updatedAt: now,
      );
      _validate(
        SharedScopeData(
          projects: data.projects,
          tasks: [...data.tasks, row],
          shoppingLists: data.shoppingLists,
          shoppingItems: data.shoppingItems,
        ),
      );
      await _put(p, scopeId, SharedRecordType.task, id, _payload(row.toJson()));
    });
    return id;
  }

  Future<void> updateTask(String scopeId, LocalTask draft) =>
      _edit(scopeId, (p) async {
        final data = await _scopeData(p, scopeId),
            row = draft.copyWith(
              title: draft.title.trim(),
              notes: draft.notes.trim(),
              updatedAt: _now,
            );
        _validate(
          SharedScopeData(
            projects: data.projects,
            tasks: data.tasks.map((r) => r.id == row.id ? row : r),
            shoppingLists: data.shoppingLists,
            shoppingItems: data.shoppingItems,
          ),
        );
        await _put(
          p,
          scopeId,
          SharedRecordType.task,
          row.id,
          _payload(row.toJson()),
          expectedLocalRevision: draft.revision,
        );
      });
  Future<void> setTaskCompleted(String scopeId, String id, bool value) =>
      _edit(scopeId, (p) async {
        final r = await _record(p, scopeId, id),
            row = LocalTask.fromJson({
              ...CollaborationRepository._map(r['payload']),
              'id': id,
              'revision': r['local_revision'],
            }).copyWith(isCompleted: value, updatedAt: _now);
        await _put(
          p,
          scopeId,
          SharedRecordType.task,
          id,
          _payload(row.toJson()),
          expectedLocalRevision: row.revision,
        );
      });
  Future<void> deleteTask(String scopeId, String id) => _edit(
    scopeId,
    (p) => _put(p, scopeId, SharedRecordType.task, id, null, deleted: true),
  );
  Future<LocalTask> toggleTaskTimer(String scopeId, LocalTask task) async {
    final profile = _requireSession().profile, epoch = _epoch;
    final timer = task.timer.running
        ? task.timer.pausedAt(_now)
        : TaskTimerState(
            elapsedSeconds: task.timer.elapsedSeconds,
            runningSince: _now,
            runId: newSharedId(),
          );
    await updateTask(scopeId, task.copyWith(timer: timer));
    _checkEpoch(epoch);
    final data = await _scopeData(profile.partition, scopeId);
    _checkEpoch(epoch);
    return data.tasks.firstWhere((row) => row.id == task.id);
  }

  Future<void> deleteProject(String scopeId, String id) => _edit(scopeId, (
    p,
  ) async {
    final data = await _scopeData(p, scopeId);
    for (final task in data.tasks.where((r) => r.projectId == id)) {
      final row = task.copyWith(
        projectId: null,
        phaseId: null,
        updatedAt: _now,
      );
      await _put(
        p,
        scopeId,
        SharedRecordType.task,
        row.id,
        _payload(row.toJson()),
        expectedLocalRevision: row.revision,
      );
    }
    for (final event in data.events.where((e) => e.projectId == id)) {
      final row = event.copyWith(projectId: null, updatedAt: _now);
      await _put(
        p,
        scopeId,
        SharedRecordType.event,
        event.id,
        _payload(row.toJson()),
      );
    }
    await _put(p, scopeId, SharedRecordType.project, id, null, deleted: true);
  });

  Future<String> publishShoppingList({
    required String scopeId,
    required LocalShoppingList list,
    required List<LocalShoppingItem> items,
  }) async {
    final id = newSharedId(), now = _now;
    await _edit(scopeId, (p) async {
      final copied = LocalShoppingList(
        id: id,
        title: list.title,
        createdAt: now,
        updatedAt: now,
      );
      final copiedItems = items.map((r) {
        if (r.listId != list.id) {
          throw const CollaborationException('invalid_copy');
        }
        return LocalShoppingItem(
          id: newSharedId(),
          listId: id,
          title: r.title,
          quantity: r.quantity,
          isChecked: r.isChecked,
          createdAt: now,
          updatedAt: now,
        );
      }).toList();
      _validate(
        SharedScopeData(shoppingLists: [copied], shoppingItems: copiedItems),
      );
      await _put(
        p,
        scopeId,
        SharedRecordType.shoppingList,
        id,
        _payload(copied.toJson()),
      );
      for (final item in copiedItems) {
        await _put(
          p,
          scopeId,
          SharedRecordType.shoppingItem,
          item.id,
          _payload(item.toJson()),
        );
      }
    });
    return id;
  }

  Future<String> publishProject({
    required String scopeId,
    required LocalProject project,
    required List<LocalTask> tasks,
    List<HouseholdPerson> people = const [],
  }) async {
    final id = newSharedId(), now = _now;
    final personIds = <String>{
      for (final task in tasks) ...[
        if (task.assigneePersonId != null) task.assigneePersonId!,
        ...task.subjectPersonIds,
      ],
    };
    if (!personIds.every((id) => people.any((person) => person.id == id))) {
      throw const CollaborationException('invalid_copy');
    }
    final personMap = {for (final id in personIds) id: newSharedId()};
    final phaseMap = {
      for (final phase in project.phases) phase.id: newSharedId(),
    };
    await _edit(scopeId, (p) async {
      for (final person in people.where(
        (person) => personIds.contains(person.id),
      )) {
        final copied = HouseholdPerson(
          id: personMap[person.id]!,
          name: person.name,
          notes: person.notes,
          archived: false,
          createdAt: now,
          updatedAt: now,
        );
        await _put(
          p,
          scopeId,
          SharedRecordType.householdPerson,
          copied.id,
          _payload(copied.toJson()),
        );
      }
      final copied = LocalProject(
        id: id,
        title: project.title,
        description: project.description,
        startAt: project.startAt,
        endAt: project.endAt,
        area: project.area,
        phases: project.phases.map(
          (phase) => ProjectPhase(
            id: phaseMap[phase.id]!,
            title: phase.title,
            milestone: phase.milestone,
            startAt: phase.startAt,
            endAt: phase.endAt,
          ),
        ),
        availabilityMinutes: project.availabilityMinutes,
        availabilityPeriod: project.availabilityPeriod,
        createdAt: now,
        updatedAt: now,
      );
      final copiedTasks = tasks.map((r) {
        if (r.projectId != project.id) {
          throw const CollaborationException('invalid_copy');
        }
        return LocalTask(
          id: newSharedId(),
          title: r.title,
          notes: r.notes,
          projectId: id,
          assigneePersonId: personMap[r.assigneePersonId],
          subjectPersonIds: r.subjectPersonIds.map((id) => personMap[id]!),
          phaseId: phaseMap[r.phaseId],
          estimateMinutes: r.estimateMinutes,
          availabilityMinutes: r.availabilityMinutes,
          availabilityPeriod: r.availabilityPeriod,
          timer: r.timer.pausedAt(now),
          startAt: r.startAt,
          endAt: r.endAt,
          dueAt: r.dueAt,
          isCompleted: r.isCompleted,
          createdAt: now,
          updatedAt: now,
        );
      }).toList();
      _validate(SharedScopeData(projects: [copied], tasks: copiedTasks));
      await _put(
        p,
        scopeId,
        SharedRecordType.project,
        id,
        _payload(copied.toJson()),
      );
      for (final task in copiedTasks) {
        await _put(
          p,
          scopeId,
          SharedRecordType.task,
          task.id,
          _payload(task.toJson()),
        );
      }
      for (final person in people.where(
        (person) => person.archived && personIds.contains(person.id),
      )) {
        final copied = HouseholdPerson(
          id: personMap[person.id]!,
          name: person.name,
          notes: person.notes,
          archived: true,
          createdAt: now,
          updatedAt: now,
        );
        await _put(
          p,
          scopeId,
          SharedRecordType.householdPerson,
          copied.id,
          _payload(copied.toJson()),
        );
      }
    });
    return id;
  }
}
