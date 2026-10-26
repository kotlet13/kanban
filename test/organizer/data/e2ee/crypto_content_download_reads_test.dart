import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_verified_finance_reads.dart';

void main() {
  test('P2 content completeness cannot borrow finance completeness', () async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final content = CryptoDomainReadState(db, 'p', domain: 'content');
    final finance = CryptoFinanceReadState(db, 'p');
    await db.execute('''INSERT INTO crypto_scope_state
      (partition,scope_id,domain,state,epoch,floor,access_revision,transport_cursor,projection_cursor,scope_sequence,complete)
      VALUES('p','s','finance','active',1,1,1,1,1,1,1)''');
    expect(await finance.capture('s'), isNotNull);
    expect(await content.capture('s'), isNull);
    await db.execute('''INSERT INTO crypto_scope_state
      (partition,scope_id,domain,state,epoch,floor,access_revision,transport_cursor,projection_cursor,scope_sequence,complete)
      VALUES('p','s','content','active',1,1,1,1,1,1,1)''');
    final before = await content.capture('s');
    expect(before, isNotNull);
    await db.execute(
      "UPDATE crypto_scope_state SET transport_cursor=2 WHERE domain='content'",
    );
    expect(await content.capture('s'), isNull);
    expect(await finance.capture('s'), isNotNull);
    await db.execute(
      "UPDATE crypto_scope_state SET projection_cursor=2 WHERE domain='content'",
    );
    expect(await content.capture('s'), isNot(before));
  });

  test(
    'P2 content chunks reuse only original current projection and lease',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.execute('''INSERT INTO crypto_scope_state
      (partition,scope_id,domain,state,epoch,floor,access_revision,transport_cursor,projection_cursor,scope_sequence,complete)
      VALUES('p','s','content','active',1,1,1,1,1,1,1)''');
      final state = CryptoDomainReadState(db, 'p', domain: 'content');
      final reads = CryptoVerifiedDomainReads();
      var pulls = 0, leaseCurrent = true;
      Future<void> chunk() => reads.read(
        's',
        pull: () async {
          pulls++;
        },
        capture: () async {
          final digest = await state.capture('s');
          if (digest == null) return null;
          return CryptoVerifiedDomainSnapshot(
            scopeId: 's',
            read: const CryptoReadContext(
              epoch: 1,
              accessRevision: 1,
              headHash: 'synthetic',
            ),
            stateDigest: digest,
            isCurrent: () async =>
                leaseCurrent && await state.capture('s') == digest,
          );
        },
      );
      for (var i = 0; i < 8; i++) {
        await chunk();
      }
      expect(pulls, 1);
      await db.execute('UPDATE crypto_scope_state SET scan_generation=1');
      await chunk();
      expect(pulls, 2);
      leaseCurrent = false;
      await chunk();
      await chunk();
      expect(pulls, 4);
      leaseCurrent = true;
      await chunk();
      reads.close();
      await chunk();
      expect(pulls, 6);
    },
  );
}
