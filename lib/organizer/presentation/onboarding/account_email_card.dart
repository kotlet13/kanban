import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_forms.dart';
import '../shared/sharing_session_boundary.dart';

class AccountEmailCard extends ConsumerStatefulWidget {
  const AccountEmailCard({super.key, required this.session});
  final AccountSession session;
  @override
  ConsumerState<AccountEmailCard> createState() => _AccountEmailCardState();
}

class _AccountEmailCardState extends ConsumerState<AccountEmailCard> {
  late final _guard = SharingSessionGuard(
    context,
    ref,
    session: widget.session,
  );
  late Future<AccountStatus> _future = _guard.controller.accountStatus();
  Future<void> _change() async {
    final l = context.l10n;
    bool requested = false;
    await showSharingForm(
      context,
      title: l.accountEmailChange,
      description: l.accountEmailRequestDescription,
      fields: [
        SharingField(
          id: 'email',
          label: l.accountEmail,
          keyboardType: TextInputType.emailAddress,
        ),
        SharingField(
          id: 'password',
          label: l.password,
          obscure: true,
          sensitive: true,
        ),
        SharingField(
          id: 'otp',
          label: l.sharingTwoFactorCode,
          required: false,
          sensitive: true,
          keyboardType: TextInputType.number,
        ),
      ],
      submitLabel: l.accountEmailSend,
      errorMessage: (e) => sharingErrorMessage(context, e),
      wrap: (form) => SharingSessionBoundary(guard: _guard, child: form),
      onSubmit: (values) async {
        await _guard.controller.requestEmailVerification(
          email: values['email']!.trim(),
          password: values['password']!,
          otp: values['otp']!.trim().isEmpty ? null : values['otp']!.trim(),
          language: Localizations.localeOf(context).languageCode == 'sl'
              ? 'sl'
              : 'en',
        );
        requested = true;
      },
    );
    if (requested && mounted && _guard.isCurrent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.accountEmailSent)));
      setState(() {
        _future = _guard.controller.accountStatus();
      });
    }
  }

  Future<void> _confirm() async {
    final l = context.l10n;
    bool confirmed = false;
    await showSharingForm(
      context,
      title: l.accountEmailConfirm,
      fields: [
        SharingField(id: 'token', label: l.accountEmailCode, sensitive: true),
      ],
      submitLabel: l.accountEmailConfirm,
      errorMessage: (e) => sharingErrorMessage(context, e),
      wrap: (form) => SharingSessionBoundary(guard: _guard, child: form),
      onSubmit: (values) async {
        await _guard.controller.confirmEmailVerification(
          values['token']!.trim(),
        );
        confirmed = true;
      },
    );
    if (confirmed && mounted && _guard.isCurrent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.accountEmailConfirmed)));
      setState(() {
        _future = _guard.controller.accountStatus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    if (!_guard.isCurrent || state?.session == null) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    return FutureBuilder<AccountStatus>(
      future: _future,
      builder: (context, snapshot) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.accountEmailTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (snapshot.hasError) ...[
                Text(sharingErrorMessage(context, snapshot.error!)),
                TextButton(
                  onPressed: () => setState(() {
                    _future = _guard.controller.accountStatus();
                  }),
                  child: Text(l.organizerRetry),
                ),
              ] else if (snapshot.connectionState != ConnectionState.done ||
                  !snapshot.hasData)
                const LinearProgressIndicator()
              else ...[
                Text(snapshot.data!.email ?? l.accountEmailNone),
                Text(
                  snapshot.data!.emailVerified
                      ? l.accountEmailVerified
                      : l.accountEmailUnverified,
                ),
                if (snapshot.data!.pendingEmail != null)
                  Text(
                    '${l.accountEmailPending}: ${snapshot.data!.pendingEmail}',
                  ),
                if (state?.emailVerificationSupported != true)
                  Text(l.accountEmailUnavailable),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: state?.emailVerificationSupported == true
                          ? _change
                          : null,
                      child: Text(l.accountEmailChange),
                    ),
                    TextButton(
                      onPressed: state?.emailVerificationSupported == true
                          ? _confirm
                          : null,
                      child: Text(l.accountEmailConfirm),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
