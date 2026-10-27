import 'editor_actions.dart';
import 'desktop/desktop_inspector.dart';
import 'desktop/desktop_layout.dart';
import 'shared/content_moderation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import '../domain/task_cost_account_default.dart';
import '../domain/draft_three_way_merge.dart';
import 'organizer_errors.dart';
import 'planning/task_plan_fields.dart';
import 'planning/date_time_field.dart';
import 'planning/record_planning_fields.dart';
import 'planning/task_timer_panel.dart';

part 'task_draft_review.dart';

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
    this.isCompleted = false,
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
  bool isCompleted;
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

/// Live, presentation-only updates for an already open editor. Replacing a
/// pristine task advances its save base; a dirty draft retains its original base.
class OrganizerEditorUpdates extends ChangeNotifier {
  OrganizerDraft? replacementDraft;
  VoidCallback? acceptReplacement;
  bool editingAllowed = true;
  bool Function()? isCurrent;
  bool allowLocalDraftContinuation = false;
  bool costEditingEnabled = false;
  bool costVisible = true;
  bool financeLoading = false;
  bool financeUnavailable = false;
  VoidCallback? onCostSectionOpened;
  Map<String, ({String name, String currency, bool archived})>
  financeAccountChoices = const {};

  void replaceDraft(OrganizerDraft value, VoidCallback accept) {
    replacementDraft = value;
    acceptReplacement = accept;
    notifyListeners();
  }

  void financeChanged() => notifyListeners();
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
  bool projectAreaEnabled = true,
  Set<String>? localRecordIds,
  String? recordId,
  bool defaultLocalOwnership = true,
  List<OrganizerPersonOption> people = const [],
  bool assignmentEnabled = false,
  List<HouseholdPerson> householdPeople = const [],
  List<LocalFinanceAccount> financeAccounts = const [],
  Map<String, ({String name, String currency, bool archived})>
      financeAccountChoices =
      const {},
  bool costEditingEnabled = false,
  bool costAccountRequired = false,
  Future<LocalTask> Function()? onTimerToggle,
  String? creatorLabel,
  Future<void> Function()? onDelete,
  Future<bool> Function()? onDeleteWithReview,
  Future<void> Function()? onShare,
  String? shareActionLabel,
  String? projectContext,
  Future<void> Function()? onReport,
  String Function(Object)? errorMessage,
  Widget Function(Widget)? wrap,
  String? sharedPolicyScopeId,
  OrganizerEditorUpdates? updates,
}) {
  final inspector = organizerUsesDesktopLayout(context)
      ? OrganizerDesktopInspectorScope.maybeOf(context)
      : null;
  Widget builder(BuildContext context) {
    final editor = _RecordEditor(
      updates: updates,
      heading: heading,
      kind: kind,
      draft: draft,
      projects: projects,
      projectSelectionEnabled: projectSelectionEnabled,
      projectAreaEnabled: projectAreaEnabled,
      localRecordIds: localRecordIds,
      recordId: recordId,
      defaultLocalOwnership: defaultLocalOwnership,
      people: people,
      assignmentEnabled: assignmentEnabled,
      householdPeople: householdPeople,
      financeAccounts: financeAccounts,
      financeAccountChoices: financeAccountChoices,
      costEditingEnabled: costEditingEnabled,
      costAccountRequired: costAccountRequired,
      onTimerToggle: onTimerToggle,
      creatorLabel: creatorLabel,
      onSave: onSave,
      onDelete: onDelete,
      onDeleteWithReview: onDeleteWithReview,
      onShare: onShare,
      shareActionLabel: shareActionLabel,
      projectContext: projectContext,
      onReport: onReport,
      errorMessage: errorMessage,
      wrap: wrap,
      sharedPolicyScopeId: sharedPolicyScopeId,
      embedded: inspector != null,
    );
    return wrap?.call(editor) ?? editor;
  }

  return inspector?.show(builder) ??
      showDialog<void>(context: context, builder: builder);
}

