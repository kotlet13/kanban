import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/local_spaces_provider.dart';
import 'sharing_errors.dart';

/// The user chooses an explicit destination; matching names are never identity.
Future<void> transferToLocalHousehold(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required Future<void> Function(String householdId) transfer,
}) async {
  final state = ref.read(localSpacesProvider).valueOrNull;
  final sourceId = state?.selectedSpaceId;
  final households =
      state?.spaces
          .where((s) => s.kind == LocalSpaceKind.household && s.binding == null)
          .toList() ??
      <LocalSpace>[];
  final chosen = await showDialog<LocalSpace>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.l10n.localSpaceChooseHousehold),
      children: [
        if (households.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.l10n.localSpaceNoHouseholds),
          ),
        for (final household in households)
          SimpleDialogOption(
            key: ValueKey('transfer-household-${household.id}'),
            onPressed: () => Navigator.pop(context, household),
            child: Text(household.name),
          ),
      ],
    ),
  );
  if (chosen == null ||
      !context.mounted ||
      ref.read(localSpacesProvider).valueOrNull?.selectedSpaceId != sourceId) {
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.localSpaceMoveToHousehold),
      content: Text(context.l10n.localSpaceMovePreview(name, chosen.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('confirm-household-transfer'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.localSpaceMoveToHousehold),
        ),
      ],
    ),
  );
  if (confirmed != true ||
      !context.mounted ||
      ref.read(localSpacesProvider).valueOrNull?.selectedSpaceId != sourceId) {
    return;
  }
  try {
    await transfer(chosen.id);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
    }
  }
}
