import 'dart:convert';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Transport implements CollaborationTransport {
  late Future<Map<String, dynamic>> Function(String, Map<String, Object?>)
  handler;
  final calls = <String>[];
  final mutations = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    if (operation != 'crypto2.receipt.get') mutations.add(params);
    return handler(operation, params);
  }

  @override
  void close() {}
}

class _Fixture {
  _Fixture(this.crypto) {
    session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: crypto.randomId(),
        accountId: crypto.randomId(),
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        deviceId: crypto.randomId(),
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic',
    );
    store = CryptoSyncStore(db, session.profile.partition);
    keys = crypto.sodium.crypto.sign.keyPair();
    queue = CryptoSyncRepository(
      crypto: crypto,
      session: session,
      transport: transport,
      store: store,
      signingKey: () async => CryptoKeyLease.borrowed(keys.secretKey),
      authorKey: (_) async => throw StateError('not a projection test'),
      contentKey: (_) async => throw StateError('not a projection test'),
      project: (_) async => throw StateError('not a projection test'),
      isCurrent: () => current,
      beforeDelivery: (signed) async {
        guardCalls++;
        events.add('guard');
        await beforeGuard?.call();
        if (guardReason != null) throw CryptoAuthorityPending(guardReason!);
      },
      heldSignerPublicKey: () async => keys.publicKey,
    );
    transport.handler = (operation, params) async {
      events.add(operation);
      if (operation == 'crypto2.receipt.get') {
        await beforeReceipt?.call();
        if (receiptMode == 'denied') {
          throw const CollaborationApiException(
            'crypto_receipt_scope_required',
          );
        }
        if (receiptMode == 'unknown') return {'outcome': 'unknown'};
        final row = (await store.outgoing(params['requestId'] as String))!;
        return {
          'outcome': 'recorded',
          'requestId': row['request_id'],
          'requestHash': receiptMode == 'substituted'
              ? '0' * 64
              : row['request_hash'],
          'authorization': jsonDecode(row['signed_body'] as String),
          'status': receiptMode == 'rejected' ? 409 : 200,
          'response': {'status': 'applied'},
        };
      }
      final row = (await store.outgoing(id))!;
      expect(row['state'], 'blocked', reason: 'never automatic retry');
      expect(params, jsonDecode(row['signed_body'] as String));
      if (throwOnMutation) throw StateError('synthetic lost transport');
      if (applyOnMutation) receiptMode = 'applied';
      return {'status': 'applied'};
    };
  }
  final CryptoCodec crypto;
  final db = CollaborationDatabase(NativeDatabase.memory());
  final transport = _Transport();
  late final DeviceSession session;
  late final CryptoSyncStore store;
  late final KeyPair keys;
  late final CryptoSyncRepository queue;
  late String id;
  var current = true, applyOnMutation = true, throwOnMutation = false;
  String? guardReason = 'scope_rotation_required';
  String receiptMode = 'unknown';
  var guardCalls = 0, currentChecks = 0;
  final events = <String>[];
  Future<void> Function()? beforeGuard, beforeReceipt;
  Future<void> checkCurrent() async {
    currentChecks++;
    if (!current) throw StateError('stale lease/session');
  }

  Future<void> held({String code = 'scope_rotation_required'}) async {
    id = await queue.enqueueCommand(
      actionKey: crypto.randomId(),
      operation: 'crypto2.domain.checkpoint',
      payload: {
        'scopeId': crypto.randomId(),
        'domain': 'content',
        'epoch': 1,
        'head': 'a' * 64,
      },
    );
    await queue.deliver();
    expect((await store.outgoing(id))!['state'], 'blocked');
    if (code != 'scope_rotation_required') {
      await db.execute(
        'UPDATE crypto_outbox SET response=? WHERE request_id=?',
        [
          jsonEncode({
            'outcome': 'unresolved',
            'reason': 'authority_pending',
            'code': code,
          }),
          id,
        ],
      );
    }
    transport.calls.clear();
    events.clear();
    guardCalls = 0;
  }

  Future<void> resume({Future<void> Function(String, bool)? onTerminal}) =>
      queue.resumeHeldCommands(
        requestIds: {id},
        checkCurrent: checkCurrent,
        onTerminal: onTerminal,
      );
  Future<void> close() async {
    keys.secretKey.dispose();
    await db.close();
  }
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  Future<_Fixture> fixture({String code = 'scope_rotation_required'}) async {
    final f = _Fixture(crypto);
    addTearDown(f.close);
    await f.held(code: code);
    return f;
  }

  test(
    'manual resume fresh resolved guard sends original signed bytes and settles applied',
    () async {
      final f = await fixture();
      final before = (await f.store.outgoing(f.id))!;
      await f.store.claimRecord({
        'scopeId': crypto.randomId(),
        'domain': 'content',
        'id': crypto.randomId(),
        'expectedRevision': 0,
      }, f.id);
      final claims = await f.db.rows('SELECT * FROM crypto_outbox_records');
      f.guardReason = null;
      await f.resume(
        onTerminal: (id, applied) async {
          expect(applied, true);
          await f.db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
            'refresh-marker',
            id,
          ]);
        },
      );
      final after = (await f.store.outgoing(f.id))!;
      expect(f.events, [
        'crypto2.receipt.get',
        'guard',
        'crypto2.domain.checkpoint',
        'crypto2.receipt.get',
      ]);
      expect(after['state'], 'applied');
      for (final key in [
        'request_id',
        'signed_body',
        'request_hash',
        'operation',
      ]) {
        expect(after[key], before[key]);
      }
      expect(await f.db.rows('SELECT * FROM crypto_outbox_records'), claims);
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          'refresh-marker',
        ]),
        [
          {'value': f.id},
        ],
      );
    },
  );
  test(
    'manual resume unchanged rotation guard stays held without mutation',
    () async {
      final f = await fixture();
      final before = (await f.store.outgoing(f.id))!;
      await f.resume();
      expect(f.guardCalls, 1);
      expect(f.transport.mutations, isEmpty);
      final after = (await f.store.outgoing(f.id))!;
      expect(after['state'], 'blocked');
      expect(after['signed_body'], before['signed_body']);
      expect(
        jsonDecode(after['response'] as String)['code'],
        'scope_rotation_required',
      );
    },
  );
  test(
    'manual resume actual rotated stale head reports fresh reason and preserves immutable work',
    () async {
      final f = await fixture();
      final before = (await f.store.outgoing(f.id))!;
      f.guardReason = 'scope_reauthorization_required';
      await f.resume();
      final after = (await f.store.outgoing(f.id))!;
      expect(f.transport.mutations, isEmpty);
      expect(after['state'], 'blocked');
      expect(after['signed_body'], before['signed_body']);
      expect(after['request_hash'], before['request_hash']);
      expect(
        jsonDecode(after['response'] as String)['code'],
        'scope_reauthorization_required',
      );
    },
  );
  test(
    'manual resume unrelated unresolved guard remains receipt only',
    () async {
      final f = await fixture(code: 'crypto_domain_operation_pending');
      final before = await f.store.outgoing(f.id);
      f.guardReason = null;
      await f.resume();
      expect(f.transport.calls, ['crypto2.receipt.get']);
      expect(f.guardCalls, 0);
      expect(await f.store.outgoing(f.id), before);
    },
  );
  test(
    'manual resume historical applied receipt skips fresh authority and mutation',
    () async {
      final f = await fixture();
      f.receiptMode = 'applied';
      await f.resume();
      expect(f.guardCalls, 0);
      expect(f.transport.mutations, isEmpty);
      expect((await f.store.outgoing(f.id))!['state'], 'applied');
    },
  );
  test(
    'manual resume exact rejected receipt retains held row without invoking guard',
    () async {
      final f = await fixture();
      final before = await f.store.outgoing(f.id);
      f.receiptMode = 'rejected';
      final results = <bool>[];
      await f.resume(
        onTerminal: (_, applied) async {
          results.add(applied);
        },
      );
      expect(results, [false]);
      expect(f.guardCalls, 0);
      expect(await f.store.outgoing(f.id), before);
    },
  );
  test(
    'manual resume denied receipt never grants authority or mutates',
    () async {
      final f = await fixture();
      final before = await f.store.outgoing(f.id);
      f.receiptMode = 'denied';
      await f.resume();
      expect(f.guardCalls, 0);
      expect(await f.store.outgoing(f.id), before);
    },
  );
  test(
    'manual resume historical signer cannot resend even if current scope ready',
    () async {
      final f = await fixture();
      final row = (await f.store.outgoing(f.id))!;
      final signed =
          jsonDecode(row['signed_body'] as String) as Map<String, dynamic>;
      final command =
          CryptoJson.decode(cryptoBase64(signed['commandBase64']))
              as Map<String, dynamic>;
      command['deviceId'] = crypto.randomId();
      final other = crypto.signDomain(
        command,
        f.keys.secretKey,
        'JivieE2EE/v2\n',
      );
      // Update only this synthetic retained fixture, including its exact command hash.
      final digest = await cryptoShaForTest(other);
      await f.db.execute(
        'UPDATE crypto_outbox SET signed_body=?,request_hash=? WHERE request_id=?',
        [jsonEncode(other), digest, f.id],
      );
      f.guardReason = null;
      await f.resume();
      expect(f.transport.mutations, isEmpty);
      expect(f.guardCalls, 0);
      expect(
        jsonDecode(
          (await f.store.outgoing(f.id))!['response'] as String,
        )['code'],
        'crypto_device_keys_pending',
      );
    },
  );
  test(
    'manual resume forged current-device signature is rejected before mutation',
    () async {
      final f = await fixture();
      final row = (await f.store.outgoing(f.id))!;
      final signed =
          jsonDecode(row['signed_body'] as String) as Map<String, dynamic>;
      signed['signatureBase64'] = base64Encode(List<int>.filled(64, 0));
      await f.db.execute(
        'UPDATE crypto_outbox SET signed_body=? WHERE request_id=?',
        [jsonEncode(signed), f.id],
      );
      f.guardReason = null;
      await expectLater(f.resume(), throwsFormatException);
      expect(f.transport.mutations, isEmpty);
      expect((await f.store.outgoing(f.id))!['state'], 'blocked');
    },
  );
  test(
    'manual resume stale session after fresh guard cannot send or change row',
    () async {
      final f = await fixture();
      final before = await f.store.outgoing(f.id);
      f.guardReason = null;
      f.beforeGuard = () async {
        f.current = false;
      };
      await expectLater(f.resume(), throwsStateError);
      expect(f.transport.mutations, isEmpty);
      expect(await f.store.outgoing(f.id), before);
    },
  );
  test(
    'manual resume concurrent retained-state change fails CAS before mutation',
    () async {
      final f = await fixture();
      f.guardReason = null;
      f.beforeGuard = () async {
        await f.db.execute(
          'UPDATE crypto_outbox SET response=? WHERE request_id=?',
          [
            jsonEncode({'outcome': 'unresolved', 'reason': 'forbidden'}),
            f.id,
          ],
        );
      };
      await expectLater(f.resume(), throwsFormatException);
      expect(f.transport.mutations, isEmpty);
      expect((await f.store.outgoing(f.id))!['state'], 'blocked');
    },
  );
  test(
    'manual resume transport interruption remains held and automatic delivery stays empty',
    () async {
      final f = await fixture();
      f.guardReason = null;
      f.throwOnMutation = true;
      await expectLater(f.resume(), throwsStateError);
      expect((await f.store.outgoing(f.id))!['state'], 'blocked');
      f.transport.calls.clear();
      await f.queue.deliver();
      expect(f.transport.calls, isEmpty);
    },
  );
  test(
    'manual resume unknown after delivery remains held for another explicit attempt',
    () async {
      final f = await fixture();
      f.guardReason = null;
      f.applyOnMutation = false;
      await f.resume();
      expect((await f.store.outgoing(f.id))!['state'], 'blocked');
      expect(f.transport.mutations, hasLength(1));
      f.transport.calls.clear();
      await f.queue.deliver();
      expect(f.transport.calls, isEmpty);
    },
  );
  test(
    'manual resume generation marker failure rolls terminal receipt back to held',
    () async {
      final f = await fixture();
      f.guardReason = null;
      await expectLater(
        f.resume(
          onTerminal: (_, applied) async {
            throw StateError('marker fault');
          },
        ),
        throwsStateError,
      );
      expect((await f.store.outgoing(f.id))!['state'], 'blocked');
    },
  );
  test(
    'manual resume exact selection cannot widen and rejects oversized inventory before network',
    () async {
      final f = await fixture();
      await expectLater(
        f.queue.resumeHeldCommands(
          requestIds: {for (var i = 0; i < 65; i++) crypto.randomId()},
          checkCurrent: f.checkCurrent,
        ),
        throwsFormatException,
      );
      expect(f.transport.calls, isEmpty);
      await f.db.execute(
        'UPDATE crypto_outbox SET response=? WHERE request_id=?',
        ['x' * 1048576, f.id],
      );
      await expectLater(f.resume(), throwsFormatException);
      expect(f.transport.calls, isEmpty);
    },
  );
  test(
    'manual resume readonly unknown lookup validates exact hash and preserves queue',
    () async {
      final f = await fixture();
      final before = (await f.store.outgoing(f.id))!;
      expect(
        await f.queue.hasUnknownHeldReceipt(
          requestId: f.id,
          requestHash: before['request_hash'] as String,
          checkCurrent: f.checkCurrent,
        ),
        true,
      );
      expect(await f.store.outgoing(f.id), before);
      expect(f.guardCalls, 0);
      await expectLater(
        f.queue.hasUnknownHeldReceipt(
          requestId: f.id,
          requestHash: '0' * 64,
          checkCurrent: f.checkCurrent,
        ),
        throwsFormatException,
      );
      expect(f.transport.calls, ['crypto2.receipt.get']);
    },
  );
}

Future<String> cryptoShaForTest(Map<String, dynamic> signed) async =>
    (await Sha256().hash(
      cryptoBase64(signed['commandBase64']),
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
