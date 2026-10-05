import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../shared/sharing_forms.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';

SharingField newPasswordField(BuildContext context) => SharingField(
  id: 'password',
  label: context.l10n.password,
  obscure: true,
  sensitive: true,
  validator: (value, _) =>
      utf8.encode(value).length < 12 || utf8.encode(value).length > 72
      ? context.l10n.accountPasswordRule
      : null,
);
SharingField confirmPasswordField(BuildContext context) => SharingField(
  id: 'confirm',
  label: context.l10n.sharingConfirmPassword,
  obscure: true,
  sensitive: true,
  validator: (value, all) =>
      value == all['password'] ? null : context.l10n.sharingPasswordMismatch,
);

Future<bool> showAccountEnrollment(
  BuildContext context,
  WidgetRef ref, {
  String initialServer = '',
  bool allowLocalHttp = false,
}) async {
  final l = context.l10n,
      guard = SharingSessionGuard(context, ref, allowSignedOut: true);
  bool enrolled = false;
  await showSharingForm(
    context,
    title: l.accountFirstTitle,
    description: l.accountFirstDescription,
    fields: [
      SharingField(
        id: 'server',
        label: l.serverURL,
        initialValue: initialServer,
        keyboardType: TextInputType.url,
      ),
      SharingField(id: 'code', label: l.accountBootstrapCode, sensitive: true),
      SharingField(id: 'username', label: l.username),
      SharingField(id: 'name', label: l.sharingDisplayName),
      newPasswordField(context),
      confirmPasswordField(context),
    ],
    submitLabel: l.accountCreate,
    errorMessage: (e) => sharingErrorMessage(context, e),
    wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
    onSubmit: (values) async {
      await guard.controller.enroll(
        serverUrl: values['server']!.trim(),
        code: values['code']!.trim(),
        username: values['username']!.trim(),
        name: values['name']!.trim(),
        password: values['password']!,
        allowLocalHttp: allowLocalHttp,
      );
      enrolled = true;
    },
  );
  return enrolled;
}

Future<void> showPasswordResetRequest(
  BuildContext context,
  WidgetRef ref, {
  String initialServer = '',
  bool allowLocalHttp = false,
  String username = '',
}) async {
  final l = context.l10n,
      guard = SharingSessionGuard(context, ref, allowSignedOut: true);
  bool requested = false;
  await showSharingForm(
    context,
    title: l.accountForgotPassword,
    description: l.accountResetRequestDescription,
    fields: [
      SharingField(
        id: 'server',
        label: l.serverURL,
        initialValue: initialServer,
        keyboardType: TextInputType.url,
      ),
      SharingField(id: 'username', label: l.username, initialValue: username),
    ],
    submitLabel: l.accountSendReset,
    errorMessage: (e) => sharingErrorMessage(context, e),
    wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
    onSubmit: (values) async {
      await guard.controller.requestPasswordReset(
        serverUrl: values['server']!.trim(),
        username: values['username']!.trim(),
        allowLocalHttp: allowLocalHttp,
        language: Localizations.localeOf(context).languageCode == 'sl'
            ? 'sl'
            : 'en',
      );
      requested = true;
    },
  );
  if (requested && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.accountResetGeneric)));
  }
}

Future<bool> showPasswordResetConfirm(
  BuildContext context,
  WidgetRef ref, {
  String initialServer = '',
  bool allowLocalHttp = false,
}) async {
  final l = context.l10n,
      guard = SharingSessionGuard(context, ref, allowSignedOut: true);
  bool reset = false;
  await showSharingForm(
    context,
    title: l.accountResetConfirm,
    description: l.accountResetConfirmDescription,
    fields: [
      SharingField(
        id: 'server',
        label: l.serverURL,
        initialValue: initialServer,
        keyboardType: TextInputType.url,
      ),
      SharingField(id: 'token', label: l.accountEmailCode, sensitive: true),
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
    submitLabel: l.accountResetPassword,
    errorMessage: (e) => sharingErrorMessage(context, e),
    wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
    onSubmit: (values) async {
      await guard.controller.confirmPasswordReset(
        serverUrl: values['server']!.trim(),
        token: values['token']!.trim(),
        password: values['password']!,
        allowLocalHttp: allowLocalHttp,
        otp: values['otp']!.trim().isEmpty ? null : values['otp']!.trim(),
      );
      reset = true;
    },
  );
  if (reset && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.accountResetDone)));
  }
  return reset;
}
