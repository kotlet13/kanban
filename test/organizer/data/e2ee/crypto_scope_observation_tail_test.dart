import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Wire implements CollaborationTransport {
  _Wire(this.server, this.account, this.device, this.head, this.entries);
  final String server, account, device;
  VerifiedAccountDirectory head;
  final List<Map<String, dynamic>> entries;
  final bundles = <Map<String, dynamic>>[];
  final calls = <String>[];
  bool badStatus = false, offline = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    if (offline) throw const CollaborationException('network');
    Map<String, dynamic> status() => {
      'initialized': true,
      'serverId': server,
      'accountId': account,
      'generation': head.generation,
      'headHash': badStatus ? 'f' * 64 : head.headHash,
      'snapshotHash': head.snapshotHash,
      'deviceSnapshotHash': head.deviceSnapshotHash,
    };
    if (operation == 'capabilities') {
      return {
        'serverId': server,
        'cryptoAuthoritySnapshotVersions': [1],
      };
    }
    if (operation == 'crypto2.authority.snapshot') {
      final after = params['accountAfterGeneration'] as int;
      return {
        'version': 1,
        'serverId': server,
        'accountId': account,
        'deviceId': device,
        'entries': [
          {
            'operation': 'crypto2.account.status',
            'params': {},
            'result': status(),
          },
          {
            'operation': 'crypto2.account.directory',
            'params': {'afterGeneration': after, 'limit': 50},
            'result': {
              'generation': head.generation,
              'headHash': head.headHash,
              'entries': entries.where((e) => e['generation'] > after).toList(),
              'nextGeneration': head.generation,
            },
          },
        ],
      };
    }
    if (operation == 'crypto2.account.status') return status();
    if (operation == 'crypto2.account.scopeObservations') {
      final after = params['afterGeneration'] as int;
      return {
        'observations': bundles.where((b) => b['generation'] > after).toList(),
        'hasMore': false,
      };
    }
    throw StateError('Unexpected synthetic endpoint: $operation');
  }

  @override
  void close() {}
}

class _Fixture {
  _Fixture(
    this.db,
    this.account,
    this.wire,
    this.initial,
    this.next,
    this.bundle,
    this.scope,
  );
  final CollaborationDatabase db;
  final AccountCryptoV2Workflow account;
  final _Wire wire;
  final PreparedDirectoryMutation initial, next;
  final Map<String, dynamic> bundle;
  final String scope;
  Future<void> cursor(int generation) => db.execute(
    'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO UPDATE SET payload=excluded.payload',
    [
      account.store.partition,
      account.directory.accountId,
      'scopeObservationCursor',
      'scopeObservationCursor',
      CryptoJson.encode({'generation': generation}),
    ],
  );
  Future<void> advance({bool local = false, bool includeBundle = true}) async {
    wire.head = next.result;
    if (includeBundle) wire.bundles.add(bundle);
    if (local) {
      await account.store.append(account.directory.accountId, next.entry);
      await account.store.remember(next.result, 'verified');
    }
  }

  Future<T> dispatch<T>(
    Future<T> Function() body,
  ) => account.directory.withAuthoritySnapshot(
    () async {
      // Every production current-head dispatch needs this same authority bundle.
      // Three independent invocations below retain no lease between dispatches.
      await account.directory.call('crypto2.account.status');
      return body();
    },
    isValid: () async => true,
    onMutation: () =>
        throw StateError('No mutations authorized in this fixture'),
  );
}

