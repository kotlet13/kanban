import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/bidirectional_scroll_view.dart';
import '../../widgets/theme_mode_menu_button.dart';

class BoardStructurePage extends ConsumerStatefulWidget {
  const BoardStructurePage({
    required this.projectId,
    required this.projectName,
    super.key,
  });

  final int projectId;
  final String projectName;

  @override
  ConsumerState<BoardStructurePage> createState() => _BoardStructurePageState();
}

class _BoardStructurePageState extends ConsumerState<BoardStructurePage> {
  bool _isLoading = false;
  String? _error;
  List<KanboardColumn> _columns = const <KanboardColumn>[];
  List<KanboardSwimlane> _swimlanes = const <KanboardSwimlane>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final columns = await api.getColumns(widget.projectId);
      final swimlanes = await api.getAllSwimlanes(widget.projectId);
      if (!mounted) return;
      setState(() {
        _columns = columns;
        _swimlanes = swimlanes;
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

  Future<void> _createOrEditColumn({KanboardColumn? column}) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final titleController = TextEditingController(text: column?.title ?? '');
    final limitController =
        TextEditingController(text: column == null ? '' : '${column.taskLimit}');
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(column == null ? 'Add column' : 'Edit column'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitController,
                decoration: const InputDecoration(labelText: 'Task limit'),
                keyboardType: TextInputType.number,
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
    );
    if (confirmed != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) return;
    final limit = int.tryParse(limitController.text.trim());

    try {
      if (column == null) {
        await api.addColumn(
          projectId: widget.projectId,
          title: title,
          taskLimit: limit,
        );
      } else {
        await api.updateColumn(columnId: column.id, title: title, taskLimit: limit);
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Column save failed: $error')));
    }
  }

  Future<void> _deleteColumn(KanboardColumn column) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Delete column?'),
        content: Text('Delete column "${column.title}"?'),
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
      await api.removeColumn(column.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Column deletion failed: $error')));
    }
  }

  Future<void> _createOrEditSwimlane({KanboardSwimlane? swimlane}) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final nameController = TextEditingController(text: swimlane?.name ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(swimlane == null ? 'Add swimlane' : 'Edit swimlane'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Name'),
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
    );
    if (confirmed != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) return;

    try {
      if (swimlane == null) {
        await api.addSwimlane(projectId: widget.projectId, name: name);
      } else {
        await api.updateSwimlane(
          projectId: widget.projectId,
          swimlaneId: swimlane.id,
          name: name,
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Swimlane save failed: $error')));
    }
  }

  Future<void> _deleteSwimlane(KanboardSwimlane swimlane) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Delete swimlane?'),
        content: Text('Delete swimlane "${swimlane.name}"?'),
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
      await api.removeSwimlane(
        projectId: widget.projectId,
        swimlaneId: swimlane.id,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Swimlane deletion failed: $error')),
      );
    }
  }

  Future<void> _reorderColumns(int oldIndex, int newIndex) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final list = List<KanboardColumn>.from(_columns);
    if (oldIndex < newIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);

    setState(() => _columns = list);
    for (var i = 0; i < list.length; i++) {
      await api.changeColumnPosition(
        projectId: widget.projectId,
        columnId: list[i].id,
        position: i + 1,
      );
    }
    await _load();
  }

  Future<void> _reorderSwimlanes(int oldIndex, int newIndex) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final list = List<KanboardSwimlane>.from(_swimlanes);
    if (oldIndex < newIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);

    setState(() => _swimlanes = list);
    for (var i = 0; i < list.length; i++) {
      await api.changeSwimlanePosition(
        projectId: widget.projectId,
        swimlaneId: list[i].id,
        position: i + 1,
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.projectName} structure'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Projects',
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: BidirectionalScrollView(
          alwaysScrollable: true,
          padding: const EdgeInsets.all(12),
          contentWidth: 1100,
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
            Row(
              children: <Widget>[
                Text(
                  'Columns',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _createOrEditColumn,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            ReorderableListView.builder(
              key: const PageStorageKey<String>('columns'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _columns.length,
              onReorder: _reorderColumns,
              itemBuilder: (context, index) {
                final c = _columns[index];
                return Card(
                  key: ValueKey('column-${c.id}'),
                  child: ListTile(
                    title: Text(c.title),
                    subtitle: Text('Position ${c.position} · Limit ${c.taskLimit}'),
                    trailing: Wrap(
                      spacing: 8,
                      children: <Widget>[
                        IconButton(
                          onPressed: () => _createOrEditColumn(column: c),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          onPressed: () => _deleteColumn(c),
                          icon: const Icon(Icons.delete),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Text(
                  'Swimlanes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _createOrEditSwimlane,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            ReorderableListView.builder(
              key: const PageStorageKey<String>('swimlanes'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _swimlanes.length,
              onReorder: _reorderSwimlanes,
              itemBuilder: (context, index) {
                final s = _swimlanes[index];
                return Card(
                  key: ValueKey('swimlane-${s.id}'),
                  child: ListTile(
                    title: Text(s.name),
                    subtitle: Text('Position ${s.position}'),
                    trailing: Wrap(
                      spacing: 8,
                      children: <Widget>[
                        IconButton(
                          onPressed: () => _createOrEditSwimlane(swimlane: s),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          onPressed: () => _deleteSwimlane(s),
                          icon: const Icon(Icons.delete),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            ],
          ),
        ),
      ),
    );
  }
}
