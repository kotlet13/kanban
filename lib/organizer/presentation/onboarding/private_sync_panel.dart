import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_session_boundary.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_status.dart';
import '../backup/backup_counts.dart';
import '../finance/shared_finance_conflicts.dart';
import '../shared/sharing_sync_conflicts.dart';

class PrivateSyncPanel extends ConsumerStatefulWidget {
  const PrivateSyncPanel({super.key, required this.onConnect});
  final VoidCallback onConnect;
  @override
  ConsumerState<PrivateSyncPanel> createState() => _PrivateSyncPanelState();
}

class _PrivateSyncPanelState extends ConsumerState<PrivateSyncPanel> {
  final _busyStatus = ValueNotifier<bool>(false);
  bool get _busy => _busyStatus.value;
  @override
  void dispose() {
    _busyStatus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted || _busy) return;
    setState(() => _busyStatus.value = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyStatus.value = false);
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
                  Text(l.privateSyncSourceDefault),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.privateSyncTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SharingStatus(
                  key: const ValueKey('private-sync-status'),
                  state: state ?? CollaborationState(),
                  privateSync: true,
                  scopeId: sync?.scopeId,
                  busyListenable: _busyStatus,
                  onSync: () => _run(
                    () => ref.read(collaborationProvider.notifier).syncNow(),
                  ),
                  onConflicts: () => showSharingSyncConflicts(context, ref),
                  onConnect: widget.onConnect,
                  detailsBuilder: (dialogContext, current, actionsEnabled) =>
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (current.privateSync.scopeId != null &&
                              current.financeConflicts.any(
                                (c) => c.scopeId == current.privateSync.scopeId,
                              ))
                            TextButton(
                              onPressed: () {
                                if (!mounted) return;
                                final active = ref
                                    .read(collaborationProvider)
                                    .valueOrNull
                                    ?.session;
                                if (active?.partition !=
                                        current.session?.partition ||
                                    active?.deviceId !=
                                        current.session?.deviceId) {
                                  return;
                                }
                                showFinanceConflicts(
                                  dialogContext,
                                  ref,
                                  current.privateSync.scopeId!,
                                );
                              },
                              child: Text(l.financeConflicts),
                            ),
                        ],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l.privateSyncDescription),
            Text(l.privateSyncSourceDefault),
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
              TextButton.icon(
                onPressed: _busy ? null : () => _run(_enable),
                icon: const Icon(Icons.devices),
                label: Text(l.privateSyncReview),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
