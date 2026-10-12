import 'dart:async';

import 'package:flutter/material.dart';

/// Owns one editing session. Opening another row never replaces an unsaved form.
class OrganizerDesktopInspectorController extends ChangeNotifier {
  _InspectorSession? _session;

  bool get isOpen => _session != null;

  Future<void> show(WidgetBuilder builder) {
    if (_session != null) return _session!.completion.future;
    final session = _InspectorSession(builder);
    _session = session;
    notifyListeners();
    return session.completion.future;
  }

  /// For invalidated identity/scope or shell disposal. Ordinary user dismissal
  /// goes through the editor's Cancel action and its existing busy state.
  void dismiss() {
    final previous = _session;
    if (previous == null) return;
    _session = null;
    previous.completion.complete();
    notifyListeners();
  }

  @override
  void dispose() {
    final previous = _session;
    _session = null;
    previous?.completion.complete();
    super.dispose();
  }
}

class _InspectorSession {
  _InspectorSession(this.builder);
  final WidgetBuilder builder;
  final completion = Completer<void>();
}

class OrganizerDesktopInspectorScope extends InheritedWidget {
  const OrganizerDesktopInspectorScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final OrganizerDesktopInspectorController controller;

  static OrganizerDesktopInspectorController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OrganizerDesktopInspectorScope>()
          ?.controller;

  @override
  bool updateShouldNotify(OrganizerDesktopInspectorScope oldWidget) =>
      controller != oldWidget.controller;
}

/// A scoped Navigator gives the existing editors and ACL boundaries a real
/// route to pop without dismissing the organizer itself.
class OrganizerDesktopInspectorPanel extends StatelessWidget {
  const OrganizerDesktopInspectorPanel({super.key, required this.controller});

  final OrganizerDesktopInspectorController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final session = controller._session;
      if (session == null) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: constraints.biggest),
          child: ClipRect(
            key: const ValueKey('organizer-desktop-inspector'),
            child: Navigator(
              key: ObjectKey(session),
              observers: [_InspectorObserver(controller, session)],
              onGenerateInitialRoutes: (_, _) => [
                _route('/inspector-base', (_) => const SizedBox.shrink()),
                _route('/inspector-editor', session.builder),
              ],
              onGenerateRoute: (_) => null,
            ),
          ),
        ),
      );
    },
  );

  static Route<void> _route(String name, WidgetBuilder builder) =>
      PageRouteBuilder<void>(
        settings: RouteSettings(name: name),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => builder(context),
      );
}

class _InspectorObserver extends NavigatorObserver {
  _InspectorObserver(this.controller, this.session);
  final OrganizerDesktopInspectorController controller;
  final _InspectorSession session;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != '/inspector-editor') return;
    // Navigator notifications can happen during route/guard builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(controller._session, session)) controller.dismiss();
    });
  }
}

/// Uses one existing editor's title, fields and actions inside the inspector.
/// Validation and persistence remain entirely in that editor.
class OrganizerDesktopEditorSurface extends StatelessWidget {
  const OrganizerDesktopEditorSurface({super.key, required this.dialog});
  final AlertDialog dialog;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dialog.title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: DefaultTextStyle(
              style:
                  dialog.titleTextStyle ??
                  Theme.of(context).textTheme.titleLarge!,
              child: dialog.title!,
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: dialog.content,
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: dialog.actions ?? const []),
        ),
      ],
    ),
  );
}
