import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_task_conflict.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_access_changes.dart';
import 'package:sodium/sodium.dart';

import 'crypto_full_sync_recovery_http_test.dart' as retained;

Map<String, dynamic> _copy(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

Future<void> _signedTaskConflictGuards() async {
  final crypto = CryptoCodec(await SodiumInit.init());
  final codec = CryptoRecordProofCodec(crypto);
  final pair = crypto.sodium.crypto.sign.keyPair();
  final key = crypto.sodium.crypto.aeadXChaCha20Poly1305IETF.keygen();
  try {
    final server = crypto.randomId(),
        account = crypto.randomId(),
        device = crypto.randomId(),
        scope = crypto.randomId(),
        task = crypto.randomId(),
        operation = crypto.randomId(),
        batch = crypto.randomId(),
        request = crypto.randomId();
    const partition = 'synthetic-partition', localHash = 'exact-local-intent';
    final reserved = await cryptoSha256(
      utf8.encode(
        'JivieReservedRecord/v2\n$server:$scope:taskDerivation:$task',
      ),
    );
    final intent =
        '${reserved.substring(0, 8)}-${reserved.substring(8, 12)}-4${reserved.substring(13, 16)}-a${reserved.substring(17, 20)}-${reserved.substring(20, 32)}';
    final proofs = <Map<String, dynamic>>[], claims = <Map<String, dynamic>>[];
    for (final entry in {
      'task': task,
      'taskDerivationIntent': intent,
    }.entries) {
      final address = CryptoRecordAddress.forType(
        serverId: server,
        scopeId: scope,
        domain: 'content',
        type: entry.key,
        canonicalId: entry.value,
      );
      proofs.add(
        codec.sealRecord(
          serverId: server,
          accountId: account,
          deviceId: device,
          batchId: batch,
          scopeId: scope,
          id: address.wireId,
          type: entry.key,
          expectedRevision: 1,
          epoch: 2,
          accessRevision: 2,
          membershipHeadHash: '1' * 64,
          domain: 'content',
          contentContract: 6,
          operationId: operation,
          previousRecordHash: '2' * 64,
          deleted: false,
          plaintext: Uint8List.fromList(utf8.encode('{}')),
          metadata: {
            'identity': address.identity,
            'references': <Object>[],
            'referenceVersions': <Object>[],
            'uniqueRefs': <String>[],
            'blobIds': <String>[],
            if (entry.key == 'task')
              'notificationState': {
                'version': 1,
                'kind': 'updated',
                'assigneeAccountIds': <String>[],
                'groupTargetId': null,
              },
            if (entry.key == 'task')
              'reminderState': {
                'version': 1,
                'dueAtEpoch': null,
                'closed': false,
                'scheduleRevision': device,
              },
          },
          contentKey: key,
          signingKey: pair.secretKey,
        ),
      );
      claims.add({
        'partition': partition,
        'scope_id': scope,
        'domain': 'content',
        'record_id': address.wireId,
        'expected_revision': 1,
        'request_id': request,
      });
    }
    final commitment = await codec.commitBatch(
      serverId: server,
      accountId: account,
      deviceId: device,
      batchId: batch,
      records: proofs,
      signingKey: pair.secretKey,
      projectionToken: (r) async => codec.projectionGroupToken(r, key),
    );
    final command = <String, dynamic>{
      'version': 2,
      'operation': 'crypto2.records.batch',
      'serverId': server,
      'accountId': account,
      'deviceId': device,
      'signer': 'device',
      'requestId': request,
      'payload': {
        'batchId': batch,
        'records': proofs,
        'commitment': commitment,
      },
    };
    Future<Map<String, dynamic>> outgoingFor(Map<String, dynamic> value) async {
      final signed = codec.signCommand(value, pair.secretKey);
      final hash = await cryptoSha256(cryptoBase64(signed['commandBase64']));
      return {
        'request_id': request,
        'request_hash': hash,
        'operation': 'crypto2.records.batch',
        'signed_body': jsonEncode(signed),
        'state': 'rejected',
        'response': jsonEncode({
          'requestId': request,
          'requestHash': hash,
          'authorization': signed,
          'status': 409,
          'response': {
            'errorCode': 'conflict',
            'details': {
              'remote': {
                'payload': {'title': 'UNTRUSTED RAW REMOTE'},
              },
            },
          },
        }),
      };
    }

    final outgoing = await outgoingFor(command);
    final business = <String, dynamic>{
      'operation_id': operation,
      'scope_id': scope,
      'domain': 'content',
      'record_id': task,
      'request_hash': localHash,
      'request_id': request,
    };
    Future<bool> inspect({
      Map<String, dynamic>? out,
      Map<String, dynamic>? journal,
      List<Map<String, dynamic>>? recordClaims,
    }) => isBoundOrdinaryTaskConflict(
      codec: codec,
      signingPublicKey: pair.publicKey,
      partition: partition,
      serverId: server,
      accountId: account,
      deviceId: device,
      scopeId: scope,
      taskId: task,
      operationId: operation,
      localHash: localHash,
      business: journal ?? business,
      outgoing: out ?? outgoing,
      claims: recordClaims ?? claims,
    );
    final original = jsonEncode({
      'outgoing': outgoing,
      'business': business,
      'claims': claims,
    });
    expect(
      await inspect(),
      true,
    ); // Batch-wide conflict, no raw remote returned.
    for (final state in ['pending', 'blocked', 'applied']) {
      expect(await inspect(out: {...outgoing, 'state': state}), false);
    }
    for (final outcome in [
      {
        'status': 200,
        'response': {'status': 'applied'},
      },
      {
        'status': 403,
        'response': {'errorCode': 'permission_revoked'},
      },
      {
        'status': 409,
        'response': {'errorCode': 'crypto_unique_conflict'},
      },
    ]) {
      final receipt = _copy(jsonDecode(outgoing['response'] as String) as Map)
        ..addAll(outcome);
      expect(
        await inspect(out: {...outgoing, 'response': jsonEncode(receipt)}),
        false,
      );
    }
    for (final keyName in ['requestId', 'requestHash', 'authorization']) {
      final receipt = _copy(jsonDecode(outgoing['response'] as String) as Map);
      receipt[keyName] = keyName == 'authorization'
          ? <String, dynamic>{}
          : 'substituted';
      await expectLater(
        inspect(out: {...outgoing, 'response': jsonEncode(receipt)}),
        throwsFormatException,
      );
    }
    await expectLater(
      inspect(out: {...outgoing, 'request_hash': '3' * 64}),
      throwsFormatException,
    );
    await expectLater(
      inspect(journal: {...business, 'request_hash': 'different-local-intent'}),
      throwsFormatException,
    );
    await expectLater(
      inspect(recordClaims: [claims.first]),
      throwsFormatException,
    );
    final wrongClaim = claims.map(_copy).toList();
    wrongClaim.last['expected_revision'] = 9;
    await expectLater(inspect(recordClaims: wrongClaim), throwsFormatException);
    final extra = _copy(command);
    (extra['payload']['records'] as List).add(proofs.first);
    await expectLater(
      inspect(out: await outgoingFor(extra)),
      throwsFormatException,
    );
    for (final change in [
      {'type': 'financeEntry', 'domain': 'finance'},
      {'id': crypto.randomId()},
      {'operationId': crypto.randomId()},
      {'membershipHeadHash': '4' * 64},
    ]) {
      final changed = _copy(command);
      final records = changed['payload']['records'] as List;
      final body = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64((records.last as Map)['commandBase64']))
            as Map,
      )..addAll(change);
      records[1] = crypto.signDomain(
        body,
        pair.secretKey,
        'JivieE2EE/record/v2\n',
      );
      await expectLater(
        inspect(out: await outgoingFor(changed)),
        throwsFormatException,
      );
    }
    final badSignature = _copy(command);
    badSignature['payload']['records'][0]['signatureBase64'] = base64Encode(
      Uint8List(64),
    );
    await expectLater(
      inspect(out: await outgoingFor(badSignature)),
      throwsFormatException,
    );
    expect(
      jsonEncode({
        'outgoing': outgoing,
        'business': business,
        'claims': claims,
      }),
      original,
    );
  } finally {
    key.dispose();
    pair.secretKey.dispose();
  }
}

