import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

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

class _PasswordVisibilityState extends State<PasswordVisibility>
    with WidgetsBindingObserver {
  bool _visible = false;
  final _inputOwner = FocusNode(skipTraversal: true, canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (defaultTargetPlatform != TargetPlatform.android ||
        !widget.secret ||
        !_inputOwner.hasFocus ||
        !const {
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.detached,
        }.contains(state)) {
      return;
    }
    // Release only this password's connection before another app starts input.
    // Android IMEs/autofill can emit inactive while typing, so leave that
    // transient state alone. Retapping keeps the password's private IME flags.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputOwner.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PasswordVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.secret != oldWidget.secret) _visible = false;
    if (defaultTargetPlatform == TargetPlatform.android &&
        widget.secret &&
        oldWidget.enabled &&
        !widget.enabled &&
        _inputOwner.hasFocus) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _inputOwner,
    child: widget.builder(
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
    ),
  );
}
