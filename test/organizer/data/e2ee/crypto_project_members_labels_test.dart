import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_member_labels.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_project_root_projection.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

String id(int n) => '00000000-0000-4000-a000-${n.toString().padLeft(12, '0')}';
final own = id(1),
    other = id(2),
    third = id(3),
    scope = id(4),
    server = id(5),
    device = id(6);
final hash = 'a' * 64;
Map<String, dynamic> wire() => {
  'version': 1,
  'serverId': server,
  'accountId': own,
  'deviceId': device,
  'scopeId': scope,
  'headHash': hash,
  'accountIds': [other, third],
  'labels': [
    {
      'accountId': other,
      'userId': 2,
      'username': 'member-beta',
      'displayName': 'Preizkus B',
      'role': 'owner',
    },
    {
      'accountId': third,
      'userId': 3,
      'username': 'member-gamma',
      'displayName': 'Preizkus C',
    },
  ],
};
Map<String, Map<String, dynamic>> parse(Map<String, dynamic> value) =>
    parseCryptoMemberLabels(
      value,
      serverId: server,
      accountId: own,
      deviceId: device,
      scopeId: scope,
      headHash: hash,
      requested: [other, third],
    );

class _Directory implements AccountDirectoryRepository {
  bool current = true, unsupported = false;
  int calls = 0;
  Map<String, dynamic> response = wire();
  @override
  String get accountId => own;
  @override
  bool Function() get isCurrent =>
      () => current;
  @override
  DeviceSession get session => DeviceSession(
    AccountSession(
      serverUrl: 'http://127.0.0.1:1/',
      serverId: server,
      accountId: own,
      userId: 1,
      username: 'owner-alpha',
      displayName: 'Preizkus A',
      deviceId: device,
      expiresAt: DateTime.utc(2030),
      allowLocalHttp: true,
    ),
    'synthetic',
  );
  @override
  Future<Map<String, dynamic>> memberLabels({
    required String scopeId,
    required String headHash,
    required List<String> accountIds,
  }) async {
    calls++;
    expect(scopeId, scope);
    expect(headHash, hash);
    expect(accountIds, [other, third]);
    if (unsupported) {
      throw const CollaborationApiException('unsupported_operation');
    }
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected directory dependency: ${invocation.memberName}',
  );
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.directory);
  @override
  final _Directory directory;
  @override
  String get deviceId => device;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected account dependency');
}

class _Head implements VerifiedScopeHead {
  @override
  String get headHash => hash;
  @override
  List<Map<String, dynamic>> get members => [
    {'accountId': own, 'role': 'owner'},
    {'accountId': other, 'role': 'member'},
    {'accountId': third, 'role': 'viewer'},
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected head dependency');
}

class _Access implements SessionCryptoAccess {
  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async => _Head();
  @override
  Future<Map<String, dynamic>> verifiedScopeDescriptor(
    String scopeId, {
    bool online = false,
  }) async => {'kind': 'project', 'accessPolicyVersion': 3};
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected authority dependency');
}

class _Store implements CryptoIdentityStore {
  @override
  String get partition => _Directory().session.profile.partition;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No crypto store access expected');
}

class _Reducer implements AccountDirectoryV2 {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No crypto reduction expected');
}

class _Transport implements CollaborationTransport {
  final operations = <String>[];
  bool supported = true, wrongServer = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    expect(token, 'synthetic');
    if (operation == 'capabilities') {
      return {
        'serverId': wrongServer ? id(99) : server,
        if (supported) 'cryptoMemberLabelsVersions': [1],
      };
    }
    if (operation == 'crypto2.scope.memberLabels') return wire();
    throw StateError('Unexpected transport');
  }

  @override
  void close() {}
}

AccountDirectoryRepository _realDirectory(_Transport transport) =>
    AccountDirectoryRepository(
      reducer: _Reducer(),
      session: _Directory().session,
      transport: transport,
      store: _Store(),
      isCurrent: () => true,
    );

