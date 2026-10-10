import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'invitation_link_providers.dart';
import 'invitation_link.dart';
import '../../state/collaboration_provider.dart';
import '../../data/pending_invitation_store.dart'
    show PendingInvitationStoreSerialization;

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
  int _deliveryGeneration = 0;
  late final _receiver = InvitationLinkReceiver(
    onLink: (link) => unawaited(_receive(link)),
    onInvalid: () {
      if (mounted) ref.read(invitationLinkErrorProvider.notifier).state = true;
    },
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _receive(InvitationLink link) async {
    final generation = ++_deliveryGeneration;
    try {
      final store = ref.read(pendingInvitationStoreProvider);
      await store.receiveLink(
        serverUrl: link.serverUrl,
        token: link.token,
        isCurrent: () => mounted && generation == _deliveryGeneration,
      );
      if (!mounted || generation != _deliveryGeneration) return;
      final pending = ref.read(pendingInvitationLinkProvider);
      if (pending?.token != link.token ||
          pending?.serverUrl != link.serverUrl) {
        ref.read(pendingInvitationLinkProvider.notifier).state = link;
      }
      ref.invalidate(securePendingInvitationProvider);
    } catch (_) {
      if (mounted && generation == _deliveryGeneration) {
        ref.read(invitationLinkErrorProvider.notifier).state = true;
      }
    }
  }

  Future<void> _start() async {
    try {
      final pending = await ref.read(pendingInvitationStoreProvider).read();
      if (!mounted) return;
      if (pending != null) {
        final session = pending.accountPartition == null
            ? null
            : await ref.read(deviceSessionStoreProvider).read();
        if (!mounted) return;
        if (pending.accountPartition == null ||
            pending.accountPartition == session?.profile.partition) {
          ref
              .read(pendingInvitationLinkProvider.notifier)
              .state = InvitationLink(
            serverUrl: pending.serverUrl,
            token: pending.token,
          );
        }
      }
    } catch (_) {
      if (mounted) ref.read(invitationLinkErrorProvider.notifier).state = true;
    }
    if (!mounted) return;
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
