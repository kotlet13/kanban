import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/organizer_repository.dart' show newLocalId;
import '../../domain/garden_models.dart';
import '../../state/garden_provider.dart';
import 'garden_area_form.dart';
import 'garden_canvas.dart';
import 'garden_bed_detail.dart';
import 'garden_planting_form.dart';
import 'garden_season_panel.dart';
import 'garden_plan_panel.dart';
import 'garden_area_list.dart';

/// The editor owns an uncommitted draft. Opening or cancelling never writes.
class GardenEditor extends ConsumerStatefulWidget {
  const GardenEditor({super.key, this.garden});
  final Garden? garden;
  @override
  ConsumerState<GardenEditor> createState() => _GardenEditorState();
}

class _GardenEditorState extends ConsumerState<GardenEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.garden?.name ?? '');
  late final _notes = TextEditingController(text: widget.garden?.notes ?? '');
  late List<GardenArea> _areas = [...?widget.garden?.areas];
  late List<GardenSeason> _seasons = [...?widget.garden?.seasons];
  late int? _year = (_seasons.map((s) => s.year).toList()..sort()).lastOrNull;
  final _draftId = newLocalId();
  late final _workspaceKey =
      ref.read(gardenProvider).valueOrNull?.workspaceKey ?? 'local';
  final _openedAt = DateTime.now();
  final _undo = <List<GardenArea>>[];
  GardenTool _tool = GardenTool.select;
  String? _selectedId;
  bool _busy = false;
  bool _allowPop = false;
  bool _askingLeave = false;
  String? _error;

  bool get _dirty =>
      _name.text != (widget.garden?.name ?? '') ||
      _notes.text != (widget.garden?.notes ?? '') ||
      !_sameAreas(_areas, widget.garden?.areas ?? const []) ||
      jsonEncode(_seasons.map((s) => s.toJson()).toList()) !=
          jsonEncode(
            (widget.garden?.seasons ?? <GardenSeason>[])
                .map((s) => s.toJson())
                .toList(),
          );

  bool _sameAreas(List<GardenArea> a, List<GardenArea> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].label != b[i].label ||
          a[i].x != b[i].x ||
          a[i].y != b[i].y ||
          a[i].width != b[i].width ||
          a[i].height != b[i].height ||
          a[i].kind != b[i].kind ||
          a[i].archived != b[i].archived) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _selectedId = _areas
        .where((a) => !a.archived && a.kind == GardenAreaKind.bed)
        .firstOrNull
        ?.id;
    _name.addListener(_textChanged);
    _notes.addListener(_textChanged);
  }

  void _textChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _changeAreas(List<GardenArea> next, {String? selectedId}) {
    setState(() {
      _undo.add([..._areas]);
      if (_undo.length > 50) _undo.removeAt(0);
      _areas = next;
      _selectedId = selectedId;
      _error = null;
    });
  }

  Future<void> _leave() async {
    if (_busy || _askingLeave) return;
    if (_dirty) {
      _askingLeave = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.gardenUnsavedTitle),
          content: Text(context.l10n.gardenUnsavedBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.gardenKeepEditing),
            ),
            FilledButton(
              key: const ValueKey('garden-discard'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.gardenDiscard),
            ),
          ],
        ),
      );
      _askingLeave = false;
      if (discard != true || !mounted) return;
    }
    if (mounted) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = ref.read(gardenProvider.notifier);
      if (widget.garden == null) {
        await controller.createGarden(
          expectedWorkspaceKey: _workspaceKey,
          name: _name.text.trim(),
          notes: _notes.text,
          areas: _areas,
          seasons: _seasons,
        );
      } else {
        await controller.updateGarden(
          widget.garden!.copyWith(
            name: _name.text.trim(),
            notes: _notes.text,
            areas: _areas,
            seasons: _seasons,
          ),
          expectedWorkspaceKey: _workspaceKey,
        );
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.l10n.gardenSaveError;
        });
      }
    }
  }

  Future<void> _editArea(GardenArea area) async {
    final edited = await showGardenAreaForm(
      context,
      area,
      allowKindChange: !_seasons.any(
        (s) => s.plantings.any((p) => p.areaId == area.id),
      ),
    );
    if (edited != null && mounted && !_sameAreas([area], [edited])) {
      _changeAreas([
        for (final item in _areas) item.id == area.id ? edited : item,
      ], selectedId: edited.id);
    }
  }

  Future<void> _addArea() async {
    if (_areas.length >= 1000) return;
    final edited = await showGardenAreaForm(
      context,
      GardenArea(
        id: newLocalId(),
        label: '',
        x: .1,
        y: .1,
        width: .25,
        height: .25,
      ),
    );
    if (edited != null && mounted) {
      _changeAreas([..._areas, edited], selectedId: edited.id);
    }
  }

  void _draw(Rect rect) {
    if (_areas.length >= 1000) return;
    final area = GardenArea(
      id: newLocalId(),
      label: context.l10n.gardenDefaultArea(_areas.length + 1),
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
    );
    _changeAreas([..._areas, area], selectedId: area.id);
    setState(() => _tool = GardenTool.select);
  }

  Garden get _draft =>
      (widget.garden ??
              Garden(
                id: _draftId,
                name: _name.text,
                createdAt: _openedAt,
                updatedAt: _openedAt,
              ))
          .copyWith(
            name: _name.text,
            notes: _notes.text,
            areas: _areas,
            seasons: _seasons,
          );

  Future<void> _addSeason() async {
    final season = await showGardenSeasonForm(
      context,
      _seasons,
      activeAreaIds: _areas.where((a) => !a.archived).map((a) => a.id).toSet(),
    );
    if (season != null && mounted) {
      setState(() {
        _seasons = [..._seasons, season];
        _year = season.year;
      });
    }
  }

  Future<void> _deleteSeason() async {
    if (_year == null) return;
    final yes = await _confirm(
      context.l10n.gardenDeleteSeason,
      context.l10n.gardenDeleteSeasonBody,
    );
    if (yes && mounted) {
      setState(() {
        _seasons = _seasons.where((s) => s.year != _year).toList();
        _year = (_seasons.map((s) => s.year).toList()..sort()).lastOrNull;
      });
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.delete),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _planting(GardenArea area, [GardenPlanting? planting]) async {
    if (_year == null || area.archived) return;
    final value = await showGardenPlantingForm(
      context,
      planting ?? GardenPlanting(id: newLocalId(), areaId: area.id, crop: ''),
      isNew: planting == null,
    );
    if (value != null && mounted) {
      setState(() {
        _seasons = [
          for (final s in _seasons)
            if (s.year != _year)
              s
            else
              s.copyWith(
                plantings: [
                  for (final p in s.plantings)
                    if (p.id != value.id) p,
                  value,
                ],
              ),
        ];
      });
    }
  }

  Future<void> _deletePlanting(GardenPlanting planting) async {
    final yes = await _confirm(
      context.l10n.gardenDeletePlanting,
      context.l10n.gardenDeletePlantingBody,
    );
    if (yes && mounted) {
      setState(() {
        _seasons = [
          for (final s in _seasons)
            if (s.year != _year)
              s
            else
              s.copyWith(
                plantings: s.plantings.where((p) => p.id != planting.id),
              ),
        ];
      });
    }
  }

  void _removeArea(GardenArea area) {
    final used = _seasons.any(
      (s) => s.plantings.any((p) => p.areaId == area.id),
    );
    _changeAreas([
      for (final a in _areas)
        if (a.id != area.id) a else if (used) a.copyWith(archived: true),
    ], selectedId: used ? area.id : null);
  }

  Widget _bedDetails() {
    final area = _areas.where((a) => a.id == _selectedId).firstOrNull;
    return GardenBedDetail(
      garden: _draft,
      area: area,
      year: _year,
      onAdd: () {
        if (area != null) _planting(area);
      },
      onEdit: (p) {
        if (area != null) _planting(area, p);
      },
      onDelete: _deletePlanting,
      onNotes: (notes) => setState(() {
        _seasons = [
          for (final s in _seasons)
            s.year == _year ? s.copyWith(notes: notes) : s,
        ];
      }),
    );
  }

  Widget _sketch() => GardenPlanPanel(
    garden: _draft,
    year: _year,
    selectedId: _selectedId,
    tool: _tool,
    onTool: (tool) => setState(() => _tool = tool),
    onSelect: (id) => setState(() => _selectedId = id),
    onDraw: _draw,
    onMove: (area) => _changeAreas([
      for (final item in _areas) item.id == area.id ? area : item,
    ], selectedId: area.id),
    onEdit: _editArea,
    onRemove: (area) => area.archived
        ? _changeAreas([
            for (final a in _areas)
              a.id == area.id ? a.copyWith(archived: false) : a,
          ], selectedId: area.id)
        : _removeArea(area),
    onUndo: _undo.isEmpty
        ? null
        : () => setState(() {
            final previous = _undo.removeLast();
            final referenced = _seasons
                .expand((s) => s.plantings)
                .map((p) => p.areaId)
                .toSet();
            final retained = _areas
                .where(
                  (a) =>
                      referenced.contains(a.id) &&
                      !previous.any((p) => p.id == a.id),
                )
                .map((a) => a.copyWith(archived: true))
                .toList();
            _areas = [...previous, ...retained];
            _selectedId = retained.firstOrNull?.id;
            if (retained.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.gardenUndoPreserved)),
              );
            }
          }),
  );

  Widget _details() {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('garden-name'),
          controller: _name,
          maxLength: 200,
          decoration: InputDecoration(labelText: l.gardenName),
          validator: (value) =>
              value!.trim().isEmpty ? l.gardenNameRequired : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('garden-notes'),
          controller: _notes,
          maxLength: 20000,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: l.organizerNotes,
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _areaList() => GardenAreaList(
    garden: _draft,
    year: _year,
    selectedId: _selectedId,
    onAdd: _addArea,
    onSelect: (id) => setState(() => _selectedId = id),
    onEdit: _editArea,
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: _allowPop || (!_dirty && !_busy),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.garden == null ? l.gardenNew : widget.garden!.name,
          ),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : _leave,
          ),
          actions: [
            TextButton(
              key: const ValueKey('garden-save'),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.gardenSave),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.gardenLocalOnly,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (widget.garden == null) ...[
                          const SizedBox(height: 20),
                          _details(),
                        ],
                        const SizedBox(height: 20),
                        GardenSeasonPanel(
                          seasons: _seasons,
                          year: _year,
                          onSelected: (year) => setState(() => _year = year),
                          onAdd: _addSeason,
                          onDelete: _deleteSeason,
                        ),
                        const SizedBox(height: 20),
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              constraints.maxWidth >= 850
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 3, child: _sketch()),
                                    const SizedBox(width: 32),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        children: [_bedDetails(), _areaList()],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _sketch(),
                                    const SizedBox(height: 20),
                                    _bedDetails(),
                                    _areaList(),
                                  ],
                                ),
                        ),
                        if (widget.garden != null) ...[
                          const SizedBox(height: 24),
                          Text(
                            l.gardenDetails,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          _details(),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
