import 'dart:async';
import 'dart:convert';

import '../collaboration_transport.dart';
import '../device_session_store.dart';
import 'account_directory_v2.dart';
import 'crypto_identity_store.dart';
import 'crypto_directory_promotion.dart';
import 'crypto_json.dart';
import 'crypto_authority_snapshot.dart';
import 'crypto_capability_discovery.dart';

/// Owns transport material for exactly one bounded verified operation.
class CryptoDirectoryAuthoritySnapshot {
  const CryptoDirectoryAuthoritySnapshot._(
    this._owner,
    this._snapshot,
    this._onFailure,
  );
  final AccountDirectoryRepository _owner;
  final CryptoAuthoritySnapshot _snapshot;
  final void Function()? _onFailure;

  Future<Map<String, dynamic>> _call(
    String operation,
    Map<String, dynamic> params,
  ) async {
    try {
      return await _snapshot.call(operation, params);
    } catch (_) {
      _onFailure?.call();
      rethrow;
    }
  }

  Future<T> run<T>(Future<T> Function() body) => runZoned(
    body,
    zoneValues: {AccountDirectoryRepository._authoritySnapshotZone: this},
  );

  void close() => _snapshot.close();
}

/// A complete signed prefix is identity evidence, not an assertion that the
/// server has shown the latest prefix. Freshness is separately compared with a
/// trusted device, established during genesis, or explicitly reset by recovery.
class AccountDirectoryRepository {
  AccountDirectoryRepository({
    required this.reducer,
    required this.session,
    required this.transport,
    required this.store,
    required this.isCurrent,
  });
  final AccountDirectoryV2 reducer;
  final DeviceSession session;
  final CollaborationTransport transport;
  final CryptoIdentityStore store;
  final bool Function() isCurrent;
  static final _authoritySnapshotZone = Object();
  VerifiedAccountDirectory? _verified;
  static final _queues = <String, Future<void>>{};
  String get accountId => session.profile.accountId;
  void _current() {
    if (!isCurrent() || store.partition != session.profile.partition) {
      throw const CryptoDirectoryException('directory_stale_identity');
    }
  }

