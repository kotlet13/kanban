import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/local_spaces_provider.dart';
import 'content_moderation.dart';
import 'sharing_session_boundary.dart';

/// Contextual linking keeps the original local identity and uses the durable
/// publication request IDs. Calling again recovers the same server destination.
Future<String?> showLocalSpaceConnection(
  BuildContext context,
  WidgetRef ref, {
  required String localSpaceId,
}) async {
  final guard = SharingSessionGuard(context, ref);
  final existing = ref
      .read(localSpacesProvider)
      .valueOrNull
      ?.spaces
      .where((s) => s.id == localSpaceId)
      .firstOrNull;
  if (existing == null || existing.archived) {
    throw const CollaborationException('backup_stale');
  }
  if (existing.binding != null) {
    if (existing.binding!.partition != guard.session?.partition) {
      throw const CollaborationException('space_bound_to_other_account');
    }
    return existing.binding!.scopeId;
  }
  final preview = await guard.controller.previewLocalSpacesPublication([
    localSpaceId,
  ]);
  if (!context.mounted || !guard.isCurrent) return null;
  if (!preview.canPublish) throw CollaborationException(preview.issues.first);
  final item = preview.spaces.single;
  final hasContents =
      item.recordCount > 0 ||
      item.gardenCount > 0 ||
      item.ideaCount > 0 ||
      item.ideaDraftCount > 0 ||
      item.linkedPaymentCount > 0 ||
      item.projects.isNotEmpty;
  if (hasContents) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => SharingSessionBoundary(
        guard: guard,
        child: AlertDialog(
          scrollable: true,
          title: Text(context.l10n.localSpaceLinkAction),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.space.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${preview.accountName} · ${Uri.tryParse(preview.serverUrl)?.host ?? preview.serverUrl}',
                ),
                const SizedBox(height: 12),
                Text(context.l10n.localSpaceConnectionPreview),
                Text(
                  context.l10n.localSpaceConnectionCounts(
                    item.recordCount,
                    item.gardenCount,
                  ),
                ),
                Text(
                  '${context.l10n.ideasCountLabel}: ${item.ideaCount} · ${context.l10n.ideaDraftsCountLabel}: ${item.ideaDraftCount}',
                ),
                if (item.linkedPaymentCount > 0)
                  Text(
                    context.l10n.paymentPublicationCount(
                      item.linkedPaymentCount,
                    ),
                  ),
                for (final project in item.projects)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(project.name),
                    subtitle: Text(
                      context.l10n.localSpaceConnectionProjectCounts(
                        project.taskCount,
                        project.financeCount,
                        project.personCount,
                        project.accountCount,
                      ),
                    ),
                  ),
                if (item.space.kind == LocalSpaceKind.organization &&
                    item.projects.isNotEmpty)
                  Text(context.l10n.organizationProjectFinanceVisibility),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey('confirm-space-connection'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.localSpaceLinkAction),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return null;
  }
  if (!context.mounted || !guard.isCurrent) return null;
  if (!await showSharedContentPolicy(context)) return null;
  if (!context.mounted || !guard.isCurrent) return null;
  await guard.controller.publishLocalSpaces(preview);
  if (!context.mounted || !guard.isCurrent) return null;
  // Publication uses the durable local ID as the remote ID.
  return localSpaceId;
}
