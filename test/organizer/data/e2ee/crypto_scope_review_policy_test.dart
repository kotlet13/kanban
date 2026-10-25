import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_policy.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_review_policy.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';

// Explicit accepted-projection seam. These tests verify the review's SQL and
// HMAC gate; they do not replace normal projector, signature or native evidence.
const server = '11111111-1111-4111-8111-111111111111';
const scope = '22222222-2222-4222-8222-222222222222';
const author = '33333333-3333-4333-8333-333333333333';
const actor = '44444444-4444-4444-8444-444444444444';
const canonicalId = '55555555-5555-4555-8555-555555555555';
const partition = 'verified-test-partition';
final key = Uint8List.fromList(List.generate(32, (i) => i));

Map<String, dynamic> record(
  String type,
  Map<String, dynamic> metadata, {
  int contract = 7,
  String domain = 'content',
}) => {
  'serverId': server,
  'scopeId': scope,
  'domain': domain,
  'id': cryptoWireRecordId(server, scope, type, canonicalId),
  'type': type,
  'accountId': actor,
  'expectedRevision': 2,
  'deleted': false,
  'previousRecordHash': 'b' * 64,
  'contentContract': contract,
  'metadata': {
    'identity': {
      'sourceKind': cryptoRecordSourceKind(type),
      'canonicalId': canonicalId,
    },
    ...metadata,
  },
};

