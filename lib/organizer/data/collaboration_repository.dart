import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart' show Sha256;
import 'dart:math';
import '../domain/collaboration_models.dart';
import '../domain/organizer_models.dart';
import '../domain/local_space_models.dart';
import '../domain/linked_payment_models.dart';
import '../domain/garden_models.dart';
import '../domain/shared_payload_validation.dart';
import '../domain/shared_finance_validation.dart';
import '../domain/shared_dates.dart';
import 'collaboration_database.dart';
import 'collaboration_transport.dart';
import 'device_session_store.dart';
import 'pending_invitation_store.dart';
import 'remote_push_store.dart';
import 'account_deletion_store.dart';
import 'account_deletion_preview.dart';
import 'sqlite_organizer_storage.dart';
import 'portable_backup_document.dart';
import 'organizer_storage.dart';
import 'garden_storage.dart';
import 'linked_payments_repository.dart';
import 'organizer_repository.dart' show OrganizerConflictException;

part 'collaboration_organization_access.dart';
part 'collaboration_linked_payments.dart';
part 'collaboration_local_space_publication.dart';
part 'collaboration_garden_actions.dart';
part 'collaboration_account_actions.dart';
part 'collaboration_email_invitations.dart';
part 'collaboration_session_renewal.dart';
part 'collaboration_record_actions.dart';
part 'collaboration_person_actions.dart';
part 'collaboration_task_cost_actions.dart';
part 'collaboration_sync_actions.dart';
part 'collaboration_event_actions.dart';
part 'collaboration_notification_actions.dart';
part 'collaboration_notification_sync.dart';
part 'collaboration_notification_routing.dart';
part 'collaboration_finance_actions.dart';
part 'collaboration_finance_sync.dart';
part 'collaboration_remote_push_actions.dart';
part 'collaboration_remote_push_routing.dart';
part 'collaboration_remote_push_cleanup.dart';
part 'collaboration_private_actions.dart';
part 'collaboration_account_recovery.dart';
part 'collaboration_backup_actions.dart';
part 'collaboration_account_deletion.dart';

class CollaborationRepository {
  CollaborationRepository(
    this.database,
    this.transport,
    this.sessionStore, {
    DateTime Function()? clock,
    this.pushStore,
    this.ownsDatabase = true,
    this.deletionStore = const SecureAccountDeletionStore(),
    this.invitationStore = const SecurePendingInvitationStore(),
  }) : clock = clock ?? DateTime.now;
  final CollaborationDatabase database;
  final CollaborationTransport transport;
  final DeviceSessionStore sessionStore;
  final RemotePushStore? pushStore;
  final bool ownsDatabase;
  final AccountDeletionStore deletionStore;
  final PendingInvitationStore invitationStore;
  final DateTime Function() clock;
  final _events = StreamController<CollaborationState>.broadcast();
  Stream<CollaborationState> get changes => _events.stream;
  CollaborationState state = CollaborationState();
  DeviceSession? _session;
  Future<void> _secureQueue = Future.value();
  Future<void> _deletionQueue = Future.value();
  Completer<void>? _syncDone, _pushSyncDone;
  Future<void> _pushSecureQueue = Future.value();
  bool _pushSyncing = false, _pushRestored = false;
  RemotePushIntent? _pushIntent;
  RemotePushRegistrationState _remotePushState =
      const RemotePushRegistrationState();
  int _epoch = 0;
  String? _sessionInvalidReason;
  DateTime? _pushStateCheckedAt;
  int _recordContractVersion = 1;
  int _financeContractVersion = 1;
  int _accountDeletionPolicyVersion = 1;
  bool _sessionRenewalSupported = false;
  Future<void>? _sessionRenewal;
  int? _sessionRenewalEpoch;
  bool _scopeAccessChangesSupported = false;
  bool _organizationsSupported = false,
      _householdPeopleSupported = false,
      _projectArchivingSupported = false;
  bool _inboxSupported = false;
  bool _emailInvitationsSupported = false;
  bool _accountDeletionSupported = false;
  bool _privateSyncSupported = false;
  bool _emailVerificationSupported = false, _passwordResetSupported = false;
  bool _financeSupported = false;
  bool _externalPushSupported = false, _smtpSupported = false;
  String? _pushProjectId;
  bool _closed = false;
  bool _syncing = false;
  int? _syncEpoch, _fullSyncEpoch;
  DateTime? _lastSyncAttemptAt, _lastSuccessfulSyncAt;
  CollaborationException? _lastError;
  final _leaseOwner = newSharedId();
  final _visibleTaskRefreshes = <String, Future<NotificationOpenResult>>{};

