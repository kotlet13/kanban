import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

const _scope = '11111111-1111-4111-a111-111111111111';
const _manifest = '22222222-2222-4222-a222-222222222222';
const _ownerOperation = '33333333-3333-4333-a333-333333333333';
const _newOperation = '44444444-4444-4444-a444-444444444444';
const _request = '55555555-5555-4555-a555-555555555555';
const _batch = '66666666-6666-4666-a666-666666666666';
const _server = '77777777-7777-4777-a777-777777777777';
const _account = '88888888-8888-4888-a888-888888888888';
const _device = '99999999-9999-4999-a999-999999999999';

class _Own implements VerifiedAccountDirectory {
  _Own(this.signing);
  final KeyPair signing;
  @override
  String get accountId => _account;
  @override
  String get serverId => _server;
  @override
  String get identityEpochId => _batch;
  @override
  String get deviceSnapshotHash => '1' * 64;
  @override
  Map<String, dynamic> activeDevice(String id) => {
    'signingKeyBase64': base64Encode(signing.publicKey),
  };
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected own-directory dependency');
}

class _Transport implements CollaborationTransport {
  late Map<String, dynamic> receipt;
  final sent = <Map<String, Object?>>[];
  final lookups = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.receipt.get') {
      lookups.add(params);
      return receipt;
    }
    if (operation == 'crypto2.records.batch') {
      sent.add(params);
      return {};
    }
    throw StateError('Unexpected RPC $operation');
  }

  @override
  void close() {}
}

class _Directory implements AccountDirectoryRepository {
  _Directory(this.own, this.transport, this.reducer);
  final _Own own;
  @override
  final _Transport transport;
  @override
  final AccountDirectoryV2 reducer;
  @override
  final session = DeviceSession(
    AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: _server,
      accountId: _account,
      deviceId: _device,
      userId: 1,
      username: 'fixture',
      displayName: 'Fixture',
      expiresAt: DateTime.utc(2030),
    ),
    'synthetic',
  );
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => own;
  @override
  Future<VerifiedAccountDirectory> cachedVerifiedDirectory() async => own;
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected directory dependency');
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.directory, this.encryption, this.crypto);
  @override
  final _Directory directory;
  final KeyPair encryption;
  final CryptoCodec crypto;
  @override
  String get deviceId => _device;
  @override
  Future<KeyPair> encryptionKey() async => KeyPair(
    publicKey: encryption.publicKey,
    secretKey: crypto.sodium.secureCopy(encryption.secretKey.extractBytes()),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected account dependency');
}

class _Access implements SessionCryptoAccess {
  _Access(this.signing, this.content);
  final KeyPair signing;
  final SecureKey content;
  final boundaries = <bool>[];
  Object? authorityFailure;
  @override
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) {
    boundaries.add(freshBoundary);
    return body();
  }

  @override
  Future<CryptoReadContext> readContext(String scope, String domain) async {
    if (authorityFailure != null) throw authorityFailure!;
    return CryptoReadContext(epoch: 1, accessRevision: 1, headHash: '1' * 64);
  }

  @override
  Future<CryptoRecordAuthority> recordAuthority(Map<String, dynamic> r) async =>
      CryptoRecordAuthority(signingKey: signing.publicKey, currentEpoch: true);
  @override
  Future<CryptoKeyLease> recordKey(Map<String, dynamic> r) async =>
      CryptoKeyLease.borrowed(content);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected access dependency');
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(super.account, super.access, super.db, this.records, this.delivery);
  final CryptoRecordProofCodec records;
  final CryptoSyncRepository delivery;
  late Map<String, Object?> initial, current;
  int pulls = 0, publications = 0;
  Object? pullFailure;
  @override
  String get p => account.directory.session.profile.partition;
  @override
  CryptoRecordProofCodec get codec => records;
  @override
  CryptoSyncRepository get queue => delivery;
  @override
  Future<String> reservedRecordId(String scope, String namespace) async =>
      _manifest;
  @override
  Future<Map<String, Object?>?> record(
    String scope,
    String domain,
    String id, {
    String? type,
  }) async => pulls == 0 ? initial : current;
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {
    pulls++;
    if (pullFailure != null) throw pullFailure!;
  }

  @override
  Future<Map<String, dynamic>> publishRaw({
    required String scopeId,
    String domain = 'content',
    required String id,
    required String type,
    required String operationId,
    required int expectedRevision,
    required Map<String, dynamic>? rawPayload,
    required String localHash,
    List<Map<String, dynamic>> tableLeases = const [],
  }) async {
    publications++;
    throw StateError('Existing publication path reached');
  }
}

