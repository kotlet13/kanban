import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_forms.dart';
import '../shared/sharing_session_boundary.dart';
import 'account_recovery_actions.dart';

/// Available immediately from account settings; opening it never starts setup.
class AccountPasswordCard extends ConsumerWidget {
  const AccountPasswordCard({super.key, required this.session, this.onSignIn});
  final AccountSession session;
  final VoidCallback? onSignIn;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref, {
    required bool reset,
  }) async {
    final l = context.l10n;
    final guard = SharingSessionGuard(context, ref, session: session);
    final identity = guard.controller.editorSessionIdentity;
    bool current() =>
        guard.isCurrent && guard.controller.editorSessionIdentity == identity;
    bool completed = false;
    await showSharingForm(
      context,
      title: reset ? l.accountResetConfirm : l.accountPasswordChange,
      description: reset
          ? l.accountSignedInResetWarning
          : l.accountPasswordChangeDescription,
      fields: [
        if (reset)
          SharingField(id: 'token', label: l.accountEmailCode, sensitive: true)
        else
          SharingField(
            id: 'currentPassword',
            label: l.accountCurrentPassword,
            obscure: true,
            sensitive: true,
          ),
        newPasswordField(context),
        confirmPasswordField(context),
        SharingField(
          id: 'otp',
          label: l.sharingTwoFactorCode,
          required: false,
          sensitive: true,
          keyboardType: TextInputType.number,
        ),
      ],
      submitLabel: reset ? l.accountResetPassword : l.accountPasswordChange,
      errorMessage: (error) =>
          _passwordError(context, error, changingPassword: !reset),
      wrap: (form) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: (_) => current(),
        child: form,
      ),
      onSubmit: (values) async {
        if (!current()) throw const CollaborationException('session_changed');
        final otp = values['otp']!.trim();
        if (reset) {
          await guard.controller.confirmSignedInPasswordReset(
            token: values['token']!.trim(),
            password: values['password']!,
            otp: otp.isEmpty ? null : otp,
          );
        } else {
          await guard.controller.changeAccountPassword(
            currentPassword: values['currentPassword']!,
            newPassword: values['password']!,
            otp: otp.isEmpty ? null : otp,
          );
        }
        completed = true;
      },
    );
    if (completed && context.mounted && current()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reset ? l.accountResetDone : l.accountPasswordChanged),
        ),
      );
    }
  }

  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final guard = SharingSessionGuard(context, ref, session: session);
    final identity = guard.controller.editorSessionIdentity;
    bool current() =>
        guard.isCurrent && guard.controller.editorSessionIdentity == identity;
    final l = context.l10n;
    final language = Localizations.localeOf(context).languageCode == 'sl'
        ? 'sl'
        : 'en';
    final confirmed = await confirmSharingAction(
      context,
      title: l.accountSignedInReset,
      description: l.accountSignedInResetWarning,
      confirmLabel: l.accountSendReset,
      wrap: (child) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: (_) => current(),
        child: child,
      ),
    );
    if (!confirmed || !current()) return;
    try {
      await guard.controller.requestSignedInPasswordReset(language: language);
      if (context.mounted && current()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.accountResetGeneric)));
      }
    } catch (error) {
      if (context.mounted && current()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_passwordError(context, error))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    if (state?.session?.partition != session.partition ||
        state?.session?.deviceId != session.deviceId) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final supported = state!.passwordChangeSupported;
    final active = supported && !state.sessionInvalid;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.accountPasswordChange,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(l.accountPasswordChangeDescription),
            if (state.sessionInvalid && onSignIn != null)
              TextButton(
                onPressed: onSignIn,
                child: Text(l.sharingLoginAction),
              ),
            if (!supported) Text(l.accountPasswordChangeUnsupported),
            FilledButton(
              onPressed: active
                  ? () => _open(context, ref, reset: false)
                  : null,
              child: Text(l.accountPasswordChange),
            ),
            const SizedBox(height: 12),
            Text(l.accountSignedInResetWarning),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: active && state.resetSupported
                      ? () => _request(context, ref)
                      : null,
                  child: Text(l.accountSignedInReset),
                ),
                TextButton(
                  onPressed: active && state.resetSupported
                      ? () => _open(context, ref, reset: true)
                      : null,
                  child: Text(l.accountResetConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _passwordError(
  BuildContext context,
  Object error, {
  bool changingPassword = false,
}) {
  if (error is CollaborationException) {
    if (changingPassword && const {'network', 'timeout'}.contains(error.code)) {
      return context.l10n.accountPasswordChangeUncertain;
    }
    return switch (error.code) {
      'invalid_credentials' =>
        changingPassword
            ? context.l10n.accountCurrentPasswordWrong
            : sharingErrorMessage(context, error),
      'password_change_unsupported' ||
      'unsupported_operation' => context.l10n.accountPasswordChangeUnsupported,
      'password_reset_identity_mismatch' =>
        context.l10n.accountResetWrongAccount,
      'password_too_long' ||
      'invalid_password' => context.l10n.accountPasswordRule,
      _ => sharingErrorMessage(context, error),
    };
  }
  return sharingErrorMessage(context, error);
}
