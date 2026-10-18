import 'dart:convert';
import 'dart:io';

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
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_structure.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_leave.dart';
import 'package:kanban/organizer/data/e2ee/crypto_access_coordinator.dart';

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
  bool loseCreate = false,
      blockReceipts = false,
      tamperObservation = false,
      offline = false;
  int creates = 0, activations = 0;
  bool tamperAccess = false, loseAccess = false;
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
    if (blockReceipts && operation == 'crypto2.receipt.get') {
      throw const CollaborationException('network');
    }
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
    if (operation == 'crypto2.access.pending' && tamperAccess) {
      final changed = jsonDecode(jsonEncode(result)) as Map<String, dynamic>;
      for (final item in changed['intents'] as List) {
        final members = item['future']['members'] as List;
        if (members.isNotEmpty) {
          members.first['financeRole'] = members.first['financeRole'] == 'none'
              ? 'write'
              : 'none';
        }
      }
      return changed;
    }
    if (operation == 'crypto2.access.activate') {
      activations++;
      if (loseAccess) {
        loseAccess = false;
        blockReceipts = true;
        throw const CollaborationException('synthetic_lost_ack');
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
  final path = Platform.environment['JIVIE_STRUCTURE_HTTP_FIXTURE'];
  test(
    'typed member removal reviews exact roster and atomically applies with lost ACK restart',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic only');
      }
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
      try {
        for (final account in [owner, guest]) {
          final file = await account.prepareRecoveryFile();
          try {
            await account.verifyAndInitialize(file);
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
            'cursor': 0,
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
        final removeRequest = crypto.randomId();
        final remove = <String, Object?>{
          'scopeId': scope,
          'accountId': guest.directory.accountId,
          'requestId': removeRequest,
        };
        final adapter = CryptoBusinessStructure(
          runtime,
          reviewRecovery: (_) async => true,
        );
        final before = await ownerAccess.currentHead(scope, online: true);
        http.tamperAccess = true;
        await expectLater(
          adapter.dispatch('scopes.removeMember', remove),
          throwsFormatException,
        );
        expect(http.activations, 0);
        expect(
          (await ownerAccess.currentHead(scope, online: true)).headHash,
          before.headHash,
        );
        http.tamperAccess = false;
        http.loseAccess = true;
        await expectLater(
          adapter.dispatch('scopes.removeMember', remove),
          throwsA(isA<CollaborationException>()),
        );
        expect(http.activations, 1);
        http.blockReceipts = false;
        final removedHead = await ownerAccess.currentHead(scope, online: true);
        final successorReview = await manager.reviewRotation(scope);
        final successor = await manager.confirmRotation(
          successorReview,
          acceptedCandidateHistory: true,
        );
        expect(successor.headHash, isNot(removedHead.headHash));
        final after = await CryptoBusinessStructure(
          CryptoBusinessSession(
            owner,
            SessionCryptoAccess(account: owner),
            ownerDb,
          ),
          reviewRecovery: (_) async => true,
        ).dispatch('scopes.removeMember', remove);
        expect(after['removed'], true);
        expect(after['accountId'], guest.directory.accountId);
        expect(after['headHash'], removedHead.headHash);
        expect(http.activations, 1);
        final active = await SessionCryptoAccess(
          account: owner,
        ).currentHead(scope, online: true);
        expect(active.members.map((m) => m['accountId']), [
          owner.directory.accountId,
        ]);
        expect(active.headHash, isNot(before.headHash));
        expect(active.headHash, successor.headHash);
        await expectLater(
          guest.directory.call('crypto2.records.pull', {
            'scopeId': scope,
            'domain': 'content',
            'accessRevision': active.accessRevision,
            'cursor': 0,
            'limit': 50,
          }),
          throwsA(
            isA<CollaborationApiException>().having(
              (e) => e.code,
              'code',
              'permission_revoked',
            ),
          ),
        );
        final remains = await runtime.record(scope, 'content', project);
        expect(
          (jsonDecode(remains!['raw_payload'] as String) as Map)['title'],
          raw['title'],
        );
        // A newly admitted member's self-leave is an exact request. It cannot
        // silently use policy3 management power to remove itself immediately.
        final rejoined = await sender.dispatch('invitations3.create', {
          ...params,
          'requestId': crypto.randomId(),
        });
        final rejoinId = rejoined['invitation']['id'] as String;
        final rejoin = InviteCryptoRepository(
          SessionCryptoAccess(account: guest),
        );
        final rejoinPreview = await rejoin.inspect(
          token: rejoined['localToken'] as String,
        );
        await rejoin.accept(rejoinPreview, actionId: rejoinId);
        final rejoinRecipient = await sender.acceptedRecipient(scope, rejoinId);
        await sender.admit(
          rejoinRecipient,
          await manager.reviewRotation(scope),
        );
        expect(await rejoin.resumeAccepted(rejoinId), scope);
        final guestLeave = CryptoBusinessSession(
          guest,
          SessionCryptoAccess(account: guest),
          guestDb,
        );
        final leaveParams = <String, Object?>{
          'scopeId': scope,
          'accountId': guest.directory.accountId,
          'requestId': crypto.randomId(),
        };
        final beforeLeave = await ownerAccess.currentHead(scope, online: true);
        await expectLater(
          CryptoBusinessStructure(
            guestLeave,
          ).dispatch('scopes.removeMember', leaveParams),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'crypto_leave_approval_required',
            ),
          ),
        );
        expect(
          (await ownerAccess.currentHead(scope, online: true)).headHash,
          beforeLeave.headHash,
        );
        final leave = CryptoBusinessLeave(runtime);
        final request = (await leave.pending(scope)).single;
        final leavePlan = await leave.prepare(scope, request);
        await CryptoAccessCoordinator(runtime).approve(
          scope,
          leavePlan['intentHash'],
          review: (review) async {
            expect(
              review.members.any(
                (m) => m['accountId'] == guest.directory.accountId,
              ),
              false,
            );
            expect(review.source.headHash, beforeLeave.headHash);
            return true;
          },
        );
        http.loseAccess = true;
        await expectLater(
          leave.finish(scope, request),
          throwsA(isA<CollaborationException>()),
        );
        http.blockReceipts = false;
        await CryptoBusinessLeave(
          CryptoBusinessSession(
            owner,
            SessionCryptoAccess(account: owner),
            ownerDb,
          ),
        ).finish(scope, request);
        expect(
          (await CryptoBusinessLeave(guestLeave).mine()).single['state'],
          'applied',
        );
        final left = await CryptoBusinessStructure(
          guestLeave,
        ).dispatch('scopes.removeMember', leaveParams);
        expect(left['removed'], true);
        expect(
          (await ownerAccess.currentHead(
            scope,
            online: true,
          )).members.map((m) => m['accountId']),
          [owner.directory.accountId],
        );
        expect(
          (await CryptoBusinessLeave(runtime).managerPlans(scope)),
          isEmpty,
        );
      } finally {
        http.close();
        await ownerDb.close();
        await guestDb.close();
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
