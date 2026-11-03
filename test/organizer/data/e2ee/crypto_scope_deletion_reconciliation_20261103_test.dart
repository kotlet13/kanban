import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_deletion.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_deletion_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

import 'crypto_checkpoint_supersession_20261102_test.dart'
    show reauthorizationFixture, scope;

// Real SQLite, signed membership, deletion leaf/header and account-event replay.
// The exact already-anchored scope and historical directory acquisition are
// seams here; the preserved real HTTP workflow separately exercises those.
class _Directory extends AccountDirectoryRepository {
  _Directory(AccountDirectoryRepository source)
    : super(
        reducer: source.reducer,
        session: source.session,
        transport: source.transport,
        store: source.store,
        isCurrent: source.isCurrent,
      );
  late VerifiedAccountDirectory before, after;
  late Map<String, dynamic> status;
  Object? statusFailure;
  bool current = true, freshBoundary = false, legacyDenied = false;
  bool loseSessionAfterStatus = false, includeEvent = true;
  int statusCalls = 0, freshReads = 0;
  @override
  bool Function() get isCurrent =>
      () => current;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async {
    if (freshBoundary) freshReads++;
    return freshBoundary && includeEvent ? after : before;
  }

  @override
  Future<Map<String, dynamic>> scopeAccessChanges(List<String> ids) async => {
    'accessChangesVersion': 1,
    'serverId': session.profile.serverId,
    'accountId': session.profile.accountId,
    'deviceId': session.profile.deviceId,
    'scopeIds': ids,
    'revokedScopeIds': legacyDenied ? ids : <String>[],
    'deletedScopeIds': <String>[],
  };
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (operation == 'crypto2.scopes.catalog') {
      return {'scopes': <Object>[], 'hasMore': false, 'nextAfterId': null};
    }
    if (operation != 'crypto2.scope.deletionStatus') {
      throw StateError('Unexpected operation $operation');
    }
    expect(params, {'scopeId': scope});
    statusCalls++;
    if (statusFailure != null) throw statusFailure!;
    if (loseSessionAfterStatus) current = false;
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(status)) as Map);
  }
}

class _Access extends SessionCryptoAccess {
  _Access({required super.account, required this.head});
  final VerifiedScopeHead head;
  bool anchorPresent = true;
  int invalidations = 0;
  _Directory get directory => account.directory as _Directory;
  @override
  Future<T> withVerifiedDeletedScope<T>(
    String scopeId,
    Map<String, dynamic> wire,
    Future<T> Function(VerifiedScopeHead head) action,
  ) async {
    if (!anchorPresent) {
      throw const CryptoAuthorityPending(
        'crypto_scope_deletion_history_pending',
      );
    }
    expect(scopeId, scope);
    expect(wire['headHash'], head.headHash);
    return action(head);
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
    expect(scopeId, scope);
    expect(scopeHeadHash, head.headHash);
    expect(accountId, directory.before.accountId);
    expect(online, true);
    if (directoryHeadHash == directory.before.headHash) return directory.before;
    if (directoryHeadHash == directory.after.headHash) return directory.after;
    throw const CryptoAuthorityPending('directory_proof_pending');
  }

  @override
  void invalidateAuthorityOperation() => invalidations++;
  @override
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) async {
    final previous = directory.freshBoundary;
    directory.freshBoundary = freshBoundary;
    try {
      return await body();
    } finally {
      directory.freshBoundary = previous;
    }
  }
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(super.account, super.access, super.db, this.commands);
  final CryptoSyncRepository commands;
  @override
  CryptoSyncRepository get queue => commands;
}

