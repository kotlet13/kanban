import 'dart:convert';
import 'dart:collection';

import '../domain/collaboration_models.dart';
import 'collaboration_database.dart';
import '../domain/inbox_retention.dart';

/// A Set remains compatible with existing callers and injected test stores;
/// the durable dates also let the projection remove expired notifications.
class FinanceInboxReadKeys extends SetBase<String> {
  FinanceInboxReadKeys(Map<String, DateTime> dates)
    : readAt = Map.unmodifiable(dates);
  final Map<String, DateTime> readAt;
  bool expired(String key, DateTime now) => inboxReadExpired(readAt[key], now);
  @override
  int get length => readAt.length;
  @override
  Iterator<String> get iterator => readAt.keys.iterator;
  @override
  bool contains(Object? value) => readAt.containsKey(value);
  @override
  String? lookup(Object? value) => contains(value) ? value as String : null;
  @override
  bool add(String value) => throw UnsupportedError('Immutable receipts');
  @override
  bool remove(Object? value) => throw UnsupportedError('Immutable receipts');
  @override
  Set<String> toSet() => readAt.keys.toSet();
}

/// Read receipts contain references/timestamps only, separate from money records.
class FinanceInboxStore {
  FinanceInboxStore(this.database, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final CollaborationDatabase database;
  final DateTime Function() clock;
  static String name(String key) => 'finance_inbox_read:$key';
  Future<Set<String>> readKeys(Iterable<ReminderPlan> plans) async {
    final identity = database.personalIdentityGeneration;
    final keys = plans.map((p) => p.stableKey).toSet(),
        result = <String, DateTime>{};
    for (final key in keys) {
      final rows = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [name(key)],
      );
      if (rows.isEmpty) continue;
      if (identity != database.personalIdentityGeneration) return <String>{};
      var date = DateTime.tryParse(rows.single['value'] as String);
      if (date == null) {
        // Legacy receipts have no trustworthy age. Start their full retention
        // window once, instead of deleting them based on notification creation.
        date = clock().toUtc();
        await database.execute(
          'UPDATE local_meta SET value=? WHERE name=? AND value=?',
          [date.toIso8601String(), name(key), rows.single['value']],
        );
        final current = await database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          [name(key)],
        );
        if (current.isEmpty) continue;
        date = DateTime.parse(current.single['value'] as String);
      }
      result[key] = date;
    }
    if (identity != database.personalIdentityGeneration) return <String>{};
    return FinanceInboxReadKeys(result);
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
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO NOTHING',
        [name(plan.stableKey), clock().toUtc().toIso8601String()],
      );
      if (identity != database.personalIdentityGeneration || !stillVisible()) {
        throw const CollaborationException('session_changed');
      }
    });
  }

  Future<void> _verify(NotificationTarget target) async {
    if (target.records.length != 1) {
      throw const CollaborationException('invalid_response');
    }
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
          throw const CollaborationException('permission_revoked');
        }
      }

      final rows = await database.rows(
        "SELECT payload FROM personal_records WHERE workspace=? AND id=? AND type='financeEntry'",
        [workspace, record.recordId],
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
