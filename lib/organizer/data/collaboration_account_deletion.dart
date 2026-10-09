part of 'collaboration_repository.dart';

extension CollaborationAccountDeletion on CollaborationRepository {
  Future<T> _deletionSecure<T>(Future<T> Function() action) {
    final result = _deletionQueue.then((_) => action());
    _deletionQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<Map<String, dynamic>> previewAccountDeletion() async {
    final session = _requireSession(), epoch = _epoch;
    await _negotiate(session, epoch);
    if (!_accountDeletionSupported) {
      throw const CollaborationException('deletion_unavailable');
    }
    final result =
        await _callSession(session, epoch, 'account.deletion.preview', {
          if (_accountDeletionPolicyVersion >= 2)
            'policyVersion': _accountDeletionPolicyVersion,
        });
    return decodeAccountDeletionPreview(result, session.profile);
  }

  Future<List<PendingAccountDeletion>> pendingAccountDeletions() =>
      deletionStore.read();

  Future<void> confirmAccountDeletion({
    required String previewHash,
    required String password,
    String? otp,
    List<Map<String, Object?>> ownershipTransfers = const [],
    List<Map<String, Object?>> resolutions = const [],
    List<String> ownedScopeDeletions = const [],
    Map<String, dynamic> review = const {},
  }) => _deletionSecure(
    () => _confirmAccountDeletion(
      previewHash: previewHash,
      password: password,
      otp: otp,
      ownershipTransfers: ownershipTransfers,
      resolutions: resolutions,
      ownedScopeDeletions: ownedScopeDeletions,
      review: review,
    ),
  );

  Future<void> _confirmAccountDeletion({
    required String previewHash,
    required String password,
    String? otp,
    List<Map<String, Object?>> ownershipTransfers = const [],
    List<Map<String, Object?>> resolutions = const [],
    List<String> ownedScopeDeletions = const [],
    Map<String, dynamic> review = const {},
  }) async {
    final session = _requireSession(), epoch = _epoch;
    if (!_accountDeletionSupported) {
      throw const CollaborationException('deletion_unavailable');
    }
    final pending = await deletionStore.read();
    _checkEpoch(epoch);
    final previous = pending
        .where((r) => r.profile.partition == session.profile.partition)
        .firstOrNull;
    if (previous != null &&
        (previous.serverAccepted ||
            previous.previewHash != previewHash ||
            jsonEncode(previous.ownershipTransfers) !=
                jsonEncode(ownershipTransfers) ||
            jsonEncode(previous.resolutions) != jsonEncode(resolutions) ||
            jsonEncode(previous.ownedScopeDeletions) !=
                jsonEncode(ownedScopeDeletions))) {
      throw const CollaborationException('deletion_pending');
    }
    final random = Random.secure();
    final request =
        previous ??
        PendingAccountDeletion(
          profile: session.profile,
          operationId: newSharedId(),
          previewHash: previewHash,
          ownershipTransfers: ownershipTransfers,
          resolutions: resolutions,
          ownedScopeDeletions: ownedScopeDeletions,
          review: review,
          policyVersion:
              review['policyVersion'] as int? ?? _accountDeletionPolicyVersion,
          receiptToken: List.generate(
            32,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join(),
        );
    // A new preview is mandatory after a stale/blocked response. Nothing is sent
    // before the receipt is durable, so a killed app can inspect an ambiguous ACK.
    await deletionStore.write([
      ...pending.where((r) => r.profile.partition != session.profile.partition),
      request,
    ]);
    _checkEpoch(epoch);
    await database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      ['deletion_pending:${session.profile.partition}', '1'],
    );
    _checkEpoch(epoch);
    database.activatePersonal(null);
    await refreshLocal();
    Map<String, dynamic> reply;
    try {
      reply = await _callSession(session, epoch, 'account.deletion.confirm', {
        'operationId': request.operationId,
        'receiptToken': request.receiptToken,
        'previewHash': request.previewHash,
        'ownershipTransfers': request.ownershipTransfers,
        'resolutions': request.resolutions,
        'ownedScopeDeletions': request.ownedScopeDeletions,
        'password': password,
        if (otp != null) 'otp': otp,
        'confirmation': 'DELETE',
        if (request.policyVersion >= 2) 'policyVersion': request.policyVersion,
      });
    } on CollaborationException catch (e) {
      if (previous == null &&
          const {
            'feature_disabled',
            'unsupported_operation',
            'native_disabled',
            'deletion_preview_stale',
            'deletion_blocked',
            'invalid_credentials',
            'two_factor_required',
            'rate_limited',
            'deletion_unavailable',
          }.contains(e.code)) {
        await database.execute('DELETE FROM local_meta WHERE name=?', [
          'deletion_pending:${session.profile.partition}',
        ]);
        _checkEpoch(epoch);
        database.activatePersonal(session.profile);
        await refreshLocal();
        await deletionStore.write(
          pending
              .where((r) => r.profile.partition != session.profile.partition)
              .toList(),
        );
      }
      rethrow;
    }
    if ((reply['deleted'] != true && reply['cleanupPending'] != true) ||
        reply['serverId'] != session.profile.serverId) {
      throw const CollaborationException('invalid_response');
    }
    _checkEpoch(epoch);
    await _finishAccountDeletion(request, completed: reply['deleted'] == true);
  }

  /// Public receipt check uses the original server, never another account bearer.
  /// false means no confirmed deletion; it does not prove a request cannot still finish.
  Future<bool> checkAccountDeletion(PendingAccountDeletion request) =>
      _deletionSecure(() => _checkAccountDeletion(request));

  Future<bool> _checkAccountDeletion(PendingAccountDeletion request) async {
    final caps = await transport.call(
      serverUrl: request.profile.serverUrl,
      operation: 'capabilities',
      allowLocalHttp: request.profile.allowLocalHttp,
    );
    if (caps['serverId'] != request.profile.serverId) {
      throw const CollaborationException('server_identity_changed');
    }
    final reply = await transport.call(
      serverUrl: request.profile.serverUrl,
      operation: 'account.deletion.status',
      params: {
        'operationId': request.operationId,
        'receiptToken': request.receiptToken,
      },
      allowLocalHttp: request.profile.allowLocalHttp,
    );
    if (reply['serverId'] != request.profile.serverId ||
        reply['deleted'] is! bool) {
      throw const CollaborationException('invalid_response');
    }
    if (reply['cancelled'] == true) {
      await _finishCancelledDeletion(request);
    }
    if (reply['deleted'] == true || reply['cleanupPending'] == true) {
      await _finishAccountDeletion(
        request,
        completed: reply['deleted'] == true,
      );
    }
    return reply['deleted'] == true;
  }

  Future<bool> cancelPendingAccountDeletion(
    PendingAccountDeletion request,
  ) => _deletionSecure(() async {
    final caps = await transport.call(
      serverUrl: request.profile.serverUrl,
      operation: 'capabilities',
      allowLocalHttp: request.profile.allowLocalHttp,
    );
    if (caps['serverId'] != request.profile.serverId) {
      throw const CollaborationException('server_identity_changed');
    }
    final reply = await transport.call(
      serverUrl: request.profile.serverUrl,
      operation: 'account.deletion.cancelPending',
      // New cancellation markers require the original account's bearer.
      // Existing receipts are public; never borrow another partition's token.
      token: _session?.profile.partition == request.profile.partition
          ? _session!.token
          : null,
      params: {
        'operationId': request.operationId,
        'receiptToken': request.receiptToken,
      },
      allowLocalHttp: request.profile.allowLocalHttp,
    );
    if (reply['serverId'] != request.profile.serverId ||
        reply['deleted'] is! bool ||
        reply['cleanupPending'] is! bool ||
        reply['cancelled'] is! bool) {
      throw const CollaborationException('invalid_response');
    }
    if (reply['deleted'] == true || reply['cleanupPending'] == true) {
      await _finishAccountDeletion(
        request,
        completed: reply['deleted'] == true,
      );
      return false;
    }
    if (reply['cancelled'] == true) {
      await _finishCancelledDeletion(request);
      return true;
    }
    throw const CollaborationException('invalid_response');
  });

  Future<void> _finishCancelledDeletion(PendingAccountDeletion request) async {
    final p = request.profile.partition;
    await database.execute('DELETE FROM local_meta WHERE name=?', [
      'deletion_pending:$p',
    ]);
    final pending = await deletionStore.read();
    await deletionStore.write(
      pending.where((r) => r.operationId != request.operationId).toList(),
    );
    if (_session?.profile.partition == p && _sessionInvalidReason == null) {
      database.activatePersonal(_session!.profile);
    }
    _lastError = null;
    await refreshLocal();
  }

  Future<void> _finishAccountDeletion(
    PendingAccountDeletion request, {
    bool completed = true,
  }) async {
    final p = request.profile.partition;
    final current = _session;
    final matches = current?.profile.partition == p;
    final epoch = matches ? ++_epoch : _epoch;
    if (matches) {
      _session = null;
      if (database.personalProfile?.partition == p) {
        database.activatePersonal(null);
      }
      _sessionInvalidReason = null;
      _pushIntent = null;
      _remotePushState = const RemotePushRegistrationState();
    }
    // The tombstone and all partition data are one commit. Anonymous local work
    // is independent and never copied from a deleted server identity.
    await database.transaction(() async {
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        ['deleted_account:$p', '1'],
      );
      for (final table in [
        'outbox',
        'conflicts',
        'finance_outbox',
        'finance_conflicts',
        'commands',
        'members',
        'inbox',
        'inbox_state',
        'notification_preferences',
        'scheduled_reminders',
        'finance_records',
        'records',
        'sync_leases',
        'scopes',
      ]) {
        await database.execute('DELETE FROM $table WHERE partition=?', [p]);
      }
      for (final table in ['personal_records', 'personal_record_map']) {
        await database.execute('DELETE FROM $table WHERE workspace=?', [
          'private:$p',
        ]);
      }
      await database.execute(
        'DELETE FROM personal_workspaces WHERE partition=?',
        [p],
      );
      await database.execute(
        'DELETE FROM restored_backups WHERE source_partition=?',
        [p],
      );
      // Payment sidecars can also live beside an explicitly selected local
      // target. Remove private links and pending requests for this identity;
      // retain only an already shared household receipt as historical facts.
      for (final table in [
        'linked_payment_events',
        'linked_payment_projections',
        'linked_payment_cash',
      ]) {
        final idColumn = table == 'linked_payment_cash'
            ? 'movement_id'
            : 'event_id';
        for (final row in await database.rows('SELECT * FROM $table')) {
          final key = row['space_key'] as String;
          final data = CollaborationRepository._map(row['data']);
          final remote = key.startsWith('remote:$p:');
          final fromDeletedSource = data['sourcePartition'] == p;
          if (remote ||
              (fromDeletedSource && table == 'linked_payment_events')) {
            await database.execute(
              'DELETE FROM $table WHERE space_key=? AND $idColumn=?',
              [key, row[idColumn]],
            );
          } else if (fromDeletedSource &&
              table == 'linked_payment_projections') {
            await database.execute('DELETE FROM local_meta WHERE name=?', [
              'linked_payment_complete:$key',
            ]);
            if (data['privateAccountId'] != null) {
              final movementIds = [
                data['eventId'],
                for (final leg in data['reimbursements'] as List)
                  (leg as Map)['legId'],
              ];
              for (final id in movementIds) {
                await database.execute(
                  'DELETE FROM linked_payment_cash WHERE space_key=? AND movement_id=?',
                  [key, id],
                );
              }
              await database.execute(
                'DELETE FROM linked_payment_projections WHERE space_key=? AND event_id=?',
                [key, row['event_id']],
              );
            } else {
              data['state'] = 'sourceRemoved';
              await database.execute(
                'UPDATE linked_payment_projections SET data=? WHERE space_key=? AND event_id=?',
                [jsonEncode(data), key, row['event_id']],
              );
            }
          }
        }
      }
      for (final row in await database.rows(
        'SELECT * FROM linked_payment_intents',
      )) {
        final data = CollaborationRepository._map(row['data']);
        final source = data['source'];
        final sourceSpace = source is Map ? source['space'] : null;
        final references = [
          sourceSpace,
          data['personal'],
          data['household'],
          data['organizationAccountScope'],
        ];
        if (data['partition'] == p ||
            references.any((ref) => ref is Map && ref['partition'] == p)) {
          await database.execute(
            'DELETE FROM linked_payment_intents WHERE id=?',
            [row['id']],
          );
        }
      }
      await database.execute('DELETE FROM accounts WHERE partition=?', [p]);
      // Exact comparison, without LIKE wildcard interpretation of server URLs.
      for (final row in await database.rows('SELECT name FROM local_meta')) {
        final name = row['name'] as String;
        if (name != 'deleted_account:$p' &&
            (name.endsWith(':$p') || name.contains(':$p:'))) {
          await database.execute('DELETE FROM local_meta WHERE name=?', [name]);
        }
      }
      await database.touchPersonal();
    });
    await _secure(epoch, () async {
      final stored = await sessionStore.read();
      if (stored?.profile.partition == p) await sessionStore.clear();
    });
    if (pushStore != null) {
      await _pushSecure(() async {
        final intent = await pushStore!.read();
        if (intent?.identity.partition == p) await pushStore!.clear();
        final cleanups = await pushStore!.readCleanups();
        await pushStore!.writeCleanups(
          cleanups.where((c) => c.session.profile.partition != p).toList(),
        );
      });
    }
    final pending = await deletionStore.read();
    await deletionStore.write([
      ...pending.where((r) => r.operationId != request.operationId),
      if (!completed)
        PendingAccountDeletion.fromJson({
          ...request.toJson(),
          'serverAccepted': true,
        }),
    ]);
    _lastError = null;
    await refreshLocal();
  }
}
