import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/portable_backup_provider.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_forms.dart';
import '../shared/sharing_session_boundary.dart';

String offlineRecoveryLimitation(BuildContext context, String code) =>
    switch (code) {
      'original_server_operations_audit_and_access_remain_archived' =>
        context.l10n.offlineRecoveryArchive,
      'new_local_copy_does_not_grant_server_access' =>
        context.l10n.offlineRecoveryNoServerAccess,
      'finance_transfers_remain_archived' ||
      'linked_payments_require_reconciliation' =>
        context.l10n.localFinanceRecoveryIncomplete,
      'finance_access_unavailable' =>
        context.l10n.offlineRecoveryFinanceUnavailable,
      'source_copy_may_be_incomplete' => context.l10n.backupIncomplete,
      _ => context.l10n.offlineRecoveryArchive,
    };

Future<void> showOfflineSpacesRecovery(
  BuildContext context,
  WidgetRef ref,
  String backupId,
) async {
  final guard = SharingSessionGuard(context, ref, allowSignedOut: true);
  final controller = ref.read(portableBackupProvider.notifier);
  OfflineSpacesRecoveryPreview? preview;
  String? password;
  await showSharingForm(
    context,
    title: context.l10n.offlineRecoveryAction,
    description: context.l10n.offlineRecoveryIntro,
    fields: [
      SharingField(
        id: 'password',
        label: context.l10n.backupPassword,
        obscure: true,
        sensitive: true,
      ),
    ],
    submitLabel: context.l10n.backupRecoveryReview,
    errorMessage: (error) => sharingErrorMessage(context, error),
    wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
    onSubmit: (values) async {
      final result = await controller.reviewRestoredSpacesAsLocal(
        backupId,
        values['password']!,
      );
      if (guard.isCurrent) {
        preview = result;
        password = values['password'];
      }
    },
  );
  if (!context.mounted ||
      !guard.isCurrent ||
      preview == null ||
      password == null) {
    return;
  }
  final captured = preview!;
  bool acknowledged = false, busy = false;
  String? error;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SharingSessionBoundary(
        guard: guard,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            scrollable: true,
            title: Text(context.l10n.offlineRecoveryAction),
            content: SizedBox(
              width: 600,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${context.l10n.backupSourceAccount}: ${captured.sourceAccount ?? context.l10n.backupLocalOnly}',
                  ),
                  Text(
                    '${context.l10n.backupSourceServer}: ${captured.sourceServer ?? context.l10n.backupLocalOnly}',
                  ),
                  const SizedBox(height: 16),
                  Text(context.l10n.offlineRecoveryIntro),
                  for (final space in captured.spaces)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_copy_outlined),
                      title: Text(space.name),
                      subtitle: Text(
                        context.l10n.localSpaceConnectionCounts(
                          space.recordCount,
                          space.gardenCount,
                        ),
                      ),
                    ),
                  for (final label
                      in captured.limitations
                          .map(
                            (code) => offlineRecoveryLimitation(context, code),
                          )
                          .toSet())
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(label),
                    ),
                  if (captured.blockedScopeIds.isNotEmpty)
                    Text(context.l10n.offlineRecoveryBlocked),
                  if (!captured.canRecover)
                    Text(context.l10n.offlineRecoveryNothingAvailable),
                  CheckboxListTile(
                    key: const ValueKey('offline-recovery-acknowledge'),
                    contentPadding: EdgeInsets.zero,
                    value: acknowledged,
                    onChanged: busy
                        ? null
                        : (value) => setDialogState(
                            () => acknowledged = value == true,
                          ),
                    title: Text(context.l10n.offlineRecoveryAcknowledge),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('offline-recovery-confirm'),
                onPressed: !acknowledged || !captured.canRecover || busy
                    ? null
                    : () async {
                        setDialogState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          if (!guard.isCurrent) return;
                          await controller.recoverRestoredSpacesAsLocal(
                            captured,
                            password: password!,
                          );
                          if (context.mounted && guard.isCurrent) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.l10n.offlineRecoverySuccess,
                                ),
                              ),
                            );
                          }
                        } catch (failure) {
                          if (context.mounted) {
                            setDialogState(
                              () =>
                                  error = sharingErrorMessage(context, failure),
                            );
                          }
                        } finally {
                          if (context.mounted) {
                            setDialogState(() => busy = false);
                          }
                        }
                      },
                child: Text(context.l10n.offlineRecoveryAction),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    password = null;
  }
}
