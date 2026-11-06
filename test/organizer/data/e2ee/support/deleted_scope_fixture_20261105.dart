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
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class DeletedScopeSecure implements AccountCryptoStore {
  final values = <String, String>{};
  final writes = <String>[];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    values[key] = value;
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
  }) async => throw StateError('unexpected_real_network');
  @override
  void close() {}
}

/// Acquisition is synthetic. Every returned account entry, scope origin,
/// membership proposal and activation is genuinely signed and replayed.
/// No SessionCryptoAccess verifier or authorization guard is overridden.
class DeletedScopeDirectory extends AccountDirectoryRepository {
  DeletedScopeDirectory({
    required super.reducer,
    required super.session,
    required super.store,
  }) : super(transport: _NoNetwork(), isCurrent: () => true);

  late VerifiedAccountDirectory verified;
  final entries = <Map<String, dynamic>>[];
  final wires = <String, Map<String, dynamic>>{};
  final calls = <String>[];
  final requests = <({String operation, Map<String, dynamic> params})>[];
  final responses = <String, Map<String, dynamic>>{};
  final handlers =
      <String, Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{};
  Future<void> Function(String operation, Map<String, dynamic> params)? onCall;
  bool current = true;
  @override
  bool Function() get isCurrent =>
      () => current;
  @override
  Future<VerifiedAccountDirectory> cachedVerifiedDirectory() async => verified;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => verified;
  @override
  Future<Map<String, dynamic>> scopeAccessChanges(List<String> ids) async => {
    'accessChangesVersion': 1,
    'serverId': session.profile.serverId,
    'accountId': session.profile.accountId,
    'deviceId': session.profile.deviceId,
    'scopeIds': ids,
    'revokedScopeIds': <String>[],
    'deletedScopeIds': <String>[],
  };
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    calls.add(operation);
    requests.add((operation: operation, params: Map.from(params)));
    await onCall?.call(operation, params);
    final handler = handlers[operation];
    if (handler != null) return handler(params);
    if (responses.containsKey(operation)) return responses[operation]!;
    if (operation == 'crypto2.account.scopeObservations') {
      return {'observations': <Object>[], 'hasMore': false};
    }
    if (operation == 'crypto2.scopes.catalog') {
      return {'scopes': <Object>[], 'hasMore': false, 'nextAfterId': null};
    }
    if (operation == 'crypto2.scope.deletionHead') {
      final wire = wires[params['headHash']];
      if (wire == null || wire['payload']['scopeId'] != params['scopeId']) {
        throw const CollaborationApiException('record_missing');
      }
      return Map<String, dynamic>.from(jsonDecode(jsonEncode(wire)) as Map);
    }
    if (operation == 'crypto2.scope.deletionDirectory') {
      final selected = entries.where(
        (entry) => entry['headHash'] == params['directoryHeadHash'],
      );
      if (selected.length != 1 || params['accountId'] != verified.accountId) {
        throw const CollaborationApiException('record_missing');
      }
      final generation = selected.single['generation'] as int;
      final after = params['afterGeneration'] as int? ?? 0;
      return {
        'entries': entries
            .where(
              (entry) =>
                  (entry['generation'] as int) > after &&
                  (entry['generation'] as int) <= generation,
            )
            .toList(),
        'hasMore': false,
      };
    }
    throw StateError('unexpected_retained_endpoint:$operation');
  }
}

class DeletedScopeFixture {
  DeletedScopeFixture._(
    this.db,
    this.secure,
    this.crypto,
    this.signing,
    this.directory,
    this.scope,
  );
  final CollaborationDatabase db;
  final DeletedScopeSecure secure;
  DeletedScopeSecure get secureMemory => secure;
  final CryptoCodec crypto;
  final KeyPair signing;
  final DeletedScopeDirectory directory;
  final String scope;
  late final account = AccountCryptoV2Workflow(directory);
  late final access = SessionCryptoAccess(account: account);
  final heads = <VerifiedScopeHead>[];
  Map<String, Map<String, dynamic>> get wires => directory.wires;
  VerifiedAccountDirectory get own => directory.verified;
  String get partition => account.store.partition;
  String get scopePinKey => 'scope2:$partition:$scope';
  late String initialPin;
  late Map<String, dynamic> baselineWire;

  Map<String, dynamic> sign(Map<String, dynamic> value, String domain) =>
      crypto.signDomain(value, signing.secretKey, domain);
  Map<String, dynamic> command(
    String operation,
    Map<String, dynamic> payload,
  ) => {
    'version': 2,
    'operation': operation,
    'requestId': crypto.randomId(),
    'serverId': own.serverId,
    'accountId': own.accountId,
    'deviceId': account.deviceId,
    'signer': 'device',
    'payload': payload,
  };

