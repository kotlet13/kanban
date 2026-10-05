import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/collaboration_models.dart';
import 'sharing_errors.dart';

class SharingStatus extends StatelessWidget {
  const SharingStatus({
    super.key,
    required this.state,
    required this.onSync,
    required this.onConflicts,
    this.onExport,
  });
  final CollaborationState state;
  final VoidCallback onSync;
  final VoidCallback onConflicts;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final label = state.isSyncing
        ? l.sharingSyncing
        : state.lastError != null
        ? sharingErrorMessage(context, state.lastError!)
        : state.pendingCount > 0
        ? '${state.pendingCount} · ${l.sharingPending}'
        : l.sharingNoPending;
    if (!state.isSyncing &&
        state.lastError == null &&
        state.pendingCount == 0 &&
        state.conflicts.isEmpty &&
        state.blockedCount == 0) {
      return Row(
        children: [
          Icon(Icons.cloud_outlined, color: scheme.onSurfaceVariant, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          IconButton(
            tooltip: l.sharingSyncNow,
            onPressed: onSync,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      );
    }
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  state.lastError != null
                      ? Icons.cloud_off_outlined
                      : Icons.sync_outlined,
                  color: scheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(label)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: state.isSyncing ? null : onSync,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l.sharingSyncNow),
                ),
                if (state.conflicts.isNotEmpty)
                  TextButton.icon(
                    onPressed: onConflicts,
                    icon: const Icon(Icons.compare_arrows, size: 18),
                    label: Text(
                      '${l.sharingConflictsButton} (${state.conflicts.length})',
                    ),
                  ),
                if (onExport != null &&
                    (state.pendingCount > 0 ||
                        state.conflicts.isNotEmpty ||
                        state.blockedCount > 0))
                  TextButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(l.sharingSaveDrafts),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SharingScopePicker extends StatelessWidget {
  const SharingScopePicker({
    super.key,
    required this.scopes,
    required this.selectedId,
    required this.onChanged,
  });
  final List<SharedScope> scopes;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('sharing-scope-$selectedId'),
    initialValue: scopes.any((scope) => scope.id == selectedId)
        ? selectedId
        : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: context.l10n.sharingChooseSpace),
    items: [
      for (final scope in scopes)
        DropdownMenuItem(
          value: scope.id,
          child: Text(
            '${scope.name} · ${sharingRoleLabel(context, scope.role)}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}
