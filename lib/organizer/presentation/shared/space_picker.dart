import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_forms.dart';
import 'sharing_errors.dart';
import '../../state/local_spaces_provider.dart';

class OrganizerSpacePicker extends ConsumerWidget {
  const OrganizerSpacePicker({
    super.key,
    required this.onSelected,
    required this.onConnect,
    this.compact = false,
    this.onAllSelected,
    this.onLocalSelected,
  });
  final ValueChanged<String?> onSelected;
  final VoidCallback onConnect;
  final bool compact;
  final VoidCallback? onAllSelected;
  final ValueChanged<String>? onLocalSelected;
  static const allAction = 'all-spaces';
  static const createAction = 'create-space';
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    String? id;
    await showSharingForm(
      context,
      title: l.spacePickerNewSpace,
      description: l.localSpaceDescription,
      fields: [
        SharingField(id: 'name', label: l.sharingSpaceName),
        SharingField(
          id: 'kind',
          label: l.sharingScopeType,
          initialValue: 'household',
          options: {
            'household': l.sharingHousehold,
            'organization': l.organizationTitle,
          },
        ),
        SharingField(
          id: 'address',
          label: l.localSpaceAddress,
          required: false,
        ),
      ],
      submitLabel: l.localSpaceCreate,
      errorMessage: (error) => sharingErrorMessage(context, error),
      onSubmit: (values) async {
        final created = await ref
            .read(localSpacesProvider.notifier)
            .createSpace(
              kind: LocalSpaceKind.values.byName(values['kind']!),
              name: values['name']!.trim(),
              address: values['address'] ?? '',
            );
        id = created.id;
      },
    );
    if (context.mounted && id != null) _selectLocal(ref, id!);
  }

  void _selectLocal(WidgetRef ref, String id) {
    if (onLocalSelected != null) {
      onLocalSelected!(id);
    } else {
      ref.read(collaborationProvider.notifier).selectSpace(null);
      ref.read(localSpacesProvider.notifier).selectSpace(id);
      onSelected(null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collaborationProvider).valueOrNull,
        l = context.l10n;
    final scopes =
        state?.scopes
            .where((scope) => scope.kind != SharedScopeKind.personal)
            .toList() ??
        <SharedScope>[];
    final local = ref.watch(localSpacesProvider).valueOrNull;
    final chosen = state?.selectedSpaceId;
    final chosenLocal = local?.selectedSpace;
    final localSpaces = local?.spaces ?? <LocalSpace>[];
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final allSelected = state?.allSpacesSelected == true;
    final selectedValue = allSelected
        ? allAction
        : chosen ?? 'local:${local?.selectedSpaceId ?? 'local'}';
    DropdownMenuItem<String> menuItem({
      required String value,
      required String title,
      required IconData icon,
      String? subtitle,
      bool enabled = true,
      bool separated = false,
    }) => DropdownMenuItem(
      value: value,
      enabled: enabled,
      child: _SpacePickerMenuRow(
        title: title,
        subtitle: subtitle,
        icon: icon,
        selected: value == selectedValue,
        enabled: enabled,
        separated: separated,
      ),
    );
    String scopeType(SharedScope scope) => switch (scope.kind) {
      SharedScopeKind.household => l.sharingHousehold,
      SharedScopeKind.project => l.spacePickerSharedProject,
      SharedScopeKind.organization => l.organizationTitle,
      SharedScopeKind.personal => l.organizerPersonal,
    };
    IconData scopeIcon(SharedScope scope) => scope.archived
        ? Icons.inventory_2_outlined
        : switch (scope.kind) {
            SharedScopeKind.household => Icons.home_outlined,
            SharedScopeKind.project => Icons.folder_outlined,
            SharedScopeKind.organization => Icons.business_outlined,
            SharedScopeKind.personal => Icons.person_outline,
          };
    final items = <DropdownMenuItem<String>>[
      menuItem(
        value: allAction,
        title: l.allSpacesTitle,
        icon: Icons.dashboard_outlined,
      ),
      for (final space in localSpaces.where((space) => space.binding == null))
        menuItem(
          value: 'local:${space.id}',
          title: space.name.isEmpty ? l.organizerPersonal : space.name,
          subtitle: l.localSpaceState,
          icon: switch (space.kind) {
            LocalSpaceKind.personal => Icons.person_outline,
            LocalSpaceKind.household => Icons.home_outlined,
            LocalSpaceKind.organization => Icons.business_outlined,
          },
        ),
      if (localSpaces.isEmpty)
        menuItem(
          value: 'local:local',
          title: l.organizerPersonal,
          icon: Icons.person_outline,
        ),
      for (final scope in scopes.where((scope) => !scope.archived))
        menuItem(
          value: scope.id,
          enabled: !scope.revoked,
          title: scope.revoked
              ? '${scope.name} · ${l.sharingAccessRevoked}'
              : scope.name,
          subtitle: scopeType(scope),
          icon: scopeIcon(scope),
        ),
      if (scopes.any((scope) => scope.archived))
        DropdownMenuItem(
          value: 'archived-section',
          enabled: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, top: 12),
            child: Text(
              l.scopeArchivedProjects,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      for (final scope in scopes.where((scope) => scope.archived))
        menuItem(
          value: scope.id,
          enabled: !scope.revoked,
          title: scope.name,
          subtitle: scopeType(scope),
          icon: scopeIcon(scope),
        ),
      if (chosen != null && !scopes.any((scope) => scope.id == chosen))
        menuItem(
          value: chosen,
          enabled: false,
          title: l.sharingAccessRevoked,
          icon: Icons.lock_outline,
        ),
      menuItem(
        value: createAction,
        title: l.spacePickerCreateAction,
        icon: Icons.add,
        separated: true,
      ),
    ];
    final selectedScope = scopes
        .where((scope) => scope.id == chosen)
        .firstOrNull;
    final chosenLabel = allSelected
        ? l.allSpacesTitle
        : chosen == null
        ? chosenLocal == null || chosenLocal.name.isEmpty
              ? l.organizerPersonal
              : chosenLocal.name
        : selectedScope == null || selectedScope.revoked
        ? l.sharingAccessRevoked
        : selectedScope.name;
    final chosenIcon = allSelected
        ? Icons.dashboard_outlined
        : chosen == null
        ? switch (chosenLocal?.kind) {
            LocalSpaceKind.household => Icons.home_outlined,
            LocalSpaceKind.organization => Icons.business_outlined,
            _ => Icons.person_outline,
          }
        : selectedScope == null || selectedScope.revoked
        ? Icons.lock_outline
        : scopeIcon(selectedScope);
    final pickerHeight = (MediaQuery.textScalerOf(context).scale(16) + 24)
        .clamp(48.0, double.infinity);
    final picker = Tooltip(
      message: '${l.spacePickerTitle}: $chosenLabel',
      child: SizedBox(
        height: pickerHeight,
        child: Theme(
          // DropdownButton captures this theme for its route. Keep native touch
          // and keyboard focus visible without the default grey selection band.
          data: theme.copyWith(
            focusColor: colors.primary.withValues(alpha: .06),
          ),
          child: DropdownButton<String>(
            key: ValueKey('active-space-${state?.session?.partition}-$chosen'),
            value: selectedValue,
            isExpanded: true,
            menuWidth: (MediaQuery.sizeOf(context).width - 32).clamp(0, 380),
            menuMaxHeight: (MediaQuery.sizeOf(context).height * .6).clamp(
              0,
              480,
            ),
            itemHeight: null,
            borderRadius: BorderRadius.circular(20),
            dropdownColor: colors.surface,
            elevation: 8,
            selectedItemBuilder: (context) => [
              for (final _ in items)
                // With itemHeight null, DropdownButton wraps selected children
                // in a shrink-wrapped Column. Give the closed content its full
                // height so both the label and suffix center in the tap target.
                SizedBox(
                  height: pickerHeight,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: compact
                        ? Row(
                            children: [
                              Icon(chosenIcon, size: 20, color: colors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  chosenLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            chosenLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
            ],
            style: compact
                ? theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  )
                : theme.textTheme.titleMedium,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 10)
                : null,
            underline: const SizedBox.shrink(),
            icon: Icon(
              Icons.expand_more,
              size: compact ? 20 : 24,
              color: colors.onSurfaceVariant,
            ),
            items: items,
            onChanged: (id) {
              if (id == allAction) {
                if (onAllSelected != null) {
                  onAllSelected!();
                } else {
                  ref.read(collaborationProvider.notifier).selectAllSpaces();
                }
              } else if (id == createAction) {
                _create(context, ref);
              } else if (id?.startsWith('local:') == true) {
                _selectLocal(ref, id!.substring(6));
              } else {
                onSelected(id);
              }
            },
          ),
        ),
      ),
    );
    return compact
        ? Material(
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: picker,
          )
        : InputDecorator(
            decoration: InputDecoration(labelText: l.spacePickerTitle),
            child: picker,
          );
  }
}

class _SpacePickerMenuRow extends StatelessWidget {
  const _SpacePickerMenuRow({
    required this.title,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.separated,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final bool separated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = !enabled
        ? theme.disabledColor
        : selected || separated
        ? colors.primary
        : colors.onSurface;
    return Semantics(
      selected: selected,
      enabled: enabled,
      child: Tooltip(
        message: subtitle == null ? title : '$title\n$subtitle',
        excludeFromSemantics: true,
        child: Container(
          margin: EdgeInsets.only(top: separated ? 8 : 2, bottom: 2),
          padding: EdgeInsets.only(top: separated ? 8 : 0),
          decoration: separated
              ? BoxDecoration(
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                )
              : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? colors.primaryContainer : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: !enabled
                      ? theme.disabledColor
                      : selected || separated
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: enabled
                                ? colors.onSurfaceVariant
                                : theme.disabledColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.check, size: 20, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
