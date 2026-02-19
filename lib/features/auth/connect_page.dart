import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../kanboard/kanboard_api.dart';
import '../../l10n/l10n.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import '../../widgets/theme_mode_menu_button.dart';
import 'credentials_transfer.dart';

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
      _status = context.l10n.loadedSavedCredentials;
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
      ref.read(sessionCredentialsProvider.notifier).state =
          successfulCredentials;

      if (!mounted) return;
      setState(() {
        _status = _usedJsonRpcFallback
            ? context.l10n.connectedViaJsonrpcTokenAuthServerVersion(version)
            : context.l10n.connectedAsVersion(me.username, version);
      });

      if (version != '1.2.50') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.connectedSuccessfullyButServerVersionIsTarget1250(
                version,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  KanboardCredentials? _credentialsFromForm() {
    final serverUrl = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final token = _tokenController.text.trim();
    if (serverUrl.isEmpty || username.isEmpty || token.isEmpty) return null;
    return KanboardCredentials(
      serverUrl: serverUrl,
      username: username,
      token: token,
    );
  }

  Future<void> _showExportQr() async {
    final credentials =
        _credentialsFromForm() ??
        await ref.read(credentialsStoreProvider).read();

    if (credentials == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.nothingToExportYetConnectOnceOrFillAllFieldsFirst,
          ),
        ),
      );
      return;
    }

    final payload = buildCredentialsTransferPayload(credentials);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.72;
        return AlertDialog(
          title: Text(context.l10n.transferCredentials),
          content: SizedBox(
            width: 340,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxDialogHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.l10n.scanThisCodeWithYourPhoneInTheConnectScreen,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: QrImageView(
                        data: payload,
                        version: QrVersions.auto,
                        size: 250,
                        gapless: false,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                        errorStateBuilder: (context, error) {
                          return Center(
                            child: Text(
                              'Could not render QR.\n$error',
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                        semanticsLabel: context.l10n.credentialsTransferQR,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      payload,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.ifQRRenderingFailsCopyPasteTheTransferCode,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    const Divider(),
                    const SizedBox(height: 4),
                    Text(
                      context
                          .l10n
                          .securityNoteThisQRContainsYourAPITokenInPlainText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: payload));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.transferCodeCopied)),
                );
              },
              child: Text(context.l10n.copyCode),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.done),
            ),
          ],
        );
      },
    );
  }

  Future<void> _applyTransferPayload(String value) async {
    try {
      final credentials = parseCredentialsTransferPayload(value);
      if (!mounted) return;
      setState(() {
        _urlController.text = credentials.serverUrl;
        _usernameController.text = credentials.username;
        _tokenController.text = credentials.token;
        _status = context.l10n.importedCredentialsFromTransferCode;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.credentialsImportedTapConnect)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.invalidTransferCode(error))),
      );
    }
  }

  Future<void> _importFromClipboard() async {
    final clipboard = await Clipboard.getData('text/plain');
    final value = clipboard?.text?.trim() ?? '';
    if (value.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.clipboardIsEmpty)));
      return;
    }
    await _applyTransferPayload(value);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.connectToKanboard),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.projects,
            onPressed: () => context.go('/projects'),
            icon: const Icon(Icons.folder_open),
          ),
          const ThemeModeMenuButton(),
        ],
      ),
      body: SafeArea(
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
                    constraints: BoxConstraints(
                      maxWidth: isCompact ? 560 : 920,
                    ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: theme
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.15),
                                        child: Icon(
                                          Icons.settings_ethernet_rounded,
                                          color: theme.colorScheme.primary,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
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
                                        context
                                            .l10n
                                            .usePersonalTokenUsernameOrUseApplicationTokenWithUsernameJsonrpc,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      CircleAvatar(
                                        radius: 25,
                                        backgroundColor: theme
                                            .colorScheme
                                            .primary
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
                                                style: theme
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                context
                                                    .l10n
                                                    .usePersonalTokenUsernameOrUseApplicationTokenWithUsernameJsonrpc,
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
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
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    FilledButton.tonalIcon(
                                      onPressed: _showExportQr,
                                      icon: const Icon(Icons.qr_code_2_rounded),
                                      label: Text(context.l10n.showTransferQR),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _importFromClipboard,
                                      icon: const Icon(Icons.content_paste),
                                      label: Text(
                                        context.l10n.pasteTransferCode,
                                      ),
                                    ),
                                  ],
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
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _usernameController,
                                  decoration: InputDecoration(
                                    labelText: context.l10n.username,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                  ),
                                  validator: (value) =>
                                      (value == null || value.trim().isEmpty)
                                      ? context.l10n.usernameIsRequired
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _tokenController,
                                  decoration: InputDecoration(
                                    labelText: context.l10n.personalAccessToken,
                                    prefixIcon: const Icon(
                                      Icons.password_rounded,
                                    ),
                                  ),
                                  obscureText: true,
                                  validator: (value) =>
                                      (value == null || value.trim().isEmpty)
                                      ? context.l10n.tokenIsRequired
                                      : null,
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: <Widget>[
                                    FilledButton.icon(
                                      onPressed: _isConnecting
                                          ? null
                                          : _connect,
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
                                    context
                                        .l10n
                                        .authNotePersonalTokenUsuallyUsesYourUsernameApplicationTokenUsuallyUsesUsernameJsonrpc,
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
      ),
    );
  }

  Widget _statusCard(ThemeData theme) {
    final isError = _status!.toLowerCase().contains('failed');
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
