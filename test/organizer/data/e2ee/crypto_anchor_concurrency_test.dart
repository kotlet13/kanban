import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_verification.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_anchor_lock.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_anchor.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  Completer<void>? entered, release;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    final pending = release;
    if (pending != null) {
      release = null;
      entered!.complete();
      await pending.future;
    }
    values[key] = value;
  }

  void pause() {
    entered = Completer<void>();
    release = Completer<void>();
  }
}

class _InterceptStore extends CryptoIdentityStore {
  _InterceptStore(super.database, super.secure, super.partition);
  Future<void> Function()? beforeRemember;
  Future<void> Function()? beforeComparison;
  Future<void> Function()? beforeHostingTrust;
  int? failGeneration;
  @override
  Future<void> pinHostDirectory(
    VerifiedAccountDirectory directory, {
    required String expectedServerId,
    required bool Function() isCurrent,
  }) async {
    final callback = beforeHostingTrust;
    beforeHostingTrust = null;
    await callback?.call();
    await super.pinHostDirectory(
      directory,
      expectedServerId: expectedServerId,
      isCurrent: isCurrent,
    );
  }

  @override
  Future<void> pinComparedIdentity(
    VerifiedAccountDirectory directory,
    String fingerprint,
  ) async {
    final callback = beforeComparison;
    beforeComparison = null;
    await callback?.call();
    await super.pinComparedIdentity(directory, fingerprint);
  }

  @override
  Future<void> remember(
    VerifiedAccountDirectory d,
    String trust, {
    String? handoffRequestId,
    String? handoffCommandHash,
  }) async {
    final callback = beforeRemember;
    beforeRemember = null;
    await callback?.call();
    await super.remember(
      d,
      trust,
      handoffRequestId: handoffRequestId,
      handoffCommandHash: handoffCommandHash,
    );
  }

  @override
  Future<void> append(String account, Map<String, dynamic> entry) async {
    if (entry['generation'] == failGeneration) {
      failGeneration = null;
      throw StateError('Synthetic promotion disk failure');
    }
    await super.append(account, entry);
  }
}

class _ReplayTransport implements CollaborationTransport {
  _ReplayTransport(this.state, this.entries);
  final VerifiedAccountDirectory state;
  final List<Map<String, dynamic>> entries;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls++;
    if (operation == 'crypto2.account.status')
      return {
        'initialized': true,
        'serverId': state.serverId,
        'accountId': state.accountId,
        'generation': state.generation,
        'headHash': state.headHash,
        'snapshotHash': state.snapshotHash,
        'deviceSnapshotHash': state.deviceSnapshotHash,
        'snapshotIncluded': true,
        'snapshot': state.snapshot,
      };
    if (operation == 'crypto2.account.directory' ||
        operation == 'crypto2.directory.read')
      return {
        'generation': state.generation,
        'headHash': state.headHash,
        'entries': entries
            .where((e) => e['generation'] > (params['afterGeneration'] as int))
            .toList(),
        'hasMore': false,
        'nextGeneration': state.generation,
      };
    throw StateError('Unexpected synthetic operation');
  }

  @override
  void close() {}
}

