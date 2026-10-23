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
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Wire implements CollaborationTransport {
  int listReads = 0, writes = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (params.containsKey('commandBase64')) writes++;
    if (operation != 'crypto2.invitations.list') {
      throw StateError('unexpected_restart_selection_transport');
    }
    listReads++;
    return {'invitations': [], 'hasMore': false, 'nextAfterId': null};
  }

  @override
  void close() {}
}

void main() {
  for (final confirmed in [false, true]) {
    test(
      'restart selector ${confirmed ? 'confirmed missing fails closed' : 'ambiguous unknown creates never send'}',
      () async {
        final db = CollaborationDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final crypto = CryptoCodec(await SodiumInit.init());
        final signer = crypto.sodium.crypto.sign.keyPair();
        addTearDown(signer.dispose);
        final profile = AccountSession(
          serverUrl: 'https://restart.invalid',
          serverId: crypto.randomId(),
          accountId: crypto.randomId(),
          userId: 1,
          username: 'synthetic',
          displayName: 'Synthetic',
          deviceId: crypto.randomId(),
          expiresAt: DateTime.utc(2030),
        );
        final wire = _Wire();
        final directory = AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: DeviceSession(profile, 'synthetic-token'),
          transport: wire,
          store: CryptoIdentityStore(db, _Secure(), profile.partition),
          isCurrent: () => true,
        );
        final scope = crypto.randomId();
        final originals = <List<int>>[];
        for (var i = 0; i < (confirmed ? 1 : 2); i++) {
          final action = crypto.randomId(), request = crypto.randomId();
          final payload = {
            'scopeId': scope,
            'invitationId': crypto.randomId(),
            'recipient': {
              'kind': 'email',
              'value': 'recipient@example.invalid',
              'accountId': crypto.randomId(),
            },
            'role': 'member',
            'language': 'en',
            'expiresAt': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            'preauthorization': {'version': 1},
          };
          final authorization = crypto.signDomain(
            {
              'version': 2,
              'operation': 'crypto2.invitations.create',
              'serverId': profile.serverId,
              'accountId': profile.accountId,
              'deviceId': profile.deviceId,
              'requestId': request,
              'signer': 'device',
              'payload': payload,
            },
            signer.secretKey,
            cryptoDirectoryDomain,
          );
          final bytes = CryptoJson.encode(authorization);
          originals.add(bytes);
          await db.execute(
            'INSERT INTO crypto_invitation_drafts VALUES(?,?,?,?)',
            [
              profile.partition,
              action,
              jsonEncode({'callerHash': 'original', 'payload': payload}),
              'retained-synthetic-token-$i',
            ],
          );
          await db.execute(
            'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
            [
              profile.partition,
              scope,
              request,
              confirmed ? 'confirmed' : 'pending',
              CryptoJson.encode({}),
              bytes,
            ],
          );
          await db.execute(
            'INSERT INTO crypto_membership_action_keys VALUES(?,?,?,?)',
            [profile.partition, scope, 'invite:$action', request],
          );
        }
        final repository = InviteCryptoRepository(
          SessionCryptoAccess(account: AccountCryptoV2Workflow(directory)),
        );
        await expectLater(
          repository.dispatch('invitations3.create', {
            'scopeId': scope,
            'recipient': 'recipient@example.invalid',
            'role': 'member',
            'language': 'en',
            'requestId': crypto.randomId(),
          }),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (error) => error.reason,
              'reason',
              confirmed
                  ? 'invitation_list_pending'
                  : 'invitation_preparation_review_required',
            ),
          ),
        );
        expect(wire.writes, 0);
        expect(wire.listReads, 1);
        final retained = await db.rows(
          'SELECT authorization FROM crypto_membership_intents ORDER BY rowid',
        );
        expect(retained.map((row) => row['authorization']).toList(), originals);
        expect(
          await db.rows('SELECT * FROM crypto_invitation_drafts'),
          hasLength(originals.length),
        );
      },
    );
  }
}
