import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_receipt_codec.dart';

void main() {
  test(
    'independent framed receipt vector binds both complete certificates and local own event',
    () async {
      final f =
          jsonDecode(
                File(
                  'server/tests/fixtures/e2ee-migration-receipts-v3.json',
                ).readAsStringSync(),
              )
              as Map;
      Future<Map<String, dynamic>> section(
        Map<String, dynamic> common,
        Map<String, dynamic> local,
      ) => CryptoMigrationReceiptCodec.section(
        context: common,
        content: Map.from(f['content']),
        finance: Map.from(f['finance']),
        localIntents: local,
      );
      final observed = await section(
        Map.from(f['common']),
        Map.from(f['localIntents']),
      );
      expect(observed, {'kind': 'receipts', 'count': 6, 'root': f['root']});
      expect(
        await CryptoMigrationReceiptCodec.artifact(
          bindingId: f['localIntents']['artifactId'],
          sourceCommitment: '2' * 64,
          domain: 'finance',
          cert: Map.from(f['finance']),
        ),
        f['artifact'],
      );
      expect(
        (await section({
          ...Map<String, dynamic>.from(f['common']),
          'sourceInventoryRoot': '3' * 64,
        }, Map.from(f['localIntents'])))['root'],
        isNot(f['root']),
      );
      expect(
        (await section(Map.from(f['common']), {
          ...Map<String, dynamic>.from(f['localIntents']),
          'ownEventCommandHash': '4' * 64,
        }))['root'],
        isNot(f['root']),
      );
      await expectLater(
        section(Map.from(f['common']), {
          ...Map<String, dynamic>.from(f['localIntents']),
          'intentCount': null,
        }),
        throwsFormatException,
      );
      await expectLater(
        section(Map.from(f['common']), {
          ...Map<String, dynamic>.from(f['localIntents']),
          'intentCount': 9007199254740991,
        }),
        throwsFormatException,
      );
      await expectLater(
        section(Map.from(f['common']), {
          ...Map<String, dynamic>.from(f['localIntents']),
          'rawRequestHash': '0' * 64,
        }),
        throwsFormatException,
      );
    },
  );
}
