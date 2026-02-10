import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

class ThemeModeMenuButton extends ConsumerWidget {
  const ThemeModeMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);
    IconData icon;
    switch (mode) {
      case ThemeMode.light:
        icon = Icons.light_mode;
        break;
      case ThemeMode.dark:
        icon = Icons.dark_mode;
        break;
      case ThemeMode.system:
        icon = Icons.brightness_auto;
        break;
    }

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Theme mode',
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.65,
        ),
      ),
      onSelected: (value) {
        ref.read(themeModeProvider.notifier).state = value;
      },
      itemBuilder: (context) => <PopupMenuEntry<ThemeMode>>[
        CheckedPopupMenuItem<ThemeMode>(
          checked: mode == ThemeMode.system,
          value: ThemeMode.system,
          child: Text('System theme'),
        ),
        CheckedPopupMenuItem<ThemeMode>(
          checked: mode == ThemeMode.light,
          value: ThemeMode.light,
          child: Text('Light theme'),
        ),
        CheckedPopupMenuItem<ThemeMode>(
          checked: mode == ThemeMode.dark,
          value: ThemeMode.dark,
          child: Text('Dark theme'),
        ),
      ],
    );
  }
}