  Future<PreparedDirectoryMutation> prepareOwnEvent({
    required String operation,
    required Map<String, dynamic> payload,
    String? requestId,
  }) async {
    final event = await directory.reducer.prepare(
      previous: own,
      serverId: own.serverId,
      accountId: own.accountId,
      deviceId: account.deviceId,
      identityEpochId: own.identityEpochId,
      operation: operation,
      signer: 'device',
      pinnedRootFingerprint: own.rootFingerprint,
      signingKey: signing.secretKey,
      requestId: requestId,
      payload: payload,
    );
    await includeOwnEvent(event);
    return event;
  }

  Future<void> includeOwnEvent(PreparedDirectoryMutation event) async {
    directory.entries.add(event.entry);
    directory.verified = event.result;
    await account.store.remember(event.result, 'verified');
  }

  Future<Map<String, dynamic>> makeHead({
    required VerifiedScopeHead? previous,
    Map<String, dynamic> changes = const {},
  }) async {
    final codec = ScopeCryptoCodec(crypto);
    final epoch = (previous?.epoch ?? 0) + 1;
    final member = {
      'accountId': own.accountId,
      'rootSigningKeyBase64': own.snapshot['rootSigningKeyBase64'],
      'rootEncryptionKeyBase64': own.snapshot['rootEncryptionKeyBase64'],
      'recoveryRootEpochId': own.snapshot['recoveryRootEpochId'],
      'identityEpochId': own.identityEpochId,
      'directoryHeadHash': own.headHash,
      'deviceSnapshotHash': own.deviceSnapshotHash,
      'role': 'owner',
      'financeRole': 'none',
      'manageKeys': true,
    };
    final body = <String, dynamic>{
      'scopeId': scope,
      'epoch': epoch,
      'previousHeadHash': previous?.headHash ?? cryptoZeroHash,
      'initialLifecycleHash': baselineWire['initialLifecycleHash'],
      'previousLifecycleHash': previous == null ? null : cryptoZeroHash,
      'accessRevision': 0,
      'expectedAccessRevision': 0,
      'accessBasis': [
        {'scopeToken': '2' * 64, 'accessRevision': 0},
      ],
      'authorDirectoryHeadHash': own.headHash,
      'members': [member],
      'membershipIntents': <Object>[],
      'closures': {
        'content': previous == null ? null : '7' * 64,
        'finance': null,
      },
      'keyIds': {'content': crypto.randomId(), 'finance': null},
      'keyCommitments': {
        'content': await cryptoSha256(
          utf8.encode('$scope:$epoch:${crypto.randomId()}'),
        ),
        'finance': null,
      },
      'contentKeyProposalProof': null,
      'financeKeyProposalProof': null,
      'financePolicyIntentProof': null,
      ...changes,
    };
    final proof = sign(
      command('crypto2.scope.headPut', body),
      cryptoDirectoryDomain,
    );
    final pending = await codec.verifyProposal(
      serverId: own.serverId,
      authorization: proof,
      previous: previous,
      authorDirectory: own,
      directoryAtHead: (_, _) async => own,
      checkIdentity: (_, _) async {},
      accessPolicyVersion: 3,
    );
    final activation = sign(
      command('crypto2.scope.activate', {
        'scopeId': scope,
        'headHash': pending.headHash,
        'grantManifestHash': '8' * 64,
        'authorDirectoryHeadHash': own.headHash,
      }),
      cryptoDirectoryDomain,
    );
    final active = await codec.verifyActivation(
      pending: pending,
      previous: previous,
      authorization: activation,
      authorDirectory: own,
      grantManifestHash: '8' * 64,
      directoryAtHead: (_, _) async => own,
    );
    final wire = <String, dynamic>{
      ...baselineWire,
      'headHash': active.headHash,
      'payload': active.body,
      'authorization': proof,
      'activationAuthorization': activation,
    };
    heads.add(active);
    wires[active.headHash] = wire;
    return wire;
  }

  Future<void> storeHead(VerifiedScopeHead head) =>
      db.execute('INSERT INTO crypto_scope_heads VALUES(?,?,?,?,?,?,?,?,?)', [
        partition,
        scope,
        head.headHash,
        head.epoch,
        head.epoch,
        head.epoch.toString(),
        head.body['previousHeadHash'],
        CryptoJson.encode(head.body),
        CryptoJson.encode(wires[head.headHash]),
      ]);

