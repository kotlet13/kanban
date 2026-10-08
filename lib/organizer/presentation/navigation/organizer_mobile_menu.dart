import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../widgets/jivie_brand_mark.dart';

class OrganizerMenuItem {
  const OrganizerMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
    this.unread = false,
  });
  final String id, label;
  final IconData icon;
  final bool selected, unread;
  final VoidCallback onSelected;
}

/// A scrollable phone menu. Selection closes the drawer before navigation.
class OrganizerMobileMenu extends StatelessWidget {
  const OrganizerMobileMenu({super.key, required this.items});
  final List<OrganizerMenuItem> items;

  @override
  Widget build(BuildContext context) => Drawer(
    key: const ValueKey('organizer-mobile-menu'),
    width: 288,
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                const JivieBrandMark(size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text(context.l10n.organizerAppName)),
                IconButton(
                  key: const ValueKey('organizer-menu-close'),
                  tooltip: context.l10n.organizerMenuClose,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final item in items)
                  ListTile(
                    key: ValueKey('organizer-menu-${item.id}'),
                    selected: item.selected,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    leading: Badge(
                      isLabelVisible: item.unread,
                      child: Icon(item.icon),
                    ),
                    title: Text(item.label),
                    onTap: () {
                      Navigator.pop(context);
                      item.onSelected();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
