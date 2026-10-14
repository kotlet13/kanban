import 'dart:convert';
import 'package:cryptography/cryptography.dart';

import '../domain/collaboration_models.dart';
import '../domain/organizer_models.dart';
import 'collaboration_database.dart';

/// Device preferences only: no money, credentials or remote delivery commands.
/// A snooze belongs to one exact reminder and one unchanged source version.
class ReminderSnoozeStore {
  ReminderSnoozeStore(this.database, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final CollaborationDatabase database;
  final DateTime Function() clock;
  static const prefix = 'reminder_snooze:';
  static const deadlinePrefix = 'local_task_deadline_reminder:';
  static Future<String> fingerprint(String source) async =>
      base64Encode((await Sha256().hash(utf8.encode(source))).bytes);

  bool _active(String type, String payload) {
    final value = jsonDecode(payload) as Map;
    return (type != 'task' || value['isCompleted'] != true) &&
        (!const ['financeEntry', 'personalFinanceEntry'].contains(type) ||
            value['status'] == 'planned');
  }

  static String signature(ReminderPlan plan) => jsonEncode([
    plan.scheduledAt.toUtc().toIso8601String(),
    plan.reason,
    plan.target.toJson(),
  ]);

  Future<String?> _source(ReminderPlan plan) async {
    final target = plan.target;
    if (target.records.length != 1) return null;
    final record = target.records.single;
    if (target.isPersonal) {
      final workspace = target.localWorkspaceId;
      if (workspace != 'local') {
        final catalog = await database.rows(
          'SELECT data FROM local_spaces WHERE id=?',
          [workspace],
        );
        if (catalog.isEmpty ||
            (jsonDecode(catalog.single['data'] as String) as Map)['binding'] !=
                null) {
          return null;
        }
      }

      final rows = await database.rows(
        "SELECT payload FROM personal_records WHERE workspace=? AND id=? AND type=?",
        [workspace, record.recordId, record.type],
      );
      final payload = rows.firstOrNull?['payload'] as String?;
      return payload != null && _active(record.type, payload) ? payload : null;
    }
    final profile = database.personalProfile;
    if (profile == null || !target.matches(profile)) return null;
    final scopes = await database.rows(
      'SELECT data,blocked,finance_policy,finance_blocked,finance_complete FROM scopes WHERE partition=? AND id=?',
      [profile.partition, target.scopeId],
    );
    if (scopes.isEmpty || scopes.first['blocked'] == 1) return null;
    final scope = jsonDecode(scopes.first['data'] as String) as Map;
    if (scope['revoked'] == true || scope['archived'] == true) return null;
    final financial =
        record.type == 'financeEntry' || record.type == 'personalFinanceEntry';
    if (financial &&
        (scopes.first['finance_blocked'] == 1 ||
            scopes.first['finance_complete'] != 1 ||
            scopes.first['finance_policy'] == null ||
            !SharedFinancePolicy.fromJson(
              jsonDecode(scopes.first['finance_policy'] as String)
                  as Map<String, dynamic>,
            ).canRead)) {
      return null;
    }
    final rows = await database.rows(
      'SELECT payload,deleted FROM ${financial ? 'finance_records' : 'records'} WHERE partition=? AND scope_id=? AND id=? AND type=?',
      [profile.partition, target.scopeId, record.recordId, record.type],
    );
    final payload = rows.isEmpty || rows.first['deleted'] == 1
        ? null
        : rows.first['payload'] as String?;
    return payload != null && _active(record.type, payload) ? payload : null;
  }

  Future<void> snooze(
    ReminderPlan plan,
    DateTime until, {
    required bool Function() stillCurrent,
  }) async {
    if (!until.isAfter(clock())) {
      throw const CollaborationException('validation_error');
    }
    final identity = database.personalIdentityGeneration;
    await database.transaction(() async {
      if (!stillCurrent()) throw const CollaborationException('stale_edit');
      final source = await _source(plan);
      if (source == null) throw const CollaborationException('record_deleted');
      if (identity != database.personalIdentityGeneration || !stillCurrent()) {
        throw const CollaborationException('session_changed');
      }
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        [
          '$prefix${plan.stableKey}',
          jsonEncode({
            'signature': signature(plan),
            'source': await fingerprint(source),
            'until': until.toUtc().toIso8601String(),
          }),
        ],
      );
    });
  }