  Future<String> durableDigest() async => cryptoSha256(
    CryptoJson.encodeDerivedState({
      'heads': await db.rows(
        'SELECT * FROM crypto_scope_heads WHERE partition=? ORDER BY head_hash',
        [partition],
      ),
      'scopedDirectories': await db.rows(
        'SELECT * FROM crypto_restore_scoped_directories WHERE partition=? ORDER BY scope_id,head_hash,account_id,directory_head_hash',
        [partition],
      ),
      'scopeKeys': await db.rows(
        'SELECT COUNT(*) AS n FROM crypto_scope_keys WHERE partition=?',
        [partition],
      ),
      'domainState': await db.rows(
        'SELECT * FROM crypto_scope_state WHERE partition=? ORDER BY scope_id,domain',
        [partition],
      ),
    }),
  );
}

Future<DeletedScopeFixture> deletedScopeFixture({int headCount = 3}) async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final secure = DeletedScopeSecure();
  final crypto = CryptoCodec(await SodiumInit.init());
  final root = crypto.sodium.crypto.sign.keyPair();
  final signing = crypto.sodium.crypto.sign.keyPair();
  final box = crypto.sodium.crypto.box.keyPair();
  final deviceBox = crypto.sodium.crypto.box.keyPair();
  for (final pair in [root, signing, box, deviceBox]) {
    addTearDown(pair.secretKey.dispose);
  }
  final profile = AccountSession(
    serverUrl: 'https://synthetic.invalid/',
    serverId: crypto.randomId(),
    accountId: crypto.randomId(),
    userId: 1,
    username: 'Synthetic',
    displayName: 'Synthetic',
    deviceId: crypto.randomId(),
    expiresAt: DateTime.utc(2030),
  );
  final directory = DeletedScopeDirectory(
    reducer: AccountDirectoryV2(crypto),
    session: DeviceSession(profile, 'synthetic-token'),
    store: CryptoIdentityStore(db, secure, profile.partition),
  );
  final initialized = await directory.reducer.prepare(
    previous: null,
    serverId: profile.serverId,
    accountId: profile.accountId,
    deviceId: profile.deviceId,
    identityEpochId: crypto.randomId(),
    operation: 'crypto2.account.initialize',
    signer: 'root',
    pinnedRootFingerprint: crypto.fingerprint(root.publicKey, box.publicKey),
    signingKey: root.secretKey,
    payload: {
      'rootSigningKeyBase64': base64Encode(root.publicKey),
      'rootEncryptionKeyBase64': base64Encode(box.publicKey),
      'deviceSigningKeyBase64': base64Encode(signing.publicKey),
      'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
      'keyringCiphertextBase64': base64Encode(Uint8List(48)),
    },
  );
  directory.verified = initialized.result;
  directory.entries.add(initialized.entry);
  await directory.store.pinRoot(
    profile.accountId,
    profile.serverId,
    initialized.result.rootFingerprint,
  );
  await directory.store.remember(initialized.result, 'verified');
  await db.execute('INSERT INTO accounts VALUES(?,?)', [
    profile.partition,
    jsonEncode(profile.toJson()),
  ]);
  final f = DeletedScopeFixture._(
    db,
    secure,
    crypto,
    signing,
    directory,
    crypto.randomId(),
  );
  final origin = f.sign({
    'version': 2,
    'operation': 'crypto2.scope.origin',
    'serverId': profile.serverId,
    'scopeId': f.scope,
    'kind': 'household',
    'accessPolicyVersion': 3,
    'parentScopeToken': null,
    'requestId': crypto.randomId(),
    'accountId': profile.accountId,
    'deviceId': profile.deviceId,
    'authorDirectoryHeadHash': f.own.headHash,
  }, 'JivieE2EE/scopeOrigin/v2\n');
  final baseline = {
    'version': 2,
    'scopeId': f.scope,
    'originKind': 'new',
    'ownArchived': false,
    'inheritedArchived': false,
    'originProofHash': await cryptoSha256(CryptoJson.encode(origin)),
  };
  f.baselineWire = {
    'initialLifecycleBaseline': baseline,
    'originAuthorization': origin,
    'originAuthorDirectoryHeadHash': f.own.headHash,
    'initialLifecycleHash': await cryptoSha256([
      ...utf8.encode('JivieLifecycleBaseline/v2\n'),
      ...CryptoJson.encode(baseline),
    ]),
  };
  for (var i = 0; i < headCount; i++) {
    await f.makeHead(previous: f.heads.isEmpty ? null : f.heads.last);
  }
  if (headCount < 2) throw ArgumentError('two_signed_heads_required');
  f.initialPin = utf8.decode(
    CryptoJson.encode({'epoch': 2, 'headHash': f.heads[1].headHash}),
  );
  await secure.write(f.scopePinKey, f.initialPin);
  // Mimic retained SQL ancestry while keeping global account entries absent:
  // historical directory replay must therefore use deletionDirectory.
  await f.storeHead(f.heads[0]);
  await f.storeHead(f.heads[1]);
  return f;
}