void main() {
  Future<_Fixture> setup() async {
    final crypto = CryptoCodec(await SodiumInit.init());
    final reducer = AccountDirectoryV2(crypto);
    final root = crypto.sodium.crypto.sign.keyPair(),
        device = crypto.sodium.crypto.sign.keyPair();
    final box = crypto.sodium.crypto.box.keyPair();
    addTearDown(() {
      root.dispose();
      device.dispose();
      box.dispose();
    });
    final server = crypto.randomId(),
        accountId = crypto.randomId(),
        deviceId = crypto.randomId(),
        epoch = crypto.randomId(),
        scope = crypto.randomId();
    final fingerprint = crypto.fingerprint(root.publicKey, box.publicKey);
    final first = await reducer.prepare(
      previous: null,
      serverId: server,
      accountId: accountId,
      deviceId: deviceId,
      identityEpochId: epoch,
      operation: 'crypto2.account.initialize',
      signer: 'root',
      pinnedRootFingerprint: fingerprint,
      signingKey: root.secretKey,
      payload: {
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(box.publicKey),
        'deviceSigningKeyBase64': base64Encode(device.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
        'keyringCiphertextBase64': base64Encode(Uint8List(48)),
      },
    );
    final observation = <String, dynamic>{
      'version': 2,
      'serverId': server,
      'accountId': accountId,
      'scopeId': scope,
      'headHash': 'a' * 64,
    };
    final next = await reducer.prepare(
      previous: first.result,
      serverId: server,
      accountId: accountId,
      deviceId: deviceId,
      identityEpochId: epoch,
      operation: 'crypto2.account.scopeObserve',
      signer: 'device',
      pinnedRootFingerprint: fingerprint,
      signingKey: device.secretKey,
      payload: {
        'scopeToken': await CryptoScopeObservations.token(
          server,
          accountId,
          scope,
        ),
        'headHash': observation['headHash'],
        'observationHash': await CryptoScopeObservations.digest(observation),
      },
    );
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: server,
        accountId: accountId,
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        deviceId: deviceId,
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic',
    );
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = CryptoIdentityStore(db, _Secure(), session.profile.partition);
    await store.pinRoot(
      accountId,
      server,
      fingerprint,
      genesisFingerprint: fingerprint,
    );
    await store.append(accountId, first.entry);
    await store.remember(first.result, 'verified');
    final wire = _Wire(server, accountId, deviceId, first.result, [
      first.entry,
      next.entry,
    ]);
    final account = AccountCryptoV2Workflow(
      AccountDirectoryRepository(
        reducer: reducer,
        session: session,
        transport: wire,
        store: store,
        isCurrent: () => true,
      ),
    );
    final bundle = {
      'generation': next.result.generation,
      'eventCommandHash': await cryptoSha256(
        cryptoBase64(next.authorization['commandBase64']),
      ),
      'observation': observation,
    };
    final fixture = _Fixture(db, account, wire, first, next, bundle, scope);
    await fixture.cursor(first.result.generation);
    return fixture;
  }

  test(
    'unchanged fresh signed own prefix skips empty observation tails across three separate dispatches',
    () async {
      final f = await setup();
      for (var i = 0; i < 3; i++) {
        expect(
          await f.dispatch(
            () => CryptoScopeObservations(f.account).recover(f.scope),
          ),
          isEmpty,
        );
      }
      expect(
        f.wire.calls.where((op) => op == 'crypto2.authority.snapshot'),
        hasLength(3),
      );
      expect(
        f.wire.calls.where((op) => op == 'crypto2.account.scopeObservations'),
        isEmpty,
      );
      // Prior source unconditionally requested one empty companion page per
      // dispatch; the independent signed authority requests remain three.
      // ignore: avoid_print
      print(
        jsonEncode({
          'separateDispatchConsumerCounts': {
            'dispatches': 3,
            'authoritySnapshots': 3,
            'wireObservations': 0,
            'sourceBaselineUnconditionalEmptyPages': 3,
          },
        }),
      );
    },
  );

  test(
    'advanced fresh own prefix fetches and validates its signed companion then skips caught-up tail',
    () async {
      final f = await setup();
      await f.advance();
      final observed = await f.dispatch(
        () => CryptoScopeObservations(f.account).recover(f.scope),
      );
      expect(observed, hasLength(1));
      expect(observed.single['generation'], f.next.result.generation);
      expect(observed.single['scopeId'], f.scope);
      final again = await f.dispatch(
        () => CryptoScopeObservations(f.account).recover(f.scope),
      );
      expect(
        again.single['observationHash'],
        observed.single['observationHash'],
      );
      expect(
        f.wire.calls.where((op) => op == 'crypto2.account.scopeObservations'),
        hasLength(1),
      );
    },
  );

  test(
    'caught-up cursor cannot hide a missing locally included signed companion',
    () async {
      final f = await setup();
      await f.advance(local: true, includeBundle: false);
      await f.cursor(f.next.result.generation);
      await expectLater(
        f.dispatch(() => CryptoScopeObservations(f.account).recover(f.scope)),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'scope_observation_bundle_missing',
          ),
        ),
      );
      expect(
        f.wire.calls.where((op) => op == 'crypto2.account.scopeObservations'),
        isEmpty,
      );
    },
  );

  test('exact read-only prefix never refreshes beyond its boundary', () async {
    final f = await setup();
    await f.advance();
    expect(
      await CryptoScopeObservations(
        f.account,
      ).recover(f.scope, readOnlyOwnPrefix: f.initial.result),
      isEmpty,
    );
    expect(f.wire.calls, isEmpty);
    expect(
      (await f.account.directory.cachedVerifiedDirectory()).headHash,
      f.initial.result.headHash,
    );
  });

  test(
    'cursor ahead of live or exact frozen signed prefix still fails before network',
    () async {
      final f = await setup();
      await f.cursor(9);
      for (final prefix in [null, f.initial.result]) {
        await expectLater(
          CryptoScopeObservations(
            f.account,
          ).recover(f.scope, readOnlyOwnPrefix: prefix),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'scope_observation_cursor_ahead',
            ),
          ),
        );
      }
      expect(f.wire.calls, isEmpty);
    },
  );

  test(
    'invalid fresh directory status fails before admitting an empty-tail skip',
    () async {
      final f = await setup();
      f.wire.badStatus = true;
      await expectLater(
        f.dispatch(() => CryptoScopeObservations(f.account).recover(f.scope)),
        throwsA(
          isA<CryptoDirectoryException>().having(
            (e) => e.code,
            'code',
            'directory_snapshot_mismatch',
          ),
        ),
      );
      expect(
        f.wire.calls.where((op) => op == 'crypto2.account.scopeObservations'),
        isEmpty,
      );
    },
  );

  test(
    'offline refresh preserves existing local signed recovery behavior',
    () async {
      final f = await setup();
      f.wire.offline = true;
      expect(
        await CryptoScopeObservations(f.account).recover(f.scope),
        isEmpty,
      );
      expect(f.wire.calls, ['crypto2.account.status']);
    },
  );
}
