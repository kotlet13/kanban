import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
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
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

String _pin(Object value) => utf8.decode(CryptoJson.encode(value));

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _NoNetwork implements CollaborationTransport {
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async => throw StateError('Unexpected network');
  @override
  void close() {}
}

class _Directory extends AccountDirectoryRepository {
  _Directory({
    required super.reducer,
    required super.session,
    required super.store,
  }) : super(transport: _NoNetwork(), isCurrent: () => true);
  late VerifiedAccountDirectory verified;
  late Map<String, dynamic> lifecycle, baseline;
  final prefixes = <String, VerifiedAccountDirectory>{};
  Future<void> Function()? onList;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => verified;
  @override
  Future<VerifiedAccountDirectory> cachedVerifiedDirectory() async => verified;
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (operation == 'crypto2.scope.lifecycle.baseline') {
      return baseline;
    }
    if (operation == 'crypto2.scope.lifecycle.list') {
      final callback = onList;
      onList = null;
      await callback?.call();
      return {
        'states': params['afterRevision'] == 0 ? [lifecycle] : [],
        'hasMore': false,
        'currentRevision': 1,
      };
    }
    throw StateError('Unexpected operation');
  }
}

// The access boundary supplies an already authenticated candidate. These tests
// exercise the real lifecycle signature/ancestry/staging/floor logic, not scope
// codecs (which have their own signed vectors).
class _Head implements VerifiedScopeHead {
  _Head(this.body, this.headHash);
  @override
  final Map<String, dynamic> body;
  @override
  final String headHash;
  @override
  Map<String, dynamic> get authorization => const {};
  @override
  bool get active => true;
  @override
  String get scopeId => body['scopeId'];
  @override
  int get epoch => body['epoch'];
  @override
  int get accessRevision => 0;
  @override
  List<Map<String, dynamic>> get members =>
      (body['members'] as List).cast<Map<String, dynamic>>();
  @override
  Map<String, dynamic> member(String id) =>
      members.singleWhere((m) => m['accountId'] == id);
  @override
  String? commitment(String domain) => null;
}

class _Access extends SessionCryptoAccess {
  _Access({
    required super.account,
    required this.source,
    required this.ancestor,
  });
  final _Head source, ancestor;
  var candidateCalls = 0, ordinaryCalls = 0;
  bool changeSource = false, authenticateDescriptor = true;
  @override
  Future<VerifiedScopeHead> recoveryCandidateHead(String scopeId) async {
    candidateCalls++;
    if (authenticateDescriptor) {
      final directory = account.directory as _Directory;
      await verifyInitialLifecycle(
        scopeId,
        directory.baseline,
        scopeHeadHash: source.headHash,
      );
    }
    return changeSource && candidateCalls > 1
        ? _Head(source.body, 'e' * 64)
        : source;
  }

  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async {
    ordinaryCalls++;
    throw const CryptoAuthorityPending('scope_authority_history_pending');
  }

  @override
  Future<VerifiedScopeHead> headAt(
    String scopeId,
    String hash, {
    bool online = false,
  }) async {
    ordinaryCalls++;
    throw const CryptoAuthorityPending('scope_authority_history_pending');
  }

  @override
  VerifiedScopeHead verifiedCandidateAncestor(String hash) {
    if (hash == ancestor.headHash) return ancestor;
    if (hash == source.headHash) return source;
    throw const CryptoAuthorityPending('scope_prefix_pending');
  }

  @override
  Set<String> observedLifecycleHashes(String scopeId) => {};
  @override
  Future<VerifiedAccountDirectory> directoryAt({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    bool online = false,
    bool allowUnverifiedContact = false,
  }) async {
    final directory = account.directory as _Directory;
    return directory.prefixes[directoryHeadHash] ?? directory.verified;
  }
}

Future<
  ({
    CryptoLifecycleEvidence evidence,
    _Access access,
    _Secure secure,
    CollaborationDatabase db,
    _Directory directory,
    String scope,
    String partition,
    Future<void> Function() advanceOwn,
  })