Future<dynamic> _fixture() async {
  final original = await reauthorizationFixture();
  final originalAccount = original.runtime.account as AccountCryptoV2Workflow;
  final directory = _Directory(originalAccount.directory);
  directory.before = await originalAccount.directory.requireFresh();
  final account = AccountCryptoV2Workflow(directory);
  final head = original.access.head as VerifiedScopeHead;
  final access = _Access(account: account, head: head);
  final runtime = _Runtime(
    account,
    access,
    original.runtime.database,
    original.runtime.queue,
  );
  final crypto = directory.reducer.crypto;
  final requestId = crypto.randomId();
  final certificate = {
    'version': 2,
    'serverId': directory.before.serverId,
    'rootScopeId': scope,
    'requestId': requestId,
    'actorAccountId': directory.before.accountId,
    'actorDeviceId': account.deviceId,
    'scopes': [
      {
        'scopeId': scope,
        'headHash': head.headHash,
        'accessRevision': head.accessRevision,
        'lifecycleHash': '1' * 64,
      },
    ],
    'graphRoot': '2' * 64,
    'graphCount': 1,
    'retention': CryptoScopeDeletionCodec.retention,
  };
  Map<String, dynamic> sign(Map<String, dynamic> value, String domain) =>
      crypto.signDomain(value, original.access.signing.secretKey, domain);
  Future<String> hash(Map value) => cryptoSha256(CryptoJson.encode(value));
  final certificateProof = sign(
    certificate,
    CryptoScopeDeletionCodec.certificateDomain,
  );
  final header = <String, dynamic>{
    'version': 2,
    'serverId': directory.before.serverId,
    'requestId': requestId,
    'actorAccountId': directory.before.accountId,
    'actorDeviceId': account.deviceId,
    'authorDirectoryHeadHash': directory.before.headHash,
    'privateCertificateHash': await hash(certificateProof),
    'rootToken': await CryptoScopeDeletionCodec.rootToken(certificate),
    'graphRoot': certificate['graphRoot'],
    'graphCount': 1,
    'retention': CryptoScopeDeletionCodec.retention,
    'scopeLeafRoot': '0' * 64,
    'scopeLeafCount': 1,
  };
  final leafProof = sign({
    'version': 2,
    'serverId': directory.before.serverId,
    'requestId': requestId,
    'headerContextHash': await CryptoScopeDeletionCodec.headerContext(header),
    ...((certificate['scopes'] as List).single as Map<String, dynamic>),
  }, CryptoScopeDeletionCodec.leafDomain);
  final leafDigest = await hash(leafProof);
  header['scopeLeafRoot'] = await CryptoScopeDeletionCodec.leafRoot(header, [
    leafDigest,
  ]);
  final headerProof = sign(header, CryptoScopeDeletionCodec.headerDomain);
  final event = await directory.reducer.prepare(
    previous: directory.before,
    serverId: directory.before.serverId,
    accountId: directory.before.accountId,
    deviceId: account.deviceId,
    identityEpochId: directory.before.identityEpochId,
    operation: 'crypto2.account.scopeDeletion',
    signer: 'device',
    requestId: requestId,
    pinnedRootFingerprint: directory.before.rootFingerprint,
    signingKey: original.access.signing.secretKey,
    payload: {
      'scopeToken': header['rootToken'],
      'certificateHash': await hash(headerProof),
    },
  );
  directory.after = event.result;
  final payload = {
    'certificateProof': certificateProof,
    'headerProof': headerProof,
    'scopeProofs': [leafProof],
    'accountEventProof': event.authorization,
    'authorDirectoryHeadHash': directory.before.headHash,
  };
  final result = {
    'deleted': true,
    'scopeId': scope,
    'deletedScopeIds': [scope],
    'records': <Object>[],
    'financeRecords': <Object>[],
    'certificateHash': await hash(headerProof),
    'headerProof': headerProof,
    'eventAuthorization': event.authorization,
    'eventHeadHash': event.result.headHash,
    'eventCommandHash': await cryptoSha256(
      cryptoBase64(event.authorization['commandBase64']),
    ),
  };
  directory.status = {
    ...result,
    'leafProof': leafProof,
    'leafDigests': [leafDigest],
    'membershipHead': {'headHash': head.headHash},
  };
  await runtime.database.execute(
    'INSERT OR IGNORE INTO accounts(partition,profile) VALUES(?,?)',
    [runtime.partition, jsonEncode(directory.session.profile.toJson())],
  );
  await runtime.database.execute(
    'INSERT INTO scopes(partition,id,data) VALUES(?,?,?)',
    [
      runtime.partition,
      scope,
      jsonEncode({
        'id': scope,
        'name': 'Retained household',
        'deleted': false,
        'revoked': false,
      }),
    ],
  );
  await runtime.database.execute(
    'INSERT INTO local_meta(name,value) VALUES(?,?)',
    [
      'scope_deletion_pending:${runtime.partition}:$scope:scope',
      jsonEncode({
        'request': {'scopeId': scope, 'requestId': requestId},
        'preview': {'previewHash': '2' * 64},
      }),
    ],
  );
  await runtime.database.execute(
    'INSERT INTO crypto_export_drafts(partition,scope_id,action_id,payload) VALUES(?,?,?,?)',
    [
      runtime.partition,
      scope,
      'scopeDeletion:$requestId',
      jsonEncode({
        'scopeId': scope,
        'previewHash': '2' * 64,
        'payload': payload,
      }),
    ],
  );
  return (
    runtime: runtime,
    directory: directory,
    access: access,
    payload: payload,
    result: result,
    requestId: requestId,
  );
}

