import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n.dart';
import '../navigation/organizer_navigation.dart';

/// Desktop commands call the shell's existing navigation and editor entry
/// points. Text operations resolve the focused Flutter action and never write
/// organizer records themselves.
class OrganizerDesktopCommands extends StatefulWidget {
  const OrganizerDesktopCommands({
    super.key,
    required this.child,
    required this.onSearch,
    required this.onSettings,
    required this.onNavigate,
    required this.visibleAreas,
    required this.areaLabel,
    this.onNew,
    this.canGoBack = false,
    this.onBack,
    this.platform,
  });

  final Widget child;
  final VoidCallback? onNew;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final ValueChanged<OrganizerArea> onNavigate;
  final List<OrganizerArea> visibleAreas;
  final String Function(OrganizerArea) areaLabel;
  final bool canGoBack;
  final VoidCallback? onBack;
  final TargetPlatform? platform;

  @override
  State<OrganizerDesktopCommands> createState() =>
      _OrganizerDesktopCommandsState();
}

class _OrganizerDesktopCommandsState extends State<OrganizerDesktopCommands> {
  final _menuScope = FocusScopeNode(debugLabel: 'Desktop menu');
  FocusNode? _editingFocus;
  bool _focusUpdatePending = false;

  TargetPlatform get _platform => widget.platform ?? defaultTargetPlatform;
  bool get _mac => _platform == TargetPlatform.macOS;
  bool get _desktop =>
      !kIsWeb &&
      (_mac ||
          _platform == TargetPlatform.windows ||
          _platform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _menuScope.dispose();
    super.dispose();
  }

