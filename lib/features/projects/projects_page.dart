import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        _error = 'No active session. Connect first.';
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

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(project == null ? 'Create project' : 'Edit project'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Project name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Project color (synced via metadata)',
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
                        label: const Text('No color'),
                      ),
                    ],
                  ),
                ],
              ),
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

    if (confirmed != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

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
      }
      await _loadProjects(fromRefresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Project save failed: $error')));
    }
  }

  Future<void> _deleteProject(KanboardProject project) async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text('This will remove "${project.name}" permanently.'),
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
      await api.removeProject(project.id);
      await _loadProjects(fromRefresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project deletion failed: $error')),
      );
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Connection settings',
            onPressed: () => context.push('/connect'),
            icon: const Icon(Icons.settings_ethernet),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : () => _loadProjects(fromRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
          const ThemeModeMenuButton(),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: hasSession ? () => _createOrEditProject() : null,
        icon: const Icon(Icons.add),
        label: const Text('Project'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadProjects(fromRefresh: true),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: <Widget>[
            if (!hasSession)
              Card(
                child: ListTile(
                  title: const Text('No active session'),
                  subtitle: const Text('Connect to Kanboard to continue.'),
                  trailing: FilledButton(
                    onPressed: () => context.push('/connect'),
                    child: const Text('Connect'),
                  ),
                ),
              ),
            if (_isLoading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_projects.isEmpty && !_isLoading && hasSession)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No projects found.')),
              ),
            for (final project in _projects)
              Card(
                child: ListTile(
                  leading: _projectBadge(project),
                  title: Text(project.name),
                  subtitle: project.description == null ||
                          project.description!.trim().isEmpty
                      ? null
                      : Text(project.description!),
                  onTap: () {
                    context.push(
                      '/board/${project.id}?projectName=${Uri.encodeComponent(project.name)}',
                    );
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _createOrEditProject(project: project);
                      } else if (value == 'delete') {
                        _deleteProject(project);
                      }
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _projectBadge(KanboardProject project) {
    final color = _parseHexColor(project.uiColorHex);
    if (color == null) {
      return const CircleAvatar(
        radius: 12,
        child: Icon(Icons.folder, size: 14),
      );
    }
    return CircleAvatar(
      radius: 12,
      backgroundColor: color,
      child: const SizedBox.shrink(),
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
      child: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
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
