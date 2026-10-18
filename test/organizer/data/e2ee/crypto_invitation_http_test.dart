import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/account_deletion_store.dart';
import '../collaboration_repository_test.dart' show MemorySessionStore;
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
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_deletion.dart';

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

class _InviteHttp extends HttpCollaborationTransport {
  bool loseDeletion = false;
  bool loseScopeDeletion = false;
  bool loseCreate = false,
      blockReceipts = false,
      tamperObservation = false,
      offline = false;
  int creates = 0;
  String? omitObservation;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (offline) throw const CollaborationException('network');
    if (blockReceipts && operation == 'crypto2.receipt.get')
      throw const CollaborationException('network');
    late Map<String, dynamic> result;
    for (var attempt = 0; ; attempt++) {
      try {
        result = await super.call(
          serverUrl: serverUrl,
          operation: operation,
          params: params,
          token: token,
          allowLocalHttp: allowLocalHttp,
        );
        break;
      } on CollaborationApiException catch (error) {
        if (error.code != 'rate_limited' || attempt >= 4) rethrow;
        final retry = error.details['retryAfter'];
        await Future<void>.delayed(
          Duration(seconds: retry is int ? retry.clamp(1, 60) : 15),
        );
      }
    }
    if (omitObservation != null &&
        operation == 'crypto2.account.scopeObservations') {
      final changed = jsonDecode(jsonEncode(result)) as Map<String, dynamic>,
          items = changed['observations'] as List;
      if (items.length >= 3) {
        items.removeAt(omitObservation == 'latest' ? items.length - 1 : 1);
      }
      changed['hasMore'] = false;
      changed['nextGeneration'] = items.isEmpty
          ? null
          : items.last['generation'];
      return changed;
    }
    if (tamperObservation &&
        operation == 'crypto2.account.scopeObservations' &&
        (result['observations'] as List).isNotEmpty) {
      final changed = jsonDecode(jsonEncode(result)) as Map<String, dynamic>;
      changed['observations'][0]['observation']['headHash'] = 'f' * 64;
      return changed;
    }
    if (operation == 'crypto2.scope.delete' && loseScopeDeletion) {
      loseScopeDeletion = false;
      throw const CollaborationException('network');
    }
    if (operation == 'account.deletion.confirm' && loseDeletion) {
      loseDeletion = false;
      throw const CollaborationException('network');
    }
    if (operation == 'crypto2.invitations.create') {
      creates++;
      if (loseCreate) {
        loseCreate = false;
        blockReceipts = true;
        throw const CollaborationException('network');
      }
    }
    return result;
  }
}

