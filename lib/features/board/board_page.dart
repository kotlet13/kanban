import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/bidirectional_scroll_view.dart';
import '../../widgets/theme_mode_menu_button.dart';
import '../tasks/task_details_page.dart';

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
  bool _isCompactDragLocked = true;
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

  Future<void> _moveTask(
    KanboardTask task,
    KanboardColumn targetColumn,
    int targetSwimlaneId,
  ) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    try {
      await api.moveTaskPosition(
        projectId: widget.projectId,
        taskId: task.id,
        columnId: targetColumn.id,
        position: targetColumn.tasks.length + 1,
        swimlaneId: targetSwimlaneId,
      );
      await _loadBoard(fromRefresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.moveFailed(error))));
    }
  }

  int? _parseMoneyToCents(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null || value < 0) return null;
    return (value * 100).round();
  }

  String _formatCents(int cents) {
    return (cents / 100).toStringAsFixed(2);
  }

  Future<void> _openExpenseSettings() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final currencyController = TextEditingController(
      text: (_expenseCurrencyCode ?? '').trim(),
    );
    final budgetController = TextEditingController(
      text: _expenseBudgetCents == null
          ? ''
          : _formatCents(_expenseBudgetCents!),
    );
    String? validationError;

    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(context.l10n.projectExpenses),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: currencyController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  decoration: InputDecoration(
                    labelText: context.l10n.currencyCode,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: budgetController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10n.budget,
                    hintText: context.l10n.leaveEmptyForNoBudget,
                  ),
                ),
                if (validationError != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final currency = currencyController.text.trim().toUpperCase();
                if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
                  setLocalState(() {
                    validationError = context.l10n.currencyMustBeA3LetterCode;
                  });
                  return;
                }
                final budgetText = budgetController.text.trim();
                final budgetCents = _parseMoneyToCents(budgetText);
                if (budgetText.isNotEmpty && budgetCents == null) {
                  setLocalState(() {
                    validationError = context.l10n.budgetMustBeAPositiveNumber;
                  });
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;
    final currency = currencyController.text.trim().toUpperCase();
    final budgetText = budgetController.text.trim();
    final budgetCents = budgetText.isEmpty
        ? null
        : _parseMoneyToCents(budgetText);
    try {
      await api.saveProjectExpenseSettings(
        projectId: widget.projectId,
        currency: currency,
        budgetCents: budgetCents,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.expenseSettingsSaved)),
      );
      await _loadBoard(fromRefresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.expenseSettingsFailed(error))),
      );
    }
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

  int _plannedExpenseCents(KanboardBoard board) {
    var total = 0;
    for (final swimlane in board.swimlanes) {
      for (final column in swimlane.columns) {
        for (final task in column.tasks) {
          if (task.score > 0) {
            total += task.score;
          }
        }
      }
    }
    return total;
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

  Widget _taskCard(KanboardTask task, {required bool dragEnabled}) {
    final theme = Theme.of(context);
    final accent = _projectAccent(theme);
    final taskCardBody = Card(
      child: InkWell(
        onTap: () => _openTaskEditor(task: task),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 6,
                height: 36,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (task.description != null &&
                        task.description!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        task.description!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      context.l10n.taskNumber(task.id),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
            ],
          ),
        ),
      ),
    );

    if (!dragEnabled) {
      return taskCardBody;
    }

    return Draggable<KanboardTask>(
      data: task,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                task.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                const Icon(Icons.open_with_rounded, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: taskCardBody,
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
      child: DragTarget<KanboardTask>(
        onAcceptWithDetails: dragEnabled
            ? (details) => _moveTask(details.data, column, swimlane.id)
            : null,
        builder: (context, candidateData, rejectedData) {
          final theme = Theme.of(context);
          final accent = _projectAccent(theme);
          final isHighlighted = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: compact
                ? const EdgeInsets.only(bottom: 10)
                : const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isHighlighted
                    ? accent
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: isHighlighted ? 2 : 1,
              ),
            ),
            child: Card(
              margin: EdgeInsets.zero,
              color: isHighlighted
                  ? Color.alphaBlend(
                      accent.withValues(alpha: 0.18),
                      theme.colorScheme.surfaceContainerHigh,
                    )
                  : null,
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
                    child: column.tasks.isEmpty
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
                                  dragEnabled
                                      ? context.l10n.dropATaskHere
                                      : context.l10n.unlockDragToMoveTasks,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: column.tasks.length,
                            itemBuilder: (context, index) {
                              return _taskCard(
                                column.tasks[index],
                                dragEnabled: dragEnabled,
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

  Widget _boardOverview(
    KanboardBoard? board, {
    required bool showCompactDragLock,
    required bool dragEnabled,
  }) {
    final theme = Theme.of(context);
    final accent = _projectAccent(theme);
    final swimlaneCount = board?.swimlanes.length ?? 0;
    final columnCount = board == null
        ? 0
        : board.swimlanes.fold<int>(
            0,
            (sum, swimlane) => sum + swimlane.columns.length,
          );
    final taskCount = board == null ? 0 : _taskCount(board);
    final plannedCents = board == null ? 0 : _plannedExpenseCents(board);
    final spentCents = board == null ? 0 : _spentExpenseCents(board);
    final budgetCents = _expenseBudgetCents;
    final remainingCents = budgetCents == null ? null : (budgetCents - spentCents);

    Widget statChip(IconData icon, String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: Color.alphaBlend(
              accent.withValues(alpha: 0.28),
              theme.colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text('$label: ', style: theme.textTheme.labelLarge),
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 10,
              spacing: 10,
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.projectName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        showCompactDragLock
                            ? dragEnabled
                                  ? context
                                        .l10n
                                        .taskDragIsUnlockedMoveTasksCarefullyWhileScrollingOrTapLockToPreventAccidentalMoves
                                  : context
                                        .l10n
                                        .taskDragIsLockedSoYouCanScrollSafelyTapUnlockInTheTopBarWhenYouWantToMoveTasks
                            : context
                                  .l10n
                                  .dragAndDropTasksAcrossSwimlanesAndColumnsUseSearchForAdvancedQuerySyntax,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: _openGroceryListEditor,
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: Text(context.l10n.groceryList),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _openExpenseSettings,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(context.l10n.projectExpenses),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _openSearch,
                      icon: const Icon(Icons.search),
                      label: Text(context.l10n.search),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _openStructureEditor,
                      icon: const Icon(Icons.view_column),
                      label: Text(context.l10n.structure),
                    ),
                    FilledButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _loadBoard(fromRefresh: true),
                      icon: const Icon(Icons.refresh),
                      label: Text(context.l10n.refresh),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                statChip(
                  Icons.horizontal_split,
                  context.l10n.swimlanes,
                  '$swimlaneCount',
                ),
                statChip(
                  Icons.view_column_outlined,
                  context.l10n.columns,
                  '$columnCount',
                ),
                statChip(
                  Icons.task_alt_outlined,
                  context.l10n.tasks,
                  '$taskCount',
                ),
                statChip(
                  Icons.payments_outlined,
                  context.l10n.planned,
                  _formatMoneyCents(plannedCents),
                ),
                statChip(
                  Icons.check_circle_outline,
                  context.l10n.spent,
                  _formatMoneyCents(spentCents),
                ),
                statChip(
                  Icons.account_balance_wallet_outlined,
                  context.l10n.budget,
                  budgetCents == null
                      ? context.l10n.noBudget
                      : _formatMoneyCents(budgetCents),
                ),
                statChip(
                  Icons.savings_outlined,
                  context.l10n.remaining,
                  remainingCents == null
                      ? context.l10n.noBudget
                      : _formatMoneyCents(remainingCents),
                ),
              ],
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
      _boardOverview(
        board,
        showCompactDragLock: stackedColumns,
        dragEnabled: dragEnabled,
      ),
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
    final dragEnabled = !stackedColumns || !_isCompactDragLocked;
    final maxColumnsPerSwimlane = board == null || board.swimlanes.isEmpty
        ? 3
        : board.swimlanes
              .map((swimlane) => swimlane.columns.length)
              .reduce((a, b) => a > b ? a : b);
    final boardContentWidth = (maxColumnsPerSwimlane * 334 + 140)
        .clamp(1200, 7000)
        .toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.projects,
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            tooltip: context.l10n.boardStructure,
            onPressed: _openStructureEditor,
            icon: const Icon(Icons.view_column),
          ),
          IconButton(
            tooltip: context.l10n.searchTasks,
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
          ),
          if (stackedColumns)
            IconButton(
              tooltip: dragEnabled
                  ? context.l10n.lockTaskDrag
                  : context.l10n.unlockTaskDrag,
              onPressed: () {
                setState(() {
                  _isCompactDragLocked = !_isCompactDragLocked;
                });
              },
              icon: Icon(dragEnabled ? Icons.lock_open : Icons.lock),
            ),
          IconButton(
            tooltip: context.l10n.refreshBoard,
            onPressed: _isLoading ? null : () => _loadBoard(fromRefresh: true),
            icon: const Icon(Icons.refresh),
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
                        title: Text(task.title),
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
