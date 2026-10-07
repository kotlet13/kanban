import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

final sharingTestNow = DateTime.utc(2026, 10, 4);
const sharingScopeId = '10000000-0000-4000-8000-000000000001';
AccountSession sharingSession({bool second = false}) => AccountSession(
  serverUrl: 'https://sharing.example.test',
  serverId: '20000000-0000-4000-8000-000000000001',
  accountId: second
      ? '30000000-0000-4000-8000-000000000002'
      : '30000000-0000-4000-8000-000000000001',
  userId: second ? 2 : 1,
  username: second ? 'second' : 'first',
  displayName: second ? 'Druga oseba' : 'Prva oseba',
  deviceId: second
      ? '40000000-0000-4000-8000-000000000002'
      : '40000000-0000-4000-8000-000000000001',
  expiresAt: DateTime.utc(2099),
);

SharedScope sharingScope({
  SharedRole role = SharedRole.owner,
  bool revoked = false,
  bool blocked = false,
}) => SharedScope(
  id: sharingScopeId,
  name: 'Skupni dom z dolgim imenom za majhen zaslon',
  kind: SharedScopeKind.household,
  role: role,
  revoked: revoked,
  blocked: blocked,
);
SharedScopeData sharingData() => SharedScopeData(
  shoppingLists: [
    LocalShoppingList(
      id: 'list',
      title: 'Skupna trgovina',
      createdAt: sharingTestNow,
      updatedAt: sharingTestNow,
    ),
  ],
  shoppingItems: [
    LocalShoppingItem(
      id: 'item',
      listId: 'list',
      title: 'Mleko za skupno gospodinjstvo',
      quantity: '2 l',
      isChecked: false,
      createdAt: sharingTestNow,
      updatedAt: sharingTestNow,
    ),
  ],
  projects: [
    LocalProject(
      id: 'project',
      title: 'Skupni vrt',
      description: '',
      createdAt: sharingTestNow,
      updatedAt: sharingTestNow,
    ),
  ],
  tasks: [
    LocalTask(
      id: 'task',
      projectId: 'project',
      title: 'Pripravi zemljo',
      notes: '',
      dueAt: null,
      isCompleted: false,
      createdAt: sharingTestNow,
      updatedAt: sharingTestNow,
    ),
  ],
);

class SharingUiController extends CollaborationController {
  @override
  Future<List<PendingAccountDeletion>> pendingAccountDeletions() async => [];
  SharingUiController({CollaborationState? initial})
    : initial =
          initial ??
          CollaborationState(
            session: sharingSession(),
            scopes: [sharingScope()],
            data: {sharingScopeId: sharingData()},
          );
  final CollaborationState initial;
  final calls = <String>[];
  final loginAttempts = <String?>[];
  bool requireOtp = false;
  bool includeSecondMember = true;
  bool? enrollmentAllowLocalHttp;
  int memberLoads = 0;
  String? registeredUsername;
  String? registeredName;
  LocalShoppingList? copiedList;
  List<LocalShoppingItem>? copiedItems;
  LocalProject? copiedProject;
  List<LocalTask>? copiedTasks;
  @override
  Future<CollaborationState> build() async => initial;
  void replace(CollaborationState value) => state = AsyncData(value);
  void switchAccount() =>
      replace(CollaborationState(session: sharingSession(second: true)));
  int? privateEnabledRevision;
  int privatePreviewLoads = 0;
  String? previewServer, previewToken;
  @override
  Future<AccountStatus> accountStatus() async =>
      const AccountStatus(emailVerified: false, resetAvailable: false);
  @override
  Future<PrivateSyncPreview> previewPrivateSync() async {
    privatePreviewLoads++;
    return PrivateSyncPreview(
      revision: 7,
      recordCounts: {'tasks': 3, 'financeEntries': 2},
      existingRemoteCount: 0,
    );
  }

  @override
  Future<void> enablePrivateSync({required int expectedRevision}) async {
    privateEnabledRevision = expectedRevision;
  }

  @override
  Future<void> pausePrivateSync() async {
    calls.add('pausePrivate');
  }

  @override
  Future<void> resumePrivateSync() async {
    calls.add('resumePrivate');
  }

  @override
  Future<void> requestEmailVerification({
    required String email,
    required String password,
    String? otp,
    String language = 'sl',
  }) async {
    calls.add('email:$email');
  }

  @override
  Future<void> confirmEmailVerification(String token) async {
    calls.add('emailConfirmed');
  }

  @override
  Future<void> enroll({
    required String serverUrl,
    required String code,
    required String username,
    required String password,
    required String name,
    String deviceName = 'Jivie',
    bool allowLocalHttp = false,
  }) async {
    enrollmentAllowLocalHttp = allowLocalHttp;
    calls.add('enroll:$username');
  }

  @override
  Future<void> requestPasswordReset({
    required String serverUrl,
    required String username,
    String language = 'sl',
    bool allowLocalHttp = false,
  }) async {
    calls.add('resetRequested:$username');
  }

  @override
  Future<void> confirmPasswordReset({
    required String serverUrl,
    required String token,
    required String password,
    String? otp,
    bool allowLocalHttp = false,
  }) async {
    calls.add('resetConfirmed');
  }

