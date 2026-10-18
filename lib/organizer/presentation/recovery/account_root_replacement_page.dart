import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../platform/recovery/recovery_file_io.dart';

/// Both external files remain with the user. Save does not authorize a root
/// change: a fresh external reimport precedes the immutable signed transition.
class AccountRootReplacementPage extends ConsumerStatefulWidget {
  const AccountRootReplacementPage({required this.workflow, super.key});
  final AccountCryptoV2Workflow workflow;
  @override
  ConsumerState<AccountRootReplacementPage> createState() =>
      _AccountRootReplacementPageState();
}

class _AccountRootReplacementPageState
    extends ConsumerState<AccountRootReplacementPage> {
  Uint8List? _oldFile;
  bool _busy = false, _failed = false, _complete = false;
  String _phase = 'locked';
  @override
  void initState() {
    super.initState();
    _phaseLoad();
  }

  Future<void> _phaseLoad() async {
    try {
      final phase = await widget.workflow.localPhase();
      if (mounted) setState(() => _phase = phase);
    } catch (_) {}
  }

  @override
  void dispose() {
    _oldFile?.fillRange(0, _oldFile!.length, 0);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await body();
      await _phaseLoad();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _selectOld() async {
    if (_oldFile != null) return true;
    final file = await ref.read(recoveryFileIoProvider).pick();
    if (file == null) return false;
    if (!mounted) {
      file.fillRange(0, file.length, 0);
      return false;
    }
    _oldFile = file;
    return true;
  }

  Future<void> _save({bool share = false}) => _run(() async {
    final title = context.l10n.recoverySaveFile;
    if (!await _selectOld()) return;
    final file = await widget.workflow.prepareRootReplacement(_oldFile!);
    try {
      final io = ref.read(recoveryFileIoProvider);
      if (share) {
        await io.share(file, title, accountOnly: true);
      } else {
        await io.save(file, title, accountOnly: true);
      }
    } finally {
      file.fillRange(0, file.length, 0);
    }
  });
  Future<void> _verify() => _run(() async {
    if (!await _selectOld()) return;
    final file = await ref.read(recoveryFileIoProvider).pick();
    if (file == null) return;
    try {
      if (!mounted) return;
      final l = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.cryptoReplaceRecoveryTitle),
          content: Text(
            '${l.cryptoReplaceRecoveryExplanation}\n\n${l.cryptoKeepBothRecoveryFiles}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.cryptoReplaceRecoveryConfirm),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await widget.workflow.verifyAndRotateRoot(
        oldExternalFile: _oldFile!,
        newExternalFile: file,
      );
      _oldFile!.fillRange(0, _oldFile!.length, 0);
      _oldFile = null;
      if (mounted) setState(() => _complete = true);
    } finally {
      file.fillRange(0, file.length, 0);
    }
  });
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pending = _phase == 'pending';
    return Scaffold(
      appBar: AppBar(title: Text(l.cryptoReplaceRecoveryTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(l.cryptoReplaceRecoveryExplanation),
                const SizedBox(height: 16),
                Text(l.cryptoKeepBothRecoveryFiles),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_failed)
                  Text(
                    l.accountRecoveryFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_complete)
                  Text(l.cryptoRecoveryReplacementComplete)
                else ...[
                  if (!pending)
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _save(),
                      icon: const Icon(Icons.save_alt),
                      label: Text(l.cryptoSaveNewRecoveryFile),
                    ),
                  if (!pending &&
                      ref.read(recoveryFileIoProvider).canShare) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _save(share: true),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(
                        l.recoveryShareFile,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _verify,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(l.cryptoImportNewRecoveryFile),
                  ),
                  if (pending)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await widget.workflow.resume();
                              if (!await widget.workflow
                                  .rootReplacementConfirmed())
                                throw StateError('replacement_not_confirmed');
                              if (mounted) setState(() => _complete = true);
                            }),
                      child: Text(l.accountRecoveryResume),
                    ),
                ],
                const SizedBox(height: 16),
                Text(l.cryptoHistoryPendingExplanation),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
