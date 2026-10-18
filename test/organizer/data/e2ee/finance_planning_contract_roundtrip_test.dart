import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_finance.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/shared_finance_validation.dart';
import 'package:sodium/sodium.dart';

import '../../support/synthetic_content_route_guard.dart';
import '../collaboration_repository_test.dart' show MemorySessionStore;

const _scope = '10000000-0000-4000-8000-000000000001';
const _account = '20000000-0000-4000-8000-000000000001';
const _bank = '30000000-0000-4000-8000-000000000001';
const _rule = '40000000-0000-4000-8000-000000000001';
final _now = DateTime.utc(2026, 10, 18, 10);

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => key.startsWith('directory2:')
      ? utf8.decode(
          CryptoJson.encode({
            'rootSigningKeyBase64': 'synthetic-root',
            'identityEpochId': 'synthetic-epoch',
          }),
        )
      : null;
  @override
  Future<void> write(String key, String value) async {}
}

class _NoNetwork implements CollaborationTransport {
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async => throw StateError('No network in synthetic planning fixture');
  @override
  void close() {}
}

class _Head implements VerifiedScopeHead {
  @override
  Map<String, dynamic> get body => {
    'scopeId': _scope,
    'keyIds': {'finance': 'synthetic-finance'},
    'previousHeadHash': cryptoZeroHash,
  };
  @override
  String get headHash => 'a' * 64;
  @override
  Map<String, dynamic> get authorization => const {};
  @override
  bool get active => true;
  @override
  String get scopeId => _scope;
  @override
  int get epoch => 1;
  @override
  int get accessRevision => 0;
  @override
  List<Map<String, dynamic>> get members => [
    {'accountId': _account, 'role': 'owner', 'financeRole': 'write'},
  ];
  @override
  Map<String, dynamic> member(String id) =>
      members.singleWhere((m) => m['accountId'] == id);
  @override
  String? commitment(String domain) => null;
}

// The authenticated scope/directory boundary is synthetic. Record encryption,
// signatures, reference versions, semantic validation and projection are real.
class _Access extends SessionCryptoAccess {
  _Access({required super.account, required this.financeKey});
  final SecureKey financeKey;
  @override
  Future<CryptoKeyLease> getScopeKey(
    String scopeId,
    String domain,
    int epoch,
  ) async => CryptoKeyLease.borrowed(financeKey);
  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async => _Head();
  @override
  Future<VerifiedScopeHead> headAt(
    String scopeId,
    String hash, {
    bool online = false,
  }) async {
    if (hash != 'a' * 64) throw const FormatException('synthetic_head');
    return _Head();
  }

  @override
  Future<Map<String, dynamic>> verifiedScopeDescriptor(
    String scopeId, {
    bool online = false,
  }) async => {'kind': 'household', 'accessPolicyVersion': 3};
  @override
  Future<CryptoReadContext> readContext(String scopeId, String domain) async =>
      CryptoReadContext(epoch: 1, accessRevision: 0, headHash: 'a' * 64);
}

DeviceSession _session() => DeviceSession(
  AccountSession(
    serverUrl: 'https://synthetic.invalid/',
    serverId: '50000000-0000-4000-8000-000000000001',
    accountId: _account,
    userId: 1,
    username: 'synthetic',
    displayName: 'Synthetic',
    deviceId: '60000000-0000-4000-8000-000000000001',
    expiresAt: DateTime.utc(2099),
  ),
  'synthetic',
);
AccountCryptoV2Workflow _workflow(
  CollaborationDatabase db,
  DeviceSession session,
  CryptoCodec crypto,
) => AccountCryptoV2Workflow(
  AccountDirectoryRepository(
    reducer: AccountDirectoryV2(crypto),
    session: session,
    transport: _NoNetwork(),
    store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
    isCurrent: () => true,
  ),
);

Future<
  ({
    CollaborationDatabase db,
    CollaborationRepository repo,
    DeviceSession session,
  })
