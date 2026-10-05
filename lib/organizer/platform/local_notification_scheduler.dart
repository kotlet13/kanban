import '../domain/notification_models.dart';

enum LocalNotificationPermission { unsupported, unknown, denied, granted }

class LocalNotificationRequest {
  const LocalNotificationRequest({
    required this.plan,
    required this.title,
    required this.body,
    this.sound = false,
  });
  final ReminderPlan plan;
  final String title, body;
  final bool sound;
}

class LocalNotificationStatus {
  const LocalNotificationStatus({
    required this.permission,
    this.timezone,
    this.scheduledCount = 0,
    this.deferredCount = 0,
    this.inexact = false,
  });
  final LocalNotificationPermission permission;
  final String? timezone;
  final int scheduledCount, deferredCount;
  final bool inexact;
}

/// Injectable plugin seam: tests verify schedule/cancel/launch behavior without
/// pretending that a test runner can deliver an operating-system notification.
abstract interface class LocalNotificationScheduler {
  bool get supported;
  bool get inexact;
  Future<String?> initialize(void Function(String payload) onOpen);
  Future<LocalNotificationPermission> permissionStatus();
  Future<LocalNotificationPermission> requestPermission();
  Future<String> refreshTimezone();
  Future<Set<int>> pendingIds();
  Future<void> schedule(
    int id,
    LocalNotificationRequest request,
    String payload,
  );
  Future<void> cancel(int id);
}
