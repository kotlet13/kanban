import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import 'collection_actions.dart';
import 'organizer_widgets.dart';
import 'planning/project_planning_summary.dart';

class OrganizerProjectsPage extends StatefulWidget {
  const OrganizerProjectsPage({
    super.key,
    required this.snapshot,
    required this.actions,
    this.home = false,
    this.selectedId,
    required this.onSelection,
    this.readOnly = false,
    this.allowProjectCreation = true,
    this.scopeLabel,
    this.onShare,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerCollectionActions actions;
  final bool readOnly;
  final bool allowProjectCreation;
  final String? scopeLabel;
  final ValueChanged<LocalProject>? onShare;
  final bool home;
  final String? selectedId;
  final ValueChanged<String?> onSelection;
  @override
  State<OrganizerProjectsPage> createState() => _OrganizerProjectsPageState();
}

class _OrganizerProjectsPageState extends State<OrganizerProjectsPage> {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final visibleProjects = widget.snapshot.projects
        .where((p) => !widget.home || p.area == ProjectArea.home)
        .toList();
    final selected = visibleProjects
        .where((p) => p.id == widget.selectedId)
        .firstOrNull;
    final projects = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: widget.home ? l.organizerHome : l.organizerProjects,
          subtitle:
              widget.scopeLabel ??
              (widget.home
                  ? l.organizerHomeIntro
                  : l.organizerNoProjectsDescription),
          action:
              visibleProjects.isEmpty ||
                  widget.readOnly ||
                  !widget.allowProjectCreation
              ? null
              : FilledButton.icon(
                  onPressed: () => widget.actions.project(
                    null,
                    widget.home ? ProjectArea.home : ProjectArea.personal,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l.organizerAddProject),
                ),
        ),
        if (visibleProjects.isEmpty)
          OrganizerEmpty(
            icon: Icons.folder_outlined,
            title: l.organizerNoProjects,
            action: widget.readOnly || !widget.allowProjectCreation
                ? null
                : l.organizerAddProject,
            onAction: widget.readOnly || !widget.allowProjectCreation
                ? null
                : () => widget.actions.project(
                    null,
                    widget.home ? ProjectArea.home : ProjectArea.personal,
                  ),
          ),
        for (final p in visibleProjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _projectCard(p),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760 && selected != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: projects),
              const SizedBox(width: 28),
              Expanded(flex: 5, child: _detail(selected, false)),
            ],
          );
        }
        return selected == null ? projects : _detail(selected, true);
      },
    );
  }

  Widget _projectCard(LocalProject project) {
    final tasks = widget.snapshot.tasks
        .where((t) => t.projectId == project.id)
        .toList();
    final done = tasks.where((t) => t.isCompleted).length;
    return Card(
      child: InkWell(
        onTap: () => widget.onSelection(project.id),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 23,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      project.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              if (project.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    project.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                context.l10n.organizerProjectProgress(done, tasks.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (tasks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: done / tasks.length,
                      minHeight: 3,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(LocalProject project, bool back) {
    final l = context.l10n;
    final tasks = widget.snapshot.tasks
        .where((t) => t.projectId == project.id)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (back)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => widget.onSelection(null),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(l.organizerProjects),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: OrganizerHeading(
                title: project.title,
                subtitle: project.description.isEmpty
                    ? (widget.scopeLabel ?? l.organizerPersonal)
                    : project.description,
              ),
            ),
            if (!widget.readOnly)
              IconButton(
                tooltip: l.organizerEditProject,
                onPressed: () => widget.actions.project(project),
                icon: const Icon(Icons.more_horiz),
              ),
          ],
        ),
        if (widget.onShare != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => widget.onShare!(project),
                icon: const Icon(Icons.people_outline, size: 18),
                label: Text(l.sharingCopyAction),
              ),
            ),
          ),
        ProjectPlanningSummary(
          project: project,
          tasks: tasks,
          onTaskSelected: widget.readOnly
              ? null
              : (task) => widget.actions.task(task: task),
        ),
        OrganizerSection(
          title: l.organizerTasks,
          action: widget.readOnly
              ? null
              : IconButton(
                  tooltip: l.organizerAddTask,
                  onPressed: () => widget.actions.task(projectId: project.id),
                  icon: const Icon(Icons.add),
                ),
          child: tasks.isEmpty
              ? OrganizerEmpty(
                  icon: Icons.check_circle_outline,
                  title: l.organizerNoMatchingTasks,
                  action: widget.readOnly ? null : l.organizerAddTask,
                  onAction: widget.readOnly
                      ? null
                      : () => widget.actions.task(projectId: project.id),
                )
              : Column(
                  children: [
                    for (final task in tasks)
                      OrganizerTaskRow(
                        task: task,
                        snapshot: widget.snapshot,
                        onEdit: widget.readOnly
                            ? null
                            : () => widget.actions.task(task: task),
                        onCompleted: widget.readOnly
                            ? null
                            : (v) =>
                                  widget.actions.setTaskCompleted(task.id, v),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class OrganizerTasksPage extends StatelessWidget {
  const OrganizerTasksPage({
    super.key,
    required this.snapshot,
    required this.actions,
    this.readOnly = false,
    this.scopeLabel,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerCollectionActions actions;
  final bool readOnly;
  final String? scopeLabel;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pending = snapshot.tasks.where((t) => !t.isCompleted).toList();
    final dated = pending.where((t) => t.dueAt != null).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final undated = pending.where((t) => t.dueAt == null).toList();
    final completed = snapshot.tasks.where((t) => t.isCompleted).toList();
    Widget row(LocalTask task) => OrganizerTaskRow(
      task: task,
      snapshot: snapshot,
      onEdit: readOnly ? null : () => actions.task(task: task),
      onCompleted: readOnly
          ? null
          : (v) => actions.setTaskCompleted(task.id, v),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.organizerTasks,
          subtitle: scopeLabel,
          action: readOnly
              ? null
              : FilledButton.icon(
                  onPressed: () => actions.task(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l.organizerAddTask),
                ),
        ),
        if (snapshot.tasks.isEmpty)
          OrganizerEmpty(
            icon: Icons.check_circle_outline,
            title: l.organizerNoTasks,
            description: l.organizerNoTasksDescription,
            action: readOnly ? null : l.organizerAddTask,
            onAction: readOnly ? null : () => actions.task(),
          ),
        for (final task in dated) row(task),
        if (undated.isNotEmpty) ...[
          const SizedBox(height: 24),
          OrganizerSection(
            title: l.organizerWithoutDate,
            child: Column(children: [for (final task in undated) row(task)]),
          ),
        ],
        if (completed.isNotEmpty) ...[
          const SizedBox(height: 20),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${l.organizerCompleted} (${completed.length})'),
            children: [for (final task in completed) row(task)],
          ),
        ],
      ],
    );
  }
}
