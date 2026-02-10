import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../storage/project_defaults_store.dart';
import '../../widgets/theme_mode_menu_button.dart';

class ProjectDefaultsPage extends ConsumerStatefulWidget {
  const ProjectDefaultsPage({super.key});

  @override
  ConsumerState<ProjectDefaultsPage> createState() =>
      _ProjectDefaultsPageState();
}

class _ProjectDefaultsPageState extends ConsumerState<ProjectDefaultsPage> {
  final _columnsController = TextEditingController();
  final _swimlaneController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(projectDefaultsStoreProvider);
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final defaults = await store.read();
      _columnsController.text = defaults.columnNames.join('\n');
      _swimlaneController.text = defaults.defaultSwimlaneName ?? '';
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<String> _parseColumns(String raw) {
    final seen = <String>{};
    final columns = <String>[];
    for (final chunk in raw.split(RegExp(r'[\n,]'))) {
      final name = chunk.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      columns.add(name);
    }
    return columns;
  }

  Future<void> _save() async {
    final store = ref.read(projectDefaultsStoreProvider);
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final columns = _parseColumns(_columnsController.text);
      final swimlane = _swimlaneController.text.trim();
      await store.save(
        ProjectDefaults(
          columnNames: columns,
          defaultSwimlaneName: swimlane.isEmpty ? null : swimlane,
        ),
      );
      ref.invalidate(projectDefaultsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project defaults saved.')));
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

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset defaults?'),
        content: const Text(
          'This clears custom defaults and uses Kanboard server defaults for new projects.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final store = ref.read(projectDefaultsStoreProvider);
    await store.clear();
    ref.invalidate(projectDefaultsProvider);
    if (!mounted) return;
    _columnsController.clear();
    _swimlaneController.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Project defaults reset.')));
  }

  @override
  void dispose() {
    _columnsController.dispose();
    _swimlaneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Defaults'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Projects',
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Template applied to every new project created from this app.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Leave fields empty to keep server defaults.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _columnsController,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Default Board Columns',
                    hintText:
                        'One per line, e.g.\nBacklog\nReady\nIn Progress\nDone',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _swimlaneController,
                  decoration: const InputDecoration(
                    labelText: 'Default Swimlane',
                    hintText: 'Example: Main',
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _reset,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reset'),
                    ),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: _isSaving
                          ? const Text('Saving...')
                          : const Text('Save defaults'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
