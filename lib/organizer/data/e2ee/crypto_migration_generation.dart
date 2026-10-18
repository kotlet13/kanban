import 'dart:typed_data';
import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_migration_own_attestation.dart';
import 'crypto_migration_commitments_v3.dart';
import 'crypto_migration_business_parity_v3.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_manager.dart';

/// Explicit review of an interrupted generation. This is not a recovery-file
/// import or silent acceptance of the server's candidate bytes.
class CryptoMigrationGeneration {
  CryptoMigrationGeneration(this.runtime);
  final CryptoBusinessSession runtime;
  static const approvalDomain = 'JivieMigrationGenerationApproval/v3\n';
  static Map<String, dynamic> map(Object? v) {
    if (v is! Map) {
      throw const FormatException('crypto_migration_generation_shape');
    }
    return Map<String, dynamic>.from(v);
  }

  Future<Map<String, dynamic>> send(
    String action,
    String op,
    Map<String, dynamic> payload,
  ) async {
    final id = await runtime.queue.enqueueCommand(
      actionKey: action,
      operation: op,
      payload: payload,
    );
    await runtime.queue.resumeUnresolved(requestIds: {id});
    return runtime.queue.commandResult(id);
  }

  Future<Map<String, dynamic>> prepare({
    required String migrationId,
    required String generationId,
    required bool afterPublication,
  }) {
    if (!isCryptoCanonicalUuid(migrationId) ||
        !isCryptoCanonicalUuid(generationId)) {
      throw const FormatException('crypto_migration_generation');
    }
    return send(
      'generationPrepare:$generationId',
      'crypto2.migration.generation.prepare',
      {
        'migrationId': migrationId,
        'generationId': generationId,
        'mode': afterPublication ? 'continue' : 'supersede',
      },
    );
  }

  Future<Map<String, dynamic>> status(String generationId) =>
      runtime.account.directory.call('crypto2.migration.generation.status', {
        'generationId': generationId,
      });
  Future<Map<String, dynamic>> forMigration(String migrationId) =>
      runtime.account.directory.call('crypto2.migration.generation.status', {
        'migrationId': migrationId,
      });
  Future<void> publishDraft({
    required String generationId,
    required String migrationId,
    required String captureId,
    required String scopeId,
  }) async {
    final state = await status(generationId);
    if (state['state'] != 'superseded' ||
        state['context']?['newMigrationId'] != migrationId) {
      throw const CryptoAuthorityPending(
        'crypto_migration_generation_not_superseded',
      );
    }
    await ScopeCryptoManager(runtime.access).publishMigrationGenerationDraft(
      generationId: generationId,
      migrationId: migrationId,
      captureId: captureId,
      scopeId: scopeId,
    );
  }

  Future<Map<String, dynamic>> draft({
    required String generationId,
    required String scopeId,
    required int accessRevision,
    required List<Map<String, dynamic>> members,
  }) async {
    final draft = await ScopeCryptoManager(runtime.access)
        .prepareMigrationGenerationDraft(
          generationId: generationId,
          scopeId: scopeId,
          accessRevision: accessRevision,
          members: members,
        );
    return send(
      'generationDraft:$generationId:$scopeId',
      'crypto2.migration.generation.draft',
      {'generationId': generationId, 'authorization': draft['authorization']},
    );
  }

  Future<Map<String, dynamic>> seal(String generationId) => send(
    'generationSeal:$generationId',
    'crypto2.migration.generation.seal',
    {'generationId': generationId},
  );

