import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_document_backup_drafts.dart';

void main() {
  test(
    'account switch and local-only exports retain foreign candidates locally without disclosing them',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      Map<String, dynamic> empty(String partition) => {
        'version': 1,
        'partition': partition,
        'tables': {
          for (final table in cryptoDocumentDraftTables.keys) table: <Object>[],
        },
      };
      final a = empty('A'), b = empty('B');
      final aId = '11111111-1111-4111-a111-111111111111';
      final bId = '22222222-2222-4222-a222-222222222222';
      a['restoredCandidates'] = [
        {'backupId': bId, 'partition': 'B', 'tables': b['tables']},
      ];
      await db.execute('INSERT INTO restored_backups VALUES(?,?,?,?)', [
        aId,
        '2026-10-17',
        'A',
        jsonEncode({'cryptoPrivateDrafts': a}),
      ]);
      await db.execute('INSERT INTO restored_backups VALUES(?,?,?,?)', [
        bId,
        '2026-10-17',
        'B',
        jsonEncode({'cryptoPrivateDrafts': b}),
      ]);
      final exportedA = await exportCryptoDocumentDrafts(db, 'A');
      expect(
        (exportedA['restoredCandidates'] as List).map((r) => r['partition']),
        ['A'],
      );
      final exportedB = await exportCryptoDocumentDrafts(db, 'B');
      expect(
        (exportedB['restoredCandidates'] as List).map((r) => r['partition']),
        ['B'],
      );
      final local = await exportCryptoDocumentDrafts(db, null);
      expect(local.containsKey('restoredCandidates'), false);
      expect(await db.rows('SELECT id FROM restored_backups'), hasLength(2));
    },
  );

  test(
    'private pending file DTO preserves bytes and exact intent, excludes caches and rejects foreign partitions',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory()),
          id = '11111111-1111-4111-a111-111111111111',
          scope = '22222222-2222-4222-a222-222222222222';
      try {
        await db.execute(
          'INSERT INTO crypto_document_uploads VALUES(?,?,?,?,?,?)',
          [
            'profile',
            scope,
            id,
            jsonEncode({'name': 'private.txt', 'size': 3}),
            3,
            'receiving',
          ],
        );
        await db.execute(
          'INSERT INTO crypto_document_upload_chunks VALUES(?,?,?,?)',
          [
            'profile',
            id,
            0,
            Uint8List.fromList([1, 2, 3]),
          ],
        );
        await db.execute('INSERT INTO crypto_document_cache VALUES(?,?,?,?)', [
          'profile',
          id,
          'cache',
          Uint8List.fromList([9]),
        ]);
        final result = await exportCryptoDocumentDrafts(db, 'profile');
        validateCryptoDocumentDrafts(result, 'profile');
        expect(
          (result['tables'] as Map).containsKey('crypto_document_cache'),
          false,
        );
        final rows = result['tables']['crypto_document_upload_chunks'] as List;
        expect(decodeCryptoDocumentDraftBlob(rows.single['bytes']), [1, 2, 3]);
        expect(
          () => validateCryptoDocumentDrafts(result, 'other'),
          throwsFormatException,
        );
        final malicious = jsonDecode(jsonEncode(result)) as Map;
        malicious['tables']['crypto_document_upload_chunks'][0]['bytes'] = {
          'blobBase64': '%%%',
        };
        expect(
          () => validateCryptoDocumentDrafts(malicious, 'profile'),
          throwsFormatException,
        );
      } finally {
        await db.close();
      }
    },
  );
}
