import 'collaboration_models.dart';
import 'organizer_models.dart';
import 'local_space_models.dart';

/// A concrete origin retained by every row of the aggregate read projection.
/// Never use an aggregate identifier as a destination for a write.
class AllSpacesSource {
  const AllSpacesSource({
    required this.key,
    this.personal,
    this.localSpace,
    this.scope,
    this.session,
    this.data,
    this.privateScopeId,
    this.privateRecordIds = const {},
    required this.canReadFinance,
    required this.financeComplete,
  });
  final String key;
  final OrganizerSnapshot? personal;
  final LocalSpace? localSpace;
  bool get isLocalSpace =>
      personal != null && !personal!.workspaceKey.startsWith('private:');
  final SharedScope? scope;
  final AccountSession? session;
  final SharedScopeData? data;
  final String? privateScopeId;

  /// Server IDs -> presentation IDs for the active private workspace.
  final Map<String, String> privateRecordIds;
  final bool canReadFinance, financeComplete;
  bool get isPersonal => personal != null;
  String? get scopeId => scope?.id;
  String? get workspaceKey => personal?.workspaceKey;
  String? get name => localSpace?.name ?? scope?.name;

  bool isCurrent(
    OrganizerSnapshot personal,
    CollaborationState shared, {
    bool financial = false,
    LocalSpacesState? localSpaces,
  }) {
    final sameSession =
        shared.localAccessAllowed &&
        shared.session?.partition == session?.partition &&
        shared.session?.deviceId == session?.deviceId;
    if (isLocalSpace && localSpaces != null) {
      final current = localSpaces.snapshots[workspaceKey];
      return current != null &&
          current.recordIds.containsAll(this.personal!.recordIds);
    }
    if (isPersonal) {
      final authoritative = workspaceKey!.startsWith('private:')
          ? localSpaces?.snapshots['local'] ?? personal
          : personal;
      return authoritative.workspaceKey == workspaceKey &&
          (!workspaceKey!.startsWith('private:') ||
              (sameSession &&
                  shared.scopes.any(
                    (s) =>
                        s.id == privateScopeId &&
                        !s.revoked &&
                        !s.archived &&
                        !s.blocked,
                  ) &&
                  (!financial ||
                      (shared.financePolicyForScope(privateScopeId!).canRead &&
                          shared.financeSnapshotComplete[privateScopeId] ==
                              true))));
    }
    return sameSession &&
        shared.scopes.any(
          (s) => s.id == scopeId && !s.revoked && !s.archived && !s.blocked,
        ) &&
        (!financial || shared.financePolicyForScope(scopeId!).canRead);
  }

  NotificationTarget target(String type, String id) {
    final privateId = privateRecordIds.entries
        .where((e) => e.value == id)
        .firstOrNull
        ?.key;
    final remote = !isPersonal || privateId != null;
    return NotificationTarget(
      serverUrl: remote ? session!.serverUrl : null,
      serverId: remote ? session!.serverId : null,
      accountId: remote ? session!.accountId : null,
      scopeId: remote ? (isPersonal ? privateScopeId : scopeId) : null,
      localSpaceId:
          !remote &&
              workspaceKey != 'local' &&
              !workspaceKey!.startsWith('private:')
          ? workspaceKey
          : null,
      records: [
        NotificationRecordTarget(
          type: privateId != null && type == 'financeEntry'
              ? 'personalFinanceEntry'
              : type,
          recordId: privateId ?? id,
        ),
      ],
    );
  }
}

class AllSpacesRecord<T> {
  const AllSpacesRecord({required this.source, required this.value});
  final AllSpacesSource source;
  final T value;
}

/// Exact totals for posted entries in one currency. Transfers are deliberately
/// separate records and contribute neither income nor expense.
class AllSpacesFinanceTotal {
  const AllSpacesFinanceTotal({
    required this.incomeMinor,
    required this.expenseMinor,
  });
  final BigInt incomeMinor, expenseMinor;
  BigInt get balanceMinor => incomeMinor - expenseMinor;
}

