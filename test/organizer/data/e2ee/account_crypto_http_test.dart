import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/encrypted_operation_codec.dart';
import 'package:kanban/organizer/data/e2ee/recovery_file_codec.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Store implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String partition) async => values[partition];
  @override
  Future<void> write(String partition, String value) async {
    values[partition] = value;
  }

  Map<String, dynamic> get state =>
      jsonDecode(values.values.single) as Map<String, dynamic>;
}

/// Every call reaches the real HTTP controller. Only the first accepted
/// initialize response is dropped to simulate a network loss after commit.
class _LostAck implements CollaborationTransport {
  _LostAck(this.inner);
  final CollaborationTransport inner;
  bool drop = true;
  bool dropRecoveryStart = false;
  bool omitRecoveryProof = false, hideRevocations = false;
  Map<String, dynamic>? replayStatusAfterKeyringWrite;
  bool _replayNextStatus = false;
  final initialized = <String>[];
  final recoveryStarts = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto.account.initialize') {
      initialized.add(jsonEncode(params));
    }
    if (operation == 'crypto.account.recoveryStart')
      recoveryStarts.add(jsonEncode(params));
    final response = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'crypto.account.initialize' && drop) {
      drop = false;
      throw TimeoutException('synthetic accepted response loss');
    }
    if (operation == 'crypto.account.recoveryStart' && dropRecoveryStart) {
      dropRecoveryStart = false;
      throw TimeoutException('synthetic accepted recovery-start response loss');
    }
    if (operation == 'crypto.account.keyringEntriesPut' &&
        replayStatusAfterKeyringWrite != null) {
      _replayNextStatus = true;
    } else if (operation == 'crypto.account.status' && _replayNextStatus) {
      _replayNextStatus = false;
      return replayStatusAfterKeyringWrite!;
    }
    if (operation == 'crypto.account.entries' && omitRecoveryProof) {
      return {
        ...response,
        'entries': [
          for (final entry in response['entries'] as List)
            if ((entry as Map)['recipientId'] != 'recovery') entry,
        ],
      };
    }
    if (operation == 'crypto.account.status' && hideRevocations) {
      return {
        ...response,
        'devices': [
          for (final device in response['devices'] as List)
            {
              ...device as Map<String, dynamic>,
              'revoked': false,
              'revocationCertificate': null,
            },
        ],
      };
    }
    return response;
  }

  @override
  void close() {}
}

DeviceSession _session(String url, Map<String, dynamic> wire) {
  final user = wire['user'] as Map<String, dynamic>;
  final device = wire['device'] as Map<String, dynamic>;
  return DeviceSession(
    AccountSession(
      serverUrl: url,
      serverId: wire['serverId'] as String,
      accountId: user['accountId'] as String,
      userId: user['id'] as int,
      username: user['username'] as String,
      displayName: user['displayName'] as String,
      deviceId: device['id'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (device['expiresAt'] as int) * 1000,
      ),
      allowLocalHttp: true,
    ),
    wire['token'] as String,
  );
}

