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
  });
  final ValueChanged<String?> onSelected;
  final VoidCallback onConnect;
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = context.l10n, guard = SharingSessionGuard(context, ref);
    String? id, submittedName;
    final createId = newSharedId(), requestId = newSharedId();
    await showSharingForm(
      context,
      title: l.organizationCreate,
      fields: [SharingField(id: 'name', label: l.sharingSpaceName)],
      submitLabel: l.organizationCreate,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
      onSubmit: (values) async {
        id = await guard.controller.createScope(
          submittedName ??= values['name']!.trim(),
          kind: SharedScopeKind.organization,
          id: createId,
          requestId: requestId,
        );
      },
    );
    if (context.mounted && guard.isCurrent && id != null) {
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
      DropdownMenuItem(value: '', child: Text(l.organizerPersonal)),
      for (final scope in scopes.where((scope) => !scope.archived))
        DropdownMenuItem(
          value: scope.id,
          enabled: !scope.revoked,
          child: Text(
            scope.revoked
                ? '${scope.name} · ${l.sharingAccessRevoked}'
                : scope.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (scopes.any((scope) => scope.archived))
        DropdownMenuItem(
          value: 'archived-section',
          enabled: false,
          child: Text(l.scopeArchivedProjects),
        ),
      for (final scope in scopes.where((scope) => scope.archived))
        DropdownMenuItem(
          value: scope.id,
          enabled: !scope.revoked,
          child: Text(scope.name, overflow: TextOverflow.ellipsis),
        ),
      if (chosen != null && !scopes.any((scope) => scope.id == chosen))
        DropdownMenuItem(
          value: chosen,
          enabled: false,
          child: Text(l.sharingAccessRevoked),
        ),
    ];
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('active-space-${state?.session?.partition}-$chosen'),
            initialValue: chosen ?? '',
            isExpanded: true,
            decoration: InputDecoration(labelText: l.spacePickerTitle),
            items: items,
            onChanged: (id) => onSelected(id == '' ? null : id),
          ),
        ),
        const SizedBox(width: 8),
        if (state?.organizationsSupported == true && !state!.sessionInvalid)
          IconButton(
            onPressed: () => _create(context, ref),
            tooltip: l.organizationCreate,
            icon: const Icon(Icons.add_business_outlined),
          )
        else if (state?.session == null)
          IconButton(
            onPressed: onConnect,
            tooltip: l.sharingConnect,
            icon: const Icon(Icons.link),
          ),
      ],
    );
  }
}
