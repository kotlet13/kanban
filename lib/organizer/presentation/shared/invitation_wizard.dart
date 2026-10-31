import 'dart:async';
import 'dart:convert';
import '../../data/e2ee/invite_crypto_repository.dart';
import '../../data/e2ee/crypto_json.dart';
import '../../data/collaboration_repository.dart' show newSharedId;
import '../../data/pending_invitation_store.dart'
    show PendingInvitationStoreSerialization;
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/session_crypto_access.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../platform/invitation_links/invitation_link.dart';
import '../../platform/invitation_links/invitation_link_providers.dart';
import '../../state/collaboration_provider.dart';
import '../../state/account_summary_refresh_provider.dart';
import '../../data/collaboration_transport.dart'
    show normalizeCollaborationServer;
import '../onboarding/account_recovery_actions.dart';
import '../password_visibility.dart';
import 'content_moderation.dart';
import 'sharing_errors.dart';
import 'hosting_disclosure.dart';
import 'sharing_invitation_details.dart';
import 'verified_invitation_permissions.dart';
import 'sharing_session_boundary.dart';
import '../recovery/account_crypto_wizard.dart';

/// A separate route keeps the invitation alive while authentication and password
/// recovery change screens. Closing this route never discards its secure record.
Future<void> showInvitationWizard(
  BuildContext context,
  WidgetRef ref, {
  InvitationLink? initialLink,
  ValueChanged<String>? onAccepted,
  bool originConfirmed = false,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => InvitationWizard(
      initialLink: initialLink,
      onAccepted: onAccepted,
      originConfirmed: originConfirmed,
    ),
  ),
);

bool _sameServer(String? a, String? b) {
  if (a == null || b == null) return false;
  try {
    return normalizeCollaborationServer(a) == normalizeCollaborationServer(b);
  } on CollaborationException {
    return false;
  }
}

enum _InvitationStep { input, origin, preview, login, register }

class InvitationWizard extends ConsumerStatefulWidget {
  const InvitationWizard({
    super.key,
    this.initialLink,
    this.onAccepted,
    this.originConfirmed = false,
    this.cryptoRepository,
  });
  final InvitationLink? initialLink;
  final ValueChanged<String>? onAccepted;
  final bool originConfirmed;
  final InviteCryptoRepository Function(AccountCryptoV2Workflow)?
  cryptoRepository;

  @override
  ConsumerState<InvitationWizard> createState() => _InvitationWizardState();
}

