import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_authority_snapshot.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capability_discovery.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

class _Transport implements CollaborationTransport {
  final calls = <({String operation, String? token})>[];
  Future<Map<String, dynamic>> Function()? response;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add((operation: operation, token: token));
    if (operation == 'capabilities') {
      return response?.call() ??
          {
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
            'result': {'fresh': calls.length},
          },
        ],
      };
    }
    return {'direct': operation};
  }

  @override
  void close() {}
}

DeviceSession _session({
  String url = 'https://synthetic.invalid/',
  String serverId = 'server',
  String accountId = 'account',
  String deviceId = 'device',
  String token = 'synthetic-token',
  bool allowLocalHttp = false,
}) => DeviceSession(
  AccountSession(
    serverUrl: url,
    serverId: serverId,
    accountId: accountId,
    deviceId: deviceId,
    userId: 1,
    username: 'synthetic',
    displayName: 'Synthetic',
    expiresAt: DateTime.utc(2030),
    allowLocalHttp: allowLocalHttp,
  ),
  token,
);

void main() {
  late _Transport transport;
  late DeviceSession session;
  var current = true;
  setUp(() {
    transport = _Transport();
    session = _session();
    current = true;
  });
  Future<T> cycle<T>(Future<T> Function() body) =>
      CryptoCapabilityDiscovery.withSync(
        body,
        transport: transport,
        session: session,
        isCurrent: () => current,
      );
  Future<Map<String, dynamic>> read({
    _Transport? otherTransport,
    DeviceSession? otherSession,
    bool authenticated = false,
  }) => CryptoCapabilityDiscovery.read(
    transport: otherTransport ?? transport,
    session: otherSession ?? session,
    authenticated: authenticated,
  );

  test(
    'one in-flight read per credential mode with deeply isolated results',
    () async {
      final response = Completer<Map<String, dynamic>>();
      transport.response = () => response.future;
      await cycle(() async {
        final first = read(), second = read();
        final bearer = read(authenticated: true);
        await pumpEventQueue();
        expect(transport.calls.map((call) => call.token), [
          null,
          session.token,
        ]);
        response.complete({
          'serverId': 'server',
          'cryptoAuthoritySnapshotVersions': [1],
        });
        (await first)['cryptoAuthoritySnapshotVersions'].clear();
        expect((await second)['cryptoAuthoritySnapshotVersions'], [1]);
        expect((await bearer)['cryptoAuthoritySnapshotVersions'], [1]);
        expect((await read())['cryptoAuthoritySnapshotVersions'], [1]);
      });
      expect(transport.calls.length, 2);
    },
  );

  test('every new cycle discovers a downgrade and ordinary fallback', () async {
    CryptoAuthoritySnapshot snapshot() => CryptoAuthoritySnapshot(
      read: (operation, params) => operation == 'capabilities'
          ? read(authenticated: true)
          : transport.call(
              serverUrl: session.profile.serverUrl,
              operation: operation,
            ),
      serverId: 'server',
      accountId: 'account',
      deviceId: 'device',
      isValid: () async => true,
      onMutation: () {},
    );
    await cycle(
      () async => expect(
        await snapshot().call('crypto2.account.status', {}),
        contains('fresh'),
      ),
    );
    transport.response = () async => {'serverId': 'server'};
    await cycle(
      () async => expect(await snapshot().call('crypto2.account.status', {}), {
        'direct': 'crypto2.account.status',
      }),
    );
    expect(transport.calls.map((call) => call.operation), [
      'capabilities',
      'crypto2.authority.snapshot',
      'capabilities',
      'crypto2.account.status',
    ]);
  });

  test('outside the explicit cycle reads always reach transport', () async {
    await read();
    await read();
    expect(transport.calls.length, 2);
  });

  for (final variant in <String, DeviceSession Function()>{
    'same values but another session object': _session,
    'URL': () => _session(url: 'https://other.invalid/'),
    'server': () => _session(serverId: 'other'),
    'account': () => _session(accountId: 'other'),
    'device': () => _session(deviceId: 'other'),
    'bearer': () => _session(token: 'other'),
    'local HTTP policy': () => _session(allowLocalHttp: true),
  }.entries) {
    test('${variant.key} never reuses cycle metadata', () async {
      await cycle(() async {
        await read();
        final other = variant.value();
        await read(otherSession: other);
        await read(otherSession: other);
      });
      expect(transport.calls.length, 3);
    });
  }

  test('different transport never reuses cycle metadata', () async {
    final other = _Transport();
    await cycle(() async {
      await read();
      await read(otherTransport: other);
      await read(otherTransport: other);
    });
    expect(transport.calls.length, 1);
    expect(other.calls.length, 2);
  });

  test(
    'identity or invalid-session change permanently closes cycle metadata',
    () async {
      await cycle(() async {
        await read();
        current = false;
        await read();
        current = true;
        await read();
      });
      expect(transport.calls.length, 3);
    },
  );

  for (final code in ['unsupported_operation', 'network']) {
    test(
      '$code shared failure is evicted and next request can recover',
      () async {
        final response = Completer<Map<String, dynamic>>();
        transport.response = () => response.future;
        await cycle(() async {
          final first = expectLater(
            read(),
            throwsA(isA<CollaborationApiException>()),
          );
          final second = expectLater(
            read(),
            throwsA(isA<CollaborationApiException>()),
          );
          response.completeError(CollaborationApiException(code));
          await Future.wait([first, second]);
          transport.response = null;
          expect(await read(), containsPair('serverId', 'server'));
          await read();
        });
        expect(transport.calls.length, 2);
      },
    );
  }

  test(
    'wrong server is returned unchanged for caller validation and not retained',
    () async {
      transport.response = () async => {'serverId': 'wrong'};
      await cycle(() async {
        expect(await read(), {'serverId': 'wrong'});
        expect(await read(), {'serverId': 'wrong'});
      });
      expect(transport.calls.length, 2);
    },
  );

  test(
    'nested cycle gets new metadata and leaves outer scope independent',
    () async {
      await cycle(() async {
        await read();
        await cycle(() async {
          await read();
          await read();
        });
        await read();
      });
      expect(transport.calls.length, 2);
    },
  );

  test(
    'detached descendants cannot retain or reuse a closed in-flight result',
    () async {
      final response = Completer<Map<String, dynamic>>();
      final released = Completer<void>();
      late Future<void> descendant;
      transport.response = () => response.future;
      await cycle(() async {
        descendant = () async {
          await read();
          await released.future;
          await read();
          await read();
        }();
        await pumpEventQueue();
      });
      response.complete({'serverId': 'server'});
      transport.response = null;
      released.complete();
      await descendant;
      expect(transport.calls.length, 3);
    },
  );

  test('late identity change cannot retain in-flight metadata', () async {
    final response = Completer<Map<String, dynamic>>();
    transport.response = () => response.future;
    await cycle(() async {
      final pending = read();
      current = false;
      response.complete({'serverId': 'server'});
      await pending;
      current = true;
      transport.response = null;
      await read();
      await read();
    });
    expect(transport.calls.length, 3);
  });

  test(
    'separate fresh authority boundaries keep separate signed snapshots',
    () async {
      var mutations = 0;
      CryptoAuthoritySnapshot snapshot() => CryptoAuthoritySnapshot(
        read: (operation, params) => operation == 'capabilities'
            ? read(authenticated: true)
            : transport.call(
                serverUrl: session.profile.serverUrl,
                operation: operation,
              ),
        serverId: 'server',
        accountId: 'account',
        deviceId: 'device',
        isValid: () async => true,
        onMutation: () => mutations++,
      );
      await cycle(() async {
        final first = snapshot();
        final original = await first.call('crypto2.account.status', {});
        await first.call('crypto2.scope.activate', {});
        expect(await first.call('crypto2.account.status', {}), {
          'direct': 'crypto2.account.status',
        });
        final next = await snapshot().call('crypto2.account.status', {});
        expect(next['fresh'], greaterThan(original['fresh'] as int));
      });
      expect(mutations, 1);
      expect(
        transport.calls
            .where((call) => call.operation == 'capabilities')
            .length,
        1,
      );
      expect(
        transport.calls
            .where((call) => call.operation == 'crypto2.authority.snapshot')
            .length,
        2,
      );
    },
  );
}
