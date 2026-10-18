import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Transport implements CollaborationTransport {
  late Future<Map<String, dynamic>> Function(String, Map<String, Object?>)
  handler;
  final calls = <({String operation, Map<String, Object?> params})>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add((operation: operation, params: params));
    return handler(operation, params);
  }

  @override
  void close() {}
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    crypto = CryptoCodec(await SodiumInit.init());
  });
  late CollaborationDatabase db;
  late CryptoSyncStore store;
  late CryptoSyncRepository repo;
  late DeviceSession session;
  late _Transport transport;
  late KeyPair signing;
  late SecureKey content;
  late String scope;
  late CryptoRecordProofCodec codec;
  final canonicalByWire = <String, String>{};
  late List<List<int>?> observed;
  var failProjection = false, stale = false, currentEpoch = true;
  setUp(() {
    canonicalByWire.clear();
    db = CollaborationDatabase(NativeDatabase.memory());
    session = DeviceSession(
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
    scope = crypto.randomId();
    store = CryptoSyncStore(db, session.profile.partition);
    signing = crypto.sodium.crypto.sign.keyPair();
    content = crypto.sodium.secureRandom(32);
    codec = CryptoRecordProofCodec(crypto);
    transport = _Transport();
    observed = [];
    failProjection = false;
    stale = false;
    currentEpoch = true;
    repo = CryptoSyncRepository(
      crypto: crypto,
      session: session,
      transport: transport,
      store: store,
      signingKey: () async => CryptoKeyLease.borrowed(signing.secretKey),
      authorKey: (r) async => CryptoRecordAuthority(
        signingKey: signing.publicKey,
        currentEpoch: currentEpoch,
      ),
      contentKey: (r) async => CryptoKeyLease.borrowed(content),
      project: (values) async {
        for (final value in values) {
          await db.execute(
            'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
            [
              value.wire['id'],
              value.plaintext == null
                  ? 'deleted'
                  : utf8.decode(value.plaintext!),
            ],
          );
        }
        if (failProjection) throw const CryptoProjectionPending();
        observed.addAll(values.map((v) => v.plaintext?.toList()));
      },
      isCurrent: () => !stale,
      beforeDelivery: (_) async {},
      readContext: (scope, domain) async => const CryptoReadContext(
        epoch: 1,
        accessRevision: 2,
        headHash:
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      completenessProof:
          ({
            required scopeId,
            required domain,
            required accessRevision,
            required scopeSequence,
            required transportCursor,
          }) async => true,
    );
  });
  tearDown(() async {
    signing.secretKey.dispose();
    content.dispose();
    await db.close();
  });

  CryptoSyncRepository clone({
    CryptoProjection? project,
    CryptoAuthorKey? authority,
    Future<void> Function(Map<String, dynamic>)? beforeDelivery,
    Future<List<CryptoProjectionRecord>> Function(
      List<CryptoProjectionRecord>,
      Set<String>,
      CryptoProjectionHistoryBudget,
    )?
    siblings,
  }) => CryptoSyncRepository(
    crypto: crypto,
    session: session,
    transport: transport,
    store: CryptoSyncStore(db, store.partition),
    signingKey: repo.signingKey,
    authorKey: authority ?? repo.authorKey,
    contentKey: repo.contentKey,
    project: project ?? repo.project,
    resolveHistoricalSiblings: siblings,
    isCurrent: repo.isCurrent,
    completenessProof: repo.completenessProof,
    beforeDelivery: beforeDelivery ?? repo.beforeDelivery,
    readContext: repo.readContext,
  );

  Future<Map<String, dynamic>> wire({
    int revision = 1,
    int sequence = 1,
    bool corrupt = false,
    Map<String, dynamic>? metadata,
    String? id,
    String? previousRecordHash,
    String? operationId,
    String? batchId,
  }) async {
    final batch = batchId ?? crypto.randomId();
    final canonical = id == null
        ? crypto.randomId()
        : (canonicalByWire[id] ?? id);
    final address = CryptoRecordAddress.forType(
      serverId: session.profile.serverId,
      scopeId: scope,
      type: 'task',
      canonicalId: canonical,
    );
    canonicalByWire[address.wireId] = canonical;
    var proof = codec.sealRecord(
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
      deviceId: session.profile.deviceId,
      batchId: batch,
      scopeId: scope,
      id: address.wireId,
      type: 'task',
      expectedRevision: revision - 1,
      epoch: 1,
      accessRevision: 2,
      membershipHeadHash: 'a' * 64,
      domain: 'content',
      contentContract: 6,
      operationId: operationId ?? crypto.randomId(),
      previousRecordHash:
          previousRecordHash ?? (revision == 1 ? '0' * 64 : 'b' * 64),
      deleted: false,
      plaintext: Uint8List.fromList(
        utf8.encode('{"title":"unknown preserved","extra":{"amount":1.25}}'),
      ),
      metadata: {
        'identity': address.identity,
        'references': <Object>[],
        'uniqueRefs': <Object>[],
        'blobIds': <Object>[],
        'notificationState': {
          'version': 1,
          'kind': revision == 1 ? 'created' : 'updated',
          'assigneeAccountIds': <String>[],
          'groupTargetId': null,
        },
        'reminderState': {
          'version': 1,
          'dueAtEpoch': null,
          'closed': false,
          'scheduleRevision': session.profile.deviceId,
        },
        ...?metadata,
      },
      contentKey: content,
      signingKey: signing.secretKey,
    );
    if (corrupt) {
      final body =
          CryptoJson.decode(cryptoBase64(proof['commandBase64']))
              as Map<String, dynamic>;
      final envelope =
          CryptoJson.decode(cryptoBase64(body['envelopeBase64']))
              as Map<String, dynamic>;
      final bytes = cryptoBase64(envelope['ciphertextBase64']);
      bytes[0] ^= 1;
      envelope['ciphertextBase64'] = base64Encode(bytes);
      body['envelopeBase64'] = base64Encode(CryptoJson.encode(envelope));
      final raw = CryptoJson.encode(body);
      proof = {
        'commandBase64': base64Encode(raw),
        'signatureBase64': base64Encode(
          crypto.sodium.crypto.sign.detached(
            message: Uint8List.fromList([
              ...utf8.encode('JivieE2EE/record/v2\n'),
              ...raw,
            ]),
            secretKey: signing.secretKey,
          ),
        ),
      };
    }
    final commitment = await codec.commitBatch(
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
      deviceId: session.profile.deviceId,
      batchId: batch,
      records: [proof],
      projectionToken: (r) async => codec.projectionGroupToken(r, content),
      signingKey: signing.secretKey,
    );
    final body =
        CryptoJson.decode(cryptoBase64(proof['commandBase64']))
            as Map<String, dynamic>;
    return {
      ...body,
      'revision': revision,
      'sequence': sequence,
      'authorization': {'recordProof': proof, 'batchCommitment': commitment},
    };
  }

  Map<String, dynamic> page(
    List<Map<String, dynamic>> rows,
    int cursor, {
    int? sequence,
    bool more = false,
  }) => {
    'records': rows,
    'cursor': cursor,
    'scopeSequence': sequence ?? cursor,
    'epoch': 1,
    'accessRevision': 2,
    'hasMore': more,
  };

  test(
    'corrupt first wire cannot reserve revision against later actual signed proof',
    () async {
      final good = await wire(sequence: 2);
      final auth = Map<String, dynamic>.from(good['authorization'] as Map);
      final proof = Map<String, dynamic>.from(auth['recordProof'] as Map);
      final bad = <String, dynamic>{
        ...good,
        'sequence': 1,
        'authorization': {
          ...auth,
          'recordProof': {
            ...proof,
            'signatureBase64': base64Encode(List<int>.filled(64, 0)),
          },
        },
      };
      transport.handler = (op, p) async => page([bad], 1);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, isEmpty);
      transport.handler = (op, p) async => page([good], 2);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, hasLength(1));
      expect(
        (await db.rows('SELECT * FROM crypto_received')).single['verdict'],
        'verified',
      );
      expect(
        await db.rows('SELECT * FROM crypto_received_candidates'),
        hasLength(2),
      );
      expect(
        (await db.rows(
          "SELECT * FROM crypto_received_candidates WHERE verdict='quarantined'",
        )).single['wire'],
        contains(proof['commandBase64']),
      );
    },
  );
  test(
    'verified restored record floor holds older current response and quarantines same-revision substitution',
    () async {
      final old = await wire();
      final newer = await wire(id: old['id'] as String, revision: 2);
      final newerProof = Map<String, dynamic>.from(
        (newer['authorization'] as Map)['recordProof'] as Map,
      );
      await db.execute(
        'INSERT INTO crypto_restore_record_anchors VALUES(?,?,?,?,?,?,?)',
        [
          store.partition,
          scope,
          'content',
          newer['id'],
          2,
          await codec.digest(newerProof),
          jsonEncode(newer),
        ],
      );
      transport.handler = (_, _) async => page([old], 1);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, isEmpty);
      expect(
        (await db.rows('SELECT error FROM crypto_received')).single['error'],
        'crypto_restore_newer_record_pending',
      );
      final conflicting = await wire(
        id: old['id'] as String,
        revision: 2,
        sequence: 2,
      );
      transport.handler = (_, _) async => page([conflicting], 2);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, isEmpty);
      expect(
        (await db.rows(
          'SELECT error FROM crypto_received WHERE revision=2',
        )).single['error'],
        'crypto_restore_record_equivocation',
      );
      expect(
        (await db.rows(
          'SELECT revision,proof_hash FROM crypto_restore_record_anchors',
        )).single,
        {'revision': 2, 'proof_hash': await codec.digest(newerProof)},
      );
    },
  );
  test(
    'unsigned empty page epoch cannot advance a trusted crypto floor',
    () async {
      transport.handler = (op, p) async => {...page([], 0), 'epoch': 999};
      await expectLater(
        repo.pull(scopeId: scope, domain: 'content', accessRevision: 2),
        throwsFormatException,
      );
      expect(await store.scope(scope, 'content'), isNull);
      final good = await wire();
      transport.handler = (op, p) async => page([good], 1);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect((await store.scope(scope, 'content'))!['floor'], 1);
      expect(observed, hasLength(1));
    },
  );
  test(
    'real corrupted AEAD tag is durable quarantine; transport progresses and other valid record is handled',
    () async {
      final bad = await wire(corrupt: true), good = await wire(sequence: 2);
      transport.handler = (op, p) async => page([bad, good], 2);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      final rows = await db.rows(
        'SELECT verdict FROM crypto_received ORDER BY sequence',
      );
      expect(rows.map((r) => r['verdict']), ['quarantined', 'verified']);
      expect((await store.scope(scope, 'content'))!['transport_cursor'], 2);
      expect((await store.scope(scope, 'content'))!['projection_cursor'], 0);
      expect((await store.scope(scope, 'content'))!['complete'], 0);
      expect(
        observed.single,
        utf8.encode('{"title":"unknown preserved","extra":{"amount":1.25}}'),
      );
    },
  );
  test(
    'crash/pending aggregate cannot partially project; next process resumes durable received rows before cursor',
    () async {
      final value = await wire();
      failProjection = true;
      transport.handler = (op, p) async => page([value], 1);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(await db.rows('SELECT * FROM local_meta'), isEmpty);
      expect(
        (await db.rows(
          'SELECT verdict FROM crypto_received',
        )).single['verdict'],
        'received',
      );
      failProjection = false;
      transport.handler = (op, p) async => page([], 1);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(await db.rows('SELECT * FROM local_meta'), hasLength(1));
      expect((await store.scope(scope, 'content'))!['complete'], 1);
    },
  );
  test(
    'revoked old-epoch author cannot inject a new revision outside signed closure',
    () async {
      currentEpoch = false;
      final value = await wire(revision: 5);
      transport.handler = (op, p) async => page([value], 1);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, isEmpty);
      expect(
        (await db.rows(
          'SELECT verdict FROM crypto_received',
        )).single['verdict'],
        'quarantined',
      );
    },
  );
  test(
    'known tail/access/checkpoint rollback fails and retains original floor',
    () async {
      await store.checkpoint(
        scopeId: scope,
        domain: 'content',
        epoch: 1,
        accessRevision: 2,
        transportCursor: 0,
        projectionCursor: 0,
        scopeSequence: 100,
        complete: false,
      );
      transport.handler = (op, p) async => page([], 0, sequence: 50);
      await expectLater(
        repo.pull(scopeId: scope, domain: 'content', accessRevision: 2),
        throwsFormatException,
      );
      expect((await store.scope(scope, 'content'))!['scope_sequence'], 100);
    },
  );
  test(
    'later exact signed repair restores completeness and keeps bad original evidence',
    () async {
      final bad = await wire(corrupt: true);
      final oldProof = Map<String, dynamic>.from(
        (bad['authorization'] as Map)['recordProof'] as Map,
      );
      final hash = await codec.digest(oldProof);
      transport.handler = (op, p) async => page([bad], 1);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      final fixed = await wire(
        id: bad['id'] as String,
        revision: 2,
        sequence: 2,
        previousRecordHash: hash,
        metadata: {
          'references': <Object>[],
          'uniqueRefs': <Object>[],
          'blobIds': <Object>[],
          'repairOf': {'revision': 1, 'recordProofHash': hash},
        },
      );
      transport.handler = (op, p) async => page([fixed], 2);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      final rows = await db.rows(
        'SELECT * FROM crypto_received ORDER BY revision',
      );
      expect(rows.map((r) => r['verdict']), ['superseded', 'verified']);
      expect(jsonDecode(rows.first['wire'] as String), bad);
      expect((await store.scope(scope, 'content'))!['complete'], 1);
    },
  );

  Future<String> enqueue(Map<String, dynamic> value) async {
    final auth = value['authorization'] as Map;
    return repo.enqueueBatch(
      batchId: value['batchId'] as String,
      recordProofs: [Map<String, dynamic>.from(auth['recordProof'] as Map)],
      commitment: Map<String, dynamic>.from(auth['batchCommitment'] as Map),
      applyLocal: () async {},
    );
  }

  Map<String, dynamic> receipt(Map<String, Object?> row) {
    final signed = jsonDecode(row['signed_body'] as String) as Map;
    final command =
        CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
    final payload = command['payload'] as Map;
    final records = (payload['records'] as List)
        .map(
          (proof) =>
              CryptoJson.decode(cryptoBase64((proof as Map)['commandBase64']))
                  as Map,
        )
        .toList();
    return {
      'requestId': row['request_id'],
      'requestHash': row['request_hash'],
      'status': 200,
      'authorization': signed,
      'response': {
        'status': 'applied',
        'records': [
          for (final r in records)
            {
              'scopeId': r['scopeId'],
              'id': r['id'],
              'revision': (r['expectedRevision'] as int) + 1,
              'sequence': 1,
            },
        ],
      },
    };
  }

  test(
    'two repositories serialize pull and do not reproject terminal evidence',
    () async {
      final value = await wire();
      final other = clone();
      transport.handler = (op, p) async =>
          p['cursor'] == 0 ? page([value], 1) : page([], 1);
      await Future.wait([
        repo.pull(scopeId: scope, domain: 'content', accessRevision: 2),
        other.pull(scopeId: scope, domain: 'content', accessRevision: 2),
      ]);
      expect(observed, hasLength(1));
      expect(transport.calls.map((c) => c.params['cursor']), [0, 1]);
      await store.receive(
        scopeId: scope,
        domain: 'content',
        wire: value,
        verdict: 'received',
      );
      expect(
        (await db.rows(
          'SELECT verdict FROM crypto_received',
        )).single['verdict'],
        'verified',
      );
    },
  );
  test(
    'concurrent same revision enqueues cannot double apply the local effect',
    () async {
      final value = await wire(), other = clone();
      final auth = value['authorization'] as Map;
      var effects = 0;
      Future<Object> stage(CryptoSyncRepository target) async {
        try {
          return await target.enqueueBatch(
            batchId: value['batchId'] as String,
            recordProofs: [
              Map<String, dynamic>.from(auth['recordProof'] as Map),
            ],
            commitment: Map<String, dynamic>.from(
              auth['batchCommitment'] as Map,
            ),
            applyLocal: () async {
              effects++;
            },
          );
        } on FormatException catch (e) {
          return e;
        }
      }

      final results = await Future.wait([stage(repo), stage(other)]);
      expect(effects, 1);
      expect(
        results.whereType<FormatException>().single.message,
        'crypto_local_revision_claimed',
      );
      expect(await store.pending(), hasLength(1));
      expect(
        await db.rows('SELECT * FROM crypto_outbox_records'),
        hasLength(1),
      );
    },
  );
  test(
    'semantic bad batch rolls back alone while unrelated valid batch projects',
    () async {
      final bad = await wire(), good = await wire(sequence: 2);
      final target = clone(
        project: (values) async {
          for (final value in values) {
            await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
              value.wire['id'],
              'effect',
            ]);
          }
          if (values.any((v) => v.wire['id'] == bad['id']))
            throw const FormatException('finance_over_refund');
        },
      );
      transport.handler = (op, p) async => page([bad, good], 2);
      await target.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(
        (await db.rows('SELECT name FROM local_meta')).single['name'],
        good['id'],
      );
      expect(
        (await db.rows(
          'SELECT verdict FROM crypto_received ORDER BY sequence',
        )).map((r) => r['verdict']),
        ['quarantined', 'verified'],
      );
      expect((await store.scope(scope, 'content'))!['complete'], 0);
    },
  );

  test(
    'authenticated bad leg cannot partially project its compound batch',
    () async {
      final batch = crypto.randomId();
      final bad = await wire(corrupt: true, batchId: batch),
          good = await wire(sequence: 2, batchId: batch),
          independent = await wire(sequence: 3);
      final commitment = await codec.commitBatch(
        serverId: session.profile.serverId,
        accountId: session.profile.accountId,
        deviceId: session.profile.deviceId,
        batchId: batch,
        records: [
          Map<String, dynamic>.from(
            (bad['authorization'] as Map)['recordProof'] as Map,
          ),
          Map<String, dynamic>.from(
            (good['authorization'] as Map)['recordProof'] as Map,
          ),
        ],
        projectionToken: (r) async => codec.projectionGroupToken(r, content),
        signingKey: signing.secretKey,
      );
      for (final value in [bad, good]) {
        (value['authorization'] as Map)['batchCommitment'] = commitment;
      }
      transport.handler = (op, p) async => page([bad, good, independent], 3);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, hasLength(1));
      expect(
        (await db.rows(
          'SELECT verdict FROM crypto_received ORDER BY sequence',
        )).map((r) => r['verdict']),
        ['quarantined', 'quarantined', 'verified'],
      );
    },
  );
  test(
    'superseded atomic sibling is evidence only and cannot become received current',
    () async {
      final batchId = crypto.randomId();
      final first = await wire(batchId: batchId);
      final old = await wire(sequence: 2, batchId: batchId);
      final oldProof = Map<String, dynamic>.from(
        old['authorization']['recordProof'] as Map,
      );
      final oldHash = await codec.digest(oldProof);
      final newer = await wire(
        id: old['id'],
        revision: 2,
        sequence: 3,
        previousRecordHash: oldHash,
      );
      final commitment = await codec.commitBatch(
        serverId: session.profile.serverId,
        accountId: session.profile.accountId,
        deviceId: session.profile.deviceId,
        batchId: batchId,
        records: [
          Map<String, dynamic>.from(
            first['authorization']['recordProof'] as Map,
          ),
          oldProof,
        ],
        projectionToken: (r) async => codec.projectionGroupToken(r, content),
        signingKey: signing.secretKey,
      );
      for (final value in [first, old]) {
        value['authorization']['batchCommitment'] = commitment;
      }
      final effects = <String>[];
      final target = clone(
        siblings: (values, missing, budget) async {
          expect(missing, {oldHash});
          final body =
              CryptoJson.decode(cryptoBase64(oldProof['commandBase64']))
                  as Map<String, dynamic>;
          await codec.verifyWire(
            serverId: session.profile.serverId,
            wire: old,
            trustedSigningKey: signing.publicKey,
            currentEpoch: true,
          );
          return [
            CryptoProjectionRecord(
              old,
              body,
              codec.openVerified(body, content),
              historyBasis: 'currentEpoch',
              batchKey: await codec.digest(commitment),
              historicalOnly: true,
              historicalAnchorWire: newer,
            ),
          ];
        },
        project: (group) async {
          if (group.length == 2) {
            expect(
              group.where((v) => v.historicalOnly).single.wire['revision'],
              1,
            );
            expect(
              group.where((v) => v.historicalOnly).single.historicalAnchorWire,
              newer,
            );
          }
          effects.addAll(
            group
                .where((v) => !v.historicalOnly)
                .map((v) => v.wire['id'] as String),
          );
        },
      );
      transport.handler = (op, p) async => page([first, newer], 3);
      await target.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(effects, unorderedEquals([first['id'], newer['id']]));
      expect(
        await db.rows(
          'SELECT * FROM crypto_received WHERE record_id=? AND revision=1',
          [old['id']],
        ),
        isEmpty,
      );
      expect(
        (await db.rows(
          'SELECT verdict FROM crypto_received',
        )).every((r) => r['verdict'] == 'verified'),
        isTrue,
      );
    },
  );

  test(
    'invalid historical sibling cannot release effects and plaintext is zeroized',
    () async {
      final batchId = crypto.randomId();
      final first = await wire(batchId: batchId),
          old = await wire(sequence: 2, batchId: batchId);
      final commitment = await codec.commitBatch(
        serverId: session.profile.serverId,
        accountId: session.profile.accountId,
        deviceId: session.profile.deviceId,
        batchId: batchId,
        records: [
          for (final value in [first, old])
            Map<String, dynamic>.from(
              value['authorization']['recordProof'] as Map,
            ),
        ],
        projectionToken: (r) async => codec.projectionGroupToken(r, content),
        signingKey: signing.secretKey,
      );
      first['authorization']['batchCommitment'] = commitment;
      final bytes = Uint8List.fromList([1, 2, 3]);
      final target = clone(
        siblings: (values, missing, budget) async => [
          CryptoProjectionRecord(
            old,
            old,
            bytes,
            historyBasis: 'currentEpoch',
            batchKey: '0' * 64,
            historicalOnly: true,
            historicalAnchorWire: old,
          ),
        ],
      );
      transport.handler = (op, p) async => page([first], 2);
      await target.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, isEmpty);
      expect(bytes, [0, 0, 0]);
      expect(
        (await db.rows(
          'SELECT verdict FROM crypto_received',
        )).single['verdict'],
        'quarantined',
      );
    },
  );

  test(
    'one full cold page projects all independent groups with bounded allocations',
    () async {
      final rows = <Map<String, dynamic>>[];
      for (var i = 1; i <= 20; i++) {
        rows.add(await wire(sequence: i));
      }
      transport.handler = (op, p) async => page(rows, 20);
      await repo.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, hasLength(20));
      expect(
        await db.rows("SELECT * FROM crypto_received WHERE verdict='received'"),
        isEmpty,
      );
      expect(
        transport.calls.where((c) => c.operation == 'crypto2.records.pull'),
        hasLength(1),
      );
    },
  );
  test(
    'bounded fair pending traversal does not starve a later valid batch',
    () async {
      final rows = <Map<String, dynamic>>[];
      for (var i = 1; i <= 33; i++) {
        rows.add(await wire(sequence: i));
      }
      final pendingIds = rows.take(32).map((r) => r['id']).toSet();
      final target = clone(
        authority: (r) async {
          if (pendingIds.contains(r['id']))
            throw const CryptoAuthorityPending('synthetic_missing_peer');
          return CryptoRecordAuthority(
            signingKey: signing.publicKey,
            currentEpoch: true,
          );
        },
      );
      transport.handler = (op, p) async =>
          p['cursor'] == 0 ? page(rows, 33) : page([], 33);
      await target.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, isEmpty);
      await target.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(observed, hasLength(1));
      expect(
        (await db.rows(
          "SELECT * FROM crypto_received WHERE verdict='received'",
        )),
        hasLength(32),
      );
      expect((await store.scope(scope, 'content'))!['complete'], 0);
    },
  );
  test(
    'historical successful receipt is consumed before fresh rotated-head preflight',
    () async {
      final id = await enqueue(await wire());
      var freshnessCalls = 0;
      final target = clone(
        beforeDelivery: (_) async {
          freshnessCalls++;
          throw const CryptoAuthorityPending('scope_rotated');
        },
      );
      transport.handler = (op, p) async {
        expect(op, 'crypto2.receipt.get');
        return receipt((await store.outgoing(id))!);
      };
      await target.deliver();
      expect(freshnessCalls, 0);
      expect((await store.outgoing(id))!['state'], 'applied');
    },
  );
  test(
    'explicit definitive rejection rebase retains operation identity and never reapplies local effect',
    () async {
      final value = await wire();
      final oldId = await enqueue(value);
      final auth = value['authorization'] as Map;
      final next = await wire(
        id: value['id'] as String,
        operationId: value['operationId'] as String,
      );
      final nextAuth = next['authorization'] as Map;
      await expectLater(
        repo.rebaseRejectedBatch(
          rejectedRequestId: oldId,
          batchId: next['batchId'] as String,
          recordProofs: [
            Map<String, dynamic>.from(nextAuth['recordProof'] as Map),
          ],
          commitment: Map<String, dynamic>.from(
            nextAuth['batchCommitment'] as Map,
          ),
        ),
        throwsFormatException,
      );
      var sent = false;
      transport.handler = (op, p) async {
        if (op == 'crypto2.records.batch') {
          sent = true;
          return {};
        }
        if (!sent) return {'outcome': 'unknown'};
        return {
          ...receipt((await store.outgoing(oldId))!),
          'status': 409,
          'response': {'errorCode': 'crypto_scope_head_changed'},
        };
      };
      await repo.deliver();
      final replacement = await repo.rebaseRejectedBatch(
        rejectedRequestId: oldId,
        batchId: next['batchId'] as String,
        recordProofs: [
          Map<String, dynamic>.from(nextAuth['recordProof'] as Map),
        ],
        commitment: Map<String, dynamic>.from(
          nextAuth['batchCommitment'] as Map,
        ),
      );
      expect((await store.outgoing(oldId))!['state'], 'rejected');
      expect((await store.outgoing(replacement))!['state'], 'pending');
      expect(
        (await db.rows(
          'SELECT * FROM crypto_outbox_records',
        )).single['request_id'],
        replacement,
      );
      expect(
        (await db.rows(
          'SELECT * FROM crypto_outbox_reconciliations',
        )).single['old_request_id'],
        oldId,
      );
      expect((await db.rows('SELECT * FROM crypto_outbox')), hasLength(2));
      expect(auth['recordProof'], isNot(nextAuth['recordProof']));
    },
  );

  test(
    'explicit retry snapshots pending selection and leaves old requests untouched',
    () async {
      final old = await enqueue(await wire()),
          selected = await enqueue(await wire());
      final oldOriginal = await store.outgoing(old);
      final applied = <String>{}, checked = <String>[];
      var allowOld = false;
      final target = clone(
        beforeDelivery: (signed) async {
          final command =
              CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
          checked.add(command['requestId'] as String);
          if (command['requestId'] == old && !allowOld) {
            throw const FormatException('old_device_pending');
          }
        },
      );
      transport.handler = (operation, params) async {
        if (operation == 'crypto2.records.batch') {
          final command =
              CryptoJson.decode(cryptoBase64(params['commandBase64'])) as Map;
          applied.add(command['requestId'] as String);
          return {};
        }
        final id = params['requestId'] as String;
        return applied.contains(id)
            ? receipt((await store.outgoing(id))!)
            : {'outcome': 'unknown'};
      };
      final selection = <String>{selected};
      final retry = target.resumeUnresolved(requestIds: selection);
      selection.add(old); // Must not expand a retry already awaiting the queue.
      await retry;
      expect(checked, [selected]);
      expect((await store.outgoing(selected))!['state'], 'applied');
      expect(await store.outgoing(old), oldOriginal);
      expect(transport.calls.first.operation, 'crypto2.receipt.get');
      expect(
        transport.calls
            .where((c) => c.operation == 'crypto2.receipt.get')
            .every((c) => c.params['requestId'] == selected),
        isTrue,
      );
      final priorCalls = transport.calls.length;
      await target.resumeUnresolved(requestIds: <String>{});
      expect(transport.calls.length, priorCalls);
      expect(await store.outgoing(old), oldOriginal);
      // Normal deliver() remains all-pending and retains its identity guard.
      await expectLater(target.deliver(), throwsFormatException);
      expect(await store.outgoing(old), oldOriginal);
      allowOld = true;
      await target.resumeUnresolved(); // Omitted selection still means all.
      expect((await store.outgoing(old))!['state'], 'applied');
      expect(
        (await store.outgoing(old))!['signed_body'],
        oldOriginal!['signed_body'],
      );
      expect(
        (await store.outgoing(old))!['request_hash'],
        oldOriginal['request_hash'],
      );
    },
  );

  test(
    'authority pending row defers alone and explicit retry preserves original ciphertext and claim',
    () async {
      final blocked = await enqueue(await wire()),
          good = await enqueue(await wire());
      final original = (await store.outgoing(blocked))!['signed_body'];
      var recovered = false;
      final applied = <String>{};
      final target = clone(
        beforeDelivery: (signed) async {
          final c =
              CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
          if (c['requestId'] == blocked && !recovered)
            throw const CryptoAuthorityPending('scope_rotation_required');
        },
      );
      transport.handler = (op, p) async {
        if (op == 'crypto2.records.batch') {
          final c = CryptoJson.decode(cryptoBase64(p['commandBase64'])) as Map;
          applied.add(c['requestId'] as String);
          return {};
        }
        final id = p['requestId'] as String;
        return applied.contains(id)
            ? receipt((await store.outgoing(id))!)
            : {'outcome': 'unknown'};
      };
      await target.deliver();
      expect((await store.outgoing(blocked))!['state'], 'blocked');
      expect((await store.outgoing(good))!['state'], 'applied');
      recovered = true;
      final beforeRetry = transport.calls.length;
      await target.resumeUnresolved(requestIds: {blocked});
      expect(transport.calls[beforeRetry].operation, 'crypto2.receipt.get');
      expect((await store.outgoing(blocked))!['signed_body'], original);
      expect((await store.outgoing(blocked))!['state'], 'applied');
      expect(
        await db.rows(
          'SELECT * FROM crypto_outbox_attempts WHERE request_id=?',
          [blocked],
        ),
        hasLength(2),
      );
      final terminalCalls = transport.calls.length;
      await target.resumeUnresolved(requestIds: {blocked});
      expect(transport.calls.length, terminalCalls);
      await expectLater(store.retryBlocked(blocked), throwsFormatException);
    },
  );
  test(
    'whole authenticated 32-leg batch joins split pages beside permanently pending unrelated work',
    () async {
      final unrelated = await wire();
      final batchId = crypto.randomId();
      final legs = <Map<String, dynamic>>[];
      for (var i = 0; i < 32; i++) {
        legs.add(await wire(sequence: i + 2, batchId: batchId));
      }
      final commitment = await codec.commitBatch(
        serverId: session.profile.serverId,
        accountId: session.profile.accountId,
        deviceId: session.profile.deviceId,
        batchId: batchId,
        records: [
          for (final leg in legs)
            Map<String, dynamic>.from(
              (leg['authorization'] as Map)['recordProof'] as Map,
            ),
        ],
        projectionToken: (r) async => codec.projectionGroupToken(r, content),
        signingKey: signing.secretKey,
      );
      for (final leg in legs) {
        (leg['authorization'] as Map)['batchCommitment'] = commitment;
      }
      final groups = <int>[];
      final target = clone(
        project: (values) async {
          if (values.any((v) => v.wire['id'] == unrelated['id']))
            throw const CryptoProjectionPending();
          if (values.length != 32) throw const CryptoProjectionPending();
          groups.add(values.length);
        },
      );
      transport.handler = (op, p) async => p['cursor'] == 0
          ? page([unrelated, ...legs.take(15)], 16, sequence: 33, more: true)
          : page(legs.skip(15).toList(), 33);
      await target.pull(scopeId: scope, domain: 'content', accessRevision: 2);
      expect(groups, [32]);
      expect(
        (await db.rows(
          "SELECT * FROM crypto_received WHERE verdict='verified'",
        )),
        hasLength(32),
      );
      expect(
        (await db.rows(
          "SELECT * FROM crypto_received WHERE verdict='received'",
        )),
        hasLength(1),
      );
      expect((await store.scope(scope, 'content'))!['complete'], 0);
    },
  );
  test(
    'lost ACK retries exact persisted ciphertext without resealing or deleting evidence',
    () async {
      final id = await enqueue(await wire());
      var lost = true;
      transport.handler = (op, p) async {
        if (op == 'crypto2.records.batch' && lost) {
          lost = false;
          throw TimeoutException('synthetic lost response');
        }
        if (op == 'crypto2.receipt.get') {
          if (lost) return {'outcome': 'unknown'};
          return receipt((await store.outgoing(id))!);
        }
        return {'status': 'applied'};
      };
      await expectLater(repo.deliver(), throwsA(isA<TimeoutException>()));
      await repo.deliver();
      final attempts = transport.calls
          .where((c) => c.operation == 'crypto2.records.batch')
          .toList();
      expect(attempts, hasLength(1));
      expect(
        attempts.single.params,
        jsonDecode((await store.outgoing(id))!['signed_body'] as String),
      );
      expect((await store.outgoing(id))!['state'], 'applied');
      expect(await db.rows('SELECT * FROM crypto_outbox'), hasLength(1));
    },
  );
  test(
    'revoked receipt stays blocked/unresolved while independent queued work succeeds',
    () async {
      final blocked = await enqueue(await wire()),
          good = await enqueue(await wire());
      transport.handler = (op, p) async {
        final request = op == 'crypto2.receipt.get'
            ? p['requestId']
            : (CryptoJson.decode(cryptoBase64(p['commandBase64']))
                  as Map)['requestId'];
        if (request == blocked) {
          throw const CollaborationApiException('permission_revoked');
        }
        if (op == 'crypto2.receipt.get') {
          return receipt((await store.outgoing(good))!);
        }
        return {'status': 'applied'};
      };
      await repo.deliver();
      expect((await store.outgoing(blocked))!['state'], 'blocked');
      expect(
        (await store.outgoing(blocked))!['response'],
        contains('unresolved'),
      );
      expect((await store.outgoing(good))!['state'], 'applied');
      expect(await db.rows('SELECT * FROM crypto_outbox'), hasLength(2));
    },
  );
}
