import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String partition) async => values[partition];
  @override
  Future<void> write(String partition, String value) async {
    values[partition] = value;
  }
}

class _NoNetwork implements CollaborationTransport {
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async =>
      throw StateError('Unexpected transport at authenticated-head seam');
  @override
  void close() {}
}

// Explicit authenticated-head boundary; real SQL, candidate-key commitment,
// signed/encrypted records and AEAD remain production. The real HTTP flow tests
// the actual head/directory chain; these controls target retained-page admission.
class _Head implements VerifiedScopeHead {
  _Head(this.scopeId, this.headHash, this.keyId, this.contentCommitment);
  @override
  final String scopeId, headHash;
  final String keyId, contentCommitment;
  @override
  Map<String, dynamic> get body => {
    'keyIds': {'content': keyId},
  };
  @override
  String? commitment(String domain) =>
      domain == 'content' ? contentCommitment : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access extends SessionCryptoAccess {
  _Access({required super.account, required this.head});
  final _Head head;
  int candidateCalls = 0, ancestorCalls = 0;
  bool warmed = false, missingAncestor = false, changedHead = false;
  Future<void> Function()? onCandidate;
  @override
  Future<VerifiedScopeHead> recoveryCandidateHead(String scopeId) async {
    expect(scopeId, head.scopeId);
    candidateCalls++;
    await onCandidate?.call();
    warmed = true;
    return changedHead
        ? _Head(head.scopeId, 'b' * 64, head.keyId, head.contentCommitment)
        : head;
  }

  @override
  VerifiedScopeHead verifiedCandidateAncestor(String hash) {
    ancestorCalls++;
    if (!warmed || missingAncestor || hash != head.headHash) {
      throw const CryptoAuthorityPending('scope_prefix_pending');
    }
    return head;
  }
}

class _Fixture {
  _Fixture(this.crypto);
  final CryptoCodec crypto;
  late final CollaborationDatabase db;
  late final AccountCryptoV2Workflow account;
  late final _Access access;
  late final ScopeCryptoManager manager;
  late final ScopeRotationReview review;
  late final SecureKey dek;
  late final KeyPair signer;
  late final String scope, keyId, recordId;
  bool current = true;
  static const partition = 'retained-scope-preview';
  static const headHash =
      'a'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  Future<void> open() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    await db.rows('SELECT name FROM local_meta LIMIT 1');
    final server = crypto.randomId(),
        actor = crypto.randomId(),
        device = crypto.randomId();
    scope = crypto.randomId();
    keyId = crypto.randomId();
    dek = crypto.sodium.secureRandom(32);
    signer = crypto.sodium.crypto.sign.keyPair();
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: server,
        accountId: actor,
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        deviceId: device,
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic-token',
    );
    account = AccountCryptoV2Workflow(
      AccountDirectoryRepository(
        reducer: AccountDirectoryV2(crypto),
        session: session,
        transport: _NoNetwork(),
        store: CryptoIdentityStore(db, _Secure(), partition),
        isCurrent: () => current,
      ),
    );
    final rawKey = dek.extractBytes();
    final commitment = await ScopeCryptoCodec(crypto).keyCommitment(rawKey);
    await db.execute(
      '''INSERT INTO crypto_scope_keys
      (partition,scope_id,domain,epoch,epoch_id,key_id,key_bytes,
       scope_head_hash,grant,recovery_wrapping_durable,write_ready)
       VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
      [
        partition,
        scope,
        'content',
        1,
        headHash,
        keyId,
        rawKey,
        headHash,
        CryptoJson.encode({'syntheticCandidate': true}),
        1,
        0,
      ],
    );
    rawKey.fillRange(0, rawKey.length, 0);
    access = _Access(
      account: account,
      head: _Head(scope, headHash, keyId, commitment),
    );
    manager = ScopeCryptoManager(access);
    review = ScopeRotationReview({
      'reviewId': crypto.randomId(),
      'scopeId': scope,
      'sourceHeadHash': headHash,
      'previousLifecycleHash': 'c' * 64,
      'historyBasis': 'reviewedRecoveryBaseline',
      'domains': {
        'content': {'sequence': 1, 'count': 1, 'manifestHash': 'd' * 64},
      },
    });
    await db.execute(
      'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
      [
        partition,
        scope,
        review.id,
        'scopeRotationReview',
        CryptoJson.encode(review.value),
      ],
    );
    final canonicalId = crypto.randomId(), batch = crypto.randomId();
    recordId = cryptoWireRecordId(server, scope, 'task', canonicalId);
    final codec = CryptoRecordProofCodec(crypto);
    final proof = codec.sealRecord(
      serverId: server,
      accountId: actor,
      deviceId: device,
      batchId: batch,
      scopeId: scope,
      id: recordId,
      type: 'task',
      expectedRevision: 0,
      epoch: 1,
      accessRevision: 1,
      membershipHeadHash: headHash,
      domain: 'content',
      contentContract: 6,
      operationId: crypto.randomId(),
      previousRecordHash: '0' * 64,
      deleted: false,
      plaintext: Uint8List.fromList(utf8.encode('retained synthetic task')),
      metadata: {
        'identity': {'sourceKind': 'records', 'canonicalId': canonicalId},
        'references': <dynamic>[],
        'uniqueRefs': <dynamic>[],
        'blobIds': <dynamic>[],
        'notificationState': {
          'version': 1,
          'kind': 'updated',
          'assigneeAccountIds': [],
          'groupTargetId': null,
        },
        'reminderState': {
          'version': 1,
          'dueAtEpoch': null,
          'closed': false,
          'scheduleRevision': crypto.randomId(),
        },
      },
      contentKey: dek,
      signingKey: signer.secretKey,
    );
    final body = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final wire = <String, dynamic>{
      ...Map<String, dynamic>.from(body),
      'revision': 1,
      'authorization': {
        'recordProof': proof,
        'batchCommitment': await codec.commitBatch(
          serverId: server,
          accountId: actor,
          deviceId: device,
          batchId: batch,
          records: [proof],
          signingKey: signer.secretKey,
          projectionToken: (record) async =>
              codec.projectionGroupToken(record, dek),
        ),
      },
    };
    await codec.verifyWire(
      serverId: server,
      wire: wire,
      trustedSigningKey: signer.publicKey,
      currentEpoch: true,
    );
    await db.execute(
      'INSERT INTO crypto_scope_review_records VALUES(?,?,?,?,?,?,?)',
      [
        partition,
        scope,
        review.id,
        'content',
        recordId,
        jsonEncode(wire),
        CryptoJson.encode({'fixture': true}),
      ],
    );
  }

  Future<String> retained() async => jsonEncode({
    for (final table in [
      'crypto_scope_keys',
      'crypto_membership_intents',
      'crypto_scope_review_records',
      'crypto_outbox',
      'crypto_identity_secrets',
    ])
      table: await db.rows('SELECT * FROM $table'),
  });

  Future<void> close() async {
    await db.close();
    dek.dispose();
    signer.secretKey.dispose();
  }
}

void main() {
  late CryptoCodec crypto;
  late _Fixture f;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  setUp(() async {
    f = _Fixture(crypto);
    await f.open();
  });
  tearDown(() => f.close());
  Matcher pending(String code) => throwsA(
    isA<CryptoAuthorityPending>().having(
      (error) => error.reason,
      'reason',
      code,
    ),
  );
  Matcher invalid(String code) => throwsA(
    isA<FormatException>().having((error) => error.message, 'message', code),
  );

  test(
    'cold retained review authenticates prefix and previews without approving history',
    () async {
      final before = await f.retained();
      final loaded = (await f.manager.pendingRotationReviews(f.scope)).single;
      expect(f.access.warmed, false);
      final rows = await f.manager.previewRotation(loaded);
      try {
        expect(rows, hasLength(1));
        expect(utf8.decode(rows.single.plaintext!), 'retained synthetic task');
        expect(f.access.candidateCalls, 1);
        expect(f.access.ancestorCalls, 1);
        expect(await f.retained(), before);
      } finally {
        for (final row in rows) {
          row.dispose();
        }
      }
    },
  );

  test('altered retained review is rejected before candidate fetch', () async {
    final altered = ScopeRotationReview({
      ...f.review.value,
      'historyBasis': 'verifiedCheckpoint',
    });
    await expectLater(
      f.manager.previewRotation(altered),
      invalid('scope_review_not_local'),
    );
    expect(f.access.candidateCalls, 0);
  });

  test('cancelled saved review cannot reopen plaintext', () async {
    await f.db.execute(
      "UPDATE crypto_membership_intents SET state='scopeRotationCancelled'",
    );
    await expectLater(
      f.manager.previewRotation(f.review),
      invalid('scope_review_not_local'),
    );
    expect(f.access.candidateCalls, 0);
  });

  test(
    'changed current head preserves saved review and requires new review',
    () async {
      f.access.changedHead = true;
      final before = await f.retained();
      await expectLater(
        f.manager.previewRotation(f.review),
        pending('scope_review_changed'),
      );
      expect(f.access.ancestorCalls, 0);
      expect(await f.retained(), before);
    },
  );

  test(
    'unverified historical ancestor remains blocked after candidate lookup',
    () async {
      f.access.missingAncestor = true;
      await expectLater(
        f.manager.previewRotation(f.review),
        pending('scope_prefix_pending'),
      );
    },
  );

  test(
    'tampered retained key still fails commitment and grants no write authority',
    () async {
      await f.db.execute('UPDATE crypto_scope_keys SET key_bytes=?', [
        Uint8List(32),
      ]);
      final before = await f.retained();
      await expectLater(
        f.manager.previewRotation(f.review),
        invalid('scope_key_commitment'),
      );
      expect(await f.retained(), before);
    },
  );

  test(
    'session changed during candidate verification cannot return preview',
    () async {
      f.access.onCandidate = () async {
        f.current = false;
      };
      await expectLater(
        f.manager.previewRotation(f.review),
        pending('crypto_stale_identity'),
      );
      expect(f.access.ancestorCalls, 0);
    },
  );

  test(
    'review replaced during candidate verification is not displayed',
    () async {
      f.access.onCandidate = () => f.db.execute(
        "UPDATE crypto_membership_intents SET state='scopeRotationReviewComplete'",
      );
      await expectLater(
        f.manager.previewRotation(f.review),
        invalid('scope_review_not_local'),
      );
      expect(f.access.ancestorCalls, 0);
    },
  );
}
