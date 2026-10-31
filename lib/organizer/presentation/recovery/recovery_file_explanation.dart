import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

enum RecoveryFileScope { installation, account, combined }

/// Describes the actual file being exported, without changing the recovery flow.
class RecoveryFileExplanation extends StatelessWidget {
  const RecoveryFileExplanation({super.key, required this.scope});

  final RecoveryFileScope scope;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          scope == RecoveryFileScope.installation
              ? l.recoveryReviewLocalBrief
              : l.recoveryReviewAccountBrief,
        ),
        TextButton(
          key: const ValueKey('recovery-file-explanation'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l.recoveryReviewDetailsTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(switch (scope) {
                      RecoveryFileScope.installation =>
                        l.recoveryInstallationExplanation,
                      RecoveryFileScope.account => l.accountRecoveryExplanation,
                      RecoveryFileScope.combined =>
                        l.recoveryCombinedExplanation,
                    }),
                    const SizedBox(height: 16),
                    Text(l.recoveryReviewBackupExplanation),
                    const SizedBox(height: 16),
                    Text(l.recoveryFileWarning),
                    if (scope == RecoveryFileScope.installation) ...[
                      const SizedBox(height: 16),
                      Text(l.recoveryLocalProtectionOnly),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.close),
                ),
              ],
            ),
          ),
          child: Text(l.recoveryReviewReadMore),
        ),
      ],
    );
  }
}