>
_fixture({bool manageKeys = true, String financeRole = 'read'}) async {
  final crypto = CryptoCodec(await SodiumInit.init());
  final root = crypto.sodium.crypto.sign.keyPair(),
      box = crypto.sodium.crypto.box.keyPair(),
      device = crypto.sodium.crypto.sign.keyPair(),
      deviceBox = crypto.sodium.crypto.box.keyPair();
  addTearDown(() {
    for (final pair in [root, box, device, deviceBox]) {
      pair.secretKey.dispose();
    }
  });
  final server = crypto.randomId(),
      accountId = crypto.randomId(),
      deviceId = crypto.randomId(),
      identityEpoch = crypto.randomId(),
      scope = crypto.randomId();
  final reducer = AccountDirectoryV2(crypto);
  final initialized = await reducer.prepare(
    previous: null,
    serverId: server,
    accountId: accountId,
    deviceId: deviceId,
    identityEpochId: identityEpoch,
    operation: 'crypto2.account.initialize',
    signer: 'root',
    pinnedRootFingerprint: crypto.fingerprint(root.publicKey, box.publicKey),
    signingKey: root.secretKey,
    payload: {
      'rootSigningKeyBase64': base64Encode(root.publicKey),
      'rootEncryptionKeyBase64': base64Encode(box.publicKey),
      'deviceSigningKeyBase64': base64Encode(device.publicKey),
      'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
      'keyringCiphertextBase64': base64Encode(Uint8List(48)),
    },
  );
  final session = DeviceSession(
    AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: server,
      accountId: accountId,
      userId: 1,
      username: 'synthetic',
      displayName: 'Synthetic',
      deviceId: deviceId,
      expiresAt: DateTime.utc(2030),
    ),
    'synthetic',
  );
  final db = CollaborationDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final secure = _Secure(), partition = session.profile.partition;
  final directory = _Directory(
    reducer: reducer,
    session: session,
    store: CryptoIdentityStore(db, secure, partition),
  )..verified = initialized.result;
  directory.prefixes[initialized.result.headHash] = initialized.result;
  final workflow = AccountCryptoV2Workflow(directory);
  final member = {
    'accountId': accountId,
    'manageKeys': true,
    'financeRole': financeRole,
    'rootSigningKeyBase64': base64Encode(root.publicKey),
    'rootEncryptionKeyBase64': base64Encode(box.publicKey),
    'deviceSnapshotHash': initialized.result.deviceSnapshotHash,
  };
  final ancestor = _Head({
    'scopeId': scope,
    'epoch': 1,
    'previousHeadHash': cryptoZeroHash,
    'previousLifecycleHash': null,
    'initialLifecycleHash': '1' * 64,
    'members': [member],
  }, '2' * 64);
  Map<String, dynamic> command(
    String operation,
    Map<String, dynamic> payload,
  ) => {
    'version': 2,
    'operation': operation,
    'serverId': server,
    'accountId': accountId,
    'deviceId': deviceId,
    'requestId': crypto.randomId(),
    'signer': 'device',
    'payload': payload,
  };
  final origin = crypto.signDomain(
    {
      'version': 2,
      'operation': 'crypto2.scope.origin',
      'serverId': server,
      'scopeId': scope,
      'kind': 'household',
      'accessPolicyVersion': 3,
      'parentScopeToken': null,
      'requestId': crypto.randomId(),
      'accountId': accountId,
      'deviceId': deviceId,
      'authorDirectoryHeadHash': initialized.result.headHash,
    },
    device.secretKey,
    'JivieE2EE/scopeOrigin/v2\n',
  );
  final baseline = <String, dynamic>{
    'version': 2,
    'scopeId': scope,
    'originKind': 'new',
    'ownArchived': false,
    'inheritedArchived': false,
    'originProofHash': await cryptoSha256(CryptoJson.encode(origin)),
  };
  final initialHash = await cryptoSha256([
    ...utf8.encode('JivieLifecycleBaseline/v2\n'),
    ...CryptoJson.encode(baseline),
  ]);
  ancestor.body['initialLifecycleHash'] = initialHash;
  directory.baseline = {
    'initialLifecycleBaseline': baseline,
    'originAuthorization': origin,
    'originAuthorDirectoryHeadHash': initialized.result.headHash,
    'initialLifecycleHash': initialHash,
  };
  final action = crypto.randomId();
  final intent = crypto.signDomain(
    command('crypto2.scope.lifecycle.prepare', {
      'scopeId': scope,
      'parentActionId': action,
      'expectedLifecycleRevision': 0,
      'previousLifecycleHash': cryptoZeroHash,
      'membershipHeadHash': ancestor.headHash,
      'expectedAccessRevision': 0,
      'authorDirectoryHeadHash': initialized.result.headHash,
      'archived': true,
    }),
    device.secretKey,
    cryptoDirectoryDomain,
  );
  Future<String> hash(Map proof) => cryptoSha256([
    ...utf8.encode(CryptoLifecycleEvidence.proofDomain),
    ...CryptoJson.encode(proof),
  ]);
  final archive = crypto.signDomain(
    command('crypto2.scope.archive', {
      'scopeId': scope,
      'parentActionId': action,
      'intentProofHash': await hash(intent),
      'childCount': 0,
      'childrenHash': '3' * 64,
    }),
    device.secretKey,
    cryptoDirectoryDomain,
  );
  final lifecycleHash = await hash(archive);
  directory.lifecycle = {
    'scopeId': scope,
    'revision': 1,
    'headHash': lifecycleHash,
    'authorization': archive,
    'intentAuthorization': intent,
    'ownArchived': true,
    'inheritedArchived': false,
  };
  final source = _Head({
    'scopeId': scope,
    'epoch': 2,
    'previousHeadHash': ancestor.headHash,
    'previousLifecycleHash': lifecycleHash,
    'initialLifecycleHash': initialHash,
    'members': [
      {...member, 'manageKeys': manageKeys},
    ],
  }, '4' * 64);
  final access = _Access(account: workflow, source: source, ancestor: ancestor);
  return (
    evidence: CryptoLifecycleEvidence(access),
    access: access,
    secure: secure,
    db: db,
    directory: directory,
    scope: scope,
    partition: partition,
    advanceOwn: () async {
      final next = await reducer.prepare(
        previous: directory.verified,
        serverId: server,
        accountId: accountId,
        deviceId: deviceId,
        identityEpochId: identityEpoch,
        operation: 'crypto2.account.projectRelocation',
        signer: 'device',
        pinnedRootFingerprint: initialized.result.rootFingerprint,
        signingKey: device.secretKey,
        payload: {'actionId': crypto.randomId(), 'publicationRoot': '5' * 64},
      );
      directory.verified = next.result;
      directory.prefixes[next.result.headHash] = next.result;
    },
  );
}

