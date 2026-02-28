import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
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
  final _currencyController = TextEditingController();

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
      _currencyController.text = defaults.defaultCurrencyCode ?? '';
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

  Future<void> _setAppLocale(String value) async {
    final locale = value == 'system' ? null : Locale(value);
    ref.read(appLocaleProvider.notifier).state = locale;
    await ref.read(localeStoreProvider).save(locale);
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
      final currency = _currencyController.text.trim().toUpperCase();
      if (currency.isNotEmpty && !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
        setState(() {
          _error = 'Default currency must be a 3-letter code (e.g. USD).';
        });
        return;
      }
      await store.save(
        ProjectDefaults(
          columnNames: columns,
          defaultSwimlaneName: swimlane.isEmpty ? null : swimlane,
          defaultCurrencyCode: currency.isEmpty ? null : currency,
        ),
      );
      if (currency.isNotEmpty) {
        final api = ref.read(kanboardApiProvider);
        if (api != null) {
          final projects = await api.getMyProjects();
          for (final project in projects) {
            await api.saveProjectExpenseSettings(
              projectId: project.id,
              currency: currency,
              budgetCents: await api.getProjectExpenseBudgetCents(project.id),
            );
          }
        }
      }
      ref.invalidate(projectDefaultsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currency.isEmpty
                ? 'Project defaults saved.'
                : 'Project defaults saved. Currency applied to all projects.',
          ),
        ),
      );
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
    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(context.l10n.resetDefaults),
        content: Text(
          context
              .l10n
              .thisClearsCustomDefaultsAndUsesKanboardServerDefaultsForNewProjects,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.reset),
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
    _currencyController.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.projectDefaultsReset)));
  }

  @override
  void dispose() {
    _columnsController.dispose();
    _swimlaneController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocale = ref.watch(appLocaleProvider);
    final localeValue = appLocale?.languageCode ?? 'system';
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.projectDefaults2),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.projects,
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
                          context
                              .l10n
                              .templateAppliedToEveryNewProjectCreatedFromThisApp,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.l10n.leaveFieldsEmptyToKeepServerDefaults,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context
                              .l10n
                              .savingADefaultCurrencyAlsoAppliesItToAllExistingProjects,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.l10n.appLanguage,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.l10n.followSystemKeepsLocaleAutomatic,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(localeValue),
                          initialValue: localeValue,
                          decoration: InputDecoration(
                            labelText: context.l10n.language,
                          ),
                          items: <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: 'system',
                              child: Text(context.l10n.followSystemDefault),
                            ),
                            DropdownMenuItem<String>(
                              value: 'en',
                              child: Text(context.l10n.english),
                            ),
                            DropdownMenuItem<String>(
                              value: 'sl',
                              child: Text(context.l10n.slovene),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _setAppLocale(value);
                          },
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
                  decoration: InputDecoration(
                    labelText: context.l10n.defaultBoardColumns,
                    hintText: context.l10n.defaultBoardColumnsHint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _swimlaneController,
                  decoration: InputDecoration(
                    labelText: context.l10n.defaultSwimlane,
                    hintText: context.l10n.exampleMain,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _currencyController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  decoration: InputDecoration(
                    labelText: context.l10n.defaultExpenseCurrency,
                    hintText: context.l10n.exampleUSD,
                    counterText: '',
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
                      label: Text(context.l10n.reset),
                    ),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: _isSaving
                          ? Text(context.l10n.saving)
                          : Text(context.l10n.saveDefaults),
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
