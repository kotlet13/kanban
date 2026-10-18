import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart'
    show CryptoAuthorityPending;
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_notifications.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

import '../collaboration_repository_test.dart' show MemorySessionStore;

class _Secure implements AccountCryptoStore {
  final rows = <String, String>{};
  @override
  Future<String?> read(String key) async => rows[key];
  @override
  Future<void> write(String key, String value) async {
    rows[key] = value;
  }
}

class _Transport implements CollaborationTransport {
  final http = HttpCollaborationTransport();
  final operations = <String>[];
  Completer<void>? lifecycleCaptured, releaseLifecycle;
  Map<String, dynamic>? substituteIntent;
  bool hideLifecycle = false;
  bool withhold = false, tamperRelative = false, tamperCancelledTarget = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    late Map<String, dynamic> reply;
    for (var attempt = 0; ; attempt++) {
      try {
        reply = await http.call(
          serverUrl: serverUrl,
          operation: operation,
          params: params,
          token: token,
          allowLocalHttp: allowLocalHttp,
        );
        break;
      } on CollaborationApiException catch (error) {
        if (error.code != 'rate_limited' || attempt >= 3) rethrow;
        final retry = error.details['retryAfter'];
        await Future<void>.delayed(
          Duration(seconds: retry is int ? retry.clamp(1, 60) : 15),
        );
      }
    }
    if (operation == 'crypto2.scope.lifecycle.list') {
      if (hideLifecycle) {
        return {
          'states': <Object>[],
          'hasMore': false,
          'nextAfterRevision': null,
          'currentRevision': 0,
        };
      }
      if (lifecycleCaptured != null && !lifecycleCaptured!.isCompleted) {
        lifecycleCaptured!.complete();
        await releaseLifecycle!.future;
      }
      if (substituteIntent != null && (reply['states'] as List).isNotEmpty) {
        (reply['states'] as List).last['intentAuthorization'] =
            substituteIntent;
      }
    }
    if (operation == 'crypto2.reminders.list' &&
        reply['reminders'] is List &&
        (reply['reminders'] as List).isNotEmpty) {
      final row = (reply['reminders'] as List).first as Map;
      if (tamperRelative && row['state'] == 'pending') {
        row['remindAt'] = DateTime.parse(
          row['remindAt'],
        ).add(const Duration(hours: 2)).toUtc().toIso8601String();
      }
      if (tamperCancelledTarget && row['state'] == 'cancelled') {
        row['targetId'] = '11111111-1111-4111-a111-111111111111';
      }
    }
    if (withhold && operation == 'crypto2.records.pull') {
      return {
        ...reply,
        'records': <Object>[],
        'cursor': params['cursor'],
        'hasMore': false,
      };
    }
    return reply;
  }

  @override
  void close() => http.close();
}

