import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_database_provider.dart';
export 'local_database_provider.dart' show collaborationDatabaseFactoryProvider;
import '../data/collaboration_repository.dart';
import '../data/sqlite_organizer_storage.dart';
import '../data/collaboration_transport.dart';
import '../data/device_session_store.dart';
import '../data/remote_push_store.dart';
import '../data/account_deletion_store.dart';
import '../domain/collaboration_models.dart';
import '../domain/organizer_models.dart';
import '../domain/local_space_models.dart';
import '../domain/garden_models.dart';
export '../domain/local_space_models.dart';
export '../domain/organization_access_models.dart';

export '../domain/collaboration_models.dart';
export '../data/account_deletion_store.dart' show PendingAccountDeletion;

final collaborationTransportFactoryProvider =
    Provider<CollaborationTransport Function()>(
      (ref) => HttpCollaborationTransport.new,
    );
final deviceSessionStoreProvider = Provider<DeviceSessionStore>(
  (ref) => const SecureDeviceSessionStore(),
);
final remotePushStoreProvider = Provider<RemotePushStore>(
  (ref) => const SecureRemotePushStore(),
);
final collaborationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final collaborationBackgroundErrorProvider = StateProvider<Object?>(
  (ref) => null,
);

class _CollaborationLifecycle {
  Future<void> closing = Future.value();
}

final _lifecycleProvider = Provider((ref) => _CollaborationLifecycle());
final collaborationRepositoryProvider = FutureProvider<CollaborationRepository>(
  (ref) async {
    final database = ref.watch(localDatabaseProvider.future);
    final pushStore = ref.watch(remotePushStoreProvider);
    final transportFactory = ref.watch(collaborationTransportFactoryProvider);
    final store = ref.watch(deviceSessionStoreProvider),
        clock = ref.watch(collaborationClockProvider);
    final lifecycle = ref.watch(_lifecycleProvider);
    final opening = () async {
      await lifecycle.closing;
      final db = await database;
      final repository = CollaborationRepository(
        db,
        transportFactory(),
        store,
        clock: clock,
        pushStore: pushStore,
        ownsDatabase: false,
      );
      try {
        await repository.initialize();
        return repository;
      } catch (_) {
        await repository.close();
        rethrow;
      }
    }();
    ref.onDispose(() {
      lifecycle.closing = opening.then(
        (repository) => repository.close(),
        onError: (Object _, StackTrace __) {},
      );
    });
    return opening;
  },
);
final collaborationProvider =
    AsyncNotifierProvider<CollaborationController, CollaborationState>(
      CollaborationController.new,
    );

class CollaborationController extends AsyncNotifier<CollaborationState> {
  CollaborationRepository? _repository;
  bool _active = false;
  @override
  Future<CollaborationState> build() async {
    var active = true;
    StreamSubscription<CollaborationState>? subscription;
    Timer? timer;
    _ResumeObserver? observer;
    ref.onDispose(() {
      active = false;
      _active = false;
      unawaited(subscription?.cancel());
      timer?.cancel();
      if (observer != null) WidgetsBinding.instance.removeObserver(observer);
    });
    final repository = await ref.watch(collaborationRepositoryProvider.future);
    if (!active) return repository.state;
    _active = true;
    _repository = repository;
    subscription = repository.changes.listen((value) {
      if (active) state = AsyncData(value);
    });
    var ticks = 0, busy = false;
    void refresh() {
      if (!active || busy) return;
      busy = true;
      unawaited(() async {
        try {
          await repository.refreshLocal();
          if (ticks++ % 4 == 0) await repository.syncNow();
          if (active) {
            ref.read(collaborationBackgroundErrorProvider.notifier).state =
                null;
          }
        } catch (error) {
          if (active) {
            ref.read(collaborationBackgroundErrorProvider.notifier).state =
                error;
          }
        } finally {
          busy = false;
        }
      }());
    }

    timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
    observer = _ResumeObserver(() {
      ticks = 0;
      refresh();
    });
    WidgetsBinding.instance.addObserver(observer);
    scheduleMicrotask(refresh);
    return repository.state;
  }

