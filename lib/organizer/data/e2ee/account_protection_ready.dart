import '../account_work_coordinator.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';
import 'crypto_migration_coordinator.dart';
import 'crypto_scope_observations.dart';
import 'scope_crypto_manager.dart';
import 'scope_crypto_codec.dart';
import '../collaboration_transport.dart' show withCollaborationRateLimitPause;
import '../../domain/collaboration_models.dart' show CollaborationException;

enum AccountProtectionStartupStatus {
  current,
  catalogChanged,
  pending,
  setupRequired,
  recoveryRequired,
  reviewRequired,
}

enum AccountProtectionStartupReason {
  none,
  accountSetup,
  accountPending,
  accountRecovery,
  scopeRecovery,
  completionMissing,
  catalogChanged,
  network,
  rateLimited,
  proofUnavailable,
}

/// Startup presentation evidence only. This never grants connected-write
/// authority or replaces the signed completion and per-scope admission guards.
class AccountProtectionStartupAssessment {
  const AccountProtectionStartupAssessment(this.status, this.reason);
  final AccountProtectionStartupStatus status;
  final AccountProtectionStartupReason reason;
}

/// A signed statement about the fully observed catalog, not proof that an
/// untrusted server disclosed unknown scopes or its globally freshest state.
class AccountProtectionReady {
  AccountProtectionReady(this.account);
  final AccountCryptoV2Workflow account;
  final _stopped = Completer<void>();
  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    _stopped.complete();
  }

  void _current() {
    if (_closed || !account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('protection_completion_cancelled');
    }
  }

  /// Reads the existing account/completion/catalog evidence once. A changed
  /// catalog needs an optional review, not automatic setup or a new signature.
  /// No scope sweep, migration inspection/resume, observation or rotation runs.
  Future<AccountProtectionStartupAssessment> assessStartupReview({
    required bool Function() isCurrent,
  }) async {
    void current({bool directory = false}) {
      if (_closed || !isCurrent()) {
        throw const CryptoAuthorityPending('protection_completion_cancelled');
      }
      if (directory) _current();
    }

    AccountProtectionStartupAssessment? requiredFor(
      String phase,
      bool incomplete,
    ) {
      if (phase != 'ready') {
        return AccountProtectionStartupAssessment(
          phase == 'recoveryRequired'
              ? AccountProtectionStartupStatus.recoveryRequired
              : AccountProtectionStartupStatus.setupRequired,
          phase == 'pending'
              ? AccountProtectionStartupReason.accountPending
              : phase == 'recoveryRequired'
              ? AccountProtectionStartupReason.accountRecovery
              : AccountProtectionStartupReason.accountSetup,
        );
      }
      return incomplete
          ? const AccountProtectionStartupAssessment(
              AccountProtectionStartupStatus.recoveryRequired,
              AccountProtectionStartupReason.scopeRecovery,
            )
          : null;
    }

    current();
    try {
      final phase = await account.localPhase();
      current(directory: phase == 'ready');
      final incomplete = await account.hasIncompleteScopeRecovery();
      current(directory: phase == 'ready');
      final initialRequired = requiredFor(phase, incomplete);
      if (initialRequired != null) return initialRequired;
      final completion = await cachedCompletion();
      current(directory: true);
      bool? matches;
      var completionDeviceMatches = true;
      if (completion != null) {
        matches = await matchesCurrentCatalog(completion);
        current(directory: true);
        // The online refresh may have changed the device snapshot since the
        // cached completion was checked. That is not merely catalog drift.
        completionDeviceMatches = await completionMatchesCurrentDevice(
          completion,
        );
        current(directory: true);
      }
      final finalPhase = await account.localPhase();
      current(directory: true);
      final finalIncomplete = await account.hasIncompleteScopeRecovery();
      current(directory: true);
      final finalRequired = requiredFor(finalPhase, finalIncomplete);
      if (finalRequired != null) return finalRequired;
      if (completion == null || !completionDeviceMatches) {
        return const AccountProtectionStartupAssessment(
          AccountProtectionStartupStatus.reviewRequired,
          AccountProtectionStartupReason.completionMissing,
        );
      }
      return AccountProtectionStartupAssessment(
        matches!
            ? AccountProtectionStartupStatus.current
            : AccountProtectionStartupStatus.catalogChanged,
        matches
            ? AccountProtectionStartupReason.none
            : AccountProtectionStartupReason.catalogChanged,
      );
    } catch (error) {
      // An invalidated/disposed operation cannot publish even an error status
      // for a different account. Unknown evidence is visible pending, not ready.
      current();
      if (!account.directory.isCurrent()) rethrow;
      if (error is CryptoDirectoryException &&
          error.code == 'directory_device_revoked') {
        return const AccountProtectionStartupAssessment(
          AccountProtectionStartupStatus.recoveryRequired,
          AccountProtectionStartupReason.accountRecovery,
        );
      }
      return AccountProtectionStartupAssessment(
        AccountProtectionStartupStatus.pending,
        error is CollaborationException && error.code == 'network'
            ? AccountProtectionStartupReason.network
            : error is CollaborationException && error.code == 'rate_limited'
            ? AccountProtectionStartupReason.rateLimited
            : AccountProtectionStartupReason.proofUnavailable,
      );
    }
  }

  String get _pauseKey =>
      'protectionReady:${account.store.partition}:${account.deviceId}:retry';
  Future<Map<String, dynamic>?> _meta(String name) async {
    final rows = await account.store.database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [name],
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(jsonDecode(rows.single['value'] as String));
  }

  Future<void> _save(String name, Map<String, dynamic> value) =>
      account.store.database.execute(
        'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
        [name, jsonEncode(value)],
      );
  Future<void> _pause(int seconds, void Function(int)? onPause) async {
    _current();
    if (seconds < 1 || seconds > 60) {
      throw const FormatException('protection_retry_deadline');
    }
    await _save(_pauseKey, {
      'retryNotBefore': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds,
    });
    onPause?.call(seconds);
    final elapsed = Completer<void>(),
        timer = Timer(Duration(seconds: seconds), () => elapsed.complete());
    try {
      await Future.any([elapsed.future, _stopped.future]);
    } finally {
      timer.cancel();
    }
    _current();
    await account.store.database.execute(
      'DELETE FROM local_meta WHERE name=?',
      [_pauseKey],
    );
    onPause?.call(0);
  }

  static Future<String> catalogHash(List<Map<String, dynamic>> scopes) async {
    final builder = BytesBuilder(copy: false)
      ..add(utf8.encode('JivieProtectionCatalog/v2\n'));
    String last = '';
    for (final scope in scopes) {
      if ((scope['id'] as String).compareTo(last) <= 0) {
        throw const FormatException('protection_catalog_cursor');
      }
      last = scope['id'];
      builder.add(CryptoJson.encode(scope));
      builder.add([10]);
    }
    builder.add(CryptoJson.encode({'count': scopes.length}));
    return cryptoSha256(builder.takeBytes());
  }

  Future<List<Map<String, dynamic>>> catalog() => withAccountWorkJob(
    account.directory.transport,
    AccountWorkKind.protection,
    () => _accountWorkCatalog(),
  );

  Future<List<Map<String, dynamic>>> _accountWorkCatalog() async {
    final result = <Map<String, dynamic>>[];
    String? after;
    var pages = 0;
    while (true) {
      _current();
      // Exhaustion is an explicit incomplete result, never a truncated catalog.
      if (++pages > 20) {
        throw const CryptoAuthorityPending(
          'protection_catalog_capacity_pending',
        );
      }
      final page = await account.directory.call('crypto2.scopes.catalog', {
        'limit': 50,
        if (after != null) 'afterId': after,
      });
      _current();
      if (page['scopes'] is! List ||
          page['scopes'].length > 50 ||
          page['hasMore'] is! bool) {
        throw const FormatException('protection_catalog_page');
      }
      for (final value in page['scopes'] as List) {
        final s = Map<String, dynamic>.from(value as Map);
        const fields = {
          'id',
          'kind',
          'parentScopeId',
          'role',
          'accessRevision',
          'expectedAccessRevision',
          'accessBasis',
          'cryptoState',
          'headHash',
          'epoch',
          'cryptoOrigin',
          'migrationId',
          'migrationState',
          'members',
        };
        if (s.length != fields.length ||
            s.keys.any((k) => !fields.contains(k)) ||
            s['members'] is! List ||
            s['accessRevision'] is! int ||
            s['epoch'] is! int ||
            s['cryptoOrigin'] is! bool) {
          throw const FormatException('protection_catalog_shape');
        }
        // The original order is authenticated in the catalog hash; do not
        // silently normalize a reordered or duplicated response.
        String last = '';
        for (final m in s['members'] as List) {
          if (m is! Map ||
              m.length != 5 ||
              !{
                'accountId',
                'role',
                'financeRole',
                'manageKeys',
                'deviceSnapshotHash',
              }.every(m.containsKey) ||
              (m['accountId'] as String).compareTo(last) <= 0) {
            throw const FormatException('protection_catalog_members');
          }
          last = m['accountId'];
        }
        result.add(s);
      }
      if (page['hasMore'] != true) break;
      final next = page['nextAfterId'];
      if (next is! String || after != null && next.compareTo(after) <= 0) {
        throw const FormatException('protection_catalog_cursor');
      }
      after = next;
    }
    await catalogHash(result);
    return result;
  }

  Map<String, dynamic> _decodeReview(Object? bytes) =>
      CryptoJson.decode(Uint8List.fromList((bytes as List).cast<int>()))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>?> cachedCompletion() async {
    if (await account.localPhase() != 'ready') return null;
    final directory = await account.directory.cachedVerifiedDirectory();
    directory.activeDevice(account.deviceId);
    if ((await account.store.anchor(directory.accountId))?['trustState'] !=
        'verified') {
      return null;
    }
    final rows = await account.store.database.rows(
      "SELECT authorization FROM crypto_identity_requests WHERE partition=? AND operation='crypto2.account.protectionReady' AND stage='confirmed' AND retired=0 ORDER BY rowid DESC",
      [account.store.partition],
    );
    for (final row in rows) {
      final proof =
              CryptoJson.decode(
                    Uint8List.fromList(
                      (row['authorization'] as List).cast<int>(),
                    ),
                  )
                  as Map<String, dynamic>,
          command =
              CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      if (command['deviceId'] != account.deviceId ||
          command['accountId'] != directory.accountId ||
          command['payload']['deviceSnapshotHash'] !=
              directory.deviceSnapshotHash) {
        continue;
      }
      final hash = await cryptoSha256(cryptoBase64(proof['commandBase64']));
      final exists = await account.store.database.rows(
        'SELECT authorization FROM crypto_directory_entries WHERE partition=? AND account_id=? AND command_hash=?',
        [account.store.partition, directory.accountId, hash],
      );
      if (exists.length != 1 ||
          base64Encode(CryptoJson.encode(proof)) !=
              base64Encode(exists.single['authorization'] as List<int>)) {
        continue;
      }
      final reviews = await account.store.database.rows(
        'SELECT authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state=?',
        [
          account.store.partition,
          directory.accountId,
          command['requestId'],
          'confirmed',
        ],
      );
      if (reviews.isNotEmpty) {
        final signed = _decodeReview(reviews.single['authorization']);
        final actor = directory.activeDevice(account.deviceId);
        final body = account.directory.reducer.crypto.verifyDomain(
          signed,
          cryptoBase64(actor['signingKeyBase64'], length: 32),
          'JivieE2EE/unavailableScopes/v2\n',
        );
        if (body['completionRequestId'] != command['requestId'] ||
            body['deviceSnapshotHash'] != directory.deviceSnapshotHash ||
            body['identityEpochId'] != directory.identityEpochId ||
            body['scopeManifestHash'] !=
                command['payload']['scopeManifestHash']) {
          return null;
        }
        for (final missing in body['missingScopes'] as List) {
          final pin = await account.store.secure.read(
            'scope2:${account.store.partition}:${missing['scopeId']}',
          );
          if (pin == null ||
              await cryptoSha256(Uint8List.fromList(utf8.encode(pin))) !=
                  missing['pinHash']) {
            return null;
          }
        }
      }
      return Map<String, dynamic>.from(command['payload'] as Map);
    }
    return null;
  }

  Future<bool> matchesCurrentCatalog(Map<String, dynamic> completion) async {
    final current = await account.directory.refresh();
    if (current == null) {
      throw const CryptoAuthorityPending('directory_missing');
    }
    current.activeDevice(account.deviceId);
    if (current.deviceSnapshotHash != completion['deviceSnapshotHash']) {
      return false;
    }
    final scopes = await catalog();
    return completion['scopeManifestHash'] == await catalogHash(scopes);
  }

  /// Reuses the freshly replayed own directory; it makes no network call and
  /// cannot make an old device-bound completion current after a device change.
  Future<bool> completionMatchesCurrentDevice(
    Map<String, dynamic> completion,
  ) async {
    _current();
    final current = await account.directory.cachedVerifiedDirectory();
    _current();
    current.activeDevice(account.deviceId);
    return current.deviceSnapshotHash == completion['deviceSnapshotHash'];
  }

  Future<Map<String, dynamic>?> unavailableReview() async {
    final own = await account.directory.requireFresh();
    final scopes = await catalog();
    final missing = await _missingScopes(scopes);
    if (missing.isEmpty) return null;
    final observed = await catalogHash(scopes), job = await _activeJob();
    return _reviewBody(
      own,
      observed,
      missing,
      job?['scopeManifestHash'] == observed &&
              job?['deviceSnapshotHash'] == own.deviceSnapshotHash
          ? job!['requestId'] as String
          : account.directory.reducer.crypto.randomId(),
    );
  }

  Map<String, dynamic> _reviewBody(
    VerifiedAccountDirectory own,
    String observed,
    List<Map<String, dynamic>> missing,
    String requestId,
  ) => {
    'version': 2,
    'purpose': 'unavailableRetainedScopes',
    'serverId': own.serverId,
    'accountId': own.accountId,
    'deviceId': account.deviceId,
    'identityEpochId': own.identityEpochId,
    'deviceSnapshotHash': own.deviceSnapshotHash,
    'scopeManifestHash': observed,
    'missingScopes': missing,
    'completionRequestId': requestId,
  };
  Future<List<Map<String, dynamic>>> _missingScopes(
    List<Map<String, dynamic>> scopes,
  ) async {
    final known = await account.store.database.rows(
      'SELECT DISTINCT scope_id FROM crypto_scope_heads WHERE partition=? ORDER BY scope_id',
      [account.store.partition],
    );
    final missing = <Map<String, dynamic>>[];
    for (final row in known) {
      final pin = await account.store.secure.read(
        'scope2:${account.store.partition}:${row['scope_id']}',
      );
      if (pin != null && !scopes.any((s) => s['id'] == row['scope_id'])) {
        missing.add({
          'scopeId': row['scope_id'],
          'pinHash': await cryptoSha256(Uint8List.fromList(utf8.encode(pin))),
        });
      }
    }
    return missing;
  }

  Future<void> complete({
    Map<String, dynamic>? reviewedUnavailable,
    void Function(int)? onPause,
  }) => withAccountWorkJob(
    account.directory.transport,
    AccountWorkKind.protection,
    () => _accountWorkComplete(
      reviewedUnavailable: reviewedUnavailable,
      onPause: onPause,
    ),
  );

  Future<void> _accountWorkComplete({
    Map<String, dynamic>? reviewedUnavailable,
    void Function(int)? onPause,
  }) async {
    _current();
    final pause = await _meta(_pauseKey), deadline = pause?['retryNotBefore'];
    if (deadline is int &&
        deadline > DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      await _pause(
        deadline - DateTime.now().millisecondsSinceEpoch ~/ 1000,
        onPause,
      );
    }
    await withCollaborationRateLimitPause(
      () => _complete(reviewedUnavailable: reviewedUnavailable),
      pause: (seconds) => _pause(seconds, onPause),
    );
  }

  /// Read one scope under the existing bounded authority lease. This phase
  /// performs no inspection, observation, signing, receipt or rotation work.
  Future<({VerifiedScopeHead head, bool stale})> readScopeMembers(
    SessionCryptoAccess access,
    String scopeId,
  ) async {
    _current();
    if (!identical(access.account, account)) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
    return access.withVerifiedOperation(() async {
      _current();
      final head = await access.currentHead(scopeId, online: true);
      var stale = false;
      for (final member in head.members) {
        final current = await access.currentMemberDirectory(
          head.scopeId,
          head.headHash,
          member['accountId'],
        );
        stale |= current.deviceSnapshotHash != member['deviceSnapshotHash'];
      }
      _current();
      return (head: head, stale: stale);
    });
  }

  String get _activeJobKey =>
      'protectionReady:${account.store.partition}:${account.deviceId}:active';
  Future<Map<String, dynamic>?> _activeJob() async {
    final active = await _meta(_activeJobKey);
    return active == null
        ? null
        : _meta('$_activeJobKey:${active['requestId']}');
  }

  String get _scopeActionKey =>
      'protectionReady:${account.store.partition}:${account.deviceId}:scopeAction';
  Future<Map<String, dynamic>?> pendingScopeAction() => _meta(_scopeActionKey);
  Future<bool> _rotateRecoveredOwners(
    List<Map<String, dynamic>> scopes,
    SessionCryptoAccess access,
  ) async {
    var changed = false;
    final manager = ScopeCryptoManager(access);
    for (final scope in scopes) {
      _current();
      if (scope['headHash'] == null ||
          !['active', 'committed'].contains(scope['cryptoState'])) {
        continue;
      }
      final observed = await readScopeMembers(access, scope['id']);
      final head = observed.head;
      if (!observed.stale) continue;
      final own = head.member(account.directory.accountId);
      final canManage = own['manageKeys'] == true;
      if (own['role'] == 'owner' && canManage) {
        try {
          final pending = await manager.pendingRotationReviews(head.scopeId);
          final review =
              pending
                  .where((r) => r.sourceHeadHash == head.headHash)
                  .firstOrNull ??
              await manager.reviewRotation(head.scopeId);
          _current();
          // Only already authenticated checkpoint history is automatic.
          // Unobserved tails still require the existing explicit review UI.
          await manager.confirmRotation(
            review,
            acceptedCandidateHistory: false,
          );
          _current();
          await account.store.database.execute(
            'DELETE FROM local_meta WHERE name=?',
            [_scopeActionKey],
          );
          changed = true;
          continue;
        } on CryptoAuthorityPending catch (error) {
          _current();
          await _save(_scopeActionKey, {
            'scopeId': head.scopeId,
            'canManage': true,
            'reason': error.reason,
          });
          throw const CryptoAuthorityPending(
            'protection_scope_action_required',
          );
        }
      }
      await _save(_scopeActionKey, {
        'scopeId': head.scopeId,
        'canManage': canManage,
        'reason': 'scope_rotation_required',
      });
      throw const CryptoAuthorityPending('protection_scope_action_required');
    }
    return changed;
  }

  Future<void> _complete({Map<String, dynamic>? reviewedUnavailable}) async {
    _current();
    final pending = await account.store.pending();
    _current();
    if (pending.isNotEmpty) {
      if (pending.any(
        (proof) =>
            !const {
              'crypto2.account.scopeObserve',
              'crypto2.account.protectionReady',
            }.contains(
              (CryptoJson.decode(cryptoBase64(proof['commandBase64']))
                  as Map)['operation'],
            ),
      )) {
        throw const CryptoAuthorityPending('directory_pending_request');
      }
      await account.directory.resume();
    }
    final own = await account.directory.requireFresh(),
        access = SessionCryptoAccess(account: account);
    var scopes = await catalog();
    if (await _rotateRecoveredOwners(scopes, access)) scopes = await catalog();
    final observed = await catalogHash(scopes);
    final prior = await _activeJob();
    if (prior != null &&
        prior['deviceSnapshotHash'] == own.deviceSnapshotHash) {
      var scanned = 0;
      await for (final entry in account.store.verifiedOperationEntries(
        own,
        'crypto2.account.protectionReady',
      )) {
        if (++scanned > 128) {
          throw const CryptoAuthorityPending(
            'protection_completion_history_pending',
          );
        }
        final proof = entry['authorization'] as Map,
            command =
                CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        if (command['requestId'] != prior['requestId']) continue;
        if (command['deviceId'] != account.deviceId ||
            command['payload']['scopeManifestHash'] !=
                prior['scopeManifestHash'] ||
            command['payload']['deviceSnapshotHash'] !=
                prior['deviceSnapshotHash']) {
          throw const FormatException('protection_completion_immutable');
        }
        await _save('$_activeJobKey:${prior['requestId']}', {
          ...prior,
          'stage': 'complete',
        });
        if (observed == prior['scopeManifestHash']) return;
        break;
      }
    }
    final requestId =
        reviewedUnavailable?['completionRequestId'] as String? ??
        (prior?['scopeManifestHash'] == observed &&
                prior?['deviceSnapshotHash'] == own.deviceSnapshotHash
            ? prior!['requestId'] as String
            : account.directory.reducer.crypto.randomId());
    final job = {
      'version': 1,
      'requestId': requestId,
      'scopeManifestHash': observed,
      'identityEpochId': own.identityEpochId,
      'deviceSnapshotHash': own.deviceSnapshotHash,
      'stage': 'preparing',
    };
    await _save('$_activeJobKey:$requestId', job);
    await _save(_activeJobKey, {'requestId': requestId});
    for (final scope in scopes) {
      _current();
      if (scope['headHash'] == null ||
          !['active', 'committed'].contains(scope['cryptoState'])) {
        throw const CryptoAuthorityPending('crypto_reconciliation_required');
      }
      if (scope['cryptoOrigin'] != true) {
        final coordinator = CryptoMigrationCoordinator(account: account);
        try {
          final state = await coordinator.inspect(scope['id']);
          if (state.phase != CryptoMigrationPhase.committed) {
            throw const CryptoAuthorityPending(
              'crypto_reconciliation_required',
            );
          }
        } finally {
          await coordinator.close();
        }
      }
      final observedScope = await readScopeMembers(access, scope['id']);
      final head = observedScope.head;
      if (head.headHash != scope['headHash'] ||
          head.epoch != scope['epoch'] ||
          head.accessRevision != scope['accessRevision']) {
        throw const FormatException('protection_catalog_head');
      }
      if (observedScope.stale) {
        throw const CryptoAuthorityPending('scope_rotation_required');
      }
      await CryptoScopeObservations(account).observe(access, head.scopeId);
    }
    final missing = await _missingScopes(scopes);
    Map<String, dynamic>? review;
    if (missing.isNotEmpty) {
      review = _reviewBody(own, observed, missing, requestId);
      if (reviewedUnavailable == null ||
          base64Encode(CryptoJson.encode(reviewedUnavailable)) !=
              base64Encode(CryptoJson.encode(review))) {
        throw const CryptoAuthorityPending('protection_known_scope_missing');
      }
    } else if (reviewedUnavailable != null) {
      throw const CryptoAuthorityPending('protection_catalog_changed');
    }
    final server = await account.directory.call(
      'crypto2.account.protectionCatalog',
    );
    if (server['scopeManifestHash'] != observed ||
        server['count'] != scopes.length ||
        server['deviceSnapshotHash'] != own.deviceSnapshotHash) {
      throw const CryptoAuthorityPending('protection_catalog_changed');
    }
    final lease = await account.signingKey();
    try {
      _current();
      final reviewProof = review == null
          ? null
          : account.directory.reducer.crypto.signDomain(
              review,
              lease.key,
              'JivieE2EE/unavailableScopes/v2\n',
            );
      await account.directory.stageAndSend(
        (previous) async {
          _current();
          if (previous == null ||
              previous.deviceSnapshotHash != own.deviceSnapshotHash) {
            throw const CryptoAuthorityPending('protection_catalog_changed');
          }
          return account.directory.reducer.prepare(
            previous: previous,
            requestId: requestId,
            serverId: previous.serverId,
            accountId: previous.accountId,
            deviceId: account.deviceId,
            identityEpochId: previous.identityEpochId,
            operation: 'crypto2.account.protectionReady',
            signer: 'device',
            payload: {
              'deviceSnapshotHash': previous.deviceSnapshotHash,
              'scopeManifestHash': observed,
            },
            pinnedRootFingerprint: account.directory.reducer.crypto.fingerprint(
              cryptoBase64(
                previous.snapshot['rootSigningKeyBase64'],
                length: 32,
              ),
              cryptoBase64(
                previous.snapshot['rootEncryptionKeyBase64'],
                length: 32,
              ),
            ),
            signingKey: lease.key,
          );
        },
        beforeSendTransaction: () async {
          if (reviewProof != null) {
            await account.store.database.execute(
              'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
              [
                account.store.partition,
                own.accountId,
                requestId,
                'confirmed',
                CryptoJson.encode({
                  'operation': 'local.unavailableScopesReview',
                }),
                CryptoJson.encode(reviewProof),
              ],
            );
          }
        },
      );
    } finally {
      lease.release();
    }
    _current();
    await _save('$_activeJobKey:$requestId', {...job, 'stage': 'complete'});
  }
}