void main() {
  final descriptor = <String, dynamic>{
    'kind': 'project',
    'accessPolicyVersion': 3,
  };
  Map<String, Object?> root(
    String rootId, {
    bool legacy = false,
    int deleted = 0,
  }) => {
    'id': rootId,
    'deleted': deleted,
    'legacy_revision': legacy ? 1 : 0,
    'revision_namespace': legacy ? 'legacy' : 'crypto',
  };
  String? projectRoot(
    List<Map<String, Object?>> rows, {
    Map<String, dynamic>? source,
    bool complete = false,
  }) => cryptoProjectRootProjection(
    scopeId: scope,
    descriptor: source ?? descriptor,
    projects: rows,
    completeVerifiedInventory: complete,
  );
  test('verified native canonical root works without a network inventory', () {
    expect(projectRoot([root(scope)]), scope);
    expect(projectRoot([]), isNull);
  });
  test(
    'migrated noncanonical root needs complete authenticated inventory and root policy',
    () {
      expect(projectRoot([root(other, legacy: true)]), isNull);
      expect(projectRoot([root(other, legacy: true)], complete: true), other);
      expect(
        projectRoot(
          [root(other, legacy: true)],
          source: {'kind': 'project', 'accessPolicyVersion': 1},
          complete: true,
        ),
        isNull,
      );
    },
  );
  test('deleted ambiguous household and catalog-only roots fail closed', () {
    expect(projectRoot([root(scope, deleted: 1)], complete: true), isNull);
    expect(projectRoot([root(scope), root(other)], complete: true), isNull);
    expect(
      projectRoot(
        [root(scope)],
        source: {
          'kind': 'household',
          'accessPolicyVersion': 3,
          'projectRootId': scope,
        },
      ),
      isNull,
    );
    expect(
      projectRoot(
        [],
        source: {...descriptor, 'projectRootId': other},
        complete: true,
      ),
      isNull,
    );
  });
  test(
    'labels bind exact server requester device scope head and requested set',
    () {
      for (final key in [
        'serverId',
        'accountId',
        'deviceId',
        'scopeId',
        'headHash',
      ]) {
        expect(() => parse({...wire(), key: id(99)}), throwsFormatException);
      }
      expect(
        () => parse({
          ...wire(),
          'accountIds': [third, other],
        }),
        throwsFormatException,
      );
    },
  );
  test('labels reject duplicates foreign IDs and invalid names', () {
    final rows = wire()['labels'] as List;
    expect(
      () => parse({
        ...wire(),
        'labels': [rows.first, rows.first],
      }),
      throwsFormatException,
    );
    expect(
      () => parse({
        ...wire(),
        'labels': [
          {...rows.first as Map, 'accountId': id(99)},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => parse({
        ...wire(),
        'labels': [
          {...rows.first as Map, 'displayName': 'name\nspoof'},
        ],
      }),
      throwsFormatException,
    );
    expect(parse(wire())[other]!.containsKey('role'), false);
  });
  test(
    'production members batches labels keeps own profile and signed roles',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final directory = _Directory();
      final result = await CryptoBusinessSession(
        _Account(directory),
        _Access(),
        db,
      ).members(scope);
      final rows = result['members'] as List;
      expect(directory.calls, 1);
      expect(rows[0]['displayName'], 'Preizkus A');
      expect(rows[1]['displayName'], 'Preizkus B');
      expect(rows[1]['role'], 'member');
      expect(rows[2]['role'], 'viewer');
      expect(rows[1]['labelUnavailable'], false);
    },
  );
  test(
    'old server and missing labels retain distinguishable account IDs without stale cached names',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final directory = _Directory()..unsupported = true;
      final result = await CryptoBusinessSession(
        _Account(directory),
        _Access(),
        db,
      ).members(scope);
      final rows = result['members'] as List;
      expect(rows[1]['labelUnavailable'], true);
      expect(rows[1]['username'], other);
      expect(rows[1]['displayName'], '');
      expect(rows[2]['username'], third);
      expect(directory.calls, 1);
    },
  );
  test('identity changed during label read cannot publish a roster', () async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final directory = _Directory()..current = false;
    expect(
      CryptoBusinessSession(_Account(directory), _Access(), db).members(scope),
      throwsA(isA<CryptoAuthorityPending>()),
    );
  });
  test(
    'direct label negotiation supports one batch with current bearer',
    () async {
      final transport = _Transport();
      expect(
        await _realDirectory(transport).memberLabels(
          scopeId: scope,
          headHash: hash,
          accountIds: [other, third],
        ),
        wire(),
      );
      expect(transport.operations, [
        'capabilities',
        'crypto2.scope.memberLabels',
      ]);
    },
  );
  test(
    'direct label negotiation avoids unknown crypto operation on old server',
    () async {
      final transport = _Transport()..supported = false;
      await expectLater(
        _realDirectory(transport).memberLabels(
          scopeId: scope,
          headHash: hash,
          accountIds: [other, third],
        ),
        throwsA(
          isA<CollaborationApiException>().having(
            (e) => e.code,
            'code',
            'unsupported_operation',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.operations, ['capabilities']);
    },
  );
  test(
    'direct label negotiation rejects changed server before profile batch',
    () async {
      final transport = _Transport()..wrongServer = true;
      await expectLater(
        _realDirectory(transport).memberLabels(
          scopeId: scope,
          headHash: hash,
          accountIds: [other, third],
        ),
        throwsA(isA<CryptoDirectoryException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.operations, ['capabilities']);
    },
  );
}
