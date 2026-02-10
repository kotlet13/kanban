import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

class ThemeModeMenuButton extends ConsumerWidget {
  const ThemeModeMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
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
      icon: Icon(icon),
      onSelected: (value) {
        ref.read(themeModeProvider.notifier).state = value;
      },
      itemBuilder: (context) => const <PopupMenuEntry<ThemeMode>>[
        PopupMenuItem<ThemeMode>(
          value: ThemeMode.system,
          child: Text('System theme'),
        ),
        PopupMenuItem<ThemeMode>(
          value: ThemeMode.light,
          child: Text('Light theme'),
        ),
        PopupMenuItem<ThemeMode>(
          value: ThemeMode.dark,
          child: Text('Dark theme'),
        ),
      ],
    );
  }
}
