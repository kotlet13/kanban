import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/all_spaces_projection.dart';
import '../domain/organizer_models.dart';
import '../state/collaboration_provider.dart';
import '../state/local_spaces_provider.dart';
import 'organizer_actions.dart';
import 'all_spaces/all_spaces_rows.dart';
import 'onboarding/getting_started.dart';
import 'planning/utrip_overview.dart';

class OrganizerTodayPage extends ConsumerWidget {
  const OrganizerTodayPage({
    super.key,
    required this.snapshot,
    required this.actions,
    required this.onShopping,
    this.showShopping = true,
    required this.onPlans,
    required this.onSharedAgenda,
    this.onCalendar,
    this.onProjects,
    this.onProjectSelected,
    this.onGettingStarted,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerActions actions;
  final VoidCallback onShopping;
  final bool showShopping;
  final VoidCallback onPlans;
  final ValueChanged<String> onSharedAgenda;
  final VoidCallback? onCalendar, onProjects, onGettingStarted;
  final ValueChanged<String>? onProjectSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(collaborationProvider);
    final all = projectAllSpaces(
      personal: snapshot,
      shared: shared.isLoading || shared.hasError
          ? CollaborationState()
          : shared.valueOrNull ?? CollaborationState(),
      localSpaces: ref.watch(localSpacesProvider).valueOrNull,
    );
    return OrganizerUtripOverview(
      snapshot: AllSpacesSnapshot(
        all.sources.where(
          (source) => source.workspaceKey == snapshot.workspaceKey,
        ),
      ),
      onOpen: (item) {
        if (!allSpacesSourceIsCurrent(ref, item.source)) return;
        switch (item.type) {
          case 'event':
            final event = snapshot.events
                .where((e) => e.id == item.id)
                .firstOrNull;
            if (event != null) actions.event(event);
          case 'project':
            final project = snapshot.projects
                .where((p) => p.id == item.id)
                .firstOrNull;
            if (project != null) {
              if (onProjectSelected != null) {
                onProjectSelected!(project.id);
              } else {
                actions.project(project);
              }
            }
          case 'task':
            final task = snapshot.tasks
                .where((t) => t.id == item.id)
                .firstOrNull;
            if (task != null) actions.task(task: task);
        }
      },
      onTasks: onPlans,
      onCalendar: onCalendar,
      onProjects: onProjects,
      onCreateTask: () => actions.task(),
      onCreateEvent: () => actions.event(),
      onCreateProject: () => actions.project(),
      headerHint: onGettingStarted == null
          ? null
          : GettingStartedHint(onStart: onGettingStarted!),
    );
  }
}
