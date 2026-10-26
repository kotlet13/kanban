import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';

/// Account-wide recovery remains reachable even when every space is hidden.
class AccessReviewButton extends ConsumerStatefulWidget {
  const AccessReviewButton({super.key});
  @override
  ConsumerState<AccessReviewButton> createState() => _AccessReviewButtonState();
}

class _AccessReviewButtonState extends ConsumerState<AccessReviewButton> {
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    final guard = SharingSessionGuard(context, ref);
    setState(() => _busy = true);
    try {
      final result = await guard.controller.checkAllAccess();
      if (!mounted || !guard.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.sharingAccessReviewResult(
              result.available,
              result.restored,
              result.revoked,
              result.unresolved,
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted && guard.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    if (state?.session == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: _busy || state!.sessionInvalid || state.deletionPending
          ? null
          : _check,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.verified_user_outlined, size: 18),
      label: Text(
        _busy
            ? context.l10n.sharingCheckingAllAccess
            : context.l10n.sharingCheckAllAccess,
      ),
    );
  }
}
