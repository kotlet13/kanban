import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../storage/ai_settings_store.dart';
import '../../widgets/theme_mode_menu_button.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _apiKeyController = TextEditingController();
  bool _enabled = false;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _isLoadingModels = false;
  String _model = 'gpt-4.1-mini';
  String _responseMode = 'instant';
  String _thinkingEffort = 'medium';
  String? _error;

  List<String> _models = <String>[
    'gpt-4.1-mini',
    'gpt-4.1',
    'gpt-4o-mini',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final settings = await ref.read(aiSettingsStoreProvider).read();
      _enabled = settings.enabled;
      _model = settings.model.trim().isEmpty ? 'gpt-4.1-mini' : settings.model;
      _responseMode = settings.responseMode;
      _thinkingEffort = settings.normalizedThinkingEffort;
      _apiKeyController.text = settings.apiKey ?? '';
      if ((settings.apiKey ?? '').trim().isNotEmpty) {
        await _fetchModels(showSnack: false);
      }
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

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref.read(aiSettingsStoreProvider).save(
            AiSettings(
              enabled: _enabled,
              model: _model,
              apiKey: _apiKeyController.text.trim(),
              responseMode: _responseMode,
              thinkingEffort: _thinkingEffort,
            ),
          );
      ref.invalidate(aiSettingsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.aiSettingsSaved)));
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

  Future<void> _test() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _error = context.l10n.openAiApiKeyIsRequired;
      });
      return;
    }
    setState(() {
      _isTesting = true;
      _error = null;
    });
    try {
      await ref.read(aiSettingsStoreProvider).save(
            AiSettings(
              enabled: true,
              model: _model,
              apiKey: key,
              responseMode: _responseMode,
              thinkingEffort: _thinkingEffort,
            ),
          );
      ref.invalidate(aiSettingsProvider);
      final count = await _fetchModels(showSnack: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.availableModelsFetched(count))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.availableModelsFetchFailed(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  Future<int> _fetchModels({bool showSnack = true}) async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      throw StateError(context.l10n.openAiApiKeyIsRequired);
    }
    setState(() {
      _isLoadingModels = true;
      _error = null;
    });
    final response = await ref.read(httpClientProvider).get(
      Uri.parse('https://api.openai.com/v1/models'),
      headers: <String, String>{'Authorization': 'Bearer $key'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as List<dynamic>? ?? const <dynamic>[];
    final modelIds = data
        .whereType<Map<String, dynamic>>()
        .map((m) => m['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (!mounted) return modelIds.length;
    setState(() {
      _models = (modelIds.isEmpty ? _models : modelIds).toSet().toList()..sort();
      if (_models.isNotEmpty && !_models.contains(_model)) {
        _model = _models.first;
      }
      _isLoadingModels = false;
    });
    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.availableModelsFetched(_models.length))),
      );
    }
    return _models.length;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelItems = _models.toSet().toList()..sort();
    final selectedModel = modelItems.contains(_model) ? _model : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.aiSettings),
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
                    child: Text(context.l10n.aiSettingsSecurityNotice),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isLoading) const LinearProgressIndicator(),
                if (_isLoadingModels)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _enabled,
                  onChanged: _isSaving ? null : (value) => setState(() => _enabled = value),
                  title: Text(context.l10n.enableAI),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'instant',
                      label: Text(context.l10n.instantResponse),
                      icon: const Icon(Icons.flash_on_outlined),
                    ),
                    ButtonSegment<String>(
                      value: 'thinking',
                      label: Text(context.l10n.thinkingResponse),
                      icon: const Icon(Icons.psychology_alt_outlined),
                    ),
                  ],
                  selected: <String>{_responseMode},
                  onSelectionChanged: _isSaving
                      ? null
                      : (Set<String> values) {
                          if (values.isEmpty) return;
                          setState(() => _responseMode = values.first);
                        },
                ),
                if (_responseMode == 'thinking') ...<Widget>[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _thinkingEffort,
                    decoration: InputDecoration(
                      labelText: context.l10n.thinkingEffort,
                    ),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: 'low',
                        child: Text(context.l10n.effortLow),
                      ),
                      DropdownMenuItem<String>(
                        value: 'medium',
                        child: Text(context.l10n.effortMedium),
                      ),
                      DropdownMenuItem<String>(
                        value: 'high',
                        child: Text(context.l10n.effortHigh),
                      ),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _thinkingEffort = value);
                          },
                  ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedModel,
                  decoration: InputDecoration(labelText: context.l10n.aiModel),
                  items: modelItems
                      .map(
                        (model) => DropdownMenuItem<String>(
                          value: model,
                          child: Text(model),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _model = value;
                          });
                        },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.openAiApiKey,
                    hintText: 'sk-...',
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _isTesting ? null : _test,
                      icon: const Icon(Icons.cloud_done_outlined),
                      label: Text(context.l10n.fetchAvailableModels),
                    ),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: Text(
                        _isSaving ? context.l10n.saving : context.l10n.save,
                      ),
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
