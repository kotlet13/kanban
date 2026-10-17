part of 'collaboration_repository.dart';

extension CollaborationModeration on CollaborationRepository {
  /// Loads only an immutable image named by this exact authorized preview.
  /// A hash alone is never an authorization or a cross-workspace cache key.
  Future<Uint8List> loadReportIdeaAsset(
    ContentReportPreview preview,
    IdeaAsset asset,
  ) async {
    final session = _requireSession(), epoch = _epoch;
    _checkModerationContext(
      session,
      preview.partition,
      preview.serverId,
      preview.deviceId,
    );
    if (preview.targetType != 'record' || preview.type != 'idea') {
      throw const CollaborationException('invalid_response');
    }
    final board = IdeaBoard.fromJson(
      Map<String, dynamic>.from(preview.evidence['board'] as Map),
    );
    if (board.id != preview.targetId ||
        !board.assets.any(
          (a) => jsonEncode(a.toJson()) == jsonEncode(asset.toJson()),
        )) {
      throw const CollaborationException('invalid_response');
    }
    await _writableReadIdea(
      session.profile.partition,
      preview.scopeId,
      board.id,
    );
    final bytes = <int>[];
    while (bytes.length < asset.size) {
      final offset = bytes.length;
      final reply = await _callSession(session, epoch, 'ideas.asset.get', {
        'scopeId': preview.scopeId,
        'boardId': board.id,
        'sha256': asset.sha256,
        'offset': offset,
        'limit': 262144,
      });
      if (reply['sha256'] != asset.sha256 ||
          reply['size'] != asset.size ||
          reply['offset'] != offset ||
          reply['mime'] != asset.mime ||
          reply['width'] != asset.width ||
          reply['height'] != asset.height) {
        throw const CollaborationException('invalid_response');
      }
      final chunk = base64Decode(reply['data'] as String);
      if (chunk.isEmpty ||
          chunk.length > 262144 ||
          bytes.length + chunk.length > asset.size) {
        throw const CollaborationException('invalid_response');
      }
      bytes.addAll(chunk);
    }
    final result = Uint8List.fromList(bytes);
    await verifyIdeaAsset(asset, result);
    _checkEpoch(epoch);
    _checkModerationContext(
      session,
      preview.partition,
      preview.serverId,
      preview.deviceId,
    );
    await _writableReadIdea(
      session.profile.partition,
      preview.scopeId,
      board.id,
    );
    return result;
  }

  void _moderationIdentity(
    DeviceSession session,
    Map<String, dynamic> reply, {
    bool account = true,
  }) {
    if (reply['serverId'] != session.profile.serverId ||
        (account && reply['accountId'] != session.profile.accountId)) {
      throw const CollaborationException('invalid_response');
    }
  }

  Future<void> _requireModeration(DeviceSession session, int epoch) async {
    // Never use cached capabilities as permission to send report evidence.
    await _negotiate(session, epoch);
    if (!_moderationSupported) {
      throw const CollaborationException('moderation_upgrade_required');
    }
  }

  Future<Map<String, dynamic>> _refreshModerationStatus(
    DeviceSession session,
    int epoch,
  ) async {
    final reply = await _callSession(
      session,
      epoch,
      'moderation.policyStatus',
      {},
    );
    _checkEpoch(epoch);
    _moderationIdentity(session, reply);
    if (reply['policyVersion'] != 1 || reply['accepted'] is! bool) {
      throw const CollaborationException('invalid_response');
    }
    _moderationAccepted = reply['accepted'] as bool;
    if (_moderationAccepted != true) {
      _sharedContentPolicy = null;
    }
    _moderationVerifiedEpoch = epoch;
    return reply;
  }

