import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

import 'support/deleted_scope_fixture_20261105.dart';

Matcher _pending(String reason) => throwsA(
  isA<CryptoAuthorityPending>().having(
    (error) => error.reason,
    'reason',
    reason,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'retained deletion context cannot authorize another access instance',
    () async {
      final f = await deletedScopeFixture();
      final foreign = SessionCryptoAccess(account: f.account);
      final before = await f.durableDigest();
      final pins = Map<String, String>.from(f.secureMemory.values);
      final writes = f.secureMemory.writes.length;
      var callbacks = 0;
      final result = await f.access.withVerifiedDeletedScope(
        f.scope,
        f.wires[f.heads.last.headHash]!,
        (head) async {
          callbacks++;
          expect(head.epoch, 3);
          final calls = f.directory.calls.length;
          await expectLater(
            foreign.directoryAt(
              scopeId: f.scope,
              scopeHeadHash: head.headHash,
              accountId: f.own.accountId,
              directoryHeadHash: f.own.headHash,
              online: true,
            ),
            _pending('crypto_deleted_scope_evidence_expired'),
          );
          expect(f.directory.calls.length, calls);
          return 'verified-owner-only';
        },
      );
      expect(result, 'verified-owner-only');
      expect(callbacks, 1);
      expect(await f.durableDigest(), before);
      expect(f.secureMemory.values, pins);
      expect(f.secureMemory.writes.length, writes);
    },
  );

  test(
    'escaped retained deletion async work expires after callback finalization',
    () async {
      final f = await deletedScopeFixture();
      final before = await f.durableDigest();
      final pins = Map<String, String>.from(f.secureMemory.values);
      final writes = f.secureMemory.writes.length;
      final release = Completer<void>();
      late Future<Object?> escaped;
      var callbacks = 0;
      final result = await f.access.withVerifiedDeletedScope(
        f.scope,
        f.wires[f.heads.last.headHash]!,
        (head) async {
          callbacks++;
          expect(head.epoch, 3);
          // Future.then retains the active zone, but execution is held until
          // withVerifiedDeletedScope has returned and finalized that context.
          escaped = release.future.then(
            (_) => f.access.directoryAt(
              scopeId: f.scope,
              scopeHeadHash: head.headHash,
              accountId: f.own.accountId,
              directoryHeadHash: f.own.headHash,
              online: true,
            ),
          );
          return 'callback-complete';
        },
      );
      expect(result, 'callback-complete');
      expect(callbacks, 1);
      final calls = f.directory.calls.length;
      final denied = expectLater(
        escaped,
        _pending('crypto_deleted_scope_evidence_expired'),
      );
      release.complete();
      await denied;
      expect(f.directory.calls.length, calls);
      expect(await f.durableDigest(), before);
      expect(f.secureMemory.values, pins);
      expect(f.secureMemory.writes.length, writes);
    },
  );

  test(
    'retained deletion context cannot open ordinary current scope authority',
    () async {
      final f = await deletedScopeFixture();
      final before = await f.durableDigest();
      final pins = Map<String, String>.from(f.secureMemory.values);
      final writes = f.secureMemory.writes.length;
      var callbacks = 0;
      final result = await f.access.withVerifiedDeletedScope(
        f.scope,
        f.wires[f.heads.last.headHash]!,
        (head) async {
          callbacks++;
          expect(head.epoch, 3);
          final calls = f.directory.calls.length;
          await expectLater(
            f.access.currentHead(f.scope, online: true),
            _pending('crypto_deleted_scope_evidence_only'),
          );
          expect(f.directory.calls.length, calls);
          return 'historical-only';
        },
      );
      expect(result, 'historical-only');
      expect(callbacks, 1);
      expect(await f.durableDigest(), before);
      expect(f.secureMemory.values, pins);
      expect(f.secureMemory.writes.length, writes);
      expect(f.directory.calls, isNot(contains('crypto2.scope.headGet')));
    },
  );
}
