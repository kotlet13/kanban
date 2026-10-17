import 'collaboration_models.dart';
import 'linked_payment_models.dart';

/// IDs in this read-only projection are scoped display keys, never write IDs.
/// Editors must use originalEntries/originalAccounts and their source maps.
class OrganizationFinanceProjection {
  const OrganizationFinanceProjection({
    required this.accounts,
    required this.entries,
    required this.transfers,
    required this.accountScopeIds,
    required this.entryScopeIds,
    required this.transferScopeIds,
    required this.originalAccounts,
    required this.originalEntries,
    required this.originalTransfers,
    required this.projectOptions,
    required this.entryProjectKeys,
    required this.payments,
    required this.complete,
  });
  final List<SharedFinanceAccount> accounts;
  final List<SharedFinanceEntry> entries;
  final List<SharedFinanceTransfer> transfers;
  final Map<String, String> accountScopeIds, entryScopeIds, transferScopeIds;
  final Map<String, SharedFinanceAccount> originalAccounts;
  final Map<String, SharedFinanceEntry> originalEntries;
  final Map<String, SharedFinanceTransfer> originalTransfers;
  final Map<String, String> projectOptions, entryProjectKeys;
  final PaymentSnapshot payments;
  final bool complete;
}

String scopedFinanceDisplayId(String scopeId, String id) => '$scopeId:$id';