class _RecordEditor extends StatefulWidget {
  const _RecordEditor({
    this.updates,
    required this.heading,
    required this.kind,
    required this.draft,
    required this.projects,
    required this.projectSelectionEnabled,
    required this.projectAreaEnabled,
    this.localRecordIds,
    this.recordId,
    required this.defaultLocalOwnership,
    required this.people,
    required this.assignmentEnabled,
    required this.householdPeople,
    required this.financeAccounts,
    required this.financeAccountChoices,
    required this.costEditingEnabled,
    required this.costAccountRequired,
    this.onTimerToggle,
    this.creatorLabel,
    required this.onSave,
    this.onDelete,
    this.onDeleteWithReview,
    this.onShare,
    this.shareActionLabel,
    this.projectContext,
    this.onReport,
    this.errorMessage,
    this.wrap,
    this.sharedPolicyScopeId,
    this.embedded = false,
  });
  final OrganizerEditorUpdates? updates;
  final String heading;
  final OrganizerEditorKind kind;
  final OrganizerDraft draft;
  final List<LocalProject> projects;
  final bool projectSelectionEnabled, defaultLocalOwnership;
  final bool projectAreaEnabled;
  final String? projectContext;
  final Future<bool> Function()? onDeleteWithReview;
  final Future<void> Function()? onShare;
  final String? shareActionLabel;
  final Set<String>? localRecordIds;
  final String? recordId;
  final List<OrganizerPersonOption> people;
  final bool assignmentEnabled;
  final List<HouseholdPerson> householdPeople;
  final List<LocalFinanceAccount> financeAccounts;
  final Map<String, ({String name, String currency, bool archived})>
  financeAccountChoices;
  final bool costEditingEnabled, costAccountRequired;
  final Future<LocalTask> Function()? onTimerToggle;
  final String? creatorLabel;
  final Future<void> Function(OrganizerDraft) onSave;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onReport;
  final String Function(Object)? errorMessage;
  final Widget Function(Widget)? wrap;
  final String? sharedPolicyScopeId;
  final bool embedded;
  @override
  State<_RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<_RecordEditor> {
  var _form = GlobalKey<FormState>();
  late OrganizerDraft _draft;
  OrganizerDraft? _lastReplacement;
  late Map<String, Object?> _taskBase;
  bool _dirty = false;
  late bool _mayDefaultCostAccount;
  bool _costAccountChosen = false;
  bool _costCurrencyChosen = false;
  bool _newerVersion = false;
  bool _busy = false;
  String? _failure;
  OrganizerDraft get draft => _draft;
  bool get _sharedWriteUnavailable => widget.updates?.editingAllowed == false;
  bool get _localDraftContinuation =>
      _sharedWriteUnavailable &&
      widget.updates?.allowLocalDraftContinuation == true;
  bool get _readOnly => _sharedWriteUnavailable && !_localDraftContinuation;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _taskBase = _taskDraftFields(_draft);
    _mayDefaultCostAccount = !widget.draft.costEnabled;
    widget.updates?.addListener(_applyUpdates);
  }

  @override
  void dispose() {
    widget.updates?.removeListener(_applyUpdates);
    super.dispose();
  }

  void _applyUpdates() {
    if (!mounted) return;
    if (widget.kind == OrganizerEditorKind.task) _form.currentState?.save();
    final updates = widget.updates!;
    final replacement = updates.replacementDraft;
    if (_readOnly) FocusScope.of(context).unfocus();
    setState(() {
      if (replacement != null && replacement != _lastReplacement) {
        _lastReplacement = replacement;
        if (_dirty ||
            _busy ||
            !DraftThreeWayMerge.equal(_taskBase, _taskDraftFields(draft))) {
          _newerVersion = true;
        } else {
          _draft = replacement;
          _taskBase = _taskDraftFields(replacement);
          _mayDefaultCostAccount = !replacement.costEnabled;
          _costAccountChosen = false;
          _costCurrencyChosen = false;
          _form = GlobalKey<FormState>();
          updates.acceptReplacement?.call();
        }
      }
    });
  }

