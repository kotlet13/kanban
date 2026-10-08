import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/notification_models.dart';
import 'local_notification_scheduler.dart';

/// Reconciles the nearest 60 requests (below Apple's 64 pending limit), using
/// persistent integer IDs. Titles/bodies are generic; routing holds references.
class LocalNotificationAdapter {
  LocalNotificationAdapter({
    required this.scheduler,
    required this.preferences,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final LocalNotificationScheduler scheduler;
  final SharedPreferences preferences;
  final DateTime Function() _now;
  static const _idsKey = 'organizer_notification_ids_v1';
  static const pendingLimit = 60;
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _initialized = false;
  void Function(NotificationTarget)? _onOpen;
  LocalNotificationStatus status = const LocalNotificationStatus(
    permission: LocalNotificationPermission.unknown,
  );

  Future<NotificationTarget?> initialize(
    void Function(NotificationTarget) onOpen,
  ) async {
    _onOpen = onOpen;
    if (_initialized) return null;
    final payload = await scheduler.initialize((payload) {
      final target = _decode(payload);
      if (target != null) _onOpen?.call(target);
    });
    _initialized = true;
    status = LocalNotificationStatus(
      permission: await scheduler.permissionStatus(),
      inexact: scheduler.inexact,
    );
    return payload == null ? null : _decode(payload);
  }

  Future<LocalNotificationPermission> requestPermission() async {
    final permission = await scheduler.requestPermission();
    status = LocalNotificationStatus(
      permission: permission,
      inexact: scheduler.inexact,
    );
    return permission;
  }

  Future<LocalNotificationStatus> reconcile(
    List<LocalNotificationRequest> requests,
  ) {
    final generation = ++_generation;
    final result = _tail.then((_) => _apply(requests, generation));
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<LocalNotificationStatus> _apply(
    List<LocalNotificationRequest> requests,
    int generation,
  ) async {
    if (!_initialized) {
      throw StateError('Local notifications must initialize first');
    }
    if (!scheduler.supported) {
      return status = const LocalNotificationStatus(
        permission: LocalNotificationPermission.unsupported,
      );
    }
    final raw = preferences.getString(_idsKey);
    final saved = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final ids = (saved['ids'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value as int),
    );
    final fingerprints = (saved['fingerprints'] as Map<String, dynamic>? ?? {})
        .map((key, value) => MapEntry(key, value as String));
    var nextId = saved['nextId'] as int? ?? 1;
    final active = {
      for (final request in requests) request.plan.stableKey: request,
    };
    // Cleanup precedes timezone and permission calls. Logout/revocation must
    // cancel known old reminders even when device timezone lookup fails.
    for (final key
        in ids.keys.where((key) => !active.containsKey(key)).toList()) {
      await scheduler.cancel(ids[key]!);
      ids.remove(key);
      fingerprints.remove(key);
    }
    final now = _now();
    // A past request can retain an inexact alarm only if it is the same
    // request previously scheduled. Date/content changes cancel even delivered
    // IDs, and never schedule the replacement in the past.
    for (final key in ids.keys.toList()) {
      final request = active[key]!;
      if (request.plan.scheduledAt.isAfter(now)) continue;
      final old = fingerprints[key];
      String? oldTimezone;
      try {
        oldTimezone = (jsonDecode(old ?? '') as List)[1] as String;
      } catch (_) {}
      if (oldTimezone == null || old != _fingerprint(request, oldTimezone)) {
        await scheduler.cancel(ids[key]!);
        ids.remove(key);
        fingerprints.remove(key);
      }
    }
    final pending = await scheduler.pendingIds();
    for (final id in pending.difference(ids.values.toSet())) {
      await scheduler.cancel(id);
    }
    Future<void> persist() async {
      if (!await preferences.setString(
        _idsKey,
        jsonEncode({
          'nextId': nextId,
          'ids': ids,
          'fingerprints': fingerprints,
        }),
      )) {
        throw StateError('Notification identity storage failed');
      }
    }

    await persist();
    if (generation != _generation) return status;
    if (active.isEmpty) {
      return status = LocalNotificationStatus(
        permission: status.permission,
        timezone: status.timezone,
        inexact: scheduler.inexact,
      );
    }
    final permission = await scheduler.permissionStatus();
    if (permission != LocalNotificationPermission.granted) {
      for (final id in ids.values) {
        await scheduler.cancel(id);
      }
      ids.clear();
      fingerprints.clear();
      await persist();
      return status = LocalNotificationStatus(
        permission: permission,
        deferredCount: active.length,
        inexact: scheduler.inexact,
      );
    }
    final timezone = await scheduler.refreshTimezone();
    final future =
        active.values
            .where((request) => request.plan.scheduledAt.isAfter(now))
            .toList()
          ..sort((a, b) => a.plan.scheduledAt.compareTo(b.plan.scheduledAt));
    // Inexact Android alarms may still be pending after their nominal time.
    // Retain them until delivery or source cancellation; never reschedule past.
    final retainedPast = ids.entries
        .where(
          (e) =>
              pending.contains(e.value) &&
              !active[e.key]!.plan.scheduledAt.isAfter(now),
        )
        .length;
    final room = (pendingLimit - retainedPast).clamp(0, pendingLimit);
    final chosen = future.take(room).toList();
    final chosenKeys = chosen.map((r) => r.plan.stableKey).toSet();
    for (final key
        in ids.keys
            .where(
              (key) =>
                  active[key]!.plan.scheduledAt.isAfter(now) &&
                  !chosenKeys.contains(key),
            )
            .toList()) {
      await scheduler.cancel(ids[key]!);
      ids.remove(key);
      fingerprints.remove(key);
    }
    for (final request in chosen) {
      if (!ids.containsKey(request.plan.stableKey)) {
        while (ids.containsValue(nextId)) {
          nextId = nextId >= 2147483646 ? 1 : nextId + 1;
        }
        ids[request.plan.stableKey] = nextId;
        nextId = nextId >= 2147483646 ? 1 : nextId + 1;
      }
    }
    if (generation != _generation) return status;
    await persist();
    for (final request in chosen) {
      if (generation != _generation) return status;
      final key = request.plan.stableKey, id = ids[key]!;
      final payload = jsonEncode(request.plan.target.toJson());
      if (_decode(payload) == null) {
        throw const FormatException('Invalid notification target');
      }
      final fingerprint = _fingerprint(request, timezone);
      if (fingerprints[key] == fingerprint && pending.contains(id)) continue;
      if (fingerprints[key] != null && fingerprints[key] != fingerprint) {
        await scheduler.cancel(id);
      }
      await scheduler.schedule(id, request, payload);
      if (generation != _generation) {
        await scheduler.cancel(id);
        return status;
      }
      fingerprints[key] = fingerprint;
      await persist();
    }
    return status = LocalNotificationStatus(
      permission: permission,
      timezone: timezone,
      scheduledCount: chosen.length + retainedPast,
      deferredCount: future.length - chosen.length,
      inexact: scheduler.inexact,
    );
  }

  String _fingerprint(LocalNotificationRequest request, String timezone) =>
      jsonEncode([
        request.plan.scheduledAt.toUtc().toIso8601String(),
        timezone,
        request.title,
        request.body,
        request.sound,
        jsonEncode(request.plan.target.toJson()),
      ]);

  Future<LocalNotificationStatus> cancelAll() => reconcile(const []);
  void dispose() {
    _generation++;
    _onOpen = null;
  }

  NotificationTarget? _decode(String payload) {
    if (payload.length > 16384) return null;
    try {
      final target = NotificationTarget.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      );
      if (target.records.isEmpty || target.records.length > 100) return null;
      if (!target.isPersonal &&
          [
            target.serverUrl,
            target.serverId,
            target.accountId,
            target.scopeId,
          ].any((value) => value == null || value.isEmpty)) {
        return null;
      }
      const allowed = {
        'task',
        'event',
        'project',
        'shoppingList',
        'shoppingItem',
        'personalFinanceEntry',
        'financeAccount',
        'financeEntry',
        'financeTransfer',
      };
      if (target.records.any(
        (record) => !allowed.contains(record.type) || record.recordId.isEmpty,
      )) {
        return null;
      }
      return target;
    } catch (_) {
      return null;
    }
  }
}