OrganizationFinanceProjection projectOrganizationFinance({
  required CollaborationState state,
  required String scopeId,
  Map<String, PaymentSnapshot> paymentsByScope = const {},
}) {
  final accounts = <String, SharedFinanceAccount>{};
  final entries = <String, SharedFinanceEntry>{};
  final transfers = <String, SharedFinanceTransfer>{};
  final accountScopes = <String, String>{};
  final entryScopes = <String, String>{};
  final transferScopes = <String, String>{};
  final originals = <String, SharedFinanceEntry>{};
  final originalTransfers = <String, SharedFinanceTransfer>{};
  final originalAccounts = <String, SharedFinanceAccount>{};
  final projects = <String, String>{};
  final entryProjects = <String, String>{};
  final events = <PaymentEvent>[];
  final cash = <PaymentCashMovement>[];
  var complete = true;
  final allowed =
      state.localAccessAllowed &&
      !state.sessionInvalid &&
      !state.deletionPending &&
      state.session != null;
  final root = allowed
      ? state.scopes
            .where(
              (s) => s.id == scopeId && s.canRead && !s.deleted && !s.revoked,
            )
            .firstOrNull
      : null;
  final sources = <SharedScope>[];
  final rootPolicy = state.financePolicyForScope(scopeId);
  final requiresContributionInventory =
      (root?.kind == SharedScopeKind.organization ||
          root?.kind == SharedScopeKind.household) &&
      (state.organizationFinanceSupported ||
          rootPolicy.requiredContractVersion >= 3);
  if (root == null || !state.financePolicyForScope(scopeId).canRead) {
    complete = false;
  } else {
    sources.add(root);
    if (root.kind == SharedScopeKind.organization ||
        root.kind == SharedScopeKind.household) {
      final policy = state.financePolicyForScope(scopeId);
      if (requiresContributionInventory) {
        if (!policy.organizationFinanceComplete ||
            policy.organizationFinanceScopeIds.any(
              (id) => !state.scopes.any(
                (s) =>
                    s.id == id &&
                    s.parentSpaceId == scopeId &&
                    s.canRead &&
                    !s.deleted &&
                    state.financePolicyForScope(id).canRead &&
                    state.financeSnapshotComplete[id] == true &&
                    policy.organizationFinanceSequences.containsKey(id) &&
                    (state.financeSnapshotSequences[id] ?? -1) >=
                        policy.organizationFinanceSequences[id]!,
              ),
            )) {
          complete = false;
        }
      }
      // Archived projects still contribute historical account movements.
      for (final child in state.scopes) {
        if (child.kind != SharedScopeKind.project ||
            child.parentSpaceId != scopeId ||
            child.deleted) {
          continue;
        }
        if (!child.canRead || !state.financePolicyForScope(child.id).canRead) {
          complete = false;
          continue;
        }
        sources.add(child);
      }
    }
  }
  for (final source in sources) {
    final id = source.id;
    if (state.financeSnapshotComplete[id] != true) complete = false;
    final data = state.dataForScope(id);
    if (id != scopeId) projects[id] = source.name;
    for (final project in data.projects) {
      if (id == scopeId && project.id != source.projectRootId) {
        projects[scopedFinanceDisplayId(id, project.id)] = project.title;
      }
    }
    for (final account in data.financeAccounts) {
      final key = scopedFinanceDisplayId(id, account.id);
      accounts[key] = SharedFinanceAccount.fromJson({
        ...account.toJson(),
        'id': key,
      });
      originalAccounts[key] = account;
      accountScopes[key] = id;
    }
  }
  for (final source in sources) {
    final id = source.id;
    final data = state.dataForScope(id);
    for (final entry in data.financeEntries) {
      final key = scopedFinanceDisplayId(id, entry.id);
      final accountScope = entry.accountScopeId ?? id;
      if (requiresContributionInventory &&
          id != scopeId &&
          accountScope == scopeId &&
          !rootPolicy.organizationFinanceScopeIds.contains(id)) {
        // The last parent-linked entry may have been deleted on the server
        // while this child's old local snapshot still contains it.
        complete = false;
      }
      // A child may use only its own or the current root's account.
      final accountKey = scopedFinanceDisplayId(accountScope, entry.accountId);
      final account = accounts[accountKey];
      if ((accountScope != id && accountScope != scopeId) ||
          account == null ||
          account.currency != entry.currency) {
        complete = false;
        continue;
      }
      entries[key] = SharedFinanceEntry.fromJson({
        ...entry.toJson(),
        'id': key,
        'accountId': accountKey,
        'accountScopeId': null,
        'ledgerAccountId': entry.ledgerAccountId == null ? null : accountKey,
      });
      originals[key] = entry;
      entryScopes[key] = id;
      if (id != scopeId) {
        entryProjects[key] = id;
      } else if (entry.projectId != null) {
        entryProjects[key] = scopedFinanceDisplayId(id, entry.projectId!);
      }
    }
    for (final transfer in data.financeTransfers) {
      final key = scopedFinanceDisplayId(id, transfer.id);
      final from = scopedFinanceDisplayId(id, transfer.fromAccountId);
      final to = scopedFinanceDisplayId(id, transfer.toAccountId);
      if (accounts[from]?.currency != transfer.currency ||
          accounts[to]?.currency != transfer.currency) {
        complete = false;
        continue;
      }
      transfers[key] = SharedFinanceTransfer.fromJson({
        ...transfer.toJson(),
        'id': key,
        'fromAccountId': from,
        'toAccountId': to,
      });
      originalTransfers[key] = transfer;
      transferScopes[key] = id;
    }
    final payment = paymentsByScope[id];
    if (state.financePolicyForScope(id).linkedPaymentsRequired &&
        (payment?.fresh != true || payment?.complete != true)) {
      complete = false;
    }
    if (payment != null) {
      if (!payment.complete) complete = false;
      for (final event in payment.events) {
        // Only the canonical source event suppresses that source's cash leg.
        if (event.sourceScopeId != id) continue;
        events.add(
          PaymentEvent(
            eventId: scopedFinanceDisplayId(id, event.eventId),
            sourceScopeId: id,
            sourceEntryId: scopedFinanceDisplayId(id, event.sourceEntryId),
            sourceRevision: event.sourceRevision,
            payerAccountId: event.payerAccountId,
            amountMinor: event.amountMinor,
            currency: event.currency,
            paidAt: event.paidAt,
            expectReimbursement: event.expectReimbursement,
            revision: event.revision,
          ),
        );
      }
      for (final movement in payment.cashMovements) {
        final accountKey = scopedFinanceDisplayId(id, movement.accountId);
        if (accounts[accountKey]?.currency != movement.currency) {
          complete = false;
          continue;
        }
        cash.add(
          PaymentCashMovement(
            id: scopedFinanceDisplayId(id, movement.id),
            accountId: accountKey,
            amountMinor: movement.amountMinor,
            currency: movement.currency,
            paidAt: movement.paidAt,
          ),
        );
      }
    }
  }
  return OrganizationFinanceProjection(
    accounts: List.unmodifiable(accounts.values),
    entries: List.unmodifiable(entries.values),
    transfers: List.unmodifiable(transfers.values),
    accountScopeIds: Map.unmodifiable(accountScopes),
    entryScopeIds: Map.unmodifiable(entryScopes),
    transferScopeIds: Map.unmodifiable(transferScopes),
    originalAccounts: Map.unmodifiable(originalAccounts),
    originalEntries: Map.unmodifiable(originals),
    originalTransfers: Map.unmodifiable(originalTransfers),
    projectOptions: Map.unmodifiable(projects),
    entryProjectKeys: Map.unmodifiable(entryProjects),
    payments: PaymentSnapshot(
      events: events,
      cashMovements: cash,
      fresh: complete,
    ),
    complete: complete,
  );
}
