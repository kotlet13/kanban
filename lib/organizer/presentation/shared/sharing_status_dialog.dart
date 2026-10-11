import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_status_projection.dart';

String sharingStatusLabel(BuildContext context, SharingSyncStatus status) =>
    switch (status) {
      SharingSyncStatus.local => context.l10n.syncStatusDeviceOnly,
      SharingSyncStatus.unknown => context.l10n.syncStatusUnknown,
      SharingSyncStatus.synced => context.l10n.syncStatusSynced,
      SharingSyncStatus.pending => context.l10n.syncStatusPending,
      SharingSyncStatus.syncing => context.l10n.sharingSyncing,
      SharingSyncStatus.offline => context.l10n.syncStatusOffline,
      SharingSyncStatus.problem => context.l10n.syncStatusProblem,
      SharingSyncStatus.paused => context.l10n.privateSyncPaused,
      SharingSyncStatus.disabled => context.l10n.privateSyncOff,
    };

typedef SharingStatusDetailsBuilder =
    Widget Function(
      BuildContext context,
      CollaborationState state,
      bool actionsEnabled,
    );

Future<void> showSharingStatusDetails(
  BuildContext context, {
  required CollaborationState state,
  required VoidCallback onSync,
  required VoidCallback onConflicts,
  VoidCallback? onExport,
  VoidCallback? onConnect,
  String? scopeId,
  bool privateSync = false,
  bool allowLocalActions = false,
  ValueListenable<bool>? busyListenable,
  SharingStatusDetailsBuilder? detailsBuilder,
  ValueListenable<SharingStatusSupplement>? supplementListenable,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SharingStatusDialog(
    originContext: context,
    capturedState: state,
    onSync: onSync,
    onConflicts: onConflicts,
    onExport: onExport,
    onConnect: onConnect,
    scopeId: scopeId,
    privateSync: privateSync,
    allowLocalActions: allowLocalActions,
    busyListenable: busyListenable,
    detailsBuilder: detailsBuilder,
    supplementListenable: supplementListenable,
  ),
);

class _SharingStatusDialog extends ConsumerWidget {
  const _SharingStatusDialog({
    required this.capturedState,
    required this.originContext,
    required this.onSync,
    required this.onConflicts,
    this.onExport,
    this.onConnect,
    this.scopeId,
    required this.privateSync,
    required this.allowLocalActions,
    this.busyListenable,
    this.detailsBuilder,
    this.supplementListenable,
  });
  final CollaborationState capturedState;
  final BuildContext originContext;
  final VoidCallback onSync, onConflicts;
  final VoidCallback? onExport, onConnect;
  final String? scopeId;
  final bool privateSync, allowLocalActions;
  final ValueListenable<bool>? busyListenable;
  final SharingStatusDetailsBuilder? detailsBuilder;
  final ValueListenable<SharingStatusSupplement>? supplementListenable;

  String _identity(CollaborationState state) =>
      '${state.session?.partition}:${state.session?.deviceId}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(collaborationProvider);
    ref.watch(collaborationBackgroundErrorProvider);
    final state = current.valueOrNull;
    if (!originContext.mounted ||
        state == null ||
        _identity(state) != _identity(capturedState)) {
      return AlertDialog(
        title: Text(context.l10n.syncStatusTitle),
        content: Text(context.l10n.sharingSessionExpired),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      );
    }
    Widget body(bool busy) => supplementListenable == null
        ? _body(
            context,
            ref,
            state,
            busy,
            current.isLoading,
            const SharingStatusSupplement(),
          )
        : ValueListenableBuilder<SharingStatusSupplement>(
            valueListenable: supplementListenable!,
            builder: (context, supplement, _) =>
                _body(context, ref, state, busy, current.isLoading, supplement),
          );
    return busyListenable == null
        ? body(false)
        : ValueListenableBuilder<bool>(
            valueListenable: busyListenable!,
            builder: (context, busy, _) => body(busy),
          );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    CollaborationState state,
    bool busy,
    bool loading,
    SharingStatusSupplement supplement,
  ) {
    final l = context.l10n;
    final backgroundError = ref.read(collaborationBackgroundErrorProvider);
    final projection = SharingStatusProjection.fromState(
      state,
      now: DateTime.now(),
      privateSync: privateSync,
      busy: busy,
      scopeId: scopeId,
      supplement: supplement,
      backgroundError: backgroundError,
    );
    final actionsEnabled =
        !busy &&
        !state.isSyncing &&
        !loading &&
        (projection.sessionValid || allowLocalActions && state.session == null);
    final localActionsEnabled = !busy && !state.isSyncing && !loading;
    final label = sharingStatusLabel(context, projection.status);
    void run(VoidCallback action) {
      final current = ref.read(collaborationProvider).valueOrNull;
      if (originContext.mounted &&
          current != null &&
          _identity(current) == _identity(capturedState)) {
        action();
      }
    }

    String time(DateTime? value, String fallback) => value == null
        ? fallback
        : DateFormat.yMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).add_Hm().format(value.toLocal());
    final scope = state.scopes
        .where((scope) => scope.id == scopeId)
        .firstOrNull;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(l.syncStatusTitle),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                key: const ValueKey('sharing-sync-dialog-status'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (scope != null) Text(scope.name),
              Text(
                state.session == null
                    ? l.syncStatusLocalScope
                    : l.syncStatusAccountScope,
              ),
              const SizedBox(height: 16),
              Text(
                '${l.syncStatusLastSuccess}: ${time(state.lastSuccessfulSyncAt, l.syncStatusNotConfirmed)}',
              ),
              const SizedBox(height: 8),
              Text(
                '${l.syncStatusLastAttempt}: ${time(state.lastSyncAttemptAt, l.syncStatusNeverAttempted)}',
              ),
              const SizedBox(height: 16),
              Text('${l.syncStatusPendingCount}: ${projection.pending}'),
              Text('${l.syncStatusConflictsCount}: ${projection.conflicts}'),
              Text('${l.syncStatusBlockedCount}: ${projection.blocked}'),
              if (supplement.label != null ||
                  supplement.pendingCount > 0 ||
                  supplement.blockedCount > 0 ||
                  supplement.hasProblem ||
                  supplement.requiresRefresh) ...[
                const SizedBox(height: 16),
                if (supplement.label != null)
                  Text(
                    supplement.label!,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                Text('${l.syncStatusPendingCount}: ${supplement.pendingCount}'),
                Text('${l.syncStatusBlockedCount}: ${supplement.blockedCount}'),
                if (supplement.hasProblem) Text(l.syncStatusProblem),
                if (supplement.requiresRefresh) Text(l.syncStatusNotConfirmed),
              ],
              if (state.lastError != null) ...[
                const SizedBox(height: 16),
                Text(
                  '${l.syncStatusLastError}: ${state.lastError!.code == 'server_identity_changed' ? l.syncStatusServerChanged : sharingErrorMessage(context, state.lastError!)}',
                ),
              ],
              if (backgroundError != null &&
                  !identical(backgroundError, state.lastError)) ...[
                const SizedBox(height: 12),
                Text(
                  '${l.syncStatusLastError}: ${sharingErrorMessage(context, backgroundError)}',
                ),
              ],
              if (privateSync) ...[
                const SizedBox(height: 12),
                Text(
                  state.privateSync.enabled
                      ? state.privateSync.paused
                            ? l.privateSyncPaused
                            : l.privateSyncOn
                      : l.privateSyncOff,
                ),
                if (state.privateSync.localPendingCount > 0)
                  Text(l.privateSyncLocalPending),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (state.session != null || allowLocalActions)
                    TextButton.icon(
                      key: const ValueKey('sharing-sync-dialog-refresh'),
                      onPressed: actionsEnabled ? () => run(onSync) : null,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(l.sharingSyncNow),
                    ),
                  if (projection.conflicts > 0)
                    TextButton.icon(
                      onPressed: localActionsEnabled
                          ? () => run(onConflicts)
                          : null,
                      icon: const Icon(Icons.compare_arrows, size: 18),
                      label: Text(l.sharingConflictsButton),
                    ),
                  if (onExport != null &&
                      (projection.pending > 0 ||
                          projection.conflicts > 0 ||
                          projection.blocked > 0))
                    TextButton.icon(
                      onPressed: localActionsEnabled
                          ? () => run(onExport!)
                          : null,
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: Text(l.sharingSaveDrafts),
                    ),
                  if (onConnect != null && !projection.sessionValid)
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () {
                              Navigator.pop(context);
                              run(onConnect!);
                            },
                      icon: const Icon(Icons.login, size: 18),
                      label: Text(l.sharingLoginAction),
                    ),
                ],
              ),
              if (detailsBuilder != null)
                detailsBuilder!(context, state, actionsEnabled),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}