  /// The explicit setting follows the deadline, not the record revision. The
  /// creation stamp fences a removed/recreated task with the same identity.
  Future<void> setDeadlineOffset(
    ReminderPlan plan,
    int? offset, {
    required bool Function() stillCurrent,
  }) async {
    if (!plan.target.isPersonal ||
        plan.target.records.single.type != 'task' ||
        (offset != null && !const [0, 60, 1440].contains(offset))) {
      throw const CollaborationException('validation_error');
    }
    final identity = database.personalIdentityGeneration;
    await database.transaction(() async {
      final source = await _source(plan);
      if (!stillCurrent() ||
          source == null ||
          identity != database.personalIdentityGeneration) {
        throw const CollaborationException('stale_edit');
      }
      final payload = jsonDecode(source) as Map;
      if (payload['dueAt'] == null) {
        throw const CollaborationException('reminder_target_unavailable');
      }
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        [
          '$deadlinePrefix${plan.stableKey}',
          jsonEncode({
            'createdAt': payload['createdAt'],
            'offsetMinutes': offset ?? 0,
            'enabled': offset != null,
            'lastRemindAt': DateTime.parse(payload['dueAt'] as String)
                .toUtc()
                .subtract(Duration(minutes: offset ?? 0))
                .toIso8601String(),
          }),
        ],
      );
      await database.execute('DELETE FROM local_meta WHERE name=?', [
        '$prefix${plan.stableKey}',
      ]);
      await database.touchPersonal();
    });
    database.personalChanged();
  }

  Future<List<ReminderPlan>> resolveDeadlineOffsets(
    List<ReminderPlan> plans,
  ) async {
    final effective = {for (final plan in plans) plan.stableKey: plan};
    final identity = database.personalIdentityGeneration;
    var materialized = false;
    await database.transaction(() async {
      for (final row in await database.rows(
        'SELECT name,value FROM local_meta WHERE name LIKE ?',
        ['$deadlinePrefix%'],
      )) {
        final key = (row['name'] as String).substring(deadlinePrefix.length);
        final plan = effective[key];
        final value = jsonDecode(row['value'] as String) as Map;
        final source = plan == null ? null : await _source(plan);
        final payload = source == null ? null : jsonDecode(source) as Map;
        if (payload == null ||
            payload['createdAt'] != value['createdAt'] ||
            payload['dueAt'] == null) {
          // Keep cancellation durable so reinstating a deadline or restoring a
          // removed task cannot quietly create a fresh explicit reminder.
          if (value['enabled'] == true) {
            value['enabled'] = false;
            await database.execute(
              'UPDATE local_meta SET value=? WHERE name=?',
              [jsonEncode(value), row['name']],
            );
          }
          effective.remove(key);
          continue;
        }
        if (value['enabled'] != true) {
          effective.remove(key);
          continue;
        }
        final offset = value['offsetMinutes'];
        if (offset is! int || !const [0, 60, 1440].contains(offset)) {
          throw const FormatException('Invalid local deadline reminder');
        }
        final at = DateTime.parse(
          payload['dueAt'] as String,
        ).toUtc().subtract(Duration(minutes: offset));
        final previousAt = DateTime.parse(value['lastRemindAt'] as String);
        if (at != previousAt && !previousAt.isAfter(clock().toUtc())) {
          value['enabled'] = false;
          effective.remove(key);
        } else {
          value['lastRemindAt'] = at.toIso8601String();
          effective[key] = ReminderPlan(
            stableKey: plan!.stableKey,
            scheduledAt: at,
            reason: plan.reason,
            target: plan.target,
          );
        }
        if (jsonEncode(value) != row['value']) {
          await database.execute('UPDATE local_meta SET value=? WHERE name=?', [
            jsonEncode(value),
            row['name'],
          ]);
        }
        if (value['enabled'] == true && !at.isAfter(clock().toUtc())) {
          final task = LocalTask.fromJson(Map<String, dynamic>.from(payload));
          final reminder = LocalReminder(
            id: reminderId(task),
            taskId: task.id,
            dueAt: task.dueAt!,
            createdAt: clock().toUtc(),
            isRead: false,
          );
          final workspace = plan!.target.localWorkspaceId;
          final old = await database.rows(
            "SELECT id FROM personal_records WHERE workspace=? AND id=?",
            [workspace, reminder.id],
          );
          if (old.isEmpty) {
            await database.execute(
              "INSERT INTO personal_records(workspace,id,type,payload) VALUES(?,?,'reminder',?)",
              [workspace, reminder.id, jsonEncode(reminder.toJson())],
            );
            materialized = true;
          }
        }
      }
      if (identity != database.personalIdentityGeneration) {
        throw const CollaborationException('session_changed');
      }
      if (materialized) await database.touchPersonal();
    });
    if (materialized) database.personalChanged();
    return effective.values.toList();
  }

  /// Invalid preferences are removed before alarms are reconciled. A removed
  /// source/version cannot regain its old snooze after deletion or revocation.
  Future<List<ReminderPlan>> resolve(List<ReminderPlan> plans) async {
    final effective = <String, ReminderPlan>{
      for (final plan in plans) plan.stableKey: plan,
    };
    final identity = database.personalIdentityGeneration;
    await database.transaction(() async {
      for (final row in await database.rows(
        'SELECT name,value FROM local_meta WHERE name LIKE ?',
        ['$prefix%'],
      )) {
        final name = row['name'] as String;
        final plan = effective[name.substring(prefix.length)];
        DateTime? until;
        if (plan != null) {
          final source = await _source(plan);
          if (source == null) effective.remove(plan.stableKey);
          final currentFingerprint = source == null
              ? null
              : await fingerprint(source);
          try {
            final value = jsonDecode(row['value'] as String) as Map;
            if (source != null &&
                currentFingerprint == value['source'] &&
                value['signature'] == signature(plan)) {
              until = DateTime.parse(value['until'] as String);
            }
          } catch (_) {
            // Corrupt device preference cancels the snooze, never the record.
          }
        }
        if (identity != database.personalIdentityGeneration) {
          throw const CollaborationException('session_changed');
        }
        if (until == null) {
          await database.execute('DELETE FROM local_meta WHERE name=?', [name]);
        } else {
          effective[plan!.stableKey] = ReminderPlan(
            stableKey: plan.stableKey,
            scheduledAt: until,
            target: plan.target,
            reason: plan.reason,
          );
        }
      }
    });
    return effective.values.toList();
  }
}
