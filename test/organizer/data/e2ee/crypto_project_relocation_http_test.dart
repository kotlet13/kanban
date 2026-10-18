import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:kanban/organizer/data/e2ee/crypto_business_documents.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_audit_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_topology.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  _Secure([this.file]);
  final File? file;
  final values = <String, String>{};
  var _next = 0;
  Future<void> _pending = Future<void>.value();
  Future<void> get settled => _pending;
  @override
  Future<String?> read(String partition) async => values[partition];
  @override
  Future<void> write(String partition, String value) {
    if (file == null) {
      values[partition] = value;
      return Future<void>.value();
    }
    return _pending = _pending.then((_) async {
      final updated = {...values, partition: value};
      final temporary = await _privateRelocationFile(
        file!.parent,
        '${file!.uri.pathSegments.last}.next-${_next++}',
      );
      await temporary.writeAsString(jsonEncode(updated), flush: true);
      await temporary.rename(file!.path);
      values[partition] = value;
    });
  }
}

class _Http extends HttpCollaborationTransport {
  bool loseCommit = false;
  final commits = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final reply = await super.call(
          serverUrl: serverUrl,
          operation: operation,
          params: params,
          token: token,
          allowLocalHttp: allowLocalHttp,
        );
        if (operation == 'crypto2.projectRelocation.commit') {
          commits.add(jsonEncode(params));
          if (loseCommit) {
            loseCommit = false;
            throw const CollaborationException('network');
          }
        }
        return reply;
      } on CollaborationApiException catch (error) {
        print('HTTP $operation ${error.code} ${error.details}');
        if (error.code != 'rate_limited' || attempt >= 4) rethrow;
        final retry = error.details['retryAfter'];
        await Future<void>.delayed(
          Duration(seconds: retry is int ? retry.clamp(1, 60) : 15),
        );
      }
    }
  }
}

