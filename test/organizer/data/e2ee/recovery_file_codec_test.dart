import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/recovery_file_codec.dart';
import 'package:sodium/sodium.dart';

void main() {
  late CryptoCodec crypto;
  late RecoveryFileCodec files;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
    files = RecoveryFileCodec(crypto);
  });

  test(
    'PHP RFC8032 golden signs and verifies identical canonical bytes',
    () async {
      final vector =
          jsonDecode(
                await File(
                  'server/tests/fixtures/e2ee-command-v1.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final publicKey = cryptoBase64(vector['publicKeyBase64'], length: 32);
      final signed = <String, dynamic>{
        'commandBase64': vector['commandBase64'],
        'signatureBase64': vector['signatureBase64'],
      };
      final command = crypto.verify(signed, publicKey);
      expect(base64Encode(CryptoJson.encode(command)), vector['commandBase64']);
      final rawSeed = cryptoBase64(vector['seedBase64'], length: 32);
      final seed = crypto.sodium.secureCopy(rawSeed);
      final keys = crypto.sodium.crypto.sign.seedKeyPair(seed);
      try {
        expect(keys.publicKey, publicKey);
        expect(crypto.sign(command, keys.secretKey), signed);
      } finally {
        keys.secretKey.dispose();
        seed.dispose();
        rawSeed.fillRange(0, rawSeed.length, 0);
      }
    },
  );

  test('canonical encoding rejects duplicate keys and ambiguous values', () {
    for (final text in [
      '{"a":1,"a":2}',
      '{"a":1.0}',
      '{"a":9007199254740992}',
      '{"a":1} ',
      '{"\\u0061":1}',
      '{"a":"\\ud800"}',
    ]) {
      expect(
        () => CryptoJson.decode(Uint8List.fromList(utf8.encode(text))),
        throwsFormatException,
        reason: text,
      );
    }
    final value = <String, dynamic>{
      'z': [9007199254740991, -9007199254740991, true, null, {}, []],
      'a': 'č 🦉\n\u2028/',
    };
    expect(CryptoJson.decode(CryptoJson.encode(value)), value);
    expect(utf8.decode(CryptoJson.encode(value)).startsWith('{"a":'), true);
  });

  test('account file externally reopens bound encrypted root only', () {
    final material = files.create(serverId: 'server', accountId: 'account');
    final external = Uint8List.fromList(material.file);
    final root = files.open(
      file: external,
      encryptedRoot: material.encryptedRoot,
      serverId: 'server',
      accountId: 'account',
      expectedFingerprint: material.fingerprint,
    );
    expect(root.signing.publicKey, material.signingPublicKey);
    expect(root.encryption.publicKey, material.encryptionPublicKey);
    expect(utf8.decode(material.file), isNot(contains('installation')));
    expect(utf8.decode(material.file), isNot(contains('token')));
    root.dispose();
    material.dispose();
  });

  test(
    'wrong server, account, root pin, scope, version and ciphertext rejected',
    () {
      final material = files.create(serverId: 'server', accountId: 'account');
      void open({
        Uint8List? file,
        String server = 'server',
        String account = 'account',
        String? pin,
        Map<String, dynamic>? encrypted,
      }) => files
          .open(
            file: file ?? material.file,
            encryptedRoot: encrypted ?? material.encryptedRoot,
            serverId: server,
            accountId: account,
            expectedFingerprint: pin ?? material.fingerprint,
          )
          .dispose();
      expect(() => open(server: 'other'), throwsFormatException);
      expect(() => open(account: 'other'), throwsFormatException);
      expect(() => open(pin: 'other'), throwsFormatException);
      final decoded = CryptoJson.decode(material.file) as Map<String, dynamic>;
      expect(
        () => open(
          file: CryptoJson.encode({...decoded, 'scope': 'installation'}),
        ),
        throwsFormatException,
      );
      expect(
        () => open(file: CryptoJson.encode({...decoded, 'version': 2})),
        throwsFormatException,
      );
      final corrupt = cryptoBase64(material.encryptedRoot['ciphertextBase64']);
      corrupt[0] ^= 1;
      expect(
        () => open(
          encrypted: {
            ...material.encryptedRoot,
            'ciphertextBase64': base64Encode(corrupt),
          },
        ),
        throwsA(anything),
      );
      material.dispose();
    },
  );

  test(
    'original recovery file decrypts new scope and future epoch after devices lost',
    () {
      final material = files.create(serverId: 'server', accountId: 'account');
      final externalFile = Uint8List.fromList(material.file);
      final savedEnvelopes =
          <({String sealed, Map<String, dynamic> context, Uint8List data})>[];
      final plaintext = Uint8List.fromList(
        utf8.encode('private finance 42.50'),
      );
      for (var epoch = 1; epoch <= 2; epoch++) {
        final key = crypto.sodium.secureRandom(32);
        final context = <String, dynamic>{
          'serverId': 'server',
          'accountId': 'account',
          'scopeId': epoch == 1 ? 'project' : 'new-project',
          'epoch': epoch,
          'purpose': 'scopeKey',
        };
        final sealed = crypto.sealKey(
          key: key,
          recipientPublicKey: material.encryptionPublicKey,
          context: context,
        );
        final cipher = CryptoJson.encode(
          crypto.encrypt(plaintext: plaintext, key: key, context: context),
        );
        savedEnvelopes.add((sealed: sealed, context: context, data: cipher));
        key.dispose();
      }
      // No routine device or root private key survives this point. The original
      // file and server ciphertext alone reconstruct both allowed epochs.
      material.dispose();
      final recovered = files.open(
        file: externalFile,
        encryptedRoot: material.encryptedRoot,
        serverId: 'server',
        accountId: 'account',
        expectedFingerprint: material.fingerprint,
      );
      for (final entry in savedEnvelopes) {
        final key = crypto.openKey(
          sealed: entry.sealed,
          recipient: recovered.encryption,
          context: entry.context,
        );
        expect(
          crypto.decrypt(
            envelope: CryptoJson.decode(entry.data) as Map<String, dynamic>,
            key: key,
            context: entry.context,
          ),
          plaintext,
        );
        expect(
          () => crypto.openKey(
            sealed: entry.sealed,
            recipient: recovered.encryption,
            context: {...entry.context, 'scopeId': 'parent-finance'},
          ),
          throwsFormatException,
        );
        key.dispose();
      }
      recovered.dispose();
    },
  );

  test('signature binds exact canonical command and sealed-box context', () {
    final keys = crypto.sodium.crypto.sign.keyPair();
    final command = <String, dynamic>{
      'version': 1,
      'requestId': crypto.randomId(),
      'operation': 'crypto.account.initialize',
      'payload': {'expectedGeneration': 0},
    };
    final signed = crypto.sign(command, keys.secretKey);
    expect(crypto.verify(signed, keys.publicKey), command);
    final changed = {...command, 'operation': 'crypto.device.revoke'};
    expect(
      () => crypto.verify({
        ...signed,
        'commandBase64': base64Encode(CryptoJson.encode(changed)),
      }, keys.publicKey),
      throwsFormatException,
    );
    expect(
      command['requestId'],
      matches(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ),
      ),
    );
    keys.secretKey.dispose();
  });
}
