import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const _scope = '11111111-1111-4111-a111-111111111111';
const _task = '22222222-2222-4222-a222-222222222222';
const _entry = '33333333-3333-4333-a333-333333333333';
const _operation = '44444444-4444-4444-a444-444444444444';
const _financeOperation = '55555555-5555-4555-a555-555555555555';
const _partition = 'synthetic-paired-stale';

class _Directory implements AccountDirectoryRepository {
  bool current = true;
  @override
  bool Function() get isCurrent =>
      () => current;
  @override
  final session = DeviceSession(
    AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: '66666666-6666-4666-a666-666666666666',
      accountId: '77777777-7777-4777-a777-777777777777',
      userId: 1,
      username: 'synthetic',
      displayName: 'Synthetic',
      deviceId: '88888888-8888-4888-a888-888888888888',
      expiresAt: DateTime.utc(2030),
    ),
    'synthetic',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No network or cryptography at orchestration seam');
}

class _Account implements AccountCryptoV2Workflow {
  @override
  final _Directory directory = _Directory();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No account mutation at orchestration seam');
}

class _Access implements SessionCryptoAccess {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No signing, keys or write admission expected');
}

// The real paired method, typed SQL lookup, immutable stagedGroup loader and
// mismatch classification run. The completed verified-pull boundary is supplied
// synthetically; this does not test signature verification, HTTP or full sync.
class _Runtime extends CryptoBusinessSession {
  _Runtime(this.owner, CollaborationDatabase db) : super(owner, _Access(), db);
  final _Account owner;
  final pulls = <String>[];
  Object? pullFailure;
  Future<void> Function()? afterPulls;
  List<Map<String, dynamic>>? resumedProofs;
  Map<String, dynamic>? resumedCommitment;
  @override
  String get p => _partition;
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {
    expect(scopeId, _scope);
    pulls.add(domain);
    if (pullFailure != null) throw pullFailure!;
    if (domain == 'finance') await afterPulls?.call();
  }

  @override
  Future<List<Map<String, dynamic>>> publishPreparedGroup({
    required String operationId,
    required String localHash,
    required List<Map<String, dynamic>> recordProofs,
    required Map<String, dynamic> commitment,
    List<Map<String, dynamic>> tableLeases = const [],
    List<Map<String, dynamic>> exportBindings = const [],
  }) async {
    expect(operationId, _operation);
    resumedProofs = recordProofs;
    resumedCommitment = commitment;
    throw const CryptoAuthorityPending('crypto_business_delivery_pending');
  }
}

Map<String, Object?> _params({int taskRevision = 1, int financeRevision = 1}) =>
    {
      'operationContractVersion': 6,
      'financeOperationContractVersion': 3,
      'operation': {
        'opId': _operation,
        'recordId': _task,
        'type': 'task',
        'deleted': false,
        'expectedRevision': taskRevision,
        'payload': {'title': 'Preserved local draft'},
      },
      'financeOperation': {
        'opId': _financeOperation,
        'recordId': _entry,
        'type': 'financeEntry',
        'deleted': false,
        'expectedRevision': financeRevision,
        'payload': {'amountMinor': 1500},
      },
    };

