import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/account_deletion_store.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_active_outbox.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/inbox_projection.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/organizer_projections.dart';
import 'package:kanban/organizer/platform/remote_push/system_push_display.dart';

// Opt-in isolated clone of the two existing October 28 accounts. Enrollment,
// sharing and FILE recovery are NOT replayed. SQL, signatures, PHP HTTP and the
// production router are real. Only secure-storage persistence and the native
// provider envelope use synthetic local seams; this does not prove FCM/iOS.
const _policy = 'schedulerAndTaskAssignees';
const _title = 'SYNTHETIC TWO RECIPIENT REMINDER 20261105';
const _notes = 'Both existing accounts must decrypt the exact same task.';

void _check(bool ok, String code) {
  if (!ok) throw StateError(code);
}

Future<Map<String, dynamic>> _read(File file) async => file.existsSync()
    ? Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map)
    : {};

Future<void> _save(File file, Object value) async {
  final next = File('${file.path}.next');
  await next.writeAsString(jsonEncode(value), flush: true);
  await next.rename(file.path);
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

// The old direct-workflow fixture used a noncanonical URL in its durable SQL
// namespace. Preserve that namespace exactly while giving the real network
// coordinator its ordinary canonical URL. No production guard is overridden.
class _RetainedWorkflowProfile extends AccountSession {
  _RetainedWorkflowProfile(AccountSession original)
    : retainedPartition = original.partition,
      super(
        serverUrl: normalizeCollaborationServer(
          original.serverUrl,
          allowLocalHttp: true,
        ),
        serverId: original.serverId,
        accountId: original.accountId,
        userId: original.userId,
        username: original.username,
        displayName: original.displayName,
        deviceId: original.deviceId,
        expiresAt: original.expiresAt,
        allowLocalHttp: true,
      );
  final String retainedPartition;
  @override
  String get partition => retainedPartition;
}

class _Sessions implements DeviceSessionStore {
  _Sessions(String url, Map wire) {
    final user = wire['user'] as Map, device = wire['device'] as Map;
    current = DeviceSession(
      _RetainedWorkflowProfile(
        AccountSession(
          serverUrl: url,
          serverId: wire['serverId'],
          accountId: user['accountId'],
          userId: user['id'],
          username: user['username'],
          displayName: user['displayName'],
          deviceId: device['id'],
          allowLocalHttp: true,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            device['expiresAt'] * 1000,
          ),
        ),
      ),
      wire['token'],
    );
  }
  late DeviceSession current;
  @override
  Future<DeviceSession?> read() async => current;
  @override
  Future<void> write(DeviceSession value) async {
    _check(
      value.profile.accountId == current.profile.accountId &&
          value.profile.deviceId == current.profile.deviceId &&
          value.profile.partition == current.profile.partition,
      'existing_identity_must_remain',
    );
    current = value;
  }

  @override
  Future<void> clear() async => throw StateError('session_clear_forbidden');
}

class _Invitations implements PendingInvitationStore {
  @override
  Future<PendingInvitation?> read() async => null;
  @override
  Future<void> write(PendingInvitation? value) async =>
      _check(value == null, 'new_invitation_forbidden');
}

class _Deletions implements AccountDeletionStore {
  @override
  Future<List<PendingAccountDeletion>> read() async => [];
  @override
  Future<void> write(List<PendingAccountDeletion> value) async =>
      _check(value.isEmpty, 'account_deletion_forbidden');
}

class _Wire extends HttpCollaborationTransport {
  final operations = <String>[];
  bool readOnlyReview = false;
  static const reviewReads = {
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
    'crypto2.records.pull',
    'crypto2.receipt.get',
  };
  Future<Map<String, dynamic>> _observe(
    String operation,
    Future<Map<String, dynamic>> Function() send,
  ) async {
    if (Platform.environment['JIVIE_RECIPIENTS_HTTP_PHASE'] ==
        'open_both_push_references') {
      _check(
        !const {
          'push.register',
          'push.unregister',
          'crypto2.reminders.put',
          'crypto2.reminders.cancel',
          'crypto2.records.batch',
          'crypto2.scope.headPut',
          'crypto2.scope.activate',
        }.contains(operation),
        'open_only_write_or_resend_forbidden',
      );
    }
    _check(
      !readOnlyReview || reviewReads.contains(operation),
      'preview_remote_mutation_forbidden',
    );
    _check(
      !const {
        'auth.login',
        'auth.register',
        'crypto2.account.initialize',
        'crypto2.account.recoveryStart',
        'crypto2.account.recoverEpoch',
        'crypto2.account.rotateRoot',
      }.contains(operation),
      'setup_replay_forbidden',
    );
    operations.add(operation);
    return send();
  }

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) => _observe(
    operation,
    () => super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    ),
  );
  @override
  Future<Map<String, dynamic>> callWithAttemptGate({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
    required CollaborationAttemptGate gate,
  }) => _observe(
    operation,
    () => super.callWithAttemptGate(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
      gate: gate,
    ),
  );
}

