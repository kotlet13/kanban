import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../platform/local_notification_scheduler.dart';
import '../../platform/notification_providers.dart';

class DeviceReminderSettings extends ConsumerStatefulWidget {
  const DeviceReminderSettings({super.key});
  @override
  ConsumerState<DeviceReminderSettings> createState() =>
      _DeviceReminderSettingsState();
}

class _DeviceReminderSettingsState
    extends ConsumerState<DeviceReminderSettings> {
  bool _busy = false;
  Future<void> _change(bool enabled, bool sound) async {
    setState(() => _busy = true);
    try {
      final adapter = await ref.read(localNotificationAdapterProvider.future);
      if (!mounted) return;
      if (enabled) {
        final permission = await adapter.requestPermission();
        if (!mounted) return;
        ref.read(localNotificationDeviceStatusProvider.notifier).state =
            AsyncData(adapter.status);
        if (permission != LocalNotificationPermission.granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                permission == LocalNotificationPermission.unsupported
                    ? context.l10n.inboxDeviceUnsupported
                    : context.l10n.inboxDeviceDenied,
              ),
            ),
          );
          return;
        }
      } else {
        await adapter.cancelAll();
      }
      await ref
          .read(localReminderSettingsProvider.notifier)
          .save(enabled: enabled, sound: sound);
    } catch (error, stack) {
      if (mounted) {
        ref.read(localNotificationDeviceStatusProvider.notifier).state =
            AsyncError(error, stack);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.inboxDeviceError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings =
        ref.watch(localReminderSettingsProvider).valueOrNull ??
        const LocalReminderSettings();
    final status = ref.watch(localNotificationDeviceStatusProvider);
    final supported =
        status.valueOrNull?.permission !=
        LocalNotificationPermission.unsupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.inboxDeviceSettings,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l.inboxDevicePrivacy),
        if (_busy) const LinearProgressIndicator(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.inboxDeviceEnable),
          value: settings.enabled,
          onChanged: _busy || !supported
              ? null
              : (enabled) => _change(enabled, settings.sound),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.inboxSound),
          value: settings.sound,
          onChanged: _busy || !settings.enabled || !supported
              ? null
              : (sound) => _change(settings.enabled, sound),
        ),
        status.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => Text(l.inboxDeviceError),
          data: (device) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (device.permission) {
                LocalNotificationPermission.unsupported =>
                  l.inboxDeviceUnsupported,
                LocalNotificationPermission.unknown => l.inboxDeviceUnknown,
                LocalNotificationPermission.denied => l.inboxDeviceDenied,
                LocalNotificationPermission.granted => l.inboxDeviceGranted,
              }),
              if (device.inexact) Text(l.inboxDeviceInexact),
              if (device.deferredCount > 0)
                Text(l.inboxDeviceLimit(device.deferredCount)),
              if (settings.enabled &&
                  device.permission == LocalNotificationPermission.granted)
                Text(l.inboxDeviceScheduled(device.scheduledCount)),
            ],
          ),
        ),
      ],
    );
  }
}
