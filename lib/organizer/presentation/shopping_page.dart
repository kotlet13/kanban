import 'shared/content_actions_menu.dart';
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
    this.titleAccessory,
    this.reportScopeId,
    this.onShare,
    this.onMoveToHousehold,
    this.emptyDescription,
    this.highlightedItemIds = const {},
    this.highlightList = false,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerCollectionActions actions;
  final bool readOnly;
  final String? scopeLabel;
  final String? reportScopeId;
  final Widget? titleAccessory;
  final ValueChanged<LocalShoppingList>? onShare, onMoveToHousehold;
  final String? emptyDescription;
  final Set<String> highlightedItemIds;
  final bool highlightList;
  final String? selectedId;
  final ValueChanged<String?> onSelection;
  @override
  State<OrganizerShoppingPage> createState() => _OrganizerShoppingPageState();
}

class _OrganizerShoppingPageState extends State<OrganizerShoppingPage> {
  bool _showAll = false;
  final _item = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _itemFocus = FocusNode();
  int _generation = 0;
  bool _busy = false;
  final _highlightKeys = <String, GlobalKey>{};
  String? _revealedList;

  @override
  void didUpdateWidget(OrganizerShoppingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.workspaceKey != widget.snapshot.workspaceKey ||
        oldWidget.reportScopeId != widget.reportScopeId ||
        oldWidget.selectedId != widget.selectedId) {
      _generation++;
      _item.clear();
      _quantity.text = '1';
    }
  }

  @override
  void dispose() {
    _item.dispose();
    _quantity.dispose();
    _itemFocus.dispose();
    super.dispose();
  }

  Future<void> _add(String listId) async {
    final title = _item.text.trim();
    if (title.isEmpty || _busy) return;
    final generation = _generation;
    final quantity = _quantity.text.trim();
    var saved = false;
    setState(() => _busy = true);
    try {
      await widget.actions.createShoppingItem(
        listId: listId,
        title: title,
        quantity: quantity,
      );
      if (mounted && generation == _generation) {
        _item.clear();
        _quantity.text = '1';
        saved = true;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.actions.errorMessage(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (saved && generation == _generation) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && generation == _generation && !widget.readOnly) {
              _itemFocus.requestFocus();
            }
          });
        }
      }
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
          titleAccessory: widget.titleAccessory,
          subtitle: widget.scopeLabel ?? l.organizerShoppingIntro,
          action:
              widget.snapshot.shoppingLists.isEmpty ||
                  widget.readOnly ||
                  !widget.actions.canCreateRecords
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
            action: widget.readOnly || !widget.actions.canCreateRecords
                ? null
                : l.organizerAddList,
            onAction: widget.readOnly || !widget.actions.canCreateRecords
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
    if (_revealedList != list.id && widget.highlightedItemIds.isNotEmpty) {
      _revealedList = list.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final id in widget.highlightedItemIds) {
          final target = _highlightKeys[id]?.currentContext;
          if (target != null) {
            Scrollable.ensureVisible(
              target,
              alignment: .3,
              duration: const Duration(milliseconds: 200),
            );
            break;
          }
        }
      });
    }
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
                titleAccessory: back ? widget.titleAccessory : null,
                subtitle: widget.scopeLabel ?? l.organizerPersonal,
              ),
            ),
            if (widget.reportScopeId != null)
              SharedContentActionsMenu(
                scopeId: widget.reportScopeId!,
                targetId: list.id,
                actions: [
                  if (!widget.readOnly &&
                      widget.actions.canEditRecord('shoppingList', list.id))
                    ContentMenuAction(
                      label: l.organizerEditList,
                      icon: Icons.edit_outlined,
                      onSelected: () => widget.actions.shoppingList(list),
                    ),
                ],
              )
            else if (!widget.readOnly &&
                widget.actions.canEditRecord('shoppingList', list.id))
              IconButton(
                tooltip: l.organizerEditList,
                onPressed: () => widget.actions.shoppingList(list),
                icon: const Icon(Icons.more_horiz),
              ),
          ],
        ),
        if (widget.highlightList)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l.notificationChanged,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
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
        if (!widget.readOnly && widget.actions.canCreateRecords)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('shopping-item-field'),
                controller: _item,
                focusNode: _itemFocus,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_busy,
                decoration: InputDecoration(hintText: l.organizerItemHint),
                onSubmitted: (_) => _add(list.id),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('shopping-quantity-field'),
                      controller: _quantity,
                      textInputAction: TextInputAction.done,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: l.organizerQuantity,
                      ),
                      onSubmitted: (_) => _add(list.id),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    tooltip: l.organizerAddItem,
                    style: IconButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    onPressed: _busy ? null : () => _add(list.id),
                    icon: const Icon(Icons.add),
                  ),
                ],
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
            initiallyExpanded: bought.any(
              (item) => widget.highlightedItemIds.contains(item.id),
            ),
            tilePadding: EdgeInsets.zero,
            title: Text('${l.organizerBought} (${bought.length})'),
            children: [for (final item in bought) _row(item)],
          ),
        ],
      ],
    );
  }

  Widget _row(LocalShoppingItem item) => Container(
    key: widget.highlightedItemIds.contains(item.id)
        ? _highlightKeys.putIfAbsent(item.id, GlobalKey.new)
        : ValueKey('shopping-row-${item.id}'),
    decoration: BoxDecoration(
      color: widget.highlightedItemIds.contains(item.id)
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .6)
          : null,
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        Checkbox(
          value: item.isChecked,
          onChanged: widget.readOnly || !widget.actions.canCheckShoppingItems
              ? null
              : (v) => widget.actions.setShoppingItemChecked(item.id, v!),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        Expanded(
          child: InkWell(
            onTap:
                widget.readOnly ||
                    !widget.actions.canEditRecord('shoppingItem', item.id)
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
                  if (widget.highlightedItemIds.contains(item.id)) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: context.l10n.notificationChanged,
                      child: Icon(
                        Icons.new_releases_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (widget.readOnly && widget.reportScopeId != null)
          SharedContentActionsMenu(
            scopeId: widget.reportScopeId!,
            targetId: item.id,
          ),
      ],
    ),
  );
}
