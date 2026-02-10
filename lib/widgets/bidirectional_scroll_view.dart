import 'package:flutter/material.dart';

class BidirectionalScrollView extends StatefulWidget {
  const BidirectionalScrollView({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.alwaysScrollable = false,
    this.contentWidth,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool alwaysScrollable;
  final double? contentWidth;

  @override
  State<BidirectionalScrollView> createState() => _BidirectionalScrollViewState();
}

class _BidirectionalScrollViewState extends State<BidirectionalScrollView> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final showDesktopScrollbars = platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeMaxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1200.0;
        final safeMaxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 800.0;

        return Scrollbar(
          controller: _verticalController,
          thumbVisibility: showDesktopScrollbars,
          trackVisibility: showDesktopScrollbars,
          child: SingleChildScrollView(
            controller: _verticalController,
            physics: widget.alwaysScrollable
                ? const AlwaysScrollableScrollPhysics()
                : null,
            child: Scrollbar(
              controller: _horizontalController,
              thumbVisibility: showDesktopScrollbars,
              trackVisibility: showDesktopScrollbars,
              notificationPredicate: (notification) {
                return notification.metrics.axis == Axis.horizontal;
              },
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: widget.contentWidth == null
                      ? null
                      : (widget.contentWidth! > safeMaxWidth
                          ? widget.contentWidth!
                          : safeMaxWidth),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: safeMaxWidth,
                      minHeight: safeMaxHeight,
                    ),
                    child: Padding(
                      padding: widget.padding,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
