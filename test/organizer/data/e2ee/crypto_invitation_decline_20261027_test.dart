import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
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
    if (operation == 'capabilities') {
      return {
        'serverId': '11111111-1111-4111-8111-111111111111',
        'invitationContractVersions': [4],
        'features': <String, dynamic>{},
      };
    }
    throw StateError('Confirmed decline must not dispatch $operation');
  }

  @override
  void close() {}
}

class _UnusedDirectory implements VerifiedAccountDirectory {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No creator inspection expected');
}

void main() {
  test('declined sender metadata remains distinct from manager revocation', () {
    final invitation = SharedInvitation.fromJson({
      'id': '55555555-5555-4555-8555-555555555555',
      'scopeId': '44444444-4444-4444-8444-444444444444',
      'recipientUsername': 'recipient',
      'role': 'member',
      'expiresAt': 2000000000,
      'revokedAt': 0,
      'declined': true,
    });
    expect(invitation.declined, isTrue);
    expect(invitation.acceptedAt, isNull);
    expect(invitation.revokedAt, isNotNull);
    expect(
      SharedInvitation.fromJson({
        'id': invitation.id,
        'scopeId': invitation.scopeId,
        'recipientUsername': 'recipient',
        'role': 'member',
        'expiresAt': 2000000000,
      }).declined,
      isFalse,
    );
  });

  for (final changed in [false, true]) {
    test(
      'confirmed decline journal replay avoids transport changed=$changed',
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
        if (!changed) {
          final refusal = InviteCryptoRepository(
            SessionCryptoAccess(account: account),
          );
          await expectLater(
            refusal.decline(
              VerifiedCryptoInvitation(
                {
                  'invitation': {'state': 'accepted'},
                },
                _UnusedDirectory(),
                [],
              ),
              actionId: 'unused',
            ),
            throwsA(
              isA<CollaborationException>().having(
                (e) => e.code,
                'code',
                'invitation_already_accepted',
              ),
            ),
          );
          expect(transport.calls, 0);
          await expectLater(
            refusal.decline(
              VerifiedCryptoInvitation(
                {
                  'invitation': {'state': 'pending'},
                },
                _UnusedDirectory(),
                [],
              ),
              actionId: 'unsupported',
            ),
            throwsA(
              isA<CollaborationException>().having(
                (e) => e.code,
                'code',
                'invitation_decline_unavailable',
              ),
            ),
          );
          expect(
            await db.rows('SELECT * FROM crypto_invitation_drafts'),
            isEmpty,
          );
        }
        final priorCalls = transport.calls;
        const scope = '44444444-4444-4444-8444-444444444444',
            invitation = '55555555-5555-4555-8555-555555555555',
            request = '66666666-6666-4666-8666-666666666666';
        final payload = {
          'scopeId': scope,
          'invitationId': invitation,
          'tokenHash': 'a' * 64,
          'creatorProofHash': 'b' * 64,
          'authorDirectoryHeadHash': 'd' * 64,
        };
        final command = {
          'version': 2,
          'operation': 'crypto2.invitations.decline',
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
        // already acknowledged recipient refusal. Production sender is real.
        await db.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
          [
            session.profile.partition,
            scope,
            request,
            'confirmed',
            utf8.encode(
              jsonEncode({
                'operation': 'crypto2.invitations.decline',
                'receipt': {
                  'status': 200,
                  'response': {'declined': true, 'invitationId': invitation},
                },
              }),
            ),
            CryptoJson.encode(proof),
          ],
        );
        await db.execute(
          'INSERT INTO crypto_membership_action_keys VALUES(?,?,?,?)',
          [session.profile.partition, scope, 'decline:$invitation', request],
        );
        final future = manager.invitationCommand(
          'crypto2.invitations.decline',
          scope,
          {...payload, if (changed) 'tokenHash': 'e' * 64},
          actionKey: 'decline:$invitation',
        );
        if (changed) {
          await expectLater(future, throwsA(isA<CryptoAuthorityPending>()));
        } else {
          final result = await future;
          expect(result['declined'], isTrue);
          expect(result['invitationId'], invitation);
          expect(
            await db.rows('SELECT intent_id FROM crypto_membership_intents'),
            hasLength(1),
          );
        }
        expect(transport.calls, priorCalls);
      },
    );
  }
}
