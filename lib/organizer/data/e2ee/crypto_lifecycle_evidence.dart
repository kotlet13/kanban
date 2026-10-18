import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_anchor_lock.dart';
import 'crypto_scoped_authority.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';
import 'session_crypto_access.dart';

/// Authenticated archive state. Scheduler/SQL flags never replace these proofs.
/// Unknown historical timing remains pending after an unanchored cold recovery.
class CryptoLifecycleEvidence {
  CryptoLifecycleEvidence(this.access);
  final SessionCryptoAccess access;
  static const proofDomain = 'JivieScopeLifecycle/v2\n';
  static const inheritedDomain = 'JivieE2EE/inheritedLifecycle/v2\n';
  static const zero =
      '0000000000000000000000000000000000000000000000000000000000000000';
  String get partition => access.account.store.partition;
  Future<String> proofHash(Map proof) =>
      cryptoSha256([...utf8.encode(proofDomain), ...CryptoJson.encode(proof)]);
  Future<String> parentToken(String childScopeId, String parentScopeId) =>
      cryptoSha256([
        ...utf8.encode('JivieParentLifecycleScope/v2\n'),
        ...CryptoJson.encode({
          'version': 2,
          'serverId': access.account.directory.session.profile.serverId,
          'scopeId': childScopeId,
          'parentScopeId': parentScopeId,
        }),
      ]);
  Map<String, dynamic> _body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  void _fields(Map value, Set<String> fields) {
    if (value.length != fields.length ||
        value.keys.any((k) => !fields.contains(k))) {
      throw const FormatException('lifecycle_fields');
    }
  }

  static final _queues = <String, Future<void>>{};
  static int _runSequence = 0;
  void _current() {
    if (!access.account.directory.isCurrent()) {
      throw const FormatException('lifecycle_stale_identity');
    }
  }

  Future<Map<String, dynamic>> current(String scopeId) => _serialized(scopeId);

