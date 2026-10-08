import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import 'organizer_errors.dart';
import 'planning/task_plan_fields.dart';
import 'planning/date_time_field.dart';
import 'planning/record_planning_fields.dart';
import 'planning/task_timer_panel.dart';

/// Dialog result is presentation data; persistence and validation stay in the
/// organizer controller and domain layer.
class OrganizerDraft {
  OrganizerDraft({
    this.phases = const [],
    this.phaseId,
    this.estimateMinutes,
    this.availabilityMinutes,
    this.availabilityPeriod,
    this.timer = const TaskTimerState(),
    this.assigneePersonId,
    this.subjectPersonIds = const [],
    this.costEnabled = false,
    this.costAmount = '',
    this.costCurrency = 'EUR',
    this.costPaid = false,
    this.costWasPaid = false,
    this.costPaidAt,
    this.ledgerAccountId,
    this.payerPersonId,
    this.recipientPersonId,
    this.createdByPersonId,
    this.title = '',
    this.notes = '',
    this.projectId,
    this.date,
    this.startAt,
    this.endAt,
    List<String> assigneeIds = const [],
    this.quantity = '1',
    this.amount = '',
    this.currency = 'EUR',
    this.kind = FinanceEntryKind.expense,
    this.financeIdentityLocked = false,
    this.area = ProjectArea.personal,
  }) : assigneeIds = [...assigneeIds];
  List<ProjectPhase> phases;
  String? phaseId, assigneePersonId;
  List<String> subjectPersonIds;
  int? estimateMinutes, availabilityMinutes;
  AvailabilityPeriod? availabilityPeriod;
  TaskTimerState timer;
  bool costEnabled, costPaid, costWasPaid;
  DateTime? costPaidAt;
  String costAmount, costCurrency;
  String? ledgerAccountId, payerPersonId, recipientPersonId, createdByPersonId;
  String title;
  String notes;
  String? projectId;
  DateTime? date;
  DateTime? startAt;
  DateTime? endAt;
  List<String> assigneeIds;
  String quantity;
  String amount;
  String currency;
  FinanceEntryKind kind;
  bool financeIdentityLocked;
  ProjectArea area;
}

enum OrganizerEditorKind {
  project,
  task,
  event,
  shoppingList,
  shoppingItem,
  finance,
}

Future<void> showOrganizerEditor(
  BuildContext context, {
  required String heading,
  required OrganizerEditorKind kind,
  required OrganizerDraft draft,
  required Future<void> Function(OrganizerDraft) onSave,
  List<LocalProject> projects = const [],
  bool projectSelectionEnabled = true,
  Set<String>? localRecordIds,
  String? recordId,
  bool defaultLocalOwnership = true,
  List<OrganizerPersonOption> people = const [],
  bool assignmentEnabled = false,
  List<HouseholdPerson> householdPeople = const [],
  List<LocalFinanceAccount> financeAccounts = const [],
  bool costEditingEnabled = false,
  bool costAccountRequired = false,
  Future<LocalTask> Function()? onTimerToggle,
  String? creatorLabel,
  Future<void> Function()? onDelete,
  String Function(Object)? errorMessage,
  Widget Function(Widget)? wrap,
}) => showDialog<void>(
  context: context,
  builder: (context) {
    final editor = _RecordEditor(
      heading: heading,
      kind: kind,
      draft: draft,
      projects: projects,
      projectSelectionEnabled: projectSelectionEnabled,
      localRecordIds: localRecordIds,
      recordId: recordId,
      defaultLocalOwnership: defaultLocalOwnership,
      people: people,
      assignmentEnabled: assignmentEnabled,
      householdPeople: householdPeople,
      financeAccounts: financeAccounts,
      costEditingEnabled: costEditingEnabled,
      costAccountRequired: costAccountRequired,
      onTimerToggle: onTimerToggle,
      creatorLabel: creatorLabel,
      onSave: onSave,
      onDelete: onDelete,
      errorMessage: errorMessage,
      wrap: wrap,
    );
    return wrap?.call(editor) ?? editor;
  },
);