Future<void> _noPromotion(dynamic f) async {
  expect(f.access.ordinaryCalls, 0);
  expect(
    await f.db.rows(
      "SELECT 1 FROM crypto_membership_intents WHERE state IN ('lifecycleCandidate','lifecycleVerified')",
    ),
    isEmpty,
  );
  expect(await f.db.rows('SELECT 1 FROM crypto_scope_heads'), isEmpty);
  expect(await f.db.rows('SELECT 1 FROM crypto_scope_keys'), isEmpty);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'finance READ without manager may inspect signed lifecycle; no floor or cache promotion',
    () async {
      final f = await _fixture(manageKeys: false);
      final before = Map.of(f.secure.values);
      final value = await f.evidence.forRecoveryReview(
        f.scope,
        sourceHeadHash: f.access.source.headHash,
        financeOnly: true,
      );
      expect(value['revision'], 1);
      expect(value['ownArchived'], true);
      expect(f.access.candidateCalls, 2);
      expect(f.secure.values, before);
      await _noPromotion(f);
    },
  );
  test(
    'full review still requires manager; finance-only still requires finance READ',
    () async {
      for (final financeOnly in [false, true]) {
        final f = await _fixture(
          manageKeys: false,
          financeRole: financeOnly ? 'none' : 'read',
        );
        await expectLater(
          f.evidence.forRecoveryReview(
            f.scope,
            sourceHeadHash: f.access.source.headHash,
            financeOnly: financeOnly,
          ),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'scope_review_changed',
            ),
          ),
        );
        expect(f.secure.values, isEmpty);
        await _noPromotion(f);
      }
    },
  );
  test(
    'changed exact source or scope pin rejects and discards staged lifecycle',
    () async {
      for (final sourceChanges in [true, false]) {
        final f = await _fixture();
        f.access.changeSource = sourceChanges;
        if (!sourceChanges) {
          f.directory.onList = () => f.secure.write(
            'scope2:${f.partition}:${f.scope}',
            _pin({'epoch': 1, 'headHash': f.access.ancestor.headHash}),
          );
        }
        await expectLater(
          f.evidence.forRecoveryReview(
            f.scope,
            sourceHeadHash: f.access.source.headHash,
            financeOnly: false,
          ),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'scope_review_changed',
            ),
          ),
        );
        expect(
          await f.secure.read('lifecycle2:${f.partition}:${f.scope}'),
          isNull,
        );
        await _noPromotion(f);
      }
    },
  );
  test(
    'existing scope and lifecycle forks cannot be accepted as review baseline',
    () async {
      for (final scopeFork in [true, false]) {
        final f = await _fixture();
        final pin = scopeFork
            ? 'scope2:${f.partition}:${f.scope}'
            : 'lifecycle2:${f.partition}:${f.scope}';
        await f.secure.write(
          pin,
          _pin(
            scopeFork
                ? {'epoch': 1, 'headHash': 'f' * 64}
                : {'revision': 1, 'headHash': 'f' * 64},
          ),
        );
        final before = Map.of(f.secure.values);
        await expectLater(
          f.evidence.forRecoveryReview(
            f.scope,
            sourceHeadHash: f.access.source.headHash,
            financeOnly: false,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              scopeFork ? 'scope_known_fork' : 'lifecycle_known_rollback',
            ),
          ),
        );
        expect(f.secure.values, before);
        await _noPromotion(f);
      }
    },
  );
  test(
    'recovery policy callback uses authenticated descriptor and expires without authority promotion',
    () async {
      final f = await _fixture();
      final before = Map.of(f.secure.values);
      VerifiedScopeRecoveryPolicy? retained;
      final value = await f.access.withRecoveryCandidatePolicy(
        scopeId: f.scope,
        sourceHeadHash: f.access.source.headHash,
        body: (policy) async {
          retained = policy;
          return policy.accessPolicyVersion;
        },
      );
      expect(value, 3);
      expect(
        () => retained!.accessPolicyVersion,
        throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(f.secure.values, before);
      await _noPromotion(f);
      await expectLater(
        f.access.verifiedScopeDescriptor(f.scope),
        throwsA(isA<CryptoAuthorityPending>()),
      );
    },
  );
  test(
    'recovery policy rejects absent descriptor, wrong source and existing floor fork before callback',
    () async {
      for (final cause in ['descriptor', 'source', 'fork']) {
        final f = await _fixture();
        f.access.authenticateDescriptor = cause != 'descriptor';
        if (cause == 'fork') {
          await f.secure.write(
            'scope2:${f.partition}:${f.scope}',
            _pin({'epoch': 1, 'headHash': 'f' * 64}),
          );
        }
        var called = false;
        final before = Map.of(f.secure.values);
        await expectLater(
          f.access.withRecoveryCandidatePolicy(
            scopeId: f.scope,
            sourceHeadHash: cause == 'source'
                ? 'e' * 64
                : f.access.source.headHash,
            body: (_) async {
              called = true;
            },
          ),
          throwsA(
            cause == 'fork'
                ? isA<FormatException>()
                : isA<CryptoAuthorityPending>(),
          ),
        );
        expect(called, false);
        expect(f.secure.values, before);
        await _noPromotion(f);
      }
    },
  );
  test(
    'recovery policy callback rejects source, own-prefix and scope-pin changes after await',
    () async {
      for (final cause in ['source', 'own', 'pin']) {
        final f = await _fixture();
        VerifiedScopeRecoveryPolicy? retained;
        await expectLater(
          f.access.withRecoveryCandidatePolicy(
            scopeId: f.scope,
            sourceHeadHash: f.access.source.headHash,
            body: (policy) async {
              retained = policy;
              expect(policy.accessPolicyVersion, 3);
              if (cause == 'source') f.access.changeSource = true;
              if (cause == 'own') await f.advanceOwn();
              if (cause == 'pin') {
                await f.secure.write(
                  'scope2:${f.partition}:${f.scope}',
                  _pin({'epoch': 1, 'headHash': f.access.ancestor.headHash}),
                );
              }
            },
          ),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'scope_review_changed',
            ),
          ),
        );
        expect(
          () => retained!.accessPolicyVersion,
          throwsA(isA<CryptoAuthorityPending>()),
        );
        await _noPromotion(f);
      }
    },
  );
}
