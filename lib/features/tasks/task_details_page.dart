import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../kanboard/jsonrpc_client.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/theme_mode_menu_button.dart';

class TaskDetailsPage extends StatelessWidget {
  const TaskDetailsPage({required this.projectId, this.taskId, super.key});

  final int projectId;
  final int? taskId;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final formMaxWidth = width < 900 ? width - 24 : 900.0;

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
  final _dueDateController = TextEditingController();
  final _scoreController = TextEditingController();
  final _newCommentController = TextEditingController();
  final _newSubtaskController = TextEditingController();
  final _tagInputController = TextEditingController();
  final _internalLinkTaskIdController = TextEditingController();
  final _externalLinkTitleController = TextEditingController();
  final _externalLinkUrlController = TextEditingController();

  bool _isSaving = false;
  bool _isLoading = false;
  bool _isLoadingDetails = false;
  bool _isWorking = false;
  bool _isUpdatingStatus = false;
  String? _error;

  int? _columnId;
  int? _swimlaneId;
  int? _ownerId;
  int _priority = 0;
  DateTime? _selectedDueDate;

  KanboardTask? _loadedTask;
  final List<String> _permissionIssues = <String>[];

  List<KanboardColumn> _columns = const <KanboardColumn>[];
  List<KanboardSwimlane> _swimlanes = const <KanboardSwimlane>[];
  List<KanboardUserReference> _assignableUsers =
      const <KanboardUserReference>[];

  List<KanboardTaskFile> _attachments = const <KanboardTaskFile>[];
  List<KanboardComment> _comments = const <KanboardComment>[];
  List<KanboardSubtask> _subtasks = const <KanboardSubtask>[];
  List<String> _taskTags = const <String>[];
  List<KanboardTag> _projectTags = const <KanboardTag>[];
  List<KanboardTaskLinkType> _linkTypes = const <KanboardTaskLinkType>[];
  List<KanboardTaskLink> _taskLinks = const <KanboardTaskLink>[];
  List<KanboardExternalTaskLink> _externalLinks =
      const <KanboardExternalTaskLink>[];

  Map<String, String> _externalLinkTypes = const <String, String>{};
  Map<String, String> _externalDependencies = const <String, String>{};

  int? _selectedLinkTypeId;
  String? _selectedExternalType;
  String? _selectedExternalDependency;

  bool get _isEditing => widget.task != null || widget.taskId != null;

  int? get _activeTaskId => _loadedTask?.id ?? widget.task?.id ?? widget.taskId;

  bool get _isTaskActive => (_loadedTask ?? widget.task)?.isActive ?? true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<T> _safeOptional<T>(
    Future<T> request,
    T fallback, {
    String? label,
    void Function(Object error)? onError,
  }) async {
    try {
      return await request;
    } catch (error) {
      onError?.call(error);
      debugPrint(
        '[TaskDetails] Optional load failed${label == null ? '' : ' ($label)'}: $error',
      );
      return fallback;
    }
  }

