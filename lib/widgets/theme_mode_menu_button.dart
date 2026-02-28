import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../state/providers.dart';

class ThemeModeMenuButton extends ConsumerWidget {
  const ThemeModeMenuButton({super.key});

  Future<void> _showThemeModeSheet(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
  ) async {
    final l10n = context.l10n;
    final selected = await showCupertinoModalPopup<ThemeMode>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(l10n.themeMode),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop(ThemeMode.system);
            },
            child: _ThemeActionLabel(
              text: l10n.systemTheme,
              selected: mode == ThemeMode.system,
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop(ThemeMode.light);
            },
            child: _ThemeActionLabel(
              text: l10n.lightTheme,
              selected: mode == ThemeMode.light,
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop(ThemeMode.dark);
            },
            child: _ThemeActionLabel(
              text: l10n.darkTheme,
              selected: mode == ThemeMode.dark,
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ),
    );

    if (selected == null || selected == mode) return;
    ref.read(themeModeProvider.notifier).state = selected;
    ref.read(themeModeStoreProvider).save(selected);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final l10n = context.l10n;
    IconData icon;
    switch (mode) {
      case ThemeMode.light:
        icon = CupertinoIcons.sun_max_fill;
        break;
      case ThemeMode.dark:
        icon = CupertinoIcons.moon_stars_fill;
        break;
      case ThemeMode.system:
        icon = CupertinoIcons.circle_lefthalf_fill;
        break;
    }

    return Tooltip(
      message: l10n.themeMode,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: const Size(32, 32),
        onPressed: () => _showThemeModeSheet(context, ref, mode),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ThemeActionLabel extends StatelessWidget {
  const _ThemeActionLabel({required this.text, required this.selected});

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (selected) ...<Widget>[
          const Icon(CupertinoIcons.check_mark_circled_solid, size: 18),
          const SizedBox(width: 8),
        ],
        Text(text),
      ],
    );
  }
}
