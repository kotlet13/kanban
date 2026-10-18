import 'dart:convert';
import 'dart:io';
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
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart' show SodiumInit;

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Http implements CollaborationTransport {
  final inner = HttpCollaborationTransport();
  bool omit = false, substitute = false;
  int accepts = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.invitations.accept') accepts++;
    final r = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'crypto2.invitations.bridgeDigests') {
      if (omit) {
        return {
          ...r,
          'digests': <String>[],
          'hasMore': false,
          'nextAfterHash': null,
        };
      }
      if (substitute) {
        final hashes = List<String>.from(r['digests'] as List);
        hashes[0] = 'f' * 64;
        hashes.sort();
        return {...r, 'digests': hashes};
      }
    }
    return r;
  }

  @override
  void close() => inner.close();
}

void main() {
  final path = Platform.environment['JIVIE_LEGACY_INVITATION_HTTP_FIXTURE'];
  test(
    'retained old token exact certificate then held until signed final cutover; no legacy grant',
    () async {
      final f = jsonDecode(await File(path!).readAsString()) as Map;
      if (f['synthetic'] != true ||
          Uri.parse(f['serverUrl']).host != '127.0.0.1') {
        throw StateError('Synthetic only');
      }
      final wire = f['session'] as Map,
          u = wire['user'] as Map,
          d = wire['device'] as Map;
      final session = DeviceSession(
        AccountSession(
          serverUrl: f['serverUrl'],
          serverId: wire['serverId'],
          accountId: u['accountId'],
          userId: u['id'],
          username: u['username'],
          displayName: u['displayName'],
          deviceId: d['id'],
          expiresAt: DateTime.fromMillisecondsSinceEpoch(d['expiresAt'] * 1000),
          allowLocalHttp: true,
        ),
        wire['token'],
      );
      final db = CollaborationDatabase(NativeDatabase.memory()),
          http = _Http(),
          crypto = CryptoCodec(await SodiumInit.init());
      addTearDown(db.close);
      addTearDown(http.close);
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: http,
          store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
          isCurrent: () => true,
        ),
      );
      final file = await account.prepareRecoveryFile();
      try {
        await account.verifyAndInitialize(file);
        final access = SessionCryptoAccess(account: account),
            invites = InviteCryptoRepository(access);
        http.omit = true;
        await expectLater(
          invites.inspect(token: f['token']),
          throwsA(isA<FormatException>()),
        );
        http.omit = false;
        http.substitute = true;
        await expectLater(
          invites.inspect(token: f['token']),
          throwsA(isA<FormatException>()),
        );
        http.substitute = false;
        final invite = await invites.inspect(token: f['token']);
        expect(invite.invitation['id'], f['invitationId']);
        expect(
          invite.creator.snapshot['rootSigningKeyBase64'],
          f['creatorRootSigningKeyBase64'],
        );
        expect(
          invite.creator.snapshot['rootEncryptionKeyBase64'],
          f['creatorRootEncryptionKeyBase64'],
        );
        expect(
          await db.rows('SELECT * FROM crypto_trusted_identities'),
          isEmpty,
        );
        await expectLater(
          invites.accept(invite, actionId: crypto.randomId()),
          throwsA(isA<CryptoAuthorityPending>()),
        );
        expect(http.accepts, 0);
        await invites.compareCreator(
          invite,
          await access.identities.publicCard(invite.creator),
        );
        await expectLater(
          invites.accept(invite, actionId: crypto.randomId()),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'crypto_invitation_bridge_cutover_pending',
            ),
          ),
        );
        expect(http.accepts, 0);
        for (final k in ['acceptedToken', 'revokedToken', 'expiredToken']) {
          await expectLater(
            invites.inspect(token: f[k]),
            throwsA(
              isA<CollaborationApiException>().having(
                (e) => e.code,
                'code',
                'invitation_invalid',
              ),
            ),
          );
        }
        expect(await db.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
      } finally {
        file.fillRange(0, file.length, 0);
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
