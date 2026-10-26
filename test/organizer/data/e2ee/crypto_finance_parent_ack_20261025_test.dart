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
import 'package:kanban/organizer/data/e2ee/crypto_business_finance.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_settlement.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_choice_selection_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scoped_exports.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:sodium/sodium.dart';

const _scope = '10000000-0000-4000-8000-000000000001';
const _parent = '10000000-0000-4000-8000-000000000002';
const _account = '20000000-0000-4000-8000-000000000001';
const _bank = '30000000-0000-4000-8000-000000000001';
const _manifest = '40000000-0000-4000-8000-000000000001';
const _expense = '50000000-0000-4000-8000-000000000001';
const _server = '60000000-0000-4000-8000-000000000001';
const _device = '70000000-0000-4000-8000-000000000001';
final _now = DateTime.utc(2026, 10, 25, 10, 54);

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Own implements VerifiedAccountDirectory {
  _Own(this.signing);
  final KeyPair signing;
  @override
  String get accountId => _account;
  @override
  String get serverId => _server;
  @override
  String get identityEpochId => _device;
  @override
  String get deviceSnapshotHash => '2' * 64;
  @override
  Map<String, dynamic> get snapshot => {
    'rootSigningKeyBase64': base64Encode(signing.publicKey),
    'rootEncryptionKeyBase64': base64Encode(signing.publicKey),
    'identityEpochId': identityEpochId,
    'recoveryRootEpochId': _account,
  };
  @override
  Map<String, dynamic> activeDevice(String id) => {
    'signingKeyBase64': base64Encode(signing.publicKey),
  };
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('Own ${i.memberName}');
}

class _Directory implements AccountDirectoryRepository {
  _Directory(this.own, this.store, CryptoCodec crypto)
    : reducer = AccountDirectoryV2(crypto);
  final _Own own;
  @override
  final CryptoIdentityStore store;
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
      username: 'synthetic',
      displayName: 'Synthetic',
      expiresAt: DateTime.utc(2030),
    ),
    'synthetic',
  );
  @override
  String get accountId => _account;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => own;
  @override
  Future<VerifiedAccountDirectory> cachedVerifiedDirectory() async => own;
  @override
  bool Function() get isCurrent =>
      () => true;
  Map<String, dynamic> certificate = {};
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (operation == 'crypto2.exports.certificates.get') {
      return {'authorization': certificate};
    }
    throw StateError('No network allowed: $operation');
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Directory ${i.memberName}');
}

class _Head implements VerifiedScopeHead {
  _Head(this.own, this.snapshotHash);
  final _Own own;
  final String snapshotHash;
  @override
  Map<String, dynamic> get body => {
    'scopeId': _scope,
    'previousHeadHash': cryptoZeroHash,
  };
  @override
  String get headHash => 'a' * 64;
  @override
  Map<String, dynamic> get authorization => {};
  @override
  bool get active => true;
  @override
  String get scopeId => _scope;
  @override
  int get epoch => 1;
  @override
  int get accessRevision => 1;
  @override
  List<Map<String, dynamic>> get members => [
    {
      ...own.snapshot,
      'accountId': _account,
      'role': 'owner',
      'financeRole': 'write',
      'manageKeys': true,
      'deviceSnapshotHash': snapshotHash,
      'directoryHeadHash': 'e' * 64,
    },
  ];
  @override
  Map<String, dynamic> member(String id) => members.single;
  @override
  String? commitment(String domain) => null;
  @override
  List<Map<String, dynamic>> get invitationPreauthorizations => [];
}

// Scope/directory authority is supplied after independent authentication. All
// record, offer, delegation and certificate signatures below are real; the
// production openHistoryChain implementation also runs without replacement.
class _Access extends SessionCryptoAccess {
  _Access({
    required super.account,
    required this.own,
    required this.key,
    required this.head,
  });
  final _Own own;
  final SecureKey key;
  final _Head head;
  bool coldAuthorDirectory = false, allowOnlineAuthorDirectory = true;
  int onlineDirectoryReads = 0;
  int readEpoch = 1, readAccessRevision = 1;
  String? readHeadHash;
  @override
  bool get canReadAuthorDirectoryOnline => allowOnlineAuthorDirectory;
  @override
  Future<CryptoReadContext> readContext(String scopeId, String domain) async =>
      CryptoReadContext(
        epoch: readEpoch,
        accessRevision: readAccessRevision,
        headHash: readHeadHash ?? head.headHash,
      );
  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async => head;
  @override
  Future<VerifiedScopeHead> headAt(
    String scopeId,
    String hash, {
    bool online = false,
  }) async => head;
  @override
  Future<Map<String, dynamic>> verifiedScopeDescriptor(
    String scopeId, {
    bool online = false,
  }) async => {
    'kind': 'project',
    'accessPolicyVersion': 3,
    'parentScopeToken': await CryptoLifecycleEvidence(
      this,
    ).parentToken(_scope, _parent),
  };
  @override
  Future<VerifiedAccountDirectory> directoryAt({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    bool online = false,
    bool allowUnverifiedContact = false,
  }) async {
    if (online) {
      onlineDirectoryReads++;
      coldAuthorDirectory = false;
    }
    if (coldAuthorDirectory) {
      throw const CryptoAuthorityPending('directory_proof_pending');
    }
    return own;
  }

