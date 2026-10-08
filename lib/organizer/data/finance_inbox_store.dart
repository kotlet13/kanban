import 'dart:convert';

import '../domain/collaboration_models.dart';
import 'collaboration_database.dart';

/// Read receipts contain references/timestamps only, separate from money records.
class FinanceInboxStore {
  FinanceInboxStore(this.database, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final CollaborationDatabase database;
  final DateTime Function() clock;
  static String name(String key) => 'finance_inbox_read:$key';
  Future<Set<String>> readKeys(Iterable<ReminderPlan> plans) async {
    final keys = plans.map((p) => p.stableKey).toSet(), result = <String>{};
    for (final key in keys) {
      final rows = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [name(key)],
      );
      if (rows.isNotEmpty) result.add(key);
    }
    return result;
  }

  Future<void> markRead(
    ReminderPlan plan, {
    required bool Function() stillVisible,
  }) async {
    final identity = database.personalIdentityGeneration;
    await database.transaction(() async {
      if (!stillVisible()) {
        throw const CollaborationException('finance_forbidden');
      }
      await _verify(plan.target);
      if (identity != database.personalIdentityGeneration || !stillVisible()) {
        throw const CollaborationException('session_changed');
      }
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        [name(plan.stableKey), clock().toUtc().toIso8601String()],
      );
    });
  }

  Future<void> _verify(NotificationTarget target) async {
    if (target.records.length != 1) {
      throw const CollaborationException('invalid_response');
    }
    final record = target.records.single;
    if (target.isPersonal) {
      final rows = await database.rows(
        "SELECT payload FROM personal_records WHERE workspace='local' AND id=? AND type='financeEntry'",
        [record.recordId],
      );
      if (rows.isEmpty ||
          (jsonDecode(rows.first['payload'] as String) as Map)['status'] !=
              'planned') {
        throw const CollaborationException('record_deleted');
      }
      return;
    }
    final profile = database.personalProfile;
    if (profile == null || !target.matches(profile)) {
      throw const CollaborationException('session_changed');
    }
    final scopes = await database.rows(
      'SELECT data,blocked,finance_policy,finance_blocked,finance_complete FROM scopes WHERE partition=? AND id=?',
      [profile.partition, target.scopeId],
    );
    if (scopes.isEmpty ||
        scopes.first['blocked'] == 1 ||
        scopes.first['finance_blocked'] == 1 ||
        scopes.first['finance_complete'] != 1 ||
        (jsonDecode(scopes.first['data'] as String) as Map)['revoked'] ==
            true ||
        scopes.first['finance_policy'] == null ||
        !SharedFinancePolicy.fromJson(
          jsonDecode(scopes.first['finance_policy'] as String)
              as Map<String, dynamic>,
        ).canRead) {
      throw const CollaborationException('finance_forbidden');
    }
    final rows = await database.rows(
      'SELECT payload,deleted FROM finance_records WHERE partition=? AND scope_id=? AND id=? AND type=?',
      [profile.partition, target.scopeId, record.recordId, record.type],
    );
    if (rows.isEmpty ||
        rows.first['deleted'] == 1 ||
        rows.first['payload'] == null ||
        (jsonDecode(rows.first['payload'] as String) as Map)['status'] !=
            'planned') {
      throw const CollaborationException('record_deleted');
    }
  }
}