void main() {
  final fixturePath = Platform.environment['JIVIE_CRYPTO_HTTP_FIXTURE'];
  test(
    'real HTTP account recovery, immutable ACK, revoked device and shared ciphertext',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString())
              as Map<String, dynamic>;
      if (fixture['synthetic'] != true ||
          !Uri.parse(fixture['serverUrl'] as String).isScheme('http') ||
          Uri.parse(fixture['serverUrl'] as String).host != '127.0.0.1') {
        throw StateError('A dedicated loopback synthetic fixture is required');
      }
      final crypto = CryptoCodec(await SodiumInit.init());
      final transport = HttpCollaborationTransport();
      final lost = _LostAck(transport);
      final accounts = fixture['accounts'] as Map<String, dynamic>;
      final ownerAccount = accounts['owner'] as Map<String, dynamic>;
      final otherAccount = accounts['other'] as Map<String, dynamic>;
      final url = fixture['serverUrl'] as String;
      final ownerSession = _session(
        url,
        ownerAccount['session'] as Map<String, dynamic>,
      );
      final otherSession = _session(
        url,
        otherAccount['session'] as Map<String, dynamic>,
      );
      final ownerStore = _Store(), otherStore = _Store();
      var ownerCurrent = true;
      AccountCryptoRepository repository(
        DeviceSession session,
        _Store store, {
        CollaborationTransport? wire,
      }) => AccountCryptoRepository(
        crypto: crypto,
        session: session,
        transport: wire ?? transport,
        store: store,
        isCurrent: () => session == ownerSession ? ownerCurrent : true,
      );
      final owner = repository(ownerSession, ownerStore, wire: lost);
      final other = repository(otherSession, otherStore);
      Future<Map<String, dynamic>> call(
        DeviceSession session,
        String operation, [
        Map<String, dynamic> params = const {},
      ]) => transport.call(
        serverUrl: url,
        operation: operation,
        params: params,
        token: session.token,
        allowLocalHttp: true,
      );
      Map<String, dynamic> signed(
        DeviceSession session,
        _Store store,
        String operation,
        Map<String, dynamic> payload,
      ) {
        final secretBytes = cryptoBase64(
          store.state['deviceSigningSecretBase64'],
          length: 64,
        );
        final key = crypto.sodium.secureCopy(secretBytes);
        secretBytes.fillRange(0, secretBytes.length, 0);
        try {
          return crypto.sign({
            'version': 1,
            'operation': operation,
            'requestId': crypto.randomId(),
            'serverId': session.profile.serverId,
            'accountId': session.profile.accountId,
            'deviceId': session.profile.deviceId,
            'signer': 'device',
            'payload': payload,
          }, key);
        } finally {
          key.dispose();
        }
      }

      try {
        expect(
          (await owner.status())['initialized'],
          false,
          reason: 'Run server/tests/crypto-http-seed.php for each run',
        );
        final originalFile = await owner.prepareRecoveryFile();
        expect(
          await owner.prepareRecoveryFile(),
          originalFile,
          reason: 'Save/cancel never generates a replacement identity',
        );
        await expectLater(
          owner.verifyAndInitialize(Uint8List.fromList(originalFile)),
          throwsA(isA<TimeoutException>()),
        );
        expect(ownerStore.state['pending'], isNotNull);
        expect(ownerStore.state.containsKey('recoveryFileBase64'), false);
        await owner.resume();
        expect(lost.initialized.length, 2);
        expect(lost.initialized[0], lost.initialized[1]);
        expect(ownerStore.state['phase'], 'ready');
        final ownerStatus = await owner.status();
        final ownerPin =
            RecoveryFileCodec(crypto).inspect(
                  originalFile,
                  serverId: ownerSession.profile.serverId,
                  accountId: ownerSession.profile.accountId,
                )['fingerprint']
                as String;
        expect(
          () => owner.verifyStatus(
            {
              ...ownerStatus,
              'rootEncryptionKeyBase64': base64Encode(
                crypto.sodium.randombytes.buf(32),
              ),
            },
            fingerprint: ownerPin,
            minimumGeneration: 1,
          ),
          throwsA(isA<AccountCryptoException>()),
        );
        expect(
          () => owner.verifyStatus(
            {...ownerStatus, 'generation': 0},
            fingerprint: ownerPin,
            minimumGeneration: 1,
          ),
          throwsA(isA<AccountCryptoException>()),
        );

        final scopeId = crypto.randomId();
        lost.omitRecoveryProof = true;
        await expectLater(
          owner.createContentKey(
            scopeId: scopeId,
            epoch: 1,
            purpose: 'scopeKey',
          ),
          throwsA(
            isA<AccountCryptoException>().having(
              (error) => error.code,
              'code',
              'crypto_outcome_unknown',
            ),
          ),
        );
        final pending = ownerStore.state['pending'] as Map<String, dynamic>;
        final pendingCommand =
            CryptoJson.decode(cryptoBase64(pending['commandBase64']))
                as Map<String, dynamic>;
        final key1Id =
            (((pendingCommand['payload'] as Map)['entries'] as List).first
                    as Map)['id']
                as String;
        await expectLater(
          owner.contentKey(key1Id),
          throwsA(isA<AccountCryptoException>()),
        );
        lost.omitRecoveryProof = false;
        final oldHead = await call(ownerSession, 'crypto.account.status');
        // A concurrent valid mutation advances the account after our original
        // keyring command committed. A stale ACK status must not lower its floor.
        await call(
          ownerSession,
          'crypto.account.keyringEntriesPut',
          signed(ownerSession, ownerStore, 'crypto.account.keyringEntriesPut', {
            'expectedGeneration': oldHead['generation'],
            'entries': (pendingCommand['payload'] as Map)['entries'],
          }),
        );
        lost.replayStatusAfterKeyringWrite = oldHead;
        await expectLater(
          owner.resume(),
          throwsA(
            isA<AccountCryptoException>().having(
              (error) => error.code,
              'code',
              'crypto_rollback',
            ),
          ),
        );
        expect(ownerStore.state['pending'], isNotNull);
        expect(
          ownerStore.state['generationFloor'],
          (oldHead['generation'] as int) + 1,
        );
        lost.replayStatusAfterKeyringWrite = null;
        await owner.resume();
        final key1 = (id: key1Id, key: await owner.contentKey(key1Id));
        final key2 = await owner.createContentKey(
          scopeId: crypto.randomId(),
          epoch: 2,
          purpose: 'scopeKey',
        );
        final expected1 = key1.key.extractBytes(),
            expected2 = key2.key.extractBytes();
        key1.key.dispose();
        key2.key.dispose();
        final page = await owner.entries();
        expect(page['hasMore'], false);
        final recoveryEntries = (page['entries'] as List)
            .cast<Map<String, dynamic>>()
            .where((entry) => entry['recipientId'] == 'recovery')
            .toList();
        expect(recoveryEntries.length, 2);

        final newSession = _session(
          url,
          await call(ownerSession, 'auth.login', {
            'username': ownerAccount['username'],
            'password': ownerAccount['password'],
            'deviceName': 'Synthetic recovery second device',
          }),
        );
        final newStore = _Store();
        final recoveredWire = _LostAck(transport)
          ..drop = false
          ..dropRecoveryStart = true;
        final recovered = repository(newSession, newStore, wire: recoveredWire);
        await expectLater(
          recovered.recover(Uint8List.fromList(originalFile)),
          throwsA(isA<TimeoutException>()),
        );
        expect(newStore.state['pendingRecoveryStart'], isNotNull);
        expect(newStore.state['pending'], isNotNull);
        expect(newStore.state.containsKey('recoveryFileBase64'), false);
        final startHead = await call(newSession, 'crypto.account.status');
        // Another approved device commits after recoveryStart, before add.
        // The old signed add must stay rejected and immutable until file import.
        await call(
          ownerSession,
          'crypto.account.keyringEntriesPut',
          signed(ownerSession, ownerStore, 'crypto.account.keyringEntriesPut', {
            'expectedGeneration': startHead['generation'],
            'entries': (pendingCommand['payload'] as Map)['entries'],
          }),
        );
        await expectLater(
          recovered.resume(),
          throwsA(
            isA<CollaborationApiException>().having(
              (error) => error.code,
              'code',
              'crypto_generation_conflict',
            ),
          ),
        );
        final rejectedAdd = jsonEncode(newStore.state['pending']);
        expect(newStore.state.containsKey('pendingRecoveryStart'), false);
        await recovered.recover(Uint8List.fromList(originalFile));
        expect(recoveredWire.recoveryStarts.length, 3);
        expect(
          recoveredWire.recoveryStarts[0],
          recoveredWire.recoveryStarts[1],
        );
        final retired =
            (newStore.state['retiredRecoveryRequests'] as List).single as Map;
        expect(jsonEncode(retired['pending']), rejectedAdd);
        expect((retired['rejectionReceipt'] as Map)['status'], 409);
        expect(newStore.state.containsKey('pendingRecoveryStart'), false);
        expect(newStore.state.containsKey('recoveryFileBase64'), false);
        expect(newStore.state.containsKey('signingSeedBase64'), false);
        final recoveredKey = await recovered.recoverContentKey(
          externalFile: originalFile,
          entry: recoveryEntries.singleWhere((e) => e['id'] == key1.id),
          expectedContext: {
            'serverId': ownerSession.profile.serverId,
            'accountId': ownerSession.profile.accountId,
            'scopeId': scopeId,
            'epoch': 1,
            'purpose': 'scopeKey',
            'keyId': key1.id,
            'recipientId': 'recovery',
          },
        );
        expect(recoveredKey.extractBytes(), expected1);
        recoveredKey.dispose();

        // A keyring mutation without a recovery recipient is rejected atomically.
        final selfState = await recovered.status();
        await expectLater(
          call(
            newSession,
            'crypto.account.keyringEntriesPut',
            signed(newSession, newStore, 'crypto.account.keyringEntriesPut', {
              'expectedGeneration': selfState['generation'],
              'entries': [
                {
                  'id': crypto.randomId(),
                  'recipientId': newSession.profile.deviceId,
                  'recipientPublicKeyBase64':
                      newStore.state['deviceEncryptionKeyBase64'],
                  'sealedEnvelopeBase64': base64Encode(
                    crypto.sodium.randombytes.buf(80),
                  ),
                },
              ],
            }),
          ),
          throwsA(
            isA<CollaborationApiException>().having(
              (error) => error.code,
              'code',
              'crypto_recovery_envelope_required',
            ),
          ),
        );

        final otherFile = await other.prepareRecoveryFile();
        await other.verifyAndInitialize(Uint8List.fromList(otherFile));
        final otherStatus = await other.status();
        await call(newSession, 'scopes.create', {
          'id': scopeId,
          'kind': 'household',
          'name': 'Synthetic crypto staging only',
          'requestId': crypto.randomId(),
        });
        final invitation = await call(newSession, 'invitations.create', {
          'scopeId': scopeId,
          'recipientUsername': otherAccount['username'],
          'role': 'member',
          'requestId': crypto.randomId(),
        });
        await call(otherSession, 'invitations.accept', {
          'token': invitation['token'],
        });
        final scopes = await call(newSession, 'scopes.list');
        final scope = (scopes['scopes'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((s) => s['id'] == scopeId);
        final revision = scope['accessRevision'] as int;
        final prepared = await call(
          newSession,
          'crypto.scope.prepare',
          signed(newSession, newStore, 'crypto.scope.prepare', {
            'scopeId': scopeId,
            'expectedAccessRevision': revision,
          }),
        );
        expect(prepared['state'], 'staged');
        expect(prepared['cutoverSupported'], false);
        final scopeKey = crypto.sodium.secureCopy(expected1);
        for (final target in [
          (newSession, await recovered.status()),
          (otherSession, otherStatus),
        ]) {
          final context = <String, dynamic>{
            'serverId': newSession.profile.serverId,
            'scopeId': scopeId,
            'domain': 'content',
            'epoch': 1,
            'accessRevision': revision,
            'accountId': target.$1.profile.accountId,
          };
          final recipients = [
            for (final recipient in [
              ('recovery', target.$2['rootEncryptionKeyBase64'] as String),
              for (final d
                  in (target.$2['devices'] as List)
                      .cast<Map<String, dynamic>>()
                      .where((d) => d['revoked'] == false))
                (d['deviceId'] as String, d['encryptionKeyBase64'] as String),
            ])
              {
                'recipientId': recipient.$1,
                'publicKeyBase64': recipient.$2,
                'sealedEnvelopeBase64': crypto.sealKey(
                  key: scopeKey,
                  recipientPublicKey: cryptoBase64(recipient.$2, length: 32),
                  context: {...context, 'recipientId': recipient.$1},
                ),
              },
          ];
          await call(
            newSession,
            'crypto.grants.put',
            signed(newSession, newStore, 'crypto.grants.put', {
              'scopeId': scopeId,
              'accountId': target.$1.profile.accountId,
              'domain': 'content',
              'epoch': 1,
              'accessRevision': revision,
              'expectedGeneration': 0,
              'recipients': recipients,
            }),
          );
        }
        final codec = EncryptedOperationCodec(crypto);
        final recordId = crypto.randomId();
        final operation = codec.seal(
          serverId: newSession.profile.serverId,
          scopeId: scopeId,
          id: recordId,
          type: 'task',
          expectedRevision: 0,
          epoch: 1,
          key: scopeKey,
          payload: {'title': 'SENTINEL private amount 42.50', 'done': false},
          metadata: {'references': [], 'uniqueRefs': []},
        );
        final batch = signed(newSession, newStore, 'crypto.records.batch', {
          'records': [operation],
        });
        await call(newSession, 'crypto.records.batch', batch);
        await call(newSession, 'crypto.records.batch', batch);
        final pulled = await call(otherSession, 'crypto.records.pull', {
          'scopeId': scopeId,
          'cursor': 0,
          'accessRevision': revision,
          'domain': 'content',
        });
        final record = (pulled['records'] as List)
            .cast<Map<String, dynamic>>()
            .single;
        expect(jsonEncode(pulled), isNot(contains('SENTINEL')));
        final grants = await call(otherSession, 'crypto.grants.list', {
          'scopeId': scopeId,
          'domain': 'content',
        });
        final grant = (grants['grants'] as List)
            .cast<Map<String, dynamic>>()
            .single;
        final ownerPublic = cryptoBase64(
          newStore.state['deviceSigningKeyBase64'],
          length: 32,
        );
        final grantCommand = crypto.verify(
          grant['authorization'] as Map<String, dynamic>,
          ownerPublic,
        );
        expect(grantCommand['operation'], 'crypto.grants.put');
        final wrapper = (grant['recipients'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere(
              (r) => r['recipientId'] == otherSession.profile.deviceId,
            );
        final recipientSecret = cryptoBase64(
          otherStore.state['deviceEncryptionSecretBase64'],
          length: 32,
        );
        final recipientKey = KeyPair(
          publicKey: cryptoBase64(
            otherStore.state['deviceEncryptionKeyBase64'],
            length: 32,
          ),
          secretKey: crypto.sodium.secureCopy(recipientSecret),
        );
        final receivedScopeKey = crypto.openKey(
          sealed: wrapper['sealedEnvelopeBase64'] as String,
          recipient: recipientKey,
          context: {
            'serverId': newSession.profile.serverId,
            'scopeId': scopeId,
            'domain': 'content',
            'epoch': 1,
            'accessRevision': revision,
            'accountId': otherSession.profile.accountId,
            'recipientId': otherSession.profile.deviceId,
          },
        );
        expect(
          codec.open(
            serverId: newSession.profile.serverId,
            wire: record,
            key: receivedScopeKey,
            independentlyTrustedSigningKey: ownerPublic,
          )['title'],
          'SENTINEL private amount 42.50',
        );
        receivedScopeKey.dispose();
        recipientKey.secretKey.dispose();
        scopeKey.dispose();

        final unknown = await call(newSession, 'crypto.legacy.lookup', {
          'scopeId': scopeId,
          'legacyId': crypto.randomId(),
          'finance': false,
          'requestHash': List.filled(64, '0').join(),
        });
        expect(unknown['outcome'], 'unknown');
        await recovered.revokeDevice(ownerSession.profile.deviceId);
        recoveredWire.hideRevocations = true;
        await expectLater(
          recovered.status(),
          throwsA(
            isA<AccountCryptoException>().having(
              (error) => error.code,
              'code',
              'crypto_revocation_rollback',
            ),
          ),
        );
        await expectLater(
          recovered.recoverContentKey(
            externalFile: originalFile,
            entry: recoveryEntries.singleWhere((e) => e['id'] == key1.id),
            expectedContext: {
              'serverId': ownerSession.profile.serverId,
              'accountId': ownerSession.profile.accountId,
              'scopeId': scopeId,
              'epoch': 1,
              'purpose': 'scopeKey',
              'keyId': key1.id,
              'recipientId': 'recovery',
            },
          ),
          throwsA(
            isA<AccountCryptoException>().having(
              (error) => error.code,
              'code',
              'crypto_revocation_rollback',
            ),
          ),
        );
        recoveredWire.hideRevocations = false;
        await expectLater(
          owner.createContentKey(
            scopeId: scopeId,
            epoch: 3,
            purpose: 'scopeKey',
          ),
          throwsA(anything),
        );
        ownerCurrent = false;
        await expectLater(
          owner.status(),
          throwsA(
            isA<AccountCryptoException>().having(
              (error) => error.code,
              'code',
              'crypto_stale_identity',
            ),
          ),
        );
        expected1.fillRange(0, expected1.length, 0);
        expected2.fillRange(0, expected2.length, 0);
        originalFile.fillRange(0, originalFile.length, 0);
        otherFile.fillRange(0, otherFile.length, 0);
      } finally {
        transport.close();
      }
    },
    skip: fixturePath == null
        ? 'Requires a fresh dedicated Docker HTTP fixture'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
