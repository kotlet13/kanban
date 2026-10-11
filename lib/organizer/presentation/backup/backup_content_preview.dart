import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/private_sync_models.dart';
import 'backup_counts.dart';

class BackupContentPreview extends StatelessWidget {
  const BackupContentPreview({super.key, required this.preview});
  final BackupPreview preview;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, summary = preview.contentSummary;
    Widget group(String key, String title, Map<String, int> counts) => Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (counts.values.any((n) => n > 0))
            BackupCounts(
              counts: {
                for (final entry in counts.entries)
                  if (entry.value > 0) entry.key: entry.value,
              },
            )
          else
            Text('${l.backupNoRecords}: 0'),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.backupCountsExplanation),
        group(
          'backup-personal-content',
          l.backupPersonalContent,
          preview.personalCounts,
        ),
        if (summary != null) ...[
          if (summary.localSpaceCount > 0)
            group(
              'backup-local-content',
              '${l.backupLocalSpaces}: ${summary.localSpaceCount}',
              summary.localCounts,
            ),
          if (summary.retainedLocalSpaceCount > 0) ...[
            group(
              'backup-retained-local-content',
              '${l.backupRetainedLocalSpaces}: ${summary.retainedLocalSpaceCount}',
              summary.retainedLocalCounts,
            ),
            Text(l.backupRetainedLocalExplanation),
          ],
          if (preview.scopeCount > 0) ...[
            Text('${l.backupScopes}: ${preview.scopeCount}'),
            Text('${l.backupPrivateSpaces}: ${summary.personalScopeCount}'),
            Text(
              '${l.backupSharedSpaces}: ${preview.scopeCount - summary.personalScopeCount}',
            ),
            group(
              'backup-downloaded-content',
              l.backupDownloadedContent,
              summary.downloadedCounts,
            ),
          ],
          if (summary.linkedPaymentCounts.values.any((n) => n > 0)) ...[
            group('backup-payment-content', l.backupLinkedPaymentContent, {
              'paymentEvents': summary.linkedPaymentCounts['events'] ?? 0,
              'paymentProjections':
                  summary.linkedPaymentCounts['projections'] ?? 0,
              'paymentCashMovements':
                  summary.linkedPaymentCounts['cashMovements'] ?? 0,
            }),
            Text(l.backupPaymentCountsExplanation),
          ],
          if (summary.standaloneFinanceLimited)
            Text(l.backupStandaloneFinanceLimit),
          if (summary.deletedRecordCount > 0)
            Text('${l.backupDeletedRecords}: ${summary.deletedRecordCount}'),
        ] else
          Text('${l.backupScopes}: ${preview.scopeCount}'),
        Text('${l.backupPending}: ${preview.pendingCount}'),
        if (summary != null) ...[
          if (summary.linkedPendingCount > 0)
            Text('${l.backupPendingPayments}: ${summary.linkedPendingCount}'),
          if (summary.blockedCount > 0)
            Text('${l.backupBlockedOperations}: ${summary.blockedCount}'),
        ],
      ],
    );
  }
}