  /// Signature-checked preparatory summaries only. These never install a
  /// head/key/floor or turn the server's catalog into ordinary authority.
  Future<List<Map<String, dynamic>>> reviewedTargets(
    Map<String, dynamic> state,
  ) async {
    final own = await runtime.account.directory.requireFresh(),
        context = map(state['context']);
    final scopes = (context['scopes'] as List).map(map).toList();
    final seen = <String>{}, summaries = <Map<String, dynamic>>[];
    for (final raw in state['targets'] as List) {
      final target = map(raw), sid = target['scopeId'];
      if (!isCryptoCanonicalUuid(sid) || !seen.add(sid)) {
        throw const FormatException('crypto_migration_generation_targets');
      }
      final token = await CryptoMigrationCommitmentsV3.scopeToken(
        serverId: own.serverId,
        migrationId: context['migrationId'],
        scopeId: sid,
        domain: 'content',
      );
      final expected = scopes.singleWhere((s) => s['scopeToken'] == token);
      if (target['scopeToken'] != token ||
          target['accessRevision'] != expected['accessRevision'] ||
          target['headHash'] != expected['headHash']) {
        throw const FormatException(
          'crypto_migration_generation_target_changed',
        );
      }
      final oldHead = expected['headHash'];
      final wire = await runtime.account.directory.call(
        oldHead == null
            ? 'crypto2.scope.lifecycle.baseline'
            : 'crypto2.scope.headGet',
        {'scopeId': sid, if (oldHead != null) 'headHash': oldHead},
      );
      final proof = context['mode'] == 'supersede'
          ? target['candidateAuthorization']
          : wire['authorization'];
      if (proof == null) {
        throw const CryptoAuthorityPending(
          'crypto_migration_generation_drafts_pending',
        );
      }
      final authorization = map(proof),
          command = map(
            CryptoJson.decode(cryptoBase64(authorization['commandBase64'])),
          ),
          body = map(command['payload']);
      final author = await runtime.access.directoryAt(
        scopeId: sid,
        scopeHeadHash: oldHead ?? cryptoZeroHash,
        accountId: command['accountId'],
        directoryHeadHash: body['authorDirectoryHeadHash'],
        online: true,
        allowUnverifiedContact: true,
      );
      if (author.accountId != own.accountId) {
        await runtime.access.identities.requireVerified(
          author.accountId,
          runtime.access.identities.fingerprint(author),
        );
      }
      final proposal = await runtime.access.codec.verifyProposal(
        serverId: own.serverId,
        authorization: authorization,
        previous: null,
        authorDirectory: author,
        directoryAtHead: (id, hash) => runtime.access.directoryAt(
          scopeId: sid,
          scopeHeadHash: oldHead ?? cryptoZeroHash,
          accountId: id,
          directoryHeadHash: hash,
          online: true,
          allowUnverifiedContact: true,
        ),
        checkIdentity: (id, fp) async {
          if (id != own.accountId) {
            await runtime.access.identities.requireVerified(id, fp);
          }
        },
      );
      final expectedHash = context['mode'] == 'supersede'
          ? expected['candidateHeadHash']
          : expected['headHash'];
      if (proposal.scopeId != sid ||
          proposal.headHash != expectedHash ||
          proposal.epoch != 1 ||
          proposal.body['previousHeadHash'] != cryptoZeroHash ||
          proposal.accessRevision != expected['accessRevision'] ||
          context['mode'] == 'supersede' &&
              await cryptoSha256(CryptoJson.encode(authorization)) !=
                  expected['candidateProposalHash']) {
        throw const FormatException('crypto_migration_generation_proposal');
      }
      summaries.add({
        'scopeId': sid,
        'headHash': proposal.headHash,
        'members': proposal.members,
        'keyCommitments': proposal.body['keyCommitments'],
        'canDraft': target['canDraft'],
      });
    }
    if (summaries.isEmpty) {
      throw const CryptoAuthorityPending(
        'crypto_migration_generation_original_context_required',
      );
    }
    return List.unmodifiable(summaries);
  }

  Future<Map<String, dynamic>> resumeAcceptedCommit(String generationId) async {
    final saved = await _commitAttempt(generationId);
    if (saved != null) return _resumeCommit(saved);
    final target = await _commitPayload(generationId);
    return send(
      'generationCommit:$generationId',
      'crypto2.migration.commit3',
      map(target['payload']),
    );
  }

