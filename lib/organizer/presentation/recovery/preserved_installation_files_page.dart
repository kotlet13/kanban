import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/local_vault_open.dart';
import '../../data/preserved_installation_files.dart';
import '../../platform/private_file_io.dart';
import '../backup/backup_file_io.dart';
import '../password_visibility.dart';

final preservedInstallationFileCodecProvider =
    Provider<PreservedInstallationFileCodec>(
      (ref) => const PreservedInstallationFileCodec(),
    );

final preservedInstallationFilesProvider =
    Provider<Future<PreservedInstallationFiles>>(
      (ref) => openPreservedInstallationFiles(),
    );

/// Deliberately outside the account backup: these old app-owned files may
/// belong to any profile previously used on this installation.
class PreservedInstallationFilesPage extends ConsumerStatefulWidget {
  const PreservedInstallationFilesPage({super.key});
  @override
  ConsumerState<PreservedInstallationFilesPage> createState() => _FilesState();
}

class _FilesState extends ConsumerState<PreservedInstallationFilesPage> {
  final _password = TextEditingController();
  List<PreservedInstallationFile> _files = const [];
  PreservedInstallationFile? _selected;
  Uint8List? _imported;
  String? _message;
  bool _busy = false, _reviewed = false;
  @override
  void initState() {
    super.initState();
    _run(() => _load());
  }

  @override
  void dispose() {
    _password.dispose();
    _imported?.fillRange(0, _imported!.length, 0);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _message = context.l10n.backupReadError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load({String? after}) async {
    final files = await (await ref.read(
      preservedInstallationFilesProvider,
    )).list(afterId: after);
    if (mounted)
      setState(() {
        _files = files;
        _selected = null;
        _reviewed = false;
      });
  }

  Future<Uint8List> _bytes() async => _imported == null
      ? (await ref.read(preservedInstallationFilesProvider)).read(_selected!.id)
      : Uint8List.fromList(_imported!);
  Future<void> _import() async {
    final input = await ref
        .read(backupFileIoProvider)
        .pick(maxBytes: 128 * 1024 * 1024);
    if (input == null) return;
    try {
      final opened = await ref
          .read(preservedInstallationFileCodecProvider)
          .decrypt(input.bytes, _password.text);
      if (!mounted) {
        opened.bytes.fillRange(0, opened.bytes.length, 0);
        return;
      }
      _imported?.fillRange(0, _imported!.length, 0);
      setState(() {
        _imported = opened.bytes;
        _selected = PreservedInstallationFile(
          'imported',
          opened.name,
          opened.bytes.length,
        );
        _reviewed = false;
      });
    } finally {
      input.bytes.fillRange(0, input.bytes.length, 0);
    }
  }

  Future<void> _save({required bool encrypted}) async {
    final selected = _selected!;
    final bytes = await _bytes();
    Uint8List? sealed;
    try {
      if (!mounted) return;
      if (encrypted) {
        sealed = await ref
            .read(preservedInstallationFileCodecProvider)
            .encrypt(
              name: selected.name,
              bytes: bytes,
              password: _password.text,
            );
        if (!mounted) return;
        final result = await ref
            .read(backupFileIoProvider)
            .save(
              sealed,
              title: context.l10n.backupSave,
              name: 'jivie-preserved-file.vsakdan',
            );
        if (mounted)
          setState(
            () => _message = result == BackupSaveStatus.cancelled
                ? context.l10n.backupSaveCancelled
                : context.l10n.backupSaved,
          );
      } else {
        final title = context.l10n.preservedFilesSaveOriginal;
        final saved = usesPrivateMobileFileIo
            ? await savePrivateFile(
                    bytes: bytes,
                    name: selected.name,
                    title: title,
                  ) !=
                  PrivateSaveStatus.cancelled
            : await FilePicker.platform.saveFile(
                    dialogTitle: title,
                    fileName: selected.name,
                    type: FileType.any,
                    bytes: bytes,
                  ) !=
                  null;
        if (mounted)
          setState(
            () => _message = saved
                ? context.l10n.backupSaved
                : context.l10n.backupSaveCancelled,
          );
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      sealed?.fillRange(0, sealed.length, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.preservedFilesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(l.preservedFilesExplanation),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) Text(_message!),
          if (_files.isEmpty && !_busy) Text(l.preservedFilesEmpty),
          for (final file in _files)
            ListTile(
              selected: _selected?.id == file.id,
              leading: Icon(
                _selected?.id == file.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(file.name),
              subtitle: Text('${file.size} B'),
              onTap: _busy
                  ? null
                  : () => setState(() {
                      _imported?.fillRange(0, _imported!.length, 0);
                      _imported = null;
                      _selected = file;
                      _reviewed = false;
                    }),
            ),
          if (_files.length == 50)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => _load(after: _files.last.id)),
              child: Text(l.preservedFilesNext),
            ),
          if (_selected != null) ...[
            Text(_selected!.name),
            CheckboxListTile(
              value: _reviewed,
              title: Text(l.preservedFilesReview),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _reviewed = v == true),
            ),
          ],
          PasswordVisibility(
            enabled: !_busy,
            builder: (obscure, _) => TextField(
              controller: _password,
              obscureText: obscure,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: l.backupPassword,
                helperText: l.backupPasswordRule,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || !_reviewed || _selected == null
                ? null
                : () => _run(() => _save(encrypted: true)),
            child: Text(l.backupSave),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy || !_reviewed || _selected == null
                ? null
                : () => _run(() => _save(encrypted: false)),
            child: Text(l.preservedFilesSaveOriginal),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : () => _run(_import),
            child: Text(l.preservedFilesOpen),
          ),
        ],
      ),
    );
  }
}
