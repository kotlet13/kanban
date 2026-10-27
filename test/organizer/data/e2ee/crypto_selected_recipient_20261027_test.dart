import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('No secure write authorized');
}

class Transport implements CollaborationTransport {
  var calls = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls++;
    throw StateError('No wire call expected');
  }

  @override
  void close() {}
}

void main() {
  test(
    'selected account mismatch refuses immutable encrypted invitation draft before transport or grant creation',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final codec = CryptoCodec(await SodiumInit.init());
      final wire = Transport();
      final profile = AccountSession(
        serverUrl: 'https://selected.invalid',
        serverId: codec.randomId(),
        accountId: codec.randomId(),
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        deviceId: codec.randomId(),
        expiresAt: DateTime.utc(2030),
      );
      final directory = AccountDirectoryRepository(
        reducer: AccountDirectoryV2(codec),
        session: DeviceSession(profile, 'synthetic'),
        transport: wire,
        store: CryptoIdentityStore(db, Secure(), profile.partition),
        isCurrent: () => true,
      );
      final scope = codec.randomId(),
          action = codec.randomId(),
          retainedAccount = codec.randomId();
      final params = <String, Object?>{
        'scopeId': scope,
        'recipient': 'reused_username',
        'recipientAccountId': codec.randomId(),
        'role': 'member',
        'language': 'en',
        'requestId': action,
      };
      final payload = {
        'scopeId': scope,
        'invitationId': codec.randomId(),
        'recipient': {
          'kind': 'username',
          'value': 'reused_username',
          'accountId': retainedAccount,
        },
        'role': 'member',
        'tokenHash': 'a' * 64,
      };
      final original = jsonEncode({
        'callerHash': await cryptoSha256(
          CryptoJson.encode({
            'operation': 'invitations3.create',
            'params': params,
          }),
        ),
        'payload': payload,
      });
      await db.execute('INSERT INTO crypto_invitation_drafts VALUES(?,?,?,?)', [
        profile.partition,
        action,
        original,
        'retained-secret',
      ]);
      final repository = InviteCryptoRepository(
        SessionCryptoAccess(account: AccountCryptoV2Workflow(directory)),
      );
      await expectLater(
        repository.dispatch('invitations3.create', params),
        throwsA(
          isA<CollaborationException>().having(
            (error) => error.code,
            'code',
            'recipient_unavailable',
          ),
        ),
      );
      expect(wire.calls, 0);
      final retained = await db.rows(
        'SELECT payload,token FROM crypto_invitation_drafts',
      );
      expect(retained.single['payload'], original);
      expect(retained.single['token'], 'retained-secret');
      expect(await db.rows('SELECT * FROM crypto_membership_intents'), isEmpty);
      expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
    },
  );
}
