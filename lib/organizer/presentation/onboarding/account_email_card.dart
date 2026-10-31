import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/account_summary_refresh_provider.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_forms.dart';
import '../shared/sharing_session_boundary.dart';

class AccountEmailCard extends ConsumerStatefulWidget {
  const AccountEmailCard({
    super.key,
    required this.session,
    this.onStatusChanged,
  });
  final AccountSession session;
  final ValueChanged<AccountStatus?>? onStatusChanged;
  @override
  ConsumerState<AccountEmailCard> createState() => _AccountEmailCardState();
}

class _AccountEmailCardState extends ConsumerState<AccountEmailCard>
    with WidgetsBindingObserver {
  late final _guard = SharingSessionGuard(
    context,
    ref,
    session: widget.session,
  );
  late Future<AccountStatus> _future = _load();
  AccountStatus? _status;
  int _generation = 0;
  Timer? _refreshTimer;
  DateTime? _pollUntil;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pollUntil = DateTime.now().add(const Duration(minutes: 3));
  }

  void _notify(AccountStatus? status, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _guard.isCurrent && generation == _generation) {
        widget.onStatusChanged?.call(status);
      }
    });
  }

  Future<AccountStatus> _load() {
    final future = _loadStatus();
    // A refresh can fail before FutureBuilder attaches on the next frame. Keep
    // the same future for its error UI, with an immediate handled branch.
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    return future;
  }

  Future<AccountStatus> _loadStatus() async {
    final generation = ++_generation;
    _refreshTimer?.cancel();
    _notify(null, generation);
    try {
      final status = await _guard.controller.accountStatus();
      if (mounted && _guard.isCurrent && generation == _generation) {
        _status = status;
        _notify(status, generation);
        _scheduleRefresh();
      }
      return status;
    } catch (_) {
      if (mounted && _guard.isCurrent && generation == _generation) {
        _status = null;
        _notify(null, generation);
      }
      rethrow;
    }
  }

  void _scheduleRefresh() {
    if (!_foreground ||
        _status?.pendingEmail == null ||
        !DateTime.now().isBefore(_pollUntil!)) {
      return;
    }
    _refreshTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _guard.isCurrent && _foreground) {
        setState(() {
          _future = _load();
        });
      }
    });
  }

  void _refresh({bool restartWindow = false}) {
    if (!mounted || !_guard.isCurrent) return;
    if (restartWindow) {
      _pollUntil = DateTime.now().add(const Duration(minutes: 3));
    }
    setState(() {
      _future = _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _refreshTimer?.cancel();
      return;
    }
    if (_status == null ||
        !_status!.emailVerified ||
        _status!.pendingEmail != null) {
      _refresh(restartWindow: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
        _future = _load();
      });
    }
  }

  Future<void> _confirm() async {
    final l = context.l10n;
    AccountStatus? confirmed;
    await showSharingForm(
      context,
      title: l.emailLinkReviewManualTitle,
      description: l.emailLinkReviewManualDescription,
      fields: [
        SharingField(id: 'token', label: l.accountEmailCode, sensitive: true),
      ],
      submitLabel: l.emailLinkReviewTitle,
      errorMessage: (e) => sharingErrorMessage(context, e),
      wrap: (form) => SharingSessionBoundary(guard: _guard, child: form),
      onSubmit: (values) async {
        confirmed = await _guard.controller.confirmEmailVerification(
          values['token']!.trim(),
        );
      },
    );
    if (confirmed != null && mounted && _guard.isCurrent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.accountEmailConfirmed)));
      _refreshTimer?.cancel();
      final generation = ++_generation;
      _status = confirmed;
      _notify(confirmed, generation);

      setState(() {
        _future = Future.value(confirmed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      accountSummaryRefreshProvider((
        widget.session.partition,
        widget.session.deviceId,
      )),
      (_, _) {
        if (!mounted || !_guard.isCurrent) return;
        setState(() {
          _future = _load();
        });
      },
    );
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
                l.emailLinkReviewCardTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (snapshot.hasError) ...[
                Text(sharingErrorMessage(context, snapshot.error!)),
                TextButton(
                  onPressed: () => setState(() {
                    _future = _load();
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
                    if (snapshot.data!.pendingEmail != null)
                      FilledButton(
                        onPressed: state?.emailVerificationSupported == true
                            ? _confirm
                            : null,
                        child: Text(l.emailLinkReviewTitle),
                      ),
                    TextButton(
                      onPressed: state?.emailVerificationSupported == true
                          ? _change
                          : null,
                      child: Text(l.accountEmailChange),
                    ),
                    if (!snapshot.data!.emailVerified ||
                        snapshot.data!.pendingEmail != null)
                      TextButton(
                        onPressed: () => _refresh(restartWindow: true),
                        child: Text(l.emailLinkReviewRefresh),
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
