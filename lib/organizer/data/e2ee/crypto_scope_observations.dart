import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../../domain/collaboration_models.dart' show CollaborationException;

import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_business_router.dart';
import 'crypto_migration_own_attestation.dart';
import 'crypto_migration_commitments_v3.dart';
import 'crypto_migration_local_artifact_cold.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// Own account log inclusion authenticates an already verified scoped view.
/// Foreign directory readers see only opaque commitments. The companion bundle
/// grants neither a global contact pin nor authority over an unobserved tail.
class CryptoScopeRecoveryIncomplete extends CryptoAuthorityPending {
  const CryptoScopeRecoveryIncomplete({
    required this.pendingScopes,
    required this.unmatchedOwnAnchors,
    required this.discoveryPending,
  }) : super('crypto_scope_recovery_incomplete');
  final int pendingScopes, unmatchedOwnAnchors;
  final bool discoveryPending;
}

class _ScopeRecoveryRun {
  _ScopeRecoveryRun(this.id, this.own, this.observed, this.events);
  final String id;
  final VerifiedAccountDirectory own;
  final List<String> observed;
  final StreamIterator<Map<String, dynamic>> events;
  int observedOffset = 0;
  bool eventsComplete = false, catalogComplete = false;
  String? afterId;
  String lastScope = '';
  String lastClaim = '';
  final recovered = <String, VerifiedRecoveredMigrationGenesis>{};
}

class CryptoScopeObservations {
  CryptoScopeObservations(this.account);
  final AccountCryptoV2Workflow account;
  static Future<String> token(String server, String account, String scope) =>
      cryptoSha256(
        utf8.encode('JivieScopeObservation/v2\n') +
            CryptoJson.encode({
              'serverId': server,
              'accountId': account,
              'scopeId': scope,
            }),
      );
  static Future<String> digest(Map<String, dynamic> bundle) => cryptoSha256(
    utf8.encode('JivieScopeObservationBundle/v2\n') + CryptoJson.encode(bundle),
  );
  Map<String, dynamic> _decode(Object raw) => Map<String, dynamic>.from(
    raw is String
        ? jsonDecode(raw)
        : CryptoJson.decode(Uint8List.fromList((raw as List).cast<int>()))
              as Map,
  );

