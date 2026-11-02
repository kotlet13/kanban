import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/account_deletion_store.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_active_outbox.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/local_vault_keys.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/data/recovery_bundle.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:sodium/sodium.dart';

// Opt-in, one durable stage per process. Only this dedicated loopback fixture is
// accepted. HTTP responses, crypto guards, reducers and sync are production code.
// Disk adapters replace OS secret storage only; the files contain SYNTHETIC keys
// and must remain in the ignored private evidence directory, never in Git.
// CollaborationRepository uses its own production router/readiness/cache path;
// only the platform secret-storage channel is redirected for account crypto.
// Each phase cold-opens the same SQL/session files. This does not exercise native
// encrypted vault/file-picker behavior or the UI's warm scheduling/lifecycle.
Future<Map<String, dynamic>> _json(File file) async => file.existsSync()
    ? Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map)
    : {};

Future<void> _save(File file, Object? value) async {
  final temporary = File('${file.path}.next');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(file.path);
}

void _check(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

String _code(Object? error) => switch (error) {
  null => 'none',
  CryptoAuthorityPending() => error.reason,
  CryptoDirectoryException() => error.code,
  CollaborationException() => error.code,
  FormatException() when RegExp(r'^[a-z0-9_]+$').hasMatch(error.message) =>
    error.message,
  StateError() when RegExp(r'^[a-z0-9_]+$').hasMatch(error.message) =>
    error.message,
  _ => error.runtimeType.toString(),
};

class _Secrets implements AccountCryptoStore {
  _Secrets(this.file);
  final File file;
  Future<void> _tail = Future.value();
  @override
  Future<String?> read(String key) async {
    await _tail;
    return (await _json(file))[key] as String?;
  }

  @override
  Future<void> write(String key, String value) {
    final next = _tail.then((_) async {
      final values = await _json(file);
      values[key] = value;
      await _save(file, values);
    });
    _tail = next;
    return next;
  }
}

class _Sessions implements DeviceSessionStore {
  _Sessions(this.file);
  final File file;
  DeviceSession? current;
  @override
  Future<DeviceSession?> read() async {
    if (current != null) return current;
    final value = await _json(file);
    if (value.isEmpty) return null;
    return current = DeviceSession(
      AccountSession.fromJson(
        Map<String, dynamic>.from(value['profile'] as Map),
      ),
      value['token'] as String,
    );
  }

  @override
  Future<void> write(DeviceSession value) async {
    await _save(file, {
      'profile': value.profile.toJson(),
      'token': value.token,
    });
    current = value;
  }

  @override
  Future<void> clear() async {
    await _save(file, {});
    current = null;
  }
}

class _Invitations implements PendingInvitationStore {
  @override
  Future<PendingInvitation?> read() async => null;
  @override
  Future<void> write(PendingInvitation? invitation) async {
    _check(invitation == null, 'unexpected_invitation_in_password_flow');
  }
}

class _Deletions implements AccountDeletionStore {
  @override
  Future<List<PendingAccountDeletion>> read() async => [];
  @override
  Future<void> write(List<PendingAccountDeletion> requests) async {
    _check(requests.isEmpty, 'unexpected_deletion_in_password_flow');
  }
}

class _Flow {
  _Flow(this.root, this.fixture, this.state, {this.readOnlyProbe = false});
  final Directory root;
  final Map<String, dynamic> fixture, state;
  final bool readOnlyProbe;
  static const _probeReadOperations = {
    'capabilities',
    'crypto2.authority.snapshot',
    'crypto2.account.status',
    'crypto2.account.directory',
    'crypto2.account.scopeObservations',
    'crypto2.scopes.catalog',
    'crypto2.scope.headGet',
    'crypto2.directory.status',
    'crypto2.directory.read',
    'crypto2.scope.lifecycle.baseline',
    'crypto2.scope.lifecycle.list',
    'crypto2.scope.recordPolicy.status',
    'crypto2.scope.recordPolicy.baseline',
    'crypto2.scope.closureGet',
    'crypto2.grants.list',
    'crypto2.grants.manifest',
  };
  late final CollaborationDatabase db;
  late final CollaborationRepository repo;
  late final _Sessions sessions;
  late final _Secrets secrets;
  late final CryptoCodec crypto;
  late final HttpCollaborationTransport wire;
  final Map<String, int> calls = {};
  DeviceSession? setupSession;
  AccountCryptoV2Workflow? setupAccount;
  bool closed = false;
  bool observedUnresolved = false;
  String get url => fixture['serverUrl'] as String;
  Map get owner => fixture['owner'] as Map;
  String get email => owner['email'] as String? ?? 'password-flow@example.test';
  String get initialPassword => owner['password'] as String;
  String get changedPassword => state['changedPassword'] as String;
  String get resetPassword => state['resetPassword'] as String;
  File get recoveryFile => File('${root.path}/owner.jivie-recovery');
  Future<void> save() => _save(File('${root.path}/ledger-private.json'), state);

  Future<void> open() async {
    db = CollaborationDatabase(
      NativeDatabase(File('${root.path}/owner.sqlite')),
    );
    sessions = _Sessions(File('${root.path}/owner-session-private.json'));
    secrets = _Secrets(File('${root.path}/owner-keys-private.json'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final key = args['key'] as String;
            switch (call.method) {
              case 'read':
                return secrets.read(key);
              case 'write':
                await secrets.write(key, args['value'] as String);
                return null;
              default:
                throw StateError('unexpected_secret_storage_method');
            }
          },
        );
    crypto = CryptoCodec(await SodiumInit.init());
    wire = HttpCollaborationTransport(
      onAttempt: (operation) {
        if (readOnlyProbe && !_probeReadOperations.contains(operation)) {
          throw StateError('probe_http_operation_not_allowed');
        }
        calls.update(operation, (n) => n + 1, ifAbsent: () => 1);
      },
    );
    repo = CollaborationRepository(
      db,
      wire,
      sessions,
      ownsDatabase: false,
      invitationStore: _Invitations(),
      deletionStore: _Deletions(),
    );
    await repo.initialize();
    state.putIfAbsent('changedPassword', () => '${crypto.randomId()}Aa1!');
    state.putIfAbsent('resetPassword', () => '${crypto.randomId()}Bb2!');
    await save();
  }

  Future<AccountCryptoV2Workflow> account() async {
    final session = await sessions.read();
    _check(session != null, 'session_required');
    if (!identical(setupSession, session)) {
      setupSession = session;
      setupAccount =
          await repo.accountCryptoPreview() as AccountCryptoV2Workflow?;
    }
    _check(setupAccount != null, 'v2_crypto_workflow_required');
    return setupAccount!;
  }

  Future<void> step(String name, Future<void> Function() action) async {
    final steps = state.putIfAbsent('steps', () => <String, dynamic>{}) as Map;
    if (steps[name] == 'passed') return;
    await action();
    steps[name] = 'passed';
    await save();
  }

  Future<void> authenticateAndObserve(
    String name,
    Future<void> Function() action,
  ) async {
    final previousDevice = sessions.current?.profile.deviceId;
    try {
      await action();
    } catch (error) {
      final current = sessions.current;
      // _authenticate saves the new HTTP session, then invokes sync. A missing
      // crypto setup/rebind can throw after successful authentication. Prove the
      // new bearer with the ordinary account status endpoint before separating
      // that sync failure from a rejected login. Never resend auth automatically.
      if (current == null ||
          current.profile.deviceId == previousDevice ||
          repo.state.session?.deviceId != current.profile.deviceId) {
        rethrow;
      }
      await repo.accountStatus();
      final observed =
          state.putIfAbsent(
                'automaticAuthSyncErrors',
                () => <String, dynamic>{},
              )
              as Map;
      observed[name] = _code(error);
      await save();
    }
    _check(repo.state.session != null, 'authentication_missing_session');
  }

  Future<void> sync(String name, {bool requireSuccess = true}) async {
    final sequence = repo.lastSyncCompletion?.sequence ?? 0;
    await repo.syncNow(manual: true);
    final completion = repo.lastSyncCompletion;
    _check(
      completion != null && completion.sequence > sequence,
      'sync_completion_missing',
    );
    observedUnresolved =
        !requireSuccess &&
        (completion!.error != null ||
            completion.work.unresolved ||
            repo.state.lastError != null);
    await snapshot(name);
    if (requireSuccess) {
      _check(completion!.error == null, 'sync_completion_error');
      _check(
        !completion.work.unresolved && repo.state.lastError == null,
        'sync_work_unresolved',
      );
    }
  }

  Future<void> snapshot(String name) async {
    final current = sessions.current;
    final outbox = await db.rows('''SELECT operation,state,request_hash,
      CASE WHEN ${cryptoActiveOutboxPredicate('crypto_outbox')} THEN 1 ELSE 0 END AS active
      FROM crypto_outbox ORDER BY sequence''');
    final report = <String, Object?>{
      'stage': name,
      'at': DateTime.now().toUtc().toIso8601String(),
      'httpOperations': calls,
      'hasSession': current != null,
      'scopeCount': repo.state.scopes.length,
      'pendingRecords': repo.state.pendingCount,
      'blockedRecords': repo.state.blockedCount,
      'pendingCommands': repo.state.pendingSyncCommandCount,
      'blockedCommands': repo.state.blockedSyncCommandCount,
      'unresolved': repo.state.hasUnresolvedSyncWork,
      'observationOutcome': observedUnresolved ? 'observed-unresolved' : null,
      'lastError': _code(repo.state.lastError),
      'diagnostic': jsonDecode(
        syncFailureDiagnosticsJson(
          repo.state.syncFailures,
          transfer: repo.state.syncTransfer,
        ),
      ),
      'automaticAuthSyncErrors': state['automaticAuthSyncErrors'] ?? {},
      'cryptoCommands': outbox,
      'recordCounts': await db.rows(
        'SELECT type,count(*) AS count FROM records GROUP BY type',
      ),
      'financeCounts': await db.rows(
        'SELECT type,count(*) AS count FROM finance_records GROUP BY type',
      ),
      'localIdentityPhases': await db.rows(
        'SELECT phase,count(*) AS count FROM crypto_identity_secrets GROUP BY phase',
      ),
      'directoryEvidence': [
        for (final row in await db.rows('''SELECT fingerprint,min_generation,
          head_hash,device_snapshot_hash,identity_epoch_id,trust_state
          FROM crypto_directory_pins'''))
          {
            ...row,
            'identity_epoch_id': await cryptoSha256(
              Uint8List.fromList(
                utf8.encode(row['identity_epoch_id'] as String),
              ),
            ),
          },
      ],
    };
    if (current != null) {
      report['localPhase'] = await (await account()).localPhase();
    }
    await _save(File('${root.path}/$name-summary.json'), report);
  }

  Future<String> identityMaterialHash() async => cryptoSha256(
    Uint8List.fromList(
      utf8.encode(
        jsonEncode(
          await db.rows('''
      SELECT * FROM crypto_identity_secrets ORDER BY partition,device_id'''),
        ),
      ),
    ),
  );

  Future<void> verifyBaseline() async {
    final expectations = [
      ('records', 'taskId', 'title', 'Password flow task'),
      ('finance_records', 'financeAccountId', 'openingBalanceMinor', 4567),
      ('finance_records', 'financeEntryId', 'amountMinor', 1234),
    ];
    for (final (table, key, field, expected) in expectations) {
      final id = state[key];
      _check(id is String, 'baseline_record_id_missing');
      final rows = await db.rows(
        'SELECT * FROM $table WHERE partition=? AND id=?',
        [sessions.current!.profile.partition, id],
      );
      _check(
        rows.length == 1 && rows.single['deleted'] == 0,
        'baseline_record_missing',
      );
      final row = rows.single;
      _check(
        (row['server_revision'] as int) > 0 && row['remote'] != null,
        'baseline_record_not_acknowledged',
      );
      final payload = jsonDecode(row['payload'] as String) as Map;
      _check(payload[field] == expected, 'baseline_payload_mismatch');
      final proofs = await db.rows(
        '''SELECT record_proof_hash,crypto_revision
        FROM crypto_business_records b JOIN crypto_business_addresses a
        ON a.partition=b.partition AND a.scope_id=b.scope_id AND a.domain=b.domain
          AND a.wire_id=b.id
        WHERE a.partition=? AND a.canonical_id=?''',
        [sessions.current!.profile.partition, id],
      );
      _check(
        proofs.length == 1 &&
            (proofs.single['record_proof_hash'] as String).isNotEmpty &&
            (proofs.single['crypto_revision'] as int) > 0,
        'baseline_verified_crypto_record_missing',
      );
    }
    final active = await db.rows(
      '''SELECT count(*) AS count FROM crypto_outbox
      WHERE state IN ('pending','blocked') AND ${cryptoActiveOutboxPredicate()}''',
    );
    _check(
      active.single['count'] == 0 &&
          repo.state.pendingCount == 0 &&
          repo.state.blockedCount == 0 &&
          repo.state.pendingSyncCommandCount == 0 &&
          repo.state.blockedSyncCommandCount == 0,
      'baseline_queue_not_empty',
    );
  }

  Future<void> verifyRepairedContinuation() async {
    final before = await _json(File('${root.path}/held-before-repair.json'));
    final originals = before['rows'] as List?;
    _check(originals != null && originals.length == 6, 'held_baseline_missing');
    final partition = sessions.current!.profile.partition;
    for (final raw in originals!) {
      final original = Map<String, dynamic>.from(raw as Map);
      final rows = await db.rows(
        '''SELECT request_id,operation,state,
        signed_body,request_hash,response FROM crypto_outbox
        WHERE partition=? AND request_id=?''',
        [partition, original['request_id']],
      );
      _check(rows.length == 1, 'original_held_row_missing');
      for (final field in original.keys) {
        _check(
          rows.single[field] == original[field],
          'original_held_evidence_changed',
        );
      }
      final marker = await db.rows('SELECT value FROM local_meta WHERE name=?', [
        'crypto_checkpoint_superseded_v1:$partition:${original['request_id']}',
      ]);
      _check(marker.length == 1, 'checkpoint_supersession_marker_missing');
      final audit = await db.rows(
        '''SELECT 1 FROM crypto_outbox_attempts
        WHERE partition=? AND request_id=? AND event='checkpoint_superseded_locally' ''',
        [partition, original['request_id']],
      );
      _check(audit.length == 1, 'checkpoint_supersession_audit_missing');
    }
    final workflow = await account();
    final access = SessionCryptoAccess(account: workflow);
    final business = CryptoBusinessSession(workflow, access, db);
    var verifiedDomains = 0;
    await access.withVerifiedOperation(() async {
      for (final key in ['householdId', 'organizationId', 'projectId']) {
        final scope = state[key] as String;
        for (final domain in ['content', 'finance']) {
          final read = await access.readContext(scope, domain);
          _check(
            await business.hasReusableCheckpoint(scope, domain, read),
            'final_scope_domain_not_complete',
          );
          verifiedDomains++;
        }
      }
    }, freshBoundary: true);
    _check(
      repo.state.syncFailures.isEmpty && !repo.state.hasUnresolvedSyncWork,
      'final_sync_not_clear',
    );
    _check(
      (await db.rows('SELECT 1 FROM local_meta WHERE name=?', [
        'held_receipt_refresh_v1:$partition',
      ])).isEmpty,
      'refresh_marker_not_finished',
    );
    await _save(File('${root.path}/repaired-continuation-result.json'), {
      'originalHeldRequests': originals.length,
      'immutableHeldEvidencePreserved': true,
      'originalRowsStillBlocked': true,
      'supersessionMarkersAndAudits': originals.length,
      'completeReusableDomains': verifiedDomains,
      'businessValuesAndProofsVerified': true,
      'activeQueuesEmpty': true,
      'currentSyncFailuresEmpty': true,
      'refreshMarkerCleared': true,
    });
  }

  Future<void> setup() async {
    final value = await account();
    if (!recoveryFile.existsSync()) {
      final accountBytes = await value.prepareRecoveryFile();
      final vault = LocalVaultKey.generate();
      final local = Uint8List.fromList(utf8.encode(vault.encode()));
      final combined = RecoveryBundleCodec.wrap(local, accountBytes);
      try {
        await recoveryFile.writeAsBytes(combined, flush: true);
      } finally {
        accountBytes.fillRange(0, accountBytes.length, 0);
        local.fillRange(0, local.length, 0);
        vault.bytes.fillRange(0, vault.bytes.length, 0);
        combined.fillRange(0, combined.length, 0);
      }
    }
    final combined = await recoveryFile.readAsBytes();
    try {
      if (!await value.hasSavedSetup() && await value.localPhase() != 'ready') {
        await value.confirmSavedRecoveryFile(combined);
      }
      await value.resumeSavedSetup();
      _check(await value.localPhase() == 'ready', 'account_setup_not_ready');
      final ready = AccountProtectionReady(value);
      try {
        _check(await ready.completeFreshSetup(), 'fresh_setup_incomplete');
        _check(
          await ready.cachedCompletion() != null,
          'fresh_setup_completion_missing',
        );
      } finally {
        ready.close();
      }
      await value.finishSavedSetup();
    } finally {
      combined.fillRange(0, combined.length, 0);
    }
  }

  Future<void> createScopes() async {
    for (final scope in [
      ('household', 'Dom', SharedScopeKind.household, null),
      ('organization', 'TriparNA', SharedScopeKind.organization, null),
      ('project', 'Projekt', SharedScopeKind.project, 'organization'),
    ]) {
      final (key, name, kind, parent) = scope;
      final id = state.putIfAbsent('${key}Id', crypto.randomId) as String;
      final request =
          state.putIfAbsent('${key}Request', crypto.randomId) as String;
      await save();
      await step('create_$key', () async {
        final created = await repo.createScope(
          name,
          kind: kind,
          id: id,
          requestId: request,
          parentScopeId: parent == null ? null : state['${parent}Id'] as String,
        );
        _check(created == id, 'created_scope_identity_mismatch');
      });
    }
  }

  Future<void> reviewPendingScopes(String phase) async {
    final workflow = await account();
    final ready = AccountProtectionReady(workflow);
    late final List<Map<String, dynamic>> actions;
    try {
      actions = await ready.pendingScopeActions();
    } finally {
      ready.close();
    }
    _check(actions.isNotEmpty, 'scope_review_actions_missing');
    final manager = ScopeCryptoManager(SessionCryptoAccess(account: workflow));
    final summaries =
        state.putIfAbsent('scopeReviewSummaries', () => <String, dynamic>{})
            as Map;
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index], scope = action['scopeId'] as String;
      _check(
        action['canManage'] == true,
        'scope_review_management_unavailable',
      );
      await step('$phase:$scope', () async {
        // First route is exact ScopeRecoveryPage._restore. The separate local
        // route models pressing _reviewLocal after a failed restore, retaining
        // the old review. No extra candidate-key hydration is inserted here.
        final localReview = phase.endsWith('_local');
        late final ScopeRotationReview review;
        List<Map<String, dynamic>>? members;
        if (localReview) {
          review = await manager.reviewRotation(scope);
        } else {
          final pending = await manager.pendingRotationReviews(scope);
          _check(pending.isNotEmpty, 'scope_saved_review_missing');
          review = pending.first;
          members = await manager.proposedMembers(review);
        }
        var count = 0, readable = 0;
        String? after;
        final digests = <String>[];
        while (true) {
          final previews = await manager.previewRotation(
            review,
            afterId: after,
          );
          try {
            if (previews.isEmpty) break;
            for (final preview in previews) {
              count++;
              if (preview.plaintext != null) {
                readable++;
                digests.add(await cryptoSha256(preview.plaintext!));
              }
            }
            after = previews.last.id;
          } finally {
            for (final preview in previews) {
              preview.dispose();
            }
          }
          _check(count <= 1000, 'scope_preview_fixture_bound');
        }
        final expected = review.domains.values.fold<int>(
          0,
          (total, domain) => total + (domain as Map)['count'] as int,
        );
        _check(count == expected, 'scope_preview_count_mismatch');
        final summary = <String, Object?>{
          'scopeOrdinal': index,
          'reviewSource': localReview ? 'reviewLocal' : 'restoreRetained',
          'historyBasis': review.historyBasis,
          'sourceHeadHash': review.sourceHeadHash,
          'domainCounts': {
            for (final domain in review.domains.keys)
              domain as String: (review.domains[domain] as Map)['count'],
          },
          'previewedRecords': count,
          'readableRecords': readable,
          'plaintextHashes': digests,
          'acceptedCandidateHistory': true,
        };
        summaries['$phase:$scope'] = summary;
        await save();
        // This synthetic user explicitly accepts the actually previewed local
        // candidate history. Production current-head/policy/receipt guards run.
        final active = await manager.confirmRotation(
          review,
          acceptedCandidateHistory: true,
          members: members,
        );
        summary['confirmedHeadHash'] = active.headHash;
        await save();
      });
    }
  }

  Future<void> verifyHeldCheckpointProbe() async {
    _check(readOnlyProbe, 'read_only_probe_transport_required');
    final beforeRows = await db.rows('''SELECT * FROM crypto_outbox
      WHERE operation='crypto2.domain.checkpoint' AND state='blocked'
        AND ${cryptoActiveOutboxPredicate()} ORDER BY sequence''');
    _check(
      beforeRows.isNotEmpty && beforeRows.length <= 20,
      'probe_held_inventory_bound',
    );
    final rowsHash = await cryptoSha256(
      Uint8List.fromList(utf8.encode(jsonEncode(beforeRows))),
    );
    final identityHash = await identityMaterialHash();
    final secretHash = await cryptoSha256(await secrets.file.readAsBytes());
    final accountValue = await account();
    final results = <Map<String, Object?>>[];
    for (final row in beforeRows) {
      final proof = Map<String, dynamic>.from(
        jsonDecode(row['signed_body'] as String) as Map,
      );
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final payload = command['payload'] as Map;
      final result = <String, Object?>{
        'requestHash': row['request_hash'],
        'domain': payload['domain'],
        'sequence': payload['expectedSequence'],
        'recordCount': payload['recordCount'],
        'authorDeviceMatchesCurrent':
            command['deviceId'] == accountValue.deviceId,
      };
      final access = SessionCryptoAccess(account: accountValue);
      try {
        await access.withVerifiedOperation(() async {
          final own = await accountValue.directory.requireFresh();
          final current = await access.currentHead(
            payload['scopeId'] as String,
            online: true,
          );
          result['oldDirectoryMatchesCurrent'] =
              payload['authorDirectoryHeadHash'] == own.headHash;
          result['oldScopeHeadMatchesCurrent'] =
              payload['membershipHeadHash'] == current.headHash;
          result['verifierEntered'] = true;
          final verified = await access.verifyDomainCheckpoint(
            proof,
            onlineAuthorDirectory: true,
          );
          result['verified'] = true;
          result['historyBasis'] = verified.historyBasis;
        }, freshBoundary: true);
      } catch (error) {
        result['verified'] = false;
        result['reason'] = _code(error);
      }
      results.add(result);
      await _save(File('${root.path}/held-checkpoint-verifier-probe.json'), {
        'readOnlyHttp': true,
        'results': results,
        'httpOperations': calls,
      });
    }
    final afterRows = await db.rows('''SELECT * FROM crypto_outbox
      WHERE operation='crypto2.domain.checkpoint' AND state='blocked'
        AND ${cryptoActiveOutboxPredicate()} ORDER BY sequence''');
    _check(
      rowsHash ==
          await cryptoSha256(
            Uint8List.fromList(utf8.encode(jsonEncode(afterRows))),
          ),
      'probe_held_rows_changed',
    );
    _check(
      identityHash == await identityMaterialHash(),
      'probe_identity_key_material_changed',
    );
    _check(
      secretHash == await cryptoSha256(await secrets.file.readAsBytes()),
      'probe_secure_store_changed',
    );
    observedUnresolved = results.any((value) => value['verified'] != true);
    await _save(File('${root.path}/held-checkpoint-verifier-probe.json'), {
      'readOnlyHttp': true,
      'heldRowsUnchanged': true,
      'identityKeyMaterialUnchanged': true,
      'secureStoreUnchanged': true,
      'results': results,
      'httpOperations': calls,
    });
  }

  Future<void> run(String phase) async {
    switch (phase) {
      case 'verify_held_checkpoint_probe':
        await verifyHeldCheckpointProbe();
      case 'enroll':
        _check(sessions.current == null, 'enrollment_already_has_session');
        await authenticateAndObserve(
          phase,
          () => repo.enroll(
            serverUrl: url,
            code: (fixture['bootstrap'] as Map)['code'] as String,
            username: owner['username'] as String,
            password: initialPassword,
            name: owner['displayName'] as String,
            allowLocalHttp: true,
            deviceName: 'Password flow local owner',
          ),
        );
        _check(repo.state.session != null, 'enrollment_missing_session');
      case 'email_request':
        await repo.requestEmailVerification(
          email: email,
          password: initialPassword,
        );
      case 'email_confirm':
        final token = (await File(
          '${root.path}/email-code.txt',
        ).readAsString()).trim();
        final status = await repo.confirmEmailVerification(token);
        _check(status.emailVerified, 'email_unverified');
      case 'setup':
        await setup();
      case 'accept_content_policy':
        final policy = await repo.sharedContentPolicy();
        if (!policy.accepted) await repo.acceptSharedContentPolicy(policy);
        _check(
          (await repo.sharedContentPolicy()).accepted,
          'content_policy_not_accepted',
        );
      case 'scopes':
        await createScopes();
      case 'records':
        await step('create_task', () async {
          state['taskId'] = await repo.createTask(
            scopeId: state['householdId'] as String,
            title: 'Password flow task',
          );
        });
        await step('create_finance_account', () async {
          final scope = state['organizationId'] as String;
          await repo.refreshFinancePolicy(scope);
          state['financeAccountId'] = await repo.createFinanceAccount(
            scopeId: scope,
            name: 'Flow account',
            currency: 'EUR',
            openingBalanceMinor: 4567,
          );
        });
      case 'finance_entry':
        await step('create_finance_entry', () async {
          state['financeEntryId'] = await repo.createFinanceEntry(
            scopeId: state['organizationId'] as String,
            accountId: state['financeAccountId'] as String,
            kind: FinanceEntryKind.expense,
            amountMinor: 1234,
            currency: 'EUR',
            title: 'Password flow expense',
            occurredAt: DateTime.utc(2026, 11, 2),
          );
        });
      case 'password_change':
        final before = sessions.current!;
        final keys = await secrets.file.readAsString();
        final identityHash = await identityMaterialHash();
        await repo.changeAccountPassword(
          currentPassword: initialPassword,
          newPassword: changedPassword,
        );
        _check(identical(before, sessions.current), 'password_changed_session');
        _check(
          keys == await secrets.file.readAsString(),
          'password_changed_keys',
        );
        _check(
          identityHash == await identityMaterialHash(),
          'password_changed_device_key_material',
        );
        state['currentPassword'] = changedPassword;
      case 'signout_login':
        await step('signout', () async {
          _check(await repo.signOut(), 'signout_not_confirmed');
        });
        await authenticateAndObserve(
          phase,
          () => repo.login(
            serverUrl: url,
            username: owner['username'] as String,
            password: changedPassword,
            allowLocalHttp: true,
            deviceName: 'Password flow same installation',
          ),
        );
        _check(repo.state.session != null, 'relogin_missing_session');
      case 'rebind_after_login':
        await (await account()).rebindLocalDevice();
        _check(
          await (await account()).localPhase() == 'ready',
          'rebind_not_ready',
        );
      case 'review_rebind_scopes':
      case 'review_recovered_scopes':
      case 'review_rebind_local':
      case 'review_recovered_local':
        await reviewPendingScopes(phase);
      case 'protection_after_rebind':
      case 'protection_continue':
        final ready = AccountProtectionReady(await account());
        try {
          await ready.complete();
        } finally {
          ready.close();
        }
      case 'reset_request':
        await repo.requestSignedInPasswordReset();
      case 'reset_confirm':
        final token = (await File(
          '${root.path}/reset-code.txt',
        ).readAsString()).trim();
        await repo.confirmSignedInPasswordReset(
          token: token,
          password: resetPassword,
        );
        state['currentPassword'] = resetPassword;
        _check(repo.state.sessionInvalid, 'reset_session_not_invalidated');
      case 'reset_login':
        await authenticateAndObserve(
          phase,
          () => repo.login(
            serverUrl: url,
            username: owner['username'] as String,
            password: resetPassword,
            allowLocalHttp: true,
            deviceName: 'Password flow after email reset',
          ),
        );
        _check(repo.state.session != null, 'reset_login_missing_session');
      case 'recover_file':
        final bytes = await recoveryFile.readAsBytes();
        try {
          await step('account_file_recovery', () async {
            await (await account()).recover(bytes);
            _check(
              await (await account()).localPhase() == 'ready',
              'file_recovery_not_ready',
            );
          });
          // Matches AccountCryptoWizard._import(recover:true), after account
          // recovery has committed. Retrying hydration never repeats recoverEpoch.
          await step('scope_file_recovery', () async {
            await (await account()).restoreScopesFromFile(bytes);
          });
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      case 'sync_after_login':
      case 'sync_before_rebind_protection':
        await sync(phase, requireSuccess: false);
      default:
        _check(
          const {
            'sync_baseline',
            'sync_records',
            'sync_after_change',
            'sync_after_rebind',
            'sync_after_recovery',
          }.contains(phase),
          'unknown_phase',
        );
        await sync(phase);
        if (phase != 'sync_records') await verifyBaseline();
        if (phase == 'sync_after_rebind') await verifyRepairedContinuation();
    }
    await save();
    await snapshot(phase);
  }

  Future<void> close() async {
    closed = true;
    await repo.close();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A test binding otherwise replaces HttpClient with canned HTTP 400 replies.
  // This opt-in fixture is loopback-validated before constructing the real client.
  HttpOverrides.global = null;
  final path = Platform.environment['JIVIE_PASSWORD_HTTP_FIXTURE'];
  final phase = Platform.environment['JIVIE_PASSWORD_HTTP_PHASE'] ?? 'enroll';
  test(
    'real HTTP persisted password flow: $phase',
    () async {
      final fixtureFile = File(path!);
      final fixture = await _json(fixtureFile);
      _check(
        fixture['synthetic'] == true &&
            fixture['purpose'] == 'password-flow-20261102' &&
            fixture['serverUrl'] == 'http://127.0.0.1:57901' &&
            fixtureFile.parent.path.endsWith(
              'build/qa/password-flow-http-20261102',
            ),
        'dedicated_synthetic_loopback_fixture_required',
      );
      final root = fixtureFile.parent;
      final ledgerFile = File('${root.path}/ledger-private.json');
      final state = await _json(ledgerFile);
      final phases =
          state.putIfAbsent('phases', () => <String, dynamic>{}) as Map;
      final entry = Map<String, dynamic>.from(phases[phase] as Map? ?? {});
      _check(
        entry['passed'] != true && entry['observed'] != true,
        'completed_phase_must_not_repeat',
      );
      final attempt = (entry['attempts'] as int? ?? 0) + 1;
      _check(attempt <= 3, 'phase_attempt_limit_reached');
      entry.addAll({
        'attempts': attempt,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      });
      phases[phase] = entry;
      await _save(ledgerFile, state);
      final flow = _Flow(
        root,
        fixture,
        state,
        readOnlyProbe: phase == 'verify_held_checkpoint_probe',
      );
      await flow.open();
      try {
        await flow.run(phase);
        final outcome = flow.observedUnresolved
            ? 'observed-unresolved'
            : 'passed';
        entry['outcome'] = outcome;
        if (flow.observedUnresolved) {
          entry['observed'] = true;
        } else {
          entry['passed'] = true;
        }
        entry['finishedAt'] = DateTime.now().toUtc().toIso8601String();
        await flow.save();
        // Only a finite stage name/status/count is emitted; private details stay
        // beside the preserved SQL/key fixture for investigation, not console logs.
        debugPrint(
          'HTTP_FLOW $phase ${outcome.toUpperCase()} attempt=$attempt calls=${flow.calls.values.fold(0, (a, b) => a + b)}',
        );
      } catch (error, stack) {
        entry['error'] = _code(error);
        entry['finishedAt'] = DateTime.now().toUtc().toIso8601String();
        entry['stack'] = stack.toString().split('\n').take(12).toList();
        await flow.save();
        try {
          await flow.snapshot('$phase-failed-$attempt');
        } catch (snapshotError) {
          entry['snapshotError'] = _code(snapshotError);
          await flow.save();
        }
        fail('HTTP_FLOW $phase FAILED attempt=$attempt reason=${_code(error)}');
      } finally {
        await flow.close();
      }
    },
    skip: path == null ? 'Dedicated loopback fixture is opt-in.' : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