  Future<void> _reviewLatestTask() async {
    _form.currentState?.save();
    final updates = widget.updates;
    final latest = updates?.replacementDraft;
    final accept = updates?.acceptReplacement;
    if (_busy ||
        _sharedWriteUnavailable ||
        latest == null ||
        accept == null ||
        updates?.isCurrent?.call() == false) {
      return;
    }
    final mine = _taskDraftFields(draft);
    final newest = _taskDraftFields(latest);
    // Timer commands have their own delivery path; a task save cannot replay
    // an earlier operational timer state as an editable draft choice.
    final merge = DraftThreeWayMerge(
      base: {..._taskBase, 'timer': newest['timer']},
      mine: {...mine, 'timer': newest['timer']},
      latest: newest,
    );
    final costEditable =
        updates?.costEditingEnabled == true &&
        updates?.costVisible == true &&
        updates?.financeUnavailable != true &&
        updates?.financeLoading != true;
    // Task-only authority cannot expose or overwrite a retained financial draft.
    if (!costEditable &&
        !DraftThreeWayMerge.equal(_taskBase['cost'], mine['cost'])) {
      setState(() => _failure = context.l10n.recordEditForbidden);
      return;
    }
    final l = context.l10n;
    final costVisibility = updates?.costVisible;
    final costPermission = updates?.costEditingEnabled;
    final costReadiness = (
      updates?.financeUnavailable,
      updates?.financeLoading,
    );
    bool current() =>
        mounted &&
        !_sharedWriteUnavailable &&
        updates?.isCurrent?.call() != false &&
        identical(widget.updates, updates) &&
        identical(updates?.replacementDraft, latest) &&
        identical(updates?.acceptReplacement, accept) &&
        DraftThreeWayMerge.equal(mine, _taskDraftFields(draft)) &&
        DraftThreeWayMerge.equal(newest, _taskDraftFields(latest)) &&
        updates?.costVisible == costVisibility &&
        updates?.costEditingEnabled == costPermission &&
        (updates?.financeUnavailable, updates?.financeLoading) == costReadiness;
    final navigator = Navigator.of(context);
    final route = DialogRoute<Map<String, Object?>>(
      context: context,
      builder: (_) => _TaskDraftReviewDialog(
        merge: merge,
        costVisible: updates?.costVisible == true,
        labels: {
          'title': l.organizerTitle,
          'notes': l.organizerNotes,
          'assignment': l.organizerDraftAssignment,
          'schedule': l.organizerDraftSchedule,
          'planning': l.organizerDraftPlanning,
          'completion': l.organizerDraftCompletion,
          'timer': l.organizerDraftTimer,
          'cost': l.organizerDraftCost,
        },
        describe: _describeTaskReview,
      ),
    );
    var invalidated = false;
    void invalidateReview() {
      if (current()) return;
      invalidated = true;
      if (route.isActive) navigator.removeRoute(route);
    }

    updates?.addListener(invalidateReview);
    Map<String, Object?>? result;
    try {
      result = await navigator.push(route);
    } finally {
      updates?.removeListener(invalidateReview);
    }
    if (!mounted) return;
    if (invalidated || !current()) {
      setState(() => _failure = l.organizerDraftReviewStale);
      return;
    }
    if (result == null) return;
    final resolved = {
      ...result,
      'cost': {
        ...result['cost'] as Map,
        'wasPaid': (newest['cost'] as Map)['wasPaid'],
      },
    };
    // No await between the final captured-version guard and base acceptance.
    accept();
    setState(() {
      _taskBase = newest;
      _draft = _taskDraftFromFields(resolved);
      _lastReplacement = latest;
      _newerVersion = false;
      _dirty = true;
      _failure = null;
      _form = GlobalKey<FormState>();
      _mayDefaultCostAccount = false;
    });
  }

