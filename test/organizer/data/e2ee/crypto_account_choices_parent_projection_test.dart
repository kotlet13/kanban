import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const _parent = '11111111-1111-4111-a111-111111111111';
const _child = '22222222-2222-4222-a222-222222222222';
const _action = '33333333-3333-4333-a333-333333333333';
const _partition = 'parent-projection-fixture';
const _other = '44444444-4444-4444-a444-444444444444';
const _server = '55555555-5555-4555-a555-555555555555';

class _FixtureDirectory implements AccountDirectoryRepository {
  @override
  DeviceSession get session => DeviceSession(
    AccountSession(
      serverUrl: 'http://127.0.0.1:1/',
      serverId: _server,
      accountId: _action,
      userId: 1,
      username: 'fixture',
      displayName: 'Fixture',
      deviceId: _other,
      expiresAt: DateTime.utc(2030),
      allowLocalHttp: true,
    ),
    'unused-fixture-token',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No directory/API calls allowed in parent projection');
}

class _UnusedAccount implements AccountCryptoV2Workflow {
  @override
  AccountDirectoryRepository get directory => _FixtureDirectory();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected account dependency in parent bootstrap');
}

class _UnusedAccess implements SessionCryptoAccess {
  @override
  AccountCryptoV2Workflow get account => _UnusedAccount();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected authority dependency in parent bootstrap');
}

class _ReachedParentFinance implements Exception {}

/// Stops before account/HTTP/crypto writes. The real prepare() must get through
/// the stored SharedScope schema and request the correct parent's finance read.
class _BootstrapRuntime extends CryptoBusinessSession {
  _BootstrapRuntime(CollaborationDatabase db)
    : super(_UnusedAccount(), _UnusedAccess(), db);
  final pulls = <(String, String)>[];
  @override
  String get p => _partition;
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {
    pulls.add((scopeId, domain));
    if (domain == 'finance') {
      if (scopeId != _parent) throw StateError('Wrong parent read');
      throw _ReachedParentFinance();
    }
  }
}

SharedScope _scope(String id, SharedScopeKind kind, {String? parent}) =>
    SharedScope(
      id: id,
      name: kind == SharedScopeKind.organization
          ? 'Synthetic org'
          : 'Synthetic project',
      kind: kind,
      role: SharedRole.owner,
      parentScopeId: parent,
      parentScopeKind: parent == null ? null : SharedScopeKind.organization,
      organizationId: parent,
      projectRootId: kind == SharedScopeKind.project ? id : null,
      accessPolicyVersion: 3,
    );

Future<Map<String, dynamic>> _projection({
  required String? token,
  Map<String, dynamic> cached = const {},
  String hintedParent = _parent,
  String? verifiedParentKind,
  bool includeParentCatalog = true,
}) => cryptoScopeParentProjection(
  scopeId: _child,
  descriptor: {'id': _child, 'kind': 'project', 'parentScopeToken': token},
  cached: cached,
  catalog: [
    {'id': _child, 'kind': 'project', 'parentScopeId': hintedParent},
    if (includeParentCatalog)
      {'id': hintedParent, 'kind': 'organization'}, // untrusted discovery kind
  ],
  verifiedDescriptors: {
    if (verifiedParentKind != null)
      hintedParent: {'id': hintedParent, 'kind': verifiedParentKind},
  },
  parentToken: CryptoLifecycleEvidence(_UnusedAccess()).parentToken,
);

void main() {
  test(
    'SharedScope round trip retains its parent through actual schema keys',
    () {
      final model = _scope(_child, SharedScopeKind.project, parent: _parent);
      final stored =
          jsonDecode(jsonEncode(model.toJson())) as Map<String, dynamic>;
      expect(stored.containsKey('parentSpaceId'), false);
      expect(stored['parentScopeId'], _parent);
      expect(stored['organizationId'], _parent);
      expect(SharedScope.fromJson(stored).parentSpaceId, _parent);
    },
  );

  test(
    'ordinary org/project stored model reaches account-choice parent bootstrap',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
        _partition,
        '{}',
      ]);
      for (final scope in [
        _scope(_parent, SharedScopeKind.organization),
        _scope(_child, SharedScopeKind.project, parent: _parent),
      ]) {
        await db.execute(
          'INSERT INTO scopes(partition,id,data) VALUES(?,?,?)',
          [_partition, scope.id, jsonEncode(scope.toJson())],
        );
      }
      final runtime = _BootstrapRuntime(db);
      await expectLater(
        CryptoFinanceAccountChoices(runtime).prepare(_child, actionId: _action),
        throwsA(isA<_ReachedParentFinance>()),
      );
      expect(runtime.pulls, [(_child, 'content'), (_parent, 'finance')]);
      expect(await db.rows('SELECT 1 FROM crypto_export_drafts'), isEmpty);
      expect(await db.rows('SELECT 1 FROM crypto_outbox'), isEmpty);
    },
  );
  test(
    'fresh crypto metadata gains parent only through verified token projection',
    () async {
      // Native createScope writes these metadata fields, with no parent UUID.
      final metadata = {
        'name': 'Synthetic project',
        'address': null,
        'archived': false,
        'kind': 'project',
        'scopeId': _child,
        'namespaceVersion': 1,
      };
      expect(metadata.containsKey('parentSpaceId'), false);
      expect(metadata.containsKey('parentScopeId'), false);
      final token = await CryptoLifecycleEvidence(
        _UnusedAccess(),
      ).parentToken(_child, _parent);
      final fields = await _projection(
        token: token,
        verifiedParentKind: 'organization',
      );
      final projected = SharedScope.fromJson({
        ..._scope(_child, SharedScopeKind.project).toJson(),
        ...fields,
      });
      expect(projected.parentSpaceId, _parent);
      expect(projected.parentScopeKind, SharedScopeKind.organization);
      expect(projected.organizationId, _parent);
      expect(projected.toJson().containsKey('parentSpaceId'), false);
    },
  );

  test(
    'child-only projection binds parent ID without reading parent keys or content',
    () async {
      final token = await CryptoLifecycleEvidence(
        _UnusedAccess(),
      ).parentToken(_child, _parent);
      final fields = await _projection(
        token: token,
        includeParentCatalog: false,
        cached: {
          'parentScopeId': _other,
          'parentScopeKind': 'organization',
          'organizationId': _other,
        },
      );
      expect(fields, {
        'parentScopeId': _parent,
        'parentScopeKind': null,
        'organizationId': null,
      });
    },
  );

  test(
    'unsigned catalog and stale cache cannot forge the signed relation',
    () async {
      final token = await CryptoLifecycleEvidence(
        _UnusedAccess(),
      ).parentToken(_child, _parent);
      final fields = await _projection(
        token: token,
        hintedParent: _other,
        verifiedParentKind: 'organization',
        cached: {
          'parentScopeId': _other,
          'parentScopeKind': 'organization',
          'organizationId': _other,
        },
      );
      expect(fields.values, everyElement(isNull));
    },
  );

  test('null parent token clears obsolete parent fields', () async {
    final fields = await _projection(
      token: null,
      cached: {
        'parentScopeId': _parent,
        'parentScopeKind': 'organization',
        'organizationId': _parent,
      },
      verifiedParentKind: 'organization',
    );
    expect(fields.values, everyElement(isNull));
  });

  test(
    'verified household parent never becomes an organization alias',
    () async {
      final token = await CryptoLifecycleEvidence(
        _UnusedAccess(),
      ).parentToken(_child, _parent);
      final fields = await _projection(
        token: token,
        verifiedParentKind: 'household',
      );
      expect(fields, {
        'parentScopeId': _parent,
        'parentScopeKind': 'household',
        'organizationId': null,
      });
    },
  );

  test(
    'parent token from another child does not admit the routing hint',
    () async {
      final token = await CryptoLifecycleEvidence(
        _UnusedAccess(),
      ).parentToken(_other, _parent);
      expect((await _projection(token: token)).values, everyElement(isNull));
    },
  );
}
