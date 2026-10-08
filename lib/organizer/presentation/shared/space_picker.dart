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
  });
  final ValueChanged<String?> onSelected;
  final VoidCallback onConnect;
  final bool compact;
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
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: '',
        child: Text(
          l.organizerPersonal,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      for (final scope in scopes.where((scope) => !scope.archived))
        DropdownMenuItem(
          value: scope.id,
          enabled: !scope.revoked,
          child: Text(
            scope.revoked
                ? '${scope.name} · ${l.sharingAccessRevoked}'
                : scope.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (scopes.any((scope) => scope.archived))
        DropdownMenuItem(
          value: 'archived-section',
          enabled: false,
          child: Text(
            l.scopeArchivedProjects,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      for (final scope in scopes.where((scope) => scope.archived))
        DropdownMenuItem(
          value: scope.id,
          enabled: !scope.revoked,
          child: Text(scope.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      if (chosen != null && !scopes.any((scope) => scope.id == chosen))
        DropdownMenuItem(
          value: chosen,
          enabled: false,
          child: Text(
            l.sharingAccessRevoked,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      DropdownMenuItem(
        value: createAction,
        child: Text(
          l.spacePickerNewSpace,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];
    final selectedScope = scopes
        .where((scope) => scope.id == chosen)
        .firstOrNull;
    final chosenLabel = chosen == null
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
        child: DropdownButton<String>(
          key: ValueKey('active-space-${state?.session?.partition}-$chosen'),
          value: chosen ?? '',
          isExpanded: true,
          menuWidth: compact ? MediaQuery.sizeOf(context).width - 32 : null,
          itemHeight: (MediaQuery.textScalerOf(context).scale(16) + 24).clamp(
            48,
            double.infinity,
          ),
          style: Theme.of(context).textTheme.titleMedium,
          underline: const SizedBox.shrink(),
          icon: const Icon(Icons.expand_more),
          items: items,
          onChanged: (id) {
            if (id == createAction) {
              _create(context, ref);
            } else {
              onSelected(id == '' ? null : id);
            }
          },
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
