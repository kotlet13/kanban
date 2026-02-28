import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/bidirectional_scroll_view.dart';
import '../../widgets/theme_mode_menu_button.dart';
import '../tasks/task_details_page.dart';

enum _BoardOverflowAction { projects, structure, search, financeTable, aiChat }

class _TaskDragPayload {
  const _TaskDragPayload({
    required this.task,
    required this.sourceColumnId,
    required this.sourceSwimlaneId,
  });

  final KanboardTask task;
  final int sourceColumnId;
  final int sourceSwimlaneId;
}

class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({
    required this.projectId,
    required this.projectName,
    this.projectColorHex,
    super.key,
  });

  final int projectId;
  final String projectName;
  final String? projectColorHex;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  bool _isLoading = false;
  String? _error;
  KanboardBoard? _board;
  String? _expenseCurrencyCode;
  int? _expenseBudgetCents;

  Color _projectAccent(ThemeData theme) {
    return _parseHexColor(widget.projectColorHex) ?? theme.colorScheme.primary;
  }

  Color? _parseHexColor(String? value) {
    final normalized = _normalizeColorHex(value);
    if (normalized == null) return null;
    return Color(int.parse('FF${normalized.substring(1)}', radix: 16));
  }

  String? _normalizeColorHex(String? value) {
    if (value == null) return null;
    final text = value.trim().toUpperCase();
    if (text.isEmpty) return null;
    final withHash = text.startsWith('#') ? text : '#$text';
    final hex = withHash.substring(1);
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(hex)) return null;
    return '#$hex';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoard());
  }

  Future<void> _loadBoard({bool fromRefresh = false}) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) {
      setState(() {
        _error = context.l10n.noActiveSessionConnectFirst;
      });
      return;
    }

    if (!fromRefresh) {
      final cache = await ref.read(cacheStoreProvider.future);
      final cachedBoard = cache.readBoard(widget.projectId);
      if (cachedBoard != null && mounted) {
        setState(() {
          _board = cachedBoard;
        });
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final boardFuture = api.getBoard(widget.projectId);
      final currencyFuture = api.getProjectExpenseCurrency(widget.projectId);
      final budgetFuture = api.getProjectExpenseBudgetCents(widget.projectId);
      final board = await boardFuture;
      final expenseCurrencyCode = await currencyFuture;
      final expenseBudgetCents = await budgetFuture;
      final cache = await ref.read(cacheStoreProvider.future);
      await cache.saveBoard(board);
      if (!mounted) return;
      setState(() {
        _board = board;
        _expenseCurrencyCode = expenseCurrencyCode;
        _expenseBudgetCents = expenseBudgetCents;
      });
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

  Future<void> _openTaskEditor({
    KanboardTask? task,
    int? columnId,
    int? swimlaneId,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final maxWidth = size.width < 760 ? size.width - 24 : 720.0;
        final maxHeight = size.height * 0.9;
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: TaskDetailsSheet(
              projectId: widget.projectId,
              task: task,
              initialColumnId: columnId,
              initialSwimlaneId: swimlaneId,
            ),
          ),
        );
      },
    );
    if (changed == true && mounted) {
      await _loadBoard(fromRefresh: true);
    }
  }

  Future<void> _deleteTask(KanboardTask task) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteTask),
        content: Text(context.l10n.deletePermanently(task.title)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await api.removeTask(task.id);
      await _loadBoard(fromRefresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.deleteFailed(error))));
    }
  }

  Future<void> _setTaskDone(KanboardTask task, {required bool done}) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    try {
      final ok = done
          ? await api.closeTask(task.id)
          : await api.openTask(task.id);
      if (!ok) {
        throw StateError('Server rejected task status update.');
      }
      await _loadBoard(fromRefresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            done ? context.l10n.taskMarkedDone : context.l10n.taskReopened,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.statusUpdateFailed(error))),
      );
    }
  }

  Future<void> _reorderTasksInColumn({
    required KanboardSwimlane swimlane,
    required KanboardColumn column,
    required int oldIndex,
    required int newIndex,
  }) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final list = List<KanboardTask>.from(column.tasks);
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    setState(() {
      column.tasks
        ..clear()
        ..addAll(list);
    });

    try {
      for (var i = 0; i < list.length; i++) {
        await api.moveTaskPosition(
          projectId: widget.projectId,
          taskId: list[i].id,
          columnId: column.id,
          position: i + 1,
          swimlaneId: swimlane.id,
        );
      }
      await _loadBoard(fromRefresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.moveFailed(error))));
      await _loadBoard(fromRefresh: true);
    }
  }

  Future<void> _moveTaskToColumn({
    required KanboardTask task,
    required int sourceColumnId,
    required int sourceSwimlaneId,
    required KanboardColumn targetColumn,
    required KanboardSwimlane targetSwimlane,
  }) async {
    if (sourceColumnId == targetColumn.id &&
        sourceSwimlaneId == targetSwimlane.id) {
      return;
    }
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;

    final targetPosition =
        targetColumn.tasks.where((existing) => existing.id != task.id).length +
        1;

    setState(() {
      final board = _board;
      if (board == null) return;
      for (final swimlane in board.swimlanes) {
        for (final column in swimlane.columns) {
          column.tasks.removeWhere((existing) => existing.id == task.id);
        }
      }
      targetColumn.tasks.add(task);
    });

    try {
      final moved = await api.moveTaskPosition(
        projectId: widget.projectId,
        taskId: task.id,
        columnId: targetColumn.id,
        position: targetPosition,
        swimlaneId: targetSwimlane.id,
      );
      if (!moved) {
        throw StateError('Task move rejected by server.');
      }
      await _loadBoard(fromRefresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.moveFailed(error))));
      await _loadBoard(fromRefresh: true);
    }
  }

  String _formatCents(int cents) {
    return (cents / 100).toStringAsFixed(2);
  }

  Future<void> _openGroceryListEditor() async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final maxWidth = size.width < 760 ? size.width - 24 : 720.0;
        final maxHeight = size.height * 0.9;
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: TaskDetailsSheet(
              projectId: widget.projectId,
              createAsGroceryList: true,
              initialTitle: dialogContext.l10n.groceryList,
            ),
          ),
        );
      },
    );
    if (changed == true && mounted) {
      await _loadBoard(fromRefresh: true);
    }
  }

  int _taskCount(KanboardBoard board) {
    var count = 0;
    for (final swimlane in board.swimlanes) {
      for (final column in swimlane.columns) {
        count += column.tasks.length;
      }
    }
    return count;
  }

  int _spentExpenseCents(KanboardBoard board) {
    var total = 0;
    for (final swimlane in board.swimlanes) {
      for (final column in swimlane.columns) {
        for (final task in column.tasks) {
          if (!task.isActive && task.score > 0) {
            total += task.score;
          }
        }
      }
    }
    return total;
  }

  int _plannedExpenseCents(KanboardBoard board) {
    var total = 0;
    for (final swimlane in board.swimlanes) {
      for (final column in swimlane.columns) {
        for (final task in column.tasks) {
          if (task.isActive && task.score > 0) {
            total += task.score;
          }
        }
      }
    }
    return total;
  }

  double _swimlaneSpentHours(KanboardSwimlane swimlane) {
    var total = 0.0;
    for (final column in swimlane.columns) {
      for (final task in column.tasks) {
        if (task.timeSpent > 0) {
          total += task.timeSpent;
        }
      }
    }
    return total;
  }

  String _formatHoursLabel(double hours) {
    var text = hours.toStringAsFixed(2);
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    return '$text h';
  }

  String _formatMoneyCents(int cents) {
    final code = (_expenseCurrencyCode ?? 'EUR').trim().toUpperCase();
    return '$code ${_formatCents(cents)}';
  }

  void _openStructureEditor() {
    context
        .push(
          '/board/${widget.projectId}/structure?projectName=${Uri.encodeComponent(widget.projectName)}',
        )
        .then((_) => _loadBoard(fromRefresh: true));
  }

  void _openAiChat() {
    context.push(
      '/board/${widget.projectId}/ai-chat?projectName=${Uri.encodeComponent(widget.projectName)}',
    );
  }

  void _openExpensesPage() {
    final query = <String, String>{
      'projectName': widget.projectName,
      if ((widget.projectColorHex ?? '').trim().isNotEmpty)
        'projectColor': widget.projectColorHex!.trim(),
    };
    final uri = Uri(
      path: '/board/${widget.projectId}/expenses',
      queryParameters: query,
    );
    context.push(uri.toString()).then((_) => _loadBoard(fromRefresh: true));
  }

  void _openFinanceTablePage() {
    final query = <String, String>{
      'projectName': widget.projectName,
      if ((widget.projectColorHex ?? '').trim().isNotEmpty)
        'projectColor': widget.projectColorHex!.trim(),
    };
    final uri = Uri(
      path: '/board/${widget.projectId}/finance-table',
      queryParameters: query,
    );
    context.push(uri.toString()).then((_) => _loadBoard(fromRefresh: true));
  }

  void _onOverflowActionSelected(_BoardOverflowAction action) {
    switch (action) {
      case _BoardOverflowAction.projects:
        context.go('/projects');
        return;
      case _BoardOverflowAction.structure:
        _openStructureEditor();
        return;
      case _BoardOverflowAction.search:
        _openSearch();
        return;
      case _BoardOverflowAction.financeTable:
        _openFinanceTablePage();
        return;
      case _BoardOverflowAction.aiChat:
        _openAiChat();
        return;
    }
  }

  Future<void> _openSearch() async {
    final l10n = context.l10n;
    final selectedTaskId = await showDialog<int>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 640),
          child: _TaskSearchSheet(projectId: widget.projectId),
        ),
      ),
    );
    if (selectedTaskId != null && selectedTaskId > 0) {
      await _openTaskEditor(
        task: KanboardTask(
          id: selectedTaskId,
          projectId: widget.projectId,
          columnId: 0,
          swimlaneId: 0,
          position: 0,
          title: l10n.taskNumber(selectedTaskId),
        ),
      );
    }
  }

  Widget _statusBanner({
    required IconData icon,
    required String text,
    bool isError = false,
    VoidCallback? onRetry,
  }) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : _projectAccent(theme);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: isError ? color : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (onRetry != null)
              FilledButton.tonal(
                onPressed: onRetry,
                child: Text(context.l10n.retry),
              ),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(
    KanboardTask task, {
    required int sourceColumnId,
    required int sourceSwimlaneId,
    required bool dragEnabled,
  }) {
    final theme = Theme.of(context);
    final accent = _projectAccent(theme);
    final isDone = !task.isActive;
    final taskDragPayload = _TaskDragPayload(
      task: task,
      sourceColumnId: sourceColumnId,
      sourceSwimlaneId: sourceSwimlaneId,
    );
    final dragFeedback = Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
    final handleChild = Container(
      width: 42,
      alignment: Alignment.center,
      child: Icon(
        Icons.drag_indicator,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    Widget? dragHandle;
    if (dragEnabled) {
      final desktopLikePlatform =
          kIsWeb ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux;
      if (desktopLikePlatform) {
        dragHandle = Draggable<_TaskDragPayload>(
          data: taskDragPayload,
          feedback: dragFeedback,
          childWhenDragging: Opacity(opacity: 0.35, child: handleChild),
          child: handleChild,
        );
      } else {
        dragHandle = LongPressDraggable<_TaskDragPayload>(
          data: taskDragPayload,
          feedback: dragFeedback,
          childWhenDragging: Opacity(opacity: 0.35, child: handleChild),
          child: handleChild,
        );
      }
    }

    Widget buildTaskCardBody() {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openTaskEditor(task: task),
          child: Row(
            children: <Widget>[
              if (dragHandle != null) dragHandle,
              Container(
                width: 4,
                height: 46,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                      Text(
                        context.l10n.taskNumber(task.id),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (task.description != null &&
                          task.description!.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          task.description!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _openTaskEditor(task: task);
                  } else if (value == 'done') {
                    _setTaskDone(task, done: true);
                  } else if (value == 'reopen') {
                    _setTaskDone(task, done: false);
                  } else if (value == 'delete') {
                    _deleteTask(task);
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text(context.l10n.edit),
                  ),
                  PopupMenuItem<String>(
                    value: task.isActive ? 'done' : 'reopen',
                    child: Text(
                      task.isActive
                          ? context.l10n.markDone
                          : context.l10n.reopen,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(context.l10n.delete),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      );
    }

    return KeyedSubtree(
      key: ValueKey('task-${task.id}'),
      child: buildTaskCardBody(),
    );
  }

  Widget _columnCard(
    KanboardSwimlane swimlane,
    KanboardColumn column, {
    bool compact = false,
    required bool dragEnabled,
  }) {
    return SizedBox(
      width: compact ? double.infinity : 320,
      height: compact ? 400 : 460,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Container(
            margin: compact
                ? const EdgeInsets.only(bottom: 10)
                : const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                column.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                context.l10n.tasks2(column.tasks.length),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _openTaskEditor(
                            columnId: column.id,
                            swimlaneId: swimlane.id,
                          ),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(
                            compact ? context.l10n.newLabel : context.l10n.task,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  Expanded(
                    child: DragTarget<_TaskDragPayload>(
                      onWillAcceptWithDetails: (details) {
                        if (!dragEnabled) return false;
                        final payload = details.data;
                        return !(payload.sourceColumnId == column.id &&
                            payload.sourceSwimlaneId == swimlane.id);
                      },
                      onAcceptWithDetails: (details) {
                        final payload = details.data;
                        _moveTaskToColumn(
                          task: payload.task,
                          sourceColumnId: payload.sourceColumnId,
                          sourceSwimlaneId: payload.sourceSwimlaneId,
                          targetColumn: column,
                          targetSwimlane: swimlane,
                        );
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isHovering = candidateData.isNotEmpty;
                        final body = column.tasks.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.inbox_outlined,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isHovering
                                          ? context.l10n.dropATaskHere
                                          : context.l10n.tasks2(0),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              )
                            : ReorderableListView.builder(
                                buildDefaultDragHandles: false,
                                padding: const EdgeInsets.all(8),
                                itemCount: column.tasks.length,
                                onReorder: dragEnabled
                                    ? (oldIndex, newIndex) =>
                                          _reorderTasksInColumn(
                                            swimlane: swimlane,
                                            column: column,
                                            oldIndex: oldIndex,
                                            newIndex: newIndex,
                                          )
                                    : (_, __) {},
                                itemBuilder: (context, index) {
                                  return _taskCard(
                                    column.tasks[index],
                                    sourceColumnId: column.id,
                                    sourceSwimlaneId: swimlane.id,
                                    dragEnabled: dragEnabled,
                                  );
                                },
                              );
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isHovering
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: isHovering
                                ? Border.all(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.6,
                                    ),
                                    width: 1.3,
                                  )
                                : null,
                          ),
                          child: body,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _boardOverview(KanboardBoard? board) {
    final theme = Theme.of(context);
    final accent = _projectAccent(theme);
    final compact = MediaQuery.sizeOf(context).width < 760;
    final taskCount = board == null ? 0 : _taskCount(board);
    final plannedCents = board == null ? 0 : _plannedExpenseCents(board);
    final spentCents = board == null ? 0 : _spentExpenseCents(board);
    final budgetCents = _expenseBudgetCents;
    final remainingCents = budgetCents == null
        ? null
        : (budgetCents - spentCents - plannedCents);
    final remainingValueColor = remainingCents == null
        ? null
        : remainingCents < 0
        ? theme.colorScheme.error
        : remainingCents > 0
        ? (theme.brightness == Brightness.dark
              ? Colors.green.shade300
              : Colors.green.shade700)
        : null;

    Widget statChip(
      IconData icon,
      String label,
      String value, {
      bool emphasized = false,
      Color? valueColor,
    }) {
      final chipColor = emphasized
          ? Color.alphaBlend(
              accent.withValues(alpha: 0.22),
              theme.colorScheme.surface,
            )
          : theme.colorScheme.surface.withValues(alpha: 0.78);
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 7 : 8,
        ),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: Color.alphaBlend(
              accent.withValues(alpha: emphasized ? 0.34 : 0.24),
              theme.colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: compact ? 15 : 16, color: accent),
            const SizedBox(width: 6),
            Text('$label: ', style: theme.textTheme.labelLarge),
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
    }

    final overviewActionStyle = FilledButton.styleFrom(
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
    );

    return Card(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.alphaBlend(
                accent.withValues(alpha: 0.24),
                theme.colorScheme.surfaceContainerHigh,
              ),
              theme.colorScheme.surfaceContainerHigh,
            ],
          ),
        ),
        padding: EdgeInsets.all(compact ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 8 : 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.44),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    style: overviewActionStyle,
                    onPressed: _openGroceryListEditor,
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: Text(context.l10n.groceryList),
                  ),
                  FilledButton.tonalIcon(
                    style: overviewActionStyle,
                    onPressed: _openExpensesPage,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(context.l10n.projectExpenses),
                  ),
                  FilledButton.tonalIcon(
                    style: overviewActionStyle,
                    onPressed: _openFinanceTablePage,
                    icon: const Icon(Icons.table_chart_outlined),
                    label: Text(context.l10n.financeTable),
                  ),
                  FilledButton.tonalIcon(
                    style: overviewActionStyle,
                    onPressed: _openSearch,
                    icon: const Icon(Icons.search),
                    label: Text(context.l10n.search),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 8 : 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.44),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  statChip(
                    Icons.task_alt_outlined,
                    context.l10n.tasks,
                    '$taskCount',
                  ),
                  statChip(
                    Icons.savings_outlined,
                    context.l10n.remaining,
                    remainingCents == null
                        ? context.l10n.noBudget
                        : _formatMoneyCents(remainingCents),
                    emphasized: true,
                    valueColor: remainingValueColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swimlaneSection(
    KanboardSwimlane swimlane, {
    bool stacked = false,
    required bool dragEnabled,
  }) {
    final theme = Theme.of(context);
    final accent = _projectAccent(theme);
    final spentHours = _swimlaneSpentHours(swimlane);
    return Card(
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: accent.withValues(alpha: 0.12),
                  child: Icon(Icons.lan_outlined, size: 15, color: accent),
                ),
                Text(
                  swimlane.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.l10n.columns2(swimlane.columns.length),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${context.l10n.spent}: ${_formatHoursLabel(spentHours)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (swimlane.columns.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  context
                      .l10n
                      .noColumnsConfiguredForThisSwimlaneUseStructureToAddColumns,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (stacked)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final column in swimlane.columns)
                    _columnCard(
                      swimlane,
                      column,
                      compact: true,
                      dragEnabled: dragEnabled,
                    ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final column in swimlane.columns)
                    _columnCard(swimlane, column, dragEnabled: dragEnabled),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBoardState() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.dashboard_outlined,
              size: 34,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.noBoardDataYet,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context
                  .l10n
                  .pullToRefreshOrOpenStructureToConfigureColumnsAndSwimlanes,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _openStructureEditor,
              icon: const Icon(Icons.view_column),
              label: Text(context.l10n.openStructure),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _boardContent(
    KanboardBoard? board, {
    required bool stackedColumns,
    required bool dragEnabled,
  }) {
    return <Widget>[
      _boardOverview(board),
      if (_isLoading)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(99)),
            child: LinearProgressIndicator(minHeight: 5),
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _statusBanner(
            icon: Icons.error_outline,
            text: _error!,
            isError: true,
            onRetry: _isLoading ? null : () => _loadBoard(fromRefresh: true),
          ),
        ),
      if (board == null && !_isLoading)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _emptyBoardState(),
        ),
      if (board != null)
        for (final swimlane in board.swimlanes)
          _swimlaneSection(
            swimlane,
            stacked: stackedColumns,
            dragEnabled: dragEnabled,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    final stackedColumns = MediaQuery.sizeOf(context).width < 900;
    const dragEnabled = true;
    final maxColumnsPerSwimlane = board == null || board.swimlanes.isEmpty
        ? 3
        : board.swimlanes
              .map((swimlane) => swimlane.columns.length)
              .reduce((a, b) => a > b ? a : b);
    final boardContentWidth = (maxColumnsPerSwimlane * 334 + 140)
        .clamp(1200, 7000)
        .toDouble();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.refreshBoard,
            onPressed: _isLoading ? null : () => _loadBoard(fromRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<_BoardOverflowAction>(
            icon: const Icon(Icons.more_vert),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.65),
            ),
            onSelected: _onOverflowActionSelected,
            itemBuilder: (context) => <PopupMenuEntry<_BoardOverflowAction>>[
              PopupMenuItem<_BoardOverflowAction>(
                value: _BoardOverflowAction.projects,
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.folder_open, size: 18),
                    const SizedBox(width: 10),
                    Text(context.l10n.projects),
                  ],
                ),
              ),
              PopupMenuItem<_BoardOverflowAction>(
                value: _BoardOverflowAction.structure,
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.view_column, size: 18),
                    const SizedBox(width: 10),
                    Text(context.l10n.structure),
                  ],
                ),
              ),
              PopupMenuItem<_BoardOverflowAction>(
                value: _BoardOverflowAction.search,
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.search, size: 18),
                    const SizedBox(width: 10),
                    Text(context.l10n.search),
                  ],
                ),
              ),
              PopupMenuItem<_BoardOverflowAction>(
                value: _BoardOverflowAction.financeTable,
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.table_chart_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text(context.l10n.financeTable),
                  ],
                ),
              ),
              PopupMenuItem<_BoardOverflowAction>(
                value: _BoardOverflowAction.aiChat,
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.smart_toy_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text(context.l10n.aiChat),
                  ],
                ),
              ),
            ],
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTaskEditor(),
        icon: const Icon(Icons.add_task),
        label: Text(context.l10n.newTask),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadBoard(fromRefresh: true),
        child: stackedColumns
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 96),
                children: _boardContent(
                  board,
                  stackedColumns: stackedColumns,
                  dragEnabled: dragEnabled,
                ),
              )
            : BidirectionalScrollView(
                alwaysScrollable: true,
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 96),
                contentWidth: boardContentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _boardContent(
                    board,
                    stackedColumns: stackedColumns,
                    dragEnabled: dragEnabled,
                  ),
                ),
              ),
      ),
    );
  }
}