class _InvitationWizardState extends ConsumerState<InvitationWizard>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _input = TextEditingController();
  final _code = TextEditingController();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _otp = TextEditingController();
  _InvitationStep _step = _InvitationStep.input;
  InvitationLink? _link;
  SharedInvitationPreview? _preview;
  VerifiedCryptoInvitation? _verifiedInvitation;
  String? _verifiedIdentity;
  InvitationLink? _verifiedLink;
  String? _error, _notice;
  Object? _lastError;
  bool _busy = true, _needsOtp = false, _joined = false;
  int _generation = 0;
  String? _pinnedServerId, _boundPartition, _joinedIdentity;
  bool _superseded = false;
  bool _cryptoPending = false;
  String? _acceptedRecipientIdentity;
  bool _declined = false, _recipientVerifiedForDecline = false;
  String? _declinedIdentity;
  InvitationLink? _declinedLink;
  late final _declineActionId = newSharedId();
  bool _preauthorizedAccepted = false;
  bool _cryptoSetupRequired = false;
  bool _routeWasCurrent = true, _refreshPreviewOnReturn = false;
  final _accessRefreshClock = Stopwatch()..start();
  Duration? _lastAccessRefresh;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_cryptoPending ||
        _busy ||
        !_active ||
        !_matchingSession ||
        ModalRoute.of(context)?.isCurrent != true ||
        (_lastAccessRefresh != null &&
            _accessRefreshClock.elapsed - _lastAccessRefresh! <
                const Duration(seconds: 5))) {
      return;
    }
    _refreshPendingAccess();
  }

  // A lifecycle refresh only checks an already accepted invitation. It never
  // invokes accept, creates a grant, or replaces the saved capability.
  Future<void> _refreshPendingAccess({
    bool allowSetup = false,
  }) => _run(() async {
    _lastAccessRefresh = _accessRefreshClock.elapsed;
    final link = _link;
    final identity = _identity;
    if (link == null || !_active || !_matchingSession) return;
    bool current() =>
        mounted &&
        _active &&
        _matchingSession &&
        _identity == identity &&
        _link?.token == link.token &&
        _sameServer(_link?.serverUrl, link.serverUrl);
    final repository = await ref.read(collaborationRepositoryProvider.future);
    if (!current()) return;
    final workflow = await repository.connectedCryptoAccount();
    if (!current()) return;
    final saved = await ref.read(pendingInvitationStoreProvider).read();
    if (!current()) return;
    if (saved?.token != link.token ||
        !_sameServer(saved?.serverUrl, link.serverUrl) ||
        saved?.serverId != null && saved!.serverId != _session?.serverId ||
        saved?.accountPartition != null &&
            saved!.accountPartition != workflow.store.partition) {
      throw const CollaborationException('session_changed');
    }
    // A link opened after acceptance in the inbox may have no account-bound
    // link checkpoint. Its current preview ID can only request status;
    // resumeAccepted still requires the exact local signed intent to activate.
    final invitationId = saved?.accountPartition == workflow.store.partition
        ? saved?.invitationId ?? _preview?.invitationId
        : _preview?.invitationId;
    if (invitationId == null) {
      throw const CollaborationException('invitation_invalid');
    }
    final phase = await workflow.localPhase();
    if (!current()) return;
    if (phase != 'ready') {
      if (!allowSetup || !mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AccountCryptoWizard(workflow: workflow),
        ),
      );
      if (!current()) return;
      final ready = await workflow.localPhase();
      if (!current() || ready != 'ready') return;
    }
    final target = await _cryptoInvites(workflow).resumeAccepted(invitationId);
    if (!current()) return;
    if (target != null) await _openEncryptedTarget(target, link);
  });

  bool get _active {
    final incoming = ref.read(pendingInvitationLinkProvider);
    return mounted &&
        !_superseded &&
        (incoming == null ||
            (incoming.token == _link?.token &&
                _sameServer(incoming.serverUrl, _link?.serverUrl)));
  }

  AccountSession? get _session =>
      ref.read(collaborationProvider).valueOrNull?.session;
  String? get _identity =>
      _session == null ? null : '${_session!.partition}:${_session!.deviceId}';
  bool get _reviewMatchesCurrent =>
      _verifiedInvitation != null &&
      _verifiedIdentity == _identity &&
      _verifiedLink?.token == _link?.token &&
      _sameServer(_verifiedLink?.serverUrl, _link?.serverUrl) &&
      _matchingSession;
  bool get _hasMatchedRecipient {
    if (!_matchingSession) return false;
    if (_joined || _acceptedRecipientIdentity == _identity) return true;
    if (!_reviewMatchesCurrent) return false;
    final verified = _verifiedInvitation!;
    final signed = verifiedInvitationPayload(verified);
    final recipient = verified.legacyEvidence == null
        ? signed['recipient'] as Map
        : verified.invitation['recipient'] as Map;
    if (recipient['accountId'] is String) {
      return recipient['accountId'] == _session!.accountId;
    }
    if (recipient['kind'] == 'username') {
      return (recipient['value'] as String).toLowerCase() ==
          _session!.username.toLowerCase();
    }
    return _recipientVerifiedForDecline;
  }

  bool get _matchingSession {
    final state = ref.read(collaborationProvider).valueOrNull;
    return state != null &&
        !state.sessionInvalid &&
        !state.deletionPending &&
        (_joinedIdentity == null || _joinedIdentity == _identity) &&
        _sameServer(_session?.serverUrl, _link?.serverUrl) &&
        (_pinnedServerId == null || _session?.serverId == _pinnedServerId) &&
        (_boundPartition == null || _session?.partition == _boundPartition) &&
        _session?.expiresAt.isAfter(DateTime.now()) == true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    final generation = ++_generation;
    try {
      final saved = await ref.read(pendingInvitationStoreProvider).read();
      if (!mounted || generation != _generation) return;
      _server.text = _session?.serverUrl ?? '';
      final link =
          widget.initialLink ??
          (saved == null
              ? null
              : InvitationLink(serverUrl: saved.serverUrl, token: saved.token));
      if (link == null) return;
      _link = link;
      if (_sameServer(saved?.serverUrl, link.serverUrl) &&
          saved?.token == link.token) {
        _pinnedServerId = saved?.serverId;
        _boundPartition = saved?.accountPartition;
      }
      _server.text = link.serverUrl;
      if (!_active) return;
      await ref.read(collaborationProvider.future);
      if (!mounted || generation != _generation || !_active) return;
      // Storage is local-only; destination confirmation still precedes every
      // capability preview or credential request.
      await ref
          .read(collaborationProvider.notifier)
          .rememberInvitation(serverUrl: link.serverUrl, token: link.token);
      if (!_active) return;
      // A previous preview pinned the origin after its explicit confirmation.
      final confirmed =
          widget.originConfirmed ||
          _matchingSession ||
          (_sameServer(saved?.serverUrl, link.serverUrl) &&
              saved?.token == link.token &&
              saved?.serverId != null);
      if (confirmed) {
        await _loadPreview();
      } else {
        _step = _InvitationStep.origin;
      }
    } catch (error) {
      if (mounted) {
        _lastError = error;
        _error = sharingErrorMessage(context, error);
      }
    } finally {
      if (mounted) {
        if (_superseded) {
          Navigator.of(context).pop();
        } else if (generation == _generation) {
          setState(() => _busy = false);
        }
      }
    }
  }

  Future<void> _openInput() async {
    final link = InvitationLink.tryParseInput(
      _input.text.trim().isNotEmpty ? _input.text : _code.text,
      serverUrl: _server.text.trim(),
    );
    if (link == null) {
      setState(() => _error = context.l10n.inviteLinkInvalid);
      return;
    }
    setState(() {
      _link = link;
      _preview = null;
      _error = null;
      _step = _InvitationStep.origin;
    });
    await _run(() async {
      if (!_active) return;
      await ref
          .read(collaborationProvider.notifier)
          .rememberInvitation(serverUrl: link.serverUrl, token: link.token);
      if (_active && _matchingSession) await _loadPreview();
    });
  }

  Future<void> _loadPreview() async {
    final link = _link!;
    final identity = _identity;
    var acceptedCheckpoint = false;
    setState(() {
      _verifiedInvitation = null;
      _recipientVerifiedForDecline = false;
      _verifiedIdentity = null;
      _verifiedLink = null;
      _cryptoSetupRequired = false;
      _preauthorizedAccepted = false;
    });
    final controller = ref.read(collaborationProvider.notifier);
    await controller.rememberInvitation(
      serverUrl: link.serverUrl,
      token: link.token,
    );
    if (!_active || _identity != identity) return;
    if (_matchingSession) {
      final saved = await ref.read(pendingInvitationStoreProvider).read();
      if (saved?.token == link.token &&
          saved?.invitationId != null &&
          saved?.accountPartition == _session?.partition) {
        acceptedCheckpoint = true;
        _acceptedRecipientIdentity = identity;
        setState(() {
          // A saved acceptance can resume before any preview is available.
          // Keep its existing access-check action visible if resumption fails
          // or still lacks verified access; the checkpoint grants no access.
          _step = _InvitationStep.preview;
          _cryptoPending = true;
          _notice = context.l10n.invitationFlowAccessVerificationPending;
        });
        final repository = await ref.read(
          collaborationRepositoryProvider.future,
        );
        final workflow = await repository.connectedCryptoAccount();
        if (await workflow.localPhase() == 'ready') {
          final scope = await _cryptoInvites(
            workflow,
          ).resumeAccepted(saved!.invitationId!);
          if (scope != null) {
            await _openEncryptedTarget(scope, link);
            return;
          }
        }
      }
    }
    final preview = await controller.previewInvitation(
      serverUrl: link.serverUrl,
      token: link.token,
    );
    if (!_active || _identity != identity || _link != link) return;
    setState(() {
      _preview = preview;
      if (preview.contractVersion != 4) {
        _error = null;
        _lastError = null;
      }
      _cryptoPending = preview.awaitingApproval || acceptedCheckpoint;
      _notice = null;
      _step = _InvitationStep.preview;
      if (!preview.isEmailInvitation) {
        _username.text = preview.recipientUsername;
      }
    });
    if (preview.contractVersion == 4 && _matchingSession) {
      final repository = await ref.read(collaborationRepositoryProvider.future);
      if (!_active ||
          !_matchingSession ||
          _identity != identity ||
          _link != link) {
        return;
      }
      final workflow = await repository.connectedCryptoAccount();
      if (!_active ||
          !_matchingSession ||
          _identity != identity ||
          _link != link) {
        return;
      }
      final phase = await workflow.localPhase();
      if (!_active ||
          !_matchingSession ||
          _identity != identity ||
          _link != link) {
        return;
      }
      if (phase != 'ready') {
        setState(() => _cryptoSetupRequired = true);
        return;
      }
      final verified = await _cryptoInvites(
        workflow,
      ).inspect(token: link.token);
      if (!_active ||
          !_matchingSession ||
          _identity != identity ||
          _link != link) {
        return;
      }
      validateInvitationReview(
        verified,
        invitationId: preview.invitationId ?? '',
        scopeId: preview.scopeId,
        creatorAccountId: preview.inviterAccountId,
      );
      var recipientVerifiedForDecline = false;
      if (!_cryptoPending &&
          verified.invitation['state'] == 'pending' &&
          ref
                  .read(collaborationProvider)
                  .valueOrNull
                  ?.invitationDeclineSupported ==
              true) {
        final command =
            CryptoJson.decode(
                  cryptoBase64(verified.authorization['commandBase64']),
                )
                as Map;
        final recipient = (command['payload'] as Map)['recipient'] as Map?;
        if (recipient?['accountId'] is String) {
          recipientVerifiedForDecline =
              recipient!['accountId'] == _session?.accountId;
        } else if (recipient?['kind'] == 'username') {
          recipientVerifiedForDecline =
              (recipient!['value'] as String).toLowerCase() ==
              _session?.username.toLowerCase();
        } else if (recipient == null || recipient['kind'] == 'email') {
          // A token preview is public. Only an authenticated ID lookup can
          // bind an older unbound email invitation to this account.
          try {
            final own = await _cryptoInvites(
              workflow,
            ).inspect(invitationId: preview.invitationId);
            recipientVerifiedForDecline =
                base64Encode(CryptoJson.encode(own.authorization)) ==
                base64Encode(CryptoJson.encode(verified.authorization));
          } catch (_) {
            recipientVerifiedForDecline = false;
          }
        }
      }
      if (!_active ||
          !_matchingSession ||
          _identity != identity ||
          _link != link) {
        return;
      }
      setState(() {
        _error = null;
        _lastError = null;
        _refreshPreviewOnReturn = false;
        _verifiedInvitation = verified;
        _verifiedIdentity = identity;
        _verifiedLink = link;
        _recipientVerifiedForDecline = recipientVerifiedForDecline;
        _preauthorizedAccepted =
            _cryptoPending && isPreauthorizedInvitation(verified);
        if (_cryptoPending) {
          _notice = _preauthorizedAccepted
              ? context.l10n.invitationFlowAccessVerificationPending
              : context.l10n.cryptoInvitationPendingKeys;
        }
      });
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool clearErrorBefore = true,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (clearErrorBefore) {
        _error = null;
        _lastError = null;
      }
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _lastError = error;
          _error = sharingErrorMessage(context, error);
        });
        // Long invitation previews can put the inline error below the viewport.
        // Keep the draft/link in place and make this failed action visible now.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(_error!)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_superseded) Navigator.of(context).pop();
      }
    }
  }

  Future<void> _dismiss() async {
    if (_busy) return;
    final link = _link;
    if (link == null || _superseded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _lastError = null;
    });
    var deferred = false;
    try {
      await ref
          .read(pendingInvitationStoreProvider)
          .deferLink(serverUrl: link.serverUrl, token: link.token);
      deferred = true;
      if (mounted) _consumeRouteHint(link);
    } catch (error) {
      if (mounted) {
        setState(() {
          _lastError = error;
          _error = sharingErrorMessage(context, error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (mounted && (deferred || _superseded)) Navigator.of(context).pop();
  }

  void _consumeRouteHint(InvitationLink link) {
    final incoming = ref.read(pendingInvitationLinkProvider);
    if (incoming?.token == link.token &&
        _sameServer(incoming?.serverUrl, link.serverUrl)) {
      ref.read(pendingInvitationLinkProvider.notifier).state = null;
    }
  }

  String _sessionMismatchMessage(BuildContext context) {
    final l = context.l10n;
    if (!_sameServer(_session?.serverUrl, _link?.serverUrl)) {
      return l.invitationFlowDifferentServer;
    }
    final state = ref.read(collaborationProvider).valueOrNull;
    if (state?.sessionInvalid == true ||
        _session?.expiresAt.isAfter(DateTime.now()) != true) {
      return l.sharingSessionExpired;
    }
    if (_pinnedServerId != null && _session?.serverId != _pinnedServerId) {
      return l.cryptoSharingIdentityChanged;
    }
    return l.sharingAccountChanged;
  }

  Future<void> _authenticate() async {
    if (!_form.currentState!.validate()) return;
    final link = _link!;
    final register = _step == _InvitationStep.register;
    await _run(() async {
      final controller = ref.read(collaborationProvider.notifier);
      try {
        if (register) {
          await controller.registerWithInvitation(
            serverUrl: link.serverUrl,
            invitationToken: link.token,
            username: _username.text.trim(),
            name: _name.text.trim(),
            password: _password.text,
            deviceName: context.l10n.organizerAppName,
          );
        } else {
          await controller.loginForInvitation(
            serverUrl: link.serverUrl,
            invitationToken: link.token,
            username: _username.text.trim(),
            password: _password.text,
            otp: _otp.text.trim().isEmpty ? null : _otp.text.trim(),
            deviceName: context.l10n.organizerAppName,
          );
        }
      } on CollaborationException catch (error) {
        if (mounted) {
          if (error.code == 'two_factor_required') _needsOtp = true;
          if (error.code == 'invitation_authentication_required' ||
              error.code == 'account_created_session_not_saved') {
            _step = _InvitationStep.login;
            _notice = context.l10n.accountCreatedInvitationSignInRequired(
              _username.text.trim(),
            );
          }
        }
        rethrow;
      }
      if (!_active || _link != link) return;
      _password.clear();
      _confirm.clear();
      _otp.clear();
      if (!mounted) return;
      await showAccountCryptoSetupIfAvailable(context, ref);
      if (!_active || _link != link) return;
      if (!_matchingSession ||
          _session?.username.toLowerCase() !=
              _username.text.trim().toLowerCase()) {
        throw const CollaborationException('session_changed');
      }
      // Legacy registration also accepts membership. Do not disguise it as the
      // separate registration/Join contract used by current invitations.
      if (register && _preview?.isEmailInvitation != true) {
        _joined = true;
        _joinedIdentity = _identity;
        await _finishJoined(_preview!);
        return;
      }
      await _loadPreview();
    });
  }

  Future<void> _join() async {
    if (!_matchingSession || _preview == null || _joined) return;
    if (_link!.token.startsWith('fhi4_') || _preview!.contractVersion == 4) {
      await _joinEncrypted();
      return;
    }
    final preview = _preview!, link = _link!;
    final guard = SharingSessionGuard(context, ref);
    await _run(() async {
      try {
        await guard.controller.acceptInvitation(link.token);
      } on CollaborationException catch (error) {
        if (error.code != 'invitation_accepted_refresh_failed') rethrow;
        if (!mounted || !_active || !guard.isCurrent) return;
        setState(() {
          _joined = true;
          _joinedIdentity = _identity;
          _notice = context.l10n.invitationFlowJoinedOpen;
        });
        return;
      }
      if (!mounted || !_active || !guard.isCurrent) return;
      setState(() {
        _joined = true;
        _joinedIdentity = _identity;
        _notice = context.l10n.invitationFlowJoinedOpen;
      });
      await _finishJoined(preview);
    });
  }

  Future<void> _openEncryptedTarget(String scopeId, InvitationLink link) async {
    if (!mounted ||
        !_active ||
        _link?.token != link.token ||
        !_sameServer(_link?.serverUrl, link.serverUrl) ||
        !_matchingSession)
      return;
    final guard = SharingSessionGuard(context, ref);
    await guard.controller.prepareAcceptedScope(scopeId);
    if (!mounted || !_active || !guard.isCurrent || _link?.token != link.token)
      return;
    final scope = ref
        .read(collaborationProvider)
        .valueOrNull
        ?.scopes
        .where((s) => s.id == scopeId && s.canRead)
        .firstOrNull;
    if (scope == null)
      throw const CollaborationException('crypto_reconciliation_required');
    await guard.controller.selectSpace(scopeId);
    if (!mounted || !_active || !guard.isCurrent || _link?.token != link.token)
      return;
    await guard.controller.clearPendingInvitation(expectedToken: link.token);
    if (!mounted || !_active || !guard.isCurrent || _link?.token != link.token)
      return;
    _consumeRouteHint(link);
    setState(() {
      _joined = true;
      _joinedIdentity = _identity;
    });
    // The target is ready. Finance, inherited scopes and unrelated pending
    // operations remain ordinary coordinator demand, independent of opening.
    unawaited(guard.controller.syncNow().catchError((Object _) {}));
    widget.onAccepted?.call(scopeId);
    Navigator.of(context).pop();
  }

  InviteCryptoRepository _cryptoInvites(AccountCryptoV2Workflow workflow) =>
      widget.cryptoRepository?.call(workflow) ??
      InviteCryptoRepository(SessionCryptoAccess(account: workflow));

  Future<void> _joinEncrypted() => _run(() async {
    final link = _link!;
    final identity = _identity;
    bool current() =>
        mounted &&
        _active &&
        _matchingSession &&
        _identity == identity &&
        _link?.token == link.token &&
        _sameServer(_link?.serverUrl, link.serverUrl);
    final repository = await ref.read(collaborationRepositoryProvider.future);
    final workflow = await repository.connectedCryptoAccount();
    if (!current()) return;
    final initialPhase = await workflow.localPhase();
    if (!mounted || !current()) return;
    if (initialPhase != 'ready') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AccountCryptoWizard(workflow: workflow),
        ),
      );
      if (!mounted || !current()) return;
      final phase = await workflow.localPhase();
      if (!mounted || !current() || phase != 'ready') return;
    }
    // Preparing an account does not accept an invitation. Return to this same
    // route with verified permissions before the deliberate final action.
    if (!_reviewMatchesCurrent) {
      await _loadPreview();
      return;
    }
    final invites = _cryptoInvites(workflow);
    final saved = await ref.read(pendingInvitationStoreProvider).read();
    if (saved?.token == link.token &&
        saved?.accountPartition == workflow.store.partition &&
        saved?.invitationId != null) {
      final target = await invites.resumeAccepted(saved!.invitationId!);
      if (target != null) {
        await _openEncryptedTarget(target, link);
        return;
      }
      if (!current()) return;
      setState(() {
        _cryptoPending = true;
        _preauthorizedAccepted = isPreauthorizedInvitation(
          _verifiedInvitation!,
        );
        _notice = _preauthorizedAccepted
            ? context.l10n.invitationFlowAccessVerificationPending
            : context.l10n.cryptoInvitationPendingKeys;
      });
      return;
    }
    final invite = _verifiedInvitation;
    if (invite == null || !current() || !_reviewMatchesCurrent) return;
    // accept rechecks the exact reviewed authorization and fresh creator
    // directory before signing. Keep that freshness boundary in the repository.
    await invites.accept(invite, actionId: invite.invitation['id']);
    if (!current()) return;
    final store = ref.read(pendingInvitationStoreProvider);
    var savedAcceptance = false;
    await store.serialized(() async {
      final previous = await store.read();
      if (!current() ||
          previous?.token != link.token ||
          !_sameServer(previous?.serverUrl, link.serverUrl) ||
          previous!.serverId != null &&
              previous.serverId != _session?.serverId ||
          previous.accountPartition != null &&
              previous.accountPartition != workflow.store.partition) {
        return;
      }
      await store.write(
        PendingInvitation(
          serverUrl: previous.serverUrl,
          token: previous.token,
          serverId: previous.serverId,
          expiresAt: previous.expiresAt,
          accountPartition: workflow.store.partition,
          invitationId: invite.invitation['id'],
        ),
      );
      savedAcceptance = true;
    });
    if (!current() || !savedAcceptance) return;
    setState(() {
      _acceptedRecipientIdentity = identity;
      _cryptoPending = true;
      _lastAccessRefresh = _accessRefreshClock.elapsed;
      _preauthorizedAccepted = isPreauthorizedInvitation(invite);
      _notice = _preauthorizedAccepted
          ? context.l10n.invitationFlowAccessVerificationPending
          : context.l10n.cryptoInvitationPendingKeys;
    });
    if (_preauthorizedAccepted) {
      final scope = await invites.resumeAccepted(invite.invitation['id']);
      if (!current()) return;
      if (scope == null) {
        throw const FormatException('invitation_activation_incomplete');
      }
      await _openEncryptedTarget(scope, link);
    }
  });

  bool get _canDecline =>
      !_declined &&
      !_joined &&
      !_cryptoPending &&
      _reviewMatchesCurrent &&
      _recipientVerifiedForDecline &&
      _verifiedInvitation?.invitation['state'] == 'pending' &&
      ref.read(collaborationProvider).valueOrNull?.invitationDeclineSupported ==
          true;

  Future<void> _finishDeclined() async {
    final link = _declinedLink;
    final identity = _declinedIdentity;
    if (!_declined ||
        link == null ||
        identity == null ||
        _identity != identity ||
        _link != link ||
        !_active ||
        !_matchingSession) {
      return;
    }
    final guard = SharingSessionGuard(context, ref);
    await guard.controller.clearPendingInvitation(expectedToken: link.token);
    if (!mounted || !_active || !guard.isCurrent || _identity != identity) {
      return;
    }
    _consumeRouteHint(link);
    ref
        .read(
          accountSummaryRefreshProvider((
            _session!.partition,
            _session!.deviceId,
          )).notifier,
        )
        .state++;
    Navigator.of(context).pop();
  }

  Future<void> _decline() => _run(() async {
    if (!_canDecline) return;
    final identity = _identity;
    final link = _link;
    final verified = _verifiedInvitation!;
    final repository = await ref.read(collaborationRepositoryProvider.future);
    if (!_canDecline || _identity != identity || _link != link) return;
    final account = await repository.connectedCryptoAccount();
    if (!_canDecline || _identity != identity || _link != link) return;
    await _cryptoInvites(account).decline(verified, actionId: _declineActionId);
    if (!_active ||
        !_matchingSession ||
        _identity != identity ||
        _link != link) {
      return;
    }
    setState(() {
      _declined = true;
      _declinedIdentity = identity;
      _declinedLink = link;
    });
    await _finishDeclined();
  });

  Future<void> _finishJoined(SharedInvitationPreview preview) async {
    if (!_active || _joinedIdentity != _identity) {
      throw const CollaborationException('session_changed');
    }
    final guard = SharingSessionGuard(context, ref);
    if (!ref
        .read(collaborationProvider)
        .valueOrNull!
        .scopes
        .any((s) => s.id == preview.scopeId && s.canRead)) {
      await guard.controller.syncNow();
      if (!mounted || !_active || !guard.isCurrent) return;
    }
    await guard.controller.selectSpace(preview.scopeId);
    if (!mounted || !_active || !guard.isCurrent) return;
    await guard.controller.clearPendingInvitation(expectedToken: _link!.token);
    if (!mounted || !_active || !guard.isCurrent) return;
    if (preview.role != SharedRole.viewer) {
      await showSharedContentPolicy(
        context,
        scopeId: preview.scopeId,
        allowReadOnly: true,
      );
    }
    if (!mounted || !_active || !guard.isCurrent) return;
    _consumeRouteHint(_link!);
    widget.onAccepted?.call(preview.scopeId);
    Navigator.of(context).pop();
  }

  Widget _field(
    String id,
    TextEditingController controller,
    String label, {
    bool secret = false,
    bool readOnly = false,
    TextInputType? keyboardType,
    String? Function(String?)? validate,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: PasswordVisibility(
      secret: secret,
      enabled: !_busy,
      builder: (obscure, toggle) => TextFormField(
        key: ValueKey('invitation-flow-$id'),
        controller: controller,
        enabled: !_busy,
        readOnly: readOnly,
        obscureText: obscure,
        autocorrect: false,
        textCapitalization: TextCapitalization.none,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        keyboardType: keyboardType,
        enableSuggestions: !secret && keyboardType == null,
        enableIMEPersonalizedLearning: !secret,
        decoration: InputDecoration(labelText: label, suffixIcon: toggle),
        validator: (value) => value == null || value.trim().isEmpty
            ? context.l10n.sharingRequired
            : validate?.call(value),
      ),
    ),
  );

  void _chooseAuth(bool register) => setState(() {
    _step = register ? _InvitationStep.register : _InvitationStep.login;
    _error = null;
    _notice = null;
    _password.clear();
    _confirm.clear();
    _otp.clear();
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    for (final c in [
      _input,
      _code,
      _server,
      _username,
      _name,
      _password,
      _confirm,
      _otp,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(collaborationProvider);
    final routeCurrent = ModalRoute.of(context)?.isCurrent == true;
    if (routeCurrent && !_routeWasCurrent) _refreshPreviewOnReturn = true;
    _routeWasCurrent = routeCurrent;
    // Account v2 setup may be presented by the saved-session coordinator while
    // our first inspection is still pending. On return, re-read this exact
    // invitation once; account readiness itself never accepts it.
    if (routeCurrent &&
        _refreshPreviewOnReturn &&
        !_busy &&
        !_joined &&
        !_cryptoPending &&
        _preview?.contractVersion == 4 &&
        _matchingSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_active ||
            !_matchingSession ||
            _busy ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        _refreshPreviewOnReturn = false;
        _run(_loadPreview, clearErrorBefore: false);
      });
    }
    ref.listen(collaborationProvider, (previous, next) {
      final before = previous?.valueOrNull?.session;
      final after = next.valueOrNull?.session;
      if (before?.partition == after?.partition &&
          before?.deviceId == after?.deviceId) {
        return;
      }
      _verifiedInvitation = null;
      _recipientVerifiedForDecline = false;
      _declined = false;
      _declinedIdentity = null;
      _declinedLink = null;
      _verifiedIdentity = null;
      _verifiedLink = null;
      _preauthorizedAccepted = false;
      _cryptoSetupRequired = false;
      _refreshPreviewOnReturn = false;
      _cryptoPending = false;
      _acceptedRecipientIdentity = null;
      _notice = null;
    });
    ref.listen(pendingInvitationLinkProvider, (_, incoming) {
      if (incoming == null ||
          _link == null ||
          (incoming.token == _link!.token &&
              _sameServer(incoming.serverUrl, _link!.serverUrl))) {
        return;
      }
      _superseded = true;
      _preauthorizedAccepted = false;
      _generation++;
      if (!_busy) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(context).pop();
          }
        });
      }
    });
    final l = context.l10n;
    final auth =
        _step == _InvitationStep.login || _step == _InvitationStep.register;
    final register = _step == _InvitationStep.register;
    return PopScope(
      canPop: !_busy && _link == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.invitationFlowTitle),
          leading: BackButton(onPressed: _busy ? null : _dismiss),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_step == _InvitationStep.input) ...[
                      Text(l.invitationFlowPasteHelp),
                      const SizedBox(height: 24),
                      _field(
                        'input',
                        _input,
                        l.inviteReviewLink,
                        keyboardType: TextInputType.url,
                      ),
                      ExpansionTile(
                        key: const ValueKey('invitation-flow-advanced-input'),
                        title: Text(l.inviteReviewCodeOption),
                        children: [
                          _field(
                            'code',
                            _code,
                            l.inviteReviewCode,
                            keyboardType: TextInputType.visiblePassword,
                          ),
                          _field(
                            'server',
                            _server,
                            l.serverURL,
                            keyboardType: TextInputType.url,
                          ),
                        ],
                      ),
                      FilledButton(
                        key: const ValueKey('invitation-flow-open'),
                        onPressed: _busy ? null : _openInput,
                        child: Text(l.invitationFlowOpen),
                      ),
                    ] else if (_step == _InvitationStep.origin) ...[
                      Text(l.inviteOpenWarning),
                      HostingDisclosureForServer(
                        key: const ValueKey('invitation-flow-origin'),
                        serverUrl: _link!.serverUrl,
                        compact: true,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const ValueKey('invitation-flow-confirm-origin'),
                        onPressed: _busy ? null : () => _run(_loadPreview),
                        child: Text(l.inviteOpenContinue),
                      ),
                    ] else ...[
                      if (_preview != null) ...[
                        if (!auth && _matchingSession && !_joined) ...[
                          SharingInvitationDetails(
                            invitation: _preview!,
                            showPermissions: _preview!.contractVersion != 4,
                            concise: _preview!.contractVersion == 4,
                            verifiedInvitation: _reviewMatchesCurrent
                                ? _verifiedInvitation
                                : null,
                          ),
                          if (_reviewMatchesCurrent) ...[
                            VerifiedInvitationPermissions(
                              invitation: _verifiedInvitation!,
                            ),
                            const SizedBox(height: 12),
                            Text(l.inviteReviewVisibility),
                          ],
                        ] else ...[
                          Text(
                            _preview!.scopeNameAvailable
                                ? l.invitationFlowInvitationTo(
                                    _preview!.scopeName,
                                  )
                                : l.cryptoInvitationTargetUnavailable,
                            style: auth
                                ? Theme.of(context).textTheme.bodyMedium
                                : Theme.of(context).textTheme.titleLarge,
                          ),
                          if (_preview!.inviterEmail != null ||
                              _preview!.inviterName.isNotEmpty)
                            Text(
                              l.emailInviteFrom(
                                _preview!.inviterEmail ?? _preview!.inviterName,
                              ),
                            ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      if (!auth) ...[
                        if (_declined) ...[
                          Text(l.invitationFlowDeclined),
                          TextButton(
                            key: const ValueKey(
                              'invitation-flow-declined-close',
                            ),
                            onPressed: _busy
                                ? null
                                : () => _run(_finishDeclined),
                            child: Text(l.close),
                          ),
                        ] else if (_matchingSession) ...[
                          Text(l.accountSignedIn(_session!.username)),
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const ValueKey('invitation-flow-join'),
                            onPressed:
                                _busy ||
                                    isSharingIdentityChanged(_lastError) ||
                                    (_preview?.contractVersion == 4 &&
                                        !_joined &&
                                        !_cryptoPending &&
                                        !_cryptoSetupRequired &&
                                        !_reviewMatchesCurrent)
                                ? null
                                : _joined
                                ? () => _run(() => _finishJoined(_preview!))
                                : _cryptoPending
                                ? () => _refreshPendingAccess(allowSetup: true)
                                : _join,
                            child: Text(
                              _cryptoPending
                                  ? l.cryptoSharingCheckAccess
                                  : _joined
                                  ? l.invitationFlowOpenSpace
                                  : _cryptoSetupRequired
                                  ? l.invitationFlowPrepareAccount
                                  : _preview?.contractVersion == 4
                                  ? l.invitationFlowAgreeAccept
                                  : _preview?.kind == SharedScopeKind.project
                                  ? l.invitationFlowJoinProject
                                  : l.invitationFlowJoinSpace,
                            ),
                          ),
                          if (_canDecline)
                            OutlinedButton(
                              key: const ValueKey('invitation-flow-decline'),
                              onPressed: _busy ? null : _decline,
                              child: Text(l.invitationFlowDecline),
                            ),
                          if (_preview?.contractVersion == 4 &&
                              !_busy &&
                              !_cryptoPending &&
                              !_joined &&
                              !_cryptoSetupRequired &&
                              !_reviewMatchesCurrent &&
                              _error == null)
                            TextButton(
                              key: const ValueKey(
                                'invitation-flow-review-retry',
                              ),
                              onPressed: () => _run(_loadPreview),
                              child: Text(l.organizerRetry),
                            ),
                          if (!_hasMatchedRecipient)
                            TextButton(
                              key: const ValueKey(
                                'invitation-flow-other-account',
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _chooseAuth(false),
                              child: Text(l.invitationFlowOtherAccount),
                            ),
                        ] else ...[
                          Text(l.invitationFlowSignInToJoin),
                          const SizedBox(height: 12),
                          if (_session != null)
                            Text(_sessionMismatchMessage(context)),
                          FilledButton(
                            key: const ValueKey('invitation-flow-login-choice'),
                            onPressed: _busy ? null : () => _chooseAuth(false),
                            child: Text(l.emailInviteHaveAccount),
                          ),
                          if (_preview?.canRegister == true)
                            OutlinedButton(
                              key: const ValueKey(
                                'invitation-flow-register-choice',
                              ),
                              onPressed: _busy ? null : () => _chooseAuth(true),
                              child: Text(l.emailInviteCreateAccount),
                            ),
                        ],
                      ] else ...[
                        Text(
                          register
                              ? l.emailInviteCreateAccount
                              : l.sharingLogin,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        _field(
                          'username',
                          _username,
                          l.username,
                          readOnly: _preview?.isEmailInvitation != true,
                          validate: register
                              ? (value) =>
                                    RegExp(
                                      r'^[a-zA-Z0-9_.-]{3,64}$',
                                    ).hasMatch(value!.trim())
                                    ? null
                                    : l.invitationFlowUsernameRule
                              : null,
                        ),
                        if (register) ...[
                          Text(
                            l.invitationFlowUsernameRule,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          _field(
                            'name',
                            _name,
                            l.sharingDisplayName,
                            validate: (value) =>
                                utf8.encode(value!.trim()).length <= 100
                                ? null
                                : l.invitationFlowNameRule,
                          ),
                        ],
                        _field(
                          'password',
                          _password,
                          l.password,
                          secret: true,
                          validate: register
                              ? (value) =>
                                    utf8.encode(value!).length < 12 ||
                                        utf8.encode(value).length > 72
                                    ? l.accountPasswordRule
                                    : null
                              : null,
                        ),
                        if (register)
                          _field(
                            'confirm',
                            _confirm,
                            l.sharingConfirmPassword,
                            secret: true,
                            validate: (value) => value == _password.text
                                ? null
                                : l.sharingPasswordMismatch,
                          ),
                        if (_needsOtp && !register)
                          _field('otp', _otp, l.sharingTwoFactorCode),
                        FilledButton(
                          key: const ValueKey('invitation-flow-authenticate'),
                          onPressed: _busy ? null : _authenticate,
                          child: Text(
                            register
                                ? _preview?.isEmailInvitation == true
                                      ? l.emailInviteCreateAccount
                                      : l.sharingRegisterAction
                                : l.sharingLoginAction,
                          ),
                        ),
                        if (!register) ...[
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => showPasswordResetRequest(
                                    context,
                                    ref,
                                    initialServer: _link!.serverUrl,
                                    username: _username.text.trim(),
                                  ),
                            child: Text(l.accountForgotPassword),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => showPasswordResetConfirm(
                                    context,
                                    ref,
                                    initialServer: _link!.serverUrl,
                                  ),
                            child: Text(l.accountResetConfirm),
                          ),
                        ],
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _step = _InvitationStep.preview;
                                  _error = null;
                                }),
                          child: Text(l.invitationFlowBackToPreview),
                        ),
                      ],
                    ],
                    if (_busy) const LinearProgressIndicator(),
                    if (_notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_notice!),
                      ),
                    if (_error != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      if (_link != null && !auth)
                        TextButton(
                          onPressed:
                              _busy ||
                                  _joined ||
                                  isSharingIdentityChanged(_lastError)
                              ? null
                              : () => _run(_loadPreview),
                          child: Text(l.organizerRetry),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
