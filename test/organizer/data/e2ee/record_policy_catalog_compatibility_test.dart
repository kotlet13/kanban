import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

const scope = '11111111-1111-4111-8111-111111111111';

class _Directory implements AccountDirectoryRepository {
  Map<String, dynamic> page = {};
  @override
  bool Function() get isCurrent =>
      () => true;
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (operation != 'crypto2.scopes.catalog') throw StateError(operation);
    return page;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.directory);
  @override
  final AccountDirectoryRepository directory;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access implements SessionCryptoAccess {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Map<String, dynamic> descriptor() => {
    'id': scope,
    'kind': 'household',
    'parentScopeId': null,
    'role': 'owner',
    'accessRevision': 1,
    'expectedAccessRevision': 1,
    'accessBasis': [
      {'scopeToken': 'a' * 64, 'accessRevision': 1},
    ],
    'cryptoState': 'active',
    'headHash': 'b' * 64,
    'epoch': 1,
    'cryptoOrigin': true,
    'migrationId': null,
    'migrationState': null,
    'members': [
      {
        'accountId': '22222222-2222-4222-8222-222222222222',
        'role': 'owner',
        'financeRole': 'none',
        'manageKeys': true,
        'deviceSnapshotHash': 'c' * 64,
      },
    ],
  };
  test(
    'original strict14 protection descriptor and catalog hash survive outer policy hint',
    () async {
      final directory = _Directory(), account = _Account(_Directory());
      final service = AccountProtectionReady(_Account(directory));
      addTearDown(service.close);
      directory.page = {
        'scopes': [descriptor()],
        'hasMore': false,
        'nextAfterId': scope,
      };
      final before = await service.catalog(),
          beforeHash = await AccountProtectionReady.catalogHash(
            await service.catalog(),
          );
      directory.page = {
        'scopes': [descriptor()],
        'hasMore': false,
        'nextAfterId': scope,
        'recordPolicyVersions': {scope: 1},
      };
      final after = await service.catalog();
      expect(after, before);
      expect(after.single, hasLength(14));
      expect(await AccountProtectionReady.catalogHash(after), beforeHash);
      expect(account, isNotNull);
    },
  );
  test(
    'business catalog attaches verified-later hint without mutating wire descriptor',
    () async {
      final directory = _Directory()
        ..page = {
          'scopes': [descriptor()],
          'hasMore': false,
          'nextAfterId': scope,
          'recordPolicyVersions': {scope: 1},
        };
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final catalog = await CryptoBusinessSession(
        _Account(directory),
        _Access(),
        db,
      ).catalog();
      expect(catalog.single['recordPolicyVersion'], 1);
      expect((directory.page['scopes'] as List).single, hasLength(14));
    },
  );
  test(
    'legacy business catalog without hints keeps original descriptor',
    () async {
      final directory = _Directory()
        ..page = {
          'scopes': [descriptor()],
          'hasMore': false,
          'nextAfterId': scope,
        };
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final catalog = await CryptoBusinessSession(
        _Account(directory),
        _Access(),
        db,
      ).catalog();
      expect(catalog.single.containsKey('recordPolicyVersion'), isFalse);
    },
  );
  test(
    'policy hint has bounded known version and cannot nominate unlisted scope',
    () async {
      final directory = _Directory();
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (final hint in [
        {scope: 2},
        {'33333333-3333-4333-8333-333333333333': 1},
        'malformed',
      ]) {
        directory.page = {
          'scopes': [descriptor()],
          'hasMore': false,
          'nextAfterId': scope,
          'recordPolicyVersions': hint,
        };
        await expectLater(
          CryptoBusinessSession(_Account(directory), _Access(), db).catalog(),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
}
