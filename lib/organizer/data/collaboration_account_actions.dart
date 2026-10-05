part of 'collaboration_repository.dart';

/// Authentication, secure session lifecycle and explicit membership actions.
extension CollaborationAccountActions on CollaborationRepository {
  Future<void> _loadCapabilities(String partition) async {
    _recordContractVersion = 1;
    _inboxSupported = false;
    _financeSupported = false;
    _privateSyncSupported = false;
    _emailVerificationSupported = false;
    _passwordResetSupported = false;
    _externalPushSupported = false;
    _pushProjectId = null;
    _smtpSupported = false;
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
    final features = caps['features'] as Map<String, dynamic>;
    _recordContractVersion = versions is List && versions.contains(2) ? 2 : 1;
    _privateSyncSupported =
        features['privateSync'] == true &&
        features['personalFinanceEntry'] == true;
    _inboxSupported = features['inbox'] == true;
    _financeSupported = features['finance'] == true;
    _externalPushSupported = features['externalPush'] == true;
    _pushProjectId = caps['pushProjectId'] is String
        ? caps['pushProjectId'] as String
        : null;
    _smtpSupported = features['smtp'] == true;
    _emailVerificationSupported = features['emailVerification'] == true;
    _passwordResetSupported = features['passwordReset'] == true;
  }

  Future<void> _negotiate(DeviceSession session, int epoch) async {
    _checkEpoch(epoch);
    final caps = await transport.call(
      serverUrl: session.profile.serverUrl,
      operation: 'capabilities',
      allowLocalHttp: session.profile.allowLocalHttp,
    );
    _checkEpoch(epoch);
    if (caps['serverId'] != session.profile.serverId) {
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
    String deviceName = 'Vsakdan',
  }) => _authenticate(serverUrl, 'auth.login', {
    'username': username,
    'password': password,
    'deviceName': deviceName,
    if (otp != null) 'otp': otp,
  }, allowLocalHttp);
  Future<void> registerWithInvitation({
    required String serverUrl,
    required String invitationToken,
    required String username,
    required String name,
    required String password,
    bool allowLocalHttp = false,
    String deviceName = 'Vsakdan',
  }) => _authenticate(serverUrl, 'auth.register', {
    'token': invitationToken,
    'username': username,
    'displayName': name,
    'password': password,
    'deviceName': deviceName,
  }, allowLocalHttp);

  Future<void> _authenticate(
    String server,
    String operation,
    Map<String, Object?> params,
    bool localHttp,
  ) async {
    final previous = _session;
    final epoch = ++_epoch;
    _session = null;
    database.activatePersonal(null);
    _pushIntent = null;
    _pushRestored = false;
    _sessionInvalidReason = null;
    _pushStateCheckedAt = null;
    _remotePushState = const RemotePushRegistrationState();
    _recordContractVersion = 1;
    _inboxSupported = false;
    _financeSupported = false;
    _privateSyncSupported = false;
    _emailVerificationSupported = false;
    _passwordResetSupported = false;
    _externalPushSupported = false;
    _pushProjectId = null;
    _smtpSupported = false;
    _lastError = null;
    await refreshLocal();
    await _clearPreviousSession(epoch, previous);
    final base = normalizeCollaborationServer(
      server,
      allowLocalHttp: localHttp,
    );
    _checkEpoch(epoch);
    final reply = await transport.call(
      serverUrl: base,
      operation: operation,
      params: params,
      allowLocalHttp: localHttp,
    );
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
    } catch (_) {
      try {
        await transport.call(
          serverUrl: base,
          operation: 'auth.revoke',
          params: {'deviceId': session.profile.deviceId},
          token: session.token,
          allowLocalHttp: localHttp,
        );
      } catch (_) {}
      rethrow;
    }
    await refreshLocal();
    // Authentication succeeds independently of connectivity after the token is stored.
    await syncNow();
  }

  /// Return whether the server confirmed revocation; local access stops first.
  Future<bool> signOut() async {
    final previous = _session;
    final epoch = ++_epoch;
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
    Map<String, Object?> params,
  ) async {
    _checkEpoch(epoch);
    if (_sessionInvalidReason != null) {
      throw CollaborationException(_sessionInvalidReason!);
    }
    if (!session.profile.expiresAt.isAfter(clock())) {
      await _invalidateDeviceSession(session, epoch, 'auth_required');
      throw const CollaborationException('auth_required');
    }
    Map<String, dynamic> reply;
    try {
      reply = await transport.call(
        serverUrl: session.profile.serverUrl,
        operation: operation,
        params: params,
        token: session.token,
        allowLocalHttp: session.profile.allowLocalHttp,
      );
    } on CollaborationException catch (e) {
      _checkEpoch(epoch);
      if (const {
            'device_revoked',
            'auth_required',
            'session_expired',
            'invalid_credentials',
          }.contains(e.code) &&
          !(operation == 'account.email.request' &&
              e.code == 'invalid_credentials')) {
        await _invalidateDeviceSession(session, epoch, e.code);
      }
      rethrow;
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
    database.activatePersonal(null);
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
  }) async {
    validateSharedText(name, 200);
    final profile = _requireSession().profile, epoch = _epoch;
    final reply = await _call('scopes.create', {
      'id': newSharedId(),
      'kind': kind.name,
      'name': name,
      'requestId': newSharedId(),
    });
    final scope = SharedScope.fromJson(reply['scope'] as Map<String, dynamic>);
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _upsertScope(profile.partition, scope);
    });
    await refreshLocal();
    return scope.id;
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
  }) async {
    final session = _requireSession(), epoch = _epoch;
    await _callSession(session, epoch, 'scopes.removeMember', {
      'scopeId': scopeId,
      'userId': userId,
      'requestId': newSharedId(),
    });
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _invalidateMemberDirectory(session.profile.partition, scopeId);
      await database.execute(
        r"DELETE FROM members WHERE partition=? AND scope_id=? AND json_extract(data,'$.userId')=?",
        [session.profile.partition, scopeId, userId],
      );
    });
    await syncNow();
  }

  Future<void> _upsertScope(String partition, SharedScope scope) async {
    final old = await database.rows(
      'SELECT blocked,cursor FROM scopes WHERE partition=? AND id=?',
      [partition, scope.id],
    );
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
      await database.execute(
        r"DELETE FROM inbox WHERE partition=? AND json_extract(data,'$.scopeId')=?",
        [partition, scope.id],
      );
      await database.execute(
        'DELETE FROM scheduled_reminders WHERE partition=? AND scope_id=?',
        [partition, scope.id],
      );
      await database.execute(
        r"UPDATE commands SET state='blocked' WHERE partition=? AND json_extract(params,'$.scopeId')=? AND state='pending'",
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