Future<String> _protectedRows(dynamic fixture) async => jsonEncode({
  for (final table in [
    'scopes',
    'crypto_outbox',
    'crypto_export_drafts',
    'local_meta',
  ])
    table: await fixture.runtime.database.rows(
      'SELECT * FROM $table ORDER BY rowid',
    ),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'omitted encrypted household recovers through signed deletion evidence and keeps journals',
    () async {
      final f = await _fixture();
      final original = await _protectedRows(f);
      final result = await f.runtime.scopes();
      expect(result['deletedScopeIds'], [scope]);
      expect(result['revokedScopeIds'], [scope]);
      expect(f.directory.statusCalls, 1);
      expect(await _protectedRows(f), original);
    },
  );

  for (final problem in [
    'bad_signature',
    'wrong_scope',
    'missing_anchor',
    'bad_event',
    'malformed',
    'forbidden',
  ]) {
    test('omission cannot delete household with $problem evidence', () async {
      final f = await _fixture();
      if (problem == 'bad_signature') {
        f.directory.status['headerProof'] = {
          ...f.directory.status['headerProof'] as Map,
          'signatureBase64': base64Encode(List<int>.filled(64, 0)),
        };
        f.directory.status['certificateHash'] = await cryptoSha256(
          CryptoJson.encode(f.directory.status['headerProof']),
        );
      }
      if (problem == 'wrong_scope') {
        f.directory.status['scopeId'] = '90000000-0000-4000-8000-000000000009';
      }
      if (problem == 'missing_anchor') f.access.anchorPresent = false;
      if (problem == 'bad_event') {
        f.directory.status['eventHeadHash'] = 'f' * 64;
      }
      if (problem == 'malformed') f.directory.status = <String, dynamic>{};
      if (problem == 'forbidden') {
        f.directory.statusFailure = const CollaborationException('forbidden');
      }
      final original = await _protectedRows(f);
      final result = await f.runtime.scopes();
      expect(result['deletedScopeIds'], isEmpty);
      expect(result['revokedScopeIds'], isEmpty);
      expect(f.directory.statusCalls, 1);
      expect(await _protectedRows(f), original);
    });
  }

  test('deletion discovery propagates authentication loss', () async {
    final f = await _fixture();
    f.directory.statusFailure = const CollaborationException('session_expired');
    final original = await _protectedRows(f);
    await expectLater(
      f.runtime.scopes(),
      throwsA(
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'session_expired',
        ),
      ),
    );
    expect(await _protectedRows(f), original);
  });

  test(
    'deletion discovery cannot apply proof after session replacement',
    () async {
      final f = await _fixture();
      f.directory.loseSessionAfterStatus = true;
      final original = await _protectedRows(f);
      await expectLater(
        f.runtime.scopes(),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(await _protectedRows(f), original);
    },
  );

  test(
    'resolved legacy denial does not request unrelated deletion evidence',
    () async {
      final f = await _fixture();
      f.directory.legacyDenied = true;
      final result = await f.runtime.scopes();
      expect(result['revokedScopeIds'], [scope]);
      expect(result['deletedScopeIds'], isEmpty);
      expect(f.directory.statusCalls, 0);
    },
  );

  test(
    'previously confirmed deletion does not repeat witness discovery',
    () async {
      final f = await _fixture();
      await f.runtime.database.execute('UPDATE scopes SET data=?', [
        jsonEncode({'id': scope, 'deleted': true, 'revoked': true}),
      ]);
      final original = await _protectedRows(f);
      final result = await f.runtime.scopes();
      expect(result['deletedScopeIds'], isEmpty);
      expect(f.directory.statusCalls, 0);
      expect(await _protectedRows(f), original);
    },
  );

  for (final included in [true, false]) {
    test(
      'exact applied deletion receipt needs fresh verified event inclusion=$included',
      () async {
        final f = await _fixture();
        f.directory.includeEvent = included;
        await f.runtime.queue.enqueueCommand(
          actionKey: 'scopeDeletion:${f.requestId}',
          operation: 'crypto2.scope.delete',
          requestId: f.requestId,
          payload: f.payload,
        );
        final row = await f.runtime.queue.store.outgoing(f.requestId);
        await f.runtime.queue.store.outcome(f.requestId, 'applied', {
          'requestId': f.requestId,
          'requestHash': row['request_hash'],
          'authorization': jsonDecode(row['signed_body'] as String),
          'status': 200,
          'response': f.result,
        });
        final original = await _protectedRows(f);
        final action = CryptoBusinessDeletion(f.runtime).dispatch(
          'scopes.delete',
          {'scopeId': scope, 'requestId': f.requestId, 'previewHash': '2' * 64},
        );
        if (included) {
          expect(await action, f.result);
        } else {
          await expectLater(
            action,
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                'crypto_scope_deletion_event_inclusion',
              ),
            ),
          );
        }
        expect(f.access.invalidations, 1);
        expect(f.directory.freshReads, 1);
        expect(await _protectedRows(f), original);
      },
    );
  }
}
