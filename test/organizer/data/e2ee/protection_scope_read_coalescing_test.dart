import 'dart:async';
import 'package:kanban/organizer/data/e2ee/crypto_verified_dispatch_reads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const _server = '10000000-0000-4000-8000-000000000001';
const _owner = '10000000-0000-4000-8000-000000000002';
const _peer = '10000000-0000-4000-8000-000000000003';
const _scope = '10000000-0000-4000-8000-000000000004';
const _device = '10000000-0000-4000-8000-000000000005';

class _Store implements CryptoIdentityStore {
  _Store(this.partition);
  @override
  final String partition;
  @override
  Future<Map<String, dynamic>?> anchor(String account) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'No secret, journal or DB mutation expected in scope read',
  );
}

class _Transport implements CollaborationTransport {
  final calls = <String>[];
  int version = 1;
  bool stalePeer = false;
  String get hash => (version == 1 ? 'b' : 'c') * 64;
  Map<String, dynamic> status(String id) => {
    'deviceSnapshotHash': (id == _peer && stalePeer ? 'e' : 'a') * 64,
  };
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    if (operation == 'capabilities')
      return {
        'serverId': _server,
        'cryptoAuthoritySnapshotVersions': [1],
      };
    if (operation == 'crypto2.authority.snapshot')
      return {
        'version': 1,
        'serverId': _server,
        'accountId': _owner,
        'deviceId': _device,
        'entries': [
          {
            'operation': 'crypto2.scope.headGet',
            'params': {'scopeId': _scope},
            'result': {'headHash': hash},
          },
          for (final id in [_owner, _peer])
            {
              'operation': 'crypto2.directory.status',
              'params': {'scopeId': _scope, 'headHash': hash, 'accountId': id},
              'result': status(id),
            },
        ],
      };
    if (operation == 'crypto2.scope.headGet') return {'headHash': hash};
    if (operation == 'crypto2.directory.status')
      return status(params['accountId'] as String);
    if (operation == 'crypto2.scope.activate') {
      version++;
      return {'applied': true};
    }
    throw StateError('Unexpected transport $operation');
  }

  @override
  void close() {}
}

