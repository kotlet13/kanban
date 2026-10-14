import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/organizer_models.dart';
import 'collaboration_provider.dart';
import 'local_spaces_provider.dart';

/// Alarm eligibility is independent of the workspace currently being edited.
/// Published local rows are parked; the authorized shared scope supplies them.
final notificationLocalSnapshotsProvider =
    FutureProvider<List<OrganizerSnapshot>>((ref) async {
      // Only authorization changes affect this catalog. A background sync or
      // notification-preference ACK must not rebuild it and its expanded rows.
      final access = ref.watch(
        collaborationProvider.select((value) {
          final state = value.valueOrNull;
          final private = state?.privateSync.scopeId;
          return (
            workspace: state?.session == null
                ? null
                : 'private:${state!.session!.partition}',
            allowed:
                state?.localAccessAllowed == true &&
                state?.session != null &&
                state!.scopes.any(
                  (scope) =>
                      scope.id == private &&
                      !scope.revoked &&
                      !scope.blocked &&
                      !scope.archived,
                ),
          );
        }),
      );
      final catalog = await ref.watch(localSpacesProvider.future);
      return List.unmodifiable([
        for (final space in catalog.spaces)
          if (!space.archived &&
              space.binding == null &&
              catalog.snapshots[space.id] != null)
            if (!catalog.snapshots[space.id]!.workspaceKey.startsWith(
                  'private:',
                ) ||
                access.allowed &&
                    catalog.snapshots[space.id]!.workspaceKey ==
                        access.workspace)
              activeProjectNotificationSnapshot(catalog.snapshots[space.id]!),
      ]);
    });

/// Archive affects active alarms, not stored financial facts or backup rows.
OrganizerSnapshot activeProjectNotificationSnapshot(
  OrganizerSnapshot snapshot,
) {
  final archived = snapshot.projects
      .where((p) => p.archived)
      .map((p) => p.id)
      .toSet();
  return archived.isEmpty
      ? snapshot
      : snapshot.copyWith(
          tasks: snapshot.tasks.where((t) => !archived.contains(t.projectId)),
          events: snapshot.events.where((e) => !archived.contains(e.projectId)),
          reminders: snapshot.reminders.where(
            (r) => snapshot.tasks.any(
              (t) => t.id == r.taskId && !archived.contains(t.projectId),
            ),
          ),
        );
}
