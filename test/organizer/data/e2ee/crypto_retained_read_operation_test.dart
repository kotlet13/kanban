import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

class _Reducer implements AccountDirectoryV2 {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No proof replay in transport lifetime controls');
}

class _Store implements CryptoIdentityStore {
  _Store(this.partition);
  @override
  final String partition;
  @override
  Future<Map<String, dynamic>?> anchor(String account) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No persistent mutation in transport lifetime controls');
}

class _Transport implements CollaborationTransport {
  final calls = <String>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    if (fail) throw const CollaborationApiException('network');
    if (operation == 'capabilities') {
      return {
        'serverId': 'server',
        'cryptoAuthoritySnapshotVersions': [1],
      };
    }
    if (operation == 'crypto2.authority.snapshot') {
      return {
        'version': 1,
        'serverId': 'server',
        'accountId': 'account',
        'deviceId': 'device',
        'entries': [
          {
            'operation': 'crypto2.account.status',
            'params': <String, dynamic>{},
            'result': {
              'nested': {'read': calls.length},
            },
          },
        ],
      };
    }
    return {'direct': operation};
  }

  @override
  void close() {}
  int get snapshots => calls
      .where((operation) => operation == 'crypto2.authority.snapshot')
      .length;
}

void main() {
  late _Transport transport;
  late SessionCryptoAccess access;
  late AccountDirectoryRepository directory;
  var current = true;
  setUp(() {
    current = true;
    transport = _Transport();
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: 'server',
        accountId: 'account',
        deviceId: 'device',
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic-token',
    );
    directory = AccountDirectoryRepository(
      reducer: _Reducer(),
      session: session,
      transport: transport,
      store: _Store(session.profile.partition),
      isCurrent: () => current,
    );
    access = SessionCryptoAccess(account: AccountCryptoV2Workflow(directory));
  });
  Future<Map<String, dynamic>> read() => access.withVerifiedOperation(
    () => directory.call('crypto2.account.status'),
  );

  test(
    'sequential combined reads keep one original snapshot and clone results',
    () async {
      final retained = access.createReadOperation();
      addTearDown(retained.close);
      final first = await retained.run(read);
      (first['nested'] as Map)['read'] = -1;
      final second = await retained.run(read);
      expect((second['nested'] as Map)['read'], isNot(-1));
      expect(transport.snapshots, 1);
      await read();
      expect(transport.snapshots, 2);
    },
  );

  test(
    'closed handle and next combined context each use fresh snapshots',
    () async {
      final retained = access.createReadOperation();
      await retained.run(read);
      retained.close();
      await retained.run(read);
      await retained.run(read);
      final next = access.createReadOperation();
      addTearDown(next.close);
      await next.run(read);
      expect(transport.snapshots, 4);
    },
  );

  test('unknown mutation retires retained snapshot before transport', () async {
    final retained = access.createReadOperation();
    addTearDown(retained.close);
    await retained.run(read);
    await retained.run(() => directory.call('crypto2.scopeObservation.put'));
    await retained.run(read);
    await retained.run(read);
    expect(transport.snapshots, 3);
    expect(transport.calls, contains('crypto2.scopeObservation.put'));
  });

  test(
    'fresh boundary permanently retires parent even when its error is caught',
    () async {
      final retained = access.createReadOperation();
      addTearDown(retained.close);
      await retained.run(() async {
        await read();
        try {
          await access.withVerifiedOperation(() async {
            await read();
            throw StateError('Synthetic fresh boundary failure');
          }, freshBoundary: true);
        } on StateError {
          // The parent's original snapshot must remain retired.
        }
        await read();
      });
      await retained.run(read);
      expect(transport.snapshots, 4);
    },
  );

  test('callback failure retires handle before next consumer', () async {
    final retained = access.createReadOperation();
    addTearDown(retained.close);
    await expectLater(
      retained.run(() async {
        await read();
        throw StateError('Synthetic consumer failure');
      }),
      throwsStateError,
    );
    await retained.run(read);
    await retained.run(read);
    expect(transport.snapshots, 3);
  });

  test(
    'caught transport failure retires handle within same callback',
    () async {
      final retained = access.createReadOperation();
      addTearDown(retained.close);
      await retained.run(() async {
        await read();
        transport.fail = true;
        await expectLater(
          directory.call('crypto2.records.pull'),
          throwsA(isA<CollaborationApiException>()),
        );
        transport.fail = false;
        expect(
          await directory.call('crypto2.account.status'),
          containsPair('direct', 'crypto2.account.status'),
        );
      });
      await retained.run(read);
      await retained.run(read);
      expect(transport.snapshots, 3);
    },
  );

  test(
    'concurrent consumers retire shared handle and cannot revive old snapshot',
    () async {
      final retained = access.createReadOperation();
      addTearDown(retained.close);
      final entered = Completer<void>(), resume = Completer<void>();
      final first = retained.run(() async {
        await read();
        entered.complete();
        await resume.future;
        return read();
      });
      await entered.future;
      await retained.run(read);
      resume.complete();
      await first;
      await retained.run(read);
      expect(transport.snapshots, 4);
    },
  );

  test(
    'identity rejection retires handle after identity is restored',
    () async {
      final retained = access.createReadOperation();
      addTearDown(retained.close);
      await retained.run(read);
      current = false;
      await expectLater(
        retained.run(read),
        throwsA(isA<CryptoDirectoryException>()),
      );
      current = true;
      await retained.run(read);
      await retained.run(read);
      expect(transport.snapshots, 3);
    },
  );

  test(
    'external authority generation change retires retained operation',
    () async {
      final retained = access.createReadOperation();
      addTearDown(retained.close);
      await retained.run(read);
      access.invalidateAuthorityOperation();
      await retained.run(read);
      await retained.run(read);
      expect(transport.snapshots, 3);
    },
  );
  test(
    'retained reads expire at original five second boundary without renewal',
    () async {
      final retained = access.createReadOperation();
      addTearDown(retained.close);
      await retained.run(read);
      await Future<void>.delayed(const Duration(seconds: 3));
      await retained.run(read);
      expect(transport.snapshots, 1);
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      await retained.run(read);
      expect(transport.snapshots, 2);
      await retained.run(read);
      expect(transport.snapshots, 3);
    },
  );
}
