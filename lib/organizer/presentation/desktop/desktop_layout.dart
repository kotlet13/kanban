import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Desktop windows remain desktop windows when resized. A large mobile screen
/// still uses the existing mobile/tablet presentation.
bool organizerIsDesktopPlatform(BuildContext context) =>
    !kIsWeb &&
    switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };

bool organizerUsesDesktopLayout(BuildContext context) =>
    organizerIsDesktopPlatform(context) ||
    (kIsWeb && MediaQuery.sizeOf(context).width >= 900);
