import 'dart:typed_data';
import 'dart:convert';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_policy_actions.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_topology.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inherited_invitation_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inherited_invitation_grants.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _recipient = '22222222-2222-4222-8222-222222222222';
const _parent = '33333333-3333-4333-8333-333333333333';
const _child = '44444444-4444-4444-8444-444444444444';
const _invitation = '55555555-5555-4555-8555-555555555555';
final _proof = 'a' * 64;

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String partition) async => values[partition];
  @override
  Future<void> write(String partition, String value) async {
    values[partition] = value;
  }
}

class _Directory implements AccountDirectoryRepository {
  _Directory(this.store);
  @override
  final CryptoIdentityStore store;
  bool current = true;
  int calls = 0;
  AccountDirectoryV2? testReducer;
  final owner = _Peer(_owner);
  @override
  AccountDirectoryV2 get reducer => testReducer!;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => owner;
  List<Map<String, dynamic>> catalog = [];
  @override
  String get accountId => _owner;
  @override
  bool Function() get isCurrent =>
      () => current;
  @override
  DeviceSession get session => DeviceSession(
    AccountSession(
      serverUrl: 'https://sharing.example.test',
      serverId: _parent,
      accountId: _owner,
      userId: 1,
      username: 'owner',
      displayName: 'Owner',
      deviceId: _owner,
      expiresAt: DateTime(2030),
    ),
    'synthetic',
  );
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    calls++;
    if (operation != 'crypto2.scopes.catalog') throw StateError(operation);
    return {'scopes': catalog, 'hasMore': false};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account implements AccountCryptoV2Workflow {
  _Account(CryptoIdentityStore store) : directory = _Directory(store);
  @override
  final _Directory directory;
  @override
  CryptoIdentityStore get store => directory.store;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Peer implements VerifiedAccountDirectory {
  _Peer([this.id = _recipient]);
  final String id;
  String hash = 'directory-head';
  bool hasAncestor = true;
  String snapshotHashValue = 'device-snapshot';
  @override
  String get rootFingerprint => 'same-root';
  @override
  int get generation => hash == 'directory-head' ? 1 : 2;
  @override
  bool includesAnchor(int generation, String hash) =>
      hasAncestor && generation == 1 && hash == 'directory-head';
  @override
  String get accountId => id;
  @override
  String get headHash => hash;
  @override
  String get deviceSnapshotHash => snapshotHashValue;
  @override
  String get identityEpochId => 'identity';
  @override
  Map<String, dynamic> get snapshot => {
    'rootSigningKeyBase64': 'signing',
    'rootEncryptionKeyBase64': 'encryption',
    'recoveryRootEpochId': 'recovery',
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _member(
  String id, {
  String role = 'member',
  String finance = 'write',
  bool manage = true,
}) => {
  'accountId': id,
  'role': role,
  'financeRole': finance,
  'manageKeys': manage,
  'rootSigningKeyBase64': 'signing',
  'rootEncryptionKeyBase64': 'encryption',
  'recoveryRootEpochId': 'recovery',
  'identityEpochId': 'identity',
  'directoryHeadHash': 'directory-head',
  'deviceSnapshotHash': 'device-snapshot',
};

class _Head implements VerifiedScopeHead {
  _Head(String id, List<Map<String, dynamic>> members, {bool admission = false})
    : body = {
        'scopeId': id,
        'epoch': 2,
        'accessRevision': 2,
        'previousHeadHash': 'genesis',
        'members': members,
        'membershipIntents': admission
            ? [
                {
                  'accountId': _recipient,
                  'invitationId': _invitation,
                  'acceptanceProofHash': _proof,
                },
              ]
            : <Map<String, dynamic>>[],
        'accessBasis': [
          {'scopeToken': 'basis', 'accessRevision': 2},
        ],
      };
  @override
  final Map<String, dynamic> body;
  String hash = 'head';
  @override
  String get headHash => hash;
  @override
  String get scopeId => body['scopeId'];
  @override
  int get accessRevision => body['accessRevision'];
  @override
  int get epoch => body['epoch'];
  @override
  bool get active => true;
  @override
  List<Map<String, dynamic>> get members =>
      (body['members'] as List).cast<Map<String, dynamic>>();
  @override
  Map<String, dynamic> member(String id) => members.singleWhere(
    (m) => m['accountId'] == id,
    orElse: () =>
        throw const CryptoDirectoryException('scope_membership_missing'),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access extends SessionCryptoAccess {
  _Access(_Account account) : super(account: account);
  late _Head parent, child;
  final peer = _Peer();
  bool mockKnownIdentities = false;
  Map<String, _Peer> oldPrefixes = {};
  @override
  Future<void> requireExistingScopeMemberIdentity(
    VerifiedScopeHead head,
    VerifiedAccountDirectory directory,
  ) async {
    if (!mockKnownIdentities) {
      await super.requireExistingScopeMemberIdentity(head, directory);
    }
  }

  @override
  Future<VerifiedAccountDirectory> directoryAt({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    bool online = false,
    bool allowUnverifiedContact = false,
  }) async {
    if (mockKnownIdentities) return oldPrefixes[accountId]!;
    return super.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: scopeHeadHash,
      accountId: accountId,
      directoryHeadHash: directoryHeadHash,
      online: online,
      allowUnverifiedContact: allowUnverifiedContact,
    );
  }

  Map<String, dynamic> parentPolicy = {
    'kind': 'organization',
    'accessPolicyVersion': 3,
  };
  late Map<String, dynamic> childPolicy;
  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async => scopeId == _parent ? parent : child;
  @override
  Future<VerifiedScopeHead> recoveryCandidateHead(String scopeId) async =>
      child;
  @override
  Future<Map<String, dynamic>> verifiedScopeDescriptor(
    String scopeId, {
    bool online = false,
  }) async => scopeId == _parent ? parentPolicy : childPolicy;
  @override
  Future<VerifiedAccountDirectory> currentMemberDirectory(
    String scopeId,
    String headHash,
    String accountId,
  ) async =>
      accountId == _owner ? (account.directory as _Directory).owner : peer;
  @override
  Future<CryptoReadContext> readContext(String scopeId, String domain) async =>
      CryptoReadContext(
        epoch: parent.epoch,
        accessRevision: parent.accessRevision,
        headHash: parent.headHash,
      );
  @override
  VerifiedScopeHead verifiedCandidateAncestor(String hash) =>
      throw const CryptoAuthorityPending('scope_prefix_pending');
}

class _Lifecycle extends CryptoLifecycleEvidence {
  _Lifecycle(super.access);
  bool archived = false;
  @override
  Future<Map<String, dynamic>> forRecoveryReview(
    String scopeId, {
    required String sourceHeadHash,
    required bool financeOnly,
  }) async => {
    'scopeId': scopeId,
    'headHash': 'lifecycle',
    'ownArchived': archived,
    'inheritedArchived': false,
  };
}

class _Finance extends CryptoFinancePolicyActions {
  _Finance(super.context);
  bool enabled = true;
  @override
  Future<CryptoFinancePolicySnapshot> readVerified(String scope) async =>
      CryptoFinancePolicySnapshot(
        enabled: enabled,
        revision: 1,
        requiredContractVersion: 3,
        grants: [
          {'accountId': _owner, 'grant': 'write'},
        ],
      );
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(super.account, super.access, super.db);
  Map<String, dynamic>? topology;
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {}
  @override
  Future<bool> hasReusableCheckpoint(
    String scope,
    String domain,
    CryptoReadContext read,
  ) async => true;
  @override
  Future<String> reservedRecordId(String scope, String namespace) async =>
      scope;
  @override
  Future<Map<String, Object?>?> record(
    String scopeId,
    String domain,
    String id, {
    String? type,
  }) async => {
    'deleted': 0,
    'raw_payload': jsonEncode({'financeTopology': topology}),
  };
}

void main() {
  late CollaborationDatabase db;
  late _Account account;
  late _Access access;
  late _Lifecycle lifecycle;
  late _Finance finance;
  late _Runtime runtime;
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    account = _Account(CryptoIdentityStore(db, _Secure(), 'synthetic'));
    access = _Access(account);
    lifecycle = _Lifecycle(access);
    finance = _Finance(CryptoBusinessSession(account, access, db));
    runtime = _Runtime(account, access, db);
    runtime.topology = await CryptoFinanceTopology.create(
      serverId: _parent,
      scopeId: _parent,
      childTokens: [
        await CryptoFinanceTopology.childToken(_parent, _parent, _child),
      ],
    );
    access.parent = _Head(_parent, [
      _member(_owner, role: 'owner'),
      _member(_recipient),
    ], admission: true);
    access.child = _Head(_child, [_member(_owner, role: 'owner')]);
    access.childPolicy = {
      'kind': 'project',
      'accessPolicyVersion': 3,
      'parentScopeToken': await lifecycle.parentToken(_child, _parent),
    };
    account.directory.catalog = [
      {
        'id': _child,
        'parentScopeId': _parent,
        'headHash': access.child.headHash,
        'expectedAccessRevision': 2,
        'accessBasis': access.child.body['accessBasis'],
        'members': access.child.members,
      },
    ];
  });
  tearDown(() async => db.close());
  Future<VerifiedInheritedInvitationAdmission> verify() =>
      VerifiedInheritedInvitationAdmission.verify(
        access: access,
        parentScopeId: _parent,
        childScopeId: _child,
        invitationId: _invitation,
        acceptanceProofHash: _proof,
        recipientAccountId: _recipient,
        lifecycleService: lifecycle,
        financePolicyService: finance,
      );
  for (final change in [
    'replaced-device',
    'revoked-device',
    'identity',
    'recovery',
    'root',
    'role',
    'finance',
    'manage',
    'roster',
    'revision',
    'basis',
    'policy',
    'unrelated-prefix',
    'prefix-device',
  ]) {
    test(
      'inherited draft resume rejects $change without changing keys or requests',
      () async {
        account.directory.testReducer = AccountDirectoryV2(
          CryptoCodec(await SodiumInit.init()),
        );
        account.directory.owner.hash = 'directory-advanced';
        access.peer.hash = 'directory-advanced';
        access.mockKnownIdentities = true;
        access.oldPrefixes = {_owner: _Peer(_owner), _recipient: _Peer()};
        final capability = await verify();
        final recorded = [_member(_owner, role: 'owner'), _member(_recipient)];
        final body = <String, dynamic>{
          'members': recorded,
          'financePolicyIntentProof': null,
          'accessIntentProof': null,
          'expectedAccessRevision': 2,
          'accessBasis': access.child.body['accessBasis'],
          'authorDirectoryHeadHash': 'directory-head',
        };
        switch (change) {
          case 'replaced-device':
            recorded.last['deviceSnapshotHash'] = 'new-device';
          case 'revoked-device':
            recorded.last['deviceSnapshotHash'] = 'revoked-device';
          case 'identity':
            recorded.last['identityEpochId'] = 'other-identity';
          case 'recovery':
            recorded.last['recoveryRootEpochId'] = 'other-recovery';
          case 'root':
            recorded.last['rootSigningKeyBase64'] = 'other-root';
          case 'role':
            recorded.last['role'] = 'viewer';
          case 'finance':
            recorded.last['financeRole'] = 'none';
          case 'manage':
            recorded.last['manageKeys'] = false;
          case 'roster':
            recorded.add(_member(_invitation));
          case 'revision':
            body['expectedAccessRevision'] = 3;
          case 'basis':
            body['accessBasis'] = [];
          case 'policy':
            body['financePolicyIntentProof'] = {'changed': true};
          case 'unrelated-prefix':
            access.peer.hasAncestor = false;
          case 'prefix-device':
            access.oldPrefixes[_recipient]!.snapshotHashValue =
                'old-revoked-snapshot';
        }
        final review = ScopeRotationReview({
          'reviewId': _invitation,
          'scopeId': _child,
          'sourceHeadHash': access.child.headHash,
          'historyBasis': 'observedCheckpointHistory',
          'domains': <String, dynamic>{},
        });
        await db.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
          [
            'synthetic',
            _child,
            _invitation,
            'scopeRotationReview',
            CryptoJson.encode(review.value),
          ],
        );
        await db.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
          [
            'synthetic',
            _child,
            'retained-draft',
            'scopeRotationDraft',
            CryptoJson.encode({
              'reviewId': _invitation,
              'headHash': 'original-head',
              'body': body,
            }),
          ],
        );
        final before = await db.rows(
          'SELECT * FROM crypto_membership_intents ORDER BY intent_id',
        );
        final calls = account.directory.calls;
        await expectLater(
          ScopeCryptoManager(access).confirmRotation(
            review,
            acceptedCandidateHistory: true,
            members: capability.members,
            inheritedInvitationAdmission: capability,
          ),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'scope_rotation_reauthorization_required',
            ),
          ),
        );
        final after = await db.rows(
          'SELECT * FROM crypto_membership_intents ORDER BY intent_id',
        );
        expect(
          base64Encode(CryptoJson.encodeDerivedState(before)) ==
              base64Encode(CryptoJson.encodeDerivedState(after)),
          isTrue,
        );
        expect(await db.rows('SELECT 1 FROM crypto_scope_keys'), isEmpty);
        expect(
          account.directory.calls - calls,
          lessThanOrEqualTo(3),
          reason:
              'Only read-only catalog checks may run; fixture rejects every mutation',
        );
      },
    );
  }
  final changed = isA<CryptoAuthorityPending>().having(
    (e) => e.reason,
    'reason',
    'crypto_inherited_invitation_changed',
  );

  test(
    'verified parent admission adds only its recipient and preserves owner',
    () async {
      final proof = await verify();
      expect(proof.member['role'], 'member');
      expect(proof.member['financeRole'], 'write');
      expect(proof.member['manageKeys'], true);
      expect(proof.members.map((m) => m['accountId']), [_owner, _recipient]);
      expect(proof.members.first['role'], 'owner');
      expect(proof.alreadyAvailable, false);
    },
  );
  test('wrong signed parent token blocks disclosure', () async {
    access.childPolicy['parentScopeToken'] = 'b' * 64;
    await expectLater(
      verify(),
      throwsA(
        isA<CryptoAuthorityPending>().having(
          (e) => e.reason,
          'reason',
          'crypto_inherited_invitation_parent',
        ),
      ),
    );
  });
  test(
    'catalog membership cannot replace a signed parent invitation intent',
    () async {
      access.parent.body['membershipIntents'] = <Map<String, dynamic>>[];
      access.parent.body['epoch'] = 1;
      await expectLater(verify(), throwsA(changed));
    },
  );
  test(
    'parent role viewer grants viewer with finance read and no management',
    () async {
      access.parent.member(_recipient)['role'] = 'viewer';
      final proof = await verify();
      expect(proof.member['role'], 'viewer');
      expect(proof.member['financeRole'], 'read');
      expect(proof.member['manageKeys'], false);
    },
  );
  test(
    'existing direct owner is preserved through parent member admission',
    () async {
      access.child.members.add(_member(_recipient, role: 'owner'));
      final proof = await verify();
      expect(proof.member['role'], 'owner');
    },
  );
  test('disabled verified policy grants no finance keys', () async {
    finance.enabled = false;
    expect((await verify()).member['financeRole'], 'none');
  });
  test('signed archived lifecycle limits finance access to read', () async {
    lifecycle.archived = true;
    expect((await verify()).member['financeRole'], 'read');
  });
  test('parent proof changed after review blocks continuation', () async {
    final proof = await verify();
    // Preserve original immutable head object as real verified heads do.
    access.parent = _Head(_parent, access.parent.members, admission: true)
      ..hash = 'replacement2';
    await expectLater(
      proof.revalidate(access: access, source: access.child),
      throwsA(changed),
    );
  });
  test('same account new device snapshot cannot be marked available', () async {
    access.child.members.add(_member(_recipient));
    access.peer.snapshotHashValue = 'new-device';
    access.parent.member(_recipient)['deviceSnapshotHash'] = 'new-device';
    expect((await verify()).alreadyAvailable, false);
  });
  test(
    'directory device snapshot outside signed parent approval stays pending',
    () async {
      access.peer.snapshotHashValue = 'unapproved-snapshot';
      await expectLater(verify(), throwsA(changed));
    },
  );
  test(
    'live effective revision mismatch prevents false already-available success',
    () async {
      access.child.members.add(_member(_recipient));
      account.directory.catalog.single['expectedAccessRevision'] = 3;
      expect((await verify()).alreadyAvailable, false);
    },
  );
  test(
    'exact active roster and live revision is idempotently available',
    () async {
      access.child.members.add(_member(_recipient));
      expect((await verify()).alreadyAvailable, true);
    },
  );
  test('proposed unrelated addition is rejected before wrappers', () async {
    final proof = await verify();
    await expectLater(
      proof.revalidate(
        access: access,
        source: access.child,
        proposedMembers: [...proof.members, _member(_invitation)],
      ),
      throwsA(changed),
    );
  });
  test('child-only invitation never creates inherited work', () async {
    final service = CryptoInheritedInvitationGrants(access, runtime: runtime);
    await service.prepare(
      parentScopeId: _child,
      invitationId: _invitation,
      recipientAccountId: _recipient,
      acceptanceProofHash: _proof,
    );
    expect(await service.pending(), isEmpty);
  });
  test(
    'same prepared parent grant keeps one payload-only durable journal',
    () async {
      final service = CryptoInheritedInvitationGrants(access, runtime: runtime);
      for (var attempt = 0; attempt < 2; attempt++) {
        await service.prepare(
          parentScopeId: _parent,
          invitationId: _invitation,
          recipientAccountId: _recipient,
          acceptanceProofHash: _proof,
        );
      }
      final rows = await db.rows(
        "SELECT * FROM crypto_membership_intents WHERE state='invitationInheritedGrants'",
      );
      expect(rows, hasLength(1));
      expect(rows.single['authorization'], isNull);
      expect((await service.pending()).single['children'], [_child]);
    },
  );
  test(
    'catalog omission of required signed child keeps access pending',
    () async {
      account.directory.catalog = [];
      final service = CryptoInheritedInvitationGrants(access, runtime: runtime);
      await expectLater(
        service.prepare(
          parentScopeId: _parent,
          invitationId: _invitation,
          recipientAccountId: _recipient,
          acceptanceProofHash: _proof,
        ),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'crypto_inherited_invitation_pending',
          ),
        ),
      );
      expect(await service.pending(), isEmpty);
    },
  );
  test(
    'catalog wrong-parent hint cannot hide a required signed child',
    () async {
      account.directory.catalog.single['parentScopeId'] = _invitation;
      final service = CryptoInheritedInvitationGrants(access, runtime: runtime);
      await service.prepare(
        parentScopeId: _parent,
        invitationId: _invitation,
        recipientAccountId: _recipient,
        acceptanceProofHash: _proof,
      );
      expect((await service.pending()).single['children'], [_child]);
    },
  );
  test(
    'required child with a different signed parent never receives keys',
    () async {
      access.childPolicy['parentScopeToken'] = 'wrong-parent';
      final service = CryptoInheritedInvitationGrants(access, runtime: runtime);
      await expectLater(
        service.prepare(
          parentScopeId: _parent,
          invitationId: _invitation,
          recipientAccountId: _recipient,
          acceptanceProofHash: _proof,
        ),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'crypto_inherited_invitation_parent',
          ),
        ),
      );
      expect(await service.pending(), isEmpty);
    },
  );
  test('missing authenticated child inventory remains pending', () async {
    runtime.topology = null;
    final service = CryptoInheritedInvitationGrants(access, runtime: runtime);
    await expectLater(
      service.prepare(
        parentScopeId: _parent,
        invitationId: _invitation,
        recipientAccountId: _recipient,
        acceptanceProofHash: _proof,
      ),
      throwsA(
        isA<CryptoAuthorityPending>().having(
          (e) => e.reason,
          'reason',
          'crypto_inherited_invitation_pending',
        ),
      ),
    );
  });
  test(
    'restored empty journal cannot claim success without signed parent admission',
    () async {
      access.parent.body['membershipIntents'] = <Map<String, dynamic>>[];
      access.parent.body['epoch'] = 1;
      await db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          'synthetic',
          _parent,
          'inherited:$_invitation',
          'invitationInheritedGrants',
          CryptoJson.encode({
            'version': 1,
            'parentScopeId': _parent,
            'invitationId': _invitation,
            'recipientAccountId': _recipient,
            'acceptanceProofHash': _proof,
            'children': <String>[],
          }),
        ],
      );
      final service = CryptoInheritedInvitationGrants(access, runtime: runtime);
      await expectLater(service.finish(_parent, _invitation), throwsA(changed));
      expect(await service.pending(), hasLength(1));
    },
  );
  test(
    'completed continuation retry has no network or duplicate grant',
    () async {
      await db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          'synthetic',
          _parent,
          'inherited:$_invitation',
          'invitationInheritedGrantsComplete',
          Uint8List(0),
        ],
      );
      final before = account.directory.calls;
      await CryptoInheritedInvitationGrants(
        access,
      ).finish(_parent, _invitation);
      expect(account.directory.calls, before);
    },
  );
}
