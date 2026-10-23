import 'dart:async';
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
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Peer implements VerifiedAccountDirectory {
  _Peer(this.id, this.device, this.publicKey);
  final String id, device, publicKey;
  @override
  String get accountId => id;
  @override
  String get headHash => 'directory-head';
  @override
  int get generation => 1;
  @override
  String get rootFingerprint => 'root:$id';
  @override
  String get deviceSnapshotHash => 'devices:$id';
  @override
  bool includesAnchor(int generation, String hash) =>
      generation == 1 && hash == headHash;
  @override
  Map<String, dynamic> activeDevice(String id) {
    if (id != device) throw const FormatException('bad_device');
    return {'deviceId': device, 'signingKeyBase64': publicKey};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Directory implements AccountDirectoryRepository {
  _Directory(this.store, this.reducer, this.session, this.own);
  @override
  final CryptoIdentityStore store;
  @override
  final AccountDirectoryV2 reducer;
  @override
  final DeviceSession session;
  final _Peer own;
  bool current = true, oldHost = false;
  int calls = 0, writes = 0;
  Map<String, dynamic>? receipt;
  @override
  String get accountId => own.accountId;
  @override
  bool Function() get isCurrent =>
      () => current;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => own;
  @override
  Future<Map<String, dynamic>> call(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    calls++;
    if (params.containsKey('commandBase64')) writes++;
    if (op == 'capabilities')
      return {
        'serverId': session.profile.serverId,
        'invitationPreauthorizationVersions': oldHost ? [] : [1],
      };
    if (op == 'crypto2.invitations.resolve')
      return {
        'recipient': {'kind': 'email', 'value': params['recipient']},
      };
    if (op == 'crypto2.invitations.resolvePreauthorization')
      throw const CollaborationApiException(
        'crypto_invitation_recipient_unregistered',
      );
    if (op == 'crypto2.receipt.get') return receipt ?? {'outcome': 'unknown'};
    throw StateError('unexpected_autoapproval_transport:$op');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Head implements VerifiedScopeHead {
  _Head(this.scopeId, this.owner);
  @override
  final String scopeId;
  final String owner;
  String hash = 'source-head';
  final additional = <Map<String, dynamic>>[];
  final intents = <Map<String, dynamic>>[];
  @override
  String get headHash => hash;
  @override
  int get accessRevision => 1;
  @override
  List<Map<String, dynamic>> get members => [
    {'accountId': owner, 'manageKeys': true},
    ...additional,
  ];
  @override
  Map<String, dynamic> member(String id) =>
      members.singleWhere((m) => m['accountId'] == id);
  @override
  Map<String, dynamic> get body => {'membershipIntents': intents};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access extends SessionCryptoAccess {
  _Access(AccountCryptoV2Workflow account, this.head, this.peer)
    : super(account: account);
  final _Head head;
  final _Peer peer;
  @override
  Future<VerifiedScopeHead> currentHead(
    String id, {
    bool online = false,
  }) async => head;
  @override
  Future<VerifiedScopeHead> recoveryCandidateHead(String id) async => head;
  @override
  Future<VerifiedAccountDirectory> currentMemberDirectory(
    String scope,
    String hash,
    String account,
  ) async => peer;
  @override
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) => body();
}

class _Manager extends ScopeCryptoManager {
  _Manager(super.access, this.fixture);
  final _Fixture fixture;
  int reviewCreates = 0, receiptResumes = 0;
  String basis = 'verifiedCheckpoint';
  final reviews = <ScopeRotationReview>[];
  @override
  Future<List<ScopeRotationReview>> pendingRotationReviews(
    String scope,
  ) async => reviews;
  @override
  Future<ScopeRotationReview> reviewRotation(
    String scope, {
    Uint8List? recoveryFile,
    bool financeOnly = false,
    dynamic inheritedInvitationAdmission,
    dynamic preauthorizedInvitationAdmission,
    String? fixedReviewId,
  }) async {
    reviewCreates++;
    final r = ScopeRotationReview({
      'reviewId': fixedReviewId,
      'scopeId': scope,
      'sourceHeadHash': fixture.head.headHash,
      'historyBasis': basis,
      'domains': {},
    });
    reviews.add(r);
    return r;
  }

  @override
  Future<void> reconcileAppliedRotation({
    required String scopeId,
    required String reviewId,
    required String headHash,
    Future<void> Function()? beforeDisclosure,
  }) async {
    await beforeDisclosure?.call();
    receiptResumes++;
  }

  @override
  Future<Map<String, dynamic>> invitationCommand(
    String op,
    String scope,
    Map<String, dynamic> payload, {
    required String actionKey,
    String? deliveryToken,
  }) async {
    final request = fixture.crypto.randomId();
    final proof = fixture.crypto.signDomain(
      {
        'version': 2,
        'operation': op,
        'requestId': request,
        'serverId': fixture.profile.serverId,
        'accountId': fixture.profile.accountId,
        'deviceId': fixture.profile.deviceId,
        'signer': 'device',
        'payload': payload,
      },
      fixture.ownerKey.secretKey,
      cryptoDirectoryDomain,
    );
    await fixture.db
        .execute('INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)', [
          fixture.profile.partition,
          scope,
          request,
          'confirmed',
          CryptoJson.encode({}),
          CryptoJson.encode(proof),
        ]);
    await fixture.db.execute(
      'INSERT INTO crypto_membership_action_keys VALUES(?,?,?,?)',
      [fixture.profile.partition, scope, actionKey, request],
    );
    fixture.originalProof = proof;
    fixture.original = Map<String, dynamic>.from(payload);
    fixture.id = payload['invitationId'];
    return {
      'authorization': proof,
      'invitation': {
        'id': fixture.id,
        'scopeId': scope,
        'state': 'pending',
        'recipient': payload['recipient'],
        'role': payload['role'],
        'expiresAtEpoch': payload['expiresAt'],
      },
    };
  }
}

class _Repository extends InviteCryptoRepository {
  _Repository(super.access, this.fixture)
    : runtimeManager = _Manager(access, fixture);
  final _Fixture fixture;
  final _Manager runtimeManager;
  int admits = 0, acceptanceReads = 0, listReads = 0;
  bool changedRights = false,
      changeRightsAtDisclosure = false,
      lostAck = false,
      loseForegroundAtDisclosure = false;
  String? chosenReview;
  Completer<void>? policyGate;
  @override
  ScopeCryptoManager get manager => runtimeManager;
  @override
  Future<Map<String, dynamic>> foregroundInvitationRights(
    Map<String, dynamic> payload, {
    String? accountId,
  }) async {
    await policyGate?.future;
    return {
      'role': payload['role'],
      'financeRole': changedRights ? 'read' : 'write',
      'manageKeys': true,
      'policyVersion': 3,
      'descriptorHash': 'descriptor',
      'financePolicyHash': 'policy',
      'ownArchived': false,
      'inheritedArchived': false,
    };
  }

  @override
  Future<Map<String, dynamic>> dispatch(
    String op,
    Map<String, Object?> params,
  ) {
    if (op.endsWith('.list')) {
      listReads++;
      return Future.value({
        'invitations': [
          {'id': fixture.id, 'state': fixture.invitationState},
        ],
      });
    }
    return super.dispatch(op, params);
  }

  @override
  Future<VerifiedCryptoInvitation> acceptedRecipient(
    String scope,
    String id, {
    String? acceptanceProofHash,
  }) async {
    acceptanceReads++;
    if (acceptanceProofHash != null &&
        acceptanceProofHash != fixture.accepted.response['acceptanceProofHash'])
      throw const FormatException('invitation_acceptance_binding');
    return fixture.accepted;
  }

  @override
  Future<void> admit(
    VerifiedCryptoInvitation recipient,
    ScopeRotationReview review, {
    Future<void> Function(VerifiedCryptoInvitation)? beforeDisclosure,
    Future<void> Function()? freshDisclosureBoundary,
  }) async {
    chosenReview = review.id;
    if (changeRightsAtDisclosure) changedRights = true;
    if (loseForegroundAtDisclosure) fixture.foreground = false;
    await freshDisclosureBoundary?.call();
    await beforeDisclosure?.call(recipient);
    admits++;
    fixture.head.additional.add(
      Map<String, dynamic>.from(recipient.response['proposedMember'] as Map),
    );
    fixture.head.intents.add({
      'accountId': fixture.peer.accountId,
      'invitationId': fixture.id,
      'acceptanceProofHash': recipient.response['acceptanceProofHash'],
    });
    fixture.head.hash = 'activated-head';
    fixture.invitationState = 'consumed';
    if (lostAck) throw const CryptoAuthorityPending('scope_receipt_pending');
  }
}

class _Fixture {
  late CollaborationDatabase db;
  late CryptoCodec crypto;
  late KeyPair ownerKey, peerKey;
  late AccountSession profile;
  late _Directory directory;
  late _Peer peer;
  late _Head head;
  late _Access access;
  late _Repository repository;
  Map<String, dynamic> original = {}, originalProof = {};
  String id = '', invitationState = 'accepted';
  bool foreground = true;
  late VerifiedCryptoInvitation accepted;
  Future<void> open() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    crypto = CryptoCodec(await SodiumInit.init());
    ownerKey = crypto.sodium.crypto.sign.keyPair();
    peerKey = crypto.sodium.crypto.sign.keyPair();
    profile = AccountSession(
      serverUrl: 'https://auto.invalid',
      serverId: crypto.randomId(),
      accountId: crypto.randomId(),
      userId: 1,
      username: 'owner',
      displayName: 'Owner',
      deviceId: crypto.randomId(),
      expiresAt: DateTime.utc(2030),
    );
    final own = _Peer(
      profile.accountId,
      profile.deviceId,
      base64Encode(ownerKey.publicKey),
    );
    peer = _Peer(
      crypto.randomId(),
      crypto.randomId(),
      base64Encode(peerKey.publicKey),
    );
    directory = _Directory(
      CryptoIdentityStore(db, _Secure(), profile.partition),
      AccountDirectoryV2(crypto),
      DeviceSession(profile, 'synthetic'),
      own,
    );
    head = _Head(crypto.randomId(), profile.accountId);
    access = _Access(AccountCryptoV2Workflow(directory), head, peer);
    repository = _Repository(access, this);
  }

  Future<void> send({bool prepareAcceptance = true}) async {
    await repository.dispatch('invitations3.create', {
      'scopeId': head.scopeId,
      'recipient': 'new@example.invalid',
      'role': 'member',
      'requestId': crypto.randomId(),
    });
    if (prepareAcceptance) await accept();
  }

  Future<void> accept({String? creatorHash}) async {
    final proof = crypto.signDomain(
      {
        'version': 2,
        'operation': 'crypto2.invitations.accept',
        'requestId': crypto.randomId(),
        'serverId': profile.serverId,
        'accountId': peer.accountId,
        'deviceId': peer.device,
        'signer': 'device',
        'payload': {
          for (final k in [
            'scopeId',
            'invitationId',
            'role',
            'tokenHash',
            'expiresAt',
            'membershipHeadHash',
          ])
            k: original[k],
          'creatorProofHash':
              creatorHash ??
              await cryptoSha256(CryptoJson.encode(originalProof)),
          'authorDirectoryHeadHash': peer.headHash,
        },
      },
      peerKey.secretKey,
      cryptoDirectoryDomain,
    );
    accepted = VerifiedCryptoInvitation(
      {
        'invitation': {'id': id, 'scopeId': head.scopeId},
        'creatorAuthorization': proof,
        'acceptanceProofHash': await cryptoSha256(CryptoJson.encode(proof)),
        'proposedMember': {
          'accountId': peer.accountId,
          'role': 'member',
          'financeRole': 'write',
          'manageKeys': true,
        },
      },
      peer,
      const [],
    );
  }

  Future<ForegroundInvitationApprovalSummary> run() => repository
      .processForegroundAutoApprovals(isForegroundCurrent: () => foreground);
  Future<List<Map<String, dynamic>>> intents() => db.rows(
    "SELECT * FROM crypto_membership_intents WHERE partition=? AND state LIKE 'invitationForegroundApproval%'",
    [profile.partition],
  );
  Future<void> close() async {
    ownerKey.dispose();
    peerKey.dispose();
    await db.close();
  }
}

void main() {
  late _Fixture f;
  setUp(() async {
    f = _Fixture();
    await f.open();
  });
  tearDown(() => f.close());
  test(
    'foreground v4 new Send captures exact local intent and admits once after signed acceptance',
    () async {
      await f.send();
      final before = await f.intents();
      expect(before, hasLength(1));
      final result = await f.run();
      expect(result.completed, 1);
      expect(result.pending, 0);
      expect(f.repository.admits, 1);
      expect(
        (await f.intents()).single['state'],
        'invitationForegroundApprovalComplete',
      );
      expect((await f.run()).completed, 0);
      expect(f.repository.admits, 1);
    },
  );
  test(
    'foreground false and account invalid stop before any invitation read or grant',
    () async {
      await f.send();
      f.foreground = false;
      await expectLater(f.run(), throwsA(isA<CryptoAuthorityPending>()));
      expect(f.repository.listReads, 0);
      expect(f.repository.admits, 0);
      f.foreground = true;
      f.directory.current = false;
      await expectLater(f.run(), throwsA(isA<CryptoAuthorityPending>()));
      expect(f.repository.listReads, 0);
    },
  );
  test(
    'old host Send never captures automatic permission retroactively',
    () async {
      f.directory.oldHost = true;
      await f.send();
      expect(await f.intents(), isEmpty);
      expect((await f.run()).completed, 0);
      expect(f.repository.listReads, 0);
      expect(f.repository.admits, 0);
    },
  );
  test(
    'unsigned pending lifecycle never manufactures recipient consent',
    () async {
      await f.send();
      f.invitationState = 'pending';
      expect((await f.run()).completed, 0);
      expect(f.repository.acceptanceReads, 0);
      expect(f.repository.admits, 0);
    },
  );
  test(
    'different signed Send acceptance is rejected before inventory or keys',
    () async {
      await f.send();
      await f.accept(creatorHash: 'f' * 64);
      final r = await f.run();
      expect(r.pending, 1);
      expect(
        r.invitations.single.errorCode,
        'crypto_invitation_auto_acceptance',
      );
      expect(f.repository.runtimeManager.reviewCreates, 0);
      expect(f.repository.admits, 0);
    },
  );
  test('changed policy remains pending with original journal intact', () async {
    await f.send();
    final before = (await f.intents()).single['payload'];
    f.repository.changedRights = true;
    final r = await f.run();
    expect(
      r.invitations.single.errorCode,
      'crypto_invitation_auto_policy_changed',
    );
    expect(f.repository.admits, 0);
    final after =
        jsonDecode(
              utf8.decode(
                ((await f.intents()).single['payload'] as List).cast<int>(),
              ),
            )
            as Map;
    final original =
        jsonDecode(utf8.decode((before as List).cast<int>())) as Map;
    after.remove('lastExamined');
    expect(after, original);
  });
  test('reviewed recovery baseline never automatically approves', () async {
    await f.send();
    f.repository.runtimeManager.basis = 'reviewedRecoveryBaseline';
    final r = await f.run();
    expect(
      r.invitations.single.errorCode,
      'scope_review_confirmation_required',
    );
    expect(f.repository.admits, 0);
  });
  test(
    'unrelated manual inventory is never selected by same source head',
    () async {
      await f.send();
      f.repository.runtimeManager.reviews.add(
        ScopeRotationReview({
          'reviewId': 'manual-review',
          'scopeId': f.head.scopeId,
          'sourceHeadHash': f.head.headHash,
          'historyBasis': 'verifiedCheckpoint',
          'domains': {},
        }),
      );
      final saved =
          jsonDecode(
                utf8.decode(
                  ((await f.intents()).single['payload'] as List).cast<int>(),
                ),
              )
              as Map;
      expect((await f.run()).completed, 1);
      expect(f.repository.chosenReview, saved['reviewId']);
      expect(f.repository.chosenReview, isNot('manual-review'));
    },
  );
  test(
    'foreground loss at final disclosure leaves acceptance journal and never grants',
    () async {
      await f.send();
      f.repository.loseForegroundAtDisclosure = true;
      final r = await f.run();
      expect(
        r.invitations.single.errorCode,
        'crypto_invitation_foreground_required',
      );
      expect(f.repository.admits, 0);
      expect(
        (await f.intents()).single['state'],
        'invitationForegroundApproval',
      );
    },
  );
  test(
    'applied lost ACK restart verifies retained exact accept and resumes without reapproval',
    () async {
      await f.send();
      f.repository.lostAck = true;
      final first = await f.run();
      expect(first.pending, 1);
      expect(f.repository.admits, 1);
      final original = f.originalProof;
      final restarted = _Repository(f.access, f);
      f.repository = restarted;
      final second = await f.run();
      expect(second.completed, 1);
      expect(restarted.admits, 0);
      expect(restarted.acceptanceReads, 0);
      expect(restarted.runtimeManager.receiptResumes, 1);
      expect(f.originalProof, original);
    },
  );
  test('simultaneous foreground signals share no duplicate approval', () async {
    await f.send();
    final gate = Completer<void>();
    f.repository.policyGate = gate;
    final first = f.run();
    await Future<void>.delayed(Duration.zero);
    final second = await f.run();
    expect(second.completed, 0);
    gate.complete();
    expect((await first).completed, 1);
    expect(f.repository.admits, 1);
  });
  test(
    'new guard no captured intent never lists or accepts old invitations',
    () async {
      await f.send();
      await f.db.execute(
        "DELETE FROM crypto_membership_intents WHERE state='invitationForegroundApproval'",
      );
      expect((await f.run()).completed, 0);
      expect(f.repository.listReads, 0);
      expect(f.repository.admits, 0);
    },
  );
  test(
    'new guard unconfirmed original Send never sends or reads acceptance',
    () async {
      await f.send();
      await f.db.execute(
        "UPDATE crypto_membership_intents SET state='pending' WHERE authorization IS NOT NULL",
      );
      final r = await f.run();
      expect(r.invitations.single.errorCode, 'invitation_send_pending');
      expect(f.repository.listReads, 0);
      expect(f.repository.acceptanceReads, 0);
      expect(f.repository.admits, 0);
    },
  );
  test(
    'new guard fresh policy change at grant boundary stops sealed disclosure',
    () async {
      await f.send();
      f.repository.changeRightsAtDisclosure = true;
      final r = await f.run();
      expect(
        r.invitations.single.errorCode,
        'crypto_invitation_auto_policy_changed',
      );
      expect(f.repository.admits, 0);
    },
  );
  test(
    'new guard pinned acceptance cannot change across foreground restart',
    () async {
      await f.send();
      f.repository.loseForegroundAtDisclosure = true;
      expect((await f.run()).pending, 1);
      f.foreground = true;
      f.repository.loseForegroundAtDisclosure = false;
      await f.accept();
      final r = await f.run();
      expect(
        r.invitations.single.errorCode,
        'invitation_acceptance_binding',
      );
      expect(f.repository.admits, 0);
    },
  );
  test('new guard exact hint only routes its locally captured Send', () async {
    await f.send();
    final r = await f.repository.processForegroundAutoApprovals(
      isForegroundCurrent: () => true,
      invitationIds: {f.crypto.randomId()},
    );
    expect(r.completed, 0);
    expect(f.repository.listReads, 0);
  });
  test(
    'new guard fair backlog records examined cursor without changing signed Send',
    () async {
      await f.send();
      f.invitationState = 'pending';
      final proof = CryptoJson.encode(f.originalProof);
      expect((await f.run()).completed, 0);
      final metadata =
          jsonDecode(
                utf8.decode(
                  ((await f.intents()).single['payload'] as List).cast<int>(),
                ),
              )
              as Map;
      expect(metadata['lastExamined'], isA<int>());
      expect(CryptoJson.encode(f.originalProof), proof);
      expect(f.repository.admits, 0);
    },
  );
  for (final applied in [false, true]) {
    test(
      'new receipt-only ${applied ? 'applied' : 'unknown'} preserves exact original activation and never resends',
      () async {
        final request = f.crypto.randomId(),
            review = f.crypto.randomId(),
            scope = f.head.scopeId;
        final proof = f.crypto.signDomain(
          {
            'version': 2,
            'operation': 'crypto2.scope.activate',
            'requestId': request,
            'serverId': f.profile.serverId,
            'accountId': f.profile.accountId,
            'deviceId': f.profile.deviceId,
            'signer': 'device',
            'payload': {'scopeId': scope, 'headHash': 'exact-head'},
          },
          f.ownerKey.secretKey,
          cryptoDirectoryDomain,
        );
        final bytes = CryptoJson.encode(proof);
        await f.db.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
          [
            f.profile.partition,
            scope,
            '$review:published',
            'scopeRotationPublished',
            CryptoJson.encode({'reviewId': review, 'headHash': 'exact-head'}),
          ],
        );
        await f.db.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
          [
            f.profile.partition,
            scope,
            request,
            'pending',
            CryptoJson.encode({'foregroundInvitationId': 'routing-only'}),
            bytes,
          ],
        );
        if (applied)
          f.directory.receipt = {
            'outcome': 'applied',
            'status': 200,
            'requestId': request,
            'requestHash': await cryptoSha256(
              cryptoBase64(proof['commandBase64']),
            ),
            'authorization': proof,
            'response': {},
          };
        final action = ScopeCryptoManager(f.access).reconcileAppliedRotation(
          scopeId: scope,
          reviewId: review,
          headHash: 'exact-head',
        );
        if (applied) {
          await action;
        } else {
          await expectLater(
            action,
            throwsA(
              isA<CryptoAuthorityPending>().having(
                (e) => e.reason,
                'reason',
                'scope_receipt_pending',
              ),
            ),
          );
        }
        final row = (await f.db.rows(
          'SELECT state,authorization FROM crypto_membership_intents WHERE intent_id=?',
          [request],
        )).single;
        expect(row['state'], applied ? 'confirmed' : 'pending');
        expect(row['authorization'], bytes);
        expect(f.directory.writes, 0);
        expect(f.directory.calls, 1);
      },
    );
  }
  test(
    'new generic manager resume skips foreground automatic staged command',
    () async {
      final request = f.crypto.randomId();
      await f.db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
        [
          f.profile.partition,
          f.head.scopeId,
          request,
          'pending',
          CryptoJson.encode({'foregroundInvitationId': 'automatic'}),
          CryptoJson.encode({'commandBase64': 'not-even-decoded'}),
        ],
      );
      await ScopeCryptoManager(f.access).resume(f.head.scopeId);
      expect(f.directory.calls, 0);
      expect(f.directory.writes, 0);
    },
  );
}
