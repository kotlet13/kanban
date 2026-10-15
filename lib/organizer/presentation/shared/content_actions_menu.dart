import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../inbox/remote_reminder_editor.dart';
import 'content_moderation.dart';
import 'sharing_session_boundary.dart';

class ContentMenuAction {
  const ContentMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final bool destructive;
  final VoidCallback? onSelected;
}

/// One accessible overflow entry for a shared record's existing actions.
/// Opening the menu does not load evidence or submit anything to the server.
class SharedContentActionsMenu extends ConsumerStatefulWidget {
  const SharedContentActionsMenu({
    super.key,
    required this.scopeId,
    required this.targetId,
    this.targetType = 'record',
    this.actions = const [],
    this.reminderType,
    this.includeReport = true,
    this.enabled = true,
  });
  final String scopeId, targetId, targetType;
  final List<ContentMenuAction> actions;
  final String? reminderType;
  final bool includeReport, enabled;
  @override
  ConsumerState<SharedContentActionsMenu> createState() =>
      _SharedContentActionsMenuState();
}

class _SharedContentActionsMenuState
    extends ConsumerState<SharedContentActionsMenu> {
  SharingSessionGuard? _openedGuard;
  String? _openedAccess;
  (String, String, String)? _openedTarget;
  List<ContentMenuAction> _openedActions = const [];
  String? _openedReminderType;
  late final _container = ProviderScope.containerOf(context, listen: false);

  String _access(CollaborationState state, SharedScope scope) =>
      '${scope.kind.name}:${scope.role.name}:${scope.accessPolicyVersion}:${scope.accessRevision}:${scope.revoked}:${scope.blocked}:${scope.archived}'
      '${widget.targetType == 'finance' ? ':${state.financePolicyForScope(scope.id).revision}:${state.financePolicyForScope(scope.id).canRead}:${state.financePolicyForScope(scope.id).canWrite}' : ''}';

  bool get _isCurrent {
    if (!mounted ||
        !widget.enabled ||
        _openedGuard?.isCurrent != true ||
        _openedTarget != (widget.scopeId, widget.targetId, widget.targetType)) {
      return false;
    }
    try {
      final current = _container.read(collaborationProvider).valueOrNull;
      final scope = current?.scopes
          .where((s) => s.id == widget.scopeId)
          .firstOrNull;
      return current != null &&
          scope != null &&
          _access(current, scope) == _openedAccess;
    } catch (_) {
      return false;
    }
  }

  void _select(String value) {
    if (!_isCurrent) return;
    if (value == 'report') {
      showContentReport(
        context,
        ref,
        scopeId: widget.scopeId,
        targetType: widget.targetType,
        targetId: widget.targetId,
      );
    } else if (value == 'reminder') {
      showRemoteReminderEditor(
        context,
        ref,
        scopeId: widget.scopeId,
        targetType: _openedReminderType!,
        targetId: widget.targetId,
      );
    } else {
      _openedActions[int.parse(value)].onSelected?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    final reminder = state == null || widget.reminderType == null
        ? null
        : remoteReminderActionLabel(
            context,
            state,
            widget.scopeId,
            widget.reminderType!,
            widget.targetId,
          );
    final scope = state?.scopes
        .where((s) => s.id == widget.scopeId)
        .firstOrNull;
    if (scope?.kind == SharedScopeKind.personal &&
        widget.actions.isEmpty &&
        reminder == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      key: ValueKey(
        'content-actions-${widget.targetType}-${widget.scopeId}-${widget.targetId}',
      ),
      tooltip: context.l10n.moderationMoreActions,
      enabled: widget.enabled,
      icon: const Icon(Icons.more_horiz),
      onSelected: _select,
      itemBuilder: (_) {
        _openedGuard = SharingSessionGuard(context, ref);
        final current = _container.read(collaborationProvider).valueOrNull;
        final scope = current?.scopes
            .where((s) => s.id == widget.scopeId)
            .firstOrNull;
        _openedAccess = current == null || scope == null
            ? null
            : _access(current, scope);
        _openedTarget = (widget.scopeId, widget.targetId, widget.targetType);
        _openedActions = List.unmodifiable(widget.actions);
        _openedReminderType = widget.reminderType;
        return [
          for (var i = 0; i < _openedActions.length; i++)
            PopupMenuItem(
              value: '$i',
              enabled: _openedActions[i].onSelected != null,
              child: _label(
                _openedActions[i].icon,
                _openedActions[i].label,
                destructive: _openedActions[i].destructive,
              ),
            ),
          if (reminder != null)
            PopupMenuItem(
              value: 'reminder',
              child: _label(Icons.notifications_outlined, reminder),
            ),
          if (widget.includeReport && scope?.kind != SharedScopeKind.personal)
            PopupMenuItem(
              key: ValueKey(
                'report-action-${widget.targetType}-${widget.scopeId}-${widget.targetId}',
              ),
              value: 'report',
              child: _label(
                Icons.flag_outlined,
                widget.targetType == 'user'
                    ? context.l10n.moderationReportUser
                    : context.l10n.moderationReportContent,
              ),
            ),
        ];
      },
    );
  }

  Widget _label(IconData icon, String text, {bool destructive = false}) => Row(
    children: [
      Icon(
        icon,
        size: 20,
        color: destructive ? Theme.of(context).colorScheme.error : null,
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          text,
          style: destructive
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : null,
        ),
      ),
    ],
  );
}
