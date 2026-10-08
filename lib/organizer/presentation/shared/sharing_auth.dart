import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import 'sharing_errors.dart';
import '../onboarding/account_recovery_actions.dart';
import '../../platform/invitation_links/invitation_link.dart';

class SharingAuthPanel extends ConsumerStatefulWidget {
  const SharingAuthPanel({
    super.key,
    required this.onStart,
    required this.onConnected,
    this.initialServer = '',
    this.invitationMode = false,
    this.initialToken = '',
  });
  final VoidCallback onStart;
  final VoidCallback onConnected;
  final String initialServer, initialToken;
  final bool invitationMode;
  @override
  ConsumerState<SharingAuthPanel> createState() => _SharingAuthPanelState();
}

class _SharingAuthPanelState extends ConsumerState<SharingAuthPanel> {
  final _form = GlobalKey<FormState>();
  late final _server = TextEditingController(text: widget.initialServer);
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  final _otp = TextEditingController();
  late final _token = TextEditingController(text: widget.initialToken);
  final _device = TextEditingController();
  late bool _invitationMode = widget.invitationMode;
  bool _register = false;
  bool _allowLocalHttp = false;
  bool _busy = false;
  bool _showingEnrollment = false;
  bool _needsOtp = false;
  String? _error;
  String? _notice;
  SharedInvitationPreview? _preview;

  bool get _isLocalHttp {
    final uri = Uri.tryParse(_server.text.trim());
    return uri?.scheme == 'http' &&
        const ['localhost', '127.0.0.1', '::1'].contains(uri?.host);
  }

