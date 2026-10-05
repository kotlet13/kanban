part of 'collaboration_repository.dart';

/// Captured old-device cleanup never borrows the current account's bearer. The
/// bounded backlog is encrypted by the secure store independently of the intent.
extension CollaborationRemotePushCleanup on CollaborationRepository {
  Future<bool> _clearPreviousSession(int epoch, DeviceSession? previous) async {
    Object? failure;
    if (previous != null && pushStore != null) {
      try {
        // Commit cleanup before deleting the only durable bearer. A killed app
        // suppresses this already-signed-out session on its next initialization.
        await _pushSecure(() async {
          final backlog = await pushStore!.readCleanups();
          if (!backlog.any((c) => c.matches(previous.profile))) {
            if (backlog.length >= 20) {
              throw const CollaborationException('push_cleanup_capacity');
            }
            await pushStore!.writeCleanups([
              ...backlog,
              RemotePushCleanup(previous),
            ]);
          }
        });
      } catch (e) {
        failure = e;
      }
    }
    try {
      await _secure(epoch, sessionStore.clear);
    } catch (e) {
      failure ??= e;
    }
    var confirmed = false;
    if (previous != null) {
      confirmed = await _sendPushCleanup(
        RemotePushCleanup(previous),
        unregister: pushStore != null,
      );
      if (pushStore != null) {
        try {
          await _pushSecure(() async {
            final saved = await pushStore!.read();
            if (saved?.identity.matches(previous.profile) == true) {
              await pushStore!.clear();
            }
          });
          if (confirmed) await _forgetPushCleanup(previous.profile);
        } catch (e) {
          failure ??= e;
        }
      }
    }
    if (failure != null) throw failure;
    return confirmed;
  }

  Future<bool> _sendPushCleanup(
    RemotePushCleanup cleanup, {
    bool unregister = true,
  }) async {
    final previous = cleanup.session;
    try {
      final caps = await transport.call(
        serverUrl: previous.profile.serverUrl,
        operation: 'capabilities',
        allowLocalHttp: previous.profile.allowLocalHttp,
      );
      if (caps['serverId'] != previous.profile.serverId) {
        return true; // Old installation is gone; never send its bearer elsewhere.
      }
    } catch (_) {
      return false;
    }
    for (final operation in [
      if (unregister) 'push.unregister',
      'auth.revoke',
    ]) {
      try {
        await transport.call(
          serverUrl: previous.profile.serverUrl,
          operation: operation,
          params: operation == 'auth.revoke'
              ? {'deviceId': previous.profile.deviceId}
              : const {},
          token: previous.token,
          allowLocalHttp: previous.profile.allowLocalHttp,
        );
      } on CollaborationException catch (e) {
        if (const {
          'auth_required',
          'device_revoked',
          'invalid_credentials',
          'session_expired',
        }.contains(e.code)) {
          return true; // An invalid bearer cannot have an active delivery worker.
        }
        if (operation == 'auth.revoke') return false;
      } catch (_) {
        if (operation == 'auth.revoke') return false;
      }
    }
    return true;
  }

  Future<void> _forgetPushCleanup(AccountSession profile) =>
      _pushSecure(() async {
        final backlog = await pushStore!.readCleanups();
        await pushStore!.writeCleanups(
          backlog.where((c) => !c.matches(profile)).toList(),
        );
      });

  Future<void> _retryRemotePushCleanups(int epoch) async {
    if (pushStore == null) return;
    try {
      final backlog = await _pushSecure(pushStore!.readCleanups);
      for (final cleanup in backlog) {
        _checkEpoch(epoch);
        if (cleanup.session.profile.expiresAt.isAfter(clock())) {
          if (!await _sendPushCleanup(cleanup)) continue;
        }
        _checkEpoch(epoch);
        await _forgetPushCleanup(cleanup.session.profile);
      }
    } on CollaborationException catch (e) {
      _checkEpoch(epoch);
      // Optional channel failure does not prevent normal local or shared use.
      _remotePushState = RemotePushRegistrationState(
        identity: remotePushIdentity,
        status: RemotePushRegistrationStatus.blocked,
        errorCode: e.code,
      );
    }
  }
}
