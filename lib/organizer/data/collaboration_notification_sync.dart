part of 'collaboration_repository.dart';

/// Canonical inbox/read-state and reminder synchronization.
extension CollaborationNotificationSync on CollaborationRepository {
  Future<void> _applyInbox(String partition, SharedInboxEntry entry) async {
    if (entry.category == 'finance' &&
        !(await _cachedFinancePolicy(partition, entry.scopeId)).canRead) {
      await database.execute('DELETE FROM inbox WHERE partition=? AND id=?', [
        partition,
        entry.id,
      ]);
      return;
    }
    final queued = await database.rows(
      "SELECT id FROM commands WHERE partition=? AND entity_key=? AND state='pending'",
      [partition, 'inbox:${entry.id}'],
    );
    final old = await database.rows(
      'SELECT data,remote FROM inbox WHERE partition=? AND id=?',
      [partition, entry.id],
    );
    var canonical = entry;
    if (old.isNotEmpty && old.first['remote'] != null) {
      final latest = SharedInboxEntry.fromJson(
        CollaborationRepository._map(old.first['remote']),
      );
      if (latest.revision > canonical.revision) canonical = latest;
    }
    final json = canonical.toJson();
    if (queued.isNotEmpty && old.isNotEmpty) {
      final candidate = SharedInboxEntry.fromJson(
        CollaborationRepository._map(old.first['data']),
      );
      json['readAt'] = candidate.readAt?.toUtc().toIso8601String();
      if (candidate.revision > canonical.revision) {
        json['revision'] = candidate.revision;
      }
    }
    await database.execute(
      'INSERT INTO inbox(partition,id,data,remote) VALUES(?,?,?,?) ON CONFLICT(partition,id) DO UPDATE SET data=excluded.data,remote=excluded.remote',
      [partition, entry.id, jsonEncode(json), jsonEncode(canonical.toJson())],
    );
  }

