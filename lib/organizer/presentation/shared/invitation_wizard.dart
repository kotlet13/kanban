import 'dart:convert';
import '../../data/e2ee/invite_crypto_repository.dart';
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
import '../../data/collaboration_transport.dart'
    show normalizeCollaborationServer;
import '../onboarding/account_recovery_actions.dart';
import '../password_visibility.dart';
import 'content_moderation.dart';
import 'sharing_errors.dart';
import 'hosting_disclosure.dart';
import 'sharing_invitation_details.dart';
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

class _InvitationWizardState extends ConsumerState<InvitationWizard> {
  final _form = GlobalKey<FormState>();
  final _input = TextEditingController();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _otp = TextEditingController();
  _InvitationStep _step = _InvitationStep.input;
  InvitationLink? _link;
  SharedInvitationPreview? _preview;
  String? _error, _notice;
  Object? _lastError;
  bool _busy = true, _needsOtp = false, _joined = false;
  int _generation = 0;
  String? _pinnedServerId, _boundPartition, _joinedIdentity;
  bool _superseded = false;
  bool _cryptoPending = false;

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
      _input.text,
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
      _step = _InvitationStep.preview;
      if (!preview.isEmailInvitation) {
        _username.text = preview.recipientUsername;
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _lastError = null;
    });
    try {
      await action();
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
    await guard.controller.syncNow();
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
        _notice = context.l10n.cryptoInvitationPendingKeys;
      });
      return;
    }
    final invite = await invites.inspect(token: link.token);
    if (!current()) return;
    await invites.trustCreatorFromDirectory(invite);
    if (!current()) return;
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
      _cryptoPending = true;
      _notice = context.l10n.cryptoInvitationPendingKeys;
    });
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
        enableSuggestions: !secret,
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
    _generation++;
    for (final c in [
      _input,
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
    ref.listen(pendingInvitationLinkProvider, (_, incoming) {
      if (incoming == null ||
          _link == null ||
          (incoming.token == _link!.token &&
              _sameServer(incoming.serverUrl, _link!.serverUrl))) {
        return;
      }
      _superseded = true;
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
                      _field('input', _input, l.invitationFlowLinkOrCode),
                      ExpansionTile(
                        title: Text(l.invitationFlowCodeServer),
                        initiallyExpanded: _server.text.isEmpty,
                        children: [_field('server', _server, l.serverURL)],
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
                        Text(
                          _preview!.role == SharedRole.viewer
                              ? l.invitationFlowStepsViewer
                              : l.invitationFlowStepsWriter,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 12),
                        if (!auth && _matchingSession && !_joined)
                          SharingInvitationDetails(invitation: _preview!)
                        else ...[
                          Text(
                            l.invitationFlowInvitationTo(_preview!.scopeName),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (_preview!.inviterName.isNotEmpty)
                            Text(l.emailInviteFrom(_preview!.inviterName)),
                        ],
                      ],
                      const SizedBox(height: 16),
                      HostingDisclosureForServer(
                        serverUrl: _link!.serverUrl,
                        compact: true,
                      ),
                      const SizedBox(height: 24),
                      if (!auth) ...[
                        if (_matchingSession) ...[
                          Text(l.accountSignedIn(_session!.username)),
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const ValueKey('invitation-flow-join'),
                            onPressed:
                                _busy || isSharingIdentityChanged(_lastError)
                                ? null
                                : _joined
                                ? () => _run(() => _finishJoined(_preview!))
                                : _join,
                            child: Text(
                              _cryptoPending
                                  ? l.cryptoSharingCheckAccess
                                  : _joined
                                  ? l.invitationFlowOpenSpace
                                  : _preview?.kind == SharedScopeKind.project
                                  ? l.invitationFlowJoinProject
                                  : l.invitationFlowJoinSpace,
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : () => _chooseAuth(false),
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
