part of 'collaboration_repository.dart';

/// Account-specific inbox, immutable read commands and safe reference routing.
extension CollaborationNotificationActions on CollaborationRepository {
  String? _reminderFingerprint(
    String type,
    Map<String, dynamic>? payload,
    bool deleted,
  ) {
    if (deleted ||
        payload == null ||
        (type == 'task' && payload['isCompleted'] == true) ||
        (type == 'financeEntry' && payload['status'] != 'planned')) {
      return null;
    }
    if (!const ['task', 'event', 'financeEntry'].contains(type)) return null;
    return jsonEncode([
      for (final key in [
        'dueAt',
        'startAt',
        'endAt',
        'occurredAt',
        'plannedAt',
      ])
        payload[key] == null
            ? null
            : DateTime.parse(
                payload[key] as String,
              ).toUtc().microsecondsSinceEpoch,
    ]);
  }

  Future<void> _reconcileLocalReminders(
    String p,
    String scope,
    String type,
    String id,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    bool deleted,
  ) async {
    if (_reminderFingerprint(type, before, false) ==
        _reminderFingerprint(type, after, deleted)) {
      return;
    }
    final rows = await database.rows(
      'SELECT id,data FROM scheduled_reminders WHERE partition=? AND scope_id=?',
      [p, scope],
    );
    for (final row in rows) {
      final reminder = SharedScheduledReminder.fromJson(
        CollaborationRepository._map(row['data']),
      );
      if (reminder.targetType != type ||
          reminder.targetId != id ||
          reminder.state != 'pending') {
        continue;
      }
      final data = reminder.toJson()..['state'] = 'cancelled';
      if (reminder.syncState == 'queued') {
        data['syncState'] = 'blocked';
        data['syncError'] = 'reminder_target_unavailable';
      }
      await database.execute(
        'UPDATE scheduled_reminders SET data=? WHERE partition=? AND id=?',
        [jsonEncode(data), p, reminder.id],
      );
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        ['reminder_cancelled:$p:${reminder.id}', '1'],
      );
      await database.execute(
        "UPDATE commands SET state='blocked' WHERE partition=? AND entity_key=? AND operation='reminders.put' AND state='pending'",
        [p, 'reminder:${reminder.id}'],
      );
    }
  }

  Future<void> _enqueueCommand(
    String partition,
    String operation,
    Map<String, Object?> params,
    String key,
  ) async {
    final id = params['requestId'] as String;
    await database.execute(
      'INSERT INTO commands(id,partition,operation,params,entity_key) VALUES(?,?,?,?,?)',
      [id, partition, operation, jsonEncode(params), key],
    );
  }

  Future<void> markInboxRead(Iterable<int> ids, {bool read = true}) async {
    final session = _requireSession(), epoch = _epoch;
    await database.transaction(() async {
      _checkEpoch(epoch);
      for (final id in ids.toSet()) {
        final rows = await database.rows(
          'SELECT data FROM inbox WHERE partition=? AND id=?',
          [session.profile.partition, id],
        );
        if (rows.isEmpty) {
          throw const CollaborationException('notification_missing');
        }
        final entry = SharedInboxEntry.fromJson(
          CollaborationRepository._map(rows.first['data']),
        );
        if (!state.scopes.any((s) => s.id == entry.scopeId && !s.revoked)) {
          throw const CollaborationException('permission_revoked');
        }
        await _enqueueCommand(session.profile.partition, 'inbox.read', {
          'id': id,
          'read': read,
          'expectedRevision': entry.revision,
          'requestId': newSharedId(),
        }, 'inbox:$id');
        final json = entry.toJson()
          ..['readAt'] = read ? clock().toUtc().toIso8601String() : null
          ..['revision'] = entry.revision + 1;
        await database.execute(
          'UPDATE inbox SET data=? WHERE partition=? AND id=?',
          [jsonEncode(json), session.profile.partition, id],
        );
      }
    });
    await refreshLocal();
  }

  Future<void> setNotificationPreferences({
    required String scopeId,
    required String category,
    required SharedNotificationSettings settings,
  }) async {
    if (!const [
      'tasks',
      'events',
      'shopping',
      'finance',
      'reminders',
      'membership',
    ].contains(category)) {
      throw const CollaborationException('validation_error');
    }
    final session = _requireSession(), epoch = _epoch;
    await database.transaction(() async {
      _checkEpoch(epoch);
      if (!state.scopes.any((s) => s.id == scopeId && !s.revoked)) {
        throw const CollaborationException('permission_revoked');
      }
      final rows = await database.rows(
        'SELECT data FROM notification_preferences WHERE partition=? AND scope_id=?',
        [session.profile.partition, scopeId],
      );
      final prefs = rows.isEmpty
          ? <String, dynamic>{}
          : CollaborationRepository._map(rows.first['data']);
      prefs[category] = settings.toJson();
      await database.execute(
        'INSERT INTO notification_preferences(partition,scope_id,data) VALUES(?,?,?) ON CONFLICT(partition,scope_id) DO UPDATE SET data=excluded.data',
        [session.profile.partition, scopeId, jsonEncode(prefs)],
      );
      await _enqueueCommand(
        session.profile.partition,
        'inbox.preferences.set',
        {
          'scopeId': scopeId,
          'category': category,
          'settings': settings.toJson(),
          'requestId': newSharedId(),
        },
        'preferences:$scopeId:$category',
      );
    });
    await refreshLocal();
  }

  Future<String> putReminder({
    String? id,
    required String scopeId,
    required String targetType,
    required String targetId,
    required DateTime remindAt,
    int expectedRevision = 0,
    String? expectedPartition,
  }) async {
    if (!const ['task', 'event', 'financeEntry'].contains(targetType) ||
        !isSharedUuid(targetId) ||
        !isSharedUuid(scopeId) ||
        (id != null && !isSharedUuid(id)) ||
        expectedRevision < 0 ||
        !remindAt.toUtc().isAfter(clock().toUtc())) {
      throw const CollaborationException('validation_error');
    }
    final session = _requireSession(),
        epoch = _epoch,
        reminderId = id ?? newSharedId();
    if (expectedPartition != null &&
        expectedPartition != session.profile.partition) {
      throw const CollaborationException('session_changed');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _writable(session.profile.partition, scopeId);
      final table = isFinancialRecordType(targetType)
          ? 'finance_records'
          : 'records';
      if (isFinancialRecordType(targetType) &&
          !(await _cachedFinancePolicy(
            session.profile.partition,
            scopeId,
          )).canRead) {
        throw const CollaborationException('finance_forbidden');
      }
      final source = await database.rows(
        'SELECT type,payload,deleted FROM $table WHERE partition=? AND scope_id=? AND id=?',
        [session.profile.partition, scopeId, targetId],
      );
      if (source.isEmpty ||
          source.first['type'] != targetType ||
          _reminderFingerprint(
                targetType,
                source.first['payload'] == null
                    ? null
                    : CollaborationRepository._map(source.first['payload']),
                source.first['deleted'] == 1,
              ) ==
              null) {
        throw const CollaborationException('reminder_target_unavailable');
      }
      final rows = await database.rows(
        'SELECT data,remote FROM scheduled_reminders WHERE partition=? AND id=?',
        [session.profile.partition, reminderId],
      );
      final old = rows.isEmpty
          ? null
          : SharedScheduledReminder.fromJson(
              CollaborationRepository._map(rows.first['data']),
            );
      if (old != null &&
          (old.scopeId != scopeId ||
              old.targetType != targetType ||
              old.targetId != targetId)) {
        throw const CollaborationException('reminder_target_immutable');
      }
      if ((old?.revision ?? 0) != expectedRevision) {
        throw const CollaborationException('stale_edit');
      }
      final serverRevision = await _nextReminderServerRevision(
        session.profile.partition,
        reminderId,
        rows.isEmpty ? null : rows.first['remote'],
      );
      final reminder = SharedScheduledReminder(
        id: reminderId,
        scopeId: scopeId,
        targetType: targetType,
        targetId: targetId,
        remindAt: remindAt.toUtc(),
        revision: expectedRevision + 1,
        state: 'pending',
        syncState: 'queued',
      );
      await database.execute('DELETE FROM local_meta WHERE name=?', [
        'reminder_cancelled:${session.profile.partition}:$reminderId',
      ]);
      await database.execute(
        'INSERT INTO scheduled_reminders(partition,id,scope_id,data) VALUES(?,?,?,?) ON CONFLICT(partition,id) DO UPDATE SET data=excluded.data',
        [
          session.profile.partition,
          reminderId,
          scopeId,
          jsonEncode(reminder.toJson()),
        ],
      );
      await _enqueueCommand(session.profile.partition, 'reminders.put', {
        'id': reminderId,
        'scopeId': scopeId,
        'targetType': targetType,
        'targetId': targetId,
        'remindAt': remindAt.toUtc().toIso8601String(),
        'expectedRevision': serverRevision,
        'requestId': newSharedId(),
      }, 'reminder:$reminderId');
      _checkEpoch(epoch);
    });
    await refreshLocal();
    return reminderId;
  }

  /// Predict only from immutable pending commands, never from a rejected draft.
  Future<int> _nextReminderServerRevision(
    String partition,
    String id,
    Object? remote,
  ) async {
    final pending = await database.rows(
      "SELECT params FROM commands WHERE partition=? AND entity_key=? AND state='pending' ORDER BY sequence DESC LIMIT 1",
      [partition, 'reminder:$id'],
    );
    if (pending.isNotEmpty) {
      return (CollaborationRepository._map(
                pending.first['params'],
              )['expectedRevision']
              as int) +
          1;
    }
    return remote == null
        ? 0
        : SharedScheduledReminder.fromJson(
            CollaborationRepository._map(remote),
          ).revision;
  }

  Future<void> cancelReminder(
    SharedScheduledReminder reminder, {
    String? expectedPartition,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    final partition = session.profile.partition;
    if (expectedPartition != null && expectedPartition != partition) {
      throw const CollaborationException('session_changed');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      final rows = await database.rows(
        'SELECT data,remote FROM scheduled_reminders WHERE partition=? AND id=?',
        [partition, reminder.id],
      );
      if (rows.isEmpty) throw const CollaborationException('stale_edit');
      final stored = SharedScheduledReminder.fromJson(
        CollaborationRepository._map(rows.first['data']),
      );
      if (stored.revision != reminder.revision) {
        throw const CollaborationException('stale_edit');
      }
      if (stored.scopeId != reminder.scopeId ||
          stored.targetId != reminder.targetId ||
          stored.targetType != reminder.targetType) {
        throw const CollaborationException('reminder_target_immutable');
      }
      await _readableReminderScope(partition, stored.scopeId);
      if (isFinancialRecordType(stored.targetType) &&
          !(await _cachedFinancePolicy(partition, stored.scopeId)).canRead) {
        throw const CollaborationException('finance_forbidden');
      }
      final serverRevision = await _nextReminderServerRevision(
        partition,
        stored.id,
        rows.first['remote'],
      );
      // A rejected create has no server reminder to cancel; an explicit
      // cancellation can finish locally and discard that rejected intent.
      final needsRemoteCancel = serverRevision > 0;
      final value = stored.toJson()
        ..['state'] = 'cancelled'
        ..['syncState'] = needsRemoteCancel ? 'queued' : 'synced'
        ..remove('syncError')
        ..['revision'] = stored.revision + 1;
      await database.execute(
        'UPDATE scheduled_reminders SET data=? WHERE partition=? AND id=?',
        [jsonEncode(value), partition, stored.id],
      );
      if (needsRemoteCancel) {
        await _enqueueCommand(partition, 'reminders.cancel', {
          'id': stored.id,
          'scopeId': stored.scopeId,
          'expectedRevision': serverRevision,
          'requestId': newSharedId(),
        }, 'reminder:${stored.id}');
      } else {
        await database.execute(
          "DELETE FROM commands WHERE partition=? AND entity_key=? AND state='blocked'",
          [partition, 'reminder:${stored.id}'],
        );
      }
      _checkEpoch(epoch);
    });
    await refreshLocal();
  }

  Future<SharedScope> _readableReminderScope(
    String partition,
    String scopeId,
  ) async {
    final rows = await database.rows(
      'SELECT data,blocked FROM scopes WHERE partition=? AND id=?',
      [partition, scopeId],
    );
    if (rows.isEmpty) throw const CollaborationException('permission_revoked');
    final scope = SharedScope.fromJson({
      ...CollaborationRepository._map(rows.first['data']),
      'blocked': rows.first['blocked'] == 1,
    });
    if (scope.revoked) throw const CollaborationException('permission_revoked');
    return scope;
  }
}