  @override
  Future<VerifiedAccountDirectory> currentMemberDirectory(
    String scopeId,
    String scopeHeadHash,
    String accountId,
  ) async => own;
  @override
  Future<CryptoRecordAuthority> recordAuthority(
    Map<String, dynamic> record,
  ) async => CryptoRecordAuthority(
    signingKey: own.signing.publicKey,
    currentEpoch: true,
  );
  @override
  Future<CryptoKeyLease> recordKey(Map<String, dynamic> record) async =>
      CryptoKeyLease.borrowed(key);
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(
    super.account,
    super.access,
    super.db, {
    super.onlineAccountChoiceDirectories,
  });
  CryptoSyncRepository? delivery;
  @override
  CryptoSyncRepository get queue => delivery ?? super.queue;
  @override
  Future<String> reservedRecordId(String scope, String namespace) async =>
      _manifest;
}

Future<
  ({
    CollaborationDatabase db,
    _Runtime runtime,
    Map<String, dynamic> raw,
    Map<String, dynamic> expenseRecord,
    Map<String, dynamic> expenseProof,
    Map<String, dynamic> expenseWire,
    Map<String, dynamic> manifestWire,
    Uint8List plaintext,
  })
>
_fixture({
  required bool deviceSnapshotAdvanced,
  bool newerManifest = false,
  bool onlineDirectories = false,
}) async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final crypto = CryptoCodec(await SodiumInit.init());
  final signing = crypto.sodium.crypto.sign.keyPair();
  addTearDown(signing.secretKey.dispose);
  final key = crypto.sodium.secureRandom(32);
  addTearDown(key.dispose);
  final own = _Own(signing);
  final store = CryptoIdentityStore(
    db,
    _Secure(),
    '${Uri.encodeComponent('https://synthetic.invalid/')}:$_server:$_account',
  );
  final directory = _Directory(own, store, crypto);
  final account = AccountCryptoV2Workflow(directory);
  final access = _Access(
    account: account,
    own: own,
    key: key,
    head: _Head(
      own,
      deviceSnapshotAdvanced ? '1' * 64 : own.deviceSnapshotHash,
    ),
  );
  final runtime = _Runtime(
    account,
    access,
    db,
    onlineAccountChoiceDirectories: onlineDirectories,
  );
  await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
    runtime.partition,
    '{}',
  ]);
  await db.execute('INSERT INTO scopes(partition,id,data) VALUES(?,?,?)', [
    runtime.partition,
    _scope,
    jsonEncode(
      SharedScope(
        id: _scope,
        name: 'Synthetic project',
        kind: SharedScopeKind.project,
        role: SharedRole.owner,
        parentScopeId: _parent,
        organizationId: _parent,
      ).toJson(),
    ),
  ]);
  final choices = <Map<String, dynamic>>[
    {
      'accountId': _bank,
      'accountScopeId': _parent,
      'archived': false,
      'currency': 'EUR',
      'name': 'Synthetic parent account',
      'sourceRevision': 1,
    },
  ];
  final sourceRecords = [
    {
      'id': runtime.address(_parent, 'finance', 'financeAccount', _bank).wireId,
      'recordProofHash': 'b' * 64,
    },
  ];
  final context = <String, dynamic>{
    'version': 2,
    'variant': CryptoFinanceChoiceSelectionCodec.variant,
    'purpose': 'financeAccountChoice',
    'serverId': _server,
    'sourceScopeId': _parent,
    'sourceHeadHash': 'b' * 64,
    'sourceCheckpoint': {
      'proofHash': 'c' * 64,
      'sequence': 1,
      'manifestHash': 'd' * 64,
    },
    'targetScopeId': _scope,
    'targetHeadHash': 'a' * 64,
    'selectionCount': 1,
    'sourceRecordRoot': await cryptoSha256(
      utf8.encode('JivieFinanceAccountChoiceSource/v2\n') +
          CryptoJson.encode(sourceRecords),
    ),
  };
  final salt = base64Encode(Uint8List(32));
  final selectionHash = await CryptoFinanceChoiceSelectionCodec.selectionHash(
    context,
    choices,
    salt,
  );
  final offer = {
    ...context,
    'operation': 'crypto2.exports.offer',
    'selectionHash': selectionHash,
    'accountId': _account,
    'deviceId': _device,
    'authorDirectoryHeadHash': 'e' * 64,
    'deviceSnapshotHash': own.deviceSnapshotHash,
  };
  final offerProof = crypto.signDomain(
    offer,
    signing.secretKey,
    CryptoScopedExports.offerDomain,
  );
  final offerHash = await runtime.codec.digest(offerProof);
  final delegation = crypto.signDomain(
    {
      'version': 2,
      'operation': 'crypto2.exports.delegate',
      'requestId': crypto.randomId(),
      'serverId': _server,
      'accountId': _account,
      'deviceId': _device,
      'signer': 'device',
      'payload': {
        'variant': CryptoFinanceChoiceSelectionCodec.variant,
        'offerHash': offerHash,
        'scopeId': _scope,
        'membershipHeadHash': 'a' * 64,
        'expectedAccessRevision': 1,
        'authorDirectoryHeadHash': 'e' * 64,
        'delegationId': crypto.randomId(),
        'selectionHash': selectionHash,
        'issuerAccountId': _account,
        'issuerDirectoryHeadHash': 'e' * 64,
        'issuerRootSigningKeyBase64': own.snapshot['rootSigningKeyBase64'],
        'issuerRootEncryptionKeyBase64':
            own.snapshot['rootEncryptionKeyBase64'],
        'issuerIdentityEpochId': own.identityEpochId,
        'issuerDeviceSnapshotHash': own.deviceSnapshotHash,
        'bridgeRecipient': <String, dynamic>{},
      },
    },
    signing.secretKey,
    cryptoDirectoryDomain,
  );
  final certificate = crypto.signDomain(
    {
      ...offer,
      'operation': 'crypto2.exports.certificate',
      'offerHash': offerHash,
      'delegationHash': await runtime.codec.digest(delegation),
      'bridge': <String, dynamic>{},
    },
    signing.secretKey,
    CryptoScopedExports.certificateDomain,
  );
  directory.certificate = certificate;
  final manifestRaw = <String, dynamic>{
    'version': 2,
    'variant': CryptoFinanceChoiceSelectionCodec.variant,
    'selection': {
      'context': context,
      'choices': choices,
      'sourceRecords': sourceRecords,
      'selectionSaltBase64': salt,
    },
    'offerAuthorization': offerProof,
    'delegationAuthorization': delegation,
    'certificateAuthorization': certificate,
  };
  Future<
    ({
      Map<String, dynamic> body,
      Map<String, dynamic> wire,
      Map<String, dynamic> proof,
      Uint8List plaintext,
    })
  >
  seal(
    String id,
    String type,
    Map<String, dynamic> raw,
    Map<String, dynamic> metadata, {
    int expectedRevision = 0,
    String? previousHash,
  }) async {
    final plaintext = CryptoJson.encode({
      'format': 2,
      'identity': runtime.address(_scope, 'finance', type, id).identity,
      'payload': raw,
    });
    final batch = crypto.randomId();
    final proof = runtime.codec.sealRecord(
      serverId: _server,
      accountId: _account,
      deviceId: _device,
      batchId: batch,
      scopeId: _scope,
      id: runtime.address(_scope, 'finance', type, id).wireId,
      type: type,
      expectedRevision: expectedRevision,
      epoch: 1,
      accessRevision: 1,
      membershipHeadHash: 'a' * 64,
      domain: 'finance',
      contentContract: 3,
      operationId: crypto.randomId(),
      previousRecordHash: previousHash ?? '0' * 64,
      deleted: false,
      plaintext: plaintext,
      metadata: metadata,
      contentKey: key,
      signingKey: signing.secretKey,
    );
    final commitment = await runtime.codec.commitBatch(
      serverId: _server,
      accountId: _account,
      deviceId: _device,
      batchId: batch,
      records: [proof],
      projectionToken: (r) async => runtime.codec.projectionGroupToken(r, key),
      signingKey: signing.secretKey,
    );
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    final wire = {
      ...body,
      'revision': expectedRevision + 1,
      'sequence': expectedRevision + 1,
      'authorization': {'recordProof': proof, 'batchCommitment': commitment},
    };
    final verified = await runtime.codec.verifyWire(
      serverId: _server,
      wire: wire,
      trustedSigningKey: signing.publicKey,
      currentEpoch: true,
    );
    expect(runtime.codec.openVerified(verified, key), plaintext);
    return (body: verified, wire: wire, proof: proof, plaintext: plaintext);
  }

  final manifestAddress = runtime.address(
    _scope,
    'finance',
    'financeAccountChoice',
    _manifest,
  );
  final manifest = await seal(_manifest, 'financeAccountChoice', manifestRaw, {
    'identity': manifestAddress.identity,
    'references': <Object>[],
    'referenceVersions': <Object>[],
    'uniqueRefs': <String>[],
    'blobIds': <String>[],
  });
  addTearDown(
    () => manifest.plaintext.fillRange(0, manifest.plaintext.length, 0),
  );
  await runtime.addresses.install(manifestAddress);
  final manifestHash = await runtime.codec.digest(manifest.proof);
  await db.execute(
    'INSERT INTO crypto_business_records VALUES(?,?,?,?,?,1,0,?,0,?,?,?,?)',
    [
      runtime.partition,
      _scope,
      'finance',
      manifestAddress.wireId,
      'financeAccountChoice',
      manifestHash,
      jsonEncode(manifestRaw),
      jsonEncode({'id': _manifest}),
      'currentEpoch',
      'crypto',
    ],
  );
  await CryptoSyncStore(db, runtime.partition).receive(
    scopeId: _scope,
    domain: 'finance',
    wire: manifest.wire,
    verdict: 'verified',
    historyBasis: 'currentEpoch',
    batchKey: 'fixture',
  );
  final raw = <String, dynamic>{
    ...SharedFinanceEntry(
      id: _expense,
      accountId: _bank,
      kind: FinanceEntryKind.expense,
      status: SharedFinanceStatus.posted,
      amountMinor: 1234,
      currency: 'EUR',
      title: 'TEST-FINANCE-25 local',
      notes: '',
      category: '',
      occurredAt: _now,
      createdAt: _now,
      updatedAt: _now,
    ).toPayload(contractVersion: 3),
    'accountScopeId': _parent,
    'accountChoiceWitness': {
      'version': 2,
      'manifestId': _manifest,
      'revision': 1,
      'recordProofHash': manifestHash,
      'targetHeadHash': 'a' * 64,
      'selectionHash': selectionHash,
    },
  };
  // The production outgoing financial validator sees the current authorized
  // directory; it does not require head.member's older device snapshot hash.
  await CryptoBusinessFinance(
    runtime,
  ).outgoing(_scope, _expense, 'financeEntry', raw);
  final metadata = await runtime.businessMetadata(
    scopeId: _scope,
    domain: 'finance',
    type: 'financeEntry',
    canonicalId: _expense,
    expectedRevision: 0,
    rawPayload: raw,
  );
  final expense = await seal(_expense, 'financeEntry', raw, metadata);
  if (newerManifest) {
    final newer = await seal(
      _manifest,
      'financeAccountChoice',
      manifestRaw,
      Map<String, dynamic>.from(manifest.body['metadata'] as Map),
      expectedRevision: 1,
      previousHash: manifestHash,
    );
    addTearDown(() => newer.plaintext.fillRange(0, newer.plaintext.length, 0));
    await CryptoSyncStore(db, runtime.partition).receive(
      scopeId: _scope,
      domain: 'finance',
      wire: newer.wire,
      verdict: 'verified',
      historyBasis: 'currentEpoch',
      batchKey: 'newer-fixture',
    );
    await db.execute(
      'UPDATE crypto_business_records SET crypto_revision=2,record_proof_hash=? WHERE partition=? AND id=?',
      [
        await runtime.codec.digest(newer.proof),
        runtime.partition,
        manifestAddress.wireId,
      ],
    );
  }
  addTearDown(
    () => expense.plaintext.fillRange(0, expense.plaintext.length, 0),
  );
  return (
    db: db,
    runtime: runtime,
    raw: raw,
    expenseRecord: expense.body,
    expenseProof: expense.proof,
    expenseWire: expense.wire,
    manifestWire: manifest.wire,
    plaintext: expense.plaintext,
  );
}

