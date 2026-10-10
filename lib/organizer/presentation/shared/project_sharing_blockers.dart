import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';

String projectSharingBlockerMessage(BuildContext context, String code) {
  final l = context.l10n;
  return switch (code) {
    'project_scope_requires_single_root' => l.sharingBlockSingleRoot,
    'project_record_upgrade_required' => l.sharingBlockRecordUpgrade,
    'project_scope_unrelated_content' => l.sharingBlockUnrelatedContent,
    'project_finance_account_shared' => l.sharingBlockAccount,
    'project_person_shared' => l.sharingBlockPerson,
    'project_recurrence_shared' => l.sharingBlockRecurrence,
    'project_transfer_cross_scope' => l.sharingBlockTransfer,
    'project_linked_payment_dependency' => l.sharingBlockLinkedPayment,
    'project_scope_id_collision' => l.sharingBlockCollision,
    _ => l.sharingProjectSharingBlocked,
  };
}
