import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_verified_finance_reads.dart';

class _Reads {
  final combined = CryptoVerifiedFinanceReads();
  int pulls = 0, epoch = 1, revision = 1;
  String head = 'head', digest = 'state';
  bool valid = true, complete = true;
  Future<bool> Function()? guard;
  Future<void> Function()? onPull;
  Future<void> read([String scope = 'scope']) => combined.read(
    scope,
    pull: () async {
      pulls++;
      await onPull?.call();
    },
    capture: () async {
      if (!complete) return null;
      final capturedHead = head, capturedDigest = digest;
      final capturedEpoch = epoch, capturedRevision = revision;
      return CryptoVerifiedFinanceSnapshot(
        scopeId: scope,
        read: CryptoReadContext(
          epoch: epoch,
          accessRevision: revision,
          headHash: head,
        ),
        stateDigest: digest,
        isCurrent: () async =>
            (await (guard?.call() ?? Future.value(valid))) &&
            complete &&
            capturedHead == head &&
            capturedDigest == digest &&
            capturedEpoch == epoch &&
            capturedRevision == revision,
      );
    },
  );
}

void main() {
  test('three consumers share one exact successful pull', () async {
    final reads = _Reads();
    await reads.read();
    await reads.read();
    await reads.read();
    expect(reads.pulls, 1);
    await reads.read('other');
    expect(reads.pulls, 2);
  });

  for (final coordinate in ['head', 'epoch', 'access revision', 'projection']) {
    test('changed $coordinate needs its own verified pull', () async {
      final reads = _Reads();
      await reads.read();
      switch (coordinate) {
        case 'head':
          reads.head = 'new';
        case 'epoch':
          reads.epoch++;
        case 'access revision':
          reads.revision++;
        case 'projection':
          reads.digest = 'new';
      }
      await reads.read();
      expect(reads.pulls, 2);
    });
  }

  test('missing complete result and failed pull never seed reuse', () async {
    final reads = _Reads()..complete = false;
    await reads.read();
    await reads.read();
    expect(reads.pulls, 2);
    reads.complete = true;
    reads.onPull = () async => throw StateError('synthetic');
    await expectLater(reads.read(), throwsStateError);
    reads.onPull = null;
    await reads.read();
    expect(reads.pulls, 4);
  });

  test('mutation during first pull captures only final state', () async {
    final reads = _Reads();
    reads.onPull = () async {
      reads.combined.invalidate();
      reads.digest = 'post-mutation';
    };
    await reads.read();
    await reads.read();
    expect(reads.pulls, 1);
    reads.combined.invalidate();
    await reads.read();
    expect(reads.pulls, 2);
  });

  test(
    'invalid original authority guard cannot reuse a prior result',
    () async {
      final reads = _Reads();
      await reads.read();
      reads.valid = false;
      await reads.read();
      await reads.read();
      expect(reads.pulls, 3);
    },
  );

  test('original pull budget expires without extending on reuse', () async {
    final reads = _Reads();
    await reads.read();
    await reads.read();
    await Future<void>.delayed(const Duration(milliseconds: 5020));
    await reads.read();
    expect(reads.pulls, 2);
  });

  test(
    'invalidation during final async guard cannot return cached result',
    () async {
      final reads = _Reads();
      await reads.read();
      var checks = 0;
      reads.guard = () async {
        if (++checks == 1) reads.combined.invalidate();
        return true;
      };
      await reads.read();
      expect(reads.pulls, 2);
    },
  );

  test('close during final seed guard prevents later reuse', () async {
    final reads = _Reads();
    reads.guard = () async {
      reads.combined.close();
      return true;
    };
    await reads.read();
    reads.guard = null;
    await reads.read();
    expect(reads.pulls, 2);
  });

  group('bounded SQLite equality evidence (never authority)', () {
    late CollaborationDatabase db;
    late CryptoFinanceReadState state;
    setUp(() async {
      db = CollaborationDatabase(NativeDatabase.memory());
      state = CryptoFinanceReadState(db, 'partition');
      await db.execute('''INSERT INTO crypto_scope_state
        (partition,scope_id,domain,state,epoch,floor,access_revision,transport_cursor,projection_cursor,scope_sequence,complete)
        VALUES('partition','scope','finance','active',1,1,1,1,1,1,1)''');
      await db.execute(
        '''INSERT INTO crypto_business_records
        (partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis)
        VALUES('partition','scope','finance','record','financeAccount',1,'proof',0,'{}','{}','currentEpoch')''',
      );
    });
    tearDown(() => db.close());

    test('exact local revision and payload changes alter equality', () async {
      final first = await state.capture('scope');
      expect(first, isNotNull);
      expect(await state.capture('scope'), first);
      await db.execute("UPDATE crypto_business_records SET crypto_revision=2");
      final second = await state.capture('scope');
      expect(second, isNot(first));
      await db.execute(
        "UPDATE crypto_business_records SET projection='changed'",
      );
      expect(await state.capture('scope'), isNot(second));
    });

    test(
      'cursor, checkpoint and access generation cannot share equality',
      () async {
        final first = await state.capture('scope');
        await db.execute('UPDATE crypto_scope_state SET scan_generation=1');
        final second = await state.capture('scope');
        expect(second, isNot(first));
        await db.execute(
          "INSERT INTO local_meta(name,value) VALUES('finance_access_generation:partition:scope','1')",
        );
        final third = await state.capture('scope');
        expect(third, isNot(second));
        await db.execute(
          '''INSERT INTO crypto_domain_checkpoints VALUES
        ('partition','scope','finance','head',1,1,1,'manifest',1,'snapshot','{}','verifiedCheckpoint')''',
        );
        expect(await state.capture('scope'), isNot(third));
      },
    );

    test('incomplete or unprojected state opts out', () async {
      await db.execute('UPDATE crypto_scope_state SET complete=0');
      expect(await state.capture('scope'), isNull);
      await db.execute(
        'UPDATE crypto_scope_state SET complete=1,transport_cursor=2',
      );
      expect(await state.capture('scope'), isNull);
      expect(await state.capture('other'), isNull);
    });

    test('payload budget opts out without changing source records', () async {
      await db.execute('UPDATE crypto_business_records SET projection=?', [
        'x' * 262145,
      ]);
      expect(await state.capture('scope'), isNull);
      expect(
        (await db.rows(
          'SELECT length(projection) AS n FROM crypto_business_records',
        )).single['n'],
        262145,
      );
    });

    test('large materialized domain opts out at bounded row count', () async {
      await db.transaction(() async {
        for (var index = 0; index < 128; index++) {
          await db.execute(
            '''INSERT INTO crypto_business_records
            SELECT partition,scope_id,domain,?,type,crypto_revision,legacy_revision,record_proof_hash,deleted,raw_payload,projection,history_basis,revision_namespace
            FROM crypto_business_records WHERE id='record' ''',
            ['row$index'],
          );
        }
      });
      expect(await state.capture('scope'), isNull);
    });
  });
}
