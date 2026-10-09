import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import 'collection_actions.dart';
import 'organizer_widgets.dart';

class OrganizerShoppingPage extends StatefulWidget {
  const OrganizerShoppingPage({
    super.key,
    required this.snapshot,
    required this.actions,
    this.selectedId,
    required this.onSelection,
    this.readOnly = false,
    this.scopeLabel,
    this.onShare,
    this.onMoveToHousehold,
    this.emptyDescription,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerCollectionActions actions;
  final bool readOnly;
  final String? scopeLabel;
  final ValueChanged<LocalShoppingList>? onShare, onMoveToHousehold;
  final String? emptyDescription;
  final String? selectedId;
  final ValueChanged<String?> onSelection;
  @override
  State<OrganizerShoppingPage> createState() => _OrganizerShoppingPageState();
}

class _OrganizerShoppingPageState extends State<OrganizerShoppingPage> {
  bool _showAll = false;
  final _item = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _item.dispose();
    super.dispose();
  }

  Future<void> _add(String listId) async {
    final title = _item.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.actions.createShoppingItem(listId: listId, title: title);
      if (mounted) _item.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.actions.errorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final selected =
        widget.snapshot.shoppingLists
            .where((list) => list.id == widget.selectedId)
            .firstOrNull ??
        (widget.snapshot.shoppingLists.length == 1 && !_showAll
            ? widget.snapshot.shoppingLists.single
            : null);
    final lists = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.organizerShopping,
          subtitle: widget.scopeLabel ?? l.organizerShoppingIntro,
          action: widget.snapshot.shoppingLists.isEmpty || widget.readOnly
              ? null
              : FilledButton.icon(
                  onPressed: () => widget.actions.shoppingList(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l.organizerAddList),
                ),
        ),
        if (widget.snapshot.shoppingLists.isEmpty)
          OrganizerEmpty(
            icon: Icons.shopping_bag_outlined,
            title: l.organizerNoLists,
            description:
                widget.emptyDescription ?? l.organizerNoListsDescription,
            action: widget.readOnly ? null : l.organizerAddList,
            onAction: widget.readOnly
                ? null
                : () => widget.actions.shoppingList(),
          ),
        for (final list in widget.snapshot.shoppingLists)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                minVerticalPadding: 18,
                leading: Icon(
                  Icons.shopping_bag_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(list.title),
                subtitle: Text(
                  l.organizerShoppingCount(
                    widget.snapshot.shoppingItems
                        .where(
                          (item) => item.listId == list.id && !item.isChecked,
                        )
                        .length,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() => _showAll = false);
                  widget.onSelection(list.id);
                },
              ),
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760 && selected != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: lists),
              const SizedBox(width: 28),
              Expanded(flex: 5, child: _detail(selected, false)),
            ],
          );
        }
        return selected == null || _showAll ? lists : _detail(selected, true);
      },
    );
  }

  Widget _detail(LocalShoppingList list, bool back) {
    final l = context.l10n;
    final items = widget.snapshot.shoppingItems
        .where((item) => item.listId == list.id)
        .toList();
    final pending = items.where((item) => !item.isChecked).toList();
    final bought = items.where((item) => item.isChecked).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (back)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _showAll = true);
                widget.onSelection(null);
              },
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(l.organizerShopping),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: OrganizerHeading(
                title: list.title,
                subtitle: widget.scopeLabel ?? l.organizerPersonal,
              ),
            ),
            if (!widget.readOnly)
              IconButton(
                tooltip: l.organizerEditList,
                onPressed: () => widget.actions.shoppingList(list),
                icon: const Icon(Icons.more_horiz),
              ),
          ],
        ),
        if (widget.onMoveToHousehold != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('shopping-assign-${list.id}'),
              onPressed: () => widget.onMoveToHousehold!(list),
              icon: const Icon(Icons.home_outlined),
              label: Text(l.localSpaceMoveToHousehold),
            ),
          ),
        if (widget.onShare != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => widget.onShare!(list),
                icon: const Icon(Icons.people_outline, size: 18),
                label: Text(l.sharingCopyAction),
              ),
            ),
          ),
        if (!widget.readOnly)
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('shopping-item-field'),
                  controller: _item,
                  textCapitalization: TextCapitalization.sentences,
                  enabled: !_busy,
                  decoration: InputDecoration(hintText: l.organizerItemHint),
                  onSubmitted: (_) => _add(list.id),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: l.organizerAddItem,
                onPressed: _busy ? null : () => _add(list.id),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              l.organizerEmptyList,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final item in pending) _row(item),
        if (bought.isNotEmpty) ...[
          const SizedBox(height: 20),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${l.organizerBought} (${bought.length})'),
            children: [for (final item in bought) _row(item)],
          ),
        ],
      ],
    );
  }

  Widget _row(LocalShoppingItem item) => Container(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        Checkbox(
          value: item.isChecked,
          onChanged: widget.readOnly
              ? null
              : (v) => widget.actions.setShoppingItemChecked(item.id, v!),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        Expanded(
          child: InkWell(
            onTap: widget.readOnly
                ? null
                : () => widget.actions.shoppingItem(item.listId, item),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        decoration: item.isChecked
                            ? TextDecoration.lineThrough
                            : null,
                        color: item.isChecked
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      item.quantity,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
