import 'dart:async';
import 'package:flutter/material.dart';

import '../../domain/attachment_models.dart';
import 'attachment_file_io.dart';
import 'attachment_strings.dart';

class AttachmentsPanel extends StatefulWidget {
  const AttachmentsPanel({
    super.key,
    required this.gateway,
    required this.canEdit,
    this.changes,
    this.canDelete,
    this.filePicker,
    this.fileExporter,
    this.onReport,
  });
  final AttachmentGateway gateway;
  final bool canEdit;
  final Stream<void>? changes;
  final bool Function(AttachmentMetadata)? canDelete;
  final AttachmentFilePicker? filePicker;
  final AttachmentFileExporter? fileExporter;
  final Future<void> Function(AttachmentMetadata)? onReport;

  @override
  State<AttachmentsPanel> createState() => _AttachmentsPanelState();
}

class _AttachmentsPanelState extends State<AttachmentsPanel> {
  List<AttachmentMetadata> _items = [];
  bool _loading = true, _busy = false;
  int _generation = 0;
  StreamSubscription<void>? _changes;
  bool _reading = false, _refreshPending = false;

  @override
  void initState() {
    super.initState();
    _changes = widget.changes?.listen((_) => _changed());
  }

  void _changed() {
    if (!mounted) return;
    if (_busy || _reading) {
      _refreshPending = true;
      return;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  String? _error, _activity;
  double? _progress;
  Future<void> Function()? _retry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _generation == 0) {
      _generation++;
      _load();
    }
  }

