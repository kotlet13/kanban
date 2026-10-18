import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'dart:async';
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
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _MemorySecure implements AccountCryptoStore {
  final rows = <String, String>{};
  @override
  Future<String?> read(String partition) async => rows[partition];
  @override
  Future<void> write(String partition, String value) async {
    rows[partition] = value;
  }
}

class _Lost implements CollaborationTransport {
  _Lost(this.inner);
  final CollaborationTransport inner;
  String? drop = 'crypto2.account.initialize';
  final sent = <String>[];
  bool receiptUnavailable = false;
  Future<void> Function()? beforeRotate;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (receiptUnavailable && operation == 'crypto2.receipt.get')
      throw TimeoutException('synthetic receipt unavailable');
    if (operation == 'crypto2.account.rotateRoot' && beforeRotate != null) {
      final callback = beforeRotate!;
      beforeRotate = null;
      await callback();
    }
    if (operation == drop) sent.add(jsonEncode(params));
    final result = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == drop) {
      drop = null;
      receiptUnavailable = true;
      throw TimeoutException('synthetic lost accepted response');
    }
    return result;
  }

  @override
  void close() {}
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
  final fixturePath = Platform.environment['JIVIE_CRYPTO2_HTTP_FIXTURE'];
  test(
    'real PHP complete directory, durable lost ACK and fresh recovery epoch',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString())
              as Map<String, dynamic>;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback fixture required');
      final owner =
          (fixture['accounts'] as Map)['owner'] as Map<String, dynamic>;
      final session = _session(url, owner['session']);
      final crypto = CryptoCodec(await SodiumInit.init());
      final http = HttpCollaborationTransport();
      final lost = _Lost(http);
      final db = CollaborationDatabase(NativeDatabase.memory());
      final secure = _MemorySecure();
      AccountCryptoV2Workflow make(
        DeviceSession s,
        CollaborationTransport wire,
      ) => AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: s,
          transport: wire,
          store: CryptoIdentityStore(db, secure, s.profile.partition),
          isCurrent: () => true,
        ),
      );
      try {
        final first = make(session, lost);
        final file = await first.prepareRecoveryFile();
        await expectLater(
          first.verifyAndInitialize(file),
          throwsA(isA<TimeoutException>()),
        );
        expect(await first.localPhase(), 'pending');
        expect(
          (await db.rows(
            'SELECT prepared_recovery FROM crypto_identity_secrets',
          )).single['prepared_recovery'],
          isNull,
        );
        final restarted = make(session, http);
        await restarted.resume();
        expect(await restarted.localPhase(), 'ready');
        final state = await restarted.directory.requireFresh();
        expect(state.generation, 1);
        final status = await restarted.status();
        expect(status['snapshotHash'], state.snapshotHash);
        final login = await http.call(
          serverUrl: url,
          operation: 'auth.login',
          params: {
            'username': owner['username'],
            'password': owner['password'],
            'deviceName': 'Synthetic v2 recovery',
          },
          allowLocalHttp: true,
        );
        final secondSession = _session(url, login);
        final recoveryLost = _Lost(http)
          ..drop = 'crypto2.account.recoveryStart';
        final second = make(secondSession, recoveryLost);
        await expectLater(
          second.recover(file),
          throwsA(isA<TimeoutException>()),
        );
        expect((await second.directory.store.pending()).length, 2);
        await make(secondSession, http).resume();
        final recovered = await second.directory.requireFresh();
        expect(recovered.generation, 3);
        expect(recovered.devices.length, 2);
        expect(
          () => recovered.activeDevice(session.profile.deviceId),
          throwsA(isA<CryptoDirectoryException>()),
        );
        final lease = await make(secondSession, http).signingKey();
        lease.release();
        final thirdLogin = await http.call(
          serverUrl: url,
          operation: 'auth.login',
          params: {
            'username': owner['username'],
            'password': owner['password'],
            'deviceName': 'Synthetic root replacement',
          },
          allowLocalHttp: true,
        );
        final thirdSession = _session(url, thirdLogin);
        final transitionLost = _Lost(http)..drop = 'crypto2.account.rotateRoot';
        final replacement = make(thirdSession, transitionLost);
        final newFile = await replacement.prepareRootReplacement(file);
        final concurrentDeviceKey = await make(
          secondSession,
          http,
        ).signingKey();
        transitionLost.beforeRotate = () async {
          // Simulate a second physical installation, outside this vault's
          // partition serializer, using its independently approved device key.
          var current = recovered;
          for (final entry in await replacement.store.entries(
            secondSession.profile.accountId,
          )) {
            if ((entry['generation'] as int) <= current.generation) continue;
            current = await replacement.directory.reducer.apply(
              previous: current,
              entry: entry,
              serverId: current.serverId,
              accountId: current.accountId,
              pinnedRootFingerprint: crypto.fingerprint(
                cryptoBase64(
                  current.snapshot['rootSigningKeyBase64'],
                  length: 32,
                ),
                cryptoBase64(
                  current.snapshot['rootEncryptionKeyBase64'],
                  length: 32,
                ),
              ),
            );
          }
          final key = crypto.sodium.secureRandom(32);
          try {
            final mutation = await replacement.directory.reducer.prepare(
              previous: current,
              serverId: current.serverId,
              accountId: current.accountId,
              deviceId: secondSession.profile.deviceId,
              identityEpochId: current.identityEpochId,
              operation: 'crypto2.account.keyringEntriesPut',
              signer: 'device',
              pinnedRootFingerprint: crypto.fingerprint(
                cryptoBase64(
                  current.snapshot['rootSigningKeyBase64'],
                  length: 32,
                ),
                cryptoBase64(
                  current.snapshot['rootEncryptionKeyBase64'],
                  length: 32,
                ),
              ),
              signingKey: concurrentDeviceKey.key,
              payload: {
                'entries': [
                  {
                    'id': crypto.randomId(),
                    'recipientKind': 'recovery',
                    'recipientId': current.snapshot['recoveryRootEpochId'],
                    'recipientPublicKeyBase64':
                        current.snapshot['rootEncryptionKeyBase64'],
                    'sealedEnvelopeBase64': crypto.sealKey(
                      key: key,
                      recipientPublicKey: cryptoBase64(
                        current.snapshot['rootEncryptionKeyBase64'],
                        length: 32,
                      ),
                      context: {'purpose': 'syntheticCASrace'},
                    ),
                  },
                ],
              },
            );
            await http.call(
              serverUrl: url,
              operation: 'crypto2.account.keyringEntriesPut',
              params: mutation.authorization,
              token: secondSession.token,
              allowLocalHttp: true,
            );
          } finally {
            key.dispose();
          }
        };
        await expectLater(
          replacement.verifyAndRotateRoot(
            oldExternalFile: file,
            newExternalFile: newFile,
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
        concurrentDeviceKey.release();
        expect((await replacement.store.rejected()).length, 1);
        expect(newFile.any((b) => b != 0), true);
        expect(file.any((b) => b != 0), true);

        await expectLater(
          replacement.verifyAndRotateRoot(
            oldExternalFile: file,
            newExternalFile: newFile,
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(
          (await db.rows(
            'SELECT prepared_recovery FROM crypto_identity_secrets WHERE device_id=?',
            [thirdSession.profile.deviceId],
          )).single['prepared_recovery'],
          isNull,
        );
        expect((await replacement.directory.store.pending()).length, 1);
        await make(thirdSession, http).resume();
        final replaced = await replacement.directory.requireFresh();
        expect(replaced.generation, 7);
        expect(
          replaced.snapshot['rootEncryptionKeyBase64'],
          isNot(recovered.snapshot['rootEncryptionKeyBase64']),
        );
        final fourthLogin = await http.call(
          serverUrl: url,
          operation: 'auth.login',
          params: {
            'username': owner['username'],
            'password': owner['password'],
            'deviceName': 'Synthetic new file cold restore',
          },
          allowLocalHttp: true,
        );
        final fourthSession = _session(url, fourthLogin);
        final coldDb = CollaborationDatabase(NativeDatabase.memory());
        final coldSecure = _MemorySecure();
        final cold = AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(crypto),
            session: fourthSession,
            transport: http,
            store: CryptoIdentityStore(
              coldDb,
              coldSecure,
              fourthSession.profile.partition,
            ),
            isCurrent: () => true,
          ),
        );
        try {
          await expectLater(
            cold.recover(file),
            throwsA(
              anyOf(isA<CryptoDirectoryException>(), isA<FormatException>()),
            ),
          );
          final info = cold.files.inspect(
            newFile,
            serverId: fourthSession.profile.serverId,
            accountId: fourthSession.profile.accountId,
          );
          final verified = await cold.directory.refresh(
            externalFingerprint: info['fingerprint'],
          );
          expect(verified!.generation, 7);
          final rootStatus = await cold.status();
          final opened = cold.files.open(
            file: newFile,
            encryptedRoot:
                CryptoJson.decode(
                      cryptoBase64(rootStatus['keyringCiphertextBase64']),
                    )
                    as Map<String, dynamic>,
            serverId: fourthSession.profile.serverId,
            accountId: fourthSession.profile.accountId,
            expectedFingerprint: info['fingerprint'],
          );
          opened.dispose();
          expect(
            (await coldDb.rows(
              'SELECT prepared_recovery FROM crypto_identity_secrets',
            )).single['prepared_recovery'],
            isNull,
          );
          expect(await cold.localPhase(), 'recoveryRequired');
        } finally {
          await coldDb.close();
        }
        newFile.fillRange(0, newFile.length, 0);
        file.fillRange(0, file.length, 0);
      } finally {
        await db.close();
        http.close();
      }
    },
    skip: fixturePath == null
        ? 'Dedicated crypto2 HTTP fixture not supplied'
        : false,
  );
  test(
    'real PHP scope genesis, per-device recovery grants, encrypted record delivery and pull',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback fixture required');
      final person =
          (fixture['accounts'] as Map)['other'] as Map<String, dynamic>;
      final session = _session(url, person['session']);
      final crypto = CryptoCodec(await SodiumInit.init());
      final http = HttpCollaborationTransport();
      final db = CollaborationDatabase(NativeDatabase.memory());
      final secure = _MemorySecure();
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: http,
          store: CryptoIdentityStore(db, secure, session.profile.partition),
          isCurrent: () => true,
        ),
      );
      try {
        final scopeId = crypto.randomId();
        final file = await account.prepareRecoveryFile();
        await account.verifyAndInitialize(file);
        final access = SessionCryptoAccess(account: account);
        await ScopeCryptoManager(
          access,
        ).createScope(id: scopeId, kind: 'household');
        final catalog = await account.directory.call('crypto2.scopes.catalog');
        final metadata =
            (catalog['scopes'] as List).singleWhere((s) => s['id'] == scopeId)
                as Map;
        final head = await ScopeCryptoManager(access).initializeEmptyScope(
          scopeId: scopeId,
          accessRevision: metadata['accessRevision'],
          members: (metadata['members'] as List).cast<Map<String, dynamic>>(),
        );
        expect(head.active, true);
        final write = await access.writeContext(scopeId, 'content');
        final signing = await account.signingKey();
        final records = CryptoRecordProofCodec(crypto);
        final batchId = crypto.randomId();
        final canonicalId=crypto.randomId();
        final id=cryptoWireRecordId(session.profile.serverId,scopeId,'task',canonicalId);
        late Map<String, dynamic> proof;
        try {
          proof = records.sealRecord(
            serverId: session.profile.serverId,
            accountId: session.profile.accountId,
            deviceId: session.profile.deviceId,
            batchId: batchId,
            scopeId: scopeId,
            id: id,
            type: 'task',
            expectedRevision: 0,
            epoch: write.epoch,
            accessRevision: write.accessRevision,
            membershipHeadHash: write.headHash,
            domain: 'content',
            contentContract: write.contentContract,
            operationId: crypto.randomId(),
            previousRecordHash: '0' * 64,
            deleted: false,
            plaintext: Uint8List.fromList(
              utf8.encode('{"title":"synthetic-scope-secret"}'),
            ),
            metadata: {
              'identity':{'sourceKind':'records','canonicalId':canonicalId},
              'references': <dynamic>[],
              'uniqueRefs': <dynamic>[],
              'blobIds': <dynamic>[],
      'notificationState': {'version':1,'kind':'updated','assigneeAccountIds':[],'groupTargetId':null},
      'reminderState': {'version':1,'dueAtEpoch':null,'closed':false,'scheduleRevision':crypto.randomId()},
            },
            contentKey: write.key.key,
            signingKey: signing.key,
          );
        } finally {
          write.key.release();
          signing.release();
        }
        final projected = <String>[];
        final sync = CryptoSyncRepository(
          crypto: crypto,
          session: session,
          transport: http,
          store: CryptoSyncStore(db, session.profile.partition),
          signingKey: access.signingKey,
          authorKey: access.recordAuthority,
          contentKey: access.recordKey,
          beforeDelivery: access.beforeDelivery,
          readContext: access.readContext,
          project: (rows) async {
            for (final row in rows) {
              if (row.plaintext != null)
                projected.add(utf8.decode(row.plaintext!));
            }
          },
          isCurrent: () => true,
        );
        final committing = await account.signingKey();
        late Map<String, dynamic> commitment;
        try {
          commitment = await records.commitBatch(
            serverId: session.profile.serverId,
            accountId: session.profile.accountId,
            deviceId: session.profile.deviceId,
            batchId: batchId,
            records: [proof],
            signingKey: committing.key,
            projectionToken: (record) async {
              final key = await access.recordKey(record);
              try {
                return records.projectionGroupToken(record, key.key);
              } finally {
                key.release();
              }
            },
          );
        } finally {
          committing.release();
        }
        await sync.enqueueBatch(
          batchId: batchId,
          recordProofs: [proof],
          commitment: commitment,
          applyLocal: () async {},
        );
        await sync.deliver();
        await sync.pull(
          scopeId: scopeId,
          domain: 'content',
          accessRevision: head.accessRevision,
        );
        expect(projected.single, contains('synthetic-scope-secret'));
        expect(
          (await db.rows('SELECT state FROM crypto_outbox')).single['state'],
          'applied',
        );
        // Approved-device pairing preserves the original device and regrants
        // all historical scope keys under a fresh current scope epoch.
        final pairLogin = await http.call(
          serverUrl: url,
          operation: 'auth.login',
          params: {
            'username': person['username'],
            'password': person['password'],
            'deviceName': 'Synthetic approved second device',
          },
          allowLocalHttp: true,
        );
        final pairSession = _session(url, pairLogin);
        final pairDb = CollaborationDatabase(NativeDatabase.memory());
        try {
          final paired = AccountCryptoV2Workflow(
            AccountDirectoryRepository(
              reducer: AccountDirectoryV2(crypto),
              session: pairSession,
              transport: http,
              store: CryptoIdentityStore(
                pairDb,
                _MemorySecure(),
                pairSession.profile.partition,
              ),
              isCurrent: () => true,
            ),
          );
          final card = await paired.prepareDeviceRequest();
          final confirmation = await account.authorizeDeviceRequest(card);
          await paired.acceptDeviceConfirmation(confirmation);
          expect(
            (await account.directory.requireFresh()).devices
                .where((d) => d['revokedGeneration'] == null)
                .length,
            2,
          );
          final manager = ScopeCryptoManager(access);
          final review = await manager.reviewRotation(scopeId);
          final rotated = await manager.confirmRotation(
            review,
            acceptedCandidateHistory: true,
          );
          expect(rotated.epoch, 2);
          final pairAccess = SessionCryptoAccess(account: paired);
          await pairAccess.currentHead(scopeId, online: true);
          await pairAccess.hydrateScopeKeys(scopeId);
          final old = await pairAccess.getScopeKey(scopeId, 'content', 1);
          old.release();
          final pairedCurrent = await pairAccess.writeContext(
            scopeId,
            'content',
          );
          final stolen = crypto.sodium.secureCopy(
            pairedCurrent.key.key.extractBytes(),
          );
          pairedCurrent.key.release();
          try {
            await account.revokeDevice(pairSession.profile.deviceId);
            final nextReview = await manager.reviewRotation(scopeId);
            final next = await manager.confirmRotation(
              nextReview,
              acceptedCandidateHistory: true,
            );
            expect(next.epoch, 3);
            await expectLater(
              paired.directory.requireFresh(),
              throwsA(anything),
            );
            final nextWrite = await access.writeContext(scopeId, 'content');
            final signer = await account.signingKey();
            try {
              final nextCanonicalId=crypto.randomId();
              final nextProof = records.sealRecord(
                serverId: session.profile.serverId,
                accountId: session.profile.accountId,
                deviceId: session.profile.deviceId,
                batchId: crypto.randomId(),
                scopeId: scopeId,
                id: cryptoWireRecordId(session.profile.serverId,scopeId,'task',nextCanonicalId),
                type: 'task',
                expectedRevision: 0,
                epoch: nextWrite.epoch,
                accessRevision: nextWrite.accessRevision,
                membershipHeadHash: nextWrite.headHash,
                domain: 'content',
                contentContract: 6,
                operationId: crypto.randomId(),
                previousRecordHash: '0' * 64,
                deleted: false,
                plaintext: Uint8List.fromList(
                  utf8.encode('{"title":"future-private"}'),
                ),
                metadata: {
                  'identity':{'sourceKind':'records','canonicalId':nextCanonicalId},
                  'references': <dynamic>[],
                  'uniqueRefs': <dynamic>[],
                  'blobIds': <dynamic>[],
      'notificationState': {'version':1,'kind':'updated','assigneeAccountIds':[],'groupTargetId':null},
      'reminderState': {'version':1,'dueAtEpoch':null,'closed':false,'scheduleRevision':crypto.randomId()},
                },
                contentKey: nextWrite.key.key,
                signingKey: signer.key,
              );
              final nextRecord =
                  CryptoJson.decode(cryptoBase64(nextProof['commandBase64']))
                      as Map<String, dynamic>;
              expect(
                () => records.openVerified(nextRecord, stolen),
                throwsA(isA<FormatException>()),
              );
              final nextCommit = await records.commitBatch(
                serverId: session.profile.serverId,
                accountId: session.profile.accountId,
                deviceId: session.profile.deviceId,
                batchId: nextRecord['batchId'],
                records: [nextProof],
                signingKey: signer.key,
                projectionToken: (record) async =>
                    records.projectionGroupToken(record, nextWrite.key.key),
              );
              await sync.enqueueBatch(
                batchId: nextRecord['batchId'],
                recordProofs: [nextProof],
                commitment: nextCommit,
                applyLocal: () async {},
              );
              await sync.deliver();
              await expectLater(
                paired.directory.call('crypto2.records.pull', {
                  'scopeId': scopeId,
                  'domain': 'content',
                  'accessRevision': next.accessRevision,
                  'cursor': 0,
                  'limit': 20,
                }),
                throwsA(anything),
              );
            } finally {
              nextWrite.key.release();
              signer.release();
            }
          } finally {
            stolen.dispose();
          }
        } finally {
          await pairDb.close();
        }
        // A completely new local vault must recover the old scope DEK from
        // its root envelope before this new device has any device wrapper.
        final login = await http.call(
          serverUrl: url,
          operation: 'auth.login',
          params: {
            'username': person['username'],
            'password': person['password'],
            'deviceName': 'Synthetic cold scope recovery',
          },
          allowLocalHttp: true,
        );
        final coldSession = _session(url, login);
        final coldDb = CollaborationDatabase(NativeDatabase.memory());
        try {
          final cold = AccountCryptoV2Workflow(
            AccountDirectoryRepository(
              reducer: AccountDirectoryV2(crypto),
              session: coldSession,
              transport: http,
              store: CryptoIdentityStore(
                coldDb,
                _MemorySecure(),
                coldSession.profile.partition,
              ),
              isCurrent: () => true,
            ),
          );
          final replacementFile = await cold.prepareRootReplacement(file);
          await cold.verifyAndRotateRoot(
            oldExternalFile: file,
            newExternalFile: replacementFile,
          );
          final coldAccess = SessionCryptoAccess(account: cold);
          await expectLater(
            coldAccess.recoverScopeCandidateKeys(scopeId, file),
            throwsFormatException,
          );
          await coldAccess.recoverScopeCandidateKeys(scopeId, replacementFile);
          final keys = await coldDb.rows(
            "SELECT * FROM crypto_scope_keys WHERE scope_id=? AND domain='content'",
            [scopeId],
          );
          expect(keys.length, 3);
          expect(keys.every((k) => k['write_ready'] == 0), true);
          final firstEpoch = keys.singleWhere((k) => k['epoch'] == 1);
          final restoredKey = crypto.sodium.secureCopy(
            Uint8List.fromList((firstEpoch['key_bytes'] as List).cast<int>()),
          );
          try {
            final raw = restoredKey.extractBytes();
            try {
              expect(
                await coldAccess.codec.keyCommitment(raw),
                head.commitment('content'),
              );
            } finally {
              raw.fillRange(0, raw.length, 0);
            }
          } finally {
            restoredKey.dispose();
          }
          expect(
            (await coldDb.rows(
              'SELECT prepared_recovery FROM crypto_identity_secrets',
            )).single['prepared_recovery'],
            isNull,
          );
          // Recovery revocation cannot turn newly supplied old-device records
          // into trusted current records while the old scope awaits rotation.
          final record =
              CryptoJson.decode(cryptoBase64(proof['commandBase64']))
                  as Map<String, dynamic>;
          await expectLater(
            coldAccess.recordAuthority(record),
            throwsA(isA<CryptoAuthorityPending>()),
          );
          final manager = ScopeCryptoManager(coldAccess);
          final review = await manager.reviewRotation(
            scopeId,
            recoveryFile: replacementFile,
          );
          expect(review.historyBasis, 'reviewedRecoveryBaseline');
          final preview = await manager.previewRotation(review);
          try {
            expect(
              preview.map((p) => utf8.decode(p.plaintext!)).join('\n'),
              contains('synthetic-scope-secret'),
            );
          } finally {
            for (final item in preview) {
              item.dispose();
            }
          }
          await expectLater(
            manager.confirmRotation(review, acceptedCandidateHistory: false),
            throwsA(isA<CryptoAuthorityPending>()),
          );
          final restored = await manager.confirmRotation(
            review,
            acceptedCandidateHistory: true,
          );
          expect(restored.epoch, 4);
          expect(
            restored.commitment('content'),
            isNot(head.commitment('content')),
          );
          final authority = await coldAccess.recordAuthority(record);
          expect(authority.currentEpoch, false);
          expect(authority.historyBasis, 'reviewedRecoveryBaseline');
          final writable = await coldAccess.writeContext(scopeId, 'content');
          writable.key.release();
          final finalLogin = await http.call(
            serverUrl: url,
            operation: 'auth.login',
            params: {
              'username': person['username'],
              'password': person['password'],
              'deviceName': 'Synthetic new-file cold scope restore',
            },
            allowLocalHttp: true,
          );
          final finalSession = _session(url, finalLogin),
              finalDb = CollaborationDatabase(NativeDatabase.memory());
          try {
            final finalAccount = AccountCryptoV2Workflow(
              AccountDirectoryRepository(
                reducer: AccountDirectoryV2(crypto),
                session: finalSession,
                transport: http,
                store: CryptoIdentityStore(
                  finalDb,
                  _MemorySecure(),
                  finalSession.profile.partition,
                ),
                isCurrent: () => true,
              ),
            );
            await finalAccount.recover(replacementFile);
            final finalAccess = SessionCryptoAccess(account: finalAccount);
            await finalAccess.recoverScopeCandidateKeys(
              scopeId,
              replacementFile,
            );
            final all = await finalDb.rows(
              "SELECT epoch FROM crypto_scope_keys WHERE scope_id=? AND domain='content' ORDER BY epoch",
              [scopeId],
            );
            expect(all.map((r) => r['epoch']).toList(), [1, 2, 3, 4]);
          } finally {
            await finalDb.close();
            replacementFile.fillRange(0, replacementFile.length, 0);
          }
        } finally {
          await coldDb.close();
        }
        file.fillRange(0, file.length, 0);
      } finally {
        await db.close();
        http.close();
      }
    },
    skip: fixturePath == null
        ? 'Dedicated crypto2 HTTP fixture not supplied'
        : false,
  );
}
