import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/bidirectional_scroll_view.dart';
import '../../widgets/theme_mode_menu_button.dart';
import '../tasks/task_details_page.dart';

class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({
    required this.projectId,
    required this.projectName,
    super.key,
  });

  final int projectId;
  final String projectName;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  bool _isLoading = false;
  String? _error;
  KanboardBoard? _board;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoard());
  }

  Future<void> _loadBoard({bool fromRefresh = false}) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) {
      setState(() {
        _error = 'No active session. Connect first.';
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
      final board = await api.getBoard(widget.projectId);
      final cache = await ref.read(cacheStoreProvider.future);
      await cache.saveBoard(board);
      if (!mounted) return;
      setState(() {
        _board = board;
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

  Future<void> _openTaskEditor({KanboardTask? task, int? columnId, int? swimlaneId}) async {
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
        title: const Text('Delete task?'),
        content: Text('Delete "${task.title}" permanently?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
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
      ).showSnackBar(SnackBar(content: Text('Delete failed: $error')));
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
      ).showSnackBar(SnackBar(content: Text('Move failed: $error')));
    }
  }

  Widget _taskCard(KanboardTask task) {
    return Draggable<KanboardTask>(
      data: task,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(task.title, maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: Card(
          child: ListTile(
            title: Text(task.title),
            subtitle: const Text('Moving...'),
          ),
        ),
      ),
      child: Card(
        child: ListTile(
          title: Text(task.title),
          subtitle: task.description == null || task.description!.isEmpty
              ? null
              : Text(
                  task.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => _openTaskEditor(task: task),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                _openTaskEditor(task: task);
              } else if (value == 'delete') {
                _deleteTask(task);
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
              PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _columnCard(KanboardSwimlane swimlane, KanboardColumn column) {
    return Container(
      width: 320,
      height: 420,
      margin: const EdgeInsets.only(right: 12),
      child: DragTarget<KanboardTask>(
        onAcceptWithDetails: (details) =>
            _moveTask(details.data, column, swimlane.id),
        builder: (context, candidateData, rejectedData) {
          final isHighlighted = candidateData.isNotEmpty;
          return Card(
            color: isHighlighted
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: Column(
              children: <Widget>[
                ListTile(
                  title: Text(column.title),
                  subtitle: Text('${column.tasks.length} task(s)'),
                  trailing: IconButton(
                    tooltip: 'New task in ${column.title}',
                    onPressed: () => _openTaskEditor(
                      columnId: column.id,
                      swimlaneId: swimlane.id,
                    ),
                    icon: const Icon(Icons.add),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: column.tasks.isEmpty
                      ? const Center(child: Text('Drop a task here'))
                      : ListView.builder(
                          itemCount: column.tasks.length,
                          itemBuilder: (context, index) {
                            return _taskCard(column.tasks[index]);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    final maxColumnsPerSwimlane = board == null || board.swimlanes.isEmpty
        ? 3
        : board.swimlanes
            .map((s) => s.columns.length)
            .reduce((a, b) => a > b ? a : b);
    final boardContentWidth =
        (maxColumnsPerSwimlane * 332 + 120).clamp(1200, 7000).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName),
        actions: <Widget>[
          IconButton(
            tooltip: 'Projects',
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            tooltip: 'Board structure',
            onPressed: () {
              context.push(
                '/board/${widget.projectId}/structure?projectName=${Uri.encodeComponent(widget.projectName)}',
              ).then((_) => _loadBoard(fromRefresh: true));
            },
            icon: const Icon(Icons.view_column),
          ),
          IconButton(
            tooltip: 'Refresh board',
            onPressed: _isLoading ? null : () => _loadBoard(fromRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTaskEditor(),
        icon: const Icon(Icons.add_task),
        label: const Text('Task'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadBoard(fromRefresh: true),
        child: BidirectionalScrollView(
          alwaysScrollable: true,
          padding: const EdgeInsets.all(12),
          contentWidth: boardContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
            if (_isLoading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (board == null && !_isLoading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No board data yet. Pull to refresh.'),
              ),
            if (board != null)
              for (final swimlane in board.swimlanes) ...<Widget>[
                Card(
                  margin: const EdgeInsets.only(top: 8, bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          swimlane.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            for (final column in swimlane.columns)
                              _columnCard(swimlane, column),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