class _NoNoticeSecrets implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _NoticeTransport implements CollaborationTransport {
  int calls = 0;
  Map<String, Object?>? params;
  void Function()? onCall;
  Object? error;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    expect(operation, 'scopes.list');
    expect(serverUrl, 'https://synthetic.invalid/');
    expect(token, 'synthetic-notice-session');
    expect(allowLocalHttp, false);
    calls++;
    this.params = params;
    onCall?.call();
    if (error != null) throw error!;
    return <String, dynamic>{};
  }

  @override
  void close() {}
}

Future<void> _noticeRequestGuards() async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  try {
    final crypto = CryptoCodec(await SodiumInit.init());
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: crypto.randomId(),
        accountId: crypto.randomId(),
        deviceId: crypto.randomId(),
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic-notice-session',
    );
    final wire = _NoticeTransport();
    var current = true, mutations = 0;
    final directory = AccountDirectoryRepository(
      reducer: AccountDirectoryV2(crypto),
      session: session,
      transport: wire,
      store: CryptoIdentityStore(
        db,
        _NoNoticeSecrets(),
        session.profile.partition,
      ),
      isCurrent: () => current,
    );
    final ids = [crypto.randomId()]..sort();
    final expected = [...ids];
    final snapshot = directory.createAuthoritySnapshot(
      isValid: () async => true,
      onMutation: () => mutations++,
    );
    await snapshot.run(() => directory.scopeAccessChanges(ids));
    expect(wire.calls, 1);
    expect(mutations, 0);
    expect(wire.params, {
      'includeAccessChanges': true,
      'accessChangesOnly': true,
      'scopeIds': expected,
    });
    ids.add(crypto.randomId());
    expect(
      wire.params!['scopeIds'],
      expected,
    ); // Snapshot the caller's selection.
    snapshot.close();
    current = false;
    await expectLater(
      directory.scopeAccessChanges(expected),
      throwsA(
        isA<CryptoDirectoryException>().having(
          (e) => e.code,
          'code',
          'directory_stale_identity',
        ),
      ),
    );
    expect(wire.calls, 1);
    current = true;
    wire.onCall = () => current = false;
    await expectLater(
      directory.scopeAccessChanges(expected),
      throwsA(
        isA<CryptoDirectoryException>().having(
          (e) => e.code,
          'code',
          'directory_stale_identity',
        ),
      ),
    );
    current = true;
    wire.onCall = null;
    wire.error = const CollaborationApiException('auth_required');
    await expectLater(
      directory.scopeAccessChanges(expected),
      throwsA(
        isA<CollaborationApiException>().having(
          (e) => e.code,
          'code',
          'auth_required',
        ),
      ),
    );
  } finally {
    await db.close();
  }
}

