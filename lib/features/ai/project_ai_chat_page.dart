import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../ai/ai_models.dart';
import '../../l10n/l10n.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../storage/ai_chat_store.dart';
import '../../widgets/theme_mode_menu_button.dart';

class ProjectAiChatPage extends ConsumerStatefulWidget {
  const ProjectAiChatPage({
    required this.projectId,
    required this.projectName,
    super.key,
  });

  final int projectId;
  final String projectName;

  @override
  ConsumerState<ProjectAiChatPage> createState() => _ProjectAiChatPageState();
}

class _ProjectAiChatPageState extends ConsumerState<ProjectAiChatPage> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  final List<AiChatMessage> _messages = <AiChatMessage>[];
  StreamSubscription<String>? _streamSubscription;
  List<AiChatThread> _threads = const <AiChatThread>[];
  String? _activeThreadId;
  bool _isSending = false;
  bool _isLoadingPolicy = false;
  bool _scrollScheduled = false;
  AiProjectPolicy _policy = const AiProjectPolicy();

  @override
  void initState() {
    super.initState();
    _loadPolicy();
    _loadThreads();
  }

  void _scheduleScrollToLatest({bool animated = false}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_messagesScrollController.hasClients) return;
      final position = _messagesScrollController.position;
      final target = position.maxScrollExtent;
      if (animated) {
        _messagesScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _messagesScrollController.jumpTo(target);
      }
    });
  }

  String _formatMessageTimestamp(int createdAtMs) {
    if (createdAtMs <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(dt));
    if (sameDay) return time;
    final date = localizations.formatShortDate(dt);
    return '$date $time';
  }

  Future<void> _loadThreads() async {
    final store = ref.read(aiChatStoreProvider);
    final threads = await store.readByProject(widget.projectId);
    if (!mounted) return;
    if (threads.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final created = AiChatThread(
        id: '${widget.projectId}-$now',
        projectId: widget.projectId,
        projectName: widget.projectName,
        createdAtMs: now,
        updatedAtMs: now,
        messages: const <AiChatMessage>[],
      );
      await store.saveThread(created);
      if (!mounted) return;
      setState(() {
        _threads = <AiChatThread>[created];
        _activeThreadId = created.id;
        _messages
          ..clear()
          ..addAll(created.messages);
      });
      _scheduleScrollToLatest();
      return;
    }
    setState(() {
      _threads = threads;
      _activeThreadId = threads.first.id;
      _messages
        ..clear()
        ..addAll(threads.first.messages);
    });
    _scheduleScrollToLatest();
  }

  Future<void> _saveActiveThread() async {
    final activeId = _activeThreadId;
    if (activeId == null) return;
    AiChatThread? existing;
    for (final thread in _threads) {
      if (thread.id == activeId) {
        existing = thread;
        break;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final thread = AiChatThread(
      id: activeId,
      projectId: widget.projectId,
      projectName: widget.projectName,
      createdAtMs: existing?.createdAtMs ?? now,
      updatedAtMs: now,
      messages: List<AiChatMessage>.from(_messages),
    );
    await ref.read(aiChatStoreProvider).saveThread(thread);
    final updated = await ref
        .read(aiChatStoreProvider)
        .readByProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _threads = updated;
    });
  }

  Future<void> _startNewChat() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final thread = AiChatThread(
      id: '${widget.projectId}-$now',
      projectId: widget.projectId,
      projectName: widget.projectName,
      createdAtMs: now,
      updatedAtMs: now,
      messages: const <AiChatMessage>[],
    );
    await ref.read(aiChatStoreProvider).saveThread(thread);
    final updated = await ref
        .read(aiChatStoreProvider)
        .readByProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _threads = updated;
      _activeThreadId = thread.id;
      _messages.clear();
    });
    _scheduleScrollToLatest();
  }

  Future<void> _pickThread() async {
    if (_threads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noSavedChatsForProject)),
      );
      return;
    }
    final selected = await showAdaptiveDialog<AiChatThread>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(context.l10n.continueChat),
        content: SizedBox(
          width: 460,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _threads.length,
            itemBuilder: (context, index) {
              final thread = _threads[index];
              final updated = DateTime.fromMillisecondsSinceEpoch(
                thread.updatedAtMs,
              );
              final subtitle =
                  '${updated.year}-${updated.month.toString().padLeft(2, '0')}-${updated.day.toString().padLeft(2, '0')} ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}';
              return ListTile(
                title: Text(thread.title),
                subtitle: Text(subtitle),
                onTap: () => Navigator.of(context).pop(thread),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _activeThreadId = selected.id;
      _messages
        ..clear()
        ..addAll(selected.messages);
    });
    _scheduleScrollToLatest();
  }

  Future<void> _exportCurrentChat() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noMessagesToExport)));
      return;
    }
    final buffer = StringBuffer()
      ..writeln('# ${widget.projectName} - ${context.l10n.aiChat}')
      ..writeln()
      ..writeln('Project ID: ${widget.projectId}')
      ..writeln('Thread ID: ${_activeThreadId ?? '-'}')
      ..writeln();
    for (final message in _messages) {
      final role = message.role.toUpperCase();
      final timestamp = _formatMessageTimestamp(message.createdAtMs);
      if (timestamp.isEmpty) {
        buffer.writeln('## $role');
      } else {
        buffer.writeln('## $role · $timestamp');
      }
      buffer.writeln(message.content.trim());
      buffer.writeln();
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: buffer.toString().trim(),
          subject: '${widget.projectName} AI chat',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.chatExportFailed(error))),
      );
    }
  }

  Future<void> _loadPolicy() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    setState(() => _isLoadingPolicy = true);
    try {
      final policy = await api.getProjectAiPolicy(widget.projectId);
      if (!mounted) return;
      setState(() {
        _policy = policy;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _policy = const AiProjectPolicy();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingPolicy = false);
      }
    }
  }

  Future<void> _savePolicy() async {
    final api = ref.read(kanboardApiProvider);
    final creds = ref.read(sessionCredentialsProvider);
    if (api == null || creds == null) return;
    final next = AiProjectPolicy(
      enabled: _policy.enabled,
      keyMode: _policy.keyMode,
      ownerUsername: creds.username,
    );
    final saved = await api.saveProjectAiPolicy(
      projectId: widget.projectId,
      policy: next,
    );
    if (!saved || !mounted) return;
    setState(() => _policy = next);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.aiProjectPolicySaved)));
  }

  Future<bool> _ensurePolicyAndConsent() async {
    if (!_policy.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.aiNotEnabledForThisProject)),
      );
      return false;
    }
    if (_policy.keyMode != AiKeyMode.ownerKey) return true;
    final creds = ref.read(sessionCredentialsProvider);
    final owner = (_policy.ownerUsername ?? '').trim();
    if (creds == null || owner.isEmpty) return true;
    if (creds.username.trim().toLowerCase() == owner.toLowerCase()) return true;
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
    if (confirm == true) {
      await consentStore.setAcceptedProjectCostWarning(
        projectId: widget.projectId,
        username: creds.username,
        accepted: true,
      );
      return true;
    }
    return false;
  }

  Future<String> _buildProjectContext() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) {
      return 'Project: ${widget.projectName} (ID: ${widget.projectId})';
    }
    final header = StringBuffer()
      ..writeln('Project: ${widget.projectName} (ID: ${widget.projectId})');
    try {
      final board = await api.getBoard(widget.projectId);
      var openCount = 0;
      var doneCount = 0;
      var included = 0;
      var truncated = false;
      const maxTasks = 120;
      final lines = <String>[];
      final columnById = <int, KanboardColumn>{};
      final totalTasksByColumnId = <int, int>{};

      final sortedSwimlanes = List<KanboardSwimlane>.from(board.swimlanes)
        ..sort((a, b) => a.position.compareTo(b.position));

      for (final swimlane in sortedSwimlanes) {
        for (final column in swimlane.columns) {
          columnById.putIfAbsent(column.id, () => column);
          totalTasksByColumnId[column.id] =
              (totalTasksByColumnId[column.id] ?? 0) + column.tasks.length;
          for (final task in column.tasks) {
            if (task.isActive) {
              openCount += 1;
            } else {
              doneCount += 1;
            }
            if (included >= maxTasks) {
              truncated = true;
              continue;
            }
            final title = task.title.replaceAll(RegExp(r'\s+'), ' ').trim();
            final status = task.isActive ? 'open' : 'done';
            lines.add(
              '- Task #${task.id} [$status] ${swimlane.name} > ${column.title}: $title',
            );
            included += 1;
          }
        }
      }

      final sortedColumns = columnById.values.toList()
        ..sort((a, b) => a.position.compareTo(b.position));

      header.writeln('Swimlanes:');
      if (sortedSwimlanes.isEmpty) {
        header.writeln('- (no swimlanes)');
      } else {
        for (final lane in sortedSwimlanes) {
          header.writeln('- #${lane.id} [pos ${lane.position}]: ${lane.name}');
        }
      }

      header.writeln('Columns (including empty):');
      if (sortedColumns.isEmpty) {
        header.writeln('- (no columns)');
      } else {
        for (final column in sortedColumns) {
          final count = totalTasksByColumnId[column.id] ?? 0;
          header.writeln(
            '- #${column.id} [pos ${column.position}] ${column.title} (tasks: $count)',
          );
        }
      }

      header.writeln('Task summary: open=$openCount, done=$doneCount');
      header.writeln('Visible tasks snapshot:');
      if (lines.isEmpty) {
        header.writeln('- (no tasks)');
      } else {
        for (final line in lines) {
          header.writeln(line);
        }
      }
      if (truncated) {
        header.writeln(
          '- (truncated to first $maxTasks tasks for context size safety)',
        );
      }
      return header.toString().trim();
    } catch (_) {
      return header.toString().trim();
    }
  }

  Future<void> _send() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isSending) return;
    final aiSettings = await ref.read(aiSettingsStoreProvider).read();
    if (!aiSettings.enabled || !aiSettings.hasApiKey) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.configureAiInSettings)),
      );
      return;
    }
    final permitted = await _ensurePolicyAndConsent();
    if (!permitted) return;
    final projectContext = await _buildProjectContext();
    const toolInstruction = '''
You are running inside a Kanboard Flutter app connected to a Kanboard server through JSON-RPC.
When the user asks to create/update Kanboard data, you may return an action plan JSON in a fenced code block.
Use this exact schema:
```json
{
  "actions": [
    {"type": "create_swimlane", "name": "Sprint 2", "alias": "sprint2"},
    {"type": "create_column", "title": "In Progress", "task_limit": 0, "alias": "inprogress"},
    {"type": "remove_column", "column_title": "Deprecated"},
    {"type": "create_task", "title": "Task title", "description": "Optional", "swimlane_alias": "sprint2"},
    {"type": "relocate_task", "task_id": 123, "column_alias": "inprogress", "swimlane_alias": "sprint2", "position": 1},
    {"type": "reorder_columns", "column_titles": ["Backlog", "In Progress", "Done"]},
    {"type": "reorder_swimlanes", "swimlane_names": ["Main", "Sprint 2"]}
  ]
}
```
Supported action types:
- create_swimlane: name (required), description (optional), alias (optional)
- create_column: title (required), description (optional), task_limit (optional), alias (optional)
- remove_column: column_id OR column_alias OR column_title (required); avoid deleting the last remaining column
- create_task: title (required), description (optional), swimlane_alias (optional), swimlane_id (optional), swimlane_name (optional), column_id (optional)
- relocate_task: task_id (preferred) or task_title (fallback), optional target column/swimlane via column_id|column_alias|column_title and swimlane_id|swimlane_alias|swimlane_name, optional position
- relocate_tasks: bulk move using task_ids OR task_titles OR source filters (source_column_title/source_swimlane_name/source_status=open|done|any), plus target column/swimlane fields and optional start_position
- reorder_columns: column_titles (required, list of titles in desired order)
- reorder_swimlanes: swimlane_names (required, list of names in desired order)
Do not invent unsupported action types.
If no action is needed, reply normally without JSON.
''';
    setState(() {
      _isSending = true;
      final now = DateTime.now().millisecondsSinceEpoch;
      _messages.add(
        AiChatMessage(role: 'user', content: prompt, createdAtMs: now),
      );
      _messages.add(
        AiChatMessage(role: 'assistant', content: '', createdAtMs: now),
      );
      _promptController.clear();
    });
    _scheduleScrollToLatest(animated: true);
    await _saveActiveThread();
    try {
      final ai = ref.read(aiFacadeProvider);
      final assistantIndex = _messages.length - 1;
      _streamSubscription = ai
          .streamChat(
            history: _messages.take(_messages.length - 1).toList(),
            userPrompt:
                'Project context:\n$projectContext\n\n$toolInstruction\n\nUser request:\n$prompt',
          )
          .listen(
            (delta) {
              if (!mounted) return;
              setState(() {
                final current = _messages[assistantIndex];
                _messages[assistantIndex] = current.copyWith(
                  content: '${current.content}$delta',
                );
              });
              _scheduleScrollToLatest();
            },
            onError: (Object error) {
              if (!mounted) return;
              setState(() {
                _streamSubscription = null;
                if (_messages.isNotEmpty &&
                    _messages.last.role == 'assistant') {
                  _messages.removeLast();
                }
                _isSending = false;
              });
              _saveActiveThread();
              _scheduleScrollToLatest();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.aiRequestFailed(error))),
              );
            },
            onDone: () {
              if (!mounted) return;
              final assistantText =
                  _messages.isNotEmpty && _messages.last.role == 'assistant'
                  ? _messages.last.content
                  : '';
              setState(() {
                _streamSubscription = null;
                if (_messages.isNotEmpty &&
                    _messages.last.role == 'assistant' &&
                    _messages.last.content.trim().isEmpty) {
                  _messages.removeLast();
                }
                _isSending = false;
              });
              _saveActiveThread();
              _scheduleScrollToLatest();
              if (assistantText.trim().isNotEmpty) {
                unawaited(_maybeExecuteActionPlan(assistantText));
              }
            },
            cancelOnError: true,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
          _messages.removeLast();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.aiRequestFailed(error))),
      );
      _scheduleScrollToLatest();
    }
  }

  Map<String, dynamic>? _extractActionPlan(String text) {
    String candidate = '';
    final fenceRegex = RegExp(r'```json\s*([\s\S]*?)```', multiLine: true);
    final fenceMatch = fenceRegex.firstMatch(text);
    if (fenceMatch != null) {
      candidate = fenceMatch.group(1)?.trim() ?? '';
    } else {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        candidate = text.substring(start, end + 1).trim();
      }
    }
    if (candidate.isEmpty) return null;
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic> && decoded['actions'] is List) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _maybeExecuteActionPlan(String assistantText) async {
    final plan = _extractActionPlan(assistantText);
    if (plan == null) return;
    final actions = plan['actions'] as List<dynamic>? ?? const <dynamic>[];
    if (actions.isEmpty || !mounted) return;

    final summary = actions
        .whereType<Map<String, dynamic>>()
        .map((action) {
          final type = action['type']?.toString() ?? 'unknown';
          final title = action['title']?.toString();
          final name = action['name']?.toString();
          return switch (type) {
            'create_swimlane' =>
              '- create swimlane: ${name ?? '(missing name)'}',
            'create_column' =>
              '- create column: ${action['title']?.toString() ?? '(missing title)'}',
            'remove_column' =>
              '- remove column: ${action['column_title']?.toString() ?? action['column_alias']?.toString() ?? '#${action['column_id']?.toString() ?? '?'}'}',
            'delete_column' =>
              '- remove column: ${action['column_title']?.toString() ?? action['column_alias']?.toString() ?? '#${action['column_id']?.toString() ?? '?'}'}',
            'create_task' => '- create task: ${title ?? '(missing title)'}',
            'relocate_task' =>
              '- relocate task: #${action['task_id']?.toString() ?? '?'} to ${action['swimlane_name']?.toString() ?? action['swimlane_alias']?.toString() ?? 'current swimlane'} / ${action['column_title']?.toString() ?? action['column_alias']?.toString() ?? 'current column'}',
            'move_task' =>
              '- move task: #${action['task_id']?.toString() ?? '?'}',
            'relocate_tasks' =>
              '- relocate tasks (bulk): ${(action['task_ids'] as List?)?.length ?? (action['task_titles'] as List?)?.length ?? '?'} items',
            'move_tasks' =>
              '- move tasks (bulk): ${(action['task_ids'] as List?)?.length ?? (action['task_titles'] as List?)?.length ?? '?'} items',
            'reorder_columns' =>
              '- reorder columns: ${(action['column_titles'] as List?)?.join(', ') ?? '(missing list)'}',
            'reorder_swimlanes' =>
              '- reorder swimlanes: ${(action['swimlane_names'] as List?)?.join(', ') ?? '(missing list)'}',
            _ => '- unsupported action: $type',
          };
        })
        .join('\n');

    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(context.l10n.aiActionPlanDetected),
        content: Text(summary),
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
    if (confirm != true) return;
    await _executeActionPlan(actions);
  }

  Future<void> _executeActionPlan(List<dynamic> rawActions) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;

    final aliases = <String, int>{};
    final columnAliases = <String, int>{};
    var createdSwimlanes = 0;
    var createdColumns = 0;
    var createdTasks = 0;
    var relocatedTasks = 0;
    var skippedRelocations = 0;
    var columns = await api.getColumns(widget.projectId);
    final defaultColumnId = columns.isNotEmpty ? columns.first.id : null;
    var swimlanes = await api.getAllSwimlanes(widget.projectId);

    String norm(String value) => value.trim().toLowerCase();

    Future<KanboardBoard> loadBoard() => api.getBoard(widget.projectId);

    List<KanboardTask> flattenTasks(KanboardBoard board) {
      final tasks = <KanboardTask>[];
      for (final lane in board.swimlanes) {
        for (final column in lane.columns) {
          tasks.addAll(column.tasks);
        }
      }
      return tasks;
    }

    int? resolveSwimlaneId(
      Map<String, dynamic> raw,
      KanboardTask? fallbackTask,
    ) {
      int? targetSwimlaneId = int.tryParse(
        raw['swimlane_id']?.toString() ?? '',
      );
      final swimlaneAlias = raw['swimlane_alias']?.toString().trim();
      if (targetSwimlaneId == null &&
          swimlaneAlias != null &&
          swimlaneAlias.isNotEmpty) {
        targetSwimlaneId = aliases[swimlaneAlias];
      }
      if (targetSwimlaneId == null) {
        final swimlaneName = raw['swimlane_name']?.toString().trim();
        if (swimlaneName != null && swimlaneName.isNotEmpty) {
          for (final lane in swimlanes) {
            if (norm(lane.name) == norm(swimlaneName)) {
              targetSwimlaneId = lane.id;
              break;
            }
          }
        }
      }
      return targetSwimlaneId ?? fallbackTask?.swimlaneId;
    }

    int? resolveColumnId(Map<String, dynamic> raw, KanboardTask? fallbackTask) {
      int? targetColumnId = int.tryParse(raw['column_id']?.toString() ?? '');
      final columnAlias = raw['column_alias']?.toString().trim();
      if (targetColumnId == null &&
          columnAlias != null &&
          columnAlias.isNotEmpty) {
        targetColumnId = columnAliases[columnAlias];
      }
      if (targetColumnId == null) {
        final columnTitle = raw['column_title']?.toString().trim();
        if (columnTitle != null && columnTitle.isNotEmpty) {
          for (final col in columns) {
            if (norm(col.title) == norm(columnTitle)) {
              targetColumnId = col.id;
              break;
            }
          }
        }
      }
      return targetColumnId ?? fallbackTask?.columnId ?? defaultColumnId;
    }

    Future<int> resolvePosition({
      required int swimlaneId,
      required int columnId,
      int? requested,
    }) async {
      if (requested != null && requested > 0) return requested;
      final board = await loadBoard();
      var maxPosition = 0;
      for (final lane in board.swimlanes) {
        if (lane.id != swimlaneId) continue;
        for (final col in lane.columns) {
          if (col.id != columnId) continue;
          for (final t in col.tasks) {
            if (t.position > maxPosition) maxPosition = t.position;
          }
        }
      }
      return maxPosition + 1;
    }

    Future<KanboardTask?> resolveTaskByIdOrTitle(
      Map<String, dynamic> raw,
    ) async {
      final taskId = int.tryParse(raw['task_id']?.toString() ?? '');
      if (taskId != null && taskId > 0) {
        return api.getTask(taskId);
      }
      final taskTitle = raw['task_title']?.toString().trim();
      if (taskTitle == null || taskTitle.isEmpty) return null;
      final board = await loadBoard();
      final allTasks = flattenTasks(board);
      KanboardTask? exact;
      for (final task in allTasks) {
        if (norm(task.title) == norm(taskTitle)) {
          exact = task;
          break;
        }
      }
      if (exact != null) return exact;
      for (final task in allTasks) {
        final taskNorm = norm(task.title);
        final queryNorm = norm(taskTitle);
        if (taskNorm.contains(queryNorm) || queryNorm.contains(taskNorm)) {
          return task;
        }
      }
      return null;
    }

    for (final raw in rawActions) {
      if (raw is! Map<String, dynamic>) continue;
      final type = raw['type']?.toString() ?? '';
      if (type == 'create_swimlane') {
        final name = raw['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final createdId = await api.addSwimlane(
          projectId: widget.projectId,
          name: name,
          description: raw['description']?.toString(),
        );
        if (createdId != null && createdId > 0) {
          createdSwimlanes += 1;
          final alias = raw['alias']?.toString().trim();
          if (alias != null && alias.isNotEmpty) {
            aliases[alias] = createdId;
          }
          swimlanes.add(
            KanboardSwimlane(
              id: createdId,
              name: name,
              columns: const <KanboardColumn>[],
            ),
          );
        }
      } else if (type == 'create_column') {
        final title = raw['title']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        final taskLimit = int.tryParse(raw['task_limit']?.toString() ?? '');
        final createdId = await api.addColumn(
          projectId: widget.projectId,
          title: title,
          taskLimit: taskLimit,
          description: raw['description']?.toString(),
        );
        if (createdId != null && createdId > 0) {
          createdColumns += 1;
          final alias = raw['alias']?.toString().trim();
          if (alias != null && alias.isNotEmpty) {
            columnAliases[alias] = createdId;
          }
          columns = await api.getColumns(widget.projectId);
        }
      } else if (type == 'remove_column' || type == 'delete_column') {
        columns = await api.getColumns(widget.projectId);
        if (columns.length <= 1) continue;
        int? columnId = int.tryParse(raw['column_id']?.toString() ?? '');
        final columnAlias = raw['column_alias']?.toString().trim();
        if (columnId == null && columnAlias != null && columnAlias.isNotEmpty) {
          columnId = columnAliases[columnAlias];
        }
        if (columnId == null) {
          final columnTitle = raw['column_title']?.toString().trim();
          if (columnTitle != null && columnTitle.isNotEmpty) {
            for (final col in columns) {
              if (norm(col.title) == norm(columnTitle)) {
                columnId = col.id;
                break;
              }
            }
          }
        }
        if (columnId == null || !columns.any((c) => c.id == columnId)) {
          continue;
        }
        final removed = await api.removeColumn(columnId);
        if (removed) {
          // "columns" in snackbar reports column changes (creates + removes).
          createdColumns += 1;
          columns = await api.getColumns(widget.projectId);
        }
      } else if (type == 'create_task') {
        final title = raw['title']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        int? swimlaneId;
        final swimlaneAlias = raw['swimlane_alias']?.toString().trim();
        if (swimlaneAlias != null && swimlaneAlias.isNotEmpty) {
          swimlaneId = aliases[swimlaneAlias];
        }
        swimlaneId ??= int.tryParse(raw['swimlane_id']?.toString() ?? '');
        if (swimlaneId == null) {
          final swimlaneName = raw['swimlane_name']?.toString().trim();
          if (swimlaneName != null && swimlaneName.isNotEmpty) {
            for (final lane in swimlanes) {
              if (lane.name.trim().toLowerCase() ==
                  swimlaneName.toLowerCase()) {
                swimlaneId = lane.id;
                break;
              }
            }
          }
        }
        int? columnId = int.tryParse(raw['column_id']?.toString() ?? '');
        final columnAlias = raw['column_alias']?.toString().trim();
        if (columnId == null && columnAlias != null && columnAlias.isNotEmpty) {
          columnId = columnAliases[columnAlias];
        }
        if (columnId == null) {
          final columnTitle = raw['column_title']?.toString().trim();
          if (columnTitle != null && columnTitle.isNotEmpty) {
            for (final col in columns) {
              if (col.title.trim().toLowerCase() == columnTitle.toLowerCase()) {
                columnId = col.id;
                break;
              }
            }
          }
        }
        columnId ??= defaultColumnId;
        final createdId = await api.createTask(
          projectId: widget.projectId,
          title: title,
          description: raw['description']?.toString(),
          swimlaneId: swimlaneId,
          columnId: columnId,
        );
        if (createdId != null && createdId > 0) {
          createdTasks += 1;
        }
      } else if (type == 'reorder_columns') {
        final orderedTitles =
            (raw['column_titles'] as List<dynamic>? ?? const <dynamic>[])
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
        if (orderedTitles.isEmpty) continue;
        columns = await api.getColumns(widget.projectId);
        final byTitle = <String, KanboardColumn>{};
        for (final c in columns) {
          byTitle[c.title.trim().toLowerCase()] = c;
        }
        var nextPosition = 1;
        final touched = <int>{};
        for (final title in orderedTitles) {
          final column = byTitle[title.toLowerCase()];
          if (column == null) continue;
          await api.changeColumnPosition(
            projectId: widget.projectId,
            columnId: column.id,
            position: nextPosition,
          );
          touched.add(column.id);
          nextPosition += 1;
        }
        for (final column in columns) {
          if (touched.contains(column.id)) continue;
          await api.changeColumnPosition(
            projectId: widget.projectId,
            columnId: column.id,
            position: nextPosition,
          );
          nextPosition += 1;
        }
        columns = await api.getColumns(widget.projectId);
      } else if (type == 'reorder_swimlanes') {
        final orderedNames =
            (raw['swimlane_names'] as List<dynamic>? ?? const <dynamic>[])
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
        if (orderedNames.isEmpty) continue;
        swimlanes = await api.getAllSwimlanes(widget.projectId);
        final byName = <String, KanboardSwimlane>{};
        for (final lane in swimlanes) {
          byName[lane.name.trim().toLowerCase()] = lane;
        }
        var nextPosition = 1;
        final touched = <int>{};
        for (final name in orderedNames) {
          final lane = byName[name.toLowerCase()];
          if (lane == null) continue;
          await api.changeSwimlanePosition(
            projectId: widget.projectId,
            swimlaneId: lane.id,
            position: nextPosition,
          );
          touched.add(lane.id);
          nextPosition += 1;
        }
        for (final lane in swimlanes) {
          if (touched.contains(lane.id)) continue;
          await api.changeSwimlanePosition(
            projectId: widget.projectId,
            swimlaneId: lane.id,
            position: nextPosition,
          );
          nextPosition += 1;
        }
        swimlanes = await api.getAllSwimlanes(widget.projectId);
      } else if (type == 'relocate_task' || type == 'move_task') {
        final task = await resolveTaskByIdOrTitle(raw);
        if (task == null) {
          skippedRelocations += 1;
          continue;
        }
        final targetSwimlaneId = resolveSwimlaneId(raw, task);
        final targetColumnId = resolveColumnId(raw, task);
        if (targetSwimlaneId == null || targetColumnId == null) {
          skippedRelocations += 1;
          continue;
        }
        final requested = int.tryParse(raw['position']?.toString() ?? '');
        final targetPosition = await resolvePosition(
          swimlaneId: targetSwimlaneId,
          columnId: targetColumnId,
          requested: requested,
        );
        final moved = await api.moveTaskPosition(
          projectId: widget.projectId,
          taskId: task.id,
          columnId: targetColumnId,
          position: targetPosition,
          swimlaneId: targetSwimlaneId,
        );
        if (moved) {
          relocatedTasks += 1;
        } else {
          skippedRelocations += 1;
        }
      } else if (type == 'relocate_tasks' || type == 'move_tasks') {
        final candidates = <KanboardTask>[];
        final taskIds = (raw['task_ids'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toSet()
            .toList();
        for (final id in taskIds) {
          final task = await api.getTask(id);
          if (task != null) candidates.add(task);
        }
        final taskTitles =
            (raw['task_titles'] as List<dynamic>? ?? const <dynamic>[])
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
        if (candidates.isEmpty && taskTitles.isNotEmpty) {
          final board = await loadBoard();
          final allTasks = flattenTasks(board);
          for (final title in taskTitles) {
            KanboardTask? match;
            for (final t in allTasks) {
              if (norm(t.title) == norm(title)) {
                match = t;
                break;
              }
            }
            if (match == null) {
              for (final t in allTasks) {
                if (norm(t.title).contains(norm(title)) ||
                    norm(title).contains(norm(t.title))) {
                  match = t;
                  break;
                }
              }
            }
            if (match != null && match.id > 0) {
              candidates.add(match);
            }
          }
        }
        if (candidates.isEmpty) {
          final board = await loadBoard();
          final sourceColumnTitle = raw['source_column_title']
              ?.toString()
              .trim();
          final sourceSwimlaneName = raw['source_swimlane_name']
              ?.toString()
              .trim();
          final sourceStatus = (raw['source_status']?.toString() ?? 'any')
              .trim()
              .toLowerCase();
          for (final lane in board.swimlanes) {
            if (sourceSwimlaneName != null &&
                sourceSwimlaneName.isNotEmpty &&
                norm(lane.name) != norm(sourceSwimlaneName)) {
              continue;
            }
            for (final col in lane.columns) {
              if (sourceColumnTitle != null &&
                  sourceColumnTitle.isNotEmpty &&
                  norm(col.title) != norm(sourceColumnTitle)) {
                continue;
              }
              for (final task in col.tasks) {
                if (sourceStatus == 'open' && !task.isActive) continue;
                if (sourceStatus == 'done' && task.isActive) continue;
                candidates.add(task);
              }
            }
          }
        }
        final unique = <int, KanboardTask>{};
        for (final task in candidates) {
          unique[task.id] = task;
        }
        var nextPosition =
            int.tryParse(raw['start_position']?.toString() ?? '') ?? 0;
        for (final task in unique.values) {
          final targetSwimlaneId = resolveSwimlaneId(raw, task);
          final targetColumnId = resolveColumnId(raw, task);
          if (targetSwimlaneId == null || targetColumnId == null) {
            skippedRelocations += 1;
            continue;
          }
          final requestedPosition = nextPosition > 0 ? nextPosition : null;
          final resolvedPosition = await resolvePosition(
            swimlaneId: targetSwimlaneId,
            columnId: targetColumnId,
            requested: requestedPosition,
          );
          final moved = await api.moveTaskPosition(
            projectId: widget.projectId,
            taskId: task.id,
            columnId: targetColumnId,
            position: resolvedPosition,
            swimlaneId: targetSwimlaneId,
          );
          if (moved) {
            relocatedTasks += 1;
            if (nextPosition > 0) {
              nextPosition = resolvedPosition + 1;
            }
          } else {
            skippedRelocations += 1;
          }
        }
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.aiActionsAppliedDetailed(
            createdSwimlanes,
            createdColumns,
            createdTasks,
            relocatedTasks,
            skippedRelocations,
          ),
        ),
      ),
    );
  }

  Future<void> _stopStreaming() async {
    final subscription = _streamSubscription;
    if (subscription == null) return;
    await subscription.cancel();
    _streamSubscription = null;
    if (!mounted) return;
    setState(() {
      _isSending = false;
      if (_messages.isNotEmpty &&
          _messages.last.role == 'assistant' &&
          _messages.last.content.trim().isEmpty) {
        _messages.removeLast();
      }
    });
    await _saveActiveThread();
    _scheduleScrollToLatest();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _messagesScrollController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.aiChatForProject(widget.projectName)),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'new':
                  _startNewChat();
                  break;
                case 'continue':
                  _pickThread();
                  break;
                case 'export':
                  _exportCurrentChat();
                  break;
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'new',
                child: Text(context.l10n.newChat),
              ),
              PopupMenuItem<String>(
                value: 'continue',
                child: Text(context.l10n.continueChat),
              ),
              PopupMenuItem<String>(
                value: 'export',
                child: Text(context.l10n.exportChat),
              ),
            ],
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_activeThreadId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.currentChatId(_activeThreadId!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _policy.enabled,
                    onChanged: _isLoadingPolicy
                        ? null
                        : (value) => setState(
                            () => _policy = AiProjectPolicy(
                              enabled: value,
                              keyMode: _policy.keyMode,
                              ownerUsername: _policy.ownerUsername,
                            ),
                          ),
                    title: Text(context.l10n.enableAIForProject),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AiKeyMode>(
                    initialValue: _policy.keyMode,
                    decoration: InputDecoration(
                      labelText: context.l10n.aiKeyMode,
                    ),
                    items: <DropdownMenuItem<AiKeyMode>>[
                      DropdownMenuItem<AiKeyMode>(
                        value: AiKeyMode.ownerKey,
                        child: Text(context.l10n.ownerKeyMode),
                      ),
                      DropdownMenuItem<AiKeyMode>(
                        value: AiKeyMode.userKeyRequired,
                        child: Text(context.l10n.userKeyRequiredMode),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(
                        () => _policy = AiProjectPolicy(
                          enabled: _policy.enabled,
                          keyMode: value,
                          ownerUsername: _policy.ownerUsername,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _savePolicy,
                      icon: const Icon(Icons.save),
                      label: Text(context.l10n.save),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _messagesScrollController,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message.role == 'user';
                final timestamp = _formatMessageTimestamp(message.createdAtMs);
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Card(
                      color: isUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: isUser
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(message.content),
                            if (timestamp.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 6),
                              Text(
                                timestamp,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isSending)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.aiIsTyping,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: context.l10n.message,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(context.l10n.send),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isSending ? _stopStreaming : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(context.l10n.stop),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