void main() {
  final path = Platform.environment['JIVIE_CRYPTO2_NOTIFICATION_HTTP_FIXTURE'];
  test(
    'actual reminder UI route preserves signed own intents and encrypted date changes',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback only');
      }
      final w =
              (fixture['session'] ?? fixture['accounts']['owner']['session'])
                  as Map,
          u = w['user'] as Map,
          d = w['device'] as Map;
      final session = DeviceSession(
        AccountSession(
          serverUrl: url,
          serverId: w['serverId'],
          accountId: u['accountId'],
          userId: u['id'],
          username: u['username'],
          displayName: u['displayName'],
          deviceId: d['id'],
          expiresAt: DateTime.fromMillisecondsSinceEpoch(d['expiresAt'] * 1000),
          allowLocalHttp: true,
        ),
        w['token'],
      );
      final db = CollaborationDatabase(NativeDatabase.memory()),
          transport = _Transport(),
          crypto = CryptoCodec(await SodiumInit.init());
      var identityCurrent = true;
      final secure = _Secure();
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: transport,
          store: CryptoIdentityStore(db, secure, session.profile.partition),
          isCurrent: () => identityCurrent,
        ),
      );
      final file = await account.prepareRecoveryFile();
      try {
        await account.verifyAndInitialize(file);
      } finally {
        file.fillRange(0, file.length, 0);
      }
      final repository = CollaborationRepository(
        db,
        transport,
        MemorySessionStore()..value = session,
        cryptoRouter: CryptoBusinessRouter(
          database: db,
          accountFor: (_) async => account,
        ),
      );
      addTearDown(repository.close);
      await repository.initialize();
      final scope = await repository.createScope('PRIVATE_NOTIFICATION_SCOPE');
      final due = DateTime.now().toUtc().add(const Duration(hours: 4));
      final task = await repository.createTask(
        scopeId: scope,
        title: 'PRIVATE_REMINDER_TITLE',
        dueAt: due,
      );
      await repository.syncNow();
      final reminder = await repository.putReminder(
        scopeId: scope,
        targetType: 'task',
        targetId: task,
        remindAt: due.subtract(const Duration(hours: 1)),
        offsetMinutes: 60,
      );
      await repository.syncNow();
      var own = (await db.rows(
        'SELECT data FROM scheduled_reminders WHERE partition=? AND id=?',
        [session.profile.partition, reminder],
      )).single;
      expect(
        jsonDecode(own['data'] as String)['syncState'],
        'synced',
        reason: repository.state.lastError?.toString(),
      );
      final runtime = CryptoBusinessSession(
            account,
            SessionCryptoAccess(account: account),
            db,
          ),
          adapter = CryptoBusinessNotifications(
            CryptoBusinessSession(
              account,
              SessionCryptoAccess(account: account),
              db,
            ),
          );
      final listed = await adapter.dispatch('reminders.list', {
        'scopeId': scope,
      });
      expect((listed['reminders'] as List).single['id'], reminder);
      transport.tamperRelative = true;
      await expectLater(
        adapter.dispatch('reminders.list', {'scopeId': scope}),
        throwsA(isA<FormatException>()),
      );
      transport.tamperRelative = false;
      final original = repository.state
          .dataForScope(scope)
          .tasks
          .singleWhere((t) => t.id == task);
      await repository.updateTask(
        scope,
        original.copyWith(title: 'PRIVATE_RENAMED_ONLY'),
      );
      await repository.syncNow();
      var rows = await adapter.dispatch('reminders.list', {'scopeId': scope});
      expect(rows['reminders'][0]['revision'], 1);
      final changed = repository.state
          .dataForScope(scope)
          .tasks
          .singleWhere((t) => t.id == task);
      await repository.updateTask(
        scope,
        changed.copyWith(dueAt: due.add(const Duration(hours: 1))),
      );
      await repository.syncNow();
      rows = await adapter.dispatch('reminders.list', {'scopeId': scope});
      expect(rows['reminders'][0]['revision'], 2);
      expect(
        DateTime.parse(
              rows['reminders'][0]['remindAt'],
            ).millisecondsSinceEpoch ~/
            1000,
        due.millisecondsSinceEpoch ~/ 1000,
      );
      await repository.cancelReminder(
        repository.state.scheduledReminders.singleWhere(
          (r) => r.id == reminder,
        ),
      );
      await repository.syncNow();
      rows = await adapter.dispatch('reminders.list', {'scopeId': scope});
      expect(rows['reminders'][0]['state'], 'cancelled');
      transport.tamperCancelledTarget = true;
      await expectLater(
        adapter.dispatch('reminders.list', {'scopeId': scope}),
        throwsA(isA<FormatException>()),
      );
      transport.tamperCancelledTarget = false;
      final prefs = await adapter.dispatch('inbox.preferences.set', {
        'scopeId': scope,
        'category': 'reminders',
        'settings': {
          'inApp': true,
          'push': true,
          'email': false,
          'sound': false,
        },
        'requestId': crypto.randomId(),
      });
      expect(prefs['preferences']['reminders']['sound'], false);
      final inbox = await adapter.dispatch('inbox.sync', {
        'cursor': 0,
        'limit': 100,
      });
      expect(inbox['items'], isEmpty);
      expect(
        transport.operations.where(
          (op) =>
              op == 'reminders.put' ||
              op == 'reminders.cancel' ||
              op.startsWith('inbox.'),
        ),
        isEmpty,
      );
      expect(await runtime.record(scope, 'content', task), isNotNull);
      final evidence = CryptoLifecycleEvidence(runtime.access);
      transport.lifecycleCaptured = Completer<void>();
      transport.releaseLifecycle = Completer<void>();
      final stale = evidence.current(scope);
      final staleCheck = expectLater(
        stale,
        completion(containsPair('revision', 1)),
      );
      await transport.lifecycleCaptured!.future;
      final head = await runtime.access.currentHead(scope, online: true);
      final directory = await account.directory.requireFresh();
      final action = crypto.randomId();
      Future<Map<String, dynamic>> signed(
        String operation,
        Map<String, dynamic> payload,
      ) async {
        final lease = await account.signingKey();
        try {
          return crypto.signDomain(
            {
              'version': 2,
              'operation': operation,
              'requestId': crypto.randomId(),
              'serverId': session.profile.serverId,
              'accountId': session.profile.accountId,
              'deviceId': session.profile.deviceId,
              'signer': 'device',
              'payload': payload,
            },
            lease.key,
            cryptoDirectoryDomain,
          );
        } finally {
          lease.release();
        }
      }

      final prepare = await signed('crypto2.scope.lifecycle.prepare', {
        'scopeId': scope,
        'parentActionId': action,
        'expectedLifecycleRevision': 0,
        'previousLifecycleHash': CryptoLifecycleEvidence.zero,
        'membershipHeadHash': head.headHash,
        'expectedAccessRevision': head.accessRevision,
        'authorDirectoryHeadHash': directory.headHash,
        'archived': false,
      });
      await account.directory.call('crypto2.scope.lifecycle.prepare', prepare);
      final archive = await signed('crypto2.scope.archive', {
        'scopeId': scope,
        'parentActionId': action,
        'intentProofHash': await evidence.proofHash(prepare),
        'childCount': 0,
        'childrenHash': await cryptoSha256([]),
      });
      final archiveAck = await account.directory.call(
        'crypto2.scope.archive',
        archive,
      );
      final finalHash = archiveAck['lifecycle']['headHash'];
      // Simulates an independent trusted process publishing a newer anchor
      // while the first scan still carries revision zero. The second pass
      // must either fetch and verify revision one or reject the stale result.
      await secure.write(
        'lifecycle2:${session.profile.partition}:$scope',
        utf8.decode(CryptoJson.encode({'revision': 1, 'headHash': finalHash})),
      );
      final concurrent = CryptoLifecycleEvidence(runtime.access).current(scope);
      transport.releaseLifecycle!.complete();
      await staleCheck;
      expect((await concurrent)['revision'], 1);
      final floor =
          CryptoJson.decode(
                utf8.encode(
                  (await secure.read(
                    'lifecycle2:${session.profile.partition}:$scope',
                  ))!,
                ),
              )
              as Map;
      expect(floor['revision'], 1);
      final changedPrepare =
          CryptoJson.decode(cryptoBase64(prepare['commandBase64'])) as Map;
      transport.substituteIntent =
          await signed('crypto2.scope.lifecycle.prepare', {
            ...Map<String, dynamic>.from(changedPrepare['payload'] as Map),
            'archived': true,
          });
      await expectLater(
        evidence.current(scope),
        throwsA(isA<FormatException>()),
      );
      final forgedOldPrepare = transport.substituteIntent!;
      transport.substituteIntent = null;
      identityCurrent = false;
      await expectLater(
        evidence.current(scope),
        throwsA(isA<FormatException>()),
      );
      identityCurrent = true;
      // A separate device learns the exact scope successor while the author
      // is active, then loses all local lifecycle rows. Its old revoked author
      // is accepted only for the exact prefix anchored by that successor.
      final person = fixture['accounts']['owner'] as Map;
      final login = await transport.call(
        serverUrl: url,
        operation: 'auth.login',
        params: {
          'username': person['username'],
          'password': person['password'],
          'deviceName': 'Lifecycle cold cache',
        },
        allowLocalHttp: true,
      );
      final pairUser = login['user'] as Map,
          pairDevice = login['device'] as Map;
      final pairSession = DeviceSession(
        AccountSession(
          serverUrl: url,
          serverId: login['serverId'],
          accountId: pairUser['accountId'],
          userId: pairUser['id'],
          username: pairUser['username'],
          displayName: pairUser['displayName'],
          deviceId: pairDevice['id'],
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            pairDevice['expiresAt'] * 1000,
          ),
          allowLocalHttp: true,
        ),
        login['token'],
      );
      final pairDb = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(pairDb.close);
      final paired = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: pairSession,
          transport: transport,
          store: CryptoIdentityStore(
            pairDb,
            _Secure(),
            pairSession.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      final card = await paired.prepareDeviceRequest();
      await paired.acceptDeviceConfirmation(
        await account.authorizeDeviceRequest(card),
      );
      final manager = ScopeCryptoManager(runtime.access);
      final rotation = await manager.reviewRotation(scope);
      final successor = await manager.confirmRotation(
        rotation,
        acceptedCandidateHistory: true,
      );
      expect(successor.body['previousLifecycleHash'], finalHash);
      final pairAccess = SessionCryptoAccess(account: paired);
      await pairAccess.currentHead(scope, online: true);
      await paired.revokeDevice(session.profile.deviceId);
      expect(
        await pairDb.rows(
          "SELECT intent_id FROM crypto_membership_intents WHERE state='lifecycleVerified'",
        ),
        isEmpty,
      );
      final coldLife = CryptoLifecycleEvidence(pairAccess);
      expect((await coldLife.current(scope))['headHash'], finalHash);
      transport.substituteIntent = forgedOldPrepare;
      await expectLater(
        coldLife.current(scope),
        throwsA(isA<FormatException>()),
      );
      transport.substituteIntent = null;
      transport.hideLifecycle = true;
      await expectLater(
        coldLife.current(scope),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      transport.hideLifecycle = false;
    },
    skip: path == null ? 'Synthetic loopback fixture not requested' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