  String _describeTaskReview(String key, Object? value) {
    final l = context.l10n;
    String person(Object? id) => id == null
        ? '—'
        : widget.people.where((p) => p.id == id).firstOrNull?.label ??
              widget.householdPeople
                  .where((p) => p.id == id)
                  .firstOrNull
                  ?.name ??
              '—';
    String date(Object? raw) => raw == null
        ? '—'
        : DateFormat.yMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).add_Hm().format(DateTime.parse(raw as String).toLocal());
    switch (key) {
      case 'title':
      case 'notes':
        return (value as String).isEmpty ? '—' : value;
      case 'assignment':
        final fields = value as Map;
        final project = widget.projects
            .where((p) => p.id == fields['project'])
            .firstOrNull;
        final phase = project?.phases
            .where((p) => p.id == fields['phase'])
            .firstOrNull;
        return [
          project?.title ?? '—',
          phase?.title ?? '—',
          person(fields['person']),
          ...[
            ...fields['subjects'] as List,
            ...fields['accounts'] as List,
          ].map(person),
        ].join(' · ');
      case 'schedule':
        final fields = value as List;
        return '${l.planningDue}: ${date(fields[0])}\n${l.planningStart}: ${date(fields[1])}\n${l.planningEnd}: ${date(fields[2])}';
      case 'planning':
        final fields = value as List;
        return '${l.planningEstimateMinutes}: ${fields[0] ?? '—'}\n${l.planningAvailabilityMinutes}: ${fields[1] ?? '—'}\n${l.planningAvailabilityPeriod}: ${fields[2] == null
            ? '—'
            : fields[2] == 'day'
            ? l.planningPerDay
            : l.planningPerWeek}';
      case 'completion':
        return value == true ? '✓' : '—';
      case 'timer':
        final timer = TaskTimerState.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        return '${l.planningElapsed}: ${planningDuration(timer.elapsedAt(DateTime.now()))}\n${l.planningStart}: ${date(timer.runningSince?.toIso8601String())}';
      case 'cost':
        final fields = value as Map;
        if (fields['enabled'] != true) return '—';
        final account =
            widget.financeAccounts
                .where((a) => a.id == fields['account'])
                .firstOrNull
                ?.name ??
            (widget.updates?.financeAccountChoices ??
                    widget.financeAccountChoices)[fields['account']]
                ?.name ??
            l.taskCostUnassignedAccount;
        return '${fields['amount']} ${fields['currency']} · $account · ${fields['paid'] == true ? l.taskCostPaid : l.taskCostPlanned}\n${l.paymentPaidAt}: ${date(fields['paidAt'])}\n${l.taskCostPayer}: ${person(fields['payer'])}\n${l.taskCostRecipient}: ${person(fields['recipient'])}\n${l.planningCreatedBy}: ${person(fields['creator'])}\n${l.organizerDraftPreviouslyPosted}: ${fields['wasPaid'] == true ? '✓' : '—'}';
      default:
        return '—';
    }
  }

  void _edit(VoidCallback change) {
    if (_readOnly) return;
    setState(() {
      _dirty = true;
      change();
    });
  }

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
    if (_busy || _sharedWriteUnavailable) return;
    if (widget.kind == OrganizerEditorKind.task && _newerVersion) {
      await _reviewLatestTask();
      return;
    }
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
      if (widget.sharedPolicyScopeId != null &&
          !await showSharedContentPolicy(
            context,
            scopeId: widget.sharedPolicyScopeId,
            allowOfflineDraft: true,
          )) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (!mounted) return;
      if (_newerVersion ||
          _sharedWriteUnavailable ||
          widget.updates?.isCurrent?.call() == false) {
        setState(() {
          _busy = false;
          _failure = context.l10n.organizerDraftReviewStale;
        });
        return;
      }
      await widget.onSave(draft);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      final accepted =
          mounted && await resolveSharedPolicyError(context, error);
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = accepted
              ? context.l10n.moderationPolicySaveAgain
              : widget.errorMessage?.call(error) ??
                    organizerErrorMessage(context, error);
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_busy || _sharedWriteUnavailable) return;
    if (widget.onDeleteWithReview != null) {
      setState(() => _busy = true);
      try {
        final deleted = await widget.onDeleteWithReview!();
        if (mounted && deleted) Navigator.pop(context);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
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
    if (confirmed != true || !mounted || _sharedWriteUnavailable) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      final accepted =
          mounted && await resolveSharedPolicyError(context, error);
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = accepted
              ? context.l10n.moderationPolicySaveAgain
              : widget.errorMessage?.call(error) ??
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
    _edit(() => draft.date = next);
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
    // Defaults affect only a newly added cost, never a stored cost or a user's
    // explicit selection. Deferred parent choices arrive through editor updates.
    final costEditable =
        !_sharedWriteUnavailable &&
        (widget.updates?.costEditingEnabled ?? widget.costEditingEnabled) &&
        (widget.updates?.costVisible ?? true) &&
        widget.updates?.financeLoading != true &&
        widget.updates?.financeUnavailable != true;
    if (widget.kind == OrganizerEditorKind.task &&
        _mayDefaultCostAccount &&
        !_costAccountChosen &&
        costEditable &&
        draft.costEnabled &&
        draft.ledgerAccountId == null) {
      final choice = defaultTaskCostAccount(
        ownAccounts: allowedAccounts.map(
          (a) => (id: a.id, currency: a.currency, archived: a.archived),
        ),
        parentAccounts:
            (widget.updates?.financeAccountChoices ??
                    widget.financeAccountChoices)
                .entries
                .map(
                  (a) => (
                    id: a.key,
                    currency: a.value.currency,
                    archived: a.value.archived,
                  ),
                ),
        currency: draft.costCurrency,
        currencyUnchosen: !_costCurrencyChosen && draft.costAmount.isEmpty,
      );
      if (choice != null) {
        draft.ledgerAccountId = choice.id;
        draft.costCurrency = choice.currency;
      }
    }
    final finance = widget.kind == OrganizerEditorKind.finance;
    final dateRequired = widget.kind == OrganizerEditorKind.event || finance;
    final dialog = AlertDialog(
      insetPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      titlePadding: compact ? const EdgeInsets.fromLTRB(16, 16, 16, 8) : null,
      contentPadding: compact ? const EdgeInsets.fromLTRB(16, 8, 16, 12) : null,
      actionsPadding: compact ? const EdgeInsets.fromLTRB(12, 0, 12, 12) : null,
      title: EditorHeading(
        title: widget.heading,
        onReport: _sharedWriteUnavailable ? null : widget.onReport,
        busy: _busy,
        style: compact
            ? Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)
            : null,
      ),
      content: SizedBox(
        width: widget.embedded ? double.infinity : 440,
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
            onChanged: () => _dirty = true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_localDraftContinuation)
                  Padding(
                    key: const ValueKey('organizer-local-draft-only'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(l.organizerDraftSharingUnavailable),
                    ),
                  ),
                if (_readOnly)
                  Padding(
                    key: const ValueKey('organizer-record-read-only'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(l.recordEditForbidden),
                    ),
                  ),
                if (_newerVersion)
                  Padding(
                    key: const ValueKey('organizer-newer-version'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.organizerNewerVersion,
                          semanticsLabel: l.organizerNewerVersion,
                        ),
                        if (widget.kind == OrganizerEditorKind.task)
                          TextButton(
                            key: const ValueKey('organizer-review-latest'),
                            onPressed: _busy || _sharedWriteUnavailable
                                ? null
                                : _reviewLatestTask,
                            child: Text(l.organizerReviewLatest),
                          ),
                      ],
                    ),
                  ),
                TextFormField(
                  key: const ValueKey('organizer-title-field'),
                  readOnly: _readOnly,
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
                if (widget.kind == OrganizerEditorKind.task &&
                    widget.recordId != null)
                  CheckboxListTile(
                    key: const ValueKey('organizer-task-completed'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.organizerCompleted),
                    value: draft.isCompleted,
                    onChanged: _busy || _readOnly
                        ? null
                        : (value) => _edit(() => draft.isCompleted = value!),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                if (_hasNotes) ...[
                  SizedBox(height: fieldGap),
                  TextFormField(
                    key: const ValueKey('organizer-notes-field'),
                    readOnly: _readOnly,
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
                if (widget.kind == OrganizerEditorKind.project &&
                    widget.projectContext != null) ...[
                  SizedBox(height: fieldGap),
                  Text(
                    widget.projectContext!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (widget.kind == OrganizerEditorKind.project &&
                    widget.onShare != null) ...[
                  SizedBox(height: fieldGap),
                  OutlinedButton.icon(
                    key: const ValueKey('project-editor-sharing'),
                    onPressed: _busy ? null : widget.onShare,
                    icon: const Icon(Icons.people_outline),
                    label: Text(widget.shareActionLabel ?? l.sharingMembers),
                  ),
                ],
                if (widget.kind == OrganizerEditorKind.project &&
                    widget.projectAreaEnabled) ...[
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
                    key: const ValueKey('organizer-project-field'),
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
                    onChanged: _busy || _readOnly
                        ? null
                        : (v) => _edit(() {
                            draft.projectId = v == '' ? null : v;
                            draft.phaseId = null;
                            draft.assigneePersonId = null;
                            draft.subjectPersonIds = [];
                            if (widget.updates?.costEditingEnabled ??
                                widget.costEditingEnabled) {
                              draft.ledgerAccountId = null;
                              draft.payerPersonId = null;
                              draft.recipientPersonId = null;
                            }
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
                        _edit(() => draft.startAt = value),
                    onEndChanged: (value) => _edit(() => draft.endAt = value),
                    people: widget.people,
                    assigneeIds: draft.assigneeIds,
                    onAssigneesChanged:
                        widget.assignmentEnabled &&
                            (widget.kind == OrganizerEditorKind.task ||
                                widget.kind == OrganizerEditorKind.event)
                        ? (ids) => _edit(() => draft.assigneeIds = ids)
                        : null,
                    creatorLabel: widget.creatorLabel,
                    enabled: !_busy && !_readOnly,
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
                    financeAccountChoices:
                        widget.updates?.financeAccountChoices ??
                        widget.financeAccountChoices,
                    costEditingEnabled:
                        !_sharedWriteUnavailable &&
                        (widget.updates?.costEditingEnabled ??
                            widget.costEditingEnabled),
                    costVisible: widget.updates?.costVisible ?? true,
                    onCostSectionOpened: _busy || _sharedWriteUnavailable
                        ? null
                        : widget.updates?.onCostSectionOpened,
                    onCostAccountChanged: () => _costAccountChosen = true,
                    onCostCurrencyChanged: () {
                      _costCurrencyChosen = true;
                      _costAccountChosen = false;
                    },
                    costAccountRequired: widget.costAccountRequired,
                    enabled: !_busy && !_readOnly,
                    wrap: widget.wrap,
                    onChanged: () => _edit(() {}),
                  ),
                if (widget.kind == OrganizerEditorKind.task &&
                    widget.updates?.financeLoading == true)
                  Padding(
                    key: const ValueKey('organizer-finance-loading'),
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(l.organizerFinanceChoicesLoading),
                  ),
                if (widget.kind == OrganizerEditorKind.task &&
                    widget.updates?.financeUnavailable == true)
                  Padding(
                    key: const ValueKey('organizer-finance-unavailable'),
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(l.organizerFinanceChoicesUnavailable),
                  ),
                if (widget.kind == OrganizerEditorKind.task &&
                    widget.onTimerToggle != null)
                  TaskTimerPanel(
                    timer: draft.timer,
                    estimateMinutes: draft.estimateMinutes,
                    onToggle: _busy || _sharedWriteUnavailable
                        ? null
                        : () async {
                            if (_sharedWriteUnavailable) return;
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
                    enabled: !_busy && !_readOnly,
                    wrap: widget.wrap,
                    onChanged: (date) => _edit(() => draft.date = date),
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
                      onPressed: _busy || _readOnly
                          ? null
                          : () => _edit(() => draft.date = null),
                      child: Text(l.organizerRemoveDate),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_failure != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Text(
                    _failure!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            EditorActionsRow(
              saveKey: const ValueKey('organizer-save'),
              busy: _busy,
              onCancel: () => Navigator.pop(context),
              onSave: _save,
              saveEnabled: !_sharedWriteUnavailable,
              onDelete:
                  _sharedWriteUnavailable ||
                      widget.onDelete == null &&
                          widget.onDeleteWithReview == null
                  ? null
                  : _delete,
            ),
          ],
        ),
      ],
    );
    if (!widget.embedded) return dialog;
    return OrganizerDesktopEditorSurface(dialog: dialog);
  }
}
