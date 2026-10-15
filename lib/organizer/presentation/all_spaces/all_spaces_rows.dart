import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/all_spaces_projection.dart';
import '../../domain/organizer_models.dart';
import '../finance/finance_money.dart';
import '../organizer_widgets.dart';
import 'all_spaces_area.dart';
import '../../state/organizer_provider.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/collaboration_provider.dart';
import '../inbox/notification_target_view.dart';
import '../inbox/visible_task_target_view.dart';
import '../personal_workspace_boundary.dart';
import '../organizer_actions.dart';
import '../organizer_errors.dart';
import '../shared/collaboration_actions.dart';

String allSpacesSourceLabel(BuildContext context, AllSpacesSource source) =>
    source.name ?? context.l10n.organizerPersonal;

class AllSpacesRow {
  const AllSpacesRow({
    required this.source,
    required this.id,
    required this.type,
    required this.title,
    this.date,
    this.endDate,
    this.startDate,
    this.notes = '',
    this.completed = false,
    this.amountMinor,
    this.currency,
    this.kind,
    this.posted = false,
    this.children = const [],
  });
  final AllSpacesSource source;
  final String id, type, title, notes;
  final DateTime? date, endDate, startDate;
  final bool completed, posted;
  final int? amountMinor;
  final String? currency;
  final FinanceEntryKind? kind;
  final List<AllSpacesRow> children;
  IconData get icon => switch (type) {
    'task' =>
      completed ? Icons.check_circle_outline : Icons.radio_button_unchecked,
    'event' => Icons.event_outlined,
    'project' => Icons.folder_outlined,
    'shoppingList' => Icons.shopping_bag_outlined,
    'shoppingItem' =>
      completed ? Icons.check_box_outlined : Icons.check_box_outline_blank,
    'person' => Icons.person_outline,
    'financeTransfer' => Icons.swap_horiz,
    _ => Icons.account_balance_wallet_outlined,
  };
}

bool _inMonth(DateTime date, DateTime? month) =>
    month == null ||
    (date.toLocal().year == month.year && date.toLocal().month == month.month);

DateTime _financeDate({
  required bool planned,
  DateTime? plannedAt,
  DateTime? paidAt,
  required DateTime occurredAt,
}) => planned ? plannedAt ?? occurredAt : paidAt ?? occurredAt;

