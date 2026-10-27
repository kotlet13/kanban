part of 'collaboration_repository.dart';

/// Authentication, secure session lifecycle and explicit membership actions.
extension CollaborationAccountActions on CollaborationRepository {
  Future<void> _loadCapabilities(String partition) async {
    _scopeAccessChangesSupported = false;
    _organizationsSupported = false;
    _householdPeopleSupported = false;
    _projectArchivingSupported = false;
    _scopeDeletionSupported = false;
    _scopeArchivingSupported = false;
    _sessionRenewalSupported = false;
    _recordContractVersion = 1;
    _financeContractVersion = 1;
    _accountDeletionPolicyVersion = 1;
    _moderationSupported = false;
    _moderationVerifiedEpoch = null;
    _moderationAccepted = null;
    _sharedContentPolicy = null;
    _inboxSupported = false;
    _accountDeletionSupported = false;
    _financeSupported = false;
    _organizationFinanceSupported = false;
    _privateSyncSupported = false;
    _emailVerificationSupported = false;
    _passwordResetSupported = false;
    _externalPushSupported = false;
    _pushProjectId = null;
    _pushDisplayVersion = 1;
    _smtpSupported = false;
    _emailInvitationsSupported = false;
    _scopedInvitationsSupported = false;
    _usernameInvitationsSupported = false;
    _recipientSearchSupported = false;
    _invitationResendSupported = false;
    _spaceProjectMembershipSupported = false;
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['capabilities:$partition'],
    );
    if (rows.isNotEmpty) {
      _applyCapabilities(CollaborationRepository._map(rows.first['value']));
    } else {
      final version = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['record_contract:$partition'],
      );
      if (version.isNotEmpty) {
        _recordContractVersion = int.parse(version.first['value'] as String);
      }
    }
  }

  void _applyCapabilities(Map<String, dynamic> caps) {
    final versions = caps['recordContractVersions'];
    _financeContractVersion =
        (caps['financeContractVersions'] is List &&
            (caps['financeContractVersions'] as List).contains(2))
        ? 2
        : 1;
    _accountDeletionPolicyVersion =
        (caps['accountDeletionPolicyVersions'] is List &&
            (caps['accountDeletionPolicyVersions'] as List).contains(4))
        ? 4
        : (caps['accountDeletionPolicyVersions'] is List &&
              (caps['accountDeletionPolicyVersions'] as List).contains(3))
        ? 3
        : (caps['accountDeletionPolicyVersions'] is List &&
              (caps['accountDeletionPolicyVersions'] as List).contains(2))
        ? 2
        : 1;
    final features = caps['features'] as Map<String, dynamic>;
    _organizationFinanceSupported =
        features['organizationFinance'] == true &&
        (caps['organizationFinanceContractVersions'] as List? ?? const [])
            .contains(1) &&
        (caps['financeContractVersions'] as List? ?? const []).contains(3);
    if (_organizationFinanceSupported) _financeContractVersion = 3;
    _recordContractVersion = versions is List && versions.contains(6)
        ? 6
        : versions is List && versions.contains(5)
        ? 5
        : versions is List && versions.contains(4)
        ? 4
        : versions is List && versions.contains(3)
        ? 3
        : (versions is List && versions.contains(2) ? 2 : 1);
    _privateSyncSupported =
        features['privateSync'] == true &&
        features['personalFinanceEntry'] == true;
    _sessionRenewalSupported = features['sessionRenewal'] == true;
    _scopeAccessChangesSupported = features['scopeAccessChanges'] == true;
    _organizationsSupported =
        features['organizations'] == true && _recordContractVersion >= 3;
    _householdPeopleSupported =
        features['householdPeople'] == true && _recordContractVersion >= 3;
    _projectArchivingSupported = features['projectArchiving'] == true;
    _scopeDeletionSupported = features['scopeDeletion'] == true;
    _scopeArchivingSupported = features['scopeArchiving'] == true;
    _moderationSupported =
        features['sharedContentPolicy'] == true &&
        features['contentReporting'] == true &&
        (caps['moderationContractVersions'] as List? ?? const []).contains(1);
    if (!_moderationSupported) {
      _moderationVerifiedEpoch = null;
      _moderationAccepted = null;
      _sharedContentPolicy = null;
    }
    _inboxSupported = features['inbox'] == true;
    _accountDeletionSupported = features['accountDeletion'] == true;
    _financeSupported = features['finance'] == true;
    _externalPushSupported = features['externalPush'] == true;
    _pushDisplayVersion = caps['pushDisplayVersion'] == 2 ? 2 : 1;
    _pushProjectId = caps['pushProjectId'] is String
        ? caps['pushProjectId'] as String
        : null;
    _smtpSupported = features['smtp'] == true;
    _emailVerificationSupported = features['emailVerification'] == true;
    _passwordResetSupported = features['passwordReset'] == true;
    _spaceProjectMembershipSupported =
        features['spaceProjectMembership'] == true &&
        (caps['spaceAccessPolicyVersions'] as List? ?? const []).contains(3);
    _scopedInvitationsSupported =
        features['scopedInvitations'] == true &&
        (caps['invitationContractVersions'] as List? ?? const []).contains(3);
    _usernameInvitationsSupported =
        _scopedInvitationsSupported && features['usernameInvitations'] == true;
    _recipientSearchSupported =
        _usernameInvitationsSupported && features['recipientSearch'] == true;
    _invitationResendSupported =
        _scopedInvitationsSupported && features['invitationResend'] == true;
    _emailInvitationsSupported =
        features['emailInvitations'] == true &&
        (caps['invitationContractVersions'] as List? ?? const []).contains(2);
  }

  Future<void> _negotiate(DeviceSession session, int epoch) async {
    _checkEpoch(epoch);
    final caps = await CryptoCapabilityDiscovery.read(
      transport: transport,
      session: session,
    );
    _checkEpoch(epoch);
    if (caps['serverId'] != session.profile.serverId) {
      await _invalidateDeviceSession(session, epoch, 'server_identity_changed');
      throw const CollaborationException('server_identity_changed');
    }
    if (caps['api'] != 'familyhub_native' ||
        caps['version'] != 1 ||
        caps['enabled'] != true ||
        caps['features'] is! Map<String, dynamic> ||
        (caps['features'] as Map)['recordSync'] != true) {
      throw const CollaborationException('incompatible_server');
    }
    _applyCapabilities(caps);
    await database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      ['capabilities:${session.profile.partition}', jsonEncode(caps)],
    );
  }

  Future<void> _saveAccount(
    AccountSession profile,
  ) => database.transaction(() async {
    await database.execute(
      'INSERT INTO accounts(partition,profile) VALUES (?,?) ON CONFLICT(partition) DO UPDATE SET profile=excluded.profile',
      [profile.partition, jsonEncode(profile.toJson())],
    );
  });

  Future<T> _secure<T>(int epoch, Future<T> Function() action) {
    final result = _secureQueue.then((_) async {
      _checkEpoch(epoch);
      return action();
    });
    _secureQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
    String? otp,
    bool allowLocalHttp = false,
    String deviceName = 'Jivie',
  }) => _authenticate(serverUrl, 'auth.login', {
    'username': username,
    'password': password,
    'deviceName': deviceName,
    if (otp != null) 'otp': otp,
  }, allowLocalHttp);

  /// Re-check the pinned invitation origin before sending account credentials.
  Future<void> loginForInvitation({
    required String serverUrl,
    required String invitationToken,
    required String username,
    required String password,
    String? otp,
    String deviceName = 'Jivie',
  }) async {
    await previewInvitation(serverUrl: serverUrl, token: invitationToken);
    final pending = await invitationStore.read();
    if (pending?.serverUrl != normalizeCollaborationServer(serverUrl) ||
        pending?.token != invitationToken) {
      throw const CollaborationException('invitation_identity_mismatch');
    }
    await _authenticate(
      serverUrl,
      'auth.login',
      {
        'username': username,
        'password': password,
        'deviceName': deviceName,
        if (otp != null) 'otp': otp,
      },
      false,
      expectedServerId: pending?.serverId,
    );
  }

  Future<void> registerWithInvitation({
    required String serverUrl,
    required String invitationToken,
    required String username,
    required String name,
    required String password,
    bool allowLocalHttp = false,
    String deviceName = 'Jivie',
  }) async {
    final encrypted =
        invitationToken.startsWith('fhi4_') ||
        invitationToken.startsWith('fhi2_') ||
        invitationToken.startsWith('fhi3_') ||
        (await previewInvitation(
              serverUrl: serverUrl,
              token: invitationToken,
              allowLocalHttp: allowLocalHttp,
            )).contractVersion ==
            4;
    if (encrypted) {
      return registerWithEmailInvitation(
        serverUrl: serverUrl,
        invitationToken: invitationToken,
        username: username,
        name: name,
        password: password,
        allowLocalHttp: allowLocalHttp,
        deviceName: deviceName,
      );
    }
    return _authenticate(serverUrl, 'auth.register', {
      'token': invitationToken,
      'username': username,
      'displayName': name,
      'password': password,
      'deviceName': deviceName,
    }, allowLocalHttp);
  }

  Future<void> _authenticate(
    String server,
    String operation,
    Map<String, Object?> params,
    bool localHttp, {
    String? expectedServerId,
  }) async {
    final previous = _session;
    final epoch = ++_epoch;
    _resetSyncEvidence();
    _session = null;
    database.activatePersonal(null);
    _pushIntent = null;
    _pushRestored = false;
    _sessionInvalidReason = null;
    _pushStateCheckedAt = null;
    _remotePushState = const RemotePushRegistrationState();
    _scopeAccessChangesSupported = false;
    _organizationsSupported = false;
    _householdPeopleSupported = false;
    _projectArchivingSupported = false;
    _scopeDeletionSupported = false;
    _scopeArchivingSupported = false;
    _sessionRenewalSupported = false;
    _recordContractVersion = 1;
    _financeContractVersion = 1;
    _accountDeletionPolicyVersion = 1;
    _moderationSupported = false;
    _moderationVerifiedEpoch = null;
    _moderationAccepted = null;
    _sharedContentPolicy = null;
    _inboxSupported = false;
    _accountDeletionSupported = false;
    _financeSupported = false;
    _organizationFinanceSupported = false;
    _privateSyncSupported = false;
    _emailVerificationSupported = false;
    _passwordResetSupported = false;
    _externalPushSupported = false;
    _pushProjectId = null;
    _pushDisplayVersion = 1;
    _smtpSupported = false;
    _emailInvitationsSupported = false;
    _scopedInvitationsSupported = false;
    _usernameInvitationsSupported = false;
    _recipientSearchSupported = false;
    _invitationResendSupported = false;
    _spaceProjectMembershipSupported = false;
    _lastError = null;
    await refreshLocal();
    await _clearPreviousSession(epoch, previous);
    final base = normalizeCollaborationServer(
      server,
      allowLocalHttp: localHttp,
    );
    _checkEpoch(epoch);
    if (expectedServerId != null) {
      final capabilities = await transport.call(
        serverUrl: base,
        operation: 'capabilities',
        allowLocalHttp: localHttp,
      );
      _checkEpoch(epoch);
      if (capabilities['api'] != 'familyhub_native' ||
          capabilities['enabled'] != true ||
          capabilities['serverId'] != expectedServerId) {
        throw const CollaborationException('server_identity_changed');
      }
    }
    final reply = await transport.call(
      serverUrl: base,
      operation: operation,
      params: params,
      allowLocalHttp: localHttp,
    );
    if (expectedServerId != null && reply['serverId'] != expectedServerId) {
      throw const CollaborationException('server_identity_changed');
    }
    final user = reply['user'] as Map<String, dynamic>,
        device = reply['device'] as Map<String, dynamic>;
    final session = DeviceSession(
      AccountSession(
        serverUrl: base,
        serverId: readString(reply, 'serverId'),
        accountId: readString(user, 'accountId'),
        userId: readInt(user, 'id'),
        username: readString(user, 'username'),
        displayName: readString(user, 'displayName'),
        deviceId: readString(device, 'id'),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          readInt(device, 'expiresAt') * 1000,
          isUtc: true,
        ),
        allowLocalHttp: localHttp,
      ),
      readString(reply, 'token'),
    );
    try {
      await _secure(epoch, () async {
        try {
          await _saveAccount(session.profile);
          _checkEpoch(epoch);
          await sessionStore.write(session);
          _checkEpoch(epoch);
          _session = session;
          database.activatePersonal(session.profile);
          await _loadCapabilities(session.profile.partition);
          _checkEpoch(epoch);
        } catch (_) {
          // This critical section prevents another login writing its token while
          // we compare and remove only this unsuccessful device session.
          final stored = await sessionStore.read();
          if (stored?.profile.deviceId == session.profile.deviceId) {
            await sessionStore.clear();
          }
          rethrow;
        }
      });
    } catch (error) {
      // Failed enrollment must lead to login, never reusing the spent code.
      if (epoch == _epoch &&
          _session?.profile.deviceId == session.profile.deviceId) {
        _session = null;
        database.activatePersonal(null);
      }
      try {
        await transport.call(
          serverUrl: base,
          operation: 'auth.revoke',
          params: {'deviceId': session.profile.deviceId},
          token: session.token,
          allowLocalHttp: localHttp,
        );
      } catch (_) {}
      _checkEpoch(epoch);
      if ((operation == 'auth.enroll' ||
              operation == 'auth.register' ||
              operation == 'auth.registerInvitation2') &&
          !(error is CollaborationException &&
              const {'session_changed', 'closed'}.contains(error.code))) {
        throw const CollaborationException('account_created_session_not_saved');
      }
      rethrow;
    }
    if (operation == 'auth.register' && params['token'] is String) {
      await _clearMatchingInvitation(
        params['token'] as String,
        serverUrl: base,
      );
    }
    await refreshLocal();
    // Authentication succeeds independently of connectivity after the token is stored.
    await syncNow();
    _checkEpoch(epoch);
  }

  /// Return whether the server confirmed revocation; local access stops first.
  Future<bool> signOut() async {
    final previous = _session;
    final epoch = ++_epoch;
    _resetSyncEvidence();
    _session = null;
    database.activatePersonal(null);
    _pushIntent = null;
    _pushRestored = false;
    _sessionInvalidReason = null;
    _pushStateCheckedAt = null;
    _remotePushState = const RemotePushRegistrationState();
    _lastError = null;
    await refreshLocal();
    return _clearPreviousSession(epoch, previous);
  }

  Future<Map<String, dynamic>> _call(
    String operation,
    Map<String, Object?> params,
  ) => _callSession(_requireSession(), _epoch, operation, params);

  Future<Map<String, dynamic>> _callSession(
    DeviceSession session,
    int epoch,
    String operation,
    Map<String, Object?> params, {
    bool capabilitiesVerified = false,
    Future<void> Function()? authorizeLegacyUploadDrain,
    CryptoVisibleTaskMetadataTarget? visibleTaskMetadata,
  }) async {
    _checkEpoch(epoch);
    if (_sessionInvalidReason != null) {
      throw CollaborationException(_sessionInvalidReason!);
    }
    if (!operation.startsWith('account.deletion.') &&
        (await database.rows(
          'SELECT value FROM local_meta WHERE name IN (?,?)',
          [
            'deleted_account:${session.profile.partition}',
            'deletion_pending:${session.profile.partition}',
          ],
        )).isNotEmpty) {
      throw const CollaborationException('deletion_pending');
    }
    _checkEpoch(epoch);
    session = _currentDeviceSession(session, epoch);
    await _renewDeviceSessionIfNeeded(session, epoch);
    session = _currentDeviceSession(session, epoch);
    if (!session.profile.expiresAt.isAfter(clock())) {
      await _invalidateDeviceSession(session, epoch, 'auth_required');
      throw const CollaborationException('auth_required');
    }
    Map<String, dynamic> reply;
    try {
      if (await _requiresSharedContentPolicy(session, operation, params)) {
        await _guardSharedUpload(
          session,
          epoch,
          capabilitiesVerified: capabilitiesVerified,
        );
      }
      if (authorizeLegacyUploadDrain != null) {
        await authorizeLegacyUploadDrain();
      }
      final encrypted =
          const {
                'account.deletion.preview',
                'account.deletion.confirm',
                'account.deletion.status',
                'account.deletion.cancelPending',
              }.contains(operation) ||
              authorizeLegacyUploadDrain != null
          ? null
          : await routeProtectedCryptoDomain(
              database: database,
              session: session,
              operation: operation,
              params: params,
              router: cryptoRouter,
              contentGuard: contentRouteGuard,
              checkCurrent: () => _checkEpoch(epoch),
              visibleTaskMetadata: visibleTaskMetadata,
            );
      if (encrypted != null) {
        reply = encrypted;
      } else {
        if (operation == 'scopes.removeMember' &&
            params.containsKey('accountId')) {
          params = {...params}..remove('accountId');
        }
        if (operation == 'scopes.list') {
          params = {
            ...params,
            if (_privateSyncSupported) 'includePersonal': true,
            if (_scopeAccessChangesSupported) 'includeAccessChanges': true,
            if (_organizationsSupported) 'includeOrganizations': true,
            if (_projectArchivingSupported) 'includeArchived': true,
          };
        }
        if (operation == 'inbox.open') {
          params = {
            ...params,
            if (_financeContractVersion >= 2 &&
                !params.containsKey('financeContractVersion'))
              'financeContractVersion': _financeContractVersion,
            if (_recordContractVersion >= 3 &&
                !params.containsKey('recordContractVersion'))
              'recordContractVersion': _recordContractVersion,
          };
        }
        if (operation.startsWith('finance.') ||
            operation.startsWith('finance2.') ||
            operation.startsWith('finance4.') ||
            operation == 'sync3.pushTaskWithCost' ||
            operation == 'sync4.pushTaskWithCost' ||
            operation == 'sync5.pushTaskWithCost' ||
            operation == 'sync6.pushTaskWithCost') {
          final cached = await database.rows(
            'SELECT value FROM local_meta WHERE name=?',
            ['capabilities:${session.profile.partition}'],
          );
          if (cached.isNotEmpty &&
              (CollaborationRepository._map(cached.single['value'])['features']
                      as Map?)?['linkedPayments'] ==
                  true) {
            params = {...params, 'linkedPaymentsAware': true};
          }
        }
        reply = await transport.call(
          serverUrl: session.profile.serverUrl,
          operation: operation,
          params: params,
          token: session.token,
          allowLocalHttp: session.profile.allowLocalHttp,
        );
      }
    } on CollaborationException catch (e) {
      _checkEpoch(epoch);
      if (e.code == 'email_verification_required') {
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
          ['verified_email:${session.profile.partition}', 'false'],
        );
        _checkEpoch(epoch);
      }
      if (e.code == 'policy_acceptance_required') {
        _moderationVerifiedEpoch = null;
        _moderationAccepted = false;
        _sharedContentPolicy = null;
      }
      if (const {
            'device_revoked',
            'auth_required',
            'session_expired',
            'invalid_credentials',
          }.contains(e.code) &&
          !((operation == 'account.email.request' ||
                  operation == 'account.deletion.confirm') &&
              e.code == 'invalid_credentials')) {
        await _invalidateDeviceSession(session, epoch, e.code);
      }
      rethrow;
    }
    _checkEpoch(epoch);
    if (!operation.startsWith('account.deletion.') &&
        (await database.rows(
          'SELECT value FROM local_meta WHERE name IN (?,?)',
          [
            'deleted_account:${session.profile.partition}',
            'deletion_pending:${session.profile.partition}',
          ],
        )).isNotEmpty) {
      throw const CollaborationException('deletion_pending');
    }
    _checkEpoch(epoch);
    return reply;
  }

  Future<void> _invalidateDeviceSession(
    DeviceSession session,
    int epoch,
    String reason,
  ) async {
    _checkEpoch(epoch);
    _sessionInvalidReason = reason;
    authorityReuse.invalidate();
    accountWork.cancelStale();
    // Expiry preserves local content; a confirmed device revocation still closes it.
    if (reason == 'device_revoked') database.activatePersonal(null);
    _remotePushState = RemotePushRegistrationState(
      identity: RemotePushIdentity.fromSession(session.profile),
      status: RemotePushRegistrationStatus.blocked,
      errorCode: reason,
    );
    await database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      [
        'invalid_session:${session.profile.partition}:${session.profile.deviceId}',
        reason,
      ],
    );
    _checkEpoch(epoch);
    await refreshLocal();
  }

  DeviceSession _requireSession() {
    if (_closed) throw const CollaborationException('closed');
    return _session ?? (throw const CollaborationException('auth_required'));
  }

  void _checkEpoch(int epoch) {
    if (_closed || epoch != _epoch) {
      throw const CollaborationException('session_changed');
    }
  }

  Future<SharedInvitationPreview> previewInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) async {
    if ((token.startsWith('fhi2_') ||
        token.startsWith('fhi3_') ||
        token.startsWith('fhi4_'))) {
      return previewEmailInvitation(
        serverUrl: serverUrl,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
    }
    final base = normalizeCollaborationServer(
      serverUrl,
      allowLocalHttp: allowLocalHttp,
    );
    final reply = await transport.call(
      serverUrl: base,
      operation: 'invitations.preview',
      params: {'token': token},
      allowLocalHttp: allowLocalHttp,
    );
    final invitation = reply['invitation'] as Map<String, dynamic>,
        scope = reply['scope'] as Map<String, dynamic>;
    if (invitation['contractVersion'] == 4) {
      // Discovery chooses the strict encrypted verification flow only. It is
      // not authority to accept a legacy token or install a membership/key.
      return _emailInvitationPreview(reply);
    }
    return SharedInvitationPreview(
      scopeName: readString(scope, 'name'),
      scopeId: readString(scope, 'id'),
      kind: SharedScopeKind.values.byName(readString(scope, 'kind')),
      recipientUsername: readString(invitation, 'recipientUsername'),
      role: SharedRole.values.byName(readString(invitation, 'role')),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        readInt(invitation, 'expiresAt') * 1000,
        isUtc: true,
      ),
      registrationAllowed: reply['registrationAllowed'] == true,
    );
  }

  Future<String> createScope(
    String name, {
    SharedScopeKind kind = SharedScopeKind.household,
    String address = '',
    String? organizationId,
    String? parentScopeId,
    String? id,
    String? requestId,
  }) async {
    if (parentScopeId != null &&
        !_spaceProjectMembershipSupported &&
        parentScopeId != organizationId) {
      throw const CollaborationException('client_upgrade_required');
    }
    if ((kind == SharedScopeKind.organization || organizationId != null) &&
        !_organizationsSupported) {
      throw const CollaborationException('client_upgrade_required');
    }
    validateSharedText(name, 200);
    validateSharedText(address, 1000, empty: true);
    final profile = _requireSession().profile, epoch = _epoch;
    final parentId = parentScopeId ?? organizationId;
    var usePolicy3 = _spaceProjectMembershipSupported;
    if (kind == SharedScopeKind.project && parentId != null) {
      final rows = await database.rows(
        'SELECT data FROM scopes WHERE partition=? AND id=?',
        [profile.partition, parentId],
      );
      _checkEpoch(epoch);
      usePolicy3 =
          usePolicy3 &&
          rows.isNotEmpty &&
          SharedScope.fromJson(
                CollaborationRepository._map(rows.single['data']),
              ).accessPolicyVersion ==
              3;
    }
    final reply = await _call('scopes.create', {
      'id': id ?? newSharedId(),
      'kind': kind.name,
      'name': name,
      'address': address.trim(),
      if (organizationId != null) 'organizationId': organizationId,
      if (parentScopeId != null && _spaceProjectMembershipSupported)
        'parentScopeId': parentScopeId,
      if (usePolicy3 &&
          (kind == SharedScopeKind.organization ||
              kind == SharedScopeKind.household ||
              kind == SharedScopeKind.project))
        'accessPolicyVersion': 3
      else if (kind == SharedScopeKind.organization &&
          _scopeAccessChangesSupported)
        'accessPolicyVersion': 2,
      'requestId': requestId ?? newSharedId(),
    });
    final scope = SharedScope.fromJson(reply['scope'] as Map<String, dynamic>);
    if (id != null && scope.id != id) {
      throw const CollaborationException('invalid_response');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _upsertScope(profile.partition, scope);
      if (reply['projectRoot'] != null) {
        await _applyRemote(
          profile.partition,
          scope.id,
          _canonical(reply['projectRoot']),
        );
      }
    });
    await refreshLocal();
    return scope.id;
  }

  Future<void> archiveProjectScope(
    String scopeId, {
    required bool archived,
    String? requestId,
  }) async {
    if (!_projectArchivingSupported && !_scopeArchivingSupported) {
      throw const CollaborationException('client_upgrade_required');
    }
    final session = _requireSession(), epoch = _epoch;
    final currentScope = state.scopes.where((s) => s.id == scopeId).firstOrNull;
    if (!_scopeArchivingSupported &&
        currentScope?.kind != SharedScopeKind.project) {
      throw const CollaborationException('client_upgrade_required');
    }
    final reply = await _callSession(session, epoch, 'scopes.archive', {
      'scopeId': scopeId,
      'archived': archived,
      'requestId': requestId ?? newSharedId(),
    });
    final scope = SharedScope.fromJson(reply['scope'] as Map<String, dynamic>);
    if (scope.id != scopeId) {
      throw const CollaborationException('invalid_response');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _upsertScope(session.profile.partition, scope);
    });
    await refreshLocal();
    await syncNow();
  }

  Future<void> selectSpace(
    String? scopeId, {
    bool Function()? stillCurrent,
  }) async {
    final session = scopeId == null ? _session : _requireSession(),
        epoch = _epoch;
    final partition = session?.profile.partition ?? 'local';
    await database.transaction(() async {
      _checkEpoch(epoch);
      if (stillCurrent?.call() == false) return;
      if (scopeId != null) {
        final scopes = await database.rows(
          'SELECT data FROM scopes WHERE partition=? AND id=?',
          [partition, scopeId],
        );
        if (scopes.isEmpty ||
            SharedScope.fromJson(
              CollaborationRepository._map(scopes.single['data']),
            ).revoked) {
          throw const CollaborationException('permission_revoked');
        }
      }
      _checkEpoch(epoch);
      if (stillCurrent?.call() == false) return;
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        ['selected_space:$partition', scopeId ?? ''],
      );
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        ['all_spaces_selected:$partition', '0'],
      );
    });
    await refreshLocal();
  }

  Future<void> selectAllSpaces() async {
    final epoch = _epoch, partition = _session?.profile.partition ?? 'local';
    await database.transaction(() async {
      _checkEpoch(epoch);
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        ['all_spaces_selected:$partition', '1'],
      );
    });
    await refreshLocal();
  }

  Future<List<SharedMember>> members(String scopeId) async {
    final session = _requireSession(), epoch = _epoch;
    return _loadMembers(session, epoch, scopeId);
  }

  Future<void> _invalidateMemberDirectory(String partition, String scopeId) =>
      database.execute('DELETE FROM local_meta WHERE name=?', [
        'member_directory_at:$partition:$scopeId',
      ]);

  Future<List<SharedMember>> _loadMembers(
    DeviceSession session,
    int epoch,
    String scopeId, {
    bool syncLease = false,
  }) async {
    final partition = session.profile.partition;
    final stampKey = 'member_directory_at:$partition:$scopeId';
    if (syncLease) {
      final stamps = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [stampKey],
      );
      final now = clock().toUtc().microsecondsSinceEpoch;
      final previous = stamps.isEmpty
          ? null
          : int.tryParse(stamps.first['value'] as String);
      if (previous != null &&
          now >= previous &&
          now - previous < const Duration(seconds: 60).inMicroseconds) {
        final cached = await database.rows(
          'SELECT data FROM members WHERE partition=? AND scope_id=?',
          [partition, scopeId],
        );
        _checkEpoch(epoch);
        if (cached.isNotEmpty) {
          return cached
              .map(
                (row) => SharedMember.fromJson(
                  CollaborationRepository._map(row['data']),
                ),
              )
              .toList();
        }
      }
    }
    final reply = await _callSession(session, epoch, 'scopes.members', {
      'scopeId': scopeId,
    });
    final members = (reply['members'] as List)
        .map((r) => SharedMember.fromJson(r as Map<String, dynamic>))
        .toList();
    await database.transaction(() async {
      _checkEpoch(epoch);
      if (syncLease) await _validLease(session.profile.partition);
      _checkEpoch(epoch);
      await database.execute(
        'DELETE FROM members WHERE partition=? AND scope_id=?',
        [session.profile.partition, scopeId],
      );
      for (final member in members) {
        await database.execute(
          'INSERT INTO members(partition,scope_id,account_id,data) VALUES(?,?,?,?)',
          [
            session.profile.partition,
            scopeId,
            member.accountId.isEmpty
                ? member.userId.toString()
                : member.accountId,
            jsonEncode(member.toJson()),
          ],
        );
      }
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        [stampKey, clock().toUtc().microsecondsSinceEpoch.toString()],
      );
    });
    await refreshLocal();
    return members;
  }

  Future<List<SharedInvitation>> invitations(String scopeId) async =>
      ((await _call('invitations.list', {'scopeId': scopeId}))['invitations']
              as List)
          .map(
            (item) => SharedInvitation.fromJson(item as Map<String, dynamic>),
          )
          .toList();
  Future<SharedInvitation> createInvitation({
    required String scopeId,
    required String recipientUsername,
    SharedRole role = SharedRole.member,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    final reply = await _callSession(session, epoch, 'invitations.create', {
      'scopeId': scopeId,
      'recipientUsername': recipientUsername,
      'role': role.name,
      'requestId': newSharedId(),
    });
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _invalidateMemberDirectory(session.profile.partition, scopeId);
    });
    return SharedInvitation.fromJson(
      reply['invitation'] as Map<String, dynamic>,
      token: reply['token'] as String?,
    );
  }

  Future<void> acceptInvitation(String token) async {
    if ((token.startsWith('fhi2_') || token.startsWith('fhi3_'))) {
      return acceptEmailInvitation(token: token);
    }
    final session = _requireSession(), epoch = _epoch;
    final reply = await _callSession(session, epoch, 'invitations.accept', {
      'token': token,
    });
    final scopeId = SharedScope.fromJson(
      reply['scope'] as Map<String, dynamic>,
    ).id;
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _invalidateMemberDirectory(session.profile.partition, scopeId);
    });
    await _clearMatchingInvitation(token, serverUrl: session.profile.serverUrl);
    await syncNow();
  }

  Future<void> revokeInvitation(String scopeId, String invitationId) async {
    await _call('invitations.revoke', {
      'scopeId': scopeId,
      'invitationId': invitationId,
      'requestId': newSharedId(),
    });
  }

  Future<void> revokeMember({
    required String scopeId,
    required int userId,
    String? accountId,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    await _callSession(session, epoch, 'scopes.removeMember', {
      'scopeId': scopeId,
      'userId': userId,
      if (accountId != null) 'accountId': accountId,
      'requestId': newSharedId(),
    });
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _invalidateMemberDirectory(session.profile.partition, scopeId);
      for (final scope in state.scopes.where(
        (s) => s.id == scopeId || s.parentSpaceId == scopeId,
      )) {
        await _invalidateMemberDirectory(session.profile.partition, scope.id);
        await database.execute(
          r"DELETE FROM members WHERE partition=? AND scope_id=? AND json_extract(data,'$.userId')=?",
          [session.profile.partition, scope.id, userId],
        );
      }
    });
    await syncNow();
  }

  Future<void> _upsertScope(String partition, SharedScope scope) async {
    final old = await database.rows(
      'SELECT blocked,cursor,data FROM scopes WHERE partition=? AND id=?',
      [partition, scope.id],
    );
    if (!scope.revoked &&
        old.isNotEmpty &&
        (CollaborationRepository._map(old.first['data'])['sequence'] as int? ??
                0) >
            scope.sequence) {
      return;
    }
    final blocked =
        scope.revoked ||
        scope.role == SharedRole.viewer ||
        (old.isNotEmpty && old.first['blocked'] == 1);
    await database.execute(
      'INSERT INTO scopes(partition,id,data,blocked) VALUES(?,?,?,?) ON CONFLICT(partition,id) DO UPDATE SET data=excluded.data,blocked=excluded.blocked',
      [partition, scope.id, jsonEncode(scope.toJson()), blocked ? 1 : 0],
    );
    if (scope.revoked) {
      await database.execute(
        r"DELETE FROM local_meta WHERE (name LIKE ? OR name LIKE ?) AND json_extract(value,'$.scopeId')=?",
        ['push_reference:$partition:%', 'push_group:$partition:%', scope.id],
      );
      await _invalidateMemberDirectory(partition, scope.id);
      await _storeFinancePolicy(
        partition,
        scope.id,
        const SharedFinancePolicy(),
      );
      await database.execute(
        'DELETE FROM members WHERE partition=? AND scope_id=?',
        [partition, scope.id],
      );
      // Retain downloaded history for recovery; revoked scopes are excluded from
      // every live projection and notifications are no longer opened from it.
      await database.execute(
        'DELETE FROM scheduled_reminders WHERE partition=? AND scope_id=?',
        [partition, scope.id],
      );
      await database.execute(
        r"UPDATE commands SET state='blocked' WHERE partition=? AND json_extract(params,'$.scopeId')=? AND state='pending'",
        [partition, scope.id],
      );
    }
    if (scope.revoked) {
      await database.execute(
        "UPDATE finance_outbox SET state='blocked' WHERE partition=? AND scope_id=? AND state='pending'",
        [partition, scope.id],
      );
    }
    if (blocked) {
      await database.execute(
        "UPDATE outbox SET state='blocked' WHERE partition=? AND scope_id=? AND state='pending'",
        [partition, scope.id],
      );
    }
  }
}