  CollaborationRepository get _repo {
    if (!_active || _repository == null) {
      throw const CollaborationException('session_changed');
    }
    return _repository!;
  }

  Future<T> _edit<T>(Future<T> Function(CollaborationRepository) action) async {
    final repo = _repo;
    final result = await action(repo);
    if (_active) {
      unawaited(
        repo.syncNow().catchError((Object error) {
          if (_active) {
            ref.read(collaborationBackgroundErrorProvider.notifier).state =
                error;
          }
        }),
      );
    }
    return result;
  }

  Future<PrivateSyncPreview> previewPrivateSync() => _repo.previewPrivateSync();
  Future<LocalSpacesPublicationPreview> previewLocalSpacesPublication(
    List<String> ids,
  ) => _repo.previewLocalSpacesPublication(ids);
  Future<void> publishLocalSpaces(LocalSpacesPublicationPreview preview) =>
      _edit((repo) => repo.publishLocalSpaces(preview));
  Future<SharedScope> updateScopeMetadata(
    String scopeId,
    String name,
    String? address, {
    required int expectedRevision,
    String? requestId,
  }) => _edit(
    (repo) => repo.updateScopeMetadata(
      scopeId,
      name,
      address,
      expectedRevision: expectedRevision,
      requestId: requestId,
    ),
  );
  Future<bool> organizationAccessAvailable() =>
      _repo.organizationAccessAvailable();
  Future<OrganizationAccessPreview> previewOrganizationAccess(String id) =>
      _repo.previewOrganizationAccess(id);
  Future<SharedScope> applyOrganizationAccess(
    String id,
    String previewHash, {
    String? requestId,
  }) => _edit(
    (repo) =>
        repo.applyOrganizationAccess(id, previewHash, requestId: requestId),
  );
  Future<void> setOrganizationLeader(
    String id,
    String accountId,
    bool enabled, {
    String? requestId,
  }) => _edit(
    (repo) => repo.setOrganizationLeader(
      id,
      accountId,
      enabled,
      requestId: requestId,
    ),
  );
  Future<void> resumeOrganizationAccessChange(String id) =>
      _edit((repo) => repo.resumeOrganizationAccessChange(id));
  Future<void> saveGarden(
    String scopeId,
    Garden garden, {
    bool isNew = false,
  }) => _edit((repo) => repo.saveGarden(scopeId, garden, isNew: isNew));
  Future<void> deleteGarden(String scopeId, Garden garden) =>
      _edit((repo) => repo.deleteGarden(scopeId, garden));
  Future<void> enablePrivateSync({required int expectedRevision}) =>
      _repo.enablePrivateSync(expectedRevision: expectedRevision);
  Future<void> pausePrivateSync() => _repo.pausePrivateSync();
  Future<void> resumePrivateSync() => _repo.resumePrivateSync();
  Future<void> enroll({
    required String serverUrl,
    required String code,
    required String username,
    required String password,
    required String name,
    String deviceName = 'Jivie',
    bool allowLocalHttp = false,
  }) => _repo.enroll(
    serverUrl: serverUrl,
    code: code,
    username: username,
    password: password,
    name: name,
    deviceName: deviceName,
    allowLocalHttp: allowLocalHttp,
  );
  Future<Map<String, dynamic>> previewAccountDeletion() =>
      _repo.previewAccountDeletion();
  Future<List<PendingAccountDeletion>> pendingAccountDeletions() =>
      _repo.pendingAccountDeletions();
  Future<bool> cancelPendingAccountDeletion(PendingAccountDeletion request) =>
      _repo.cancelPendingAccountDeletion(request);
  Future<bool> checkAccountDeletion(PendingAccountDeletion request) =>
      _repo.checkAccountDeletion(request);
  Future<void> confirmAccountDeletion({
    required String previewHash,
    required String password,
    String? otp,
    List<Map<String, Object?>> ownershipTransfers = const [],
    List<Map<String, Object?>> resolutions = const [],
    List<String> ownedScopeDeletions = const [],
    Map<String, dynamic> review = const {},
  }) => _repo.confirmAccountDeletion(
    previewHash: previewHash,
    password: password,
    otp: otp,
    ownershipTransfers: ownershipTransfers,
    resolutions: resolutions,
    ownedScopeDeletions: ownedScopeDeletions,
    review: review,
  );
  Future<AccountStatus> accountStatus() => _repo.accountStatus();
  Future<void> requestEmailVerification({
    required String email,
    required String password,
    String? otp,
    String language = 'sl',
  }) => _repo.requestEmailVerification(
    email: email,
    password: password,
    otp: otp,
    language: language,
  );
  Future<void> confirmEmailVerification(String token) =>
      _repo.confirmEmailVerification(token);
  Future<void> requestPasswordReset({
    required String serverUrl,
    required String username,
    String language = 'sl',
    bool allowLocalHttp = false,
  }) => _repo.requestPasswordReset(
    serverUrl: serverUrl,
    username: username,
    language: language,
    allowLocalHttp: allowLocalHttp,
  );
  Future<void> confirmPasswordReset({
    required String serverUrl,
    required String token,
    required String password,
    String? otp,
    bool allowLocalHttp = false,
  }) => _repo.confirmPasswordReset(
    serverUrl: serverUrl,
    token: token,
    password: password,
    otp: otp,
    allowLocalHttp: allowLocalHttp,
  );
  RemotePushIdentity? get remotePushIdentity => _repo.remotePushIdentity;
  Future<RemotePushRegistrationState> configureRemotePush({
    required RemotePushIdentity identity,
    required String token,
    required String platform,
    required String language,
    required String projectId,
  }) => _repo.configureRemotePush(
    identity: identity,
    token: token,
    platform: platform,
    language: language,
    projectId: projectId,
  );
  Future<RemotePushRegistrationState> disableRemotePush({
    required RemotePushIdentity identity,
  }) => _repo.disableRemotePush(identity: identity);
  Future<RemotePushOpenResult> openRemotePushReference(
    RemotePushReference reference,
  ) => _repo.openRemotePushReference(reference);
  Future<bool> receiveRemotePushReference(RemotePushReference reference) =>
      _repo.receiveRemotePushReference(reference);

