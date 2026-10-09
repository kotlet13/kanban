import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';

class GardenSpaceChooser extends ConsumerWidget {
  const GardenSpaceChooser({
    super.key,
    required this.onLocal,
    required this.onShared,
  });
  final ValueChanged<String> onLocal, onShared;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final local = ref.watch(localSpacesProvider).valueOrNull;
    final shared = ref.watch(collaborationProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.gardenTitle,
          subtitle: l.localSpaceChooseHousehold,
        ),
        for (final space in local?.spaces ?? <LocalSpace>[])
          if (space.kind == LocalSpaceKind.household && space.binding == null)
            ListTile(
              key: ValueKey('garden-space-local-${space.id}'),
              leading: const Icon(Icons.home_outlined),
              title: Text(space.name),
              subtitle: Text(l.localSpaceState),
              onTap: () => onLocal(space.id),
            ),
        if (shared?.localAccessAllowed == true)
          for (final scope in shared!.scopes)
            if (scope.kind == SharedScopeKind.household &&
                !scope.revoked &&
                !scope.blocked)
              ListTile(
                key: ValueKey('garden-space-shared-${scope.id}'),
                leading: const Icon(Icons.home_outlined),
                title: Text(scope.name),
                subtitle: Text(l.sharingShared),
                onTap: () => onShared(scope.id),
              ),
      ],
    );
  }
}
