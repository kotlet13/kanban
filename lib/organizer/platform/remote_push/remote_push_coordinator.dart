import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/collaboration_provider.dart';
import 'remote_push_lifecycle.dart';
import 'remote_push_providers.dart';

class RemotePushCoordinator extends ConsumerStatefulWidget {
  const RemotePushCoordinator({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<RemotePushCoordinator> createState() =>
      _RemotePushCoordinatorState();
}

class _RemotePushCoordinatorState extends ConsumerState<RemotePushCoordinator>
    with WidgetsBindingObserver {
  int _generation = 0;
  String? _language;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _update(force: true);
  }

  Future<void> _update({bool prompt = false, bool force = false}) async {
    final generation = ++_generation;
    if (!mounted) return;
    final shared = ref.read(collaborationProvider);
    final optIn = ref.read(remotePushOptInProvider);
    if (shared.isLoading || !optIn.hasValue) return;
    final data = shared.valueOrNull, session = data?.session;
    final identity = session == null
        ? null
        : RemotePushIdentity.fromSession(session);
    final binding = session == null
        ? null
        : RemotePushBinding(
            identity: identity!,
            session: session,
            optedIn: optIn.requireValue[pushDeviceKey(session)] == true,
            serverSupported: data!.externalPushSupported,
            serverProjectId: data.pushProjectId,
            accountUsable: remotePushAccountUsable(data),
            blockedReason:
                data.remotePushRegistration.status ==
                    RemotePushRegistrationStatus.blocked
                ? data.remotePushRegistration.errorCode ??
                      'push_registration_blocked'
                : null,
            language: _language == 'sl' ? 'sl' : 'en',
          );
    try {
      final lifecycle = await ref.read(remotePushLifecycleProvider.future);
      if (!mounted || generation != _generation) return;
      final current = ref.read(collaborationProvider);
      if (current.isLoading ||
          (identity != null &&
              !(current.valueOrNull?.session != null &&
                  identity.matches(current.requireValue.session!))) ||
          (identity == null && current.valueOrNull?.session != null)) {
        return;
      }
      await lifecycle.update(binding, requestPermission: prompt, force: force);
      if (mounted && generation == _generation && data != null) {
        // Do not replace a newer registration produced by this SDK operation.
        final now = ref.read(collaborationProvider).valueOrNull;
        if (identity != null &&
            now?.remotePushRegistration.identity?.same(identity) == true) {
          lifecycle.applyRegistration(now!.remotePushRegistration);
        }
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        ref
            .read(remotePushDeviceStateProvider.notifier)
            .state = const RemotePushDeviceState(
          RemotePushDevicePhase.invalidConfiguration,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(collaborationProvider, (_, _) => _update());
    ref.listen(remotePushOptInProvider, (_, _) => _update());
    ref.listen(
      remotePushPermissionRequestProvider,
      (_, _) => _update(prompt: true, force: true),
    );
    ref.watch(remotePushOptInProvider);
    final language = Localizations.localeOf(context).languageCode;
    if (_language != language) {
      _language = language;
      WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    }
    return widget.child;
  }
}