  Future<void> enableFinance(String scopeId, bool enabled) =>
      _repo.enableFinance(scopeId, enabled);
  Future<void> grantFinance({
    required String scopeId,
    required String accountId,
    required SharedFinanceGrant grant,
  }) =>
      _repo.grantFinance(scopeId: scopeId, accountId: accountId, grant: grant);
  Future<Map<String, SharedFinanceGrant>> financeGrants(String scopeId) =>
      _repo.financeGrants(scopeId);
  Future<SharedFinancePolicy> refreshFinancePolicy(String scopeId) =>
      _repo.refreshFinancePolicy(scopeId);
  Future<List<SharedFinanceAuditEntry>> financeAudit({
    required String scopeId,
    required String recordId,
    int? beforeRevision,
    int limit = 50,
  }) => _repo.financeAudit(
    scopeId: scopeId,
    recordId: recordId,
    beforeRevision: beforeRevision,
    limit: limit,
  );
  Future<void> resumeBlockedFinanceChanges(String scopeId) =>
      _repo.resumeBlockedFinanceChanges(scopeId);
  Future<void> resolveFinanceConflict({
    required String conflictId,
    required bool keepLocal,
  }) => _edit(
    (repo) => repo.resolveFinanceConflict(
      conflictId: conflictId,
      keepLocal: keepLocal,
    ),
  );
  Future<void> saveFinancePlanForScope({
    required String scopeId,
    required List<LocalFinanceAccount> accounts,
    required List<FinanceRecurrenceRule> rules,
  }) => _edit(
    (repo) => repo.saveFinancePlanForScope(
      scopeId: scopeId,
      accounts: accounts,
      rules: rules,
    ),
  );
  Future<void> updateFinanceRecurrenceRule(
    String scopeId,
    FinanceRecurrenceRule rule,
  ) => _edit((repo) => repo.updateFinanceRecurrenceRule(scopeId, rule));
  Future<void> materializeFinanceOccurrencesForScope(String scopeId) =>
      _edit((repo) => repo.materializeFinanceOccurrencesForScope(scopeId));
  Future<void> confirmFinanceOccurrenceForScope(
    String scopeId,
    SharedFinanceEntry entry, {
    required int amountMinor,
    required DateTime paidAt,
  }) => _edit(
    (repo) => repo.confirmFinanceOccurrenceForScope(
      scopeId,
      entry,
      amountMinor: amountMinor,
      paidAt: paidAt,
    ),
  );
  Future<String> createFinanceAccount({
    required String scopeId,
    required String name,
    required String currency,
    int openingBalanceMinor = 0,
    String? ownerAccountId,
  }) => _edit(
    (repo) => repo.createFinanceAccount(
      scopeId: scopeId,
      name: name,
      currency: currency,
      openingBalanceMinor: openingBalanceMinor,
      ownerAccountId: ownerAccountId,
    ),
  );
  Future<void> updateFinanceAccount(
    String scopeId,
    SharedFinanceAccount draft,
  ) => _edit((repo) => repo.updateFinanceAccount(scopeId, draft));
  Future<void> deleteFinanceAccount(String scopeId, String id) =>
      _edit((repo) => repo.deleteFinanceAccount(scopeId, id));
  Future<String> createFinanceEntry({
    required String scopeId,
    required String accountId,
    required FinanceEntryKind kind,
    SharedFinanceStatus status = SharedFinanceStatus.posted,
    required int amountMinor,
    required String currency,
    required String title,
    String notes = '',
    String category = '',
    String? payerAccountId,
    String? recipientAccountId,
    required DateTime occurredAt,
  }) => _edit(
    (repo) => repo.createFinanceEntry(
      scopeId: scopeId,
      accountId: accountId,
      kind: kind,
      status: status,
      amountMinor: amountMinor,
      currency: currency,
      title: title,
      notes: notes,
      category: category,
      payerAccountId: payerAccountId,
      recipientAccountId: recipientAccountId,
      occurredAt: occurredAt,
    ),
  );
  Future<void> updateFinanceEntry(String scopeId, SharedFinanceEntry draft) =>
      _edit((repo) => repo.updateFinanceEntry(scopeId, draft));
  Future<void> deleteFinanceEntry(String scopeId, String id) =>
      _edit((repo) => repo.deleteFinanceEntry(scopeId, id));
  Future<String> createFinanceTransfer({
    required String scopeId,
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    required String currency,
    SharedFinanceStatus status = SharedFinanceStatus.posted,
    required String title,
    String notes = '',
    required DateTime occurredAt,
  }) => _edit(
    (repo) => repo.createFinanceTransfer(
      scopeId: scopeId,
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amountMinor: amountMinor,
      currency: currency,
      status: status,
      title: title,
      notes: notes,
      occurredAt: occurredAt,
    ),
  );
  Future<void> updateFinanceTransfer(
    String scopeId,
    SharedFinanceTransfer draft,
  ) => _edit((repo) => repo.updateFinanceTransfer(scopeId, draft));
  Future<void> deleteFinanceTransfer(String scopeId, String id) =>
      _edit((repo) => repo.deleteFinanceTransfer(scopeId, id));
  Future<void> markInboxRead(Iterable<int> ids, {bool read = true}) =>
      _edit((repo) => repo.markInboxRead(ids, read: read));
  Future<void> setNotificationPreferences({
    required String scopeId,
    required String category,
    required SharedNotificationSettings settings,
  }) => _edit(
    (repo) => repo.setNotificationPreferences(
      scopeId: scopeId,
      category: category,
      settings: settings,
    ),
  );
  Future<String> putReminder({
    String? id,
    required String scopeId,
    required String targetType,
    required String targetId,
    required DateTime remindAt,
    int expectedRevision = 0,
    String? expectedPartition,
  }) => _edit(
    (repo) => repo.putReminder(
      id: id,
      scopeId: scopeId,
      targetType: targetType,
      targetId: targetId,
      remindAt: remindAt,
      expectedRevision: expectedRevision,
      expectedPartition: expectedPartition,
    ),
  );
  Future<void> cancelReminder(
    SharedScheduledReminder reminder, {
    String? expectedPartition,
  }) => _edit(
    (repo) =>
        repo.cancelReminder(reminder, expectedPartition: expectedPartition),
  );
  Future<NotificationOpenResult> openNotificationTarget(
    NotificationTarget target,
  ) async {
    if (!target.isPersonal) return _repo.openNotificationTarget(target);
    final db = await ref.read(localDatabaseProvider.future);
    final storage = SqliteOrganizerStorage(
      db,
      workspaceId: target.localWorkspaceId,
    );
    await storage.initialize();
    final catalog = await db.rows('SELECT data FROM local_spaces WHERE id=?', [
      target.localWorkspaceId,
    ]);
    if (catalog.isEmpty) {
      return NotificationOpenResult(
        status: NotificationOpenStatus.deleted,
        target: target,
      );
    }
    final personal = await storage.read();
    // Bound catalog sources are parked; only the concrete shared target routes them.
    if (personal.recordIds.isEmpty) {
      return NotificationOpenResult(
        status: NotificationOpenStatus.deleted,
        target: target,
      );
    }
    final valid = target.records.every(
      (r) => switch (r.type) {
        'financeEntry' || 'personalFinanceEntry' => personal.financeEntries.any(
          (v) => v.id == r.recordId,
        ),
        'task' => personal.tasks.any((v) => v.id == r.recordId),
        'event' => personal.events.any((v) => v.id == r.recordId),
        'project' => personal.projects.any((v) => v.id == r.recordId),
        'shoppingList' => personal.shoppingLists.any((v) => v.id == r.recordId),
        'shoppingItem' => personal.shoppingItems.any((v) => v.id == r.recordId),
        _ => false,
      },
    );
    return NotificationOpenResult(
      status: valid
          ? NotificationOpenStatus.available
          : NotificationOpenStatus.deleted,
      target: target,
    );
  }

