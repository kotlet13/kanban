import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_documents.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import '../../support/synthetic_content_route_guard.dart';
import '../collaboration_repository_test.dart'
    show FakeServer, MemorySessionStore;

class _UnusedRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) =>
      throw StateError('Synthetic legacy seam must stay in fixture transport');
}

class _UnusedAccount implements AccountCryptoV2Workflow {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No account/HTTP calls at verified projection seam');
}

class _UnusedAccess implements SessionCryptoAccess {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No authority calls at verified projection seam');
}

/// Supplies already verified projection rows, with the real SQL page adapter.
/// This is a routing/cursor test, not a cryptographic proof or native test.
class _Runtime extends CryptoBusinessSession {
  _Runtime(CollaborationDatabase db, this.fixturePartition)
    : super(_UnusedAccount(), _UnusedAccess(), db);
  final String fixturePartition;
  int verifiedPulls = 0;
  Object? verifiedFailure;
  @override
  String get p => fixturePartition;
  // Synthetic authority metadata only. The real SQL paging/completeness marker
  // is exercised; neither these values nor the fixture bypass proves authority.
  @override
  Future<Map<String, dynamic>> financePolicy(String scope) async => {
    'revision': 7,
  };
  @override
  Future<Map<String, dynamic>> organizationFinanceCoverage(
    String scope, {
    bool refreshRootFinance = false,
    String? expectedHeadHash,
  }) async => {
    'organizationFinanceComplete': false,
    'organizationFinanceScopeIds': <String>[],
    'organizationFinanceSequences': <String, int>{},
  };
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {
    verifiedPulls++;
    if (verifiedFailure != null) throw verifiedFailure!;
  }
}

class _Transport implements CollaborationTransport {
  _Transport(this.server);
  final FakeServer server;
  _Runtime? runtime;
  final replies = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'sync.pull' && runtime != null) {
      final reply = await runtime!.pull(
        params['scopeId'] as String,
        'content',
        params,
      );
      replies.add(reply);
      return reply;
    }
    return server.call(operation, params, token);
  }

  @override
  void close() {}
}

Future<
  ({
    CollaborationRepository repo,
    _Runtime runtime,
    String scope,
    _Transport transport,
  })
>
_fixture() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = CollaborationDatabase(NativeDatabase.memory());
  final server = FakeServer();
  final transport = _Transport(server);
  final repo = CollaborationRepository(
    db,
    transport,
    MemorySessionStore(),
    contentRouteGuard: const SyntheticContentRouteGuard(),
    cryptoRouter: _UnusedRouter(),
  );
  addTearDown(repo.close);
  await repo.initialize();
  await repo.login(
    serverUrl: 'https://synthetic.invalid/',
    username: 'alice',
    password: 'synthetic',
  );
  final scope = await repo.createScope('Synthetic content projection');
  final partition = repo.state.session!.partition;
  final runtime = transport.runtime = _Runtime(db, partition);
  return (repo: repo, runtime: runtime, scope: scope, transport: transport);
}

String _id(int sequence) =>
    '70000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}';

Future<void> _seed(
  _Runtime runtime,
  String scope,
  int sequence,
  String type, {
  bool deleted = false,
  String domain = 'content',
  Map<String, dynamic>? body,
}) async {
  final payload = deleted ? null : body ?? <String, dynamic>{'synthetic': true};
  final canonical = {
    'id': _id(sequence),
    'type': type,
    'revision': 1,
    'deleted': deleted,
    'payload': payload,
  };
  await runtime.db.execute(
    'INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,?,?,?,1,?,?,?,?,?)',
    [
      runtime.p,
      scope,
      domain,
      _id(sequence),
      type,
      'a' * 64,
      deleted ? 1 : 0,
      payload == null ? null : jsonEncode(payload),
      jsonEncode(canonical),
      'currentEpoch',
    ],
  );
  await runtime.db.execute(
    "INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict) VALUES(?,?,?, ?,1,?,'{}','verified')",
    [runtime.p, scope, domain, _id(sequence), sequence],
  );
}

