import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_checkpoint_publisher.dart';
import 'e2ee/crypto_checkpoint_supersession_20261102_test.dart'
    show reauthorizationFixture, scope;
import 'held_command_coordinator_20261102_test.dart'
    show reauthorizationCoordinatorFixture;

// Outer content/finance transport and receipt-sweep dispatch are synthetic.
// The full-pass hook invokes the real signed checkpoint publisher, verifier,
// supersession transaction and coordinator completion on the SAME SQLite DB.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final denied in [false, true]) {
    test(
      'manual coordinator and verified checkpoint retirement with denied=$denied',
      () async {
        final f = await reauthorizationCoordinatorFixture();
        final c = await reauthorizationFixture(
          downloaded: true,
          count: 19,
          database: f.db,
          session: f.session,
        );
        c.wire.denied = denied;
        final prior = f.repo.state.lastSuccessfulSyncAt;
        f.now = f.now.add(const Duration(minutes: 1));
        final rows = await f.db.rows(
          "SELECT * FROM crypto_outbox WHERE state='blocked' ORDER BY sequence",
        );
        var publications = 0;
        f.transport.beforeScopes = () async {
          f.transport.beforeScopes = null;
          publications++;
          await CryptoDomainCheckpointPublisher(
            c.runtime,
          ).publish(scope, 'content');
        };
        f.transport.calls.clear();
        await (f.repo as CollaborationRepository).syncNow(manual: true);
        expect(
          publications,
          1,
          reason:
              'calls=${f.transport.calls}, error=${f.repo.state.lastError}, failures=${f.repo.state.syncFailures}',
        );
        expect(f.transport.calls, containsAll(['sync.pull', 'finance.pull']));
        expect(
          await f.db.rows(
            "SELECT * FROM crypto_outbox WHERE state='blocked' ORDER BY sequence",
          ),
          rows,
        );
        expect(f.repo.state.blockedSyncCommandCount, denied ? 19 : 0);
        if (denied) {
          expect(f.repo.state.lastError, isNotNull);
          expect(f.repo.state.lastSuccessfulSyncAt, prior);
        } else {
          expect(f.repo.state.lastError, isNull);
          expect(f.repo.state.lastSuccessfulSyncAt, f.now);
          f.transport.calls.clear();
          await (f.repo as CollaborationRepository).syncNow();
          expect(f.transport.calls, ['account.changes']);
        }
      },
    );
  }
}