class AllSpacesSnapshot {
  AllSpacesSnapshot(Iterable<AllSpacesSource> sources)
    : sources = List.unmodifiable(sources);
  final List<AllSpacesSource> sources;
  bool get financeComplete => sources.every((s) => s.financeComplete);
  List<AllSpacesSource> get incompleteFinanceSources =>
      List.unmodifiable(sources.where((s) => !s.financeComplete));

  List<AllSpacesRecord<T>> _rows<T>(
    Iterable<T> Function(OrganizerSnapshot) personal,
    Iterable<T> Function(SharedScopeData) shared,
  ) => List.unmodifiable([
    for (final source in sources)
      for (final value
          in source.isPersonal
              ? personal(source.personal!)
              : shared(source.data!))
        AllSpacesRecord(source: source, value: value),
  ]);

  List<AllSpacesRecord<LocalProject>> get projects =>
      _rows((s) => s.projects, (s) => s.projects);
  List<AllSpacesRecord<LocalTask>> get tasks =>
      _rows((s) => s.tasks, (s) => s.tasks);
  List<AllSpacesRecord<LocalShoppingList>> get shoppingLists =>
      _rows((s) => s.shoppingLists, (s) => s.shoppingLists);
  List<AllSpacesRecord<LocalShoppingItem>> get shoppingItems =>
      _rows((s) => s.shoppingItems, (s) => s.shoppingItems);
  List<AllSpacesRecord<HouseholdPerson>> get people => _rows(
    (s) => s.people.where((p) => !p.archived),
    (s) => s.people.where((p) => !p.archived),
  );
  List<AllSpacesRecord<LocalEvent>> get localEvents =>
      _rows((s) => s.events, (_) => const []);
  List<AllSpacesRecord<SharedEvent>> get sharedEvents =>
      _rows((_) => const [], (s) => s.events);
  List<AllSpacesRecord<FinanceEntry>> get localFinanceEntries =>
      _rows((s) => s.financeEntries, (_) => const []);
  List<AllSpacesRecord<SharedFinanceEntry>> get sharedFinanceEntries =>
      _rows((_) => const [], (s) => s.financeEntries);
  List<AllSpacesRecord<SharedFinanceTransfer>> get financeTransfers =>
      _rows((_) => const [], (s) => s.financeTransfers);

  /// Totals cover complete readable sources only. Incomplete sources may have
  /// visible downloaded entries but must never masquerade as full balances.
  Map<String, AllSpacesFinanceTotal> get financeTotalsByCurrency {
    final income = <String, BigInt>{}, expense = <String, BigInt>{};
    void add(String currency, FinanceEntryKind kind, int amount) {
      final sums = kind == FinanceEntryKind.income ? income : expense;
      sums[currency] = (sums[currency] ?? BigInt.zero) + BigInt.from(amount);
    }

    for (final row in localFinanceEntries) {
      if (!row.source.financeComplete) continue;
      final v = row.value;
      if (v.status == FinanceEntryStatus.posted) {
        add(v.currency, v.kind, v.amountMinor);
      }
    }
    for (final row in sharedFinanceEntries) {
      if (!row.source.financeComplete) continue;
      final v = row.value;
      if (v.status == SharedFinanceStatus.posted) {
        add(v.currency, v.kind, v.amountMinor);
      }
    }
    return Map.unmodifiable({
      for (final currency in {...income.keys, ...expense.keys})
        currency: AllSpacesFinanceTotal(
          incomeMinor: income[currency] ?? BigInt.zero,
          expenseMinor: expense[currency] ?? BigInt.zero,
        ),
    });
  }
}

