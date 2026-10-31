import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/account_summary_refresh_provider.dart';
import '../../presentation/shared/sharing_errors.dart';
import 'email_verification_link.dart';

/// Reviewing a link cannot sign in, switch accounts or accept an invitation.
class EmailVerificationLinkReview extends ConsumerStatefulWidget {
  const EmailVerificationLinkReview({super.key, required this.link});
  final EmailVerificationLink link;
  @override
  ConsumerState<EmailVerificationLinkReview> createState() =>
      _EmailVerificationLinkReviewState();
}

class _EmailVerificationLinkReviewState
    extends ConsumerState<EmailVerificationLinkReview> {
  bool _busy = false, _verified = false;
  Object? _error;
  late final _session = ref.read(collaborationProvider).valueOrNull?.session;
  bool get _matches {
    final current = ref.read(collaborationProvider).valueOrNull?.session;
    return current != null &&
        _session != null &&
        current.partition == _session.partition &&
        current.deviceId == _session.deviceId &&
        widget.link.matches(current);
  }

  Future<void> _confirm() async {
    if (!_matches || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await ref
          .read(collaborationProvider.notifier)
          .confirmEmailVerificationLink(
            widget.link.token,
            accountId: widget.link.accountId,
            serverId: widget.link.serverId,
            email: widget.link.email,
          );
      if (!mounted || !_matches) return;
      if (!status.emailVerified || status.email != widget.link.email) {
        throw const CollaborationException('account_token_invalid');
      }
      refreshAccountSummaries(
        ProviderScope.containerOf(context),
        partition: _session!.partition,
        deviceId: _session.deviceId,
      );
      setState(() => _verified = true);
    } catch (error) {
      if (mounted && _matches) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(collaborationProvider);
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.emailLinkReviewTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.link.email),
          const SizedBox(height: 8),
          Text(widget.link.serverUrl),
          const SizedBox(height: 12),
          Text(
            _verified
                ? l.accountEmailConfirmed
                : !_matches
                ? l.emailLinkReviewWrongAccount
                : l.emailLinkReviewDescription,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(sharingErrorMessage(context, _error!)),
          ],
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.close),
        ),
        if (!_verified && _matches)
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: Text(l.emailLinkReviewTitle),
          ),
      ],
    );
  }
}
