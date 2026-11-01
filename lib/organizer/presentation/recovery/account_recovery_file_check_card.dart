import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/account_directory_v2.dart';
import '../../platform/recovery/recovery_file_io.dart';
import '../../state/collaboration_provider.dart';

/// Account settings entry. Rendering it never starts setup, recovery or sync.
class AccountRecoveryFileCheckCard extends ConsumerWidget {
  const AccountRecoveryFileCheckCard({super.key, required this.session});

  final AccountSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool current() =>
        context.mounted &&
        identical(
          ref.read(collaborationProvider).valueOrNull?.session,
          session,
        );
    return RecoveryFileCheckCard(
      sessionIdentity: session,
      isCurrent: current,
      pickFile: () => ref.read(recoveryFileIoProvider).pick(),
      checkFile: (bytes) async {
        if (!current()) {
          throw const CryptoDirectoryException('directory_stale_identity');
        }
        final workflow = await ref
            .read(collaborationProvider.notifier)
            .accountCryptoPreview();
        if (!current()) {
          throw const CryptoDirectoryException('directory_stale_identity');
        }
        if (workflow is! AccountCryptoV2Workflow) {
          throw const CryptoDirectoryException('recovery_check_unavailable');
        }
        await workflow.checkRecoveryFile(bytes);
      },
    );
  }
}

enum _CheckStatus { idle, busy, success, cancelled, failed }

/// Only the selected bytes cross this seam, never a filename or file path.
/// A new choice always invalidates the previous result before opening a picker.
class RecoveryFileCheckCard extends StatefulWidget {
  const RecoveryFileCheckCard({
    super.key,
    required this.sessionIdentity,
    required this.isCurrent,
    required this.pickFile,
    required this.checkFile,
  });

  final Object sessionIdentity;
  final bool Function() isCurrent;
  final Future<Uint8List?> Function() pickFile;
  final Future<void> Function(Uint8List bytes) checkFile;

  @override
  State<RecoveryFileCheckCard> createState() => _RecoveryFileCheckCardState();
}

class _RecoveryFileCheckCardState extends State<RecoveryFileCheckCard> {
  _CheckStatus _status = _CheckStatus.idle;
  String? _failure;
  int _generation = 0;

  @override
  void didUpdateWidget(RecoveryFileCheckCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessionIdentity, widget.sessionIdentity)) {
      _generation++;
      _status = _CheckStatus.idle;
      _failure = null;
    }
  }

  Future<void> _check() async {
    if (_status == _CheckStatus.busy || !widget.isCurrent()) return;
    final generation = ++_generation;
    final isCurrent = widget.isCurrent;
    final pick = widget.pickFile;
    final check = widget.checkFile;
    bool current() => mounted && generation == _generation && isCurrent();
    setState(() {
      _status = _CheckStatus.busy;
      _failure = null;
    });
    Uint8List? bytes;
    try {
      bytes = await pick();
      if (!current()) return;
      if (bytes == null) {
        setState(() => _status = _CheckStatus.cancelled);
        return;
      }
      await check(bytes);
      if (current()) setState(() => _status = _CheckStatus.success);
    } catch (error) {
      if (current()) {
        setState(() {
          _failure = _safeFailure(error);
          _status = _CheckStatus.failed;
        });
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted && generation == _generation && !isCurrent()) {
        setState(() {
          _status = _CheckStatus.idle;
          _failure = null;
        });
      }
    }
  }

  // Store only a closed vocabulary. Raw errors, file content and identifiers
  // never become widget state, logs, snackbars or diagnostic copy.
  String _safeFailure(Object error) {
    final code = error is CryptoDirectoryException
        ? error.code
        : error is CollaborationException
        ? error.code
        : null;
    return switch (code) {
      'recovery_check_unavailable' => 'unavailable',
      'directory_stale_identity' ||
      'session_changed' ||
      'auth_required' ||
      'session_expired' ||
      'invalid_credentials' ||
      'device_revoked' => 'session',
      'directory_recovery_status_changed' => 'sync',
      'directory_recovery_file_invalid' => 'file',
      'directory_recovery_ciphertext' => 'ciphertext',
      'directory_recovery_identity' => 'identity',
      'network' || 'offline' || 'network_error' || 'timeout' => 'network',
      _ => error is FormatException ? 'file' : 'failed',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final message = switch (_status) {
      _CheckStatus.success => l.recoveryCheckSuccess,
      _CheckStatus.cancelled => l.recoveryCheckCancelled,
      _CheckStatus.failed => switch (_failure) {
        'unavailable' => l.recoveryCheckUnavailable,
        'session' => l.recoveryCheckSessionChanged,
        'sync' => l.recoveryCheckSyncRequired,
        'identity' => l.recoveryCheckIdentity,
        'ciphertext' => l.recoveryCheckCiphertext,
        'network' => l.recoveryCheckNetwork,
        'file' => l.recoveryCheckInvalidFile,
        _ => l.recoveryCheckFailed,
      },
      _CheckStatus.busy => l.recoveryCheckProgress,
      _CheckStatus.idle => null,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.recoveryCheckTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l.recoveryCheckDescription),
            const SizedBox(height: 8),
            Text(l.recoveryCheckScope),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('recovery-file-check'),
              onPressed: _status == _CheckStatus.busy ? null : _check,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(l.recoveryCheckTitle),
            ),
            if (_status == _CheckStatus.busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    key: const ValueKey('recovery-file-check-result'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