  void _resetSyncEvidence() {
    _lastSyncAttemptAt = null;
    _lastSuccessfulSyncAt = null;
    _fullSyncEpoch = null;
  }

  Future<void> initialize() async {
    await database.rows('SELECT name FROM local_meta LIMIT 1');
    _session = await sessionStore.read();
    if (_session != null &&
        (await database.rows('SELECT value FROM local_meta WHERE name=?', [
          'deleted_account:${_session!.profile.partition}',
        ])).isNotEmpty) {
      _session = null;
      await sessionStore.clear();
    }
    if (_session != null && pushStore != null) {
      final cleanup = await pushStore!.readCleanups();
      if (cleanup.any((c) => c.matches(_session!.profile))) {
        // Cleanup committed before a crash during secure session deletion.
        _session = null;
        await sessionStore.clear();
      }
    }
    if (_session != null) {
      normalizeCollaborationServer(
        _session!.profile.serverUrl,
        allowLocalHttp: _session!.profile.allowLocalHttp,
      );
      await _saveAccount(_session!.profile);
      await _loadCapabilities(_session!.profile.partition);
      await _restoreRemotePush(_epoch);
      final invalid = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [
          'invalid_session:${_session!.profile.partition}:${_session!.profile.deviceId}',
        ],
      );
      if (invalid.isNotEmpty) {
        _sessionInvalidReason = invalid.first['value'] as String;
      }
      if (_sessionInvalidReason != null) {
        _remotePushState = RemotePushRegistrationState(
          identity: remotePushIdentity,
          status: RemotePushRegistrationStatus.blocked,
          errorCode: _sessionInvalidReason,
        );
      }
      if (!_session!.profile.expiresAt.isAfter(clock())) {
        _lastError = const CollaborationException('auth_required');
      }
      // Authentication expiry does not revoke previously downloaded content.
      if (_sessionInvalidReason != 'device_revoked') {
        database.activatePersonal(_session!.profile);
      }
    }
    await refreshLocal();
  }

  Future<void> refreshLocal() async {
    final epoch = _epoch, profile = _session?.profile;
    if (_closed) return;
    if (profile != null &&
        (await database.rows('SELECT value FROM local_meta WHERE name=?', [
          'deleted_account:${profile.partition}',
        ])).isNotEmpty) {
      if (epoch != _epoch || _closed) {
        return;
      }
      _session = null;
      final endedEpoch = ++_epoch;
      _resetSyncEvidence();
      if (database.personalProfile?.partition == profile.partition) {
        database.activatePersonal(null);
      }
      await _secure(endedEpoch, () async {
        final stored = await sessionStore.read();
        if (stored?.profile.partition == profile.partition) {
          await sessionStore.clear();
        }
      });
      await refreshLocal();
      return;
    }
    if (profile == null) {
      final selection = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['all_spaces_selected:local'],
      );
      if (epoch != _epoch || _closed) return;
      state = CollaborationState(
        lastError: _lastError,
        allSpacesSelected: selection.firstOrNull?['value'] == '1',
      );
    } else {
      final deletionPending = (await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['deletion_pending:${profile.partition}'],
      )).isNotEmpty;
      if (deletionPending &&
          database.personalProfile?.partition == profile.partition) {
        database.activatePersonal(null);
      }
      final scopes = await database.rows(
        'SELECT data,blocked FROM scopes WHERE partition=? ORDER BY id',
        [profile.partition],
      );
      final parsedScopes = scopes
          .map(
            (r) => SharedScope.fromJson({
              ..._map(r['data']),
              'blocked': r['blocked'] == 1,
            }),
          )
          .toList();
      final data = <String, SharedScopeData>{};
      final members = <String, List<SharedMember>>{};
      final financePolicies = <String, SharedFinancePolicy>{};
      final financeComplete = <String, bool>{};
      for (final scope in parsedScopes) {
        if (!scope.revoked) {
          data[scope.id] = await _scopeData(profile.partition, scope.id);
          financePolicies[scope.id] = await _cachedFinancePolicy(
            profile.partition,
            scope.id,
          );
          financeComplete[scope.id] =
              (await database.rows(
                'SELECT finance_complete FROM scopes WHERE partition=? AND id=?',
                [profile.partition, scope.id],
              )).first['finance_complete'] ==
              1;
          members[scope.id] = (await database.rows(
            'SELECT data FROM members WHERE partition=? AND scope_id=?',
            [profile.partition, scope.id],
          )).map((r) => SharedMember.fromJson(_map(r['data']))).toList();
        }
      }
      final inbox =
          (await database.rows(
                'SELECT data FROM inbox WHERE partition=? ORDER BY id DESC',
                [profile.partition],
              ))
              .map((r) => SharedInboxEntry.fromJson(_map(r['data'])))
              .where(
                (e) => parsedScopes.any((s) => s.id == e.scopeId && !s.revoked),
              )
              .toList();
      final notificationPreferences = <String, SharedNotificationPreferences>{};
      for (final row in await database.rows(
        'SELECT scope_id,data FROM notification_preferences WHERE partition=?',
        [profile.partition],
      )) {
        final scopeId = row['scope_id'] as String;
        if (parsedScopes.any((s) => s.id == scopeId && !s.revoked)) {
          notificationPreferences[scopeId] = SharedNotificationPreferences(
            scopeId: scopeId,
            categories: _map(row['data']).map(
              (k, v) => MapEntry(
                k,
                SharedNotificationSettings.fromJson(v as Map<String, dynamic>),
              ),
            ),
          );
        }
      }
      final reminderCommandStates = <String, String>{};
      for (final command in await database.rows(
        "SELECT entity_key,state FROM commands WHERE partition=? AND entity_key LIKE 'reminder:%'",
        [profile.partition],
      )) {
        final id = (command['entity_key'] as String).substring(
          'reminder:'.length,
        );
        // Older local snapshots predate syncState. Never describe their queued
        // or rejected operation as a confirmed server schedule after restore.
        if (command['state'] == 'pending') {
          reminderCommandStates[id] = 'queued';
        } else if (!reminderCommandStates.containsKey(id)) {
          reminderCommandStates[id] = 'blocked';
        }
      }
      final reminders =
          (await database.rows(
                'SELECT data FROM scheduled_reminders WHERE partition=?',
                [profile.partition],
              ))
              .map((r) {
                final value = _map(r['data']);
                return SharedScheduledReminder.fromJson({
                  ...value,
                  if (value['syncState'] == null &&
                      reminderCommandStates[value['id']] != null)
                    'syncState': reminderCommandStates[value['id']],
                });
              })
              .where(
                (e) => parsedScopes.any(
                  (s) => s.id == e.scopeId && !s.revoked && !s.archived,
                ),
              )
              .toList();
      final commands =
          (await database.rows(
                'SELECT COUNT(*) AS count FROM commands WHERE partition=?',
                [profile.partition],
              )).first['count']
              as int;
      final blockedCommands =
          (await database.rows(
                "SELECT COUNT(*) AS count FROM commands WHERE partition=? AND state='blocked'",
                [profile.partition],
              )).first['count']
              as int;
      final outbox = await database.rows(
        'SELECT COUNT(*) AS count FROM outbox WHERE partition=?',
        [profile.partition],
      );
      final blocked = await database.rows(
        "SELECT COUNT(*) AS count FROM outbox WHERE partition=? AND state='blocked'",
        [profile.partition],
      );
      final conflicts = await database.rows(
        'SELECT c.*,r.payload AS candidate FROM conflicts c JOIN records r ON r.partition=c.partition AND r.scope_id=c.scope_id AND r.id=c.record_id WHERE c.partition=?',
        [profile.partition],
      );
      final financeQueue = await database.rows(
        'SELECT state FROM finance_outbox WHERE partition=?',
        [profile.partition],
      );
      final financeConflicts = <SharedFinanceConflict>[];
      for (final row in await database.rows(
        'SELECT c.*,r.payload AS candidate FROM finance_conflicts c JOIN finance_records r ON r.partition=c.partition AND r.scope_id=c.scope_id AND r.id=c.record_id WHERE c.partition=?',
        [profile.partition],
      )) {
        if (financePolicies[row['scope_id']]?.canRead != true) continue;
        final remote = row['remote'] == null ? null : _map(row['remote']);
        financeConflicts.add(
          SharedFinanceConflict(
            id: row['id'] as String,
            scopeId: row['scope_id'] as String,
            recordId: row['record_id'] as String,
            recordType: SharedFinanceRecordType.values.byName(
              row['type'] as String,
            ),
            reason: row['reason'] as String,
            remoteDeleted: remote?['deleted'] == true,
            localPayload: row['candidate'] == null
                ? null
                : _map(row['candidate']),
            remotePayload: remote?['payload'] as Map<String, dynamic>?,
          ),
        );
      }
      inbox.removeWhere(
        (e) =>
            e.category == 'finance' &&
            financePolicies[e.scopeId]?.canRead != true,
      );
      reminders.removeWhere(
        (e) =>
            isFinancialRecordType(e.targetType) &&
            financePolicies[e.scopeId]?.canRead != true,
      );
      if (epoch != _epoch || _closed) return;
      final selectedSpace = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['selected_space:${profile.partition}'],
      );
      final allSpaces = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['all_spaces_selected:${profile.partition}'],
      );
      final privateState = await _privateSyncState(profile);
      final runtimePrivateIds = <String, String>{};
      if (!deletionPending) {
        for (final row in await database.rows(
          'SELECT r.id FROM records r JOIN personal_workspaces w ON w.partition=r.partition AND w.scope_id=r.scope_id WHERE r.partition=? AND w.enabled=1 UNION SELECT f.id FROM finance_records f JOIN personal_workspaces w ON w.partition=f.partition AND w.scope_id=f.scope_id WHERE f.partition=? AND w.enabled=1',
          [profile.partition, profile.partition],
        )) {
          runtimePrivateIds[row['id'] as String] = row['id'] as String;
        }
        for (final row in await database.rows(
          'SELECT id,remote_id FROM personal_record_map WHERE workspace=?',
          ['private:${profile.partition}'],
        )) {
          runtimePrivateIds[row['remote_id'] as String] = row['id'] as String;
        }
      }
      if (epoch != _epoch || _closed) return;
      state = CollaborationState(
        allSpacesSelected: allSpaces.firstOrNull?['value'] == '1',
        selectedSpaceId:
            selectedSpace.isEmpty || selectedSpace.first['value'] == ''
            ? null
            : selectedSpace.first['value'] as String,
        session: profile,
        remotePushRegistration: _remotePushState,
        sessionInvalid: _sessionInvalidReason != null || deletionPending,
        localAccessAllowed:
            !deletionPending && _sessionInvalidReason != 'device_revoked',
        deletionPending: deletionPending,
        privateSync: privateState,
        privateRecordIds: runtimePrivateIds,
        pushProjectId: _pushProjectId,
        financePolicies: financePolicies,
        financeSnapshotComplete: financeComplete,
        financeConflicts: financeConflicts,
        financePendingCount: financeQueue.length,
        financeBlockedCount: financeQueue
            .where((e) => e['state'] == 'blocked')
            .length,
        sessionRenewalSupported: _sessionRenewalSupported,
        organizationsSupported: _organizationsSupported,
        householdPeopleSupported: _householdPeopleSupported,
        projectArchivingSupported: _projectArchivingSupported,
        inboxSupported: _inboxSupported,
        financeSupported: _financeSupported,
        financeContractVersion: _financeContractVersion,
        recordContractVersion: _recordContractVersion,
        emailVerificationSupported: _emailVerificationSupported,
        resetSupported: _passwordResetSupported,
        externalPushSupported: _externalPushSupported,
        smtpSupported: _smtpSupported,
        emailInvitationsSupported: _emailInvitationsSupported,
        members: members,
        scopes: parsedScopes,
        data: data,
        pendingCount:
            (outbox.first['count'] as int) + commands + financeQueue.length,
        inbox: inbox,
        notificationPreferences: notificationPreferences,
        scheduledReminders: reminders,
        blockedCount: (blocked.first['count'] as int) + blockedCommands,
        isSyncing:
            (_syncing && _syncEpoch == _epoch) || _fullSyncEpoch == _epoch,
        lastSyncAttemptAt: _lastSyncAttemptAt,
        lastSuccessfulSyncAt: _lastSuccessfulSyncAt,
        lastError: _lastError,
        conflicts: conflicts.map(
          (r) => SharedConflict(
            id: r['id'] as String,
            scopeId: r['scope_id'] as String,
            recordId: r['record_id'] as String,
            recordType: SharedRecordType.values.byName(r['type'] as String),
            reason: r['reason'] as String,
            remoteDeleted:
                r['remote'] != null && _map(r['remote'])['deleted'] == true,
            localPayload: r['candidate'] == null ? null : _map(r['candidate']),
            remotePayload: r['remote'] == null
                ? null
                : _map(r['remote'])['payload'] as Map<String, dynamic>?,
          ),
        ),
      );
    }
    if (epoch == _epoch && !_closed) {
      _events.add(state);
      database.personalChanged();
    }
  }

  Future<SharedScopeData> _scopeData(String partition, String scopeId) async {
    final rows = await database.rows(
      'SELECT * FROM records WHERE partition=? AND scope_id=? AND deleted=0 ORDER BY id',
      [partition, scopeId],
    );
    final projects = <LocalProject>[],
        tasks = <LocalTask>[],
        lists = <LocalShoppingList>[],
        items = <LocalShoppingItem>[];
    final people = <HouseholdPerson>[];
    final gardens = <Garden>[];
    final personalFinanceEntries = <FinanceEntry>[];
    final events = <SharedEvent>[];
    for (final r in rows) {
      final json = {
        ...normalizeSharedPayloadDates(_map(r['payload'])),
        'id': r['id'],
        'revision': r['local_revision'],
        'createdByAccountId': r['remote'] == null
            ? null
            : _map(r['remote'])['createdByAccountId'],
        'updatedByAccountId': r['remote'] == null
            ? null
            : _map(r['remote'])['updatedByAccountId'],
      };
      switch (SharedRecordType.values.byName(r['type'] as String)) {
        case SharedRecordType.garden:
          gardens.add(
            Garden.fromJson({
              ..._map(r['payload']),
              'revision': r['local_revision'],
            }),
          );
        case SharedRecordType.householdPerson:
          people.add(HouseholdPerson.fromJson(json));
        case SharedRecordType.event:
          events.add(SharedEvent.fromJson(json));
        case SharedRecordType.project:
          projects.add(LocalProject.fromJson(json));
        case SharedRecordType.task:
          tasks.add(LocalTask.fromJson(json));
        case SharedRecordType.shoppingList:
          lists.add(LocalShoppingList.fromJson(json));
        case SharedRecordType.shoppingItem:
          items.add(LocalShoppingItem.fromJson(json));
      }
    }
    final financeAccounts = <SharedFinanceAccount>[],
        financeEntries = <SharedFinanceEntry>[],
        financeTransfers = <SharedFinanceTransfer>[];
    final financeRecurrenceRules = <FinanceRecurrenceRule>[];
    final complete = (await database.rows(
      'SELECT finance_complete FROM scopes WHERE partition=? AND id=?',
      [partition, scopeId],
    )).firstOrNull;
    if (complete?['finance_complete'] == 1 &&
        (await _cachedFinancePolicy(partition, scopeId)).canRead) {
      for (final row in await database.rows(
        "SELECT r.*,EXISTS(SELECT 1 FROM finance_outbox o WHERE o.partition=r.partition AND o.scope_id=r.scope_id AND o.record_id=r.id AND o.state!='pending') AS rejected FROM finance_records r WHERE partition=? AND scope_id=?",
        [partition, scopeId],
      )) {
        final remote = row['remote'] == null ? null : _map(row['remote']);
        final useCanonical = row['rejected'] == 1;
        if (useCanonical && (remote == null || remote['deleted'] == true)) {
          continue;
        }
        if (!useCanonical && row['deleted'] == 1) continue;
        final visiblePayload = useCanonical
            ? remote!['payload'] as Map<String, dynamic>
            : _map(row['payload']);
        final json = {
          ...visiblePayload,
          'id': row['id'],
          'revision': row['local_revision'],
          'createdByAccountId': remote?['createdByAccountId'],
          'updatedByAccountId': remote?['updatedByAccountId'],
        };
        switch (SharedFinanceRecordType.values.byName(row['type'] as String)) {
          case SharedFinanceRecordType.personalFinanceAccount:
            break;
          case SharedFinanceRecordType.financeRecurrenceRule:
            financeRecurrenceRules.add(FinanceRecurrenceRule.fromJson(json));
          case SharedFinanceRecordType.personalFinanceEntry:
            personalFinanceEntries.add(FinanceEntry.fromJson(json));
          case SharedFinanceRecordType.financeAccount:
            financeAccounts.add(SharedFinanceAccount.fromJson(json));
          case SharedFinanceRecordType.financeEntry:
            financeEntries.add(SharedFinanceEntry.fromJson(json));
          case SharedFinanceRecordType.financeTransfer:
            financeTransfers.add(SharedFinanceTransfer.fromJson(json));
        }
      }
    }
    final liveAccounts = {for (final a in financeAccounts) a.id: a.currency};
    financeEntries.removeWhere((e) => liveAccounts[e.accountId] != e.currency);
    financeTransfers.removeWhere(
      (e) =>
          liveAccounts[e.fromAccountId] != e.currency ||
          liveAccounts[e.toAccountId] != e.currency,
    );
    return SharedScopeData(
      gardens: gardens,
      people: people,
      personalFinanceEntries: personalFinanceEntries,
      financeAccounts: financeAccounts,
      financeRecurrenceRules: financeRecurrenceRules,
      financeEntries: financeEntries,
      financeTransfers: financeTransfers,
      events: events,
      projects: projects,
      tasks: tasks,
      shoppingLists: lists,
      shoppingItems: items,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_epoch;
    transport.close();
    await _secureQueue;
    await _pushSecureQueue;
    await _syncDone?.future;
    await _pushSyncDone?.future;
    if (ownsDatabase) await database.close();
    await _events.close();
  }

  static Map<String, dynamic> _map(Object? value) =>
      jsonDecode(value as String) as Map<String, dynamic>;
}

String newSharedId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
