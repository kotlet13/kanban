import '../../data/collaboration_repository.dart' show newSharedId;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_forms.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';

class OrganizerSpacePicker extends ConsumerWidget {
  const OrganizerSpacePicker({
    super.key,
    required this.onSelected,
    required this.onConnect,
    this.compact = false,
    this.onAllSelected,
  });
  final ValueChanged<String?> onSelected;
  final VoidCallback onConnect;
  final bool compact;
  final VoidCallback? onAllSelected;
  static const allAction = 'all-spaces';
  static const createAction = 'create-space';
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = context.l10n, guard = SharingSessionGuard(context, ref);
    final state = ref.read(collaborationProvider).valueOrNull;
    if (state?.session == null ||
        state!.sessionInvalid ||
        !state.session!.expiresAt.isAfter(DateTime.now())) {
      onConnect();
      return;
    }
    String? id, submittedName, submittedKind;
    bool currentSessionUsable() {
      final current = ref.read(collaborationProvider).valueOrNull;
      return guard.isCurrent &&
          current != null &&
          !current.sessionInvalid &&
          current.session?.expiresAt.isAfter(DateTime.now()) == true;
    }

    final createId = newSharedId(), requestId = newSharedId();
    await showSharingForm(
      context,
      title: l.spacePickerNewSpace,
      description: l.spacePickerInitialVisibility,
      fields: [
        SharingField(id: 'name', label: l.sharingSpaceName),
        SharingField(
          id: 'kind',
          label: l.sharingScopeType,
          initialValue: 'household',
          options: {
            'household': l.sharingHousehold,
            'project': l.spacePickerSharedProject,
            if (state.organizationsSupported)
              'organization': l.organizationTitle,
          },
        ),
      ],
      submitLabel: l.sharingCreateSpace,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: (form) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: (current) =>
            !current.sessionInvalid &&
            current.session?.expiresAt.isAfter(DateTime.now()) == true,
        child: form,
      ),
      onSubmit: (values) async {
        if (!currentSessionUsable()) {
          throw const CollaborationException('auth_required');
        }
        id = await guard.controller.createScope(
          submittedName ??= values['name']!.trim(),
          kind: SharedScopeKind.values.byName(
            submittedKind ??= values['kind']!,
          ),
          id: createId,
          requestId: requestId,
        );
      },
    );
    if (context.mounted && currentSessionUsable() && id != null) {
      onSelected(id);
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
    final chosen = state?.selectedSpaceId;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final allSelected = state?.allSpacesSelected == true;
    final selectedValue = allSelected ? allAction : chosen ?? '';
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
      menuItem(
        value: '',
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
        ? l.organizerPersonal
        : selectedScope == null || selectedScope.revoked
        ? l.sharingAccessRevoked
        : selectedScope.name;
    final picker = Tooltip(
      message: '${l.spacePickerTitle}: $chosenLabel',
      child: SizedBox(
        height: (MediaQuery.textScalerOf(context).scale(16) + 24).clamp(
          48,
          double.infinity,
        ),
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
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    chosenLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            style: Theme.of(context).textTheme.titleMedium,
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.expand_more),
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
              } else {
                onSelected(id == '' ? null : id);
              }
            },
          ),
        ),
      ),
    );
    return compact
        ? picker
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
