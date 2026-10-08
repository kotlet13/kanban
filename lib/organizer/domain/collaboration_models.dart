import 'dart:collection';

import 'organizer_models.dart';
export 'household_person.dart';
import 'shared_event.dart';
import 'shared_finance_models.dart';
import 'notification_models.dart';
import 'remote_push_models.dart';
export 'shared_event.dart';
export 'shared_finance_models.dart';
export 'notification_models.dart';
export 'remote_push_models.dart';
export 'private_sync_models.dart';
import 'private_sync_models.dart';

enum SharedRole { owner, member, viewer }

enum SharedScopeKind { household, project, personal, organization }

enum SharedRecordType {
  project,
  task,
  shoppingList,
  shoppingItem,
  event,
  householdPerson,
}

class CollaborationException implements Exception {
  const CollaborationException(this.code);
  final String code;
  @override
  String toString() => 'CollaborationException($code)';
}

class AccountSession {
  const AccountSession({
    required this.serverUrl,
    required this.serverId,
    required this.accountId,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.deviceId,
    required this.expiresAt,
    this.allowLocalHttp = false,
  });
  final String serverUrl;
  final String serverId;
  final String accountId;
  final int userId;
  final String username;
  final String displayName;
  final String deviceId;
  final DateTime expiresAt;
  final bool allowLocalHttp;
  String get partition =>
      '${Uri.encodeComponent(serverUrl)}:$serverId:$accountId';
  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'serverId': serverId,
    'accountId': accountId,
    'userId': userId,
    'username': username,
    'displayName': displayName,
    'deviceId': deviceId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'allowLocalHttp': allowLocalHttp,
  };
  factory AccountSession.fromJson(Map<String, dynamic> json) => AccountSession(
    serverUrl: readString(json, 'serverUrl'),
    serverId: readString(json, 'serverId'),
    accountId: readString(json, 'accountId'),
    userId: readInt(json, 'userId'),
    username: readString(json, 'username'),
    displayName: readString(json, 'displayName'),
    deviceId: readString(json, 'deviceId'),
    expiresAt: readDate(json, 'expiresAt'),
    allowLocalHttp: readBool(json, 'allowLocalHttp'),
  );
}

class SharedScope {
  const SharedScope({
    required this.id,
    required this.name,
    required this.kind,
    required this.role,
    this.organizationId,
    this.projectRootId,
    this.requiredRecordContractVersion = 1,
    this.sequence = 0,
    this.archived = false,
    this.revoked = false,
    this.blocked = false,
  });
  final String id;
  final String name;
  final SharedScopeKind kind;
  final String? organizationId, projectRootId;
  final int requiredRecordContractVersion, sequence;
  final SharedRole role;
  final bool archived;
  final bool revoked;
  final bool blocked;
  bool get canEdit =>
      !revoked && !archived && !blocked && role != SharedRole.viewer;
  bool get canManage => !revoked && role == SharedRole.owner;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'organizationId': organizationId,
    'projectRootId': projectRootId,
    'requiredRecordContractVersion': requiredRecordContractVersion,
    'sequence': sequence,
    'archived': archived,
    'role': role.name,
    'revoked': revoked,
    'blocked': blocked,
  };
  factory SharedScope.fromJson(Map<String, dynamic> json) => SharedScope(
    id: readString(json, 'id'),
    name: readString(json, 'name'),
    kind: SharedScopeKind.values.byName(readString(json, 'kind')),
    organizationId: readNullableString(json, 'organizationId'),
    projectRootId: readNullableString(json, 'projectRootId'),
    requiredRecordContractVersion: json['requiredRecordContractVersion'] is int
        ? json['requiredRecordContractVersion'] as int
        : 1,
    sequence: json['sequence'] is int ? json['sequence'] as int : 0,
    archived: json['archived'] == true,
    role: SharedRole.values.byName(readString(json, 'role')),
    revoked: json['revoked'] == true,
    blocked: json['blocked'] == true,
  );
}

class SharedMember {
  const SharedMember({
    required this.userId,
    this.accountId = '',
    required this.username,
    required this.displayName,
    required this.role,
    required this.active,
  });
  final int userId;
  final String accountId;
  final String username;
  final String displayName;
  final SharedRole role;
  final bool active;
  Map<String, Object?> toJson() => {
    'userId': userId,
    'accountId': accountId,
    'username': username,
    'displayName': displayName,
    'role': role.name,
    'active': active,
  };
  factory SharedMember.fromJson(Map<String, dynamic> json) => SharedMember(
    userId: readInt(json, 'userId'),
    accountId: json['accountId'] is String ? readString(json, 'accountId') : '',
    username: readString(json, 'username'),
    displayName: readString(json, 'displayName'),
    role: SharedRole.values.byName(readString(json, 'role')),
    active: readBool(json, 'active'),
  );
}

