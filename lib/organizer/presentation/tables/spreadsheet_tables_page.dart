import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/spreadsheet_models.dart';
import '../../domain/spreadsheet_tsv.dart';
import '../../domain/collaboration_models.dart' show CollaborationException;
import 'spreadsheet_grid.dart';
import 'tables_strings.dart';
import 'table_text_prompt.dart';

class SpreadsheetTablesPage extends StatefulWidget {
  const SpreadsheetTablesPage({
    super.key,
    required this.gateway,
    this.attachmentsBuilder,
    this.onReport,
    this.changes,
  });
  final SpreadsheetGateway gateway;
  final Stream<void>? changes;
  final Widget Function(String tableId)? attachmentsBuilder;
  final Future<void> Function(String tableId)? onReport;
  @override
  State<SpreadsheetTablesPage> createState() => _SpreadsheetTablesPageState();
}

class _SpreadsheetTablesPageState extends State<SpreadsheetTablesPage> {
  List<SpreadsheetDocument>? _tables;
  bool _busy = false;
  String? _error;
  Timer? _accessTimer;
  StreamSubscription<void>? _changes;
  bool _reading = false, _readAgain = false;
  bool _accessLost = false;
  @override
  void initState() {
    super.initState();
    _changes = widget.changes?.listen((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent != false) _load();
    });
    _load();
    _accessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_accessLost && !widget.gateway.isCurrent) {
        setState(() => _accessLost = true);
      }
    });
  }

  @override
  void dispose() {
    _accessTimer?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  void didUpdateWidget(SpreadsheetTablesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.changes, widget.changes)) {
      unawaited(_changes?.cancel());
      _changes = widget.changes?.listen((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent != false) _load();
      });
    }
    if (!identical(oldWidget.gateway, widget.gateway)) {
      _tables = null;
      _accessLost = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    final gateway = widget.gateway;
    try {
      if (gateway is SpreadsheetLocalPreview) {
        final cached = await (gateway as SpreadsheetLocalPreview).cachedList();
        if (cached != null &&
            mounted &&
            identical(gateway, widget.gateway) &&
            gateway.isCurrent) {
          setState(() => _tables = cached);
        }
      }
      if (!mounted ||
          !identical(gateway, widget.gateway) ||
          !gateway.isCurrent) {
        return;
      }
      final tables = await gateway.list();
      if (mounted && identical(gateway, widget.gateway) && gateway.isCurrent) {
        setState(() {
          _tables = tables;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && identical(gateway, widget.gateway) && gateway.isCurrent) {
        setState(() => _error = TablesStrings.of(context).failed);
      }
    } finally {
      _reading = false;
      if (mounted && identical(gateway, widget.gateway) && !gateway.isCurrent) {
        setState(() {
          _tables = null;
          _accessLost = true;
        });
      }
      if (_readAgain && mounted) {
        _readAgain = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _open(SpreadsheetDocument document) async {
    if (!widget.gateway.isCurrent) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpreadsheetDetailPage(
          gateway: widget.gateway,
          document: document,
          attachmentsBuilder: widget.attachmentsBuilder,
          onReport: widget.onReport,
          changes: widget.changes,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _create() async {
    final s = TablesStrings.of(context);
    final title = await tableTextPrompt(
      context,
      title: s.newTable,
      label: s.title,
    );
    if (title == null || title.isEmpty || !mounted) return;
    final gateway = widget.gateway;
    setState(() => _busy = true);
    try {
      final doc = await gateway.create(title);
      if (mounted && identical(gateway, widget.gateway) && gateway.isCurrent) {
        await _open(doc);
      }
    } catch (_) {
      if (mounted) setState(() => _error = s.failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = TablesStrings.of(context);
    if (!widget.gateway.isCurrent) {
      return Scaffold(
        appBar: AppBar(title: Text(s.tables)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(s.accessLost),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tables),
        actions: [
          IconButton(
            tooltip: s.refresh,
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: widget.gateway.canEdit && widget.gateway.online
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add),
              label: Text(s.newTable),
            )
          : null,
      body: Column(
        children: [
          if (!widget.gateway.online) _Message(s.offline),
          if (_error != null) _Message(_error!),
          Expanded(
            child: _tables == null
                ? const Center(child: CircularProgressIndicator())
                : _tables!.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(s.empty),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _tables!.length,
                    itemBuilder: (context, index) {
                      final table = _tables![index];
                      return ListTile(
                        leading: const Icon(Icons.grid_on),
                        title: Text(table.title),
                        subtitle: Text('${s.revision} ${table.revision}'),
                        onTap: () => _open(table),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class SpreadsheetDetailPage extends StatefulWidget {
  const SpreadsheetDetailPage({
    super.key,
    required this.gateway,
    required this.document,
    this.attachmentsBuilder,
    this.onReport,
    this.changes,
  });
  final SpreadsheetGateway gateway;
  final Stream<void>? changes;
  final SpreadsheetDocument document;
  final Widget Function(String tableId)? attachmentsBuilder;
  final Future<void> Function(String tableId)? onReport;
  @override
  State<SpreadsheetDetailPage> createState() => _SpreadsheetDetailPageState();
}

class _SpreadsheetDetailPageState extends State<SpreadsheetDetailPage>
    with WidgetsBindingObserver {
  late SpreadsheetDocument _document;
  late Map<String, String> _cells;
  late String _title;
  SpreadsheetLease? _lease;
  SpreadsheetDraft? _recovery;
  bool _editing = false, _busy = false, _dirty = false, _leaving = false;
  bool _accessLost = false;
  bool _missingTable = false;
  bool _localDraftOnly = false;
  bool _hasRead = false;
  String? _message;
  Timer? _timer;
  int _ticks = 0;
  StreamSubscription<void>? _changes;
  bool _reading = false, _readAgain = false;
  Future<void> _draftWrite = Future.value();
  bool get _draftIdentityCurrent => widget.gateway is SpreadsheetDraftIdentity
      ? (widget.gateway as SpreadsheetDraftIdentity).isDraftIdentityCurrent
      : widget.gateway.isCurrent;
  bool get _keepingLocalDraft =>
      _editing &&
      _draftIdentityCurrent &&
      (_localDraftOnly ||
          !widget.gateway.isCurrent ||
          !widget.gateway.canEditDocument(_document));
  bool get _draftEditable => _writable || _keepingLocalDraft;
  bool get _writable =>
      !_missingTable &&
      !_localDraftOnly &&
      _draftIdentityCurrent &&
      _editing &&
      _lease?.token != null &&
      _lease!.active &&
      widget.gateway.online &&
      widget.gateway.canEditDocument(_document) &&
      widget.gateway.isCurrent;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _document = widget.document;
    _title = _document.title;
    _cells = Map.of(_document.cells);
    _hasRead = widget.gateway is! SpreadsheetLocalPreview;
    _changes = widget.changes?.listen((_) => _load());
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_changes?.cancel());
    final token = _lease?.token;
    if (token != null) {
      unawaited(
        widget.gateway.release(_document.id, token).catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _editing) {
      _persist().catchError((Object _) {
        if (mounted) {
          setState(() => _message = TablesStrings.of(context).draftFailed);
        }
      });
      if (!_keepingLocalDraft) _stopEditing();
    }
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_missingTable || _editing || _dirty || _leaving || !mounted) return;
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    final gateway = widget.gateway, id = _document.id;
    bool current() =>
        mounted &&
        identical(gateway, widget.gateway) &&
        id == _document.id &&
        !_editing &&
        !_dirty &&
        !_leaving &&
        !_missingTable &&
        gateway.isCurrent;
    try {
      final recovery = await gateway.loadDraft(id);
      if (current()) setState(() => _recovery = recovery);
      if (!current()) return;
      if (gateway is SpreadsheetLocalPreview) {
        final cached = await (gateway as SpreadsheetLocalPreview).cachedRead(
          id,
        );
        if (cached != null && current()) {
          setState(() {
            _document = cached.document;
            _title = _document.title;
            _cells = Map.of(_document.cells);
            _lease = null;
            _hasRead = true;
          });
        }
      }
      if (!current()) return;
      final result = await gateway.read(id);
      if (!current()) return;
      setState(() {
        _document = result.document;
        _title = _document.title;
        _cells = Map.of(_document.cells);
        _lease = result.lease;
        _hasRead = true;
      });
    } catch (error) {
      if (mounted &&
          identical(gateway, widget.gateway) &&
          !_markMissing(error)) {
        setState(() => _message = TablesStrings.of(context).failed);
      }
    } finally {
      _reading = false;
      if (mounted && identical(gateway, widget.gateway) && !gateway.isCurrent) {
        setState(() => _accessLost = true);
      }
      if (_readAgain && mounted) {
        _readAgain = false;
        unawaited(_load());
      }
    }
  }

  void _tick() {
    if (!mounted || _leaving || _missingTable) return;
    if (!widget.gateway.isCurrent || !_draftIdentityCurrent) {
      if (_keepingLocalDraft) {
        if (!_localDraftOnly) _lose();
        return;
      }
      if (!_accessLost) {
        _accessLost = true;
        _lose();
        final route = ModalRoute.of(context);
        if (route != null) {
          Navigator.of(context).popUntil((candidate) => candidate == route);
        }
      }
      return;
    }
    if (_localDraftOnly) return;
    _ticks++;
    if (_editing &&
        (!_lease!.active ||
            !widget.gateway.online ||
            !widget.gateway.canEditDocument(_document))) {
      _lose();
      return;
    }
    if (_editing && _ticks % 25 == 0 && !_busy) _renew();
    // Content refresh is driven by the shared coordinator change stream.
    // This timer only manages the active editing lease and local access.
  }

  Future<void> _persist() {
    if (!_dirty) return _draftWrite;
    final draft = SpreadsheetDraft(
      tableId: _document.id,
      baseRevision: _document.revision,
      title: _title,
      cells: _cells,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    // Serialize writes so a delayed older keystroke cannot replace a newer draft.
    _draftWrite = _draftWrite
        .catchError((Object _) {})
        .then((_) => widget.gateway.storeDraft(draft));
    return _draftWrite;
  }

  void _change(Map<String, String> cells) {
    if (!_draftEditable || _recovery != null) return;
    setState(() {
      _cells = Map.of(cells);
      _dirty = true;
    });
    _persist().catchError((Object _) {
      if (mounted) {
        setState(() => _message = TablesStrings.of(context).draftFailed);
      }
    });
  }

  Future<void> _begin() async {
    if (_missingTable || !_hasRead) return;
    if (_busy ||
        !widget.gateway.online ||
        !widget.gateway.canEditDocument(_document)) {
      return;
    }
    setState(() => _busy = true);
    SpreadsheetLease? acquired;
    try {
      final lease = acquired = await widget.gateway.acquire(_document.id);
      final fresh = await widget.gateway.read(_document.id);
      if (!mounted || _leaving || _missingTable || !widget.gateway.isCurrent) {
        if (lease.token != null) {
          await widget.gateway.release(_document.id, lease.token!);
        }
        return;
      }
      if (lease.token == null || !lease.active) {
        throw StateError('lease unavailable');
      }
      setState(() {
        _lease = lease;
        _editing = true;
        _localDraftOnly = false;
        _ticks = 0;
        _message = null;
        if (_dirty && fresh.document.revision != _document.revision) {
          _recovery = SpreadsheetDraft(
            tableId: _document.id,
            baseRevision: _document.revision,
            title: _title,
            cells: _cells,
            updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
          _dirty = false;
        }
        if (!_dirty) {
          _document = fresh.document;
          _title = _document.title;
          _cells = Map.of(_document.cells);
        }
      });
    } catch (error) {
      final missing = _markMissing(error);
      if (!_editing && acquired?.token != null) {
        try {
          await widget.gateway.release(_document.id, acquired!.token!);
        } catch (_) {}
      }
      if (mounted && !missing) {
        setState(() => _message = TablesStrings.of(context).lockedOrFailed);
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renew() async {
    final token = _lease?.token;
    if (token == null) return;
    try {
      final lease = await widget.gateway.renew(_document.id, token);
      if (mounted &&
          _editing &&
          _lease?.token == token &&
          widget.gateway.isCurrent) {
        if (lease.token != token || !lease.active) {
          _lose();
        } else {
          setState(() => _lease = lease);
        }
      }
    } catch (error) {
      if (!_markMissing(error) &&
          mounted &&
          _editing &&
          _lease?.token == token) {
        _lose();
      }
    }
  }

  bool _markMissing(Object error) {
    if (error is! CollaborationException || error.code != 'table_unavailable') {
      return false;
    }
    if (mounted && !_missingTable) {
      _persist().catchError((Object _) {});
      setState(() {
        _missingTable = true;
        _editing = false;
        _lease = null;
      });
      final route = ModalRoute.of(context);
      if (route != null) {
        Navigator.of(context).popUntil((candidate) => candidate == route);
      }
    }
    return true;
  }

  void _lose() {
    if (!mounted) return;
    _persist().catchError((Object _) {});
    if (_keepingLocalDraft) {
      final token = _lease?.token;
      setState(() {
        _localDraftOnly = true;
        _lease = null;
        _message = null;
      });
      if (token != null) {
        unawaited(
          widget.gateway.release(_document.id, token).catchError((Object _) {}),
        );
      }
      return;
    }
    setState(() {
      _editing = false;
      _lease = null;
      _message = TablesStrings.of(context).lost;
    });
  }

  Future<void> _stopEditing() async {
    final token = _lease?.token;
    if (mounted) {
      setState(() {
        _editing = false;
        _lease = null;
      });
    }
    if (token != null) {
      try {
        await widget.gateway.release(_document.id, token);
      } catch (_) {}
    }
  }

  Future<bool> _save({bool finish = false}) async {
    if (!_writable || _busy || _recovery != null) return false;
    setState(() => _busy = true);
    final token = _lease!.token!;
    try {
      await _persist();
      final saved = await widget.gateway.save(
        _document.id,
        token,
        _document.revision,
        _title,
        Map.of(_cells),
      );
      // Acknowledged content may become the base only while this same lease is held.
      if (!mounted ||
          !_editing ||
          _lease?.token != token ||
          !widget.gateway.isCurrent) {
        return false;
      }
      await widget.gateway.clearDraft(_document.id);
      if (!mounted || !widget.gateway.isCurrent) return false;
      setState(() {
        _document = saved;
        _cells = Map.of(saved.cells);
        _title = saved.title;
        _dirty = false;
        _recovery = null;
        _message = TablesStrings.of(context).saved;
      });
      if (finish) await _stopEditing();
      return true;
    } catch (error) {
      if (!_markMissing(error)) _lose();
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_leaving || (_busy && widget.gateway.isCurrent && !_missingTable)) {
      return;
    }
    try {
      await _persist();
    } catch (_) {
      if (mounted) {
        setState(() => _message = TablesStrings.of(context).draftFailed);
      }
      return;
    }
    await _stopEditing();
    if (mounted) {
      setState(() => _leaving = true);
      Navigator.pop(context);
    }
  }

  Future<void> _rename() async {
    if (_recovery != null) return;
    final s = TablesStrings.of(context);
    final title = await tableTextPrompt(
      context,
      title: s.rename,
      label: s.title,
      initial: _title,
    );
    if (title != null && title.isNotEmpty && mounted && _writable) {
      setState(() {
        _title = title;
        _dirty = true;
      });
      await _persist();
    }
  }

  Future<void> _delete() async {
    if (!widget.gateway.canDeleteDocument(_document)) return;
    final s = TablesStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.delete),
        content: Text(s.deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (yes != true || !_writable || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.gateway.delete(
        _document.id,
        _lease!.token!,
        _document.revision,
      );
      await widget.gateway.clearDraft(_document.id);
      if (mounted) {
        setState(() => _leaving = true);
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _message = s.failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    final recovery = _recovery;
    if (recovery == null || !_writable) return;
    if (recovery.baseRevision != _document.revision) {
      await Clipboard.setData(
        ClipboardData(
          text: SpreadsheetTsv.encode(
            recovery.cells.entries.map((e) => [e.key, e.value]),
          ),
        ),
      );
      if (mounted) {
        setState(() => _message = TablesStrings.of(context).draftCopied);
      }
      return;
    }
    setState(() {
      _title = recovery.title;
      _cells = Map.of(recovery.cells);
      _dirty = true;
      _recovery = null;
    });
    await _persist();
  }

  Future<void> _discardRecovery() async {
    final s = TablesStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.useSaved),
        content: Text(s.discardDraft),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.useSaved),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !_writable) return;
    try {
      await widget.gateway.clearDraft(_document.id);
      if (mounted && widget.gateway.isCurrent) setState(() => _recovery = null);
    } catch (_) {
      if (mounted) setState(() => _message = s.draftFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = TablesStrings.of(context), lease = _lease;
    if ((!widget.gateway.isCurrent && !_keepingLocalDraft) ||
        !_draftIdentityCurrent ||
        _missingTable) {
      return PopScope(
        canPop: _leaving,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(title: Text(s.tables)),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_missingTable ? s.missingTable : s.accessLost),
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: [
            if (_keepingLocalDraft)
              IconButton(
                tooltip: s.keepDraftAndClose,
                onPressed: _busy ? null : _leave,
                icon: const Icon(Icons.check),
              )
            else if (_writable) ...[
              IconButton(
                tooltip: s.save,
                onPressed: _busy || _recovery != null ? null : () => _save(),
                icon: const Icon(Icons.save_outlined),
              ),
              IconButton(
                tooltip: s.finish,
                onPressed: _busy || _recovery != null
                    ? null
                    : () => _save(finish: true),
                icon: const Icon(Icons.check),
              ),
            ] else if (_hasRead &&
                widget.gateway.canEditDocument(_document) &&
                widget.gateway.online)
              IconButton(
                tooltip: s.edit,
                onPressed: _busy ? null : _begin,
                icon: const Icon(Icons.edit_outlined),
              ),
            if (!_keepingLocalDraft && (_writable || widget.onReport != null))
              PopupMenuButton<String>(
                tooltip: s.more,
                onSelected: (value) async {
                  if (value == 'rename') _rename();
                  if (value == 'delete') _delete();
                  if (value == 'report' && widget.gateway.isCurrent) {
                    try {
                      await widget.onReport!(_document.id);
                    } catch (_) {
                      if (mounted) setState(() => _message = s.failed);
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (_writable)
                    PopupMenuItem(
                      value: 'rename',
                      enabled: !_busy && _recovery == null,
                      child: Text(s.rename),
                    ),
                  if (_writable && widget.gateway.canDeleteDocument(_document))
                    PopupMenuItem(
                      value: 'delete',
                      enabled: !_busy,
                      child: Text(s.delete),
                    ),
                  if (widget.onReport != null)
                    PopupMenuItem(value: 'report', child: Text(s.report)),
                ],
              ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .4,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (!widget.gateway.online) _Message(s.offline),
                      if (!_editing && lease != null && lease.active)
                        _Message(s.locked(lease.holderName)),
                      if (_keepingLocalDraft)
                        _Message(s.localDraftOnly)
                      else if (_editing)
                        _Message(s.editing),
                      if (_message != null) _Message(_message!),
                      if (_recovery != null)
                        _Message(
                          s.recovery,
                          action: Wrap(
                            alignment: WrapAlignment.end,
                            children: [
                              TextButton(
                                onPressed: _writable ? _recover : null,
                                child: Text(
                                  _recovery!.baseRevision == _document.revision
                                      ? s.restore
                                      : s.copyDraft,
                                ),
                              ),
                              TextButton(
                                onPressed: _writable ? _discardRecovery : null,
                                child: Text(s.useSaved),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: !_hasRead
                    ? Center(
                        child: _message == null
                            ? const CircularProgressIndicator()
                            : Text(_message!),
                      )
                    : SpreadsheetGrid(
                        cells: _cells,
                        editable: _draftEditable && !_busy && _recovery == null,
                        onChanged: _change,
                        canAccess: () => _draftIdentityCurrent,
                      ),
              ),
              if (!_keepingLocalDraft && widget.attachmentsBuilder != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .25,
                  ),
                  child: widget.attachmentsBuilder!(_document.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        if (action != null)
          Align(alignment: Alignment.centerRight, child: action!),
      ],
    ),
  );
}