  Future<Map<String, dynamic>> _commitPayload(String generationId) async {
    final state = await status(generationId), context = map(state['context']);
    final contextHash = await cryptoSha256([
      ...utf8.encode('JivieMigrationGenerationContext/v3\n'),
      ...CryptoJson.encode(context),
    ]);
    if (context['generationId'] != generationId ||
        context['serverId'] !=
            runtime.account.directory.session.profile.serverId ||
        state['contextHash'] != contextHash ||
        context['mode'] != 'continue' ||
        state['state'] != 'review') {
      throw const FormatException('crypto_migration_generation_state');
    }
    final refs = <Map<String, dynamic>>[];
    String? after, inventory, component;
    do {
      final page = await runtime.account.directory
          .call('crypto2.migration.activation.refs', {
            'migrationId': context['migrationId'],
            'limit': 50,
            if (after != null) 'afterScopeToken': after,
          });
      if (page['version'] != 3 ||
          page['migrationId'] != context['migrationId'] ||
          page['scopeActivations'] is! List ||
          page['hasMore'] is! bool ||
          inventory != null && inventory != page['inventoryCommitment'] ||
          component != null && component != page['componentCommitment']) {
        throw const FormatException('crypto_migration_generation_publications');
      }
      inventory = page['inventoryCommitment'];
      component = page['componentCommitment'];
      for (final raw in page['scopeActivations'] as List) {
        final ref = map(raw);
        CryptoMigrationBusinessParityV3.exact(ref, {
          'scopeToken',
          'activationHash',
        });
        if (!CryptoMigrationBusinessParityV3.hash(ref['scopeToken']) ||
            !CryptoMigrationBusinessParityV3.hash(ref['activationHash']) ||
            after != null && after.compareTo(ref['scopeToken']) >= 0 ||
            refs.length >= 1000) {
          throw const FormatException(
            'crypto_migration_generation_publications',
          );
        }
        refs.add(ref);
        after = ref['scopeToken'];
      }
      if (page['hasMore'] == false) break;
      if (page['nextAfterScopeToken'] != after ||
          (page['scopeActivations'] as List).isEmpty) {
        throw const FormatException('crypto_migration_generation_publications');
      }
    } while (true);
    final tokens = (context['scopes'] as List)
        .map((v) => v['scopeToken'])
        .toList();
    if (refs.length != tokens.length ||
        !refs.every((r) => tokens.contains(r['scopeToken']))) {
      throw const CryptoAuthorityPending(
        'crypto_migration_generation_missing_signed_material',
      );
    }
    for (final old in context['published'] as List) {
      if (!refs.any(
        (r) =>
            r['scopeToken'] == old['scopeToken'] &&
            r['activationHash'] == old['activationHash'],
      )) {
        throw const FormatException(
          'crypto_migration_generation_publication_changed',
        );
      }
    }
    return {
      'contextHash': contextHash,
      'approvals': state['approvals'],
      'payload': {
        'version': 3,
        'migrationId': context['migrationId'],
        'componentId': context['componentId'],
        'componentCommitment': component,
        'inventoryCommitment': inventory,
        'scopeActivations': refs,
      },
    };
  }

  String _retryPointer(String generationId) =>
      'migration_generation_commit_attempt:${runtime.partition}:$generationId';

  bool _same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

