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
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/recovery_file_codec.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

String _scope(int n) =>
    '40000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

class _Database extends CollaborationDatabase {
  _Database() : super(NativeDatabase.memory());
  void Function(List<Object?>)? afterIntent;
  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) async {
    await super.execute(sql, args);
    if (sql.startsWith('INSERT INTO crypto_membership_intents')) {
      afterIntent?.call(args);
    }
  }
}

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
  }) async => throw StateError('No native/network operations allowed');
  @override
  void close() {}
}

class _Directory extends AccountDirectoryRepository {
  _Directory({
    required super.reducer,
    required super.session,
    required super.store,
    required bool Function() current,
  }) : super(transport: _NoNetwork(), isCurrent: current);
  late VerifiedAccountDirectory verified;
  late Map<String, dynamic> status;
  final scopes = <String>[];
  final calls = <String>[];
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => verified;
  @override
  Future<VerifiedAccountDirectory> cachedVerifiedDirectory() async => verified;
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    calls.add(operation);
    if (operation == 'crypto2.account.status') return status;
    if (operation == 'crypto2.scopes.catalog') {
      final after = params['afterId'] as String?;
      final rest = scopes
          .where((s) => after == null || s.compareTo(after) > 0)
          .toList();
      final page = rest.take(params['limit'] as int).toList();
      return {
        'scopes': [
          for (final s in page) {'id': s},
        ],
        'hasMore': page.length < rest.length,
        if (page.length < rest.length) 'nextAfterId': page.last,
      };
    }
    throw StateError('Forbidden operation $operation');
  }
}

