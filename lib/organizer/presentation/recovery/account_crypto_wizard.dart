import 'account_protection_completion.dart';
import '../onboarding/account_email_card.dart';
import '../onboarding/account_deletion_panel.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_repository.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/crypto_scope_observations.dart';
import 'account_devices_page.dart';
import 'crypto_migration_wizard.dart';
import '../../data/e2ee/crypto_migration_coordinator.dart';
import '../../platform/recovery/recovery_file_io.dart';
import '../../state/account_crypto_provider.dart';
import '../../state/collaboration_provider.dart';

/// Preview servers may offer account key preparation after authentication. The
/// invitation stays in its existing durable workflow and Join remains explicit.
Future<void> showAccountCryptoSetupIfAvailable(
  BuildContext context,
  WidgetRef ref,
) async {
  final identity = ref.read(collaborationProvider).valueOrNull?.session;
  if (identity == null) return;
  AccountCryptoWorkflow? workflow;
  try {
    workflow = await ref.read(accountCryptoPreviewProvider.future);
  } catch (_) {
    // A failed optional preview capability query never undoes a valid login.
    // Settings exposes this same operation with its own retry and error state.
    return;
  }
  if (!context.mounted ||
      workflow == null ||
      ref.read(collaborationProvider).valueOrNull?.session?.partition !=
          identity.partition ||
      ref.read(collaborationProvider).valueOrNull?.session?.deviceId !=
          identity.deviceId) {
    return;
  }
  // The saved-session coordinator also handles first v2 login, preserving one
  // continuous startup route rather than stacking two account wizards.
  if (workflow is AccountCryptoV2Workflow) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => AccountCryptoWizard(workflow: workflow!)),
  );
}

