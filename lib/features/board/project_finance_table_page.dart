import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../kanboard/kanboard_api.dart';
import '../../l10n/l10n.dart';
import '../../models/finance_models.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';
import 'finance/finance_projection.dart';

class ProjectFinanceTablePage extends ConsumerStatefulWidget {
  const ProjectFinanceTablePage({
    required this.projectId,
    required this.projectName,
    this.projectColorHex,
    super.key,
  });

  final int projectId;
  final String projectName;
  final String? projectColorHex;

  @override
  ConsumerState<ProjectFinanceTablePage> createState() =>
      _ProjectFinanceTablePageState();
}

class _ProjectFinanceTablePageState
    extends ConsumerState<ProjectFinanceTablePage> {
  final _currentBalanceController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  String? _validationError;
  String? _currentUserContributorId;
  Timer? _autoSaveTimer;
  int _changeVersion = 0;
  int _savedChangeVersion = 0;
  bool _allowPop = false;

  int _horizonMonths = 12;
  bool _showPastMonths = false;
  bool _includeSpentExternalExpensesInProjection = false;
  String _projectCurrencyCode = 'EUR';
  FinanceTableData _data = FinanceTableData.empty();
  List<_ExternalTaskExpenseRow> _externalTaskExpenses =
      const <_ExternalTaskExpenseRow>[];

  bool get _hasUnsavedChanges => _changeVersion > _savedChangeVersion;

  @override
  void initState() {
    super.initState();
    _currentBalanceController.text = '0.00';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _currentBalanceController.dispose();
    super.dispose();
  }

  Color _projectAccent(ThemeData theme) {
    return _parseHexColor(widget.projectColorHex) ?? theme.colorScheme.primary;
  }

  Color? _parseHexColor(String? value) {
    final normalized = _normalizeColorHex(value);
    if (normalized == null) return null;
    return Color(int.parse('FF${normalized.substring(1)}', radix: 16));
  }

  String? _normalizeColorHex(String? value) {
    if (value == null) return null;
    final text = value.trim().toUpperCase();
    if (text.isEmpty) return null;
    final withHash = text.startsWith('#') ? text : '#$text';
    final hex = withHash.substring(1);
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(hex)) return null;
    return '#$hex';
  }

  Future<void> _loadData() async {
    final api = ref.read(kanboardApiProvider);
    final session = ref.read(sessionCredentialsProvider);
    if (api == null) {
      setState(() {
        _error = context.l10n.noActiveSessionConnectFirst;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _validationError = null;
    });

    try {
      final rawFinanceFuture = api.getProjectFinanceTableRaw(widget.projectId);
      final projectUsersFuture = api.getProjectUsers(widget.projectId);
      final defaultCurrencyFuture = api.getProjectExpenseCurrency(
        widget.projectId,
      );
      final meFuture = api.getMe();

      final rawFinance = await rawFinanceFuture;
      final sharedUsers = await projectUsersFuture;
      final defaultCurrency = await defaultCurrencyFuture;
      KanboardUser? me;
      try {
        me = await meFuture;
      } catch (_) {
        me = null;
      }

      FinanceTableData parsed = FinanceTableData.empty();
      if (rawFinance != null && rawFinance.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawFinance);
          if (decoded is Map<String, dynamic>) {
            parsed = FinanceTableData.fromJson(decoded);
          } else if (decoded is Map) {
            parsed = FinanceTableData.fromJson(
              Map<String, dynamic>.from(decoded),
            );
          }
        } catch (_) {
          parsed = FinanceTableData.empty();
        }
      }

      final needsAllUsersLookup = parsed.contributors.any(
        (entry) => entry.id.trim().startsWith('username:'),
      );
      List<KanboardUserReference> allUsers = const <KanboardUserReference>[];
      if (needsAllUsersLookup) {
        try {
          allUsers = await api.getAllUsers();
        } catch (_) {
          allUsers = const <KanboardUserReference>[];
        }
      }

      final mergedContributors = _mergeContributors(
        existing: parsed.contributors,
        sharedUsers: sharedUsers,
        allUsers: allUsers,
        sessionUsername: session?.username,
        meUserId: me?.id,
        meUsername: me?.username,
        meDisplayName: me?.name,
      );
      final normalizedMonths = _ensureMonths(
        existing: parsed.months,
        contributorIds: mergedContributors.contributors
            .map((e) => e.id)
            .toList(),
        idAliases: mergedContributors.idAliases,
      );
      final projectCurrency = (defaultCurrency ?? '').trim().toUpperCase();
      final parsedCurrency = parsed.currencyCode.trim().toUpperCase();
      final currency = RegExp(r'^[A-Z]{3}$').hasMatch(projectCurrency)
          ? projectCurrency
          : (RegExp(r'^[A-Z]{3}$').hasMatch(parsedCurrency)
                ? parsedCurrency
                : 'EUR');
      final normalized = parsed.copyWith(
        schemaVersion: FinanceTableData.currentSchemaVersion,
        currencyCode: currency.toUpperCase(),
        contributors: mergedContributors.contributors,
        months: normalizedMonths,
      );
      final externalTaskExpenses = await _loadExternalTaskExpenses(
        api: api,
        contributors: normalized.contributors,
      );

      if (!mounted) return;
      setState(() {
        _data = normalized;
        _externalTaskExpenses = externalTaskExpenses;
        _projectCurrencyCode = normalized.currencyCode;
        _currentBalanceController.text = (normalized.currentBalanceCents / 100)
            .toStringAsFixed(2);
        _currentUserContributorId = _resolveCurrentUserContributorId(
          contributors: normalized.contributors,
          meUserId: me?.id,
          meUsername: me?.username,
          sessionUsername: session?.username,
        );
        _changeVersion = 0;
        _savedChangeVersion = 0;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  _ContributorMergeResult _mergeContributors({
    required List<FinanceContributor> existing,
    required List<dynamic> sharedUsers,
    required List<KanboardUserReference> allUsers,
    required String? sessionUsername,
    required int? meUserId,
    required String? meUsername,
    required String? meDisplayName,
  }) {
    final allUsersByUsername = <String, KanboardUserReference>{};
    for (final user in allUsers) {
      final userId = user.id;
      final username = user.username.trim();
      if (userId <= 0 || username.isEmpty) continue;
      allUsersByUsername[username.toLowerCase()] = user;
    }

    final usernameToUserContributorId = <String, String>{};
    final userContributorNames = <String, String>{};
    for (final user in allUsers) {
      final userId = user.id;
      final username = user.username.trim();
      if (userId <= 0 || username.isEmpty) continue;
      final contributorId = 'user:$userId';
      usernameToUserContributorId.putIfAbsent(
        username.toLowerCase(),
        () => contributorId,
      );
      userContributorNames.putIfAbsent(
        contributorId,
        () => user.displayName.trim().isEmpty ? username : user.displayName,
      );
    }
    for (final user in sharedUsers) {
      final username = (user.username ?? '').toString().trim();
      var userId = user.userId ?? 0;
      if (userId <= 0 && username.isNotEmpty) {
        userId = allUsersByUsername[username.toLowerCase()]?.id ?? 0;
      }
      final displayName = (user.displayName ?? '').toString().trim();
      if (userId <= 0 || username.isEmpty) continue;
      final contributorId = 'user:$userId';
      usernameToUserContributorId[username.toLowerCase()] = contributorId;
      userContributorNames[contributorId] = displayName.isNotEmpty
          ? displayName
          : (allUsersByUsername[username.toLowerCase()]?.displayName
                        .trim()
                        .isNotEmpty ==
                    true
                ? allUsersByUsername[username.toLowerCase()]!.displayName
                : username);
    }
    final normalizedMeUsername = (meUsername ?? '').trim();
    if ((meUserId ?? 0) > 0 && normalizedMeUsername.isNotEmpty) {
      final meContributorId = 'user:$meUserId';
      usernameToUserContributorId[normalizedMeUsername.toLowerCase()] =
          meContributorId;
      final normalizedMeDisplayName = (meDisplayName ?? '').trim();
      userContributorNames[meContributorId] = normalizedMeDisplayName.isNotEmpty
          ? normalizedMeDisplayName
          : normalizedMeUsername;
    }

    final merged = <String, FinanceContributor>{
      for (final contributor in existing)
        if (contributor.id.trim().isNotEmpty)
          contributor.id: FinanceContributor(
            id: contributor.id.trim(),
            name: contributor.name,
          ),
    };
    final idAliases = <String, String>{};

    for (final contributor in existing) {
      final id = contributor.id.trim();
      if (!id.startsWith('username:')) continue;
      final username = id.substring('username:'.length).trim().toLowerCase();
      final mappedUserId = usernameToUserContributorId[username];
      if (mappedUserId == null) continue;

      idAliases[id] = mappedUserId;
      merged.remove(id);
      merged[mappedUserId] = FinanceContributor(
        id: mappedUserId,
        name: userContributorNames[mappedUserId] ?? contributor.name,
      );
    }

    for (final user in sharedUsers) {
      final id = user.userId ?? 0;
      final username = (user.username ?? '').toString().trim();
      final name = (user.displayName ?? '').toString().trim();
      if (id <= 0 || username.isEmpty) continue;
      final contributorId = 'user:$id';
      merged[contributorId] = FinanceContributor(
        id: contributorId,
        name: name.isNotEmpty ? name : username,
      );
    }

    final normalizedSession = (sessionUsername ?? '').trim();
    if (normalizedSession.isNotEmpty) {
      final sessionKey = normalizedSession.toLowerCase();
      final alreadyMappedUserId = usernameToUserContributorId[sessionKey];
      final alreadyIncluded =
          (alreadyMappedUserId != null &&
              merged.containsKey(alreadyMappedUserId)) ||
          merged.containsKey('username:$sessionKey') ||
          merged.values.any(
            (entry) =>
                entry.name.toLowerCase() == normalizedSession.toLowerCase(),
          );
      if (!alreadyIncluded) {
        merged['username:$sessionKey'] = FinanceContributor(
          id: 'username:$sessionKey',
          name: normalizedSession,
        );
      }
    }

    if (merged.isEmpty) {
      merged['self'] = FinanceContributor(
        id: 'self',
        name: context.l10n.financeContributorMe,
      );
    }

    final list = merged.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return _ContributorMergeResult(contributors: list, idAliases: idAliases);
  }

  List<FinanceMonthEntry> _ensureMonths({
    required List<FinanceMonthEntry> existing,
    required List<String> contributorIds,
    Map<String, String> idAliases = const <String, String>{},
    int count = 12,
  }) {
    final monthMap = <String, FinanceMonthEntry>{};
    for (final row in existing) {
      if (!_isValidMonthKey(row.monthKey)) continue;
      final normalizedSource = <String, int>{};
      row.incomesByContributorCents.forEach((id, amount) {
        final mappedId = idAliases[id] ?? id;
        normalizedSource[mappedId] = (normalizedSource[mappedId] ?? 0) + amount;
      });
      monthMap[row.monthKey] = FinanceMonthEntry(
        monthKey: row.monthKey,
        incomesByContributorCents: <String, int>{
          for (final id in contributorIds) id: normalizedSource[id] ?? 0,
        },
      );
    }

    final now = DateTime.now();
    for (var i = 0; i < count; i++) {
      final date = DateTime(now.year, now.month + i);
      final monthKey = _monthKeyForDate(date);
      monthMap.putIfAbsent(
        monthKey,
        () => FinanceMonthEntry(
          monthKey: monthKey,
          incomesByContributorCents: <String, int>{
            for (final id in contributorIds) id: 0,
          },
        ),
      );
    }

    final rows = monthMap.values.toList()
      ..sort((a, b) => a.monthKey.compareTo(b.monthKey));
    return rows;
  }

  int? _parseMoneyToCents(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null) return null;
    return (parsed * 100).round();
  }

  String _formatCents(int cents) {
    return (cents / 100).toStringAsFixed(2);
  }

  String _formatMoney(int cents) {
    final normalized =
        RegExp(
          r'^[A-Z]{3}$',
        ).hasMatch(_projectCurrencyCode.trim().toUpperCase())
        ? _projectCurrencyCode.trim().toUpperCase()
        : 'EUR';
    return '$normalized ${_formatCents(cents)}';
  }

  void _markDirtyAndScheduleAutoSave() {
    final hadUnsavedChanges = _hasUnsavedChanges;
    _changeVersion += 1;
    if (!hadUnsavedChanges && mounted) {
      setState(() {});
    }
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 900), () async {
      if (!mounted || !_hasUnsavedChanges) return;
      if (_isLoading || _isSaving) {
        _scheduleAutoSave();
        return;
      }
      await _save(showFeedback: false, reloadAfterSave: false);
    });
  }

  Future<bool> _confirmLeaveWithUnsavedChanges() async {
    final l10n = context.l10n;
    final result = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(l10n.unsavedFinanceChangesTitle),
        content: Text(l10n.unsavedFinanceChangesMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.leaveWithoutSaving),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    _autoSaveTimer?.cancel();
    await _save(showFeedback: false, reloadAfterSave: false);
    if (!_hasUnsavedChanges) return true;
    if (!mounted) return false;
    return _confirmLeaveWithUnsavedChanges();
  }

  void _onPopInvokedWithResult(bool didPop, Object? result) async {
    if (didPop) return;
    final shouldPop = await _onWillPop();
    if (!shouldPop || !mounted) return;
    setState(() {
      _allowPop = true;
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    Navigator.of(context).pop(result);
    if (mounted) {
      setState(() {
        _allowPop = false;
      });
    }
  }

  Future<bool> _save({
    bool showFeedback = true,
    bool reloadAfterSave = true,
  }) async {
    if (_isSaving) return false;
    final api = ref.read(kanboardApiProvider);
    if (api == null) return false;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final saveVersion = _changeVersion;

    final rawBalance = _currentBalanceController.text.trim();
    final balanceCents = rawBalance.isEmpty
        ? _data.currentBalanceCents
        : _parseMoneyToCents(rawBalance);
    if (balanceCents == null) {
      setState(() {
        _validationError = l10n.currentBalanceMustBeValidNumber;
      });
      return false;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });

    try {
      final projectCurrencyRaw =
          (await api.getProjectExpenseCurrency(widget.projectId) ?? '')
              .trim()
              .toUpperCase();
      final currency = RegExp(r'^[A-Z]{3}$').hasMatch(projectCurrencyRaw)
          ? projectCurrencyRaw
          : _projectCurrencyCode;
      final toSave = _data.copyWith(
        schemaVersion: FinanceTableData.currentSchemaVersion,
        currencyCode: currency,
        currentBalanceCents: balanceCents,
      );
      final saved = await api.saveProjectFinanceTableData(
        projectId: widget.projectId,
        data: toSave.toJson(),
      );
      if (!saved) {
        throw StateError(l10n.serverRejectedFinanceTableSave);
      }
      if (!mounted) return false;
      setState(() {
        _data = toSave;
        _projectCurrencyCode = currency;
        if (saveVersion > _savedChangeVersion) {
          _savedChangeVersion = saveVersion;
        }
      });
      if (showFeedback) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.financeTableSaved)));
      }
      if (reloadAfterSave) {
        await _loadData();
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      if (showFeedback) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.financeTableSaveFailed('$error'))),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _upsertRecurring({RecurringExpense? existing}) async {
    final l10n = context.l10n;
    final categoryController = TextEditingController(
      text: existing?.category ?? '',
    );
    final amountController = TextEditingController(
      text: existing == null ? '' : _formatCents(existing.amountCents),
    );
    final monthOptions = _monthOptionsWith(existing?.startMonthKey);
    for (final month in _monthOptionsWith(existing?.endMonthKey)) {
      if (!monthOptions.contains(month)) monthOptions.add(month);
    }
    monthOptions.sort();
    var selectedStartMonth = existing?.startMonthKey ?? _defaultMonthKey();
    String? selectedEndMonth = existing?.endMonthKey;
    String? selectedContributorId =
        existing?.contributorId ?? _defaultContributorIdForDialogs();
    var enabled = existing?.enabled ?? true;

    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog.adaptive(
          title: Text(
            existing == null
                ? context.l10n.addRecurringExpense
                : context.l10n.editRecurringExpense,
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<String?>(
                  initialValue: selectedContributorId,
                  decoration: InputDecoration(
                    labelText: context.l10n.contributorOptional,
                  ),
                  items: <DropdownMenuItem<String?>>[
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(context.l10n.otherExpense),
                    ),
                    ..._data.contributors.map(
                      (contributor) => DropdownMenuItem<String?>(
                        value: contributor.id,
                        child: Text(contributor.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setLocalState(() {
                      selectedContributorId = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: categoryController,
                  decoration: InputDecoration(labelText: context.l10n.category),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10n.monthlyAmount,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedStartMonth,
                  decoration: InputDecoration(
                    labelText: context.l10n.startMonthYYYYMM,
                  ),
                  items: monthOptions
                      .map(
                        (month) => DropdownMenuItem<String>(
                          value: month,
                          child: Text(month),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setLocalState(() {
                      selectedStartMonth = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: selectedEndMonth,
                  decoration: InputDecoration(
                    labelText: context.l10n.endMonthOptionalYYYYMM,
                  ),
                  items: <DropdownMenuItem<String?>>[
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(context.l10n.ongoing),
                    ),
                    ...monthOptions.map(
                      (month) => DropdownMenuItem<String?>(
                        value: month,
                        child: Text(month),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setLocalState(() {
                      selectedEndMonth = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  title: Text(context.l10n.enabled),
                  value: enabled,
                  onChanged: (value) => setLocalState(() => enabled = value),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final amount = _parseMoneyToCents(amountController.text);
    final category = categoryController.text.trim();
    final startMonth = selectedStartMonth.trim();
    final endMonth = (selectedEndMonth ?? '').trim();
    if (amount == null ||
        amount < 0 ||
        category.isEmpty ||
        !_isValidMonthKey(startMonth) ||
        (endMonth.isNotEmpty && !_isValidMonthKey(endMonth))) {
      setState(() {
        _validationError = l10n.recurringExpenseFieldsNotValid;
      });
      return;
    }

    final nextItem = RecurringExpense(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      category: category,
      amountCents: amount,
      startMonthKey: startMonth,
      endMonthKey: endMonth.isEmpty ? null : endMonth,
      contributorId: selectedContributorId,
      enabled: enabled,
    );
    final next = List<RecurringExpense>.from(_data.recurringExpenses);
    final index = next.indexWhere((item) => item.id == nextItem.id);
    if (index >= 0) {
      next[index] = nextItem;
    } else {
      next.add(nextItem);
    }
    setState(() {
      _data = _data.copyWith(recurringExpenses: next);
      _validationError = null;
    });
    _markDirtyAndScheduleAutoSave();
  }

  Future<void> _upsertPlanned({PlannedExpense? existing}) async {
    final l10n = context.l10n;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final categoryController = TextEditingController(
      text: existing?.category ?? '',
    );
    final amountController = TextEditingController(
      text: existing == null ? '' : _formatCents(existing.amountCents),
    );
    final monthOptions = _monthOptionsWith(existing?.monthKey);
    var selectedMonthKey = existing?.monthKey ?? _defaultMonthKey();
    String? selectedContributorId =
        existing?.contributorId ?? _defaultContributorIdForDialogs();

    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(
          existing == null
              ? context.l10n.addPlannedExpense
              : context.l10n.editPlannedExpense,
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String?>(
                initialValue: selectedContributorId,
                decoration: InputDecoration(
                  labelText: context.l10n.contributorOptional,
                ),
                items: <DropdownMenuItem<String?>>[
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.l10n.otherExpense),
                  ),
                  ..._data.contributors.map(
                    (contributor) => DropdownMenuItem<String?>(
                      value: contributor.id,
                      child: Text(contributor.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  selectedContributorId = value;
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: context.l10n.title),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: categoryController,
                decoration: InputDecoration(labelText: context.l10n.category),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: context.l10n.amount),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedMonthKey,
                decoration: InputDecoration(
                  labelText: context.l10n.monthYYYYMM,
                ),
                items: monthOptions
                    .map(
                      (month) => DropdownMenuItem<String>(
                        value: month,
                        child: Text(month),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  selectedMonthKey = value;
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final title = titleController.text.trim();
    final category = categoryController.text.trim();
    final monthKey = selectedMonthKey.trim();
    final amount = _parseMoneyToCents(amountController.text);
    if (title.isEmpty ||
        category.isEmpty ||
        amount == null ||
        !_isValidMonthKey(monthKey)) {
      setState(() {
        _validationError = l10n.plannedExpenseFieldsNotValid;
      });
      return;
    }

    final nextItem = PlannedExpense(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      category: category,
      amountCents: amount,
      monthKey: monthKey,
      contributorId: selectedContributorId,
    );
    final next = List<PlannedExpense>.from(_data.plannedExpenses);
    final index = next.indexWhere((item) => item.id == nextItem.id);
    if (index >= 0) {
      next[index] = nextItem;
    } else {
      next.add(nextItem);
    }
    setState(() {
      _data = _data.copyWith(plannedExpenses: next);
      _validationError = null;
    });
    _markDirtyAndScheduleAutoSave();
  }

  Future<void> _upsertRecurringIncome({RecurringIncome? existing}) async {
    final l10n = context.l10n;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final amountController = TextEditingController(
      text: existing == null ? '' : _formatCents(existing.amountCents),
    );
    final monthOptions = _monthOptionsWith(existing?.startMonthKey);
    for (final month in _monthOptionsWith(existing?.endMonthKey)) {
      if (!monthOptions.contains(month)) monthOptions.add(month);
    }
    monthOptions.sort();
    var selectedStartMonth = existing?.startMonthKey ?? _defaultMonthKey();
    String? selectedEndMonth = existing?.endMonthKey;
    String? selectedContributorId =
        existing?.contributorId ?? _defaultContributorIdForDialogs();
    var enabled = existing?.enabled ?? true;

    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog.adaptive(
          title: Text(
            existing == null
                ? context.l10n.addRecurringIncome
                : context.l10n.editRecurringIncome,
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<String?>(
                  initialValue: selectedContributorId,
                  decoration: InputDecoration(
                    labelText: context.l10n.contributorOptional,
                  ),
                  items: <DropdownMenuItem<String?>>[
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(context.l10n.otherIncome),
                    ),
                    ..._data.contributors.map(
                      (contributor) => DropdownMenuItem<String?>(
                        value: contributor.id,
                        child: Text(contributor.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setLocalState(() {
                      selectedContributorId = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(labelText: context.l10n.source),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10n.monthlyAmount,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedStartMonth,
                  decoration: InputDecoration(
                    labelText: context.l10n.startMonthYYYYMM,
                  ),
                  items: monthOptions
                      .map(
                        (month) => DropdownMenuItem<String>(
                          value: month,
                          child: Text(month),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setLocalState(() {
                      selectedStartMonth = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: selectedEndMonth,
                  decoration: InputDecoration(
                    labelText: context.l10n.endMonthOptionalYYYYMM,
                  ),
                  items: <DropdownMenuItem<String?>>[
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(context.l10n.ongoing),
                    ),
                    ...monthOptions.map(
                      (month) => DropdownMenuItem<String?>(
                        value: month,
                        child: Text(month),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setLocalState(() {
                      selectedEndMonth = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  title: Text(context.l10n.enabled),
                  value: enabled,
                  onChanged: (value) => setLocalState(() => enabled = value),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final amount = _parseMoneyToCents(amountController.text);
    final title = titleController.text.trim();
    final startMonth = selectedStartMonth.trim();
    final endMonth = (selectedEndMonth ?? '').trim();
    final resolvedTitle = title.isNotEmpty
        ? title
        : _contributorName(selectedContributorId) ?? l10n.otherIncome;
    if (amount == null ||
        amount < 0 ||
        resolvedTitle.isEmpty ||
        !_isValidMonthKey(startMonth) ||
        (endMonth.isNotEmpty && !_isValidMonthKey(endMonth))) {
      setState(() {
        _validationError = l10n.recurringIncomeFieldsNotValid;
      });
      return;
    }

    final nextItem = RecurringIncome(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: resolvedTitle,
      amountCents: amount,
      startMonthKey: startMonth,
      endMonthKey: endMonth.isEmpty ? null : endMonth,
      contributorId: selectedContributorId,
      enabled: enabled,
    );
    final next = List<RecurringIncome>.from(_data.recurringIncomes);
    final index = next.indexWhere((item) => item.id == nextItem.id);
    if (index >= 0) {
      next[index] = nextItem;
    } else {
      next.add(nextItem);
    }
    setState(() {
      _data = _data.copyWith(recurringIncomes: next);
      _validationError = null;
    });
    _markDirtyAndScheduleAutoSave();
  }

  Future<void> _upsertPlannedIncome({PlannedIncome? existing}) async {
    final l10n = context.l10n;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final amountController = TextEditingController(
      text: existing == null ? '' : _formatCents(existing.amountCents),
    );
    final monthOptions = _monthOptionsWith(existing?.monthKey);
    var selectedMonthKey = existing?.monthKey ?? _defaultMonthKey();
    String? selectedContributorId =
        existing?.contributorId ?? _defaultContributorIdForDialogs();

    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(
          existing == null
              ? context.l10n.addPlannedIncome
              : context.l10n.editPlannedIncome,
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String?>(
                initialValue: selectedContributorId,
                decoration: InputDecoration(
                  labelText: context.l10n.contributorOptional,
                ),
                items: <DropdownMenuItem<String?>>[
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.l10n.otherIncome),
                  ),
                  ..._data.contributors.map(
                    (contributor) => DropdownMenuItem<String?>(
                      value: contributor.id,
                      child: Text(contributor.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  selectedContributorId = value;
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: context.l10n.source),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: context.l10n.amount),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedMonthKey,
                decoration: InputDecoration(
                  labelText: context.l10n.monthYYYYMM,
                ),
                items: monthOptions
                    .map(
                      (month) => DropdownMenuItem<String>(
                        value: month,
                        child: Text(month),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  selectedMonthKey = value;
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final title = titleController.text.trim();
    final monthKey = selectedMonthKey.trim();
    final amount = _parseMoneyToCents(amountController.text);
    if (title.isEmpty || amount == null || !_isValidMonthKey(monthKey)) {
      setState(() {
        _validationError = l10n.plannedIncomeFieldsNotValid;
      });
      return;
    }

    final nextItem = PlannedIncome(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      amountCents: amount,
      monthKey: monthKey,
      contributorId: selectedContributorId,
    );
    final next = List<PlannedIncome>.from(_data.plannedIncomes);
    final index = next.indexWhere((item) => item.id == nextItem.id);
    if (index >= 0) {
      next[index] = nextItem;
    } else {
      next.add(nextItem);
    }
    setState(() {
      _data = _data.copyWith(plannedIncomes: next);
      _validationError = null;
    });
    _markDirtyAndScheduleAutoSave();
  }

  void _removeRecurringIncome(String id) {
    setState(() {
      _data = _data.copyWith(
        recurringIncomes: _data.recurringIncomes
            .where((item) => item.id != id)
            .toList(),
      );
    });
    _markDirtyAndScheduleAutoSave();
  }

  void _removePlannedIncome(String id) {
    setState(() {
      _data = _data.copyWith(
        plannedIncomes: _data.plannedIncomes
            .where((item) => item.id != id)
            .toList(),
      );
    });
    _markDirtyAndScheduleAutoSave();
  }

  void _removeRecurring(String id) {
    setState(() {
      _data = _data.copyWith(
        recurringExpenses: _data.recurringExpenses
            .where((item) => item.id != id)
            .toList(),
      );
    });
    _markDirtyAndScheduleAutoSave();
  }

  void _removePlanned(String id) {
    setState(() {
      _data = _data.copyWith(
        plannedExpenses: _data.plannedExpenses
            .where((item) => item.id != id)
            .toList(),
      );
    });
    _markDirtyAndScheduleAutoSave();
  }

  bool _isValidMonthKey(String monthKey) {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(monthKey)) return false;
    final month = int.tryParse(monthKey.substring(5));
    return month != null && month >= 1 && month <= 12;
  }

  String _defaultMonthKey() {
    return _monthKeyForDate(DateTime.now());
  }

  String _monthKeyForDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  String _monthKeyFromTaskDateRaw(String? raw) {
    final fallback = _monthKeyForDate(DateTime.now());
    final text = (raw ?? '').trim();
    if (text.isEmpty || text == '0') return fallback;
    final unix = int.tryParse(text);
    if (unix != null && unix > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(unix * 1000).toLocal();
      return _monthKeyForDate(date);
    }
    final normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return fallback;
    return _monthKeyForDate(parsed.toLocal());
  }

  List<String> _monthOptionsWith(String? include) {
    final now = DateTime.now();
    final options = <String>[];
    var monthsForward = _horizonMonths;
    if (monthsForward < 6) monthsForward = 6;
    if (monthsForward > 24) monthsForward = 24;
    for (var i = 0; i < monthsForward; i++) {
      final date = DateTime(now.year, now.month + i);
      options.add('${date.year}-${date.month.toString().padLeft(2, '0')}');
    }
    final normalizedInclude = (include ?? '').trim();
    if (_isValidMonthKey(normalizedInclude) &&
        !options.contains(normalizedInclude)) {
      options.add(normalizedInclude);
      options.sort();
    }
    return options;
  }

  String? _contributorName(String? contributorId) {
    if (contributorId == null || contributorId.trim().isEmpty) return null;
    for (final contributor in _data.contributors) {
      if (contributor.id == contributorId) return contributor.name;
    }
    return null;
  }

  String? _defaultContributorIdForDialogs() {
    if (_currentUserContributorId != null &&
        _currentUserContributorId!.trim().isNotEmpty) {
      return _currentUserContributorId;
    }
    if (_data.contributors.isNotEmpty) return _data.contributors.first.id;
    return null;
  }

  String? _resolveCurrentUserContributorId({
    required List<FinanceContributor> contributors,
    required int? meUserId,
    required String? meUsername,
    required String? sessionUsername,
  }) {
    if ((meUserId ?? 0) > 0) {
      final candidate = 'user:$meUserId';
      if (contributors.any((entry) => entry.id == candidate)) return candidate;
    }
    final meUsernameNormalized = (meUsername ?? '').trim().toLowerCase();
    if (meUsernameNormalized.isNotEmpty) {
      final candidate = 'username:$meUsernameNormalized';
      if (contributors.any((entry) => entry.id == candidate)) return candidate;
    }
    final sessionNormalized = (sessionUsername ?? '').trim().toLowerCase();
    if (sessionNormalized.isNotEmpty) {
      final candidate = 'username:$sessionNormalized';
      if (contributors.any((entry) => entry.id == candidate)) return candidate;
    }
    return null;
  }

  int? _userIdFromContributorId(String contributorId) {
    if (!contributorId.startsWith('user:')) return null;
    return int.tryParse(contributorId.substring('user:'.length));
  }

  Future<List<_ExternalTaskExpenseRow>> _loadExternalTaskExpenses({
    required KanboardApi api,
    required List<FinanceContributor> contributors,
  }) async {
    final contributorNamesByUserId = <int, String>{};
    for (final contributor in contributors) {
      final userId = _userIdFromContributorId(contributor.id);
      if (userId != null && userId > 0) {
        contributorNamesByUserId[userId] = contributor.name;
      }
    }
    final unassignedContributorLabel = context.l10n.otherExpense;

    final rows = <_ExternalTaskExpenseRow>[];
    List<KanboardProject> projects;
    try {
      projects = await api.getMyProjects();
    } catch (_) {
      return const <_ExternalTaskExpenseRow>[];
    }

    final externalProjects = projects
        .where((project) => project.id != widget.projectId)
        .toList();
    await Future.wait(
      externalProjects.map((project) async {
        try {
          final board = await api.getBoard(project.id);
          for (final swimlane in board.swimlanes) {
            for (final column in swimlane.columns) {
              for (final task in column.tasks) {
                if (task.score <= 0) continue;
                final contributorName = contributorNamesByUserId[task.ownerId];
                rows.add(
                  _ExternalTaskExpenseRow(
                    projectId: project.id,
                    projectName: project.name,
                    taskId: task.id,
                    taskTitle: task.title,
                    monthKey: _monthKeyFromTaskDateRaw(task.dateDueRaw),
                    amountCents: task.score,
                    isSpent: !task.isActive,
                    contributorName:
                        contributorName ??
                        (task.ownerId > 0
                            ? 'User #${task.ownerId}'
                            : unassignedContributorLabel),
                  ),
                );
              }
            }
          }
        } catch (_) {
          // Ignore one project failing; keep partial results.
        }
      }),
    );

    rows.sort((a, b) {
      final amountCompare = b.amountCents.compareTo(a.amountCents);
      if (amountCompare != 0) return amountCompare;
      final projectCompare = a.projectName.toLowerCase().compareTo(
        b.projectName.toLowerCase(),
      );
      if (projectCompare != 0) return projectCompare;
      return a.taskId.compareTo(b.taskId);
    });
    return rows;
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
    bool emphasized = false,
  }) {
    final theme = Theme.of(context);
    final accent = _projectAccent(theme);
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasized
            ? Color.alphaBlend(
                accent.withValues(alpha: 0.22),
                theme.colorScheme.surface,
              )
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Color.alphaBlend(
            accent.withValues(alpha: emphasized ? 0.35 : 0.24),
            theme.colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsibleSectionCard({
    required String storageKey,
    required String title,
    required Widget content,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        key: PageStorageKey<String>(storageKey),
        initiallyExpanded: false,
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        children: <Widget>[
          if (action != null) ...<Widget>[
            Align(alignment: Alignment.centerRight, child: action),
            const SizedBox(height: 8),
          ],
          content,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMonthKey = _monthKeyForDate(DateTime.now());
    final months = List<FinanceMonthEntry>.from(_data.months)
      ..sort((a, b) => a.monthKey.compareTo(b.monthKey));
    final projectedMonths = months
        .where((month) => month.monthKey.compareTo(currentMonthKey) >= 0)
        .toList();
    final pastMonths = months
        .where((month) => month.monthKey.compareTo(currentMonthKey) < 0)
        .toList();
    final futureVisibleMonths = projectedMonths.take(_horizonMonths).toList();
    final visibleMonths = _showPastMonths
        ? <FinanceMonthEntry>[...pastMonths, ...futureVisibleMonths]
        : futureVisibleMonths;
    final projectionStartMonth = projectedMonths.isEmpty
        ? null
        : projectedMonths.first.monthKey;
    final externalProjectedExpenses = _externalTaskExpenses
        .where(
          (row) => _includeSpentExternalExpensesInProjection || !row.isSpent,
        )
        .where((row) => row.monthKey.compareTo(currentMonthKey) >= 0)
        .map(
          (row) => PlannedExpense(
            id: 'external:${row.projectId}:${row.taskId}',
            title: row.taskTitle,
            category: context.l10n.expensesFromOtherProjects,
            amountCents: row.amountCents,
            monthKey: row.monthKey,
          ),
        )
        .toList();
    final projectedTableData = _data.copyWith(
      months: projectedMonths,
      plannedExpenses: <PlannedExpense>[
        ..._data.plannedExpenses,
        ...externalProjectedExpenses,
      ],
    );
    final projection = buildFinanceProjection(
      tableData: projectedTableData,
      horizonMonths: _horizonMonths,
      startMonthKey: projectionStartMonth,
    );
    final projectionByMonth = <String, FinanceProjectionMonth>{
      for (final month in projection.months) month.monthKey: month,
    };
    final currentMonthProjection = projection.months.isEmpty
        ? null
        : projection.months.first;
    final summedMonthlyIncomeCents =
        currentMonthProjection?.totalIncomeCents ?? 0;
    final summedMonthlyExpenseCents =
        currentMonthProjection?.totalExpenseCents ?? 0;
    final totalBalanceCents =
        _parseMoneyToCents(_currentBalanceController.text) ??
        _data.currentBalanceCents;
    FinanceProjectionMonth? lowestMonthlyNetMonth;
    for (final month in projection.months) {
      if (lowestMonthlyNetMonth == null ||
          month.netCents < lowestMonthlyNetMonth.netCents) {
        lowestMonthlyNetMonth = month;
      }
    }

    return PopScope<Object?>(
      canPop: _allowPop || !_hasUnsavedChanges,
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.financeTable),
          actions: <Widget>[
            IconButton(
              tooltip: context.l10n.showPastMonths,
              onPressed: () {
                setState(() => _showPastMonths = !_showPastMonths);
              },
              icon: Icon(
                _showPastMonths
                    ? Icons.history_toggle_off_outlined
                    : Icons.history_outlined,
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          child: IgnorePointer(
            ignoring: _isLoading,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.projectName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(context.l10n.sharedFinanceTable),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _currentBalanceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => _markDirtyAndScheduleAutoSave(),
                          decoration: InputDecoration(
                            labelText: context.l10n.currentBalance,
                            hintText: context.l10n.amountHint,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _horizonMonths,
                          decoration: InputDecoration(
                            labelText: context.l10n.projectionHorizon,
                          ),
                          items: <DropdownMenuItem<int>>[
                            DropdownMenuItem(
                              value: 3,
                              child: Text(context.l10n.months3),
                            ),
                            DropdownMenuItem(
                              value: 6,
                              child: Text(context.l10n.months6),
                            ),
                            DropdownMenuItem(
                              value: 12,
                              child: Text(context.l10n.months12),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _horizonMonths = value);
                          },
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            context
                                .l10n
                                .includeSpentExternalExpensesInProjection,
                          ),
                          value: _includeSpentExternalExpensesInProjection,
                          onChanged: (value) {
                            setState(
                              () => _includeSpentExternalExpensesInProjection =
                                  value,
                            );
                          },
                        ),
                        if (_validationError != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            _validationError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _metricTile(
                          icon: Icons.trending_up_outlined,
                          label: context.l10n.summedMonthlyIncome,
                          value: _formatMoney(summedMonthlyIncomeCents),
                        ),
                        _metricTile(
                          icon: Icons.trending_down_outlined,
                          label: context.l10n.summedMonthlyExpenses,
                          value: _formatMoney(summedMonthlyExpenseCents),
                        ),
                        _metricTile(
                          icon: Icons.savings_outlined,
                          label: context.l10n.totalBalance,
                          value: _formatMoney(totalBalanceCents),
                          emphasized: true,
                        ),
                        _metricTile(
                          icon: Icons.event_note_outlined,
                          label: context.l10n.biggestIncomeExpenseGap,
                          value: lowestMonthlyNetMonth == null
                              ? '-'
                              : '${lowestMonthlyNetMonth.monthKey} (${_formatMoney(lowestMonthlyNetMonth.netCents)})',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.l10n.monthlyIncomesAndProjections,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (visibleMonths.isEmpty)
                          Text(
                            context.l10n.noResultsYet,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: <DataColumn>[
                                DataColumn(label: Text(context.l10n.month)),
                                DataColumn(
                                  label: Text(context.l10n.incomeTotal),
                                ),
                                DataColumn(
                                  label: Text(context.l10n.expensesTotal),
                                ),
                                DataColumn(label: Text(context.l10n.net)),
                                DataColumn(label: Text(context.l10n.closing)),
                              ],
                              rows: visibleMonths.map((month) {
                                final projectionMonth =
                                    projectionByMonth[month.monthKey];
                                return DataRow(
                                  cells: <DataCell>[
                                    DataCell(Text(month.monthKey)),
                                    DataCell(
                                      Text(
                                        _formatMoney(
                                          projectionMonth?.totalIncomeCents ??
                                              month.totalIncomeCents,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        projectionMonth == null
                                            ? '-'
                                            : _formatMoney(
                                                projectionMonth
                                                    .totalExpenseCents,
                                              ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        projectionMonth == null
                                            ? '-'
                                            : _formatMoney(
                                                projectionMonth.netCents,
                                              ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        projectionMonth == null
                                            ? '-'
                                            : _formatMoney(
                                                projectionMonth
                                                    .closingBalanceCents,
                                              ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _collapsibleSectionCard(
                  storageKey: 'finance-recurring-incomes-section',
                  title: context.l10n.recurringIncomes,
                  action: FilledButton.tonalIcon(
                    onPressed: _upsertRecurringIncome,
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.add),
                  ),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_data.recurringIncomes.isEmpty)
                        Text(context.l10n.noResultsYet)
                      else
                        for (final item in _data.recurringIncomes)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.title),
                            subtitle: Text(
                              '${item.startMonthKey} -> ${item.endMonthKey ?? context.l10n.ongoing}'
                              '${item.contributorId == null ? '' : ' · ${context.l10n.contributor}: ${_contributorName(item.contributorId) ?? item.contributorId}'}',
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: <Widget>[
                                Text(_formatMoney(item.amountCents)),
                                IconButton(
                                  tooltip: context.l10n.edit,
                                  onPressed: () =>
                                      _upsertRecurringIncome(existing: item),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: context.l10n.delete,
                                  onPressed: () =>
                                      _removeRecurringIncome(item.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _collapsibleSectionCard(
                  storageKey: 'finance-planned-incomes-section',
                  title: context.l10n.plannedIncomes,
                  action: FilledButton.tonalIcon(
                    onPressed: _upsertPlannedIncome,
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.add),
                  ),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_data.plannedIncomes.isEmpty)
                        Text(context.l10n.noResultsYet)
                      else
                        for (final item in _data.plannedIncomes)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.title),
                            subtitle: Text(
                              '${item.monthKey}'
                              '${item.contributorId == null ? '' : ' · ${context.l10n.contributor}: ${_contributorName(item.contributorId) ?? item.contributorId}'}',
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: <Widget>[
                                Text(_formatMoney(item.amountCents)),
                                IconButton(
                                  tooltip: context.l10n.edit,
                                  onPressed: () =>
                                      _upsertPlannedIncome(existing: item),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: context.l10n.delete,
                                  onPressed: () =>
                                      _removePlannedIncome(item.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _collapsibleSectionCard(
                  storageKey: 'finance-recurring-expenses-section',
                  title: context.l10n.recurringExpenses,
                  action: FilledButton.tonalIcon(
                    onPressed: _upsertRecurring,
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.add),
                  ),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_data.recurringExpenses.isEmpty)
                        Text(context.l10n.noResultsYet)
                      else
                        for (final item in _data.recurringExpenses)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.category),
                            subtitle: Text(
                              '${item.startMonthKey} -> ${item.endMonthKey ?? context.l10n.ongoing}'
                              '${item.contributorId == null ? '' : ' · ${context.l10n.contributor}: ${_contributorName(item.contributorId) ?? item.contributorId}'}',
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: <Widget>[
                                Text(_formatMoney(item.amountCents)),
                                IconButton(
                                  tooltip: context.l10n.edit,
                                  onPressed: () =>
                                      _upsertRecurring(existing: item),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: context.l10n.delete,
                                  onPressed: () => _removeRecurring(item.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _collapsibleSectionCard(
                  storageKey: 'finance-planned-expenses-section',
                  title: context.l10n.plannedExpenses,
                  action: FilledButton.tonalIcon(
                    onPressed: _upsertPlanned,
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.add),
                  ),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_data.plannedExpenses.isEmpty)
                        Text(context.l10n.noResultsYet)
                      else
                        for (final item in _data.plannedExpenses)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.title),
                            subtitle: Text(
                              '${item.monthKey} - ${item.category}'
                              '${item.contributorId == null ? '' : ' · ${context.l10n.contributor}: ${_contributorName(item.contributorId) ?? item.contributorId}'}',
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: <Widget>[
                                Text(_formatMoney(item.amountCents)),
                                IconButton(
                                  tooltip: context.l10n.edit,
                                  onPressed: () =>
                                      _upsertPlanned(existing: item),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: context.l10n.delete,
                                  onPressed: () => _removePlanned(item.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _collapsibleSectionCard(
                  storageKey: 'finance-external-expenses-section',
                  title: context.l10n.expensesFromOtherProjects,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_externalTaskExpenses.isEmpty)
                        Text(context.l10n.noResultsYet)
                      else
                        for (final row in _externalTaskExpenses)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              row.isSpent
                                  ? Icons.check_circle_outline
                                  : Icons.payments_outlined,
                            ),
                            title: Text(
                              row.taskTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${row.projectName} · ${row.monthKey} · ${row.contributorName} · ${context.l10n.taskNumber(row.taskId)} · ${row.isSpent ? context.l10n.spent : context.l10n.planned}',
                            ),
                            trailing: Text(
                              _formatMoney(row.amountCents),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                    ],
                  ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(99)),
                      child: LinearProgressIndicator(minHeight: 5),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContributorMergeResult {
  const _ContributorMergeResult({
    required this.contributors,
    required this.idAliases,
  });

  final List<FinanceContributor> contributors;
  final Map<String, String> idAliases;
}

class _ExternalTaskExpenseRow {
  const _ExternalTaskExpenseRow({
    required this.projectId,
    required this.projectName,
    required this.taskId,
    required this.taskTitle,
    required this.monthKey,
    required this.amountCents,
    required this.isSpent,
    required this.contributorName,
  });

  final int projectId;
  final String projectName;
  final int taskId;
  final String taskTitle;
  final String monthKey;
  final int amountCents;
  final bool isSpent;
  final String contributorName;
}
