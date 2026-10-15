import 'shared/content_actions_menu.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import 'collection_actions.dart';
import 'organizer_widgets.dart';
import 'desktop/desktop_layout.dart';
import 'inbox/remote_reminder_editor.dart';
import 'inbox/local_task_reminder_editor.dart';
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
    this.titleAccessory,
    this.reminderScopeId,
    this.reportScopeId,
    this.onShare,
    this.detailMenuBuilder,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerCollectionActions actions;
  final bool readOnly;
  final bool allowProjectCreation;
  final String? scopeLabel;
  final Widget? titleAccessory;
  final String? reminderScopeId;
  final String? reportScopeId;
  final ValueChanged<LocalProject>? onShare;
  final Widget Function(LocalProject)? detailMenuBuilder;
  final bool home;
  final String? selectedId;
  final ValueChanged<String?> onSelection;
  @override
  State<OrganizerProjectsPage> createState() => _OrganizerProjectsPageState();
}

class _OrganizerProjectsPageState extends State<OrganizerProjectsPage> {
  ProjectArea? _category;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final visibleProjects = widget.snapshot.projects
        .where(
          (p) =>
              !p.archived &&
              (!widget.home || p.area == ProjectArea.home) &&
              (_category == null || p.area == _category),
        )
        .toList();
    final archivedProjects = widget.snapshot.projects
        .where(
          (p) =>
              p.archived &&
              (!widget.home || p.area == ProjectArea.home) &&
              (_category == null || p.area == _category),
        )
        .toList();
    final selected = [
      ...visibleProjects,
      ...archivedProjects,
    ].where((p) => p.id == widget.selectedId).firstOrNull;
    final projects = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: widget.home ? l.organizerHome : l.organizerProjects,
          titleAccessory: widget.titleAccessory,
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
                    widget.home
                        ? ProjectArea.home
                        : _category ?? ProjectArea.personal,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l.organizerAddProject),
                ),
        ),
        if (!widget.home &&
            widget.reportScopeId == null &&
            widget.scopeLabel == null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('projects-category-all'),
                label: Text(l.allSpacesTitle),
                selected: _category == null,
                onSelected: (_) => setState(() => _category = null),
              ),
              ChoiceChip(
                key: const ValueKey('projects-category-home'),
                label: Text(l.organizerHomeProjects),
                selected: _category == ProjectArea.home,
                onSelected: (_) => setState(() => _category = ProjectArea.home),
              ),
              ChoiceChip(
                key: const ValueKey('projects-category-personal'),
                label: Text(l.organizerPersonal),
                selected: _category == ProjectArea.personal,
                onSelected: (_) =>
                    setState(() => _category = ProjectArea.personal),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
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
                    widget.home
                        ? ProjectArea.home
                        : _category ?? ProjectArea.personal,
                  ),
          ),
        for (final p in visibleProjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _projectCard(p),
          ),
        if (archivedProjects.isNotEmpty)
          ExpansionTile(
            key: const ValueKey('projects-archived'),
            tilePadding: EdgeInsets.zero,
            title: Text(
              '${l.scopeArchivedProjects} (${archivedProjects.length})',
            ),
            children: [
              for (final project in archivedProjects) _projectCard(project),
            ],
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = organizerUsesDesktopLayout(context);
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final splitWidth = desktop ? 820 * scale.clamp(1, 1.5) : 760;
        if (constraints.maxWidth >= splitWidth && selected != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (desktop)
                SizedBox(
                  width: (constraints.maxWidth * .34).clamp(280, 420),
                  child: projects,
                )
              else
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
    if (organizerUsesDesktopLayout(context)) return _desktopProjectRow(project);
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
                  _projectMenu(project),
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

  Widget _desktopProjectRow(LocalProject project) {
    final tasks = widget.snapshot.tasks
        .where((task) => task.projectId == project.id)
        .toList();
    final done = tasks.where((task) => task.isCompleted).length;
    final selected = widget.selectedId == project.id;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        key: ValueKey('desktop-project-${project.id}'),
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => widget.onSelection(project.id),
        leading: Icon(Icons.folder_outlined, color: colors.primary),
        title: Text(
          project.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (project.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Text(context.l10n.organizerProjectProgress(done, tasks.length)),
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: done / tasks.length, minHeight: 3),
            ],
          ],
        ),
        trailing: _projectMenu(project),
      ),
    );
  }

  Widget _projectMenu(LocalProject project) {
    final l = context.l10n;
    if (widget.readOnly) return const Icon(Icons.chevron_right, size: 20);
    return PopupMenuButton<String>(
      key: ValueKey('project-menu-${project.id}'),
      tooltip: '${l.scopeLifecycleMenu} · ${project.title}',
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) async {
        switch (action) {
          case 'edit':
            await widget.actions.project(project);
          case 'archive':
            await widget.actions.archiveProject(
              project,
              archived: !project.archived,
            );
          case 'delete':
            await widget.actions.deleteProject(project);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          enabled: !project.archived,
          child: Text(l.organizerEditProject),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Text(project.archived ? l.peopleRestore : l.peopleArchive),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            l.delete,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }

  Widget _detail(LocalProject project, bool back) {
    final l = context.l10n;
    final readOnly = widget.readOnly || project.archived;
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
                titleAccessory: back ? widget.titleAccessory : null,
                subtitle: project.description.isEmpty
                    ? (widget.scopeLabel ?? l.organizerPersonal)
                    : project.description,
              ),
            ),
            if (widget.detailMenuBuilder != null)
              widget.detailMenuBuilder!(project)
            else if (widget.reportScopeId != null)
              SharedContentActionsMenu(
                scopeId: widget.reportScopeId!,
                targetId: project.id,
                actions: [
                  if (!readOnly)
                    ContentMenuAction(
                      label: l.organizerEditProject,
                      icon: Icons.edit_outlined,
                      onSelected: () => widget.actions.project(project),
                    ),
                ],
              )
            else if (!readOnly)
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
          onTaskSelected: readOnly
              ? null
              : (task) => widget.actions.task(task: task),
        ),
        OrganizerSection(
          title: l.organizerTasks,
          action: readOnly
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
                  action: readOnly ? null : l.organizerAddTask,
                  onAction: readOnly
                      ? null
                      : () => widget.actions.task(projectId: project.id),
                )
              : Column(
                  children: [
                    for (final task in tasks)
                      OrganizerTaskRow(
                        task: task,
                        snapshot: widget.snapshot,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (readOnly && widget.reportScopeId != null)
                              SharedContentActionsMenu(
                                scopeId: widget.reportScopeId!,
                                targetId: task.id,
                                reminderType: 'task',
                              ),
                            if (widget.reminderScopeId == null && !readOnly)
                              LocalTaskReminderButton(
                                task: task,
                                workspaceKey: widget.snapshot.workspaceKey,
                              ),
                            if (widget.reminderScopeId != null &&
                                (!readOnly || widget.reportScopeId == null))
                              RemoteReminderButton(
                                scopeId: widget.reminderScopeId!,
                                targetType: 'task',
                                targetId: task.id,
                              ),
                          ],
                        ),
                        onEdit: readOnly
                            ? null
                            : () => widget.actions.task(task: task),
                        onCompleted: readOnly
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
    this.titleAccessory,
    this.reminderScopeId,
    this.reportScopeId,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerCollectionActions actions;
  final bool readOnly;
  final String? scopeLabel;
  final Widget? titleAccessory;
  final String? reminderScopeId;
  final String? reportScopeId;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final active = snapshot.tasks.where(
      (t) => !snapshot.projects.any((p) => p.id == t.projectId && p.archived),
    );
    final pending = active.where((t) => !t.isCompleted).toList();
    final dated = pending.where((t) => t.dueAt != null).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final undated = pending.where((t) => t.dueAt == null).toList();
    final completed = active.where((t) => t.isCompleted).toList();
    Widget row(LocalTask task) => OrganizerTaskRow(
      task: task,
      snapshot: snapshot,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (readOnly && reportScopeId != null)
            SharedContentActionsMenu(
              scopeId: reportScopeId!,
              targetId: task.id,
              reminderType: 'task',
            ),
          if (reminderScopeId == null && !readOnly)
            LocalTaskReminderButton(
              task: task,
              workspaceKey: snapshot.workspaceKey,
            ),
          if (reminderScopeId != null && (!readOnly || reportScopeId == null))
            RemoteReminderButton(
              scopeId: reminderScopeId!,
              targetType: 'task',
              targetId: task.id,
            ),
        ],
      ),
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
          titleAccessory: titleAccessory,
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