  /// The recovery review can inspect a lifecycle against its exact authenticated
  /// candidate before ordinary history is accepted. No floor/cache is promoted.
  Future<Map<String, dynamic>> forRecoveryReview(
    String scopeId, {
    required String sourceHeadHash,
    required bool financeOnly,
  }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceHeadHash)) {
      throw const FormatException('scope_review_source');
    }
    return _serialized(
      scopeId,
      recoverySourceHeadHash: sourceHeadHash,
      financeOnly: financeOnly,
    );
  }

  Future<Map<String, dynamic>> _serialized(
    String scopeId, {
    String? recoverySourceHeadHash,
    bool financeOnly = false,
  }) async {
    final key = '$partition:$scopeId';
    final work = (_queues[key] ?? Future<void>.value()).then(
      (_) => _currentState(
        scopeId,
        recoverySourceHeadHash: recoverySourceHeadHash,
        financeOnly: financeOnly,
      ),
    );
    final marker = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _queues[key] = marker;
    try {
      return await work;
    } finally {
      if (identical(_queues[key], marker)) _queues.remove(key);
    }
  }

  bool _mayReview(Map member, {required bool financeOnly}) => financeOnly
      ? const {'read', 'write'}.contains(member['financeRole'])
      : member['manageKeys'] == true;

  Future<Map<String, dynamic>> _currentState(
    String scopeId, {
    String? recoverySourceHeadHash,
    bool financeOnly = false,
  }) async {
    _current();
    final ownBefore = recoverySourceHeadHash == null
        ? null
        : await access.account.directory.requireFresh();
    final scopeKey = 'scope2:$partition:$scopeId';
    final scopePin = recoverySourceHeadHash == null
        ? null
        : await access.account.store.secure.read(scopeKey);
    final currentHead = recoverySourceHeadHash == null
        ? await access.currentHead(scopeId, online: true)
        : await access.recoveryCandidateHead(scopeId);
    if (recoverySourceHeadHash != null &&
        (currentHead.headHash != recoverySourceHeadHash ||
            !_mayReview(
              currentHead.member(ownBefore!.accountId),
              financeOnly: financeOnly,
            ))) {
      throw const CryptoAuthorityPending('scope_review_changed');
    }
    final initial = await access.account.directory.call(
      'crypto2.scope.lifecycle.baseline',
      {'scopeId': scopeId},
    );
    if (await access.verifyInitialLifecycle(
          scopeId,
          initial,
          scopeHeadHash: currentHead.headHash,
        ) !=
        currentHead.body['initialLifecycleHash']) {
      throw const FormatException('lifecycle_initial_substitution');
    }
    final baseline = initial['initialLifecycleBaseline'] as Map;
    var state = <String, dynamic>{
      'scopeId': scopeId,
      'revision': 0,
      'headHash': zero,
      'ownArchived': baseline['ownArchived'],
      'inheritedArchived': baseline['inheritedArchived'],
    };
    final secureKey = 'lifecycle2:$partition:$scopeId';
    // A later authenticated scope head commits an exact lifecycle prefix. First
    // locate those commitments in bounded pages, then verify the entire chain
    // chronologically. A revoked signature alone never establishes old timing.
    final requiredHashes = <String>{...access.observedLifecycleHashes(scopeId)};
    final scopeFloor = scopePin == null
        ? null
        : CryptoJson.decode(Uint8List.fromList(utf8.encode(scopePin))) as Map;
    if (scopeFloor != null && scopeFloor['epoch'] > currentHead.epoch) {
      throw const FormatException('scope_known_rollback');
    }
    var scopeFloorIncluded = scopeFloor == null;
    final recoveryHeads = recoverySourceHeadHash == null
        ? null
        : <String, VerifiedScopeHead>{};
    var ancestor = currentHead;
    while (true) {
      recoveryHeads?[ancestor.headHash] = ancestor;
      if (scopeFloor != null && ancestor.epoch == scopeFloor['epoch']) {
        if (ancestor.headHash != scopeFloor['headHash']) {
          throw const FormatException('scope_known_fork');
        }
        scopeFloorIncluded = true;
      }
      final hash = ancestor.body['previousLifecycleHash'];
      if (hash is String && hash != zero) requiredHashes.add(hash);
      final previous = ancestor.body['previousHeadHash'];
      if (previous == zero) break;
      final previousHead = recoveryHeads == null
          ? await access.headAt(scopeId, previous)
          : access.verifiedCandidateAncestor(previous);
      if (recoveryHeads != null &&
          (previousHead.scopeId != scopeId ||
              previousHead.headHash != previous ||
              previousHead.epoch >= ancestor.epoch)) {
        throw const FormatException('lifecycle_review_head');
      }
      ancestor = previousHead;
    }
    if (!scopeFloorIncluded) {
      throw const FormatException('scope_known_fork');
    }
    final anchorPositions = <String, int>{};
    var scanAfter = 0;
    while (true) {
      final page = await _page(scopeId, scanAfter);
      for (final raw in page['states'] as List) {
        final wire = raw as Map;
        if (wire['revision'] != scanAfter + 1 ||
            wire['authorization'] is! Map) {
          throw const FormatException('lifecycle_sequence');
        }
        scanAfter++;
        final hash = await proofHash(wire['authorization'] as Map);
        if (requiredHashes.contains(hash)) anchorPositions[hash] = scanAfter;
      }
      if (!_hasMore(page, scanAfter)) break;
    }
    if (anchorPositions.length != requiredHashes.length) {
      throw const CryptoAuthorityPending('lifecycle_closed_prefix_missing');
    }
    final anchoredRevision = anchorPositions.values.fold<int>(
      0,
      (maximum, value) => value > maximum ? value : maximum,
    );
    final observedAnchors = <String>{};
    final stagePrefix =
        'lifecycleCandidate:${DateTime.now().microsecondsSinceEpoch}:${_runSequence++}:';
    var after = 0;
    try {
      while (true) {
        final page = await _page(scopeId, after);
        for (final raw in page['states'] as List) {
          final next = Map<String, dynamic>.from(raw as Map);
          state = await _next(
            currentHead,
            state,
            next,
            anchored: next['revision'] <= anchoredRevision,
            stagePrefix: stagePrefix,
            recoveryHeads: recoveryHeads,
          );
          after = state['revision'];
          final position = anchorPositions[state['headHash']];
          if (position != null) {
            if (position != after) {
              throw const FormatException('lifecycle_anchor_position');
            }
            observedAnchors.add(state['headHash']);
          }
        }
        if (!_hasMore(page, after)) break;
      }
      if (observedAnchors.length != requiredHashes.length) {
        throw const CryptoAuthorityPending('lifecycle_closed_prefix_missing');
      }
      // No SQL transaction may wait on the shared secure-anchor mutex. Inspect
      // the candidate outside it, then compare/retry the exact secure value.
      while (true) {
        _current();
        final saved = await access.account.store.secure.read(secureKey);
        final floor = saved == null
            ? null
            : CryptoJson.decode(Uint8List.fromList(utf8.encode(saved))) as Map;
        if (floor != null &&
            (floor['revision'] > after ||
                floor['revision'] == after &&
                    floor['headHash'] != state['headHash'])) {
          throw const FormatException('lifecycle_known_rollback');
        }
        if (floor != null && floor['revision'] > 0) {
          final rows = await access.account.store.database.rows(
            'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state=?',
            [
              partition,
              scopeId,
              '$stagePrefix${floor['revision'].toString().padLeft(20, '0')}',
              'lifecycleCandidate',
            ],
          );
          if (rows.length != 1 ||
              (CryptoJson.decode(
                        Uint8List.fromList(
                          (rows.single['payload'] as List).cast<int>(),
                        ),
                      )
                      as Map)['headHash'] !=
                  floor['headHash']) {
            throw const FormatException('lifecycle_known_fork');
          }
        }
        if (recoverySourceHeadHash != null) {
          // Recheck the exact candidate, own identity and existing floors after
          // the complete signed lifecycle scan. Candidate verification enforces
          // its included own observation/invitation/publication ancestry; it
          // never installs an ordinary scope anchor or current WRITE authority.
          final latest = await access.recoveryCandidateHead(scopeId);
          final ownAfter = await access.account.directory.requireFresh();
          _current();
          if (latest.headHash != recoverySourceHeadHash ||
              !_mayReview(
                latest.member(ownAfter.accountId),
                financeOnly: financeOnly,
              ) ||
              ownAfter.headHash != ownBefore!.headHash ||
              await access.account.store.secure.read(scopeKey) != scopePin ||
              await access.account.store.secure.read(secureKey) != saved) {
            throw const CryptoAuthorityPending('scope_review_changed');
          }
          return state;
        }
        final updated = await withCryptoAnchorLock(partition, () async {
          _current();
          if (await access.account.store.secure.read(secureKey) != saved) {
            return false;
          }
          await access.account.store.secure.write(
            secureKey,
            utf8.decode(
              CryptoJson.encode({
                'revision': after,
                'headHash': state['headHash'],
              }),
            ),
          );
          _current();
          return true;
        });
        if (updated) break;
      }
      // A crash after the secure write is safe: it requires the exact verified
      // prefix on retry, even if these derived cache rows were not committed.
      await _promote(scopeId, stagePrefix);
      _current();
      return state;
    } finally {
      await access.account.store.database.execute(
        'DELETE FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state=? AND intent_id LIKE ?',
        [partition, scopeId, 'lifecycleCandidate', '$stagePrefix%'],
      );
    }
  }

  Future<Map<String, dynamic>> _page(String scopeId, int after) async {
    _current();
    final page = await access.account.directory.call(
      'crypto2.scope.lifecycle.list',
      {'scopeId': scopeId, 'afterRevision': after, 'limit': 20},
    );
    if (page['states'] is! List || (page['states'] as List).length > 20) {
      throw const FormatException('lifecycle_page');
    }
    return page;
  }

  bool _hasMore(Map page, int after) {
    if (page['hasMore'] == false) {
      if (page['currentRevision'] != after) {
        throw const CryptoAuthorityPending('lifecycle_incomplete');
      }
      return false;
    }
    if (page['hasMore'] != true ||
        (page['states'] as List).isEmpty ||
        page['nextAfterRevision'] != after) {
      throw const FormatException('lifecycle_cursor');
    }
    return true;
  }

  Future<void> _promote(String scopeId, String prefix) async {
    await access.account.store.database.transaction(() async {
      var cursor = '';
      while (true) {
        final rows = await access.account.store.database.rows(
          'SELECT intent_id,payload,authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state=? AND intent_id LIKE ? AND intent_id>? ORDER BY intent_id LIMIT 20',
          [partition, scopeId, 'lifecycleCandidate', '$prefix%', cursor],
        );
        for (final row in rows) {
          _current();
          final state =
              CryptoJson.decode(
                    Uint8List.fromList((row['payload'] as List).cast<int>()),
                  )
                  as Map;
          await access.account.store.database.execute(
            "INSERT INTO crypto_membership_intents(partition,scope_id,intent_id,state,payload,authorization) VALUES(?,?,?,'lifecycleVerified',?,?) ON CONFLICT(partition,scope_id,intent_id) DO NOTHING",
            [
              partition,
              scopeId,
              'lifecycle:${state['revision']}',
              row['payload'],
              row['authorization'],
            ],
          );
          cursor = row['intent_id'] as String;
        }
        if (rows.length < 20) break;
      }
    });
  }

  Future<VerifiedScopeHead> _lifecycleHead(
    String scopeId,
    String hash,
    Map<String, VerifiedScopeHead>? recoveryHeads,
  ) async {
    if (recoveryHeads == null) return access.headAt(scopeId, hash);
    final head = recoveryHeads[hash];
    if (head == null || head.scopeId != scopeId || head.headHash != hash) {
      throw const FormatException('lifecycle_review_head');
    }
    return head;
  }

  Future<Map<String, dynamic>> _next(
    VerifiedScopeHead currentHead,
    Map<String, dynamic> prior,
    Map<String, dynamic> wire, {
    required bool anchored,
    required String stagePrefix,
    Map<String, VerifiedScopeHead>? recoveryHeads,
  }) async {
    if (wire['scopeId'] != prior['scopeId'] ||
        wire['revision'] != prior['revision'] + 1 ||
        wire['authorization'] is! Map) {
      throw const FormatException('lifecycle_sequence');
    }
    final proof = Map<String, dynamic>.from(wire['authorization'] as Map),
        body = _body(proof);
    final hash = await proofHash(proof);
    if (hash != wire['headHash']) throw const FormatException('lifecycle_hash');
    final cached = await access.account.store.database.rows(
      "SELECT authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='lifecycleVerified'",
      [partition, prior['scopeId'], 'lifecycle:${wire['revision']}'],
    );
    final known =
        cached.length == 1 &&
        base64Encode(CryptoJson.encode(proof)) ==
            base64Encode((cached.single['authorization'] as List).cast<int>());
    late bool own, inherited;
    if (body['operation'] == 'crypto2.scope.archive') {
      _fields(body['payload'] as Map, {
        'scopeId',
        'parentActionId',
        'intentProofHash',
        'childCount',
        'childrenHash',
      });
      final intentProof = Map<String, dynamic>.from(
            wire['intentAuthorization'] as Map,
          ),
          intentCommand = _body(intentProof),
          intent = intentCommand['payload'] as Map;
      _fields(intent, {
        'scopeId',
        'parentActionId',
        'expectedLifecycleRevision',
        'previousLifecycleHash',
        'membershipHeadHash',
        'expectedAccessRevision',
        'authorDirectoryHeadHash',
        'archived',
      });
      final finalPayload = body['payload'] as Map;
      if (finalPayload['scopeId'] != prior['scopeId'] ||
          finalPayload['parentActionId'] != intent['parentActionId'] ||
          finalPayload['intentProofHash'] != await proofHash(intentProof) ||
          intentCommand['operation'] != 'crypto2.scope.lifecycle.prepare' ||
          body['accountId'] != intentCommand['accountId'] ||
          body['deviceId'] != intentCommand['deviceId']) {
        throw const FormatException('lifecycle_intent_binding');
      }
      _previous(intent, prior);
      final head = await _lifecycleHead(
        prior['scopeId'],
        intent['membershipHeadHash'],
        recoveryHeads,
      );
      if (!head.member(body['accountId'])['manageKeys'] ||
          intent['expectedAccessRevision'] != head.accessRevision) {
        throw const FormatException('lifecycle_manager');
      }
      await _signature(
        proof,
        body,
        head,
        intent['authorDirectoryHeadHash'],
        known || anchored,
      );
      await _signature(
        intentProof,
        intentCommand,
        head,
        intent['authorDirectoryHeadHash'],
        known || anchored,
      );
      if (intent['archived'] is! bool) {
        throw const FormatException('lifecycle_state');
      }
      own = intent['archived'];
      inherited = prior['inheritedArchived'];
    } else if (body['operation'] == 'crypto2.scope.lifecycle.attestBaseline') {
      final p = body['payload'] as Map;
      _fields(p, {
        'scopeId',
        'membershipHeadHash',
        'expectedAccessRevision',
        'authorDirectoryHeadHash',
        'migrationId',
        'inventoryHash',
        'initialLifecycleHash',
        'ownArchived',
        'inheritedArchived',
      });
      if (prior['revision'] != 0 ||
          p['scopeId'] != prior['scopeId'] ||
          p['initialLifecycleHash'] !=
              currentHead.body['initialLifecycleHash'] ||
          p['ownArchived'] != prior['ownArchived'] ||
          p['inheritedArchived'] != prior['inheritedArchived']) {
        throw const FormatException('lifecycle_baseline');
      }
      final head = await _lifecycleHead(
        prior['scopeId'],
        p['membershipHeadHash'],
        recoveryHeads,
      );
      if (!head.member(body['accountId'])['manageKeys'] ||
          head.accessRevision != p['expectedAccessRevision']) {
        throw const FormatException('lifecycle_manager');
      }
      await _signature(
        proof,
        body,
        head,
        p['authorDirectoryHeadHash'],
        known || anchored,
      );
      own = p['ownArchived'];
      inherited = p['inheritedArchived'];
    } else {
      _fields(body, {
        'version',
        'serverId',
        'accountId',
        'deviceId',
        'authorDirectoryHeadHash',
        'parentActionId',
        'parentScopeToken',
        'parentMembershipHeadHash',
        'parentExpectedLifecycleRevision',
        'parentPreviousLifecycleHash',
        'parentIntentProofHash',
        'parentDeviceSnapshotHash',
        'archived',
        'scopeId',
        'membershipHeadHash',
        'expectedLifecycleRevision',
        'previousLifecycleHash',
        'delegationProofHash',
      });
      _previous(body, prior);
      final head = await _lifecycleHead(
        prior['scopeId'],
        body['membershipHeadHash'],
        recoveryHeads,
      );
      if (body['delegationProofHash'] == null) {
        if (!head.member(body['accountId'])['manageKeys']) {
          throw const FormatException('lifecycle_manager');
        }
      } else {
        final grantProof = Map<String, dynamic>.from(
              wire['delegationAuthorization'] as Map,
            ),
            grantCommand = _body(grantProof),
            grant = grantCommand['payload'] as Map;
        _fields(grant, {
          'scopeId',
          'delegationId',
          'membershipHeadHash',
          'expectedAccessRevision',
          'authorDirectoryHeadHash',
          'parentScopeToken',
          'parentAccountId',
          'parentDirectoryHeadHash',
          'parentRootSigningKeyBase64',
          'parentRootEncryptionKeyBase64',
          'parentIdentityEpochId',
          'parentDeviceSnapshotHash',
          'effect',
        });
        if (grantCommand['operation'] != 'crypto2.scope.lifecycle.delegate' ||
            grant['scopeId'] != prior['scopeId'] ||
            grant['membershipHeadHash'] != head.headHash ||
            grant['parentScopeToken'] != body['parentScopeToken'] ||
            grant['parentAccountId'] != body['accountId'] ||
            grant['effect'] != 'inheritedArchived' ||
            await proofHash(grantProof) != body['delegationProofHash'] ||
            !head.member(grantCommand['accountId'])['manageKeys']) {
          throw const FormatException('lifecycle_delegation');
        }
        await _signature(
          grantProof,
          grantCommand,
          head,
          grant['authorDirectoryHeadHash'],
          known || anchored,
        );
        final parent = await access.directoryAt(
          scopeId: head.scopeId,
          scopeHeadHash: head.headHash,
          accountId: body['accountId'],
          directoryHeadHash: body['authorDirectoryHeadHash'],
          allowUnverifiedContact: true,
        );
        if (parent.snapshot['rootSigningKeyBase64'] !=
                grant['parentRootSigningKeyBase64'] ||
            parent.snapshot['rootEncryptionKeyBase64'] !=
                grant['parentRootEncryptionKeyBase64'] ||
            parent.identityEpochId != grant['parentIdentityEpochId'] ||
            parent.deviceSnapshotHash != grant['parentDeviceSnapshotHash']) {
          throw const FormatException('lifecycle_delegated_identity');
        }
      }
      await _signature(
        proof,
        body,
        head,
        body['authorDirectoryHeadHash'],
        known || anchored,
        domain: inheritedDomain,
        scopedDelegate: body['delegationProofHash'] != null,
      );
      if (body['archived'] is! bool) {
        throw const FormatException('lifecycle_state');
      }
      own = prior['ownArchived'];
      inherited = body['archived'];
    }
    if (wire['ownArchived'] != own || wire['inheritedArchived'] != inherited) {
      throw const FormatException('lifecycle_state_substitution');
    }
    final next = <String, dynamic>{
      'scopeId': prior['scopeId'],
      'revision': wire['revision'],
      'headHash': hash,
      'ownArchived': own,
      'inheritedArchived': inherited,
    };
    if (cached.isNotEmpty && !known) {
      throw const FormatException('lifecycle_known_fork');
    }
    _current();
    await access.account.store.database.execute(
      "INSERT INTO crypto_membership_intents(partition,scope_id,intent_id,state,payload,authorization) VALUES(?,?,?,'lifecycleCandidate',?,?) ON CONFLICT(partition,scope_id,intent_id) DO NOTHING",
      [
        partition,
        prior['scopeId'],
        '$stagePrefix${wire['revision'].toString().padLeft(20, '0')}',
        CryptoJson.encode(next),
        CryptoJson.encode(proof),
      ],
    );
    return next;
  }

  void _previous(Map p, Map prior) {
    if (p['scopeId'] != prior['scopeId'] ||
        p['expectedLifecycleRevision'] != prior['revision'] ||
        p['previousLifecycleHash'] != prior['headHash']) {
      throw const FormatException('lifecycle_predecessor');
    }
  }

  Future<void> _signature(
    Map<String, dynamic> proof,
    Map command,
    VerifiedScopeHead head,
    String reference,
    bool known, {
    String domain = cryptoDirectoryDomain,
    bool scopedDelegate = false,
  }) async {
    if (domain == cryptoDirectoryDomain) {
      _fields(command, {
        'version',
        'operation',
        'requestId',
        'serverId',
        'accountId',
        'deviceId',
        'signer',
        'payload',
      });
    }
    if (command['version'] != 2 ||
        command['serverId'] !=
            access.account.directory.session.profile.serverId ||
        domain == cryptoDirectoryDomain && command['signer'] != 'device') {
      throw const FormatException('lifecycle_author');
    }
    final author = await access.directoryAt(
      scopeId: head.scopeId,
      scopeHeadHash: head.headHash,
      accountId: command['accountId'],
      directoryHeadHash: reference,
      online: true,
      allowUnverifiedContact: true,
    );
    if (!scopedDelegate) {
      final member = head.member(command['accountId']);
      if (member['rootSigningKeyBase64'] !=
              author.snapshot['rootSigningKeyBase64'] ||
          member['rootEncryptionKeyBase64'] !=
              author.snapshot['rootEncryptionKeyBase64'] ||
          member['deviceSnapshotHash'] != author.deviceSnapshotHash) {
        throw const FormatException('lifecycle_author_snapshot');
      }
    }
    if (domain == inheritedDomain &&
        command['parentDeviceSnapshotHash'] != author.deviceSnapshotHash) {
      throw const FormatException('lifecycle_delegated_identity');
    }
    final actor = author.activeDevice(command['deviceId']);
    access.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(actor['signingKeyBase64'], length: 32),
      domain,
    );
    if (!known) {
      final pin = await access.account.store.anchor(command['accountId']);
      if (scopedDelegate) {
        await CryptoScopedAuthority(access).current(
          scopeId: head.scopeId,
          scopeHeadHash: head.headHash,
          accountId: command['accountId'],
          signingPublicKey: author.snapshot['rootSigningKeyBase64'],
          encryptionPublicKey: author.snapshot['rootEncryptionKeyBase64'],
          identityEpochId: author.identityEpochId,
          deviceSnapshotHash: author.deviceSnapshotHash,
        );
      } else if (pin == null ||
          pin['deviceSnapshotHash'] != author.deviceSnapshotHash) {
        throw const CryptoAuthorityPending('lifecycle_history_review_required');
      }
    }
  }
}
