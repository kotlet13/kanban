import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/jivie_theme.dart';
import '../../data/local_vault.dart';
import '../../data/local_vault_open.dart';
import '../../platform/recovery/recovery_file_io.dart';
import '../../state/app_preferences_provider.dart';

final localVaultServiceProvider = FutureProvider<LocalVaultService>(
  (ref) => openLocalVaultService(),
);

/// The normal app is not mounted until the vault can be opened. In particular,
/// router builders, preference replay, invitation listeners and push/sync
/// coordinators cannot create a database handle during the conversion.
class LocalVaultBootstrap extends ConsumerStatefulWidget {
  const LocalVaultBootstrap({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<LocalVaultBootstrap> createState() =>
      _LocalVaultBootstrapState();
}

class _LocalVaultBootstrapState extends ConsumerState<LocalVaultBootstrap> {
  LocalVaultStatus? _status;
  Object? _error;
  bool _busy = true;
  bool _continueWithCleanup = false;
  bool _continueBrowserSource = false;
  String _warningLabel = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _inspect();
  }

  Future<void> _loadPreferences() async {
    try {
      final locale = await ref.read(localeStoreProvider).read();
      final theme = await ref.read(themeModeStoreProvider).read();
      if (!mounted) return;
      ref.read(appLocaleProvider.notifier).state = locale;
      ref.read(themeModeProvider.notifier).state = theme;
    } catch (_) {
      // Preferences never authorize opening data or substitute for the journal.
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _inspect() async {
    if (ref.read(localVaultServiceProvider).hasError) {
      ref.invalidate(localVaultServiceProvider);
    }
    await _run((service) async {
      await ref.read(recoveryFileIoProvider).cleanup();
      return service.inspect();
    });
  }

  Future<void> _run(
    Future<LocalVaultStatus?> Function(LocalVaultService service) action,
  ) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    LocalVaultService? service;
    try {
      service = await ref.read(localVaultServiceProvider.future);
      final status = await action(service!);
      if (!mounted || generation != _generation) return;
      if (status != null) _status = status;
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _error = error;
      // A conversion may have committed before a cleanup failure. Inspect the
      // durable journal instead of guessing whether the original is current.
      try {
        final status = await service?.inspect();
        if (!mounted || generation != _generation) return;
        _status = status;
      } catch (_) {
        // Retain the previous state; never open a database after an unknown
        // result and never expose exception text containing platform paths.
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save(String title, {bool share = false}) =>
      _run((service) async {
        final bytes = await service.prepareRecoveryFile();
        try {
          final io = ref.read(recoveryFileIoProvider);
          if (share) {
            await io.share(bytes, title);
          } else {
            await io.save(bytes, title);
          }
          return await service.inspect();
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      });

  Future<void> _import({required bool recover}) => _run((service) async {
    final Uint8List? bytes = await ref.read(recoveryFileIoProvider).pick();
    if (bytes == null) return null;
    try {
      return await (recover
          ? service.recover(bytes)
          : service.verifyRecoveryFile(bytes));
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  });

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final cleanup = status?.phase == LocalVaultPhase.cleanupPending;
    final retainedOnly = status?.canContinueWithRetainedCopies == true;
    if (!_busy &&
        _error == null &&
        ((status?.canOpenDatabase == true &&
                (!cleanup || _continueWithCleanup || retainedOnly)) ||
            (kIsWeb && _continueBrowserSource))) {
      if (retainedOnly) {
        // A completed encrypted installation needs no recovery action for
        // unrelated retained files. Keep their unconfirmed protection visible.
        final locale =
            ref.watch(appLocaleProvider) ??
            WidgetsBinding.instance.platformDispatcher.locale;
        final l = lookupAppLocalizations(
          Locale(locale.languageCode == 'sl' ? 'sl' : 'en'),
        );
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Semantics(
            label: l.recoveryHistoricalExportsRetained,
            child: Banner(
              key: const ValueKey('vault_retained_copies_notice'),
              message: l.recoveryHistoricalExportsLabel,
              location: BannerLocation.topEnd,
              child: widget.child,
            ),
          ),
        );
      }
      return cleanup || _continueBrowserSource
          ? Builder(
              builder: (context) => Directionality(
                textDirection: TextDirection.ltr,
                child: Banner(
                  message: _warningLabel,
                  location: BannerLocation.topEnd,
                  child: widget.child,
                ),
              ),
            )
          : widget.child;
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: ref.watch(appLocaleProvider),
      themeMode: ref.watch(themeModeProvider),
      theme: buildJivieTheme(Brightness.light),
      darkTheme: buildJivieTheme(Brightness.dark),
      home: Builder(builder: _buildRecovery),
    );
  }

  Widget _buildRecovery(BuildContext context) {
    final l10n = context.l10n;
    final phase = _status?.phase;
    final locked = phase == LocalVaultPhase.recoveryRequired;
    final unsupported = phase == LocalVaultPhase.unsupported;
    final cleanup = phase == LocalVaultPhase.cleanupPending;
    final verified = phase == LocalVaultPhase.migrationPending;
    final mayPrepare =
        phase == LocalVaultPhase.needsSetup ||
        phase == LocalVaultPhase.recoveryUnverified;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recoverySetupTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  l10n.recoveryInstallationScope,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(l10n.recoveryInstallationExplanation),
                const SizedBox(height: 16),
                Text(l10n.recoveryFileWarning),
                const SizedBox(height: 16),
                Text(l10n.recoveryLocalProtectionOnly),
                const SizedBox(height: 24),
                if (unsupported) Text(l10n.recoveryUnsupported),
                if (locked) Text(l10n.recoveryLockedExplanation),
                if (cleanup)
                  Text(
                    _status?.errorCode == 'vault_historical_exports_retained'
                        ? l10n.recoveryHistoricalExportsRetained
                        : l10n.recoveryCleanupPending,
                  ),
                if (_error != null) ...[
                  Text(
                    l10n.recoveryOperationFailed,
                    key: const ValueKey('vault_error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    verified || cleanup
                        ? l10n.recoveryProtectingDevice
                        : l10n.recoveryCheckingDevice,
                  ),
                ],
                if (mayPrepare) ...[
                  FilledButton.icon(
                    key: const ValueKey('vault_save'),
                    onPressed: _busy
                        ? null
                        : () => _save(l10n.recoverySaveFile),
                    icon: const Icon(Icons.save_alt),
                    label: Text(l10n.recoverySaveFile),
                  ),
                  if (ref.read(recoveryFileIoProvider).canShare) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('vault_share'),
                      onPressed: _busy
                          ? null
                          : () => _save(l10n.recoveryShareFile, share: true),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(
                        l10n.recoveryShareFile,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(l10n.recoveryExternalVerification),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('vault_verify'),
                    onPressed: _busy ? null : () => _import(recover: false),
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(l10n.recoverySelectSavedFile),
                  ),
                ],
                if (locked)
                  FilledButton.icon(
                    key: const ValueKey('vault_recover'),
                    onPressed: _busy ? null : () => _import(recover: true),
                    icon: const Icon(Icons.lock_open),
                    label: Text(l10n.recoveryUnlockInstallation),
                  ),
                if (verified || cleanup)
                  FilledButton(
                    key: const ValueKey('vault_migrate'),
                    onPressed: _busy
                        ? null
                        : () => _run((service) => service.migrate()),
                    child: Text(
                      cleanup ? l10n.recoveryRetry : l10n.recoveryProtectDevice,
                    ),
                  ),
                if (cleanup && !_busy)
                  TextButton(
                    key: const ValueKey('vault_continue_cleanup'),
                    onPressed: () => setState(() {
                      _error = null;
                      _continueWithCleanup = true;
                      _warningLabel = l10n.recoveryCleanupLabel;
                    }),
                    child: Text(l10n.recoveryContinue),
                  ),
                if (unsupported && kIsWeb)
                  TextButton(
                    key: const ValueKey('vault_browser_source'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _continueBrowserSource = true;
                            _warningLabel = l10n.recoveryBrowserUnprotected;
                          }),
                    child: Text(l10n.recoveryBrowserContinue),
                  ),
                if (_error != null || phase == null)
                  TextButton(
                    onPressed: _busy ? null : _inspect,
                    child: Text(l10n.recoveryRetry),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
