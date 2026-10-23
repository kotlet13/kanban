import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_addresses.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'crypto_project_root_address_seam_test.dart' as fixture;

const own = '00000000-0000-4000-a000-000000000011';
const device = '00000000-0000-4000-a000-000000000012';
final headHash = 'b' * 64;

class _MemorySecure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String partition) async => values[partition];
  @override
  Future<void> write(String partition, String value) async {
    values[partition] = value;
  }
}

class _Own implements VerifiedAccountDirectory {
  @override
  String get serverId => fixture.server;
  @override
  String get accountId => own;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected own-prefix dependency');
}

class _Directory implements AccountDirectoryRepository {
  final calls = <String>[];
  @override
  String get accountId => own;
  @override
  bool Function() get isCurrent =>
      () => true;
  @override
  DeviceSession get session => DeviceSession(
    AccountSession(
      serverUrl: 'http://127.0.0.1:1/',
      serverId: fixture.server,
      accountId: own,
      userId: 1,
      username: 'synthetic',
      displayName: 'Synthetic',
      deviceId: device,
      expiresAt: DateTime.utc(2030),
      allowLocalHttp: true,
    ),
    'synthetic',
  );
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => _Own();
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    calls.add(operation);
    if (operation == 'crypto2.scope.lifecycle.baseline') {
      return {
        'initialLifecycleBaseline': {
          'ownArchived': false,
          'inheritedArchived': false,
        },
      };
    }
    if (operation == 'crypto2.scope.lifecycle.list') {
      return {'states': <Object>[], 'hasMore': false, 'currentRevision': 0};
    }
    throw StateError(
      'No extra authority or content request allowed: $operation',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected directory dependency');
}

class _Account implements AccountCryptoV2Workflow {
  _Account(CollaborationDatabase db)
    : store = CryptoIdentityStore(db, _MemorySecure(), fixture.partition);
  @override
  final _Directory directory = _Directory();
  @override
  final CryptoIdentityStore store;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected account dependency');
}

class _Head implements VerifiedScopeHead {
  @override
  String get headHash => 'b' * 64;
  @override
  Map<String, dynamic> get body => {
    'initialLifecycleHash': headHash,
    'previousHeadHash': CryptoLifecycleEvidence.zero,
    'previousLifecycleHash': null,
  };
  @override
  int get epoch => 1;
  @override
  int get accessRevision => 0;
  @override
  Map<String, dynamic> member(String account) => {
    'accountId': own,
    'role': 'owner',
  };
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected head dependency');
}

class _Access implements SessionCryptoAccess {
  _Access(this.account);
  @override
  final _Account account;
  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async => _Head();
  @override
  Future<Map<String, dynamic>> verifiedScopeDescriptor(
    String scopeId, {
    bool online = false,
  }) async => fixture.descriptor;
  @override
  Future<String> verifyInitialLifecycle(
    String scopeId,
    Map<String, dynamic> wire, {
    required String scopeHeadHash,
  }) async => headHash;
  @override
  Set<String> observedLifecycleHashes(String scopeId) => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected authority dependency ${invocation.memberName}',
  );
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(_Account account, CollaborationDatabase db)
    : super(account, _Access(account), db);
  @override
  Future<List<Map<String, dynamic>>> catalog() async => [
    {'id': fixture.scope},
  ];
}

void main() {
  test(
    'production scopes caller resolves persisted wire project to canonical root without new content reads',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await fixture.seed(db, fixture.scope);
      final runtime = _Runtime(_Account(db), db);
      final metadataId = await runtime.reservedRecordId(
        fixture.scope,
        'scopeMetadata',
      );
      final metadataAddress = CryptoRecordAddress.forType(
        serverId: fixture.server,
        scopeId: fixture.scope,
        type: 'scopeMetadata',
        canonicalId: metadataId,
      );
      await CryptoBusinessAddresses(
        db,
        fixture.partition,
        fixture.server,
      ).install(metadataAddress);
      await db.execute(
        'INSERT INTO crypto_business_records VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          fixture.partition,
          fixture.scope,
          'content',
          metadataAddress.wireId,
          'scopeMetadata',
          1,
          0,
          'c' * 64,
          0,
          jsonEncode({'name': 'Exact project'}),
          '{}',
          'ordinary',
          'crypto',
        ],
      );
      final result = await runtime.scopes();
      final projected = (result['scopes'] as List).single as Map;
      expect(projected['projectRootId'], fixture.scope);
      expect(projected['id'], fixture.scope);
      expect(projected['name'], 'Exact project');
      expect(projected['role'], 'owner');
      final directory = (runtime.account as _Account).directory;
      expect(directory.calls, [
        'crypto2.scope.lifecycle.baseline',
        'crypto2.scope.lifecycle.list',
        'crypto2.scope.lifecycle.list',
      ]);

    },
  );
}
