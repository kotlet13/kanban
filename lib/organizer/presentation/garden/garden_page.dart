import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/garden_models.dart';
import '../../state/garden_provider.dart';
import '../organizer_widgets.dart';
import 'garden_editor.dart';

class GardenPage extends ConsumerWidget {
  const GardenPage({super.key});

  Future<void> _open(BuildContext context, {Garden? garden}) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => GardenEditor(garden: garden)));

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Garden garden,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.gardenDeleteTitle),
        content: Text(context.l10n.gardenDeleteBody(garden.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('garden-confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(gardenProvider.notifier).deleteGarden(garden);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.gardenSaveError)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(title: l.gardenTitle, subtitle: l.gardenIntro),
        Text(l.gardenLocalOnly, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 20),
        ref
            .watch(gardenProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => OrganizerEmpty(
                icon: Icons.error_outline,
                title: l.organizerLoadError,
                action: l.organizerRetry,
                onAction: () => ref.invalidate(gardenRepositoryProvider),
              ),
              data: (snapshot) => snapshot.gardens.isEmpty
                  ? OrganizerEmpty(
                      icon: Icons.yard_outlined,
                      title: l.gardenEmptyTitle,
                      description: l.gardenEmptyBody,
                      action: l.gardenNew,
                      onAction: () => _open(context),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            key: const ValueKey('garden-new'),
                            onPressed: snapshot.gardens.length >= 500
                                ? null
                                : () => _open(context),
                            icon: const Icon(Icons.add),
                            label: Text(l.gardenNew),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final garden in snapshot.gardens)
                          Card(
                            child: ListTile(
                              key: ValueKey('garden-${garden.id}'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              leading: const Icon(Icons.yard_outlined),
                              title: Text(
                                garden.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  l.gardenAreaCount(garden.areas.length),
                                  if (garden.notes.isNotEmpty) garden.notes,
                                ].join('\n'),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _open(context, garden: garden),
                              trailing: IconButton(
                                tooltip: l.delete,
                                onPressed: () => _delete(context, ref, garden),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
      ],
    );
  }
}