  Future<T> exclusive<T>(Future<T> Function() body) async {
    final partition = store.partition;
    final previous = _queues[partition] ?? Future<void>.value();
    final task = previous.then((_) {
      _current();
      return body();
    });
    final marker = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _queues[partition] = marker;
    try {
      return await task;
    } finally {
      if (identical(_queues[partition], marker)) _queues.remove(partition);
    }
  }

  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    _current();
    final snapshot = Zone.current[_authoritySnapshotZone];
    if (snapshot is CryptoDirectoryAuthoritySnapshot &&
        identical(snapshot._owner, this)) {
      final result = await snapshot._call(operation, params);
      _current();
      return result;
    }
    return _callDirect(operation, params);
  }

  /// Denial metadata is an ordinary authenticated read, independent of the
  /// signed authority snapshot. It cannot carry scope content or signed work.
  Future<Map<String, dynamic>> scopeAccessChanges(List<String> scopeIds) =>
      _callDirect('scopes.list', {
        'includeAccessChanges': true,
        'accessChangesOnly': true,
        'scopeIds': List<String>.unmodifiable(scopeIds),
      });

  /// Display metadata is independent of signed authority snapshot material.
  Future<Map<String, dynamic>> memberLabels({
    required String scopeId,
    required String headHash,
    required List<String> accountIds,
  }) async {
    final capabilities = await _callDirect('capabilities', const {});
    if (capabilities['serverId'] != session.profile.serverId) {
      throw const CryptoDirectoryException('directory_server_identity');
    }
    final versions = capabilities['cryptoMemberLabelsVersions'];
    if (versions is! List || !versions.contains(1)) {
      throw const CollaborationApiException('unsupported_operation');
    }
    return _callDirect('crypto2.scope.memberLabels', {
      'scopeId': scopeId,
      'headHash': headHash,
      'accountIds': List<String>.unmodifiable(accountIds),
    });
  }

  /// Scope transport coalescing to the same verified-operation lease as the
  /// signed-proof memo. This never changes directory or scope admission.
  Future<T> withAuthoritySnapshot<T>(
    Future<T> Function() body, {
    required Future<bool> Function() isValid,
    required void Function() onMutation,
  }) async {
    final snapshot = createAuthoritySnapshot(
      isValid: isValid,
      onMutation: onMutation,
    );
    try {
      return await snapshot.run(body);
    } finally {
      snapshot.close();
    }
  }

  CryptoDirectoryAuthoritySnapshot createAuthoritySnapshot({
    required Future<bool> Function() isValid,
    required void Function() onMutation,
    void Function()? onFailure,
  }) => CryptoDirectoryAuthoritySnapshot._(
    this,
    CryptoAuthoritySnapshot(
      read: _callDirect,
      serverId: session.profile.serverId,
      accountId: accountId,
      deviceId: session.profile.deviceId,
      isValid: isValid,
      onMutation: onMutation,
      accountAfterGeneration: () async =>
          _verified?.generation ??
          (await store.anchor(accountId))?['generation'] as int? ??
          0,
      directoryAfterGenerations: _verifiedDirectoryCursorHints,
    ),
    onFailure,
  );

  /// A transport hint for the own prefix already replayed by this repository.
  /// This skips repeated unused log bodies, not any consumer's proof replay.
  /// A cold/incomplete or changed local prefix keeps the original page-zero
  /// bundle; a missing historical page still uses its exact ordinary endpoint.
  Future<Map<String, int>> _verifiedDirectoryCursorHints() async {
    _current();
    final verified = _verified;
    if (verified == null) return const {};
    final anchor = await store.anchor(accountId);
    _current();
    if (!identical(_verified, verified) ||
        anchor == null ||
        anchor['serverId'] != session.profile.serverId ||
        anchor['accountId'] != accountId ||
        anchor['trustState'] != 'verified' ||
        anchor['generation'] != verified.generation ||
        anchor['headHash'] != verified.headHash ||
        anchor['snapshotHash'] != verified.snapshotHash ||
        anchor['fingerprint'] != verified.rootFingerprint) {
      return const {};
    }
    // At most one account, independent of catalog size. Contact and lifecycle
    // hints are deliberately absent: their consumers may need full histories.
    return {accountId: verified.generation};
  }

  Future<Map<String, dynamic>> _callDirect(
    String operation,
    Map<String, dynamic> params,
  ) async {
    _current();
    if (operation == 'capabilities' && params.isEmpty) {
      final result = await CryptoCapabilityDiscovery.read(
        transport: transport,
        session: session,
        authenticated: true,
      );
      _current();
      return result;
    }
    final result = await transport.call(
      serverUrl: session.profile.serverUrl,
      operation: operation,
      params: params,
      token: session.token,
      allowLocalHttp: session.profile.allowLocalHttp,
    );
    _current();
    return result;
  }

  Future<VerifiedAccountDirectory?> refresh({String? externalFingerprint}) =>
      exclusive(() => _refresh(externalFingerprint: externalFingerprint));
  Future<void> _finishCommittedPromotion() async {
    final recovered = await finishCryptoDirectoryPromotion(
      store: store,
      reducer: reducer,
      accountId: accountId,
      serverId: session.profile.serverId,
      isCurrent: () =>
          isCurrent() && store.partition == session.profile.partition,
    );
    if (recovered != null) _verified = recovered;
  }

  Future<VerifiedAccountDirectory?> _refresh({
    String? externalFingerprint,
  }) async {
    await _finishCommittedPromotion();
    final run = reducer.crypto.randomId();
    try {
      return await _refreshRun(
        externalFingerprint: externalFingerprint,
        run: run,
      );
    } finally {
      final anchor = await store.anchor(accountId);
      final durable =
          anchor == null ||
          (await store.database.rows(
            'SELECT generation FROM crypto_directory_entries WHERE partition=? AND account_id=? AND generation=? AND head_hash=?',
            [
              store.partition,
              accountId,
              anchor['generation'],
              anchor['headHash'],
            ],
          )).isNotEmpty;
      if (durable)
        await store.database.execute(
          'DELETE FROM crypto_directory_replay_staging WHERE partition=? AND run_id=?',
          [store.partition, run],
        );
    }
  }

  Future<VerifiedAccountDirectory?> _refreshRun({
    String? externalFingerprint,
    required String run,
  }) async {
    final anchor = await store.anchor(accountId);
    final pin = externalFingerprint ?? anchor?['fingerprint'];
    if (pin is! String || pin.isEmpty) {
      throw const CryptoDirectoryException('directory_identity_unverified');
    }
    if (anchor != null &&
        anchor['fingerprint'] != pin &&
        (anchor['pendingRootTransition'] as Map?)?['newFingerprint'] != pin) {
      throw const CryptoDirectoryException('directory_root_changed');
    }
    final status = await call('crypto2.account.status');
    if (status['serverId'] != session.profile.serverId ||
        status['accountId'] != accountId) {
      throw const CryptoDirectoryException('directory_identity');
    }
    if (status['initialized'] != true) {
      if ((anchor?['generation'] ?? 0) != 0) {
        throw const CryptoDirectoryException('directory_rollback');
      }
      return null;
    }
    final target = status['generation'];
    final targetHead = status['headHash'];
    if (target is! int ||
        target < 1 ||
        targetHead is! String ||
        target < (anchor?['generation'] as int? ?? 0)) {
      throw const CryptoDirectoryException('directory_rollback');
    }
    var state = _verified;

    var genesisPin = anchor?['genesisFingerprint'] as String?;
    String genesisFrom(Map<String, dynamic> entry) {
      final command =
          CryptoJson.decode(
                cryptoBase64((entry['authorization'] as Map)['commandBase64']),
              )
              as Map;
      final payload = command['payload'] as Map;
      return reducer.crypto.fingerprint(
        cryptoBase64(payload['rootSigningKeyBase64'], length: 32),
        cryptoBase64(payload['rootEncryptionKeyBase64'], length: 32),
      );
    }

    // Never restore authority from an unverified database cache or backup row.
    if (state == null) {
      await for (final entry in store.streamEntries(accountId)) {
        genesisPin ??= genesisFrom(entry);
        state = await reducer.apply(
          previous: state,
          entry: entry,
          serverId: session.profile.serverId,
          accountId: accountId,
          pinnedRootFingerprint: genesisPin,
        );
        if (anchor?['generation'] == state.generation &&
            anchor?['headHash'] != state.headHash) {
          throw const CryptoDirectoryException('directory_fork');
        }
      }
    }
    if (state != null && state.generation > target) {
      throw const CryptoDirectoryException('directory_rollback');
    }
    while ((state?.generation ?? 0) < target) {
      final after = state?.generation ?? 0;
      final page = await call('crypto2.account.directory', {
        'afterGeneration': after,
        'limit': 50,
      });
      if (page['generation'] != target ||
          page['headHash'] != targetHead ||
          page['entries'] is! List ||
          (page['entries'] as List).isEmpty) {
        throw const CryptoDirectoryException('directory_changed_retry');
      }
      for (final raw in page['entries'] as List) {
        if (raw is! Map) {
          throw const CryptoDirectoryException('directory_log_shape');
        }
        final entry = Map<String, dynamic>.from(raw);
        genesisPin ??= genesisFrom(entry);
        state = await reducer.apply(
          previous: state,
          entry: entry,
          serverId: session.profile.serverId,
          accountId: accountId,
          pinnedRootFingerprint: genesisPin,
        );
        if (state.generation > target) {
          throw const CryptoDirectoryException('directory_changed_retry');
        }
        if (anchor?['generation'] == state.generation &&
            anchor?['headHash'] != state.headHash) {
          throw const CryptoDirectoryException('directory_fork');
        }
        await store.stageReplay(run, accountId, entry);
      }
      if (page['nextGeneration'] != state!.generation ||
          state.generation <= after) {
        throw const CryptoDirectoryException('directory_log_shape');
      }
    }
    if (state == null ||
        state.headHash != targetHead ||
        state.snapshotHash != status['snapshotHash'] ||
        state.deviceSnapshotHash != status['deviceSnapshotHash']) {
      throw const CryptoDirectoryException('directory_snapshot_mismatch');
    }
    if (status['snapshotIncluded'] == true &&
        base64Encode(CryptoJson.encodeDerivedState(status['snapshot'])) !=
            base64Encode(CryptoJson.encodeDerivedState(state.snapshot))) {
      throw const CryptoDirectoryException('directory_snapshot_mismatch');
    }
    final observedFingerprint = reducer.crypto.fingerprint(
      cryptoBase64(state.snapshot['rootSigningKeyBase64'], length: 32),
      cryptoBase64(state.snapshot['rootEncryptionKeyBase64'], length: 32),
    );
    final handoff = anchor?['pendingRootTransition'];
    Map? completion;
    if (observedFingerprint != pin ||
        (handoff is Map && handoff['newFingerprint'] == observedFingerprint)) {
      if (handoff is! Map || handoff['newFingerprint'] != observedFingerprint) {
        throw const CryptoDirectoryException(
          'directory_root_reverification_required',
        );
      }
      if (await store.entryByHash(accountId, handoff['commandHash']) == null &&
          await store.entryByHash(
                accountId,
                handoff['commandHash'],
                runId: run,
              ) ==
              null) {
        throw const CryptoDirectoryException(
          'directory_root_transition_missing',
        );
      }
      completion = handoff;
    } else {
      await store.pinRoot(
        accountId,
        session.profile.serverId,
        pin,
        genesisFingerprint: genesisPin,
      );
    }
    // Root identity, final ancestry floor and pending-marker retirement commit
    // in one secure write. A rejected fork must not leave half a handoff.
    await store.remember(
      state,
      anchor?['trustState'] as String? ?? 'freshnessPending',
      handoffRequestId: completion?['requestId'] as String?,
      handoffCommandHash: completion?['commandHash'] as String?,
    );
    await store.database.transaction(() async {
      await for (final entry in store.streamEntries(accountId, runId: run)) {
        await store.append(accountId, entry);
      }
    });
    _verified = state;
    return state;
  }

  /// Last locally verified authority permits durable offline staging only.
  /// It does not assert that no revocation happened since the last connection.
  /// Cryptographic own-prefix evidence for isolated frozen-source inspection.
  /// This never marks freshness, changes the anchor, or populates the live memo.
  Future<VerifiedAccountDirectory> replayFileAnchoredCandidate(
    String fingerprint,
  ) => exclusive(() async {
    final before = await store.anchor(accountId);
    if (before == null || before['fingerprint'] != fingerprint) {
      throw const CryptoDirectoryException('directory_recovery_identity');
    }
    VerifiedAccountDirectory? state;
    final genesis = before['genesisFingerprint'] ?? before['fingerprint'];
    await for (final entry in store.streamEntries(accountId)) {
      state = await reducer.apply(
        previous: state,
        entry: entry,
        serverId: session.profile.serverId,
        accountId: accountId,
        pinnedRootFingerprint: genesis,
      );
    }
    final after = await store.anchor(accountId);
    if (!isCurrent() ||
        after == null ||
        base64Encode(CryptoJson.encode(before)) !=
            base64Encode(CryptoJson.encode(after)) ||
        state == null ||
        state.generation != before['generation'] ||
        state.headHash != before['headHash'] ||
        state.snapshotHash != before['snapshotHash'] ||
        state.rootFingerprint != fingerprint) {
      throw const CryptoDirectoryException(
        'directory_recovery_candidate_changed',
      );
    }
    return state;
  });

  Future<VerifiedAccountDirectory> cachedVerifiedDirectory() => exclusive(
    () async {
      await _finishCommittedPromotion();
      final anchor = await store.anchor(accountId);
      if (anchor == null ||
          anchor['trustState'] != 'verified' ||
          anchor['fingerprint'] is! String) {
        throw const CryptoDirectoryException('directory_freshness_pending');
      }
      var state = _verified;
      if (state == null || state.headHash != anchor['headHash']) {
        state = null;
        final pin = anchor['genesisFingerprint'] ?? anchor['fingerprint'];
        await for (final entry in store.streamEntries(accountId)) {
          state = await reducer.apply(
            previous: state,
            entry: entry,
            serverId: session.profile.serverId,
            accountId: accountId,
            pinnedRootFingerprint: pin,
          );
        }
      }
      if (state == null ||
          state.generation != anchor['generation'] ||
          state.headHash != anchor['headHash'] ||
          state.snapshotHash != anchor['snapshotHash'] ||
          reducer.crypto.fingerprint(
                cryptoBase64(
                  state.snapshot['rootSigningKeyBase64'],
                  length: 32,
                ),
                cryptoBase64(
                  state.snapshot['rootEncryptionKeyBase64'],
                  length: 32,
                ),
              ) !=
              anchor['fingerprint']) {
        throw const CryptoDirectoryException('directory_local_anchor_mismatch');
      }
      _verified = state;
      return state;
    },
  );

  Future<VerifiedAccountDirectory> requireFresh() async {
    final state = await refresh();
    final anchor = await store.anchor(accountId);
    if (state == null || anchor?['trustState'] != 'verified') {
      throw const CryptoDirectoryException('directory_freshness_pending');
    }
    state.activeDevice(session.profile.deviceId);
    return state;
  }

  /// The peer supplies this tuple over an independently authenticated channel,
  /// e.g. QR scan or a full safety-code comparison, never from this server alone.
  Future<void> compareTrustedPeer({
    required String fingerprint,
    required int generation,
    required String headHash,
  }) => exclusive(() async {
    final state = await _refresh(externalFingerprint: fingerprint);
    if (state == null ||
        generation != state.generation ||
        headHash != state.headHash) {
      throw const CryptoDirectoryException('directory_peer_head_mismatch');
    }
    await store.remember(state, 'verified');
  });
  Future<void> stageAndSend(
    Future<PreparedDirectoryMutation> Function(
      VerifiedAccountDirectory? previous,
    )
    prepare, {
    String? externalFingerprint,
    bool establishesFreshness = false,
    Future<void> Function()? beforeSendTransaction,
    String? verifiedNewRootFingerprint,
  }) => stageSequenceAndSend(
    (previous) async => [await prepare(previous)],
    externalFingerprint: externalFingerprint,
    establishesFreshness: establishesFreshness,
    beforeSendTransaction: beforeSendTransaction,
    verifiedNewRootFingerprint: verifiedNewRootFingerprint,
  );
  Future<void> stageSequenceAndSend(
    Future<List<PreparedDirectoryMutation>> Function(
      VerifiedAccountDirectory? previous,
    )
    prepare, {
    String? externalFingerprint,
    bool establishesFreshness = false,
    Future<void> Function()? beforeSendTransaction,
    String? verifiedNewRootFingerprint,
  }) => exclusive(() async {
    if ((await store.pending()).isNotEmpty) {
      throw const CryptoDirectoryException('directory_pending_request');
    }
    final previous = await _refresh(externalFingerprint: externalFingerprint);
    if (previous != null &&
        !establishesFreshness &&
        (await store.anchor(accountId))?['trustState'] != 'verified') {
      throw const CryptoDirectoryException('directory_freshness_pending');
    }
    final mutations = await prepare(previous);
    if (mutations.isEmpty) {
      throw const CryptoDirectoryException('directory_empty_sequence');
    }
    if (externalFingerprint != null) {
      await store.pinRoot(
        accountId,
        session.profile.serverId,
        externalFingerprint,
      );
    }
    await store.database.transaction(() async {
      for (final mutation in mutations) {
        await store.stage(mutation.authorization, 'pending');
      }
      if (beforeSendTransaction != null) await beforeSendTransaction();
    });
    for (final mutation in mutations) {
      final c =
          CryptoJson.decode(
                cryptoBase64(mutation.authorization['commandBase64']),
              )
              as Map;
      if (c['operation'] == 'crypto2.account.rotateRoot') {
        if (verifiedNewRootFingerprint == null) {
          throw const CryptoDirectoryException(
            'directory_new_file_not_verified',
          );
        }
        final p = c['payload'] as Map;
        final fp = reducer.crypto.fingerprint(
          cryptoBase64(p['newRootSigningKeyBase64'], length: 32),
          cryptoBase64(p['newRootEncryptionKeyBase64'], length: 32),
        );
        if (fp != verifiedNewRootFingerprint) {
          throw const CryptoDirectoryException(
            'directory_new_file_not_verified',
          );
        }
        await store.authorizeRootHandoff(mutation.authorization, fp);
      }
    }
    for (final mutation in mutations) {
      await _send(
        mutation.authorization,
        externalFingerprint: externalFingerprint,
        establishesFreshness: _establishes(mutation.authorization),
      );
    }
  });
  bool _establishes(Map<String, dynamic> proof) {
    final c = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    return [
      'crypto2.account.initialize',
      'crypto2.account.recoverEpoch',
      'crypto2.account.rotateRoot',
    ].contains(c['operation']);
  }

  Future<void> resume() => exclusive(() async {
    if ((await store.rejected()).isNotEmpty) {
      throw const CryptoDirectoryException('directory_file_reimport_required');
    }
    for (final proof in await store.pending()) {
      await _send(proof, establishesFreshness: _establishes(proof));
    }
  });
  Future<void> _send(
    Map<String, dynamic> proof, {
    String? externalFingerprint,
    bool establishesFreshness = false,
  }) async {
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64']))
            as Map<String, dynamic>;
    if (command['operation'] == 'crypto2.account.rotateRoot') {
      final anchor = await store.anchor(accountId);
      final p = command['payload'] as Map;
      final fp = reducer.crypto.fingerprint(
        cryptoBase64(p['newRootSigningKeyBase64'], length: 32),
        cryptoBase64(p['newRootEncryptionKeyBase64'], length: 32),
      );
      final marker = anchor?['pendingRootTransition'];
      if (anchor?['fingerprint'] != fp &&
          (marker is! Map ||
              marker['requestId'] != command['requestId'] ||
              marker['newFingerprint'] != fp)) {
        throw const CryptoDirectoryException(
          'directory_new_file_reimport_required',
        );
      }
    }
    // Reconcile exact historical outcomes before any current-authority check.
    // A later revocation or root transition cannot invalidate an applied ACK.
    final hash = await cryptoSha256(cryptoBase64(proof['commandBase64']));
    Future<Map<String, dynamic>> lookup() => call('crypto2.receipt.get', {
      'requestId': command['requestId'],
      'requestHash': hash,
    });
    bool exact(Map<String, dynamic> receipt) =>
        receipt['requestHash'] == hash &&
        receipt['requestId'] == command['requestId'] &&
        receipt['status'] is int &&
        base64Encode(CryptoJson.encode(receipt['authorization'])) ==
            base64Encode(CryptoJson.encode(proof));
    var receipt = await lookup();
    if (!exact(receipt)) {
      if (receipt['outcome'] != 'unknown') {
        throw const CryptoDirectoryException('directory_receipt_unknown');
      }
      await store.markSending(command['requestId'] as String);
      try {
        await call(command['operation'] as String, proof);
      } catch (error, stack) {
        final after = await lookup();
        if (!exact(after)) Error.throwWithStackTrace(error, stack);
        receipt = after;
      }
      if (!exact(receipt)) receipt = await lookup();
    }
    if (!exact(receipt)) {
      throw const CryptoDirectoryException('directory_receipt_unknown');
    }
    if (receipt['status'] != 200) {
      await store.recordReceipt(
        command['requestId'] as String,
        receipt,
        'rejected',
      );
      throw const CryptoDirectoryException('directory_file_reimport_required');
    }
    final state = await _refresh(externalFingerprint: externalFingerprint);
    final result = receipt['response'];
    if (state == null ||
        result is! Map ||
        (result['generation'] as int) > state.generation) {
      throw const CryptoDirectoryException('directory_receipt_unknown');
    }
    final history = await store.entries(accountId);
    if (!history.any(
      (entry) =>
          entry['commandHash'] == hash &&
          base64Encode(CryptoJson.encode(entry['authorization'])) ==
              base64Encode(CryptoJson.encode(proof)),
    )) {
      throw const CryptoDirectoryException('directory_receipt_unknown');
    }
    if (establishesFreshness) await store.remember(state, 'verified');
    await store.receipt(command['requestId'] as String, receipt);
  }
}
