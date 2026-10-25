import 'package:flutter/foundation.dart';

import '../../domain/collaboration_models.dart';

typedef FinanceEntryAccountOption = ({
  String id,
  String? scopeId,
  String name,
  String currency,
});

/// Presentation state only. A refresh may change available destinations, never
/// the form's selected account or any other draft value. Core admission remains
/// authoritative, including the original unchanged-account offline path.
class FinanceEntryAccounts extends ChangeNotifier {
  FinanceEntryAccounts({
    required this.scopeId,
    required this.original,
    required this.unavailableLabel,
    required CollaborationState initial,
  }) {
    update(initial, notify: false);
  }
  final String scopeId, unavailableLabel;
  final SharedFinanceEntry? original;
  final _available = <String, FinanceEntryAccountOption>{};
  final _known = <String, FinanceEntryAccountOption>{};
  bool loading = false, refreshUnavailable = false;

  String? get originalKey => original == null
      ? null
      : original!.accountScopeId == null
      ? original!.accountId
      : '${original!.accountScopeId}:${original!.accountId}';

  FinanceEntryAccountOption? get _originalOption => original == null
      ? null
      : (
          id: original!.accountId,
          scopeId: original!.accountScopeId,
          name: unavailableLabel,
          currency: original!.currency,
        );

  String get initialSelection =>
      originalKey ??
      _available.entries
          .where((e) => e.value.scopeId != null)
          .firstOrNull
          ?.key ??
      _available.keys.firstOrNull ??
      '';

  bool update(CollaborationState value, {bool notify = true}) {
    final next = <String, FinanceEntryAccountOption>{};
    for (final account in value.dataForScope(scopeId).financeAccounts) {
      if (!account.archived || account.id == originalKey) {
        next[account.id] = (
          id: account.id,
          scopeId: null,
          name: account.name,
          currency: account.currency,
        );
      }
    }
    for (final account
        in value.financeAccountChoices[scopeId] ??
            <SharedFinanceAccountChoice>[]) {
      final key = '${account.scopeId}:${account.id}';
      if (!account.archived || key == originalKey) {
        next[key] = (
          id: account.id,
          scopeId: account.scopeId,
          name: account.name,
          currency: account.currency,
        );
      }
    }
    final changed = !mapEquals(_available, next);
    if (changed) {
      _available
        ..clear()
        ..addAll(next);
      _known.addAll(next);
      if (notify) notifyListeners();
    }
    return changed;
  }

  FinanceEntryAccountOption? option(String key) =>
      _available[key] ?? (key == originalKey ? _originalOption : null);

  Map<String, FinanceEntryAccountOption> displayOptions(String selected) => {
    ..._available,
    if (originalKey != null && !_available.containsKey(originalKey))
      originalKey!: _originalOption!,
    if (selected.isNotEmpty &&
        !_available.containsKey(selected) &&
        selected != originalKey &&
        _known.containsKey(selected))
      selected: (
        id: _known[selected]!.id,
        scopeId: _known[selected]!.scopeId,
        name: unavailableLabel,
        currency: _known[selected]!.currency,
      ),
  };

  void finishRefresh(CollaborationState value, {required bool failed}) {
    final statusChanged = loading || refreshUnavailable != failed;
    loading = false;
    refreshUnavailable = failed;
    final optionsChanged = update(value, notify: false);
    if (statusChanged || optionsChanged) notifyListeners();
  }
}