List<AllSpacesRow> allSpacesRows(
  AllSpacesSnapshot snapshot,
  AllSpacesArea area, {
  required DateTime now,
  bool showCompleted = false,
  DateTime? month,
  String? currency,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final tasks = [
    for (final record in snapshot.tasks)
      AllSpacesRow(
        source: record.source,
        id: record.value.id,
        type: 'task',
        title: record.value.title,
        notes: record.value.notes,
        date: record.value.dueAt ?? record.value.startAt,
        completed: record.value.isCompleted,
        startDate: record.value.startAt,
        endDate: record.value.endAt,
      ),
  ];
  final tasksByProject = <String, List<AllSpacesRow>>{};
  final tasksByPerson = <String, List<AllSpacesRow>>{};
  final taskRecords = snapshot.tasks;
  for (var index = 0; index < taskRecords.length; index++) {
    final record = taskRecords[index], row = tasks[index];
    final projectId = record.value.projectId;
    if (projectId != null) {
      (tasksByProject['${record.source.key}:$projectId'] ??= []).add(row);
    }
    for (final personId in {
      if (record.value.assigneePersonId != null) record.value.assigneePersonId!,
      ...record.value.subjectPersonIds,
    }) {
      (tasksByPerson['${record.source.key}:$personId'] ??= []).add(row);
    }
  }
  final itemsByList = <String, List<AllSpacesRow>>{};
  for (final item in snapshot.shoppingItems) {
    (itemsByList['${item.source.key}:${item.value.listId}'] ??= []).add(
      AllSpacesRow(
        source: item.source,
        id: item.value.id,
        type: 'shoppingItem',
        title: item.value.title,
        notes: item.value.quantity,
        completed: item.value.isChecked,
      ),
    );
  }
  final events = [
    for (final record in snapshot.localEvents)
      AllSpacesRow(
        source: record.source,
        id: record.value.id,
        type: 'event',
        title: record.value.title,
        notes: record.value.notes,
        date: record.value.startsAt,
        endDate: record.value.endsAt,
      ),
    for (final record in snapshot.sharedEvents)
      AllSpacesRow(
        source: record.source,
        id: record.value.id,
        type: 'event',
        title: record.value.title,
        notes: record.value.notes,
        date: record.value.startAt,
        endDate: record.value.endAt,
      ),
  ];
  final finances = [
    for (final record in snapshot.localFinanceEntries)
      AllSpacesRow(
        source: record.source,
        id: record.value.id,
        type: 'personalFinanceEntry',
        title: record.value.title,
        notes: record.value.notes,
        date: _financeDate(
          planned: record.value.status.name == 'planned',
          plannedAt: record.value.plannedAt,
          paidAt: record.value.paidAt,
          occurredAt: record.value.occurredAt,
        ),
        amountMinor: record.value.amountMinor,
        currency: record.value.currency,
        kind: record.value.kind,
        posted: record.value.status == FinanceEntryStatus.posted,
      ),
    for (final record in snapshot.sharedFinanceEntries)
      AllSpacesRow(
        source: record.source,
        id: record.value.id,
        type: 'financeEntry',
        title: record.value.title,
        notes: record.value.notes,
        date: _financeDate(
          planned: record.value.status.name == 'planned',
          plannedAt: record.value.plannedAt,
          paidAt: record.value.paidAt,
          occurredAt: record.value.occurredAt,
        ),
        amountMinor: record.value.amountMinor,
        currency: record.value.currency,
        kind: record.value.kind,
        posted: record.value.status.name == 'posted',
      ),
  ];
  final transfers = [
    for (final record in snapshot.financeTransfers)
      AllSpacesRow(
        source: record.source,
        id: record.value.id,
        type: 'financeTransfer',
        title: record.value.title,
        date: record.value.occurredAt,
        amountMinor: record.value.amountMinor,
        currency: record.value.currency,
      ),
  ];
  final rows = switch (area) {
    AllSpacesArea.today => [
      ...tasks.where(
        (row) =>
            !row.completed &&
            (row.date == null ||
                row.date!.toLocal().isBefore(tomorrow) ||
                (row.startDate != null &&
                    row.startDate!.toLocal().isBefore(tomorrow) &&
                    (!row.startDate!.toLocal().isBefore(today) ||
                        row.endDate?.toLocal().isAfter(today) == true))),
      ),
      ...events.where(
        (row) =>
            row.date!.toLocal().isBefore(tomorrow) &&
            (row.endDate != null
                ? row.endDate!.toLocal().isAfter(today)
                : !row.date!.toLocal().isBefore(today)),
      ),
      ...finances.where(
        (row) => !row.posted && row.date!.toLocal().isBefore(tomorrow),
      ),
    ],
    AllSpacesArea.tasks =>
      tasks.where((row) => row.completed == showCompleted).toList(),
    AllSpacesArea.calendar => [
      ...events.where(
        (row) =>
            month == null ||
            row.date!.toLocal().isBefore(
                  DateTime(month.year, month.month + 1),
                ) &&
                (row.endDate != null
                    ? row.endDate!.toLocal().isAfter(
                        DateTime(month.year, month.month),
                      )
                    : !row.date!.toLocal().isBefore(
                        DateTime(month.year, month.month),
                      )),
      ),
      ...tasks.where(
        (row) =>
            !row.completed && row.date != null && _inMonth(row.date!, month),
      ),
    ],
    AllSpacesArea.projects || AllSpacesArea.home => [
      for (final record in snapshot.projects)
        if (area != AllSpacesArea.home || record.value.area == ProjectArea.home)
          AllSpacesRow(
            source: record.source,
            id: record.value.id,
            type: 'project',
            title: record.value.title,
            notes: record.value.description,
            date: record.value.startAt,
            children:
                tasksByProject['${record.source.key}:${record.value.id}'] ??
                const [],
          ),
    ],
    AllSpacesArea.shopping => [
      for (final record in snapshot.shoppingLists)
        AllSpacesRow(
          source: record.source,
          id: record.value.id,
          type: 'shoppingList',
          title: record.value.title,
          children:
              itemsByList['${record.source.key}:${record.value.id}'] ??
              const [],
        ),
    ],
    AllSpacesArea.finances =>
      [...finances, ...transfers]
          .where(
            (row) =>
                _inMonth(row.date!, month) &&
                (currency == null || row.currency == currency),
          )
          .toList(),
    AllSpacesArea.people => [
      for (final record in snapshot.people)
        if (!record.value.archived)
          AllSpacesRow(
            source: record.source,
            id: record.value.id,
            type: 'person',
            title: record.value.name,
            notes: record.value.notes,
            children:
                tasksByPerson['${record.source.key}:${record.value.id}'] ??
                const [],
          ),
    ],
  };
  rows.sort((a, b) {
    if (area == AllSpacesArea.projects ||
        area == AllSpacesArea.home ||
        area == AllSpacesArea.shopping ||
        area == AllSpacesArea.people) {
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
    if (a.date == null) return b.date == null ? a.title.compareTo(b.title) : 1;
    if (b.date == null) return -1;
    final order = area == AllSpacesArea.finances
        ? b.date!.compareTo(a.date!)
        : a.date!.compareTo(b.date!);
    return order != 0
        ? order
        : '${a.title}:${a.source.key}:${a.id}'.compareTo(
            '${b.title}:${b.source.key}:${b.id}',
          );
  });
  return rows;
}

class AllSpacesRowTile extends StatelessWidget {
  const AllSpacesRowTile({
    super.key,
    required this.row,
    required this.onOpen,
    required this.onSource,
  });
  final AllSpacesRow row;
  final VoidCallback onOpen, onSource;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final metadata = [
      allSpacesSourceLabel(context, row.source),
      if (row.date != null) organizerDate(context, row.date!),
      if (row.amountMinor != null)
        sharedMoneyLabel(context, BigInt.from(row.amountMinor!), row.currency!),
      if (row.type == 'financeTransfer') l.financeTransfer,
      if (row.kind != null)
        row.kind == FinanceEntryKind.income
            ? l.organizerIncome
            : l.organizerExpense,
      if (row.kind != null) row.posted ? l.financePosted : l.financePlanned,
      if (row.notes.isNotEmpty && row.type == 'shoppingItem') row.notes,
    ].join(' · ');
    return Card(
      key: ValueKey('all-row-${row.source.key}-${row.type}-${row.id}'),
      child: row.children.isEmpty
          ? ListTile(
              leading: row.type == 'task'
                  ? _TaskCompletionCheckbox(
                      key: ValueKey('task-check-${row.source.key}-${row.id}'),
                      row: row,
                    )
                  : Icon(row.icon),
              title: Text(row.title),
              subtitle: Text(metadata),
              trailing: IconButton(
                tooltip: l.allSpacesOpenSource,
                onPressed: onSource,
                icon: const Icon(Icons.chevron_right),
              ),
              onTap: onOpen,
            )
          : ExpansionTile(
              leading: row.type == 'task'
                  ? _TaskCompletionCheckbox(
                      key: ValueKey('task-check-${row.source.key}-${row.id}'),
                      row: row,
                    )
                  : Icon(row.icon),
              title: Text(row.title),
              subtitle: Text(metadata),
              children: [
                if (row.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(row.notes),
                  ),
                for (final child in row.children)
                  _ChildRow(
                    key: ValueKey(
                      'all-child-${child.source.key}-${child.type}-${child.id}',
                    ),
                    row: child,
                  ),
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l.allSpacesOpenSource),
                ),
              ],
            ),
    );
  }
}

