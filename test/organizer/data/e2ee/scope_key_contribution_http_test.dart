import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/e2ee/scope_key_contributions.dart';

class _MemorySecure implements AccountCryptoStore {
  final rows = <String, String>{};
  @override
  Future<String?> read(String partition) async => rows[partition];
  @override
  Future<void> write(String partition, String value) async {
    rows[partition] = value;
  }
}

DeviceSession _session(String url, Map<String, dynamic> wire) {
  final user = wire['user'] as Map, device = wire['device'] as Map;
  return DeviceSession(
    AccountSession(
      serverUrl: url,
      serverId: wire['serverId'],
      accountId: user['accountId'],
      userId: user['id'],
      username: user['username'],
      displayName: user['displayName'],
      deviceId: device['id'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        device['expiresAt'] * 1000,
      ),
      allowLocalHttp: true,
    ),
    wire['token'],
  );
}

void main() {
  final path = Platform.environment['JIVIE_CRYPTO2_TRANSFER_HTTP_FIXTURE'];
  test(
    'three real contributors transfer ownership without exposing future domain keys to departing owner',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback required');
      }
      final crypto = CryptoCodec(await SodiumInit.init()),
          http = HttpCollaborationTransport();
      final dbs = List.generate(
        3,
        (_) => CollaborationDatabase(NativeDatabase.memory()),
      );
      final names = ['oldOwner', 'newOwner', 'financeContributor'];
      final accounts = <AccountCryptoV2Workflow>[];
      for (var i = 0; i < 3; i++) {
        final session = _session(url, fixture['accounts'][names[i]]['session']);
        final account = AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(crypto),
            session: session,
            transport: http,
            store: CryptoIdentityStore(
              dbs[i],
              _MemorySecure(),
              session.profile.partition,
            ),
            isCurrent: () => true,
          ),
        );
        accounts.add(account);
      }
      try {
        for (final account in accounts) {
          final file = await account.prepareRecoveryFile();
          try {
            await account.verifyAndInitialize(file);
          } finally {
            file.fillRange(0, file.length, 0);
          }
        }
        final accesses = [
          for (final a in accounts) SessionCryptoAccess(account: a),
        ];
        final dirs = [
          for (final a in accounts) await a.directory.requireFresh(),
        ];
        final scopeId = fixture['transferScope']['id'] as String;
        for (var i = 0; i < 3; i++)
          for (var j = 0; j < 3; j++) {
            if (i != j) {
              await accesses[i].verifyContactCard(
                scopeId,
                dirs[j].accountId,
                await accesses[j].identities.publicCard(dirs[j]),
              );
            }
          }
        final managers = [for (final a in accesses) ScopeCryptoManager(a)];
        final catalog = await accounts[0].directory.call(
          'crypto2.scopes.catalog',
        );
        final metadata =
            (catalog['scopes'] as List).singleWhere((s) => s['id'] == scopeId)
                as Map;
        Future<dynamic> genesis() => managers[0].initializeEmptyScope(
          scopeId: scopeId,
          accessRevision: metadata['accessRevision'],
          members: (metadata['members'] as List).cast<Map<String, dynamic>>(),
        );
        await expectLater(genesis(), throwsA(isA<CryptoAuthorityPending>()));
        final financeDraft =
            (await managers[2].financeDrafts(scopeId)).single['draftId']
                as String;
        await managers[2].contributeFinanceDraft(scopeId, financeDraft);
        await expectLater(genesis(), throwsA(isA<CryptoAuthorityPending>()));
        await managers[2].publishFinanceGrants(scopeId, financeDraft);
        final initial = await genesis();
        for (var i = 1; i < 3; i++) {
          await accesses[i].currentHead(scopeId, online: true);
          await accesses[i].hydrateScopeKeys(scopeId);
        }
        final proofCodec = CryptoRecordProofCodec(crypto),
            observed = <String>[];
        CryptoSyncRepository sync(int i) => CryptoSyncRepository(
          crypto: crypto,
          session: accounts[i].directory.session,
          transport: http,
          store: CryptoSyncStore(dbs[i], accounts[i].store.partition),
          signingKey: accesses[i].signingKey,
          authorKey: accesses[i].recordAuthority,
          contentKey: accesses[i].recordKey,
          beforeDelivery: accesses[i].beforeDelivery,
          readContext: accesses[i].readContext,
          project: (rows) async {
            for (final row in rows) {
              if (row.plaintext != null) {
                observed.add(utf8.decode(row.plaintext!));
            }
              }
          },
          isCurrent: () => true,
        );
        Future<void> publish(int i, String text) async {
          final context = await accesses[i].writeContext(scopeId, 'content'),
              signing = await accounts[i].signingKey(),
              batch = crypto.randomId();
          try {
            final canonicalId=crypto.randomId();
            final proof = proofCodec.sealRecord(
              serverId: dirs[i].serverId,
              accountId: dirs[i].accountId,
              deviceId: accounts[i].deviceId,
              batchId: batch,
              scopeId: scopeId,
              id: cryptoWireRecordId(dirs[i].serverId,scopeId,'idea',canonicalId),
              type: 'idea',
              expectedRevision: 0,
              epoch: context.epoch,
              accessRevision: context.accessRevision,
              membershipHeadHash: context.headHash,
              domain: 'content',
              contentContract: 6,
              operationId: crypto.randomId(),
              previousRecordHash: cryptoZeroHash,
              deleted: false,
              plaintext: Uint8List.fromList(utf8.encode(text)),
              metadata: {
                'identity':{'sourceKind':'records','canonicalId':canonicalId},
                'references': [],
                'uniqueRefs': [],
                'blobIds': [],
                'notificationState': {
                  'version': 1,
                  'kind': 'created',
                  'assigneeAccountIds': [],
                  'groupTargetId': null,
                },
              },
              contentKey: context.key.key,
              signingKey: signing.key,
            );
            final commitment = await proofCodec.commitBatch(
              serverId: dirs[i].serverId,
              accountId: dirs[i].accountId,
              deviceId: accounts[i].deviceId,
              batchId: batch,
              records: [proof],
              signingKey: signing.key,
              projectionToken: (r) async =>
                  proofCodec.projectionGroupToken(r, context.key.key),
            );
            await sync(i).enqueueBatch(
              batchId: batch,
              recordProofs: [proof],
              commitment: commitment,
              applyLocal: () async {},
            );
            await sync(i).deliver();
          } finally {
            context.key.release();
            signing.release();
          }
        }

        await publish(0, 'historical HTTP content');
        final oldContent = await accesses[0].getScopeKey(scopeId, 'content', 1);
        final oldCipher = crypto.encrypt(
          plaintext: Uint8List.fromList(utf8.encode('old historical content')),
          key: oldContent.key,
          context: {'purpose': 'transfer-test'},
        );
        oldContent.release();
        final review = await managers[0].reviewRotation(scopeId);
        final members = <Map<String, dynamic>>[
          for (final m in initial.members)
            if (m['accountId'] != dirs[0].accountId)
              {
                ...m,
                if (m['accountId'] == dirs[1].accountId) 'role': 'owner',
                if (m['accountId'] == dirs[1].accountId) 'manageKeys': true,
              },
        ];
        Future<dynamic> transfer() => managers[0].confirmRotation(
          review,
          acceptedCandidateHistory: true,
          members: members,
        );
        await expectLater(transfer(), throwsA(isA<CryptoAuthorityPending>()));
        final successors = ScopeKeyContributions(managers[1]),
            finance = ScopeKeyContributions(managers[2]);
        expect((await successors.list(scopeId)).single['draftId'], review.id);
        await successors.offer(scopeId, review.id, 'content');
        final financeReview = await managers[2].reviewRotation(
          scopeId,
          financeOnly: true,
        );
        await finance.offer(
          scopeId,
          review.id,
          'finance',
          financeReview: financeReview,
        );
        await successors.sign(scopeId, review.id, 'content');
        await finance.sign(scopeId, review.id, 'finance');
        await expectLater(transfer(), throwsA(isA<CryptoAuthorityPending>()));
        await successors.publishContent(scopeId, review.id);
        await finance.publishFinance(scopeId, review.id);
        await successors.acceptOwnership(scopeId, review.id);
        final active = await transfer();
        expect(active.epoch, 2);
        expect(
          await dbs[0].rows(
            'SELECT key_id FROM crypto_scope_keys WHERE epoch=2',
          ),
          isEmpty,
        );
        for (var i = 1; i < 3; i++) {
          await accesses[i].currentHead(scopeId, online: true);
          await accesses[i].hydrateScopeKeys(scopeId);
        }
        await publish(1, 'future HTTP content');
        await sync(1).pull(
          scopeId: scopeId,
          domain: 'content',
          accessRevision: active.accessRevision,
        );
        expect(
          observed,
          containsAll(['historical HTTP content', 'future HTTP content']),
        );
        final historical = await accesses[1].getScopeKey(scopeId, 'content', 1),
            future = await accesses[1].getScopeKey(scopeId, 'content', 2);
        try {
          expect(
            utf8.decode(
              crypto.decrypt(
                envelope: oldCipher,
                key: historical.key,
                context: {'purpose': 'transfer-test'},
              ),
            ),
            'old historical content',
          );
          final futureCipher = crypto.encrypt(
            plaintext: Uint8List.fromList(utf8.encode('new private content')),
            key: future.key,
            context: {'purpose': 'transfer-test'},
          );
          final stolen = await accesses[0].candidateKey(initial, 'content');
          try {
            expect(
              () => crypto.decrypt(
                envelope: futureCipher,
                key: stolen.key,
                context: {'purpose': 'transfer-test'},
              ),
              throwsFormatException,
            );
          } finally {
            stolen.release();
          }
        } finally {
          historical.release();
          future.release();
        }
        expect(
          await dbs[0].rows(
            "SELECT key_id FROM crypto_scope_keys WHERE domain='finance'",
          ),
          isEmpty,
        );
        await expectLater(
          accounts[0].directory.call('crypto2.records.pull', {
            'scopeId': scopeId,
            'domain': 'content',
            'cursor': 0,
            'accessRevision': active.accessRevision,
            'limit': 50,
          }),
          throwsA(
            isA<CollaborationException>().having(
              (e) => e.code,
              'permission_revoked',
              'permission_revoked',
            ),
          ),
        );
      } finally {
        for (final db in dbs) {
          await db.close();
        }
        http.close();
      }
    },
    skip: path == null
        ? 'Dedicated three-party transfer fixture not supplied'
        : false,
  );
}