void main() {
  late CollaborationDatabase db;
  late _Account owner;
  late _Runtime runtime;
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    owner = _Account();
    runtime = _Runtime(owner, db);
    await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
      _partition,
      '{}',
    ]);
    // Opaque immutable sentinels exercise preservation only, not proof validity.
    await db.execute(
      'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
      [
        _partition,
        'older-request',
        'crypto2.records.batch',
        'old-signed-bytes',
        'old-hash',
        'applied',
      ],
    );
    await db.execute(
      'INSERT INTO crypto_outbox_records(partition,request_id,scope_id,domain,record_id,expected_revision) VALUES(?,?,?,?,?,?)',
      [_partition, 'older-request', _scope, 'content', 'older-wire', 0],
    );
  });
  tearDown(() => db.close());

  Future<Map<String, dynamic>> seed(
    String domain,
    String id,
    String type, {
    int revision = 2,
    bool deleted = false,
    Map<String, dynamic>? override,
  }) async {
    final canonical = <String, dynamic>{
      'id': id,
      'type': type,
      'revision': revision,
      'deleted': deleted,
      'contractVersion': domain == 'content' ? 6 : 3,
      'payload': deleted ? null : {'verified': domain},
      ...?override,
    };
    await db.execute(
      'INSERT OR REPLACE INTO crypto_business_records VALUES(?,?,?,?,?,?,0,?,?,?,?,?,?)',
      [
        _partition,
        _scope,
        domain,
        runtime.address(_scope, domain, type, id).wireId,
        type,
        revision,
        'a' * 64,
        deleted ? 1 : 0,
        jsonEncode({'raw': domain}),
        jsonEncode(canonical),
        'currentEpoch',
        'crypto',
      ],
    );
    return canonical;
  }

  Future<List<Object?>> immutable() async => [
    await db.rows('SELECT * FROM crypto_outbox ORDER BY sequence'),
    await db.rows('SELECT * FROM crypto_outbox_records ORDER BY request_id'),
    await db.rows(
      'SELECT * FROM crypto_business_requests ORDER BY operation_id',
    ),
  ];

  for (final stale in ['task', 'finance', 'both']) {
    test(
      '$stale mismatch returns both current canonical projections without staging',
      () async {
        final params = _params(
          taskRevision: stale == 'finance' ? 2 : 1,
          financeRevision: stale == 'task' ? 2 : 1,
        );
        await seed('content', _task, 'task', revision: 1);
        final finance = await seed('finance', _entry, 'financeEntry');
        late Map<String, dynamic> task;
        runtime.afterPulls = () async {
          task = await seed('content', _task, 'task');
        };
        final originalParams = jsonEncode(params), before = await immutable();
        await expectLater(
          runtime.pushTaskWithCost(
            _scope,
            params,
            route: 'sync6.pushTaskWithCost',
          ),
          throwsA(
            isA<CollaborationApiException>()
                .having((e) => e.code, 'code', 'conflict')
                .having((e) => e.details, 'current pair', {
                  'serverRecord': predicate<Map>(
                    (value) => value.toString() == task.toString(),
                  ),
                  'financeRecord': finance,
                }),
          ),
        );
        expect(runtime.pulls, ['content', 'finance']);
        expect(runtime.resumedProofs, isNull);
        expect(jsonEncode(params), originalParams);
        expect(await immutable(), before);
      },
    );
  }

  test(
    'missing and deleted counterparts remain explicit verified conflict state',
    () async {
      final finance = await seed(
        'finance',
        _entry,
        'financeEntry',
        deleted: true,
      );
      final before = await immutable();
      await expectLater(
        runtime.pushTaskWithCost(
          _scope,
          _params(),
          route: 'sync6.pushTaskWithCost',
        ),
        throwsA(
          isA<CollaborationApiException>().having(
            (e) => e.details,
            'missing task/deleted cost',
            {'serverRecord': null, 'financeRecord': finance},
          ),
        ),
      );
      expect(await immutable(), before);
    },
  );

  test(
    'projection identity type revision and deletion mismatches fail closed',
    () async {
      await seed('finance', _entry, 'financeEntry');
      final before = await immutable();
      for (final invalid in <Map<String, dynamic>>[
        {'id': _entry},
        {'type': 'project'},
        {'revision': 3},
        {'deleted': true},
      ]) {
        await seed('content', _task, 'task', override: invalid);
        await expectLater(
          runtime.pushTaskWithCost(
            _scope,
            _params(),
            route: 'sync6.pushTaskWithCost',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'binding',
              'crypto_task_cost_projection_binding',
            ),
          ),
        );
      }
      expect(runtime.resumedProofs, isNull);
      expect(await immutable(), before);
    },
  );

  test(
    'verified pull failures and late identity change are never converted to conflicts',
    () async {
      await seed('content', _task, 'task');
      await seed('finance', _entry, 'financeEntry');
      final before = await immutable();
      for (final failure in <Object>[
        const CryptoAuthorityPending('crypto_scope_frozen'),
        const CollaborationApiException('permission_revoked'),
        const FormatException('crypto_record_signature'),
      ]) {
        runtime.pullFailure = failure;
        await expectLater(
          runtime.pushTaskWithCost(
            _scope,
            _params(),
            route: 'sync6.pushTaskWithCost',
          ),
          throwsA(same(failure)),
        );
      }
      runtime.pullFailure = null;
      runtime.afterPulls = () async {
        owner.directory.current = false;
      };
      await expectLater(
        runtime.pushTaskWithCost(
          _scope,
          _params(),
          route: 'sync6.pushTaskWithCost',
        ),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'identity',
            'crypto_stale_identity',
          ),
        ),
      );
      expect(runtime.resumedProofs, isNull);
      expect(await immutable(), before);
    },
  );

  test(
    'existing staged pair resumes exact original payload before stale classification',
    () async {
      final params = _params();
      final hash = await CryptoBusinessJson.hash({
        'scopeId': _scope,
        ...params,
        'route': 'sync6.pushTaskWithCost',
      });
      final payload = {
        'records': [
          {'original': 'signed-task'},
          {'original': 'signed-finance'},
        ],
        'commitment': {'original': 'signed-commitment'},
      };
      final signed = jsonEncode({
        'commandBase64': base64Encode(
          CryptoBusinessJson.encode({'payload': payload}),
        ),
        'signatureBase64': 'original',
      });
      await db.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
        [
          _partition,
          'saved-request',
          'crypto2.records.batch',
          signed,
          'saved-hash',
          'pending',
        ],
      );
      await db.execute(
        'INSERT INTO crypto_business_requests VALUES(?,?,?,?,?,?,?)',
        [
          _partition,
          _operation,
          _scope,
          'content',
          hash,
          'saved-request',
          _task,
        ],
      );
      await seed('content', _task, 'task');
      await seed('finance', _entry, 'financeEntry');
      final before = await immutable();
      await expectLater(
        runtime.pushTaskWithCost(
          _scope,
          params,
          route: 'sync6.pushTaskWithCost',
        ),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'original delivery',
            'crypto_business_delivery_pending',
          ),
        ),
      );
      expect(runtime.pulls, isEmpty);
      expect(runtime.resumedProofs, payload['records']);
      expect(runtime.resumedCommitment, payload['commitment']);
      expect(await immutable(), before);
    },
  );
}