void main() {
  late CollaborationDatabase db;
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    await db.rows('SELECT name FROM local_meta LIMIT 1');
  });
  tearDown(() => db.close());

  Future<void> seed(
    Map<String, dynamic> r,
    Map<String, dynamic> raw, {
    String? creator,
  }) => db.execute(
    'INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
    [
      partition,
      scope,
      r['domain'],
      r['id'],
      r['type'],
      3,
      'a' * 64,
      0,
      jsonEncode(raw),
      jsonEncode({
        'id': canonicalId,
        'type': r['type'],
        'revision': 3,
        'deleted': false,
        'createdByAccountId': creator,
      }),
      'verifiedCheckpoint',
    ],
  );
  Future<void> review(
    Map<String, dynamic> r, {
    String? proof,
    int revision = 3,
  }) => CryptoScopeReviewPolicy.requireVerifiedProjection(
    database: db,
    partition: partition,
    record: r,
    recordProofHash: proof ?? 'a' * 64,
    revision: revision,
  );
  Matcher pending() => throwsA(
    isA<CryptoAuthorityPending>().having(
      (e) => e.reason,
      'reason',
      'scope_review_policy_projection_pending',
    ),
  );

  test(
    'policy scope review requires exact accepted proof revision and immutable creator',
    () async {
      final raw = CryptoRecordPolicy.attachSecret({
        'title': 'Assigned task',
        'assigneeAccountIds': [actor],
      }, key);
      final policy = await CryptoRecordPolicy.prepare(
        serverId: server,
        scopeId: scope,
        domain: 'content',
        wireId: cryptoWireRecordId(server, scope, 'task', canonicalId),
        type: 'task',
        creator: author,
        operation: 'edit',
        payload: raw,
      );
      final r = record('task', {'recordPolicy': policy});
      expect(CryptoScopeReviewPolicy.allowsContentViewer(r), isTrue);
      await expectLater(review(r), pending());
      await seed(r, raw, creator: author);
      await review(r);
      await expectLater(review(r, proof: 'c' * 64), pending());
      await expectLater(review(r, revision: 4), pending());
      await db.execute('UPDATE crypto_business_records SET projection=?', [
        jsonEncode({
          'id': canonicalId,
          'type': 'task',
          'deleted': false,
          'createdByAccountId': actor,
        }),
      ]);
      await expectLater(review(r), pending());
    },
  );

  test(
    'policy scope review recomputes checked plaintext MAC before checkpoint',
    () async {
      final raw = CryptoRecordPolicy.attachSecret({
        'title': 'Milk',
        'isChecked': true,
      }, key);
      final policy = await CryptoRecordPolicy.prepare(
        serverId: server,
        scopeId: scope,
        domain: 'content',
        wireId: cryptoWireRecordId(server, scope, 'shoppingItem', canonicalId),
        type: 'shoppingItem',
        creator: author,
        operation: 'shoppingCheck',
        payload: raw,
      );
      final r = record('shoppingItem', {'recordPolicy': policy});
      await seed(r, raw, creator: author);
      await review(r);
      await db.execute('UPDATE crypto_business_records SET raw_payload=?', [
        jsonEncode({...raw, 'title': 'Forged title'}),
      ]);
      await expectLater(review(r), throwsFormatException);
    },
  );

  test(
    'policy scope review companion requires accepted projection while legacy and finance viewer roles stay unchanged',
    () async {
      final companion = {
        'version': 1,
        'taskId': cryptoWireRecordId(server, scope, 'task', canonicalId),
        'taskRevision': 3,
        'taskProofHash': 'd' * 64,
      };
      final r = record('taskDerivationIntent', {
        'recordPolicyCompanion': companion,
      }, contract: 6);
      expect(CryptoScopeReviewPolicy.allowsContentViewer(r), isTrue);
      await expectLater(review(r), pending());
      await seed(r, {'version': 1, 'taskId': canonicalId});
      await review(r);
      final legacy = record('task', {}, contract: 6);
      expect(CryptoScopeReviewPolicy.allowsContentViewer(legacy), isFalse);
      await review(
        legacy,
      ); // No blanket projection requirement for old history.
      expect(
        CryptoScopeReviewPolicy.allowsContentViewer(
          record(
            'financeEntry',
            {
              'recordPolicy': {'version': 1},
            },
            contract: 4,
            domain: 'finance',
          ),
        ),
        isFalse,
      );
      expect(
        CryptoScopeReviewPolicy.allowsContentViewer(
          record('scopeMetadata', {
            'recordPolicy': {'version': 1},
          }),
        ),
        isFalse,
      );
    },
  );
  test(
    'policy scope review resets only unsigned partial snapshot and preserves every prepared review',
    () async {
      const reviewId = '66666666-6666-4666-8666-666666666666';
      Future<void> partial(String id) => db.execute(
        'INSERT INTO crypto_scope_review_records(partition,scope_id,review_id,domain,record_id,wire,descriptor) VALUES(?,?,?,?,?,?,?)',
        [partition, scope, id, 'content', 'wire', '{}', Uint8List(0)],
      );
      Future<void> reset() =>
          CryptoScopeReviewPolicy.resetUnsignedPartialReview(
            database: db,
            partition: partition,
            scopeId: scope,
            reviewId: reviewId,
          );
      await partial(reviewId);
      await partial('other-review');
      await reset();
      expect(
        (await db.rows(
          'SELECT review_id FROM crypto_scope_review_records',
        )).single['review_id'],
        'other-review',
      );
      await partial(reviewId);
      Future<void> retained(
        String state,
        String id,
        Map<String, dynamic> payload,
      ) => db.execute(
        'INSERT INTO crypto_membership_intents(partition,scope_id,intent_id,state,payload) VALUES(?,?,?,?,?)',
        [
          partition,
          scope,
          id,
          state,
          Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        ],
      );
      for (final state in [
        'scopeRotationReview',
        'scopeRotationReviewComplete',
        'scopeRotationDraft',
        'scopeSuccessorDraft',
      ]) {
        await retained(
          state,
          state == 'scopeRotationDraft'
              ? 'draft'
              : state == 'scopeSuccessorDraft'
              ? '$reviewId:successor'
              : reviewId,
          {'reviewId': reviewId},
        );
        await expectLater(
          reset(),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'scope_review_confirmation_required',
            ),
          ),
        );
        expect(
          (await db.rows(
            'SELECT 1 FROM crypto_scope_review_records WHERE review_id=?',
            [reviewId],
          )).length,
          1,
        );
        await db.execute('DELETE FROM crypto_membership_intents');
      }
      await reset();
      expect(
        (await db.rows(
          'SELECT review_id FROM crypto_scope_review_records',
        )).single['review_id'],
        'other-review',
      );
    },
  );
}
