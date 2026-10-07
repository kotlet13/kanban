import 'dart:typed_data';
import 'dart:convert';
import 'backup_file_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../../state/providers.dart';
import '../../platform/notification_providers.dart';
import '../onboarding/getting_started.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../../state/portable_backup_provider.dart';
import '../organizer_widgets.dart';
import '../shared/sharing_errors.dart';
import 'backup_counts.dart';

Future<void> showBackupWizard(BuildContext context, {required bool restore}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackupWizard(restore: restore),
    );

class BackupWizard extends ConsumerStatefulWidget {
  const BackupWizard({super.key, required this.restore});
  final bool restore;
  @override
  ConsumerState<BackupWizard> createState() => _BackupWizardState();
}

class _BackupWizardState extends ConsumerState<BackupWizard> {
  final _password = TextEditingController(),
      _confirm = TextEditingController(),
      _form = GlobalKey<FormState>();
  String? _identity;
  String get _currentIdentity {
    final s = ref.read(collaborationProvider).valueOrNull?.session;
    return '${s?.partition}:${s?.deviceId}';
  }

  bool get _validIdentity =>
      _identity == _currentIdentity &&
      ref.read(collaborationProvider).valueOrNull?.sessionInvalid != true;
  bool _busy = false, _done = false;
  String? _error, _fileName, _saveMessage;
  Uint8List? _bytes;
  BackupPreview? _preview;
  int? _targetRevision;
  BackupRestoreMode _mode = BackupRestoreMode.merge;
  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _bytes = null;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _message(e);
          if (e is CollaborationException && e.code == 'backup_stale') {
            _preview = null;
            _targetRevision = null;
            _saveMessage = null;
            if (!widget.restore) _bytes = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object e) {
    final l = context.l10n;
    if (e is BackupFileTooLarge) return l.backupTooLarge;
    if (e is CollaborationException) {
      return switch (e.code) {
        'backup_auth_failed' || 'backup_invalid' => l.backupWrongPassword,
        'backup_unsupported' => l.backupUnsupported,
        'backup_stale' || 'stale_revision' => l.backupChanged,
        'backup_conflict' => l.backupMergeConflict,
        'backup_too_large' => l.backupTooLarge,
        'backup_password_invalid' => l.backupPasswordRule,
        _ => sharingErrorMessage(context, e),
      };
    }
    return e is FormatException ? l.backupWrongPassword : l.backupReadError;
  }

  Future<void> _pick() async {
    final result = await ref
        .read(backupFileIoProvider)
        .pick(maxBytes: 64 * 1024 * 1024);
    if (result == null || !mounted || !_validIdentity) return;
    setState(() {
      _bytes = result.bytes;
      _fileName = result.name;
      _preview = null;
    });
  }

  Future<void> _prepare() async {
    if (!_form.currentState!.validate()) return;
    final controller = ref.read(portableBackupProvider.notifier),
        password = _password.text;
    final bytes = widget.restore
        ? _bytes
        : await controller.exportEncryptedBackup(password);
    if (bytes == null) throw const FormatException();
    final preview = await controller.inspectEncryptedBackup(bytes, password);
    final personal = await ref.read(organizerProvider.future);
    if (!mounted || !_validIdentity) return;
    setState(() {
      _bytes = bytes;
      _preview = preview;
      _targetRevision = personal.revision;
    });
  }

  Future<void> _save() async {
    if (!_validIdentity || _bytes == null) return;
    await ref
        .read(portableBackupProvider.notifier)
        .validatePreparedExport(_preview!.backupId);
    if (!mounted || !_validIdentity) return;
    final l = context.l10n;
    final status = await ref
        .read(backupFileIoProvider)
        .save(
          _bytes!,
          title: l.backupSave,
          name:
              'jivie-${DateTime.now().toIso8601String().substring(0, 10)}.vsakdan',
        );
    if (mounted && _validIdentity) {
      setState(
        () => _saveMessage = switch (status) {
          BackupSaveStatus.saved => l.backupSaved,
          BackupSaveStatus.cancelled => l.backupSaveCancelled,
          BackupSaveStatus.downloadStarted => l.backupDownloadStarted,
        },
      );
    }
  }