DeviceSession _session(String url, Map w) {
  final u = w['user'] as Map, d = w['device'] as Map;
  return DeviceSession(
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
}

/// Opt-in snapshots of this synthetic loopback test only. Never normal storage.
Future<Directory?> _relocationCheckpointDirectory() async {
  final path =
      Platform.environment['JIVIE_PROJECT_RELOCATION_DIAGNOSTIC_DIRECTORY'];
  if (path == null) return null;
  final target = Directory(path);
  if (!target.isAbsolute) throw StateError('Checkpoint path must be absolute');
  final parent = await target.parent.resolveSymbolicLinks(),
      repository = await Directory.current.resolveSymbolicLinks();
  if (parent == repository ||
      parent.startsWith('$repository/') ||
      (await Directory(parent).stat()).mode & 0x3f != 0) {
    throw StateError(
      'Checkpoint requires a private directory outside the repository',
    );
  }
  final output = Directory(
    '$parent/${target.uri.pathSegments.where((s) => s.isNotEmpty).last}',
  );
  final created = await Process.run('/bin/mkdir', ['-m', '700', output.path]);
  if (created.exitCode != 0) {
    throw StateError('Cannot create private checkpoint');
  }
  return output;
}

Future<File> _privateRelocationFile(Directory directory, String name) async {
  final output = File('${directory.path}/$name');
  await output.create(exclusive: true);
  final permissions = await Process.run('/bin/chmod', ['600', output.path]);
  if (permissions.exitCode != 0) {
    throw StateError('Cannot protect checkpoint');
  }
  return output;
}

Future<CollaborationDatabase> _relocationDatabase(
  Directory? checkpoint,
  String role,
) async => CollaborationDatabase(
  checkpoint == null
      ? NativeDatabase.memory()
      : NativeDatabase(
          await _privateRelocationFile(checkpoint, 'live-$role.sqlite'),
        ),
);

Future<_Secure> _relocationSecure(Directory? checkpoint, String role) async {
  if (checkpoint == null) return _Secure();
  final file = await _privateRelocationFile(
    checkpoint,
    'live-$role.secure.json',
  );
  await file.writeAsString('{}', flush: true);
  return _Secure(file);
}

Future<void> _saveRelocationCheckpoint(
  Directory directory,
  String role,
  AccountCryptoV2Workflow account,
  Uint8List recoveryFile,
  Map<String, Object?> state,
) async {
  Future<File> privateFile(String suffix) =>
      _privateRelocationFile(directory, '$role.$suffix');

  final secure = account.store.secure;
  if (secure is! _Secure) throw StateError('Synthetic secure store required');
  await secure.settled;
  final database = await privateFile('sqlite');
  final quotedPath = database.path.replaceAll("'", "''");
  await account.store.database.execute("VACUUM INTO '$quotedPath'");
  final session = account.directory.session;
  await (await privateFile('session.json')).writeAsString(
    jsonEncode({'profile': session.profile.toJson(), 'token': session.token}),
    flush: true,
  );
  await (await privateFile(
    'secure.json',
  )).writeAsString(jsonEncode(secure.values), flush: true);
  await (await privateFile(
    'recovery.file',
  )).writeAsBytes(recoveryFile, flush: true);
  await (await privateFile(
    'state.json',
  )).writeAsString(jsonEncode(state), flush: true);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['JIVIE_PROJECT_RELOCATION_HTTP_FIXTURE'];
  test(
    'actual project sharing relocation >32, parent topology and lost final ACK',
    () async {
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback only');
      final checkpoint = await _relocationCheckpointDirectory();
      var complete = false, phase = 'owner-initialize';
      final elapsed = Stopwatch()..start();
      final references = <String, Object?>{};
      final checkpointRoles = <String>[];
      final checkpointAccounts =
          <
            String,
            ({
              AccountCryptoV2Workflow account,
              Uint8List recoveryFile,
              _Http http,
            })
          >{};
      Future<void> saveBoundary(String label) async {
        if (checkpoint == null) return;
        for (final entry in checkpointAccounts.entries) {
          final saved = entry.value;
          await _saveRelocationCheckpoint(
            checkpoint,
            '$label-${entry.key}',
            saved.account,
            saved.recoveryFile,
            {
              'version': 1,
              'synthetic': true,
              'phase': phase,
              'boundary': label,
              'elapsedMs': elapsed.elapsedMilliseconds,
              'role': entry.key,
              'roles': checkpointRoles,
              'fixturePath': path,
              'references': references,
              'acceptedCommitRequests': saved.http.commits,
              'nextCommitAckLossArmed': saved.http.loseCommit,
            },
          );
        }
        // ignore: avoid_print
        print(
          'relocation.boundary $label elapsedMs=${elapsed.elapsedMilliseconds}',
        );
      }

      void retainOnFailure(
        String role,
        AccountCryptoV2Workflow account,
        Uint8List recoveryFile,
        _Http http,
      ) {
        checkpointRoles.add(role);
        checkpointAccounts[role] = (
          account: account,
          recoveryFile: recoveryFile,
          http: http,
        );
        // Registered after FILE wiping and DB closing callbacks: LIFO saves first.
        addTearDown(() async {
          if (checkpoint == null || complete) return;
          try {
            await _saveRelocationCheckpoint(
              checkpoint,
              role,
              account,
              recoveryFile,
              {
                'version': 1,
                'synthetic': true,
                'phase': phase,
                'elapsedMs': elapsed.elapsedMilliseconds,
                'role': role,
                'roles': checkpointRoles,
                'fixturePath': path,
                'references': references,
                'acceptedCommitRequests': http.commits,
                'nextCommitAckLossArmed': http.loseCommit,
              },
            );
          } catch (_) {
            // Diagnostics never replace the original test failure or prevent wiping.
            print(
              'Optional relocation failure checkpoint unavailable for $role',
            );
          }
        });
      }

      final w = fixture['accounts']['owner']['session'] as Map,
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
      final db = await _relocationDatabase(checkpoint, 'owner');
      addTearDown(db.close);
      final http = _Http(), crypto = CryptoCodec(await SodiumInit.init());
      var current = true;
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: http,
          store: CryptoIdentityStore(
            db,
            await _relocationSecure(checkpoint, 'owner'),
            session.profile.partition,
          ),
          isCurrent: () => current,
        ),
      );
      final file = await account.prepareRecoveryFile();
      addTearDown(() => file.fillRange(0, file.length, 0));
      retainOnFailure('owner', account, file, http);
      await account.verifyAndInitialize(file);
      final access = SessionCryptoAccess(account: account);
      final runtime = CryptoBusinessSession(account, access, db);
      CryptoBusinessRouter.configurePayloads(runtime);
      final scope = crypto.randomId();
      references['sourceScopeId'] = scope;
      phase = 'create-parent';
      await runtime.createScope({
        'id': scope,
        'kind': 'household',
        'name': 'Relocation parent',
        'requestId': crypto.randomId(),
      });
      final project = crypto.randomId(),
          other = crypto.randomId(),
          now = DateTime.utc(2026, 10, 17);
      Map<String, dynamic> payload(Map raw) => Map<String, dynamic>.from(raw)
        ..remove('id')
        ..remove('revision')
        ..remove('createdByAccountId')
        ..remove('updatedByAccountId');
      references.addAll({'projectId': project, 'unrelatedProjectId': other});
      phase = 'stage-projects';
      print('relocation stage projects');
      for (final id in [project, other]) {
        final raw = payload(
          LocalProject(
            id: id,
            title: 'Selected $id',
            description: '',
            createdAt: now,
            updatedAt: now,
            area: ProjectArea.home,
          ).toJson(),
        );
        try {
          await runtime.publishRaw(
            scopeId: scope,
            id: id,
            type: 'project',
            operationId: crypto.randomId(),
            expectedRevision: 0,
            rawPayload: raw,
            localHash: await CryptoBusinessJson.hash(raw),
          );
        } catch (error) {
          print(await db.rows('SELECT verdict,error FROM crypto_received'));
          rethrow;
        }
      }
      phase = 'stage-events';
      print('relocation stage events');
      final eventIds = List.generate(35, (_) => crypto.randomId());
      for (var start = 0; start < eventIds.length; start += 32) {
        final batch = crypto.randomId(),
            op = crypto.randomId(),
            write = await access.writeContext(scope, 'content'),
            signing = await account.signingKey();
        try {
          final proofs = <Map<String, dynamic>>[];
          for (final id in eventIds.skip(start).take(32)) {
            final raw = payload(
              SharedEvent(
                id: id,
                title: 'Finite event',
                notes: '',
                startAt: now,
                endAt: null,
                projectId: project,
                createdAt: now,
                updatedAt: now,
              ).toJson(),
            );
            final address = runtime.address(scope, 'content', 'event', id);
            proofs.add(
              runtime.codec.sealRecord(
                serverId: session.profile.serverId,
                accountId: session.profile.accountId,
                deviceId: account.deviceId,
                batchId: batch,
                scopeId: scope,
                id: address.wireId,
                type: 'event',
                expectedRevision: 0,
                epoch: write.epoch,
                accessRevision: write.accessRevision,
                membershipHeadHash: write.headHash,
                domain: 'content',
                contentContract: write.contentContract,
                operationId: op,
                previousRecordHash: '0' * 64,
                deleted: false,
                plaintext: CryptoBusinessJson.encode({
                  'format': 2,
                  'identity': address.identity,
                  'payload': raw,
                }),
                metadata: await runtime.businessMetadata(
                  scopeId: scope,
                  domain: 'content',
                  type: 'event',
                  canonicalId: id,
                  expectedRevision: 0,
                  rawPayload: raw,
                ),
                contentKey: write.key.key,
                signingKey: signing.key,
              ),
            );
          }
          final commitment = await runtime.codec.commitBatch(
            serverId: session.profile.serverId,
            accountId: session.profile.accountId,
            deviceId: account.deviceId,
            batchId: batch,
            records: proofs,
            signingKey: signing.key,
            projectionToken: (r) async =>
                runtime.codec.projectionGroupToken(r, write.key.key),
          );
          for (var pass = 0; ; pass++) {
            try {
              await runtime.publishPreparedGroup(
                operationId: op,
                localHash: 'a' * 64,
                recordProofs: proofs,
                commitment: commitment,
              );
              break;
            } on CryptoAuthorityPending catch (error) {
              print(
                await db.rows(
                  'SELECT verdict,error,COUNT(*) AS n FROM crypto_received GROUP BY verdict,error',
                ),
              );
              if (error.reason != 'crypto_business_ack_projection_pending' ||
                  pass >= 3)
                rethrow;
            }
          }
        } finally {
          write.key.release();
          signing.release();
        }
      }
      Future<
        ({
          AccountCryptoV2Workflow account,
          CollaborationDatabase db,
          DeviceSession session,
          Uint8List file,
        })
      >
      participant(String kind) async {
        final who = _session(url, fixture['accounts'][kind]['session'] as Map),
            database = await _relocationDatabase(checkpoint, kind);
        addTearDown(database.close);
        final a = AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(crypto),
            session: who,
            transport: http,
            store: CryptoIdentityStore(
              database,
              await _relocationSecure(checkpoint, kind),
              who.profile.partition,
            ),
            isCurrent: () => true,
          ),
        );
        final recovery = await a.prepareRecoveryFile();
        addTearDown(() => recovery.fillRange(0, recovery.length, 0));
        retainOnFailure(kind, a, recovery, http);
        await a.verifyAndInitialize(recovery);
        return (account: a, db: database, session: who, file: recovery);
      }

      Future<void> join(
        CryptoBusinessSession senderRuntime,
        ({
          AccountCryptoV2Workflow account,
          CollaborationDatabase db,
          DeviceSession session,
          Uint8List file,
        })
        p,
        String target,
      ) async {
        final sender = InviteCryptoRepository(senderRuntime.access),
            receiver = InviteCryptoRepository(
              SessionCryptoAccess(account: p.account),
            );
        final invitation = await sender.dispatch('invitations3.create', {
          'scopeId': target,
          'recipient': p.session.profile.username,
          'role': 'member',
          'language': 'en',
          'requestId': crypto.randomId(),
        });
        final id = invitation['invitation']['id'] as String;
        final inspected = await receiver.inspect(
          token: invitation['localToken'] as String,
        );
        await receiver.compareCreator(
          inspected,
          await senderRuntime.access.identities.publicCard(
            await senderRuntime.account.directory.cachedVerifiedDirectory(),
          ),
        );
        await receiver.accept(inspected, actionId: id);
        final accepted = await sender.acceptedRecipient(target, id);
        await sender.compareCreator(
          accepted,
          await receiver.access.identities.publicCard(
            await p.account.directory.cachedVerifiedDirectory(),
          ),
        );
        await sender.admit(
          accepted,
          await ScopeCryptoManager(senderRuntime.access).reviewRotation(target),
        );
        expect(await receiver.resumeAccepted(id), target);
      }

      phase = 'admit-initiating-manager';
      final actor = await participant('other');
      await join(runtime, actor, scope);
      final actorRuntime = CryptoBusinessSession(
        actor.account,
        SessionCryptoAccess(account: actor.account),
        actor.db,
      );
      CryptoBusinessRouter.configurePayloads(actorRuntime);
      await actorRuntime.pullVerified(scope, 'content');
      await actorRuntime.pullVerified(scope, 'finance');
      final router = CryptoBusinessRouter(
        database: actor.db,
        accountFor: (_) async => actor.account,
      );
      Future<Map<String, dynamic>> dispatch(
        String op,
        Map<String, Object?> params,
      ) => router.dispatch(
        session: actor.session,
        operation: op,
        params: params,
        protectedScopeIds: {scope},
      );
      final task = crypto.randomId(),
          ledger = crypto.randomId(),
          expense = crypto.randomId();
      references.addAll({
        'taskId': task,
        'ledgerId': ledger,
        'expenseId': expense,
      });
      phase = 'stage-task-finance-attachment';
      final taskRaw = payload(
        LocalTask(
          id: task,
          title: 'Move task',
          notes: '',
          projectId: project,
          dueAt: null,
          isCompleted: false,
          createdAt: now,
          updatedAt: now,
        ).toJson(),
      );
      await runtime.publishRaw(
        scopeId: scope,
        id: task,
        type: 'task',
        operationId: crypto.randomId(),
        expectedRevision: 0,
        rawPayload: taskRaw,
        localHash: await CryptoBusinessJson.hash(taskRaw),
      );
      final ledgerRaw = SharedFinanceAccount(
        id: ledger,
        name: 'Move ledger',
        currency: 'EUR',
        createdAt: now,
        updatedAt: now,
      ).toPayload(contractVersion: 3);
      await runtime.publishRaw(
        scopeId: scope,
        domain: 'finance',
        id: ledger,
        type: 'financeAccount',
        operationId: crypto.randomId(),
        expectedRevision: 0,
        rawPayload: ledgerRaw,
        localHash: await CryptoBusinessJson.hash(ledgerRaw),
      );
      for (var rev = 0; rev < 21; rev++) {
        final raw = <String, dynamic>{
          ...SharedFinanceEntry(
            id: expense,
            accountId: ledger,
            taskId: task,
            kind: FinanceEntryKind.expense,
            status: SharedFinanceStatus.planned,
            amountMinor: 500 + rev,
            currency: 'EUR',
            title: 'Moved audit $rev',
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
          ).toPayload(contractVersion: 3),
          'futureFloat': 1.25,
        };
        await runtime.publishRaw(
          scopeId: scope,
          domain: 'finance',
          id: expense,
          type: 'financeEntry',
          operationId: crypto.randomId(),
          expectedRevision: rev,
          rawPayload: raw,
          localHash: await CryptoBusinessJson.hash(raw),
        );
      }
      final docs = CryptoBusinessDocuments(runtime),
          attachment = crypto.randomId();
      references['attachmentId'] = attachment;
      final bytes = Uint8List.fromList(
            List.generate(300000, (i) => (i * 31 + 7) & 255),
          ),
          byteHash = await cryptoSha256(bytes);
      final fileTarget = <String, Object?>{
        'scopeId': scope,
        'targetType': 'task',
        'targetId': task,
        'id': attachment,
      };
      await docs.dispatch('attachments.begin', {
        ...fileTarget,
        'requestId': attachment,
        'name': 'move.txt',
        'mime': 'text/plain',
        'size': bytes.length,
        'sha256': byteHash,
      });
      for (var offset = 0; offset < bytes.length; offset += 262144) {
        await docs.dispatch('attachments.chunk', {
          ...fileTarget,
          'offset': offset,
          'dataBase64': base64Encode(
            Uint8List.sublistView(
              bytes,
              offset,
              (offset + 262144).clamp(0, bytes.length),
            ),
          ),
        });
      }
      await docs.dispatch('attachments.complete', {
        ...fileTarget,
        'requestId': crypto.randomId(),
      });
      phase = 'relocation-preview';
      print('relocation stage preview');
      late Map<String, dynamic> preview;
      for (var pass = 0; ; pass++) {
        try {
          preview = await dispatch('scopes.projectSharingPreview', {
            'scopeId': scope,
            'projectId': project,
          });
          break;
        } on CryptoAuthorityPending catch (error) {
          print(
            await actor.db.rows(
              'SELECT verdict,error,COUNT(*) AS n FROM crypto_received GROUP BY verdict,error',
            ),
          );
          print(
            await actor.db.rows(
              'SELECT domain,complete FROM crypto_scope_state WHERE partition=? AND scope_id=?',
              [actor.session.profile.partition, scope],
            ),
          );
          if (error.reason != 'crypto_inline_delete_inventory_pending' ||
              pass >= 3)
            rethrow;
          await actorRuntime.pullVerified(scope, 'content');
          await actorRuntime.pullVerified(scope, 'finance');
        }
      }
      expect(preview['canApply'], true, reason: jsonEncode(preview));
      expect((preview['movedRecordIds'] as List).length, greaterThan(32));
      expect(preview['movedFinanceRecordIds'], containsAll([ledger, expense]));
      final request = <String, Object?>{
        'scopeId': scope,
        'projectId': project,
        'previewHash': preview['previewHash'],
        'requestId': crypto.randomId(),
      };
      references['applyRequest'] = request;
      phase = 'apply-with-lost-final-ack';
      http.loseCommit = true;
      await expectLater(
        (() async {
          try {
            return await dispatch('scopes.projectSharingApply', request);
          } catch (_) {
            print(
              await actor.db.rows(
                r"SELECT operation,state,json_extract(response,'$.code') AS code,json_extract(response,'$.response.errorCode') AS errorCode FROM crypto_outbox WHERE state!='applied'",
              ),
            );
            rethrow;
          }
        })(),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'network',
          ),
        ),
      );
      expect(http.commits.length, 1);
      phase = 'retry-exact-apply';
      final result = await dispatch('scopes.projectSharingApply', request);
      expect((result['scope'] as Map)['id'], project);
      expect(http.commits.length, 1);
      await saveBoundary('afterCommit');
      phase = 'normal-target-reader';
      final rebuilt = CryptoBusinessSession(
        actor.account,
        SessionCryptoAccess(account: actor.account),
        actor.db,
      );
      CryptoBusinessRouter.configurePayloads(rebuilt);
      for (var pass = 0; pass < 5; pass++) {
        await rebuilt.pullVerified(project, 'content', attest: false);
        final rows = await actor.db.rows(
          'SELECT COUNT(*) AS n FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=\'content\' AND deleted=0',
          [actor.session.profile.partition, project],
        );
        if (rows.single['n'] == (preview['movedRecordIds'] as List).length + 1)
          break;
        print(
          await db.rows(
            'SELECT verdict,error,COUNT(*) AS n FROM crypto_received GROUP BY verdict,error',
          ),
        );
      }
      for (final id in [project, ...eventIds]) {
        final row = await rebuilt.record(
          project,
          'content',
          id,
          type: id == project ? 'project' : 'event',
        );
        expect(row, isNotNull, reason: id);
        expect(row!['deleted'], 0);
        expect((jsonDecode(row['projection'] as String) as Map)['revision'], 1);
      }
      expect(
        (await rebuilt.record(
          scope,
          'content',
          other,
          type: 'project',
        ))!['deleted'],
        0,
      );
      final parent = await rebuilt.scopes();
      expect(
        (parent['scopes'] as List).where((s) => s['id'] == project).length,
        1,
      );
      await rebuilt.pullVerified(project, 'finance', attest: false);
      final movedExpense = await rebuilt.record(
        project,
        'finance',
        expense,
        type: 'financeEntry',
      );
      expect(
        (jsonDecode(movedExpense!['projection'] as String) as Map)['revision'],
        21,
      );
      phase = 'relocated-audit-read';
      final preserved = <Map<String, dynamic>>[];
      await for (final page in CryptoFinanceAuditEvidence(
        rebuilt,
      ).historyPages(project, expense)) {
        preserved.addAll(page);
      }
      expect(preserved.length, 21);
      expect(
        preserved.every((e) => e['revisionNamespace'] == 'relocated'),
        true,
      );
      final allAudit = jsonEncode(preserved);
      expect(allAudit, contains('futureFloat'));
      expect(allAudit, contains('1.25'));
      phase = 'relocated-attachment-read';
      final readDocs = CryptoBusinessDocuments(rebuilt),
          received = BytesBuilder(copy: false);
      while (received.length < bytes.length) {
        final page = await readDocs.dispatch('attachments.get', {
          'scopeId': project,
          'targetType': 'task',
          'targetId': task,
          'id': attachment,
          'offset': received.length,
          'limit': 262144,
        });
        received.add(base64Decode(page['dataBase64'] as String));
      }
      expect(await cryptoSha256(received.takeBytes()), byteHash);
      await rebuilt.pullVerified(scope, 'content', attest: false);
      final metadata = (await actor.db.rows(
        "SELECT raw_payload FROM crypto_business_records WHERE partition=? AND scope_id=? AND type='scopeMetadata'",
        [actor.session.profile.partition, scope],
      )).single;
      final topology =
          (jsonDecode(metadata['raw_payload'] as String)
                  as Map)['financeTopology']
              as Map;
      expect(topology['generation'], 1);
      expect(topology['childTokens'], [
        await CryptoFinanceTopology.childToken(
          session.profile.serverId,
          scope,
          project,
        ),
      ]);
      phase = 'target-only-admission-and-reader';
      final targetOnly = await participant('recipient');
      await join(rebuilt, targetOnly, project);
      await saveBoundary('afterAdmission');
      final targetReader = CryptoBusinessSession(
        targetOnly.account,
        SessionCryptoAccess(account: targetOnly.account),
        targetOnly.db,
      );
      CryptoBusinessRouter.configurePayloads(targetReader);
      await targetReader.pullVerified(project, 'content');
      Future<({Map<String, Object?> state, List<Map<String, Object?>> blocked})>
      recipientContentState() async {
        final state = (await targetOnly.db.rows(
          'SELECT * FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
          [targetOnly.session.profile.partition, project, 'content'],
        )).single;
        final blocked = await targetOnly.db.rows(
          "SELECT verdict,error FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND verdict NOT IN ('verified','superseded')",
          [targetOnly.session.profile.partition, project, 'content'],
        );
        return (state: state, blocked: blocked);
      }

      var recipientState = await recipientContentState();
      if (recipientState.blocked.isNotEmpty &&
          recipientState.blocked.every(
            (r) =>
                r['verdict'] == 'received' &&
                r['error'] == 'crypto_history_authority_changed',
          )) {
        // An interrupted authority window can be retried once through the
        // unchanged public reader; it never acknowledges the old pending rows.
        await targetReader.pullVerified(project, 'content');
        recipientState = await recipientContentState();
      }
      expect(recipientState.blocked, isEmpty);
      // Data completion is required here. Checkpoint completeness is required
      // again below after the explicit new-device rotation, with its exact head.

      expect(
        recipientState.state['projection_cursor'],
        recipientState.state['transport_cursor'],
      );
      expect(
        recipientState.state['projection_cursor'],
        recipientState.state['scope_sequence'],
      );
      final recipientContent = await targetOnly.db.rows(
        'SELECT COUNT(*) AS n FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=?',
        [targetOnly.session.profile.partition, project, 'content'],
      );
      expect(
        recipientContent.single['n'],
        (preview['movedRecordIds'] as List).length + 1,
      );
      for (final id in eventIds) {
        expect(
          await targetReader.record(project, 'content', id, type: 'event'),
          isNotNull,
        );
      }
      await targetReader.pullVerified(project, 'finance');
      expect(
        await targetReader.record(project, 'content', project, type: 'project'),
        isNotNull,
      );
      expect(
        await targetOnly.db.rows(
          'SELECT id FROM crypto_business_records WHERE scope_id=?',
          [scope],
        ),
        isEmpty,
      );
      final oldRecipientCheckpoints = <Map<String, Object?>>[];
      for (final candidate in await targetOnly.db.rows(
        "SELECT request_id,signed_body,state FROM crypto_outbox WHERE partition=? AND operation='crypto2.domain.checkpoint' AND state='blocked'",
        [targetOnly.session.profile.partition],
      )) {
        final proof = jsonDecode(candidate['signed_body'] as String) as Map;
        final command =
            jsonDecode(
                  utf8.decode(base64Decode(proof['commandBase64'] as String)),
                )
                as Map;
        final payload = command['payload'] as Map;
        if (payload['scopeId'] == project && payload['domain'] == 'content') {
          oldRecipientCheckpoints.add(candidate);
        }
      }
      await saveBoundary('afterRecipientRead');
      phase = 'new-login-file-recovery';
      final login = await http.call(
        serverUrl: url,
        operation: 'auth.login',
        params: {
          'username': fixture['accounts']['other']['username'],
          'password': fixture['accounts']['other']['password'],
          'deviceName': 'Relocation FILE recovery',
        },
        allowLocalHttp: true,
      );
      final coldSession = _session(url, login),
          coldDb = await _relocationDatabase(checkpoint, 'coldReader');
      addTearDown(coldDb.close);
      final recovered = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: coldSession,
          transport: http,
          store: CryptoIdentityStore(
            coldDb,
            await _relocationSecure(checkpoint, 'coldReader'),
            coldSession.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      retainOnFailure('coldReader', recovered, actor.file, http);
      await recovered.recover(actor.file);
      await CryptoScopeObservations(
        recovered,
      ).hydrateObservedScopes(actor.file);
      final cold = CryptoBusinessSession(
        recovered,
        SessionCryptoAccess(account: recovered),
        coldDb,
      );
      CryptoBusinessRouter.configurePayloads(cold);
      await saveBoundary('afterHydrate');
      String? confirmedHead;
      try {
        await cold.access.currentHead(project, online: true);
      } on CryptoAuthorityPending catch (error) {
        if (error.reason != 'scope_authority_history_pending') rethrow;
        // FILE restores keys. A successor not included in this account's own
        // observed history still needs the existing explicit recovery review.
        phase = 'new-device-history-review';
        final source = await cold.access.recoveryCandidateHead(project);
        final manager = ScopeCryptoManager(cold.access);
        final reviews = await manager.pendingRotationReviews(project);
        final review =
            reviews
                .where((r) => r.sourceHeadHash == source.headHash)
                .firstOrNull ??
            await manager.reviewRotation(project);
        expect(review.historyBasis, 'reviewedRecoveryBaseline');
        final roster = await manager.proposedMembers(review) ?? source.members;
        expect(roster.map((m) => m['accountId']).toSet(), {
          session.profile.accountId,
          actor.session.profile.accountId,
          targetOnly.session.profile.accountId,
        });
        final expectedRows = review.domains.values.fold<int>(
          0,
          (n, value) => n + ((value as Map)['count'] as int),
        );
        expect(
          expectedRows,
          (preview['movedRecordIds'] as List).length +
              (preview['movedFinanceRecordIds'] as List).length +
              1,
        );
        var inspected = 0, taskSeen = false, expenseSeen = false;
        String? after;
        while (inspected < expectedRows) {
          final rows = await manager.previewRotation(
            review,
            afterId: after,
            limit: 20,
          );
          try {
            expect(rows, isNotEmpty);
            for (final row in rows) {
              expect(after == null || row.id.compareTo(after) > 0, isTrue);
              after = row.id;
              inspected++;
              final stored = await coldDb.rows(
                'SELECT wire FROM crypto_scope_review_records WHERE partition=? AND scope_id=? AND review_id=? AND record_id=?',
                [coldSession.profile.partition, project, review.id, row.id],
              );
              expect(stored, hasLength(1));
              final wire = jsonDecode(stored.single['wire'] as String) as Map;
              final proof =
                  (wire['authorization'] as Map)['recordProof'] as Map;
              final body =
                  jsonDecode(
                        utf8.decode(
                          base64Decode(proof['commandBase64'] as String),
                        ),
                      )
                      as Map;
              expect(body['scopeId'], project);
              expect(body['id'], row.id);
              if (body['deleted'] == true) {
                expect(row.plaintext, isNull);
                continue;
              }
              expect(row.plaintext, isNotNull);
              final envelope = jsonDecode(utf8.decode(row.plaintext!)) as Map;
              final identity = envelope['identity'] as Map;
              expect(identity.keys.toSet(), {'sourceKind', 'canonicalId'});
              expect(
                CryptoBusinessJson.canonical(identity),
                CryptoBusinessJson.canonical(
                  (body['metadata'] as Map)['identity'],
                ),
              );
              final canonical = identity['canonicalId'];
              final raw = envelope['payload'] as Map;
              if (canonical == task) {
                expect(body['type'], 'task');
                expect(body['domain'], 'content');
                expect(raw['title'], 'Move task');
                expect(raw['projectId'], project);
                taskSeen = true;
              }
              if (canonical == expense) {
                expect(body['type'], 'financeEntry');
                expect(body['domain'], 'finance');
                expect(raw['taskId'], task);
                expect(raw['amountMinor'], 520);
                expect(raw['futureFloat'], 1.25);
                expenseSeen = true;
              }
            }
          } finally {
            for (final row in rows) {
              row.dispose();
            }
          }
        }
        expect(inspected, expectedRows);
        expect(taskSeen && expenseSeen, isTrue);
        references['recoveryReviewId'] = review.id;
        references['recoverySourceHeadHash'] = source.headHash;
        await saveBoundary('afterReview');
        await expectLater(
          manager.confirmRotation(review, acceptedCandidateHistory: false),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (error) => error.reason,
              'reason',
              'scope_review_confirmation_required',
            ),
          ),
        );
        // Explicit synthetic approval of the same UI review, never a
        // production fallback or automatic acceptance of candidate history.
        phase = 'new-device-confirm-reviewed-history';
        final confirmed = await manager.confirmRotation(
          review,
          acceptedCandidateHistory: true,
        );
        confirmedHead = confirmed.headHash;
        references['confirmedRecoveryHeadHash'] = confirmed.headHash;
        references['confirmedRecoveryEpoch'] = confirmed.epoch;
        expect(confirmed.headHash, isNot(source.headHash));
        expect(
          confirmed.member(recovered.directory.accountId)['deviceSnapshotHash'],
          (await recovered.directory.requireFresh()).deviceSnapshotHash,
        );
        expect(
          (await cold.access.currentHead(project, online: true)).headHash,
          confirmed.headHash,
        );
      }
      await saveBoundary('afterConfirmation');
      phase = 'new-device-normal-reader';
      await cold.access.hydrateScopeKeys(project);
      await cold.pullVerified(project, 'content', attest: false);
      await cold.pullVerified(project, 'finance', attest: false);
      expect(
        await cold.record(project, 'content', project, type: 'project'),
        isNotNull,
      );
      expect(
        (jsonDecode(
              (await cold.record(
                    project,
                    'finance',
                    expense,
                    type: 'financeEntry',
                  ))!['projection']
                  as String,
            )
            as Map)['revision'],
        21,
      );
      for (final domain in ['content', 'finance']) {
        final rows = await coldDb.rows(
          'SELECT verdict,COUNT(*) AS n FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? GROUP BY verdict',
          [coldSession.profile.partition, project, domain],
        );
        expect(rows, [
          {
            'verdict': 'verified',
            'n': domain == 'content'
                ? (preview['movedRecordIds'] as List).length + 1
                : (preview['movedFinanceRecordIds'] as List).length,
          },
        ]);
      }
      await saveBoundary('afterColdRead');
      phase = 'recipient-after-recovery-rotation';
      await targetReader.pullVerified(project, 'content');
      final finalRecipient = await recipientContentState();
      expect(finalRecipient.blocked, isEmpty);
      expect(finalRecipient.state['complete'], 1);
      expect(
        finalRecipient.state['projection_cursor'],
        finalRecipient.state['transport_cursor'],
      );
      expect(
        finalRecipient.state['projection_cursor'],
        finalRecipient.state['scope_sequence'],
      );
      expect(
        (await targetOnly.db.rows(
          "SELECT COUNT(*) AS n FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND verdict='verified'",
          [targetOnly.session.profile.partition, project, 'content'],
        )).single['n'],
        (preview['movedRecordIds'] as List).length + 1,
      );
      final recipientHead = await targetReader.access.currentHead(
        project,
        online: true,
      );
      final recoveredHead = await cold.access.currentHead(
        project,
        online: true,
      );
      expect(recipientHead.headHash, recoveredHead.headHash);
      if (confirmedHead != null) expect(recipientHead.headHash, confirmedHead);
      final context = await targetReader.access.readContext(project, 'content');
      expect(context.headHash, recipientHead.headHash);
      expect(
        await targetReader.hasReusableCheckpoint(project, 'content', context),
        isTrue,
      );
      for (final old in oldRecipientCheckpoints) {
        final exact = await targetOnly.db.rows(
          'SELECT request_id,signed_body,state FROM crypto_outbox WHERE partition=? AND request_id=?',
          [targetOnly.session.profile.partition, old['request_id']],
        );
        expect(exact, [old]);
      }
      expect(
        await targetOnly.db.rows(
          'SELECT id FROM crypto_business_records WHERE scope_id=?',
          [scope],
        ),
        isEmpty,
      );
      await saveBoundary('complete');
      complete = true;
      print('relocation complete normal route');
    },
    skip: path == null,
    // This opt-in HTTP representative includes the measured 5–7 minute prefix,
    // approximately 5 minute recipient pass, and more than 8 minute cold pass.
    // A finite 30 minute budget changes no production retry/rate-limit policy.
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
