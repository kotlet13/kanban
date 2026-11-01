part of 'collaboration_repository.dart';

/// Separate enrollment, existing-account login and verification/reset commands.
/// Passwords and single-use codes are forwarded only in this initiating call.
extension CollaborationAccountRecovery on CollaborationRepository {
  Future<void> enroll({
    required String serverUrl,
    required String code,
    required String username,
    required String password,
    required String name,
    String deviceName = 'Jivie',
    bool allowLocalHttp = false,
  }) => _authenticate(serverUrl, 'auth.enroll', {
    'code': code,
    'username': username,
    'password': password,
    'displayName': name,
    'deviceName': deviceName,
  }, allowLocalHttp);
  Future<AccountStatus> accountStatus() async {
    final session = _requireSession(), epoch = _epoch;
    final j = await _callSession(session, epoch, 'account.status', {});
    _checkEpoch(epoch);
    await database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      [
        'verified_email:${session.profile.partition}',
        j['emailVerified'] == true ? 'true' : 'false',
      ],
    );
    _checkEpoch(epoch);
    return AccountStatus(
      email: readNullableString(j, 'email'),
      pendingEmail: readNullableString(j, 'pendingEmail'),
      emailVerified: readBool(j, 'emailVerified'),
      resetAvailable: readBool(j, 'resetAvailable'),
    );
  }

  /// Called before a new connected local mutation, outside its SQL transaction.
  /// Previously verified offline work stays local; unknown/unverified identities
  /// cannot create a new connected entry merely because upload is postponed.
  Future<void> requireVerifiedEmailForConnectedEntry() async {
    final session = _requireSession(), epoch = _epoch;
    if (contentRouteGuard != null) {
      await contentRouteGuard!.authorizeConnectedEntry(session: session);
      _checkEpoch(epoch);
      return;
    }
    final known = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['verified_email:${session.profile.partition}'],
    );
    _checkEpoch(epoch);
    if (known.isNotEmpty && known.single['value'] == 'true') return;
    final status = await accountStatus();
    _checkEpoch(epoch);
    if (!status.emailVerified) {
      throw const CollaborationException('email_verification_required');
    }
  }

  Future<void> requestEmailVerification({
    required String email,
    required String password,
    String? otp,
    String language = 'sl',
  }) async {
    await _call('account.email.request', {
      'email': email,
      'password': password,
      'language': language,
      if (otp != null) 'otp': otp,
    });
  }

  Future<AccountStatus> confirmEmailVerification(
    String token, {
    String? accountId,
    String? serverId,
    String? email,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    await _callSession(session, epoch, 'account.email.confirm', {
      'token': token,
      if (accountId != null) 'accountId': accountId,
      if (serverId != null) 'serverId': serverId,
      if (email != null) 'email': email,
    });
    _checkEpoch(epoch);
    return accountStatus();
  }

  /// Credential change preserves the current bearer and all local crypto state.
  Future<void> changeAccountPassword({
    required String currentPassword,
    required String newPassword,
    String? otp,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    await _negotiate(session, epoch);
    _currentDeviceSession(session, epoch);
    if (!_passwordChangeSupported) {
      throw const CollaborationException('password_change_unsupported');
    }
    final reply =
        await _callSession(session, epoch, 'account.password.change', {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
          if (otp != null) 'otp': otp,
        }, capabilitiesVerified: true);
    _currentDeviceSession(session, epoch);
    if (reply['changed'] != true ||
        reply['sessionPreserved'] != true ||
        reply['accountId'] != session.profile.accountId ||
        reply['deviceId'] != session.profile.deviceId) {
      throw const CollaborationException('invalid_response');
    }
  }

  /// Account settings fixes the destination to this signed-in identity.
  Future<void> requestSignedInPasswordReset({String language = 'sl'}) async {
    final session = _requireSession(), epoch = _epoch;
    await _negotiate(session, epoch);
    _currentDeviceSession(session, epoch);
    if (!_passwordChangeSupported || !_passwordResetSupported) {
      throw const CollaborationException('password_change_unsupported');
    }
    await requestPasswordReset(
      serverUrl: session.profile.serverUrl,
      username: session.profile.username,
      language: language,
      allowLocalHttp: session.profile.allowLocalHttp,
    );
    _currentDeviceSession(session, epoch);
  }

  Future<void> confirmSignedInPasswordReset({
    required String token,
    required String password,
    String? otp,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    await _negotiate(session, epoch);
    _currentDeviceSession(session, epoch);
    // The bound confirm parameters are part of the passwordChange capability.
    if (!_passwordChangeSupported || !_passwordResetSupported) {
      throw const CollaborationException('password_change_unsupported');
    }
    final reply = await transport.call(
      serverUrl: session.profile.serverUrl,
      operation: 'auth.reset.confirm',
      params: {
        'token': token,
        'password': password,
        'expectedAccountId': session.profile.accountId,
        'expectedServerId': session.profile.serverId,
        if (otp != null) 'otp': otp,
      },
      allowLocalHttp: session.profile.allowLocalHttp,
    );
    _currentDeviceSession(session, epoch);
    if (reply['reset'] != true) {
      throw const CollaborationException('invalid_response');
    }
    // Confirmed reset revokes all sessions, including this one. Preserve local
    // content/keys and show the existing session-invalid flow, without logout.
    await _invalidateDeviceSession(session, epoch, 'session_expired');
  }

  Future<void> requestPasswordReset({
    required String serverUrl,
    required String username,
    String language = 'sl',
    bool allowLocalHttp = false,
  }) async {
    await transport.call(
      serverUrl: normalizeCollaborationServer(
        serverUrl,
        allowLocalHttp: allowLocalHttp,
      ),
      operation: 'auth.reset.request',
      params: {'username': username, 'language': language},
      allowLocalHttp: allowLocalHttp,
    );
  }

  Future<void> confirmPasswordReset({
    required String serverUrl,
    required String token,
    required String password,
    String? otp,
    bool allowLocalHttp = false,
  }) async {
    final base = normalizeCollaborationServer(
      serverUrl,
      allowLocalHttp: allowLocalHttp,
    );
    final initiatingSession = _session, initiatingEpoch = _epoch;
    await transport.call(
      serverUrl: base,
      operation: 'auth.reset.confirm',
      params: {
        'token': token,
        'password': password,
        if (otp != null) 'otp': otp,
      },
      allowLocalHttp: allowLocalHttp,
    );
    if (initiatingSession != null &&
        initiatingEpoch == _epoch &&
        initiatingSession.profile.serverUrl == base) {
      // The public reset code may belong to another account. Verify this device;
      // never invalidate an unrelated account merely because it uses this URL.
      try {
        await _callSession(initiatingSession, initiatingEpoch, 'auth.me', {});
      } on CollaborationException catch (e) {
        if (!const {
          'auth_required',
          'device_revoked',
          'session_expired',
        }.contains(e.code)) {
          rethrow;
        }
      }
    }
  }
}
