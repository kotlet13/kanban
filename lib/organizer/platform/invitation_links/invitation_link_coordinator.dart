import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'invitation_link_providers.dart';
import 'invitation_link.dart';
import '../email_verification/email_verification_link.dart';
import '../email_verification/email_verification_link_review.dart';
import '../../../app_router.dart';
import '../../presentation/recovery/account_crypto_startup.dart';
import '../../state/collaboration_provider.dart';
import '../../data/collaboration_transport.dart'
    show normalizeCollaborationServer;
import '../../data/pending_invitation_store.dart'
    show PendingInvitationStoreSerialization;

class InvitationLinkCoordinator extends ConsumerStatefulWidget {
  const InvitationLinkCoordinator({
    super.key,
    required this.child,
    this.navigatorKey,
  });
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  @override
  ConsumerState<InvitationLinkCoordinator> createState() =>
      _InvitationLinkCoordinatorState();
}

class _InvitationLinkCoordinatorState
    extends ConsumerState<InvitationLinkCoordinator> {
  StreamSubscription<Uri>? _subscription;
  int _deliveryGeneration = 0;
  bool _bootstrapping = true;
  final _bufferedLinks = <Uri>[];
  Uri? _initialEcho;
  Timer? _echoExpiry;
  bool _sameLink(Uri a, Uri? b) {
    if (b == null) return false;
    final emailLeft = EmailVerificationLink.tryParse(a),
        emailRight = EmailVerificationLink.tryParse(b);
    if (emailLeft != null && emailRight != null) {
      return emailLeft.toUri().toString() == emailRight.toUri().toString();
    }
    final left = InvitationLink.tryParse(a), right = InvitationLink.tryParse(b);
    return left != null &&
        right != null &&
        left.token == right.token &&
        normalizeCollaborationServer(left.serverUrl) ==
            normalizeCollaborationServer(right.serverUrl);
  }

  void _streamLink(Uri uri) {
    if (_bootstrapping) {
      _bufferedLinks.add(uri);
      if (_bufferedLinks.length > 16) _bufferedLinks.removeAt(0);
      return;
    }
    final echo = _initialEcho;
    _initialEcho = null;
    if (_sameLink(uri, echo)) return;
    unawaited(_dispatch(uri, automatic: false));
  }

  Future<bool> _dispatch(Uri uri, {required bool automatic}) async {
    final emailLink = EmailVerificationLink.tryParse(uri);
    if (emailLink != null) {
      // Keep the invitation store and its delivery generation untouched. A mail
      // verification link has no authority over the existing invitation wizard.
      try {
        await ref.read(collaborationProvider.future);
      } catch (_) {}
      if (!mounted) return false;
      // The required startup page may arrive after the account session. Wait
      // for its shared assessment and push frame so review stays above it.
      try {
        await ref.read(accountCryptoStartupActionProvider.future);
      } catch (_) {}
      if (!mounted) return false;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return false;
      final navigatorContext =
          (widget.navigatorKey ?? appRouter.routerDelegate.navigatorKey)
              .currentContext;
      if (navigatorContext == null || !navigatorContext.mounted) return false;
      unawaited(
        showDialog<void>(
          context: navigatorContext,
          builder: (_) => EmailVerificationLinkReview(link: emailLink),
        ),
      );
      return false;
    }
    final parsed = InvitationLink.tryParse(uri);
    if (parsed == null) {
      if (mounted) ref.read(invitationLinkErrorProvider.notifier).state = true;
      return false;
    }
    return _receive(parsed, automatic: automatic);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<bool> _receive(InvitationLink link, {bool automatic = false}) async {
    final generation = ++_deliveryGeneration;
    try {
      final store = ref.read(pendingInvitationStoreProvider);
      final received = await store.receiveLink(
        serverUrl: link.serverUrl,
        token: link.token,
        automatic: automatic,
        isCurrent: () => mounted && generation == _deliveryGeneration,
      );
      if (!received || !mounted || generation != _deliveryGeneration) {
        return false;
      }
      return await store.serialized(() async {
        final saved = await store.read();
        if (!mounted ||
            generation != _deliveryGeneration ||
            saved?.token != link.token ||
            saved?.serverUrl != normalizeCollaborationServer(link.serverUrl)) {
          return false;
        }
        if (automatic) {
          if (!await store.mayAutoOpen(saved!)) return false;
          final session = saved.accountPartition == null
              ? null
              : await ref.read(deviceSessionStoreProvider).read();
          if (!mounted ||
              generation != _deliveryGeneration ||
              (saved.accountPartition != null &&
                  saved.accountPartition != session?.profile.partition)) {
            return false;
          }
        }
        final pending = ref.read(pendingInvitationLinkProvider);
        if (pending?.token != link.token ||
            pending?.serverUrl != link.serverUrl) {
          ref.read(pendingInvitationLinkProvider.notifier).state = link;
        }
        ref.invalidate(securePendingInvitationProvider);
        return true;
      });
    } catch (_) {
      if (mounted && generation == _deliveryGeneration) {
        ref.read(invitationLinkErrorProvider.notifier).state = true;
      }
      return false;
    }
  }

  Future<void> _start() async {
    final source = ref.read(invitationLinkSourceProvider);
    Uri? initial;
    var initialKnown = source == null;
    if (source != null) {
      try {
        // Subscribe before any storage waits. Buffer bootstrap stream events so
        // the plugin's initial echo is distinguishable from a newer live link.
        _subscription = source.links.listen(
          _streamLink,
          onError: (Object error) {
            if (error is! MissingPluginException && mounted) {
              ref.read(invitationLinkErrorProvider.notifier).state = true;
            }
          },
        );
        initial = await source.initialLink().timeout(
          const Duration(seconds: 2),
        );
        initialKnown = true;
      } on MissingPluginException {
        initialKnown = true;
      } on TimeoutException {
        // Do not keep startup waiting or later deliver an obsolete initial URI.
      } catch (_) {
        if (mounted) {
          ref.read(invitationLinkErrorProvider.notifier).state = true;
        }
      }
    }
    if (!mounted) return;
    final distinct = _bufferedLinks.where((uri) => !_sameLink(uri, initial));
    final buffered = distinct.isNotEmpty
        ? distinct.last
        : (_bufferedLinks.isEmpty ? null : _bufferedLinks.last);
    _bufferedLinks.clear();
    _initialEcho = buffered == null ? initial : null;
    if (_initialEcho != null) {
      // Native bootstrap echoes can arrive just after getInitialLink. Do not
      // suppress a user's later warm click indefinitely when no echo arrives.
      _echoExpiry = Timer(
        const Duration(seconds: 1),
        () => _initialEcho = null,
      );
    }
    _bootstrapping = false;
    final incoming = buffered ?? initial;
    if (incoming != null &&
        await _dispatch(
          incoming,
          automatic:
              buffered == null || !initialKnown || _sameLink(buffered, initial),
        )) {
      return;
    }
    if (!mounted) return;
    final generation = _deliveryGeneration;
    try {
      final store = ref.read(pendingInvitationStoreProvider);
      final pending = await store.read();
      if (pending == null || !mounted) return;
      final session = pending.accountPartition == null
          ? null
          : await ref.read(deviceSessionStoreProvider).read();
      if (!mounted || generation != _deliveryGeneration) return;
      await store.serialized(() async {
        // Acceptance, Back, or a newer link may have changed storage while the
        // saved device session was loading. Never resurrect that old snapshot.
        final current = await store.read();
        if (current == null ||
            current.token != pending.token ||
            current.serverUrl != pending.serverUrl ||
            !await store.mayAutoOpen(current) ||
            !mounted ||
            generation != _deliveryGeneration) {
          return;
        }
        if (current.accountPartition == null ||
            current.accountPartition == session?.profile.partition) {
          ref
              .read(pendingInvitationLinkProvider.notifier)
              .state = InvitationLink(
            serverUrl: current.serverUrl,
            token: current.token,
          );
        }
      });
    } catch (_) {
      if (mounted && generation == _deliveryGeneration) {
        ref.read(invitationLinkErrorProvider.notifier).state = true;
      }
    }
  }

  @override
  void dispose() {
    _echoExpiry?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