  Future<SharedContentPolicy> sharedContentPolicy({String? scopeId}) async {
    final session = _requireSession(), epoch = _epoch;
    await _requireModeration(session, epoch);
    final policy = await transport.call(
      serverUrl: session.profile.serverUrl,
      operation: 'moderation.policy',
      allowLocalHttp: session.profile.allowLocalHttp,
    );
    _checkEpoch(epoch);
    _moderationIdentity(session, policy, account: false);
    if (policy['contractVersion'] != 1 || policy['policyVersion'] != 1) {
      throw const CollaborationException('invalid_response');
    }
    final status = await _refreshModerationStatus(session, epoch);
    final result = SharedContentPolicy(
      serverId: session.profile.serverId,
      partition: session.profile.partition,
      deviceId: session.profile.deviceId,
      policyVersion: readInt(policy, 'policyVersion'),
      title: readString(policy, 'title'),
      textSl: readString(policy, 'textSl'),
      textEn: readString(policy, 'textEn'),
      recipientName: readString(
        Map<String, dynamic>.from(policy['recipient'] as Map),
        'name',
      ),
      accepted: status['accepted'] as bool,
      acceptedAt: status['acceptedAt'] == null
          ? null
          : DateTime.parse(status['acceptedAt'] as String),
    );
    _checkEpoch(epoch);
    _sharedContentPolicy = result;
    await refreshLocal();
    _checkEpoch(epoch);
    return result;
  }

  void _checkModerationContext(
    DeviceSession session,
    String partition,
    String serverId,
    String deviceId,
  ) {
    if (session.profile.partition != partition ||
        session.profile.serverId != serverId ||
        session.profile.deviceId != deviceId) {
      throw const CollaborationException('session_changed');
    }
  }

  Future<void> acceptSharedContentPolicy(SharedContentPolicy policy) async {
    final session = _requireSession(), epoch = _epoch;
    _checkModerationContext(
      session,
      policy.partition,
      policy.serverId,
      policy.deviceId,
    );
    await _requireModeration(session, epoch);
    final reply = await _callSession(
      session,
      epoch,
      'moderation.acceptPolicy',
      {'policyVersion': policy.policyVersion},
    );
    _moderationIdentity(session, reply);
    if (reply['policyVersion'] != policy.policyVersion ||
        reply['accepted'] != true) {
      throw const CollaborationException('policy_acceptance_required');
    }
    _checkEpoch(epoch);
    _moderationAccepted = true;
    _moderationVerifiedEpoch = epoch;
    _sharedContentPolicy = SharedContentPolicy(
      serverId: policy.serverId,
      partition: policy.partition,
      deviceId: policy.deviceId,
      policyVersion: policy.policyVersion,
      title: policy.title,
      textSl: policy.textSl,
      textEn: policy.textEn,
      recipientName: policy.recipientName,
      accepted: true,
      acceptedAt: reply['acceptedAt'] == null
          ? null
          : DateTime.parse(reply['acceptedAt'] as String),
    );
    // Acceptance itself never sends previously queued edits or a report.
    await refreshLocal();
    _checkEpoch(epoch);
  }

  Future<ContentReportPreview> previewContentReport({
    required String scopeId,
    required String targetType,
    required String targetId,
  }) async {
    if (!const {
          'record',
          'finance',
          'user',
          'table',
          'attachment',
        }.contains(targetType) ||
        !isSharedUuid(scopeId) ||
        !isSharedUuid(targetId)) {
      throw const CollaborationException('validation_error');
    }
    final session = _requireSession(), epoch = _epoch;
    await _requireModeration(session, epoch);
    final reply = await _callSession(
      session,
      epoch,
      'moderation.reportPreview',
      {'scopeId': scopeId, 'targetType': targetType, 'targetId': targetId},
    );
    _moderationIdentity(session, reply);
    if (reply['scopeId'] != scopeId ||
        reply['targetType'] != targetType ||
        reply['targetId'] != targetId ||
        reply['evidence'] is! Map ||
        reply['subject'] is! Map ||
        reply['recipient'] is! Map ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(readString(reply, 'previewHash'))) {
      throw const CollaborationException('invalid_response');
    }
    final subject = Map<String, dynamic>.from(reply['subject'] as Map);
    return ContentReportPreview(
      serverId: session.profile.serverId,
      partition: session.profile.partition,
      deviceId: session.profile.deviceId,
      requestId: newSharedId(),
      scopeId: scopeId,
      targetType: targetType,
      targetId: targetId,
      previewHash: readString(reply, 'previewHash'),
      targetRevision: readInt(reply, 'targetRevision'),
      title: readString(subject, 'title'),
      type: readString(subject, 'type'),
      recipientName: readString(
        Map<String, dynamic>.from(reply['recipient'] as Map),
        'name',
      ),
      evidence: Map<String, dynamic>.from(reply['evidence'] as Map),
    );
  }