class SharedInvitation {
  const SharedInvitation({
    required this.id,
    required this.scopeId,
    required this.recipientUsername,
    required this.role,
    required this.expiresAt,
    this.token,
    this.acceptedAt,
    this.revokedAt,
  });
  final String id;
  final String scopeId;
  final String recipientUsername;
  final SharedRole role;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;
  final String? token;
  factory SharedInvitation.fromJson(
    Map<String, dynamic> json, {
    String? token,
  }) => SharedInvitation(
    id: readString(json, 'id'),
    scopeId: readString(json, 'scopeId'),
    recipientUsername: readString(json, 'recipientUsername'),
    role: SharedRole.values.byName(readString(json, 'role')),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      readInt(json, 'expiresAt') * 1000,
      isUtc: true,
    ),
    acceptedAt: json['acceptedAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['acceptedAt'] as int) * 1000,
            isUtc: true,
          )
        : null,
    revokedAt: json['revokedAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['revokedAt'] as int) * 1000,
            isUtc: true,
          )
        : null,
    token: token,
  );
}

class SharedInvitationPreview {
  const SharedInvitationPreview({
    required this.scopeName,
    required this.scopeId,
    required this.kind,
    required this.recipientUsername,
    required this.role,
    required this.expiresAt,
    required this.registrationAllowed,
  });
  final String scopeName;
  final String scopeId;
  final SharedScopeKind kind;
  final String recipientUsername;
  final SharedRole role;
  final DateTime expiresAt;
  final bool registrationAllowed;
  bool get canRegister => registrationAllowed;
}

class SharedConflict {
  SharedConflict({
    required this.id,
    required this.scopeId,
    required this.recordId,
    required this.recordType,
    required this.reason,
    this.remoteDeleted = false,
    required Map<String, dynamic>? localPayload,
    required Map<String, dynamic>? remotePayload,
  }) : localPayload = localPayload == null
           ? null
           : UnmodifiableMapView(localPayload),
       remotePayload = remotePayload == null
           ? null
           : UnmodifiableMapView(remotePayload);
  final String id;
  final String scopeId;
  final String recordId;
  final SharedRecordType recordType;
  final String reason;
  final bool remoteDeleted;
  final Map<String, dynamic>? localPayload;
  final Map<String, dynamic>? remotePayload;
}

class SharedScopeData {
  SharedScopeData({
    Iterable<FinanceRecurrenceRule> financeRecurrenceRules = const [],
    Iterable<HouseholdPerson> people = const [],
    Iterable<SharedEvent> events = const [],
    Iterable<SharedFinanceAccount> financeAccounts = const [],
    Iterable<SharedFinanceEntry> financeEntries = const [],
    Iterable<SharedFinanceTransfer> financeTransfers = const [],
    Iterable<FinanceEntry> personalFinanceEntries = const [],
    Iterable<LocalProject> projects = const [],
    Iterable<LocalTask> tasks = const [],
    Iterable<LocalShoppingList> shoppingLists = const [],
    Iterable<LocalShoppingItem> shoppingItems = const [],
  }) : financeRecurrenceRules = List.unmodifiable(financeRecurrenceRules),
       people = List.unmodifiable(people),
       events = List.unmodifiable(events),
       financeAccounts = List.unmodifiable(financeAccounts),
       financeEntries = List.unmodifiable(financeEntries),
       personalFinanceEntries = List.unmodifiable(personalFinanceEntries),
       financeTransfers = List.unmodifiable(financeTransfers),
       projects = List.unmodifiable(projects),
       tasks = List.unmodifiable(tasks),
       shoppingLists = List.unmodifiable(shoppingLists),
       shoppingItems = List.unmodifiable(shoppingItems);
  final List<FinanceRecurrenceRule> financeRecurrenceRules;
  final List<HouseholdPerson> people;
  final List<SharedEvent> events;
  final List<SharedFinanceAccount> financeAccounts;
  final List<SharedFinanceEntry> financeEntries;
  final List<SharedFinanceTransfer> financeTransfers;
  final List<FinanceEntry> personalFinanceEntries;
  final List<LocalProject> projects;
  final List<LocalTask> tasks;
  final List<LocalShoppingList> shoppingLists;
  final List<LocalShoppingItem> shoppingItems;
}

