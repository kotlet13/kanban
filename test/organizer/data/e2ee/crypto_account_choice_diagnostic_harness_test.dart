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
import 'package:kanban/organizer/data/e2ee/crypto_finance_choice_selection_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scoped_exports.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

const _parent = 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
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
  _Own(this.signing, this.encryption);
  final KeyPair signing, encryption;
  @override
  String get headHash => 'd' * 64;
  @override
  Map<String, dynamic> get snapshot => {
    'rootSigningKeyBase64': base64Encode(signing.publicKey),
    'rootEncryptionKeyBase64': base64Encode(encryption.publicKey),
  };
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
    'encryptionKeyBase64': base64Encode(encryption.publicKey),
  };
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected own-directory dependency');
}

class _Transport implements CollaborationTransport {
  late Map<String, dynamic> receipt;
  final certificates = <String, Map<String, dynamic>>{};
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
      diagnostic('owner_receipt', 'entered');
      lookups.add(params);
      return receipt;
    }
    if (operation == 'crypto2.records.batch') {
      diagnostic('owner_replay', 'entered');
      sent.add(params);
      return {};
    }
    if (operation == 'crypto2.exports.certificates.get') {
      diagnostic('incoming_verify', 'entered');
      return {'authorization': certificates[params['certificateHash']]};
    }
    throw StateError('Unexpected fixture RPC');
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
  _Access(this.signing, this.content, this.own, this.account);
  @override
  final AccountCryptoV2Workflow account;
  final _Own own;
  final KeyPair signing;
  final SecureKey content;
  final boundaries = <bool>[];
  String headHash = '1' * 64;
  @override
  Future<VerifiedScopeHead> currentHead(
    String scope, {
    bool online = false,
  }) async {
    diagnostic('current_head_check', 'entered');
    return _Head(headHash);
  }

  @override
  Future<VerifiedAccountDirectory> directoryAt({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    bool allowUnverifiedContact = false,
    bool online = false,
  }) async => own;
  @override
  Future<VerifiedAccountDirectory> currentMemberDirectory(
    String scopeId,
    String scopeHeadHash,
    String accountId,
  ) async => own;
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
    return CryptoReadContext(epoch: 1, accessRevision: 1, headHash: headHash);
  }

  @override
  Future<CryptoRecordAuthority> recordAuthority(Map<String, dynamic> r) async =>
      CryptoRecordAuthority(signingKey: signing.publicKey, currentEpoch: true);
  @override
  Future<CryptoKeyLease> recordKey(Map<String, dynamic> r) async {
    diagnostic('current_wire_open', 'entered');
    return CryptoKeyLease.borrowed(content);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected access dependency');
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(super.account, super.access, super.db, this.records, this.delivery);
  final CryptoRecordProofCodec records;
  final CryptoSyncRepository delivery;
  late Map<String, Object?> initial, current;
  int pulls = 0;
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
    diagnostic('current_pull', 'entered');
  }

  @override
  Future<Map<String, dynamic>> verifiedBusinessScopeDescriptor(
    String scope,
  ) async => {
    'kind': 'project',
    'parentScopeToken': await CryptoLifecycleEvidence(
      access,
    ).parentToken(_scope, _parent),
  };
}

class _Head implements VerifiedScopeHead {
  _Head(this.headHash);
  @override
  final String headHash;
  @override
  String get scopeId => _scope;
  @override
  int get accessRevision => 1;
  @override
  Map<String, dynamic> member(String accountId) => {'manageKeys': true};
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected fixture head dependency');
}

void diagnostic(
  String stage,
  String outcome, {
  Object? error,
  StackTrace? stack,
}) {
  final code = error is CryptoAuthorityPending ? error.reason : null;
  // No exception message, request, scope, record, payload, key or identifier.
  // The bounded diagnostic runner consumes this explicit machine protocol.
  // ignore: avoid_print
  print(
    'JIVIE_DIAGNOSTIC ${jsonEncode({'version': 1, 'stage': stage, 'outcome': outcome, if (error != null) 'errorType': error.runtimeType.toString(), if (code != null) 'code': code, if (stack != null) 'stack': stack.toString()})}',
  );
}

