/// A suggested account for a new task cost, never an authorization decision.
/// Callers supply only accounts visible in the current editor's ownership scope.
typedef TaskCostAccountOption = ({String id, String currency, bool archived});

TaskCostAccountOption? defaultTaskCostAccount({
  required Iterable<TaskCostAccountOption> ownAccounts,
  required Iterable<TaskCostAccountOption> parentAccounts,
  required String currency,
  bool currencyUnchosen = false,
}) {
  final own = ownAccounts.where((a) => !a.archived).toList();
  // An ambiguous project must not silently send its costs to its parent.
  final candidates = own.isNotEmpty
      ? own
      : parentAccounts.where((a) => !a.archived).toList();
  final matching = candidates.where((a) => a.currency == currency).toList();
  if (matching.length == 1) return matching.single;
  if (matching.isEmpty && currencyUnchosen && candidates.length == 1) {
    return candidates.single;
  }
  return null;
}