class CollaborationState {
  CollaborationState({
    this.session,
    this.selectedSpaceId,
    this.pushProjectId,
    this.sessionInvalid = false,
    this.sessionRenewalSupported = false,
    this.organizationsSupported = false,
    this.householdPeopleSupported = false,
    this.projectArchivingSupported = false,
    this.deletionPending = false,
    this.privateSync = const PrivateSyncState(),
    Map<String, String> privateRecordIds = const {},
    this.remotePushRegistration = const RemotePushRegistrationState(),
    Iterable<SharedFinanceConflict> financeConflicts = const [],
    this.financePendingCount = 0,
    this.financeBlockedCount = 0,
    Map<String, bool> financeSnapshotComplete = const {},
    this.inboxSupported = false,
    this.financeSupported = false,
    this.financeContractVersion = 1,
    this.recordContractVersion = 1,
    this.emailVerificationSupported = false,
    this.resetSupported = false,
    this.externalPushSupported = false,
    this.smtpSupported = false,
    Map<String, List<SharedMember>> members = const {},
    Map<String, SharedFinancePolicy> financePolicies = const {},
    Iterable<SharedInboxEntry> inbox = const [],
    Map<String, SharedNotificationPreferences> notificationPreferences =
        const {},
    Iterable<SharedScheduledReminder> scheduledReminders = const [],
    Iterable<SharedScope> scopes = const [],
    Map<String, SharedScopeData> data = const {},
    Iterable<SharedConflict> conflicts = const [],
    this.pendingCount = 0,
    this.blockedCount = 0,
    this.isSyncing = false,
    this.lastError,
  }) : privateRecordIds = Map.unmodifiable(privateRecordIds),
       financeConflicts = List.unmodifiable(financeConflicts),
       financeSnapshotComplete = Map.unmodifiable(financeSnapshotComplete),
       members = Map.unmodifiable({
         for (final e in members.entries)
           e.key: List<SharedMember>.unmodifiable(e.value),
       }),
       financePolicies = Map.unmodifiable(financePolicies),
       inbox = List.unmodifiable(inbox),
       notificationPreferences = Map.unmodifiable(notificationPreferences),
       scheduledReminders = List.unmodifiable(scheduledReminders),
       scopes = List.unmodifiable(scopes),
       data = UnmodifiableMapView(data),
       conflicts = List.unmodifiable(conflicts);
  final Map<String, List<SharedMember>> members;
  final Map<String, SharedFinancePolicy> financePolicies;
  final List<SharedInboxEntry> inbox;
  final Map<String, SharedNotificationPreferences> notificationPreferences;
  final List<SharedScheduledReminder> scheduledReminders;
  List<SharedMember> membersForScope(String id) => members[id] ?? const [];
  SharedFinancePolicy financePolicyForScope(String id) =>
      financePolicies[id] ?? const SharedFinancePolicy();
  final List<SharedFinanceConflict> financeConflicts;
  final int financePendingCount, financeBlockedCount;
  final Map<String, bool> financeSnapshotComplete;
  final bool emailVerificationSupported, resetSupported;
  final bool inboxSupported,
      financeSupported,
      externalPushSupported,
      smtpSupported;
  final AccountSession? session;
  final String? selectedSpaceId;
  final RemotePushRegistrationState remotePushRegistration;
  final String? pushProjectId;
  final bool sessionInvalid;
  final bool sessionRenewalSupported;
  final bool organizationsSupported,
      householdPeopleSupported,
      projectArchivingSupported;
  final int financeContractVersion, recordContractVersion;
  final bool deletionPending;
  final PrivateSyncState privateSync;
  final Map<String, String> privateRecordIds;
  String personalRecordId(String serverRecordId) =>
      privateRecordIds[serverRecordId] ?? serverRecordId;
  final List<SharedScope> scopes;
  final Map<String, SharedScopeData> data;
  final List<SharedConflict> conflicts;
  final int pendingCount;
  final int blockedCount;
  final bool isSyncing;
  final CollaborationException? lastError;
  SharedScopeData dataForScope(String scopeId) =>
      data[scopeId] ?? SharedScopeData();
}
