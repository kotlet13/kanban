import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../inbox/notification_target_view.dart';
import '../personal_workspace_boundary.dart';
import 'finance_access_guard.dart';

/// Resolves the source from the currently authorized projection. IDs from one
/// workspace never resolve against a different account or shared scope.
class FinanceSourceLink extends ConsumerStatefulWidget {
  const FinanceSourceLink({
    super.key,
    required this.entryId,
    this.workspaceKey,
    this.scopeId,
    this.partition,
  });
  final String entryId;
  final String? workspaceKey, scopeId, partition;

  @override
  ConsumerState<FinanceSourceLink> createState() => _FinanceSourceLinkState();
}

class _FinanceSourceLinkState extends ConsumerState<FinanceSourceLink> {
  String? _trackedId;
  bool _wasLinked = false;
  String get entryId => widget.entryId;
  String? get workspaceKey => widget.workspaceKey;
  String? get scopeId => widget.scopeId;
  String? get partition => widget.partition;
  @override
  Widget build(BuildContext context) {
    final sourceKey = '$workspaceKey:$partition:$scopeId:$entryId';
    if (_trackedId != sourceKey) {
      _trackedId = sourceKey;
      _wasLinked = false;
    }
    final l = context.l10n;
    final personal = ref.watch(organizerProvider).valueOrNull;
    final shared = ref.watch(collaborationProvider).valueOrNull;
    String? taskId;
    List<LocalTask> tasks;
    List<LocalProject> projects;
    FinanceAccessGuard? financial;
    PersonalWorkspaceGuard? guard;
    if (scopeId != null) {
      if (shared?.session?.partition != partition ||
          shared?.sessionInvalid == true) {
        return const SizedBox.shrink();
      }
      financial = FinanceAccessGuard(context, ref, scopeId!);
      if (!financial.isCurrent) return const SizedBox.shrink();
      final data = shared!.dataForScope(scopeId!);
      final entry = data.financeEntries
          .where((e) => e.id == entryId)
          .firstOrNull;
      if (entry == null) return Text(l.financeSourceUnavailable);
      taskId = entry.taskId;
      tasks = data.tasks;
      projects = data.projects;
    } else {
      if (personal == null || personal.workspaceKey != workspaceKey) {
        return const SizedBox.shrink();
      }
      guard = PersonalWorkspaceGuard(context, ref, workspaceKey!);
      if (!guard.isCurrent) return const SizedBox.shrink();
      final entry = personal.financeEntries
          .where((e) => e.id == entryId)
          .firstOrNull;
      if (entry == null) return Text(l.financeSourceUnavailable);
      final private =
          workspaceKey != 'local' &&
          shared?.privateRecordIds.values.contains(entryId) == true;
      if (private) {
        final privateScope = shared?.privateSync.scopeId;
        if (privateScope == null) return const SizedBox.shrink();
        financial = FinanceAccessGuard(context, ref, privateScope);
        if (!financial.isCurrent) return const SizedBox.shrink();
      }
      taskId = entry.taskId;
      tasks = personal.tasks;
      projects = personal.projects;
    }
    if (taskId == null) {
      return _wasLinked
          ? Text(l.financeSourceUnlinked)
          : const SizedBox.shrink();
    }
    _wasLinked = true;
    final task = tasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return Text(l.financeSourceUnavailable);
    final project = projects.where((p) => p.id == task.projectId).firstOrNull;
    NotificationTarget target;
    if (scopeId != null) {
      target = NotificationTarget(
        serverUrl: shared!.session!.serverUrl,
        serverId: shared.session!.serverId,
        accountId: shared.session!.accountId,
        scopeId: scopeId,
        records: [NotificationRecordTarget(type: 'task', recordId: task.id)],
      );
    } else {
      final remote = shared?.privateRecordIds.entries
          .where((e) => e.value == task.id)
          .firstOrNull
          ?.key;
      target = NotificationTarget(
        serverUrl: remote == null ? null : shared!.session!.serverUrl,
        serverId: remote == null ? null : shared!.session!.serverId,
        accountId: remote == null ? null : shared!.session!.accountId,
        scopeId: remote == null ? null : shared!.privateSync.scopeId,
        records: [
          NotificationRecordTarget(type: 'task', recordId: remote ?? task.id),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          key: ValueKey('finance-source-$entryId'),
          icon: const Icon(Icons.task_alt_outlined),
          label: Text(l.financeSourceTask(task.title)),
          onPressed: () async {
            if (guard?.isCurrent == false || financial?.isCurrent == false) {
              return;
            }
            final currentTaskId = scopeId == null
                ? ref
                      .read(organizerProvider)
                      .valueOrNull
                      ?.financeEntries
                      .where((e) => e.id == entryId)
                      .firstOrNull
                      ?.taskId
                : ref
                      .read(collaborationProvider)
                      .valueOrNull
                      ?.dataForScope(scopeId!)
                      .financeEntries
                      .where((e) => e.id == entryId)
                      .firstOrNull
                      ?.taskId;
            if (currentTaskId != task.id) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.financeSourceUnavailable)),
              );
              return;
            }
            if (!target.isPersonal) {
              await showNotificationTarget(context, ref, target);
            } else {
              // Keep a device-local source dialog pinned even when a login or
              // logout changes the personal projection while it is open.
              await showDialog<void>(
                context: context,
                builder: (dialogContext) => guard!.wrap(
                  AlertDialog(
                    title: Text(l.financeSourceTask(task.title)),
                    content: SizedBox(
                      width: 700,
                      child: SingleChildScrollView(
                        child: NotificationTargetContent(target: target),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(l.close),
                      ),
                    ],
                  ),
                ),
              );
            }
          },
        ),
        if (project != null) Text(l.financeSourceProject(project.title)),
      ],
    );
  }
}