  @override
  void didUpdateWidget(AttachmentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.changes, widget.changes)) {
      unawaited(_changes?.cancel());
      _changes = widget.changes?.listen((_) => _changed());
    }
    if (!identical(oldWidget.gateway, widget.gateway)) {
      _generation++;
      _items = [];
      _error = null;
      _retry = null;
      _busy = false;
      _loading = true;
      _load();
    } else if (oldWidget.canEdit != widget.canEdit) {
      _retry = null;
    }
  }

  bool _active(
    AttachmentGateway gateway,
    int generation, {
    bool edit = false,
  }) =>
      mounted &&
      generation == _generation &&
      identical(gateway, widget.gateway) &&
      gateway.isCurrent &&
      (!edit || (widget.canEdit && gateway.isOnline));

  Future<void> _load() async {
    if (_reading) {
      _refreshPending = true;
      return;
    }
    final gateway = widget.gateway, generation = _generation;
    if (!gateway.isCurrent) {
      if (mounted) {
        setState(() {
          _loading = false;
          _clearIfAccessLost();
        });
      }
      return;
    }
    _reading = true;
    setState(() {
      _loading = true;
      _error = null;
      _retry = null;
    });
    try {
      if (gateway is AttachmentLocalPreview) {
        final cached = await (gateway as AttachmentLocalPreview).cachedList();
        if (cached != null && _active(gateway, generation)) {
          _validateItems(gateway, cached);
          setState(() => _items = List.unmodifiable(cached));
        }
      }
      if (!_active(gateway, generation)) return;
      final items = await gateway.list();
      if (!_active(gateway, generation)) return;
      _validateItems(gateway, items);
      setState(() => _items = List.unmodifiable(items));
    } catch (_) {
      if (_active(gateway, generation)) {
        setState(() {
          _error = AttachmentStrings(context).loadError;
          _retry = _load;
        });
      }
    } finally {
      _reading = false;
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _clearIfAccessLost();
        });
      }
      if (_refreshPending && mounted && !_busy) {
        _refreshPending = false;
        unawaited(_load());
      }
    }
  }

  void _validateItems(
    AttachmentGateway gateway,
    List<AttachmentMetadata> items,
  ) {
    for (final attachment in items) {
      attachment.validate();
      if (attachment.target != gateway.target) {
        throw const FormatException('Attachment target mismatch');
      }
    }
  }

  void _begin(String activity) => setState(() {
    _busy = true;
    _activity = activity;
    _progress = null;
    _error = null;
    _retry = null;
  });

  void _finish(int generation) {
    if (mounted && generation == _generation) {
      setState(() {
        _busy = false;
        _activity = null;
        _progress = null;
        _clearIfAccessLost();
      });
      if (_refreshPending && !_reading) {
        _refreshPending = false;
        unawaited(_load());
      }
    }
  }

  void _clearIfAccessLost() {
    if (widget.gateway.isCurrent) return;
    _items = [];
    _error = null;
    _retry = null;
    _busy = false;
    _loading = false;
    _activity = null;
    _progress = null;
  }

  void _updateProgress(
    AttachmentGateway gateway,
    int generation,
    double value,
  ) {
    if (_active(gateway, generation) && value.isFinite) {
      setState(() => _progress = value.clamp(0, 1));
    }
  }

  Future<void> _pick() async {
    final gateway = widget.gateway, generation = _generation;
    if (_busy || !_active(gateway, generation, edit: true)) return;
    _begin(AttachmentStrings(context).picking);
    PickedAttachmentFile? file;
    try {
      file = await (widget.filePicker ?? AttachmentFilePicker()).pick();
      if (!_active(gateway, generation, edit: true) || file == null) return;
      validateAttachmentFile(file.name, file.bytes.length);
    } catch (_) {
      if (_active(gateway, generation)) {
        setState(() => _error = AttachmentStrings(context).pickError);
      }
      return;
    } finally {
      _finish(generation);
    }
    if (_active(gateway, generation, edit: true)) {
      await _upload(file, gateway, generation);
    }
  }

  Future<void> _upload(
    PickedAttachmentFile file,
    AttachmentGateway gateway,
    int generation,
  ) async {
    if (_busy || !_active(gateway, generation, edit: true)) return;
    _begin(AttachmentStrings(context).uploading);
    try {
      final mime = validateAttachmentFile(file.name, file.bytes.length);
      await gateway.upload(
        name: file.name,
        mime: mime,
        bytes: file.bytes,
        onProgress: (value) => _updateProgress(gateway, generation, value),
      );
      if (_active(gateway, generation, edit: true)) await _load();
    } catch (_) {
      if (_active(gateway, generation, edit: true)) {
        setState(() {
          _error = AttachmentStrings(context).uploadError;
          _retry = () => _upload(file, gateway, generation);
        });
      }
    } finally {
      _finish(generation);
    }
  }

  Future<void> _download(AttachmentMetadata attachment) async {
    final gateway = widget.gateway, generation = _generation;
    if (_busy || !_active(gateway, generation)) return;
    _begin(AttachmentStrings(context).downloading);
    try {
      final bytes = await gateway.download(
        attachment,
        onProgress: (value) => _updateProgress(gateway, generation, value),
      );
      if (!mounted || !_active(gateway, generation)) return;
      final status = await (widget.fileExporter ?? AttachmentFileExporter())
          .save(
            attachment: attachment,
            bytes: bytes,
            title: AttachmentStrings(context).save,
          );
      if (!mounted || !_active(gateway, generation)) return;
      final l = AttachmentStrings(context);
      if (status != AttachmentExportStatus.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == AttachmentExportStatus.saved
                  ? l.saved
                  : l.downloadStarted,
            ),
          ),
        );
      }
    } catch (_) {
      if (_active(gateway, generation)) {
        setState(() {
          _error = AttachmentStrings(context).downloadError;
          _retry = () => _download(attachment);
        });
      }
    } finally {
      _finish(generation);
    }
  }

  Future<void> _delete(AttachmentMetadata attachment) async {
    final gateway = widget.gateway, generation = _generation;
    if (_busy ||
        !(_active(gateway, generation) &&
            gateway.isOnline &&
            (widget.canDelete?.call(attachment) ?? widget.canEdit))) {
      return;
    }
    final l = AttachmentStrings(context);
    setState(() {
      _busy = true;
      _activity = null;
      _error = null;
      _retry = null;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.deleteTitle),
          content: Text(l.deleteBody(attachment.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.delete),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !(_active(gateway, generation) &&
              gateway.isOnline &&
              (widget.canDelete?.call(attachment) ?? widget.canEdit))) {
        return;
      }
      _begin(l.deleting);
      await gateway.delete(attachment);
      if ((_active(gateway, generation) &&
          gateway.isOnline &&
          (widget.canDelete?.call(attachment) ?? widget.canEdit))) {
        await _load();
      }
    } catch (_) {
      if ((_active(gateway, generation) &&
          gateway.isOnline &&
          (widget.canDelete?.call(attachment) ?? widget.canEdit))) {
        setState(() {
          _error = AttachmentStrings(context).deleteError;
          _retry = () => _delete(attachment);
        });
      }
    } finally {
      _finish(generation);
    }
  }

  Future<void> _report(AttachmentMetadata attachment) async {
    final gateway = widget.gateway, generation = _generation;
    final report = widget.onReport;
    if (_busy ||
        report == null ||
        !gateway.isOnline ||
        !_active(gateway, generation)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _retry = null;
    });
    try {
      await report(attachment);
    } catch (_) {
      if (_active(gateway, generation)) {
        setState(() => _error = AttachmentStrings(context).reportError);
      }
    } finally {
      _finish(generation);
    }
  }

  Widget _menuLabel(IconData icon, String label) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l = AttachmentStrings(context), gateway = widget.gateway;
    if (!gateway.isCurrent) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(l.stale)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l.title, style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              tooltip: l.refresh,
              onPressed: _busy || _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            if (widget.canEdit)
              FilledButton.icon(
                key: const ValueKey('attachment-add'),
                onPressed: _busy || _loading || !gateway.isOnline
                    ? null
                    : _pick,
                icon: const Icon(Icons.attach_file),
                label: Text(l.add),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l.supported),
        if (!widget.canEdit) ...[const SizedBox(height: 8), Text(l.readOnly)],
        if (!gateway.isOnline) ...[const SizedBox(height: 8), Text(l.offline)],
        if (_loading || (_busy && _activity != null)) ...[
          const SizedBox(height: 16),
          if (_activity != null) Text(_activity!),
          LinearProgressIndicator(
            value: _busy ? _progress : null,
            semanticsLabel: _activity ?? l.refresh,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(_error!)),
          if (_retry != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _busy || _loading ? null : _retry,
                icon: const Icon(Icons.refresh),
                label: Text(l.retry),
              ),
            ),
        ],
        const SizedBox(height: 16),
        if (_items.isEmpty && !_loading && _error == null) Text(l.empty),
        for (final item in _items) _attachment(item, l),
      ],
    );
  }

  Widget _attachment(AttachmentMetadata item, AttachmentStrings l) {
    final gateway = widget.gateway;
    final generation = _generation;
    final cached = gateway.localBytes(item) != null;
    return Card(
      key: ValueKey('attachment-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${_fileSize(item.size)} · ${item.name.split('.').last.toUpperCase()}',
            ),
            if (!item.complete) Text(l.pending),
            if (item.complete && cached) Text(l.cached),
            if (item.complete && !cached && !gateway.isOnline)
              Text(l.notCached),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: PopupMenuButton<String>(
                key: ValueKey('attachment-menu-${item.id}'),
                tooltip: l.actions,
                enabled: !_busy && !_loading,
                onSelected: (action) async {
                  if (!_active(gateway, generation)) return;
                  if (action == 'save') await _download(item);
                  if (action == 'delete') await _delete(item);
                  if (action == 'report') await _report(item);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: ValueKey('attachment-save-${item.id}'),
                    value: 'save',
                    enabled: item.complete && (gateway.isOnline || cached),
                    child: _menuLabel(Icons.download_outlined, l.save),
                  ),
                  if (widget.canDelete?.call(item) ?? widget.canEdit)
                    PopupMenuItem(
                      key: ValueKey('attachment-delete-${item.id}'),
                      value: 'delete',
                      enabled: gateway.isOnline,
                      child: _menuLabel(Icons.delete_outline, l.delete),
                    ),
                  if (widget.onReport != null)
                    PopupMenuItem(
                      key: ValueKey('attachment-report-${item.id}'),
                      value: 'report',
                      enabled: gateway.isOnline && item.complete,
                      child: _menuLabel(Icons.flag_outlined, l.report),
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

String _fileSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