class AccountCryptoPanel extends ConsumerWidget {
  const AccountCryptoPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(
      collaborationProvider.select((state) => state.valueOrNull?.session),
    );
    if (session == null) return const SizedBox.shrink();
    final preview = ref.watch(accountCryptoPreviewProvider);
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.accountRecoveryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            preview.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.accountRecoveryFailed),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(accountCryptoPreviewProvider),
                    child: Text(l.recoveryRetry),
                  ),
                ],
              ),
              data: (workflow) => workflow == null
                  ? Text(l.accountRecoveryUnavailable)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.accountRecoveryPreview),
                        TextButton.icon(
                          icon: const Icon(Icons.key_outlined),
                          label: Text(l.accountRecoveryTitle),
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AccountCryptoWizard(workflow: workflow),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountCryptoWizard extends ConsumerStatefulWidget {
  const AccountCryptoWizard({required this.workflow, super.key});
  final AccountCryptoWorkflow workflow;
  @override
  ConsumerState<AccountCryptoWizard> createState() =>
      _AccountCryptoWizardState();
}

class _AccountCryptoWizardState extends ConsumerState<AccountCryptoWizard> {
  Map<String, dynamic>? _remote;
  String _phase = 'locked';
  bool _canRebind = false;
  bool _scopeRecoveryIncomplete = false;
  bool _busy = true, _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _refresh() => _run(() async {});

  Future<void> _run(Future<void> Function() operation) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await operation();
      final remote = await widget.workflow.status();
      final phase = await widget.workflow.localPhase();
      final canRebind =
          phase != 'ready' &&
              phase != 'pending' &&
              widget.workflow is AccountCryptoV2Workflow
          ? await (widget.workflow as AccountCryptoV2Workflow)
                .canRebindLocalDevice()
          : false;
      if (!mounted || generation != _generation) return;
      final scopeRecoveryIncomplete =
          widget.workflow is AccountCryptoV2Workflow &&
          await (widget.workflow as AccountCryptoV2Workflow)
              .hasIncompleteScopeRecovery();
      if (!mounted || generation != _generation) return;
      _scopeRecoveryIncomplete = scopeRecoveryIncomplete;
      _remote = remote;
      _phase = phase;
      _canRebind = canRebind;
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _failed = error is! CryptoScopeRecoveryIncomplete;
      if (widget.workflow is AccountCryptoV2Workflow) {
        try {
          final incomplete = await (widget.workflow as AccountCryptoV2Workflow)
              .hasIncompleteScopeRecovery();
          if (!mounted || generation != _generation) return;
          _scopeRecoveryIncomplete = incomplete;
        } catch (_) {
          _scopeRecoveryIncomplete = true;
        }
      }
      // An accepted request with a lost ACK remains resumable. Read durable
      // local phase even when the network cannot provide current status.
      try {
        final phase = await widget.workflow.localPhase();
        if (!mounted || generation != _generation) return;
        _phase = phase;
      } catch (_) {}
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save(String title, {bool share = false}) => _run(() async {
    final bytes = await widget.workflow.prepareRecoveryFile();
    try {
      final io = ref.read(recoveryFileIoProvider);
      if (share) {
        await io.share(bytes, title, accountOnly: true);
      } else {
        await io.save(bytes, title, accountOnly: true);
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  });

  Future<void> _import({required bool recover}) async {
    if (recover) {
      final l = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.cryptoRecoveryRevokeTitle),
          content: Text(l.cryptoRecoveryRevokeExplanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.cryptoRecoveryRevokeConfirm),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    await _run(() async {
      final Uint8List? file = await ref.read(recoveryFileIoProvider).pick();
      if (file == null) return;
      try {
        await (recover
            ? widget.workflow.recover(file)
            : widget.workflow.verifyAndInitialize(file));
        if (recover && widget.workflow is AccountCryptoV2Workflow) {
          await (widget.workflow as AccountCryptoV2Workflow)
              .restoreScopesFromFile(file);
        }
      } finally {
        file.fillRange(0, file.length, 0);
      }
    });
  }

  Future<void> _retryScopeRecovery() => _run(() async {
    final file = await ref.read(recoveryFileIoProvider).pick();
    if (file == null) return;
    try {
      await (widget.workflow as AccountCryptoV2Workflow).restoreScopesFromFile(
        file,
      );
    } finally {
      file.fillRange(0, file.length, 0);
    }
  });

  Widget _buttonLabel(String label) => Text(label, textAlign: TextAlign.center);
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final initialized = _remote?['initialized'] == true;
    final ready = _phase == 'ready' && !_scopeRecoveryIncomplete;
    final recoveringScopes = _phase == 'ready' && _scopeRecoveryIncomplete;
    final pending = _phase == 'verified' || _phase == 'pending';
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: shape, padding: padding),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(shape: shape, padding: padding),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.workflow is AccountCryptoV2Workflow
                ? l.recoverySetupTitle
                : l.accountRecoveryTitle,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    l.accountRecoveryScope,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(l.accountRecoveryExplanation),
                  if (ref.exists(collaborationProvider) &&
                      ref.watch(collaborationProvider).valueOrNull?.session !=
                          null) ...[
                    const SizedBox(height: 12),
                    Text(l.deletionWithoutKeysExplanation),
                    TextButton.icon(
                      key: const ValueKey(
                        'recovery-account-delete-without-keys',
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(l.deletionWithoutKeys)),
                            body: const SingleChildScrollView(
                              padding: EdgeInsets.all(16),
                              child: AccountDeletionPanel(),
                            ),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.person_remove_outlined),
                      label: Text(l.deletionWithoutKeys),
                    ),
                  ],
                  if (widget.workflow is AccountCryptoV2Workflow &&
                      ref.exists(collaborationProvider) &&
                      ref.watch(collaborationProvider).valueOrNull?.session !=
                          null)
                    AccountEmailCard(
                      session: ref
                          .watch(collaborationProvider)
                          .valueOrNull!
                          .session!,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    l.accountRecoveryPreview,
                    key: const ValueKey('account_crypto_preview_warning'),
                  ),
                  const SizedBox(height: 16),
                  Text(l.accountRecoveryManualShare),
                  if (widget.workflow is AccountCryptoV2Workflow)
                    TextButton.icon(
                      icon: const Icon(Icons.devices_outlined),
                      label: _buttonLabel(l.cryptoDevicesTitle),
                      onPressed: _busy
                          ? null
                          : () async {
                              await Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => AccountDevicesPage(
                                    workflow:
                                        widget.workflow
                                            as AccountCryptoV2Workflow,
                                  ),
                                ),
                              );
                              if (mounted) await _refresh();
                            },
                    ),
                  const SizedBox(height: 24),
                  if (_busy) const LinearProgressIndicator(),
                  if (_failed)
                    Text(
                      l.accountRecoveryFailed,
                      key: const ValueKey('account_crypto_error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (recoveringScopes) ...[
                    Text(
                      l.accountRecoveryScopesPending,
                      key: const ValueKey('account_crypto_scopes_pending'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('account_crypto_scopes_retry'),
                      onPressed: _busy ? null : _retryScopeRecovery,
                      icon: const Icon(Icons.file_open_outlined),
                      label: _buttonLabel(l.accountRecoveryScopesRetry),
                    ),
                    TextButton.icon(
                      key: const ValueKey('account_crypto_scopes_partial'),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: _buttonLabel(l.accountRecoveryUseRecovered),
                    ),
                  ],
                  if (ready)
                    Text(
                      widget.workflow is AccountCryptoV2Workflow
                          ? l.accountRecoveryV2Prepared
                          : l.accountRecoveryReady,
                      key: const ValueKey('account_crypto_prepared'),
                    ),
                  if (ready && widget.workflow is AccountCryptoV2Workflow)
                    FilledButton.icon(
                      key: const ValueKey('account_crypto_migration'),
                      icon: const Icon(Icons.shield_outlined),
                      label: _buttonLabel(l.cryptoMigrationContinue),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => CryptoMigrationWizard(
                                  onFinished: () => finishAccountProtection(
                                    context,
                                    widget.workflow as AccountCryptoV2Workflow,
                                  ),
                                  cachedLabels: {
                                    for (final scope
                                        in ref
                                                .read(collaborationProvider)
                                                .valueOrNull
                                                ?.scopes ??
                                            [])
                                      scope.id: scope.name,
                                  },
                                  controller: AccountMigrationController(
                                    CryptoMigrationCoordinator(
                                      account:
                                          widget.workflow
                                              as AccountCryptoV2Workflow,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  if (pending)
                    FilledButton(
                      key: const ValueKey('account_crypto_resume'),
                      onPressed: _busy
                          ? null
                          : () => _run(widget.workflow.resume),
                      child: _buttonLabel(l.accountRecoveryResume),
                    ),
                  if (pending && _failed)
                    OutlinedButton(
                      key: const ValueKey('account_crypto_rebase'),
                      onPressed: _busy ? null : () => _import(recover: true),
                      child: _buttonLabel(l.accountRecoveryRebase),
                    ),
                  if (!initialized &&
                      !ready &&
                      !pending &&
                      _remote != null) ...[
                    FilledButton.icon(
                      key: const ValueKey('account_crypto_save'),
                      onPressed: _busy ? null : () => _save(l.recoverySaveFile),
                      icon: const Icon(Icons.save_alt),
                      label: _buttonLabel(l.recoverySaveFile),
                    ),
                    if (ref.read(recoveryFileIoProvider).canShare) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('account_crypto_share'),
                        onPressed: _busy
                            ? null
                            : () => _save(l.recoveryShareFile, share: true),
                        icon: const Icon(Icons.share_outlined),
                        label: _buttonLabel(l.recoveryShareFile),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(l.recoveryExternalVerification),
                    if (_phase == 'prepared')
                      OutlinedButton.icon(
                        key: const ValueKey('account_crypto_verify'),
                        onPressed: _busy ? null : () => _import(recover: false),
                        icon: const Icon(Icons.file_open_outlined),
                        label: _buttonLabel(l.accountRecoveryVerify),
                      ),
                  ],
                  if (initialized &&
                      !ready &&
                      !pending &&
                      !recoveringScopes) ...[
                    Text(l.accountRecoveryLocked),
                    if (_canRebind)
                      FilledButton.icon(
                        key: const ValueKey('account_crypto_local_approval'),
                        onPressed: _busy
                            ? null
                            : () => _run(
                                (widget.workflow as AccountCryptoV2Workflow)
                                    .rebindLocalDevice,
                              ),
                        icon: const Icon(Icons.verified_user_outlined),
                        label: _buttonLabel(l.cryptoRebindLocalDevice),
                      ),
                    if (_canRebind) const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const ValueKey('account_crypto_recover'),
                      onPressed: _busy ? null : () => _import(recover: true),
                      icon: const Icon(Icons.file_open_outlined),
                      label: _buttonLabel(l.recoverySelectSavedFile),
                    ),
                  ],
                  if (_failed)
                    TextButton(
                      onPressed: _busy ? null : _refresh,
                      child: Text(l.recoveryRetry),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
