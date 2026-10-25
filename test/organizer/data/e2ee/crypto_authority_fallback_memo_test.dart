import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/crypto_authority_snapshot.dart';

const head = 'crypto2.scope.headGet';
const directory = 'crypto2.directory.status';
const receipt = 'crypto2.receipt.get';

class _Reads {
  bool valid = true;
  int mutations = 0;
  final requests = <({String operation, Map<String, dynamic> params})>[];
  final bundle = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? fallback;
  late final snapshot = CryptoAuthoritySnapshot(
    read: read,
    serverId: 'server',
    accountId: 'account',
    deviceId: 'device',
    isValid: () async => valid,
    onMutation: () => mutations++,
  );

  Future<Map<String, dynamic>> read(
    String operation,
    Map<String, dynamic> params,
  ) async {
    requests.add((operation: operation, params: Map.of(params)));
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
        'entries': bundle,
      };
    }
    return fallback?.call(operation, params) ??
        {
          'proof': {'value': 'original'},
          'params': Map.of(params),
        };
  }

  int count(String operation) =>
      requests.where((r) => r.operation == operation).length;
}

void main() {
  test(
    'authority fallback memo preserves bundle priority exact selectors singleflight and independent maps',
    () async {
      final reads = _Reads();
      final current = {'scopeId': 'scope'};
      reads.bundle.add({
        'operation': head,
        'params': current,
        'result': {
          'proof': {'value': 'bundled'},
        },
      });
      expect((await reads.snapshot.call(head, current))['proof'], {
        'value': 'bundled',
      });
      expect(reads.count(head), 0);
      final waiting = Completer<Map<String, dynamic>>();
      reads.fallback = (op, p) => waiting.future;
      final historical = {
        'scopeId': 'scope',
        'headHash': 'old',
        'accountId': 'member',
        'directoryHeadHash': 'prefix',
      };
      final first = reads.snapshot.call(directory, historical);
      final second = reads.snapshot.call(
        directory,
        Map.fromEntries(historical.entries.toList().reversed),
      );
      await pumpEventQueue();
      expect(reads.count(directory), 1);
      waiting.complete({
        'proof': {'value': 'original'},
      });
      final values = await Future.wait([first, second]);
      (values.first['proof'] as Map)['value'] = 'changed';
      expect(values.last['proof'], {'value': 'original'});
      expect((await reads.snapshot.call(directory, historical))['proof'], {
        'value': 'original',
      });
      expect(reads.count(directory), 1);
      reads.fallback = null;
      for (final selector in [
        {...historical, 'scopeId': 'other'},
        {...historical, 'headHash': 'new'},
        {...historical, 'accountId': 'other'},
        {...historical, 'directoryHeadHash': 'other'},
      ]) {
        await reads.snapshot.call(directory, selector);
      }
      expect(reads.count(directory), 5);
      await reads.snapshot.call(head, {
        'scopeId': 'scope',
        'headHash': 'historical',
      });
      await reads.snapshot.call(head, {
        'headHash': 'historical',
        'scopeId': 'scope',
      });
      expect(reads.count(head), 1);
      expect(reads.count('crypto2.authority.snapshot'), 1);
    },
  );

  test(
    'authority fallback memo expires on original validity and mutation excludes late results',
    () async {
      final expired = _Reads();
      final p = {'scopeId': 'scope', 'headHash': 'historical'};
      await expired.snapshot.call(head, p);
      expired.valid = false;
      await expired.snapshot.call(head, p);
      await expired.snapshot.call(head, p);
      expect(expired.count(head), 3);
      final reads = _Reads(), waiting = Completer<Map<String, dynamic>>();
      var first = true;
      reads.fallback = (op, p) {
        if (op == directory && first) {
          first = false;
          return waiting.future;
        }
        return Future.value({
          'proof': {'value': 'fresh'},
        });
      };
      final pending = reads.snapshot.call(directory, p);
      await pumpEventQueue();
      await reads.snapshot.call('crypto2.records.batch', {
        'commandBase64': 'exact-signed-command',
      });
      expect(reads.mutations, 1);
      waiting.complete({
        'proof': {'value': 'stale'},
      });
      expect((await pending)['proof'], {'value': 'fresh'});
      await reads.snapshot.call(directory, p);
      expect(reads.count(directory), 3);
      expect(reads.count('crypto2.authority.snapshot'), 0);
    },
  );

  test(
    'authority fallback memo never retains errors receipts or pending capabilities',
    () async {
      final reads = _Reads();
      final p = {'scopeId': 'scope', 'headHash': 'historical'};
      reads.fallback = (op, p) async =>
          throw const CollaborationApiException('permission_revoked');
      for (var i = 0; i < 2; i++) {
        await expectLater(
          reads.snapshot.call(directory, p),
          throwsA(isA<CollaborationApiException>()),
        );
      }
      expect(reads.count(directory), 2);
      reads.fallback = null;
      await reads.snapshot.call(directory, p);
      await reads.snapshot.call(directory, p);
      expect(reads.count(directory), 3);
      for (var i = 0; i < 2; i++) {
        await reads.snapshot.call(head, {...p, 'pendingCapability': 'opaque'});
        await reads.snapshot.call(receipt, {
          'requestId': 'retained-exact-request',
        });
      }
      expect(reads.count(head), 2);
      expect(reads.count(receipt), 2);
    },
  );

  test(
    'authority fallback memo shares existing entry and byte bounds without evicting or extending lease',
    () async {
      final bounded = _Reads();
      for (var i = 0; i < 64; i++) {
        await bounded.snapshot.call(head, {
          'scopeId': 'scope',
          'headHash': 'old-$i',
        });
      }
      await bounded.snapshot.call(head, {
        'scopeId': 'scope',
        'headHash': 'old-0',
      });
      expect(bounded.count(head), 64);
      for (var i = 0; i < 2; i++) {
        await bounded.snapshot.call(head, {
          'scopeId': 'scope',
          'headHash': 'over-capacity',
        });
      }
      expect(bounded.count(head), 66);
      final large = _Reads();
      large.fallback = (op, p) async => {'ciphertext': 'x' * (512 * 1024)};
      final p = {'scopeId': 'scope', 'headHash': 'large'};
      for (var i = 0; i < 2; i++) {
        expect(
          utf8.encode(jsonEncode(await large.snapshot.call(head, p))).length,
          greaterThan(512 * 1024),
        );
      }
      expect(large.count(head), 2);
    },
  );
}
