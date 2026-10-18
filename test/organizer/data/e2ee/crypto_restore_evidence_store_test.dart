import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_backup_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_restore_evidence_store.dart';

void main() {
  test(
    'all newer and older restore candidates survive; concurrent restore prevents stale reconciliation',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const partition = 'synthetic';
      final store = CryptoRestoreEvidenceStore(db, partition);
      Future<Map<String, dynamic>> evidence(int floor) async {
        final result = await exportCryptoEvidence(db, partition);
        (result['tables'] as Map)['crypto_scope_state'] = [
          {
            'partition': partition,
            'scope_id': '00000000-0000-4000-8000-000000000001',
            'domain': 'content',
            'state': 'active',
            'epoch': floor,
            'scan_generation': 0,
            'access_revision': floor,
            'transport_cursor': floor,
            'projection_cursor': floor,
            'scope_sequence': floor,
            'complete': 1,
            'floor': floor,
            'manifest': null,
          },
        ];
        return result;
      }

      await db.transaction(
        () async => fenceRestoredCryptoEvidence(
          db,
          await evidence(9),
          partition,
          'newer',
        ),
      );
      final first = await store.snapshot();
      await db.transaction(
        () async => fenceRestoredCryptoEvidence(
          db,
          await evidence(3),
          partition,
          'older',
        ),
      );
      expect(await db.rows('SELECT * FROM crypto_scope_state'), isEmpty);
      expect((await store.snapshot()).candidates.map((c) => c['backupId']), [
        'newer',
        'older',
      ]);
      var merged = false;
      await expectLater(
        store.commitVerified(
          first,
          mergeVerifiedAnchors: () async {
            merged = true;
          },
        ),
        throwsFormatException,
      );
      expect(merged, false);
      expect(
        (await db.rows(
          'SELECT state FROM crypto_restore_fences',
        )).single['state'],
        'requires_reconciliation',
      );
      final both = await store.snapshot();
      // A real authority verifier must authenticate these logs; this SQL store
      // test proves every candidate is available, not merely the latest filename.
      expect(jsonEncode(both.candidates), contains('newer'));
      expect(jsonEncode(both.candidates), contains('older'));
      final reexport = await exportCryptoEvidence(db, partition);
      final target = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      await target.transaction(
        () async => fenceRestoredCryptoEvidence(
          target,
          reexport,
          partition,
          'reexport',
        ),
      );
      expect(
        (await CryptoRestoreEvidenceStore(
          target,
          partition,
        ).snapshot()).candidates,
        hasLength(3),
      );
      await store.commitVerified(both, mergeVerifiedAnchors: () async {});
      expect(
        (await db.rows(
          'SELECT state FROM crypto_restore_fences',
        )).single['state'],
        'verified',
      );
      expect(
        await db.rows('SELECT * FROM crypto_restore_evidence'),
        hasLength(2),
      );
    },
  );
}
