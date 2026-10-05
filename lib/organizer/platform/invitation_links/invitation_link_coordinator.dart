import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'invitation_link_providers.dart';

class InvitationLinkCoordinator extends ConsumerStatefulWidget {
  const InvitationLinkCoordinator({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<InvitationLinkCoordinator> createState() =>
      _InvitationLinkCoordinatorState();
}

class _InvitationLinkCoordinatorState
    extends ConsumerState<InvitationLinkCoordinator> {
  StreamSubscription<Uri>? _subscription;
  late final _receiver = InvitationLinkReceiver(
    onLink: (link) {
      if (mounted) {
        final pending = ref.read(pendingInvitationLinkProvider);
        if (pending?.token != link.token ||
            pending?.serverUrl != link.serverUrl) {
          ref.read(pendingInvitationLinkProvider.notifier).state = link;
        }
      }
    },
    onInvalid: () {
      if (mounted) ref.read(invitationLinkErrorProvider.notifier).state = true;
    },
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final source = ref.read(invitationLinkSourceProvider);
    if (source == null) return;
    try {
      _subscription = source.links.listen(
        _receiver.receive,
        onError: (Object error) {
          if (error is! MissingPluginException && mounted) {
            ref.read(invitationLinkErrorProvider.notifier).state = true;
          }
        },
      );
      final initial = await source.initialLink();
      if (mounted && initial != null) _receiver.receiveInitial(initial);
    } on MissingPluginException {
      // No native link handler in widget tests or unsupported desktop setups.
    } catch (_) {
      if (mounted) ref.read(invitationLinkErrorProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