  @override
  void dispose() {
    for (final controller in [
      _server,
      _username,
      _password,
      _confirm,
      _name,
      _otp,
      _token,
      _device,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _previewInvitation() async {
    if (_token.text.trim().isEmpty || _busy) {
      setState(() => _error = context.l10n.sharingRequired);
      return;
    }
    final invitationUri = Uri.tryParse(_token.text.trim());
    if (InvitationLink.supportedSchemes.contains(invitationUri?.scheme)) {
      final link = InvitationLink.tryParse(invitationUri!);
      if (link == null) {
        setState(() => _error = context.l10n.inviteLinkInvalid);
        return;
      }
      _server.text = link.serverUrl;
      _token.text = link.token;
    }
    if (_server.text.trim().isEmpty) {
      setState(() => _error = context.l10n.sharingRequired);
      return;
    }
    final controller = ref.read(collaborationProvider.notifier);
    widget.onStart();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await controller.previewInvitation(
        serverUrl: _server.text.trim(),
        token: _token.text.trim(),
        allowLocalHttp: _allowLocalHttp,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _username.text = preview.recipientUsername;
          _register = preview.canRegister;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = sharingErrorMessage(context, error);
          _needsOtp =
              error is CollaborationException &&
              error.code == 'two_factor_required';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    if (_busy || !_form.currentState!.validate()) return;
    final controller = ref.read(collaborationProvider.notifier);
    final server = _server.text.trim();
    final username = _username.text.trim();
    final password = _password.text;
    final otp = _otp.text.trim();
    final token = _invitationMode ? _token.text.trim() : null;
    final registering = _register && token != null;
    final device = _device.text.trim().isEmpty
        ? context.l10n.organizerAppName
        : _device.text.trim();
    widget.onStart();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (registering) {
        await controller.registerWithInvitation(
          serverUrl: server,
          invitationToken: token,
          username: username,
          name: _name.text.trim(),
          password: password,
          deviceName: device,
          allowLocalHttp: _allowLocalHttp,
        );
      } else {
        await controller.login(
          serverUrl: server,
          username: username,
          password: password,
          otp: otp.isEmpty ? null : otp,
          deviceName: device,
          allowLocalHttp: _allowLocalHttp,
        );
        if (token != null) await controller.acceptInvitation(token);
      }
      if (mounted) {
        _password.clear();
        _confirm.clear();
        _otp.clear();
        _token.clear();
        if (registering) {
          final session = ref.read(collaborationProvider).valueOrNull?.session;
          if (session != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.accountCreatedSignedIn(session.username),
                ),
              ),
            );
          }
        }
        widget.onConnected();
      }
    } catch (error) {
      if (mounted) {
        if (registering &&
            error is CollaborationException &&
            error.code == 'account_created_session_not_saved') {
          _prepareCreatedAccountLogin(server, username);
          return;
        }
        setState(() {
          _error = sharingErrorMessage(context, error);
          _needsOtp =
              error is CollaborationException &&
              error.code == 'two_factor_required';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enroll() async {
    widget.onStart();
    setState(() {
      _busy = true;
      _showingEnrollment = true;
    });
    try {
      final enrolled = await showAccountEnrollment(
        context,
        ref,
        initialServer: _server.text.trim(),
        allowLocalHttp: _allowLocalHttp && _isLocalHttp,
        onAccountCreatedWithoutSession: (server, username) {
          if (mounted) _prepareCreatedAccountLogin(server, username);
        },
      );
      if (enrolled && mounted) widget.onConnected();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _showingEnrollment = false;
        });
      }
    }
  }

  void _prepareCreatedAccountLogin(String server, String username) {
    setState(() {
      _server.text = server;
      _username.text = username;
      _password.clear();
      _confirm.clear();
      _otp.clear();
      _token.clear();
      _preview = null;
      _invitationMode = false;
      _register = false;
      _needsOtp = false;
      _error = null;
      _notice = context.l10n.accountCreatedSignInRequired(username);
    });
  }

  Widget _field(
    String id,
    TextEditingController controller,
    String label, {
    bool secret = false,
    bool required = true,
    bool readOnly = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('sharing-$id'),
      controller: controller,
      enabled: !_busy,
      readOnly: readOnly,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret && id != 'invitation-token' && id != 'otp',
      enableIMEPersonalizedLearning:
          !secret && id != 'invitation-token' && id != 'otp',
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      onChanged: id == 'server'
          ? (_) => setState(() {
              if (!_isLocalHttp) _allowLocalHttp = false;
            })
          : null,
      validator: (value) => required && (value == null || value.trim().isEmpty)
          ? context.l10n.sharingRequired
          : validator?.call(value),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(title: l.sharingAccount, subtitle: l.sharingIntro),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            selected: !_invitationMode,
                            label: Text(l.sharingLogin),
                            onSelected: _busy
                                ? null
                                : (_) => setState(() {
                                    _invitationMode = false;
                                    _register = false;
                                    _preview = null;
                                    _error = null;
                                  }),
                          ),
                          ChoiceChip(
                            selected: _invitationMode,
                            label: Text(l.sharingHaveInvite),
                            onSelected: _busy
                                ? null
                                : (_) => setState(() {
                                    _invitationMode = true;
                                    _register = false;
                                    _preview = null;
                                    _error = null;
                                  }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _field(
                        'server',
                        _server,
                        l.serverURL,
                        readOnly: _preview != null,
                        keyboardType: TextInputType.url,
                      ),
                      if (_preview == null && _isLocalHttp)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _allowLocalHttp,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _allowLocalHttp = value!),
                          title: Text(l.localDevelopmentConnection),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      if (_invitationMode) ...[
                        const SizedBox(height: 16),
                        Text(l.sharingInvitationHint),
                        const SizedBox(height: 16),
                        _field(
                          'invitation-token',
                          _token,
                          l.sharingInvitationCode,
                          readOnly: _preview != null,
                        ),
                        if (_preview == null)
                          OutlinedButton(
                            key: const ValueKey('sharing-preview-invite'),
                            onPressed: _busy ? null : _previewInvitation,
                            child: Text(l.sharingPreviewInvite),
                          ),
                        if (_preview != null) ...[
                          Text(
                            _preview!.scopeName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${sharingRoleLabel(context, _preview!.role)} · ${l.sharingExpires} ${organizerDate(context, _preview!.expiresAt)}',
                          ),
                          const SizedBox(height: 12),
                          if (_preview!.canRegister)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l.sharingRegister),
                              value: _register,
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                        setState(() => _register = value),
                            ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _preview = null;
                                    _register = false;
                                  }),
                            child: Text(l.sharingPreviewInvite),
                          ),
                        ],
                      ],
                      if (!_invitationMode || _preview != null) ...[
                        const SizedBox(height: 16),
                        _field(
                          'username',
                          _username,
                          l.username,
                          readOnly: _preview != null,
                        ),
                        if (_register)
                          _field('display-name', _name, l.sharingDisplayName),
                        _field('password', _password, l.password, secret: true),
                        if (_register)
                          _field(
                            'confirm-password',
                            _confirm,
                            l.sharingConfirmPassword,
                            secret: true,
                            validator: (value) => value == _password.text
                                ? null
                                : l.sharingPasswordMismatch,
                          ),
                        if (!_register && _needsOtp)
                          _field(
                            'otp',
                            _otp,
                            l.sharingTwoFactorCode,
                            required: false,
                            keyboardType: TextInputType.number,
                          ),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(l.sharingAdvancedLogin),
                          children: [
                            if (!_register && !_needsOtp)
                              _field(
                                'otp',
                                _otp,
                                l.sharingTwoFactorCode,
                                required: false,
                                keyboardType: TextInputType.number,
                              ),
                            _field(
                              'device',
                              _device,
                              l.sharingDeviceName,
                              required: false,
                            ),
                          ],
                        ),
                        FilledButton(
                          key: const ValueKey('sharing-connect'),
                          onPressed: _busy ? null : _connect,
                          child: Text(
                            _register
                                ? l.sharingRegisterAction
                                : _invitationMode
                                ? l.sharingAcceptInvite
                                : l.sharingLoginAction,
                          ),
                        ),
                      ],
                      if (!_invitationMode) ...[
                        TextButton(
                          onPressed: _busy ? null : _enroll,
                          child: Text(l.accountFirstTitle),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => showPasswordResetRequest(
                                  context,
                                  ref,
                                  initialServer: _server.text.trim(),
                                  allowLocalHttp:
                                      _allowLocalHttp && _isLocalHttp,
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
                                  initialServer: _server.text.trim(),
                                  allowLocalHttp:
                                      _allowLocalHttp && _isLocalHttp,
                                ),
                          child: Text(l.accountResetConfirm),
                        ),
                      ],
                      if (_busy && !_showingEnrollment)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: LinearProgressIndicator(),
                        ),
                      if (_notice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_notice!),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