  @override
  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
    String? otp,
    bool allowLocalHttp = false,
    String deviceName = 'Jivie',
  }) async {
    loginAttempts.add(otp);
    if (requireOtp && otp == null) {
      throw const CollaborationException('two_factor_required');
    }
    replace(
      CollaborationState(
        session: sharingSession(),
        scopes: [sharingScope()],
        data: {sharingScopeId: sharingData()},
      ),
    );
  }

  @override
  Future<SharedInvitationPreview> previewInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) async {
    previewServer = serverUrl;
    previewToken = token;
    return SharedInvitationPreview(
      scopeName: 'Povabljeni dom',
      scopeId: sharingScopeId,
      kind: SharedScopeKind.household,
      recipientUsername: 'second',
      role: SharedRole.member,
      expiresAt: DateTime.utc(2099),
      registrationAllowed: true,
    );
  }

  @override
  Future<void> registerWithInvitation({
    required String serverUrl,
    required String invitationToken,
    required String username,
    required String name,
    required String password,
    bool allowLocalHttp = false,
    String deviceName = 'Jivie',
  }) async {
    registeredUsername = username;
    registeredName = name;
    replace(
      CollaborationState(
        session: sharingSession(second: true),
        scopes: [sharingScope(role: SharedRole.member)],
        data: {sharingScopeId: sharingData()},
      ),
    );
  }

  @override
  Future<void> acceptInvitation(String token) async {
    calls.add('accept');
  }

  @override
  Future<List<SharedMember>> members(String scopeId) async {
    memberLoads++;
    return [
      const SharedMember(
        userId: 1,
        username: 'first',
        displayName: 'Member Alpha',
        role: SharedRole.owner,
        active: true,
      ),
      if (includeSecondMember)
        const SharedMember(
          userId: 2,
          username: 'second',
          displayName: 'Member Beta',
          role: SharedRole.member,
          active: true,
        ),
    ];
  }

  @override
  Future<List<SharedInvitation>> invitations(String scopeId) async {
    calls.add('invitations');
    return [];
  }

  @override
  Future<SharedInvitation> createInvitation({
    required String scopeId,
    required String recipientUsername,
    SharedRole role = SharedRole.member,
  }) async {
    calls.add('invite');
    return SharedInvitation(
      id: 'invite',
      scopeId: scopeId,
      recipientUsername: recipientUsername,
      role: role,
      expiresAt: DateTime.utc(2099),
      token: 'synthetic-invitation-token',
    );
  }

  @override
  Future<void> revokeMember({
    required String scopeId,
    required int userId,
  }) async {
    calls.add('remove:$userId');
  }

  @override
  Future<void> syncNow() async {
    calls.add('sync');
  }

  @override
  Future<bool> signOut() async {
    replace(CollaborationState());
    return true;
  }

  @override
  Future<void> setShoppingItemChecked(
    String scopeId,
    String id,
    bool value,
  ) async {
    calls.add('check:$value');
    final old = state.requireValue;
    final data = old.dataForScope(scopeId);
    replace(
      CollaborationState(
        session: old.session,
        scopes: old.scopes,
        data: {
          scopeId: SharedScopeData(
            projects: data.projects,
            tasks: data.tasks,
            shoppingLists: data.shoppingLists,
            shoppingItems: data.shoppingItems.map(
              (item) => item.id == id ? item.copyWith(isChecked: value) : item,
            ),
          ),
        },
        pendingCount: 1,
      ),
    );
  }

  @override
  Future<String> createShoppingItem({
    required String scopeId,
    required String listId,
    required String title,
    String quantity = '',
  }) async {
    calls.add('item:$title');
    final old = state.requireValue, data = old.dataForScope(scopeId);
    replace(
      CollaborationState(
        session: old.session,
        scopes: old.scopes,
        data: {
          scopeId: SharedScopeData(
            shoppingLists: data.shoppingLists,
            shoppingItems: [
              ...data.shoppingItems,
              LocalShoppingItem(
                id: 'new-item',
                listId: listId,
                title: title,
                quantity: quantity,
                isChecked: false,
                createdAt: sharingTestNow,
                updatedAt: sharingTestNow,
              ),
            ],
          ),
        },
        pendingCount: 1,
      ),
    );
    return 'new-item';
  }

  @override
  Future<String> publishShoppingList({
    required String scopeId,
    required LocalShoppingList list,
    required List<LocalShoppingItem> items,
  }) async {
    copiedList = list;
    copiedItems = items;
    return 'list';
  }

  @override
  Future<String> publishProject({
    required String scopeId,
    required LocalProject project,
    required List<LocalTask> tasks,
  }) async {
    copiedProject = project;
    copiedTasks = tasks;
    return 'project';
  }

  @override
  Future<void> resolveConflict({
    required String conflictId,
    required bool keepLocal,
  }) async {
    calls.add('resolve:$keepLocal');
    final old = state.requireValue;
    replace(
      CollaborationState(
        session: old.session,
        scopes: old.scopes,
        data: old.data,
      ),
    );
  }
}
