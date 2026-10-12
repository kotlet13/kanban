import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../organizer_widgets.dart';

/// Presentation-only rows. The caller owns authorization and financial meaning.
class DesktopFinanceRow {
  const DesktopFinanceRow({
    required this.id,
    required this.title,
    required this.date,
    required this.typeStatus,
    required this.amount,
    required this.amountMinor,
    required this.currency,
    required this.account,
    this.onOpen,
    this.openLabel,
    this.source,
    this.actions,
    this.people,
    this.author,
  });
  final String id, title, typeStatus, amount, currency, account;
  final int amountMinor;
  final DateTime? date;
  final VoidCallback? onOpen;
  final String? openLabel, people, author;
  final Widget? source, actions;
}

/// Scrollable at small native window widths; keeps currencies separate when
/// sorting amounts and never computes a balance from the displayed rows.
class DesktopFinanceTable extends StatefulWidget {
  const DesktopFinanceTable({
    super.key,
    required this.rows,
    this.showPeople = false,
    this.initialSortAscending = false,
  });
  final List<DesktopFinanceRow> rows;
  final bool showPeople, initialSortAscending;

  @override
  State<DesktopFinanceTable> createState() => _DesktopFinanceTableState();
}

class _DesktopFinanceTableState extends State<DesktopFinanceTable> {
  final _scroll = ScrollController();
  int _column = 0;
  late bool _ascending;

  @override
  void initState() {
    super.initState();
    _ascending = widget.initialSortAscending;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _compare(DesktopFinanceRow a, DesktopFinanceRow b) {
    final value = switch (_column) {
      0 =>
        a.date == null
            ? (b.date == null ? 0 : -1)
            : b.date == null
            ? 1
            : a.date!.compareTo(b.date!),
      1 => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      2 => a.typeStatus.compareTo(b.typeStatus),
      3 =>
        a.currency == b.currency
            ? a.amountMinor.compareTo(b.amountMinor)
            : a.currency.compareTo(b.currency),
      4 => a.account.toLowerCase().compareTo(b.account.toLowerCase()),
      _ => 0,
    };
    return value == 0 ? a.id.compareTo(b.id) : (_ascending ? value : -value);
  }

  Future<void> _contextMenu(DesktopFinanceRow row, Offset position) async {
    if (row.onOpen == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: true,
          child: Text(row.openLabel ?? context.l10n.edit),
        ),
      ],
    );
    if (choice == true && mounted) {
      // Resolve the current row after the menu closes, since permissions or
      // the selected workspace may have changed while it was open.
      final current = widget.rows
          .where((item) => item.id == row.id)
          .firstOrNull;
      current?.onOpen?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rows = [...widget.rows]..sort(_compare);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      notificationPredicate: (notification) => notification.depth == 0,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 14),
        child: DataTable(
          key: const ValueKey('desktop-finance-table'),
          sortColumnIndex: _column,
          sortAscending: _ascending,
          showCheckboxColumn: false,
          horizontalMargin: 16,
          columnSpacing: 24,
          headingRowHeight: 56 * scale,
          dataRowMinHeight: 72 * scale,
          dataRowMaxHeight: 160 * scale,
          columns: [
            for (final label in [
              l.financeDate,
              l.organizerTitle,
              l.type,
              l.amount,
              l.financeAccount,
            ])
              DataColumn(
                label: Text(label),
                numeric: label == l.amount,
                onSort: (column, ascending) => setState(() {
                  _column = column;
                  _ascending = ascending;
                }),
              ),
            if (widget.showPeople) ...[
              DataColumn(label: Text(l.financePayerRecipient)),
              DataColumn(label: Text(l.financeEnteredBy)),
            ],
            DataColumn(label: Text(l.moderationMoreActions)),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                key: ValueKey('desktop-finance-row-${row.id}'),
                cells: [
                  DataCell(
                    Text(
                      row.date == null
                          ? l.financePlanUndatedEntry
                          : organizerDate(context, row.date!),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 260 * scale.clamp(1, 1.5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onSecondaryTapDown: row.onOpen == null
                                ? null
                                : (details) =>
                                      _contextMenu(row, details.globalPosition),
                            child: row.onOpen == null
                                ? Text(
                                    row.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : TextButton(
                                    key: ValueKey(
                                      'desktop-finance-open-${row.id}',
                                    ),
                                    style: TextButton.styleFrom(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      minimumSize: const Size(48, 48),
                                    ),
                                    onPressed: row.onOpen,
                                    child: Tooltip(
                                      message: row.title,
                                      child: Text(
                                        row.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                          ),
                          if (row.source != null) row.source!,
                        ],
                      ),
                    ),
                  ),
                  DataCell(Text(row.typeStatus)),
                  DataCell(Text(row.amount)),
                  DataCell(
                    SizedBox(width: 180 * scale, child: Text(row.account)),
                  ),
                  if (widget.showPeople) ...[
                    DataCell(
                      SizedBox(
                        width: 240 * scale,
                        child: Text(row.people ?? ''),
                      ),
                    ),
                    DataCell(Text(row.author ?? '')),
                  ],
                  DataCell(row.actions ?? const SizedBox.shrink()),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
