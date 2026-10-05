part of 'collaboration_repository.dart';

/// Atomic local record edits, dependency ordering and explicit personal copies.
extension CollaborationRecordActions on CollaborationRepository {
  Future<void> _writable(String partition, String scopeId) async {
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
    if (payload != null) {
      validateSharedPayload(type, Map<String, dynamic>.from(payload));
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
        _recordContractVersion,
      ],
    );
  }

  Map<String, Object?> _payload(Map<String, Object?> json) {
    final value = Map<String, Object?>.of(json)
      ..remove('id')
      ..remove('revision')
      ..remove('createdByAccountId')
      ..remove('updatedByAccountId');
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
  }) async {
    final id = newSharedId(), now = _now;
    await _edit(scopeId, (p) async {
      final data = await _scopeData(p, scopeId);
      final row = LocalTask(
        id: id,
        title: title.trim(),
        notes: notes.trim(),
        projectId: projectId,
        assigneeAccountIds: assigneeAccountIds,
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
  Future<void> deleteProject(String scopeId, String id) => _edit(scopeId, (
    p,
  ) async {
    final data = await _scopeData(p, scopeId);
    for (final task in data.tasks.where((r) => r.projectId == id)) {
      final row = task.copyWith(projectId: null, updatedAt: _now);
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
  }) async {
    final id = newSharedId(), now = _now;
    await _edit(scopeId, (p) async {
      final copied = LocalProject(
        id: id,
        title: project.title,
        description: project.description,
        startAt: project.startAt,
        endAt: project.endAt,
        area: project.area,
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
    });
    return id;
  }
}
