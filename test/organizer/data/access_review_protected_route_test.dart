import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'access_review_coordinator_test.dart' as fixture;

void main() {
  for (final fenced in [false, true]) {
    test(
      'startup access review uses production router and never legacy fallback fenced=$fenced',
      () async {
        final f = await fixture.setup();
        await f.block(f.parent);
        if (fenced)
          await f.repo.database.execute(
            'INSERT INTO crypto_restore_fences(partition,minimum_transport,backup_id,state) VALUES(?,?,?,?)',
            [f.p, 2, 'test-fence', 'requires_reconciliation'],
          );
        final before = await f.repo.database.rows(
          'SELECT * FROM scopes ORDER BY id',
        );
        var accountCalls = 0;
        final guarded = CollaborationRepository(
          f.repo.database,
          f.transport,
          f.store,
          ownsDatabase: false,
          cryptoRouter: CryptoBusinessRouter(
            database: f.repo.database,
            accountFor: (_) async {
              accountCalls++;
              throw const CryptoAuthorityPending('crypto_stale_identity');
            },
          ),
        );
        addTearDown(guarded.close);
        await guarded.initialize();
        await expectLater(
          guarded.checkAllAccess(),
          throwsA(
            fenced
                ? isA<CollaborationException>()
                : isA<CryptoAuthorityPending>(),
          ),
        );
        expect(accountCalls, fenced ? 0 : 1);
        expect(f.transport.calls.where((s) => s == 'scopes.list'), isEmpty);
        expect(
          await f.repo.database.rows('SELECT * FROM scopes ORDER BY id'),
          before,
        );
      },
    );
  }
}