void main() {
  test(
    'diagnostic original document projection reaches ordinary enum and leaves cursor',
    () async {
      final f = await _fixture();
      await _seed(f.runtime, f.scope, 1, 'table');
      await _seed(f.runtime, f.scope, 2, 'attachment');
      final original = await f.runtime.pull(f.scope, 'content', {'cursor': 0});
      expect((original['records'] as List).map((v) => v['type']), [
        'table',
        'attachment',
      ]);
      for (final row in original['records'] as List) {
        expect(
          () => SharedRecordType.values.byName(row['type'] as String),
          throwsArgumentError,
        );
      }
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'invalid_response');
      expect(
        (await f.runtime.db.rows(
          'SELECT cursor FROM scopes WHERE partition=? AND id=?',
          [f.runtime.p, f.scope],
        )).single['cursor'],
        0,
      );
      expect(
        (await f.runtime.db.rows(
          'SELECT type FROM crypto_business_records WHERE partition=? ORDER BY id',
          [f.runtime.p],
        )).map((v) => v['type']),
        ['table', 'attachment'],
      );
      expect(
        await f.runtime.db.rows('SELECT id FROM records WHERE partition=?', [
          f.runtime.p,
        ]),
        isEmpty,
      );
    },
    skip: Platform.environment['JIVIE_DOCUMENT_PULL_BASELINE'] != '1',
  );

  test(
    'routing mixed documents stay in dedicated adapters and ordinary sync completes',
    () async {
      final f = await _fixture();
      final tableBody = <String, dynamic>{
        'id': _id(1),
        'scopeId': f.scope,
        'title': 'Synthetic sheet',
        'revision': 1,
        'cells': <String, String>{'A1': '7', 'B1': '=A1*2'},
      };
      final attachmentBody = <String, dynamic>{
        'id': _id(2),
        'scopeId': f.scope,
        'targetType': 'task',
        'targetId': _id(3),
        'fileName': 'synthetic.txt',
        'complete': true,
      };
      await _seed(f.runtime, f.scope, 1, 'table', body: tableBody);
      await _seed(f.runtime, f.scope, 2, 'attachment', body: attachmentBody);
      await _seed(f.runtime, f.scope, 3, 'task', deleted: true);
      final before = await f.runtime.db.rows(
        'SELECT * FROM crypto_business_records WHERE partition=? ORDER BY id',
        [f.runtime.p],
      );
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.replies.single['cursor'], 3);
      expect(
        (f.transport.replies.single['records'] as List).map((v) => v['type']),
        ['task'],
      );
      expect(
        (await f.runtime.db.rows(
          'SELECT cursor FROM scopes WHERE partition=? AND id=?',
          [f.runtime.p, f.scope],
        )).single['cursor'],
        3,
      );
      expect(
        (await f.runtime.db.rows(
          'SELECT type,deleted FROM records WHERE partition=?',
          [f.runtime.p],
        )).single,
        {'type': 'task', 'deleted': 1},
      );
      expect(
        await f.runtime.db.rows(
          'SELECT * FROM crypto_business_records WHERE partition=? ORDER BY id',
          [f.runtime.p],
        ),
        before,
      );
      final documents = CryptoBusinessDocuments(f.runtime);
      final tables = await documents.dispatch('tables.list', {
        'scopeId': f.scope,
      });
      expect((tables['sheets'] as List).single['id'], _id(1));
      final attachments = await documents.dispatch('attachments.list', {
        'scopeId': f.scope,
        'targetType': 'task',
        'targetId': _id(3),
      });
      expect((attachments['attachments'] as List).single, attachmentBody);
    },
  );

  test(
    'routing document and internal-only page advances before following ordinary record',
    () async {
      final f = await _fixture();
      await f.runtime.db.transaction(() async {
        for (var n = 1; n <= 100; n++) {
          await _seed(
            f.runtime,
            f.scope,
            n,
            const [
              'table',
              'attachment',
              'scopeMetadata',
              'taskDerivationIntent',
              'taskDerivationResolution',
              'financeAccountChoice',
            ][n % 6],
            deleted: n % 3 == 0,
          );
        }
        await _seed(f.runtime, f.scope, 101, 'task', deleted: true);
      });
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.replies, hasLength(2));
      expect(f.transport.replies[0]['records'], isEmpty);
      expect(f.transport.replies[0]['cursor'], 100);
      expect(f.transport.replies[0]['hasMore'], isTrue);
      expect(
        (f.transport.replies[1]['records'] as List).single['type'],
        'task',
      );
      expect(f.transport.replies[1]['cursor'], 101);
      expect(f.transport.replies[1]['hasMore'], isFalse);
      expect(
        (await f.runtime.db.rows(
          'SELECT cursor FROM scopes WHERE partition=? AND id=?',
          [f.runtime.p, f.scope],
        )).single['cursor'],
        101,
      );
      expect(
        await f.runtime.db.rows(
          'SELECT id FROM crypto_business_records WHERE partition=?',
          [f.runtime.p],
        ),
        hasLength(101),
      );
    },
  );

  test(
    'routing internal-only terminal page advances without ordinary records',
    () async {
      final f = await _fixture();
      for (var n = 1; n <= 4; n++) {
        await _seed(
          f.runtime,
          f.scope,
          n,
          const [
            'scopeMetadata',
            'taskDerivationIntent',
            'taskDerivationResolution',
            'financeAccountChoice',
          ][n - 1],
        );
      }
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.replies.single['records'], isEmpty);
      expect(f.transport.replies.single['cursor'], 4);
      expect(f.transport.replies.single['hasMore'], isFalse);
      expect(
        (await f.runtime.db.rows(
          'SELECT cursor FROM scopes WHERE partition=? AND id=?',
          [f.runtime.p, f.scope],
        )).single['cursor'],
        4,
      );
    },
  );

  test(
    'routing unknown type remains fail closed and cursor is not committed',
    () async {
      final f = await _fixture();
      await _seed(f.runtime, f.scope, 1, 'table');
      await _seed(f.runtime, f.scope, 2, 'futureDocument');
      await _seed(f.runtime, f.scope, 3, 'task', deleted: true);
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'invalid_response');
      expect(
        (f.transport.replies.single['records'] as List).map((v) => v['type']),
        ['futureDocument', 'task'],
      );
      expect(
        (await f.runtime.db.rows(
          'SELECT cursor FROM scopes WHERE partition=? AND id=?',
          [f.runtime.p, f.scope],
        )).single['cursor'],
        0,
      );
      expect(
        await f.runtime.db.rows('SELECT id FROM records WHERE partition=?', [
          f.runtime.p,
        ]),
        isEmpty,
      );
      expect(
        await f.runtime.db.rows(
          'SELECT id FROM crypto_business_records WHERE partition=?',
          [f.runtime.p],
        ),
        hasLength(3),
      );
    },
  );

  test('routing document-only tail advances across page boundary', () async {
    final f = await _fixture();
    await f.runtime.db.transaction(() async {
      for (var n = 1; n <= 101; n++) {
        await _seed(
          f.runtime,
          f.scope,
          n,
          n.isEven ? 'attachment' : 'table',
          deleted: n % 3 == 0,
        );
      }
    });
    await f.repo.syncNow();
    expect(f.repo.state.lastError, isNull);
    expect(f.transport.replies, hasLength(2));
    expect(f.transport.replies.map((v) => v['records']), everyElement(isEmpty));
    expect(f.transport.replies.map((v) => v['cursor']), [100, 101]);
    expect(f.transport.replies.map((v) => v['hasMore']), [true, false]);
    expect(
      (await f.runtime.db.rows(
        'SELECT cursor FROM scopes WHERE partition=? AND id=?',
        [f.runtime.p, f.scope],
      )).single['cursor'],
      101,
    );
    expect(
      await f.runtime.db.rows('SELECT id FROM records WHERE partition=?', [
        f.runtime.p,
      ]),
      isEmpty,
    );
    expect(
      await f.runtime.db.rows(
        'SELECT id FROM crypto_business_records WHERE partition=?',
        [f.runtime.p],
      ),
      hasLength(101),
    );
  });

  test(
    'routing malformed projection type fails before document exclusion',
    () async {
      final f = await _fixture();
      await _seed(f.runtime, f.scope, 1, 'table');
      await f.runtime.db.execute(
        'UPDATE crypto_business_records SET projection=? WHERE partition=? AND scope_id=? AND id=?',
        [
          jsonEncode({
            'id': _id(1),
            'type': null,
            'revision': 1,
            'deleted': false,
            'payload': <String, dynamic>{},
          }),
          f.runtime.p,
          f.scope,
          _id(1),
        ],
      );
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'invalid_response');
      expect(
        (await f.runtime.db.rows(
          'SELECT cursor FROM scopes WHERE partition=? AND id=?',
          [f.runtime.p, f.scope],
        )).single['cursor'],
        0,
      );
      expect(
        await f.runtime.db.rows(
          'SELECT id FROM crypto_business_records WHERE partition=?',
          [f.runtime.p],
        ),
        hasLength(1),
      );
      expect(
        await f.runtime.db.rows('SELECT id FROM records WHERE partition=?', [
          f.runtime.p,
        ]),
        isEmpty,
      );
    },
  );

  test(
    'routing verifier rejection precedes document scanning and cursor commit',
    () async {
      final f = await _fixture();
      await _seed(f.runtime, f.scope, 1, 'table');
      f.runtime.verifiedFailure = const FormatException(
        'synthetic rejected proof',
      );
      await f.repo.syncNow();
      expect(f.runtime.verifiedPulls, 1);
      expect(f.repo.state.lastError?.code, 'invalid_response');
      expect(f.transport.replies, isEmpty);
      expect(
        (await f.runtime.db.rows(
          'SELECT cursor FROM scopes WHERE partition=? AND id=?',
          [f.runtime.p, f.scope],
        )).single['cursor'],
        0,
      );
      expect(
        await f.runtime.db.rows(
          'SELECT id FROM crypto_business_records WHERE partition=?',
          [f.runtime.p],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'routing finance scans internal pages and retains financial and unknown projections',
    () async {
      final f = await _fixture();
      await f.runtime.db.transaction(() async {
        for (var n = 1; n <= 100; n++) {
          await _seed(
            f.runtime,
            f.scope,
            n,
            n.isEven ? 'financeAccountChoice' : 'taskDerivationResolution',
            domain: 'finance',
          );
        }
        await _seed(
          f.runtime,
          f.scope,
          101,
          'financeAccount',
          domain: 'finance',
        );
        await _seed(f.runtime, f.scope, 102, 'financeEntry', domain: 'finance');
        await _seed(
          f.runtime,
          f.scope,
          103,
          'futureFinanceType',
          domain: 'finance',
        );
        await _seed(f.runtime, f.scope, 104, 'table');
      });
      final before = await f.runtime.db.rows(
        'SELECT * FROM crypto_business_records WHERE partition=? ORDER BY domain,id',
        [f.runtime.p],
      );
      final first = await f.runtime.pull(f.scope, 'finance', {'cursor': 0});
      expect(first['records'], isEmpty);
      expect(first['cursor'], 100);
      expect(first['hasMore'], isTrue);
      final second = await f.runtime.pull(f.scope, 'finance', {
        'cursor': first['cursor'],
      });
      expect((second['records'] as List).map((v) => v['type']), [
        'financeAccount',
        'financeEntry',
        'futureFinanceType',
      ]);
      expect(second['cursor'], 103);
      expect(second['hasMore'], isFalse);
      for (final page in [first, second]) {
        expect(page['accessRevision'], 7);
        expect(page['cryptoProjectionComplete'], isFalse);
        expect(page['cryptoCompletenessBasis'], 'signerObservedSnapshot');
        expect(page['organizationFinanceComplete'], isFalse);
        expect(page['organizationFinanceScopeIds'], isEmpty);
        expect(page['organizationFinanceSequences'], isEmpty);
      }
      expect(
        await f.runtime.db.rows(
          'SELECT * FROM crypto_business_records WHERE partition=? ORDER BY domain,id',
          [f.runtime.p],
        ),
        before,
      );
      // The domain-independent type binding must reject a malformed financial row.
      await f.runtime.db.execute(
        'UPDATE crypto_business_records SET projection=? WHERE partition=? AND scope_id=? AND domain=? AND id=?',
        [
          jsonEncode({'type': 'financeEntry'}),
          f.runtime.p,
          f.scope,
          'finance',
          _id(101),
        ],
      );
      await expectLater(
        f.runtime.pull(f.scope, 'finance', {'cursor': 100}),
        throwsFormatException,
      );
      expect(
        (await f.runtime.db.rows(
          'SELECT cursor,finance_cursor FROM scopes WHERE partition=? AND id=?',
          [f.runtime.p, f.scope],
        )).single,
        {'cursor': 0, 'finance_cursor': 0},
      );
    },
  );
}
