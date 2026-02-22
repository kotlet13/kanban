import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/kanboard_models.dart';
import '../../state/providers.dart';

class ProjectExpensesPage extends ConsumerStatefulWidget {
  const ProjectExpensesPage({
    required this.projectId,
    required this.projectName,
    this.projectColorHex,
    super.key,
  });

  final int projectId;
  final String projectName;
  final String? projectColorHex;

  @override
  ConsumerState<ProjectExpensesPage> createState() =>
      _ProjectExpensesPageState();
}

class _ProjectExpensesPageState extends ConsumerState<ProjectExpensesPage> {
  final _currencyController = TextEditingController();
  final _budgetController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  String? _validationError;
  KanboardBoard? _board;
  String _expenseCurrencyCode = 'EUR';
  int? _expenseBudgetCents;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _currencyController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final api = ref.read(kanboardApiProvider);
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
      final boardFuture = api.getBoard(widget.projectId);
      final currencyFuture = api.getProjectExpenseCurrency(widget.projectId);
      final budgetFuture = api.getProjectExpenseBudgetCents(widget.projectId);
      final board = await boardFuture;
      final currency = await currencyFuture;
      final budget = await budgetFuture;
      final normalizedCurrency = (currency ?? 'EUR').trim().toUpperCase();
      if (!mounted) return;
      setState(() {
        _board = board;
        _expenseCurrencyCode = normalizedCurrency;
        _expenseBudgetCents = budget;
        _currencyController.text = normalizedCurrency;
        _budgetController.text = budget == null ? '' : _formatCents(budget);
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

  int _plannedExpenseCents(KanboardBoard board) {
    var total = 0;
    for (final swimlane in board.swimlanes) {
      for (final column in swimlane.columns) {
        for (final task in column.tasks) {
          if (task.isActive && task.score > 0) {
            total += task.score;
          }
        }
      }
    }
    return total;
  }

  int _spentExpenseCents(KanboardBoard board) {
    var total = 0;
    for (final swimlane in board.swimlanes) {
      for (final column in swimlane.columns) {
        for (final task in column.tasks) {
          if (!task.isActive && task.score > 0) {
            total += task.score;
          }
        }
      }
    }
    return total;
  }

  int? _parseMoneyToCents(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null || value < 0) return null;
    return (value * 100).round();
  }

  String _formatCents(int cents) {
    return (cents / 100).toStringAsFixed(2);
  }

  String _formatMoneyCents(int cents) {
    final code = _expenseCurrencyCode.trim().isEmpty
        ? 'EUR'
        : _expenseCurrencyCode.trim().toUpperCase();
    return '$code ${_formatCents(cents)}';
  }

  Future<void> _saveExpenseSettings() async {
    final api = ref.read(kanboardApiProvider);
    if (api == null) return;

    final currency = _currencyController.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      setState(() {
        _validationError = context.l10n.currencyMustBeA3LetterCode;
      });
      return;
    }

    final budgetText = _budgetController.text.trim();
    final budgetCents = budgetText.isEmpty
        ? null
        : _parseMoneyToCents(budgetText);
    if (budgetText.isNotEmpty && budgetCents == null) {
      setState(() {
        _validationError = context.l10n.budgetMustBeAPositiveNumber;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });

    try {
      await api.saveProjectExpenseSettings(
        projectId: widget.projectId,
        currency: currency,
        budgetCents: budgetCents,
      );
      if (!mounted) return;
      setState(() {
        _expenseCurrencyCode = currency;
        _expenseBudgetCents = budgetCents;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.expenseSettingsSaved)),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.expenseSettingsFailed(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<_ExpenseTaskRow> _expenseRows(KanboardBoard board) {
    final rows = <_ExpenseTaskRow>[];
    for (final swimlane in board.swimlanes) {
      for (final column in swimlane.columns) {
        for (final task in column.tasks) {
          if (task.score <= 0) continue;
          rows.add(
            _ExpenseTaskRow(
              taskId: task.id,
              title: task.title,
              amountCents: task.score,
              isSpent: !task.isActive,
            ),
          );
        }
      }
    }
    rows.sort((a, b) => b.amountCents.compareTo(a.amountCents));
    return rows;
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
    bool emphasized = false,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final accent = _projectAccent(theme);
    return Container(
      constraints: const BoxConstraints(minWidth: 156),
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
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final board = _board;
    final plannedCents = board == null ? 0 : _plannedExpenseCents(board);
    final spentCents = board == null ? 0 : _spentExpenseCents(board);
    final budgetCents = _expenseBudgetCents;
    final remainingCents = budgetCents == null
        ? null
        : budgetCents - spentCents - plannedCents;
    final remainingValueColor = remainingCents == null
        ? null
        : remainingCents < 0
        ? theme.colorScheme.error
        : remainingCents > 0
        ? (theme.brightness == Brightness.dark
              ? Colors.green.shade300
              : Colors.green.shade700)
        : null;
    final expenseRows = board == null
        ? const <_ExpenseTaskRow>[]
        : _expenseRows(board);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.projectExpenses)),
      body: RefreshIndicator(
        onRefresh: _loadData,
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.expenses,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _metricTile(
                          icon: Icons.payments_outlined,
                          label: context.l10n.planned,
                          value: _formatMoneyCents(plannedCents),
                        ),
                        _metricTile(
                          icon: Icons.check_circle_outline,
                          label: context.l10n.spent,
                          value: _formatMoneyCents(spentCents),
                        ),
                        _metricTile(
                          icon: Icons.account_balance_wallet_outlined,
                          label: context.l10n.budget,
                          value: budgetCents == null
                              ? context.l10n.noBudget
                              : _formatMoneyCents(budgetCents),
                        ),
                        _metricTile(
                          icon: Icons.savings_outlined,
                          label: context.l10n.remaining,
                          value: remainingCents == null
                              ? context.l10n.noBudget
                              : _formatMoneyCents(remainingCents),
                          emphasized: true,
                          valueColor: remainingValueColor,
                        ),
                      ],
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
                      context.l10n.projectExpenses,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _currencyController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 3,
                      decoration: InputDecoration(
                        labelText: context.l10n.currencyCode,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _budgetController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.l10n.budget,
                        hintText: context.l10n.leaveEmptyForNoBudget,
                      ),
                    ),
                    if (_validationError != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        _validationError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveExpenseSettings,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(context.l10n.save),
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
                      context.l10n.tasks,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (expenseRows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          context.l10n.noResultsYet,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      for (final row in expenseRows)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            row.isSpent
                                ? Icons.check_circle_outline
                                : Icons.payments_outlined,
                          ),
                          title: Text(
                            row.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${context.l10n.taskNumber(row.taskId)} - ${row.isSpent ? context.l10n.spent : context.l10n.planned}',
                          ),
                          trailing: Text(
                            _formatMoneyCents(row.amountCents),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                  ],
                ),
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
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseTaskRow {
  const _ExpenseTaskRow({
    required this.taskId,
    required this.title,
    required this.amountCents,
    required this.isSpent,
  });

  final int taskId;
  final String title;
  final int amountCents;
  final bool isSpent;
}
