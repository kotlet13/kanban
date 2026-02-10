import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../kanboard/kanboard_api.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/bidirectional_scroll_view.dart';
import '../../widgets/theme_mode_menu_button.dart';

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

  bool _isConnecting = false;
  String? _status;
  bool _usedJsonRpcFallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillSaved());
  }

  Future<void> _prefillSaved() async {
    final saved = await ref.read(credentialsStoreProvider).read();
    if (!mounted || saved == null) return;
    setState(() {
      _urlController.text = saved.serverUrl;
      _usernameController.text = saved.username;
      _tokenController.text = saved.token;
      _status = 'Loaded saved credentials.';
    });
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isConnecting = true;
      _status = null;
    });

    final credentials = KanboardCredentials(
      serverUrl: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      token: _tokenController.text.trim(),
    );

    try {
      debugPrint(
        '[Connect] Attempting auth with username="${credentials.username}" endpoint="${credentials.normalizedEndpoint}"',
      );

      _usedJsonRpcFallback = false;

      String version;
      KanboardUser me;
      KanboardCredentials successfulCredentials = credentials;

      try {
        final api = KanboardApi.fromCredentials(credentials);
        version = await api.getVersion();
        me = await api.getMe();
      } catch (firstError) {
        debugPrint('[Connect] Primary auth failed: $firstError');
        if (credentials.username.toLowerCase() != 'jsonrpc') {
          debugPrint(
            '[Connect] Retrying with username="jsonrpc" using same token.',
          );
          final fallbackCredentials = KanboardCredentials(
            serverUrl: credentials.serverUrl,
            username: 'jsonrpc',
            token: credentials.token,
          );
          final fallbackApi = KanboardApi.fromCredentials(fallbackCredentials);
          version = await fallbackApi.getVersion();
          me = await fallbackApi.getMe();
          successfulCredentials = fallbackCredentials;
          _usedJsonRpcFallback = true;
        } else {
          rethrow;
        }
      }

      await ref.read(credentialsStoreProvider).save(successfulCredentials);
      ref.read(sessionCredentialsProvider.notifier).state = successfulCredentials;

      if (!mounted) return;
      setState(() {
        _status = _usedJsonRpcFallback
            ? 'Connected via jsonrpc token auth. Server version: $version'
            : 'Connected as ${me.username}. Version: $version';
      });

      if (version != '1.2.50') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Connected successfully, but server version is $version (target: 1.2.50).',
            ),
          ),
        );
      }

      if (_usedJsonRpcFallback) {
        _usernameController.text = 'jsonrpc';
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connected only after switching to username "jsonrpc". Your token appears to be an application API token.',
            ),
          ),
        );
      }

      context.go('/projects');
    } catch (error) {
      debugPrint('[Connect] Final connection failure: $error');
      if (!mounted) return;
      setState(() {
        _status =
            'Connection failed: $error\nTip: if you copied "API User Access", try username "jsonrpc" with that token.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Kanboard'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Projects',
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: BidirectionalScrollView(
            padding: const EdgeInsets.all(16),
            contentWidth: 920,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://kanboard.example.com',
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Server URL is required.';
                  final uri = Uri.tryParse(text);
                  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
                    return 'Enter a valid URL.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Username is required.'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Personal access token',
                ),
                obscureText: true,
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Token is required.'
                        : null,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isConnecting ? null : _connect,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Test connection & continue'),
              ),
              const SizedBox(height: 8),
              Text(
                'Auth note: personal token usually uses your username; application token usually uses username "jsonrpc".',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isConnecting
                    ? null
                    : () => context.go('/projects'),
                icon: const Icon(Icons.list),
                label: const Text('Open projects (uses saved session)'),
              ),
              if (_status != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(_status!),
              ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
