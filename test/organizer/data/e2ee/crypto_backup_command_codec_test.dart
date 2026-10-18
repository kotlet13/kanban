import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart'
    show cryptoSha256;
import 'package:kanban/organizer/data/e2ee/crypto_backup_command_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:sodium/sodium.dart';

void main() {
  test(
    'backup references reconstruct exact immutable signed body and receipt; tampered or missing bytes fail closed',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init()),
          signing = crypto.sodium.crypto.sign.keyPair();
      addTearDown(signing.dispose);
      final recordCodec = CryptoRecordProofCodec(crypto),
          part = 'synthetic-partition',
          scope = crypto.randomId(),
          blob = crypto.randomId();
      final bytes = crypto.sodium.randombytes.buf(196608);
      Map<String, dynamic> drafts(List<Map<String, dynamic>> chunks) => {
        'version': 1,
        'partition': part,
        'tables': {
          'crypto_document_jobs': [
            {'partition': part, 'id': blob, 'scope_id': scope},
          ],
          'crypto_document_chunks': chunks,
        },
      };
      final chunk = <String, dynamic>{
        'partition': part,
        'id': blob,
        'offset': 0,
        'cipher': {'blobBase64': base64Encode(bytes)},
      };
      final source = drafts([chunk]);
      final codec = CryptoBackupCommandCodec(source, part);
      final command = {
        'version': 2,
        'operation': 'crypto2.blob.chunk',
        'requestId': crypto.randomId(),
        'serverId': crypto.randomId(),
        'accountId': crypto.randomId(),
        'deviceId': crypto.randomId(),
        'signer': 'device',
        'payload': {
          'scopeId': scope,
          'id': blob,
          'domain': 'content',
          'epoch': 1,
          'accessRevision': 0,
          'membershipHeadHash': 'a' * 64,
          'offset': 0,
          'dataBase64': base64Encode(bytes),
        },
      };
      final signed = recordCodec.signCommand(command, signing.secretKey);
      final original = utf8.decode(CryptoJson.encode(signed));
      final hash = await cryptoSha256(cryptoBase64(signed['commandBase64']));
      final compact = await codec.compactSigned(original, requestHash: hash);
      expect(compact.length, lessThan(3000));
      final restored = await codec.expandSigned(compact, requestHash: hash);
      expect(restored, original);
      crypto.verifyDomain(
        Map<String, dynamic>.from(jsonDecode(restored) as Map),
        signing.publicKey,
        'JivieE2EE/v2\n',
      );
      final receipt = utf8.decode(
        CryptoJson.encode({
          'authorization': signed,
          'requestHash': hash,
          'requestId': command['requestId'],
          'outcome': 'applied',
          'status': 200,
          'response': {'received': 196608},
        }),
      );
      final compactReceipt = await codec.compactReceipt(
        receipt,
        requestHash: hash,
      );
      expect(compactReceipt!.length, lessThan(4000));
      expect(
        await codec.expandReceipt(compactReceipt, requestHash: hash),
        receipt,
      );
      await expectLater(
        CryptoBackupCommandCodec(
          drafts([]),
          part,
        ).expandSigned(compact, requestHash: hash),
        throwsFormatException,
      );
      final oldEvidence = {
        'tables': {
          'crypto_outbox': [
            {
              'signed_body': compact,
              'request_hash': hash,
              'response': compactReceipt,
            },
          ],
          'crypto_restore_evidence': <Object>[],
        },
      };
      final nested = {
        'tables': {
          'crypto_outbox': <Object>[],
          'crypto_restore_evidence': [
            {'backup_id': 'old-backup', 'evidence': jsonEncode(oldEvidence)},
          ],
        },
      };
      final reexportedDrafts = drafts([])
        ..['restoredCandidates'] = [
          {
            'backupId': 'old-backup',
            'partition': part,
            'tables': source['tables'],
          },
        ];
      await CryptoBackupCommandCodec(
        reexportedDrafts,
        part,
      ).validateEvidence(nested);
      await expectLater(
        CryptoBackupCommandCodec(drafts([]), part).validateEvidence(nested),
        throwsFormatException,
      );
      final changed = Uint8List.fromList(bytes)..[0] ^= 1;
      final badChunk = {
        ...chunk,
        'cipher': {'blobBase64': base64Encode(changed)},
      };
      await expectLater(
        CryptoBackupCommandCodec(
          drafts([badChunk]),
          part,
        ).expandSigned(compact, requestHash: hash),
        throwsFormatException,
      );
      expect(
        () => CryptoBackupCommandCodec(drafts([chunk, badChunk]), part),
        throwsFormatException,
      );
      await expectLater(
        codec.expandSigned(compact, requestHash: 'f' * 64),
        throwsFormatException,
      );
      await expectLater(
        CryptoBackupCommandCodec(
          source,
          'another-partition',
        ).expandSigned(compact, requestHash: hash),
        throwsFormatException,
      );
      final ref =
          jsonDecode(compact.substring(compact.indexOf('\n') + 1)) as Map;
      ref['offset'] = 1;
      final tampered =
          compact.substring(0, compact.indexOf('\n') + 1) + jsonEncode(ref);
      await expectLater(
        codec.expandSigned(tampered, requestHash: hash),
        throwsFormatException,
      );
    },
  );
}