  Future<void> _loadInitial() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _permissionIssues.clear();
    });

    try {
      final initialResults = await Future.wait<dynamic>(<Future<dynamic>>[
        api.getColumns(widget.projectId),
        api.getAllSwimlanes(widget.projectId),
        _safeOptional<List<KanboardUserReference>>(
          api.getAssignableUsers(widget.projectId),
          const <KanboardUserReference>[],
          label: 'getAssignableUsers',
        ),
        _safeOptional<List<KanboardTag>>(
          api.getTagsByProject(widget.projectId),
          const <KanboardTag>[],
          label: 'getTagsByProject',
        ),
        _safeOptional<List<KanboardTaskLinkType>>(
          api.getAllLinks(),
          const <KanboardTaskLinkType>[],
          label: 'getAllLinks',
          onError: (error) {
            if (error is JsonRpcException &&
                (error.code == 403 || error.message.contains('403'))) {
              _permissionIssues.add(
                'No permission for internal task links (`getAllLinks`).',
              );
            }
          },
        ),
        _safeOptional<Map<String, String>>(
          api.getExternalTaskLinkTypes(),
          const <String, String>{},
          label: 'getExternalTaskLinkTypes',
        ),
        _safeOptional<Map<String, String>>(
          api.getExternalTaskLinkProviderDependencies(),
          const <String, String>{},
          label: 'getExternalTaskLinkProviderDependencies',
        ),
      ]);

      final columns = initialResults[0] as List<KanboardColumn>;
      final swimlanes = initialResults[1] as List<KanboardSwimlane>;
      final users = initialResults[2] as List<KanboardUserReference>;
      final projectTags = initialResults[3] as List<KanboardTag>;
      final linkTypes = initialResults[4] as List<KanboardTaskLinkType>;
      final externalTypes = initialResults[5] as Map<String, String>;
      final externalDeps = initialResults[6] as Map<String, String>;

      KanboardTask? task = widget.task;
      if (widget.taskId != null) {
        task = await api.getTask(widget.taskId!);
      } else if (task != null) {
        task = await api.getTask(task.id) ?? task;
      }

      _loadedTask = task;
      _titleController.text = task?.title ?? '';
      _descriptionController.text = task?.description ?? '';
      _dueDateController.text = task?.dateDueForInput ?? '';
      _selectedDueDate = _parseDueDateInput(_dueDateController.text.trim());
      _scoreController.text = task == null ? '' : '${task.score}';

      _columnId =
          task?.columnId ??
          widget.initialColumnId ??
          (columns.isNotEmpty ? columns.first.id : null);
      _swimlaneId =
          task?.swimlaneId ??
          widget.initialSwimlaneId ??
          (swimlanes.isNotEmpty ? swimlanes.first.id : 0);
      _ownerId = task != null && task.ownerId > 0 ? task.ownerId : null;
      if (_ownerId != null && !users.any((u) => u.id == _ownerId)) {
        _ownerId = null;
      }
      _priority = task?.priority ?? 0;

      _selectedLinkTypeId = linkTypes.isNotEmpty ? linkTypes.first.id : null;
      _selectedExternalType = externalTypes.keys.isNotEmpty
          ? externalTypes.keys.first
          : null;
      _selectedExternalDependency = externalDeps.keys.isNotEmpty
          ? externalDeps.keys.first
          : null;

      if (!mounted) return;
      setState(() {
        _columns = columns;
        _swimlanes = swimlanes;
        _assignableUsers = users;
        _projectTags = projectTags;
        _linkTypes = linkTypes;
        _externalLinkTypes = externalTypes;
        _externalDependencies = externalDeps;
      });

      final taskId = _activeTaskId;
      if (taskId != null && taskId > 0) {
        await _loadTaskDetails(taskId);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTaskDetails(int taskId) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;

    setState(() {
      _isLoadingDetails = true;
    });

    try {
      final detailResults = await Future.wait<dynamic>(<Future<dynamic>>[
        _safeOptional<List<KanboardTaskFile>>(
          api.getAllTaskFiles(taskId),
          const <KanboardTaskFile>[],
          label: 'getAllTaskFiles',
        ),
        _safeOptional<List<KanboardComment>>(
          api.getAllComments(taskId),
          const <KanboardComment>[],
          label: 'getAllComments',
        ),
        _safeOptional<List<KanboardSubtask>>(
          api.getAllSubtasks(taskId),
          const <KanboardSubtask>[],
          label: 'getAllSubtasks',
        ),
        _safeOptional<List<String>>(
          api.getTaskTags(taskId),
          const <String>[],
          label: 'getTaskTags',
        ),
        _safeOptional<List<KanboardTaskLink>>(
          api.getAllTaskLinks(taskId),
          const <KanboardTaskLink>[],
          label: 'getAllTaskLinks',
        ),
        _safeOptional<List<KanboardExternalTaskLink>>(
          api.getAllExternalTaskLinks(taskId),
          const <KanboardExternalTaskLink>[],
          label: 'getAllExternalTaskLinks',
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _attachments = detailResults[0] as List<KanboardTaskFile>;
        _comments = detailResults[1] as List<KanboardComment>;
        _subtasks = detailResults[2] as List<KanboardSubtask>;
        _taskTags = detailResults[3] as List<String>;
        _taskLinks = detailResults[4] as List<KanboardTaskLink>;
        _externalLinks = detailResults[5] as List<KanboardExternalTaskLink>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
      }
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

    final score = int.tryParse(_scoreController.text.trim());
    if (_scoreController.text.trim().isNotEmpty && score == null) {
      setState(() => _error = 'Score must be an integer.');
      return;
    }
    final dueDateValue = _selectedDueDate == null
        ? ''
        : _formatDueDateForApi(_selectedDueDate!);

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      if (_isEditing) {
        final id = _activeTaskId!;
        await api.updateTask(
          id: id,
          title: title,
          description: _descriptionController.text.trim(),
          ownerId: _ownerId ?? 0,
          dateDue: dueDateValue,
          clearDateDue: dueDateValue.isEmpty,
          priority: _priority,
          score: score ?? 0,
        );
      } else {
        await api.createTask(
          projectId: widget.projectId,
          title: title,
          description: _descriptionController.text.trim(),
          columnId: _columnId,
          swimlaneId: _swimlaneId,
          ownerId: _ownerId,
          dateDue: dueDateValue,
          priority: _priority,
          score: score,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
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

  Future<void> _setTaskDone({required bool done}) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null || taskId <= 0) return;
    setState(() {
      _isUpdatingStatus = true;
      _error = null;
    });
    try {
      final ok = done
          ? await api.closeTask(taskId)
          : await api.openTask(taskId);
      if (!ok) {
        throw StateError('Server rejected task status update.');
      }
      final refreshed = await api.getTask(taskId);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) {
          _loadedTask = refreshed;
        }
      });
      _showSnack(done ? 'Task marked done.' : 'Task reopened.');
      if (!widget.isStandalonePage) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
      _showSnack('Task status update failed: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingStatus = false;
        });
      }
    }
  }

  Future<void> _addAttachments() async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null || taskId <= 0) return;
    var effectiveProjectId = _loadedTask?.projectId ?? widget.projectId;
    try {
      final latestTask = await api.getTask(taskId);
      if (latestTask != null) {
        effectiveProjectId = latestTask.projectId;
        if (mounted) {
          setState(() {
            _loadedTask = latestTask;
          });
        }
      }
    } catch (_) {
      // Continue with the best-known project id.
    }

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
    } on PlatformException catch (error) {
      final missingEntitlement =
          error.code == 'ENTITLEMENT_NOT_FOUND' ||
          (error.message ?? '').contains('entitlement');
      if (missingEntitlement) {
        _showSnack(
          'macOS file access entitlement missing. Rebuild the app after enabling user-selected file read entitlement.',
          isError: true,
        );
      } else {
        _showSnack('Attachment picker failed: $error', isError: true);
      }
      return;
    } catch (error) {
      _showSnack('Attachment picker failed: $error', isError: true);
      return;
    }
    if (picked == null || picked.files.isEmpty) return;

    setState(() => _isWorking = true);
    try {
      for (final file in picked.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final base64Data = base64Encode(bytes);
        final createdId = await api.createTaskFile(
          projectId: effectiveProjectId,
          taskId: taskId,
          filename: file.name,
          contentBase64: base64Data,
        );
        if (createdId == null || createdId <= 0) {
          throw StateError('Server rejected attachment "${file.name}".');
        }
      }
      await _loadTaskDetails(taskId);
      _showSnack('Attachment upload complete.');
    } catch (error) {
      _showSnack('Attachment upload failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _exportAttachment(KanboardTaskFile file) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    try {
      final encoded = await api.downloadTaskFile(file.id);
      if (encoded == null || encoded.isEmpty) {
        _showSnack('Attachment has no downloadable content.', isError: true);
        return;
      }
      final bytes = base64Decode(encoded);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile.fromData(bytes, name: file.name)],
          text: file.name,
        ),
      );
    } catch (error) {
      _showSnack('Attachment export failed: $error', isError: true);
    }
  }

  Future<void> _deleteAttachment(KanboardTaskFile file) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    try {
      await api.removeTaskFile(file.id);
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Attachment delete failed: $error', isError: true);
    }
  }

  Future<void> _addComment() async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    final comment = _newCommentController.text.trim();
    if (comment.isEmpty) return;
    try {
      await api.createComment(taskId: taskId, comment: comment);
      _newCommentController.clear();
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Comment save failed: $error', isError: true);
    }
  }

  Future<void> _editComment(KanboardComment comment) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    final controller = TextEditingController(text: comment.comment);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Comment'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    try {
      await api.updateComment(commentId: comment.id, comment: text);
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Comment update failed: $error', isError: true);
    }
  }

  Future<void> _deleteComment(KanboardComment comment) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    try {
      await api.removeComment(comment.id);
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Comment delete failed: $error', isError: true);
    }
  }

  Future<void> _addSubtask() async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    final title = _newSubtaskController.text.trim();
    if (title.isEmpty) return;
    try {
      await api.createSubtask(taskId: taskId, title: title);
      _newSubtaskController.clear();
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Subtask create failed: $error', isError: true);
    }
  }

  Future<void> _toggleSubtask(KanboardSubtask subtask, bool done) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    try {
      await api.updateSubtask(id: subtask.id, status: done ? 1 : 0);
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Subtask update failed: $error', isError: true);
    }
  }

  Future<void> _editSubtask(KanboardSubtask subtask) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;

    final titleController = TextEditingController(text: subtask.title);
    final estimateController = TextEditingController(
      text: subtask.timeEstimated > 0 ? '${subtask.timeEstimated}' : '',
    );
    final spentController = TextEditingController(
      text: subtask.timeSpent > 0 ? '${subtask.timeSpent}' : '',
    );
    int? selectedUser = subtask.userId > 0 ? subtask.userId : null;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Edit subtask'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: selectedUser,
                  decoration: const InputDecoration(labelText: 'Assignee'),
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ..._assignableUsers.map(
                      (u) => DropdownMenuItem<int?>(
                        value: u.id,
                        child: Text(u.displayName),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setLocalState(() => selectedUser = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: estimateController,
                  decoration: const InputDecoration(labelText: 'Estimate (h)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: spentController,
                  decoration: const InputDecoration(labelText: 'Spent (h)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    try {
      await api.updateSubtask(
        id: subtask.id,
        title: titleController.text.trim(),
        userId: selectedUser ?? 0,
        timeEstimated: double.tryParse(estimateController.text.trim()),
        timeSpent: double.tryParse(spentController.text.trim()),
      );
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Subtask update failed: $error', isError: true);
    }
  }

  Future<void> _deleteSubtask(KanboardSubtask subtask) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    try {
      await api.removeSubtask(subtask.id);
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Subtask delete failed: $error', isError: true);
    }
  }

  Future<void> _applyTags() async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    final entered = _tagInputController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final merged = <String>{..._taskTags, ...entered}.toList()..sort();
    try {
      await api.setTaskTags(taskId: taskId, tags: merged);
      _tagInputController.clear();
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Tag update failed: $error', isError: true);
    }
  }

  Future<void> _toggleTag(String tagName) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    final nextTags = List<String>.from(_taskTags);
    if (nextTags.contains(tagName)) {
      nextTags.remove(tagName);
    } else {
      nextTags.add(tagName);
    }
    nextTags.sort();
    try {
      await api.setTaskTags(taskId: taskId, tags: nextTags);
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Tag update failed: $error', isError: true);
    }
  }

  Future<void> _addInternalLink() async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null || _selectedLinkTypeId == null) return;
    final oppositeTaskId = int.tryParse(
      _internalLinkTaskIdController.text.trim(),
    );
    if (oppositeTaskId == null || oppositeTaskId <= 0) {
      _showSnack('Enter a valid linked task ID.', isError: true);
      return;
    }
    try {
      await api.createTaskLink(
        taskId: taskId,
        oppositeTaskId: oppositeTaskId,
        linkId: _selectedLinkTypeId!,
      );
      _internalLinkTaskIdController.clear();
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Task link failed: $error', isError: true);
    }
  }

  Future<void> _removeInternalLink(KanboardTaskLink link) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    try {
      await api.removeTaskLink(link.id);
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('Link delete failed: $error', isError: true);
    }
  }

  Future<void> _addExternalLink() async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null ||
        taskId == null ||
        _selectedExternalType == null ||
        _selectedExternalDependency == null) {
      return;
    }
    final title = _externalLinkTitleController.text.trim();
    final url = _externalLinkUrlController.text.trim();
    if (title.isEmpty || url.isEmpty) {
      _showSnack('External link title and URL are required.', isError: true);
      return;
    }
    try {
      await api.createExternalTaskLink(
        taskId: taskId,
        title: title,
        url: url,
        linkType: _selectedExternalType!,
        dependency: _selectedExternalDependency!,
      );
      _externalLinkTitleController.clear();
      _externalLinkUrlController.clear();
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('External link failed: $error', isError: true);
    }
  }

  Future<void> _removeExternalLink(KanboardExternalTaskLink link) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    try {
      await api.removeExternalTaskLink(taskId: taskId, linkId: link.id);
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack('External link delete failed: $error', isError: true);
    }
  }

  Future<void> _openExternalLink(KanboardExternalTaskLink link) async {
    final uri = Uri.tryParse(link.url);
    if (uri == null) {
      _showSnack('Invalid URL.', isError: true);
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link.url));
      _showSnack('Could not open URL. Copied to clipboard.');
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _formatUnix(int unixSeconds) {
    if (unixSeconds <= 0) return '-';
    final date = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
    ).toLocal();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$month-$day $hour:$minute';
  }

  DateTime? _parseDueDateInput(String raw) {
    if (raw.isEmpty) return null;
    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    return parsed?.toLocal();
  }

  String _formatDueDateForApi(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$month-$day $hour:$minute';
  }

  Future<void> _pickDueDateTime() async {
    final initial = _selectedDueDate ?? DateTime.now();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        var draft = initial;
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(draft),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.dateAndTime,
                    use24hFormat: true,
                    initialDateTime: initial,
                    minimumDate: DateTime(2000),
                    maximumDate: DateTime(2100),
                    onDateTimeChanged: (value) {
                      draft = value;
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;

    setState(() {
      _selectedDueDate = picked;
      _dueDateController.text = _formatDueDateForApi(picked);
    });
  }

  void _clearDueDate() {
    setState(() {
      _selectedDueDate = null;
      _dueDateController.clear();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _dueDateController.dispose();
    _scoreController.dispose();
    _newCommentController.dispose();
    _newSubtaskController.dispose();
    _tagInputController.dispose();
    _internalLinkTaskIdController.dispose();
    _externalLinkTitleController.dispose();
    _externalLinkUrlController.dispose();
    super.dispose();
  }

  Widget _section({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isPersistedTask = _activeTaskId != null && _activeTaskId! > 0;
    final isTaskDone = isPersistedTask && !_isTaskActive;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: widget.isStandalonePage
              ? MainAxisSize.max
              : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!widget.isStandalonePage)
              Text(
                _isEditing ? 'Edit task' : 'Create task',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            if (_isLoading) const LinearProgressIndicator(),
            if (_isLoadingDetails)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            if (isPersistedTask)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Chip(
                        avatar: Icon(
                          isTaskDone
                              ? Icons.check_circle_outline
                              : Icons.radio_button_checked,
                          size: 16,
                        ),
                        label: Text(isTaskDone ? 'Done' : 'Open'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _isSaving || _isUpdatingStatus
                            ? null
                            : () => _setTaskDone(done: !isTaskDone),
                        icon: Icon(
                          isTaskDone ? Icons.undo_rounded : Icons.task_alt,
                        ),
                        label: Text(
                          isTaskDone ? 'Reopen task' : 'Mark as done',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _columnId,
                    items: _columns
                        .map(
                          (c) => DropdownMenuItem<int>(
                            value: c.id,
                            child: Text(c.title),
                          ),
                        )
                        .toList(),
                    onChanged: _isEditing
                        ? null
                        : (v) => setState(() => _columnId = v),
                    decoration: const InputDecoration(labelText: 'Column'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _swimlaneId,
                    items: _swimlanes
                        .map(
                          (s) => DropdownMenuItem<int>(
                            value: s.id,
                            child: Text(s.name),
                          ),
                        )
                        .toList(),
                    onChanged: _isEditing
                        ? null
                        : (v) => setState(() => _swimlaneId = v),
                    decoration: const InputDecoration(labelText: 'Swimlane'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _ownerId,
                    decoration: const InputDecoration(labelText: 'Assignee'),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Unassigned'),
                      ),
                      ..._assignableUsers.map(
                        (u) => DropdownMenuItem<int?>(
                          value: u.id,
                          child: Text(u.displayName),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _ownerId = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: const <DropdownMenuItem<int>>[
                      DropdownMenuItem<int>(value: 0, child: Text('0')),
                      DropdownMenuItem<int>(value: 1, child: Text('1')),
                      DropdownMenuItem<int>(value: 2, child: Text('2')),
                      DropdownMenuItem<int>(value: 3, child: Text('3')),
                      DropdownMenuItem<int>(value: 4, child: Text('4')),
                      DropdownMenuItem<int>(value: 5, child: Text('5')),
                    ],
                    onChanged: (v) => setState(() => _priority = v ?? 0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _dueDateController,
                    readOnly: true,
                    onTap: _pickDueDateTime,
                    decoration: InputDecoration(
                      labelText: 'Due date',
                      hintText: 'Pick date/time',
                      suffixIcon: Wrap(
                        spacing: 0,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Pick due date',
                            onPressed: _pickDueDateTime,
                            icon: const Icon(Icons.calendar_today_outlined),
                          ),
                          if (_selectedDueDate != null)
                            IconButton(
                              tooltip: 'Clear due date',
                              onPressed: _clearDueDate,
                              icon: const Icon(Icons.clear),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _scoreController,
                    decoration: const InputDecoration(labelText: 'Score'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
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
            if (!isPersistedTask)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Save this task first to manage attachments, comments, subtasks, tags, and links.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (isPersistedTask) ...<Widget>[
              if (_permissionIssues.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _permissionIssues.join('\n'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              _section(
                title: 'Attachments',
                trailing: FilledButton.tonalIcon(
                  onPressed: _isWorking ? null : _addAttachments,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Add'),
                ),
                child: _attachments.isEmpty
                    ? const Text('No attachments yet.')
                    : Column(
                        children: _attachments
                            .map(
                              (file) => ListTile(
                                dense: true,
                                title: Text(file.name),
                                subtitle: Text(
                                  '${file.sizeLabel} · ${_formatUnix(file.dateCreation)}',
                                ),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: <Widget>[
                                    IconButton(
                                      tooltip: 'Export',
                                      onPressed: () => _exportAttachment(file),
                                      icon: const Icon(Icons.download_rounded),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteAttachment(file),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
              _section(
                title: 'Comments',
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _newCommentController,
                            decoration: const InputDecoration(
                              labelText: 'New comment',
                            ),
                            minLines: 1,
                            maxLines: 4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addComment,
                          child: const Text('Post'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_comments.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No comments yet.'),
                      ),
                    if (_comments.isNotEmpty)
                      Column(
                        children: _comments
                            .map(
                              (comment) => ListTile(
                                dense: true,
                                title: Text(comment.comment),
                                subtitle: Text(
                                  '${comment.username ?? 'User #${comment.userId}'} · ${_formatUnix(comment.dateCreation)}',
                                ),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: <Widget>[
                                    IconButton(
                                      onPressed: () => _editComment(comment),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      onPressed: () => _deleteComment(comment),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
              _section(
                title: 'Subtasks',
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _newSubtaskController,
                            decoration: const InputDecoration(
                              labelText: 'New subtask',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addSubtask,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_subtasks.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No subtasks yet.'),
                      ),
                    if (_subtasks.isNotEmpty)
                      Column(
                        children: _subtasks
                            .map(
                              (subtask) => CheckboxListTile(
                                dense: true,
                                value: subtask.isDone,
                                onChanged: (checked) =>
                                    _toggleSubtask(subtask, checked ?? false),
                                title: Text(subtask.title),
                                subtitle: Text(
                                  'Est ${subtask.timeEstimated}h · Spent ${subtask.timeSpent}h',
                                ),
                                secondary: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _editSubtask(subtask);
                                    } else if (value == 'delete') {
                                      _deleteSubtask(subtask);
                                    }
                                  },
                                  itemBuilder: (context) =>
                                      const <PopupMenuEntry<String>>[
                                        PopupMenuItem<String>(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
              _section(
                title: 'Tags',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_taskTags.isEmpty) const Text('No tags assigned.'),
                    if (_taskTags.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _taskTags
                            .map(
                              (tag) => InputChip(
                                label: Text(tag),
                                onDeleted: () => _toggleTag(tag),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _tagInputController,
                            decoration: const InputDecoration(
                              labelText: 'Add tags (comma separated)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _applyTags,
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                    if (_projectTags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _projectTags
                            .map(
                              (tag) => FilterChip(
                                label: Text(tag.name),
                                selected: _taskTags.contains(tag.name),
                                onSelected: (_) => _toggleTag(tag.name),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              _section(
                title: 'Task Links',
                child: Column(
                  children: <Widget>[
                    if (_linkTypes.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Internal link types unavailable for this user/project.',
                          ),
                        ),
                      ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _internalLinkTaskIdController,
                            decoration: const InputDecoration(
                              labelText: 'Linked task ID',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedLinkTypeId,
                            items: _linkTypes
                                .map(
                                  (type) => DropdownMenuItem<int>(
                                    value: type.id,
                                    child: Text(type.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _selectedLinkTypeId = value),
                            decoration: const InputDecoration(
                              labelText: 'Relation',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _linkTypes.isEmpty
                              ? null
                              : _addInternalLink,
                          child: const Text('Link'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_taskLinks.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No task links.'),
                      ),
                    if (_taskLinks.isNotEmpty)
                      Column(
                        children: _taskLinks
                            .map(
                              (link) => ListTile(
                                dense: true,
                                title: Text(
                                  '${link.label ?? 'linked to'} #${link.oppositeTaskId}',
                                ),
                                subtitle: Text(
                                  link.oppositeTaskTitle ??
                                      'Task #${link.oppositeTaskId}',
                                ),
                                trailing: IconButton(
                                  onPressed: () => _removeInternalLink(link),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
              _section(
                title: 'External Links',
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _externalLinkTitleController,
                            decoration: const InputDecoration(
                              labelText: 'Link title',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _externalLinkUrlController,
                            decoration: const InputDecoration(labelText: 'URL'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedExternalType,
                            items: _externalLinkTypes.entries
                                .map(
                                  (entry) => DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _selectedExternalType = value),
                            decoration: const InputDecoration(
                              labelText: 'Type',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedExternalDependency,
                            items: _externalDependencies.entries
                                .map(
                                  (entry) => DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(
                              () => _selectedExternalDependency = value,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Dependency',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addExternalLink,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_externalLinks.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No external links.'),
                      ),
                    if (_externalLinks.isNotEmpty)
                      Column(
                        children: _externalLinks
                            .map(
                              (link) => ListTile(
                                dense: true,
                                title: Text(link.title),
                                subtitle: Text(link.url),
                                onTap: () => _openExternalLink(link),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: <Widget>[
                                    IconButton(
                                      onPressed: () => _openExternalLink(link),
                                      icon: const Icon(Icons.open_in_new),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          _removeExternalLink(link),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