void main() {
  final path = Platform.environment['JIVIE_INVITATION_HTTP_FIXTURE'];
  test(
    'real invitation lost ACK, explicit identity comparison, pending keys and activated historical access',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic only');
      final crypto = CryptoCodec(await SodiumInit.init()), http = _InviteHttp();
      final ownerDb = CollaborationDatabase(NativeDatabase.memory()),
          guestDb = CollaborationDatabase(NativeDatabase.memory());
      AccountCryptoV2Workflow make(String who, CollaborationDatabase db) =>
          AccountCryptoV2Workflow(
            AccountDirectoryRepository(
              reducer: AccountDirectoryV2(crypto),
              session: _session(url, fixture['accounts'][who]['session']),
              transport: http,
              store: CryptoIdentityStore(
                db,
                _MemorySecure(),
                _session(
                  url,
                  fixture['accounts'][who]['session'],
                ).profile.partition,
              ),
              isCurrent: () => true,
            ),
          );
      final owner = make('owner', ownerDb), guest = make('other', guestDb);
      Uint8List? guestFile;
      final deletion =
          Platform.environment['JIVIE_INVITATION_DELETE_OWNER'] == '1';
      Map<String, dynamic>? deletionAncestor;
      try {
        for (final account in [owner, guest]) {
          final file = await account.prepareRecoveryFile();
          try {
            await account.verifyAndInitialize(file);
            if (identical(account, guest)) guestFile = Uint8List.fromList(file);
          } finally {
            file.fillRange(0, file.length, 0);
          }
        }
        final ownerAccess = SessionCryptoAccess(account: owner),
            scope = crypto.randomId();
        final manager = ScopeCryptoManager(ownerAccess);
        await manager.createScope(id: scope, kind: 'household');
        final page = await owner.directory.call('crypto2.scopes.catalog');
        final metadata =
            (page['scopes'] as List).singleWhere((v) => v['id'] == scope)
                as Map;
        await manager.initializeEmptyScope(
          scopeId: scope,
          accessRevision: metadata['accessRevision'],
          members: (metadata['members'] as List).cast<Map<String, dynamic>>(),
        );
        final runtime = CryptoBusinessSession(owner, ownerAccess, ownerDb);
        final project = crypto.randomId(), now = DateTime.utc(2026, 10, 17);
        final raw =
            Map<String, dynamic>.from(
                LocalProject(
                  id: project,
                  title: 'History shared only after keys',
                  description: 'Private history',
                  createdAt: now,
                  updatedAt: now,
                  area: ProjectArea.home,
                ).toJson(),
              )
              ..remove('id')
              ..remove('revision')
              ..remove('createdByAccountId')
              ..remove('updatedByAccountId');
        await runtime.publishRaw(
          scopeId: scope,
          id: project,
          type: 'project',
          operationId: crypto.randomId(),
          expectedRevision: 0,
          rawPayload: raw,
          localHash: await CryptoBusinessJson.hash(raw),
        );
        if (deletion) {
          final initialPage = await owner.directory
              .call('crypto2.records.pull', {
                'scopeId': scope,
                'domain': 'content',
                'cursor': 0,
                'limit': 20,
                'accessRevision': (await ownerAccess.currentHead(
                  scope,
                )).accessRevision,
              });
          deletionAncestor = Map<String, dynamic>.from(
            (initialPage['records'] as List).singleWhere(
                  (r) => r['metadata']['identity']['canonicalId'] == project,
                )
                as Map,
          );
          await runtime.publishRaw(
            scopeId: scope,
            id: project,
            type: 'project',
            operationId: crypto.randomId(),
            expectedRevision: 1,
            rawPayload: raw,
            localHash: await CryptoBusinessJson.hash(raw),
          );
        }
        final sender = InviteCryptoRepository(ownerAccess);
        final params = <String, Object?>{
          'scopeId': scope,
          'recipient': fixture['accounts']['other']['username'],
          'role': 'member',
          'language': 'en',
          'requestId': crypto.randomId(),
        };
        http.loseCreate = true;
        await expectLater(
          sender.dispatch('invitations3.create', params),
          throwsA(isA<CollaborationException>()),
        );
        http.blockReceipts = false;
        final created = await InviteCryptoRepository(
          SessionCryptoAccess(account: owner),
        ).dispatch('invitations3.create', params);
        expect(http.creates, 1);
        final token = created['localToken'] as String,
            id = created['invitation']['id'] as String;
        final receiver = InviteCryptoRepository(
          SessionCryptoAccess(account: guest),
        );
        final inspected = await receiver.inspect(token: token);
        await expectLater(
          receiver.accept(inspected, actionId: id),
          throwsA(isA<CryptoAuthorityPending>()),
        );
        await receiver.compareCreator(
          inspected,
          await ownerAccess.identities.publicCard(
            await owner.directory.cachedVerifiedDirectory(),
          ),
        );
        final accepted = await receiver.accept(inspected, actionId: id);
        expect(accepted['state'], 'pendingKeys');
        await expectLater(
          guest.directory.call('crypto2.records.pull', {
            'scopeId': scope,
            'domain': 'content',
            'afterSequence': 0,
            'limit': 50,
          }),
          throwsA(isA<CollaborationException>()),
        );
        final recipient = await sender.acceptedRecipient(scope, id);
        await sender.compareCreator(
          recipient,
          await receiver.access.identities.publicCard(
            await guest.directory.cachedVerifiedDirectory(),
          ),
        );
        final review = await manager.reviewRotation(scope);
        await sender.admit(recipient, review);
        expect(await receiver.resumeAccepted(id), scope);
        final scoped = SessionCryptoAccess(account: guest);
        final rebuilt = CryptoBusinessSession(guest, scoped, guestDb);
        await rebuilt.pullVerified(scope, 'content');
        final restored = await rebuilt.record(scope, 'content', project);
        expect(
          (jsonDecode(restored!['raw_payload'] as String) as Map)['title'],
          raw['title'],
        );
        expect(
          await receiver.resumeAccepted(id),
          scope,
        ); // Restart/retry remains openable.
        final checkpoint = (await guestDb.rows(
          'SELECT * FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? ORDER BY sequence DESC LIMIT 1',
          [guest.store.partition, scope, 'content'],
        )).single;
        await guestDb.execute(
          'UPDATE crypto_domain_checkpoints SET record_count=record_count+1 WHERE partition=? AND scope_id=?',
          [guest.store.partition, scope],
        );
        await expectLater(
          CryptoScopeObservations(guest).observe(scoped, scope),
          throwsFormatException,
        );
        await guestDb.execute(
          'UPDATE crypto_domain_checkpoints SET record_count=? WHERE partition=? AND scope_id=?',
          [checkpoint['record_count'], guest.store.partition, scope],
        );
        await CryptoScopeObservations(guest).observe(scoped, scope);
        await rebuilt.pullVerified(scope, 'finance');
        await CryptoScopeObservations(guest).observe(scoped, scope);
        final observed = await guest.directory.call(
          'crypto2.account.scopeObservations',
          {'limit': 20},
        );
        expect(
          (observed['observations'] as List).length,
          greaterThanOrEqualTo(3),
        );
        final login = _session(
          url,
          await http.call(
            serverUrl: url,
            operation: 'auth.login',
            params: {
              'username': fixture['accounts']['other']['username'],
              'password': fixture['accounts']['other']['password'],
              'deviceName': 'Synthetic blank shared file recovery',
            },
            allowLocalHttp: true,
          ),
        );
        final blank = CollaborationDatabase(NativeDatabase.memory()),
            coldSecure = _MemorySecure();
        try {
          final cold = AccountCryptoV2Workflow(
            AccountDirectoryRepository(
              reducer: AccountDirectoryV2(crypto),
              session: login,
              transport: http,
              store: CryptoIdentityStore(
                blank,
                coldSecure,
                login.profile.partition,
              ),
              isCurrent: () => true,
            ),
          );
          await cold.recover(guestFile!);
          expect(
            await blank.rows('SELECT * FROM crypto_trusted_identities'),
            isEmpty,
          );
          expect(
            await blank.rows('SELECT * FROM crypto_invitation_drafts'),
            isEmpty,
          );
          expect(
            await blank.rows(
              "SELECT * FROM crypto_membership_intents WHERE state='invitationScopeAnchor'",
            ),
            isEmpty,
          );
          final anchoredHead =
              (await cold.directory.cachedVerifiedDirectory()).headHash;
          for (final omission in ['latest', 'middle']) {
            http.omitObservation = omission;
            await expectLater(
              SessionCryptoAccess(
                account: cold,
              ).recoverScopeCandidateKeys(scope, guestFile),
              throwsA(isA<CryptoAuthorityPending>()),
            );
            expect(
              (await cold.directory.cachedVerifiedDirectory()).headHash,
              anchoredHead,
            );
            expect(await blank.rows('SELECT * FROM crypto_received'), isEmpty);
            await blank.execute(
              "DELETE FROM crypto_membership_intents WHERE state IN ('scopeObservationIncluded','scopeObservationCursor')",
            );
          }
          http.omitObservation = null;
          http.tamperObservation = true;
          await expectLater(
            SessionCryptoAccess(
              account: cold,
            ).recoverScopeCandidateKeys(scope, guestFile),
            throwsFormatException,
          );
          http.tamperObservation = false;
          final coldAccess = SessionCryptoAccess(account: cold);
          await CryptoScopeObservations(cold).hydrateObservedScopes(guestFile);
          final coldRuntime = CryptoBusinessSession(cold, coldAccess, blank);
          await coldRuntime.pullVerified(scope, 'content', attest: false);
          final recovered = await coldRuntime.record(
            scope,
            'content',
            project,
            type: 'project',
          );
          expect(jsonDecode(recovered!['raw_payload'] as String), raw);
          http.offline = true;
          final offlineHead = await SessionCryptoAccess(
            account: cold,
          ).currentHead(scope);
          expect(offlineHead.scopeId, scope);
          http.offline = false;
          expect(
            await blank.rows('SELECT * FROM crypto_trusted_identities'),
            isEmpty,
          );
          expect(
            (await blank.rows(
              'SELECT account_id FROM crypto_directory_pins',
            )).map((r) => r['account_id']).toSet(),
            {login.profile.accountId},
          );
          expect(
            (await blank.rows(
              'SELECT prepared_recovery FROM crypto_identity_secrets',
            )).every((r) => r['prepared_recovery'] == null),
            true,
          );
          await expectLater(
            coldRuntime.publishRaw(
              scopeId: scope,
              id: project,
              type: 'project',
              operationId: crypto.randomId(),
              expectedRevision: 1,
              rawPayload: {...raw, 'title': 'Must await new authority'},
              localHash: 'a' * 64,
            ),
            throwsA(isA<CryptoAuthorityPending>()),
          );
          if (Platform.environment['JIVIE_INVITATION_DELETE_SCOPE'] == '1') {
            final router = CryptoBusinessRouter(
              database: ownerDb,
              accountFor: (_) async => owner,
            );
            final preview = await router.dispatch(
              session: owner.directory.session,
              operation: 'scopes.deletionPreview',
              params: {'scopeId': scope},
              protectedScopeIds: {scope},
            );
            final request = <String, Object?>{
              'scopeId': scope,
              'previewHash': preview['previewHash'],
              'requestId': crypto.randomId(),
            };
            http.loseScopeDeletion = true;
            await expectLater(
              router.dispatch(
                session: owner.directory.session,
                operation: 'scopes.delete',
                params: request,
                protectedScopeIds: {scope},
              ),
              throwsA(
                isA<CollaborationException>().having(
                  (e) => e.code,
                  'code',
                  'network',
                ),
              ),
            );
            final applied = await router.dispatch(
              session: owner.directory.session,
              operation: 'scopes.delete',
              params: request,
              protectedScopeIds: {scope},
            );
            expect(applied['deleted'], true);
            final retainedDb = CollaborationDatabase(NativeDatabase.memory());
            try {
              final relogin = _session(
                url,
                await http.call(
                  serverUrl: url,
                  operation: 'auth.login',
                  params: {
                    'username': fixture['accounts']['other']['username'],
                    'password': fixture['accounts']['other']['password'],
                    'deviceName': 'Synthetic FILE after scope deletion',
                  },
                  allowLocalHttp: true,
                ),
              );
              final retainedSecure = _MemorySecure();
              final retainedAccount = AccountCryptoV2Workflow(
                AccountDirectoryRepository(
                  reducer: AccountDirectoryV2(crypto),
                  session: relogin,
                  transport: http,
                  store: CryptoIdentityStore(
                    retainedDb,
                    retainedSecure,
                    relogin.profile.partition,
                  ),
                  isCurrent: () => true,
                ),
              );
              await retainedAccount.recover(guestFile);
              expect(
                await retainedSecure.read(
                  'scope2:${relogin.profile.partition}:$scope',
                ),
                isNull,
              );
              final retainedAccess = SessionCryptoAccess(
                account: retainedAccount,
              );
              final deletionAdapter = CryptoBusinessDeletion(
                CryptoBusinessSession(
                  retainedAccount,
                  retainedAccess,
                  retainedDb,
                ),
              );
              final witness = await deletionAdapter.retainedStatus(scope);
              expect(witness['scopeId'], scope);
              expect(witness.containsKey('rootScopeId'), false);
              expect(witness.containsKey('privateCertificateProof'), false);
              expect(
                await retainedSecure.read(
                  'scope2:${relogin.profile.partition}:$scope',
                ),
                isNull,
              );
              expect(
                await retainedDb.rows('SELECT * FROM crypto_received'),
                isEmpty,
              );
              expect(
                await retainedDb.rows('SELECT * FROM crypto_outbox'),
                isEmpty,
              );
              expect(
                (await retainedDb.rows(
                  'SELECT account_id FROM crypto_directory_pins',
                )).map((r) => r['account_id']).toSet(),
                {relogin.profile.accountId},
              );
              await expectLater(
                retainedAccess.writeContext(scope, 'content'),
                throwsA(isA<Exception>()),
              );
            } finally {
              await retainedDb.close();
            }
          }
          if (deletion) {
            // Fresh login-backed repository has neither FILE nor any device/root
            // crypto secrets. Exact deletion operations must bypass the crypto router.
            final authDb = CollaborationDatabase(NativeDatabase.memory());
            final sessions = MemorySessionStore()
              ..value = owner.directory.session;
            final receipts = MemoryAccountDeletionStore();
            final noKeys = CollaborationRepository(
              authDb,
              http,
              sessions,
              deletionStore: receipts,
              ownsDatabase: false,
            );
            try {
              await noKeys.initialize();
              expect(
                await authDb.rows('SELECT * FROM crypto_identity_secrets'),
                isEmpty,
              );
              final preview = await noKeys.previewAccountDeletion();
              expect(preview['policyVersion'], 4);
              final choices = [
                for (final c in preview['cryptoScopes'] as List)
                  <String, Object?>{
                    'scopeId': c['scopeId'],
                    'action': 'preserveReadOnly',
                    'headHash': c['headHash'],
                    'accessRevision': c['accessRevision'],
                  },
              ];
              http.loseDeletion = true;
              await expectLater(
                noKeys.confirmAccountDeletion(
                  previewHash: preview['previewHash'],
                  password: fixture['accounts']['owner']['password'],
                  review: preview,
                  cryptoResolutions: choices,
                ),
                throwsA(
                  isA<CollaborationException>().having(
                    (e) => e.code,
                    'code',
                    'network',
                  ),
                ),
              );
              final pending = await noKeys.pendingAccountDeletions();
              expect(pending, hasLength(1));
              expect(pending.single.cryptoResolutions, choices);
              expect(await noKeys.checkAccountDeletion(pending.single), true);
              expect(await noKeys.pendingAccountDeletions(), isEmpty);
              expect(
                await authDb.rows('SELECT * FROM crypto_identity_secrets'),
                isEmpty,
              );
              await expectLater(
                owner.directory.call('auth.me'),
                throwsA(isA<CollaborationException>()),
              );
              // Normal scoped read and exact ancestor verification continue
              // after the author users row/FK is actually removed.
              final survivingAccess = SessionCryptoAccess(account: cold);
              final surviving = CryptoBusinessSession(
                cold,
                survivingAccess,
                blank,
              );
              await surviving.pullVerified(scope, 'content', attest: false);
              expect(
                jsonDecode(
                  (await surviving.record(
                        scope,
                        'content',
                        project,
                        type: 'project',
                      ))!['raw_payload']
                      as String,
                ),
                raw,
              );
              final currentWire = Map<String, dynamic>.from(
                jsonDecode(
                      (await blank.rows(
                            'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND record_id=? AND revision=2',
                            [
                              cold.store.partition,
                              scope,
                              deletionAncestor!['id'],
                            ],
                          )).single['wire']
                          as String,
                    )
                    as Map,
              );
              final chain = await survivingAccess.openHistoryChain(currentWire);
              final ancestor = await cold.directory
                  .call('crypto2.records.historyGet', {
                    'scopeId': scope,
                    'domain': 'content',
                    'accessRevision': (await survivingAccess.currentHead(
                      scope,
                    )).accessRevision,
                    'id': deletionAncestor['id'],
                    'revision': 1,
                    'recordProofHash': await cryptoSha256(
                      CryptoJson.encode(
                        deletionAncestor['authorization']['recordProof'],
                      ),
                    ),
                  });
              final authority = await chain.authority(
                Map<String, dynamic>.from(ancestor['record'] as Map),
              );
              expect(authority.signingKey, isNotEmpty);
            } finally {
              await noKeys.close();
              await authDb.close();
            }
          }
        } finally {
          http.tamperObservation = false;
          http.omitObservation = null;
          http.offline = false;
          await blank.close();
        }
      } finally {
        guestFile?.fillRange(0, guestFile.length, 0);
        await ownerDb.close();
        await guestDb.close();
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