/// Uses the active personal projection exactly once. Its private server scope
/// is not added a second time, nor is the parked original local workspace read.
AllSpacesSnapshot projectAllSpaces({
  required OrganizerSnapshot personal,
  required CollaborationState shared,
  LocalSpacesState? localSpaces,
}) {
  final defaultPersonal = localSpaces?.snapshots['local'];
  if (defaultPersonal?.workspaceKey.startsWith('private:') == true) {
    personal = defaultPersonal!;
  }
  final session = shared.session;
  final authorized = session != null && shared.localAccessAllowed;
  final bound = personal.workspaceKey.startsWith('private:');
  final matchingPersonal =
      !bound ||
      (authorized && personal.workspaceKey == 'private:${session.partition}');
  final sources = <AllSpacesSource>[];
  SharedScope? privateScope;
  if (bound && authorized) {
    privateScope = shared.scopes
        .where(
          (s) =>
              s.id == shared.privateSync.scopeId &&
              !s.revoked &&
              !s.archived &&
              !s.blocked,
        )
        .firstOrNull;
  }
  final selectedLocal = localSpaces?.spaces
      .where((s) => s.id == personal.workspaceKey)
      .firstOrNull;
  if (matchingPersonal &&
      selectedLocal?.binding == null &&
      (!bound || privateScope != null)) {
    final canReadFinance =
        !bound || shared.financePolicyForScope(privateScope!.id).canRead;
    final complete =
        !bound ||
        (!canReadFinance ||
            shared.financeSnapshotComplete[privateScope!.id] == true);
    // A known policy change/incomplete refresh must not expose an older bound
    // personal snapshot while its asynchronous storage projection catches up.
    final safePersonal = bound && (!canReadFinance || !complete)
        ? personal.copyWith(
            financeEntries: const [],
            financeAccounts: const [],
            financeRecurrenceRules: const [],
          )
        : personal;
    sources.add(
      AllSpacesSource(
        key: personal.workspaceKey,
        personal: safePersonal,
        localSpace: localSpaces?.spaces
            .where((s) => s.id == (bound ? 'local' : personal.workspaceKey))
            .firstOrNull,
        session: bound ? session : null,
        privateScopeId: bound ? privateScope!.id : null,
        privateRecordIds: bound ? shared.privateRecordIds : const {},
        canReadFinance: canReadFinance,
        financeComplete:
            complete && !(selectedLocal?.financeRecoveryIncomplete ?? false),
      ),
    );
  }
  if (localSpaces != null) {
    for (final space in localSpaces.spaces) {
      // The active personal projection may include its private server rows.
      if (space.binding != null) continue;
      if (space.id == personal.workspaceKey || (bound && space.id == 'local')) {
        continue;
      }
      final snapshot = localSpaces.snapshots[space.id];
      if (snapshot == null) continue;
      sources.add(
        AllSpacesSource(
          key: space.id,
          personal: snapshot,
          localSpace: space,
          canReadFinance: true,
          financeComplete: !space.financeRecoveryIncomplete,
        ),
      );
    }
  }
  if (authorized) {
    for (final scope in shared.scopes.where(
      (s) =>
          !s.revoked &&
          !s.archived &&
          !s.blocked &&
          s.kind != SharedScopeKind.personal,
    )) {
      final data = shared.dataForScope(scope.id);
      final canRead = shared.financePolicyForScope(scope.id).canRead;
      final complete =
          !canRead || shared.financeSnapshotComplete[scope.id] == true;
      sources.add(
        AllSpacesSource(
          key: '${session.partition}:${scope.id}',
          scope: scope,
          session: session,
          canReadFinance: canRead,
          financeComplete: complete,
          data: SharedScopeData(
            projects: data.projects,
            tasks: data.tasks,
            people: data.people,
            events: data.events,
            shoppingLists: data.shoppingLists,
            shoppingItems: data.shoppingItems,
            financeAccounts: canRead ? data.financeAccounts : const [],
            financeEntries: canRead ? data.financeEntries : const [],
            financeTransfers: canRead ? data.financeTransfers : const [],
            financeRecurrenceRules: canRead
                ? data.financeRecurrenceRules
                : const [],
          ),
        ),
      );
    }
  }
  return AllSpacesSnapshot(sources);
}