class _Head implements VerifiedScopeHead {
  _Head(this.headHash);
  @override
  final String headHash;
  @override
  String get scopeId => _scope;
  @override
  List<Map<String, dynamic>> get members => [
    for (final id in [_owner, _peer])
      {'accountId': id, 'deviceSnapshotHash': 'a' * 64},
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VerifiedDirectory implements VerifiedAccountDirectory {
  _VerifiedDirectory(this.deviceSnapshotHash);
  @override
  final String deviceSnapshotHash;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The real operation lease and authority snapshot transport run. The scope and
// directory proof consumers are explicit verified seams; no cryptographic
// membership proof or native/protection completion claim follows from this test.
class _Access extends SessionCryptoAccess {
  _Access({required super.account});
  @override
  Future<VerifiedScopeHead> currentHead(
    String scope, {
    bool online = false,
  }) async {
    expect(online, isTrue);
    final wire = await account.directory.call('crypto2.scope.headGet', {
      'scopeId': scope,
    });
    final head = _Head(wire['headHash']);
    // A head verifier already reads its members. The protection phase then
    // performs its own explicit current-member check using the same transport.
    for (final member in head.members) {
      await currentMemberDirectory(scope, head.headHash, member['accountId']);
    }
    return head;
  }

  @override
  Future<VerifiedAccountDirectory> currentMemberDirectory(
    String scope,
    String hash,
    String id,
  ) async {
    final status = await account.directory.call('crypto2.directory.status', {
      'scopeId': scope,
      'headHash': hash,
      'accountId': id,
    });
    return _VerifiedDirectory(status['deviceSnapshotHash']);
  }
}

void main() {
  Future<
    ({AccountProtectionReady service, _Access access, _Transport transport})
  >
  fixture() async {
    final transport = _Transport();
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: _server,
        accountId: _owner,
        userId: 1,
        username: 'fixture',
        displayName: 'Fixture',
        deviceId: _device,
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic',
    );
    final account = AccountCryptoV2Workflow(
      AccountDirectoryRepository(
        reducer: AccountDirectoryV2(CryptoCodec(await SodiumInit.init())),
        session: session,
        transport: transport,
        store: _Store(session.profile.partition),
        isCurrent: () => true,
      ),
    );
    final service = AccountProtectionReady(account);
    addTearDown(service.close);
    return (
      service: service,
      access: _Access(account: account),
      transport: transport,
    );
  }

  test(
    'metadata readgroup shares sequential metadata transport and account resolution',
    () async {
      final f = await fixture();
      var resolutions = 0;
      final session = f.access.account.directory.session;
      final group = CryptoVerifiedDispatchReads(
        session: session,
        accountFor: (_) async {
          resolutions++;
          return f.access.account;
        },
        createAccess: (_) => f.access,
      );
      addTearDown(group.close);
      await group.run('scopes.list', session, (shared) async {
        expect(identical(shared, f.access), isTrue);
        await shared!.currentHead(_scope, online: true);
      });
      await group.run('scopes.members', session, (shared) async {
        expect(identical(shared, f.access), isTrue);
        for (final id in [_owner, _peer]) {
          await shared!.currentMemberDirectory(_scope, 'b' * 64, id);
        }
      });
      expect(resolutions, 1);
      expect(f.transport.calls, ['capabilities', 'crypto2.authority.snapshot']);
    },
  );
  test(
    'metadata readgroup original deadline and identity changes permanently close reuse',
    () async {
      final f = await fixture();
      final session = f.access.account.directory.session;
      CryptoVerifiedDispatchReads make() => CryptoVerifiedDispatchReads(
        session: session,
        accountFor: (_) async => f.access.account,
        createAccess: (_) => f.access,
      );
      final group = make();
      addTearDown(group.close);
      await group.run(
        'scopes.list',
        session,
        (shared) => shared!.currentHead(_scope, online: true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5100));
      await group.run(
        'scopes.members',
        session,
        (shared) => shared!.currentHead(_scope, online: true),
      );
      await group.run(
        'scopes.list',
        session,
        (shared) async => expect(shared, isNull),
      );
      expect(
        f.transport.calls.where((op) => op == 'crypto2.authority.snapshot'),
        hasLength(2),
      );
      final identityGroup = make();
      addTearDown(identityGroup.close);
      await identityGroup.run(
        'scopes.list',
        session,
        (shared) => shared!.currentHead(_scope, online: true),
      );
      final changed = DeviceSession(
        AccountSession.fromJson({
          ...session.profile.toJson(),
          'deviceId': '10000000-0000-4000-8000-000000000009',
        }),
        session.token,
      );
      await identityGroup.run(
        'scopes.members',
        changed,
        (shared) async => expect(shared, isNull),
      );
      await identityGroup.run(
        'scopes.members',
        session,
        (shared) async => expect(shared, isNull),
      );
    },
  );
  test(
    'metadata readgroup mutation error unknown route and overlap cannot resume authority',
    () async {
      final f = await fixture();
      final session = f.access.account.directory.session;
      CryptoVerifiedDispatchReads make() => CryptoVerifiedDispatchReads(
        session: session,
        accountFor: (_) async => f.access.account,
        createAccess: (_) => f.access,
      );
      final mutation = make();
      await mutation.run('scopes.list', session, (shared) async {
        await shared!.currentHead(_scope, online: true);
        await shared.account.directory.call('crypto2.scope.activate', {
          'scopeId': _scope,
        });
      });
      await mutation.run(
        'scopes.members',
        session,
        (shared) async => expect(shared, isNull),
      );
      final failed = make();
      await expectLater(
        failed.run<void>('scopes.list', session, (shared) async {
          await shared!.currentHead(_scope, online: true);
          throw const FormatException('failed-phase');
        }),
        throwsFormatException,
      );
      await failed.run(
        'scopes.members',
        session,
        (shared) async => expect(shared, isNull),
      );
      final unknown = make();
      await unknown.run(
        'scopes.list',
        session,
        (shared) => shared!.currentHead(_scope, online: true),
      );
      await unknown.run(
        'finance4.accountChoices',
        session,
        (shared) async => expect(shared, isNull),
      );
      await unknown.run(
        'scopes.members',
        session,
        (shared) async => expect(shared, isNull),
      );
      final overlap = make(),
          entered = Completer<void>(),
          release = Completer<void>();
      final first = overlap.run('scopes.list', session, (shared) async {
        await shared!.currentHead(_scope, online: true);
        entered.complete();
        await release.future;
      });
      await entered.future;
      await overlap.run(
        'scopes.members',
        session,
        (shared) async => expect(shared, isNull),
      );
      release.complete();
      await first;
      await overlap.run(
        'scopes.members',
        session,
        (shared) async => expect(shared, isNull),
      );
    },
  );

  test(
    'protection scope read coalesces repeated verified member transport',
    () async {
      final f = await fixture();
      final direct = await f.access.currentHead(_scope, online: true);
      for (final member in direct.members) {
        await f.access.currentMemberDirectory(
          _scope,
          direct.headHash,
          member['accountId'],
        );
      }
      expect(f.transport.calls, [
        'crypto2.scope.headGet',
        ...List.filled(4, 'crypto2.directory.status'),
      ]);
      f.transport.calls.clear();
      final result = await f.service.readScopeMembers(f.access, _scope);
      expect(result.head.headHash, 'b' * 64);
      expect(result.stale, isFalse);
      expect(f.transport.calls, ['capabilities', 'crypto2.authority.snapshot']);
    },
  );
  test(
    'protection scope read ends before mutation and next phase fetches fresh head',
    () async {
      final f = await fixture();
      final first = await f.service.readScopeMembers(f.access, _scope);
      await f.access.account.directory.call('crypto2.scope.activate', {
        'scopeId': _scope,
      });
      final second = await f.service.readScopeMembers(f.access, _scope);
      expect(first.head.headHash, 'b' * 64);
      expect(second.head.headHash, 'c' * 64);
      expect(f.transport.calls, [
        'capabilities',
        'crypto2.authority.snapshot',
        'crypto2.scope.activate',
        'capabilities',
        'crypto2.authority.snapshot',
      ]);
    },
  );
  test('protection scope read preserves stale member detection', () async {
    final f = await fixture();
    f.transport.stalePeer = true;
    final result = await f.service.readScopeMembers(f.access, _scope);
    expect(result.stale, isTrue);
    expect(f.transport.calls, ['capabilities', 'crypto2.authority.snapshot']);
  });
}