class _ChildRow extends ConsumerWidget {
  const _ChildRow({super.key, required this.row});
  final AllSpacesRow row;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    leading: row.type == 'task'
        ? _TaskCompletionCheckbox(
            key: ValueKey('task-check-${row.source.key}-${row.id}'),
            row: row,
          )
        : Icon(row.icon),
    title: Text(row.title),
    subtitle: Text(
      [
        allSpacesSourceLabel(context, row.source),
        if (row.notes.isNotEmpty && row.type == 'shoppingItem') row.notes,
      ].join(' · '),
    ),
    onTap: () => openAllSpacesRow(context, ref, row),
  );
}

/// A completion action always targets the row's concrete source, never the
/// selected aggregate space. The repository rechecks identity and edit rights.
class _TaskCompletionCheckbox extends ConsumerStatefulWidget {
  const _TaskCompletionCheckbox({super.key, required this.row});
  final AllSpacesRow row;
  @override
  ConsumerState<_TaskCompletionCheckbox> createState() =>
      _TaskCompletionCheckboxState();
}

class _TaskCompletionCheckboxState
    extends ConsumerState<_TaskCompletionCheckbox> {
  bool _saving = false;

  bool get _editable {
    final row = widget.row;
    if (!allSpacesSourceIsCurrent(ref, row.source)) return false;
    final shared = ref.read(collaborationProvider).valueOrNull;
    final personal = ref.read(organizerProvider).valueOrNull;
    if (row.source.isPersonal) {
      if (!row.source.isLocalSpace) {
        final scope = shared?.scopes
            .where((s) => s.id == row.source.privateScopeId)
            .firstOrNull;
        if (scope?.canEdit != true ||
            scope!.deleted ||
            !scope.canRead ||
            shared?.deletionPending == true) {
          return false;
        }
      }
      final snapshot = row.source.isLocalSpace
          ? ref
                    .read(localSpacesProvider)
                    .valueOrNull
                    ?.snapshots[row.source.workspaceKey] ??
                (personal?.workspaceKey == row.source.workspaceKey
                    ? personal
                    : null)
          : ref.read(localSpacesProvider).valueOrNull?.snapshots['local'] ??
                personal;
      final task = snapshot?.tasks.where((t) => t.id == row.id).firstOrNull;
      return snapshot?.workspaceKey == row.source.workspaceKey &&
          task != null &&
          !snapshot!.projects.any((p) => p.id == task.projectId && p.archived);
    }
    final scope = shared?.scopes
        .where((s) => s.id == row.source.scopeId)
        .firstOrNull;
    final data = scope == null ? null : shared!.dataForScope(scope.id);
    final task = data?.tasks.where((t) => t.id == row.id).firstOrNull;
    return scope?.canEdit == true &&
        scope!.canRead &&
        !scope.deleted &&
        shared?.deletionPending != true &&
        task != null &&
        !data!.projects.any((p) => p.id == task.projectId && p.archived);
  }

  Future<void> _setCompleted(bool value) async {
    if (_saving || !_editable) return;
    setState(() => _saving = true);
    final row = widget.row;
    try {
      if (row.source.isPersonal) {
        final personal = ref.read(organizerProvider).valueOrNull!;
        if (personal.workspaceKey == row.source.workspaceKey) {
          await OrganizerActions(
            context,
            ref,
            personal,
          ).setTaskCompleted(row.id, value);
        } else {
          await ref
              .read(localSpacesProvider.notifier)
              .setTaskCompleted(
                row.source.isLocalSpace ? row.source.workspaceKey! : 'local',
                row.id,
                value,
                expectedWorkspaceKey: row.source.workspaceKey!,
                stillVisible: () => mounted && _editable,
              );
        }
      } else {
        final shared = ref.read(collaborationProvider).valueOrNull!;
        final scope = shared.scopes.firstWhere(
          (s) => s.id == row.source.scopeId,
        );
        await CollaborationActions(
          context,
          ref,
          scope,
          shared.dataForScope(scope.id),
        ).setTaskCompleted(row.id, value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(organizerErrorMessage(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(organizerProvider);
    ref.watch(collaborationProvider);
    ref.watch(localSpacesProvider);
    final l = context.l10n;
    return Semantics(
      label: widget.row.title,
      child: GestureDetector(
        // Keep taps on a disabled or saving checkbox out of the row's detail
        // navigation gesture as well.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Checkbox(
          key: ValueKey(
            'all-task-complete-${widget.row.source.key}-${widget.row.id}',
          ),
          value: widget.row.completed,
          shape: const CircleBorder(),
          onChanged: _saving || !_editable
              ? null
              : (value) => _setCompleted(value!),
          semanticLabel: l.organizerCompleted,
        ),
      ),
    );
  }
}

bool allSpacesSourceIsCurrent(
  WidgetRef ref,
  AllSpacesSource source, {
  bool financial = false,
}) {
  final personalState = ref.read(organizerProvider);
  final sharedState = ref.read(collaborationProvider);
  if (personalState.isLoading ||
      personalState.hasError ||
      sharedState.isLoading ||
      sharedState.hasError) {
    return false;
  }
  final personal = personalState.asData?.value;
  final shared = sharedState.asData?.value;
  return personal != null &&
      source.isCurrent(
        personal,
        shared ?? CollaborationState(),
        financial: financial,
        localSpaces: ref.read(localSpacesProvider).valueOrNull,
      );
}

Future<void> openAllSpacesRow(
  BuildContext context,
  WidgetRef ref,
  AllSpacesRow row,
) async {
  if (!allSpacesSourceIsCurrent(
    ref,
    row.source,
    financial: row.type.contains('Finance') || row.type.startsWith('finance'),
  )) {
    return;
  }
  if (row.type == 'task') {
    await showVisibleTaskTarget(
      context,
      ref,
      row.source.target(row.type, row.id),
      isCurrent: () =>
          context.mounted && allSpacesSourceIsCurrent(ref, row.source),
    );
    return;
  }
  final guard = row.source.isPersonal
      ? PersonalWorkspaceGuard(context, ref, row.source.workspaceKey!)
      : null;
  await showNotificationTarget(
    context,
    ref,
    row.source.target(row.type, row.id),
    wrap: guard?.wrap,
    isCurrent: () =>
        context.mounted &&
        allSpacesSourceIsCurrent(
          ref,
          row.source,
          financial: row.amountMinor != null,
        ),
  );
}

class AllSpacesFinanceSummary extends StatelessWidget {
  const AllSpacesFinanceSummary({
    super.key,
    required this.snapshot,
    this.month,
    this.currency,
    required this.onCurrency,
  });
  final AllSpacesSnapshot snapshot;
  final DateTime? month;
  final String? currency;
  final ValueChanged<String?> onCurrency;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final entries = allSpacesRows(
      snapshot,
      AllSpacesArea.finances,
      now: DateTime.now(),
      month: month,
    );
    final currencies = entries.map((row) => row.currency!).toSet().toList()
      ..sort();
    final summary = <Widget>[];
    final completeCurrencies =
        entries
            .where((row) => row.posted && row.source.financeComplete)
            .map((row) => row.currency!)
            .toSet()
            .toList()
          ..sort();
    for (final code in completeCurrencies.where(
      (code) => currency == null || code == currency,
    )) {
      var income = BigInt.zero, expense = BigInt.zero;
      for (final row in entries.where(
        (row) =>
            row.currency == code && row.posted && row.source.financeComplete,
      )) {
        if (row.kind == FinanceEntryKind.income) {
          income += BigInt.from(row.amountMinor!);
        } else if (row.kind == FinanceEntryKind.expense) {
          expense += BigInt.from(row.amountMinor!);
        }
      }
      summary.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$code · ${l.financePosted}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${l.organizerIncome}: ${sharedMoneyLabel(context, income, code)}',
                ),
                Text(
                  '${l.organizerExpense}: ${sharedMoneyLabel(context, expense, code)}',
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(l.allSpacesTitle),
              selected: currency == null,
              onSelected: (_) => onCurrency(null),
            ),
            for (final code in currencies)
              ChoiceChip(
                label: Text(code),
                selected: code == currency,
                onSelected: (_) => onCurrency(code),
              ),
          ],
        ),
        ...summary,
      ],
    );
  }
}