class _TaskSearchSheet extends ConsumerStatefulWidget {
  const _TaskSearchSheet({required this.projectId});

  final int projectId;

  @override
  ConsumerState<_TaskSearchSheet> createState() => _TaskSearchSheetState();
}

class _TaskSearchSheetState extends ConsumerState<_TaskSearchSheet> {
  final _queryController = TextEditingController();
  bool _isSearching = false;
  String? _error;
  List<KanboardTask> _results = const <KanboardTask>[];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const <KanboardTask>[];
        _error = context.l10n.enterASearchQuery;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final results = await api.searchTasks(
        projectId: widget.projectId,
        query: query,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.taskSearch,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context
                .l10n
                .useKanboardQuerySyntaxExampleStatusOpenAssigneeMeDueTomorrow,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: InputDecoration(
                    labelText: context.l10n.query,
                    hintText: context.l10n.queryExampleStatusOpenCategoryBug,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isSearching ? null : _search,
                icon: const Icon(Icons.search),
                label: Text(context.l10n.search),
              ),
            ],
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      context.l10n.noResultsYet,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final task = _results[index];
                      return ListTile(
                        onTap: () => Navigator.of(context).pop(task.id),
                        title: Text(
                          task.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            decoration: !task.isActive
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                        subtitle: Text(context.l10n.taskNumber(task.id)),
                        trailing: const Icon(Icons.chevron_right),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.close),
            ),
          ),
        ],
      ),
    );
  }
}