>
_fixture(int version) async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  final session = _session();
  final caps = {
    'serverId': session.profile.serverId,
    'recordContractVersions': [1],
    'financeContractVersions': [1, if (version >= 2) 2, if (version == 3) 3],
    'organizationFinanceContractVersions': [1],
    'api': 'familyhub_native',
    'version': 1,
    'enabled': true,
    'features': {
      'recordSync': true,
      'finance': true,
      'organizationFinance': version == 3,
    },
  };
  await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
    'capabilities:${session.profile.partition}',
    jsonEncode(caps),
  ]);
  final repo = CollaborationRepository(
    db,
    _NoNetwork(),
    MemorySessionStore()..value = session,
    clock: () => _now,
    contentRouteGuard: const SyntheticContentRouteGuard(),
  );
  addTearDown(repo.close);
  await repo.initialize();
  final scope = SharedScope(
    id: _scope,
    kind: SharedScopeKind.household,
    name: 'Synthetic household',
    role: SharedRole.owner,
    sequence: 0,
  );
  final policy = SharedFinancePolicy(
    enabled: true,
    grant: SharedFinanceGrant.write,
    revision: 1,
    requiredContractVersion: version,
  );
  await db.execute(
    'INSERT INTO scopes(partition,id,data,finance_policy,finance_complete) VALUES(?,?,?,?,1)',
    [
      session.profile.partition,
      _scope,
      jsonEncode(scope.toJson()),
      jsonEncode(policy.toJson()),
    ],
  );
  final bank = SharedFinanceAccount(
    id: _bank,
    name: 'Synthetic bank',
    currency: 'EUR',
    openingBalanceMinor: 6789,
    createdAt: _now,
    updatedAt: _now,
  );
  await db.execute(
    "INSERT INTO finance_records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,'financeAccount',1,1,?,0)",
    [
      session.profile.partition,
      _scope,
      _bank,
      jsonEncode(bank.toPayload(contractVersion: version)),
    ],
  );
  await repo.refreshLocal();
  return (db: db, repo: repo, session: session);
}

