import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_task_resolution.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

const _partition = 'empty-reconciliation-fixture';
const _scope = '11111111-1111-4111-a111-111111111111';

class _Directory implements AccountDirectoryRepository {
  @override
  bool Function() get isCurrent =>
      () => true;
  @override
  String get accountId => 'owner';
  @override
  Future<T> withAuthoritySnapshot<T>(
    Future<T> Function() body, {
    required Future<bool> Function() isValid,
    required void Function() onMutation,
  }) => body();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No transport or directory proof expected at this seam');
}

class _Account implements AccountCryptoV2Workflow {
  @override
  final directory = _Directory();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No key or account mutation expected');
}

class _Head implements VerifiedScopeHead {
  @override
  Map<String, dynamic> member(String account) => {'financeRole': 'read'};
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Read-only contributor has no reconciliation writes');
}

class _Access extends SessionCryptoAccess {
  _Access() : super(account: _Account());
  final boundaries = <bool>[];
  Zone? pullZone, headZone;
  int heads = 0, keyAdmissions = 0;
  Object? denied;
  @override
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) {
    boundaries.add(freshBoundary);
    return super.withVerifiedOperation(body, freshBoundary: freshBoundary);
  }

  @override
  Future<void> ensureScopeReadKeys(String scopeId, String domain) async {
    keyAdmissions++;
    pullZone = Zone.current;
  }

  @override
  Future<CryptoReadContext> readContext(String scopeId, String domain) async =>
      const CryptoReadContext(
        epoch: 1,
        accessRevision: 1,
        headHash: 'verified-read-head',
      );
  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async {
    heads++;
    headZone = Zone.current;
    if (denied != null) throw denied!;
    return _Head();
  }
}

class _Queue implements CryptoSyncRepository {
  var pulls = 0;
  @override
  Future<void> pull({
    required String scopeId,
    required String domain,
    required int accessRevision,
  }) async {
    expect(scopeId, _scope);
    expect(domain, 'finance');
    expect(accessRevision, 1);
    pulls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No other queue operation allowed');
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(_Access access, CollaborationDatabase db)
    : super(access.account, access, db);
  final verifiedQueue = _Queue();
  @override
  String get p => _partition;
  @override
  CryptoSyncRepository get queue => verifiedQueue;
}

void main() {
  late CollaborationDatabase db;
  late _Access access;
  late _Runtime runtime;
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    access = _Access();
    runtime = _Runtime(access, db);
  });
  tearDown(() async => db.close());
  Future<void> row(
    String id, {
    String partition = _partition,
    String scope = _scope,
    String domain = 'finance',
    String type = 'financeEntry',
    bool deleted = false,
    Map<String, dynamic> raw = const {'taskId': 'task'},
  }) => db.execute(
    'INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,?,?,?,1,?,?,?,?,?)',
    [
      partition,
      scope,
      domain,
      id,
      type,
      'a' * 64,
      deleted ? 1 : 0,
      jsonEncode(raw),
      '{}',
      'verifiedCheckpoint',
    ],
  );

  // The queue/read proof boundary is controlled; the real pullVerified flow,
  // actual authority leases, SQL candidate selection and reconciliation run.
  // These tests do not claim to replace encrypted queue/verifier coverage.
  test(
    'empty finance pull retains admission and queue pull but reads no reconciliation head',
    () async {
      access.denied = const CryptoAuthorityPending(
        'unexpected_reconciliation_head',
      );
      await runtime.pullVerified(_scope, 'finance', attest: false);
      expect(access.keyAdmissions, 1);
      expect(runtime.verifiedQueue.pulls, 1);
      expect(access.heads, 0);
      expect(access.boundaries, [false]);
    },
  );

  test(
    'nonempty candidate keeps a fresh authority lease and the existing contributor role gate',
    () async {
      await row('entry');
      await runtime.pullVerified(_scope, 'finance', attest: false);
      expect(access.heads, 1);
      expect(access.headZone, isNot(same(access.pullZone)));
      expect(access.boundaries, [false, true]);
      expect(runtime.verifiedQueue.pulls, 1);
      expect(
        (await db.rows(
          'SELECT raw_payload FROM crypto_business_records',
        )).single['raw_payload'],
        jsonEncode({'taskId': 'task'}),
      );
    },
  );

  test('eligible work still propagates current authority denial', () async {
    await row('entry');
    access.denied = const CryptoAuthorityPending('scope_membership_missing');
    await expectLater(
      runtime.pullVerified(_scope, 'finance', attest: false),
      throwsA(same(access.denied)),
    );
    expect(access.heads, 1);
    expect(access.headZone, isNot(same(access.pullZone)));
    expect(
      await db.rows('SELECT id FROM crypto_business_records'),
      hasLength(1),
    );
  });

  test(
    'exact iterator exclusions skip no work and a later personal entry is considered next pull',
    () async {
      await row('other-partition', partition: 'other');
      await row('other-scope', scope: 'other');
      await row('content', domain: 'content');
      await row('account', type: 'financeAccount');
      await row('deleted', deleted: true);
      await row('null-task', raw: {'taskId': null});
      await row('no-task', raw: {});
      await runtime.pullVerified(_scope, 'finance', attest: false);
      expect(access.heads, 0);
      expect(
        await cryptoTaskDerivationPages(db, _partition, _scope).toList(),
        isEmpty,
      );
      await row('late-personal', type: 'personalFinanceEntry');
      await runtime.pullVerified(_scope, 'finance', attest: false);
      expect(access.heads, 1);
      expect(runtime.verifiedQueue.pulls, 2);
      final pages = await cryptoTaskDerivationPages(
        db,
        _partition,
        _scope,
      ).toList();
      expect(pages.single.single['id'], 'late-personal');
    },
  );
}
