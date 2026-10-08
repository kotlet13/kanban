import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/collaboration_models.dart';
import '../../domain/organizer_projections.dart';
import '../organizer_widgets.dart';
import '../inbox/remote_reminder_editor.dart';
import 'task_plan_fields.dart';

class SharedAgendaPage extends StatefulWidget {
  const SharedAgendaPage({
    super.key,
    required this.scope,
    required this.data,
    required this.people,
    required this.onOpen,
    this.onAddEvent,
    this.timeline = false,
    this.selectedProjectId,
    this.onProjectSelected,
  });
  final SharedScope scope;
  final SharedScopeData data;
  final List<OrganizerPersonOption> people;
  final ValueChanged<AgendaItem> onOpen;
  final VoidCallback? onAddEvent;
  final bool timeline;
  final String? selectedProjectId;
  final ValueChanged<String?>? onProjectSelected;
  @override
  State<SharedAgendaPage> createState() => _SharedAgendaPageState();
}

class _SharedAgendaPageState extends State<SharedAgendaPage> {
  DateTime _day = DateTime.now();
  String _personId = '';
  String? _projectId;
  @override
  void initState() {
    super.initState();
    _projectId = widget.selectedProjectId;
  }

  @override
  void didUpdateWidget(covariant SharedAgendaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope.id != widget.scope.id) {
      _personId = '';
      _projectId = widget.selectedProjectId;
      _day = DateTime.now();
    } else if (oldWidget.selectedProjectId != widget.selectedProjectId) {
      _projectId = widget.selectedProjectId;
    }
    if (_projectId != null &&
        !widget.data.projects.any((p) => p.id == _projectId)) {
      _projectId = null;
    }
    if (_personId.isNotEmpty && !widget.people.any((p) => p.id == _personId)) {
      _personId = '';
    }
  }

  String _people(AgendaItem item) {
    final names = [
      for (final id in item.assigneeAccountIds)
        widget.people.where((p) => p.id == id).firstOrNull?.label ??
            context.l10n.planningFormerMember,
    ];
    final task = widget.data.tasks.where((t) => t.id == item.id).firstOrNull;
    if (task?.assigneePersonId != null) {
      names.add(
        widget.data.people
                .where((p) => p.id == task!.assigneePersonId)
                .firstOrNull
                ?.name ??
            context.l10n.planningFormerMember,
      );
    }
    return names.isEmpty ? context.l10n.planningUnassigned : names.join(', ');
  }

  String _when(AgendaItem item) {
    final material = MaterialLocalizations.of(context);
    String at(DateTime value) {
      final local = value.toLocal();
      return '${material.formatMediumDate(local)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    }

    return [
      if (item.startAt != null)
        '${context.l10n.planningStart}: ${at(item.startAt!)}',
      if (item.endAt != null) '${context.l10n.planningEnd}: ${at(item.endAt!)}',
      if (item.dueAt != null) '${context.l10n.planningDue}: ${at(item.dueAt!)}',
      if (item.sortAt == null) context.l10n.planningNoTime,
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final items =
        (widget.timeline
                ? projectTimeline(
                    widget.data,
                    scopeId: widget.scope.id,
                    projectId: _projectId,
                  )
                : dailyAgenda(widget.data, scopeId: widget.scope.id, day: _day))
            .where(
              (item) =>
                  (widget.timeline || !widget.scope.archived) &&
                  (_personId.isEmpty ||
                      item.assigneeAccountIds.contains(_personId)),
            )
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.scope.archived) Text(l.scopeArchivedDescription),
        OrganizerHeading(
          title: widget.timeline ? l.planningTimeline : l.planningSharedToday,
          subtitle: widget.scope.name,
          action: widget.onAddEvent == null
              ? null
              : IconButton(
                  tooltip: l.organizerAddEvent,
                  onPressed: widget.onAddEvent,
                  icon: const Icon(Icons.add),
                ),
        ),
        if (!widget.timeline)
          Row(
            children: [
              IconButton(
                tooltip: l.planningPreviousDay,
                onPressed: () => setState(
                  () => _day = DateTime(_day.year, _day.month, _day.day - 1),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  organizerDate(context, _day),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: l.planningNextDay,
                onPressed: () => setState(
                  () => _day = DateTime(_day.year, _day.month, _day.day + 1),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        if (widget.timeline) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('timeline-project-$_projectId'),
            initialValue: widget.data.projects.any((p) => p.id == _projectId)
                ? _projectId
                : '',
            isExpanded: true,
            decoration: InputDecoration(labelText: l.project),
            items: [
              DropdownMenuItem(value: '', child: Text(l.planningAllProjects)),
              for (final project in widget.data.projects)
                DropdownMenuItem(
                  value: project.id,
                  child: Text(project.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) => setState(() {
              _projectId = id == '' ? null : id;
              widget.onProjectSelected?.call(_projectId);
            }),
          ),
          const SizedBox(height: 12),
        ],
        DropdownButtonFormField<String>(
          key: ValueKey('agenda-person-$_personId'),
          initialValue: widget.people.any((p) => p.id == _personId)
              ? _personId
              : '',
          isExpanded: true,
          decoration: InputDecoration(labelText: l.planningAssignees),
          items: [
            DropdownMenuItem(value: '', child: Text(l.planningAllPeople)),
            for (final person in widget.people)
              DropdownMenuItem(
                value: person.id,
                child: Text(person.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id != null) setState(() => _personId = id);
          },
        ),
        const SizedBox(height: 20),
        if (items.isEmpty)
          OrganizerEmpty(
            icon: Icons.event_note_outlined,
            title: widget.timeline ? l.planningNoTimeline : l.planningNoAgenda,
          ),
        for (final item in items)
          Card(
            child: InkWell(
              onTap: () => widget.onOpen(item),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.type == 'event'
                          ? Icons.event_outlined
                          : item.type == 'project'
                          ? Icons.folder_outlined
                          : item.isCompleted
                          ? Icons.check_circle_outline
                          : Icons.check_circle_outline,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(_people(item)),
                          if (item.projectId != null && item.type != 'project')
                            Text(
                              widget.data.projects
                                      .where((p) => p.id == item.projectId)
                                      .firstOrNull
                                      ?.title ??
                                  l.organizerNoProject,
                            ),
                          const SizedBox(height: 6),
                          Text(
                            _when(item),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (item.isCompleted) Text(l.organizerCompleted),
                        ],
                      ),
                    ),
                    if (!widget.scope.archived &&
                        (item.type == 'task' || item.type == 'event'))
                      RemoteReminderButton(
                        scopeId: widget.scope.id,
                        targetType: item.type,
                        targetId: item.id,
                      ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
