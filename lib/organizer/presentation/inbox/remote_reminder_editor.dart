import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';
import 'inbox_preferences.dart';

/// Remote schedules belong to the signed-in account, not to all assignees.
/// This component does not enable any delivery channel or schedule locally.
class RemoteReminderButton extends ConsumerWidget {
  const RemoteReminderButton({
    super.key,
    required this.scopeId,
    required this.targetType,
    required this.targetId,
  });
  final String scopeId, targetType, targetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    if (state == null ||
        !remoteReminderTargetAvailable(state, scopeId, targetType, targetId)) {
      return const SizedBox.shrink();
    }
    final reminders = _reminders(state, scopeId, targetType, targetId);
    final active = reminders.any((r) => r.state == 'pending');
    final canSchedule =
        state.scopes.where((s) => s.id == scopeId).firstOrNull?.canEdit == true;
    if (!canSchedule && !active) return const SizedBox.shrink();
    return IconButton(
      key: ValueKey('remote-reminder-$scopeId-$targetType-$targetId'),
      tooltip: !canSchedule
          ? context.l10n.remoteReminderCancel
          : active
          ? context.l10n.remoteReminderEdit
          : context.l10n.remoteReminderAdd,
      icon: Icon(
        active ? Icons.notifications_active_outlined : Icons.add_alert_outlined,
        size: 20,
      ),
      onPressed: () {
        final guard = SharingSessionGuard(context, ref);
        final selectedSpaceId = state.selectedSpaceId;
        final financePolicyRevision = targetType == 'financeEntry'
            ? state.financePolicyForScope(scopeId).revision
            : null;
        showDialog<void>(
          context: context,
          builder: (_) => SharingSessionBoundary(
            guard: guard,
            visibleWhen: (current) =>
                current.selectedSpaceId == selectedSpaceId &&
                (financePolicyRevision == null ||
                    current.financePolicyForScope(scopeId).revision ==
                        financePolicyRevision) &&
                remoteReminderTargetAvailable(
                  current,
                  scopeId,
                  targetType,
                  targetId,
                ),
            child: _RemoteReminderDialog(
              scopeId: scopeId,
              targetType: targetType,
              targetId: targetId,
              guard: guard,
              selectedSpaceId: selectedSpaceId,
              financePolicyRevision: financePolicyRevision,
            ),
          ),
        );
      },
    );
  }
}

bool remoteReminderTargetAvailable(
  CollaborationState state,
  String scopeId,
  String type,
  String id,
) {
  final scope = state.scopes.where((s) => s.id == scopeId).firstOrNull;
  if (state.session == null ||
      state.sessionInvalid ||
      state.deletionPending ||
      !state.inboxSupported ||
      !state.session!.expiresAt.isAfter(DateTime.now()) ||
      scope == null ||
      scope.revoked ||
      scope.kind == SharedScopeKind.personal) {
    return false;
  }
  final data = state.dataForScope(scopeId);
  return switch (type) {
    'task' => data.tasks.any((t) => t.id == id && !t.isCompleted),
    'event' => data.events.any((e) => e.id == id),
    'financeEntry' =>
      state.financePolicyForScope(scopeId).canRead &&
          state.financeSnapshotComplete[scopeId] == true &&
          data.financeEntries.any(
            (e) => e.id == id && e.status == SharedFinanceStatus.planned,
          ),
    _ => false,
  };
}

List<SharedScheduledReminder> _reminders(
  CollaborationState state,
  String scopeId,
  String type,
  String id,
) =>
    state.scheduledReminders
        .where(
          (r) =>
              r.scopeId == scopeId && r.targetType == type && r.targetId == id,
        )
        .toList()
      ..sort((a, b) => b.remindAt.compareTo(a.remindAt));