class _Actor {
  _Actor(this.name, this.root, this.fixture);
  final String name;
  final Directory root;
  final Map<String, dynamic> fixture;
  final wire = _Wire();
  late final CollaborationDatabase db;
  late final _Sessions sessions;
  late final CollaborationRepository repo;
  Future<void> open() async {
    sessions = _Sessions(fixture['serverUrl'], fixture['actors'][name] as Map);
    db = CollaborationDatabase(
      NativeDatabase(File('${root.path}/$name.sqlite')),
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
  }

  Future<void> sync() async {
    final before = repo.lastSyncCompletion?.sequence ?? 0;
    final checkBefore = repo.state.lastSuccessfulChangeCheckAt;
    await repo.syncNow(manual: true);
    final completed = repo.lastSyncCompletion;
    final checked = repo.state.lastSuccessfulChangeCheckAt;
    _check(
      (completed != null && completed.sequence > before) ||
          (checked != null &&
              (checkBefore == null || checked.isAfter(checkBefore))),
      'fresh_completion_or_successful_check_required',
    );
    await assertClear();
  }

  Future<void> assertClear() async {
    _check(
      repo.state.lastError == null &&
          !repo.state.hasUnresolvedSyncWork &&
          repo.state.pendingCount == 0 &&
          repo.state.blockedCount == 0 &&
          repo.state.pendingSyncCommandCount == 0 &&
          repo.state.blockedSyncCommandCount == 0,
      'real_http_sync_not_clear',
    );
    final pending = await db.rows(
      '''SELECT COUNT(*) AS n FROM crypto_outbox
      WHERE partition=? AND ${cryptoActiveOutboxPredicate()}
      AND state IN ('pending','blocked')''',
      [sessions.current.profile.partition],
    );
    _check(pending.single['n'] == 0, 'active_crypto_commands_remain');
  }

  Future<void> acceptRulesIfRequired() async {
    final policy = await repo.sharedContentPolicy();
    if (!policy.accepted) await repo.acceptSharedContentPolicy(policy);
  }

  Future<void> protectExactRetainedScope() async {
    final scope = fixture['scopeId'] as String;
    final partition = sessions.current.profile.partition;
    final evidence = <String, Object?>{
      'scopeCount': 1,
      'membershipChangePermitted': false,
      'unseenHistoryAccepted': false,
      'stage': 'read_only_preview',
    };
    final proofFile = File('${root.path}/scope-protection-r5-evidence.json');
    final started = wire.operations.length;
    await _save(proofFile, evidence);
    final knownRows = await db.rows(
      '''SELECT id,domain,type,crypto_revision,
      record_proof_hash,deleted,raw_payload FROM crypto_business_records
      WHERE partition=? AND scope_id=?''',
      [partition, scope],
    );
    final known = {for (final row in knownRows) row['id'] as String: row};
    _check(
      known.isNotEmpty && known.length <= 100,
      'bounded_preexisting_history_required',
    );
    final beforeHeads = await db.rows(
      '''SELECT head_hash FROM crypto_scope_heads
      WHERE partition=? AND scope_id=? ORDER BY epoch DESC LIMIT 1''',
      [partition, scope],
    );
    final held = await db.rows(
      '''SELECT request_id,signed_body,request_hash,
      response,state FROM crypto_outbox WHERE partition=? AND state='blocked'
      ORDER BY sequence''',
      [partition],
    );
    List<Map<String, dynamic>> membership(List<Map<String, dynamic>> rows) =>
        [
          for (final row in rows)
            {
              for (final field in const [
                'accountId',
                'role',
                'financeRole',
                'manageKeys',
              ])
                field: row[field],
            },
        ]..sort(
          (a, b) =>
              (a['accountId'] as String).compareTo(b['accountId'] as String),
        );
    wire.readOnlyReview = true;
    try {
      final account = await repo.connectedCryptoAccount();
      final access = SessionCryptoAccess(account: account);
      final head = await access.currentHead(scope, online: true);
      _check(
        head.scopeId == scope &&
            beforeHeads.length == 1 &&
            beforeHeads.single['head_hash'] == head.headHash,
        'selected_scope_head_must_already_be_known',
      );
      final members = membership(head.members);
      final ids = members.map((m) => m['accountId']).toSet();
      _check(
        members.length == 2 &&
            ids.contains(sessions.current.profile.accountId) &&
            ids.contains(fixture['actors']['recipient']['user']['accountId']) &&
            head.member(sessions.current.profile.accountId)['role'] ==
                'owner' &&
            head.member(sessions.current.profile.accountId)['manageKeys'] ==
                true,
        'exact_existing_owner_and_other_membership_required',
      );
      final manager = ScopeCryptoManager(access);
      final review = await manager.reviewRotation(scope);
      _check(
        review.sourceHeadHash == head.headHash,
        'preview_source_head_changed',
      );
      final reviewedRows = await db.rows(
        '''SELECT record_id,domain,wire FROM
        crypto_scope_review_records WHERE partition=? AND scope_id=? AND
        review_id=? ORDER BY record_id''',
        [partition, scope, review.id],
      );
      final codec = CryptoRecordProofCodec(account.directory.reducer.crypto);
      final reviewedIdentities = <String, Object?>{};
      _check(
        reviewedRows.length == known.length,
        'preview_inventory_must_equal_preexisting_history',
      );
      for (final row in reviewedRows) {
        final old = known[row['record_id']];
        final wireRecord = jsonDecode(row['wire'] as String) as Map;
        final proof = Map<String, dynamic>.from(
          wireRecord['authorization']['recordProof'] as Map,
        );
        final body =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        _check(
          old != null &&
              old['domain'] == row['domain'] &&
              old['crypto_revision'] == wireRecord['revision'] &&
              old['record_proof_hash'] == await codec.digest(proof) &&
              body['scopeId'] == scope &&
              body['id'] == old['id'] &&
              body['type'] == old['type'] &&
              body['deleted'] == (old['deleted'] == 1),
          'preview_unseen_or_changed_record_forbidden',
        );
        reviewedIdentities[row['record_id'] as String] =
            body['metadata']['identity'];
      }
      var count = 0;
      String? after;
      while (true) {
        final page = await manager.previewRotation(review, afterId: after);
        try {
          if (page.isEmpty) break;
          for (final item in page) {
            final old = known[item.id];
            _check(old != null, 'unseen_preview_record_forbidden');
            if (old!['deleted'] == 1) {
              _check(item.plaintext == null, 'deleted_preview_mismatch');
            } else {
              _check(item.plaintext != null, 'known_record_not_decrypted');
              final plain = jsonDecode(utf8.decode(item.plaintext!)) as Map;
              _check(
                plain['format'] == 2 &&
                    CryptoBusinessJson.canonical(plain['identity']) ==
                        CryptoBusinessJson.canonical(
                          reviewedIdentities[item.id],
                        ) &&
                    CryptoBusinessJson.canonical(plain['payload']) ==
                        CryptoBusinessJson.canonical(
                          jsonDecode(old['raw_payload'] as String),
                        ),
                'known_preview_plaintext_mismatch',
              );
            }
            count++;
          }
          after = page.last.id;
        } finally {
          for (final item in page) {
            item.dispose();
          }
        }
        _check(count <= known.length, 'preview_inventory_bound');
      }
      final expected = review.domains.values.fold<int>(
        0,
        (sum, value) => sum + (value as Map)['count'] as int,
      );
      _check(
        count == known.length && count == expected,
        'all_known_history_must_be_previewed',
      );
      evidence.addAll({
        'historyBasis': review.historyBasis,
        'previewedKnownRecords': count,
        'allProofHashesAndPlaintextsMatch': true,
        'readOnlyPreviewHttpCount': wire.operations.length - started,
        'stage': 'verified_known_history_before_confirmation',
      });
      await _save(proofFile, evidence);
      wire.readOnlyReview = false;
      // This protocol flag acknowledges only the exact previously known
      // history fully verified/decrypted above, never an unseen candidate.
      final active = await manager.confirmRotation(
        review,
        acceptedCandidateHistory: true,
        members: head.members.map((m) => Map<String, dynamic>.from(m)).toList(),
      );
      _check(
        active.scopeId == scope &&
            active.epoch == head.epoch + 1 &&
            active.body['previousHeadHash'] == head.headHash &&
            CryptoBusinessJson.canonical(membership(active.members)) ==
                CryptoBusinessJson.canonical(members),
        'rotation_changed_selected_scope_membership',
      );
      final retained = await db.rows(
        '''SELECT request_id,signed_body,request_hash,
        response,state FROM crypto_outbox WHERE partition=? AND state='blocked'
        ORDER BY sequence''',
        [partition],
      );
      _check(
        jsonEncode(retained) == jsonEncode(held),
        'rotation_must_preserve_original_held_evidence',
      );
      evidence.addAll({
        'stage': 'confirmed',
        'sameMembership': true,
        'previousEpoch': head.epoch,
        'newEpoch': active.epoch,
        'heldRowsPreserved': true,
        'totalProtectionHttpCount': wire.operations.length - started,
      });
      await _save(proofFile, evidence);
    } catch (error) {
      evidence['error'] = _code(error);
      await _save(proofFile, evidence);
      rethrow;
    } finally {
      wire.readOnlyReview = false;
    }
  }

  Future<Map<String, Object?>> evidence() async {
    final counts = <String, int>{};
    for (final op in wire.operations) {
      counts.update(op, (n) => n + 1, ifAbsent: () => 1);
    }
    return {
      'httpCounts': counts,
      'httpSequence': wire.operations,
      'lastError': _code(repo.state.lastError),
      'pendingRecords': repo.state.pendingCount,
      'blockedRecords': repo.state.blockedCount,
      'pendingCommands': repo.state.pendingSyncCommandCount,
      'blockedCommands': repo.state.blockedSyncCommandCount,
      'unresolved': repo.state.hasUnresolvedSyncWork,
      'diagnostics': jsonDecode(
        syncFailureDiagnosticsJson(
          repo.state.syncFailures,
          transfer: repo.state.syncTransfer,
        ),
      ),
    };
  }

  Future<bool> assertTask(
    String task, {
    bool requireFutureDeadline = true,
  }) async {
    final rows = await db.rows(
      '''SELECT payload,server_revision,remote,deleted
      FROM records WHERE partition=? AND scope_id=? AND id=? AND type='task' ''',
      [sessions.current.profile.partition, fixture['scopeId'], task],
    );
    _check(
      rows.length == 1 &&
          rows.single['deleted'] == 0 &&
          rows.single['remote'] != null &&
          (rows.single['server_revision'] as int) > 0,
      'exact_task_projection_missing',
    );
    final value = jsonDecode(rows.single['payload'] as String) as Map;
    _check(
      value['title'] == _title &&
          value['notes'] == _notes &&
          (value['assigneeAccountIds'] as List).contains(
            fixture['actors']['recipient']['user']['accountId'],
          ),
      'exact_task_plaintext_mismatch',
    );
    _check(value['dueAt'] is String, 'exact_task_deadline_required');
    final future = DateTime.parse(
      value['dueAt'] as String,
    ).toUtc().isAfter(DateTime.now().toUtc());
    _check(
      !requireFutureDeadline || future,
      'exact_task_deadline_must_still_be_future',
    );
    return future;
  }

  Future<void> close() async {
    await repo.close();
    await db.close();
  }
}

Future<void> _finishRetainedPreparation({
  required List<_Actor> actors,
  required Directory root,
  required Map<String, dynamic> fixture,
  required Map<String, dynamic> ledger,
  required File ledgerFile,
  required Map<String, Object?> result,
  required Future<void> Function(String, Future<void> Function()) step,
}) async {
  final sender = actors[0], recipient = actors[1];
  _check(
    ledger['taskId'] is String &&
        ledger['reminderId'] == null &&
        ledger['phases']['prepare_both_recipients']['attempts'] == 5 &&
        ledger['phases']['prepare_both_recipients']['passed'] == false,
    'exact_partial_task_setup_required',
  );
  final protection = await _read(
    File('${root.path}/scope-protection-r5-evidence.json'),
  );
  _check(
    protection['stage'] == 'confirmed' &&
        protection['sameMembership'] == true &&
        protection['newEpoch'] == 3 &&
        protection['allProofHashesAndPlaintextsMatch'] == true,
    'completed_protection_must_not_repeat',
  );
  await step('resume_existing_task', () async {
    await sender.sync();
    await recipient.sync();
    for (final actor in actors) {
      await actor.assertTask(ledger['taskId'] as String);
    }
  });
  await step('register_and_save_absolute_once', () async {
    for (final actor in actors) {
      final session = actor.sessions.current;
      final response = await actor.wire.call(
        serverUrl: fixture['serverUrl'],
        operation: 'push.register',
        params: {
          'token': 'synthetic-reminder-recipients-${actor.name}-20261105',
          'platform': 'android',
          'language': 'en',
          'displayVersion': 2,
          'projectId': 'synthetic-reminders',
          'expectedRevision': 0,
        },
        token: session.token,
        allowLocalHttp: true,
      );
      _check(
        (response['registration'] as Map)['registered'] == true,
        'synthetic_push_registration_required',
      );
    }
    final due = DateTime.now().toUtc().add(const Duration(seconds: 60));
    ledger['dueAt'] = due.toIso8601String();
    ledger['reminderId'] = await sender.repo.putReminder(
      scopeId: fixture['scopeId'],
      targetType: 'task',
      targetId: ledger['taskId'],
      remindAt: due,
      recipientPolicy: _policy,
    );
    await _save(ledgerFile, ledger);
    await sender.sync();
    final own = sender.repo.state.scheduledReminders
        .where((r) => r.id == ledger['reminderId'])
        .toList();
    _check(
      own.length == 1 &&
          own.single.state == 'pending' &&
          own.single.revision == 1 &&
          own.single.syncState == 'synced' &&
          own.single.recipientPolicy == _policy,
      'one_absolute_recipient_reminder_must_be_confirmed',
    );
    ledger['r6PreparationConfirmed'] = true;
    await _save(ledgerFile, ledger);
    result['reminderConfirmed'] = true;
    result['dueAt'] = ledger['dueAt'];
  });
  await step('natural_due_wait', () async {
    final due = DateTime.parse(ledger['dueAt'] as String).toUtc();
    while (DateTime.now().toUtc().isBefore(due)) {
      final remaining = due.difference(DateTime.now().toUtc());
      await Future<void>.delayed(
        remaining > const Duration(seconds: 15)
            ? const Duration(seconds: 15)
            : remaining,
      );
    }
    for (final actor in actors) {
      await actor.assertTask(ledger['taskId'] as String);
    }
  });
  await step('due_worker_and_provider_capture', () async {
    final file = File('${root.path}/renewal-20261106.json');
    final authorization = await _read(file);
    _check(
      authorization['serviceSteps'] == null &&
          authorization['oneEndToEndThirdTestAuthorized'] == true,
      'worker_may_run_once_inside_r6_only',
    );
    final entry = <String, Object?>{
      'attempt': 1,
      'status': 'running',
      'startedAt': DateTime.now().toUtc().toIso8601String(),
    };
    authorization['serviceSteps'] = {'natural_due_capture': entry};
    await _save(file, authorization);
    final worker = await Process.run('docker', [
      'exec',
      'jivie-reminder-recipients-renewed-20261106',
      'php',
      '/diagnostic-private/run_due_and_capture.php',
    ]);
    await File(
      '${root.path}/worker-r6-service.log',
    ).writeAsString('${worker.stdout}${worker.stderr}', flush: true);
    entry['exitCode'] = worker.exitCode;
    entry['status'] = worker.exitCode == 0 ? 'passed' : 'failed';
    entry['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    await _save(file, authorization);
    _check(worker.exitCode == 0, 'embedded_due_provider_worker_failed');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final fixturePath = Platform.environment['JIVIE_RECIPIENTS_HTTP_FIXTURE'];
  final phase = Platform.environment['JIVIE_RECIPIENTS_HTTP_PHASE'];
  test(
    'task reminder two existing recipients real HTTP $phase',
    () async {
      final file = File(fixturePath!);
      final fixture = await _read(file), root = file.parent;
      _check(
        fixture['synthetic'] == true &&
            fixture['purpose'] == 'task-reminder-recipients-20261105' &&
            fixture['serverUrl'] == 'http://127.0.0.1:57881' &&
            root.absolute.path ==
                '${Directory.current.path}/build/qa/reminder-recipients-http-20261105/private',
        'dedicated_two_account_clone_required',
      );
      _check(
        const {
          'prepare_both_recipients',
          'open_both_push_references',
          'complete_retained_scenario',
        }.contains(phase),
        'unknown_new_scenario_phase',
      );
      final ledgerFile = File('${root.path}/scenario-ledger-private.json');
      final ledger = await _read(ledgerFile);
      final phases = Map<String, dynamic>.from(ledger['phases'] as Map? ?? {});
      final previous = Map<String, dynamic>.from(phases[phase] as Map? ?? {});
      _check(previous['passed'] != true, 'passed_phase_rerun_forbidden');
      final attempt = phase == 'complete_retained_scenario'
          ? 6
          : phase == 'open_both_push_references'
          ? 7
          : (previous['attempts'] as int? ?? 0) + 1;
      // November 6 test 1 (attempt 4) stopped on the legacy fixture URL seam.
      // Explicit test 2 permits attempt 5 with verified known-history scope
      // protection. Test 3 may capture delivery; opening is not yet authorized.
      final openOnly = phase == 'open_both_push_references';
      final renewal = await _read(
        File(
          '${root.path}/${openOnly ? 'open-only-authorization-20261106.json' : 'renewal-20261106.json'}',
        ),
      );
      final renewalId = openOnly
          ? 'task-reminder-open-only-20261106'
          : 'task-reminder-recipients-renewal-20261106';
      final grant = renewal['phases']?[phase];
      _check(
        Platform.environment['JIVIE_RECIPIENTS_HTTP_RENEWAL'] == renewalId &&
            renewal['id'] == renewalId &&
            renewal['halted'] == false &&
            renewal['fixtureSha256'] ==
                await cryptoSha256(await file.readAsBytes()) &&
            renewal['allowedAttemptByPhase']?[phase] == attempt &&
            grant is Map &&
            grant['status'] == 'running' &&
            grant['attempt'] == attempt &&
            ((phase == 'prepare_both_recipients' &&
                    attempt == 5 &&
                    renewal['exactScopeProtectionForTest2Authorized'] ==
                        true) ||
                (phase == 'open_both_push_references' &&
                    attempt == 7 &&
                    previous.isEmpty &&
                    renewal['openingSeparatelyAuthorized'] == true &&
                    renewal['deliverySha256'] ==
                        await cryptoSha256(
                          await File(
                            '${root.path}/delivery-private.json',
                          ).readAsBytes(),
                        )) ||
                (phase == 'complete_retained_scenario' &&
                    attempt == 6 &&
                    previous.isEmpty &&
                    renewal['oneEndToEndThirdTestAuthorized'] == true &&
                    (renewal['attemptHistory'] as List).length == 2)),
        'explicit_same_fixture_single_use_renewal_required',
      );
      phases[phase!] = {'attempts': attempt, 'passed': false};
      ledger['phases'] = phases;
      await _save(ledgerFile, ledger);
      final keysFile = File('${root.path}/shared-keys-private.json');
      final secrets = await _read(keysFile);
      Future<void> secretTail = Future.value();
      final channel =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      channel.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final pluginKey = args['key'] as String;
          const wrapper = 'jivie_account_crypto_v1_';
          _check(
            pluginKey.startsWith(wrapper),
            'unexpected_secure_storage_key',
          );
          // The retained direct AccountCryptoStore map predates the native
          // plugin wrapper. Only its known wrapper label is adapted; all
          // original partition/anchor names and value bytes stay unchanged.
          final key = pluginKey.substring(wrapper.length);
          if (call.method == 'read') {
            await secretTail;
            return secrets[key];
          }
          if (call.method == 'write') {
            secretTail = secretTail.then((_) async {
              secrets[key] = args['value'];
              await _save(keysFile, secrets);
            });
            await secretTail;
            return null;
          }
          throw StateError('unexpected_secure_storage_method');
        },
      );
      final actors = <_Actor>[];
      final result = <String, Object?>{
        'phase': phase,
        'attempt': attempt,
        'renewal': renewalId,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'productionMutations': 0,
        'nativeProviderEnvelopeSynthetic': true,
        'setupSharingRecoveryReplayed': false,
        'retainedNamespaceCanonicalNetworkAdapter': true,
        'steps': <String, Object?>{},
      };
      Future<void> step(String name, Future<void> Function() action) async {
        final entry = <String, Object?>{
          'startedAt': DateTime.now().toUtc().toIso8601String(),
          'outcome': 'running',
        };
        (result['steps'] as Map)[name] = entry;
        try {
          await action();
          entry['outcome'] = 'passed';
        } catch (error) {
          entry['outcome'] = 'failed';
          entry['error'] = _code(error);
          rethrow;
        } finally {
          entry['finishedAt'] = DateTime.now().toUtc().toIso8601String();
          await _save(
            File('${root.path}/$phase-r$attempt-result.json'),
            result,
          );
        }
      }

      try {
        final sender = _Actor('sender', root, fixture),
            recipient = _Actor('recipient', root, fixture);
        for (final actor in [sender, recipient]) {
          await actor.open();
          actors.add(actor);
        }
        if (phase == 'prepare_both_recipients') {
          await sender.protectExactRetainedScope();
          for (final actor in actors) {
            await actor.sync();
            _check(
              actor.repo.state.scopes.any(
                (s) =>
                    s.id == fixture['scopeId'] &&
                    s.canEdit &&
                    !s.revoked &&
                    !s.deleted,
              ),
              'existing_shared_scope_not_editable',
            );
            await actor.acceptRulesIfRequired();
            await actor.repo.setNotificationPreferences(
              scopeId: fixture['scopeId'],
              category: 'reminders',
              settings: const SharedNotificationSettings(),
            );
            await actor.sync();
          }
          if (ledger['taskId'] == null) {
            ledger['taskId'] = await sender.repo.createTask(
              scopeId: fixture['scopeId'],
              title: _title,
              notes: _notes,
              dueAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
              assigneeAccountIds: [
                recipient.sessions.current.profile.accountId,
              ],
            );
            await _save(ledgerFile, ledger);
          }
          await sender.sync();
          await recipient.sync();
          for (final actor in actors) {
            await actor.assertTask(ledger['taskId'] as String);
            final session = actor.sessions.current;
            final registration = await actor.wire.call(
              serverUrl: fixture['serverUrl'],
              operation: 'push.register',
              params: {
                'token': 'synthetic-reminder-recipients-${actor.name}-20261105',
                'platform': 'android',
                'language': 'en',
                'displayVersion': 2,
                'projectId': 'synthetic-reminders',
                'expectedRevision': 0,
              },
              token: session.token,
              allowLocalHttp: true,
            );
            _check(
              (registration['registration'] as Map)['registered'] == true,
              'synthetic_push_registration_required',
            );
          }
          if (ledger['reminderId'] == null) {
            final due = DateTime.now().toUtc().add(const Duration(seconds: 90));
            ledger['dueAt'] = due.toIso8601String();
            ledger['reminderId'] = await sender.repo.putReminder(
              scopeId: fixture['scopeId'],
              targetType: 'task',
              targetId: ledger['taskId'],
              remindAt: due,
              recipientPolicy: _policy,
            );
            await _save(ledgerFile, ledger);
          }
          await sender.sync();
          final scheduled = sender.repo.state.scheduledReminders
              .where((r) => r.id == ledger['reminderId'])
              .toList();
          _check(
            scheduled.length == 1 &&
                scheduled.single.revision == 1 &&
                scheduled.single.state == 'pending' &&
                scheduled.single.syncState == 'synced' &&
                scheduled.single.recipientPolicy == _policy,
            'signed_both_recipients_reminder_not_confirmed',
          );
          result.addAll({
            'reminderConfirmed': true,
            'senderReminderCount': scheduled.length,
            'dueAt': ledger['dueAt'],
            'bothTaskPlaintextsVerified': true,
            'policy': _policy,
          });
        } else {
          if (phase == 'complete_retained_scenario') {
            await _finishRetainedPreparation(
              actors: actors,
              root: root,
              fixture: fixture,
              ledger: ledger,
              ledgerFile: ledgerFile,
              result: result,
              step: step,
            );
          }
          _check(
            (phases['prepare_both_recipients']?['passed'] == true ||
                    ledger['r6PreparationConfirmed'] == true) &&
                ledger['taskId'] is String &&
                ledger['reminderId'] is String,
            'prepared_scenario_required',
          );
          final delivery = await _read(
            File('${root.path}/delivery-private.json'),
          );
          _check(
            delivery['delivered'] == true &&
                delivery['recipientCount'] == 2 &&
                delivery['pushAcceptedCount'] == 2 &&
                delivery['naturalDue'] == true,
            'one_due_worker_and_two_captured_pushes_required',
          );
          var allOpened = true;
          for (final actor in actors) {
            try {
              await step('${actor.name}_real_open_and_projection', () async {
                final id = delivery['notificationIds'][actor.name];
                _check(
                  id is int && id > 0,
                  'exact_worker_notification_required',
                );
                final session = actor.sessions.current;
                final providerData = Map<String, dynamic>.from(
                  delivery['envelopes'][actor.name] as Map,
                );
                _check(
                  providerData['serverId'] == session.profile.serverId &&
                      providerData['accountId'] == session.profile.accountId &&
                      providerData['notificationId'] == '$id',
                  'captured_provider_reference_binding_required',
                );
                // Android display2 includes five presentation fields. Validate
                // the real provider envelope through the production adapter,
                // which extracts the strict four-field typed inbox reference.
                final display = SystemPushMessage.tryParse(providerData);
                _check(display != null, 'captured_display_v2_invalid');
                final reference = display!.reference;
                // No explicit pre-open sync: the actual production tap route owns it.
                final opened = await actor.repo.openRemotePushReference(
                  reference,
                );
                result['${actor.name}RouteStatus'] = opened.status.name;
                final target = opened.target;
                final exact =
                    opened.status == RemotePushOpenStatus.available &&
                    target != null &&
                    target.matches(session.profile) &&
                    target.scopeId == fixture['scopeId'] &&
                    target.inboxIds.contains(id) &&
                    target.records.any(
                      (r) => r.type == 'task' && r.recordId == ledger['taskId'],
                    );
                result['${actor.name}ExactTaskRoute'] = exact;
                _check(exact, 'exact_recipient_task_route_unavailable');
                await actor.assertClear();
                result['${actor.name}ClearSync'] = true;
                final deadlineFuture = await actor.assertTask(
                  ledger['taskId'] as String,
                  requireFutureDeadline: !openOnly,
                );
                result['${actor.name}TaskDeadlineStillFuture'] = deadlineFuture;
                result['${actor.name}BeforeDeadlineCoverage'] = deadlineFuture
                    ? 'observed_at_open'
                    : 'NOT_MEASURED_ORIGINAL_DEADLINE_PASSED';
                result['${actor.name}ActualOpenAt'] = DateTime.now()
                    .toUtc()
                    .toIso8601String();
                final plans = desiredReminderPlans(
                  personal: OrganizerSnapshot(),
                  shared: actor.repo.state,
                );
                final projection = projectOrganizerInbox(
                  personal: null,
                  shared: actor.repo.state,
                  effectivePlans: plans,
                  now: DateTime.now().toUtc(),
                );
                final visible = projection.shared.where(
                  (item) => item.group.entries.any(
                    (entry) =>
                        entry.id == id &&
                        entry.kind == 'reminder.due' &&
                        entry.targetId == ledger['taskId'],
                  ),
                );
                result['${actor.name}DueInboxVisibleAtActualTime'] =
                    visible.length == 1;
                _check(
                  visible.length == 1,
                  'due_peer_inbox_hidden_by_future_task_deadline',
                );
              });
            } catch (error, stack) {
              if (!openOnly) rethrow;
              allOpened = false;
              result['${actor.name}OpenError'] = _code(error);
              result['${actor.name}OpenStack'] = stack
                  .toString()
                  .split('\n')
                  .take(18)
                  .toList();
            }
          }
          _check(allOpened, 'one_or_more_actual_opens_failed');
          result['bothTaskPlaintextsVerified'] = true;
        }
        phases[phase] = {'attempts': attempt, 'passed': true};
        await _save(ledgerFile, ledger);
        result['passed'] = true;
      } catch (error, stack) {
        result['passed'] = false;
        result['error'] = _code(error);
        result['safeStack'] = stack.toString().split('\n').take(18).toList();
        throw StateError('two_account_http_${_code(error)}');
      } finally {
        result['finishedAt'] = DateTime.now().toUtc().toIso8601String();
        for (final actor in actors) {
          result[actor.name] = await actor.evidence();
        }
        await _save(File('${root.path}/$phase-r$attempt-result.json'), result);
        for (final actor in actors.reversed) {
          await actor.close();
        }
        channel.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
      }
    },
    skip: fixturePath == null || phase == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
