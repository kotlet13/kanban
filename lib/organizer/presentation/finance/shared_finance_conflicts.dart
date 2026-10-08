import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_errors.dart';
import 'finance_access_guard.dart';
import 'finance_snapshot_view.dart';
import '../organizer_widgets.dart' show organizerDate;

Future<void> showFinanceConflicts(
  BuildContext context,
  WidgetRef ref,
  String scopeId,
) {
  final guard = FinanceAccessGuard(context, ref, scopeId);
  return showDialog<void>(
    context: context,
    builder: (context) => guard.wrap(
      AlertDialog(
        title: Text(context.l10n.financeConflicts),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(child: _FinanceConflicts(guard: guard)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    ),
  );
}

class _FinanceConflicts extends ConsumerStatefulWidget {
  const _FinanceConflicts({required this.guard});
  final FinanceAccessGuard guard;
  @override
  ConsumerState<_FinanceConflicts> createState() => _FinanceConflictsState();
}

class _FinanceConflictsState extends ConsumerState<_FinanceConflicts> {
  bool _busy = false;
  Future<void> _resolve(SharedFinanceConflict conflict, bool keepLocal) async {
    setState(() => _busy = true);
    try {
      await widget.guard.controller.resolveFinanceConflict(
        conflictId: conflict.id,
        keepLocal: keepLocal,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic>? _existingOccurrence(
    SharedFinanceConflict conflict,
    CollaborationState? state,
  ) {
    if (conflict.reason != 'duplicate_finance_reference' || state == null) {
      return conflict.remotePayload;
    }
    final data = state.dataForScope(conflict.scopeId),
        local = conflict.localPayload;
    final rule = local?['recurrenceRuleId'], key = local?['occurrenceKey'];
    if (rule == null || key == null) return null;
    final shared = data.financeEntries
        .where(
          (e) =>
              e.id != conflict.recordId &&
              e.recurrenceRuleId == rule &&
              e.occurrenceKey == key,
        )
        .firstOrNull;
    if (shared != null) return shared.toJson().cast<String, dynamic>();
    return data.personalFinanceEntries
        .where(
          (e) =>
              e.id != conflict.recordId &&
              e.recurrenceRuleId == rule &&
              e.occurrenceKey == key,
        )
        .firstOrNull
        ?.toJson()
        .cast<String, dynamic>();
  }

  Widget _taskReview(
    SharedFinanceConflict conflict,
    CollaborationState? state,
  ) {
    if (state == null) return const SizedBox.shrink();
    final data = state.dataForScope(conflict.scopeId);
    final taskId =
        conflict.localPayload?['taskId'] ??
        conflict.remotePayload?['taskId'] ??
        data.financeEntries
            .where((e) => e.id == conflict.recordId)
            .firstOrNull
            ?.taskId ??
        data.personalFinanceEntries
            .where((e) => e.id == conflict.recordId)
            .firstOrNull
            ?.taskId;
    if (taskId == null) return const SizedBox.shrink();
    final paired = state.conflicts
        .where(
          (c) =>
              c.scopeId == conflict.scopeId &&
              c.recordType == SharedRecordType.task &&
              c.recordId == taskId,
        )
        .firstOrNull;
    if (paired == null) return const SizedBox.shrink();
    final fresh =
        data.tasks
            .where((t) => t.id == taskId)
            .firstOrNull
            ?.toJson()
            .cast<String, dynamic>() ??
        paired.remotePayload;
    Widget version(String label, Map<String, dynamic>? payload) {
      final date = DateTime.tryParse('${payload?['dueAt'] ?? ''}');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            Text('${payload?['title'] ?? context.l10n.sharingDeletedVersion}'),
            if (payload != null)
              Text(
                date == null
                    ? context.l10n.organizerNoDate
                    : organizerDate(context, date),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.financePairedTaskReview,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        version(context.l10n.sharingLocalVersion, paired.localPayload),
        version(context.l10n.sharingRemoteVersion, fresh),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.sharingConflictDescription),
        for (final conflict
            in state?.financeConflicts.where(
                  (c) => c.scopeId == widget.guard.scopeId,
                ) ??
                <SharedFinanceConflict>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    sharingErrorMessage(
                      context,
                      CollaborationException(conflict.reason),
                    ),
                  ),
                  _taskReview(conflict, state),
                  ExpansionTile(
                    title: Text(l.sharingLocalVersion),
                    children: [
                      FinanceSnapshotView(
                        scopeId: widget.guard.scopeId,
                        value: conflict.localPayload,
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text(l.sharingRemoteVersion),
                    children: [
                      FinanceSnapshotView(
                        scopeId: widget.guard.scopeId,
                        value: _existingOccurrence(conflict, state),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (state
                                  ?.financePolicyForScope(widget.guard.scopeId)
                                  .canWrite ==
                              true &&
                          !conflict.remoteDeleted &&
                          conflict.reason == 'conflict')
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _resolve(conflict, true),
                          child: Text(l.sharingKeepLocal),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _resolve(conflict, false),
                        child: Text(l.sharingKeepRemote),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
