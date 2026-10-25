import 'dart:convert';
import '../../data/e2ee/crypto_migration_idea_draft_recovery.dart';
import '../../platform/private_file_io.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/collaboration_repository.dart' show newSharedId;
import '../../state/idea_provider.dart';
import '../../state/local_database_provider.dart';
import '../../data/idea_repository.dart';
import '../../data/idea_storage.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../shared/sharing_session_boundary.dart';
import '../backup/backup_file_io.dart' show readBoundedBackup;
import '../editor_actions.dart';
import '../desktop/desktop_layout.dart';
import '../shared/content_moderation.dart';
import 'idea_canvas.dart';

final _openingIdeaEditors = Expando<bool>();

/// Keeps an aggregate's anonymous local source readable when personal sync
/// selects another repository. This route cannot bypass the local writer guard.
Future<void> openLocalIdeaViewer(
  BuildContext context,
  WidgetRef ref, {
  required String spaceId,
  required String boardId,
  VoidCallback? onReviewPrivate,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context, rootNavigator: true);
  final session = (await container.read(collaborationProvider.future)).session;
  final db = await container.read(localDatabaseProvider.future);
  if (!navigator.mounted || db.selectedLocalWorkspaceId != spaceId) return;
  final repository = IdeaRepository(IdeaStorage(db));
  try {
    final snapshot = await repository.initialize();
    final current = container.read(collaborationProvider).valueOrNull?.session;
    if (!navigator.mounted ||
        db.selectedLocalWorkspaceId != spaceId ||
        (session?.partition, session?.deviceId) !=
            (current?.partition, current?.deviceId)) {
      return;
    }
    final board = snapshot.boards.where((b) => b.id == boardId).firstOrNull;
    if (board == null) return;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => ProviderScope(
          overrides: [
            ideaRepositoryProvider.overrideWith((ref) async => repository),
            ideaProvider.overrideWith(IdeaController.new),
          ],
          child: IdeaEditor(
            board: board,
            base: board,
            workspaceKey: spaceId,
            canEdit: false,
            readOnlyReason: navigator.context.l10n.ideasLocalSeparate,
            onReadOnlyAction: onReviewPrivate,
          ),
        ),
      ),
    );
  } finally {
    await repository.close();
  }
}