void main() {
  test(
    'detached callback cannot inherit an expired reentrant anchor lease',
    () async {
      final start = Completer<void>(),
          entered = Completer<void>(),
          release = Completer<void>();
      late Future<void> detached;
      await withCryptoAnchorLock('detached-race', () async {
        detached = Future<void>(() async {
          await start.future;
          await withCryptoAnchorLock('detached-race', () async {
            entered.complete();
          });
        });
      });
      final holding = withCryptoAnchorLock('detached-race', () async {
        start.complete();
        await release.future;
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(entered.isCompleted, false);
      release.complete();
      await holding;
      await detached;
      expect(entered.isCompleted, true);
    },
  );
  test(
    'shared scope commit rejects stale and higher divergent prefix after suspended secure write',
    () async {
      final secure = _Secure();
      Future<void> put(int epoch, Map<int, String> prefix) =>
          commitCryptoScopeAnchor(
            partition: 'scope-race',
            key: 'scope',
            secure: secure,
            epoch: epoch,
            headHash: prefix[epoch]!,
            verifiedPrefix: prefix,
            isCurrent: () => true,
          );
      await put(4, {4: 'four'});
      secure.pause();
      final release = secure.release!;
      final b = put(6, {4: 'four', 5: 'five-b', 6: 'six-b'});
      await secure.entered!.future;
      final stale = expectLater(
        put(5, {4: 'four', 5: 'five-a'}),
        throwsFormatException,
      );
      release.complete();
      await b;
      await stale;
      await expectLater(
        put(7, {4: 'four', 5: 'five-a', 6: 'six-a', 7: 'seven-a'}),
        throwsFormatException,
      );
      expect(jsonDecode(secure.values['scope']!)['headHash'], 'six-b');
      await put(7, {4: 'four', 5: 'five-b', 6: 'six-b', 7: 'seven-b'});
      expect(jsonDecode(secure.values['scope']!)['epoch'], 7);
    },
  );
  test(
    'scope identity change while awaiting final local validation prevents commit',
    () async {
      final secure = _Secure();
      var current = true;
      await expectLater(
        commitCryptoScopeAnchor(
          partition: 'identity-race',
          key: 'scope',
          secure: secure,
          epoch: 1,
          headHash: 'one',
          verifiedPrefix: {1: 'one'},
          isCurrent: () => current,
          validateCurrent: (_) async {
            await Future<void>.value();
            current = false;
          },
        ),
        throwsFormatException,
      );
      expect(secure.values, isEmpty);
    },
  );
  for (final competingFork in [true, false]) {
    test(
      competingFork
          ? 'root handoff rejects concurrent old-root fork without partial secure mutation'
          : 'root handoff promotion failure resumes offline with consistent new root',
      () async {
        final crypto = CryptoCodec(await SodiumInit.init());
        final reducer = AccountDirectoryV2(crypto);
        final pairs = List.generate(
          6,
          (_) => crypto.sodium.crypto.sign.keyPair(),
        );
        final boxes = List.generate(
          2,
          (_) => crypto.sodium.crypto.box.keyPair(),
        );
        final db = CollaborationDatabase(NativeDatabase.memory());
        final secure = _Secure();
        final server = crypto.randomId(), account = crypto.randomId();
        final deviceId = crypto.randomId(), epoch = crypto.randomId();
        final partition =
            '${Uri.encodeComponent('https://synthetic.invalid')}:$server:$account';
        final fp = crypto.fingerprint(pairs[0].publicKey, boxes[0].publicKey);
        final newFp = crypto.fingerprint(
          pairs[2].publicKey,
          boxes[1].publicKey,
        );
        try {
          final genesis = await reducer.prepare(
            previous: null,
            serverId: server,
            accountId: account,
            deviceId: deviceId,
            identityEpochId: epoch,
            operation: 'crypto2.account.initialize',
            signer: 'root',
            pinnedRootFingerprint: fp,
            signingKey: pairs[0].secretKey,
            payload: {
              'rootSigningKeyBase64': base64Encode(pairs[0].publicKey),
              'rootEncryptionKeyBase64': base64Encode(boxes[0].publicKey),
              'deviceSigningKeyBase64': base64Encode(pairs[1].publicKey),
              'deviceEncryptionKeyBase64': base64Encode(pairs[3].publicKey),
              'keyringCiphertextBase64': base64Encode(Uint8List(48)),
            },
          );
          final rotation = await reducer.prepare(
            previous: genesis.result,
            serverId: server,
            accountId: account,
            deviceId: crypto.randomId(),
            identityEpochId: epoch,
            operation: 'crypto2.account.rotateRoot',
            signer: 'root',
            pinnedRootFingerprint: fp,
            signingKey: pairs[0].secretKey,
            incomingRootSigningKey: pairs[2].secretKey,
            payload: {
              'transitionId': crypto.randomId(),
              'newRootSigningKeyBase64': base64Encode(pairs[2].publicKey),
              'newRootEncryptionKeyBase64': base64Encode(boxes[1].publicKey),
              'newIdentityEpochId': crypto.randomId(),
              'newDeviceSigningKeyBase64': base64Encode(pairs[4].publicKey),
              'newDeviceEncryptionKeyBase64': base64Encode(pairs[5].publicKey),
              'keyringCiphertextBase64': base64Encode(Uint8List(48)),
            },
          );
          final store = CryptoIdentityStore(db, secure, partition);
          await store.pinRoot(account, server, fp, genesisFingerprint: fp);
          await store.remember(genesis.result, 'verified');
          await store.append(account, genesis.entry);
          await store.authorizeRootHandoff(rotation.authorization, newFp);
          final initial = await store.anchor(account);
          final intercepted = _InterceptStore(db, secure, partition);
          if (competingFork) {
            final fork = await reducer.prepare(
              previous: genesis.result,
              serverId: server,
              accountId: account,
              deviceId: deviceId,
              identityEpochId: epoch,
              operation: 'crypto2.account.migrationAttest',
              signer: 'device',
              pinnedRootFingerprint: fp,
              signingKey: pairs[1].secretKey,
              payload: {
                'migrationId': crypto.randomId(),
                'scopeToken': '1' * 64,
                'domain': 'content',
                'attestationHash': '2' * 64,
              },
            );
            intercepted.beforeRemember = () async {
              await store.remember(fork.result, 'verified');
              await store.append(account, fork.entry);
            };
          } else {
            intercepted.failGeneration = 2;
          }
          final session = DeviceSession(
            AccountSession(
              serverUrl: 'https://synthetic.invalid',
              serverId: server,
              accountId: account,
              userId: 1,
              username: 'synthetic',
              displayName: 'Synthetic',
              deviceId: deviceId,
              expiresAt: DateTime.utc(2030),
            ),
            'synthetic',
          );
          AccountDirectoryRepository repository(_ReplayTransport transport) =>
              AccountDirectoryRepository(
                reducer: reducer,
                session: session,
                transport: transport,
                store: intercepted,
                isCurrent: () => true,
              );
          await expectLater(
            repository(
              _ReplayTransport(rotation.result, [rotation.entry]),
            ).refresh(),
            competingFork
                ? throwsA(
                    isA<CryptoDirectoryException>().having(
                      (e) => e.code,
                      'code',
                      'directory_anchor_fork',
                    ),
                  )
                : throwsStateError,
          );
          final anchor = (await store.anchor(account))!;
          if (competingFork) {
            expect(anchor['fingerprint'], fp);
            expect(
              anchor['rootSigningKeyBase64'],
              genesis.result.snapshot['rootSigningKeyBase64'],
            );
            expect(
              anchor['pendingRootTransition'],
              initial!['pendingRootTransition'],
            );
            expect(
              (await store.entries(account)).last['headHash'],
              anchor['headHash'],
            );
            expect(
              (await store.entries(
                account,
              )).any((e) => e['headHash'] == rotation.result.headHash),
              false,
            );
          } else {
            expect(anchor['fingerprint'], newFp);
            expect(
              anchor['rootSigningKeyBase64'],
              rotation.result.snapshot['rootSigningKeyBase64'],
            );
            expect(anchor['pendingRootTransition'], isNull);
            expect((await store.entries(account)).last['generation'], 1);
            final offline = _ReplayTransport(rotation.result, []);
            final recovered = await repository(
              offline,
            ).cachedVerifiedDirectory();
            expect(offline.calls, 0);
            expect(recovered.headHash, rotation.result.headHash);
            expect(recovered.rootFingerprint, newFp);
            expect((await store.entries(account)).last['generation'], 2);
            expect(
              await db.rows('SELECT * FROM crypto_directory_replay_staging'),
              isEmpty,
            );
          }
        } finally {
          for (final pair in [...pairs, ...boxes]) {
            pair.secretKey.dispose();
          }
          await db.close();
        }
      },
    );
  }
  test(
    'directory compare, refresh, fork and restore CAS share monotonic commit lock',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init()),
          reducer = AccountDirectoryV2(crypto);
      final root = crypto.sodium.crypto.sign.keyPair(),
          box = crypto.sodium.crypto.box.keyPair(),
          device = crypto.sodium.crypto.sign.keyPair(),
          deviceBox = crypto.sodium.crypto.box.keyPair();
      final db = CollaborationDatabase(NativeDatabase.memory()),
          secure = _Secure();
      final server = crypto.randomId(),
          account = crypto.randomId(),
          deviceId = crypto.randomId(),
          epoch = crypto.randomId(),
          partition =
              '${Uri.encodeComponent('https://synthetic.invalid')}:$server:$account';
      final fp = crypto.fingerprint(root.publicKey, box.publicKey);
      try {
        final genesis = await reducer.prepare(
          previous: null,
          serverId: server,
          accountId: account,
          deviceId: deviceId,
          identityEpochId: epoch,
          operation: 'crypto2.account.initialize',
          signer: 'root',
          pinnedRootFingerprint: fp,
          signingKey: root.secretKey,
          payload: {
            'rootSigningKeyBase64': base64Encode(root.publicKey),
            'rootEncryptionKeyBase64': base64Encode(box.publicKey),
            'deviceSigningKeyBase64': base64Encode(device.publicKey),
            'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
            'keyringCiphertextBase64': base64Encode(Uint8List(48)),
          },
        );
        Future<PreparedDirectoryMutation> next(
          VerifiedAccountDirectory state,
          String marker,
        ) => reducer.prepare(
          previous: state,
          serverId: server,
          accountId: account,
          deviceId: deviceId,
          identityEpochId: epoch,
          operation: 'crypto2.account.migrationAttest',
          signer: 'device',
          pinnedRootFingerprint: fp,
          signingKey: device.secretKey,
          payload: {
            'migrationId': crypto.randomId(),
            'scopeToken': '1' * 64,
            'domain': 'content',
            'attestationHash': marker * 64,
          },
        );
        final a2 = await next(genesis.result, 'a'),
            b2 = await next(genesis.result, 'b'),
            a3 = await next(a2.result, 'c');
        final first = CryptoIdentityStore(db, secure, partition),
            second = CryptoIdentityStore(db, secure, partition);
        await first.pinRoot(account, server, fp);
        await first.remember(genesis.result, 'freshnessPending');
        secure.pause();
        final release = secure.release!;
        final comparison = second.pinComparedIdentity(b2.result, fp);
        await secure.entered!.future;
        final stale = expectLater(
          first.remember(genesis.result, 'freshnessPending'),
          throwsA(isA<CryptoDirectoryException>()),
        );
        release.complete();
        await comparison;
        await stale;
        await second.remember(b2.result, 'freshnessPending');
        expect((await first.anchor(account))!['trustState'], 'verified');
        await expectLater(
          first.remember(a3.result, 'verified'),
          throwsA(isA<CryptoDirectoryException>()),
        );
        final key = 'directory2:$partition:$account',
            before = secure.values[key]!;
        secure.pause();
        final release2 = secure.release!;
        final refresh = second.pinComparedIdentity(b2.result, fp);
        await secure.entered!.future;
        final restored = withCryptoAnchorLock(partition, () async {
          final current = await secure.read(key);
          // An imported candidate may not overwrite a concurrently changed pin.
          if (current != before)
            throw const FormatException('restore_anchor_changed');
          await secure.write(key, current!);
        });
        release2.complete();
        await refresh;
        await restored;
        expect((await first.anchor(account))!['headHash'], b2.result.headHash);
        expect((await first.anchor(account))!['fingerprint'], fp);
        await first.append(account, genesis.entry);
        await first.append(account, b2.entry);
        final c3 = await next(b2.result, 'd'),
            d3 = await next(b2.result, 'e'),
            c4 = await next((await next(b2.result, 'f')).result, 'a');
        // Use the exact C prefix below; a concurrent D3 writer must win before
        // any C candidate is promoted to the immutable live log.
        final c4Exact = await next(c3.result, 'b');
        final raceStore = _InterceptStore(db, secure, partition)
          ..beforeRemember = () async {
            await first.remember(d3.result, 'verified');
            await first.append(account, d3.entry);
          };
        final session = DeviceSession(
          AccountSession(
            serverUrl: 'https://synthetic.invalid',
            serverId: server,
            accountId: account,
            userId: 1,
            username: 'synthetic',
            displayName: 'Synthetic',
            deviceId: deviceId,
            expiresAt: DateTime.utc(2030),
          ),
          'synthetic',
        );
        AccountDirectoryRepository repository(
          CryptoIdentityStore store,
          _ReplayTransport transport,
        ) => AccountDirectoryRepository(
          reducer: reducer,
          session: session,
          transport: transport,
          store: store,
          isCurrent: () => true,
        );
        await expectLater(
          repository(
            raceStore,
            _ReplayTransport(c4Exact.result, [c3.entry, c4Exact.entry]),
          ).refresh(),
          throwsA(
            isA<CryptoDirectoryException>().having(
              (e) => e.code,
              'code',
              'directory_anchor_fork',
            ),
          ),
        );
        expect(
          (await first.entries(account)).last['headHash'],
          d3.result.headHash,
        );
        expect(
          (await first.entries(
            account,
          )).any((e) => e['headHash'] == c3.result.headHash),
          false,
        );
        final d4 = await next(d3.result, 'c'),
            failing = _InterceptStore(db, secure, partition)
              ..failGeneration = 4;
        await expectLater(
          repository(
            failing,
            _ReplayTransport(d4.result, [d4.entry]),
          ).refresh(),
          throwsStateError,
        );
        expect((await first.anchor(account))!['headHash'], d4.result.headHash);
        expect((await first.entries(account)).last['generation'], 3);
        expect(
          await db.rows('SELECT * FROM crypto_directory_replay_staging'),
          isNotEmpty,
        );
        final offline = _ReplayTransport(c4.result, []);
        final restarted = await repository(
          failing,
          offline,
        ).cachedVerifiedDirectory();
        expect(offline.calls, 0);
        expect(restarted.headHash, d4.result.headHash);
        expect((await first.entries(account)).last['generation'], 4);
        expect(
          await db.rows('SELECT * FROM crypto_directory_replay_staging'),
          isEmpty,
        );
        // The scoped foreign-directory route shares the same final CAS and
        // durable promotion journal; rejected prefixes never poison its log.
        final ownId = crypto.randomId();
        final foreignPartition =
            '${Uri.encodeComponent('https://synthetic.invalid')}:$server:$ownId';
        final foreignStore = _InterceptStore(db, secure, foreignPartition);
        final foreignSession = DeviceSession(
          AccountSession(
            serverUrl: 'https://synthetic.invalid',
            serverId: server,
            accountId: ownId,
            userId: 2,
            username: 'reader',
            displayName: 'Reader',
            deviceId: crypto.randomId(),
            expiresAt: DateTime.utc(2030),
          ),
          'synthetic',
        );
        final verification = CryptoIdentityVerification(crypto, foreignStore);
        await foreignStore.pinRoot(account, server, fp, genesisFingerprint: fp);
        await foreignStore.remember(genesis.result, 'verified');
        await foreignStore.append(account, genesis.entry);
        await verification.compareAndPin(
          directory: genesis.result,
          externallyComparedSafetyCode: await verification.safetyCode(
            genesis.result,
          ),
          externallyComparedGeneration: 1,
          externallyComparedHeadHash: genesis.result.headHash,
        );
        SessionCryptoAccess foreignAccess(_ReplayTransport transport) =>
            SessionCryptoAccess(
              account: AccountCryptoV2Workflow(
                AccountDirectoryRepository(
                  reducer: reducer,
                  session: foreignSession,
                  transport: transport,
                  store: foreignStore,
                  isCurrent: () => true,
                ),
              ),
            );
        foreignStore.beforeHostingTrust = () async {
          await CryptoIdentityStore(
            db,
            secure,
            foreignPartition,
          ).remember(b2.result, 'verified');
          await foreignStore.append(account, b2.entry);
        };
        final scope = crypto.randomId();
        await expectLater(
          foreignAccess(
            _ReplayTransport(a3.result, [genesis.entry, a2.entry, a3.entry]),
          ).directoryAt(
            scopeId: scope,
            scopeHeadHash: '0' * 64,
            accountId: account,
            directoryHeadHash: a3.result.headHash,
            online: true,
          ),
          throwsA(
            isA<CryptoDirectoryException>().having(
              (e) => e.code,
              'code',
              'directory_anchor_fork',
            ),
          ),
        );
        expect(
          (await foreignStore.entries(account)).last['headHash'],
          b2.result.headHash,
        );
        final b3 = await next(b2.result, 'd');
        foreignStore.failGeneration = 3;
        await expectLater(
          foreignAccess(
            _ReplayTransport(b3.result, [genesis.entry, b2.entry, b3.entry]),
          ).directoryAt(
            scopeId: scope,
            scopeHeadHash: '0' * 64,
            accountId: account,
            directoryHeadHash: b3.result.headHash,
            online: true,
          ),
          throwsStateError,
        );
        expect(
          (await foreignStore.anchor(account))!['headHash'],
          b3.result.headHash,
        );
        final noNetwork = _ReplayTransport(b3.result, []);
        final foreignRecovered = await foreignAccess(noNetwork).directoryAt(
          scopeId: scope,
          scopeHeadHash: '0' * 64,
          accountId: account,
          directoryHeadHash: b3.result.headHash,
        );
        expect(noNetwork.calls, 0);
        expect(foreignRecovered.headHash, b3.result.headHash);
        expect((await foreignStore.entries(account)).last['generation'], 3);
        // Invitation safety comparison uses this same durable promotion path;
        // it must not append a competing prefix before the final comparison CAS.
        final inviteB4 = await next(b3.result, 'b');
        final inviteC4 = await next(b3.result, 'c');
        Future<String> card(VerifiedAccountDirectory state) async =>
            utf8.decode(
              CryptoJson.encode({
                'version': 2,
                'purpose': 'identityVerification',
                'serverId': state.serverId,
                'accountId': state.accountId,
                'generation': state.generation,
                'headHash': state.headHash,
                'safetyCode': await verification.safetyCode(state),
              }),
            );
        foreignStore.beforeComparison = () async {
          await CryptoIdentityStore(
            db,
            secure,
            foreignPartition,
          ).remember(inviteC4.result, 'verified');
          await foreignStore.append(account, inviteC4.entry);
        };
        final inviteAccess = foreignAccess(
          _ReplayTransport(inviteB4.result, []),
        );
        await expectLater(
          InviteCryptoRepository(inviteAccess).compareCreator(
            VerifiedCryptoInvitation({}, inviteB4.result, [
              genesis.entry,
              b2.entry,
              b3.entry,
              inviteB4.entry,
            ]),
            await card(inviteB4.result),
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
        expect(
          (await foreignStore.anchor(account))!['headHash'],
          inviteC4.result.headHash,
        );
        expect(
          (await foreignStore.entries(account)).last['headHash'],
          inviteC4.result.headHash,
        );
        expect(
          (await foreignStore.entries(
            account,
          )).any((e) => e['headHash'] == inviteB4.result.headHash),
          false,
        );
        final inviteD5 = await next(inviteC4.result, 'd');
        foreignStore.failGeneration = 5;
        await expectLater(
          InviteCryptoRepository(inviteAccess).compareCreator(
            VerifiedCryptoInvitation({}, inviteD5.result, [
              genesis.entry,
              b2.entry,
              b3.entry,
              inviteC4.entry,
              inviteD5.entry,
            ]),
            await card(inviteD5.result),
          ),
          throwsStateError,
        );
        expect(
          (await foreignStore.anchor(account))!['headHash'],
          inviteD5.result.headHash,
        );
        expect((await foreignStore.entries(account)).last['generation'], 4);
        expect(
          await db.rows(
            'SELECT * FROM crypto_directory_replay_staging WHERE partition=?',
            [foreignPartition],
          ),
          isNotEmpty,
        );
        final inviteOffline = _ReplayTransport(inviteD5.result, []);
        final inviteRecovered = await foreignAccess(inviteOffline).directoryAt(
          scopeId: scope,
          scopeHeadHash: '0' * 64,
          accountId: account,
          directoryHeadHash: inviteD5.result.headHash,
        );
        expect(inviteOffline.calls, 0);
        expect(inviteRecovered.headHash, inviteD5.result.headHash);
        expect((await foreignStore.entries(account)).last['generation'], 5);
      } finally {
        for (final pair in [root, box, device, deviceBox]) {
          pair.secretKey.dispose();
        }
        await db.close();
      }
    },
  );
}
