import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
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
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inline_deletion_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String partition) async => values[partition];
  @override
  Future<void> write(String partition, String value) async {
    values[partition] = value;
  }
}

class _Http extends HttpCollaborationTransport {
  bool loseCommit = false;
  String? mutation;
  void Function()? afterEvidence;
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
        final result = await super.call(
          serverUrl: serverUrl,
          operation: operation,
          params: params,
          token: token,
          allowLocalHttp: allowLocalHttp,
        );
        if (operation == 'crypto2.inlineDelete.commit') {
          commits.add(jsonEncode(params));
          if (loseCommit) {
            loseCommit = false;
            throw const CollaborationException('network');
          }
        }
        if (operation == 'crypto2.inlineDelete.evidence') {
          afterEvidence?.call();
          if (mutation != null) {
            final changed = Map<String, dynamic>.from(
              jsonDecode(jsonEncode(result)) as Map,
            );
            final digests = changed['tombstoneDigests'] as List;
            if (mutation == 'omit') {
              digests.removeLast();
              changed['hasMore'] = false;
            }
            if (mutation == 'extra') {
              digests.add('f' * 64);
            }
            if (mutation == 'action') {
              final proof = changed['certificateProof'] as Map;
              final body =
                  CryptoJson.decode(cryptoBase64(proof['commandBase64']))
                      as Map;
              body['actionId'] = 'ffffffff-ffff-4fff-afff-ffffffffffff';
              proof['commandBase64'] = base64Encode(CryptoJson.encode(body));
            }
            return changed;
          }
        }
        return result;
      } on CollaborationApiException catch (error) {
        if (error.code != 'rate_limited' || attempt >= 4) rethrow;
        final retry = error.details['retryAfter'];
        await Future<void>.delayed(
          Duration(seconds: retry is int ? retry.clamp(1, 60) : 15),
        );
      }
    }
  }
}

void main() {
  final path = Platform.environment['JIVIE_INLINE_DELETE_HTTP_FIXTURE'];
  test(
    'actual inline project >32 final publication lost ACK, scoped proofs and current-read failures',
    () async {
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback only');
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
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final http = _Http(), crypto = CryptoCodec(await SodiumInit.init());
      var current = true;
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: http,
          store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
          isCurrent: () => current,
        ),
      );
      final file = await account.prepareRecoveryFile();
      try {
        await account.verifyAndInitialize(file);
      } finally {
        file.fillRange(0, file.length, 0);
      }
      final access = SessionCryptoAccess(account: account),
          manager = ScopeCryptoManager(SessionCryptoAccess(account: account));
      final scope = crypto.randomId(),
          created = await manager.createScope(id: scope, kind: 'household'),
          descriptor = created['scope'] as Map;
      await manager.initializeEmptyScope(
        scopeId: scope,
        accessRevision: descriptor['accessRevision'],
        members: (descriptor['members'] as List).cast<Map<String, dynamic>>(),
      );
      final runtime = CryptoBusinessSession(account, access, db);
      CryptoBusinessRouter.configurePayloads(runtime);
      final project = crypto.randomId(),
          other = crypto.randomId(),
          now = DateTime.utc(2026, 10, 17);
      Map<String, dynamic> payload(Map raw) => Map<String, dynamic>.from(raw)
        ..remove('id')
        ..remove('revision')
        ..remove('createdByAccountId')
        ..remove('updatedByAccountId');
      print('inline stage projects');
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
      print('inline stage events');
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
      final router = CryptoBusinessRouter(
        database: db,
        accountFor: (_) async => account,
      );
      Future<Map<String, dynamic>> dispatch(
        String op,
        Map<String, Object?> params,
      ) => router.dispatch(
        session: session,
        operation: op,
        params: params,
        protectedScopeIds: {scope},
      );
      print('inline stage preview');
      final preview = await dispatch('scopes.deletionPreview', {
        'scopeId': scope,
        'projectId': project,
      });
      expect(preview['canDelete'], true);
      expect(preview['graphCount'], 36);
      final request = {
        'scopeId': scope,
        'projectId': project,
        'previewHash': preview['previewHash'],
        'requestId': crypto.randomId(),
      };
      http.loseCommit = true;
      await expectLater(
        dispatch('scopes.delete', request),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'network',
          ),
        ),
      );
      expect(http.commits.length, 1);
      final result = await dispatch('scopes.delete', request);
      expect(result['deleted'], true);
      expect(result['deletedScopeIds'], isEmpty);
      expect(
        http.commits.length,
        1,
      ); // Reconciliation uses the original receipt.
      final rebuilt = CryptoBusinessSession(
        account,
        SessionCryptoAccess(account: account),
        db,
      );
      CryptoBusinessRouter.configurePayloads(rebuilt);
      for (var pass = 0; pass < 6; pass++) {
        await rebuilt.pullVerified(scope, 'content', attest: false);
        final active = await db.rows(
          "SELECT COUNT(*) AS n FROM crypto_business_records WHERE partition=? AND scope_id=? AND deleted=0 AND type IN ('event','project')",
          [session.profile.partition, scope],
        );
        if (active.single['n'] == 1) break;
        print(
          await db.rows(
            'SELECT verdict,error,COUNT(*) AS n FROM crypto_received GROUP BY verdict,error',
          ),
        );
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
      for (final id in [project, ...eventIds]) {
        expect(
          (await rebuilt.record(
            scope,
            'content',
            id,
            type: id == project ? 'project' : 'event',
          ))!['deleted'],
          1,
        );
      }
      final record = (await db.rows(
        'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND record_id=? ORDER BY revision DESC LIMIT 1',
        [
          session.profile.partition,
          scope,
          runtime.address(scope, 'content', 'project', project).wireId,
        ],
      )).single;
      final wire = Map<String, dynamic>.from(
        jsonDecode(record['wire'] as String) as Map,
      );
      final body = Map<String, dynamic>.from(
        CryptoJson.decode(
              cryptoBase64(
                wire['authorization']['recordProof']['commandBase64'],
              ),
            )
            as Map,
      );
      final admitted = await access.recordAuthority(body);
      expect(admitted.historyBasis, 'inlineProjectDeletion');
      for (final kind in ['omit', 'extra', 'action']) {
        http.mutation = kind;
        await expectLater(
          SessionCryptoAccess(account: account).recordAuthority(body),
          throwsFormatException,
        );
      }
      http.mutation = null;
      final wrongClosure = CryptoInlineDeletionEvidence(
        access,
        ordinaryAuthority: (_) async => CryptoRecordAuthority(
          signingKey: admitted.signingKey,
          currentEpoch: false,
          closedRecordProofHash: '0' * 64,
        ),
      );
      await expectLater(
        wrongClosure.authority(body),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'crypto_inline_delete_closure_substitution',
          ),
        ),
      );
      http.afterEvidence = () {
        current = false;
      };
      await expectLater(
        SessionCryptoAccess(account: account).recordAuthority(body),
        throwsA(
          isA<CryptoDirectoryException>().having(
            (e) => e.code,
            'code',
            'directory_stale_identity',
          ),
        ),
      );
      current = true;
      http.afterEvidence = null;
      expect(
        (await access.recordAuthority(body)).historyBasis,
        'inlineProjectDeletion',
      );
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
