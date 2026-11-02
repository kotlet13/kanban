import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
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
    'diagnostic current guard is distinct from unknown receipt and immutable command stays held',
    () async {
      final f = await fixture();
      final before = (await f.store.outgoing(f.id))!;
      f.guardReason = 'crypto_device_keys_pending';
      final samples = <HeldCommandDiagnostic>[];
      await f.queue.resumeHeldCommands(
        requestIds: {f.id},
        checkCurrent: f.checkCurrent,
        observe: (id, hash, detail) {
          expect(id, f.id);
          expect(hash, before['request_hash']);
          samples.add(detail);
        },
      );
      expect(samples.last.receipt, HeldReceiptResult.unknown);
      expect(samples.last.resume, HeldResumeResult.guardBlocked);
      expect(samples.last.currentReason, 'crypto_device_keys_pending');
      expect(f.transport.calls, ['crypto2.receipt.get']);
      expect(
        (await f.store.outgoing(f.id))!['signed_body'],
        before['signed_body'],
      );
      expect((await f.store.outgoing(f.id))!['state'], 'blocked');
    },
  );
  test(
    'diagnostic lookup denial is captured without claiming server unknown or resending',
    () async {
      final f = await fixture();
      f.receiptMode = 'denied';
      HeldCommandDiagnostic? last;
      await f.queue.resumeHeldCommands(
        requestIds: {f.id},
        checkCurrent: f.checkCurrent,
        observe: (_, __, d) => last = d,
      );
      expect(last!.receipt, HeldReceiptResult.denied);
      expect(last!.currentReason, 'crypto_receipt_scope_required');
      expect(last!.resume, HeldResumeResult.notAttempted);
      expect(f.transport.calls, ['crypto2.receipt.get']);
      expect(f.guardCalls, 0);
    },
  );
  test(
    'diagnostic other held reason reports ineligible with no mutation',
    () async {
      final f = await fixture(code: 'scope_reauthorization_required');
      HeldCommandDiagnostic? last;
      await f.queue.resumeHeldCommands(
        requestIds: {f.id},
        checkCurrent: f.checkCurrent,
        observe: (_, __, d) => last = d,
      );
      expect(last!.receipt, HeldReceiptResult.unknown);
      expect(last!.resume, HeldResumeResult.ineligible);
      expect(f.transport.mutations, isEmpty);
    },
  );
  test(
    'diagnostic send without final receipt remains unknown and blocked',
    () async {
      final f = await fixture();
      f.guardReason = null;
      f.applyOnMutation = false;
      HeldCommandDiagnostic? last;
      await f.queue.resumeHeldCommands(
        requestIds: {f.id},
        checkCurrent: f.checkCurrent,
        observe: (_, __, d) => last = d,
      );
      expect(last!.receipt, HeldReceiptResult.unknown);
      expect(last!.resume, HeldResumeResult.sent);
      expect(f.transport.calls, [
        'crypto2.receipt.get',
        'crypto2.domain.checkpoint',
        'crypto2.receipt.get',
      ]);
      expect((await f.store.outgoing(f.id))!['state'], 'blocked');
    },
  );
  for (final mode in ['applied', 'rejected']) {
    test(
      'diagnostic verified terminal $mode is observed without extra HTTP',
      () async {
        final f = await fixture();
        f.receiptMode = mode;
        HeldCommandDiagnostic? last;
        await f.queue.resumeHeldCommands(
          requestIds: {f.id},
          checkCurrent: f.checkCurrent,
          observe: (_, __, d) => last = d,
        );
        expect(
          last!.receipt,
          mode == 'applied'
              ? HeldReceiptResult.applied
              : HeldReceiptResult.rejected,
        );
        expect(f.transport.calls, ['crypto2.receipt.get']);
        expect(
          (await f.store.outgoing(f.id))!['state'],
          mode == 'applied' ? 'applied' : 'blocked',
        );
      },
    );
  }
  test(
    'throwing diagnostic consumer cannot block a valid exact resend',
    () async {
      final f = await fixture();
      f.guardReason = null;
      await f.queue.resumeHeldCommands(
        requestIds: {f.id},
        checkCurrent: f.checkCurrent,
        observe: (_, __, d) => throw StateError('observer only'),
      );
      expect((await f.store.outgoing(f.id))!['state'], 'applied');
      expect(f.transport.calls, [
        'crypto2.receipt.get',
        'crypto2.domain.checkpoint',
        'crypto2.receipt.get',
      ]);
    },
  );
  test('unbound receipt is never observed as confirmed execution', () async {
    final f = await fixture();
    f.receiptMode = 'substituted';
    HeldCommandDiagnostic? last;
    await expectLater(
      f.queue.resumeHeldCommands(
        requestIds: {f.id},
        checkCurrent: f.checkCurrent,
        observe: (_, __, d) => last = d,
      ),
      throwsFormatException,
    );
    expect(last!.receipt, HeldReceiptResult.notChecked);
    expect((await f.store.outgoing(f.id))!['state'], 'blocked');
  });
  test(
    'server errorCode in validated rejected receipt is captured without details',
    () async {
      final f = await fixture();
      f.receiptMode = 'rejected';
      final handler = f.transport.handler;
      f.transport.handler = (op, params) async {
        final result = await handler(op, params);
        if (op == 'crypto2.receipt.get') {
          result['response'] = {
            'errorCode': 'scope_rotation_required',
            'details': {'private': 'must not leave'},
          };
        }
        return result;
      };
      HeldCommandDiagnostic? last;
      await f.queue.resumeHeldCommands(
        requestIds: {f.id},
        checkCurrent: f.checkCurrent,
        observe: (_, __, d) => last = d,
      );
      expect(last!.receipt, HeldReceiptResult.rejected);
      expect(last!.currentReason, 'scope_rotation_required');
      expect(
        jsonEncode(last!.toJson(safeSyncFailureReason)),
        isNot(contains('private')),
      );
      expect((await f.store.outgoing(f.id))!['state'], 'blocked');
    },
  );
}
