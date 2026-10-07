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
    final j = await _call('account.status', {});
    return AccountStatus(
      email: readNullableString(j, 'email'),
      pendingEmail: readNullableString(j, 'pendingEmail'),
      emailVerified: readBool(j, 'emailVerified'),
      resetAvailable: readBool(j, 'resetAvailable'),
    );
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

  Future<void> confirmEmailVerification(String token) async {
    await _call('account.email.confirm', {'token': token});
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