  Future<void> _restore() async {
    final l = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.backupRestoreConfirm),
        content: Text(
          _mode == BackupRestoreMode.replace
              ? l.backupReplaceDescription
              : l.backupMergeDescription,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.backupRestoreConfirm),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !_validIdentity) return;
    await ref
        .read(portableBackupProvider.notifier)
        .restoreEncryptedBackup(
          _bytes!,
          _password.text,
          mode: _mode,
          expectedPersonalRevision: _targetRevision!,
        );
    if (!mounted || !_validIdentity) return;
    final locale = await ref.read(localeStoreProvider).read();
    final theme = await ref.read(themeModeStoreProvider).read();
    if (!mounted || !_validIdentity) return;
    ref.read(appLocaleProvider.notifier).state = locale;
    ref.read(themeModeProvider.notifier).state = theme;
    ref.invalidate(gettingStartedSeenProvider);
    ref.invalidate(localReminderSettingsProvider);
    _password.clear();
    _confirm.clear();
    _bytes = null;
    setState(() => _done = true);
  }

  Widget _passwordFields() {
    final l = context.l10n;
    return Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            key: const ValueKey('backup-password'),
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            enabled: !_busy,
            decoration: InputDecoration(labelText: l.backupPassword),
            validator: (value) =>
                (value ?? '').runes.length < 12 ||
                    utf8.encode(value ?? '').length > 1024
                ? l.backupPasswordRule
                : null,
          ),
          if (!widget.restore) ...[
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('backup-confirm'),
              controller: _confirm,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              enabled: !_busy,
              decoration: InputDecoration(labelText: l.sharingConfirmPassword),
              validator: (value) =>
                  value == _password.text ? null : l.sharingPasswordMismatch,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shared = ref.watch(collaborationProvider);
    final l = context.l10n;
    if (shared.isLoading && shared.valueOrNull == null) {
      return AlertDialog(
        title: Text(widget.restore ? l.backupRestore : l.backupTitle),
        content: const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ],
      );
    }
    _identity ??= _currentIdentity;
    final current = _validIdentity;
    if (!current) {
      _bytes = null;
      _preview = null;
      _password.clear();
      _confirm.clear();
    }
    return AlertDialog(
      title: Text(widget.restore ? l.backupRestore : l.backupTitle),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!current)
                Text(l.sharingSessionExpired)
              else if (_done)
                Text(l.backupRestored)
              else ...[
                Text(l.backupDescription),
                const SizedBox(height: 12),
                Text(l.backupPasswordHint),
                const SizedBox(height: 16),
                if (_preview == null) ...[
                  if (widget.restore) ...[
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(_pick),
                      icon: const Icon(Icons.folder_open),
                      label: Text(l.backupPick),
                    ),
                    if (_fileName != null) Text(_fileName!),
                    const SizedBox(height: 16),
                  ],
                  _passwordFields(),
                ] else ...[
                  Text(
                    l.backupReview,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${l.backupCreatedAt}: ${organizerDate(context, _preview!.createdAt)}',
                  ),
                  Text(
                    '${l.backupSourceAccount}: ${_preview!.sourceAccount ?? l.sharingPersonal}',
                  ),
                  Text(
                    '${l.backupSourceServer}: ${_preview!.sourceServer ?? l.backupLocalOnly}',
                  ),
                  Text(l.backupAccountMatches),
                  BackupCounts(counts: _preview!.personalCounts),
                  Text('${l.backupScopes}: ${_preview!.scopeCount}'),
                  Text('${l.backupPending}: ${_preview!.pendingCount}'),
                  const SizedBox(height: 12),
                  Text(l.backupCredentialsExcluded),
                  if (_preview!.hasRemoteRecovery)
                    Text(l.backupRemoteQuarantine),
                  Text(l.backupCompleteness),
                  if (_preview!.incompleteScopes.isNotEmpty)
                    Text(l.backupIncomplete),
                  if (_saveMessage != null) Text(_saveMessage!),
                  if (widget.restore) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<BackupRestoreMode>(
                      initialValue: _mode,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: BackupRestoreMode.merge,
                          child: Text(l.backupMerge),
                        ),
                        DropdownMenuItem(
                          value: BackupRestoreMode.replace,
                          child: Text(l.backupReplace),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _mode = value!),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _mode == BackupRestoreMode.replace
                          ? l.backupReplaceDescription
                          : l.backupMergeDescription,
                    ),
                  ],
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.close),
        ),
        if (current && !_done)
          FilledButton(
            onPressed: _busy || (widget.restore && _bytes == null)
                ? null
                : () => _run(
                    _preview == null
                        ? _prepare
                        : widget.restore
                        ? _restore
                        : _save,
                  ),
            child: Text(
              _preview == null
                  ? widget.restore
                        ? l.backupOpen
                        : l.backupPrepare
                  : widget.restore
                  ? l.backupRestoreConfirm
                  : l.backupSave,
            ),
          ),
      ],
    );
  }
}
