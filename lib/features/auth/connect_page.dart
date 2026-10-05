import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../kanboard/kanboard_api.dart';
import '../../l10n/l10n.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/theme_mode_menu_button.dart';
import '../../storage/credentials_store.dart';
import '../../kanboard/jsonrpc_client.dart';

class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _tokenController = TextEditingController();
  KanboardAuthMode _authMode = KanboardAuthMode.password;

  bool _isConnecting = false;
  String? _status;
  bool _allowLocalHttp = false;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillSaved());
  }

  Future<void> _prefillSaved() async {
    try {
      final saved = await ref.read(credentialsStoreProvider).read();
      if (!mounted || saved == null) return;
      setState(() {
        _urlController.text = saved.serverUrl;
        _usernameController.text = saved.username;
        _tokenController.text = saved.token;
        _authMode = saved.authMode;
        _allowLocalHttp = saved.allowLocalHttp;
        _status = context.l10n.loadedSavedCredentials;
        _statusIsError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = context.l10n.secureStorageUnavailable;
        _statusIsError = true;
      });
    }
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isConnecting = true;
      _status = null;
      _statusIsError = false;
    });
    final credentials = KanboardCredentials(
      serverUrl: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      token: _authMode == KanboardAuthMode.password
          ? _tokenController.text
          : _tokenController.text.trim(),
      authMode: _authMode,
      allowLocalHttp: _allowLocalHttp,
    );
    KanboardApi? api;
    try {
      api = KanboardApi.fromCredentials(credentials);
      final version = await api.getVersion();
      final me = await api.getMe();
      await ref.read(credentialsStoreProvider).save(credentials);
      if (!mounted) return;
      ref.read(sessionCredentialsProvider.notifier).state = credentials;
      setState(() {
        _status = context.l10n.connectedAsVersion(me.username, version);
      });
      context.go('/projects');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error is CredentialsStorageException
            ? context.l10n.secureStorageUnavailable
            : context.l10n.connectionFailed;
        _statusIsError = true;
      });
    } finally {
      api?.close();
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = theme.platform;
    final isApple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final l10n = context.l10n;
    final isPasswordMode = _authMode == KanboardAuthMode.password;
    final secretFieldLabel = isPasswordMode
        ? l10n.password
        : l10n.personalAccessToken;
    final secretRequiredMessage = isPasswordMode
        ? l10n.passwordIsRequired
        : l10n.tokenIsRequired;
    final connectionHint = isPasswordMode
        ? l10n.useYourKanboardUsernameAndPassword
        : l10n.personalTokenHint;
    final authNote = isPasswordMode
        ? l10n.authNotePasswordModeUsesYourKanboardLoginCredentials
        : l10n.personalTokenHint;
    final body = SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 760;
          final horizontalPadding = isCompact ? 12.0 : 16.0;

          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isCompact ? 560 : 920),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Card(
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
                          padding: const EdgeInsets.all(18),
                          child: isCompact
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: theme.colorScheme.primary
                                          .withValues(alpha: 0.15),
                                      child: Icon(
                                        Icons.settings_ethernet_rounded,
                                        color: theme.colorScheme.primary,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      context.l10n.connectYourKanboardInstance,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      connectionHint,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    CircleAvatar(
                                      radius: 25,
                                      backgroundColor: theme.colorScheme.primary
                                          .withValues(alpha: 0.15),
                                      child: Icon(
                                        Icons.settings_ethernet_rounded,
                                        color: theme.colorScheme.primary,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 620,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              context
                                                  .l10n
                                                  .connectYourKanboardInstance,
                                              style: theme.textTheme.titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              connectionHint,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                context.l10n.credentials,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.authMode,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<KanboardAuthMode>(
                                segments: <ButtonSegment<KanboardAuthMode>>[
                                  ButtonSegment<KanboardAuthMode>(
                                    value: KanboardAuthMode.apiToken,
                                    label: Text(l10n.apiTokenMode),
                                    icon: const Icon(Icons.key_rounded),
                                  ),
                                  ButtonSegment<KanboardAuthMode>(
                                    value: KanboardAuthMode.password,
                                    label: Text(l10n.passwordMode),
                                    icon: const Icon(Icons.password_rounded),
                                  ),
                                ],
                                selected: <KanboardAuthMode>{_authMode},
                                onSelectionChanged:
                                    (Set<KanboardAuthMode> selection) {
                                      if (selection.isEmpty) return;
                                      setState(() {
                                        _authMode = selection.first;
                                      });
                                    },
                              ),
                              const SizedBox(height: 12),
                              Text(l10n.credentialsSharingDisabled),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _allowLocalHttp,
                                title: Text(l10n.localDevelopmentConnection),
                                onChanged: _isConnecting
                                    ? null
                                    : (value) => setState(
                                        () => _allowLocalHttp = value ?? false,
                                      ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _urlController,
                                decoration: InputDecoration(
                                  labelText: context.l10n.serverURL,
                                  hintText: context.l10n.serverURLExample,
                                  prefixIcon: const Icon(Icons.link_rounded),
                                ),
                                keyboardType: TextInputType.url,
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (text.isEmpty) {
                                    return context.l10n.serverURLIsRequired;
                                  }
                                  final uri = Uri.tryParse(text);
                                  if (uri == null ||
                                      !uri.hasScheme ||
                                      uri.host.isEmpty) {
                                    return context.l10n.enterAValidURL;
                                  }
                                  try {
                                    JsonRpcClient.validateEndpoint(
                                      Uri.parse(
                                        KanboardCredentials(
                                          serverUrl: text,
                                          username: 'validation',
                                          token: '',
                                        ).normalizedEndpoint,
                                      ),
                                      allowLocalHttp: _allowLocalHttp,
                                    );
                                  } catch (_) {
                                    return l10n.secureConnectionRequired;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _usernameController,
                                decoration: InputDecoration(
                                  labelText: context.l10n.username,
                                  prefixIcon: const Icon(Icons.person_outline),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return l10n.usernameIsRequired;
                                  }
                                  if (value.trim().toLowerCase() == 'jsonrpc') {
                                    return l10n.personalTokenHint;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _tokenController,
                                decoration: InputDecoration(
                                  labelText: secretFieldLabel,
                                  prefixIcon: const Icon(
                                    Icons.password_rounded,
                                  ),
                                ),
                                obscureText: true,
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                    ? secretRequiredMessage
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: <Widget>[
                                  FilledButton.icon(
                                    onPressed: _isConnecting ? null : _connect,
                                    icon: _isConnecting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.login_rounded),
                                    label: Text(
                                      context.l10n.testConnectionContinue,
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _isConnecting
                                        ? null
                                        : () => context.go('/projects'),
                                    icon: const Icon(Icons.folder_open),
                                    label: Text(context.l10n.openProjects),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: theme.colorScheme.secondary
                                    .withValues(alpha: 0.16),
                                child: Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  authNote,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_status != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _statusCard(theme),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (isApple) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(l10n.connectToKanboard),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(30, 30),
                onPressed: () => context.go('/projects'),
                child: const Icon(CupertinoIcons.folder, size: 20),
              ),
              const SizedBox(width: 4),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(30, 30),
                onPressed: () => context.go('/'),
                child: const Icon(CupertinoIcons.house, size: 20),
              ),
              const ThemeModeMenuButton(),
            ],
          ),
        ),
        child: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.connectToKanboard),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.organizerToday,
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            tooltip: l10n.projects,
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      body: body,
    );
  }

  Widget _statusCard(ThemeData theme) {
    final isError = _statusIsError;
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
              child: Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _status!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isError ? color : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
