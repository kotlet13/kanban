part of 'collaboration_repository.dart';

/// Device-bound provider registration. Sensitive retry state lives only in the
/// injected secure store; ordinary SQLite outboxes and exports never contain it.
extension CollaborationRemotePushActions on CollaborationRepository {
  RemotePushIdentity? get remotePushIdentity => _session == null
      ? null
      : RemotePushIdentity.fromSession(_session!.profile);

  void _checkPushIdentity(RemotePushIdentity identity, int epoch) {
    _checkEpoch(epoch);
    if (_sessionInvalidReason != null) {
      throw CollaborationException(_sessionInvalidReason!);
    }
    if (_session == null || !identity.matches(_session!.profile)) {
      throw const CollaborationException('session_changed');
    }
  }

  Future<T> _pushSecure<T>(Future<T> Function() action) {
    final result = _pushSecureQueue.then((_) => action());
    _pushSecureQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> _restoreRemotePush(int epoch) async {
    if (pushStore == null || _session == null) return;
    _pushRestored = true;
    try {
      await _pushSecure(() async {
        final intent = await pushStore!.read();
        _checkEpoch(epoch);
        if (intent != null && intent.identity.matches(_session!.profile)) {
          _pushIntent = intent;
          _remotePushState = intent.publicState;
        }
      });
    } on CollaborationException catch (e) {
      _checkEpoch(epoch);
      _remotePushState = RemotePushRegistrationState(
        identity: remotePushIdentity,
        status: RemotePushRegistrationStatus.blocked,
        errorCode: e.code,
      );
    }
  }

  Future<bool> _writeRemotePush(
    RemotePushIntent intent,
    int epoch, {
    String? onlyGeneration,
  }) => _pushSecure(() async {
    _checkPushIdentity(intent.identity, epoch);
    if (onlyGeneration != null && _pushIntent?.generation != onlyGeneration) {
      return false;
    }
    if (pushStore == null) {
      throw const CollaborationException('push_storage_unavailable');
    }
    await pushStore!.write(intent);
    _checkPushIdentity(intent.identity, epoch);
    _pushIntent = intent;
    _remotePushState = intent.publicState;
    return true;
  });

  Future<void> _verifyRemotePushRegistration(
    DeviceSession session,
    int epoch,
    RemotePushIntent intent, {
    bool force = false,
  }) async {
    if (!force &&
        _pushStateCheckedAt != null &&
        clock().difference(_pushStateCheckedAt!) <
            const Duration(seconds: 60)) {
      return;
    }
    try {
      final reply = await _callSession(session, epoch, 'push.state', {});
      final wire = reply['registration'];
      if (wire is! Map<String, dynamic> ||
          wire['registered'] is! bool ||
          wire['revision'] is! int ||
          (wire['revision'] as int) < 0) {
        throw const CollaborationException('invalid_response');
      }
      _pushStateCheckedAt = clock();
      if (wire['registered'] != true ||
          wire['revision'] != intent.confirmedRevision ||
          wire['platform'] != intent.platform ||
          wire['language'] != intent.language) {
        await _writeRemotePush(
          intent.copy(
            status: RemotePushRegistrationStatus.blocked,
            errorCode: wire['registered'] == true
                ? 'push_conflict'
                : 'push_registration_lost',
          ),
          epoch,
          onlyGeneration: intent.generation,
        );
      }
    } on CollaborationException catch (e) {
      _checkEpoch(epoch);
      if (e.code != 'network' && e.code != 'rate_limited') rethrow;
      // Unknown while offline remains last-confirmed registration, not a new ACK.
    }
    await refreshLocal();
  }

  Future<RemotePushRegistrationState> configureRemotePush({
    required RemotePushIdentity identity,
    required String token,
    required String platform,
    required String language,
    required String projectId,
  }) async {
    final epoch = _epoch;
    _checkPushIdentity(identity, epoch);
    if (!RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(projectId) ||
        !const ['ios', 'android'].contains(platform) ||
        !const ['sl', 'en'].contains(language) ||
        utf8.encode(token).length > 4096 ||
        token.isEmpty ||
        !RegExp(r'^[\x21-\x7e]+$').hasMatch(token)) {
      throw const CollaborationException('validation_error');
    }
    // Token rotation is a new explicit intent. Do not mutate an in-flight CAS.
    final old = _pushIntent;
    if (old != null &&
        old.identity.same(identity) &&
        old.enabled &&
        old.token == token &&
        old.platform == platform &&
        old.language == language &&
        old.projectId == projectId &&
        old.status != RemotePushRegistrationStatus.blocked) {
      if (old.status == RemotePushRegistrationStatus.registered) {
        await _verifyRemotePushRegistration(
          _requireSession(),
          epoch,
          old,
          force: true,
        );
      } else if (old.pending) {
        await _syncRemotePushRegistration(_requireSession(), epoch);
      }
      _checkPushIdentity(identity, epoch);
      return _remotePushState;
    }
    await _writeRemotePush(
      RemotePushIntent(
        identity: identity,
        generation: newSharedId(),
        enabled: true,
        token: token,
        platform: platform,
        language: language,
        projectId: projectId,
        status: RemotePushRegistrationStatus.pendingRegistration,
      ),
      epoch,
    );
    await refreshLocal();
    await _syncRemotePushRegistration(_requireSession(), epoch);
    _checkPushIdentity(identity, epoch);
    return _remotePushState;
  }

  Future<RemotePushRegistrationState> disableRemotePush({
    required RemotePushIdentity identity,
  }) async {
    final epoch = _epoch;
    _checkPushIdentity(identity, epoch);
    final old = _pushIntent;
    if (old != null &&
        old.identity.same(identity) &&
        !old.enabled &&
        old.status != RemotePushRegistrationStatus.blocked) {
      if (old.pending) {
        await _syncRemotePushRegistration(_requireSession(), epoch);
      }
      _checkPushIdentity(identity, epoch);
      return _remotePushState;
    }
    await _writeRemotePush(
      RemotePushIntent(
        identity: identity,
        generation: newSharedId(),
        enabled: false,
        status: RemotePushRegistrationStatus.pendingUnregistration,
      ),
      epoch,
    );
    await refreshLocal();
    await _syncRemotePushRegistration(_requireSession(), epoch);
    _checkPushIdentity(identity, epoch);
    return _remotePushState;
  }

  Future<void> _syncRemotePushRegistration(
    DeviceSession session,
    int epoch,
  ) async {
    if (_pushSyncing || pushStore == null) return;
    _pushSyncing = true;
    final done = _pushSyncDone = Completer<void>();
    try {
      if (!_pushRestored) {
        await _restoreRemotePush(epoch);
      }
      while (true) {
        _checkEpoch(epoch);
        final savedIntent = _pushIntent;
        if (savedIntent?.status == RemotePushRegistrationStatus.registered) {
          await _verifyRemotePushRegistration(session, epoch, savedIntent!);
          return;
        }
        if (savedIntent == null ||
            !savedIntent.identity.matches(session.profile) ||
            !savedIntent.pending) {
          return;
        }
        var intent = savedIntent;
        if (intent.enabled &&
            (!_externalPushSupported || _pushProjectId != intent.projectId)) {
          await _writeRemotePush(
            intent.copy(
              status: RemotePushRegistrationStatus.unavailable,
              errorCode: _externalPushSupported
                  ? 'push_project_mismatch'
                  : 'push_unavailable',
            ),
            epoch,
            onlyGeneration: intent.generation,
          );
          return;
        }
        try {
          if (intent.status == RemotePushRegistrationStatus.unavailable) {
            intent = intent.copy(
              status: RemotePushRegistrationStatus.pendingRegistration,
            );
            if (!await _writeRemotePush(
              intent,
              epoch,
              onlyGeneration: intent.generation,
            )) {
              continue;
            }
          }
          if (intent.expectedRevision == null) {
            final stateReply = await _callSession(
              session,
              epoch,
              'push.state',
              {},
            );
            final wire = stateReply['registration'];
            if (wire is! Map<String, dynamic> ||
                wire['registered'] is! bool ||
                wire['revision'] is! int ||
                (wire['revision'] as int) < 0) {
              throw const CollaborationException('invalid_response');
            }
            intent = intent.copy(expectedRevision: wire['revision'] as int);
            if (!await _writeRemotePush(
              intent,
              epoch,
              onlyGeneration: intent.generation,
            )) {
              continue;
            }
          }
          final reply = await _callSession(
            session,
            epoch,
            intent.enabled ? 'push.register' : 'push.unregister',
            {
              if (intent.enabled) ...{
                'token': intent.token,
                'platform': intent.platform,
                'language': intent.language,
                'projectId': intent.projectId,
              },
              'expectedRevision': intent.expectedRevision,
            },
          );
          final wire = reply['registration'];
          if (wire is! Map<String, dynamic> ||
              wire['registered'] != intent.enabled ||
              wire['revision'] is! int ||
              (wire['revision'] as int) < intent.expectedRevision!) {
            throw const CollaborationException('invalid_response');
          }
          final accepted = intent.copy(
            confirmedRevision: wire['revision'] as int,
            status: intent.enabled
                ? RemotePushRegistrationStatus.registered
                : RemotePushRegistrationStatus.disabled,
          );
          await _writeRemotePush(
            accepted,
            epoch,
            onlyGeneration: intent.generation,
          );
        } on CollaborationException catch (e) {
          _checkEpoch(epoch);
          final status = e.code == 'network' || e.code == 'rate_limited'
              ? intent.status
              : e.code == 'push_unavailable'
              ? RemotePushRegistrationStatus.unavailable
              : RemotePushRegistrationStatus.blocked;
          await _writeRemotePush(
            intent.copy(status: status, errorCode: e.code),
            epoch,
            onlyGeneration: intent.generation,
          );
          return;
        }
      }
    } finally {
      _pushSyncing = false;
      done.complete();
      await refreshLocal();
    }
  }

  Future<bool> receiveRemotePushReference(RemotePushReference reference) async {
    RemotePushReference.parse(reference.toData());
    final session = _session;
    if (_sessionInvalidReason != null) return false;
    if (session == null || !reference.matches(session.profile)) return false;
    final epoch = _epoch;
    await syncNow();
    _checkEpoch(epoch);
    return true;
  }
}