Future<void> openIdeaEditor(
  BuildContext context,
  WidgetRef ref, {
  IdeaBoard? board,
  String? projectId,
  bool draftOnly = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_openingIdeaEditors[navigator] == true) return;
  _openingIdeaEditors[navigator] = true;
  try {
    final host = navigator.context;
    final openedSession = (await container.read(
      collaborationProvider.future,
    )).session;
    final snapshot = await container.read(ideaProvider.future);
    if (!host.mounted) return;
    final controller = container.read(ideaProvider.notifier);
    final now = DateTime.now().toUtc();
    final projectScope = container
        .read(collaborationProvider)
        .valueOrNull
        ?.scopes
        .where(
          (s) =>
              s.id == snapshot.sharedScopeId &&
              s.kind == SharedScopeKind.project,
        )
        .firstOrNull;
    final initial =
        board ??
        IdeaBoard(
          id: newSharedId(),
          title: host.l10n.ideasUntitled,
          projectId:
              projectId ?? (projectScope?.projectRootId ?? projectScope?.id),
          createdAt: now,
          updatedAt: now,
        );
    IdeaBoard? draft;
    try {
      draft =
          canEditIdeaBoard(
            container.read(collaborationProvider).valueOrNull,
            snapshot,
            board,
          )
          ? await controller.readDraft(
              initial.id,
              expectedWorkspaceKey: snapshot.workspaceKey,
            )
          : null;
    } on CryptoRecoveredIdeaDraftConflict catch (conflict) {
      if (!host.mounted) return;
      final sl = Localizations.localeOf(host).languageCode == 'sl';
      final choice = await showDialog<int>(
        context: host,
        builder: (context) => AlertDialog(
          title: Text(
            sl ? 'Več ohranjenih osnutkov' : 'Multiple retained drafts',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sl
                      ? 'Izberite osnutek za pregled. Vsi izvirniki ostanejo ohranjeni; izbira še ne shrani plošče ali pošlje sprememb.'
                      : 'Select a draft to review. All originals are retained; selecting one does not save the board or send changes.',
                ),
                for (var i = 0; i < conflict.versions.length; i++)
                  ListTile(
                    title: Text(
                      '${i + 1}. ${(jsonDecode(conflict.versions[i]['payload'] as String) as Map)['title']}',
                    ),
                    subtitle: Text(
                      '${(jsonDecode(conflict.versions[i]['payload'] as String) as Map)['updatedAt']}',
                    ),
                    onTap: () => Navigator.pop(context, i),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
          ],
        ),
      );
      if (choice == null || !host.mounted) return;
      await conflict.select(choice);
      draft = await controller.readDraft(
        initial.id,
        expectedWorkspaceKey: snapshot.workspaceKey,
      );
    }
    final draftBase = draft == null
        ? null
        : await controller.readDraftBase(
            initial.id,
            expectedWorkspaceKey: snapshot.workspaceKey,
          );
    final currentSession = container
        .read(collaborationProvider)
        .valueOrNull
        ?.session;
    if (!host.mounted ||
        (currentSession?.partition, currentSession?.deviceId) !=
            (openedSession?.partition, openedSession?.deviceId) ||
        container.read(ideaProvider).valueOrNull?.workspaceKey !=
            snapshot.workspaceKey) {
      return;
    }
    await Navigator.of(host).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IdeaEditor(
          board: draft ?? initial,
          base: draftBase ?? (draftOnly ? null : board),
          workspaceKey: snapshot.workspaceKey,
          sharedScopeId: snapshot.sharedScopeId,
          canEdit: canEditIdeaBoard(
            container.read(collaborationProvider).valueOrNull,
            snapshot,
            board,
          ),
        ),
      ),
    );
  } finally {
    _openingIdeaEditors[navigator] = false;
  }
}

Future<bool> openIdeaNotificationBoard(
  BuildContext context,
  WidgetRef ref,
  NotificationTarget target,
  String boardId,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final host = Navigator.of(context, rootNavigator: true).context;
  bool matches() {
    final state = container.read(collaborationProvider).valueOrNull;
    return target.isPersonal ||
        state?.session != null && target.matches(state!.session!);
  }

  if (!matches()) return false;
  if (!target.isPersonal) {
    await container
        .read(collaborationProvider.notifier)
        .selectSpace(target.scopeId);
  }
  if (!host.mounted || !matches()) return false;
  final snapshot = await container.read(ideaProvider.future);
  if (!host.mounted ||
      !matches() ||
      (!target.isPersonal && snapshot.sharedScopeId != target.scopeId)) {
    return false;
  }
  final board = snapshot.boards.where((b) => b.id == boardId).firstOrNull;
  if (board == null) return false;
  await openIdeaEditor(host, ref, board: board);
  return true;
}

class IdeaEditor extends ConsumerStatefulWidget {
  const IdeaEditor({
    super.key,
    required this.board,
    this.base,
    required this.workspaceKey,
    this.sharedScopeId,
    required this.canEdit,
    this.readOnlyReason,
    this.onReadOnlyAction,
  });
  final IdeaBoard board;
  final IdeaBoard? base;
  final String workspaceKey;
  final String? sharedScopeId;
  final bool canEdit;
  final String? readOnlyReason;
  final VoidCallback? onReadOnlyAction;
  @override
  ConsumerState<IdeaEditor> createState() => _IdeaEditorState();
}

