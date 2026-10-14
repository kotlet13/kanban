import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Visibility belongs to this field instance and never changes its value.
class PasswordVisibility extends StatefulWidget {
  const PasswordVisibility({
    super.key,
    required this.builder,
    this.secret = true,
    this.enabled = true,
  });

  final Widget Function(bool obscure, Widget? toggle) builder;
  final bool secret, enabled;

  @override
  State<PasswordVisibility> createState() => _PasswordVisibilityState();
}

class _PasswordVisibilityState extends State<PasswordVisibility> {
  bool _visible = false;

  @override
  void didUpdateWidget(PasswordVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.secret != oldWidget.secret) _visible = false;
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    widget.secret && !_visible,
    widget.secret
        ? IconButton(
            tooltip: _visible
                ? context.l10n.passwordHide
                : context.l10n.passwordShow,
            onPressed: widget.enabled
                ? () => setState(() => _visible = !_visible)
                : null,
            icon: Icon(
              _visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          )
        : null,
  );
}
