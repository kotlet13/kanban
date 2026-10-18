import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _UnusedTransport implements CollaborationTransport {
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) => throw StateError('Pure proof verifier must never access a transport');
  @override
  void close() {}
}

class _UnusedStore implements AccountCryptoStore {
  @override
  Future<String?> read(String partition) => throw StateError('No reads');
  @override
  Future<void> write(String partition, String value) =>
      throw StateError('No writes');
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));

  test(
    'low privilege device cannot forge unknown or root-only directory heads',
    () {
      final root = crypto.sodium.crypto.sign.keyPair();
      final rootEncryption = crypto.sodium.crypto.box.keyPair();
      final first = crypto.sodium.crypto.sign.keyPair();
      final firstEncryption = crypto.sodium.crypto.box.keyPair();
      final low = crypto.sodium.crypto.sign.keyPair();
      final lowEncryption = crypto.sodium.crypto.box.keyPair();
      final ids = List.generate(4, (_) => crypto.randomId());
      final session = DeviceSession(
        AccountSession(
          serverUrl: 'https://test.invalid/',
          serverId: ids[0],
          accountId: ids[1],
          userId: 1,
          username: 'synthetic',
          displayName: 'Synthetic',
          deviceId: ids[2],
          expiresAt: DateTime.utc(2030),
        ),
        'synthetic',
      );
      final repository = AccountCryptoRepository(
        crypto: crypto,
        session: session,
        transport: _UnusedTransport(),
        store: _UnusedStore(),
        isCurrent: () => true,
      );
      Map<String, dynamic> command(
        String operation,
        String deviceId,
        Map<String, dynamic> payload,
        SecureKey key, {
        String signer = 'root',
      }) => crypto.sign({
        'version': 1,
        'serverId': ids[0],
        'accountId': ids[1],
        'deviceId': deviceId,
        'signer': signer,
        'operation': operation,
        'requestId': crypto.randomId(),
        'payload': payload,
      }, key);
      final ciphertext = base64Encode(crypto.sodium.randombytes.buf(64));
      final initPayload = <String, dynamic>{
        'expectedGeneration': 0,
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(rootEncryption.publicKey),
        'deviceSigningKeyBase64': base64Encode(first.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(firstEncryption.publicKey),
        'keyringCiphertextBase64': ciphertext,
      };
      final genesis = command(
        'crypto.account.initialize',
        ids[2],
        initPayload,
        root.secretKey,
      );
      final lowCert = command('crypto.device.add', ids[2], {
        'expectedGeneration': 1,
        'deviceId': ids[3],
        'signingKeyBase64': base64Encode(low.publicKey),
        'encryptionKeyBase64': base64Encode(lowEncryption.publicKey),
        'keyringWrite': false,
        'manageDevices': true,
      }, root.secretKey);
      final devices = <Map<String, dynamic>>[
        {
          'deviceId': ids[2],
          'signingKeyBase64': base64Encode(first.publicKey),
          'encryptionKeyBase64': base64Encode(firstEncryption.publicKey),
          'keyringWrite': true,
          'manageDevices': true,
          'revoked': false,
          'certificate': genesis,
          'revocationCertificate': null,
        },
        {
          'deviceId': ids[3],
          'signingKeyBase64': base64Encode(low.publicKey),
          'encryptionKeyBase64': base64Encode(lowEncryption.publicKey),
          'keyringWrite': false,
          'manageDevices': true,
          'revoked': false,
          'certificate': lowCert,
          'revocationCertificate': null,
        },
      ];
      final remote = <String, dynamic>{
        'initialized': true,
        'serverId': ids[0],
        'accountId': ids[1],
        'generation': 2,
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(rootEncryption.publicKey),
        'keyringCiphertextBase64': ciphertext,
        'devices': devices,
        'genesisCertificate': genesis,
        'keyringCertificate': genesis,
        'generationCertificate': lowCert,
      };
      final fingerprint = crypto.fingerprint(
        root.publicKey,
        rootEncryption.publicKey,
      );
      try {
        repository.verifyStatus(
          remote,
          fingerprint: fingerprint,
          minimumGeneration: 0,
        );
        for (final operation in [
          'crypto.unrecognized',
          'crypto.account.initialize',
          'crypto.account.recoveryStart',
        ]) {
          final forged = command(
            operation,
            ids[3],
            {'expectedGeneration': 2},
            low.secretKey,
            signer: 'device',
          );
          expect(
            () => repository.verifyStatus(
              {...remote, 'generation': 3, 'generationCertificate': forged},
              fingerprint: fingerprint,
              minimumGeneration: 0,
            ),
            throwsA(
              isA<AccountCryptoException>().having(
                (error) => error.code,
                'code',
                'crypto_head_authorization',
              ),
            ),
          );
        }
        // Even a correctly root-signed alternative initialize is not the pinned
        // genesis and cannot become an additional privileged initial device.
        final alternative = command('crypto.account.initialize', ids[3], {
          ...initPayload,
          'deviceSigningKeyBase64': base64Encode(low.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(lowEncryption.publicKey),
        }, root.secretKey);
        final fakeInitial = {
          ...devices[1],
          'keyringWrite': true,
          'certificate': alternative,
        };
        expect(
          () => repository.verifyStatus(
            {
              ...remote,
              'devices': [devices[0], fakeInitial],
            },
            fingerprint: fingerprint,
            minimumGeneration: 0,
          ),
          throwsA(
            isA<AccountCryptoException>().having(
              (error) => error.code,
              'code',
              'crypto_device_certificate',
            ),
          ),
        );
        // A manager signed fake initialize cannot escalate its limited keyring cap.
        final fakeManagerInit = command(
          'crypto.account.initialize',
          ids[3],
          {
            ...initPayload,
            'expectedGeneration': 2,
            'deviceSigningKeyBase64': base64Encode(low.publicKey),
            'deviceEncryptionKeyBase64': base64Encode(lowEncryption.publicKey),
          },
          low.secretKey,
          signer: 'device',
        );
        expect(
          () => repository.verifyStatus(
            {
              ...remote,
              'devices': [
                devices[0],
                {...fakeInitial, 'certificate': fakeManagerInit},
              ],
            },
            fingerprint: fingerprint,
            minimumGeneration: 0,
          ),
          throwsA(isA<AccountCryptoException>()),
        );
      } finally {
        for (final pair in [
          root,
          rootEncryption,
          first,
          firstEncryption,
          low,
          lowEncryption,
        ]) {
          pair.secretKey.dispose();
        }
      }
    },
  );
}
