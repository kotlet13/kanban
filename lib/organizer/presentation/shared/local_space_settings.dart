import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/local_spaces_provider.dart';
import '../organizer_widgets.dart';
import 'sharing_forms.dart';
import 'sharing_errors.dart';

class LocalSpaceSettings extends ConsumerWidget {
  const LocalSpaceSettings({
    super.key,
    required this.space,
    required this.onConnect,
  });
  final LocalSpace space;
  final VoidCallback onConnect;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    await showSharingForm(
      context,
      title: l.localSpaceRename,
      description: l.localSpaceDescription,
      fields: [
        SharingField(
          id: 'name',
          label: l.sharingSpaceName,
          initialValue: space.name.isEmpty ? l.organizerPersonal : space.name,
        ),
        SharingField(
          id: 'address',
          label: l.localSpaceAddress,
          initialValue: space.address,
          required: false,
        ),
      ],
      submitLabel: l.save,
      errorMessage: (error) => sharingErrorMessage(context, error),
      onSubmit: (values) => ref
          .read(localSpacesProvider.notifier)
          .renameSpace(
            space.id,
            name: values['name']!.trim(),
            address: values['address'] ?? '',
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(title: l.spaceSettingsTitle),
        ListTile(
          key: ValueKey('local-space-settings-${space.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(space.name.isEmpty ? l.organizerPersonal : space.name),
          subtitle: Text(
            [
              switch (space.kind) {
                LocalSpaceKind.personal => l.organizerPersonal,
                LocalSpaceKind.household => l.sharingHousehold,
                LocalSpaceKind.organization => l.organizationTitle,
              },
              l.localSpaceState,
              if (space.address.isNotEmpty) space.address,
            ].join(' · '),
          ),
          trailing: IconButton(
            onPressed: () => _edit(context, ref),
            tooltip: l.localSpaceRename,
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Text(l.localSpaceDescription),
        const SizedBox(height: 16),
        Text(l.localSpaceMembersDescription),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.cloud_outlined),
            label: Text(l.localSpaceLinkAction),
          ),
        ),
      ],
    );
  }
}
