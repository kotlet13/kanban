import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
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
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Transport implements CollaborationTransport {
  _Transport(this.session, this.prefix, this.corrupt);
  final DeviceSession session;
  final List<PreparedDirectoryMutation> prefix;
  final bool corrupt;
  final calls = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add({'operation': operation, 'params': Map.of(params)});
    if (operation == 'capabilities') {
      return {
        'serverId': session.profile.serverId,
        'cryptoAuthoritySnapshotVersions': [1],
      };
    }
    if (operation == 'crypto2.authority.snapshot') {
      expect(params['directoryAfterGenerations'], {
        session.profile.accountId: prefix.length,
      });
      final scope = params['scopeId'];
      return {
        'version': 1,
        'serverId': session.profile.serverId,
        'accountId': session.profile.accountId,
        'deviceId': session.profile.deviceId,
        // The server clamps the hint to the exact selected historical prefix.
        // These empty tail pages cannot satisfy a consumer's page-zero key.
        'entries': [
          {
            'operation': 'crypto2.scope.headGet',
            'params': {'scopeId': scope},
            'result': <String, dynamic>{},
          },
          for (final selected in prefix.skip(1))
            {
              'operation': 'crypto2.directory.read',
              'params': {
                'scopeId': scope,
                'accountId': session.profile.accountId,
                'directoryHeadHash': selected.result.headHash,
                'afterGeneration': selected.result.generation,
                'limit': 50,
              },
              'result': {'entries': [], 'hasMore': false},
            },
        ],
      };
    }
    if (operation == 'crypto2.directory.read') {
      final selected = prefix.indexWhere(
        (value) => value.result.headHash == params['directoryHeadHash'],
      );
      if (selected < 0) throw StateError('Unknown synthetic directory');
      final after = params['afterGeneration'] as int;
      final entries =
          jsonDecode(
                jsonEncode([
                  for (final value in prefix.take(selected + 1))
                    if (value.result.generation > after) value.entry,
                ]),
              )
              as List;
      if (corrupt && after == 0) {
        (entries.first['authorization'] as Map)['signatureBase64'] =
            base64Encode(Uint8List(64));
      }
      return {'entries': entries, 'hasMore': false};
    }
    throw StateError('Unexpected synthetic operation: $operation');
  }

  @override
  void close() {}
}

void main() {
  for (final corrupt in [false, true]) {
    test(
      corrupt
          ? 'hinted historical fallback rejects forged signature without changing secure pin'
          : 'hinted historical read with missing local prefix fetches page zero and reconnects secure anchor',
      () async {
        final crypto = CryptoCodec(await SodiumInit.init());
        final reducer = AccountDirectoryV2(crypto);
        final root = crypto.sodium.crypto.sign.keyPair();
        final box = crypto.sodium.crypto.box.keyPair();
        final device = crypto.sodium.crypto.sign.keyPair();
        final deviceBox = crypto.sodium.crypto.box.keyPair();
        addTearDown(() {
          for (final pair in [root, box, device, deviceBox]) {
            pair.secretKey.dispose();
          }
        });
        final session = DeviceSession(
          AccountSession(
            serverUrl: 'https://synthetic.invalid/',
            serverId: crypto.randomId(),
            accountId: crypto.randomId(),
            userId: 1,
            username: 'synthetic',
            displayName: 'Synthetic',
            deviceId: crypto.randomId(),
            expiresAt: DateTime.utc(2030),
          ),
          'synthetic',
        );
        final identityEpoch = crypto.randomId();
        final fingerprint = crypto.fingerprint(root.publicKey, box.publicKey);
        final first = await reducer.prepare(
          previous: null,
          serverId: session.profile.serverId,
          accountId: session.profile.accountId,
          deviceId: session.profile.deviceId,
          identityEpochId: identityEpoch,
          operation: 'crypto2.account.initialize',
          signer: 'root',
          pinnedRootFingerprint: fingerprint,
          signingKey: root.secretKey,
          payload: {
            'rootSigningKeyBase64': base64Encode(root.publicKey),
            'rootEncryptionKeyBase64': base64Encode(box.publicKey),
            'deviceSigningKeyBase64': base64Encode(device.publicKey),
            'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
            'keyringCiphertextBase64': base64Encode(Uint8List(48)),
          },
        );
        final prefix = [first];
        for (var index = 0; index < 2; index++) {
          prefix.add(
            await reducer.prepare(
              previous: prefix.last.result,
              serverId: session.profile.serverId,
              accountId: session.profile.accountId,
              deviceId: session.profile.deviceId,
              identityEpochId: identityEpoch,
              operation: 'crypto2.account.projectRelocation',
              signer: 'device',
              pinnedRootFingerprint: fingerprint,
              signingKey: device.secretKey,
              payload: {
                'actionId': crypto.randomId(),
                'publicationRoot': '${index + 1}' * 64,
              },
            ),
          );
        }
        final db = CollaborationDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final secure = _Secure();
        final store = CryptoIdentityStore(
          db,
          secure,
          session.profile.partition,
        );
        for (final value in prefix) {
          await store.append(session.profile.accountId, value.entry);
        }
        await store.pinComparedIdentity(first.result, fingerprint);
        await store.remember(prefix.last.result, 'verified');
        final transport = _Transport(session, prefix, corrupt);
        final directory = AccountDirectoryRepository(
          reducer: reducer,
          session: session,
          transport: transport,
          store: store,
          isCurrent: () => true,
        );
        await directory.cachedVerifiedDirectory();
        await db.execute(
          'DELETE FROM crypto_directory_entries WHERE partition=?',
          [store.partition],
        );
        final before = Map.of(secure.values);
        final access = SessionCryptoAccess(
          account: AccountCryptoV2Workflow(directory),
        );
        final scope = crypto.randomId();
        final historical = prefix[1].result;
        final result = access.withVerifiedOperation(() async {
          // Start the actual repository's bundle before the historical reader.
          // Scope admission itself is outside this directory-focused fixture.
          await directory.call('crypto2.scope.headGet', {'scopeId': scope});
          return access.directoryAt(
            scopeId: scope,
            scopeHeadHash: '0' * 64,
            accountId: session.profile.accountId,
            directoryHeadHash: historical.headHash,
            online: true,
            allowUnverifiedContact: true,
          );
        });
        if (corrupt) {
          await expectLater(result, throwsFormatException);
        } else {
          expect((await result).headHash, historical.headHash);
        }
        final exact = transport.calls
            .where((call) => call['operation'] == 'crypto2.directory.read')
            .toList();
        expect(exact.first['params'], containsPair('afterGeneration', 0));
        expect(
          exact.first['params'],
          containsPair('directoryHeadHash', historical.headHash),
        );
        if (!corrupt) {
          expect(exact, hasLength(2));
          expect(exact.last['params'], containsPair('afterGeneration', 2));
          expect(
            exact.last['params'],
            containsPair('directoryHeadHash', prefix.last.result.headHash),
          );
        }
        expect(secure.values, before);
        expect(await store.entries(session.profile.accountId), isEmpty);
      },
    );
  }
}
