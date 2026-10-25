import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/crypto_authority_snapshot.dart';

Map<String, dynamic> entry(
  String operation,
  Map<String, dynamic> params, [
  Map<String, dynamic> result = const {'signed': 'original'},
]) => {'operation': operation, 'params': params, 'result': result};

Map<String, dynamic> envelope(List<Map<String, dynamic>> entries) => {
  'version': 1,
  'serverId': 'server',
  'accountId': 'account',
  'deviceId': 'device',
  'entries': entries,
};

void main() {
  const head = 'crypto2.scope.headGet';
  const status = 'crypto2.account.status';
  final calls = <String>[];
  var valid = true, mutations = 0;
  late Map<String, dynamic> reply;
  var advertised = true;
  Future<Map<String, dynamic>> read(
    String operation,
    Map<String, dynamic> params,
  ) async {
    calls.add(operation);
    if (operation == 'capabilities') {
      return {
        'serverId': 'server',
        if (advertised) 'cryptoAuthoritySnapshotVersions': [1],
      };
    }
    if (operation == 'crypto2.authority.snapshot') return reply;
    return {'direct': operation, 'params': params};
  }

  CryptoAuthoritySnapshot snapshot({CryptoAuthorityRead? override}) =>
      CryptoAuthoritySnapshot(
        read: override ?? read,
        serverId: 'server',
        accountId: 'account',
        deviceId: 'device',
        isValid: () async => valid,
        onMutation: () => mutations++,
      );

  setUp(() {
    calls.clear();
    valid = true;
    mutations = 0;
    advertised = true;
    reply = envelope([
      entry(status, {}),
      entry(head, {'scopeId': 'parent'}),
      entry(head, {'scopeId': 'child'}),
      entry('crypto2.scope.lifecycle.baseline', {'scopeId': 'child'}),
    ]);
  });

  test(
    'account and space children use two requests through exact read route',
    () async {
      final batch = snapshot();
      for (final item in reply['entries'] as List) {
        expect(await batch.call(item['operation'], item['params']), {
          'signed': 'original',
        });
      }
      expect(calls, ['capabilities', 'crypto2.authority.snapshot']);
    },
  );

  test(
    'content read preserves bundle and returned maps cannot change proof',
    () async {
      final batch = snapshot();
      final first = await batch.call(head, {'scopeId': 'child'});
      first['signed'] = 'altered';
      await batch.call('crypto2.records.pull', {'scopeId': 'child'});
      expect(await batch.call(head, {'scopeId': 'child'}), {
        'signed': 'original',
      });
      expect(calls, [
        'capabilities',
        'crypto2.authority.snapshot',
        'crypto2.records.pull',
      ]);
      expect(mutations, 0);
    },
  );

  test(
    'per-scope revocation error stays a denial; absent selector reads exact',
    () async {
      (reply['entries'] as List).add({
        'operation': head,
        'params': {'scopeId': 'revoked'},
        'error': {
          'code': 'permission_revoked',
          'status': 403,
          'details': {'scopeId': 'revoked'},
        },
      });
      final batch = snapshot();
      await batch.call(status, {});
      await expectLater(
        batch.call(head, {'scopeId': 'revoked'}),
        throwsA(
          isA<CollaborationApiException>().having(
            (error) => error.code,
            'code',
            'permission_revoked',
          ),
        ),
      );
      expect(
        await batch.call(head, {'scopeId': 'child', 'headHash': 'old'}),
        containsPair('direct', head),
      );
      expect(calls, ['capabilities', 'crypto2.authority.snapshot', head]);
    },
  );

  test(
    'writes and unsigned observation writes end the whole snapshot',
    () async {
      for (final operation in [
        'crypto2.scope.activate',
        'crypto2.account.scopeObservation.put',
      ]) {
        calls.clear();
        final batch = snapshot();
        await batch.call(head, {'scopeId': 'child'});
        await batch.call(operation, {});
        expect(
          await batch.call(head, {'scopeId': 'child'}),
          containsPair('direct', head),
        );
        expect(calls, [
          'capabilities',
          'crypto2.authority.snapshot',
          operation,
          head,
        ]);
      }
      expect(mutations, 2);
    },
  );

  test(
    'expired pin identity lifecycle or generation rejects late bundle',
    () async {
      final loading = Completer<Map<String, dynamic>>();
      final batch = snapshot(
        override: (operation, params) {
          if (operation == 'crypto2.authority.snapshot') {
            calls.add(operation);
            return loading.future;
          }
          return read(operation, params);
        },
      );
      final pending = batch.call(head, {'scopeId': 'child'});
      await pumpEventQueue();
      valid = false;
      loading.complete(reply);
      expect(await pending, containsPair('direct', head));
      expect(calls, ['capabilities', 'crypto2.authority.snapshot', head]);
    },
  );

  test(
    'old advertisement skips snapshot and preserves exact ordinary read',
    () async {
      advertised = false;
      final batch = snapshot();
      await batch.call(status, {});
      await batch.call(head, {'scopeId': 'child'});
      expect(calls, ['capabilities', status, head]);
    },
  );

  test(
    'finite snapshot capacity falls back but authorization errors propagate',
    () async {
      for (final code in [
        'crypto_authority_snapshot_capacity',
        'permission_revoked',
        'rate_limited',
      ]) {
        calls.clear();
        final batch = snapshot(
          override: (operation, params) async {
            if (operation == 'crypto2.authority.snapshot') {
              calls.add(operation);
              throw CollaborationApiException(code);
            }
            return read(operation, params);
          },
        );
        if (code == 'crypto_authority_snapshot_capacity') {
          expect(await batch.call(status, {}), containsPair('direct', status));
          await batch.call(head, {'scopeId': 'child'});
          expect(calls, [
            'capabilities',
            'crypto2.authority.snapshot',
            status,
            head,
          ]);
        } else {
          await expectLater(
            batch.call(status, {}),
            throwsA(isA<CollaborationApiException>()),
          );
          expect(calls, ['capabilities', 'crypto2.authority.snapshot']);
        }
      }
    },
  );

  test(
    'own verified generation is a cursor hint and does not change read key',
    () async {
      final batch = CryptoAuthoritySnapshot(
        read: (operation, params) async {
          if (operation == 'crypto2.authority.snapshot') {
            expect(params['accountAfterGeneration'], 21);
          }
          return read(operation, params);
        },
        serverId: 'server',
        accountId: 'account',
        deviceId: 'device',
        isValid: () async => valid,
        onMutation: () => mutations++,
        accountAfterGeneration: () async => 21,
      );
      expect(await batch.call(status, {}), {'signed': 'original'});
    },
  );

  test(
    'malformed bundle is rejected atomically before any result admitted',
    () async {
      for (final corrupt in <void Function(Map<String, dynamic>)>[
        (value) => value['accountId'] = 'another',
        (value) => value['serverId'] = 'another',
        (value) => value['deviceId'] = 'another',
        (value) => value['version'] = 2,
        (value) => (value['entries'] as List).add(entry(status, {})),
        (value) =>
            (value['entries'] as List).add(entry('crypto2.records.batch', {})),
        (value) => (value['entries'] as List).add({
          ...entry(head, {'scopeId': 'bad'}),
          'error': {'code': 'denied'},
        }),
      ]) {
        reply = envelope([entry(status, {})]);
        corrupt(reply);
        await expectLater(snapshot().call(status, {}), throwsFormatException);
      }
    },
  );

  test(
    'pending and first historical or paginated reads never expand authority',
    () async {
      final batch = snapshot();
      for (final params in [
        {
          'scopeId': 'child',
          'pendingCapability': {'token': 'private'},
        },
        {'scopeId': 'child', 'headHash': 'historical'},
        {'scopeId': 'child', 'afterRevision': 20},
      ]) {
        expect(await batch.call(head, params), containsPair('direct', head));
      }
      expect(calls, [head, head, head]);
    },
  );

  test(
    'concurrent legacy expired or closed waiters never start another snapshot',
    () async {
      for (final boundary in ['legacy', 'expired', 'closed']) {
        calls.clear();
        valid = true;
        final capabilities = Completer<Map<String, dynamic>>();
        final batch = snapshot(
          override: (operation, params) {
            if (operation == 'capabilities') {
              calls.add(operation);
              return capabilities.future;
            }
            return read(operation, params);
          },
        );
        final pending = Future.wait([
          batch.call(status, {}),
          batch.call(head, {'scopeId': 'child'}),
        ]);
        await pumpEventQueue();
        expect(calls, ['capabilities']);
        if (boundary == 'expired') valid = false;
        if (boundary == 'closed') batch.close();
        capabilities.complete({
          'serverId': 'server',
          if (boundary != 'legacy') 'cryptoAuthoritySnapshotVersions': [1],
        });
        final results = await pending;
        expect(results[0], containsPair('direct', status));
        expect(results[1], containsPair('direct', head));
        expect(calls.first, 'capabilities');
        expect(calls.skip(1), unorderedEquals([status, head]));
      }
    },
  );

  test(
    'concurrent account and child consumers share one in-flight bundle',
    () async {
      final batch = snapshot();
      await Future.wait([
        batch.call(status, {}),
        batch.call(head, {'scopeId': 'child'}),
      ]);
      expect(calls, ['capabilities', 'crypto2.authority.snapshot']);
    },
  );
  test(
    'new record policy status and baseline preserve exact authority bundle',
    () async {
      final batch = snapshot();
      await batch.call(head, {'scopeId': 'child'});
      await batch.call('crypto2.scope.recordPolicy.status', {
        'scopeId': 'child',
      });
      await batch.call('crypto2.scope.recordPolicy.baseline', {
        'scopeId': 'child',
        'recordId': 'target',
      });
      expect(await batch.call(head, {'scopeId': 'child'}), {
        'signed': 'original',
      });
      expect(mutations, 0);
      expect(calls, [
        'capabilities',
        'crypto2.authority.snapshot',
        'crypto2.scope.recordPolicy.status',
        'crypto2.scope.recordPolicy.baseline',
      ]);
    },
  );
  test(
    'new record policy mutations still invalidate authority bundle',
    () async {
      final batch = snapshot();
      await batch.call(head, {'scopeId': 'child'});
      await batch.call('crypto2.scope.recordPolicy.stage', {
        'commandBase64': 'signed',
      });
      expect(mutations, 1);
    },
  );
}
