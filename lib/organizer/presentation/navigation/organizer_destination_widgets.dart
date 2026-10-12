import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import 'organizer_navigation.dart';

/// A label remains readable at enlarged text sizes without swiping page content.
class OrganizerPlannerViews extends StatelessWidget {
  const OrganizerPlannerViews({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final OrganizerArea selected;
  final ValueChanged<OrganizerArea> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (area, label, icon) in [
            (OrganizerArea.plans, l.organizerTasks, Icons.checklist_outlined),
            (
              OrganizerArea.calendar,
              l.organizerCalendar,
              Icons.calendar_month_outlined,
            ),
            (OrganizerArea.ideas, l.ideasTitle, Icons.lightbulb_outline),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('planner-view-${area.name}'),
                avatar: Icon(icon, size: 18),
                label: Text(label),
                selected: selected == area,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                onSelected: (_) => onSelected(area),
              ),
            ),
        ],
      ),
    );
  }
}

class OrganizerHubLink extends StatelessWidget {
  const OrganizerHubLink({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final emblem = ExcludeSemantics(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: colors.primary),
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 420 &&
              MediaQuery.textScalerOf(context).scale(16) > 24;
          return ListTile(
            minTileHeight: 72,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: stacked ? null : emblem,
            title: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          emblem,
                          const Spacer(),
                          const ExcludeSemantics(
                            child: Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(title),
                    ],
                  )
                : Text(title),
            subtitle: subtitle == null ? null : Text(subtitle!),
            trailing: stacked
                ? null
                : const ExcludeSemantics(child: Icon(Icons.chevron_right)),
            onTap: onTap,
          );
        },
      ),
    );
  }
}