class _Head implements VerifiedScopeHead {
  _Head(this.scopeId, this.owner, {this.canManage = true});
  @override
  final String scopeId;
  final String owner;
  final bool canManage;
  @override
  String get headHash => 'a' * 64;
  @override
  Map<String, dynamic> member(String id) => {
    'accountId': owner,
    'role': canManage ? 'owner' : 'editor',
    'manageKeys': canManage,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager implements ScopeCryptoManager {
  _Manager(this.access);
  @override
  final SessionCryptoAccess access;
  final reviews = <String, ScopeRotationReview>{};
  final failures = <String, Object>{};
  final prepared = <String>[];
  final confirmed = <String>[];
  Future<void> Function(String)? onConfirm;
  @override
  Future<List<ScopeRotationReview>> pendingRotationReviews(
    String scopeId,
  ) async => [if (reviews[scopeId] != null) reviews[scopeId]!];
  @override
  Future<ScopeRotationReview> reviewRotation(
    String scopeId, {
    Uint8List? recoveryFile,
    bool financeOnly = false,
    dynamic inheritedInvitationAdmission,
    dynamic preauthorizedInvitationAdmission,
    String? fixedReviewId,
  }) async {
    expect(recoveryFile, isNull);
    prepared.add(scopeId);
    return reviews[scopeId] = ScopeRotationReview({
      'reviewId': scopeId,
      'scopeId': scopeId,
      'sourceHeadHash': 'a' * 64,
      'historyBasis': 'verifiedCheckpoint',
      'domains': {},
    });
  }

  // Keep the production confirmation signature while checking its consent
  // argument at this explicit manager boundary.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #confirmRotation) {
      return (() async {
        final review =
            invocation.positionalArguments.single as ScopeRotationReview;
        expect(invocation.namedArguments[#acceptedCandidateHistory], isFalse);
        confirmed.add(review.scopeId);
        await onConfirm?.call(review.scopeId);
        if (failures[review.scopeId] != null) throw failures[review.scopeId]!;
        if (review.historyBasis == 'reviewedRecoveryBaseline') {
          throw const CryptoAuthorityPending(
            'scope_review_confirmation_required',
          );
        }
        return _Head(review.scopeId, access.account.directory.accountId)
            as VerifiedScopeHead;
      })();
    }
    throw StateError('Unexpected manager operation ${invocation.memberName}');
  }
}

class _Batch extends AccountProtectionReady {
  _Batch(super.account, this.manager);
  final _Manager manager;
  CryptoScopeObservations? recovery;
  @override
  CryptoScopeObservations scopeObservations() =>
      recovery ?? super.scopeObservations();
  final heads = <String, _Head>{};
  final failures = <String, Object>{};
  final reads = <String>[];
  @override
  ScopeCryptoManager scopeManager(SessionCryptoAccess access) => manager;
  @override
  Future<List<Map<String, dynamic>>> catalog() async => [
    for (final h in heads.values)
      {'id': h.scopeId, 'headHash': h.headHash, 'cryptoState': 'active'},
  ];
  @override
  Future<({VerifiedScopeHead head, bool stale})> readScopeMembers(
    SessionCryptoAccess access,
    String scopeId,
  ) async {
    reads.add(scopeId);
    if (failures[scopeId] != null) throw failures[scopeId]!;
    return (head: heads[scopeId]!, stale: true);
  }
}

class _RecoveryAccess extends SessionCryptoAccess {
  _RecoveryAccess({required super.account});
  final attempts = <String>[];
  final savedAttempts = <String>[];
  @override
  Future<void> hydrateExistingCandidateKeys(String scopeId) async {
    savedAttempts.add(scopeId);
    await during?.call(scopeId);
    if (failures[scopeId] != null) throw failures[scopeId]!;
  }

  final failures = <String, Object>{};
  Uint8List? expectedFile;
  Future<void> Function(String)? during;
  @override
  Future<void> recoverScopeCandidateKeys(
    String scopeId,
    Uint8List externalFile,
  ) async {
    expect(identical(externalFile, expectedFile), isTrue);
    attempts.add(scopeId);
    await during?.call(scopeId);
    if (failures[scopeId] != null) throw failures[scopeId]!;
  }
}

class _Observations extends CryptoScopeObservations {
  _Observations(super.account, this.access, {super.isCurrent});
  final _RecoveryAccess access;
  @override
  SessionCryptoAccess scopeAccess() => access;
  @override
  Future<List<Map<String, dynamic>>> recover(
    String? scope, {
    VerifiedAccountDirectory? readOnlyOwnPrefix,
    bool descriptorHistory = false,
  }) async => [];
}

class _BlockedRecovery extends CryptoScopeObservations {
  _BlockedRecovery(super.account);
  @override
  Future<void> resumeObservedScopesFromSavedKeys() async =>
      throw const CryptoScopeRecoveryIncomplete(
        pendingScopes: 1,
        unmatchedOwnAnchors: 0,
        discoveryPending: false,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CryptoCodec crypto;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  late CollaborationDatabase db;
  late AccountCryptoV2Workflow account;
  late _Directory directory;
  late AccountRecoveryMaterial material;
  late bool current;
  Future<void> fixture() async {
    current = true;
    db = _Database();
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://batch.invalid/',
        serverId: crypto.randomId(),
        accountId: crypto.randomId(),
        deviceId: crypto.randomId(),
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic-session',
    );
    final files = RecoveryFileCodec(crypto);
    material = files.create(
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
    );
    final root = files.open(
      file: material.file,
      encryptedRoot: material.encryptedRoot,
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
      expectedFingerprint: material.fingerprint,
    );
    final sign = crypto.sodium.crypto.sign.keyPair();
    final box = crypto.sodium.crypto.box.keyPair();
    final reducer = AccountDirectoryV2(crypto);
    late PreparedDirectoryMutation genesis;
    try {
      genesis = await reducer.prepare(
        previous: null,
        serverId: session.profile.serverId,
        accountId: session.profile.accountId,
        deviceId: session.profile.deviceId,
        identityEpochId: crypto.randomId(),
        operation: 'crypto2.account.initialize',
        signer: 'root',
        pinnedRootFingerprint: material.fingerprint,
        signingKey: root.signing.secretKey,
        payload: {
          'rootSigningKeyBase64': base64Encode(material.signingPublicKey),
          'rootEncryptionKeyBase64': base64Encode(material.encryptionPublicKey),
          'deviceSigningKeyBase64': base64Encode(sign.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
          'keyringCiphertextBase64': base64Encode(
            CryptoJson.encode(material.encryptedRoot),
          ),
        },
      );
    } finally {
      root.dispose();
      sign.dispose();
      box.dispose();
    }
    final store = CryptoIdentityStore(db, _Secure(), session.profile.partition);
    await store.pinRoot(
      session.profile.accountId,
      session.profile.serverId,
      material.fingerprint,
      genesisFingerprint: material.fingerprint,
    );
    await store.append(session.profile.accountId, genesis.entry);
    await store.remember(genesis.result, 'verified');
    directory =
        _Directory(
            reducer: reducer,
            session: session,
            store: store,
            current: () => current,
          )
          ..verified = genesis.result
          ..status = {
            'keyringCiphertextBase64': base64Encode(
              CryptoJson.encode(material.encryptedRoot),
            ),
          };
    account = AccountCryptoV2Workflow(directory);
    addTearDown(() async {
      material.dispose();
      await db.close();
    });
  }

  _Batch batchFixture() {
    final manager = _Manager(SessionCryptoAccess(account: account));
    final batch = _Batch(account, manager);
    for (var i = 1; i <= 3; i++) {
      batch.heads[_scope(i)] = _Head(
        _scope(i),
        directory.accountId,
        canManage: i != 3,
      );
    }
    addTearDown(batch.close);
    return batch;
  }

  Future<void> pending(_Batch batch) => expectLater(
    batch.complete(),
    throwsA(
      isA<CryptoAuthorityPending>().having(
        (e) => e.reason,
        'reason',
        'protection_scope_action_required',
      ),
    ),
  );

  test(
    'account batch retains candidate review and continues eligible later owner',
    () async {
      await fixture();
      final batch = batchFixture();
      final review = ScopeRotationReview({
        'reviewId': 'retained',
        'scopeId': _scope(1),
        'sourceHeadHash': 'a' * 64,
        'historyBasis': 'reviewedRecoveryBaseline',
        'domains': {
          'content': {'count': 1},
        },
      });
      batch.manager.reviews[_scope(1)] = review;
      await pending(batch);
      expect(batch.reads, [_scope(1), _scope(2), _scope(3)]);
      expect(batch.manager.prepared, [_scope(2)]);
      expect(batch.manager.confirmed, [_scope(1), _scope(2)]);
      expect(identical(batch.manager.reviews[_scope(1)], review), isTrue);
      expect(await batch.pendingScopeActions(), [
        {
          'scopeId': _scope(1),
          'canManage': true,
          'reason': 'scope_review_confirmation_required',
        },
        {
          'scopeId': _scope(3),
          'canManage': false,
          'reason': 'scope_rotation_required',
        },
      ]);
      expect(await account.store.pending(), isEmpty);
      expect(directory.calls, isEmpty);
    },
  );

  test('old-head saved review never replaces fresh per-scope review', () async {
    await fixture();
    final batch = batchFixture();
    batch.manager.reviews[_scope(1)] = ScopeRotationReview({
      'reviewId': 'old',
      'scopeId': _scope(1),
      'sourceHeadHash': 'b' * 64,
      'historyBasis': 'reviewedRecoveryBaseline',
      'domains': {},
    });
    await pending(batch);
    expect(batch.manager.prepared, [_scope(1), _scope(2)]);
    expect(batch.manager.reviews[_scope(1)]!.sourceHeadHash, 'a' * 64);
    expect((await batch.pendingScopeActions()).map((v) => v['scopeId']), [
      _scope(3),
    ]);
  });

  test(
    'invalid first scope proof does not authorize it or stop other owner',
    () async {
      await fixture();
      final batch = batchFixture();
      batch.failures[_scope(1)] = const FormatException('private proof data');
      await pending(batch);
      expect(batch.manager.confirmed, [_scope(2)]);
      expect((await batch.pendingScopeActions()).first, {
        'scopeId': _scope(1),
        'canManage': false,
        'reason': 'scope_proof_unavailable',
      });
      expect(batch.reads, [_scope(1), _scope(2), _scope(3)]);
    },
  );

  test(
    'scope-specific policy blocker is retained exactly while later owner progresses',
    () async {
      await fixture();
      final batch = batchFixture();
      batch.manager.failures[_scope(1)] = const CryptoAuthorityPending(
        'scope_review_policy_projection_pending',
      );
      await pending(batch);
      expect(batch.manager.confirmed, [_scope(1), _scope(2)]);
      expect(
        (await batch.pendingScopeActions()).first['reason'],
        'scope_review_policy_projection_pending',
      );
    },
  );

  test(
    'account session invalidation immediately stops scope progression',
    () async {
      await fixture();
      final batch = batchFixture();
      batch.manager.onConfirm = (_) async => current = false;
      await expectLater(
        batch.complete(),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'protection_completion_cancelled',
          ),
        ),
      );
      expect(batch.reads, [_scope(1)]);
      expect(batch.manager.confirmed, [_scope(1)]);
      expect(directory.calls, isEmpty);
    },
  );

  test(
    'incomplete saved-key verification cannot sign account completion',
    () async {
      await fixture();
      final batch = batchFixture()
        ..heads.clear()
        ..recovery = _BlockedRecovery(account);
      await db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          account.store.partition,
          directory.accountId,
          'fileScopeRecoverySummary',
          'scopeRecoveryPending',
          CryptoJson.encode({'pendingScopes': 1}),
        ],
      );
      await expectLater(
        batch.complete(),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'crypto_scope_recovery_incomplete',
          ),
        ),
      );
      expect(directory.calls, isEmpty);
      expect(await account.store.pending(), isEmpty);
      expect(await account.hasIncompleteScopeRecovery(), isTrue);
    },
  );

  Future<void> unfinished() => db.execute(
    'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
    [
      account.store.partition,
      directory.accountId,
      'fileScopeRecoverySummary',
      'scopeRecoveryPending',
      CryptoJson.encode({'pendingScopes': 1}),
    ],
  );

  test(
    'saved keys reverify all unfinished scope routes without another FILE selection',
    () async {
      await fixture();
      await unfinished();
      directory.scopes.addAll([for (var i = 1; i <= 25; i++) _scope(i)]);
      final access = _RecoveryAccess(account: account);
      await _Observations(account, access).resumeObservedScopesFromSavedKeys();
      expect(access.savedAttempts, directory.scopes);
      expect(access.attempts, isEmpty);
      expect(await account.hasIncompleteScopeRecovery(), isFalse);
      expect(directory.calls.toSet(), {'crypto2.scopes.catalog'});
    },
  );

  test(
    'missing saved key retains exact obligation while other saved scopes progress',
    () async {
      await fixture();
      await unfinished();
      directory.scopes.addAll([_scope(1), _scope(2), _scope(3)]);
      final access = _RecoveryAccess(account: account);
      access.failures[_scope(1)] = const CryptoAuthorityPending(
        'scope_key_recovery_required',
      );
      await expectLater(
        _Observations(account, access).resumeObservedScopesFromSavedKeys(),
        throwsA(
          isA<CryptoScopeRecoveryIncomplete>().having(
            (e) => e.pendingScopes,
            'pending',
            1,
          ),
        ),
      );
      expect(access.savedAttempts.toSet(), directory.scopes.toSet());
      expect(access.attempts, isEmpty);
      expect(await account.hasIncompleteScopeRecovery(), isTrue);
      expect(directory.calls.toSet(), {'crypto2.scopes.catalog'});
    },
  );

  test(
    'closing foreground owner at bounded pass boundary stops later scopes',
    () async {
      await fixture();
      directory.scopes.addAll([for (var i = 1; i <= 25; i++) _scope(i)]);
      final access = _RecoveryAccess(account: account)
        ..expectedFile = material.file;
      var foregroundCurrent = true;
      (db as _Database).afterIntent = (args) {
        if (args[2] == 'fileScopeRecoverySummary') {
          final payload =
              CryptoJson.decode(
                    Uint8List.fromList((args[4] as List).cast<int>()),
                  )
                  as Map;
          if (payload['pendingScopes'] == 5) foregroundCurrent = false;
        }
      };
      await expectLater(
        _Observations(
          account,
          access,
          isCurrent: () => foregroundCurrent,
        ).hydrateAllAvailableObservedScopes(material.file),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'scope_recovery_identity_changed',
          ),
        ),
      );
      expect(access.attempts, directory.scopes.take(20).toList());
      expect(
        directory.calls.where((c) => c == 'crypto2.account.status'),
        hasLength(1),
      );
      expect(await account.hasIncompleteScopeRecovery(), isTrue);
      final summary = await db.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND intent_id='fileScopeRecoverySummary'",
        [account.store.partition],
      );
      expect(
        (CryptoJson.decode(
              Uint8List.fromList(
                (summary.single['payload'] as List).cast<int>(),
              ),
            )
            as Map)['pendingScopes'],
        5,
      );
      expect(
        current,
        isTrue,
        reason: 'Only foreground controller closed, not account session',
      );
    },
  );

  test(
    'single FILE selection drains more than one bounded scope page',
    () async {
      await fixture();
      directory.scopes.addAll([for (var i = 1; i <= 45; i++) _scope(i)]);
      final access = _RecoveryAccess(account: account)
        ..expectedFile = material.file;
      final before = Uint8List.fromList(material.file);
      await _Observations(
        account,
        access,
      ).hydrateAllAvailableObservedScopes(material.file);
      expect(access.attempts, directory.scopes);
      expect(material.file, before);
      expect(await account.hasIncompleteScopeRecovery(), isFalse);
      expect(directory.calls.toSet(), {
        'crypto2.account.status',
        'crypto2.scopes.catalog',
      });
    },
  );

  test(
    'blocked early scopes retain exact obligations while later keys progress',
    () async {
      await fixture();
      directory.scopes.addAll([for (var i = 1; i <= 45; i++) _scope(i)]);
      final access = _RecoveryAccess(account: account)
        ..expectedFile = material.file;
      for (var i = 1; i <= 20; i++) {
        access.failures[_scope(i)] = const CryptoAuthorityPending(
          'scope_key_recovery_required',
        );
      }
      await expectLater(
        _Observations(
          account,
          access,
        ).hydrateAllAvailableObservedScopes(material.file),
        throwsA(
          isA<CryptoScopeRecoveryIncomplete>().having(
            (e) => e.pendingScopes,
            'pending',
            20,
          ),
        ),
      );
      expect(access.attempts.toSet(), directory.scopes.toSet());
      final verified = await db.rows(
        "SELECT scope_id FROM crypto_membership_intents WHERE partition=? AND intent_id='fileScopeRecoveryRoute' AND json_extract(CAST(payload AS TEXT),'\$.verifiedRunId') IS NOT NULL",
        [account.store.partition],
      );
      expect(verified.length, 25);
      expect(await account.hasIncompleteScopeRecovery(), isTrue);
      expect(access.attempts.length, lessThanOrEqualTo(105));
    },
  );

  test('FILE batch rejects different root before any scope recovery', () async {
    await fixture();
    directory.scopes.add(_scope(1));
    final other = account.files.create(
      serverId: directory.session.profile.serverId,
      accountId: directory.accountId,
    );
    addTearDown(other.dispose);
    final access = _RecoveryAccess(account: account)..expectedFile = other.file;
    await expectLater(
      _Observations(
        account,
        access,
      ).hydrateAllAvailableObservedScopes(other.file),
      throwsFormatException,
    );
    expect(access.attempts, isEmpty);
    expect(directory.calls, isEmpty);
  });

  test(
    'FILE batch session change cannot clear pending scope summary',
    () async {
      await fixture();
      directory.scopes.addAll([_scope(1), _scope(2)]);
      final access = _RecoveryAccess(account: account)
        ..expectedFile = material.file
        ..during = (_) async => current = false;
      await expectLater(
        _Observations(
          account,
          access,
        ).hydrateAllAvailableObservedScopes(material.file),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(access.attempts, [_scope(1)]);
      expect(await account.hasIncompleteScopeRecovery(), isTrue);
    },
  );

  test(
    'scope action reader sanitizes legacy persisted untrusted reason',
    () async {
      await fixture();
      await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'protectionReady:${account.store.partition}:${account.deviceId}:scopeAction',
        jsonEncode({
          'scopeId': _scope(1),
          'canManage': true,
          'reason': 'private-user-error https://secret.invalid',
        }),
      ]);
      final batch = AccountProtectionReady(account);
      expect(await batch.pendingScopeActions(), [
        {
          'scopeId': _scope(1),
          'canManage': true,
          'reason': 'scope_proof_unavailable',
        },
      ]);
      expect(
        (await batch.pendingScopeAction())!['reason'],
        'scope_proof_unavailable',
      );
      batch.close();
    },
  );
}
