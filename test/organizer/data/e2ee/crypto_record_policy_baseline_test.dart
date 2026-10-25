import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_document_blob.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_blob_target.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_policy.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

// Explicit verified-authority seams isolate signed baseline and AEAD binding.
// No fixture pretends to prove membership history or a native/server workflow.
class _Head implements VerifiedScopeHead {
  _Head(this.scopeId, this.owner, this.device, this.headHash);
  final String owner, device;
  String role = 'owner';
  @override
  final String scopeId;
  @override
  final String headHash;
  @override
  int get epoch => 1;
  @override
  int get accessRevision => 1;
  @override
  List<Map<String, dynamic>> get members => [
    {
      'accountId': owner,
      'role': role,
      'financeRole': 'none',
      'directoryHeadHash': 'a' * 64,
    },
  ];
  @override
  Map<String, dynamic> get body => {
    'keyIds': {'content': 'content-key', 'finance': null},
  };
  @override
  Map<String, dynamic> member(String id) =>
      members.singleWhere((m) => m['accountId'] == id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VerifiedDirectory implements VerifiedAccountDirectory {
  _VerifiedDirectory(this.device, this.publicKey);
  final String device;
  final Uint8List publicKey;
  @override
  Map<String, dynamic> activeDevice(String id) {
    if (id != device) throw const FormatException('fixture_wrong_device');
    return {'signingKeyBase64': base64Encode(publicKey)};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transport implements CollaborationTransport {
  late Future<Map<String, dynamic>> Function(String, Map<String, Object?>)
  handler;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) => handler(operation, params);
  @override
  void close() {}
}

class _Directory implements AccountDirectoryRepository {
  _Directory(this.session, this.reducer, this.transport);
  @override
  final DeviceSession session;
  @override
  final AccountDirectoryV2 reducer;
  @override
  final CollaborationTransport transport;
  @override
  String get accountId => session.profile.accountId;
  @override
  bool Function() get isCurrent =>
      () => true;
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) => transport.call(
    serverUrl: session.profile.serverUrl,
    operation: operation,
    params: params,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements CryptoIdentityStore {
  _Store(this.database, this.partition);
  @override
  final CollaborationDatabase database;
  @override
  final String partition;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.directory);
  @override
  final AccountDirectoryRepository directory;
  CryptoIdentityStore? storeValue;
  @override
  CryptoIdentityStore get store => storeValue!;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access implements SessionCryptoAccess {
  _Access(this.head, this.directory, this.crypto, this.domainKey);
  final _Head head;
  final VerifiedAccountDirectory directory;
  final CryptoCodec crypto;
  final Uint8List domainKey;
  Future<CryptoHistoryChain> Function(Map<String, dynamic>)? restoreChain;
  @override
  Future<CryptoHistoryChain> openHistoryChain(
    Map<String, dynamic> anchorWire, {
    Map<String, dynamic>? reference,
    Map<String, dynamic>? referenceAnchorWire,
    Map<String, dynamic>? carrierAnchorWire,
  }) => restoreChain!(anchorWire);
  @override
  Future<CryptoKeyLease> recordKey(Map<String, dynamic> record) async =>
      CryptoKeyLease.owned(crypto.sodium.secureCopy(domainKey));
  @override
  Future<VerifiedScopeHead> currentHead(
    String scope, {
    bool online = false,
  }) async => head;
  @override
  Future<VerifiedScopeHead> headAt(
    String scope,
    String hash, {
    bool online = false,
  }) async {
    if (hash != head.headHash) throw const FormatException('fixture_head');
    // Historical baseline author was owner; current membership may differ.
    return _Head(head.scopeId, head.owner, head.device, head.headHash);
  }

  @override
  Future<bool> isRecordOwner(
    String scope,
    String account, {
    VerifiedScopeHead? head,
    String? parentScopeId,
    bool requireParentEvidence = false,
  }) async =>
      account == this.head.owner &&
      (head ?? this.head).member(account)['role'] == 'owner';
  @override
  Future<VerifiedAccountDirectory> directoryAt({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    bool online = false,
    bool allowUnverifiedContact = false,
  }) async => directory;
  @override
  Future<CryptoWriteContext> writeContext(
    String scope,
    String domain, {
    bool online = false,
    bool allowRecordPolicy = false,
  }) async {
    if (domain != 'content' || (head.role == 'viewer' && !allowRecordPolicy)) {
      throw const CryptoAuthorityPending('scope_write_forbidden');
    }
    return CryptoWriteContext(
      headHash: head.headHash,
      epoch: 1,
      accessRevision: 1,
      contentContract: 6,
      keyId: 'content-key',
      key: CryptoKeyLease.owned(crypto.sodium.secureCopy(domainKey)),
    );
  }

  @override
  Future<CryptoKeyLease> getScopeKey(
    String scope,
    String domain,
    int epoch,
  ) async => CryptoKeyLease.owned(crypto.sodium.secureCopy(domainKey));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Explicit historical-authority seam: signature/ciphertext validation remains real.
class _RestoreChain implements CryptoHistoryChain {
  _RestoreChain(this.codec, this.signingKey, this.nextRevision, this.nextHash);
  final CryptoRecordProofCodec codec;
  final Uint8List signingKey;
  @override
  int nextRevision;
  @override
  String nextHash;
  @override
  Future<CryptoRecordAuthority> authority(Map<String, dynamic> wire) async {
    final proof = Map<String, dynamic>.from(
      wire['authorization']['recordProof'] as Map,
    );
    final body = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    if (await codec.digest(proof) != nextHash ||
        wire['revision'] != nextRevision) {
      throw const FormatException('fixture_history_fork');
    }
    nextRevision = body['expectedRevision'];
    nextHash = body['previousRecordHash'];
    return CryptoRecordAuthority(signingKey: signingKey, currentEpoch: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Business implements CryptoBusinessSession {
  _Business(this.db, this.account, this.access, this.p);
  @override
  final CollaborationDatabase db;
  @override
  final AccountCryptoV2Workflow account;
  @override
  final SessionCryptoAccess access;
  @override
  final String p;
  CryptoSyncRepository? queueValue;
  @override
  CryptoSyncRepository get queue => queueValue!;
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {
    await db.execute(
      'INSERT INTO crypto_scope_state(partition,scope_id,domain,transport_cursor,projection_cursor,complete) VALUES(?,?,?,?,?,1) ON CONFLICT(partition,scope_id,domain) DO UPDATE SET complete=1',
      [p, scopeId, domain, 1, 1],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<
    ({
      CryptoRecordPolicyBaseline baseline,
      CollaborationDatabase db,
      String scope,
      String id,
      String canonicalId,
      CryptoBusinessSession realBusiness,
      _Head head,
      String proof,
      Uint8List key,
      Map<String, dynamic> raw,
      Map<String, dynamic> page,
      List<({String op, Map<String, Object?> params})> calls,
      Future<CryptoKeyLease> Function() signingKey,
    })
  >
  fixture({
    bool badContext = false,
    String type = 'shoppingList',
    bool blobTargets = true,
  }) async {
    final crypto = CryptoCodec(await SodiumInit.init()),
        codec = CryptoRecordProofCodec(CryptoCodec(await SodiumInit.init()));
    final pair = crypto.sodium.crypto.sign.keyPair();
    addTearDown(pair.secretKey.dispose);
    final server = crypto.randomId(),
        account = crypto.randomId(),
        device = crypto.randomId(),
        scope = crypto.randomId(),
        baselineId = crypto.randomId(),
        canonical = crypto.randomId();
    final id = CryptoRecordAddress.forType(
      serverId: server,
      scopeId: scope,
      type: type,
      canonicalId: canonical,
    ).wireId;
    final profile = AccountSession(
      serverUrl: 'https://example.test/',
      serverId: server,
      accountId: account,
      userId: 1,
      username: 'fixture',
      displayName: 'Fixture',
      deviceId: device,
      expiresAt: DateTime.utc(2030),
    );
    final transport = _Transport(),
        directory = _Directory(
          DeviceSession(profile, 'synthetic'),
          AccountDirectoryV2(crypto),
          transport,
        );
    final domainKey = crypto.sodium.randombytes.buf(32),
        key = crypto.sodium.randombytes.buf(32);
    addTearDown(() => domainKey.fillRange(0, domainKey.length, 0));
    addTearDown(() => key.fillRange(0, key.length, 0));
    final head = _Head(scope, account, device, 'b' * 64), proof = 'c' * 64;
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.rows('SELECT name FROM local_meta LIMIT 1');
    await db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_membership_intents(partition TEXT,scope_id TEXT,state TEXT,authorization BLOB)',
    );
    final context = {
      'version': 1,
      'purpose': badContext ? 'wrong-purpose' : 'recordPolicyBaseline',
      'serverId': server,
      'scopeId': scope,
      'domain': 'content',
      'id': id,
      'type': type,
      'recordProofHash': proof,
      'createdByAccountId': account,
      'membershipHeadHash': head.headHash,
      'accessRevision': 1,
    };
    final raw = <String, dynamic>{
      'title': 'Fixture',
      'createdAt': '2026-10-24T00:00:00Z',
      'updatedAt': '2026-10-24T00:00:00Z',
    };
    final policy = await CryptoRecordPolicy.prepare(
      serverId: server,
      scopeId: scope,
      domain: 'content',
      wireId: id,
      type: type,
      creator: account,
      operation: 'edit',
      payload: CryptoRecordPolicy.attachSecret(raw, key),
    );
    final secure = crypto.sodium.secureCopy(domainKey);
    late Map<String, dynamic> envelope;
    try {
      envelope = crypto.encrypt(
        plaintext: CryptoJson.encode({
          'version': 1,
          'keyBase64': base64Encode(key),
        }),
        key: secure,
        context: context,
      );
    } finally {
      secure.dispose();
    }
    final entry = <String, dynamic>{
      'id': id,
      'domain': 'content',
      'type': type,
      'recordProofHash': proof,
      'createdByAccountId': account,
      'fieldCommitments': policy['fieldCommitments'],
      'policyEnvelopeBase64': base64Encode(CryptoJson.encode(envelope)),
    };
    final common = <String, dynamic>{
      'scopeId': scope,
      'baselineId': baselineId,
      'membershipHeadHash': head.headHash,
      'accessRevision': 1,
    };
    Map<String, dynamic> signed(String op, Map<String, dynamic> payload) =>
        codec.signCommand({
          'version': 2,
          'operation': op,
          'requestId': crypto.randomId(),
          'serverId': server,
          'accountId': account,
          'deviceId': device,
          'signer': 'device',
          'payload': payload,
        }, pair.secretKey);
    final root = await CryptoRecordPolicyBaseline.root([entry]);
    final status = <String, dynamic>{
      'version': 1,
      'serverId': server,
      'accountId': account,
      'deviceId': device,
      ...common,
      'active': true,
      'activeBaselineId': baselineId,
      'policyVersion': 1,
      'baselineCount': 1,
      'baselineRoot': root,
      'expectedContentSequence': 1,
      'expectedFinanceSequence': 0,
    };
    final page = <String, dynamic>{
      ...status,
      'prepareAuthorization': signed('crypto2.scope.recordPolicy.prepare', {
        ...common,
        'policyVersion': 1,
        'expectedContentSequence': 1,
        'expectedFinanceSequence': 0,
      }),
      'activationAuthorization': signed('crypto2.scope.recordPolicy.activate', {
        ...common,
        'policyVersion': 1,
        'baselineCount': 1,
        'baselineRoot': root,
      }),
      'records': [
        {
          'entry': entry,
          'stageAuthorization': signed('crypto2.scope.recordPolicy.stage', {
            ...common,
            'records': [entry],
          }),
        },
      ],
      'hasMore': false,
      'nextAfterId': id,
    };
    final calls = <({String op, Map<String, Object?> params})>[];
    transport.handler = (op, params) async {
      calls.add((op: op, params: params));
      if (op == 'capabilities')
        return {
          'serverId': server,
          'recordPolicyVersions': [1],
          'recordPolicyBlobTargets': blobTargets,
          'recordPolicyRestores': true,
        };
      if (op.endsWith('.status')) return status;
      if (op.endsWith('.baseline')) return page;
      throw StateError(op);
    };
    final business = _Business(
      db,
      _Account(directory),
      _Access(
        head,
        _VerifiedDirectory(device, pair.publicKey),
        crypto,
        domainKey,
      ),
      profile.partition,
    );
    final realAccount = _Account(directory)
      ..storeValue = _Store(db, profile.partition);
    final realBusiness = CryptoBusinessSession(
      realAccount,
      business.access,
      db,
    );
    return (
      canonicalId: canonical,
      realBusiness: realBusiness,
      head: head,
      baseline: CryptoRecordPolicyBaseline(business),
      db: db,
      scope: scope,
      id: id,
      proof: proof,
      key: key,
      raw: raw,
      page: page,
      calls: calls,
      signingKey: () async => CryptoKeyLease.borrowed(pair.secretKey),
    );
  }

  Future<void> seedBlobRecord(dynamic f) async {
    await f.db.execute(
      'INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
      [
        f.realBusiness.partition,
        f.scope,
        'content',
        f.id,
        'table',
        1,
        f.proof,
        0,
        jsonEncode(f.raw),
        jsonEncode({
          'id': f.canonicalId,
          'createdByAccountId': f.head.owner,
          'creatorProvenance': 'verifiedCreation',
        }),
        'verifiedCheckpoint',
      ],
    );
  }

  test(
    'restore helper real signed nearest live history recovers stable key and explicit CAS',
    () async {
      final f = await fixture();
      final business = f.realBusiness,
          access = f.realBusiness.access as _Access;
      final codec = business.codec, directory = business.account.directory;
      final raw = CryptoRecordPolicy.attachSecret({
        ...f.raw,
        'futureBusiness': {'keep': 7},
      }, f.key);
      final policy = await CryptoRecordPolicy.prepare(
        serverId: directory.session.profile.serverId,
        scopeId: f.scope,
        domain: 'content',
        wireId: f.id,
        type: 'shoppingList',
        creator: f.head.owner,
        operation: 'create',
        payload: raw,
      );
      Future<Map<String, dynamic>> seal(
        bool deleted,
        int revision,
        String previous,
      ) async {
        final signing = await f.signingKey();
        final secure = await access.getScopeKey(f.scope, 'content', 1);
        try {
          final batch = directory.reducer.crypto.randomId();
          final proof = codec.sealRecord(
            serverId: directory.session.profile.serverId,
            accountId: f.head.owner,
            deviceId: f.head.device,
            batchId: batch,
            scopeId: f.scope,
            id: f.id,
            type: 'shoppingList',
            expectedRevision: revision,
            epoch: 1,
            accessRevision: 1,
            membershipHeadHash: f.head.headHash,
            domain: 'content',
            contentContract: 7,
            operationId: directory.reducer.crypto.randomId(),
            previousRecordHash: previous,
            deleted: deleted,
            plaintext: deleted
                ? null
                : CryptoBusinessJson.encode({
                    'format': 2,
                    'identity': business
                        .address(
                          f.scope,
                          'content',
                          'shoppingList',
                          f.canonicalId,
                        )
                        .identity,
                    'payload': raw,
                  }),
            metadata: {
              'identity': business
                  .address(f.scope, 'content', 'shoppingList', f.canonicalId)
                  .identity,
              'references': [],
              'uniqueRefs': [],
              'blobIds': [],
              'notificationState': {
                'version': 1,
                'kind': deleted ? 'deleted' : 'created',
                'assigneeAccountIds': [],
                'groupTargetId': null,
              },
              'recordPolicy': {
                ...policy,
                'operation': deleted ? 'delete' : 'create',
              },
            },
            contentKey: secure.key,
            signingKey: signing.key,
          );
          return {
            ...Map<String, dynamic>.from(
              CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
            ),
            'revision': revision + 1,
            'authorization': {
              'recordProof': proof,
              'batchCommitment': await codec.commitBatch(
                serverId: directory.session.profile.serverId,
                accountId: f.head.owner,
                deviceId: f.head.device,
                batchId: batch,
                records: [proof],
                signingKey: signing.key,
                projectionToken: (r) async =>
                    codec.projectionGroupToken(r, secure.key),
              ),
            },
          };
        } finally {
          secure.release();
          signing.release();
        }
      }

      final live = await seal(false, 0, '0' * 64);
      final liveHash = await codec.digest(
        Map<String, dynamic>.from(live['authorization']['recordProof'] as Map),
      );
      final tombstone = await seal(true, 1, liveHash);
      final tombHash = await codec.digest(
        Map<String, dynamic>.from(
          tombstone['authorization']['recordProof'] as Map,
        ),
      );
      for (final wire in [live, tombstone]) {
        await f.db.execute(
          'INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict,history_basis) VALUES(?,?,?,?,?,?,?,?,?)',
          [
            business.p,
            f.scope,
            'content',
            f.id,
            wire['revision'],
            wire['revision'],
            jsonEncode(wire),
            'verified',
            'currentEpoch',
          ],
        );
      }
      await f.db.execute(
        'INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          business.p,
          f.scope,
          'content',
          f.id,
          'shoppingList',
          2,
          tombHash,
          1,
          null,
          jsonEncode({
            'id': f.canonicalId,
            'revision': 2,
            'createdByAccountId': f.head.owner,
          }),
          'currentEpoch',
        ],
      );
      final public = (access.directory as _VerifiedDirectory).publicKey;
      access.restoreChain = (anchor) async {
        final body = await codec.verifyWire(
          serverId: directory.session.profile.serverId,
          wire: anchor,
          trustedSigningKey: public,
          currentEpoch: true,
        );
        return _RestoreChain(
          codec,
          public,
          body['expectedRevision'],
          body['previousRecordHash'],
        );
      };
      f.head.role = 'viewer';
      final prepared = await business.prepareExplicitRestore(
        scope: f.scope,
        domain: 'content',
        type: 'shoppingList',
        canonicalId: f.canonicalId,
        expectedRevision: 2,
      );
      expect(prepared['createdByAccountId'], f.head.owner);
      expect(prepared['recordRestore'], {
        'version': 1,
        'tombstoneProofHash': tombHash,
        'previousLiveProofHash': liveHash,
      });
      final before = await business.record(
        f.scope,
        'content',
        f.canonicalId,
        type: 'shoppingList',
      );
      final next = await business.prepareRecordPolicy(
        scope: f.scope,
        domain: 'content',
        type: 'shoppingList',
        canonicalId: f.canonicalId,
        expectedRevision: 2,
        raw: {...f.raw, 'title': 'Recovered draft'},
        before: before,
        restoreTag: Map<String, dynamic>.from(prepared['recordRestore'] as Map),
      );
      expect(next.policy!['operation'], 'restore');
      expect(CryptoRecordPolicy.secret(next.raw!), f.key);
      await expectLater(
        business.prepareRecordPolicy(
          scope: f.scope,
          domain: 'content',
          type: 'shoppingList',
          canonicalId: f.canonicalId,
          expectedRevision: 2,
          raw: f.raw,
          before: before,
          restoreTag: {
            ...prepared['recordRestore'] as Map,
            'previousLiveProofHash': 'd' * 64,
          },
        ),
        throwsFormatException,
      );
      expect(
        f.calls.where((c) => c.op.contains('push') || c.op.contains('blob.')),
        isEmpty,
      );
    },
  );

  test(
    'blob target client real viewer creator stages encrypted large table',
    () async {
      final f = await fixture(type: 'table');
      await seedBlobRecord(f);
      // Owner signed baseline evidence is verified first; the current membership
      // seam then represents the same creator with viewer content rights.
      expect(await f.realBusiness.recordPolicies.active(f.scope), isTrue);
      f.head.role = 'viewer';
      final plain = Uint8List.fromList(List.generate(100001, (i) => i % 251));
      final descriptor = await CryptoDocumentBlob(f.realBusiness).stage(
        scopeId: f.scope,
        recordId: f.canonicalId,
        operationId: 'large-table-new',
        kind: 'table',
        plaintext: plain,
      );
      final target = Map<String, dynamic>.from(
        descriptor['recordPolicyTarget'] as Map,
      );
      expect(target, {
        'type': 'table',
        'wireId': f.id,
        'currentRecordProofHash': f.proof,
      });
      CryptoRecordBlobTarget.validate(target);
      final chunks = await f.db.rows(
        'SELECT cipher FROM crypto_document_chunks WHERE partition=? AND id=? ORDER BY offset',
        [f.realBusiness.partition, descriptor['id']],
      );
      final cipher = Uint8List.fromList(
        chunks.expand((r) => r['cipher'] as Uint8List).toList(),
      );
      expect(cipher.length, greaterThan(90000));
      expect(cipher, isNot(equals(plain)));
      expect(await cryptoSha256(cipher), descriptor['cipherSha256']);
      expect(f.calls.where((c) => c.op.contains('blob.')), isEmpty);
      final jobs = await f.db.rows('SELECT state FROM crypto_document_jobs');
      expect(jobs.single['state'], 'staged');
    },
  );

  test(
    'blob target client rejects changed proof other record and future target authority',
    () async {
      final f = await fixture(type: 'table');
      await seedBlobRecord(f);
      final target = <String, dynamic>{
        'type': 'table',
        'wireId': f.id,
        'currentRecordProofHash': 'd' * 64,
      };
      await expectLater(
        f.realBusiness.authorizeBlobPolicyTarget(f.scope, target),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(
        () => CryptoRecordBlobTarget.requireRecordBinding(
          {...target, 'currentRecordProofHash': f.proof},
          {'id': 'other-record', 'type': 'table', 'domain': 'content'},
        ),
        throwsFormatException,
      );
      expect(
        () => CryptoRecordBlobTarget.validate({
          ...target,
          'futureAuthority': true,
        }),
        throwsFormatException,
      );
      expect(
        CryptoRecordBlobTarget.typeForKind('payload:financeEntry'),
        isNull,
      );
      expect(await f.db.rows('SELECT * FROM crypto_document_jobs'), isEmpty);
    },
  );

  test(
    'blob target client unsupported host preserves viewer work without staging',
    () async {
      final f = await fixture(type: 'table', blobTargets: false);
      await seedBlobRecord(f);
      expect(await f.realBusiness.recordPolicies.active(f.scope), isTrue);
      f.head.role = 'viewer';
      await expectLater(
        CryptoDocumentBlob(f.realBusiness).stage(
          scopeId: f.scope,
          recordId: f.canonicalId,
          operationId: 'unsupported-target-new',
          kind: 'table',
          plaintext: Uint8List(100001),
        ),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'crypto_record_policy_blob_target_upgrade_pending',
          ),
        ),
      );
      expect(await f.db.rows('SELECT * FROM crypto_document_jobs'), isEmpty);
      expect(await f.db.rows('SELECT * FROM crypto_document_chunks'), isEmpty);
    },
  );

  test(
    'signed baseline exact entry decrypts key and uses targeted request',
    () async {
      final f = await fixture();
      final value = await f.baseline.record(
        scopeId: f.scope,
        domain: 'content',
        id: f.id,
        recordProofHash: f.proof,
      );
      expect(value, isNotNull);
      try {
        expect(value!.key, f.key);
        expect(value.policy['createdByAccountId'], isNotNull);
      } finally {
        value?.key.fillRange(0, value.key.length, 0);
      }
      expect(f.calls.last.params['recordId'], f.id);
    },
  );
  test('signed baseline AEAD purpose substitution fails closed', () async {
    final f = await fixture(badContext: true);
    await expectLater(
      f.baseline.record(
        scopeId: f.scope,
        domain: 'content',
        id: f.id,
        recordProofHash: f.proof,
      ),
      throwsA(isA<FormatException>()),
    );
  });
  test(
    'verified baseline cannot supply secret for another proof revision',
    () async {
      final f = await fixture();
      await expectLater(
        f.baseline.record(
          scopeId: f.scope,
          domain: 'content',
          id: f.id,
          recordProofHash: 'd' * 64,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );
  test(
    'baseline evidence identity cannot be substituted by status metadata',
    () async {
      final f = await fixture();
      f.page['accountId'] = 'foreign';
      await expectLater(
        f.baseline.active(f.scope),
        throwsA(isA<FormatException>()),
      );
    },
  );
  test(
    'baseline old exact pending and namespace commands prevent activation',
    () async {
      final f = await fixture();
      final p = (f.baseline.business.p);
      expect(await f.baseline.hasPendingWork(f.scope), isFalse);
      await f.db.execute(
        'INSERT INTO accounts(partition,profile) VALUES(?,?)',
        [p, '{}'],
      );
      await f.db.execute(
        'INSERT INTO scopes(partition,id,data) VALUES(?,?,?)',
        [p, f.scope, '{}'],
      );
      await f.db.execute(
        'INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,?,?,?,?,?)',
        [p, f.scope, 'id', 'task', 1, 1, '{}', 0],
      );
      await f.db.execute(
        'INSERT INTO outbox(op_id,partition,scope_id,record_id,request,wire_version) VALUES(?,?,?,?,?,?)',
        ['op', p, f.scope, 'id', '{}', 6],
      );
      expect(await f.baseline.hasPendingWork(f.scope), isTrue);
      await f.db.execute('DELETE FROM outbox');
      final command = {
        'commandBase64': base64Encode(
          CryptoJson.encode({
            'payload': {'scopeId': f.scope},
          }),
        ),
      };
      await f.db.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
        [
          p,
          'command',
          'crypto2.scope.delete',
          jsonEncode(command),
          'hash',
          'pending',
        ],
      );
      expect(await f.baseline.hasPendingWork(f.scope), isTrue);
    },
  );
  test(
    'baseline pending finance intent is preserved while own baseline journal can resume',
    () async {
      final f = await fixture();
      final p = f.baseline.business.p;
      await f.db.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
        [
          p,
          'baseline',
          'crypto2.scope.recordPolicy.stage',
          '{}',
          'hash',
          'pending',
        ],
      );
      expect(await f.baseline.hasPendingWork(f.scope), isFalse);
      await f.db.execute(
        'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request,wire_version) VALUES(?,?,?,?,?,?)',
        ['finance', p, f.scope, 'id', '{}', 3],
      );
      expect(await f.baseline.hasPendingWork(f.scope), isTrue);
    },
  );
  test(
    'baseline root is independent of input order and rejects duplicate IDs',
    () async {
      final entries = <Map<String, dynamic>>[
        {'id': 'b', 'x': 2},
        {'id': 'a', 'x': 1},
      ];
      expect(
        await CryptoRecordPolicyBaseline.root(entries),
        await CryptoRecordPolicyBaseline.root(entries.reversed.toList()),
      );
      await expectLater(
        CryptoRecordPolicyBaseline.root([entries.first, entries.first]),
        throwsA(isA<FormatException>()),
      );
    },
  );
  Future<
    ({
      CryptoRecordPolicyBaseline baseline,
      _Business business,
      CollaborationDatabase db,
      String scope,
      List<String> mutations,
      Map<String, dynamic> Function() journalState,
    })
  >
  publisher({required bool loseStageAck, required bool rejectStage}) async {
    final f = await fixture();
    final business = f.baseline.business as _Business;
    final directory = business.account.directory as _Directory,
        crypto = directory.reducer.crypto;
    final access = business.access as _Access,
        profile = directory.session.profile;
    final transport = directory.transport as _Transport;
    final id = CryptoRecordAddress.forType(
      serverId: profile.serverId,
      scopeId: f.scope,
      type: 'scopeMetadata',
      canonicalId: crypto.randomId(),
    ).wireId;
    await f.db.execute(
      'INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
      [
        business.p,
        f.scope,
        'content',
        id,
        'scopeMetadata',
        1,
        f.proof,
        0,
        '{"name":"Fresh"}',
        '{}',
        'verifiedCheckpoint',
      ],
    );
    await f.db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
      'record_policy_new_scope_v1:${business.p}:${f.scope}',
      jsonEncode({
        'version': 1,
        'serverId': profile.serverId,
        'scopeId': f.scope,
        'accountId': profile.accountId,
        'deviceId': profile.deviceId,
        'originProofHash': 'e' * 64,
      }),
    ]);
    final receipts = <String, Map<String, dynamic>>{}, mutations = <String>[];
    String? baselineId;
    bool active = false, lost = false, rejected = false;
    Map<String, dynamic>? prepareProof, activateProof;
    final entries = <Map<String, dynamic>>[];
    Map<String, dynamic>? stageProof;
    int? count;
    String? root;
    Map<String, dynamic> metadata() => {
      'version': 1,
      'serverId': profile.serverId,
      'accountId': profile.accountId,
      'deviceId': profile.deviceId,
      'scopeId': f.scope,
      'active': active,
      'activeBaselineId': active ? baselineId : null,
      'baselineId': baselineId,
      'policyVersion': active ? 1 : 0,
      'membershipHeadHash': access.head.headHash,
      'accessRevision': 1,
      'expectedContentSequence': 1,
      'expectedFinanceSequence': 0,
      'baselineCount': count,
      'baselineRoot': root,
    };
    transport.handler = (op, params) async {
      if (op == 'capabilities')
        return {
          'serverId': profile.serverId,
          'recordPolicyVersions': [1],
        };
      if (op.endsWith('.status')) return metadata();
      if (op.endsWith('.baseline'))
        return {
          ...metadata(),
          'prepareAuthorization': prepareProof,
          'activationAuthorization': activateProof,
          'records': [
            for (final entry in entries)
              {'entry': entry, 'stageAuthorization': stageProof},
          ],
          'hasMore': false,
          'nextAfterId': entries.isEmpty ? null : entries.last['id'],
        };
      if (op == 'crypto2.receipt.get')
        return receipts[params['requestId']] ?? {'outcome': 'unknown'};
      final signed = Map<String, dynamic>.from(params);
      final command = crypto.verifyDomain(
        signed,
        (access.directory as _VerifiedDirectory).publicKey,
        cryptoDirectoryDomain,
      );
      final payload = command['payload'] as Map;
      final hash = await cryptoSha256(cryptoBase64(signed['commandBase64']));
      final request = command['requestId'] as String;
      mutations.add(op);
      Map<String, dynamic> response = {
        'version': 1,
        'scopeId': f.scope,
        'baselineId': payload['baselineId'],
      };
      var status = 200;
      if (op.endsWith('.prepare')) {
        baselineId = payload['baselineId'] as String;
        prepareProof = signed;
        entries.clear();
        response['prepared'] = true;
      } else if (op.endsWith('.stage')) {
        if (rejectStage && !rejected) {
          rejected = true;
          status = 409;
          response = {'errorCode': 'crypto_record_policy_baseline_changed'};
        } else {
          stageProof = signed;
          entries.addAll(
            (payload['records'] as List).map(
              (r) => Map<String, dynamic>.from(r as Map),
            ),
          );
          response['staged'] = entries.length;
        }
      } else if (op.endsWith('.activate')) {
        count = payload['baselineCount'] as int;
        root = payload['baselineRoot'] as String;
        if (count != entries.length ||
            root != await CryptoRecordPolicyBaseline.root(entries))
          throw const FormatException('fixture_baseline_root');
        active = true;
        activateProof = signed;
        response.addAll({
          'active': true,
          'policyVersion': 1,
          'baselineCount': count,
          'baselineRoot': root,
        });
      } else {
        throw StateError(op);
      }
      receipts[request] = {
        'requestId': request,
        'requestHash': hash,
        'authorization': signed,
        'status': status,
        'response': response,
      };
      if (op.endsWith('.stage') && loseStageAck && !lost) {
        lost = true;
        throw const CollaborationException('network');
      }
      if (status != 200)
        throw const CollaborationApiException(
          'crypto_record_policy_baseline_changed',
        );
      return response;
    };
    business.queueValue = CryptoSyncRepository(
      crypto: crypto,
      session: directory.session,
      transport: transport,
      store: CryptoSyncStore(f.db, business.p),
      signingKey: f.signingKey,
      authorKey: (_) async =>
          throw StateError('No business proofs in baseline fixture'),
      contentKey: (_) async =>
          throw StateError('No business proofs in baseline fixture'),
      project: (_) async {},
      beforeDelivery: (_) async {},
      isCurrent: () => true,
    );
    return (
      baseline: CryptoRecordPolicyBaseline(business),
      business: business,
      db: f.db,
      scope: f.scope,
      mutations: mutations,
      journalState: metadata,
    );
  }

  test(
    'new owner baseline lost stage ACK resumes exact journal receipt before activation',
    () async {
      final f = await publisher(loseStageAck: true, rejectStage: false);
      await expectLater(
        f.baseline.ensure(f.scope),
        throwsA(isA<CollaborationException>()),
      );
      final key = 'record_policy_baseline_v1:${f.business.p}:${f.scope}';
      final before = (await f.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      )).single['value'];
      final original = await f.db.rows(
        'SELECT request_id,signed_body FROM crypto_outbox ORDER BY sequence',
      );
      await CryptoRecordPolicyBaseline(f.business).ensure(f.scope);
      expect(f.journalState()['active'], isTrue);
      expect(f.mutations.where((op) => op.endsWith('.stage')), hasLength(1));
      expect(f.mutations.where((op) => op.endsWith('.prepare')), hasLength(1));
      expect(f.mutations.where((op) => op.endsWith('.activate')), hasLength(1));
      expect(
        (await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          key,
        ])).single['value'],
        before,
      );
      final after = await f.db.rows(
        'SELECT request_id,signed_body FROM crypto_outbox ORDER BY sequence',
      );
      expect(after.take(original.length).toList(), original);
    },
  );
  test(
    'new definitive changed-baseline rejection archives journal before fresh bounded retry',
    () async {
      final f = await publisher(loseStageAck: false, rejectStage: true);
      await expectLater(
        f.baseline.ensure(f.scope),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      final key = 'record_policy_baseline_v1:${f.business.p}:${f.scope}';
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name=?', [key]),
        isEmpty,
      );
      expect(
        await f.db.rows('SELECT name FROM local_meta WHERE name LIKE ?', [
          'record_policy_baseline_archive:${f.business.p}:${f.scope}:%',
        ]),
        hasLength(1),
      );
      final original = await f.db.rows(
        'SELECT request_id,signed_body FROM crypto_outbox ORDER BY sequence',
      );
      await CryptoRecordPolicyBaseline(f.business).ensure(f.scope);
      expect(f.journalState()['active'], isTrue);
      expect(f.mutations.where((op) => op.endsWith('.prepare')), hasLength(2));
      final after = await f.db.rows(
        'SELECT request_id,signed_body FROM crypto_outbox ORDER BY sequence',
      );
      expect(after.take(original.length).toList(), original);
    },
  );
}
