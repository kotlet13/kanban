import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
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
    final limitController = TextEditingController(
      text: column == null ? '' : '${column.taskLimit}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(
          column == null ? context.l10n.addColumn : context.l10n.editColumn,
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: context.l10n.title),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitController,
                decoration: InputDecoration(labelText: context.l10n.taskLimit),
                keyboardType: TextInputType.number,
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
        await api.updateColumn(
          columnId: column.id,
          title: title,
          taskLimit: limit,
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.columnSaveFailed(error))),
      );
    }
  }

  Future<void> _deleteColumn(KanboardColumn column) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteColumn),
        content: Text(context.l10n.deleteColumn2(column.title)),
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
      await api.removeColumn(column.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.columnDeletionFailed(error))),
      );
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
        title: Text(
          swimlane == null
              ? context.l10n.addSwimlane
              : context.l10n.editSwimlane,
        ),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: nameController,
            decoration: InputDecoration(labelText: context.l10n.name),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.swimlaneSaveFailed(error))),
      );
    }
  }

  Future<void> _deleteSwimlane(KanboardSwimlane swimlane) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteSwimlane),
        content: Text(context.l10n.deleteSwimlane2(swimlane.name)),
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
      await api.removeSwimlane(
        projectId: widget.projectId,
        swimlaneId: swimlane.id,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.swimlaneDeletionFailed(error))),
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

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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

  Widget _headerCard() {
    final theme = Theme.of(context);
    return Card(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surfaceContainerHigh,
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.boardStructure2(widget.projectName),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.dragRowsToReorderChangesAreSavedImmediately,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _statChip(
                  icon: Icons.view_column_outlined,
                  label: context.l10n.columns,
                  value: '${_columns.length}',
                ),
                _statChip(
                  icon: Icons.horizontal_split,
                  label: context.l10n.swimlanes,
                  value: '${_swimlanes.length}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onAdd,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.12,
                  ),
                  child: Icon(icon, size: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.add),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _emptyListState(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _rowShell({
    required Key key,
    required int index,
    required String title,
    required String subtitle,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: <Widget>[
          ReorderableDragStartListener(
            index: index,
            child: Container(
              width: 42,
              alignment: Alignment.center,
              child: Icon(
                Icons.drag_indicator,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            width: 4,
            height: 46,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: accent,
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
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.edit,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: context.l10n.delete,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _columnsList() {
    if (_columns.isEmpty) {
      return _emptyListState(context.l10n.noColumnsYetAddOne);
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _columns.length,
      onReorder: _reorderColumns,
      itemBuilder: (context, index) {
        final column = _columns[index];
        return _rowShell(
          key: ValueKey('column-${column.id}'),
          index: index,
          title: column.title,
          subtitle: context.l10n.positionLimit(
            column.position,
            column.taskLimit,
          ),
          onEdit: () => _createOrEditColumn(column: column),
          onDelete: () => _deleteColumn(column),
          accent: Theme.of(context).colorScheme.primary,
        );
      },
    );
  }

  Widget _swimlanesList() {
    if (_swimlanes.isEmpty) {
      return _emptyListState(context.l10n.noSwimlanesYetAddOne);
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _swimlanes.length,
      onReorder: _reorderSwimlanes,
      itemBuilder: (context, index) {
        final swimlane = _swimlanes[index];
        return _rowShell(
          key: ValueKey('swimlane-${swimlane.id}'),
          index: index,
          title: swimlane.name,
          subtitle: context.l10n.position(swimlane.position),
          onEdit: () => _createOrEditSwimlane(swimlane: swimlane),
          onDelete: () => _deleteSwimlane(swimlane),
          accent: Theme.of(context).colorScheme.tertiary,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.structure2(widget.projectName)),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.projects,
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1120;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
              children: <Widget>[
                _headerCard(),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                      child: LinearProgressIndicator(minHeight: 5),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _panel(
                          icon: Icons.view_column_outlined,
                          title: context.l10n.columns,
                          subtitle: context.l10n.horizontalStructureOfTheBoard,
                          onAdd: _createOrEditColumn,
                          child: _columnsList(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _panel(
                          icon: Icons.horizontal_split,
                          title: context.l10n.swimlanes,
                          subtitle: context.l10n.verticalWorkGrouping,
                          onAdd: _createOrEditSwimlane,
                          child: _swimlanesList(),
                        ),
                      ),
                    ],
                  )
                else ...<Widget>[
                  _panel(
                    icon: Icons.view_column_outlined,
                    title: context.l10n.columns,
                    subtitle: context.l10n.horizontalStructureOfTheBoard,
                    onAdd: _createOrEditColumn,
                    child: _columnsList(),
                  ),
                  const SizedBox(height: 12),
                  _panel(
                    icon: Icons.horizontal_split,
                    title: context.l10n.swimlanes,
                    subtitle: context.l10n.verticalWorkGrouping,
                    onAdd: _createOrEditSwimlane,
                    child: _swimlanesList(),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
