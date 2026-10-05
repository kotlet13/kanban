import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_session_boundary.dart';
import '../shared/sharing_errors.dart';
import '../backup/backup_counts.dart';
import '../finance/shared_finance_conflicts.dart';
import '../shared/sharing_conflicts.dart';

class PrivateSyncPanel extends ConsumerStatefulWidget {
  const PrivateSyncPanel({super.key, required this.onConnect});
  final VoidCallback onConnect;
  @override
  ConsumerState<PrivateSyncPanel> createState() => _PrivateSyncPanelState();
}

class _PrivateSyncPanelState extends ConsumerState<PrivateSyncPanel> {
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    final guard = SharingSessionGuard(context, ref);
    final preview = await guard.controller.previewPrivateSync();
    if (!mounted || !guard.isCurrent) return;
    final l = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: (state) => !state.sessionInvalid,
        child: AlertDialog(
          title: Text(l.privateSyncReview),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.privateSyncUploadWarning),
                  const SizedBox(height: 16),
                  BackupCounts(counts: preview.recordCounts),
                  Text(
                    '${l.privateSyncRemoteCount}: ${preview.existingRemoteCount}',
                  ),
                  if (!preview.canEnable) Text(l.privateSyncIssue),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: preview.canEnable
                  ? () => Navigator.pop(context, true)
                  : null,
              child: Text(l.privateSyncEnable),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted && guard.isCurrent) {
      await guard.controller.enablePrivateSync(
        expectedRevision: preview.revision,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n,
        state = ref.watch(collaborationProvider).valueOrNull,
        session = state?.session,
        sync = state?.privateSync;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.privateSyncTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l.privateSyncDescription),
            const SizedBox(height: 12),
            if (session == null) ...[
              Text(l.privateSyncUnavailable),
              TextButton(
                onPressed: widget.onConnect,
                child: Text(l.sharingLoginAction),
              ),
            ] else if (state?.sessionInvalid == true ||
                !session.expiresAt.isAfter(DateTime.now()))
              Text(l.sharingSessionExpired)
            else if (sync?.available != true)
              Text(l.privateSyncUnavailable)
            else if (sync!.enabled) ...[
              Text(sync.paused ? l.privateSyncPaused : l.privateSyncOn),
              Text('${l.privateSyncPending}: ${sync.pendingCount}'),
              if (state!.conflicts.any((c) => c.scopeId == sync.scopeId))
                TextButton(
                  onPressed: () => showSharingConflicts(context, ref),
                  child: Text(l.sharingConflicts),
                ),
              if (sync.scopeId != null &&
                  state.financeConflicts.any((c) => c.scopeId == sync.scopeId))
                TextButton(
                  onPressed: () =>
                      showFinanceConflicts(context, ref, sync.scopeId!),
                  child: Text(l.financeConflicts),
                ),
              if (sync.localPendingCount > 0) ...[
                Text(l.privateSyncLocalPending),
                TextButton(
                  onPressed: _busy ? null : () => _run(_enable),
                  child: Text(l.privateSyncReview),
                ),
              ],
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => sync.paused
                            ? ref
                                  .read(collaborationProvider.notifier)
                                  .resumePrivateSync()
                            : ref
                                  .read(collaborationProvider.notifier)
                                  .pausePrivateSync(),
                      ),
                icon: Icon(sync.paused ? Icons.play_arrow : Icons.pause),
                label: Text(
                  sync.paused ? l.privateSyncResume : l.privateSyncPause,
                ),
              ),
            ] else ...[
              Text(l.privateSyncOff),
              TextButton.icon(
                onPressed: _busy ? null : () => _run(_enable),
                icon: const Icon(Icons.devices),
                label: Text(l.privateSyncReview),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