// This fixture controls trust-provider outputs and transport availability. It
// does not subclass choices, override verify, or inject a head-changed error.
// Both inner endorsement generations are fully verified at their matching head
// before the real materialize continuation opens the stale signed winner.
void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  for (final mode in [
    'conflict_stale',
    'applied_stale',
    'pending_unknown',
    'conflict_current',
  ]) {
    test('diagnostic production choice continuation $mode', () async {
      diagnostic('setup', 'entered');
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final signing = crypto.sodium.crypto.sign.keyPair();
      final encryption = crypto.sodium.crypto.box.keyPair();
      final content = crypto.sodium.secureRandom(32);
      addTearDown(() {
        signing.secretKey.dispose();
        encryption.secretKey.dispose();
        content.dispose();
      });
      final own = _Own(signing, encryption);
      final transport = _Transport();
      final directory = _Directory(own, transport, AccountDirectoryV2(crypto));
      final account = _Account(directory, encryption, crypto);
      final access = _Access(signing, content, own, account);
      final records = CryptoRecordProofCodec(crypto);
      final partition = directory.session.profile.partition;
      final store = CryptoSyncStore(db, partition);
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
      final runtime = _Runtime(account, access, db, records, delivery);
      final choices = CryptoFinanceAccountChoices(runtime);
      final address = runtime.address(
        _scope,
        'finance',
        CryptoFinanceAccountChoices.type,
        _manifest,
      );
      await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
        partition,
        '{}',
      ]);
      await db.execute('INSERT INTO scopes(partition,id,data) VALUES(?,?,?)', [
        partition,
        _scope,
        jsonEncode(
          SharedScope(
            id: _scope,
            name: 'Synthetic child',
            kind: SharedScopeKind.project,
            role: SharedRole.owner,
            parentScopeId: _parent,
            parentScopeKind: SharedScopeKind.organization,
            organizationId: _parent,
            projectRootId: _scope,
            accessPolicyVersion: 3,
          ).toJson(),
        ),
      ]);
      Future<String> hash(Object value) =>
          cryptoSha256(CryptoJson.encode(value));
      Future<Map<String, dynamic>> generation(String targetHead) async {
        const variant = CryptoFinanceAccountChoices.variant;
        final selectionContext = <String, dynamic>{
          'version': 2,
          'variant': variant,
          'purpose': CryptoFinanceAccountChoices.type,
          'serverId': _server,
          'sourceScopeId': _parent,
          'sourceHeadHash': 'a' * 64,
          'sourceCheckpoint': {
            'proofHash': 'b' * 64,
            'sequence': 1,
            'manifestHash': 'c' * 64,
          },
          'targetScopeId': _scope,
          'targetHeadHash': targetHead,
          'selectionCount': 0,
          'sourceRecordRoot': await cryptoSha256([
            ...utf8.encode('JivieFinanceAccountChoiceSource/v2\n'),
            ...CryptoJson.encode(<Object>[]),
          ]),
        };
        final salt = base64Encode(Uint8List(32));
        final selected = <Map<String, dynamic>>[];
        final offerBody = {
          ...selectionContext,
          'operation': 'crypto2.exports.offer',
          'selectionHash':
              await CryptoFinanceChoiceSelectionCodec.selectionHash(
                selectionContext,
                selected,
                salt,
              ),
          'accountId': _account,
          'deviceId': _device,
          'authorDirectoryHeadHash': own.headHash,
          'deviceSnapshotHash': own.deviceSnapshotHash,
        };
        final offer = crypto.signDomain(
          offerBody,
          signing.secretKey,
          CryptoScopedExports.offerDomain,
        );
        final recipient = {
          'accountId': _account,
          'deviceId': _device,
          'deviceSnapshotHash': own.deviceSnapshotHash,
          'encryptionPublicKeyBase64': base64Encode(encryption.publicKey),
        };
        final delegation = crypto.signDomain(
          {
            'version': 2,
            'operation': 'crypto2.exports.delegate',
            'requestId': _request,
            'serverId': _server,
            'accountId': _account,
            'deviceId': _device,
            'signer': 'device',
            'payload': {
              'variant': variant,
              'offerHash': await hash(offer),
              'scopeId': _scope,
              'membershipHeadHash': targetHead,
              'expectedAccessRevision': 1,
              'authorDirectoryHeadHash': own.headHash,
              'delegationId': _batch,
              'selectionHash': offerBody['selectionHash'],
              'issuerAccountId': _account,
              'issuerDirectoryHeadHash': own.headHash,
              'issuerRootSigningKeyBase64':
                  own.snapshot['rootSigningKeyBase64'],
              'issuerRootEncryptionKeyBase64':
                  own.snapshot['rootEncryptionKeyBase64'],
              'issuerIdentityEpochId': own.identityEpochId,
              'issuerDeviceSnapshotHash': own.deviceSnapshotHash,
              'bridgeRecipient': recipient,
            },
          },
          signing.secretKey,
          cryptoDirectoryDomain,
        );
        final selection = {
          'context': selectionContext,
          'choices': selected,
          'sourceRecords': <Object>[],
          'selectionSaltBase64': salt,
        };
        final envelope = {
          'context': {
            'variant': variant,
            'offerHash': await hash(offer),
            'delegationHash': await hash(delegation),
            'selectionHash': offerBody['selectionHash'],
            'requestId': _request,
            'recipient': recipient,
          },
          'selection': selection,
        };
        final certificate = crypto.signDomain(
          {
            ...offerBody,
            'operation': 'crypto2.exports.certificate',
            'offerHash': await hash(offer),
            'delegationHash': await hash(delegation),
            'bridge': {
              'requestId': _request,
              'sealedDisclosureBase64': base64Encode(
                crypto.sodium.crypto.box.seal(
                  message: Uint8List.fromList(
                    utf8.encode(jsonEncode(envelope)),
                  ),
                  publicKey: encryption.publicKey,
                ),
              ),
            },
          },
          signing.secretKey,
          CryptoScopedExports.certificateDomain,
        );
        transport.certificates[await hash(certificate)] = certificate;
        return {
          'version': 2,
          'variant': variant,
          'selection': selection,
          'offerAuthorization': offer,
          'delegationAuthorization': delegation,
          'certificateAuthorization': certificate,
        };
      }

      final stale = await generation('2' * 64),
          fresh = await generation('1' * 64);
      // New controls: prove both complete inner endorsements pass their real
      // verifier under the matching head, before reproducing a stale read.
      access.headHash = '2' * 64;
      expect(await choices.verify(stale, expectedScopeId: _scope), isEmpty);
      access.headHash = '1' * 64;
      expect(await choices.verify(fresh, expectedScopeId: _scope), isEmpty);
      diagnostic('incoming_verify', 'passed');
      Future<Map<String, dynamic>> seal(
        Map<String, dynamic> raw,
        String operation,
      ) async => records.sealRecord(
        serverId: _server,
        accountId: _account,
        deviceId: _device,
        batchId: _batch,
        scopeId: _scope,
        id: address.wireId,
        type: CryptoFinanceAccountChoices.type,
        expectedRevision: 1,
        epoch: 1,
        accessRevision: 1,
        membershipHeadHash: raw['selection']['context']['targetHeadHash'],
        domain: 'finance',
        contentContract: 3,
        operationId: operation,
        previousRecordHash: '3' * 64,
        deleted: false,
        plaintext: Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'format': 2,
              'identity': address.identity,
              'payload': raw,
            }),
          ),
        ),
        metadata: {
          'identity': address.identity,
          'references': <Object>[],
          'uniqueRefs': <Object>[],
          'blobIds': <Object>[],
          'auditState': {'version': 1, 'changedAt': '2026-10-21T00:00:00Z'},
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
            projectionToken: (r) async =>
                records.projectionGroupToken(r, content),
          );
      final ownerRaw = mode == 'applied_stale' ? stale : fresh;
      final ownerProof = await seal(ownerRaw, _ownerOperation);
      final signed = records.signCommand({
        'version': 2,
        'operation': 'crypto2.records.batch',
        'requestId': _request,
        'serverId': _server,
        'accountId': _account,
        'deviceId': _device,
        'signer': 'device',
        'payload': {
          'batchId': _batch,
          'records': [ownerProof],
          'commitment': await commitment(ownerProof),
        },
      }, signing.secretKey);
      final commandHash = await cryptoSha256(
        cryptoBase64(signed['commandBase64']),
      );
      final state = mode == 'pending_unknown'
          ? 'pending'
          : mode == 'applied_stale'
          ? 'applied'
          : 'rejected';
      transport.receipt = mode == 'pending_unknown'
          ? {'outcome': 'unknown'}
          : {
              'requestId': _request,
              'requestHash': commandHash,
              'authorization': signed,
              'status': state == 'applied' ? 200 : 409,
              'response': state == 'applied'
                  ? {
                      'status': 'applied',
                      'records': [
                        {
                          'scopeId': _scope,
                          'id': address.wireId,
                          'revision': 2,
                          'sequence': 2,
                        },
                      ],
                    }
                  : {'errorCode': 'conflict'},
            };
      await db.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state,response) VALUES(?,?,?,?,?,?,?)',
        [
          partition,
          _request,
          'crypto2.records.batch',
          jsonEncode(signed),
          commandHash,
          state,
          state == 'pending' ? null : jsonEncode(transport.receipt),
        ],
      );
      await db.execute(
        'INSERT INTO crypto_business_requests VALUES(?,?,?,?,?,?,?)',
        [
          partition,
          _ownerOperation,
          _scope,
          'finance',
          await hash(ownerRaw),
          _request,
          _manifest,
        ],
      );
      await db.execute(
        'INSERT INTO crypto_outbox_records VALUES(?,?,?,?,?,?)',
        [partition, _scope, 'finance', address.wireId, 1, _request],
      );
      // An applied owner's exact proof is the accepted revision-2 winner.
      // A rejected owner may have lost CAS to another authorized materializer.
      final winner = mode == 'applied_stale'
          ? ownerProof
          : await seal(
              mode == 'conflict_current' ? fresh : stale,
              _newOperation,
            );
      final winnerBody = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(winner['commandBase64'])) as Map,
      );
      final wire = {
        ...winnerBody,
        'revision': 2,
        'authorization': {
          'recordProof': winner,
          'batchCommitment': await commitment(winner),
        },
      };
      runtime.initial = {'crypto_revision': 1};
      runtime.current = {
        'id': address.wireId,
        'crypto_revision': 2,
        'deleted': 0,
        'record_proof_hash': await records.digest(winner),
        'projection': jsonEncode({'newDiagnosticProjection': true}),
      };
      await db.execute(
        'INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict) VALUES(?,?,?,?,?,?,?,?)',
        [
          partition,
          _scope,
          'finance',
          address.wireId,
          2,
          2,
          jsonEncode(wire),
          'verified',
        ],
      );
      Future<String> snapshot() async => jsonEncode([
        await db.rows('SELECT * FROM crypto_outbox'),
        await db.rows('SELECT * FROM crypto_outbox_records'),
        await db.rows('SELECT * FROM crypto_business_requests'),
        await db.rows('SELECT * FROM crypto_outbox_reconciliations'),
      ]);
      final before = await snapshot();
      String? observed;
      try {
        final result = await choices.materialize(
          _scope,
          offerAuthorization: Map<String, dynamic>.from(
            fresh['offerAuthorization'],
          ),
          delegationAuthorization: Map<String, dynamic>.from(
            fresh['delegationAuthorization'],
          ),
          certificateAuthorization: Map<String, dynamic>.from(
            fresh['certificateAuthorization'],
          ),
          operationId: _newOperation,
        );
        expect(mode, 'conflict_current');
        expect(result, {'newDiagnosticProjection': true});
      } on CryptoAuthorityPending catch (error, stack) {
        observed = error.reason;
        diagnostic('scenario_result', 'failed', error: error, stack: stack);
        if (mode == 'pending_unknown') {
          expect(error.reason, 'crypto_business_delivery_pending');
          expect(transport.sent, [signed]);
          expect(runtime.pulls, 0);
        } else {
          expect(error.reason, 'crypto_account_choices_head_changed');
          expect(
            stack.toString(),
            contains('CryptoFinanceAccountChoices._verifyManager'),
          );
          expect(
            stack.toString(),
            contains(
              'CryptoFinanceAccountChoices._reconcileMaterializationClaim',
            ),
          );
          expect(runtime.pulls, 1);
        }
      }
      if (mode != 'conflict_current') expect(observed, isNotNull);
      expect(await snapshot(), before);
      diagnostic('journal_immutable', 'passed');
      diagnostic('scenario_result', 'passed');
    });
  }
}
