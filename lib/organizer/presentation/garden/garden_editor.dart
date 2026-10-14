import '../editor_actions.dart';
import '../shared/content_actions_menu.dart';
import '../shared/content_moderation.dart';
import '../shared/sharing_errors.dart';
import '../../state/collaboration_provider.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/organizer_repository.dart' show newLocalId;
import '../../domain/garden_models.dart';
import '../../state/garden_provider.dart';
import '../../state/local_spaces_provider.dart';
import 'garden_area_form.dart';
import 'garden_canvas.dart';
import 'garden_bed_detail.dart';
import 'garden_planting_form.dart';
import 'garden_season_panel.dart';
import 'garden_plan_panel.dart';
import 'garden_area_list.dart';
import 'garden_scene_view.dart';
import '../../domain/garden_scene.dart';

/// The editor owns an uncommitted draft. Opening or cancelling never writes.
class GardenEditor extends ConsumerStatefulWidget {
  const GardenEditor({
    super.key,
    this.garden,
    this.reportScopeId,
    this.startInScene = false,
  });
  final bool startInScene;
  final Garden? garden;
  final String? reportScopeId;
  @override
  ConsumerState<GardenEditor> createState() => _GardenEditorState();
}

class _GardenEditorState extends ConsumerState<GardenEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.garden?.name ?? '');
  late final _notes = TextEditingController(text: widget.garden?.notes ?? '');
  late final _width = TextEditingController(
    text: widget.garden?.widthMeters?.toString() ?? '',
  );
  late final _height = TextEditingController(
    text: widget.garden?.heightMeters?.toString() ?? '',
  );
  late bool _sceneMode = widget.startInScene;
  double? get _widthValue => double.tryParse(_width.text.replaceAll(',', '.'));
  double? get _heightValue =>
      double.tryParse(_height.text.replaceAll(',', '.'));
  bool get _hasValidSize => [_widthValue, _heightValue].every(
    (value) => value != null && value.isFinite && value >= .1 && value <= 10000,
  );
  double? get _previewWidth =>
      _hasValidSize ? _widthValue : widget.garden?.widthMeters;
  double? get _previewHeight =>
      _hasValidSize ? _heightValue : widget.garden?.heightMeters;
  bool get _canEdit {
    final active = ref.read(gardenProvider).valueOrNull;
    if (active != null && active.workspaceKey != _workspaceKey) return false;
    if (!_workspaceKey.startsWith('shared:')) {
      final local = ref.read(localSpacesProvider).valueOrNull;
      if (_workspaceKey == 'local') return true;
      if (local == null) return false;
      final space = local.spaces
          .where((s) => s.id == _workspaceKey)
          .firstOrNull;
      return space != null && !space.archived && space.binding == null;
    }
    final state = ref.read(collaborationProvider).valueOrNull;
    final scope = state?.scopes
        .where((s) => _workspaceKey.endsWith(':${s.id}'))
        .firstOrNull;
    return state?.localAccessAllowed == true && scope?.canEdit == true;
  }

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
      _widthValue != widget.garden?.widthMeters ||
      _heightValue != widget.garden?.heightMeters ||
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
    _width.addListener(_textChanged);
    _height.addListener(_textChanged);
  }

  void _textChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _width.dispose();
    _height.dispose();
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
    if (_busy || !_canEdit) return;
    if (_form.currentState != null && !_form.currentState!.validate()) return;
    if (_name.text.trim().isEmpty ||
        _sizeError(_width.text) != null ||
        _sizeError(_height.text) != null) {
      setState(() => _sceneMode = false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final shared = ref.read(collaborationProvider).valueOrNull;
      final scope = shared?.scopes
          .where(
            (s) =>
                s.id == shared.selectedSpaceId &&
                s.kind == SharedScopeKind.household &&
                !s.revoked,
          )
          .firstOrNull;
      if (scope != null &&
          !await showSharedContentPolicy(
            context,
            scopeId: scope.id,
            allowOfflineDraft: true,
          )) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (!mounted) return;
      final controller = ref.read(gardenProvider.notifier);
      if (widget.garden == null) {
        await controller.createGarden(
          expectedWorkspaceKey: _workspaceKey,
          name: _name.text.trim(),
          notes: _notes.text,
          widthMeters: _widthValue,
          heightMeters: _heightValue,
          areas: _areas,
          seasons: _seasons,
        );
      } else {
        await controller.updateGarden(
          widget.garden!.copyWith(
            name: _name.text.trim(),
            notes: _notes.text,
            widthMeters: _widthValue,
            heightMeters: _heightValue,
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
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is CollaborationException
              ? sharingErrorMessage(context, error)
              : context.l10n.gardenSaveError;
        });
      }
    }
  }

  Future<void> _editArea(GardenArea area) async {
    final edited = await showGardenAreaForm(
      context,
      area,
      garden: _draft,
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
      garden: _draft,
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
            widthMeters: _previewWidth,
            heightMeters: _previewHeight,
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

  void _harvest(GardenPlanting planting) {
    if (!_canEdit) return;
    try {
      final value = planting.harvested
          ? planting.copyWith(harvested: false)
          : harvestGardenPlanting(planting, DateTime.now());
      setState(
        () => _seasons = [
          for (final s in _seasons)
            s.year == _year
                ? s.copyWith(
                    plantings: [
                      for (final p in s.plantings) p.id == value.id ? value : p,
                    ],
                  )
                : s,
        ],
      );
    } on FormatException {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.gardenHarvestError)));
    }
  }

  Widget _bedDetails({VoidCallback? refresh}) {
    final area = _areas.where((a) => a.id == _selectedId).firstOrNull;
    return GardenBedDetail(
      garden: _draft,
      area: area,
      year: _year,
      readOnly: !_canEdit,
      onAdd: () async {
        if (area != null) await _planting(area);
        refresh?.call();
      },
      onEdit: (p) async {
        if (area != null) await _planting(area, p);
        refresh?.call();
      },
      onDelete: (p) async {
        await _deletePlanting(p);
        refresh?.call();
      },
      onHarvest: (p) {
        _harvest(p);
        refresh?.call();
      },
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

  String? _sizeError(String? value) {
    if (widget.garden != null &&
        !widget.garden!.hasPhysicalSize &&
        _width.text.trim().isEmpty &&
        _height.text.trim().isEmpty) {
      return null;
    }
    final n = double.tryParse((value ?? '').replaceAll(',', '.'));
    return n == null || !n.isFinite || n < .1 || n > 10000
        ? context.l10n.gardenPhysicalRequired
        : null;
  }

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
        Text(
          l.gardenPhysicalHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('garden-width-meters'),
                controller: _width,
                decoration: InputDecoration(
                  labelText: l.gardenPhysicalWidth,
                  suffixText: 'm',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _sizeError,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const ValueKey('garden-height-meters'),
                controller: _height,
                decoration: InputDecoration(
                  labelText: l.gardenPhysicalHeight,
                  suffixText: 'm',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _sizeError,
              ),
            ),
          ],
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

  Future<void> _showBed(GardenArea area) async {
    setState(() => _selectedId = area.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 650),
      builder: (context) => StatefulBuilder(
        builder: (context, sheetState) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: _bedDetails(
                    refresh: () {
                      if (context.mounted) sheetState(() {});
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBeds() async {
    final selected = await showModalBottomSheet<GardenArea>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 650),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            ListTile(
              title: Text(context.l10n.gardenSceneBeds),
              trailing: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final area in _areas.where((a) => !a.archived))
                    ListTile(
                      leading: const Icon(Icons.grass),
                      title: Text(area.label),
                      subtitle: Text(
                        _draft.hasPhysicalSize
                            ? gardenAreaSize(_draft, area)
                            : context.l10n.gardenPhysicalUnknown,
                      ),
                      onTap: () => Navigator.pop(context, area),
                    ),
                  if (_areas.any((a) => a.archived))
                    ExpansionTile(
                      title: Text(context.l10n.gardenArchivedArea),
                      children: [
                        for (final area in _areas.where((a) => a.archived))
                          ListTile(
                            title: Text(area.label),
                            onTap: () => Navigator.pop(context, area),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) await _showBed(selected);
  }

  Widget _scene() {
    final l = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _seasons.isEmpty
                    ? Text(l.gardenNoSeasons)
                    : DropdownButton<int>(
                        key: const ValueKey('garden-scene-season'),
                        value: _year,
                        isExpanded: true,
                        items: [
                          for (final year
                              in (_seasons.map((s) => s.year).toList()
                                ..sort((a, b) => b.compareTo(a))))
                            DropdownMenuItem(
                              value: year,
                              child: Text(
                                MediaQuery.textScalerOf(context).scale(14) > 20
                                    ? '$year'
                                    : '${l.gardenSeason} $year',
                              ),
                            ),
                        ],
                        onChanged: (year) => setState(() => _year = year),
                      ),
              ),
              if (_canEdit)
                IconButton(
                  tooltip: l.gardenNewSeason,
                  onPressed: _addSeason,
                  icon: const Icon(Icons.add),
                ),
              IconButton(
                key: const ValueKey('garden-scene-beds'),
                tooltip: l.gardenSceneBeds,
                onPressed: _showBeds,
                icon: const Icon(Icons.list_alt),
              ),
              Tooltip(
                message: '${l.gardenSceneHelp}\n\n${l.gardenVisualGrowthHelp}',
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.info_outline, size: 20),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: GardenSceneView(garden: _draft, year: _year, onBed: _showBed),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dirty
                      ? l.gardenSceneDraft
                      : _draft.hasPhysicalSize
                      ? '≈ ${gardenMeters(_draft.widthMeters!)} × ${gardenMeters(_draft.heightMeters!)} m'
                      : l.gardenPhysicalUnknown,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_canEdit)
                if (MediaQuery.sizeOf(context).width < 360 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20)
                  IconButton(
                    key: const ValueKey('garden-edit-layout'),
                    tooltip: l.gardenSceneEditLayout,
                    onPressed: () => setState(() => _sceneMode = false),
                    icon: const Icon(Icons.tune),
                  )
                else
                  TextButton.icon(
                    key: const ValueKey('garden-edit-layout'),
                    onPressed: () => setState(() => _sceneMode = false),
                    icon: const Icon(Icons.tune),
                    label: Text(l.gardenSceneEditLayout),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    ref.watch(collaborationProvider);
    ref.watch(gardenProvider);
    ref.watch(localSpacesProvider);
    return PopScope(
      canPop: _allowPop || (!_dirty && !_busy),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.garden == null ? l.gardenNew : widget.garden!.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : _leave,
          ),
          actions: [
            if (!_sceneMode)
              IconButton(
                key: const ValueKey('garden-open-scene'),
                tooltip: l.gardenSceneView,
                onPressed: () => setState(() => _sceneMode = true),
                icon: const Icon(Icons.yard_outlined),
              ),
            if (widget.reportScopeId != null && widget.garden != null)
              SharedContentActionsMenu(
                scopeId: widget.reportScopeId!,
                targetId: widget.garden!.id,
                enabled: !_busy,
              ),
            EditorSaveButton(
              key: const ValueKey('garden-save'),
              onPressed: _canEdit ? _save : null,
              busy: _busy,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: SafeArea(
            child: _sceneMode
                ? _scene()
                : AbsorbPointer(
                    absorbing: !_canEdit,
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
                                  _workspaceKey.startsWith('shared:')
                                      ? l.sharingShared
                                      : l.localSpaceState,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (_error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
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
                                  onSelected: (year) =>
                                      setState(() => _year = year),
                                  onAdd: _addSeason,
                                  onDelete: _deleteSeason,
                                ),
                                const SizedBox(height: 20),
                                LayoutBuilder(
                                  builder: (context, constraints) =>
                                      constraints.maxWidth >= 850
                                      ? Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(flex: 3, child: _sketch()),
                                            const SizedBox(width: 32),
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                children: [
                                                  _bedDetails(),
                                                  _areaList(),
                                                ],
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
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
      ),
    );
  }
}