Future<void> _scopeAccessNoticeGuards() async {
  const server = '00000000-0000-4000-a000-000000000001';
  const account = '00000000-0000-4000-a000-000000000002';
  const device = '00000000-0000-4000-a000-000000000003';
  const first = '00000000-0000-4000-a000-000000000004';
  const second = '00000000-0000-4000-a000-000000000005';
  const foreign = '00000000-0000-4000-a000-000000000006';
  const requested = [first, second];
  final valid = <String, dynamic>{
    'accessChangesVersion': 1,
    'serverId': server,
    'accountId': account,
    'deviceId': device,
    'scopeIds': requested,
    'revokedScopeIds': requested,
    'deletedScopeIds': [second],
  };
  ({List<String> revoked, List<String> deleted})? parse(
    Object? value, {
    List<String> ids = requested,
  }) => parseScopeAccessChanges(
    value,
    requested: ids,
    serverId: server,
    accountId: account,
    deviceId: device,
  );
  final original = jsonEncode(valid);
  final accepted = parse(valid)!;
  expect(accepted.revoked, requested);
  expect(accepted.deleted, [second]);
  expect(() => accepted.revoked.add(foreign), throwsUnsupportedError);
  expect(
    parse({
      'scopes': [
        {'id': foreign, 'name': 'old plaintext ignored'},
      ],
    }),
    isNull,
  );
  expect(parse(null), isNull);
  for (final change in [
    {'accessChangesVersion': 2},
    {'serverId': foreign},
    {'accountId': foreign},
    {'deviceId': foreign},
    {
      'scopeIds': [second, first],
    },
    {
      'scopeIds': [first],
    },
    {
      'scopeIds': [first, first],
    },
    {
      'revokedScopeIds': [first, first],
    },
    {
      'revokedScopeIds': [foreign],
    },
    {
      'deletedScopeIds': [foreign],
    },
    {
      'deletedScopeIds': [second, second],
    },
    {
      'revokedScopeIds': [first],
      'deletedScopeIds': [second],
    },
    {'revokedScopeIds': 'malformed'},
    {'scopeIds': null},
    {'scopes': <Object>[]},
  ]) {
    expect(parse({...valid, ...change}), isNull);
  }
  final empty = parse({
    ...valid,
    'revokedScopeIds': <String>[],
    'deletedScopeIds': <String>[],
  });
  expect(
    empty!.revoked,
    isEmpty,
  ); // Absence of an explicit notice never revokes.
  expect(parse(valid, ids: []), isNull);
  expect(parse(valid, ids: [second, first]), isNull);
  expect(parse(valid, ids: [first, first]), isNull);
  expect(parse(valid, ids: List.filled(51, first)), isNull);
  expect(jsonEncode(valid), original);
  await _noticeRequestGuards();
}

void main() {
  final fixture = Platform.environment['JIVIE_FULLSYNC_HTTP_FIXTURE'];
  final root = Platform.environment['JIVIE_FULLSYNC_CORRECTION_ROOT'];
  final phase = Platform.environment['JIVIE_FULLSYNC_PHASE'];
  test(
    '22 October H4 signed guards and retained task conflict correction',
    () async {
      final marker = File('$root/h4-signed-guards-passed.json');
      if (!marker.existsSync()) {
        await _signedTaskConflictGuards();
        await marker.parent.create(recursive: true);
        await marker.writeAsString(
          jsonEncode({'explicitScope': '2026-10-22-H4', 'passed': true}),
        );
      }
      await retained.runRetainedTaskConflictCorrection(fixture!, root!);
    },
    skip:
        fixture == null ||
        root == null ||
        phase != 'H4_task_conflict_correction',
    timeout: const Timeout(Duration(minutes: 15)),
  );
  test(
    '22 October H7 notice guards and retained revoked access correction',
    () async {
      final marker = File('$root/h7-notice-guards-passed.json');
      if (!marker.existsSync()) {
        await _scopeAccessNoticeGuards();
        await marker.parent.create(recursive: true);
        await marker.writeAsString(
          jsonEncode({'explicitScope': '2026-10-22-H7', 'passed': true}),
        );
      }
      await retained.runRetainedRevokedAccessCorrection(fixture!, root!);
    },
    skip:
        fixture == null ||
        root == null ||
        phase != 'H7_revoked_access_correction',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
