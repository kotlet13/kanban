import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/crypto_authority_snapshot.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_checkpoint.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:sodium/sodium.dart';

void main() {
  const observations = 'crypto2.account.scopeObservations';
  const inventory = 'crypto2.domain.inventory';
  var valid = true, mutations = 0;
  final calls = <String>[];
  Future<Map<String, dynamic>> read(String op, Map<String, dynamic> p) async {
    calls.add(op);
    return {
      'nested': {'value': calls.length},
      'params': p,
    };
  }

  CryptoAuthoritySnapshot snapshot({CryptoAuthorityRead? transport}) =>
      CryptoAuthoritySnapshot(
        read: transport ?? read,
        serverId: 'server',
        accountId: 'account',
        deviceId: 'device',
        isValid: () async => valid,
        onMutation: () => mutations++,
      );
  setUp(() {
    valid = true;
    mutations = 0;
    calls.clear();
  });

  test(
    'exact wire pages coalesce concurrent and sequential consumers with independent deep copies',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final memo = snapshot(
        transport: (op, p) {
          calls.add(op);
          return gate.future;
        },
      );
      final pending = Future.wait([
        memo.call(observations, {'limit': 20, 'afterGeneration': 0}),
        memo.call(observations, {'afterGeneration': 0, 'limit': 20}),
      ]);
      await pumpEventQueue();
      expect(calls, [observations]);
      gate.complete({
        'observations': [
          {'generation': 3},
        ],
        'hasMore': false,
      });
      final values = await pending;
      (values.first['observations'] as List).clear();
      expect(values.last['observations'], hasLength(1));
      expect(
        (await memo.call(observations, {
          'afterGeneration': 0,
          'limit': 20,
        }))['observations'],
        hasLength(1),
      );
      expect(calls, [observations]);
    },
  );

  test(
    'scope domain checkpoint selector pagination and parameter types stay isolated',
    () async {
      final memo = snapshot();
      for (final p in <Map<String, dynamic>>[
        {'scopeId': 'a', 'domain': 'content', 'limit': 50},
        {'scopeId': 'b', 'domain': 'content', 'limit': 50},
        {'scopeId': 'a', 'domain': 'finance', 'limit': 50},
        {'scopeId': 'a', 'domain': 'content', 'limit': 50, 'afterId': 'next'},
        {
          'scopeId': 'a',
          'domain': 'content',
          'limit': 50,
          'checkpoint': {'sequence': 1},
        },
        {'scopeId': 'a', 'domain': 'content', 'limit': '50'},
      ]) {
        await memo.call(inventory, p);
        await memo.call(inventory, Map.of(p));
      }
      expect(calls, List.filled(6, inventory));
    },
  );

  test(
    'lease invalidation and fresh snapshot do not reuse successful wire pages',
    () async {
      final memo = snapshot();
      await memo.call(observations, {});
      valid = false;
      await memo.call(observations, {});
      await snapshot().call(observations, {});
      expect(calls, List.filled(3, observations));
    },
  );

  test(
    'mutation unknown signed-command and pending capability paths do not reuse pages',
    () async {
      for (final op in [
        'crypto2.account.scopeObservation.put',
        'unknown.operation',
        inventory,
      ]) {
        final memo = snapshot();
        await memo.call(observations, {});
        await memo.call(op, op == inventory ? {'commandBase64': 'signed'} : {});
        await memo.call(observations, {});
      }
      expect(mutations, 3);
      final memo = snapshot();
      for (var i = 0; i < 2; i++) {
        await memo.call(observations, {
          'pendingCapability': {'token': 'synthetic'},
        });
      }
      expect(calls.where((op) => op == observations), hasLength(8));
    },
  );

  test(
    'late response after closed or invalid lease uses ordinary fresh endpoint',
    () async {
      for (final close in [false, true]) {
        valid = true;
        final gate = Completer<Map<String, dynamic>>();
        var count = 0;
        final memo = snapshot(
          transport: (op, p) async {
            count++;
            return count == 1 ? gate.future : {'fresh': count};
          },
        );
        final pending = memo.call(inventory, {});
        await pumpEventQueue();
        if (close) {
          memo.close();
        } else {
          valid = false;
        }
        gate.complete({'stale': true});
        expect(await pending, {'fresh': 2});
        expect(count, 2);
      }
    },
  );

  test(
    'coalesced errors propagate without retaining failure or retrying',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      var count = 0;
      final memo = snapshot(
        transport: (op, p) async {
          count++;
          return count == 1 ? gate.future : {'fresh': count};
        },
      );
      final first = expectLater(
        memo.call(observations, {}),
        throwsA(isA<CollaborationApiException>()),
      );
      final second = expectLater(
        memo.call(observations, {}),
        throwsA(isA<CollaborationApiException>()),
      );
      await pumpEventQueue();
      gate.completeError(const CollaborationApiException('rate_limited'));
      await Future.wait([first, second]);
      expect(count, 1);
      expect(await memo.call(observations, {}), {'fresh': 2});
    },
  );

  test(
    'entry and byte bounds preserve ordinary reads without growing retained data',
    () async {
      final memo = snapshot();
      for (var i = 0; i < 65; i++) {
        await memo.call(inventory, {'page': i});
      }
      await memo.call(inventory, {'page': 0});
      await memo.call(inventory, {'page': 64});
      expect(calls, hasLength(66));
      var largeCalls = 0;
      final large = snapshot(
        transport: (op, p) async {
          largeCalls++;
          return {'body': 'a' * (512 * 1024)};
        },
      );
      await large.call(inventory, {});
      await large.call(inventory, {});
      expect(largeCalls, 2);
    },
  );

  test(
    'production checkpoint reader repeats signature verification while two exact inventories become one',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init());
      final codec = CryptoRecordProofCodec(crypto);
      final key = crypto.sodium.crypto.sign.keyPair();
      addTearDown(key.dispose);
      final scope = crypto.randomId();
      const context = CryptoReadContext(
        epoch: 1,
        accessRevision: 1,
        headHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      final hash = (await Sha256().hash(
        [],
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final proof = codec.signCommand({
        'version': 2,
        'operation': 'crypto2.domain.checkpoint',
        'requestId': crypto.randomId(),
        'serverId': crypto.randomId(),
        'accountId': crypto.randomId(),
        'deviceId': crypto.randomId(),
        'signer': 'device',
        'payload': {
          'scopeId': scope,
          'domain': 'content',
          'epoch': 1,
          'membershipHeadHash': context.headHash,
          'accessRevision': 1,
          'expectedSequence': 0,
          'recordCount': 0,
          'manifestHash': hash,
          'historyBasis': 'verifiedCheckpoint',
          'authorDirectoryHeadHash': 'b' * 64,
        },
      }, key.secretKey);
      final counts = <String, Map<String, int>>{};
      for (final memoized in [false, true]) {
        final db = CollaborationDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        var wire = 0, verified = 0;
        Future<Map<String, dynamic>> endpoint(
          String op,
          Map<String, dynamic> p,
        ) async {
          expect(op, inventory);
          wire++;
          return {
            'scopeId': scope,
            'domain': 'content',
            'epoch': 1,
            'membershipHeadHash': context.headHash,
            'scopeSequence': 0,
            'descriptors': [],
            'hasMore': false,
            'checkpoint': {
              'manifestHash': hash,
              'recordCount': 0,
              'membershipHeadHash': context.headHash,
              'domainSequence': 0,
              'attestations': [
                {'authorization': proof},
              ],
              'hasMore': false,
            },
          };
        }

        final memo = snapshot(transport: endpoint);
        final reader = CryptoDomainCheckpointReader(
          database: db,
          partition: 'synthetic',
          codec: codec,
          call: memoized ? memo.call : endpoint,
          verify: (p) async {
            crypto.verifyDomain(p, key.publicKey, 'JivieE2EE/v2\n');
            verified++;
            return 'verifiedCheckpoint';
          },
        );
        final first = await reader.reconcile(scope, 'content', context);
        expect(first, isNotNull);
        expect(await reader.reconcile(scope, 'content', context), first);
        expect(wire, memoized ? 1 : 2);
        expect(verified, 2);
        counts[memoized ? 'memo' : 'directBaseline'] = {
          'wireInventory': wire,
          'signedProofVerifications': verified,
        };
        memo.close();
      }
      // Bounded synthetic transport and actual SQLite/checkpoint/signature consumer;
      // this is not an HTTP/native peak-rate or full-sync result.
      // ignore: avoid_print
      print(jsonEncode({'productionConsumerCounts': counts}));
    },
  );
}