  /// Refresh an already visible task without syncing the entire account.
  Future<NotificationOpenResult> refreshVisibleTaskTarget(
    NotificationTarget target,
  ) => target.isPersonal
      ? openNotificationTarget(target)
      : _repo.refreshVisibleTaskTarget(target);

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
    String? otp,
    bool allowLocalHttp = false,
    String deviceName = 'Jivie',
  }) => _repo.login(
    serverUrl: serverUrl,
    username: username,
    password: password,
    otp: otp,
    allowLocalHttp: allowLocalHttp,
    deviceName: deviceName,
  );
  Future<void> registerWithInvitation({
    required String serverUrl,
    required String invitationToken,
    required String username,
    required String name,
    required String password,
    bool allowLocalHttp = false,
    String deviceName = 'Jivie',
  }) => _repo.registerWithInvitation(
    serverUrl: serverUrl,
    invitationToken: invitationToken,
    username: username,
    name: name,
    password: password,
    allowLocalHttp: allowLocalHttp,
    deviceName: deviceName,
  );
  Future<SharedInvitationPreview> previewInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) => _repo.previewInvitation(
    serverUrl: serverUrl,
    token: token,
    allowLocalHttp: allowLocalHttp,
  );
  Future<bool> signOut() => _repo.signOut();
  Future<void> selectSpace(String? scopeId) => _repo.selectSpace(scopeId);
  Future<void> selectAllSpaces() => _repo.selectAllSpaces();
  Future<void> archiveProjectScope(
    String scopeId, {
    required bool archived,
    String? requestId,
  }) => _repo.archiveProjectScope(
    scopeId,
    archived: archived,
    requestId: requestId,
  );
  Future<void> syncNow() => _repo.syncNow();
  Future<String> createScope(
    String name, {
    SharedScopeKind kind = SharedScopeKind.household,
    String? organizationId,
    String? id,
    String? requestId,
  }) => _repo.createScope(
    name,
    kind: kind,
    organizationId: organizationId,
    id: id,
    requestId: requestId,
  );
  Future<String> createPerson({
    required String scopeId,
    required String name,
    String notes = '',
  }) => _edit(
    (repo) => repo.createPerson(scopeId: scopeId, name: name, notes: notes),
  );
  Future<void> updatePerson(String scopeId, HouseholdPerson person) =>
      _edit((repo) => repo.updatePerson(scopeId, person));
  Future<void> archivePerson(
    String scopeId,
    HouseholdPerson person, {
    bool archived = true,
  }) =>
      _edit((repo) => repo.archivePerson(scopeId, person, archived: archived));
  Future<List<SharedMember>> members(String scopeId) => _repo.members(scopeId);
  Future<List<SharedInvitation>> invitations(String scopeId) =>
      _repo.invitations(scopeId);
  Future<SharedInvitation> createInvitation({
    required String scopeId,
    required String recipientUsername,
    SharedRole role = SharedRole.member,
  }) => _repo.createInvitation(
    scopeId: scopeId,
    recipientUsername: recipientUsername,
    role: role,
  );
  Future<void> acceptInvitation(String token) => _repo.acceptInvitation(token);
  Future<void> revokeInvitation(String scopeId, String invitationId) =>
      _repo.revokeInvitation(scopeId, invitationId);
  Future<void> revokeMember({required String scopeId, required int userId}) =>
      _repo.revokeMember(scopeId: scopeId, userId: userId);
  Future<void> resumeBlockedChanges(String scopeId) =>
      _repo.resumeBlockedChanges(scopeId);
  Future<void> resolveConflict({
    required String conflictId,
    required bool keepLocal,
  }) => _edit(
    (repo) =>
        repo.resolveConflict(conflictId: conflictId, keepLocal: keepLocal),
  );
  Future<String> exportUnsentWork() => _repo.exportUnsentWork();
  Future<String> createShoppingList({
    required String scopeId,
    required String title,
  }) =>
      _edit((repo) => repo.createShoppingList(scopeId: scopeId, title: title));
  Future<void> updateShoppingList(String scopeId, LocalShoppingList draft) =>
      _edit((repo) => repo.updateShoppingList(scopeId, draft));
  Future<void> deleteShoppingList(String scopeId, String id) =>
      _edit((repo) => repo.deleteShoppingList(scopeId, id));
  Future<String> createShoppingItem({
    required String scopeId,
    required String listId,
    required String title,
    String quantity = '',
  }) => _edit(
    (repo) => repo.createShoppingItem(
      scopeId: scopeId,
      listId: listId,
      title: title,
      quantity: quantity,
    ),
  );
  Future<void> updateShoppingItem(String scopeId, LocalShoppingItem draft) =>
      _edit((repo) => repo.updateShoppingItem(scopeId, draft));
  Future<void> deleteShoppingItem(String scopeId, String id) =>
      _edit((repo) => repo.deleteShoppingItem(scopeId, id));
  Future<void> setShoppingItemChecked(String scopeId, String id, bool value) =>
      _edit((repo) => repo.setShoppingItemChecked(scopeId, id, value));
  Future<String> createEvent({
    required String scopeId,
    required String title,
    String notes = '',
    required DateTime startAt,
    DateTime? endAt,
    String? projectId,
    Iterable<String> assigneeAccountIds = const [],
  }) => _edit(
    (repo) => repo.createEvent(
      scopeId: scopeId,
      title: title,
      notes: notes,
      startAt: startAt,
      endAt: endAt,
      projectId: projectId,
      assigneeAccountIds: assigneeAccountIds,
    ),
  );
  Future<void> updateEvent(String scopeId, SharedEvent draft) =>
      _edit((repo) => repo.updateEvent(scopeId, draft));
  Future<void> deleteEvent(String scopeId, String id) =>
      _edit((repo) => repo.deleteEvent(scopeId, id));
  Future<String> createProject({
    required String scopeId,
    required String title,
    String description = '',
    DateTime? startAt,
    DateTime? endAt,
    ProjectArea area = ProjectArea.home,
    Iterable<ProjectPhase> phases = const [],
    int? availabilityMinutes,
    AvailabilityPeriod? availabilityPeriod,
  }) => _edit(
    (repo) => repo.createProject(
      scopeId: scopeId,
      title: title,
      description: description,
      area: area,
      phases: phases,
      availabilityMinutes: availabilityMinutes,
      availabilityPeriod: availabilityPeriod,
      startAt: startAt,
      endAt: endAt,
    ),
  );
  Future<void> updateProject(String scopeId, LocalProject draft) =>
      _edit((repo) => repo.updateProject(scopeId, draft));
  Future<void> deleteProject(String scopeId, String id) =>
      _edit((repo) => repo.deleteProject(scopeId, id));
  Future<String> createTask({
    required String scopeId,
    required String title,
    String notes = '',
    String? projectId,
    DateTime? dueAt,
    DateTime? startAt,
    DateTime? endAt,
    Iterable<String> assigneeAccountIds = const [],
    String? assigneePersonId,
    Iterable<String> subjectPersonIds = const [],
    String? phaseId,
    int? estimateMinutes,
    int? availabilityMinutes,
    AvailabilityPeriod? availabilityPeriod,
    TaskTimerState timer = const TaskTimerState(),
  }) => _edit(
    (repo) => repo.createTask(
      scopeId: scopeId,
      title: title,
      notes: notes,
      projectId: projectId,
      assigneeAccountIds: assigneeAccountIds,
      assigneePersonId: assigneePersonId,
      subjectPersonIds: subjectPersonIds,
      phaseId: phaseId,
      estimateMinutes: estimateMinutes,
      availabilityMinutes: availabilityMinutes,
      availabilityPeriod: availabilityPeriod,
      timer: timer,
      dueAt: dueAt,
      startAt: startAt,
      endAt: endAt,
    ),
  );
  Future<void> saveTaskWithCost(
    String scopeId,
    LocalTask task, {
    bool isNew = false,
    TaskCostDraft? cost,
    bool removeCost = false,
    int? expectedFinanceRevision,
  }) => _edit(
    (repo) => repo.saveTaskWithCost(
      scopeId,
      task,
      isNew: isNew,
      cost: cost,
      removeCost: removeCost,
      expectedFinanceRevision: expectedFinanceRevision,
    ),
  );
  Future<LocalTask> toggleTaskTimer(String scopeId, LocalTask task) =>
      _edit((repo) => repo.toggleTaskTimer(scopeId, task));
  Future<void> updateTask(String scopeId, LocalTask draft) =>
      _edit((repo) => repo.updateTask(scopeId, draft));
  Future<void> deleteTask(String scopeId, String id) =>
      _edit((repo) => repo.deleteTask(scopeId, id));
  Future<void> setTaskCompleted(String scopeId, String id, bool value) =>
      _edit((repo) => repo.setTaskCompleted(scopeId, id, value));
  Future<String> publishShoppingList({
    required String scopeId,
    required LocalShoppingList list,
    required List<LocalShoppingItem> items,
  }) => _edit(
    (repo) =>
        repo.publishShoppingList(scopeId: scopeId, list: list, items: items),
  );
  Future<String> publishProject({
    required String scopeId,
    required LocalProject project,
    required List<LocalTask> tasks,
    List<HouseholdPerson> people = const [],
  }) => _edit(
    (repo) => repo.publishProject(
      scopeId: scopeId,
      project: project,
      tasks: tasks,
      people: people,
    ),
  );
}

class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this.onResume);
  final void Function() onResume;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
