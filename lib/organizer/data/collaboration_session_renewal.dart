part of 'collaboration_repository.dart';

/// Sliding expiry keeps active devices signed in. The bearer stays unchanged,
/// so a lost response or failed secure write can be retried after reconnecting.
extension CollaborationSessionRenewal on CollaborationRepository {
  DeviceSession _currentDeviceSession(DeviceSession original, int epoch) {
    _checkEpoch(epoch);
    final current = _requireSession();
    if (current.profile.partition != original.profile.partition ||
        current.profile.deviceId != original.profile.deviceId ||
        current.token != original.token) {
      throw const CollaborationException('session_changed');
    }
    if (_sessionInvalidReason != null) {
      throw CollaborationException(_sessionInvalidReason!);
    }
    return current;
  }

  Future<void> _renewDeviceSessionIfNeeded(
    DeviceSession original,
    int epoch,
  ) async {
    // A lost earlier reply can leave a stale local expiry. Only the server
    // decides whether the bearer is still active; durable invalid markers win.
    final session = _currentDeviceSession(original, epoch);
    if (!_sessionRenewalSupported ||
        session.profile.expiresAt.difference(clock()) >
            const Duration(days: 7)) {
      return;
    }
    if (_sessionRenewalEpoch == epoch && _sessionRenewal != null) {
      await _sessionRenewal;
      _currentDeviceSession(original, epoch);
      return;
    }
    final pending = _renewDeviceSession(session, epoch);
    _sessionRenewalEpoch = epoch;
    _sessionRenewal = pending;
    try {
      await pending;
    } finally {
      if (identical(_sessionRenewal, pending)) {
        _sessionRenewal = null;
        _sessionRenewalEpoch = null;
      }
    }
  }

  Future<void> _checkRenewalPersistence(
    DeviceSession session,
    int epoch,
  ) async {
    _currentDeviceSession(session, epoch);
    final invalid = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [
        'invalid_session:${session.profile.partition}:${session.profile.deviceId}',
      ],
    );
    _currentDeviceSession(session, epoch);
    if (invalid.isNotEmpty) {
      final reason = invalid.first['value'] as String;
      await _invalidateDeviceSession(session, epoch, reason);
      throw CollaborationException(reason);
    }
    if ((await database.rows(
      'SELECT value FROM local_meta WHERE name IN (?,?)',
      [
        'deleted_account:${session.profile.partition}',
        'deletion_pending:${session.profile.partition}',
      ],
    )).isNotEmpty) {
      throw const CollaborationException('deletion_pending');
    }
    _currentDeviceSession(session, epoch);
  }

  Future<void> _renewDeviceSession(DeviceSession session, int epoch) async {
    Map<String, dynamic> reply;
    try {
      reply = await transport.call(
        serverUrl: session.profile.serverUrl,
        operation: 'auth.renew',
        params: {'deviceId': session.profile.deviceId},
        token: session.token,
        allowLocalHttp: session.profile.allowLocalHttp,
      );
    } on CollaborationException catch (error) {
      _currentDeviceSession(session, epoch);
      if (const {
        'device_revoked',
        'auth_required',
        'session_expired',
        'invalid_credentials',
      }.contains(error.code)) {
        await _invalidateDeviceSession(session, epoch, error.code);
      }
      rethrow;
    }
    _currentDeviceSession(session, epoch);
    final user = reply['user'], device = reply['device'];
    if (reply['serverId'] != session.profile.serverId ||
        user is! Map<String, dynamic> ||
        user['accountId'] != session.profile.accountId ||
        user['id'] != session.profile.userId ||
        device is! Map<String, dynamic> ||
        device['id'] != session.profile.deviceId ||
        device['expiresAt'] is! int) {
      throw const CollaborationException('invalid_response');
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      (device['expiresAt'] as int) * 1000,
      isUtc: true,
    );
    if (!expiresAt.isAfter(clock()) ||
        expiresAt.isBefore(session.profile.expiresAt)) {
      throw const CollaborationException('invalid_response');
    }
    final profile = session.profile;
    final renewed = DeviceSession(
      AccountSession(
        serverUrl: profile.serverUrl,
        serverId: profile.serverId,
        accountId: profile.accountId,
        userId: profile.userId,
        username: profile.username,
        displayName: profile.displayName,
        deviceId: profile.deviceId,
        expiresAt: expiresAt,
        allowLocalHttp: profile.allowLocalHttp,
      ),
      session.token,
    );
    await _secure(epoch, () async {
      await _checkRenewalPersistence(session, epoch);
      await sessionStore.write(renewed);
      // Revocation arriving during a secure write keeps its durable invalid
      // marker; neither this response nor a restart may reactivate the device.
      await _checkRenewalPersistence(session, epoch);
      await _saveAccount(renewed.profile);
      _currentDeviceSession(session, epoch);
      _session = renewed;
      if (database.personalProfile?.partition == profile.partition) {
        database.personalProfile = renewed.profile;
      }
    });
    await refreshLocal();
  }
}