  Future<void> observe(SessionCryptoAccess access, String scope) async {
    final head = await access.currentHead(scope, online: true);
    final checkpoints = <Map<String, dynamic>>[];
    for (final domain in ['content', 'finance']) {
      if (domain == 'finance' &&
          head.member(account.directory.accountId)['financeRole'] == 'none')
        continue;
      final rows = await account.store.database.rows(
        'SELECT * FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? ORDER BY sequence DESC LIMIT 1',
        [account.store.partition, scope, domain],
      );
      if (rows.isEmpty) continue;
      final row = rows.single, proof = _decode(row['authorization']!);
      // These rows are populated only after full manifest verification. Verify
      // the certificate again before committing its exact observation hash.
      await access.verifyDomainCheckpoint(proof);
      final signed =
              CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
          p = signed['payload'] as Map;
      if (p['scopeId'] != scope ||
          p['domain'] != domain ||
          p['membershipHeadHash'] != row['head_hash'] ||
          p['epoch'] != row['epoch'] ||
          p['accessRevision'] != row['access_revision'] ||
          p['expectedSequence'] != row['sequence'] ||
          p['manifestHash'] != row['manifest_hash'] ||
          p['recordCount'] != row['record_count'] ||
          p['historyBasis'] != row['history_basis'])
        throw const FormatException('scope_observation_checkpoint_coordinates');
      checkpoints.add({
        'domain': domain,
        'membershipHeadHash': row['head_hash'],
        'sequence': row['sequence'],
        'manifestHash': row['manifest_hash'],
        'recordCount': row['record_count'],
        'proofHashes': [await cryptoSha256(CryptoJson.encode(proof))],
      });
    }
    String? acceptance;
    for (final row in await account.store.database.rows(
      "SELECT authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='confirmed' AND authorization IS NOT NULL",
      [account.store.partition, scope],
    )) {
      final proof = _decode(row['authorization']!);
      final raw =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      if (raw['operation'] == 'crypto2.invitations.accept' &&
          raw['accountId'] == account.directory.accountId) {
        acceptance = await cryptoSha256(CryptoJson.encode(proof));
        break;
      }
    }
    final crypto = account.directory.reducer.crypto;
    final bundle = <String, dynamic>{
      'version': 2,
      'serverId': account.directory.session.profile.serverId,
      'accountId': account.directory.accountId,
      'scopeId': scope,
      'headHash': head.headHash,
      'proposalProofHash': await cryptoSha256(
        CryptoJson.encode(head.authorization),
      ),
      'activationProofHash': null,
      'grantManifestHash': null,
      'members': [
        for (final m in head.members)
          {
            'accountId': m['accountId'],
            'directoryHeadHash': m['directoryHeadHash'],
            'deviceSnapshotHash': m['deviceSnapshotHash'],
            'rootFingerprint': crypto.fingerprint(
              cryptoBase64(m['rootSigningKeyBase64']),
              cryptoBase64(m['rootEncryptionKeyBase64']),
            ),
          },
      ],
      'acceptanceProofHash': acceptance,
      'checkpoints': checkpoints,
      'lifecycleHash': await access.verifiedLifecycleHash(scope),
    };
    final stored = (await account.store.database.rows(
      'SELECT authorization FROM crypto_scope_heads WHERE partition=? AND scope_id=? AND head_hash=?',
      [account.store.partition, scope, head.headHash],
    )).single;
    final wire = _decode(stored['authorization']!),
        activation = Map<String, dynamic>.from(
          wire['activationAuthorization'] as Map,
        );
    final ac =
        CryptoJson.decode(cryptoBase64(activation['commandBase64'])) as Map;
    bundle['activationProofHash'] = await cryptoSha256(
      CryptoJson.encode(activation),
    );
    bundle['grantManifestHash'] = ac['payload']['grantManifestHash'];
    final hash = await digest(bundle),
        scopeToken = await token(
          bundle['serverId'],
          bundle['accountId'],
          scope,
        );
    // Exact local state is journaled before any upload. Candidate PUT precedes
    // log inclusion so a device loss can never strand an included commitment.
    await account.store.database.execute(
      'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO NOTHING',
      [
        account.store.partition,
        scope,
        hash,
        'scopeObservationCandidate',
        CryptoJson.encode(bundle),
      ],
    );
    final known = await recover(scope);
    if (known.any((b) => b['observationHash'] == hash)) return;
    await account.directory.call('crypto2.account.scopeObservation.put', {
      'observation': bundle,
    });
    await account.observeScope(
      scopeToken: scopeToken,
      headHash: head.headHash,
      observationHash: hash,
    );
    if (!(await recover(scope)).any((b) => b['observationHash'] == hash))
      throw const CryptoAuthorityPending('scope_observation_pending');
  }

  static final _recoveryRuns = Expando<_ScopeRecoveryRun>();

  static Future<bool> recoveryIncomplete(
    AccountCryptoV2Workflow account,
  ) async => (await account.store.database.rows(
    "SELECT 1 FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id='fileScopeRecoverySummary' AND state='scopeRecoveryPending'",
    [account.store.partition, account.directory.accountId],
  )).isNotEmpty;

