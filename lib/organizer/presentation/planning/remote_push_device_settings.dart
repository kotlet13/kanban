import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../platform/remote_push/remote_push_lifecycle.dart';
import '../../platform/remote_push/remote_push_providers.dart';

class RemotePushDeviceSettings extends ConsumerStatefulWidget {
  const RemotePushDeviceSettings({super.key});
  @override
  ConsumerState<RemotePushDeviceSettings> createState() =>
      _RemotePushDeviceSettingsState();
}

class _RemotePushDeviceSettingsState
    extends ConsumerState<RemotePushDeviceSettings> {
  bool _busy = false;
  Future<void> _change(bool enabled) async {
    final session = ref.read(collaborationProvider).valueOrNull?.session;
    if (session == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(remotePushOptInProvider.notifier).save(session, enabled);
      if (!mounted ||
          !(ref.read(collaborationProvider).valueOrNull?.session?.partition ==
                  session.partition &&
              ref.read(collaborationProvider).valueOrNull?.session?.deviceId ==
                  session.deviceId)) {
        return;
      }
      ref.read(remotePushPermissionRequestProvider.notifier).state++;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.remotePushError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final device = ref.watch(remotePushDeviceStateProvider);
    final shared = ref.watch(collaborationProvider).valueOrNull;
    final session = shared?.session;
    final accountUsable = remotePushAccountUsable(shared);
    final sdk = ref.watch(remotePushSdkProvider);
    final config = ref.watch(remotePushConfigurationProvider);
    final optIn = ref.watch(remotePushOptInProvider).valueOrNull;
    final enabled = session != null && optIn?[pushDeviceKey(session)] == true;
    final phase = !sdk.supported
        ? RemotePushDevicePhase.unsupported
        : ref.watch(remotePushConfigurationInvalidProvider)
        ? RemotePushDevicePhase.invalidConfiguration
        : config == null
        ? RemotePushDevicePhase.unconfigured
        : session == null || !accountUsable
        ? RemotePushDevicePhase.needsAccount
        : device.bindingKey != null &&
              device.bindingKey != pushDeviceKey(session)
        ? RemotePushDevicePhase.disabled
        : device.phase;
    final message = switch (phase) {
      RemotePushDevicePhase.unsupported => l.remotePushUnsupported,
      RemotePushDevicePhase.unconfigured => l.remotePushUnconfigured,
      RemotePushDevicePhase.invalidConfiguration =>
        l.remotePushInvalidConfiguration,
      RemotePushDevicePhase.needsAccount => l.remotePushNeedsAccount,
      RemotePushDevicePhase.disabled => l.remotePushDisabled,
      RemotePushDevicePhase.preparing => l.remotePushPreparing,
      RemotePushDevicePhase.denied => l.remotePushDenied,
      RemotePushDevicePhase.waitingApns => l.remotePushWaitingApns,
      RemotePushDevicePhase.registered => l.remotePushRegistered,
      RemotePushDevicePhase.offline => l.remotePushOffline,
      RemotePushDevicePhase.serverUnavailable =>
        device.errorCode == 'push_project_mismatch'
            ? l.remotePushProjectMismatch
            : l.remotePushServerUnavailable,
      RemotePushDevicePhase.cleanupRequired => l.remotePushCleanupRequired,
      RemotePushDevicePhase.error => l.remotePushError,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.remotePushTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l.remotePushPrivacy),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.remotePushEnable),
          value: enabled,
          onChanged:
              _busy ||
                  !sdk.supported ||
                  config == null ||
                  session == null ||
                  optIn == null ||
                  (!accountUsable && !enabled)
              ? null
              : _change,
        ),
        Text(message),
        if (_busy || phase == RemotePushDevicePhase.preparing)
          const LinearProgressIndicator(),
        if (sdk.supported && config != null && session != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => ref
                        .read(remotePushPermissionRequestProvider.notifier)
                        .state++,
              icon: const Icon(Icons.refresh),
              label: Text(l.remotePushRetry),
            ),
          ),
      ],
    );
  }
}
