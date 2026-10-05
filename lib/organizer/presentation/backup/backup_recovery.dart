import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/portable_backup_provider.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';
import '../shared/sharing_forms.dart';

class BackupRecoveryPanel extends ConsumerStatefulWidget {
  const BackupRecoveryPanel({super.key});
  @override
  ConsumerState<BackupRecoveryPanel> createState() =>
      _BackupRecoveryPanelState();
}

class _BackupRecoveryPanelState extends ConsumerState<BackupRecoveryPanel> {
  late Future<List<BackupPreview>> _future = ref
      .read(portableBackupProvider.notifier)
      .listRestoredBackups();
  void _refresh() => setState(() {
    _future = ref.read(portableBackupProvider.notifier).listRestoredBackups();
  });
  Future<void> _review(BackupPreview preview) async {
    final guard = SharingSessionGuard(context, ref, allowSignedOut: true),
        controller = ref.read(portableBackupProvider.notifier);
    final l = context.l10n;
    BackupRecoveryReview? review;
    String? password;
    await showSharingForm(
      context,
      title: l.backupRecoveryReview,
      description: l.backupRemoteQuarantine,
      fields: [
        SharingField(
          id: 'password',
          label: l.backupPassword,
          obscure: true,
          sensitive: true,
        ),
      ],
      submitLabel: l.backupRecoveryReview,
      wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
      errorMessage: (e) => sharingErrorMessage(context, e),
      onSubmit: (values) async {
        guard.controller;
        final next = await controller.reviewRestoredWork(
          preview.backupId,
          values['password']!,
        );
        if (guard.isCurrent) {
          review = next;
          password = values['password'];
        }
      },
    );
    if (!mounted || !guard.isCurrent || review == null) return;
    final capturedReview = review!;
    final financialRevisions = <String, int>{
      for (final item in capturedReview.items.where((item) => item.isFinancial))
        item.scopeId: ref
            .read(collaborationProvider)
            .requireValue
            .financePolicyForScope(item.scopeId)
            .revision,
    };
    bool visible(CollaborationState state) =>
        (!capturedReview.canResume || !state.sessionInvalid) &&
        financialRevisions.entries.every(
          (entry) =>
              state.scopes.any(
                (scope) => scope.id == entry.key && !scope.revoked,
              ) &&
              state.financePolicyForScope(entry.key).canRead &&
              state.financePolicyForScope(entry.key).revision == entry.value,
        );
    bool busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: visible,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(l.backupRecoveryReview),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${l.backupSourceAccount}: ${capturedReview.sourceAccount ?? l.sharingPersonal}',
                    ),
                    Text(
                      '${l.backupSourceServer}: ${capturedReview.sourceServer ?? l.backupLocalOnly}',
                    ),
                    Text(l.backupArchiveReview),
                    Text(l.backupRemoteQuarantine),
                    if (!capturedReview.canResume)
                      Text(l.backupRecoveryBlocked),
                    const SizedBox(height: 16),
                    if (capturedReview.items.isEmpty)
                      Text(l.backupRecoveryBlocked),
                    for (final item in capturedReview.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.title.isEmpty
                              ? _recordLabel(context, item.recordType)
                              : item.title,
                        ),
                        subtitle: Text(
                          '${item.scopeName} · ${_recordLabel(context, item.recordType)}\n${_stateLabel(context, item.state)}',
                        ),
                        isThreeLine: true,
                        leading: Icon(
                          item.isFinancial
                              ? Icons.account_balance_wallet_outlined
                              : Icons.description_outlined,
                        ),
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
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: Text(l.close),
              ),
              if (capturedReview.canResume && guard.session != null)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setDialogState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            guard.controller;
                            final current = ref
                                .read(collaborationProvider)
                                .valueOrNull;
                            if (current == null || !visible(current)) {
                              throw const CollaborationException(
                                'finance_forbidden',
                              );
                            }
                            await controller.resumeRestoredWork(
                              preview.backupId,
                              password: password!,
                            );
                            if (context.mounted && guard.isCurrent) {
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setDialogState(
                                () => error = sharingErrorMessage(context, e),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setDialogState(() => busy = false);
                            }
                          }
                        },
                  child: Text(l.backupRecoveryResume),
                ),
            ],
          ),
        ),
      ),
    );
    password = null;
    if (mounted) _refresh();
  }

  String _recordLabel(BuildContext context, String type) => switch (type) {
    'project' => context.l10n.organizerProjects,
    'task' => context.l10n.organizerTasks,
    'shoppingList' => context.l10n.organizerShopping,
    'shoppingItem' => context.l10n.backupShoppingItems,
    'event' => context.l10n.organizerCalendar,
    'financeAccount' ||
    'financeEntry' ||
    'financeTransfer' ||
    'personalFinanceEntry' => context.l10n.organizerFinances,
    _ => context.l10n.backupOtherRecords,
  };
  String _stateLabel(BuildContext context, String state) => switch (state) {
    'blocked' => context.l10n.backupRecoveryBlocked,
    'conflict' => context.l10n.sharingConflicts,
    'pending' => context.l10n.sharingPending,
    'cached' => context.l10n.backupCached,
    _ => context.l10n.backupRecoveryReady,
  };
  @override
  Widget build(BuildContext context) {
    ref.watch(collaborationProvider);
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.backupRecoveryTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  tooltip: l.organizerRetry,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            FutureBuilder<List<BackupPreview>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(l.backupReadError);
                if (!snapshot.hasData) return const LinearProgressIndicator();
                if (snapshot.data!.isEmpty) return Text(l.backupRecoveryNone);
                return Column(
                  children: [
                    for (final preview in snapshot.data!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(preview.sourceAccount ?? l.backupLocalOnly),
                        subtitle: Text(
                          '${preview.sourceServer ?? l.backupLocalOnly}\n${l.backupPending}: ${preview.pendingCount}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _review(preview),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
