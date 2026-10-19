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
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('No new secure state expected');
}

class _Transport implements CollaborationTransport {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls++;
    throw StateError('Confirmed acceptance must not dispatch $operation');
  }

  @override
  void close() {}
}

void main() {
  for (final changed in [false, true]) {
    test(
      'confirmed invitation journal replay avoids transport changed=$changed',
      () async {
        final db = CollaborationDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final transport = _Transport();
        final session = DeviceSession(
          AccountSession(
            serverUrl: 'https://example.test/',
            serverId: '11111111-1111-4111-8111-111111111111',
            accountId: '22222222-2222-4222-8222-222222222222',
            userId: 1,
            username: 'synthetic',
            displayName: 'Synthetic',
            deviceId: '33333333-3333-4333-8333-333333333333',
            expiresAt: DateTime.utc(2027),
          ),
          'synthetic',
        );
        final account = AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(CryptoCodec(await SodiumInit.init())),
            session: session,
            transport: transport,
            store: CryptoIdentityStore(
              db,
              _Secure(),
              session.profile.partition,
            ),
            isCurrent: () => true,
          ),
        );
        final manager = ScopeCryptoManager(
          SessionCryptoAccess(account: account),
        );
        const scope = '44444444-4444-4444-8444-444444444444',
            invitation = '55555555-5555-4555-8555-555555555555',
            request = '66666666-6666-4666-8666-666666666666';
        final payload = {
          'scopeId': scope,
          'invitationId': invitation,
          'tokenHash': 'a' * 64,
          'creatorProofHash': 'b' * 64,
          'role': 'member',
          'expiresAt': 2000000000,
          'membershipHeadHash': 'c' * 64,
          'authorDirectoryHeadHash': 'd' * 64,
        };
        final command = {
          'version': 2,
          'operation': 'crypto2.invitations.accept',
          'requestId': request,
          'serverId': session.profile.serverId,
          'accountId': session.profile.accountId,
          'deviceId': session.profile.deviceId,
          'signer': 'device',
          'payload': payload,
        };
        final proof = {
          'commandBase64': base64Encode(CryptoJson.encode(command)),
          'signatureBase64': base64Encode(List<int>.filled(64, 0)),
        };
        // Disposable fixture models the immutable confirmed journal left by the
        // already acknowledged first native Join. Production sender is real.
        await db.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
          [
            session.profile.partition,
            scope,
            request,
            'confirmed',
            utf8.encode(
              jsonEncode({
                'operation': 'crypto2.invitations.accept',
                'receipt': {
                  'status': 200,
                  'response': {'pendingKeys': true, 'requestId': request},
                },
              }),
            ),
            CryptoJson.encode(proof),
          ],
        );
        await db.execute(
          'INSERT INTO crypto_membership_action_keys VALUES(?,?,?,?)',
          [session.profile.partition, scope, 'accept:$invitation', request],
        );
        final future = manager.invitationCommand(
          'crypto2.invitations.accept',
          scope,
          {...payload, if (changed) 'tokenHash': 'e' * 64},
          actionKey: 'accept:$invitation',
        );
        if (changed) {
          await expectLater(future, throwsA(isA<CryptoAuthorityPending>()));
        } else {
          final result = await future;
          expect(result['pendingKeys'], isTrue);
          expect(result['requestId'], request);
          expect(
            await db.rows('SELECT intent_id FROM crypto_membership_intents'),
            hasLength(1),
          );
        }
        expect(transport.calls, 0);
      },
    );
  }
}
