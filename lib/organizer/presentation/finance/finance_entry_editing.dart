import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/organizer_models.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../personal_workspace_boundary.dart';
import 'finance_access_guard.dart';
import 'finance_plan_forms.dart';

Future<void> editRecordedPersonalOccurrence(
  BuildContext context,
  WidgetRef ref,
  OrganizerSnapshot snapshot,
  FinanceEntry entry,
) {
  final guard = PersonalWorkspaceGuard(context, ref, snapshot.workspaceKey);
  final state = ref.read(collaborationProvider).valueOrNull;
  final private =
      snapshot.workspaceKey != 'local' &&
      state?.privateRecordIds.values.contains(entry.id) == true;
  final financial = private
      ? FinanceAccessGuard(
          context,
          ref,
          state!.privateSync.scopeId!,
          write: true,
        )
      : null;
  return showRecordedFinanceOccurrenceEditor(
    context,
    entry: entry,
    wrap: (child) => guard.wrap(financial?.wrap(child) ?? child),
    onSave: (updated) async {
      if (!guard.isCurrent || financial?.isCurrent == false) {
        throw const CollaborationException('finance_forbidden');
      }
      await ref.read(organizerProvider.notifier).updateFinanceEntry(updated);
      if (!guard.isCurrent || financial?.isCurrent == false) {
        throw const CollaborationException('session_changed');
      }
    },
  );
}

bool canConfirmPersonalFinanceEntry(
  BuildContext context,
  WidgetRef ref,
  OrganizerSnapshot snapshot,
  FinanceEntry entry,
) {
  if (!PersonalWorkspaceGuard(context, ref, snapshot.workspaceKey).isCurrent) {
    return false;
  }
  final state = ref.read(collaborationProvider).valueOrNull;
  final private =
      snapshot.workspaceKey != 'local' &&
      state?.privateRecordIds.values.contains(entry.id) == true;
  return !private ||
      state?.financeContractVersion == 2 &&
          FinanceAccessGuard(
            context,
            ref,
            state?.privateSync.scopeId ?? '',
            write: true,
          ).isCurrent;
}

Future<void> confirmPersonalFinanceEntry(
  BuildContext context,
  WidgetRef ref,
  OrganizerSnapshot snapshot,
  FinanceEntry entry,
) async {
  final guard = PersonalWorkspaceGuard(context, ref, snapshot.workspaceKey);
  final state = ref.read(collaborationProvider).valueOrNull;
  final private =
      snapshot.workspaceKey != 'local' &&
      state?.privateRecordIds.values.contains(entry.id) == true;
  final financial = private
      ? FinanceAccessGuard(
          context,
          ref,
          state?.privateSync.scopeId ?? '',
          write: true,
        )
      : null;
  bool isCurrent() => guard.isCurrent && (financial?.isCurrent ?? true);
  if (!canConfirmPersonalFinanceEntry(context, ref, snapshot, entry)) return;
  await showFinanceOccurrenceConfirmation(
    context,
    entry: entry,
    initialPaidAt: ref.read(organizerClockProvider)(),
    sourceWorkspaceKey: snapshot.workspaceKey,
    wrap: (child) => guard.wrap(financial?.wrap(child) ?? child),
    isCurrent: isCurrent,
    onConfirm: (amount, date) async {
      if (!isCurrent()) {
        throw const CollaborationException('finance_forbidden');
      }
      await ref
          .read(organizerProvider.notifier)
          .confirmFinanceOccurrence(
            entry: entry,
            amountMinor: amount,
            paidAt: date,
            expectedWorkspaceKey: snapshot.workspaceKey,
          );
      if (!isCurrent()) {
        throw const CollaborationException('session_changed');
      }
    },
  );
}