class _IdeaEditorState extends ConsumerState<IdeaEditor> {
  late IdeaBoard _board = widget.board;
  late final TextEditingController _title = TextEditingController(
    text: _board.title,
  );
  final _canvasKey = GlobalKey();
  final List<IdeaBoard> _undo = [], _redo = [];
  final Map<String, ui.Image> _images = {};
  final Set<String> _loadingImages = {};
  IdeaTool _tool = IdeaTool.select;
  String? _selected;
  int _color = 0xff263238;
  double _width = 3;
  bool _busy = false,
      _draftError = false,
      _dirty = false,
      _allowPop = false,
      _draftSaving = false,
      _draftSaved = false;
  late final AccountSession? _session = ref
      .read(collaborationProvider)
      .valueOrNull
      ?.session;
  late final SharingSessionGuard _sessionGuard = SharingSessionGuard(
    context,
    ref,
    session: _session,
    allowSignedOut: true,
  );
  bool get _sameContext {
    final current = ref.read(ideaProvider).valueOrNull;
    if (current != null && current.workspaceKey != widget.workspaceKey) {
      return false;
    }
    if (widget.sharedScopeId == null) return _sessionGuard.isCurrent;
    final shared = ref.read(collaborationProvider).valueOrNull;
    return _sessionGuard.isCurrent &&
        shared?.localAccessAllowed == true &&
        shared!.scopes.any((s) => s.id == widget.sharedScopeId && s.canRead);
  }

  Timer? _draftTimer;
  Future<void> _draftWrites = Future.value();
  bool get _parentArchived {
    final projects = widget.sharedScopeId == null
        ? ref.read(organizerProvider).valueOrNull?.projects
        : ref
              .read(collaborationProvider)
              .valueOrNull
              ?.dataForScope(widget.sharedScopeId!)
              .projects;
    return projects?.any((p) => p.id == _board.projectId && p.archived) == true;
  }

