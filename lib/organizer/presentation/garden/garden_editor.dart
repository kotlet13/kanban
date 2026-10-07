import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/organizer_repository.dart' show newLocalId;
import '../../domain/garden_models.dart';
import '../../state/garden_provider.dart';
import 'garden_area_form.dart';
import 'garden_canvas.dart';

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
      !_sameAreas(_areas, widget.garden?.areas ?? const []);

  bool _sameAreas(List<GardenArea> a, List<GardenArea> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].label != b[i].label ||
          a[i].x != b[i].x ||
          a[i].y != b[i].y ||
          a[i].width != b[i].width ||
          a[i].height != b[i].height) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
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
          name: _name.text.trim(),
          notes: _notes.text,
          areas: _areas,
        );
      } else {
        await controller.updateGarden(
          widget.garden!.copyWith(
            name: _name.text.trim(),
            notes: _notes.text,
            areas: _areas,
          ),
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
    final edited = await showGardenAreaForm(context, area);
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

  Widget _sketch() {
    final l = context.l10n;
    final selected = _areas.where((area) => area.id == _selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.gardenLayout, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('garden-tool-select'),
              avatar: const Icon(Icons.open_with, size: 18),
              selected: _tool == GardenTool.select,
              label: Text(l.gardenSelectTool),
              onSelected: (_) => setState(() => _tool = GardenTool.select),
            ),
            ChoiceChip(
              key: const ValueKey('garden-tool-draw'),
              avatar: const Icon(Icons.crop_square, size: 18),
              selected: _tool == GardenTool.draw,
              label: Text(l.gardenDrawTool),
              onSelected: _areas.length >= 1000
                  ? null
                  : (_) => setState(() => _tool = GardenTool.draw),
            ),
            IconButton(
              tooltip: l.gardenUndo,
              onPressed: _undo.isEmpty
                  ? null
                  : () => setState(() {
                      _areas = _undo.removeLast();
                      _selectedId = null;
                    }),
              icon: const Icon(Icons.undo),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _tool == GardenTool.draw ? l.gardenDrawHelp : l.gardenSelectHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        GardenCanvas(
          areas: _areas,
          tool: _tool,
          selectedId: _selectedId,
          onSelect: (id) => setState(() => _selectedId = id),
          onDraw: _draw,
          onMove: (area) => _changeAreas([
            for (final item in _areas) item.id == area.id ? area : item,
          ], selectedId: area.id),
          semanticLabel: l.gardenCanvasDescription,
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(selected.label),
                TextButton.icon(
                  onPressed: () => _editArea(selected),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l.edit),
                ),
                TextButton.icon(
                  onPressed: () => _changeAreas(
                    _areas.where((item) => item.id != selected.id).toList(),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(l.delete),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          l.gardenSketchDisclaimer,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
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

  Widget _areaList() {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(l.gardenAreas, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l.gardenAreaListHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('garden-add-area'),
          onPressed: _areas.length >= 1000 ? null : _addArea,
          icon: const Icon(Icons.add),
          label: Text(l.gardenAddArea),
        ),
        if (_areas.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(l.gardenNoAreas),
          ),
        for (final area in _areas)
          ListTile(
            key: ValueKey('garden-area-${area.id}'),
            contentPadding: EdgeInsets.zero,
            selected: _selectedId == area.id,
            leading: const Icon(Icons.crop_square),
            title: Text(
              area.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              l.gardenAreaPosition(
                (area.x * 100).round(),
                (area.y * 100).round(),
                (area.width * 100).round(),
                (area.height * 100).round(),
              ),
            ),
            onTap: () {
              setState(() => _selectedId = area.id);
              _editArea(area);
            },
            trailing: IconButton(
              tooltip: l.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _changeAreas(
                _areas.where((item) => item.id != area.id).toList(),
              ),
            ),
          ),
      ],
    );
  }

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
          title: Text(widget.garden == null ? l.gardenNew : l.gardenEdit),
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
                  : Text(l.save),
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
                                        children: [_details(), _areaList()],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _details(),
                                    const SizedBox(height: 24),
                                    _sketch(),
                                    _areaList(),
                                  ],
                                ),
                        ),
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
