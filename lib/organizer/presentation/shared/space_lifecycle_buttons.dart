import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

/// Explicit space actions belong at the end of its settings, after its details.
/// Callbacks retain the existing archive and counted deletion confirmation flow.
class SpaceLifecycleButtons extends StatelessWidget {
  const SpaceLifecycleButtons({
    super.key,
    required this.actionKey,
    required this.archived,
    this.onArchive,
    this.onDelete,
  });

  final String actionKey;
  final bool archived;
  final VoidCallback? onArchive, onDelete;

  @override
  Widget build(BuildContext context) {
    if (onArchive == null && onDelete == null) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const SizedBox(height: 12),
          if (onArchive != null)
            OutlinedButton.icon(
              key: ValueKey('$actionKey-archive'),
              onPressed: onArchive,
              icon: Icon(
                archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              label: Text(
                archived ? l.spaceRestoreAction : l.spaceArchiveAction,
              ),
            ),
          if (onArchive != null && onDelete != null) const SizedBox(height: 8),
          if (onDelete != null)
            TextButton.icon(
              key: ValueKey('$actionKey-delete'),
              onPressed: onDelete,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline),
              label: Text(l.spaceDeleteAction),
            ),
        ],
      ),
    );
  }
}
