import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';

void main() {
  final enabled = Platform.environment['JIVIE_CRYPTO_HTTP_FIXTURE'] != null;
  test(
    'Dart and PHP canonical golden including Unicode and malformed input',
    () async {
      final container =
          Platform.environment['JIVIE_CRYPTO_DOCKER'] ??
          'familyhub-crypto-tests-sqlite-1';
      Future<String> php(String mode, Uint8List bytes) async {
        final process = await Process.start('docker', [
          'exec',
          '-i',
          container,
          'php',
          '-r',
          r'''
require '/var/www/app/app/common.php';
$raw=stream_get_contents(STDIN);
try {
  if($argv[1]==='canonical') {
    echo base64_encode(\Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::canonical(json_decode($raw,false,34,JSON_THROW_ON_ERROR)));
  } else {
    \Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::decode(['commandBase64'=>base64_encode($raw),'signatureBase64'=>base64_encode(str_repeat(chr(0),64))]);
    echo 'accepted';
  }
} catch(\Throwable $e) { echo 'rejected'; }
''',
          mode,
        ]);
        process.stdin.add(bytes);
        await process.stdin.close();
        final output = process.stdout.transform(utf8.decoder).join();
        final error = process.stderr.transform(utf8.decoder).join();
        expect(await process.exitCode, 0, reason: await error);
        return output;
      }

      final vector = <String, dynamic>{
        'z': [9007199254740991, -9007199254740991, true, false, null, {}, []],
        'unicode': 'č 🦉 / \\ " \u0000\b\f\n\r\t \u2028\u2029',
        'a': {
          'nested': [
            'value',
            {'empty': ''},
          ],
        },
      };
      final bytes = CryptoJson.encode(vector);
      expect(await php('canonical', bytes), base64Encode(bytes));
      expect(await php('decode', bytes), 'accepted');
      for (final malformed in [
        '{"a":1,"a":2}',
        '{"a":1.0}',
        '{"a":1} ',
        '{"\\u0061":1}',
        '{"a":9007199254740992}',
        '{"a":"\\ud800"}',
      ]) {
        final bytes = Uint8List.fromList(utf8.encode(malformed));
        expect(() => CryptoJson.decode(bytes), throwsFormatException);
        expect(await php('decode', bytes), 'rejected', reason: malformed);
      }
    },
    skip: enabled ? false : 'Requires a dedicated Docker PHP crypto runtime',
  );
}