  /// A bounded retry preserves readable recovered scopes. Durable cursors and
  /// route rows are discovery only; completion uses a fresh random run handle
  /// whose covered commands were produced by full cryptographic verification.
  Future<void> hydrateObservedScopes(Uint8List file) async {
    final db = account.store.database, partition = account.store.partition;
    final own = await account.directory.cachedVerifiedDirectory();
    final info = account.files.inspect(
      file,
      serverId: own.serverId,
      accountId: own.accountId,
    );
    if (info['fingerprint'] != own.rootFingerprint) {
      throw const FormatException('scope_recovery_file_identity');
    }
    final status = await account.status();
    final root = account.files.open(
      file: file,
      encryptedRoot: Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(status['keyringCiphertextBase64']))
            as Map,
      ),
      serverId: own.serverId,
      accountId: own.accountId,
      expectedFingerprint: own.rootFingerprint,
    );
    root.dispose();
    Future<void> save(
      String scope,
      String id,
      String state,
      Map<String, dynamic> payload,
    ) => db.execute(
      'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO UPDATE SET state=excluded.state,payload=excluded.payload',
      [partition, scope, id, state, CryptoJson.encode(payload)],
    );
    await save(
      own.accountId,
      'fileScopeRecoverySummary',
      'scopeRecoveryPending',
      {'reason': 'scope_recovery_verification_required'},
    );
    var run = _recoveryRuns[account];
    // A running pre-upgrade verification may have derived route rows without
    // the finance token. Start a fresh bounded verification run, rather than
    // treating those rows as evidence or stranding an evicted capsule forever.
    final oldRouteFormat =
        run != null &&
        (await db.rows(
          "SELECT 1 FROM crypto_membership_intents WHERE partition=? AND intent_id='fileScopeRecoveryRoute' AND json_extract(CAST(payload AS TEXT),'\$.verifiedRunId')=? AND json_extract(CAST(payload AS TEXT),'\$.genesisHeadHash') IS NOT NULL AND json_extract(CAST(payload AS TEXT),'\$.financeToken') IS NULL LIMIT 1",
          [partition, run.id],
        )).isNotEmpty;
    if (run == null || run.own.headHash != own.headHash || oldRouteFormat) {
      await run?.events.cancel();
      final observed = (await recover(
        null,
      )).map((b) => b['scopeId'] as String).toList();
      run = _ScopeRecoveryRun(
        account.directory.reducer.crypto.randomId(),
        own,
        observed,
        StreamIterator(
          account.store.verifiedOperationEntries(
            own,
            'crypto2.account.migrationAttest',
          ),
        ),
      );
      final cursor = await db.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id='fileScopeRecoveryDiscovery'",
        [partition, own.accountId],
      );
      if (cursor.length == 1) {
        final previous = _decode(cursor.single['payload']!);
        if (previous['ownHeadHash'] == own.headHash &&
            previous['catalogComplete'] == false &&
            isCryptoCanonicalUuid(previous['afterId']))
          run.afterId = previous['afterId'];
      }
      _recoveryRuns[account] = run;
    }
    final activeRun = run;
    Future<void> route(String scope) async {
      if (!isCryptoCanonicalUuid(scope))
        throw const FormatException('scope_recovery_route');
      await db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO NOTHING',
        [
          partition,
          scope,
          'fileScopeRecoveryRoute',
          'scopeRecoveryDiscovered',
          CryptoJson.encode({'ownHeadHash': own.headHash}),
        ],
      );
    }

    for (
      var n = 0;
      n < 50 && activeRun.observedOffset < activeRun.observed.length;
      n++
    ) {
      await route(activeRun.observed[activeRun.observedOffset++]);
    }
    for (
      var pageNumber = 0;
      pageNumber < 4 && !activeRun.catalogComplete;
      pageNumber++
    ) {
      final page = await account.directory.call('crypto2.scopes.catalog', {
        if (activeRun.afterId != null) 'afterId': activeRun.afterId,
        'limit': 50,
      });
      final values = page['scopes'];
      if (values is! List || values.length > 50)
        throw const FormatException('scope_recovery_catalog');
      var last = activeRun.afterId;
      for (final value in values) {
        if (value is! Map ||
            !isCryptoCanonicalUuid(value['id']) ||
            last != null && last.compareTo(value['id']) >= 0)
          throw const FormatException('scope_recovery_catalog');
        last = value['id'] as String;
        await route(last);
      }
      if (page['hasMore'] == false) {
        activeRun.catalogComplete = true;
      } else if (page['hasMore'] != true ||
          values.isEmpty ||
          last == null ||
          page['nextAfterId'] != last) {
        throw const FormatException('scope_recovery_catalog');
      }
      activeRun.afterId = last;
    }
    await save(
      own.accountId,
      'fileScopeRecoveryDiscovery',
      'scopeRecoveryDiscovery',
      {
        'ownHeadHash': own.headHash,
        'afterId': activeRun.afterId,
        'catalogComplete': activeRun.catalogComplete,
      },
    );
    // The account log fixes the expected publication set. Unsigned catalog
    // omission therefore cannot turn an empty discovered list into success.
    for (var n = 0; n < 128 && !activeRun.eventsComplete; n++) {
      if (!await activeRun.events.moveNext()) {
        activeRun.eventsComplete = true;
        await activeRun.events.cancel();
        break;
      }
      final entry = activeRun.events.current,
          proof = Map<String, dynamic>.from(
            activeRun.events.current['authorization'] as Map,
          );
      final commandHash = await cryptoSha256(
        cryptoBase64(proof['commandBase64']),
      );
      final recomputed = await cryptoSha256([
        ...utf8.encode(cryptoDirectoryLogDomain),
        ...CryptoJson.encode({
          'serverId': own.serverId,
          'accountId': own.accountId,
          'generation': entry['generation'],
          'previousHeadHash': entry['previousHeadHash'],
          'commandHash': commandHash,
          'signatureBase64': proof['signatureBase64'],
        }),
      ]);
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      if (command['operation'] != 'crypto2.account.migrationAttest' ||
          command['accountId'] != own.accountId ||
          command['serverId'] != own.serverId ||
          recomputed != entry['headHash'] ||
          !own.includesAnchor(entry['generation'], recomputed))
        throw const FormatException('scope_recovery_migration_inclusion');
      await save(
        own.accountId,
        'scopeRecoveryExpected:$commandHash',
        'scopeRecoveryExpected',
        {'runId': activeRun.id, 'commandHash': commandHash, 'entry': entry},
      );
    }
    var work = await db.rows(
      "SELECT scope_id FROM crypto_membership_intents WHERE partition=? AND intent_id='fileScopeRecoveryRoute' AND COALESCE(json_extract(CAST(payload AS TEXT),'\$.verifiedRunId'),'')<>? AND scope_id>? ORDER BY scope_id LIMIT 20",
      [partition, activeRun.id, activeRun.lastScope],
    );
    if (work.isEmpty && activeRun.lastScope.isNotEmpty) {
      activeRun.lastScope = '';
      work = await db.rows(
        "SELECT scope_id FROM crypto_membership_intents WHERE partition=? AND intent_id='fileScopeRecoveryRoute' AND COALESCE(json_extract(CAST(payload AS TEXT),'\$.verifiedRunId'),'')<>? ORDER BY scope_id LIMIT 20",
        [partition, activeRun.id],
      );
    }
    for (final row in work) {
      final scope = row['scope_id'] as String;
      activeRun.lastScope = scope;
      try {
        final access = SessionCryptoAccess(account: account);
        await access.recoverScopeCandidateKeys(scope, file);
        final genesis = await access.recoveredMigrationGenesis(scope);
        if (genesis != null) {
          if (activeRun.recovered.length >= 20)
            activeRun.recovered.remove(activeRun.recovered.keys.first);
          activeRun.recovered[scope] = genesis;
        }
        for (final hash in access.verifiedMigrationPublicationCommandHashes(
          scope,
        )) {
          await save(
            own.accountId,
            'scopeRecoveryCovered:$hash',
            'scopeRecoveryCovered',
            {'runId': activeRun.id, 'commandHash': hash},
          );
        }
        await save(scope, 'fileScopeRecoveryRoute', 'scopeRecoveryDiscovered', {
          'ownHeadHash': own.headHash,
          'verifiedRunId': activeRun.id,
          if (genesis != null) 'genesisHeadHash': genesis.headHash,
          if (genesis != null) 'migrationId': genesis.migrationId,
          if (genesis != null)
            'financeToken': await CryptoMigrationCommitmentsV3.scopeToken(
              serverId: own.serverId,
              migrationId: genesis.migrationId,
              scopeId: scope,
              domain: 'finance',
            ),
          if (genesis != null)
            'structureToken': await cryptoSha256([
              ...utf8.encode('JivieStructureSourceToken/v3\n'),
              ...CryptoJson.encode({
                'version': 3,
                'serverId': own.serverId,
                'migrationId': genesis.migrationId,
                'accountId': own.accountId,
                'scopeId': scope,
              }),
            ]),
        });
        await db.execute(
          "DELETE FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id='fileScopeRecovery' AND state='scopeRecoveryPending'",
          [partition, scope],
        );
      } on CryptoAuthorityPending catch (error) {
        await save(scope, 'fileScopeRecovery', 'scopeRecoveryPending', {
          'reason': error.reason,
        });
      }
    }
    // Classify at most twenty additional own attestations per pass. Original
    // signed controls are not missing spaces; private work is recovered through
    // the FILE-bound verifier and kept in quarantine before marking it covered.
    Future<List<Map<String, Object?>>> claims(String after) => db.rows(
      "SELECT e.intent_id,e.payload FROM crypto_membership_intents e WHERE e.partition=? AND e.scope_id=? AND e.state='scopeRecoveryExpected' AND json_extract(CAST(e.payload AS TEXT),'\$.runId')=? AND e.intent_id>? AND NOT EXISTS (SELECT 1 FROM crypto_membership_intents c WHERE c.partition=e.partition AND c.scope_id=e.scope_id AND c.intent_id='scopeRecoveryCovered:'||json_extract(CAST(e.payload AS TEXT),'\$.commandHash') AND json_extract(CAST(c.payload AS TEXT),'\$.runId')=?) ORDER BY e.intent_id LIMIT 20",
      [partition, own.accountId, activeRun.id, after, activeRun.id],
    );
    var claimRows = await claims(activeRun.lastClaim);
    if (claimRows.isEmpty && activeRun.lastClaim.isNotEmpty) {
      activeRun.lastClaim = '';
      claimRows = await claims('');
    }
    final classifier = CryptoMigrationOwnAttestation(account, own);
    for (final row in claimRows) {
      activeRun.lastClaim = row['intent_id'] as String;
      final pendingClaim = _decode(row['payload']!);
      final hash = pendingClaim['commandHash'] as String;
      try {
        final entry = Map<String, dynamic>.from(pendingClaim['entry'] as Map);
        final classified = await classifier.classify(entry);
        var covered = classified.privateControl;
        if (classified.privateArtifact) {
          final restored = await restoreCryptoMigrationOwnLocalArtifact(
            runtime: CryptoBusinessSession(
              account,
              SessionCryptoAccess(account: account),
              db,
            ),
            attestation: classified,
            recoveryFile: file,
            ownEvent: Map<String, dynamic>.from(entry['authorization'] as Map),
          );
          await save(
            own.accountId,
            'scopeRecoveryArtifact:$hash',
            'scopeRecoveryQuarantine',
            {'runId': activeRun.id, ...restored.result},
          );
          covered = true;
        } else if (classified.scopedContribution) {
          final c = classified.scopedClaim!;
          final candidates = await db.rows(
            "SELECT scope_id FROM crypto_membership_intents WHERE partition=? AND intent_id='fileScopeRecoveryRoute' AND json_extract(CAST(payload AS TEXT),'\$.migrationId')=? AND json_extract(CAST(payload AS TEXT),'\$.financeToken')=? AND json_extract(CAST(payload AS TEXT),'\$.verifiedRunId')=? LIMIT 2",
            [partition, c['migrationId'], c['scopeToken'], activeRun.id],
          );
          if (candidates.length == 1) {
            final scope = candidates.single['scope_id'] as String;
            final access = SessionCryptoAccess(account: account);
            await access.recoverScopeCandidateKeys(scope, file);
            final genesis = await access.recoveredMigrationGenesis(scope);
            final cached = activeRun.recovered[scope];
            if (genesis != null &&
                cached != null &&
                (genesis.scopeId != cached.scopeId ||
                    genesis.headHash != cached.headHash ||
                    genesis.migrationId != cached.migrationId)) {
              throw const FormatException('scope_recovery_genesis_changed');
            }
            if (genesis != null) {
              covered = await classified.matchesFinalFinanceContribution(
                access,
                genesis,
              );
            }
          }
        } else if (classified.scopedClaim != null) {
          final c = classified.scopedClaim!;
          final candidates = await db.rows(
            "SELECT scope_id FROM crypto_membership_intents WHERE partition=? AND intent_id='fileScopeRecoveryRoute' AND json_extract(CAST(payload AS TEXT),'\$.migrationId')=? AND json_extract(CAST(payload AS TEXT),'\$.genesisHeadHash')=? AND (? IS NULL OR scope_id=?) AND (? IS NULL OR json_extract(CAST(payload AS TEXT),'\$.structureToken')=?) LIMIT 2",
            [
              partition,
              c['migrationId'],
              c['membershipHeadHash'],
              c['scopeId'],
              c['scopeId'],
              c['scopeToken'],
              c['scopeToken'],
            ],
          );
          if (candidates.length == 1) {
            final scope = candidates.single['scope_id'] as String;
            var capsule = activeRun.recovered[scope];
            if (capsule == null) {
              final access = SessionCryptoAccess(account: account);
              await access.recoverScopeCandidateKeys(scope, file);
              capsule = await access.recoveredMigrationGenesis(scope);
            }
            covered =
                capsule != null &&
                await classified.matchesRecoveredGenesis(capsule);
            if (covered) {
              for (final nested in await classified.coveredCommandsFor(
                capsule,
              )) {
                await save(
                  own.accountId,
                  'scopeRecoveryCovered:$nested',
                  'scopeRecoveryCovered',
                  {'runId': activeRun.id, 'commandHash': nested},
                );
              }
            }
          }
        }
        if (covered) {
          await save(
            own.accountId,
            'scopeRecoveryCovered:$hash',
            'scopeRecoveryCovered',
            {'runId': activeRun.id, 'commandHash': hash},
          );
        }
      } on CryptoAuthorityPending catch (_) {
        // Keep the exact obligation; neither absence nor a server label clears it.
      } on CollaborationException catch (error) {
        if (!const {
          'crypto_own_attestation_pending',
          'crypto_migration_activation_pending',
          'permission_denied',
          'permission_revoked',
          'scope_not_found',
        }.contains(error.code))
          rethrow;
      }
    }
    if ((await account.directory.cachedVerifiedDirectory()).headHash !=
        own.headHash) {
      throw const CryptoScopeRecoveryIncomplete(
        pendingScopes: 0,
        unmatchedOwnAnchors: 0,
        discoveryPending: true,
      );
    }
    final pending =
        (await db.rows(
              "SELECT COUNT(*) AS n FROM crypto_membership_intents WHERE partition=? AND intent_id='fileScopeRecoveryRoute' AND COALESCE(json_extract(CAST(payload AS TEXT),'\$.verifiedRunId'),'')<>?",
              [partition, activeRun.id],
            )).single['n']
            as int;
    final unmatched =
        (await db.rows(
              "SELECT COUNT(*) AS n FROM crypto_membership_intents e WHERE e.partition=? AND e.scope_id=? AND e.state='scopeRecoveryExpected' AND json_extract(CAST(e.payload AS TEXT),'\$.runId')=? AND NOT EXISTS (SELECT 1 FROM crypto_membership_intents c WHERE c.partition=e.partition AND c.scope_id=e.scope_id AND c.intent_id='scopeRecoveryCovered:'||json_extract(CAST(e.payload AS TEXT),'\$.commandHash') AND json_extract(CAST(c.payload AS TEXT),'\$.runId')=?)",
              [partition, own.accountId, activeRun.id, activeRun.id],
            )).single['n']
            as int;
    final discoveryPending =
        !activeRun.catalogComplete ||
        !activeRun.eventsComplete ||
        activeRun.observedOffset < activeRun.observed.length;
    if (pending != 0 || unmatched != 0 || discoveryPending) {
      await save(
        own.accountId,
        'fileScopeRecoverySummary',
        'scopeRecoveryPending',
        {
          'reason': 'crypto_scope_recovery_incomplete',
          'pendingScopes': pending,
          'unmatchedOwnAnchors': unmatched,
          'discoveryPending': discoveryPending,
        },
      );
      throw CryptoScopeRecoveryIncomplete(
        pendingScopes: pending,
        unmatchedOwnAnchors: unmatched,
        discoveryPending: discoveryPending,
      );
    }
    await db.execute(
      "DELETE FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id='fileScopeRecoverySummary' AND state='scopeRecoveryPending'",
      [partition, own.accountId],
    );
  }

  Future<List<Map<String, dynamic>>> recover(
    String? scope, {
    VerifiedAccountDirectory? readOnlyOwnPrefix,
    bool descriptorHistory = false,
  }) async {
    if (descriptorHistory && scope == null) {
      throw const FormatException('scope_descriptor_history_scope_required');
    }
    var own =
        readOnlyOwnPrefix ?? await account.directory.cachedVerifiedDirectory();
    if (own.accountId != account.directory.accountId ||
        own.serverId != account.directory.session.profile.serverId) {
      throw const FormatException('scope_observation_own_prefix');
    }

    final result = <Map<String, dynamic>>[];
    Future<Map<String, dynamic>> accept(
      Map value, {
      Map<String, dynamic>? expected,
    }) async {
      final entry =
          expected ??
          await account.store.entryByHash(
            own.accountId,
            value['eventCommandHash'],
          );
      if (entry == null ||
          !own.includesAnchor(entry['generation'], entry['headHash']) ||
          expected == null && entry['generation'] != value['generation'])
        throw const FormatException('scope_observation_inclusion');
      final command =
              CryptoJson.decode(
                    cryptoBase64(entry['authorization']['commandBase64']),
                  )
                  as Map,
          p = command['payload'] as Map;
      final bundle = Map<String, dynamic>.from(value['observation'] as Map),
          hash = await digest(bundle);
      if (command['operation'] != 'crypto2.account.scopeObserve' ||
          command['accountId'] != own.accountId ||
          bundle['version'] != 2 ||
          bundle['serverId'] != own.serverId ||
          bundle['accountId'] != own.accountId ||
          p['scopeToken'] !=
              await token(own.serverId, own.accountId, bundle['scopeId']) ||
          p['headHash'] != bundle['headHash'] ||
          p['observationHash'] != hash)
        throw const FormatException('scope_observation_substitution');
      return {
        ...bundle,
        'observationHash': hash,
        'generation': entry['generation'],
      };
    }

    try {
      final cursor = (await account.store.database.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id='scopeObservationCursor' AND state='scopeObservationCursor'",
        [account.store.partition, account.directory.accountId],
      )).firstOrNull;
      var after = cursor == null
          ? 0
          : _decode(cursor['payload']!)['generation'] as int;
      if (after > own.generation)
        throw const FormatException('scope_observation_cursor_ahead');
      while (true) {
        final page = await account.directory.call(
          'crypto2.account.scopeObservations',
          {'afterGeneration': after, 'limit': 20},
        );
        if (page['observations'] is! List || page['hasMore'] is! bool)
          throw const FormatException('scope_observation_page');
        var last = after;
        for (final value in page['observations'] as List) {
          if (value is! Map ||
              value['generation'] is! int ||
              value['generation'] <= last)
            throw const FormatException('scope_observation_order');
          last = value['generation'];
          if (value['generation'] > own.generation) {
            if (readOnlyOwnPrefix != null) break;
            own =
                (await account.directory.refresh()) ??
                (throw const FormatException(
                  'scope_observation_directory_missing',
                ));
          }
          await accept(value);
          final bundle = Map<String, dynamic>.from(value['observation'] as Map),
              hash = await digest(bundle);
          await account.store.database.execute(
            'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO UPDATE SET state=excluded.state,payload=excluded.payload',
            [
              account.store.partition,
              bundle['scopeId'],
              hash,
              'scopeObservationIncluded',
              CryptoJson.encode(Map<String, dynamic>.from(value)),
            ],
          );
        }
        if (page['hasMore'] != true ||
            readOnlyOwnPrefix != null && last > own.generation)
          break;
        if (page['nextGeneration'] is! int ||
            page['nextGeneration'] <= after ||
            page['nextGeneration'] != last)
          throw const FormatException('scope_observation_cursor');
        after = page['nextGeneration'];
      }
    } on CollaborationException catch (error) {
      if (error.code != 'network') rethrow;
    }
    // The authenticated account log, never unsigned page/cursor metadata,
    // determines which companion bundles MUST be present. Even an older valid
    // bundle cannot cover an omitted later observation of the same space.
    final headers = own.verifiedHeaders.iterator;
    headers.moveNext();
    final seen = <String>{}, carrierHeads = <String>{};
    await for (final entry in account.store.verifiedOperationEntries(
      own,
      'crypto2.account.scopeObserve',
    )) {
      while (headers.current.generation > entry['generation']) {
        if (!headers.moveNext())
          throw const FormatException('scope_observation_inclusion');
      }
      if (headers.current.generation != entry['generation'] ||
          headers.current.headHash != entry['headHash'])
        throw const FormatException('scope_observation_inclusion');
      final c =
              CryptoJson.decode(
                    cryptoBase64(entry['authorization']['commandBase64']),
                  )
                  as Map,
          p = c['payload'] as Map;
      if (c['operation'] != 'crypto2.account.scopeObserve')
        throw const FormatException('scope_observation_index');
      final stored = await account.store.database.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND intent_id=? AND state='scopeObservationIncluded'",
        [account.store.partition, p['observationHash']],
      );
      if (stored.length != 1)
        throw const CryptoAuthorityPending('scope_observation_bundle_missing');
      final bundle = await accept(
        _decode(stored.single['payload']!),
        expected: entry,
      );
      if (scope == null || bundle['scopeId'] == scope) {
        if (descriptorHistory) {
          // This is a bounded transport search, never an absence/completeness
          // claim. Keep validating every included signed observation even when
          // the returned newest-first candidate prefix reaches its limit.
          if (result.length < 128 && carrierHeads.add(bundle['headHash'])) {
            result.add(bundle);
          }
        } else if (seen.add(bundle['scopeId'])) {
          result.add(bundle);
        }
      }
    }
    await account.store.database.execute(
      "INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO UPDATE SET payload=CASE WHEN CAST(json_extract(CAST(excluded.payload AS TEXT),'\$.generation') AS INTEGER)>CAST(json_extract(CAST(crypto_membership_intents.payload AS TEXT),'\$.generation') AS INTEGER) THEN excluded.payload ELSE crypto_membership_intents.payload END",
      [
        account.store.partition,
        own.accountId,
        'scopeObservationCursor',
        'scopeObservationCursor',
        CryptoJson.encode({'generation': own.generation}),
      ],
    );
    return result;
  }
}
