import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_task_resolution.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

const _scope = '11111111-1111-4111-a111-111111111111';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Transport implements CollaborationTransport {
  _Transport(this.own);
  final VerifiedAccountDirectory own;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    switch (operation) {
      case 'capabilities':
        return {'serverId': own.serverId};
      case 'crypto2.account.status':
        return {
          'serverId': own.serverId,
          'accountId': own.accountId,
          'initialized': true,
          'generation': own.generation,
          'headHash': own.headHash,
        };
      case 'crypto2.account.scopeObservations':
        return {'observations': <Object>[], 'hasMore': false};
      case 'crypto2.scope.headGet':
        expect(params['scopeId'], _scope);
        // The actual online verifier must propagate a fresh denial. There is
        // no permissive fallback from a candidate to cached finance authority.
        throw const CollaborationApiException('permission_revoked');
      default:
        throw StateError('Unexpected synthetic request: $operation');
    }
  }

  @override
  void close() {}
}

void main() {
  late CollaborationDatabase db;
  late DeviceSession session;
  setUp(() {
    db = CollaborationDatabase(NativeDatabase.memory());
    session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: '22222222-2222-4222-a222-222222222222',
        accountId: '33333333-3333-4333-a333-333333333333',
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        deviceId: '44444444-4444-4444-a444-444444444444',
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic',
    );
  });
  tearDown(() => db.close());

  Future<void> row(
    String id,
    String domain,
    String type, {
    String? partition,
    String scope = _scope,
    bool deleted = false,
    String proof = 'intent-proof',
    Map<String, dynamic> raw = const {'taskId': 'task'},
  }) => db.execute(
    'INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,?,?,?,1,?,?,?,?,?)',
    [
      partition ?? session.profile.partition,
      scope,
      domain,
      id,
      type,
      proof,
      deleted ? 1 : 0,
      jsonEncode(raw),
      '{}',
      'verifiedCheckpoint',
    ],
  );

  Future<bool> selectWithoutAuthority() => CryptoBusinessRouter(
    database: db,
    accountFor: (_) =>
        throw StateError('No candidate requires no account proof'),
  ).needsFinanceForTaskDerivations(session: session, scopeId: _scope);

  test(
    'fresh ordinary content skips finance dependency proof and transport',
    () async {
      await row('ordinary-task', 'content', 'task');
      expect(await selectWithoutAuthority(), isFalse);
      expect(await db.rows('SELECT 1 FROM crypto_outbox'), isEmpty);
    },
  );

  test(
    'candidate hint excludes other profiles/scopes, deleted and resolved links',
    () async {
      await row('intent', 'content', 'taskDerivationIntent');
      await row('other-profile', 'finance', 'financeEntry', partition: 'other');
      await row('other-scope', 'finance', 'financeEntry', scope: 'other');
      await row('deleted', 'finance', 'financeEntry', deleted: true);
      expect(await selectWithoutAuthority(), isFalse);
      await row('expense', 'finance', 'financeEntry');
      expect(
        await cryptoHasUnresolvedTaskDerivations(
          db,
          session.profile.partition,
          _scope,
        ),
        isTrue,
      );
      await row(
        'resolution',
        'finance',
        'taskDerivationResolution',
        raw: {'intentProofHash': 'intent-proof', 'state': 'derived'},
      );
      expect(await selectWithoutAuthority(), isFalse);
    },
  );

  test(
    'local candidate never grants finance read or absent roles a write dependency',
    () async {
      await row('intent', 'content', 'taskDerivationIntent');
      await row('expense', 'finance', 'personalFinanceEntry');
      for (final role in ['none', 'read', 'write']) {
        expect(
          await cryptoNeedsTaskDerivationFinanceRefresh(
            db,
            session.profile.partition,
            _scope,
            financeRole: role,
          ),
          role == 'write',
        );
      }
    },
  );

  test(
    'unresolved candidate uses online head verification and preserves denial',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init());
      final reducer = AccountDirectoryV2(crypto);
      final root = crypto.sodium.crypto.sign.keyPair();
      final box = crypto.sodium.crypto.box.keyPair();
      final device = crypto.sodium.crypto.sign.keyPair();
      final deviceBox = crypto.sodium.crypto.box.keyPair();
      addTearDown(() {
        for (final pair in [root, box, device, deviceBox]) {
          pair.secretKey.dispose();
        }
      });
      final pin = crypto.fingerprint(root.publicKey, box.publicKey);
      final first = await reducer.prepare(
        previous: null,
        serverId: session.profile.serverId,
        accountId: session.profile.accountId,
        deviceId: session.profile.deviceId,
        identityEpochId: crypto.randomId(),
        operation: 'crypto2.account.initialize',
        signer: 'root',
        pinnedRootFingerprint: pin,
        signingKey: root.secretKey,
        payload: {
          'rootSigningKeyBase64': base64Encode(root.publicKey),
          'rootEncryptionKeyBase64': base64Encode(box.publicKey),
          'deviceSigningKeyBase64': base64Encode(device.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
          'keyringCiphertextBase64': base64Encode(Uint8List(48)),
        },
      );
      final secure = _Secure();
      final store = CryptoIdentityStore(db, secure, session.profile.partition);
      await store.append(session.profile.accountId, first.entry);
      await store.pinRoot(
        session.profile.accountId,
        session.profile.serverId,
        pin,
        genesisFingerprint: pin,
      );
      await store.remember(first.result, 'verified');
      final before = Map.of(secure.values);
      final transport = _Transport(first.result);
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: reducer,
          session: session,
          transport: transport,
          store: store,
          isCurrent: () => true,
        ),
      );
      await row('intent', 'content', 'taskDerivationIntent');
      await row('expense', 'finance', 'financeEntry');
      final router = CryptoBusinessRouter(
        database: db,
        accountFor: (_) async => account,
      );
      await expectLater(
        router.needsFinanceForTaskDerivations(
          session: session,
          scopeId: _scope,
        ),
        throwsA(
          isA<CollaborationApiException>().having(
            (e) => e.code,
            'code',
            'permission_revoked',
          ),
        ),
      );
      expect(
        transport.calls.where((op) => op == 'crypto2.scope.headGet'),
        hasLength(1),
      );
      expect(secure.values, before);
      expect(await db.rows('SELECT 1 FROM crypto_outbox'), isEmpty);
      expect(
        await db.rows('SELECT 1 FROM crypto_business_records'),
        hasLength(2),
      );
    },
  );
}