class _PullTransport implements CollaborationTransport {
  _PullTransport(this.wire);
  final Map<String, dynamic> wire;
  final operations = <String>[];
  bool delivered = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    if (operation != 'crypto2.records.pull') {
      throw StateError('No mutation/network: $operation');
    }
    final send = !delivered;
    delivered = true;
    return {
      'cursor': 2,
      'scopeSequence': 2,
      'epoch': 1,
      'accessRevision': 1,
      'hasMore': false,
      'records': send
          ? [
              {...wire, 'sequence': 2},
            ]
          : <Object>[],
    };
  }

  @override
  void close() {}
}

void main() {
  // Signed record/offer/delegation/certificate and SQLite projection are real.
  // The cold proof/online read boundary is synthetic; no native speed claim.
  test(
    'startup cold root witness hydrates exact current directory before projection',
    () async {
      final f = await _fixture(
        deviceSnapshotAdvanced: false,
        onlineDirectories: true,
      );
      final access = f.runtime.access as _Access;
      access.coldAuthorDirectory = true;
      access.onlineDirectoryReads = 0;
      await f.runtime.project([
        CryptoProjectionRecord(
          f.expenseWire,
          f.expenseRecord,
          f.plaintext,
          historyBasis: 'currentEpoch',
          batchKey: 'startup-cold-witness',
        ),
      ]);
      final record = await f.runtime.record(
        _scope,
        'finance',
        _expense,
        type: 'financeEntry',
      );
      requireExactBusinessProjection(
        record: record,
        stagedRecord: f.expenseRecord,
        stagedProofHash: await f.runtime.codec.digest(f.expenseProof),
      );
      expect(jsonDecode(record!['raw_payload'] as String), f.raw);
      expect(access.onlineDirectoryReads, 2);
      expect(access.coldAuthorDirectory, isFalse);
    },
  );
  for (final guard in [
    'head',
    'access',
    'epoch',
    'frozen',
    'offline',
    'ancestor',
  ]) {
    test(
      'startup cold witness $guard boundary stays offline and pending',
      () async {
        final f = await _fixture(
          deviceSnapshotAdvanced: false,
          onlineDirectories: guard != 'offline',
          newerManifest: guard == 'ancestor',
        );
        final access = f.runtime.access as _Access;
        access.coldAuthorDirectory = true;
        access.onlineDirectoryReads = 0;
        switch (guard) {
          case 'head':
            access.readHeadHash = 'b' * 64;
          case 'access':
            access.readAccessRevision = 2;
          case 'epoch':
            access.readEpoch = 2;
          case 'frozen':
            access.allowOnlineAuthorDirectory = false;
        }
        await expectLater(
          CryptoFinanceAccountChoices(
            f.runtime,
          ).verifyFinancialRecord(_scope, f.raw, record: f.expenseRecord),
          throwsA(isA<CryptoAuthorityPending>()),
        );
        expect(access.onlineDirectoryReads, 0);
        expect(access.coldAuthorDirectory, isTrue);
        expect(
          await f.runtime.record(
            _scope,
            'finance',
            _expense,
            type: 'financeEntry',
          ),
          isNull,
        );
      },
    );
  }

  test(
    'signed parent-account expense projects and releases exact ACK with matching directory snapshot',
    () async {
      final f = await _fixture(deviceSnapshotAdvanced: false);
      await f.runtime.project([
        CryptoProjectionRecord(
          f.expenseWire,
          f.expenseRecord,
          f.plaintext,
          historyBasis: 'currentEpoch',
          batchKey: 'fixture-expense',
        ),
      ]);
      final record = await f.runtime.record(
        _scope,
        'finance',
        _expense,
        type: 'financeEntry',
      );
      requireExactBusinessProjection(
        record: record,
        stagedRecord: f.expenseRecord,
        stagedProofHash: await f.runtime.codec.digest(f.expenseProof),
      );
      expect(jsonDecode(record!['raw_payload'] as String), f.raw);
    },
  );

  test(
    'new guard: older signed manifest witness verifies authenticated predecessor chain',
    () async {
      final f = await _fixture(
        deviceSnapshotAdvanced: false,
        newerManifest: true,
      );
      await CryptoFinanceAccountChoices(
        f.runtime,
      ).verifyFinancialRecord(_scope, f.raw, record: f.expenseRecord);
      final history = await f.db.rows(
        'SELECT revision FROM crypto_business_history_proofs WHERE partition=? AND record_id=? ORDER BY revision',
        [f.runtime.partition, f.manifestWire['id']],
      );
      expect(history, [
        {'revision': 1},
        {'revision': 2},
      ]);
    },
  );
  test(
    'new guard: mismatched witness hash remains rejected before business effect',
    () async {
      final f = await _fixture(deviceSnapshotAdvanced: false);
      final raw = {
        ...f.raw,
        'accountChoiceWitness': {
          ...f.raw['accountChoiceWitness'] as Map,
          'recordProofHash': '0' * 64,
        },
      };
      final record = {
        ...f.expenseRecord,
        'metadata': {
          ...f.expenseRecord['metadata'] as Map,
          'referenceVersions': [
            for (final ref
                in f.expenseRecord['metadata']['referenceVersions'] as List)
              {...ref as Map, 'recordProofHash': '0' * 64},
          ],
        },
      };
      await expectLater(
        CryptoFinanceAccountChoices(
          f.runtime,
        ).verifyFinancialRecord(_scope, raw, record: record),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'exact hash guard',
            'crypto_account_choices_financial_witness',
          ),
        ),
      );
      expect(
        await f.runtime.record(
          _scope,
          'finance',
          _expense,
          type: 'financeEntry',
        ),
        isNull,
      );
    },
  );
  test(
    'new guard: retained original signed request settles after missing manifest arrives with no duplicate batch',
    () async {
      final f = await _fixture(deviceSnapshotAdvanced: false);
      final access = f.runtime.access as _Access;
      final transport = _PullTransport(f.expenseWire);
      f.runtime.delivery = CryptoSyncRepository(
        crypto: f.runtime.codec.crypto,
        session: f.runtime.account.directory.session,
        transport: transport,
        store: CryptoSyncStore(f.db, f.runtime.partition),
        signingKey: () async => throw StateError('No signing on replay'),
        authorKey: access.recordAuthority,
        contentKey: access.recordKey,
        project: f.runtime.project,
        readContext: access.readContext,
        isCurrent: () => true,
      );
      final signed = f.runtime.codec.crypto.signDomain(
        {
          'version': 2,
          'operation': 'crypto2.records.batch',
          'serverId': _server,
          'accountId': _account,
          'deviceId': _device,
          'requestId': _expense,
          'signer': 'device',
          'payload': {
            'records': [f.expenseProof],
            'commitment': f.expenseWire['authorization']['batchCommitment'],
          },
        },
        access.own.signing.secretKey,
        cryptoDirectoryDomain,
      );
      final signedBytes = jsonEncode(signed),
          signedHash = await f.runtime.codec.digest(signed);
      await f.db.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
        [
          f.runtime.partition,
          _expense,
          'crypto2.records.batch',
          signedBytes,
          signedHash,
          'applied',
        ],
      );
      await f.db.execute(
        'DELETE FROM crypto_received WHERE partition=? AND record_id=?',
        [f.runtime.partition, f.manifestWire['id']],
      );
      await expectLater(
        f.runtime.reconcileOriginalRecordRequest(_expense),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'exact retained terminal reason',
            'crypto_business_ack_projection_pending',
          ),
        ),
      );
      final pending = await f.db.rows(
        'SELECT verdict,error FROM crypto_received WHERE partition=? AND record_id=?',
        [f.runtime.partition, f.expenseWire['id']],
      );
      expect(pending, [
        {'verdict': 'received', 'error': 'crypto_projection_pending'},
      ]);
      expect(
        await CryptoBusinessSettlement.contains(
          database: f.db,
          partition: f.runtime.partition,
          requestId: _expense,
        ),
        isFalse,
      );
      await CryptoSyncStore(f.db, f.runtime.partition).receive(
        scopeId: _scope,
        domain: 'finance',
        wire: f.manifestWire,
        verdict: 'verified',
        historyBasis: 'currentEpoch',
        batchKey: 'fixture',
      );
      await f.runtime.reconcileOriginalRecordRequest(_expense);
      expect(
        await CryptoBusinessSettlement.contains(
          database: f.db,
          partition: f.runtime.partition,
          requestId: _expense,
        ),
        isTrue,
      );
      expect(
        await f.db.rows(
          'SELECT signed_body,request_hash,state FROM crypto_outbox',
        ),
        [
          {
            'signed_body': signedBytes,
            'request_hash': signedHash,
            'state': 'applied',
          },
        ],
      );
      expect(transport.operations, everyElement('crypto2.records.pull'));
      expect(
        await f.db.rows(
          "SELECT 1 FROM crypto_business_records WHERE type='financeEntry'",
        ),
        hasLength(1),
      );
    },
  );
}