class _RemoteReminderDialog extends ConsumerStatefulWidget {
  const _RemoteReminderDialog({
    required this.scopeId,
    required this.targetType,
    required this.targetId,
    required this.guard,
    required this.selectedSpaceId,
    required this.financePolicyRevision,
  });
  final String scopeId, targetType, targetId;
  final SharingSessionGuard guard;
  final String? selectedSpaceId;
  final int? financePolicyRevision;
  @override
  ConsumerState<_RemoteReminderDialog> createState() =>
      _RemoteReminderDialogState();
}

class _RemoteReminderDialogState extends ConsumerState<_RemoteReminderDialog> {
  SharedScheduledReminder? _editing;
  late DateTime _at;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final state = ref.read(collaborationProvider).requireValue;
    final reminders = _reminders(
      state,
      widget.scopeId,
      widget.targetType,
      widget.targetId,
    );
    _editing =
        reminders.where((r) => r.state == 'pending').firstOrNull ??
        reminders.firstOrNull;
    _at =
        (_editing?.remindAt ??
                ref
                    .read(collaborationClockProvider)()
                    .add(const Duration(hours: 1)))
            .toLocal();
  }

  bool get _current {
    final state = ref.read(collaborationProvider).valueOrNull;
    return widget.guard.isCurrent &&
        state != null &&
        state.selectedSpaceId == widget.selectedSpaceId &&
        (widget.financePolicyRevision == null ||
            state.financePolicyForScope(widget.scopeId).revision ==
                widget.financePolicyRevision) &&
        remoteReminderTargetAvailable(
          state,
          widget.scopeId,
          widget.targetType,
          widget.targetId,
        );
  }

  Future<void> _chooseDate() async {
    final now = ref.read(collaborationClockProvider)().toLocal();
    final first = DateUtils.dateOnly(now);
    final last = DateTime(now.year + 10, 12, 31);
    final selected = DateUtils.dateOnly(_at);
    final initial = selected.isBefore(first)
        ? first
        : selected.isAfter(last)
        ? last
        : selected;
    final chosen = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: (context, child) => SharingSessionBoundary(
        guard: widget.guard,
        visibleWhen: (_) => _current,
        closingChild: const SizedBox.shrink(),
        child: child!,
      ),
    );
    if (chosen != null && mounted && _current) {
      setState(() {
        _at = DateTime(
          chosen.year,
          chosen.month,
          chosen.day,
          _at.hour,
          _at.minute,
        );
        _error = null;
      });
    }
  }

  Future<void> _chooseTime() async {
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      builder: (context, child) => SharingSessionBoundary(
        guard: widget.guard,
        visibleWhen: (_) => _current,
        closingChild: const SizedBox.shrink(),
        child: child!,
      ),
    );
    if (chosen != null && mounted && _current) {
      setState(() {
        _at = DateTime(
          _at.year,
          _at.month,
          _at.day,
          chosen.hour,
          chosen.minute,
        );
        _error = null;
      });
    }
  }

  Future<void> _submit({bool cancel = false}) async {
    if (!_current || _busy) return;
    if (!cancel &&
        ref
                .read(collaborationProvider)
                .valueOrNull
                ?.scopes
                .where((s) => s.id == widget.scopeId)
                .firstOrNull
                ?.canEdit !=
            true) {
      return;
    }
    if (!cancel && !_at.isAfter(ref.read(collaborationClockProvider)())) {
      setState(() => _error = context.l10n.remoteReminderFuture);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = widget.guard.controller;
      final partition = widget.guard.session!.partition;
      if (cancel) {
        await controller.cancelReminder(
          _editing!,
          expectedPartition: partition,
        );
      } else {
        await controller.putReminder(
          id: _editing?.id,
          scopeId: widget.scopeId,
          targetType: widget.targetType,
          targetId: widget.targetId,
          remindAt: _at.toUtc(),
          expectedRevision: _editing?.revision ?? 0,
          expectedPartition: partition,
        );
      }
      if (!mounted || !_current) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cancel
                ? context.l10n.remoteReminderCancelQueued
                : context.l10n.remoteReminderSaved,
          ),
        ),
      );
    } catch (error) {
      if (mounted && _current) {
        setState(() {
          _error =
              error is CollaborationException &&
                  error.code == 'reminder_target_unavailable'
              ? context.l10n.remoteReminderUnavailable
              : sharingErrorMessage(context, error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _status(SharedScheduledReminder reminder) {
    final l = context.l10n;
    if (reminder.syncState == 'queued') return l.remoteReminderQueued;
    if (reminder.syncState == 'blocked') return l.remoteReminderBlocked;
    return switch (reminder.state) {
      'delivered' => l.remoteReminderDelivered,
      'cancelled' => l.remoteReminderCancelled,
      _ => l.remoteReminderScheduled,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(collaborationProvider).valueOrNull;
    final reminders = state == null
        ? <SharedScheduledReminder>[]
        : _reminders(state, widget.scopeId, widget.targetType, widget.targetId);
    final currentReminder = reminders
        .where((r) => r.id == _editing?.id)
        .firstOrNull;
    final canSchedule =
        state?.scopes
            .where((s) => s.id == widget.scopeId)
            .firstOrNull
            ?.canEdit ==
        true;
    return AlertDialog(
      title: Text(l.remoteReminderTitle),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(switch (widget.targetType) {
                  'task' =>
                    state
                            .dataForScope(widget.scopeId)
                            .tasks
                            .where((t) => t.id == widget.targetId)
                            .firstOrNull
                            ?.title ??
                        '',
                  'event' =>
                    state
                            .dataForScope(widget.scopeId)
                            .events
                            .where((e) => e.id == widget.targetId)
                            .firstOrNull
                            ?.title ??
                        '',
                  'financeEntry' =>
                    state
                            .dataForScope(widget.scopeId)
                            .financeEntries
                            .where((e) => e.id == widget.targetId)
                            .firstOrNull
                            ?.title ??
                        '',
                  _ => '',
                }, style: Theme.of(context).textTheme.titleMedium),
              ),
            Text(l.remoteReminderDescription),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => showInboxPreferences(
                      context,
                      ref,
                      initialScopeId: widget.scopeId,
                    ),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(l.inboxSettings),
            ),
            if (reminders.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('remote-reminder-choice-${_editing?.id}'),
                initialValue: currentReminder?.id ?? '',
                isExpanded: true,
                decoration: InputDecoration(labelText: l.remoteReminderTitle),
                items: [
                  DropdownMenuItem(value: '', child: Text(l.remoteReminderAdd)),
                  for (final reminder in reminders)
                    DropdownMenuItem(
                      value: reminder.id,
                      child: Text(
                        '${organizerDate(context, reminder.remindAt)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(reminder.remindAt.toLocal()))}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) => setState(() {
                        _editing = reminders
                            .where((r) => r.id == id)
                            .firstOrNull;
                        _at =
                            (_editing?.remindAt ??
                                    ref
                                        .read(collaborationClockProvider)()
                                        .add(const Duration(hours: 1)))
                                .toLocal();
                        _error = null;
                      }),
              ),
              if (currentReminder != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_status(currentReminder)),
                ),
            ],
            OutlinedButton.icon(
              key: const ValueKey('remote-reminder-date'),
              onPressed: _busy || !canSchedule ? null : _chooseDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(
                '${l.remoteReminderDate}: ${MaterialLocalizations.of(context).formatMediumDate(_at)}',
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('remote-reminder-time'),
              onPressed: _busy || !canSchedule ? null : _chooseTime,
              icon: const Icon(Icons.schedule_outlined, size: 18),
              label: Text(
                '${l.remoteReminderTime}: ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_at))}',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (_editing != null && currentReminder?.state == 'pending')
          TextButton(
            onPressed: _busy ? null : () => _submit(cancel: true),
            child: Text(l.remoteReminderCancel),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.close),
        ),
        FilledButton(
          onPressed: _busy || !canSchedule ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.save),
        ),
      ],
    );
  }
}