class _RecordEditor extends StatefulWidget {
  const _RecordEditor({
    required this.heading,
    required this.kind,
    required this.draft,
    required this.projects,
    required this.projectSelectionEnabled,
    this.localRecordIds,
    this.recordId,
    required this.defaultLocalOwnership,
    required this.people,
    required this.assignmentEnabled,
    required this.householdPeople,
    required this.financeAccounts,
    required this.costEditingEnabled,
    required this.costAccountRequired,
    this.onTimerToggle,
    this.creatorLabel,
    required this.onSave,
    this.onDelete,
    this.errorMessage,
    this.wrap,
  });
  final String heading;
  final OrganizerEditorKind kind;
  final OrganizerDraft draft;
  final List<LocalProject> projects;
  final bool projectSelectionEnabled, defaultLocalOwnership;
  final Set<String>? localRecordIds;
  final String? recordId;
  final List<OrganizerPersonOption> people;
  final bool assignmentEnabled;
  final List<HouseholdPerson> householdPeople;
  final List<LocalFinanceAccount> financeAccounts;
  final bool costEditingEnabled, costAccountRequired;
  final Future<LocalTask> Function()? onTimerToggle;
  final String? creatorLabel;
  final Future<void> Function(OrganizerDraft) onSave;
  final Future<void> Function()? onDelete;
  final String Function(Object)? errorMessage;
  final Widget Function(Widget)? wrap;
  @override
  State<_RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<_RecordEditor> {
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _failure;
  OrganizerDraft get draft => widget.draft;
  bool get _hasProject => {
    OrganizerEditorKind.task,
    OrganizerEditorKind.event,
    OrganizerEditorKind.finance,
  }.contains(widget.kind);
  bool get _hasDate => _hasProject;
  bool get _hasNotes =>
      widget.kind != OrganizerEditorKind.shoppingList &&
      widget.kind != OrganizerEditorKind.shoppingItem;

  Future<void> _save() async {
    final invalidFields = _form.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      // Validation can happen while the user is at the bottom of the form.
      // Reveal the first error after its extra line has been laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !invalidFields.first.mounted) return;
        final fieldContext = invalidFields.first.context;
        final object = fieldContext.findRenderObject()!;
        final position = Scrollable.of(fieldContext).position;
        final offset = RenderAbstractViewport.of(
          object,
        ).getOffsetToReveal(object, 0).offset;
        // Include the floating label, which is outside the FormField box.
        final labelMargin = MediaQuery.textScalerOf(context).scale(16);
        position.animateTo(
          (offset - labelMargin).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
      return;
    }
    _form.currentState!.save();
    final planStart = widget.kind == OrganizerEditorKind.event
        ? draft.date
        : draft.startAt;
    if (planStart != null &&
        draft.endAt != null &&
        draft.endAt!.isBefore(planStart)) {
      setState(() => _failure = context.l10n.planningInvalidSchedule);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.onSave(draft);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure =
              widget.errorMessage?.call(error) ??
              organizerErrorMessage(context, error);
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dialog = AlertDialog(
          title: Text(context.l10n.organizerDeleteConfirm),
          content: widget.kind == OrganizerEditorKind.project
              ? Text(context.l10n.organizerDeleteProjectNote)
              : null,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.delete),
            ),
          ],
        );
        return widget.wrap?.call(dialog) ?? dialog;
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure =
              widget.errorMessage?.call(error) ??
              organizerErrorMessage(context, error);
        });
      }
    }
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final current = draft.date?.toLocal() ?? now;
    final first = DateTime(1900);
    final last = DateTime(2200);
    final initial = current.isBefore(first)
        ? first
        : current.isAfter(last)
        ? last
        : current;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: widget.wrap == null
          ? null
          : (context, child) => widget.wrap!(child!),
    );
    if (picked == null || !mounted) return;
    var next = widget.kind == OrganizerEditorKind.task
        ? DateTime(picked.year, picked.month, picked.day, 23, 59)
        : DateTime(picked.year, picked.month, picked.day);
    if (widget.kind == OrganizerEditorKind.event) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(current),
        builder: widget.wrap == null
            ? null
            : (context, child) => widget.wrap!(child!),
      );
      if (time == null || !mounted) return;
      next = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time.hour,
        time.minute,
      );
    }
    setState(() => draft.date = next);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final fieldGap = compact ? 12.0 : 16.0;
    final fieldStyle = compact
        ? Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15)
        : null;
    final localIds = widget.localRecordIds;
    final localOwnership = localIds == null
        ? null
        : widget.recordId != null
        ? localIds.contains(widget.recordId)
        : draft.projectId != null
        ? localIds.contains(draft.projectId)
        : widget.kind == OrganizerEditorKind.finance
        ? null
        : widget.defaultLocalOwnership;
    final allowedPeople = widget.householdPeople
        .where(
          (person) =>
              localOwnership == null ||
              localIds!.contains(person.id) == localOwnership,
        )
        .toList();
    final allowedAccounts = widget.financeAccounts
        .where(
          (account) =>
              localOwnership == null ||
              localIds!.contains(account.id) == localOwnership,
        )
        .toList();
    final finance = widget.kind == OrganizerEditorKind.finance;
    final dateRequired = widget.kind == OrganizerEditorKind.event || finance;
    return AlertDialog(
      insetPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      titlePadding: compact ? const EdgeInsets.fromLTRB(16, 16, 16, 8) : null,
      contentPadding: compact ? const EdgeInsets.fromLTRB(16, 8, 16, 12) : null,
      actionsPadding: compact ? const EdgeInsets.fromLTRB(12, 0, 12, 12) : null,
      title: Text(
        widget.heading,
        style: compact
            ? Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)
            : null,
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          key: const ValueKey('organizer-editor-scroll'),
          // Outlined fields paint their floating label above the field's box.
          // Keep that paint inside the viewport, including with larger text.
          padding: EdgeInsets.only(
            top: MediaQuery.textScalerOf(context).scale(12),
            bottom: 4,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('organizer-title-field'),
                  initialValue: draft.title,
                  autofocus: true,
                  style: fieldStyle,
                  textInputAction:
                      _hasNotes ||
                          widget.kind == OrganizerEditorKind.shoppingItem
                      ? TextInputAction.next
                      : TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: l.organizerTitle),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? l.organizerRequired
                      : null,
                  onSaved: (v) => draft.title = v!.trim(),
                ),
                if (_hasNotes) ...[
                  SizedBox(height: fieldGap),
                  TextFormField(
                    key: const ValueKey('organizer-notes-field'),
                    initialValue: draft.notes,
                    minLines: compact ? 2 : 3,
                    maxLines: compact ? 4 : 3,
                    style: fieldStyle,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: widget.kind == OrganizerEditorKind.project
                          ? l.organizerDescription
                          : l.organizerNotes,
                    ),
                    onSaved: (v) => draft.notes = v ?? '',
                  ),
                ],
                if (widget.kind == OrganizerEditorKind.shoppingItem) ...[
                  SizedBox(height: fieldGap),
                  TextFormField(
                    initialValue: draft.quantity,
                    style: fieldStyle,
                    decoration: InputDecoration(labelText: l.organizerQuantity),
                    onSaved: (v) => draft.quantity = v?.trim() ?? '',
                  ),
                ],
                if (widget.kind == OrganizerEditorKind.project) ...[
                  SizedBox(height: fieldGap),
                  DropdownButtonFormField<ProjectArea>(
                    isExpanded: true,
                    initialValue: draft.area,
                    decoration: InputDecoration(
                      labelText: l.organizerProjectArea,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: ProjectArea.personal,
                        child: Text(l.organizerPersonalArea),
                      ),
                      DropdownMenuItem(
                        value: ProjectArea.home,
                        child: Text(l.organizerHomeArea),
                      ),
                    ],
                    onChanged: _busy ? null : (v) => draft.area = v!,
                  ),
                ],
                if (_hasProject && widget.projectSelectionEnabled) ...[
                  SizedBox(height: fieldGap),
                  DropdownButtonFormField<String>(
                    initialValue: draft.projectId ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.project),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(l.organizerNoProject),
                      ),
                      for (final p in widget.projects)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(p.title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            draft.projectId = v == '' ? null : v;
                            draft.phaseId = null;
                            draft.assigneePersonId = null;
                            draft.subjectPersonIds = [];
                            draft.ledgerAccountId = null;
                            draft.payerPersonId = null;
                            draft.recipientPersonId = null;
                          }),
                  ),
                ],
                if (widget.kind == OrganizerEditorKind.task ||
                    widget.kind == OrganizerEditorKind.project ||
                    widget.kind == OrganizerEditorKind.event)
                  OrganizerTaskPlanFields(
                    startAt: widget.kind == OrganizerEditorKind.event
                        ? draft.date
                        : draft.startAt,
                    showStart: widget.kind != OrganizerEditorKind.event,
                    endAt: draft.endAt,
                    onStartChanged: (value) =>
                        setState(() => draft.startAt = value),
                    onEndChanged: (value) =>
                        setState(() => draft.endAt = value),
                    people: widget.people,
                    assigneeIds: draft.assigneeIds,
                    onAssigneesChanged:
                        widget.assignmentEnabled &&
                            (widget.kind == OrganizerEditorKind.task ||
                                widget.kind == OrganizerEditorKind.event)
                        ? (ids) => setState(() => draft.assigneeIds = ids)
                        : null,
                    creatorLabel: widget.creatorLabel,
                    enabled: !_busy,
                    wrap: widget.wrap,
                  ),
                if (widget.kind == OrganizerEditorKind.project ||
                    widget.kind == OrganizerEditorKind.task)
                  OrganizerRecordPlanningFields(
                    draft: draft,
                    project: widget.kind == OrganizerEditorKind.project,
                    projects: widget.projects,
                    key: ValueKey(localOwnership),
                    people: allowedPeople,
                    financeAccounts: allowedAccounts,
                    costEditingEnabled: widget.costEditingEnabled,
                    costAccountRequired: widget.costAccountRequired,
                    enabled: !_busy,
                    wrap: widget.wrap,
                    onChanged: () => setState(() {}),
                  ),
                if (widget.kind == OrganizerEditorKind.task &&
                    widget.onTimerToggle != null)
                  TaskTimerPanel(
                    timer: draft.timer,
                    estimateMinutes: draft.estimateMinutes,
                    onToggle: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              final task = await widget.onTimerToggle!();
                              if (mounted) {
                                setState(() => draft.timer = task.timer);
                              }
                            } catch (error) {
                              if (mounted) {
                                setState(
                                  () => _failure =
                                      widget.errorMessage?.call(error) ??
                                      organizerErrorMessage(context, error),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                  ),
                if (finance) ...[
                  SizedBox(height: fieldGap),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('personal-finance-account'),
                    initialValue: draft.ledgerAccountId ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.financeAccount),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(l.taskCostUnassignedAccount),
                      ),
                      for (final account in allowedAccounts.where(
                        (a) => !a.archived || a.id == draft.ledgerAccountId,
                      ))
                        DropdownMenuItem(
                          value: account.id,
                          child: Text('${account.name} · ${account.currency}'),
                        ),
                      if (draft.ledgerAccountId != null &&
                          !allowedAccounts.any(
                            (a) => a.id == draft.ledgerAccountId,
                          ))
                        DropdownMenuItem(
                          value: draft.ledgerAccountId!,
                          child: Text(l.financeAccountUnavailable),
                        ),
                    ],
                    validator: (id) =>
                        id == null ||
                            id.isEmpty ||
                            allowedAccounts.any(
                              (a) => a.id == id && a.currency == draft.currency,
                            )
                        ? null
                        : l.financeAccountUnavailable,
                    onChanged: _busy || draft.financeIdentityLocked
                        ? null
                        : (id) => setState(() {
                            draft.ledgerAccountId = id == '' ? null : id;
                            final account = allowedAccounts
                                .where((a) => a.id == id)
                                .firstOrNull;
                            if (account != null) {
                              draft.currency = account.currency;
                            }
                          }),
                  ),
                  SizedBox(height: fieldGap),
                  DropdownButtonFormField<FinanceEntryKind>(
                    isExpanded: true,
                    initialValue: draft.kind,
                    decoration: InputDecoration(labelText: l.type),
                    items: [
                      DropdownMenuItem(
                        value: FinanceEntryKind.expense,
                        child: Text(l.organizerExpense),
                      ),
                      DropdownMenuItem(
                        value: FinanceEntryKind.income,
                        child: Text(l.organizerIncome),
                      ),
                    ],
                    onChanged: _busy || draft.financeIdentityLocked
                        ? null
                        : (v) => draft.kind = v!,
                  ),
                  SizedBox(height: fieldGap),
                  TextFormField(
                    key: const ValueKey('personal-finance-amount'),
                    initialValue: draft.amount,
                    style: fieldStyle,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: l.amount),
                    validator: (v) {
                      try {
                        return parseMoneyMinor(v ?? '') > 0
                            ? null
                            : l.organizerInvalidMoney;
                      } catch (_) {
                        return l.organizerInvalidMoney;
                      }
                    },
                    onSaved: (v) => draft.amount = v!,
                  ),
                  SizedBox(height: fieldGap),
                  DropdownButtonFormField<String>(
                    key: ValueKey('finance-currency-${draft.currency}'),
                    initialValue: draft.currency,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.organizerCurrency),
                    items: const ['EUR', 'USD', 'GBP', 'CHF']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged:
                        _busy ||
                            draft.financeIdentityLocked ||
                            draft.ledgerAccountId != null
                        ? null
                        : (v) => draft.currency = v!,
                  ),
                ],
                if (widget.kind == OrganizerEditorKind.task) ...[
                  SizedBox(height: fieldGap),
                  OrganizerDateTimeField(
                    key: const ValueKey('task-due-date'),
                    label: l.planningDue,
                    value: draft.date,
                    enabled: !_busy,
                    wrap: widget.wrap,
                    onChanged: (date) => setState(() => draft.date = date),
                  ),
                ],
                if (_hasDate && widget.kind != OrganizerEditorKind.task) ...[
                  SizedBox(height: fieldGap),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      draft.date == null
                          ? l.organizerNoDate
                          : '${MaterialLocalizations.of(context).formatMediumDate(draft.date!.toLocal())}${widget.kind == OrganizerEditorKind.event ? ' · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(draft.date!.toLocal()))}' : ''}',
                    ),
                  ),
                  if (!dateRequired && draft.date != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => draft.date = null),
                      child: Text(l.organizerRemoveDate),
                    ),
                ],
                if (_failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _failure!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          IconButton(
            tooltip: l.delete,
            onPressed: _busy ? null : _delete,
            icon: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('organizer-save'),
          onPressed: _busy ? null : _save,
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
