import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n.dart';
import 'desktop_inspector.dart';

/// One workspace frame across desktop operating systems. Resizing a window
/// rearranges the same inspector element, preserving its unfinished form.
class OrganizerDesktopFrame extends StatefulWidget {
  const OrganizerDesktopFrame({
    super.key,
    required this.sidebar,
    required this.toolbar,
    required this.content,
    required this.inspector,
    required this.controller,
  });
  final Widget Function(bool compact) sidebar;
  final Widget Function(VoidCallback toggleSidebar) toolbar;
  final Widget content, inspector;
  final OrganizerDesktopInspectorController controller;
  @override
  State<OrganizerDesktopFrame> createState() => _OrganizerDesktopFrameState();
}

class _OrganizerDesktopFrameState extends State<OrganizerDesktopFrame> {
  double _sidebarWidth = 240, _inspectorWidth = 420;
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final open = widget.controller.isOpen;
        final showBeside = width >= 1040;
        final compact = _collapsed || width < 800;
        final sidebarWidth = compact ? 64.0 : _sidebarWidth.clamp(200.0, 300.0);
        final inspectorWidth = _inspectorWidth.clamp(
          340.0,
          (width - sidebarWidth - 340).clamp(340.0, 560.0),
        );
        final colors = Theme.of(context).colorScheme;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: sidebarWidth, child: widget.sidebar(compact)),
            if (!compact)
              _PaneDivider(
                label: context.l10n.desktopResizeSidebar,
                value: sidebarWidth,
                onChange: (delta) => setState(
                  () => _sidebarWidth = (_sidebarWidth + delta).clamp(200, 300),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: widget.toolbar(
                      () => setState(() => _collapsed = !_collapsed),
                    ),
                  ),
                  Expanded(
                    child: open && !showBeside
                        ? widget.inspector
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: widget.content),
                              if (open) ...[
                                _PaneDivider(
                                  label: context.l10n.desktopResizeInspector,
                                  value: inspectorWidth,
                                  valueDirection: -1,
                                  onChange: (delta) => setState(
                                    () => _inspectorWidth =
                                        (_inspectorWidth - delta).clamp(
                                          340,
                                          560,
                                        ),
                                  ),
                                ),
                                SizedBox(
                                  width: inspectorWidth,
                                  child: widget.inspector,
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _PaneDivider extends StatelessWidget {
  const _PaneDivider({
    required this.label,
    required this.value,
    required this.onChange,
    this.valueDirection = 1,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChange;
  final double valueDirection;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: label,
    value: '${value.round()}',
    increasedValue: '${(value + 20).round()}',
    decreasedValue: '${(value - 20).round()}',
    onIncrease: () => onChange(20 * valueDirection),
    onDecrease: () => onChange(-20 * valueDirection),
    child: Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onChange(event.logicalKey == LogicalKeyboardKey.arrowLeft ? -20 : 20);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => onChange(details.delta.dx),
          child: Container(
            width: 8,
            alignment: Alignment.center,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    ),
  );
}
