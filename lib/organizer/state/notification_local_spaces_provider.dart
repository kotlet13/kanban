import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/organizer_models.dart';
import 'collaboration_provider.dart';
import 'local_spaces_provider.dart';

/// Alarm eligibility is independent of the workspace currently being edited.
/// Published local rows are parked; the authorized shared scope supplies them.
final notificationLocalSnapshotsProvider =
    FutureProvider<List<OrganizerSnapshot>>((ref) async {
      final shared = ref.watch(collaborationProvider);
      final catalog = await ref.watch(localSpacesProvider.future);
      final state = shared.valueOrNull;
      return List.unmodifiable([
        for (final space in catalog.spaces)
          if (space.binding == null && catalog.snapshots[space.id] != null)
            if (!catalog.snapshots[space.id]!.workspaceKey.startsWith(
                  'private:',
                ) ||
                state?.localAccessAllowed == true &&
                    state?.session != null &&
                    catalog.snapshots[space.id]!.workspaceKey ==
                        'private:${state!.session!.partition}' &&
                    state.scopes.any(
                      (scope) =>
                          scope.id == state.privateSync.scopeId &&
                          !scope.revoked &&
                          !scope.blocked &&
                          !scope.archived,
                    ))
              catalog.snapshots[space.id]!,
      ]);
    });
