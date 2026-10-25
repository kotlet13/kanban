import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const _server = '10000000-0000-4000-8000-000000000001';
const _actor = '10000000-0000-4000-8000-000000000002';
const _scope = '10000000-0000-4000-8000-000000000003';
const _stoppedAtPull = _PullBoundary();

class _PullBoundary implements Exception {
  const _PullBoundary();
}

class _Transport implements CollaborationTransport {
  _Transport(this.caps);
  final Map<String, dynamic> caps;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    expect(operation, 'capabilities');
    calls++;
    return caps;
  }

  @override
  void close() {}
}

class _VerifiedDirectory implements VerifiedAccountDirectory {
  @override
  String get deviceSnapshotHash => 'a' * 64;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Directory implements AccountDirectoryRepository {
  _Directory(this.reducer, this.transport);
  @override
  final AccountDirectoryV2 reducer;
  @override
  final _Transport transport;
  @override
  final DeviceSession session = DeviceSession(
    AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: _server,
      accountId: _actor,
      userId: 1,
      username: 'fixture',
      displayName: 'Fixture',
      deviceId: '10000000-0000-4000-8000-000000000004',
      expiresAt: DateTime.utc(2030),
    ),
    'synthetic',
  );
  @override
  String get accountId => _actor;
  @override
  bool Function() get isCurrent =>
      () => true;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => _VerifiedDirectory();
  final pulls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    expect(operation, 'crypto2.records.pull');
    pulls.add(Map<String, dynamic>.from(params));
    throw _stoppedAtPull;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements CryptoIdentityStore {
  @override
  String get partition => 'synthetic-scope-review-negotiation';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No journal mutation expected before captured pull');
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.directory);
  @override
  final _Directory directory;
  @override
  final CryptoIdentityStore store = _Store();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Head implements VerifiedScopeHead {
  @override
  String get scopeId => _scope;
  @override
  String get headHash => 'b' * 64;
  @override
  int get accessRevision => 1;
  @override
  int get epoch => 1;
  @override
  List<Map<String, dynamic>> get members => [
    {
      'accountId': _actor,
      'role': 'owner',
      'manageKeys': true,
      'financeRole': 'none',
      'deviceSnapshotHash': 'a' * 64,
    },
  ];
  @override
  Map<String, dynamic> member(String account) =>
      members.singleWhere((m) => m['accountId'] == account);
  @override
  String? commitment(String domain) => domain == 'content' ? 'c' * 64 : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access implements SessionCryptoAccess {
  _Access(this.account);
  @override
  final _Account account;
  @override
  Future<VerifiedScopeHead> recoveryCandidateHead(String scopeId) async =>
      _Head();
  @override
  Future<void> hydrateExistingCandidateKeys(String scopeId) async {}
  @override
  Future<VerifiedAccountDirectory> currentMemberDirectory(
    String scopeId,
    String scopeHeadHash,
    String accountId,
  ) async => _VerifiedDirectory();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected authority or mutation at pull capture seam');
}

// Actual reviewRotation executes to its first raw record pull. Membership/key
// seams are explicit; this control does not claim grant/signature/native proof.
void main() {
  Future<({ScopeCryptoManager manager, _Directory directory})> fixture(
    Map<String, dynamic> caps,
  ) async {
    final directory = _Directory(
      AccountDirectoryV2(CryptoCodec(await SodiumInit.init())),
      _Transport(caps),
    );
    return (
      manager: ScopeCryptoManager(_Access(_Account(directory))),
      directory: directory,
    );
  }

  test(
    'actual scope review advertises negotiated policy v1 at raw pull',
    () async {
      final f = await fixture({
        'serverId': _server,
        'recordPolicyVersions': [1],
      });
      await expectLater(
        f.manager.reviewRotation(_scope),
        throwsA(same(_stoppedAtPull)),
      );
      expect(f.directory.pulls.single, {
        'scopeId': _scope,
        'domain': 'content',
        'accessRevision': 1,
        'cursor': 0,
        'limit': 20,
        'supportedRecordPolicyVersion': 1,
      });
      expect(f.directory.transport.calls, 1);
    },
  );
  test('actual scope review preserves old server raw pull shape', () async {
    final f = await fixture({'serverId': _server});
    await expectLater(
      f.manager.reviewRotation(_scope),
      throwsA(same(_stoppedAtPull)),
    );
    expect(f.directory.pulls.single, {
      'scopeId': _scope,
      'domain': 'content',
      'accessRevision': 1,
      'cursor': 0,
      'limit': 20,
    });
  });
  test(
    'actual scope review rejects capability server substitution before pull',
    () async {
      final f = await fixture({
        'serverId': '10000000-0000-4000-8000-000000000009',
        'recordPolicyVersions': [1],
      });
      await expectLater(
        f.manager.reviewRotation(_scope),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'scope_review_server',
          ),
        ),
      );
      expect(f.directory.pulls, isEmpty);
    },
  );
}