  bool get _editable =>
      !_parentArchived &&
      _sameContext &&
      widget.canEdit &&
      ref.read(ideaProvider).valueOrNull?.workspaceKey == widget.workspaceKey &&
      ref.read(ideaProvider).valueOrNull != null &&
      canEditIdeaBoard(
        ref.read(collaborationProvider).valueOrNull,
        ref.read(ideaProvider).valueOrNull!,
        widget.base == null ? null : _board,
      );
  IdeaElement? get _selectedElement =>
      _board.elements.where((e) => e.id == _selected).firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadImages());
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _title.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  void _change(IdeaBoard board, {bool history = true}) {
    if (!_editable || _busy) return;
    try {
      board
          .copyWith(
            title: board.title.trim().isEmpty
                ? context.l10n.ideasUntitled
                : board.title,
          )
          .validate();
    } catch (_) {
      _message(context.l10n.ideasSaveError);
      return;
    }
    if (history) {
      _undo.add(_board);
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
    }
    setState(() {
      _board = board;
      _dirty = true;
    });
    final needed = _board.assets.map((a) => a.sha256).toSet();
    for (final key
        in _images.keys.where((key) => !needed.contains(key)).toList()) {
      _images.remove(key)?.dispose();
    }
    unawaited(_loadImages());
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), _queueDraft);
  }

  void _queueDraft() {
    final board = _board.copyWith(
      title: _title.text.trim().isEmpty
          ? context.l10n.ideasUntitled
          : _title.text.trim(),
    );
    final controller = ref.read(ideaProvider.notifier);
    if (mounted) setState(() => _draftSaving = true);
    _draftWrites = _draftWrites
        .catchError((Object _) {})
        .then(
          (_) => controller.saveDraft(
            board,
            base: widget.base,
            expectedWorkspaceKey: widget.workspaceKey,
          ),
        )
        .then(
          (_) {
            if (mounted) {
              setState(() {
                _draftError = false;
                _draftSaving = false;
                _draftSaved = true;
              });
            }
          },
          onError: (Object _, StackTrace __) {
            if (mounted) {
              setState(() {
                _draftError = true;
                _draftSaving = false;
              });
            }
          },
        );
  }

  Future<void> _loadImages({bool download = false}) async {
    final missingMessage = context.l10n.ideasMissingPhoto;
    final controller = ref.read(ideaProvider.notifier);
    if (download) {
      try {
        await controller.ensureAssets(
          _board,
          expectedWorkspaceKey: widget.workspaceKey,
        );
      } catch (_) {
        if (mounted) _message(missingMessage);
      }
    }
    for (final asset in _board.assets) {
      if (_images.containsKey(asset.sha256) ||
          !_loadingImages.add(asset.sha256)) {
        continue;
      }
      try {
        final bytes = await controller.readAsset(asset);
        if (bytes == null) continue;
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: math.min(1024, asset.width),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        if (mounted &&
            _sameContext &&
            _board.assets.any((a) => a.sha256 == asset.sha256) &&
            ref.read(ideaProvider).valueOrNull?.workspaceKey ==
                widget.workspaceKey) {
          setState(() => _images[asset.sha256] = frame.image);
        } else {
          frame.image.dispose();
        }
      } catch (_) {
        /* Missing/corrupt media stays explicitly visible. */
      } finally {
        _loadingImages.remove(asset.sha256);
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _save() async {
    if (!_editable || _busy) return;
    final saveError = context.l10n.ideasSaveError;
    setState(() => _busy = true);
    _draftTimer?.cancel();
    _queueDraft();
    try {
      await _draftWrites;
      if (!mounted || !_editable) return;
      if (widget.sharedScopeId != null &&
          !await showSharedContentPolicy(
            context,
            scopeId: widget.sharedScopeId,
            allowOfflineDraft: true,
          )) {
        return;
      }
      if (!mounted || !_editable) return;
      final updated = _board.copyWith(
        title: _title.text.trim().isEmpty
            ? context.l10n.ideasUntitled
            : _title.text.trim(),
      );
      updated.validate();
      await ref
          .read(ideaProvider.notifier)
          .saveBoard(
            updated,
            isNew: widget.base == null,
            base: widget.base,
            expectedWorkspaceKey: widget.workspaceKey,
          );
      await ref
          .read(ideaProvider.notifier)
          .discardDraft(updated.id, expectedWorkspaceKey: widget.workspaceKey);
      if (mounted) {
        setState(() {
          _dirty = false;
          _allowPop = true;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      _message(saveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    _draftTimer?.cancel();
    if (_dirty && _editable) {
      setState(() => _busy = true);
      _queueDraft();
      await _draftWrites;
    }
    if (mounted && _draftError) setState(() => _busy = false);
    if (mounted && !_draftError) {
      setState(() {
        _dirty = false;
        _allowPop = true;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final saveError = context.l10n.ideasSaveError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.ideasDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_editable) return;
    setState(() => _busy = true);
    try {
      _draftTimer?.cancel();
      await _draftWrites;
      if (!mounted || !_editable) return;
      await ref
          .read(ideaProvider.notifier)
          .deleteBoard(widget.base!, expectedWorkspaceKey: widget.workspaceKey);
      await ref
          .read(ideaProvider.notifier)
          .discardDraft(_board.id, expectedWorkspaceKey: widget.workspaceKey);
      if (mounted) {
        setState(() {
          _dirty = false;
          _allowPop = true;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      _message(saveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dialog(Widget child, {bool write = false}) => Consumer(
    builder: (context, ref, _) {
      ref.watch(ideaProvider);
      return SharingSessionBoundary(
        guard: _sessionGuard,
        visibleWhen: (_) => _sameContext && (!write || _editable),
        child: child,
      );
    },
  );

  Future<void> _text({
    IdeaElement? element,
    bool sticky = false,
    bool attached = false,
  }) async {
    final controller = TextEditingController(text: element?.text ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _dialog(
        AlertDialog(
          title: Text(context.l10n.ideasEditText),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 20000,
            decoration: InputDecoration(labelText: context.l10n.ideasText),
          ),
          actions: [
            EditorActionsRow(
              onCancel: () => Navigator.pop(context),
              onSave: () => Navigator.pop(context, controller.text),
            ),
          ],
        ),
        write: true,
      ),
    );
    controller.dispose();
    if (value == null || !mounted || !_editable) return;
    if (element != null) {
      _replace(element.copyWith(text: value));
      return;
    }
    final parent = attached && _selectedElement?.kind == IdeaElementKind.image
        ? _selectedElement
        : null;
    final e = IdeaElement(
      id: newSharedId(),
      kind: sticky ? IdeaElementKind.sticky : IdeaElementKind.text,
      x: parent == null ? 100 : 1.04,
      y: parent == null ? 100 : .05,
      width: parent == null ? 300 : .65,
      height: parent == null ? 180 : .6,
      text: value,
      color: sticky ? 0xffffe69a : _color,
      parentImageId: parent?.id,
    );
    _change(_board.copyWith(elements: [..._board.elements, e]));
    setState(() {
      _selected = e.id;
      _tool = IdeaTool.select;
    });
  }

  void _replace(IdeaElement element) {
    element = element.copyWith(
      width: element.width.clamp(
        element.kind == IdeaElementKind.image ? 1 : 0,
        element.parentImageId == null ? _board.width : 32768,
      ),
      height: element.height.clamp(
        element.kind == IdeaElementKind.image ? 1 : 0,
        element.parentImageId == null ? _board.height : 32768,
      ),
    );
    _change(
      _board.copyWith(
        elements: _board.elements
            .map((e) => e.id == element.id ? element : e)
            .toList(),
      ),
    );
  }

  Future<void> _photo() async {
    if (!_editable || _busy) return;
    final photoError = context.l10n.ideasPhotoError;
    if (_board.assets.length >= 20) {
      _message(context.l10n.ideasPhotoLimit);
      return;
    }
    try {
      Uint8List bytes;
      if (usesPrivateMobileFileIo) {
        final selected = await pickPrivateFile(
          extensions: ['jpg', 'jpeg', 'png'],
          maxBytes: 20 * 1024 * 1024,
        );
        if (selected == null || !mounted || !_editable) return;
        bytes = selected.bytes;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png'],
          withData: false,
          withReadStream: true,
        );
        if (result == null || !mounted || !_editable) return;
        bytes = await readBoundedBackup(
          result.files.single,
          maxBytes: 20 * 1024 * 1024,
        );
      }
      if (!mounted || !_editable) return;
      setState(() => _busy = true);
      final asset = await ref.read(ideaProvider.notifier).importImage(bytes);
      if (!mounted || !_editable) return;
      final scale = math.min(
        1.0,
        math.min(650 / asset.width, 1000 / asset.height),
      );
      final width = asset.width * scale, height = asset.height * scale;
      final e = IdeaElement(
        id: newSharedId(),
        kind: IdeaElementKind.image,
        x: 80,
        y: 80,
        width: width,
        height: height,
        asset: asset,
      );
      setState(() => _busy = false);
      _change(_board.copyWith(elements: [..._board.elements, e]));
      setState(() {
        _selected = e.id;
        _tool = IdeaTool.select;
      });
      await _loadImages();
    } catch (_) {
      _message(photoError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _undoChange(bool redo) {
    if (!_editable || _busy) return;
    final source = redo ? _redo : _undo, target = redo ? _undo : _redo;
    if (source.isEmpty) return;
    target.add(_board);
    final board = source.removeLast();
    _title.text = board.title;
    _change(board, history: false);
  }

  Future<void> _chooseElement() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in _board.elements)
              ListTile(
                key: ValueKey('idea-element-${e.id}'),
                leading: Icon(
                  e.kind == IdeaElementKind.image
                      ? Icons.image_outlined
                      : e.kind == IdeaElementKind.sticky
                      ? Icons.note_outlined
                      : Icons.draw_outlined,
                ),
                title: Text(
                  e.text.isEmpty
                      ? '${context.l10n.ideasElements} · ${e.kind.name}'
                      : e.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, e.id),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted && _sameContext) {
      setState(() {
        _selected = selected;
        _tool = IdeaTool.select;
      });
    }
  }

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? callback, {
    bool selected = false,
    Key? key,
  }) => IconButton(
    key: key,
    tooltip: label,
    onPressed: _busy ? null : callback,
    isSelected: selected,
    style: selected
        ? IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          )
        : null,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: Icon(icon),
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(ideaProvider);
    ref.watch(collaborationProvider);
    if (!_sameContext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pop(context);
        }
      });
      return Scaffold(
        body: Center(child: Text(context.l10n.sharingSessionExpired)),
      );
    }
    final desktop =
        organizerUsesDesktopLayout(context) &&
        MediaQuery.sizeOf(context).width >= 1000;
    final l = context.l10n, selected = _selectedElement, editable = _editable;
    final sharedState = ref.watch(collaborationProvider).valueOrNull;
    final scope = sharedState?.scopes
        .where((s) => s.id == widget.sharedScopeId)
        .firstOrNull;
    final projects = widget.sharedScopeId == null
        ? ref.watch(organizerProvider).valueOrNull?.projects ?? []
        : sharedState?.dataForScope(widget.sharedScopeId!).projects ?? [];
    final fixedProject = scope?.kind == SharedScopeKind.project
        ? scope?.projectRootId ?? scope?.id
        : null;
    final projectOptions = scope?.kind == SharedScopeKind.organization
        ? <String, String>{}
        : {
            for (final project in projects.where((p) => !p.archived))
              project.id: project.title,
          };
    final missing = _board.assets.any((a) => !_images.containsKey(a.sha256));
    final tools = <(IdeaTool, String, IconData)>[
      (IdeaTool.select, l.ideasSelect, Icons.touch_app_outlined),
      (IdeaTool.pan, l.ideasPan, Icons.pan_tool_outlined),
      (IdeaTool.pen, l.ideasPen, Icons.edit_outlined),
      (IdeaTool.highlighter, l.ideasHighlighter, Icons.border_color_outlined),
      (IdeaTool.eraser, l.ideasEraser, Icons.auto_fix_normal_outlined),
      (IdeaTool.line, l.ideasLine, Icons.horizontal_rule),
      (IdeaTool.arrow, l.ideasArrow, Icons.north_east),
      (IdeaTool.rectangle, l.ideasRectangle, Icons.crop_square),
      (IdeaTool.ellipse, l.ideasEllipse, Icons.circle_outlined),
    ];
    return PopScope(
      canPop: _allowPop || !_sameContext || !_dirty && !_busy,
      onPopInvokedWithResult: (popped, result) {
        if (!popped) unawaited(_leave());
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyZ, control: true):
              _UndoIntent(),
          SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
              _RedoIntent(),
          SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _UndoIntent(),
          SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
              _RedoIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _UndoIntent: CallbackAction<_UndoIntent>(
              onInvoke: (_) {
                _undoChange(false);
                return null;
              },
            ),
            _RedoIntent: CallbackAction<_RedoIntent>(
              onInvoke: (_) {
                _undoChange(true);
                return null;
              },
            ),
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: l.close,
                onPressed: _busy ? null : _leave,
                icon: const Icon(Icons.close),
              ),
              title: EditorHeading(
                title: l.ideasTitle,
                busy: _busy,
                onReport:
                    widget.base != null &&
                        widget.sharedScopeId != null &&
                        ref
                                .read(collaborationProvider)
                                .valueOrNull
                                ?.scopes
                                .where((s) => s.id == widget.sharedScopeId)
                                .firstOrNull
                                ?.kind !=
                            SharedScopeKind.personal
                    ? () => showContentReport(
                        context,
                        ref,
                        scopeId: widget.sharedScopeId!,
                        targetType: 'record',
                        targetId: widget.base!.id,
                      )
                    : null,
              ),
              actions: [
                IconButton(
                  key: const ValueKey('idea-elements'),
                  tooltip: l.ideasElements,
                  onPressed: _chooseElement,
                  icon: const Icon(Icons.layers_outlined),
                ),
                IconButton(
                  tooltip: l.ideasHelp,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      content: Text(l.ideasHelp),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(l.close),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.help_outline),
                ),
              ],
            ),
            body: SafeArea(
              child: _IdeaWorkspace(
                desktop: desktop,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: TextField(
                      key: const ValueKey('idea-title'),
                      controller: _title,
                      readOnly: !editable || _busy,
                      maxLength: 200,
                      decoration: InputDecoration(
                        labelText: l.organizerTitle,
                        counterText: '',
                        isDense: true,
                      ),
                      onChanged: (value) => _change(
                        _board.copyWith(title: value),
                        history: false,
                      ),
                    ),
                  ),
                  if (editable &&
                      fixedProject == null &&
                      (projectOptions.isNotEmpty || _board.projectId != null))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('idea-project-${_board.projectId}'),
                        initialValue: _board.projectId ?? '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l.ideasProject,
                          isDense: true,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(l.ideasNoProject),
                          ),
                          for (final entry in projectOptions.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (_board.projectId != null &&
                              !projectOptions.containsKey(_board.projectId))
                            DropdownMenuItem(
                              value: _board.projectId,
                              child: Text(l.organizerNoProject),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => _change(
                                _board.copyWith(
                                  projectId: value == '' ? null : value,
                                  clearProjectId: value == '',
                                ),
                              ),
                      ),
                    ),
                  if (editable)
                    _IdeaToolbar(
                      desktop: desktop,
                      height: 52,
                      children: [
                        for (final t in tools)
                          _button(
                            t.$2,
                            t.$3,
                            _busy ? null : () => setState(() => _tool = t.$1),
                            selected: _tool == t.$1,
                            key: ValueKey('idea-tool-${t.$1.name}'),
                          ),
                        _button(
                          l.ideasText,
                          Icons.text_fields,
                          _busy ? null : () => _text(),
                        ),
                        _button(
                          l.ideasSticky,
                          Icons.note_outlined,
                          _busy ? null : () => _text(sticky: true),
                        ),
                        _button(
                          l.ideasPhoto,
                          Icons.add_photo_alternate_outlined,
                          _busy ? null : _photo,
                        ),
                        _button(
                          l.ideasUndo,
                          Icons.undo,
                          _undo.isEmpty || _busy
                              ? null
                              : () => _undoChange(false),
                        ),
                        _button(
                          l.ideasRedo,
                          Icons.redo,
                          _redo.isEmpty || _busy
                              ? null
                              : () => _undoChange(true),
                        ),
                      ],
                    ),
                  if (editable)
                    _IdeaToolbar(
                      desktop: desktop,
                      height: 48,
                      children: [
                        for (final color in [
                          0xff263238,
                          0xff2367c8,
                          0xffdc3545,
                          0xff2c854e,
                          0xffffc107,
                          0xffffffff,
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Semantics(
                              label:
                                  '${l.ideasColor} ${color.toRadixString(16)}',
                              selected: _color == color,
                              child: IconButton(
                                tooltip: l.ideasColor,
                                onPressed: () => setState(() => _color = color),
                                icon: Icon(
                                  _color == color
                                      ? Icons.check_circle
                                      : Icons.circle,
                                  color: Color(color),
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ),
                          ),
                        SizedBox(
                          width: 120,
                          child: Slider(
                            semanticFormatterCallback: (v) =>
                                '${l.ideasWidth} ${v.round()}',
                            value: _width,
                            min: 1,
                            max: 12,
                            divisions: 11,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _width = v),
                          ),
                        ),
                        if (selected != null) ...[
                          _button(
                            l.ideasRotate,
                            Icons.rotate_right,
                            () => _replace(
                              selected.copyWith(
                                rotation:
                                    (selected.rotation + math.pi / 12) %
                                    (2 * math.pi),
                              ),
                            ),
                          ),
                          _button(
                            l.ideasSize,
                            Icons.zoom_in,
                            () => _replace(
                              selected.copyWith(
                                width: selected.width * 1.1,
                                height: selected.height * 1.1,
                              ),
                            ),
                          ),
                          _button(
                            l.ideasSize,
                            Icons.zoom_out,
                            () => _replace(
                              selected.copyWith(
                                width: selected.width / 1.1,
                                height: selected.height / 1.1,
                              ),
                            ),
                          ),
                          if ([
                            IdeaElementKind.text,
                            IdeaElementKind.sticky,
                          ].contains(selected.kind)) ...[
                            _button(
                              l.ideasFontSizeIncrease,
                              Icons.text_increase,
                              () => _replace(
                                selected.copyWith(
                                  fontSize: (selected.fontSize * 1.2).clamp(
                                    selected.parentImageId == null ? 6 : .005,
                                    selected.parentImageId == null ? 300 : 2,
                                  ),
                                ),
                              ),
                            ),
                            _button(
                              l.ideasFontSizeDecrease,
                              Icons.text_decrease,
                              () => _replace(
                                selected.copyWith(
                                  fontSize: (selected.fontSize / 1.2).clamp(
                                    selected.parentImageId == null ? 6 : .005,
                                    selected.parentImageId == null ? 300 : 2,
                                  ),
                                ),
                              ),
                            ),
                            _button(
                              l.ideasEditText,
                              Icons.edit_note,
                              () => _text(element: selected),
                            ),
                          ],
                          if (selected.kind == IdeaElementKind.image)
                            _button(
                              l.ideasAttachNote,
                              Icons.note_add_outlined,
                              () => _text(sticky: true, attached: true),
                            ),
                          _button(
                            l.ideasDeleteElement,
                            Icons.delete_outline,
                            () => _change(
                              _board.copyWith(
                                elements: _board.elements
                                    .where(
                                      (e) =>
                                          e.id != selected.id &&
                                          e.parentImageId != selected.id,
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  if (missing)
                    Row(
                      children: [
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.image_not_supported_outlined,
                          size: 18,
                        ),
                        Expanded(child: Text(l.ideasMissingPhoto, maxLines: 2)),
                        _button(
                          l.ideasRefreshPhotos,
                          Icons.download_outlined,
                          () => _loadImages(download: true),
                        ),
                      ],
                    ),
                  Expanded(
                    child: IdeaCanvas(
                      key: _canvasKey,
                      board: _board,
                      images: _images,
                      editable: editable && !_busy,
                      tool: editable ? _tool : IdeaTool.pan,
                      selectedId: _selected,
                      onSelected: (id) => setState(() => _selected = id),
                      color: _color,
                      strokeWidth: _width,
                      onChanged: _change,
                      onEditText: (e) => _text(element: e),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Text(
                      editable
                          ? (_draftError
                                ? l.ideasDraftError
                                : _draftSaving || _draftTimer?.isActive == true
                                ? l.ideasDraftPending
                                : _draftSaved
                                ? l.ideasDraft
                                : l.ideasDraftHint)
                          : widget.readOnlyReason ?? l.ideasReadOnly,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 3,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: editable
                        ? EditorActionsRow(
                            onDelete: widget.base == null ? null : _delete,
                            onCancel: _leave,
                            onSave: _save,
                            busy: _busy,
                            saveKey: const ValueKey('idea-save'),
                          )
                        : Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (widget.onReadOnlyAction != null)
                                  Expanded(
                                    child: TextButton(
                                      key: const ValueKey(
                                        'idea-review-private',
                                      ),
                                      onPressed: () async {
                                        if (!_sameContext) return;
                                        await _leave();
                                        widget.onReadOnlyAction?.call();
                                      },
                                      child: Text(l.privateSyncTitle),
                                    ),
                                  ),
                                TextButton(
                                  onPressed: _leave,
                                  child: Text(l.close),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

/// Wide desktop windows reserve the canvas height and keep metadata/tools in a
/// scrollable side panel. The same form and canvas move intact when resizing.
class _IdeaWorkspace extends StatelessWidget {
  const _IdeaWorkspace({required this.desktop, required this.children});
  final bool desktop;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!desktop) return Column(children: children);
    final canvasIndex = children.indexWhere((child) => child is Expanded);
    return Row(
      key: const ValueKey('idea-desktop-workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children.take(canvasIndex).toList(),
                  ),
                ),
              ),
              const Divider(height: 1),
              ...children.skip(canvasIndex + 1),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        children[canvasIndex],
      ],
    );
  }
}

class _IdeaToolbar extends StatelessWidget {
  const _IdeaToolbar({
    required this.desktop,
    required this.height,
    required this.children,
  });
  final bool desktop;
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => desktop
      ? Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          ),
        )
      : SizedBox(
          height: height,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: children),
          ),
        );
}