/// The new incoming certificate and selection verifier are an orchestration
/// seam. Retained command signature/hash, current wire signature/commitment,
/// decryption, identity binding and SQL journals use the real implementations.
class _Choices extends CryptoFinanceAccountChoices {
  _Choices(super.context);
  Object? currentVerificationFailure;
  int verifications = 0;
  @override
  Future<List<Map<String, dynamic>>> verify(
    Map<String, dynamic> raw, {
    required String expectedScopeId,
  }) async {
    if (++verifications > 1 && currentVerificationFailure != null) {
      throw currentVerificationFailure!;
    }
    return [];
  }
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  late CollaborationDatabase db;
  late KeyPair signing, encryption;
  late SecureKey content;
  late _Transport transport;
  late _Runtime runtime;
  late _Access access;
  late _Choices choices;
  late CryptoRecordProofCodec records;
  late Map<String, dynamic> signed, offer, delegation, certificate;
  late Map<String, Object?> originalCurrent;
  late String partition, wireId;

  Map<String, dynamic> body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  Map<String, dynamic> unverifiedProof(Map<String, dynamic> value) => {
    'commandBase64': base64Encode(CryptoJson.encode(value)),
    'signatureBase64': base64Encode(Uint8List(64)),
  };
  Future<Map<String, dynamic>> seal(
    int expected,
    String operation, {
    String type = CryptoFinanceAccountChoices.type,
  }) async => records.sealRecord(
    serverId: _server,
    accountId: _account,
    deviceId: _device,
    batchId: _batch,
    scopeId: _scope,
    id: runtime.address(_scope, 'finance', type, _manifest).wireId,
    type: type,
    expectedRevision: expected,
    epoch: 1,
    accessRevision: 1,
    membershipHeadHash: '1' * 64,
    domain: 'finance',
    contentContract: 3,
    operationId: operation,
    previousRecordHash: (expected == 0 ? '0' : '3') * 64,
    deleted: false,
    plaintext: Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 2,
          'identity': runtime
              .address(_scope, 'finance', type, _manifest)
              .identity,
          'payload': {'selection': <Object>[]},
        }),
      ),
    ),
    metadata: {
      'identity': runtime.address(_scope, 'finance', type, _manifest).identity,
      'references': <Object>[],
      'uniqueRefs': <Object>[],
      'blobIds': <Object>[],
      'auditState': {'version': 1, 'changedAt': '2026-10-21T00:00:00Z'},
      if (type == 'financeAccount')
        'notificationState': {
          'version': 1,
          'kind': expected == 0 ? 'created' : 'updated',
          'assigneeAccountIds': <String>[],
          'groupTargetId': null,
        },
    },
    contentKey: content,
    signingKey: signing.secretKey,
  );
  Future<Map<String, dynamic>> commitment(Map<String, dynamic> proof) =>
      records.commitBatch(
        serverId: _server,
        accountId: _account,
        deviceId: _device,
        batchId: _batch,
        records: [proof],
        signingKey: signing.secretKey,
        projectionToken: (r) async => records.projectionGroupToken(r, content),
      );
  Future<void> saveOwner({
    int revision = 1,
    String type = CryptoFinanceAccountChoices.type,
  }) async {
    final proof = await seal(revision, _ownerOperation, type: type);
    signed = records.signCommand({
      'version': 2,
      'operation': 'crypto2.records.batch',
      'requestId': _request,
      'serverId': _server,
      'accountId': _account,
      'deviceId': _device,
      'signer': 'device',
      'payload': {
        'batchId': _batch,
        'records': [proof],
        'commitment': await commitment(proof),
      },
    }, signing.secretKey);
    final hash = await cryptoSha256(cryptoBase64(signed['commandBase64']));
    transport.receipt = {
      'requestId': _request,
      'requestHash': hash,
      'authorization': signed,
      'outcome': 'rejected',
      'status': 409,
      'response': {'errorCode': 'conflict'},
    };
    await db.execute(
      'UPDATE crypto_outbox SET signed_body=?,request_hash=?,response=? WHERE partition=? AND request_id=?',
      [
        jsonEncode(signed),
        hash,
        jsonEncode(transport.receipt),
        partition,
        _request,
      ],
    );
  }

  Future<Object> journals() async => [
    await db.rows('SELECT * FROM crypto_outbox'),
    await db.rows('SELECT * FROM crypto_outbox_records'),
    await db.rows('SELECT * FROM crypto_business_requests'),
    await db.rows('SELECT * FROM crypto_outbox_reconciliations'),
  ];
  Future<Map<String, dynamic>> materialize({
    String operation = _newOperation,
  }) => choices.materialize(
    _scope,
    offerAuthorization: offer,
    delegationAuthorization: delegation,
    certificateAuthorization: certificate,
    operationId: operation,
  );
  final pending = throwsA(
    isA<CryptoAuthorityPending>().having(
      (e) => e.reason,
      'reason',
      'crypto_business_delivery_pending',
    ),
  );

  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    signing = crypto.sodium.crypto.sign.keyPair();
    encryption = crypto.sodium.crypto.box.keyPair();
    content = crypto.sodium.secureRandom(32);
    records = CryptoRecordProofCodec(crypto);
    transport = _Transport();
    final directory = _Directory(
      _Own(signing),
      transport,
      AccountDirectoryV2(crypto),
    );
    final account = _Account(directory, encryption, crypto);
    access = _Access(signing, content);
    final store = CryptoSyncStore(db, directory.session.profile.partition);
    final delivery = CryptoSyncRepository(
      crypto: crypto,
      session: directory.session,
      transport: transport,
      store: store,
      signingKey: () async => CryptoKeyLease.borrowed(signing.secretKey),
      authorKey: access.recordAuthority,
      contentKey: access.recordKey,
      readContext: access.readContext,
      project: (_) async {},
      isCurrent: () => true,
      beforeDelivery: (_) async {},
    );
    runtime = _Runtime(account, access, db, records, delivery);
    choices = _Choices(runtime);
    partition = runtime.partition;
    wireId = runtime
        .address(_scope, 'finance', CryptoFinanceAccountChoices.type, _manifest)
        .wireId;
    runtime.initial = {'crypto_revision': 1};
    final currentProof = await seal(1, _newOperation);
    final currentBody = body(currentProof);
    final wire = {
      ...currentBody,
      'revision': 2,
      'authorization': {
        'recordProof': currentProof,
        'batchCommitment': await commitment(currentProof),
      },
    };
    originalCurrent = runtime.current = {
      'id': wireId,
      'crypto_revision': 2,
      'deleted': 0,
      'record_proof_hash': await records.digest(currentProof),
      'projection': jsonEncode({'verifiedCurrentChoice': true}),
    };
    await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
      partition,
      '{}',
    ]);
    await db.execute(
      'INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict) VALUES(?,?,?,?,?,?,?,?)',
      [
        partition,
        _scope,
        'finance',
        wireId,
        2,
        2,
        jsonEncode(wire),
        'verified',
      ],
    );
    await db.execute(
      'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
      [
        partition,
        _request,
        'crypto2.records.batch',
        '{}',
        '0' * 64,
        'rejected',
      ],
    );
    await db
        .execute('INSERT INTO crypto_business_requests VALUES(?,?,?,?,?,?,?)', [
          partition,
          _ownerOperation,
          _scope,
          'finance',
          'raw-local-hash',
          _request,
          _manifest,
        ]);
    await db.execute('INSERT INTO crypto_outbox_records VALUES(?,?,?,?,?,?)', [
      partition,
      _scope,
      'finance',
      wireId,
      1,
      _request,
    ]);
    await saveOwner();
    final recipient = {
      'accountId': _account,
      'deviceId': _device,
      'deviceSnapshotHash': directory.own.deviceSnapshotHash,
    };
    offer = unverifiedProof({'fixture': 'incoming-offer'});
    delegation = unverifiedProof({
      'payload': {'bridgeRecipient': recipient},
    });
    final envelope = {
      'context': {
        'variant': CryptoFinanceAccountChoices.variant,
        'offerHash': await cryptoSha256(CryptoJson.encode(offer)),
        'delegationHash': await cryptoSha256(CryptoJson.encode(delegation)),
        'selectionHash': '2' * 64,
        'requestId': _request,
        'recipient': recipient,
      },
      'selection': <String, dynamic>{},
    };
    certificate = unverifiedProof({
      'selectionHash': '2' * 64,
      'bridge': {
        'requestId': _request,
        'sealedDisclosureBase64': base64Encode(
          crypto.sodium.crypto.box.seal(
            message: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
            publicKey: encryption.publicKey,
          ),
        ),
      },
    });
  });
  tearDown(() async {
    signing.secretKey.dispose();
    encryption.secretKey.dispose();
    content.dispose();
    await db.close();
  });

  for (final state in ['rejected', 'applied', 'pending']) {
    test(
      'server-shaped terminal receipt without outcome continues $state owner',
      () async {
        transport.receipt.remove('outcome');
        if (state != 'rejected') {
          transport.receipt = {
            ...transport.receipt,
            'status': 200,
            'response': {
              'status': 'applied',
              'records': [
                {'scopeId': _scope, 'id': wireId, 'revision': 2, 'sequence': 2},
              ],
            },
          };
        }
        await db.execute('UPDATE crypto_outbox SET state=?,response=?', [
          state,
          state == 'pending' ? null : jsonEncode(transport.receipt),
        ]);
        final immutable = await db.rows(
          'SELECT request_id,signed_body,request_hash FROM crypto_outbox',
        );
        final claims = await db.rows('SELECT * FROM crypto_outbox_records');
        expect(await materialize(), {'verifiedCurrentChoice': true});
        expect(runtime.publications, 0);
        expect(transport.sent, isEmpty);
        expect(
          await db.rows(
            'SELECT request_id,signed_body,request_hash FROM crypto_outbox',
          ),
          immutable,
        );
        expect(await db.rows('SELECT * FROM crypto_outbox_records'), claims);
        expect(
          (await db.rows('SELECT state FROM crypto_outbox')).single['state'],
          state == 'rejected' ? 'rejected' : 'applied',
        );
      },
    );
  }
  test(
    'different certificate uses signed advanced current choice without a replacement request',
    () async {
      final before = jsonEncode(await journals());
      expect(await materialize(), {'verifiedCurrentChoice': true});
      expect(runtime.publications, 0);
      expect(runtime.pulls, 1);
      expect(access.boundaries, contains(true));
      expect(transport.sent, isEmpty);
      expect(jsonEncode(await journals()), before);
    },
  );
  test(
    'pending unknown owner replays only the original signed request and stays pending',
    () async {
      await db.execute(
        "UPDATE crypto_outbox SET state='pending',response=NULL",
      );
      transport.receipt = {'outcome': 'unknown'};
      final before = jsonEncode(await journals());
      await expectLater(materialize(), pending);
      expect(transport.sent, [signed]);
      expect(transport.lookups.every((v) => v['requestId'] == _request), true);
      expect(runtime.publications, 0);
      expect(runtime.pulls, 0);
      expect(jsonEncode(await journals()), before);
    },
  );
  for (final corruption in [
    'mapping',
    'signature',
    'hash',
    'type',
    'revision',
  ]) {
    test(
      'retained owner $corruption corruption fails closed before publication',
      () async {
        switch (corruption) {
          case 'mapping':
            await db.execute(
              "UPDATE crypto_business_requests SET record_id=?",
              [_newOperation],
            );
          case 'signature':
            await db.execute('UPDATE crypto_outbox SET signed_body=?', [
              jsonEncode({
                ...signed,
                'signatureBase64': base64Encode(Uint8List(64)),
              }),
            ]);
          case 'hash':
            await db.execute('UPDATE crypto_outbox SET request_hash=?', [
              '0' * 64,
            ]);
          case 'type':
            await saveOwner(type: 'financeAccount');
          case 'revision':
            await saveOwner(revision: 0);
        }
        final before = jsonEncode(await journals());
        await expectLater(materialize(), throwsFormatException);
        expect(runtime.publications, 0);
        expect(runtime.pulls, 0);
        expect(transport.sent, isEmpty);
        expect(jsonEncode(await journals()), before);
      },
    );
  }
  for (final mode in [
    'wrong-hash',
    'wrong-authorization',
    'unknown',
    'nonconflict',
  ]) {
    test('owner receipt $mode cannot satisfy continuation', () async {
      transport.receipt = switch (mode) {
        'wrong-hash' => {...transport.receipt, 'requestHash': '0' * 64},
        'wrong-authorization' => {...transport.receipt, 'authorization': {}},
        'unknown' => {'outcome': 'unknown'},
        _ => {
          ...transport.receipt,
          'status': 403,
          'response': {'errorCode': 'permission_revoked'},
        },
      };
      final before = jsonEncode(await journals());
      await expectLater(
        materialize(),
        mode.startsWith('wrong-') ? throwsFormatException : pending,
      );
      expect(runtime.publications, 0);
      expect(runtime.pulls, 0);
      expect(jsonEncode(await journals()), before);
    });
  }
  for (final mode in ['forbidden', 'stale', 'deleted', 'no-advance']) {
    test('current manifest $mode cannot satisfy terminal conflict', () async {
      if (mode == 'forbidden') {
        runtime.pullFailure = const CollaborationApiException(
          'finance_forbidden',
        );
      }
      if (mode == 'stale') {
        choices.currentVerificationFailure = const CryptoAuthorityPending(
          'crypto_account_choices_head_changed',
        );
      }
      if (mode == 'deleted') {
        runtime.current = {...originalCurrent, 'deleted': 1};
      }
      if (mode == 'no-advance') runtime.initial = {'crypto_revision': 2};
      if (mode == 'no-advance') {
        await db.execute(
          'UPDATE crypto_outbox_records SET expected_revision=2',
        );
        await saveOwner(revision: 2);
      }
      final before = jsonEncode(await journals());
      await expectLater(
        materialize(),
        mode == 'forbidden'
            ? throwsA(isA<CollaborationApiException>())
            : throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(runtime.publications, 0);
      expect(transport.sent, isEmpty);
      expect(jsonEncode(await journals()), before);
    });
  }
  test(
    'already staged current operation keeps the existing exact-intent path',
    () async {
      await expectLater(
        materialize(operation: _ownerOperation),
        throwsStateError,
      );
      expect(runtime.publications, 1);
      expect(runtime.pulls, 0);
      expect(transport.lookups, isEmpty);
    },
  );
}
