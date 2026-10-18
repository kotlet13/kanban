import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../platform/private_file_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/crypto_restore_reconciler.dart';
import '../../data/e2ee/session_crypto_access.dart';
import '../../platform/recovery/recovery_file_io.dart';
import 'account_devices_page.dart';
import 'scope_recovery_page.dart';

/// Restored evidence is deliberately reviewed separately from automatic sync.
/// Backing out preserves every retained candidate and all unsent drafts.
class CryptoRestorePage extends ConsumerStatefulWidget {
  const CryptoRestorePage({required this.account,this.serviceFactory, super.key});
  final AccountCryptoV2Workflow account;
  final CryptoRestoreReconciler Function(AccountCryptoV2Workflow)? serviceFactory;
  @override
  ConsumerState<CryptoRestorePage> createState() => _CryptoRestorePageState();
}

class _CryptoRestorePageState extends ConsumerState<CryptoRestorePage> {
  late final service = widget.serviceFactory?.call(widget.account) ?? CryptoRestoreReconciler(widget.account);
  CryptoRestoreReport? _report;
  bool _busy = false, _failed = false, _complete = false;
  List<RecoveredCryptoDocumentDraft> _drafts = [];
  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _inspect();
  }

  bool get _current => mounted && widget.account.directory.isCurrent();
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (_current) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inspect() => _run(() async {
    final result = await service.inspect();
    if (_current) setState(() => _report = result);
  });
  Future<void> _confirm() => _run(() async {
    await service.reconcile();
    if (_current) setState(() => _complete = true);
  });
  Future<void> _keys() => _run(() async {
    final bytes = await ref.read(recoveryFileIoProvider).pick();
    if (bytes == null) return;
    try {
      if (!_current) return;
      final recovered = await service.recoverDocumentDrafts(bytes);
      if (!_current) {
        for (final draft in recovered) {
          draft.dispose();
        }
        return;
      }
      for (final draft in _drafts) {
        draft.dispose();
      }
      setState(() => _drafts = recovered);
      final access = SessionCryptoAccess(account: widget.account);
      for (final scope
          in _complete ? await service.verifiedScopes() : <String>[]) {
        await access.recoverScopeCandidateKeys(scope, bytes);
        if (!_current) return;
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  });
  @override
  Widget build(BuildContext context) {
    final l = context.l10n, report = _report;
    return Scaffold(
      appBar: AppBar(title: Text(l.cryptoRestoreTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(l.cryptoRestoreExplanation),
                const SizedBox(height: 20),
                if (_busy) const LinearProgressIndicator(),
                if (_failed)
                  Text(
                    l.accountRecoveryFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (report != null)
                  Text(
                    l.cryptoRestoreCounts(
                      report.backupCount,
                      report.scopeCount,
                      report.recordCount,
                    ),
                  ),
                if (report != null &&
                    report.identityReviewAccounts.isNotEmpty) ...[
                  Text(l.cryptoRestoreCompareIdentities),
                  OutlinedButton(style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),padding:const EdgeInsets.symmetric(horizontal:20,vertical:14)),
                    onPressed: _busy
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AccountDevicesPage(
                                  workflow: widget.account,
                                ),
                              ),
                            );
                            if (_current) await _inspect();
                          },
                    child: Text(l.cryptoCompareContact),
                  ),
                ],
                if (report != null &&
                    report.historyReviewScopes.isNotEmpty) ...[
                  Text(l.cryptoRestoreHistoryPending),
                  for (final scope in report.historyReviewScopes)
                    OutlinedButton(style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),padding:const EdgeInsets.symmetric(horizontal:20,vertical:14)),
                      onPressed: _busy
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ScopeRecoveryPage(
                                    account: widget.account,
                                    scopeId: scope,
                                    label: l.cryptoScopeRecoveryTitle,
                                  ),
                                ),
                              );
                              if (_current) await _inspect();
                            },
                      child: Text(l.cryptoScopeRecoveryTitle),
                    ),
                ],
                if (_complete) Text(l.cryptoRestoreComplete),
                if (!_complete && report?.canReconcile == true)
                  FilledButton(style:FilledButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),padding:const EdgeInsets.symmetric(horizontal:20,vertical:14)),
                    onPressed: _busy ? null : _confirm,
                    child: Text(l.cryptoRestoreConfirm),
                  ),
                if (report != null)
                  OutlinedButton(style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),padding:const EdgeInsets.symmetric(horizontal:20,vertical:14)),
                    onPressed: _busy ? null : _keys,
                    child: Text(l.cryptoRestoreKeys),
                  ),
                for (var i = 0; i < _drafts.length; i++)
                  ListTile(
                    title: Text('${l.cryptoRestoreDraft} ${i + 1}'),
                    subtitle: Text('${_drafts[i].bytes.length} B'),
                    trailing: IconButton(
                      icon: const Icon(Icons.save_alt),
                      tooltip: l.save,
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final draft = _drafts[i],
                                  name = 'Jivie-restored-${i + 1}.bin';
                              if (usesPrivateMobileFileIo) {
                                await savePrivateFile(
                                  bytes: draft.bytes,
                                  name: name,
                                  title: l.cryptoRestoreDraft,
                                );
                              } else {
                                await FilePicker.platform.saveFile(
                                  dialogTitle: l.cryptoRestoreDraft,
                                  fileName: name,
                                  type: FileType.any,
                                  bytes: draft.bytes,
                                );
                              }
                            }),
                    ),
                  ),
                TextButton(
                  onPressed: _busy ? null : _inspect,
                  child: Text(l.cryptoRestoreVerify),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.cryptoContinueLocally),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
