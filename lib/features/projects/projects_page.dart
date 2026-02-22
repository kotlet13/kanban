import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../kanboard/kanboard_api.dart';
import '../../l10n/l10n.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/theme_mode_menu_button.dart';

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  static const List<Color> _projectColorPalette = <Color>[
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFF59E0B),
    Color(0xFF84CC16),
    Color(0xFF10B981),
    Color(0xFF14B8A6),
    Color(0xFF06B6D4),
    Color(0xFF3B82F6),
    Color(0xFF6366F1),
    Color(0xFF8B5CF6),
    Color(0xFFD946EF),
    Color(0xFFEC4899),
    Color(0xFF6B7280),
  ];

  bool _isLoading = false;
  String? _error;
  List<KanboardProject> _projects = const <KanboardProject>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProjects());
  }

  Future<void> _loadProjects({bool fromRefresh = false}) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) {
      setState(() {
        _error = context.l10n.noActiveSessionConnectFirst;
      });
      return;
    }

    if (!fromRefresh) {
      final cache = await ref.read(cacheStoreProvider.future);
      final cachedProjects = cache.readProjects();
      if (cachedProjects.isNotEmpty && mounted) {
        setState(() {
          _projects = cachedProjects;
        });
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final projects = await api.getMyProjects();
      final cache = await ref.read(cacheStoreProvider.future);
      await cache.saveProjects(projects);
      if (!mounted) return;
      setState(() {
        _projects = projects;
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

  Future<void> _createOrEditProject({KanboardProject? project}) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;

    final nameController = TextEditingController(text: project?.name ?? '');
    final descriptionController = TextEditingController(
      text: project?.description ?? '',
    );
    String? selectedColorHex = _normalizeColorHex(project?.uiColorHex);
    var isFinanceProject =
        (project?.uiProjectType ?? '').trim().toLowerCase() ==
        KanboardApi.financeProjectTypeValue;

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            project == null
                ? context.l10n.createProject
                : context.l10n.editProject,
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: context.l10n.projectName,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: context.l10n.description,
                    ),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.l10n.projectColorSyncedViaMetadata,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final color in _projectColorPalette)
                        InkWell(
                          borderRadius: BorderRadius.circular(99),
                          onTap: () {
                            setLocalState(() {
                              selectedColorHex = _toHexColor(color);
                            });
                          },
                          child: _colorDot(
                            color: color,
                            selected: selectedColorHex == _toHexColor(color),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: () {
                          setLocalState(() {
                            selectedColorHex = null;
                          });
                        },
                        icon: const Icon(Icons.clear),
                        label: Text(context.l10n.noColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: isFinanceProject,
                    onChanged: (value) {
                      setLocalState(() {
                        isFinanceProject = value;
                      });
                    },
                    title: Text(context.l10n.financeProject),
                    subtitle: Text(context.l10n.financeProjectDescription),
                  ),
                ],
              ),
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

    if (confirmed != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    String? defaultsError;

    try {
      if (project == null) {
        final projectId = await api.createProject(
          name: name,
          description: descriptionController.text.trim(),
        );
        if (projectId == null || projectId <= 0) {
          throw Exception('Project was not created.');
        }
        await api.saveProjectColorHex(
          projectId: projectId,
          colorHex: selectedColorHex,
        );
        await api.saveProjectType(
          projectId: projectId,
          projectType: isFinanceProject
              ? KanboardApi.financeProjectTypeValue
              : null,
        );
        try {
          await _applyProjectDefaults(api: api, projectId: projectId);
        } catch (error) {
          defaultsError = '$error';
        }
      } else {
        await api.updateProject(
          projectId: project.id,
          name: name,
          description: descriptionController.text.trim(),
        );
        await api.saveProjectColorHex(
          projectId: project.id,
          colorHex: selectedColorHex,
        );
        await api.saveProjectType(
          projectId: project.id,
          projectType: isFinanceProject
              ? KanboardApi.financeProjectTypeValue
              : null,
        );
      }
      await _loadProjects(fromRefresh: true);
      if (defaultsError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.projectCreatedButDefaultsFailedToApply(
                defaultsError,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.projectSaveFailed(error))),
      );
    }
  }

  Future<void> _applyProjectDefaults({
    required KanboardApi api,
    required int projectId,
  }) async {
    final defaults = await ref.read(projectDefaultsStoreProvider).read();
    if (!defaults.hasAnyValue) return;

    if (defaults.columnNames.isNotEmpty) {
      final currentColumns = await api.getColumns(projectId);
      final overlap = currentColumns.length < defaults.columnNames.length
          ? currentColumns.length
          : defaults.columnNames.length;

      for (var index = 0; index < overlap; index++) {
        final column = currentColumns[index];
        await api.updateColumn(
          columnId: column.id,
          title: defaults.columnNames[index],
          taskLimit: column.taskLimit,
        );
      }

      if (currentColumns.length > defaults.columnNames.length) {
        for (
          var index = defaults.columnNames.length;
          index < currentColumns.length;
          index++
        ) {
          await api.removeColumn(currentColumns[index].id);
        }
      } else if (defaults.columnNames.length > currentColumns.length) {
        for (
          var index = currentColumns.length;
          index < defaults.columnNames.length;
          index++
        ) {
          await api.addColumn(
            projectId: projectId,
            title: defaults.columnNames[index],
          );
        }
      }
    }

    final swimlaneName = defaults.defaultSwimlaneName?.trim();
    if (swimlaneName == null || swimlaneName.isEmpty) return;

    final swimlanes = await api.getAllSwimlanes(projectId);
    final hasMatch = swimlanes.any(
      (lane) => lane.name.trim().toLowerCase() == swimlaneName.toLowerCase(),
    );
    if (hasMatch) return;

    if (swimlanes.length == 1) {
      await api.updateSwimlane(
        projectId: projectId,
        swimlaneId: swimlanes.first.id,
        name: swimlaneName,
      );
      return;
    }

    await api.addSwimlane(projectId: projectId, name: swimlaneName);
  }

  Future<void> _deleteProject(KanboardProject project) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteProject2),
        content: Text(context.l10n.thisWillRemovePermanently(project.name)),
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
      await api.removeProject(project.id);
      await _loadProjects(fromRefresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.projectDeletionFailed(error))),
      );
    }
  }

  Future<void> _openProjectAttachments(KanboardProject project) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _ProjectFilesDialog(project: project),
    );
  }

  Future<void> _openProjectPermissions(KanboardProject project) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _ProjectPermissionsDialog(project: project),
    );
  }

  Future<void> _logout() async {
    await ref.read(credentialsStoreProvider).clear();
    ref.read(sessionCredentialsProvider.notifier).state = null;
    if (!mounted) return;
    context.go('/connect');
  }

  @override
  Widget build(BuildContext context) {
    final hasSession = ref.watch(kanboardApiProvider) != null;
    final activeProjects = _projects
        .where((project) => project.isActive)
        .length;
    final archivedProjects = (_projects.length - activeProjects).clamp(
      0,
      _projects.length,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.projects),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.projectDefaults,
            onPressed: () => context.push('/settings/project-defaults'),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: context.l10n.aiSettings,
            onPressed: () => context.push('/settings/ai'),
            icon: const Icon(Icons.smart_toy_outlined),
          ),
          IconButton(
            tooltip: context.l10n.connectionSettings,
            onPressed: () => context.push('/connect'),
            icon: const Icon(Icons.settings_ethernet),
          ),
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: _isLoading
                ? null
                : () => _loadProjects(fromRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
          const ThemeModeMenuButton(),
          IconButton(
            tooltip: context.l10n.logout,
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: hasSession ? () => _createOrEditProject() : null,
        icon: const Icon(Icons.add),
        label: Text(context.l10n.newProject),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadProjects(fromRefresh: true),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 1280
                ? 3
                : width >= 820
                ? 2
                : 1;

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                  sliver: SliverToBoxAdapter(
                    child: _summaryCard(
                      hasSession: hasSession,
                      activeProjects: activeProjects,
                      archivedProjects: archivedProjects,
                    ),
                  ),
                ),
                if (_isLoading)
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverToBoxAdapter(
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(99)),
                        child: LinearProgressIndicator(minHeight: 5),
                      ),
                    ),
                  ),
                if (_error != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    sliver: SliverToBoxAdapter(
                      child: _statusCard(
                        icon: Icons.error_outline,
                        title: context.l10n.couldNotLoadProjects,
                        subtitle: _error!,
                        isError: true,
                        action: FilledButton.tonalIcon(
                          onPressed: _isLoading
                              ? null
                              : () => _loadProjects(fromRefresh: true),
                          icon: const Icon(Icons.refresh),
                          label: Text(context.l10n.retry),
                        ),
                      ),
                    ),
                  ),
                if (!hasSession)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    sliver: SliverToBoxAdapter(
                      child: _statusCard(
                        icon: Icons.link_off,
                        title: context.l10n.noActiveSession,
                        subtitle: context.l10n.connectToKanboardToContinue,
                        action: FilledButton.icon(
                          onPressed: () => context.push('/connect'),
                          icon: const Icon(Icons.settings_ethernet),
                          label: Text(context.l10n.connect),
                        ),
                      ),
                    ),
                  ),
                if (hasSession && _projects.isEmpty && !_isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: _EmptyProjectsState(),
                      ),
                    ),
                  ),
                if (hasSession && _projects.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 110),
                    sliver: crossAxisCount == 1
                        ? SliverList.separated(
                            itemBuilder: (context, index) {
                              final project = _projects[index];
                              return _projectCard(project);
                            },
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemCount: _projects.length,
                          )
                        : SliverGrid.builder(
                            itemCount: _projects.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  mainAxisExtent: width >= 1200 ? 252 : 262,
                                ),
                            itemBuilder: (context, index) =>
                                _projectCard(_projects[index]),
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openProjectBoard(KanboardProject project) {
    final query = <String, String>{'projectName': project.name};
    final colorHex = _normalizeColorHex(project.uiColorHex);
    if (colorHex != null) {
      query['projectColor'] = colorHex;
    }
    final projectType = (project.uiProjectType ?? '').trim().toLowerCase();
    final path = projectType == KanboardApi.financeProjectTypeValue
        ? '/board/${project.id}/finance-table'
        : '/board/${project.id}';
    final uri = Uri(path: path, queryParameters: query);
    context.push(uri.toString());
  }

  Widget _projectCard(KanboardProject project) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = _parseHexColor(project.uiColorHex) ?? colorScheme.primary;
    final isFinanceProject =
        (project.uiProjectType ?? '').trim().toLowerCase() ==
        KanboardApi.financeProjectTypeValue;
    final hasDescription =
        project.description != null && project.description!.trim().isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProjectBoard(project),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.alphaBlend(
                  accent.withValues(alpha: 0.20),
                  colorScheme.surface,
                ),
                colorScheme.surface,
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _projectBadge(project),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _metaPill(
                          icon: project.isActive
                              ? Icons.check_circle_outline
                              : Icons.pause_circle_outline,
                          text: project.isActive
                              ? context.l10n.active
                              : context.l10n.inactive,
                          foreground: project.isActive
                              ? Colors.green.shade800
                              : theme.colorScheme.onSurfaceVariant,
                          background: project.isActive
                              ? Colors.green.withValues(alpha: 0.12)
                              : theme.colorScheme.surfaceContainerHighest,
                        ),
                        _metaPill(
                          icon: Icons.badge_outlined,
                          text: 'ID ${project.id}',
                          foreground: theme.colorScheme.onSurfaceVariant,
                          background: theme.colorScheme.surfaceContainerHighest,
                        ),
                        if (isFinanceProject)
                          _metaPill(
                            icon: Icons.table_chart_outlined,
                            text: context.l10n.financeTable,
                            foreground: Colors.indigo.shade800,
                            background: Colors.indigo.withValues(alpha: 0.14),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                project.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                ),
              ),
              if (project.identifier != null &&
                  project.identifier!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  project.identifier!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                hasDescription
                    ? project.description!.trim()
                    : context.l10n.noDescriptionYetOpenTheProjectToAddContext,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hasDescription
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontStyle: hasDescription
                      ? FontStyle.normal
                      : FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: () => _openProjectBoard(project),
                    icon: const Icon(Icons.view_kanban_outlined, size: 18),
                    label: Text(context.l10n.openBoard),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: context.l10n.projectAttachments,
                    onPressed: () => _openProjectAttachments(project),
                    icon: const Icon(Icons.attach_file),
                  ),
                  IconButton(
                    tooltip: 'Project permissions',
                    onPressed: () => _openProjectPermissions(project),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                  ),
                  IconButton(
                    tooltip: context.l10n.editProject,
                    onPressed: () => _createOrEditProject(project: project),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: context.l10n.deleteProject,
                    onPressed: () => _deleteProject(project),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard({
    required bool hasSession,
    required int activeProjects,
    required int archivedProjects,
  }) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.15,
                  ),
                  child: Icon(
                    Icons.dashboard_customize_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.l10n.projectsWorkspace,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasSession
                            ? context
                                  .l10n
                                  .trackOrganizeAndOpenYourKanboardProjects
                            : context
                                  .l10n
                                  .connectYourKanboardAccountToLoadProjectData,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _statsChip(
                  icon: Icons.folder_copy_outlined,
                  label: context.l10n.total,
                  value: '${_projects.length}',
                ),
                _statsChip(
                  icon: Icons.check_circle_outline,
                  label: context.l10n.active,
                  value: '$activeProjects',
                ),
                _statsChip(
                  icon: Icons.pause_circle_outline,
                  label: context.l10n.inactive,
                  value: '$archivedProjects',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
    bool isError = false,
  }) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            action,
          ],
        ),
      ),
    );
  }

  Widget _statsChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label:',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
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

  Widget _metaPill({
    required IconData icon,
    required String text,
    required Color foreground,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _projectBadge(KanboardProject project) {
    final color = _parseHexColor(project.uiColorHex);
    if (color == null) {
      return CircleAvatar(
        radius: 15,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Icon(Icons.folder_outlined, size: 16),
      );
    }
    return CircleAvatar(
      radius: 15,
      backgroundColor: color,
      child: Icon(
        Icons.folder_open,
        size: 15,
        color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black87,
      ),
    );
  }

  Widget _colorDot({required Color color, required bool selected}) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Colors.white : Colors.black26,
          width: selected ? 3 : 1,
        ),
        boxShadow: selected
            ? const <BoxShadow>[
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: selected
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }

  Color? _parseHexColor(String? hex) {
    final normalized = _normalizeColorHex(hex);
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

  String _toHexColor(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

class _ProjectFilesDialog extends ConsumerStatefulWidget {
  const _ProjectFilesDialog({required this.project});

  final KanboardProject project;

  @override
  ConsumerState<_ProjectFilesDialog> createState() =>
      _ProjectFilesDialogState();
}

class _ProjectFilesDialogState extends ConsumerState<_ProjectFilesDialog> {
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  List<KanboardProjectFile> _files = const <KanboardProjectFile>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final files = await api.getAllProjectFiles(widget.project.id);
      if (!mounted) return;
      setState(() {
        _files = files;
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

  Future<void> _addFiles() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final l10n = context.l10n;

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
      _showSnack(
        missingEntitlement
            ? l10n.macosFileAccessEntitlementMissingRebuildTheAppAfterEnablingUserSelectedFileReadEntitlement
            : l10n.filePickerFailed(error),
        isError: true,
      );
      return;
    } catch (error) {
      _showSnack(l10n.filePickerFailed(error), isError: true);
      return;
    }
    if (picked == null || picked.files.isEmpty) return;

    setState(() => _isWorking = true);
    try {
      for (final file in picked.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        await api.createProjectFile(
          projectId: widget.project.id,
          filename: file.name,
          contentBase64: base64Encode(bytes),
        );
      }
      await _load();
      _showSnack(l10n.projectAttachmentsUploaded);
    } catch (error) {
      _showSnack(l10n.uploadFailed(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Future<void> _downloadFile(KanboardProjectFile file) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final l10n = context.l10n;
    try {
      final encoded = await api.downloadProjectFile(file.id);
      if (encoded == null || encoded.isEmpty) {
        _showSnack(l10n.attachmentContentMissing, isError: true);
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
      _showSnack(l10n.downloadFailed(error), isError: true);
    }
  }

  Future<void> _removeFile(KanboardProjectFile file) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final l10n = context.l10n;
    try {
      await api.removeProjectFile(file.id);
      await _load();
    } catch (error) {
      _showSnack(l10n.deleteFailed(error), isError: true);
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.attachments(widget.project.name)),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
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
            if (_files.isEmpty && !_isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(context.l10n.noProjectAttachmentsYet),
              ),
            if (_files.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    return ListTile(
                      dense: true,
                      title: Text(file.name),
                      subtitle: Text(
                        '${file.sizeLabel} · ${_formatUnix(file.dateCreation)}',
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        children: <Widget>[
                          IconButton(
                            tooltip: context.l10n.download,
                            onPressed: () => _downloadFile(file),
                            icon: const Icon(Icons.download_rounded),
                          ),
                          IconButton(
                            tooltip: context.l10n.delete,
                            onPressed: () => _removeFile(file),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        OutlinedButton.icon(
          onPressed: _isWorking ? null : _addFiles,
          icon: const Icon(Icons.attach_file),
          label: Text(context.l10n.addFiles),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

class _ProjectPermissionsDialog extends ConsumerStatefulWidget {
  const _ProjectPermissionsDialog({required this.project});

  final KanboardProject project;

  @override
  ConsumerState<_ProjectPermissionsDialog> createState() =>
      _ProjectPermissionsDialogState();
}

class _ProjectPermissionsDialogState
    extends ConsumerState<_ProjectPermissionsDialog> {
  static const List<String> _projectRoles = <String>[
    'project-manager',
    'project-member',
    'project-viewer',
  ];

  bool _isLoading = false;
  bool _isWorking = false;
  bool _isSearchingUsers = false;
  bool _usesAutocompleteFallback = false;
  String? _error;
  String? _searchError;
  int? _selectedUserId;
  String _selectedRole = 'project-member';
  final TextEditingController _searchController = TextEditingController();
  List<KanboardProjectPermission> _sharedUsers =
      const <KanboardProjectPermission>[];
  List<KanboardUserReference> _allUsers = const <KanboardUserReference>[];
  List<KanboardUserReference> _searchedUsers = const <KanboardUserReference>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sharedUsersFuture = api.getProjectUsers(widget.project.id);
      List<KanboardUserReference> allUsers;
      var usesAutocompleteFallback = false;
      try {
        allUsers = await api.getAllUsers();
      } catch (_) {
        // Fallback for restricted accounts that cannot list all instance users.
        usesAutocompleteFallback = true;
        allUsers = await api.getAssignableUsers(widget.project.id);
      }
      final sharedUsers = await sharedUsersFuture;
      final sharedUsersWithRoles = await Future.wait<KanboardProjectPermission>(
        sharedUsers.map((user) async {
          try {
            final resolvedRole = await api.getProjectUserRole(
              projectId: widget.project.id,
              userId: user.userId,
            );
            return KanboardProjectPermission(
              userId: user.userId,
              username: user.username,
              name: user.name,
              role: resolvedRole ?? user.role,
            );
          } catch (_) {
            return user;
          }
        }),
      );

      final mergedUsers = <int, KanboardUserReference>{
        for (final user in allUsers)
          if (user.id > 0) user.id: user,
      };
      for (final permission in sharedUsersWithRoles) {
        if (permission.userId <= 0) continue;
        final username = permission.username.trim();
        final name = permission.name?.trim() ?? '';
        mergedUsers[permission.userId] = KanboardUserReference(
          id: permission.userId,
          name: name.isNotEmpty ? name : username,
          username: username,
        );
      }
      final normalizedUsers = mergedUsers.values.toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

      if (!mounted) return;
      setState(() {
        _sharedUsers = sharedUsersWithRoles;
        _allUsers = normalizedUsers;
        _usesAutocompleteFallback = usesAutocompleteFallback;
        if (!usesAutocompleteFallback) {
          _searchedUsers = const <KanboardUserReference>[];
          _searchError = null;
        }
      });
      _ensureSelectedCandidate();
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

  List<KanboardUserReference> _shareCandidates() {
    final sharedIds = _sharedUsers.map((entry) => entry.userId).toSet();
    final available = <int, KanboardUserReference>{
      for (final user in _allUsers)
        if (user.id > 0) user.id: user,
      for (final user in _searchedUsers)
        if (user.id > 0) user.id: user,
    };
    return available.values
        .where((user) => user.id > 0 && !sharedIds.contains(user.id))
        .toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
  }

  void _ensureSelectedCandidate() {
    final candidates = _shareCandidates();
    final selectedIsValid =
        _selectedUserId != null &&
        candidates.any((user) => user.id == _selectedUserId);
    if (selectedIsValid) return;
    setState(() {
      _selectedUserId = candidates.isEmpty ? null : candidates.first.id;
    });
  }

  Future<void> _searchUsers() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _searchError = 'Type at least 2 characters to search users.';
      });
      return;
    }

    setState(() {
      _isSearchingUsers = true;
      _searchError = null;
    });
    try {
      final found = await api.searchUsersByAutocomplete(query);
      if (!mounted) return;
      final merged = <int, KanboardUserReference>{
        for (final user in _searchedUsers)
          if (user.id > 0) user.id: user,
        for (final user in found)
          if (user.id > 0) user.id: user,
      };
      final normalized = merged.values.toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      setState(() {
        _searchedUsers = normalized;
        if (found.isEmpty) {
          _searchError = 'No users found for "$query".';
        }
      });
      _ensureSelectedCandidate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searchError = 'User search failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingUsers = false;
        });
      }
    }
  }

  Future<void> _addSelectedUser() async {
    final selectedUserId = _selectedUserId;
    if (selectedUserId == null || selectedUserId <= 0) return;
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    setState(() => _isWorking = true);
    try {
      final saved = await api.addProjectUser(
        projectId: widget.project.id,
        userId: selectedUserId,
        role: _selectedRole,
      );
      if (!saved) {
        throw StateError('Server rejected project permission update.');
      }
      await _load();
      _showSnack(
        'User added with role: ${_roleLabel(_selectedRole).toLowerCase()}.',
      );
    } catch (error) {
      _showSnack('Failed to add user: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Future<void> _removeUser(KanboardProjectPermission user) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Remove project access?'),
        content: Text('Remove ${user.displayName} from this project?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isWorking = true);
    try {
      final removed = await api.removeProjectUser(
        projectId: widget.project.id,
        userId: user.userId,
      );
      if (!removed) {
        throw StateError('Server rejected project permission update.');
      }
      await _load();
      _showSnack('User removed from project permissions.');
    } catch (error) {
      _showSnack('Failed to remove user: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Future<void> _changeUserRole({
    required KanboardProjectPermission user,
    required String role,
  }) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    if (role.trim() == (user.role ?? '').trim()) return;
    setState(() => _isWorking = true);
    try {
      final changed = await api.changeProjectUserRole(
        projectId: widget.project.id,
        userId: user.userId,
        role: role,
      );
      if (!changed) {
        throw StateError('Server rejected role change.');
      }
      await _load();
      _showSnack('Updated role for ${user.displayName}.');
    } catch (error) {
      _showSnack('Failed to change role: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
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

  String _roleLabel(String? role) {
    switch ((role ?? '').trim()) {
      case 'project-manager':
        return 'Project Manager';
      case 'project-viewer':
        return 'Project Viewer';
      case 'project-member':
        return 'Project Member';
      default:
        return 'Project Member';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = _shareCandidates();
    final selectedInCandidates =
        _selectedUserId != null &&
        candidates.any((user) => user.id == _selectedUserId);

    return AlertDialog(
      title: Text('Project permissions - ${widget.project.name}'),
      content: SizedBox(
        width: 700,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_isLoading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Share this project with a user',
              style: theme.textTheme.labelLarge,
            ),
            if (_usesAutocompleteFallback) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Global user listing is restricted by API permissions. '
                'Search by name/username to match web Project Permissions.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      enabled: !_isWorking && !_isLoading && !_isSearchingUsers,
                      decoration: const InputDecoration(
                        labelText: 'Search users',
                        hintText: 'Type a name or username',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _searchUsers(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _isWorking || _isLoading || _isSearchingUsers
                        ? null
                        : _searchUsers,
                    icon: const Icon(Icons.search),
                    label: Text(context.l10n.search),
                  ),
                ],
              ),
              if (_isSearchingUsers) ...<Widget>[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (_searchError != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  _searchError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
            const SizedBox(height: 8),
            if (candidates.isEmpty)
              Text(
                _usesAutocompleteFallback
                    ? 'No additional users available yet. Use search above.'
                    : 'No additional users available to add.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: selectedInCandidates ? _selectedUserId : null,
                      decoration: const InputDecoration(
                        labelText: 'User',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: candidates
                          .map(
                            (user) => DropdownMenuItem<int>(
                              value: user.id,
                              child: Text(
                                user.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _isWorking
                          ? null
                          : (value) => setState(() => _selectedUserId = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      value: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _projectRoles
                          .map(
                            (role) => DropdownMenuItem<String>(
                              value: role,
                              child: Text(_roleLabel(role)),
                            ),
                          )
                          .toList(),
                      onChanged: _isWorking || _isLoading || _isSearchingUsers
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _selectedRole = value);
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed:
                        _isWorking ||
                            _isLoading ||
                            _isSearchingUsers ||
                            !selectedInCandidates
                        ? null
                        : _addSelectedUser,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(context.l10n.add),
                  ),
                ],
              ),
            if (_isWorking) ...<Widget>[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Text('Users with access', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            if (_sharedUsers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No delegated users for this project yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _sharedUsers.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    final user = _sharedUsers[index];
                    final username = user.username.trim();
                    final role = user.role?.trim() ?? 'project-member';
                    final details = <String>[
                      if (username.isNotEmpty) '@$username',
                      'role: ${_roleLabel(role)}',
                    ];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(user.displayName),
                      subtitle: details.isEmpty
                          ? null
                          : Text(details.join('  ')),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Manage role',
                        enabled: !_isWorking,
                        onSelected: (value) {
                          if (value == 'remove') {
                            _removeUser(user);
                            return;
                          }
                          _changeUserRole(user: user, role: value);
                        },
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          for (final candidateRole in _projectRoles)
                            CheckedPopupMenuItem<String>(
                              value: candidateRole,
                              checked: candidateRole == role,
                              child: Text(_roleLabel(candidateRole)),
                            ),
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            value: 'remove',
                            child: Text(context.l10n.remove),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isLoading || _isWorking ? null : _load,
          child: Text(context.l10n.refresh),
        ),
        FilledButton(
          onPressed: _isWorking ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

class _EmptyProjectsState extends StatelessWidget {
  const _EmptyProjectsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.12,
                ),
                child: Icon(
                  Icons.workspaces_outline,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.noProjectsYet,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context
                    .l10n
                    .createYourFirstProjectFromTheActionButtonAndStartOrganizingYourBoard,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
