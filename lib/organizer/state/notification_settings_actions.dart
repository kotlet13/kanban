import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'collaboration_provider.dart';
import 'local_notification_preferences_provider.dart';
import 'notification_local_spaces_provider.dart';
import '../platform/notification_providers.dart';
import '../platform/remote_push/remote_push_providers.dart';

final notificationSettingsActionsProvider = Provider(
  NotificationSettingsActions.new,
);

class NotificationSettingsActions {
  NotificationSettingsActions(this.ref);
  final Ref ref;
  String? get identity {
    final session = ref.read(collaborationProvider).valueOrNull?.session;
    return session == null ? null : pushDeviceKey(session);
  }

  void _check(String? expected) {
    if (identity != expected) {
      throw const CollaborationException('session_changed');
    }
  }

  Future<void> change({
    required String channel,
    required bool enabled,
    required String? expectedIdentity,
    Iterable<String> scopeIds = const [],
    String? category,
    bool includeLocal = false,
    String? workspace,
    String? project,
    bool all = false,
  }) async {
    _check(expectedIdentity);
    final shared = ref.read(collaborationProvider).valueOrNull;
    final ids = scopeIds.toList();
    if (ids.isNotEmpty) {
      if (shared?.session == null) {
        throw const CollaborationException('auth_required');
      }
      await ref
          .read(collaborationProvider.notifier)
          .setNotificationChannel(
            scopeIds: ids,
            channel: channel,
            enabled: enabled,
            expectedPartition: shared!.session!.partition,
            category: category,
          );
      _check(expectedIdentity);
    }
    if (!all &&
        channel == 'push' &&
        (category == null || category == 'reminders')) {
      for (final id in ids) {
        await ref
            .read(localNotificationPreferencesProvider.notifier)
            .change(
              'push',
              enabled,
              stillCurrent: () => identity == expectedIdentity,
              workspace: sharedDeviceNotificationWorkspace(
                shared!.session!.partition,
                id,
              ),
            );
        _check(expectedIdentity);
      }
    }
    if (includeLocal && channel != 'email') {
      await ref
          .read(localNotificationPreferencesProvider.notifier)
          .change(
            channel,
            enabled,
            workspace: workspace,
            project: project,
            stillCurrent: () => identity == expectedIdentity,
            resetWorkspaces: all
                ? {
                    for (final snapshot
                        in ref
                                .read(notificationLocalSnapshotsProvider)
                                .valueOrNull ??
                            [])
                      snapshot.workspaceKey,
                    if (shared?.session != null)
                      for (final id in ids)
                        sharedDeviceNotificationWorkspace(
                          shared!.session!.partition,
                          id,
                        ),
                  }
                : null,
          );
      _check(expectedIdentity);
      if (channel == 'push' && enabled) {
        final adapter = await ref.read(localNotificationAdapterProvider.future);
        _check(expectedIdentity);
        await adapter.requestPermission();
        _check(expectedIdentity);
        ref.read(localNotificationDeviceStatusProvider.notifier).state =
            AsyncData(adapter.status);
      }
    }
    // A user enabling push opts this supported device in, too. Preferences on
    // other devices still belong to this account; platform consent remains local.
    if (channel == 'push' &&
        (ids.isNotEmpty || all) &&
        (enabled || all) &&
        shared?.session != null &&
        ref.read(remotePushSdkProvider).supported &&
        ref.read(remotePushConfigurationProvider) != null) {
      _check(expectedIdentity);
      final optIns = await ref.read(remotePushOptInProvider.future);
      _check(expectedIdentity);
      if (optIns[pushDeviceKey(shared!.session!)] != enabled) {
        await ref
            .read(remotePushOptInProvider.notifier)
            .save(shared.session!, enabled);
        _check(expectedIdentity);
        ref.read(remotePushPermissionRequestProvider.notifier).state++;
      }
    }
  }
}
