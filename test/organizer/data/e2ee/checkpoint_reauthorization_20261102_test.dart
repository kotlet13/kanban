import 'dart:convert';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart'
    show cryptoSha256;
import 'held_command_observation_test.dart' show reauthorizationResumeFixture;
import 'package:kanban/organizer/domain/held_sync_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_active_outbox.dart';
import 'package:kanban/organizer/data/e2ee/crypto_checkpoint_supersession.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_checkpoint_publisher.dart';
import 'package:kanban/organizer/domain/payment_completion_diagnostics.dart';
import 'crypto_checkpoint_supersession_20261102_test.dart'
    show reauthorizationFixture, scope;

Future<int> active(dynamic f) async =>
    ((await f.runtime.database.rows(
                  "SELECT COUNT(*) AS n FROM crypto_outbox WHERE partition=? AND state='blocked' AND ${cryptoActiveOutboxPredicate()}",
                  [f.runtime.partition],
                ))
                as List)
            .single['n']
        as int;
Future<int> reconcile(dynamic f) async => CryptoCheckpointSupersession(
  f.runtime,
).reconcile(scope, 'content', await f.access.readContext(scope, 'content'));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '19 reauthorization checkpoints retire against downloaded verified attestation',
    () async {
      final f = await reauthorizationFixture(downloaded: true, count: 19);
      final before = await f.runtime.database.rows(
        "SELECT * FROM crypto_outbox WHERE state='blocked' ORDER BY sequence",
      );
      expect(await active(f), 19);
      expect(
        await CryptoDomainCheckpointPublisher(
          f.runtime,
        ).publish(scope, 'content'),
        PaymentCheckpointStep.reusableCheckpoint,
      );
      expect(await active(f), 0);
      expect(
        await f.runtime.database.rows(
          "SELECT * FROM crypto_outbox WHERE state='blocked' ORDER BY sequence",
        ),
        before,
      );
      expect(
        await f.runtime.database.rows(
          "SELECT * FROM crypto_outbox WHERE state='applied'",
        ),
        isEmpty,
      );
      expect(f.wire.lookups, 19);
      expect(
        await f.runtime.database.rows(
          "SELECT * FROM crypto_outbox_attempts WHERE event='checkpoint_superseded_locally'",
        ),
        hasLength(19),
      );
    },
  );
  test(
    'later complete inventory retires older derived assertion while preserving evidence',
    () async {
      final f = await reauthorizationFixture(
        downloaded: true,
        laterInventory: true,
      );
      final before = await f.runtime.queue.store.outgoing(f.old);
      expect(await reconcile(f), 1);
      expect(await active(f), 0);
      expect(await f.runtime.queue.store.outgoing(f.old), before);
    },
  );
  test(
    'authorized other member downloaded checkpoint retires own reauthorization work',
    () async {
      final f = await reauthorizationFixture(
        downloaded: true,
        otherAuthor: true,
      );
      expect(await reconcile(f), 1);
      expect(await active(f), 0);
      expect(
        await f.runtime.database.rows(
          "SELECT * FROM crypto_outbox WHERE state='applied'",
        ),
        isEmpty,
      );
    },
  );
  for (final mode in ['fresh', 'stillStale', 'revoked', 'wrongDevice']) {
    test('reauthorization resume revalidates exact original for $mode', () async {
      final f = await reauthorizationResumeFixture();
      final before = await f.store.outgoing(f.id);
      f.guardReason = mode == 'fresh'
          ? null
          : mode == 'revoked'
          ? 'permission_revoked'
          : 'scope_reauthorization_required';
      if (mode == 'wrongDevice') {
        // A valid immutable envelope from another device is never sent by this one.
        final row = await f.store.outgoing(f.id);
        final proof = jsonDecode(row['signed_body'] as String) as Map;
        final raw =
            jsonDecode(
                  utf8.decode(base64Decode(proof['commandBase64'] as String)),
                )
                as Map<String, dynamic>;
        raw['deviceId'] = f.crypto.randomId();
        final changed = f.crypto.signDomain(
          raw,
          f.keys.secretKey,
          'JivieE2EE/v2\n',
        );
        // The queue validates binding before it evaluates device identity.
        final bytes = base64Decode(changed['commandBase64'] as String);
        final hash = await cryptoSha256(bytes);
        await f.db.execute(
          'UPDATE crypto_outbox SET signed_body=?,request_hash=? WHERE request_id=?',
          [jsonEncode(changed), hash, f.id],
        );
      }
      HeldCommandDiagnostic? last;
      await f.queue.resumeHeldCommands(
        requestIds: <String>{f.id as String},
        checkCurrent: () async {},
        observe: (id, hash, d) {
          last = d;
        },
      );
      expect(
        last!.resume,
        mode == 'fresh' ? HeldResumeResult.sent : HeldResumeResult.guardBlocked,
      );
      expect(f.transport.mutations, mode == 'fresh' ? hasLength(1) : isEmpty);
      if (mode == 'fresh') {
        expect((await f.store.outgoing(f.id))['state'], 'applied');
        expect(
          (await f.store.outgoing(f.id))['signed_body'],
          before['signed_body'],
        );
      } else {
        expect((await f.store.outgoing(f.id))['state'], 'blocked');
      }
    });
  }
  for (final mode in [
    'denied',
    'terminal',
    'missingHistory',
    'incomplete',
    'missingCheckpoint',
    'claimedRecord',
    'tamperedSignature',
    'differentSameSequence',
    'staleDuringLookup',
    'noAudit',
    'changedReplacement',
  ]) {
    test('reauthorization retains guard for $mode', () async {
      final f = await reauthorizationFixture(downloaded: true);
      final db = f.runtime.database, p = f.runtime.partition;
      if (mode == 'denied') f.wire.denied = true;
      if (mode == 'terminal') f.wire.outcome = 'applied';
      if (mode == 'missingHistory') f.access.historyMissing = true;
      if (mode == 'incomplete') {
        await db.execute('UPDATE crypto_scope_state SET complete=0');
      }
      if (mode == 'missingCheckpoint') {
        await db.execute('DELETE FROM crypto_domain_checkpoints');
      }
      if (mode == 'claimedRecord') {
        await db.execute(
          'INSERT INTO crypto_outbox_records VALUES(?,?,?,?,?,?)',
          [p, scope, 'content', 'claim', 0, f.old],
        );
      }
      if (mode == 'tamperedSignature') {
        final row = await f.runtime.queue.store.outgoing(f.old);
        final proof = jsonDecode(row['signed_body'] as String) as Map;
        proof['signatureBase64'] = base64Encode(List<int>.filled(64, 0));
        await db.execute(
          'UPDATE crypto_outbox SET signed_body=? WHERE request_id=?',
          [jsonEncode(proof), f.old],
        );
      }
      if (mode == 'differentSameSequence') {
        await db.execute(
          "UPDATE crypto_domain_checkpoints SET manifest_hash=?",
          ['a' * 64],
        );
      }
      if (mode == 'staleDuringLookup') {
        f.wire.afterLookup = () async {
          await db.execute('UPDATE crypto_scope_state SET complete=0');
        };
      }
      if (mode == 'noAudit' || mode == 'changedReplacement') {
        expect(await reconcile(f), 1);
        if (mode == 'noAudit') {
          await db.execute('DELETE FROM crypto_outbox_attempts');
        }
        if (mode == 'changedReplacement') {
          await db.execute(
            "UPDATE crypto_domain_checkpoints SET authorization='{}'",
          );
        }
      } else {
        expect(await reconcile(f), 0);
      }
      expect(await active(f), 1);
      expect((await f.runtime.queue.store.outgoing(f.old))['state'], 'blocked');
    });
  }
}
