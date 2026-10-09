import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../personal_workspace_boundary.dart';
import '../shared/sharing_session_boundary.dart';
import 'notification_target_view.dart';
import 'local_notification_target.dart';

// A rapid second tap must not stack another detail route or refresh request.
final _openingTasks = Expando<bool>();

/// Opens only tasks already visible under the current identity and local ACL.
/// Notification launches and financial targets use showNotificationTarget.
Future<bool> showVisibleTaskTarget(
  BuildContext context,
  WidgetRef ref,
  NotificationTarget target, {
  bool Function()? isCurrent,
}) async {
  if (!await activateLocalNotificationTarget(context, ref, target) ||
      !context.mounted ||
      isCurrent?.call() == false) {
    return false;
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_openingTasks[navigator] == true ||
      isCurrent?.call() == false ||
      target.records.length != 1 ||
      target.records.single.type != 'task' ||
      target.inboxIds.isNotEmpty ||
      !_taskIsVisible(ref, target)) {
    return false;
  }
  final personal = ref.read(organizerProvider).valueOrNull!;
  final state = ref.read(collaborationProvider).valueOrNull;
  final scope = state?.scopes.where((s) => s.id == target.scopeId).firstOrNull;
  final personalGuard =
      target.isPersonal || scope?.kind == SharedScopeKind.personal
      ? PersonalWorkspaceGuard(context, ref, personal.workspaceKey)
      : null;
  final sessionGuard = target.isPersonal
      ? null
      : SharingSessionGuard(context, ref);
  _openingTasks[navigator] = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (context) {
        Widget dialog = AlertDialog(
          title: Text(scope?.name ?? context.l10n.inboxForMe),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: _VisibleTaskContent(target: target),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.close),
            ),
          ],
        );
        if (sessionGuard != null) {
          dialog = SharingSessionBoundary(
            guard: sessionGuard,
            visibleWhen: (state) => _taskScopeAccessible(state, target),
            child: dialog,
          );
        }
        return personalGuard?.wrap(dialog) ?? dialog;
      },
    );
    return true;
  } finally {
    _openingTasks[navigator] = false;
  }
}

bool _taskScopeAccessible(
  CollaborationState state,
  NotificationTarget target,
) =>
    state.localAccessAllowed &&
    state.session != null &&
    target.matches(state.session!) &&
    state.scopes.any(
      (s) => s.id == target.scopeId && !s.revoked && !s.blocked && !s.archived,
    );

bool _taskIsVisible(WidgetRef ref, NotificationTarget target) {
  final personalState = ref.read(organizerProvider);
  final sharedState = ref.read(collaborationProvider);
  if (personalState.isLoading ||
      personalState.hasError ||
      sharedState.isLoading ||
      sharedState.hasError) {
    return false;
  }
  final personal = personalState.asData?.value;
  final state = sharedState.asData?.value;
  if (personal == null) return false;
  final id = target.records.single.recordId;
  if (target.isPersonal) {
    return (personal.workspaceKey == target.localWorkspaceId ||
            target.localWorkspaceId == 'local' &&
                personal.workspaceKey.startsWith('private:') &&
                state?.localAccessAllowed == true &&
                personal.workspaceKey ==
                    'private:${state?.session?.partition}') &&
        personal.tasks.any((t) => t.id == id);
  }
  if (state == null || !_taskScopeAccessible(state, target)) return false;
  final scope = state.scopes.firstWhere((s) => s.id == target.scopeId);
  if (scope.kind == SharedScopeKind.personal) {
    return personal.workspaceKey == 'private:${state.session!.partition}' &&
        personal.tasks.any((t) => t.id == state.personalRecordId(id));
  }
  return state.dataForScope(scope.id).tasks.any((t) => t.id == id);
}

class _VisibleTaskContent extends ConsumerStatefulWidget {
  const _VisibleTaskContent({required this.target});
  final NotificationTarget target;
  @override
  ConsumerState<_VisibleTaskContent> createState() =>
      _VisibleTaskContentState();
}

class _VisibleTaskContentState extends ConsumerState<_VisibleTaskContent> {
  NotificationOpenStatus? _status;
  @override
  void initState() {
    super.initState();
    if (!widget.target.isPersonal) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final result = await ref
          .read(collaborationProvider.notifier)
          .refreshVisibleTaskTarget(widget.target);
      if (mounted) setState(() => _status = result.status);
    } catch (_) {
      // Identity changes are handled by the enclosing boundaries. An unavailable
      // connection must not delay or discard an already visible local task.
      if (mounted) setState(() => _status = NotificationOpenStatus.offline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final personal = ref.watch(organizerProvider);
    final shared = ref.watch(collaborationProvider);
    if (personal.isLoading || shared.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (personal.hasError || shared.hasError) {
      return Text(context.l10n.inboxNeedsConnection);
    }
    if (_status == NotificationOpenStatus.permissionDenied) {
      return Text(context.l10n.sharingAccessRevoked);
    }
    if (_status == NotificationOpenStatus.deleted ||
        !_taskIsVisible(ref, widget.target)) {
      return Text(context.l10n.inboxDeleted);
    }
    return NotificationTargetContent(
      target: widget.target,
      offline: _status == NotificationOpenStatus.offline,
    );
  }
}
