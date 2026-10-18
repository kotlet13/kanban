import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_finance.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_addresses.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_history.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:sodium/sodium.dart';

import '../collaboration_repository_test.dart' show FakeServer, FakeTransport;

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String p) async => null;
  @override
  Future<void> write(String p, String v) async {}
}

void main() {
  test(
    'finance group validator preserves references, parent facts and uniqueness before visible effects',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final crypto = CryptoCodec(await SodiumInit.init());
      final session = DeviceSession(
        AccountSession(
          serverUrl: 'https://synthetic.invalid/',
          serverId: crypto.randomId(),
          accountId: crypto.randomId(),
          userId: 1,
          username: 'synthetic',
          displayName: 'Synthetic',
          deviceId: crypto.randomId(),
          expiresAt: DateTime.utc(2030),
        ),
        'synthetic',
      );
      final transport = FakeTransport(FakeServer());
      addTearDown(transport.close);
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: transport,
          store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
          isCurrent: () => true,
        ),
      );
      final context = CryptoBusinessSession(
        account,
        SessionCryptoAccess(account: account),
        db,
      );
      final finance = CryptoBusinessFinance(context),
          scope = crypto.randomId(),
          ledger = crypto.randomId(),
          expense = crypto.randomId(),
          task = crypto.randomId();
      final now = DateTime.utc(2026, 10, 17);
      final bank = SharedFinanceAccount(
        id: ledger,
        name: 'Account',
        currency: 'EUR',
        createdAt: now,
        updatedAt: now,
      ).toPayload(contractVersion: 3);
      final raw = SharedFinanceEntry(
        id: expense,
        accountId: ledger,
        kind: FinanceEntryKind.expense,
        status: SharedFinanceStatus.posted,
        amountMinor: 123,
        currency: 'EUR',
        title: 'Expense',
        notes: '',
        category: '',
        occurredAt: now,
        createdAt: now,
        updatedAt: now,
      ).toPayload(contractVersion: 3);
      Future<void> seed(
        String id,
        String type,
        Map<String, Object?> payload, {
        String domain = 'finance',
      }) async {
        final address = CryptoRecordAddress.forType(
          serverId: session.profile.serverId,
          scopeId: scope,
          type: type,
          canonicalId: id,
          domain: domain,
        );
        // Every replacement below is deliberate synthetic current state.
        await db.execute(
          'DELETE FROM crypto_business_addresses WHERE partition=? AND scope_id=? AND source_kind=? AND canonical_id=?',
          [context.partition, scope, address.sourceKind, id],
        );
        await CryptoBusinessAddresses(
          db,
          context.partition,
          session.profile.serverId,
        ).install(address);
        await db.execute(
          'INSERT OR REPLACE INTO crypto_business_records VALUES(?,?,?,?,?,1,0,?,0,?,?,?,\'crypto\')',
          [
            context.partition,
            scope,
            domain,
            address.wireId,
            type,
            'a' * 64,
            jsonEncode(payload),
            jsonEncode({'id': id}),
            'currentEpoch',
          ],
        );
      }

      Future<CryptoBusinessProjection> candidate(
        String id,
        String type,
        Map<String, dynamic>? value, {
        Map<String, dynamic>? before,
      }) async => CryptoBusinessProjection(
        record: {
          'scopeId': scope,
          'domain': 'finance',
          'id': context.address(scope, 'finance', type, id).wireId,
          '_canonicalId': id,
          'type': type,
          'metadata': {
            'uniqueRefs': await finance.uniqueRefs(scope, type, value),
          },
        },
        raw: value,
        previousRaw: before,
      );
      await seed(ledger, 'financeAccount', bank);
      await finance.validate([
        await candidate(expense, 'financeEntry', Map.from(raw)),
      ]);
      await expectLater(
        finance.validate([
          await candidate(expense, 'financeEntry', {...raw, 'currency': 'USD'}),
        ], forWrite: true),
        throwsFormatException,
      );
      await seed(ledger, 'financeEntry', raw);
      await expectLater(
        finance.validate([
          await candidate(expense, 'financeEntry', Map.from(raw)),
        ], forWrite: true),
        throwsFormatException,
      );
      await seed(ledger, 'financeAccount', {...bank, 'archived': true});
      await expectLater(
        finance.validate([
          await candidate(expense, 'financeEntry', Map.from(raw)),
        ], forWrite: true),
        throwsFormatException,
      );
      await finance.validate([
        await candidate(
          expense,
          'financeEntry',
          Map.from(raw),
          before: Map.from(raw),
        ),
      ]);
      await seed(ledger, 'financeAccount', bank);
      await seed(expense, 'financeEntry', raw);
      await expectLater(
        finance.validate([
          await candidate(
            ledger,
            'financeAccount',
            null,
            before: Map.from(bank),
          ),
        ], forWrite: true),
        throwsFormatException,
      );
      await finance.validate([
        await candidate(ledger, 'financeAccount', null, before: Map.from(bank)),
        await candidate(expense, 'financeEntry', null, before: Map.from(raw)),
      ]);
      await seed(task, 'task', {
        'dueAt': now.toIso8601String(),
      }, domain: 'content');
      final linked = <String, dynamic>{
        ...raw,
        'taskId': task,
        'plannedAt': now.toIso8601String(),
      };
      await expectLater(
        finance.validate([
          await candidate(expense, 'financeEntry', linked),
          await candidate(crypto.randomId(), 'financeEntry', linked),
        ], forWrite: true),
        throwsFormatException,
      );
      await expectLater(
        finance.validate([
          await candidate(expense, 'financeEntry', {
            ...linked,
            'plannedAt': now.add(const Duration(days: 1)).toIso8601String(),
          }),
        ], forWrite: true),
        throwsFormatException,
      );
      // An offline financier sees an authentic old fact after the content
      // editor moves the task. This is unfinished derivation, not corruption.
      await seed(task, 'task', {
        'dueAt': now.add(const Duration(days: 1)).toIso8601String(),
      }, domain: 'content');
      await expectLater(
        finance.validate([await candidate(expense, 'financeEntry', linked)]),
        throwsA(isA<CryptoProjectionPending>()),
      );
      await finance.validate([
        await candidate(expense, 'financeEntry', {
          ...linked,
          'plannedAt': now.add(const Duration(days: 1)).toIso8601String(),
        }),
      ]);
      await expectLater(
        finance.validate([
          await candidate(expense, 'financeEntry', {
            ...raw,
            'accountScopeId': crypto.randomId(),
          }),
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'missing certified account selection witness',
            'crypto_account_choices_shape',
          ),
        ),
      );
      // Validation has no projection side effect, even for a valid first leg of a
      // later-invalid authenticated group.
      expect(
        (await context.record(scope, 'finance', expense))!['crypto_revision'],
        1,
      );
      // A restored authenticated floor must intersect the candidate chain, even
      // when an earlier complete cache job proves a different signed fork.
      final signing = crypto.sodium.crypto.sign.keyPair();
      final key = crypto.sodium.secureRandom(32);
      addTearDown(signing.secretKey.dispose);
      addTearDown(key.dispose);
      final codec = CryptoRecordProofCodec(crypto);
      final address = context.address(
        scope,
        'content',
        'taskDerivationIntent',
        crypto.randomId(),
      );
      Future<CryptoProjectionRecord> signed(
        int revision,
        String previous,
      ) async {
        final batchId = crypto.randomId();
        final proof = codec.sealRecord(
          serverId: session.profile.serverId,
          accountId: session.profile.accountId,
          deviceId: session.profile.deviceId,
          batchId: batchId,
          scopeId: scope,
          id: address.wireId,
          type: 'taskDerivationIntent',
          expectedRevision: revision - 1,
          epoch: 1,
          accessRevision: 0,
          membershipHeadHash: 'a' * 64,
          domain: 'content',
          contentContract: 6,
          operationId: crypto.randomId(),
          previousRecordHash: previous,
          deleted: false,
          plaintext: Uint8List.fromList(utf8.encode('{}')),
          metadata: {
            'identity': address.identity,
            'references': <Object>[],
            'uniqueRefs': <Object>[],
            'blobIds': <Object>[],
          },
          contentKey: key,
          signingKey: signing.secretKey,
        );
        final commitment = await codec.commitBatch(
          serverId: session.profile.serverId,
          accountId: session.profile.accountId,
          deviceId: session.profile.deviceId,
          batchId: batchId,
          records: [proof],
          projectionToken: (r) async => codec.projectionGroupToken(r, key),
          signingKey: signing.secretKey,
        );
        final body =
            CryptoJson.decode(cryptoBase64(proof['commandBase64']))
                as Map<String, dynamic>;
        final wire = {
          ...body,
          'revision': revision,
          'sequence': revision,
          'authorization': {
            'recordProof': proof,
            'batchCommitment': commitment,
          },
        };
        final verified = await codec.verifyWire(
          serverId: session.profile.serverId,
          wire: wire,
          trustedSigningKey: signing.publicKey,
          currentEpoch: true,
        );
        return CryptoProjectionRecord(
          wire,
          verified,
          null,
          historyBasis: 'currentEpoch',
          batchKey: await codec.digest(commitment),
        );
      }

      final anchor = await signed(2, 'b' * 64);
      final anchorHash = await codec.digest(
        Map<String, dynamic>.from(
          (anchor.wire['authorization'] as Map)['recordProof'] as Map,
        ),
      );
      await db.execute(
        'INSERT INTO crypto_restore_record_anchors VALUES(?,?,?,?,?,?,?)',
        [
          context.partition,
          scope,
          'content',
          address.wireId,
          2,
          anchorHash,
          jsonEncode(anchor.wire),
        ],
      );
      final alternate = await signed(2, 'c' * 64);
      final alternateHash = await codec.digest(
        Map<String, dynamic>.from(
          (alternate.wire['authorization'] as Map)['recordProof'] as Map,
        ),
      );
      final fork = await signed(3, alternateHash);
      await db.execute(
        'INSERT INTO crypto_business_history_jobs VALUES(?,?,?,?,?,?,?,?,1)',
        [
          context.partition,
          scope,
          'content',
          address.wireId,
          2,
          alternateHash,
          0,
          '0' * 64,
        ],
      );
      final history = CryptoBusinessHistory(context);
      final existingJobs = await db.rows(
        'SELECT * FROM crypto_business_history_jobs ORDER BY target_hash',
      );
      final identityPending = throwsA(
        isA<CryptoDirectoryException>().having(
          (error) => error.code,
          'unverified current directory',
          'directory_freshness_pending',
        ),
      );
      // A complete SQL job cannot bypass current identity authentication.
      await expectLater(history.prepare([fork]), identityPending);
      expect(
        await db.rows(
          'SELECT * FROM crypto_business_history_jobs ORDER BY target_hash',
        ),
        existingJobs,
      );
      await expectLater(
        history.requireRestoredIntersection(fork),
        throwsFormatException,
      );
      final successor = await signed(3, anchorHash);
      await expectLater(history.prepare([successor]), identityPending);
      expect(
        await db.rows(
          'SELECT * FROM crypto_business_history_jobs WHERE target_hash=?',
          [alternateHash],
        ),
        existingJobs,
      );
      expect(
        (await db.rows(
          'SELECT complete FROM crypto_business_history_jobs WHERE target_hash=?',
          [anchorHash],
        )).single['complete'],
        0,
      );
      // The SQL-only projection CAS independently requires the exact signed
      // restored anchor, regardless of the unfinished authentication job.
      await history.requireRestoredIntersection(successor);
      // An independently verified newer restore arriving after hydration keeps
      // this older projection pending, without mutating either proof history.
      await db.execute(
        'UPDATE crypto_restore_record_anchors SET revision=4 WHERE partition=?',
        [context.partition],
      );
      await expectLater(
        history.requireRestoredIntersection(successor),
        throwsA(isA<CryptoProjectionPending>()),
      );
    },
  );
}
