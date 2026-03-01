import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../kanboard/kanboard_api.dart';
import '../../ai/ai_models.dart';
import '../shared/attachment_share.dart';
import '../../l10n/l10n.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/theme_mode_menu_button.dart';

class TaskDetailsPage extends StatelessWidget {
  const TaskDetailsPage({required this.projectId, this.taskId, super.key});

  final int projectId;
  final int? taskId;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isApple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final width = MediaQuery.sizeOf(context).width;
    final formMaxWidth = width < 900 ? width - 24 : 900.0;
    final pageBody = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: formMaxWidth),
        child: TaskDetailsSheet(
          projectId: projectId,
          task: null,
          taskId: taskId,
          isStandalonePage: true,
        ),
      ),
    );

    if (isApple) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(
            taskId == null ? context.l10n.newTask2 : context.l10n.editTask,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(30, 30),
                onPressed: () => context.go('/projects'),
                child: const Icon(CupertinoIcons.folder, size: 20),
              ),
              const SizedBox(width: 4),
              const ThemeModeMenuButton(),
            ],
          ),
        ),
        child: pageBody,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          taskId == null ? context.l10n.newTask2 : context.l10n.editTask,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.projects,
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      body: pageBody,
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
    this.initialTitle,
    this.createAsGroceryList = false,
    this.isStandalonePage = false,
    super.key,
  });

  final int projectId;
  final KanboardTask? task;
  final int? taskId;
  final int? initialColumnId;
  final int? initialSwimlaneId;
  final String? initialTitle;
  final bool createAsGroceryList;
  final bool isStandalonePage;

  @override
  ConsumerState<TaskDetailsSheet> createState() => _TaskDetailsSheetState();
}

class _DraftGroceryItem {
  const _DraftGroceryItem({required this.title, this.isDone = false});

  final String title;
  final bool isDone;
}

class _TaskDetailsSheetState extends ConsumerState<TaskDetailsSheet> {
  static const String _groceryMarker = '[grocery-list]';

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _scoreController = TextEditingController();
  final _timeEstimatedController = TextEditingController();
  final _timeSpentController = TextEditingController();
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
  bool _isAiWorking = false;
  bool _isUpdatingStatus = false;
  bool _advancedExpanded = false;
  bool _isPreparingAdvanced = false;
  String? _titleInlineError;
  String? _error;
  String? _lastSavedSignature;

  int? _columnId;
  int? _swimlaneId;
  int? _ownerId;
  int _priority = 0;
  DateTime? _selectedDueDate;

  KanboardTask? _loadedTask;
  bool _isGroceryList = false;

  List<KanboardColumn> _columns = const <KanboardColumn>[];
  List<KanboardSwimlane> _swimlanes = const <KanboardSwimlane>[];
  List<KanboardUserReference> _assignableUsers =
      const <KanboardUserReference>[];

