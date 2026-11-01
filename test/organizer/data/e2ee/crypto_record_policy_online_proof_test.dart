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
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_policy.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

// Scope-history admission is an explicit seam. Directory history, identity
// anchoring, owner checks, all baseline signatures and AEAD are production code.
class _Head implements VerifiedScopeHead {
  _Head(this.scopeId, this.owner, this.directoryHeadHash);
  @override
  final String scopeId;
  final String owner, directoryHeadHash;
  @override
  String get headHash => 'b' * 64;
  @override
  int get epoch => 1;
  @override
  int get accessRevision => 1;
  @override
  List<Map<String, dynamic>> get members => [
    {
      'accountId': owner,
      'role': 'owner',
      'directoryHeadHash': directoryHeadHash,
    },
  ];
  @override
  Map<String, dynamic> member(String id) =>
      members.singleWhere((m) => m['accountId'] == id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access extends SessionCryptoAccess {
  _Access(AccountCryptoV2Workflow account, this.head, this.key, this.crypto)
    : super(account: account);
  final _Head head;
  final Uint8List key;
  final CryptoCodec crypto;
  final headReads = <bool>[];
  @override
  Future<VerifiedScopeHead> headAt(
    String scopeId,
    String hash, {
    bool online = false,
  }) async {
    expect(scopeId, head.scopeId);
    expect(hash, head.headHash);
    headReads.add(online);
    return head;
  }

  @override
  Future<CryptoKeyLease> getScopeKey(
    String scope,
    String domain,
    int epoch,
  ) async {
    expect([scope, domain, epoch], [head.scopeId, 'content', 1]);
    return CryptoKeyLease.owned(crypto.sodium.secureCopy(key));
  }
}

class _Transport implements CollaborationTransport {
  late Future<Map<String, dynamic>> Function(String, Map<String, Object?>)
  handler;
  final calls = <({String op, Map<String, Object?> params})>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) {
    calls.add((op: operation, params: Map.of(params)));
    return handler(operation, params);
  }

  @override
  void close() {}
}

void main() {
  Future<
    ({
      CryptoRecordPolicyBaseline baseline,
      CollaborationDatabase db,
      CryptoIdentityStore store,
      _Secure secure,
      _Access access,
      _Transport transport,
      String owner,
      String scope,
      String id,
      String recordProof,
      String historicalHash,
      String knownHash,
      Uint8List secret,
      Map<String, dynamic> page,
      Map<String, String> before,
      void Function() expire,
    })
  >
  fixture({
    bool corruptDirectory = false,
    bool foreignDirectory = false,
  }) async {
    final crypto = CryptoCodec(await SodiumInit.init());
    final reducer = AccountDirectoryV2(crypto);
    final keys = [
      crypto.sodium.crypto.sign.keyPair(),
      crypto.sodium.crypto.box.keyPair(),
      crypto.sodium.crypto.sign.keyPair(),
      crypto.sodium.crypto.box.keyPair(),
    ];
    addTearDown(() {
      for (final pair in keys) {
        pair.secretKey.dispose();
      }
    });
    final root = keys[0], box = keys[1], device = keys[2], deviceBox = keys[3];
    final server = crypto.randomId(), owner = crypto.randomId();
    final deviceId = crypto.randomId(), identityEpoch = crypto.randomId();
    final fingerprint = crypto.fingerprint(root.publicKey, box.publicKey);
    final first = await reducer.prepare(
      previous: null,
      serverId: server,
      accountId: owner,
      deviceId: deviceId,
      identityEpochId: identityEpoch,
      operation: 'crypto2.account.initialize',
      signer: 'root',
      pinnedRootFingerprint: fingerprint,
      signingKey: root.secretKey,
      payload: {
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(box.publicKey),
        'deviceSigningKeyBase64': base64Encode(device.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
        'keyringCiphertextBase64': base64Encode(Uint8List(48)),
      },
    );
    final prefix = [first];
    for (var i = 0; i < 2; i++) {
      prefix.add(
        await reducer.prepare(
          previous: prefix.last.result,
          serverId: server,
          accountId: owner,
          deviceId: deviceId,
          identityEpochId: identityEpoch,
          operation: 'crypto2.account.projectRelocation',
          signer: 'device',
          pinnedRootFingerprint: fingerprint,
          signingKey: device.secretKey,
          payload: {
            'actionId': crypto.randomId(),
            'publicationRoot': '${i + 1}' * 64,
          },
        ),
      );
    }
    final recipient = crypto.randomId();
    final profile = AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: server,
      accountId: recipient,
      userId: 2,
      username: 'recipient',
      displayName: 'Recipient',
      deviceId: crypto.randomId(),
      expiresAt: DateTime.utc(2030),
    );
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secure = _Secure();
    final store = CryptoIdentityStore(db, secure, profile.partition);
    // Recipient retains its independently verified newer owner pin, but the
    // historical owner journal has not been materialized in its local SQL.
    await store.pinComparedIdentity(prefix.last.result, fingerprint);
    await store.remember(prefix.last.result, 'verified');
    expect(await store.entries(owner), isEmpty);
    final before = Map.of(secure.values);
    final transport = _Transport();
    var current = true;
    final repository = AccountDirectoryRepository(
      reducer: reducer,
      session: DeviceSession(profile, 'synthetic'),
      transport: transport,
      store: store,
      isCurrent: () => current,
    );
    final account = AccountCryptoV2Workflow(repository);
    final scope = crypto.randomId(), baselineId = crypto.randomId();
    final head = _Head(scope, owner, prefix[1].result.headHash);
    final domainKey = crypto.sodium.randombytes.buf(32);
    final secret = crypto.sodium.randombytes.buf(32);
    addTearDown(() {
      domainKey.fillRange(0, domainKey.length, 0);
      secret.fillRange(0, secret.length, 0);
    });
    final access = _Access(account, head, domainKey, crypto);
    final baseline = CryptoRecordPolicyBaseline(
      CryptoBusinessSession(account, access, db),
    );
    final id = CryptoRecordAddress.forType(
          serverId: server,
          scopeId: scope,
          type: 'shoppingList',
          canonicalId: crypto.randomId(),
        ).wireId,
        recordProof = 'c' * 64;
    final policy = await CryptoRecordPolicy.prepare(
      serverId: server,
      scopeId: scope,
      domain: 'content',
      wireId: id,
      type: 'shoppingList',
      creator: owner,
      operation: 'edit',
      payload: CryptoRecordPolicy.attachSecret({'title': 'Synthetic'}, secret),
    );
    final encryptionKey = crypto.sodium.secureCopy(domainKey);
    late Map<String, dynamic> envelope;
    try {
      envelope = crypto.encrypt(
        plaintext: CryptoJson.encode({
          'version': 1,
          'keyBase64': base64Encode(secret),
        }),
        key: encryptionKey,
        context: {
          'version': 1,
          'purpose': 'recordPolicyBaseline',
          'serverId': server,
          'scopeId': scope,
          'domain': 'content',
          'id': id,
          'type': 'shoppingList',
          'recordProofHash': recordProof,
          'createdByAccountId': owner,
          'membershipHeadHash': head.headHash,
          'accessRevision': 1,
        },
      );
    } finally {
      encryptionKey.dispose();
    }
    final entry = <String, dynamic>{
      'id': id,
      'domain': 'content',
      'type': 'shoppingList',
      'recordProofHash': recordProof,
      'createdByAccountId': owner,
      'fieldCommitments': policy['fieldCommitments'],
      'policyEnvelopeBase64': base64Encode(CryptoJson.encode(envelope)),
    };
    final common = <String, dynamic>{
      'scopeId': scope,
      'baselineId': baselineId,
      'membershipHeadHash': head.headHash,
      'accessRevision': 1,
    };
    Map<String, dynamic> signed(
      String operation,
      Map<String, dynamic> payload,
    ) => CryptoRecordProofCodec(crypto).signCommand({
      'version': 2,
      'operation': operation,
      'requestId': crypto.randomId(),
      'serverId': server,
      'accountId': owner,
      'deviceId': deviceId,
      'signer': 'device',
      'payload': {...common, ...payload},
    }, device.secretKey);
    final baselineRoot = await CryptoRecordPolicyBaseline.root([entry]);
    final status = <String, dynamic>{
      'version': 1,
      'serverId': server,
      'accountId': recipient,
      'deviceId': profile.deviceId,
      ...common,
      'active': true,
      'activeBaselineId': baselineId,
      'policyVersion': 1,
      'baselineCount': 1,
      'baselineRoot': baselineRoot,
      'expectedContentSequence': 1,
      'expectedFinanceSequence': 0,
    };
    final page = <String, dynamic>{
      ...status,
      'prepareAuthorization': signed('crypto2.scope.recordPolicy.prepare', {
        'policyVersion': 1,
        'expectedContentSequence': 1,
        'expectedFinanceSequence': 0,
      }),
      'activationAuthorization': signed('crypto2.scope.recordPolicy.activate', {
        'policyVersion': 1,
        'baselineCount': 1,
        'baselineRoot': baselineRoot,
      }),
      'records': [
        {
          'entry': entry,
          'stageAuthorization': signed('crypto2.scope.recordPolicy.stage', {
            'records': [entry],
          }),
        },
      ],
      'hasMore': false,
    };
    transport.handler = (operation, params) async {
      if (operation == 'capabilities') {
        return {
          'serverId': server,
          'recordPolicyVersions': [1],
        };
      }
      if (operation == 'crypto2.scope.recordPolicy.status') return status;
      if (operation == 'crypto2.scope.recordPolicy.baseline') return page;
      if (operation == 'crypto2.directory.read') {
        expect(params['scopeId'], scope);
        expect(params['headHash'], head.headHash);
        expect(params['accountId'], owner);
        expect(params['limit'], 50);
        final selected = prefix.indexWhere(
          (e) => e.result.headHash == params['directoryHeadHash'],
        );
        expect(selected, greaterThanOrEqualTo(0));
        final after = params['afterGeneration'] as int;
        final entries =
            jsonDecode(
                  jsonEncode([
                    for (final mutation in prefix.take(selected + 1))
                      if (mutation.result.generation > after) mutation.entry,
                  ]),
                )
                as List;
        if (corruptDirectory && after == 0) {
          entries.first['authorization']['signatureBase64'] = base64Encode(
            Uint8List(64),
          );
        }
        if (foreignDirectory && after == 0) {
          final command =
              CryptoJson.decode(
                    cryptoBase64(
                      entries.first['authorization']['commandBase64'],
                    ),
                  )
                  as Map<String, dynamic>;
          command['accountId'] = recipient;
          entries.first['authorization'] = CryptoRecordProofCodec(
            crypto,
          ).signCommand(command, root.secretKey);
        }
        return {'entries': entries, 'hasMore': false};
      }
      throw StateError('Unexpected operation $operation');
    };
    return (
      baseline: baseline,
      db: db,
      store: store,
      secure: secure,
      access: access,
      transport: transport,
      owner: owner,
      scope: scope,
      id: id,
      recordProof: recordProof,
      historicalHash: prefix[1].result.headHash,
      knownHash: prefix.last.result.headHash,
      secret: secret,
      page: page,
      before: before,
      expire: () => current = false,
    );
  }

  test(
    'recipient fetches missing historical signer proof and verifies baseline record',
    () async {
      final f = await fixture();
      final record = await f.baseline.record(
        scopeId: f.scope,
        domain: 'content',
        id: f.id,
        recordProofHash: f.recordProof,
      );
      expect(record, isNotNull);
      try {
        expect(record!.key, orderedEquals(f.secret));
        expect(record.policy['createdByAccountId'], f.owner);
      } finally {
        record?.key.fillRange(0, record.key.length, 0);
      }
      expect(f.access.headReads.first, isTrue);
      // A later record read must use the same verified historical prefix,
      // without re-fetching the two directory pages.
      final warm = await f.baseline.record(
        scopeId: f.scope,
        domain: 'content',
        id: f.id,
        recordProofHash: f.recordProof,
      );
      try {
        expect(warm!.key, orderedEquals(f.secret));
      } finally {
        warm?.key.fillRange(0, warm.key.length, 0);
      }
      final reads = f.transport.calls
          .where((c) => c.op == 'crypto2.directory.read')
          .toList();
      expect(reads, hasLength(2));
      expect(reads.first.params, containsPair('afterGeneration', 0));
      expect(
        reads.first.params,
        containsPair('directoryHeadHash', f.historicalHash),
      );
      expect(reads.last.params, containsPair('afterGeneration', 2));
      expect(reads.last.params, containsPair('directoryHeadHash', f.knownHash));
      expect(f.secure.values, f.before);
      expect(await f.store.entries(f.owner), isEmpty);
    },
  );

  test(
    'forged fetched directory signature fails closed and preserves secure identity',
    () async {
      final f = await fixture(corruptDirectory: true);
      await expectLater(f.baseline.active(f.scope), throwsFormatException);
      expect(f.secure.values, f.before);
      expect(await f.store.entries(f.owner), isEmpty);
    },
  );

  test(
    'fetched directory for another account fails closed and preserves secure identity',
    () async {
      final f = await fixture(foreignDirectory: true);
      await expectLater(
        f.baseline.active(f.scope),
        throwsA(isA<CryptoDirectoryException>()),
      );
      expect(f.secure.values, f.before);
      expect(await f.store.entries(f.owner), isEmpty);
    },
  );

  for (final authorization in [
    'prepareAuthorization',
    'activationAuthorization',
  ]) {
    test(
      'forged $authorization remains rejected after historical signer retrieval',
      () async {
        final f = await fixture();
        (f.page[authorization] as Map)['signatureBase64'] = base64Encode(
          Uint8List(64),
        );
        await expectLater(f.baseline.active(f.scope), throwsFormatException);
        expect(f.secure.values, f.before);
        expect(await f.store.entries(f.owner), isEmpty);
      },
    );
  }

  test(
    'forged stage signature cannot return a baseline record secret',
    () async {
      final f = await fixture();
      f.page['records'][0]['stageAuthorization']['signatureBase64'] =
          base64Encode(Uint8List(64));
      await expectLater(
        f.baseline.record(
          scopeId: f.scope,
          domain: 'content',
          id: f.id,
          recordProofHash: f.recordProof,
        ),
        throwsFormatException,
      );
      expect(f.secure.values, f.before);
      expect(await f.store.entries(f.owner), isEmpty);
    },
  );

  test(
    'session change during historical retrieval rejects baseline without identity mutation',
    () async {
      final f = await fixture();
      final original = f.transport.handler;
      f.transport.handler = (op, params) async {
        final result = await original(op, params);
        if (op == 'crypto2.directory.read') f.expire();
        return result;
      };
      await expectLater(
        f.baseline.active(f.scope),
        throwsA(
          isA<CryptoDirectoryException>().having(
            (e) => e.code,
            'code',
            'directory_stale_identity',
          ),
        ),
      );
      expect(f.secure.values, f.before);
      expect(await f.store.entries(f.owner), isEmpty);
    },
  );
}