  /// Follow immutable action keys from the original request. The pointer can
  /// lag an interrupted enqueue, but can never select a request outside this
  /// exact same-payload chain. It is a journal, not authority to finalize.
  Future<Map<String, dynamic>?> _commitAttempt(String generationId) async {
    if (!isCryptoCanonicalUuid(generationId)) {
      throw const FormatException('crypto_migration_generation');
    }
    var action = 'generationCommit:$generationId';
    final chain = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? root, latest;
    while (true) {
      final rows = await runtime.database.rows(
        'SELECT o.*,k.payload_hash FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
        [runtime.partition, action],
      );
      if (rows.isEmpty) break;
      if (rows.length != 1 || chain.length >= 1000) {
        throw const FormatException('crypto_migration_commit_attempt_chain');
      }
      final row = Map<String, dynamic>.from(rows.single);
      final signed = map(jsonDecode(row['signed_body'] as String));
      final body = map(
        CryptoJson.decode(cryptoBase64(signed['commandBase64'])),
      );
      final payload = map(body['payload']);
      final profile = runtime.account.directory.session.profile;
      if (row['operation'] != 'crypto2.migration.commit3' ||
          body['operation'] != row['operation'] ||
          body['version'] != 2 ||
          body['signer'] != 'device' ||
          body['serverId'] != profile.serverId ||
          body['accountId'] != profile.accountId ||
          body['requestId'] != row['request_id'] ||
          await cryptoSha256(cryptoBase64(signed['commandBase64'])) !=
              row['request_hash'] ||
          await cryptoSha256(
                CryptoJson.encode({
                  'operation': row['operation'],
                  'payload': payload,
                }),
              ) !=
              row['payload_hash'] ||
          root != null && !_same(root['_payload'], payload) ||
          chain.containsKey(row['request_id'])) {
        throw const FormatException('crypto_migration_commit_attempt_chain');
      }
      row['_payload'] = payload;
      root ??= row;
      chain[row['request_id']] = row;
      latest = row;
      action = 'generationCommitRetry:$generationId:${row['request_id']}';
    }
    final pointers = await runtime.database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [_retryPointer(generationId)],
    );
    if (pointers.isNotEmpty) {
      final pointer = map(jsonDecode(pointers.single['value'] as String));
      CryptoMigrationBusinessParityV3.exact(pointer, {
        'version',
        'generationId',
        'rootRequestId',
        'rootRequestHash',
        'requestId',
        'requestHash',
        'contextHash',
        'payloadHash',
      });
      if (pointer['version'] != 1 ||
          pointer['generationId'] != generationId ||
          root == null ||
          pointer['rootRequestId'] != root['request_id'] ||
          pointer['rootRequestHash'] != root['request_hash'] ||
          chain[pointer['requestId']]?['request_hash'] !=
              pointer['requestHash'] ||
          pointer['payloadHash'] != root['payload_hash'] ||
          !CryptoMigrationBusinessParityV3.hash(pointer['contextHash'])) {
        throw const FormatException('crypto_migration_commit_attempt_pointer');
      }
      latest!['_contextHash'] = pointer['contextHash'];
    }
    if (latest != null) {
      latest['_rootRequestId'] = root!['request_id'];
      latest['_rootRequestHash'] = root['request_hash'];
      latest['_chainIds'] = chain.keys.toSet();
    }
    return latest;
  }

  Map<String, dynamic> _rejection(Map<String, dynamic> row) {
    if (row['state'] != 'rejected' || row['response'] is! String) {
      throw const FormatException('crypto_migration_commit_requires_rejection');
    }
    final receipt = map(jsonDecode(row['response'] as String));
    if (receipt['status'] != 409 ||
        receipt.containsKey('outcome') ||
        receipt['requestId'] != row['request_id'] ||
        receipt['requestHash'] != row['request_hash'] ||
        !_same(
          receipt['authorization'],
          jsonDecode(row['signed_body'] as String),
        ) ||
        receipt['response'] is! Map ||
        receipt['response']['errorCode'] is! String) {
      throw const FormatException('crypto_migration_commit_requires_rejection');
    }
    return receipt;
  }

  Future<String?> rejectedCommitRequest(String generationId) async {
    final row = await _commitAttempt(generationId);
    if (row == null || row['state'] != 'rejected') return null;
    _rejection(row);
    return row['request_id'] as String;
  }

  Future<Map<String, dynamic>> _resumeCommit(Map<String, dynamic> row) async {
    final id = row['request_id'] as String;
    await runtime.queue.resumeUnresolved(requestIds: {id});
    return runtime.queue.commandResult(id);
  }

  /// Explicit user retry after a definite rejection, never an unknown ACK.
  /// Same action key means an interrupted/repeated click resumes exact bytes.
  Future<Map<String, dynamic>> retryRejectedCommit(
    String generationId, {
    required String rejectedRequestId,
  }) async {
    final latest = await _commitAttempt(generationId);
    if (latest == null ||
        !(latest['_chainIds'] as Set).contains(rejectedRequestId)) {
      throw const FormatException('crypto_migration_commit_attempt_chain');
    }
    if (latest['request_id'] != rejectedRequestId) return _resumeCommit(latest);
    final receipt = _rejection(latest);
    final fresh = await runtime.account.directory.call('crypto2.receipt.get', {
      'requestId': rejectedRequestId,
      'requestHash': latest['request_hash'],
    });
    if (!_same(fresh, receipt)) {
      throw const FormatException('crypto_migration_commit_receipt_changed');
    }
    final target = await _commitPayload(generationId);
    if (!_same(target['payload'], latest['_payload']) ||
        latest['_contextHash'] != null &&
            latest['_contextHash'] != target['contextHash']) {
      throw const FormatException('crypto_migration_commit_intent_changed');
    }
    final approvals = await runtime.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='migrationGenerationApproval'",
      [runtime.partition, map(target['payload'])['migrationId'], generationId],
    );
    if (approvals.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_migration_generation_original_context_required',
      );
    }
    final proof = map(
      CryptoJson.decode(
        Uint8List.fromList((approvals.single['payload'] as List).cast<int>()),
      ),
    );
    final body = map(CryptoJson.decode(cryptoBase64(proof['commandBase64'])));
    final own = await runtime.account.directory.requireFresh();
    final device = own.activeDevice(body['deviceId']);
    runtime.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      approvalDomain,
    );
    if (body['version'] != 3 ||
        body['generationId'] != generationId ||
        body['mode'] != 'continue' ||
        body['migrationId'] != map(target['payload'])['migrationId'] ||
        body['serverId'] != own.serverId ||
        body['accountId'] != own.accountId ||
        body['contextHash'] != target['contextHash'] ||
        !own.verifiedHeaders.any(
          (h) => h.headHash == body['authorDirectoryHeadHash'],
        ) ||
        body['deviceSnapshotHash'] != own.deviceSnapshotHash ||
        device['keyringWrite'] != true ||
        !(target['approvals'] as List).any(
          (v) => v is Map && _same(v['authorization'], proof),
        )) {
      throw const FormatException('crypto_migration_commit_intent_changed');
    }
    // Queue signs only under the current device and retains the original row.
    // Normal delivery still checks current authority; the server revalidates
    // every fresh generation approval and exact source/head before effects.
    await runtime.queue.enqueueCommand(
      actionKey: 'generationCommitRetry:$generationId:$rejectedRequestId',
      operation: 'crypto2.migration.commit3',
      payload: map(target['payload']),
    );
    final next = (await _commitAttempt(generationId))!;
    final pointer = {
      'version': 1,
      'generationId': generationId,
      'rootRequestId': next['_rootRequestId'],
      'rootRequestHash': next['_rootRequestHash'],
      'requestId': next['request_id'],
      'requestHash': next['request_hash'],
      'contextHash': target['contextHash'],
      'payloadHash': next['payload_hash'],
    };
    await runtime.database.execute(
      'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
      [_retryPointer(generationId), jsonEncode(pointer)],
    );
    return _resumeCommit(next);
  }

  Future<Map<String, dynamic>> approve(
    String generationId, {
    required Future<bool> Function(Map<String, dynamic> exactContext) review,
  }) async {
    final before = await status(generationId);
    final context = map(before['context']);
    final encoded = CryptoJson.encode(context);
    final contextHash = await cryptoSha256([
      ...utf8.encode('JivieMigrationGenerationContext/v3\n'),
      ...encoded,
    ]);
    if (before['state'] != 'review' ||
        before['contextHash'] != contextHash ||
        context['generationId'] != generationId ||
        context['serverId'] !=
            runtime.account.directory.session.profile.serverId ||
        !const {'supersede', 'continue'}.contains(context['mode'])) {
      throw const FormatException('crypto_migration_generation_context');
    }
    final own = await runtime.account.directory.requireFresh();
    // Before publication each required account checks its COMPLETE verified own
    // prefix for already-anchored scope activations, including SQL-index lies.
    if (context['mode'] == 'supersede') {
      final tokens = <String>{};
      for (final scope in context['scopes'] as List) {
        final token = scope['scopeToken'];
        if (token is! String || !tokens.add(token)) {
          throw const FormatException('crypto_migration_generation_scope_set');
        }
      }
      if ((context['published'] as List).isNotEmpty) {
        throw const FormatException(
          'crypto_migration_generation_publication_boundary',
        );
      }
      // An activation token has its own framing, so compare exact known own
      // final-activation entries through retained proofs, not event_index labels.
      await for (final entry in runtime.account.store.verifiedOperationEntries(
        own,
        'crypto2.account.migrationAttest',
      )) {
        final e = map(
          CryptoJson.decode(
            cryptoBase64(entry['authorization']['commandBase64']),
          ),
        );
        if (e['payload']['migrationId'] != context['migrationId']) continue;
        if (!own.includesAnchor(entry['generation'], entry['headHash'])) {
          throw const FormatException('crypto_migration_generation_event_fork');
        }
        // A final activation is deliberately not a private/source control.
        // An unknown or withheld original proof must leave A incomplete;
        // review of an opaque server context is never absence evidence.
        final classification = await CryptoMigrationOwnAttestation(
          runtime.account,
          own,
        ).classify(entry);
        if (!classification.privateControl &&
            !classification.privateArtifact &&
            classification.kind != 'scopedSource') {
          throw const CryptoAuthorityPending(
            'crypto_migration_generation_publication_boundary',
          );
        }
      }
    }
    final targets = await reviewedTargets(before);
    if (!await review(
      Map<String, dynamic>.unmodifiable({...context, 'reviewTargets': targets}),
    )) {
      throw const CryptoAuthorityPending(
        'crypto_migration_generation_review_required',
      );
    }
    final after = await status(generationId);
    if (after['contextHash'] != contextHash ||
        after['state'] != 'review' ||
        base64Encode(CryptoJson.encode(after['context'])) !=
            base64Encode(encoded)) {
      throw const CryptoAuthorityPending('crypto_migration_generation_changed');
    }
    final current = await runtime.account.directory.requireFresh();
    if (current.deviceSnapshotHash != own.deviceSnapshotHash ||
        current.identityEpochId != own.identityEpochId) {
      throw const CryptoAuthorityPending(
        'crypto_migration_generation_authority_changed',
      );
    }
    final key = 'generationApproval:$generationId';
    final saved = await runtime.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='migrationGenerationApproval'",
      [runtime.partition, context['migrationId'], generationId],
    );
    Map<String, dynamic> proof;
    if (saved.isNotEmpty) {
      proof = map(
        CryptoJson.decode(
          Uint8List.fromList((saved.single['payload'] as List).cast<int>()),
        ),
      );
      final b = map(CryptoJson.decode(cryptoBase64(proof['commandBase64'])));
      if (b['contextHash'] != contextHash ||
          b['accountId'] != own.accountId ||
          b['deviceId'] != runtime.account.deviceId ||
          b['deviceSnapshotHash'] != own.deviceSnapshotHash) {
        throw const FormatException('crypto_immutable_generation_approval');
      }
    } else {
      final lease = await runtime.account.signingKey();
      try {
        proof = runtime.account.directory.reducer.crypto.signDomain(
          {
            'version': 3,
            'serverId': own.serverId,
            'migrationId': context['migrationId'],
            'generationId': generationId,
            'mode': context['mode'],
            'contextHash': contextHash,
            'accountId': own.accountId,
            'deviceId': runtime.account.deviceId,
            'authorDirectoryHeadHash': current.headHash,
            'deviceSnapshotHash': current.deviceSnapshotHash,
          },
          lease.key,
          approvalDomain,
        );
      } finally {
        lease.release();
      }
      await runtime.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          runtime.partition,
          context['migrationId'],
          generationId,
          'migrationGenerationApproval',
          CryptoJson.encode(proof),
        ],
      );
    }
    final token = await cryptoSha256([
      ...utf8.encode('JivieMigrationGenerationToken/v3\n'),
      ...CryptoJson.encode({
        'version': 3,
        'serverId': own.serverId,
        'migrationId': context['migrationId'],
        'generationId': generationId,
      }),
    ]);
    final event = await runtime.account.attestMigration(
      migrationId: context['migrationId'],
      scopeToken: token,
      domain: 'content',
      attestationHash: await cryptoSha256(CryptoJson.encode(proof)),
    );
    return send(key, 'crypto2.migration.generation.approve', {
      'generationId': generationId,
      'authorization': proof,
      'eventAuthorization': event['authorization'],
    });
  }

  Future<Map<String, dynamic>> finish(
    String generationId,
    String contextHash,
  ) => send(
    'generationFinish:$generationId',
    'crypto2.migration.generation.finish',
    {'generationId': generationId, 'contextHash': contextHash},
  );
}
