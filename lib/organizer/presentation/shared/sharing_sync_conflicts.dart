import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../finance/shared_finance_conflicts.dart';
import 'sharing_conflicts.dart';
import 'sharing_session_boundary.dart';

/// The cloud reports both conflict contracts. Route to the matching editor.
Future<void> showSharingSyncConflicts(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(collaborationProvider).valueOrNull;
  if (current == null || current.session == null) return;
  final guard = SharingSessionGuard(context, ref);
  final financeIds = current.financeConflicts.map((c) => c.scopeId).toSet();
  if (financeIds.isEmpty) {
    await showSharingConflicts(context, ref);
    return;
  }
  if (current.conflicts.isEmpty && financeIds.length == 1) {
    await showFinanceConflicts(context, ref, financeIds.single);
    return;
  }
  final chosen = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SharingSessionBoundary(
      guard: guard,
      child: Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(collaborationProvider).valueOrNull;
          final ids =
              state?.financeConflicts.map((c) => c.scopeId).toSet() ?? {};
          return AlertDialog(
            title: Text(context.l10n.sharingConflicts),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state?.conflicts.isNotEmpty == true)
                      TextButton(
                        key: const ValueKey('sync-general-conflicts'),
                        onPressed: () => Navigator.pop(context, 'general'),
                        child: Text(context.l10n.sharingConflictsButton),
                      ),
                    for (final scopeId in ids)
                      TextButton(
                        key: ValueKey('sync-finance-conflicts-$scopeId'),
                        onPressed: () => Navigator.pop(context, scopeId),
                        child: Text(
                          '${context.l10n.financeConflicts} · ${state?.scopes.where((s) => s.id == scopeId && !s.revoked).firstOrNull?.name ?? context.l10n.financeNoAccess}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.close),
              ),
            ],
          );
        },
      ),
    ),
  );
  if (chosen == null || !context.mounted || !guard.isCurrent) return;
  if (chosen == 'general') {
    await showSharingConflicts(context, ref);
  } else {
    await showFinanceConflicts(context, ref, chosen);
  }
}