  Future<void> _applyReminder(
    String partition,
    SharedScheduledReminder reminder,
  ) async {
    if (isFinancialRecordType(reminder.targetType) &&
        !(await _cachedFinancePolicy(partition, reminder.scopeId)).canRead) {
      return;
    }
    final scopes = await database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [partition, reminder.scopeId],
    );
    if (scopes.isEmpty ||
        SharedScope.fromJson(
          CollaborationRepository._map(scopes.first['data']),
        ).revoked) {
      return;
    }
    final queued = await database.rows(
      "SELECT id FROM commands WHERE partition=? AND entity_key=? AND state='pending'",
      [partition, 'reminder:${reminder.id}'],
    );
    final old = await database.rows(
      'SELECT data,remote FROM scheduled_reminders WHERE partition=? AND id=?',
      [partition, reminder.id],
    );
    if (old.isNotEmpty) {
      final stored = SharedScheduledReminder.fromJson(
        CollaborationRepository._map(old.first['data']),
      );
      if (stored.scopeId != reminder.scopeId ||
          stored.targetType != reminder.targetType ||
          stored.targetId != reminder.targetId) {
        throw const CollaborationException('invalid_response');
      }
    }
    var canonical = reminder;
    if (old.isNotEmpty && old.first['remote'] != null) {
      final latest = SharedScheduledReminder.fromJson(
        CollaborationRepository._map(old.first['remote']),
      );
      if (latest.revision > canonical.revision) canonical = latest;
    }
    final cancelled = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['reminder_cancelled:$partition:${reminder.id}'],
    );
    final canonicalJson = canonical.toJson();
    if (cancelled.isNotEmpty) canonicalJson['state'] = 'cancelled';
    var data = jsonEncode(canonicalJson);
    if (old.isNotEmpty) {
      final candidate = SharedScheduledReminder.fromJson(
        CollaborationRepository._map(old.first['data']),
      );
      if (queued.isNotEmpty || candidate.syncState == 'blocked') {
        final local = candidate.toJson();
        if (cancelled.isNotEmpty) local['state'] = 'cancelled';
        data = jsonEncode(local);
      }
    }
    await database.execute(
      'INSERT INTO scheduled_reminders(partition,id,scope_id,data,remote) VALUES(?,?,?,?,?) ON CONFLICT(partition,id) DO UPDATE SET data=excluded.data,remote=excluded.remote',
      [
        partition,
        reminder.id,
        reminder.scopeId,
        data,
        jsonEncode(canonical.toJson()),
      ],
    );
  }

  Future<void> _syncCommands(DeviceSession session, int epoch) async {
    final p = session.profile.partition;
    while (true) {
      _checkEpoch(epoch);
      await _renewLease(p);
      final rows = await database.rows(
        "SELECT * FROM commands WHERE partition=? AND state='pending' ORDER BY sequence LIMIT 1",
        [p],
      );
      if (rows.isEmpty) return;
      final command = rows.first,
          params = CollaborationRepository._map(command['params']);
      try {
        if ((command['operation'] as String).startsWith('reminders.')) {
          SharedScope scope;
          try {
            scope = await _readableReminderScope(
              p,
              params['scopeId'] as String,
            );
          } on CollaborationException catch (error) {
            if (error.code != 'permission_revoked') rethrow;
            throw const CollaborationApiException('permission_revoked');
          }
          if (command['operation'] == 'reminders.put' && scope.archived) {
            throw const CollaborationApiException('scope_archived');
          }
          final stored = await database.rows(
            'SELECT data FROM scheduled_reminders WHERE partition=? AND id=?',
            [p, params['id']],
          );
          if (stored.isNotEmpty &&
              isFinancialRecordType(
                SharedScheduledReminder.fromJson(
                  CollaborationRepository._map(stored.first['data']),
                ).targetType,
              ) &&
              !(await _cachedFinancePolicy(p, scope.id)).canRead) {
            throw const CollaborationApiException('finance_forbidden');
          }
        }
        final reply = await _callSession(
          session,
          epoch,
          command['operation'] as String,
          Map<String, Object?>.from(params),
        );
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(p);
          _checkEpoch(epoch);
          if ((command['operation'] as String).startsWith('reminders.')) {
            if (reply['reminder'] is! Map<String, dynamic>) {
              throw const CollaborationException('invalid_response');
            }
            final item = SharedScheduledReminder.fromJson(
              reply['reminder'] as Map<String, dynamic>,
            );
            if (item.id != params['id'] ||
                item.scopeId != params['scopeId'] ||
                item.revision != (params['expectedRevision'] as int) + 1 ||
                (command['operation'] == 'reminders.put' &&
                    (item.targetType != params['targetType'] ||
                        item.targetId != params['targetId']))) {
              throw const CollaborationException('invalid_response');
            }
            // An explicit accepted edit/cancel resolves only older rejected
            // intent. A later local rejection must survive a delayed ACK.
            await database.execute(
              "DELETE FROM commands WHERE partition=? AND entity_key=? AND state='blocked' AND sequence<?",
              [p, command['entity_key'], command['sequence']],
            );
          }
          await database.execute(
            'DELETE FROM commands WHERE partition=? AND id=?',
            [p, command['id']],
          );
          if (reply['item'] is Map<String, dynamic>) {
            await _applyInbox(
              p,
              SharedInboxEntry.fromJson(reply['item'] as Map<String, dynamic>),
            );
          }
          if (reply['reminder'] is Map<String, dynamic>) {
            await _applyReminder(
              p,
              SharedScheduledReminder.fromJson(
                reply['reminder'] as Map<String, dynamic>,
              ),
            );
          }
        });
      } on CollaborationApiException catch (e) {
        if (!const [
          'inbox_conflict',
          'conflict',
          'permission_revoked',
          'finance_forbidden',
          'target_missing',
          'validation_error',
          'reminder_conflict',
          'reminder_target_unavailable',
          'reminder_target_immutable',
          'reminder_missing',
          'record_missing',
          'scope_archived',
        ].contains(e.code)) {
          rethrow;
        }
        String? deniedScope;
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(p);
          _checkEpoch(epoch);
          await database.execute(
            "UPDATE commands SET state='blocked' WHERE partition=? AND entity_key=?",
            [p, command['entity_key']],
          );
          if ((command['operation'] as String).startsWith('reminders.')) {
            final local = await database.rows(
              'SELECT data FROM scheduled_reminders WHERE partition=? AND id=?',
              [p, params['id']],
            );
            if (local.isNotEmpty) {
              final data = CollaborationRepository._map(local.first['data'])
                ..['syncState'] = 'blocked'
                ..['syncError'] = e.code;
              await database.execute(
                'UPDATE scheduled_reminders SET data=? WHERE partition=? AND id=?',
                [jsonEncode(data), p, params['id']],
              );
            }
          }
          if (e.details['item'] is Map<String, dynamic>) {
            await _applyInbox(
              p,
              SharedInboxEntry.fromJson(
                e.details['item'] as Map<String, dynamic>,
              ),
            );
          }
          if (e.code == 'permission_revoked' || e.code == 'finance_forbidden') {
            deniedScope = params['scopeId'] as String?;
            if (params['id'] is int) {
              final existing = await database.rows(
                'SELECT data FROM inbox WHERE partition=? AND id=?',
                [p, params['id']],
              );
              if (existing.isNotEmpty) {
                deniedScope = SharedInboxEntry.fromJson(
                  CollaborationRepository._map(existing.first['data']),
                ).scopeId;
              }
              await database.execute(
                'DELETE FROM inbox WHERE partition=? AND id=?',
                [p, params['id']],
              );
            }
          }
          if (deniedScope != null && e.code == 'finance_forbidden') {
            await _storeFinancePolicy(
              p,
              deniedScope!,
              const SharedFinancePolicy(),
            );
          }
        });
        if (deniedScope != null && e.code == 'permission_revoked') {
          await _blockScope(p, deniedScope!, epoch);
        }
        _lastError = e;
      }
    }
  }

  Future<void> _syncInbox(DeviceSession session, int epoch) async {
    final p = session.profile.partition;
    for (var attempt = 0; attempt < 2; attempt++) {
      final rows = await database.rows(
        'SELECT cursor,visibility_revision FROM inbox_state WHERE partition=?',
        [p],
      );
      var cursor = rows.isEmpty ? 0 : rows.first['cursor'] as int,
          visibility = rows.isEmpty
              ? 0
              : rows.first['visibility_revision'] as int;
      try {
        var more = true;
        while (more) {
          await _renewLease(p);
          final reply = await _callSession(session, epoch, 'inbox.sync', {
            'cursor': cursor,
            if (rows.isNotEmpty || cursor > 0) 'visibilityRevision': visibility,
            'limit': 100,
          });
          final next = readInt(reply, 'cursor'),
              nextVisibility = readInt(reply, 'visibilityRevision');
          more = readBool(reply, 'hasMore');
          if (next < cursor || (more && next == cursor)) {
            throw const CollaborationException('invalid_response');
          }
          if (cursor > 0 && nextVisibility != visibility) {
            throw const CollaborationException('invalid_response');
          }
          visibility = nextVisibility;
          cursor = next;
          final items = (reply['items'] as List)
              .map((r) => SharedInboxEntry.fromJson(r as Map<String, dynamic>))
              .toList();
          await database.transaction(() async {
            _checkEpoch(epoch);
            await _validLease(p);
            _checkEpoch(epoch);
            for (final item in items) {
              await _applyInbox(p, item);
            }
            await database.execute(
              'INSERT INTO inbox_state(partition,cursor,visibility_revision) VALUES(?,?,?) ON CONFLICT(partition) DO UPDATE SET cursor=excluded.cursor,visibility_revision=excluded.visibility_revision',
              [p, cursor, visibility],
            );
          });
          await refreshLocal();
        }
        return;
      } on CollaborationApiException catch (e) {
        if (e.code != 'visibility_changed') rethrow;
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(p);
          _checkEpoch(epoch);
          await database.execute('DELETE FROM inbox WHERE partition=?', [p]);
          await database.execute('DELETE FROM inbox_state WHERE partition=?', [
            p,
          ]);
        });
        await refreshLocal();
      }
    }
    throw const CollaborationException('visibility_changed');
  }

  Future<void> _syncNotificationConfiguration(
    DeviceSession session,
    int epoch,
    List<SharedScope> scopes,
  ) async {
    final p = session.profile.partition;
    for (final scope in scopes) {
      await _renewLease(p);
      try {
        final prefs = await _callSession(
          session,
          epoch,
          'inbox.preferences.get',
          {'scopeId': scope.id},
        );
        final remoteReminders = <SharedScheduledReminder>[];
        String? before;
        var more = true;
        while (more) {
          await _renewLease(p);
          final page = await _callSession(session, epoch, 'reminders.list', {
            'scopeId': scope.id,
            if (before != null) 'beforeId': before,
            'limit': 100,
          });
          remoteReminders.addAll(
            (page['reminders'] as List).map(
              (r) =>
                  SharedScheduledReminder.fromJson(r as Map<String, dynamic>),
            ),
          );
          more = readBool(page, 'hasMore');
          final next = page['nextBeforeId'] as String?;
          if (more && (next == null || next == before)) {
            throw const CollaborationException('invalid_response');
          }
          before = next;
        }
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(p);
          _checkEpoch(epoch);
          final candidate = await database.rows(
            "SELECT id FROM commands WHERE partition=? AND entity_key LIKE ? AND state='pending'",
            [p, 'preferences:${scope.id}:%'],
          );
          if (candidate.isEmpty) {
            await database.execute(
              'INSERT INTO notification_preferences(partition,scope_id,data) VALUES(?,?,?) ON CONFLICT(partition,scope_id) DO UPDATE SET data=excluded.data',
              [p, scope.id, jsonEncode(prefs['preferences'])],
            );
          }
          for (final reminder in remoteReminders) {
            if (reminder.scopeId != scope.id) {
              throw const CollaborationException('invalid_response');
            }
            await _applyReminder(p, reminder);
          }
        });
      } on CollaborationApiException catch (e) {
        if (e.code != 'permission_revoked') rethrow;
      }
    }
  }
}