  List<KanboardTaskFile> _attachments = const <KanboardTaskFile>[];
  List<KanboardComment> _comments = const <KanboardComment>[];
  List<KanboardSubtask> _subtasks = const <KanboardSubtask>[];
  List<_DraftGroceryItem> _draftGroceryItems = const <_DraftGroceryItem>[];
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
    _isGroceryList = widget.createAsGroceryList;
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
      _titleInlineError = null;
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
      _titleController.text = task?.title ?? widget.initialTitle ?? '';
      _descriptionController.text = _stripGroceryMarker(task?.description);
      _dueDateController.text = task?.dateDueForInput ?? '';
      _selectedDueDate = _parseDueDateInput(_dueDateController.text.trim());
      _scoreController.text = task == null
          ? ''
          : _formatCentsToAmount(task.score);
      _timeEstimatedController.text = task == null
          ? ''
          : _formatHoursForInput(task.timeEstimated);
      _timeSpentController.text = task == null
          ? ''
          : _formatHoursForInput(task.timeSpent);

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
      _isGroceryList =
          widget.createAsGroceryList ||
          _hasGroceryMarker(task?.description) ||
          ((task?.title ?? '').trim().toLowerCase() ==
              context.l10n.groceryList.trim().toLowerCase());
      _lastSavedSignature = _currentTaskSignature();

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
      if (taskId != null &&
          taskId > 0 &&
          (_advancedExpanded || _isGroceryList)) {
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
      final rawSubtasks = detailResults[2] as List<KanboardSubtask>;
      setState(() {
        _attachments = detailResults[0] as List<KanboardTaskFile>;
        _comments = detailResults[1] as List<KanboardComment>;
        _subtasks = rawSubtasks
            .where(
              (subtask) =>
                  subtask.title != KanboardApi.taskHoursTrackerSubtaskTitle,
            )
            .toList();
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

  Future<bool> _save({bool closeOnSuccess = true}) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return false;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.l10n.titleIsRequired);
      return false;
    }

    final score = _parseAmountToCents(_scoreController.text.trim());
    if (_scoreController.text.trim().isNotEmpty && score == null) {
      setState(() => _error = context.l10n.scoreMustBeAnInteger);
      return false;
    }
    final timeEstimated = _parseHoursToDecimal(_timeEstimatedController.text);
    if (_timeEstimatedController.text.trim().isNotEmpty &&
        timeEstimated == null) {
      setState(() => _error = 'Estimate (h) must be a positive number.');
      return false;
    }
    final timeSpent = _parseHoursToDecimal(_timeSpentController.text);
    if (_timeSpentController.text.trim().isNotEmpty && timeSpent == null) {
      setState(() => _error = 'Spent (h) must be a positive number.');
      return false;
    }
    final dueDateValue = _selectedDueDate == null
        ? ''
        : _formatDueDateForApi(_selectedDueDate!);
    final descriptionValue = _descriptionForSave();
    final hasPersistedId = _activeTaskId != null && _activeTaskId! > 0;
    final signatureBeforeSave = _currentTaskSignature();
    if (closeOnSuccess &&
        hasPersistedId &&
        _lastSavedSignature != null &&
        _lastSavedSignature == signatureBeforeSave) {
      if (!mounted) return false;
      Navigator.of(context).pop(false);
      return true;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      if (_isEditing) {
        final id = _activeTaskId!;
        final originalTask = _loadedTask;
        final nextColumnId = _columnId;
        final nextSwimlaneId = _swimlaneId;
        final originalOwnerId = originalTask != null && originalTask.ownerId > 0
            ? originalTask.ownerId
            : null;
        final originalDueDateValue = originalTask?.dateDueForInput ?? '';
        final nextScore = score ?? 0;
        final nextTimeEstimated = timeEstimated ?? 0;
        final nextTimeSpent = timeSpent ?? 0;

        final titleChanged =
            originalTask == null || originalTask.title != title;
        final descriptionChanged =
            originalTask == null ||
            (originalTask.description ?? '') != descriptionValue;
        final ownerChanged =
            originalTask == null || originalOwnerId != _ownerId;
        final dueChanged =
            originalTask == null || originalDueDateValue != dueDateValue;
        final priorityChanged =
            originalTask == null || originalTask.priority != _priority;
        final scoreChanged =
            originalTask == null || originalTask.score != nextScore;
        final timeEstimatedChanged =
            originalTask == null ||
            originalTask.timeEstimated != nextTimeEstimated;
        final timeSpentChanged =
            originalTask == null || originalTask.timeSpent != nextTimeSpent;

        final hasNonLocationChanges =
            titleChanged ||
            descriptionChanged ||
            ownerChanged ||
            dueChanged ||
            priorityChanged ||
            scoreChanged ||
            timeEstimatedChanged ||
            timeSpentChanged;

        if (hasNonLocationChanges) {
          final updated = await api.updateTask(
            id: id,
            title: titleChanged ? title : null,
            description: descriptionChanged ? descriptionValue : null,
            ownerId: ownerChanged ? (_ownerId ?? 0) : null,
            dateDue: dueChanged && dueDateValue.isNotEmpty
                ? dueDateValue
                : null,
            clearDateDue: dueChanged && dueDateValue.isEmpty,
            priority: priorityChanged ? _priority : null,
            score: scoreChanged ? nextScore : null,
            timeEstimated: timeEstimatedChanged ? nextTimeEstimated : null,
            timeSpent: timeSpentChanged ? nextTimeSpent : null,
          );
          if (!updated) {
            throw StateError('Task was not updated on server.');
          }
        }
        if (originalTask != null &&
            nextColumnId != null &&
            nextSwimlaneId != null &&
            (originalTask.columnId != nextColumnId ||
                originalTask.swimlaneId != nextSwimlaneId)) {
          final effectiveProjectId = originalTask.projectId > 0
              ? originalTask.projectId
              : widget.projectId;
          final targetPosition = await _resolveTargetTaskPosition(
            api: api,
            projectId: effectiveProjectId,
            taskId: id,
            columnId: nextColumnId,
            swimlaneId: nextSwimlaneId,
          );
          final moved = await api.moveTaskPosition(
            projectId: effectiveProjectId,
            taskId: id,
            columnId: nextColumnId,
            position: targetPosition,
            swimlaneId: nextSwimlaneId,
          );
          if (!moved) {
            throw StateError('Task move was rejected by server.');
          }
        }
        _loadedTask = await api.getTask(id) ?? _loadedTask;
        if (!closeOnSuccess && _advancedExpanded) {
          await _loadTaskDetails(id);
        }
      } else {
        final createdTaskId = await api.createTask(
          projectId: widget.projectId,
          title: title,
          description: descriptionValue,
          columnId: _columnId,
          swimlaneId: _swimlaneId,
          ownerId: _ownerId,
          dateDue: dueDateValue,
          priority: _priority,
          score: score,
          timeEstimated: timeEstimated,
          timeSpent: timeSpent,
        );
        if (createdTaskId == null || createdTaskId <= 0) {
          throw StateError(context.l10n.taskWasNotCreated);
        }
        if (widget.createAsGroceryList && createdTaskId > 0) {
          final tags = <String>{..._taskTags, 'grocery-list'}.toList()..sort();
          try {
            await api.setTaskTags(taskId: createdTaskId, tags: tags);
          } catch (_) {
            // Ignore tag-sync failures on older Kanboard servers.
          }
          if (_draftGroceryItems.isNotEmpty) {
            for (final item in _draftGroceryItems) {
              final subtaskId = await api.createSubtask(
                taskId: createdTaskId,
                title: item.title,
              );
              if (item.isDone && subtaskId != null && subtaskId > 0) {
                await api.updateSubtask(
                  id: subtaskId,
                  taskId: createdTaskId,
                  status: 1,
                );
              }
            }
          }
        }
        if (!closeOnSuccess) {
          _loadedTask = await api.getTask(createdTaskId);
          if (_advancedExpanded) {
            await _loadTaskDetails(createdTaskId);
          }
        }
      }
      if (!mounted) return false;
      _lastSavedSignature = _currentTaskSignature();
      if (closeOnSuccess) {
        Navigator.of(context).pop(true);
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _error = '$error';
      });
      return false;
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
        throw StateError(context.l10n.serverRejectedTaskStatusUpdate);
      }
      final refreshed = await api.getTask(taskId);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) {
          _loadedTask = refreshed;
        }
      });
      _showSnack(
        done ? context.l10n.taskMarkedDone : context.l10n.taskReopened,
      );
      if (!widget.isStandalonePage) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
      _showSnack(context.l10n.taskStatusUpdateFailed(error), isError: true);
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
          context
              .l10n
              .macosFileAccessEntitlementMissingRebuildTheAppAfterEnablingUserSelectedFileReadEntitlement,
          isError: true,
        );
      } else {
        _showSnack(context.l10n.attachmentPickerFailed(error), isError: true);
      }
      return;
    } catch (error) {
      _showSnack(context.l10n.attachmentPickerFailed(error), isError: true);
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
          throw StateError(
            context.l10n.serverRejectedAttachmentName(file.name),
          );
        }
      }
      await _loadTaskDetails(taskId);
      _showSnack(context.l10n.attachmentUploadComplete);
    } catch (error) {
      _showSnack(context.l10n.attachmentUploadFailed(error), isError: true);
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
        _showSnack(
          context.l10n.attachmentHasNoDownloadableContent,
          isError: true,
        );
        return;
      }
      final bytes = base64Decode(encoded);
      await openAttachmentBytes(bytes: bytes, filename: file.name);
    } catch (error) {
      _showSnack(context.l10n.attachmentExportFailed(error), isError: true);
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
      _showSnack(context.l10n.attachmentDeleteFailed(error), isError: true);
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
      _showSnack(context.l10n.commentSaveFailed(error), isError: true);
    }
  }

  Future<void> _editComment(KanboardComment comment) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    final controller = TextEditingController(text: comment.comment);
    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(context.l10n.editComment),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(labelText: context.l10n.comment),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.save),
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
      _showSnack(context.l10n.commentUpdateFailed(error), isError: true);
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
      _showSnack(context.l10n.commentDeleteFailed(error), isError: true);
    }
  }

  Future<void> _addSubtask() async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    final title = _newSubtaskController.text.trim();
    if (title.isEmpty) return;
    if (_isGroceryList && taskId == null) {
      setState(() {
        _draftGroceryItems = <_DraftGroceryItem>[
          ..._draftGroceryItems,
          _DraftGroceryItem(title: title),
        ];
        _newSubtaskController.clear();
      });
      return;
    }
    if (api == null || taskId == null) return;
    try {
      await api.createSubtask(taskId: taskId, title: title);
      _newSubtaskController.clear();
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack(context.l10n.subtaskCreateFailed(error), isError: true);
    }
  }

  void _toggleDraftGroceryItem(int index, bool done) {
    final next = List<_DraftGroceryItem>.from(_draftGroceryItems);
    if (index < 0 || index >= next.length) return;
    final current = next[index];
    next[index] = _DraftGroceryItem(title: current.title, isDone: done);
    setState(() {
      _draftGroceryItems = next;
    });
  }

  void _deleteDraftGroceryItem(int index) {
    if (index < 0 || index >= _draftGroceryItems.length) return;
    final next = List<_DraftGroceryItem>.from(_draftGroceryItems)
      ..removeAt(index);
    setState(() {
      _draftGroceryItems = next;
    });
  }

  Future<bool> _confirmDeleteGroceryItem(String itemTitle) async {
    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: Text(context.l10n.delete),
        content: Text(context.l10n.deletePermanently(itemTitle)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  Future<void> _toggleSubtask(KanboardSubtask subtask, bool done) async {
    final api = ref.read(kanboardApiProvider);
    final taskId = _activeTaskId;
    if (api == null || taskId == null) return;
    try {
      await api.updateSubtask(
        id: subtask.id,
        taskId: taskId,
        status: done ? 1 : 0,
      );
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack(context.l10n.subtaskUpdateFailed(error), isError: true);
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

    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog.adaptive(
          title: Text(context.l10n.editSubtask),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(labelText: context.l10n.title),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: selectedUser,
                  decoration: InputDecoration(labelText: context.l10n.assignee),
                  items: <DropdownMenuItem<int?>>[
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(context.l10n.unassigned),
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
                  decoration: InputDecoration(
                    labelText: context.l10n.estimateH,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: spentController,
                  decoration: InputDecoration(labelText: context.l10n.spentH),
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
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    try {
      await api.updateSubtask(
        id: subtask.id,
        taskId: taskId,
        title: titleController.text.trim(),
        userId: selectedUser ?? 0,
        timeEstimated: double.tryParse(estimateController.text.trim()),
        timeSpent: double.tryParse(spentController.text.trim()),
      );
      await _loadTaskDetails(taskId);
    } catch (error) {
      _showSnack(context.l10n.subtaskUpdateFailed(error), isError: true);
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
      _showSnack(context.l10n.subtaskDeleteFailed(error), isError: true);
    }
  }

  Future<void> _showSubtaskActionSheet(KanboardSubtask subtask) async {
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(subtask.title),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop('edit'),
            child: Text(context.l10n.edit),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(popupContext).pop('delete'),
            child: Text(context.l10n.delete),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text(context.l10n.cancel),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'edit') {
      _editSubtask(subtask);
    } else if (selected == 'delete') {
      _deleteSubtask(subtask);
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
      _showSnack(context.l10n.tagUpdateFailed(error), isError: true);
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
      _showSnack(context.l10n.tagUpdateFailed(error), isError: true);
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
      _showSnack(context.l10n.enterAValidLinkedTaskID, isError: true);
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
      _showSnack(context.l10n.taskLinkFailed(error), isError: true);
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
      _showSnack(context.l10n.linkDeleteFailed(error), isError: true);
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
      _showSnack(
        context.l10n.externalLinkTitleAndURLAreRequired,
        isError: true,
      );
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
      _showSnack(context.l10n.externalLinkFailed(error), isError: true);
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
      _showSnack(context.l10n.externalLinkDeleteFailed(error), isError: true);
    }
  }

  Future<void> _openExternalLink(KanboardExternalTaskLink link) async {
    final uri = Uri.tryParse(link.url);
    if (uri == null) {
      _showSnack(context.l10n.invalidURL, isError: true);
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link.url));
      _showSnack(context.l10n.couldNotOpenURLCopiedToClipboard);
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

  int? _parseAmountToCents(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    if (value.isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 0) return null;
    return (parsed * 100).round();
  }

  String _formatCentsToAmount(int cents) {
    final whole = cents ~/ 100;
    final fraction = (cents % 100).toString().padLeft(2, '0');
    return '$whole.$fraction';
  }

  double? _parseHoursToDecimal(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    if (value.isEmpty) return 0;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  String _formatHoursForInput(double hours) {
    if (hours <= 0) return '';
    if (hours == hours.roundToDouble()) return hours.toStringAsFixed(0);
    return hours.toString();
  }

  bool _hasGroceryMarker(String? description) {
    if (description == null) return false;
    return description.contains(_groceryMarker);
  }

  String _stripGroceryMarker(String? description) {
    if (description == null || description.trim().isEmpty) return '';
    return description
        .replaceAll(_groceryMarker, '')
        .replaceAll(RegExp(r'^\s+|\s+$'), '');
  }

  String _descriptionForSave() {
    final text = _descriptionController.text.trim();
    if (!_isGroceryList) return text;
    if (_hasGroceryMarker(text)) return text;
    return text.isEmpty ? _groceryMarker : '$_groceryMarker\n$text';
  }

  String _currentTaskSignature() {
    final taskId = _activeTaskId ?? 0;
    return [
      taskId.toString(),
      _titleController.text.trim(),
      _descriptionController.text.trim(),
      (_columnId ?? 0).toString(),
      (_swimlaneId ?? 0).toString(),
      (_ownerId ?? 0).toString(),
      _priority.toString(),
      _dueDateController.text.trim(),
      _scoreController.text.trim(),
      _timeEstimatedController.text.trim(),
      _timeSpentController.text.trim(),
      _isGroceryList ? '1' : '0',
    ].join('|');
  }

  Future<int> _resolveTargetTaskPosition({
    required KanboardApi api,
    required int projectId,
    required int taskId,
    required int columnId,
    required int swimlaneId,
  }) async {
    try {
      final board = await api.getBoard(projectId);
      for (final swimlane in board.swimlanes) {
        if (swimlane.id != swimlaneId) continue;
        for (final column in swimlane.columns) {
          if (column.id != columnId) continue;
          return column.tasks.where((task) => task.id != taskId).length + 1;
        }
      }
    } catch (_) {
      // Fall back to first position if board snapshot cannot be loaded.
    }
    return 1;
  }

  String? _requiredMessageBeforeExpand() {
    if (_titleController.text.trim().isEmpty) {
      return context.l10n.enterATitleBeforeOpeningAdditionalDetails;
    }
    return null;
  }

  Future<void> _toggleAdvancedSection() async {
    if (_advancedExpanded) {
      setState(() {
        _advancedExpanded = false;
      });
      return;
    }

    final validationMessage = _requiredMessageBeforeExpand();
    if (validationMessage != null) {
      setState(() {
        _titleInlineError = validationMessage;
      });
      return;
    }

    setState(() {
      _isPreparingAdvanced = true;
      _error = null;
      _titleInlineError = null;
    });
    try {
      var taskId = _activeTaskId;
      if (taskId == null || taskId <= 0) {
        final saved = await _save(closeOnSuccess: false);
        if (!saved || !mounted) return;
        taskId = _activeTaskId;
      }
      if (taskId == null || taskId <= 0) return;

      await _loadTaskDetails(taskId);
      if (!mounted) return;
      setState(() {
        _advancedExpanded = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingAdvanced = false;
        });
      }
    }
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
                        child: Text(context.l10n.cancel),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(draft),
                        child: Text(context.l10n.done),
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

  Future<bool> _ensureAiAllowed() async {
    final settings = await ref.read(aiSettingsStoreProvider).read();
    if (!settings.enabled || !settings.hasApiKey) {
      _showSnack(context.l10n.configureAiInSettings, isError: true);
      return false;
    }
    final api = ref.read(kanboardApiProvider);
    final creds = ref.read(sessionCredentialsProvider);
    if (api == null || creds == null) return false;
    final policy = await api.getProjectAiPolicy(widget.projectId);
    if (!policy.enabled) {
      _showSnack(context.l10n.aiNotEnabledForThisProject, isError: true);
      return false;
    }
    if (policy.keyMode != AiKeyMode.ownerKey) return true;
    final owner = (policy.ownerUsername ?? '').trim();
    if (owner.isEmpty ||
        owner.toLowerCase() == creds.username.trim().toLowerCase()) {
      return true;
    }
    final consentStore = ref.read(aiConsentStoreProvider);
    final accepted = await consentStore.hasAcceptedProjectCostWarning(
      projectId: widget.projectId,
      username: creds.username,
    );
    if (accepted) return true;
    if (!mounted) return false;
    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(context.l10n.aiCostNoticeTitle),
        content: Text(context.l10n.aiCostNoticeBody(owner)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.iUnderstand),
          ),
        ],
      ),
    );
    if (confirm != true) return false;
    await consentStore.setAcceptedProjectCostWarning(
      projectId: widget.projectId,
      username: creds.username,
      accepted: true,
    );
    return true;
  }

  Future<void> _assistTitleWithAi() async {
    if (_isAiWorking) return;
    final allowed = await _ensureAiAllowed();
    if (!allowed || !mounted) return;
    setState(() => _isAiWorking = true);
    try {
      final ai = ref.read(aiFacadeProvider);
      final suggestion = await ai.assistTaskTitle(
        AiTaskAssistRequest(
          projectName: 'Project ${widget.projectId}',
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
        ),
      );
      if (!mounted) return;
      final apply = await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(context.l10n.aiSuggestedTitle),
          content: Text(suggestion),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.apply),
            ),
          ],
        ),
      );
      if (apply == true && mounted) {
        setState(() {
          _titleController.text = suggestion.trim();
        });
      }
    } catch (error) {
      _showSnack(context.l10n.aiRequestFailed(error), isError: true);
    } finally {
      if (mounted) setState(() => _isAiWorking = false);
    }
  }

  Future<void> _assistDescriptionWithAi() async {
    if (_isAiWorking) return;
    final allowed = await _ensureAiAllowed();
    if (!allowed || !mounted) return;
    setState(() => _isAiWorking = true);
    try {
      final ai = ref.read(aiFacadeProvider);
      final suggestion = await ai.assistTaskDescription(
        AiTaskAssistRequest(
          projectName: 'Project ${widget.projectId}',
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
        ),
      );
      if (!mounted) return;
      final apply = await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(context.l10n.aiSuggestedDescription),
          content: SingleChildScrollView(child: Text(suggestion)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.apply),
            ),
          ],
        ),
      );
      if (apply == true && mounted) {
        setState(() {
          _descriptionController.text = suggestion.trim();
        });
      }
    } catch (error) {
      _showSnack(context.l10n.aiRequestFailed(error), isError: true);
    } finally {
      if (mounted) setState(() => _isAiWorking = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _dueDateController.dispose();
    _scoreController.dispose();
    _timeEstimatedController.dispose();
    _timeSpentController.dispose();
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
    final isGroceryEditor = _isGroceryList;

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
                isGroceryEditor
                    ? (_isEditing
                          ? context.l10n.editGroceryList
                          : context.l10n.createGroceryList)
                    : (_isEditing
                          ? context.l10n.editTask2
                          : context.l10n.createTask),
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
                        label: Text(
                          isTaskDone ? context.l10n.done : context.l10n.open,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _isSaving || _isUpdatingStatus
                            ? null
                            : () => _setTaskDone(done: !isTaskDone),
                        icon: Icon(
                          isTaskDone ? Icons.undo_rounded : Icons.task_alt,
                        ),
                        label: Text(
                          isTaskDone
                              ? context.l10n.reopenTask
                              : context.l10n.markAsDone,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    onChanged: (_) {
                      if (_titleInlineError != null) {
                        setState(() {
                          _titleInlineError = null;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: isGroceryEditor
                          ? context.l10n.groceryListTitle
                          : context.l10n.title,
                      errorText: _titleInlineError,
                    ),
                  ),
                ),
                if (!isGroceryEditor) ...<Widget>[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: context.l10n.aiImproveTitle,
                    onPressed: _isAiWorking ? null : _assistTitleWithAi,
                    icon: const Icon(Icons.auto_fix_high_outlined),
                  ),
                ],
              ],
            ),
            if (!isGroceryEditor) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: context.l10n.description,
                      ),
                      minLines: 3,
                      maxLines: 6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: context.l10n.aiImproveDescription,
                    onPressed: _isAiWorking ? null : _assistDescriptionWithAi,
                    icon: const Icon(Icons.auto_awesome_outlined),
                  ),
                ],
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
                      onChanged: _isSaving
                          ? null
                          : (v) => setState(() => _columnId = v),
                      decoration: InputDecoration(
                        labelText: context.l10n.column,
                      ),
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
                      onChanged: _isSaving
                          ? null
                          : (v) => setState(() => _swimlaneId = v),
                      decoration: InputDecoration(
                        labelText: context.l10n.swimlane,
                      ),
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
                      decoration: InputDecoration(
                        labelText: context.l10n.assignee,
                      ),
                      items: <DropdownMenuItem<int?>>[
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(context.l10n.unassigned),
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
                      decoration: InputDecoration(
                        labelText: context.l10n.priority,
                      ),
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
                        labelText: context.l10n.dueDate,
                        hintText: context.l10n.pickDateTime,
                        suffixIcon: Wrap(
                          spacing: 0,
                          children: <Widget>[
                            IconButton(
                              tooltip: context.l10n.pickDueDate,
                              onPressed: _pickDueDateTime,
                              icon: const Icon(Icons.calendar_today_outlined),
                            ),
                            if (_selectedDueDate != null)
                              IconButton(
                                tooltip: context.l10n.clearDueDate,
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
                      decoration: InputDecoration(
                        labelText: context.l10n.expense,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _timeEstimatedController,
                      decoration: InputDecoration(
                        labelText: context.l10n.estimateH,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _timeSpentController,
                      decoration: InputDecoration(
                        labelText: context.l10n.spentH,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: _isSaving ? null : () => _save(),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10n.save),
                ),
              ],
            ),
            if (!isGroceryEditor)
              Card(
                margin: const EdgeInsets.only(top: 12),
                child: Column(
                  children: <Widget>[
                    ListTile(
                      title: Text(context.l10n.additionalDetails),
                      subtitle: Text(
                        _advancedExpanded
                            ? context.l10n.additionalDetails
                            : context.l10n.tapToExpandAdvancedTaskDetails,
                      ),
                      trailing: _isPreparingAdvanced
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _advancedExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                      onTap: _isSaving || _isPreparingAdvanced
                          ? null
                          : _toggleAdvancedSection,
                    ),
                    if (!_advancedExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            isPersistedTask
                                ? context.l10n.advancedSectionsAreHidden
                                : context
                                      .l10n
                                      .forNewTasksTheAppSavesFirstThenOpensAdvancedSections,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (!isPersistedTask && isGroceryEditor)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  context
                      .l10n
                      .forNewTasksTheAppSavesFirstThenOpensAdvancedSections,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if ((isPersistedTask && _advancedExpanded) ||
                isGroceryEditor) ...<Widget>[
              if (!isGroceryEditor)
                _section(
                  title: context.l10n.attachments2,
                  trailing: FilledButton.tonalIcon(
                    onPressed: _isWorking ? null : _addAttachments,
                    icon: const Icon(Icons.attach_file),
                    label: Text(context.l10n.add),
                  ),
                  child: _attachments.isEmpty
                      ? Text(context.l10n.noAttachmentsYet)
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
                                        tooltip: context.l10n.export,
                                        onPressed: () =>
                                            _exportAttachment(file),
                                        icon: const Icon(
                                          Icons.download_rounded,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: context.l10n.delete,
                                        onPressed: () =>
                                            _deleteAttachment(file),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              if (!isGroceryEditor)
                _section(
                  title: context.l10n.comments,
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _newCommentController,
                              decoration: InputDecoration(
                                labelText: context.l10n.newComment,
                              ),
                              minLines: 1,
                              maxLines: 4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _addComment,
                            child: Text(context.l10n.post),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_comments.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(context.l10n.noCommentsYet),
                        ),
                      if (_comments.isNotEmpty)
                        Column(
                          children: _comments
                              .map(
                                (comment) => ListTile(
                                  dense: true,
                                  title: Text(comment.comment),
                                  subtitle: Text(
                                    '${comment.username ?? context.l10n.userNumber(comment.userId)} · ${_formatUnix(comment.dateCreation)}',
                                  ),
                                  trailing: Wrap(
                                    spacing: 6,
                                    children: <Widget>[
                                      IconButton(
                                        onPressed: () => _editComment(comment),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            _deleteComment(comment),
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
                title: isGroceryEditor
                    ? context.l10n.groceryList
                    : context.l10n.subtasks,
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _newSubtaskController,
                            decoration: InputDecoration(
                              labelText: isGroceryEditor
                                  ? context.l10n.newGroceryItem
                                  : context.l10n.newSubtask,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addSubtask,
                          child: Text(context.l10n.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if ((isPersistedTask && _subtasks.isEmpty) ||
                        (!isPersistedTask && _draftGroceryItems.isEmpty))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isGroceryEditor
                              ? context.l10n.noGroceryItemsYet
                              : context.l10n.noSubtasksYet,
                        ),
                      ),
                    if (isPersistedTask && _subtasks.isNotEmpty)
                      isGroceryEditor
                          ? Container(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Column(
                                children: _subtasks.asMap().entries.map((
                                  entry,
                                ) {
                                  final index = entry.key;
                                  final subtask = entry.value;
                                  return Column(
                                    children: <Widget>[
                                      ListTile(
                                        dense: true,
                                        leading: Checkbox(
                                          value: subtask.isDone,
                                          onChanged: (checked) =>
                                              _toggleSubtask(
                                                subtask,
                                                checked ?? false,
                                              ),
                                          checkColor: Colors.black,
                                          activeColor: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                        title: Text(
                                          subtask.title,
                                          style: TextStyle(
                                            color: Colors.white,
                                            decoration: subtask.isDone
                                                ? TextDecoration.lineThrough
                                                : TextDecoration.none,
                                            decorationColor: Colors.white,
                                            decorationThickness: 2,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          tooltip: context.l10n.delete,
                                          onPressed: () async {
                                            final ok =
                                                await _confirmDeleteGroceryItem(
                                                  subtask.title,
                                                );
                                            if (!ok) return;
                                            await _deleteSubtask(subtask);
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      if (index < _subtasks.length - 1)
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: Colors.white.withValues(
                                            alpha: 0.14,
                                          ),
                                        ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            )
                          : Column(
                              children: _subtasks
                                  .map(
                                    (subtask) => CheckboxListTile(
                                      dense: true,
                                      value: subtask.isDone,
                                      onChanged: (checked) => _toggleSubtask(
                                        subtask,
                                        checked ?? false,
                                      ),
                                      title: Text(
                                        subtask.title,
                                        style: TextStyle(
                                          decoration: subtask.isDone
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                        ),
                                      ),
                                      subtitle: Text(
                                        context.l10n.estHSpentH(
                                          subtask.timeEstimated,
                                          subtask.timeSpent,
                                        ),
                                      ),
                                      secondary:
                                          Theme.of(context).platform ==
                                                  TargetPlatform.iOS ||
                                              Theme.of(context).platform ==
                                                  TargetPlatform.macOS
                                          ? CupertinoButton(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(30, 30),
                                              onPressed: () =>
                                                  _showSubtaskActionSheet(
                                                    subtask,
                                                  ),
                                              child: const Icon(
                                                CupertinoIcons.ellipsis_circle,
                                                size: 20,
                                              ),
                                            )
                                          : PopupMenuButton<String>(
                                              onSelected: (value) {
                                                if (value == 'edit') {
                                                  _editSubtask(subtask);
                                                } else if (value == 'delete') {
                                                  _deleteSubtask(subtask);
                                                }
                                              },
                                              itemBuilder: (context) =>
                                                  <PopupMenuEntry<String>>[
                                                    PopupMenuItem<String>(
                                                      value: 'edit',
                                                      child: Text(
                                                        context.l10n.edit,
                                                      ),
                                                    ),
                                                    PopupMenuItem<String>(
                                                      value: 'delete',
                                                      child: Text(
                                                        context.l10n.delete,
                                                      ),
                                                    ),
                                                  ],
                                            ),
                                    ),
                                  )
                                  .toList(),
                            ),
                    if (!isPersistedTask &&
                        isGroceryEditor &&
                        _draftGroceryItems.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          children: _draftGroceryItems.asMap().entries.map((
                            entry,
                          ) {
                            final index = entry.key;
                            final item = entry.value;
                            return Column(
                              children: <Widget>[
                                ListTile(
                                  dense: true,
                                  leading: Checkbox(
                                    value: item.isDone,
                                    onChanged: (checked) =>
                                        _toggleDraftGroceryItem(
                                          index,
                                          checked ?? false,
                                        ),
                                    checkColor: Colors.black,
                                    activeColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  title: Text(
                                    item.title,
                                    style: TextStyle(
                                      color: Colors.white,
                                      decoration: item.isDone
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                      decorationColor: Colors.white,
                                      decorationThickness: 2,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: context.l10n.delete,
                                    onPressed: () async {
                                      final ok =
                                          await _confirmDeleteGroceryItem(
                                            item.title,
                                          );
                                      if (!ok) return;
                                      _deleteDraftGroceryItem(index);
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (index < _draftGroceryItems.length - 1)
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Colors.white.withValues(alpha: 0.14),
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              if (!isGroceryEditor)
                _section(
                  title: context.l10n.tags,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_taskTags.isEmpty) Text(context.l10n.noTagsAssigned),
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
                              decoration: InputDecoration(
                                labelText: context.l10n.addTagsCommaSeparated,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _applyTags,
                            child: Text(context.l10n.apply),
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
              if (!isGroceryEditor)
                _section(
                  title: context.l10n.taskLinks,
                  child: Column(
                    children: <Widget>[
                      if (_linkTypes.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              context
                                  .l10n
                                  .internalLinkTypesUnavailableForThisUserProject,
                            ),
                          ),
                        ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _internalLinkTaskIdController,
                              decoration: InputDecoration(
                                labelText: context.l10n.linkedTaskID,
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
                              decoration: InputDecoration(
                                labelText: context.l10n.relation,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _linkTypes.isEmpty
                                ? null
                                : _addInternalLink,
                            child: Text(context.l10n.link),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_taskLinks.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(context.l10n.noTaskLinks),
                        ),
                      if (_taskLinks.isNotEmpty)
                        Column(
                          children: _taskLinks
                              .map(
                                (link) => ListTile(
                                  dense: true,
                                  title: Text(
                                    '${link.label ?? context.l10n.linkedTo} #${link.oppositeTaskId}',
                                  ),
                                  subtitle: Text(
                                    link.oppositeTaskTitle ??
                                        context.l10n.taskNumber(
                                          link.oppositeTaskId,
                                        ),
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
              if (!isGroceryEditor)
                _section(
                  title: context.l10n.externalLinks,
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _externalLinkTitleController,
                              decoration: InputDecoration(
                                labelText: context.l10n.linkTitle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _externalLinkUrlController,
                              decoration: InputDecoration(
                                labelText: context.l10n.url,
                              ),
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
                              decoration: InputDecoration(
                                labelText: context.l10n.type,
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
                              decoration: InputDecoration(
                                labelText: context.l10n.dependency,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _addExternalLink,
                            child: Text(context.l10n.add),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_externalLinks.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(context.l10n.noExternalLinks),
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
                                        onPressed: () =>
                                            _openExternalLink(link),
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