  void _focusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    // Opening an in-window menu moves keyboard focus into the menu. Keep its
    // previous text target so mouse and keyboard menu activation work alike.
    if (focus == _menuScope ||
        (focus != null && focus.ancestors.contains(_menuScope))) {
      return;
    }
    _editingFocus = focus;
    if (_focusUpdatePending) return;
    _focusUpdatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusUpdatePending = false;
      if (mounted) setState(() {});
    });
  }

  void _refreshEditMenu() {
    if (mounted) setState(() {});
  }

  bool _canEdit(Intent intent) {
    final target = _editingFocus?.context;
    if (target == null || !target.mounted) return false;
    final action = Actions.maybeFind<Intent>(target, intent: intent);
    return action != null && action.isEnabled(intent);
  }

  VoidCallback? _editCallback(Intent intent) {
    if (!_canEdit(intent)) return null;
    return () {
      final focus = _editingFocus;
      final target = focus?.context;
      if (target == null || !target.mounted) return;
      focus!.requestFocus();
      Actions.maybeInvoke(target, intent);
    };
  }

  bool get _textHasFocus {
    final target = FocusManager.instance.primaryFocus?.context;
    return target?.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _backShortcut() {
    if (!_textHasFocus && widget.canGoBack) widget.onBack?.call();
  }

  SingleActivator _shortcut(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(key, meta: _mac, control: !_mac, shift: shift);

  SingleActivator get _backKey => _mac
      ? const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true)
      : const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true);

  List<({String label, Intent intent, SingleActivator shortcut})> _edits(
    AppLocalizations l,
  ) => [
    (
      label: l.desktopUndo,
      intent: const UndoTextIntent(SelectionChangedCause.keyboard),
      shortcut: _shortcut(LogicalKeyboardKey.keyZ),
    ),
    (
      label: l.desktopRedo,
      intent: const RedoTextIntent(SelectionChangedCause.keyboard),
      shortcut: _mac
          ? _shortcut(LogicalKeyboardKey.keyZ, shift: true)
          : _shortcut(LogicalKeyboardKey.keyY),
    ),
    (
      label: l.desktopCut,
      intent: const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
      shortcut: _shortcut(LogicalKeyboardKey.keyX),
    ),
    (
      label: l.desktopCopy,
      intent: CopySelectionTextIntent.copy,
      shortcut: _shortcut(LogicalKeyboardKey.keyC),
    ),
    (
      label: l.desktopPaste,
      intent: const PasteTextIntent(SelectionChangedCause.keyboard),
      shortcut: _shortcut(LogicalKeyboardKey.keyV),
    ),
    (
      label: l.desktopSelectAll,
      intent: const SelectAllTextIntent(SelectionChangedCause.keyboard),
      shortcut: _shortcut(LogicalKeyboardKey.keyA),
    ),
  ];

  List<PlatformMenuItem> _nativeMenus(AppLocalizations l) => [
    PlatformMenu(
      label: l.organizerAppName,
      menus: [
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.about,
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l.organizerSettings,
              shortcut: _shortcut(LogicalKeyboardKey.comma),
              onSelected: widget.onSettings,
            ),
          ],
        ),
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.servicesSubmenu,
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: l.desktopMenuFile,
      menus: [
        PlatformMenuItem(
          label: l.desktopNew,
          shortcut: _shortcut(LogicalKeyboardKey.keyN),
          onSelected: widget.onNew,
        ),
      ],
    ),
    PlatformMenu(
      label: l.desktopMenuEdit,
      onOpen: _refreshEditMenu,
      menus: [
        for (final entry in _edits(l))
          PlatformMenuItem(
            label: entry.label,
            shortcut: entry.shortcut,
            onSelected: _editCallback(entry.intent),
          ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l.desktopSearch,
              shortcut: _shortcut(LogicalKeyboardKey.keyF),
              onSelected: widget.onSearch,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: l.desktopMenuView,
      menus: [
        PlatformMenuItem(
          label: l.desktopBack,
          // macOS dispatches native menu shortcuts before Flutter receives the
          // key. Leave editing shortcuts to the text field while it has focus;
          // clicking the Back menu item remains an explicit navigation action.
          shortcut: _textHasFocus ? null : _backKey,
          onSelected: widget.canGoBack ? widget.onBack : null,
        ),
        PlatformMenuItemGroup(
          members: [
            for (final area in widget.visibleAreas)
              PlatformMenuItem(
                label: widget.areaLabel(area),
                onSelected: () => widget.onNavigate(area),
              ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: l.desktopMenuWindow,
      menus: const [
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.minimizeWindow,
        ),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.toggleFullScreen,
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      ],
    ),
  ];

  Widget _inWindowMenus(AppLocalizations l) => FocusScope(
    node: _menuScope,
    child: SizedBox(
      width: double.infinity,
      child: MenuBar(
        children: [
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: widget.onNew,
                shortcut: _shortcut(LogicalKeyboardKey.keyN),
                child: Text(l.desktopNew),
              ),
              const Divider(),
              MenuItemButton(
                onPressed: widget.onSettings,
                shortcut: _shortcut(LogicalKeyboardKey.comma),
                child: Text(l.organizerSettings),
              ),
            ],
            child: Text(l.desktopMenuFile),
          ),
          SubmenuButton(
            onOpen: _refreshEditMenu,
            menuChildren: [
              for (final entry in _edits(l))
                MenuItemButton(
                  onPressed: _editCallback(entry.intent),
                  shortcut: entry.shortcut,
                  child: Text(entry.label),
                ),
              const Divider(),
              MenuItemButton(
                onPressed: widget.onSearch,
                shortcut: _shortcut(LogicalKeyboardKey.keyF),
                child: Text(l.desktopSearch),
              ),
            ],
            child: Text(l.desktopMenuEdit),
          ),
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: widget.canGoBack ? widget.onBack : null,
                shortcut: _backKey,
                child: Text(l.desktopBack),
              ),
              const Divider(),
              for (final area in widget.visibleAreas)
                MenuItemButton(
                  onPressed: () => widget.onNavigate(area),
                  child: Text(widget.areaLabel(area)),
                ),
            ],
            child: Text(l.desktopMenuView),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_desktop) return widget.child;
    final l = context.l10n;
    final content = CallbackShortcuts(
      bindings: {
        if (widget.onNew != null)
          _shortcut(LogicalKeyboardKey.keyN): widget.onNew!,
        _shortcut(LogicalKeyboardKey.keyF): widget.onSearch,
        _shortcut(LogicalKeyboardKey.comma): widget.onSettings,
        _backKey: _backShortcut,
        if (_mac)
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
              _backShortcut,
      },
      child: widget.child,
    );
    if (_mac) {
      // The Flutter menu channel replaces the initial XIB menu; it does not
      // append another menu bar. OS-supplied window/application actions retain
      // their native behavior.
      return PlatformMenuBar(menus: _nativeMenus(l), child: content);
    }
    return Column(
      children: [
        _inWindowMenus(l),
        Expanded(child: content),
      ],
    );
  }
}
