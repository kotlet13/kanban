part of 'collaboration_repository.dart';

extension CollaborationEmailInvitations on CollaborationRepository {
  Future<T> _withInvitationStore<T>(Future<T> Function() action) =>
      invitationStore.serialized(action);

  Future<PendingInvitation?> pendingInvitation() async {
    final pending = await invitationStore.read();
    if (pending?.accountPartition != null &&
        pending!.accountPartition != _session?.profile.partition) {
      return null;
    }
    return pending;
  }

  /// Store first, even while offline, then pin the server via public capabilities
  /// before any request containing the invitation token.
  Future<void> rememberInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) => _withInvitationStore(() async {
    if (!RegExp(r'^fhi[12]_[a-f0-9]{64}$').hasMatch(token)) {
      throw const CollaborationException('invalid_invitation');
    }
    // Native invitation links and durable tokens always require HTTPS.
    final base = normalizeCollaborationServer(serverUrl);
    final previous = await invitationStore.read();
    if (previous?.token == token && previous?.serverUrl != base) {
      throw const CollaborationException('invitation_identity_mismatch');
    }
    if (previous?.token == token && previous?.serverUrl == base) return;
    await invitationStore.write(
      PendingInvitation(serverUrl: base, token: token),
    );
  });

  Future<void> _clearMatchingInvitation(
    String token, {
    required String serverUrl,
  }) => _withInvitationStore(() async {
    final pending = await invitationStore.read();
    if (pending?.token == token && pending?.serverUrl == serverUrl) {
      await invitationStore.write(null);
    }
  });

  Future<void> clearPendingInvitation({String? expectedToken}) =>
      _withInvitationStore(() async {
        final pending = await invitationStore.read();
        if (expectedToken == null || pending?.token == expectedToken) {
          await invitationStore.write(null);
        }
      });

  Future<Map<String, dynamic>> _emailInvitationCapabilities(
    String base, {
    bool allowLocalHttp = false,
    PendingInvitation? pending,
  }) async {
    final caps = await transport.call(
      serverUrl: base,
      operation: 'capabilities',
      allowLocalHttp: allowLocalHttp,
    );
    if (caps['api'] != 'familyhub_native' ||
        caps['version'] != 1 ||
        caps['enabled'] != true ||
        caps['serverId'] is! String) {
      throw const CollaborationException('incompatible_server');
    }
    if (pending?.serverId != null && caps['serverId'] != pending!.serverId) {
      throw const CollaborationException('server_identity_changed');
    }
    if ((caps['features'] as Map?)?['emailInvitations'] != true ||
        !(caps['invitationContractVersions'] as List? ?? const []).contains(
          2,
        )) {
      throw const CollaborationException('email_invitations_unavailable');
    }
    return caps;
  }

  SharedInvitationPreview _emailInvitationPreview(Map<String, dynamic> reply) {
    final invitation = reply['invitation'] as Map<String, dynamic>,
        scope = reply['scope'] as Map<String, dynamic>;
    return SharedInvitationPreview(
      scopeName: readString(scope, 'name'),
      scopeId: readString(scope, 'id'),
      kind: SharedScopeKind.values.byName(readString(scope, 'kind')),
      recipientUsername: invitation['recipientUsername'] as String? ?? '',
      recipientEmail: invitation['recipientEmail'] as String?,
      invitationId: readString(invitation, 'id'),
      contractVersion: 2,
      inviterName: reply['inviterName'] as String? ?? '',
      projectFinanceIncluded: scope['projectFinanceIncluded'] == true,
      requiresExplicitAcceptance: reply['requiresExplicitAcceptance'] == true,
      role: SharedRole.values.byName(readString(invitation, 'role')),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        readInt(invitation, 'expiresAt') * 1000,
        isUtc: true,
      ),
      registrationAllowed: reply['registrationAllowed'] == true,
    );
  }

  Future<SharedInvitationPreview> previewEmailInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) async {
    await rememberInvitation(
      serverUrl: serverUrl,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    final epoch = _epoch;
    final pending = (await invitationStore.read())!;
    if (pending.token != token) {
      throw const CollaborationException('session_changed');
    }
    final caps = await _emailInvitationCapabilities(
      pending.serverUrl,
      pending: pending,
      allowLocalHttp: allowLocalHttp,
    );
    _checkEpoch(epoch);
    await _withInvitationStore(() async {
      final current = await invitationStore.read();
      if (current?.token != token || current?.serverUrl != pending.serverUrl) {
        throw const CollaborationException('session_changed');
      }
      await invitationStore.write(
        PendingInvitation(
          serverUrl: pending.serverUrl,
          token: token,
          serverId: caps['serverId'] as String,
          expiresAt: pending.expiresAt,
          accountPartition: pending.accountPartition,
          invitationId: pending.invitationId,
        ),
      );
    });
    final session = _session;
    final canRecoverAcceptance =
        pending.accountPartition != null &&
        session != null &&
        pending.accountPartition == session.profile.partition &&
        pending.serverUrl == session.profile.serverUrl &&
        caps['serverId'] == session.profile.serverId;
    final reply = canRecoverAcceptance
        ? await _callSession(session, epoch, 'invitations2.preview', {
            'token': token,
          })
        : await transport.call(
            serverUrl: pending.serverUrl,
            operation: 'invitations2.preview',
            params: {'token': token},
            allowLocalHttp: allowLocalHttp,
          );
    _checkEpoch(epoch);
    final preview = _emailInvitationPreview(reply);
    await _withInvitationStore(() async {
      final current = await invitationStore.read();
      if (current?.token != token || current?.serverUrl != pending.serverUrl) {
        throw const CollaborationException('session_changed');
      }
      await invitationStore.write(
        PendingInvitation(
          serverUrl: pending.serverUrl,
          token: token,
          serverId: caps['serverId'] as String,
          expiresAt: preview.expiresAt,
          accountPartition: pending.accountPartition,
          invitationId: preview.invitationId,
        ),
      );
    });
    return preview;
  }

  Future<void> registerWithEmailInvitation({
    required String serverUrl,
    required String invitationToken,
    required String username,
    required String name,
    required String password,
    bool allowLocalHttp = false,
    String deviceName = 'Jivie',
  }) async {
    await previewEmailInvitation(
      serverUrl: serverUrl,
      token: invitationToken,
      allowLocalHttp: allowLocalHttp,
    );
    final pending = await invitationStore.read();
    if (pending?.token != invitationToken || pending?.serverId == null) {
      throw const CollaborationException('invitation_identity_mismatch');
    }
    await _authenticate(
      serverUrl,
      'auth.registerInvitation2',
      {
        'token': invitationToken,
        'username': username,
        'displayName': name,
        'password': password,
        'deviceName': deviceName,
      },
      allowLocalHttp,
      expectedServerId: pending!.serverId,
    );
  }

  Future<SharedInvitation> createEmailInvitation({
    required String scopeId,
    required String recipientEmail,
    SharedRole role = SharedRole.member,
    String language = 'sl',
    String? requestId,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    await _negotiate(session, epoch);
    if (!_emailInvitationsSupported) {
      throw const CollaborationException('email_invitations_unavailable');
    }
    final reply = await _callSession(session, epoch, 'invitations2.create', {
      'scopeId': scopeId,
      'recipientEmail': recipientEmail.trim(),
      'role': role.name,
      'language': language,
      'requestId': requestId ?? newSharedId(),
    });
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _invalidateMemberDirectory(session.profile.partition, scopeId);
    });
    return SharedInvitation.fromJson({
      ...reply['invitation'] as Map<String, dynamic>,
      'deliveryQueued': reply['deliveryQueued'] == true,
    });
  }

  Future<List<SharedInvitationPreview>> pendingInvitations() async {
    final session = _requireSession(), epoch = _epoch;
    await _negotiate(session, epoch);
    if (!_emailInvitationsSupported) return const [];
    final reply = await _callSession(
      session,
      epoch,
      'invitations2.pending',
      const {},
    );
    return (reply['invitations'] as List)
        .map((item) => _emailInvitationPreview(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> acceptEmailInvitation({
    String? token,
    String? invitationId,
  }) async {
    if ((token == null) == (invitationId == null)) {
      throw const CollaborationException('invalid_invitation');
    }
    final session = _requireSession(), epoch = _epoch;
    await _negotiate(session, epoch);
    if (!_emailInvitationsSupported) {
      throw const CollaborationException('email_invitations_unavailable');
    }
    if (token != null) {
      await _withInvitationStore(() async {
        final pending = await invitationStore.read();
        if (pending == null ||
            pending.token != token ||
            pending.serverUrl != session.profile.serverUrl ||
            pending.serverId != session.profile.serverId ||
            (pending.accountPartition != null &&
                pending.accountPartition != session.profile.partition)) {
          throw const CollaborationException('invitation_identity_mismatch');
        }
        _checkEpoch(epoch);
        await invitationStore.write(
          PendingInvitation(
            serverUrl: pending.serverUrl,
            token: token,
            serverId: pending.serverId,
            expiresAt: pending.expiresAt,
            accountPartition: session.profile.partition,
            invitationId: pending.invitationId,
          ),
        );
      });
    }
    if (invitationId != null) {
      await _withInvitationStore(() async {
        final pending = await invitationStore.read();
        if (pending?.invitationId != invitationId) return;
        if (pending!.serverUrl != session.profile.serverUrl ||
            pending.serverId != session.profile.serverId ||
            (pending.accountPartition != null &&
                pending.accountPartition != session.profile.partition)) {
          throw const CollaborationException('invitation_identity_mismatch');
        }
        _checkEpoch(epoch);
        await invitationStore.write(
          PendingInvitation(
            serverUrl: pending.serverUrl,
            token: pending.token,
            serverId: pending.serverId,
            expiresAt: pending.expiresAt,
            invitationId: invitationId,
            accountPartition: session.profile.partition,
          ),
        );
      });
    }
    Map<String, dynamic> reply;
    try {
      reply = await _callSession(session, epoch, 'invitations2.accept', {
        if (token != null) 'token': token,
        if (invitationId != null) 'invitationId': invitationId,
      });
    } on CollaborationApiException catch (error) {
      // A definitive rejection means the server did not accept this account.
      // Preserve the capability so its intended recipient can sign in instead.
      if (error.code == 'invitation_invalid') {
        await _withInvitationStore(() async {
          _checkEpoch(epoch);
          final pending = await invitationStore.read();
          if (pending != null &&
              ((token != null && pending.token == token) ||
                  (invitationId != null &&
                      pending.invitationId == invitationId)) &&
              pending.accountPartition == session.profile.partition) {
            await invitationStore.write(
              PendingInvitation(
                serverUrl: pending.serverUrl,
                token: pending.token,
                serverId: pending.serverId,
                expiresAt: pending.expiresAt,
                invitationId: pending.invitationId,
              ),
            );
          }
        });
      }
      rethrow;
    }
    final scopeId = SharedScope.fromJson(
      reply['scope'] as Map<String, dynamic>,
    ).id;
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _invalidateMemberDirectory(session.profile.partition, scopeId);
    });
    if (token != null) {
      await _withInvitationStore(() async {
        _checkEpoch(epoch);
        final pending = await invitationStore.read();
        if (pending?.token == token &&
            pending?.accountPartition == session.profile.partition) {
          await invitationStore.write(null);
        }
      });
    }
    if (invitationId != null) {
      await _withInvitationStore(() async {
        _checkEpoch(epoch);
        final pending = await invitationStore.read();
        if (pending?.invitationId == invitationId &&
            pending?.serverUrl == session.profile.serverUrl &&
            pending?.serverId == session.profile.serverId &&
            (pending?.accountPartition == null ||
                pending?.accountPartition == session.profile.partition)) {
          await invitationStore.write(null);
        }
      });
    }
    await syncNow();
    _checkEpoch(epoch);
  }
}
