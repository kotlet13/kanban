// Static synthetic stage markers only; no payload/credential logging.
// ignore_for_file: avoid_print

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
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
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

// Replays precisely the old native createScope sequence: real signed scope,
// activation and scopeMetadata; only the new bootstrap step is absent.
class _OldNativeCreation extends CryptoBusinessSession {
  _OldNativeCreation(super.account, super.access, super.db);
  @override
  Future<Map<String, dynamic>?> ensureNativeProjectRoot(
    String scope,
    String? parent,
  ) async => null;
}

class _IncompleteInventory extends CryptoBusinessSession {
  _IncompleteInventory(super.account, super.access, super.db);
  @override
  Future<void> pullVerified(
    String scope,
    String domain, {
    bool attest = true,
  }) async {}
}

Future<
  ({
    CollaborationDatabase db,
    CryptoCodec crypto,
    AccountCryptoV2Workflow account,
    CollaborationRepository repository,
    DeviceSession session,
  })
>
_openFixture(String path) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final fixture = jsonDecode(await File(path).readAsString()) as Map;
  final url = fixture['serverUrl'] as String;
  if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
    throw StateError('Synthetic loopback required');
  }
  final w = fixture['accounts']['owner']['session'] as Map;
  final u = w['user'] as Map, d = w['device'] as Map;
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
  final db = CollaborationDatabase(NativeDatabase.memory());
  final transport = HttpCollaborationTransport();
  final crypto = CryptoCodec(await SodiumInit.init());
  final account = AccountCryptoV2Workflow(
    AccountDirectoryRepository(
      reducer: AccountDirectoryV2(crypto),
      session: session,
      transport: transport,
      store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
      isCurrent: () => true,
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
  await repository.syncNow();
  return (
    db: db,
    crypto: crypto,
    account: account,
    repository: repository,
    session: session,
  );
}

void main() {
  final path = Platform.environment['JIVIE_NATIVE_CHILD_TASK_FIXTURE'];
  test(
    'fresh native child create and pull permits its first ordinary task',
    () async {
      final (:db, :crypto, :account, :repository, :session) =
          await _openFixture(path!);
      final parent = await repository.createScope(
        'Synthetic parent',
        kind: SharedScopeKind.organization,
      );
      print('native_child_stage=parent_created');
      final child = await repository.createScope(
        'Synthetic child',
        kind: SharedScopeKind.project,
        parentScopeId: parent,
        organizationId: parent,
      );
      print('native_child_stage=child_created');
      await repository.syncNow();
      final scoped = repository.state.scopes.singleWhere((s) => s.id == child);
      expect(scoped.parentSpaceId, parent);
      expect(scoped.canEdit, true);
      final roots = await db.rows(
        "SELECT id FROM records WHERE partition=? AND scope_id=? AND type='project' AND deleted=0",
        [session.profile.partition, child],
      );
      final metadata = await db.rows(
        "SELECT id FROM crypto_business_records WHERE partition=? AND scope_id=? AND type='scopeMetadata'",
        [session.profile.partition, child],
      );
      expect(metadata, hasLength(1));
      expect(roots, hasLength(1));
      expect(roots.single['id'], child);
      expect(
        repository.state.dataForScope(child).projects.single.title,
        'Synthetic child',
      );
      print(
        'native_child_stage=pulled project_rows=${roots.length} signed_metadata_rows=${metadata.length}',
      );
      try {
        final task = await repository.createTask(
          scopeId: child,
          title: 'Synthetic first child task',
          notes: 'Synthetic preserved note',
          projectId: child,
        );
        final tasks = repository.state.dataForScope(child).tasks;
        expect(tasks.where((t) => t.id == task), hasLength(1));
        expect(tasks.singleWhere((t) => t.id == task).projectId, child);
        print('native_child_stage=first_task_created');
        await repository.syncNow();
        final access = SessionCryptoAccess(account: account);
        final old = _OldNativeCreation(account, access, db);
        CryptoBusinessRouter.configurePayloads(old);
        Future<String> oldChild(String name) async {
          final id = crypto.randomId();
          await access.withVerifiedOperation(
            () => old.createScope({
              'id': id,
              'kind': 'project',
              'name': name,
              'parentScopeId': parent,
              'organizationId': parent,
              'requestId': crypto.randomId(),
            }),
          );
          return id;
        }

        final historical = await oldChild('Existing malformed native child');
        final list = crypto.randomId(),
            timestamp = DateTime.now().toUtc().toIso8601String();
        final listRaw = {
          'title': 'Preserved list',
          'createdAt': timestamp,
          'updatedAt': timestamp,
        };
        await old.publishRaw(
          scopeId: historical,
          id: list,
          type: 'shoppingList',
          operationId: crypto.randomId(),
          expectedRevision: 0,
          rawPayload: listRaw,
          localHash: await CryptoBusinessJson.hash(listRaw),
        );
        await repository.syncNow();
        expect(repository.state.dataForScope(historical).projects, isEmpty);
        final kept = await db.rows(
          "SELECT type,record_proof_hash,raw_payload FROM crypto_business_records WHERE partition=? AND scope_id=? ORDER BY id",
          [session.profile.partition, historical],
        );
        final repairedTask = await repository.createTask(
          scopeId: historical,
          title: 'First existing-child task',
          notes: 'Preserved note',
          projectId: historical,
        );
        final repaired = repository.state.dataForScope(historical);
        expect(repaired.projects.single.id, historical);
        expect(
          repaired.projects.single.title,
          'Existing malformed native child',
        );
        expect(repaired.shoppingLists.single.id, list);
        expect(repaired.tasks.single.id, repairedTask);
        final after = await db.rows(
          "SELECT type,record_proof_hash,raw_payload FROM crypto_business_records WHERE partition=? AND scope_id=? AND type!='project' ORDER BY id",
          [session.profile.partition, historical],
        );
        expect(after, kept);
        final stable = await db.rows(
          "SELECT * FROM crypto_business_requests WHERE partition=? AND scope_id=?",
          [session.profile.partition, historical],
        );
        final ordinaryBeforeRetry = await db.rows(
          'SELECT * FROM records WHERE partition=? AND scope_id=? ORDER BY id',
          [session.profile.partition, historical],
        );
        final outboxBeforeRetry = await db.rows(
          'SELECT * FROM outbox WHERE partition=? AND scope_id=? ORDER BY sequence',
          [session.profile.partition, historical],
        );
        expect(outboxBeforeRetry, hasLength(1));
        final normal = CryptoBusinessSession(
          account,
          SessionCryptoAccess(account: account),
          db,
        );
        CryptoBusinessRouter.configurePayloads(normal);
        await normal.ensureNativeProjectRoot(historical, parent);
        await normal.ensureNativeProjectRoot(historical, parent);
        expect(
          await db.rows(
            "SELECT * FROM crypto_business_requests WHERE partition=? AND scope_id=?",
            [session.profile.partition, historical],
          ),
          stable,
        );
        expect(
          await db.rows(
            "SELECT 1 FROM crypto_business_records WHERE partition=? AND scope_id=? AND type='project'",
            [session.profile.partition, historical],
          ),
          hasLength(1),
        );
        expect(
          await db.rows(
            'SELECT * FROM records WHERE partition=? AND scope_id=? ORDER BY id',
            [session.profile.partition, historical],
          ),
          ordinaryBeforeRetry,
        );
        expect(
          await db.rows(
            'SELECT * FROM outbox WHERE partition=? AND scope_id=? ORDER BY sequence',
            [session.profile.partition, historical],
          ),
          outboxBeforeRetry,
        );
        print('native_child_stage=existing_child_repair_idempotent');

        // Actual signed tombstone is authoritative and must never be recreated.
        final root = (await normal.record(
          historical,
          'content',
          historical,
          type: 'project',
        ))!;
        await normal.publishRaw(
          scopeId: historical,
          id: historical,
          type: 'project',
          operationId: crypto.randomId(),
          expectedRevision: root['crypto_revision'] as int,
          rawPayload: null,
          localHash: await CryptoBusinessJson.hash({'deleted': true}),
        );
        await expectLater(
          normal.ensureNativeProjectRoot(historical, parent),
          throwsA(
            isA<CollaborationException>().having(
              (e) => e.code,
              'code',
              'record_deleted',
            ),
          ),
        );
        print('native_child_stage=tombstone_rejected');
      } on CollaborationException catch (error) {
        print('native_child_stage=first_task_failed code=${error.code}');
        rethrow;
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'incomplete inventory rejects native project root repair without an intent',
    () async {
      final (:db, :crypto, :account, :repository, :session) =
          await _openFixture(path!);
      final parent = await repository.createScope(
        'Incomplete guard parent',
        kind: SharedScopeKind.organization,
      );
      final access = SessionCryptoAccess(account: account);
      final old = _OldNativeCreation(account, access, db);
      CryptoBusinessRouter.configurePayloads(old);
      Future<String> oldChild(String name) async {
        final id = crypto.randomId();
        await access.withVerifiedOperation(
          () => old.createScope({
            'id': id,
            'kind': 'project',
            'name': name,
            'parentScopeId': parent,
            'organizationId': parent,
            'requestId': crypto.randomId(),
          }),
        );
        return id;
      }

      final incomplete = await oldChild('Incomplete native child');
      await repository.syncNow();
      await db.execute(
        "UPDATE crypto_scope_state SET complete=0 WHERE partition=? AND scope_id=? AND domain='content'",
        [session.profile.partition, incomplete],
      );
      final unavailable = _IncompleteInventory(
        account,
        SessionCryptoAccess(account: account),
        db,
      );
      await expectLater(
        unavailable.ensureNativeProjectRoot(incomplete, parent),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'crypto_project_root_inventory_pending',
          ),
        ),
      );
      expect(
        await db.rows(
          "SELECT 1 FROM crypto_business_records WHERE partition=? AND scope_id=? AND type='project'",
          [session.profile.partition, incomplete],
        ),
        isEmpty,
      );
      expect(
        await db.rows("SELECT 1 FROM local_meta WHERE name=?", [
          'crypto_native_project_root_v1:${session.profile.partition}:$incomplete',
        ]),
        isEmpty,
      );
      print('native_child_stage=incomplete_inventory_rejected');
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
