import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_access_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

class _Secure implements AccountCryptoStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String partition) async => _values[partition];
  @override
  Future<void> write(String partition, String value) async {
    _values[partition] = value;
  }
}

class _Sessions implements DeviceSessionStore {
  _Sessions(this.value);
  DeviceSession? value;
  @override Future<DeviceSession?> read() async => value;
  @override Future<void> write(DeviceSession session) async {value=session;}
  @override Future<void> clear() async {value=null;}
}

class _Transport implements CollaborationTransport {
  _Transport(this.inner);
  final CollaborationTransport inner;
  bool lose = false, block = false;
  var activations = 0;
  @override void close() {} // The enclosing fixture owns the real transport.
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (block && operation == 'crypto2.receipt.get') {
      throw const CollaborationException('network');
    }
    final value = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'crypto2.access.activate') {
      activations++;
      if (lose) {
        lose = false;
        block = true;
        throw const CollaborationException('network');
      }
    }
    return value;
  }
}

/// Optional actual repository successors AFTER real commit, before fresh FILE
/// recovery. It never changes the normal baseline fixture or persists secrets.
Future<void> run({
  required CryptoBusinessSession live,
  required Uint8List recoveryFile,
  required Map fixture,
}) async {
  if (fixture['synthetic'] != true ||
      fixture['successorGuest'] is! Map ||
      recoveryFile.isEmpty) {
    throw StateError('Dedicated synthetic successor fixture required');
  }
  final scope = fixture['scopeId'] as String,
      session = live.account.directory.session;
  final transport = _Transport(live.account.directory.transport);
  final account = AccountCryptoV2Workflow(
    AccountDirectoryRepository(
      reducer: live.account.directory.reducer,
      session: session,
      transport: transport,
      store: live.account.store,
      isCurrent: () => true,
    ),
  );
  final access = SessionCryptoAccess(account: account),
      manager = ScopeCryptoManager(access);
  final runtime = CryptoBusinessSession(account, access, live.database);
  final repository = CollaborationRepository(
    live.database,
    transport,
    _Sessions(session),
    ownsDatabase: false,
    cryptoRouter: CryptoBusinessRouter(
      database: live.database,
      accountFor: (_) async => account,
    ),
  );
  await repository.initialize();
  try {
    expect(
      (await access.verifiedScopeDescriptor(scope))['accessPolicyVersion'],
      1,
    );
    final preview = await repository.previewOrganizationAccess(scope);
    expect(preview.canApply, true);
    await expectLater(
      repository.applyOrganizationAccess(scope, preview.previewHash),
      throwsA(
        isA<CryptoAuthorityPending>().having(
          (e) => e.reason,
          'reason',
          'crypto_access_approval_required',
        ),
      ),
    );
    final coordinator = CryptoAccessCoordinator(runtime);
    final policy = (await coordinator.pendingApprovals(scope)).single;
    await coordinator.approve(
      scope,
      policy['intentHash'],
      review: (review) async {
        expect(review.descriptor['accessPolicyVersion'], 2);
        expect(review.descriptor['leaderAccountIds'], isEmpty);
        return true;
      },
    );
    await repository.resumeOrganizationAccessChange(scope);
    expect(
      (await access.verifiedScopeDescriptor(
        scope,
        online: true,
      ))['accessPolicyVersion'],
      2,
    );

    final guestWire = (fixture['successorGuest'] as Map)['session'] as Map;
    final u = guestWire['user'] as Map, d = guestWire['device'] as Map;
    final guestSession = DeviceSession(
      AccountSession(
        serverUrl: session.profile.serverUrl,
        serverId: guestWire['serverId'],
        accountId: u['accountId'],
        userId: u['id'],
        username: u['username'],
        displayName: u['displayName'],
        deviceId: d['id'],
        expiresAt: DateTime.fromMillisecondsSinceEpoch(d['expiresAt'] * 1000),
        allowLocalHttp: true,
      ),
      guestWire['token'],
    );
    final guestDb = CollaborationDatabase(NativeDatabase.memory());
    try {
      final guest = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: account.directory.reducer,
          session: guestSession,
          transport: transport,
          store: CryptoIdentityStore(
            guestDb,
            _Secure(),
            guestSession.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      final file = await guest.prepareRecoveryFile();
      try {
        await guest.verifyAndInitialize(file);
      } finally {
        file.fillRange(0, file.length, 0);
      }
      final sender = InviteCryptoRepository(access),
          receiver = InviteCryptoRepository(
            SessionCryptoAccess(account: guest),
          );
      final invitation = await sender.dispatch('invitations3.create', {
        'scopeId': scope,
        'recipient': (fixture['successorGuest'] as Map)['username'],
        'role': 'member',
        'language': 'en',
        'requestId': account.directory.reducer.crypto.randomId(),
      });
      final id = invitation['invitation']['id'] as String,
          inspected = await receiver.inspect(
            token: invitation['localToken'] as String,
          );
      await receiver.compareCreator(
        inspected,
        await access.identities.publicCard(
          await account.directory.requireFresh(),
        ),
      );
      await receiver.accept(inspected, actionId: id);
      final recipient = await sender.acceptedRecipient(scope, id);
      await sender.compareCreator(
        recipient,
        await receiver.access.identities.publicCard(
          await guest.directory.requireFresh(),
        ),
      );
      await sender.admit(recipient, await manager.reviewRotation(scope));
      expect(await receiver.resumeAccepted(id), scope);
      final guestId = guest.directory.accountId;
      await expectLater(
        repository.setOrganizationLeader(scope, guestId, true),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'crypto_access_approval_required',
          ),
        ),
      );
      final leader = (await coordinator.pendingApprovals(scope)).single;
      await coordinator.approve(
        scope,
        leader['intentHash'],
        review: (review) async {
          expect(review.descriptor['leaderAccountIds'], [guestId]);
          expect(
            review.members.singleWhere(
              (m) => m['accountId'] == guestId,
            )['manageKeys'],
            false,
          );
          return true;
        },
      );
      transport.lose = true;
      await expectLater(
        repository.resumeOrganizationAccessChange(scope),
        throwsA(isA<CollaborationException>()),
      );
      transport.block = false;
      final applied = (await access.currentHead(scope, online: true)).headHash;
      final successor = await manager.confirmRotation(
        await manager.reviewRotation(scope),
        acceptedCandidateHistory: true,
      );
      expect(successor.headHash, isNot(applied));
      final count = transport.activations;
      await repository.resumeOrganizationAccessChange(scope);
      expect(transport.activations, count);
      expect(
        (await repository.members(
          scope,
        )).singleWhere((m) => m.accountId == guestId).organizationLeader,
        true,
      );
      expect(
        (await access.currentHead(scope, online: true)).headHash,
        successor.headHash,
      );
      expect(
        (await access.verifiedScopeDescriptor(scope))['leaderAccountIds'],
        [guestId],
      );
    } finally {
      await guestDb.close();
    }
  } finally {
    await repository.close();
  }
}