  Future<ContentReportReceipt> submitContentReport({
    required ContentReportPreview preview,
    required String reason,
    String details = '',
  }) async {
    if (!const {
          'harassment',
          'hate',
          'sexual',
          'violence',
          'illegal',
          'spam',
          'privacy',
          'other',
        }.contains(reason) ||
        utf8.encode(details).length > 2000) {
      throw const CollaborationException('validation_error');
    }
    final session = _requireSession(), epoch = _epoch;
    _checkModerationContext(
      session,
      preview.partition,
      preview.serverId,
      preview.deviceId,
    );
    await _requireModeration(session, epoch);
    final reply = await _callSession(session, epoch, 'moderation.report', {
      'requestId': preview.requestId,
      'scopeId': preview.scopeId,
      'targetType': preview.targetType,
      'targetId': preview.targetId,
      'previewHash': preview.previewHash,
      'reason': reason,
      'details': details,
    });
    _moderationIdentity(session, reply, account: false);
    if (reply['status'] != 'submitted' ||
        !isSharedUuid(readString(reply, 'reportId'))) {
      throw const CollaborationException('invalid_response');
    }
    return ContentReportReceipt(
      reportId: readString(reply, 'reportId'),
      status: 'submitted',
      createdAt: DateTime.parse(readString(reply, 'createdAt')),
    );
  }

  bool get _sharedUploadsAllowed =>
      _moderationSupported && _moderationAccepted == true;

  Future<bool> _requiresSharedContentPolicy(
    DeviceSession session,
    String operation,
    Map<String, Object?> params,
  ) async {
    final parts = operation.split('.');
    if (parts.length != 2) return false;
    final actions = <String, Set<String>>{
      'scopes': {
        'create',
        'updateMetadata',
        'setLeader',
        'accessMigrationApply',
        'projectSharingApply',
      },
      for (final prefix in ['invitations', 'invitations2', 'invitations3'])
        prefix: {'create'},
      for (final prefix in [
        'sync',
        'sync2',
        'sync3',
        'sync4',
        'sync5',
        'sync6',
      ])
        prefix: {'push', 'pushTaskWithCost'},
      for (final prefix in ['finance', 'finance2', 'finance4'])
        prefix: {'push', 'enable', 'grant'},
      'finance3': {'paymentCommit', 'paymentReimburse'},
      'reminders': {'put'},
      'tables': {'create', 'save'},
      'attachments': {'begin', 'chunk', 'complete'},
    };
    if (actions[parts.first]?.contains(parts.last) != true) {
      return false;
    }
    if (operation == 'scopes.create' && params['kind'] == 'personal') {
      return false;
    }
    final scopeId = params['scopeId'];
    return scopeId is! String ||
        !await _isPersonalScope(session.profile.partition, scopeId);
  }

  Future<void> _guardSharedUpload(
    DeviceSession session,
    int epoch, {
    bool capabilitiesVerified = false,
  }) async {
    if (_syncEpoch != epoch && !capabilitiesVerified) {
      await _negotiate(session, epoch);
    }
    if (!_moderationSupported) {
      throw const CollaborationException('moderation_upgrade_required');
    }
    if (_moderationVerifiedEpoch != epoch) {
      await _refreshModerationStatus(session, epoch);
    }
    if (_moderationAccepted != true) {
      throw const CollaborationException('policy_acceptance_required');
    }
    _checkEpoch(epoch);
  }
}
