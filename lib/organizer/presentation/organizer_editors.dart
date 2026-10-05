import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import 'organizer_errors.dart';
import 'planning/task_plan_fields.dart';
import 'planning/date_time_field.dart';

/// Dialog result is presentation data; persistence and validation stay in the
/// organizer controller and domain layer.
class OrganizerDraft {
  OrganizerDraft({
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
    this.area = ProjectArea.personal,
  }) : assigneeIds = [...assigneeIds];
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
  List<OrganizerPersonOption> people = const [],
  bool assignmentEnabled = false,
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
      people: people,
      assignmentEnabled: assignmentEnabled,
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
    required this.people,
    required this.assignmentEnabled,
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
  final List<OrganizerPersonOption> people;
  final bool assignmentEnabled;
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
    if (!_form.currentState!.validate()) return;
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
    final finance = widget.kind == OrganizerEditorKind.finance;
    final dateRequired = widget.kind == OrganizerEditorKind.event || finance;
    return AlertDialog(
      title: Text(widget.heading),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
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
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: l.organizerTitle),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? l.organizerRequired
                      : null,
                  onSaved: (v) => draft.title = v!.trim(),
                ),
                if (_hasNotes) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: draft.notes,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: widget.kind == OrganizerEditorKind.project
                          ? l.organizerDescription
                          : l.organizerNotes,
                    ),
                    onSaved: (v) => draft.notes = v?.trim() ?? '',
                  ),
                ],
                if (widget.kind == OrganizerEditorKind.shoppingItem) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: draft.quantity,
                    decoration: InputDecoration(labelText: l.organizerQuantity),
                    onSaved: (v) => draft.quantity = v?.trim() ?? '',
                  ),
                ],
                if (widget.kind == OrganizerEditorKind.project) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ProjectArea>(
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
                if (_hasProject) ...[
                  const SizedBox(height: 16),
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
                        : (v) => draft.projectId = v == '' ? null : v,
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
                if (finance) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<FinanceEntryKind>(
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
                    onChanged: _busy ? null : (v) => draft.kind = v!,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: draft.amount,
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
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: draft.currency,
                    decoration: InputDecoration(labelText: l.organizerCurrency),
                    items: const ['EUR', 'USD', 'GBP', 'CHF']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: _busy ? null : (v) => draft.currency = v!,
                  ),
                ],
                if (widget.kind == OrganizerEditorKind.task) ...[
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
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
