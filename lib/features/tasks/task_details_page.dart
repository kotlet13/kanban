import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/theme_mode_menu_button.dart';

class TaskDetailsPage extends StatelessWidget {
  const TaskDetailsPage({
    required this.projectId,
    this.taskId,
    super.key,
  });

  final int projectId;
  final int? taskId;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final formMaxWidth = width < 720 ? width - 24 : 700.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(taskId == null ? 'New Task' : 'Edit Task'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Projects',
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: formMaxWidth),
          child: TaskDetailsSheet(
            projectId: projectId,
            task: null,
            taskId: taskId,
            isStandalonePage: true,
          ),
        ),
      ),
    );
  }
}

class TaskDetailsSheet extends ConsumerStatefulWidget {
  const TaskDetailsSheet({
    required this.projectId,
    this.task,
    this.taskId,
    this.initialColumnId,
    this.initialSwimlaneId,
    this.isStandalonePage = false,
    super.key,
  });

  final int projectId;
  final KanboardTask? task;
  final int? taskId;
  final int? initialColumnId;
  final int? initialSwimlaneId;
  final bool isStandalonePage;

  @override
  ConsumerState<TaskDetailsSheet> createState() => _TaskDetailsSheetState();
}

class _TaskDetailsSheetState extends ConsumerState<TaskDetailsSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isSaving = false;
  bool _isLoading = false;
  String? _error;

  int? _columnId;
  int? _swimlaneId;
  List<KanboardColumn> _columns = const <KanboardColumn>[];
  List<KanboardSwimlane> _swimlanes = const <KanboardSwimlane>[];

  bool get _isEditing => widget.task != null || widget.taskId != null;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final columns = await api.getColumns(widget.projectId);
      final swimlanes = await api.getAllSwimlanes(widget.projectId);

      KanboardTask? task = widget.task;
      if (task == null && widget.taskId != null) {
        task = await api.getTask(widget.taskId!);
      }

      _titleController.text = task?.title ?? '';
      _descriptionController.text = task?.description ?? '';
      _columnId = task?.columnId ??
          widget.initialColumnId ??
          (columns.isNotEmpty ? columns.first.id : null);
      _swimlaneId =
          task?.swimlaneId ??
              widget.initialSwimlaneId ??
              (swimlanes.isNotEmpty ? swimlanes.first.id : 0);

      setState(() {
        _columns = columns;
        _swimlanes = swimlanes;
      });
    } catch (error) {
      setState(() {
        _error = '$error';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      if (_isEditing) {
        final id = widget.task?.id ?? widget.taskId!;
        await api.updateTask(
          id: id,
          title: title,
          description: _descriptionController.text.trim(),
        );
      } else {
        await api.createTask(
          projectId: widget.projectId,
          title: title,
          description: _descriptionController.text.trim(),
          columnId: _columnId,
          swimlaneId: _swimlaneId,
        );
      }
      if (!mounted) return;
      if (widget.isStandalonePage) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: widget.isStandalonePage ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!widget.isStandalonePage)
              Text(
                _isEditing ? 'Edit task' : 'Create task',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            if (_isLoading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _columnId,
              items: _columns
                  .map(
                    (c) => DropdownMenuItem<int>(
                      value: c.id,
                      child: Text(c.title),
                    ),
                  )
                  .toList(),
              onChanged: _isEditing ? null : (v) => setState(() => _columnId = v),
              decoration: const InputDecoration(labelText: 'Column'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _swimlaneId,
              items: _swimlanes
                  .map(
                    (s) => DropdownMenuItem<int>(
                      value: s.id,
                      child: Text(s.name),
                    ),
                  )
                  .toList(),
              onChanged: _isEditing ? null : (v) => setState(() => _swimlaneId = v),
              decoration: const InputDecoration(labelText: 'Swimlane'),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                TextButton(
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
