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
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_active_outbox.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/shared_payload_validation.dart';

// Opt-in investigation against an isolated COPY of the retained HTTP fixture.
// Production repository/router, SQL, signatures and PHP transport are used.
// Only OS secure storage is replaced by the retained synthetic disk secrets.
// No native push delivery, device vault or UI behavior is asserted here.
Future<Map<String, dynamic>> _read(File file) async => file.existsSync()
    ? Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map)
    : {};

Future<void> _save(File file, Object? value) async {
  final temporary = File('${file.path}.next');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(file.path);
}

void _require(bool value, String reason) {
  if (!value) throw StateError(reason);
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
    return (await _read(file))[key] as String?;
  }

  @override
  Future<void> write(String key, String value) {
    final next = _tail.then((_) async {
      final values = await _read(file);
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
    final value = await _read(file);
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
  Future<void> clear() =>
      throw StateError('diagnostic_session_clear_forbidden');
}

class _Invitations implements PendingInvitationStore {
  @override
  Future<PendingInvitation?> read() async => null;
  @override
  Future<void> write(PendingInvitation? invitation) async =>
      _require(invitation == null, 'diagnostic_invitation_write_forbidden');
}

class _Deletions implements AccountDeletionStore {
  @override
  Future<List<PendingAccountDeletion>> read() async => [];
  @override
  Future<void> write(List<PendingAccountDeletion> requests) async =>
      _require(requests.isEmpty, 'diagnostic_deletion_write_forbidden');
}

class _Wire extends HttpCollaborationTransport {
  final operations = <String>[];
  final observations = <Map<String, Object?>>[];
  Future<Map<String, dynamic>> _observe(
    String operation,
    Future<Map<String, dynamic>> Function() send,
  ) async {
    operations.add(operation);
    try {
      final reply = await send();
      if (operation == 'crypto2.reminders.list' ||
          operation == 'crypto2.reminders.put') {
        final rows = reply['reminders'] is List
            ? reply['reminders'] as List
            : reply['reminder'] is Map
            ? [reply['reminder']]
            : <Object?>[];
        observations.add({
          'operation': operation,
          'rows': [
            for (final raw in rows)
              if (raw is Map)
                {
                  for (final key in const [
                    'state',
                    'revision',
                    'targetRevision',
                    'scheduleRevision',
                    'scheduleMode',
                    'offsetMinutes',
                  ])
                    key: raw[key],
                },
          ],
        });
      }
      return reply;
    } catch (error, stack) {
      observations.add({
        'operation': operation,
        'error': _code(error),
        'stack': stack.toString().split('\n').take(12).toList(),
      });
      rethrow;
    }
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

class _Diagnostic {
  _Diagnostic(this.root, this.fixture, this.ledger);
  final Directory root;
  final Map<String, dynamic> fixture, ledger;
  late final CollaborationDatabase db;
  late final CollaborationRepository repo;
  late final _Sessions sessions;
  final wire = _Wire();
  bool observedUnresolved = false;
  String? syncOutcome;
  List<Map<String, Object?>>? ownDirectoryBefore;
  final phaseEvidence = <String, Object?>{};
  Future<void> save() =>
      _save(File('${root.path}/reminder-ledger-private.json'), ledger);

  Future<void> open() async {
    db = CollaborationDatabase(
      NativeDatabase(File('${root.path}/owner.sqlite')),
    );
    sessions = _Sessions(File('${root.path}/owner-session-private.json'));
    final session = await sessions.read();
    _require(
      session != null &&
          session.profile.serverUrl ==
              normalizeCollaborationServer(
                fixture['serverUrl'] as String,
                allowLocalHttp: true,
              ) &&
          session.profile.allowLocalHttp,
      'retained_loopback_session_required',
    );
    final secrets = _Secrets(File('${root.path}/owner-keys-private.json'));
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

  Future<void> snapshot(String phase) async {
    final partition = sessions.current!.profile.partition;
    final counts = <String, int>{};
    for (final operation in wire.operations) {
      counts.update(operation, (n) => n + 1, ifAbsent: () => 1);
    }
    await _save(File('${root.path}/$phase-summary.json'), {
      'at': DateTime.now().toUtc().toIso8601String(),
      'phase': phase,
      'syncOutcome': syncOutcome,
      'ownDirectoryBefore': ownDirectoryBefore,
      'ownDirectoryAfter': await ownDirectoryMarker(),
      'phaseEvidence': phaseEvidence,
      'lastChangeCheckAttemptAt': repo.state.lastChangeCheckAttemptAt
          ?.toUtc()
          .toIso8601String(),
      'lastSuccessfulChangeCheckAt': repo.state.lastSuccessfulChangeCheckAt
          ?.toUtc()
          .toIso8601String(),
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
      'httpOperations': counts,
      'httpSequence': wire.operations,
      'wireObservations': wire.observations,
      'scopes': [
        for (final scope in repo.state.scopes)
          {
            'id': scope.id,
            'kind': scope.kind.name,
            'role': scope.role.name,
            'canEdit': scope.canEdit,
            'revoked': scope.revoked,
            'deleted': scope.deleted,
            'projectRootId': scope.projectRootId,
          },
      ],
      'reminders': [
        for (final reminder in repo.state.scheduledReminders)
          {
            'id': reminder.id,
            'state': reminder.state,
            'revision': reminder.revision,
            'syncState': reminder.syncState,
            'syncError': reminder.syncError,
          },
      ],
      'cryptoCommands': await db.rows(
        '''SELECT operation,state,CASE WHEN ${cryptoActiveOutboxPredicate()} THEN 1 ELSE 0 END AS active FROM crypto_outbox WHERE partition=? ORDER BY sequence''',
        [partition],
      ),
      'localIdentityPhases': await db.rows(
        'SELECT phase,count(*) AS count FROM crypto_identity_secrets WHERE partition=? GROUP BY phase',
        [partition],
      ),
    });
  }

  Future<List<Map<String, Object?>>> ownDirectoryMarker() => db.rows(
    '''SELECT min_generation,head_hash,snapshot_hash,device_snapshot_hash,trust_state
       FROM crypto_directory_pins WHERE partition=? AND account_id=?''',
    [sessions.current!.profile.partition, sessions.current!.profile.accountId],
  );

  Future<void> assertClearPhase(String phase, Set<int> previousDueInbox) async {
    if (phase == 'discovery') return;
    final partition = sessions.current!.profile.partition;
    final taskId = ledger['taskId'];
    final task = await db.rows(
      "SELECT server_revision,remote,deleted FROM records WHERE partition=? AND scope_id=? AND id=? AND type='task'",
      [partition, fixture['scopeId'], taskId],
    );
    _require(
      task.length == 1 &&
          task.single['server_revision'] is int &&
          (task.single['server_revision'] as int) > 0 &&
          task.single['remote'] != null &&
          task.single['deleted'] == 0,
      'diagnostic_task_server_projection_required',
    );
    final pending = await db.rows(
      '''SELECT COUNT(*) AS count FROM crypto_outbox WHERE partition=?
         AND ${cryptoActiveOutboxPredicate()} AND state IN ('pending','blocked')''',
      [partition],
    );
    _require(pending.single['count'] == 0, 'active_crypto_work_remains');
    final taskPending = await db.rows(
      'SELECT op_id FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
      [partition, fixture['scopeId'], taskId],
    );
    _require(taskPending.isEmpty, 'diagnostic_task_outbox_remains');
    phaseEvidence['taskServerRevision'] = task.single['server_revision'];
    phaseEvidence['activeCryptoPendingOrBlocked'] = pending.single['count'];
    if (phase == 'create_task') return;
    final relative =
        phase == 'create_relative' || phase == 'sync_after_relative_delivery';
    final id = ledger[relative ? 'relativeReminderId' : 'absoluteReminderId'];
    _require(id is String, 'specific_diagnostic_reminder_required');
    final reminder = await db.rows(
      'SELECT data,remote FROM scheduled_reminders WHERE partition=? AND id=?',
      [partition, id],
    );
    _require(
      reminder.length == 1 && reminder.single['remote'] != null,
      'specific_reminder_server_projection_required',
    );
    final local = SharedScheduledReminder.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(reminder.single['data'] as String) as Map,
      ),
    );
    final remote = SharedScheduledReminder.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(reminder.single['remote'] as String) as Map,
      ),
    );
    _require(
      local.syncState == 'synced' &&
          local.syncError == null &&
          local.targetId == taskId &&
          remote.targetId == taskId &&
          local.revision >= 1 &&
          remote.revision >= 1,
      'specific_reminder_not_confirmed',
    );
    final commands = await db.rows(
      'SELECT id FROM commands WHERE partition=? AND entity_key=?',
      [partition, 'reminder:$id'],
    );
    _require(commands.isEmpty, 'specific_reminder_command_remains');
    phaseEvidence['reminderServerRevision'] = remote.revision;
    phaseEvidence['reminderServerState'] = remote.state;
    if (phase == 'open_existing_absolute_push') {
      _require(
        local.state == 'delivered' && remote.state == 'delivered',
        'opened_absolute_reminder_not_delivered',
      );
      phaseEvidence['openedAbsoluteReminderDelivered'] = true;
    }
    if (phase.startsWith('sync_after_')) {
      _require(
        local.state == 'delivered' && remote.state == 'delivered',
        'specific_reminder_not_delivered',
      );
      final newDue = repo.state.inbox
          .where(
            (item) =>
                item.kind == 'reminder.due' &&
                item.scopeId == fixture['scopeId'] &&
                item.targetType == 'task' &&
                item.targetId == taskId &&
                !previousDueInbox.contains(item.id),
          )
          .toList();
      _require(newDue.isNotEmpty, 'new_specific_target_due_inbox_required');
      phaseEvidence['newTargetDueInboxCount'] = newDue.length;
    }
  }

  Future<void> sync(String phase) async {
    ownDirectoryBefore = await ownDirectoryMarker();
    final previousDueInbox = {
      for (final item in repo.state.inbox)
        if (item.kind == 'reminder.due') item.id,
    };
    final before = repo.lastSyncCompletion?.sequence ?? 0;
    final checkBefore = repo.state.lastSuccessfulChangeCheckAt;
    await repo.syncNow(manual: true);
    final completed = repo.lastSyncCompletion;
    final newCompletion = completed != null && completed.sequence > before;
    final checkAfter = repo.state.lastSuccessfulChangeCheckAt;
    final successfulCheck =
        checkAfter != null &&
        (checkBefore == null || checkAfter.isAfter(checkBefore));
    _require(
      newCompletion || successfulCheck,
      'sync_completion_or_successful_change_check_required',
    );
    syncOutcome = newCompletion ? 'completed' : 'unchanged';
    observedUnresolved =
        (newCompletion &&
            (completed.error != null || completed.work.unresolved)) ||
        repo.state.hasUnresolvedSyncWork ||
        repo.state.lastError != null;
    if (!observedUnresolved) await assertClearPhase(phase, previousDueInbox);
    await snapshot(phase);
  }

  Future<void> openExistingAbsolutePush(String phase) async {
    final session = sessions.current!;
    final notificationId = fixture['notificationId'];
    _require(
      notificationId is int && notificationId > 0,
      'explicit_delivered_notification_required',
    );
    _require(
      ledger['taskId'] is String && ledger['absoluteReminderId'] is String,
      'prepared_absolute_tap_scenario_required',
    );
    final pending = await db.rows(
      '''SELECT
        (SELECT COUNT(*) FROM commands WHERE partition=?) AS businessCommands,
        (SELECT COUNT(*) FROM crypto_outbox WHERE partition=? AND
          ${cryptoActiveOutboxPredicate()} AND state IN ('pending','blocked')) AS cryptoCommands''',
      [session.profile.partition, session.profile.partition],
    );
    phaseEvidence['businessCommandsBeforeOpen'] =
        pending.single['businessCommands'];
    phaseEvidence['activeCryptoCommandsBeforeOpen'] =
        pending.single['cryptoCommands'];
    _require(
      pending.single['businessCommands'] == 0 &&
          pending.single['cryptoCommands'] == 0,
      'absolute_tap_requires_no_preexisting_command_work',
    );
    ownDirectoryBefore = await ownDirectoryMarker();
    phaseEvidence['nativeEnvelopeSynthetic'] = true;
    phaseEvidence['globalErrorBeforeOpen'] = _code(repo.state.lastError);
    final completionBefore = repo.lastSyncCompletion?.sequence ?? 0;
    final reference = RemotePushReference.parse({
      'type': 'familyhub.inbox.v1',
      'serverId': session.profile.serverId,
      'accountId': session.profile.accountId,
      'notificationId': '$notificationId',
    });
    // The production tap route owns its own normal sync. There is no extra
    // explicit sync, queue filtering or synthetic inbox/content response here.
    final opened = await repo.openRemotePushReference(reference);
    final target = opened.target;
    final targetMatches =
        target != null &&
        target.matches(session.profile) &&
        target.scopeId == fixture['scopeId'] &&
        target.inboxIds.contains(notificationId) &&
        target.records.any(
          (record) =>
              record.type == 'task' && record.recordId == ledger['taskId'],
        );
    phaseEvidence['routeStatus'] = opened.status.name;
    phaseEvidence['routeTargetMatchesPreparedTaskAndInbox'] = targetMatches;
    phaseEvidence['globalErrorAfterOpen'] = _code(repo.state.lastError);
    final completed = repo.lastSyncCompletion;
    syncOutcome = completed != null && completed.sequence > completionBefore
        ? 'route_completed_sync'
        : 'route_without_new_completion';
    observedUnresolved =
        repo.state.hasUnresolvedSyncWork || repo.state.lastError != null;
    await snapshot(phase);
    _require(
      opened.status == RemotePushOpenStatus.available && targetMatches,
      'absolute_push_target_not_available',
    );
    if (!observedUnresolved) await assertClearPhase(phase, {});
    await snapshot(phase);
  }

  Future<void> run(String phase) async {
    if (phase == 'open_existing_absolute_push') {
      await openExistingAbsolutePush(phase);
      return;
    }
    if (phase == 'discovery' ||
        phase == 'sync_after_delivery' ||
        phase == 'sync_after_relative_delivery') {
      await sync(phase);
      return;
    }
    final scopeId = fixture['scopeId'];
    _require(
      scopeId is String && isSharedUuid(scopeId),
      'explicit_fixture_scope_required',
    );
    _require(
      repo.state.scopes.any((s) => s.id == scopeId && s.canEdit),
      'explicit_fixture_scope_not_writable',
    );
    if (phase == 'prepare_existing_absolute_tap') {
      if (ledger['taskId'] == null) {
        final existingTask = fixture['taskId'];
        if (existingTask != null) {
          _require(
            existingTask is String && isSharedUuid(existingTask),
            'explicit_existing_task_id_invalid',
          );
          ledger['taskId'] = existingTask;
          phaseEvidence['usedExistingTask'] = true;
        } else {
          ledger['taskId'] = await repo.createTask(
            scopeId: scopeId as String,
            projectId: fixture['projectId'] as String?,
            title: 'Synthetic absolute tap diagnostic 20261105',
            dueAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
            assigneeAccountIds: (fixture['assigneeAccountIds'] as List? ?? [])
                .cast<String>(),
          );
          phaseEvidence['createdRequiredScenarioTask'] = true;
        }
        await save();
      }
      if (ledger['absoluteReminderId'] == null) {
        ledger['absoluteReminderId'] = await repo.putReminder(
          scopeId: scopeId as String,
          targetType: 'task',
          targetId: ledger['taskId'] as String,
          remindAt: DateTime.now().toUtc().add(const Duration(seconds: 90)),
        );
        await save();
      }
      await sync(phase);
      return;
    }
    if (phase == 'create_task') {
      if (ledger['taskId'] == null) {
        final due = fixture['dueAt'] is String
            ? DateTime.parse(fixture['dueAt'] as String).toUtc()
            : DateTime.now().toUtc().add(const Duration(minutes: 5));
        _require(
          due.isAfter(DateTime.now().toUtc()),
          'diagnostic_task_due_must_be_future',
        );
        ledger['taskId'] = await repo.createTask(
          scopeId: scopeId as String,
          projectId: fixture['projectId'] as String?,
          title: 'Synthetic reminder diagnostic 20261105',
          dueAt: due,
          assigneeAccountIds: (fixture['assigneeAccountIds'] as List? ?? [])
              .cast<String>(),
        );
        ledger['dueAt'] = due.toIso8601String();
        await save();
      }
      await sync(phase);
      return;
    }
    _require(
      phase == 'create_absolute' || phase == 'create_relative',
      'unknown_diagnostic_phase',
    );
    final taskId = ledger['taskId'];
    _require(taskId is String, 'diagnostic_task_required');
    final relative = phase == 'create_relative';
    final key = relative ? 'relativeReminderId' : 'absoluteReminderId';
    if (ledger[key] == null) {
      ledger[key] = await repo.putReminder(
        scopeId: scopeId as String,
        targetType: 'task',
        targetId: taskId as String,
        remindAt: relative
            ? DateTime.parse(ledger['dueAt'] as String)
            : DateTime.now().toUtc().add(const Duration(minutes: 3)),
        offsetMinutes: relative ? 0 : null,
      );
      await save();
    }
    await sync(phase);
  }

  Future<void> close() async {
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
  HttpOverrides.global = null;
  final path = Platform.environment['JIVIE_REMINDER_HTTP_FIXTURE'];
  final phase =
      Platform.environment['JIVIE_REMINDER_HTTP_PHASE'] ?? 'discovery';
  test(
    'isolated persisted HTTP reminder investigation: $phase',
    () async {
      final fixtureFile = File(path!);
      final fixture = await _read(fixtureFile);
      final originalDiagnostic =
          fixture['purpose'] == 'reminder-sync-20261105' &&
          fixtureFile.parent.path.endsWith(
            'build/qa/reminder-sync-20261105/private',
          );
      final absoluteTapDiagnostic =
          fixture['purpose'] == 'reminder-absolute-tap-20261105' &&
          fixtureFile.parent.path.endsWith(
            'build/qa/reminder-sync-20261105/absolute-tap',
          ) &&
          const {
            'prepare_existing_absolute_tap',
            'open_existing_absolute_push',
          }.contains(phase);
      _require(
        fixture['synthetic'] == true &&
            fixture['serverUrl'] == 'http://127.0.0.1:57901' &&
            (originalDiagnostic || absoluteTapDiagnostic),
        'dedicated_synthetic_clone_required',
      );
      final root = fixtureFile.parent;
      final ledgerFile = File('${root.path}/reminder-ledger-private.json');
      final ledger = await _read(ledgerFile);
      final phases =
          ledger.putIfAbsent('phases', () => <String, dynamic>{}) as Map;
      final entry = Map<String, dynamic>.from(phases[phase] as Map? ?? {});
      _require(
        entry['passed'] != true && entry['observed'] != true,
        'completed_phase_must_not_repeat',
      );
      final attempt = (entry['attempts'] as int? ?? 0) + 1;
      _require(attempt <= 3, 'phase_attempt_limit_reached');
      entry.addAll({
        'attempts': attempt,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      });
      phases[phase] = entry;
      await _save(ledgerFile, ledger);
      final diagnostic = _Diagnostic(root, fixture, ledger);
      var opened = false;
      try {
        await diagnostic.open();
        opened = true;
        await diagnostic.run(phase);
        entry['observed'] = true;
        entry['outcome'] = diagnostic.observedUnresolved
            ? 'observed-unresolved'
            : 'observed-clear';
        entry['finishedAt'] = DateTime.now().toUtc().toIso8601String();
        await diagnostic.save();
        debugPrint(
          'REMINDER_HTTP $phase ${entry['outcome']} '
          'attempt=$attempt requests=${diagnostic.wire.operations.length}',
        );
      } catch (error, stack) {
        entry['error'] = _code(error);
        entry['stack'] = stack.toString().split('\n').take(12).toList();
        entry['finishedAt'] = DateTime.now().toUtc().toIso8601String();
        await _save(ledgerFile, ledger);
        if (opened) await diagnostic.snapshot('$phase-failed-$attempt');
        fail(
          'REMINDER_HTTP $phase FAILED attempt=$attempt reason=${_code(error)}',
        );
      } finally {
        if (opened) await diagnostic.close();
      }
    },
    skip: path == null ? 'Dedicated isolated HTTP clone is opt-in.' : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