FinanceRecurrenceRule _draft() => FinanceRecurrenceRule(
  id: _rule,
  title: 'Synthetic future monthly expense',
  kind: FinanceRecurrenceKind.expense,
  currency: 'EUR',
  ledgerAccountId: _bank,
  estimatedAmountMinor: 123,
  startYear: 2027,
  startMonth: 9,
  monthDay: 20,
  remindersEnabled: false,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _encryptedRoundtrip(
  CollaborationDatabase db,
  DeviceSession session,
  List<Map<String, Object?>> rows,
) async {
  final crypto = CryptoCodec(await SodiumInit.init());
  final key = crypto.sodium.secureRandom(32);
  addTearDown(key.dispose);
  final senderAccount = _workflow(db, session, crypto);
  final sender = CryptoBusinessSession(
    senderAccount,
    _Access(account: senderAccount, financeKey: key),
    db,
  );
  final readerDb = CollaborationDatabase(NativeDatabase.memory());
  addTearDown(readerDb.close);
  final readerAccount = _workflow(readerDb, session, crypto);
  final reader = CryptoBusinessSession(
    readerAccount,
    _Access(account: readerAccount, financeKey: key),
    readerDb,
  );
  final signing = crypto.sodium.crypto.sign.keyPair();
  addTearDown(signing.secretKey.dispose);
  var sequence = 0;
  for (final row in rows) {
    final id = row['id'] as String, type = row['type'] as String;
    final raw = Map<String, dynamic>.from(
      jsonDecode(row['payload'] as String) as Map,
    );
    final metadata = await sender.businessMetadata(
      scopeId: _scope,
      domain: 'finance',
      type: type,
      canonicalId: id,
      expectedRevision: 0,
      rawPayload: raw,
    );
    if (type == 'financeRecurrenceRule') {
      expect(
        metadata['references'],
        isEmpty,
        reason: 'preserve the existing signed rule wire shape',
      );
    }
    await CryptoBusinessFinance(sender).outgoing(_scope, id, type, raw);
    final batch = crypto.randomId(),
        address = sender.address(_scope, 'finance', type, id);
    final plaintext = CryptoJson.encode({
      'format': 2,
      'identity': address.identity,
      'payload': raw,
    });
    final proof = sender.codec.sealRecord(
      serverId: session.profile.serverId,
      accountId: _account,
      deviceId: session.profile.deviceId,
      batchId: batch,
      scopeId: _scope,
      id: address.wireId,
      type: type,
      expectedRevision: 0,
      epoch: 1,
      accessRevision: 0,
      membershipHeadHash: 'a' * 64,
      domain: 'finance',
      contentContract: 3,
      operationId: crypto.randomId(),
      previousRecordHash: '0' * 64,
      deleted: false,
      plaintext: plaintext,
      metadata: metadata,
      contentKey: key,
      signingKey: signing.secretKey,
    );
    final commitment = await sender.codec.commitBatch(
      serverId: session.profile.serverId,
      accountId: _account,
      deviceId: session.profile.deviceId,
      batchId: batch,
      records: [proof],
      projectionToken: (r) async => sender.codec.projectionGroupToken(r, key),
      signingKey: signing.secretKey,
    );
    final body =
        CryptoJson.decode(cryptoBase64(proof['commandBase64']))
            as Map<String, dynamic>;
    final wire = {
      ...body,
      'revision': 1,
      'sequence': ++sequence,
      'authorization': {'recordProof': proof, 'batchCommitment': commitment},
    };
    final verified = await sender.codec.verifyWire(
      serverId: session.profile.serverId,
      wire: wire,
      trustedSigningKey: signing.publicKey,
      currentEpoch: true,
    );
    final opened = sender.codec.openVerified(verified, key)!;
    expect((CryptoJson.decode(opened) as Map)['payload'], raw);
    final candidate = CryptoProjectionRecord(
      wire,
      verified,
      opened,
      historyBasis: 'currentEpoch',
      batchKey: await sender.codec.digest(commitment),
    );
    await sender.project([candidate]);
    await reader.project([candidate]);
    final restored = (await reader.record(_scope, 'finance', id, type: type))!;
    final canonical = jsonDecode(restored['projection'] as String) as Map;
    expect(canonical['payload'], raw);
    validateSharedFinancePayload(
      SharedFinanceRecordType.values.byName(type),
      Map<String, dynamic>.from(canonical['payload'] as Map),
      contractVersion: 3,
    );
    if (type == 'financeEntry') {
      expect((verified['metadata'] as Map)['referenceVersions'], hasLength(2));
      expect(
        await CryptoBusinessFinance(reader).uniqueRefs(_scope, type, raw),
        hasLength(1),
      );
    }
    opened.fillRange(0, opened.length, 0);
    plaintext.fillRange(0, plaintext.length, 0);
  }
  final rules = await readerDb.rows(
    "SELECT projection FROM crypto_business_records WHERE type='financeRecurrenceRule'",
  );
  final entries = await readerDb.rows(
    "SELECT projection FROM crypto_business_records WHERE type='financeEntry'",
  );
  expect(rules, hasLength(1));
  expect(entries, hasLength(1));
  final payload = Map<String, dynamic>.from(
    (jsonDecode(entries.single['projection'] as String) as Map)['payload']
        as Map,
  );
  expect(payload['status'], 'planned');
  expect(payload['amountMinor'], 123);
  expect(payload['recurrenceRuleId'], _rule);
  expect(payload['occurrenceKey'], '2027-09');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final version in [2, 3]) {
    test(
      'contract$version saves one future rule, materializes once and encrypted-roundtrips unchanged wire shape',
      () async {
        final f = await _fixture(version);
        expect(f.repo.state.financeContractVersion, version);
        await f.repo.saveFinancePlanForScope(
          scopeId: _scope,
          accounts: [],
          rules: [_draft()],
        );
        expect(
          f.repo.state.dataForScope(_scope).financeRecurrenceRules,
          hasLength(1),
        );
        expect(f.repo.state.dataForScope(_scope).financeEntries, hasLength(1));
        await f.repo.materializeFinanceOccurrencesForScope(_scope);
        expect(f.repo.state.dataForScope(_scope).financeEntries, hasLength(1));
        expect(await f.db.rows('SELECT wire_version FROM finance_outbox'), [
          {'wire_version': version},
          {'wire_version': version},
        ]);
        final rows = await f.db.rows(
          "SELECT id,type,payload FROM finance_records ORDER BY CASE type WHEN 'financeAccount' THEN 0 WHEN 'financeRecurrenceRule' THEN 1 ELSE 2 END",
        );
        final data = f.repo.state.dataForScope(_scope);
        expect(
          summarizeSharedFinance(
            accounts: data.financeAccounts,
            entries: data.financeEntries,
            transfers: [],
          )['EUR']!.balanceMinor,
          BigInt.from(6789),
        );
        await _encryptedRoundtrip(f.db, f.session, rows);
      },
    );
  }
  test(
    'unsupported contract1 rejects planning without pending writes',
    () async {
      final f = await _fixture(1);
      await expectLater(
        f.repo.saveFinancePlanForScope(
          scopeId: _scope,
          accounts: [],
          rules: [_draft()],
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'unsupported_version',
          ),
        ),
      );
      expect(await f.db.rows('SELECT * FROM finance_outbox'), isEmpty);
      expect(f.repo.state.dataForScope(_scope).financeRecurrenceRules, isEmpty);
    },
  );
}
