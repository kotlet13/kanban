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
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Transport extends HttpCollaborationTransport {
  Future<void> Function(Map<String, dynamic>)? onProposal;
  Map<String, dynamic>? forgedCurrent;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.scope.headGet' &&
        params['headHash'] == null &&
        forgedCurrent != null) {
      return forgedCurrent!;
    }
    late Map<String, dynamic> reply;
    for (var attempt = 0; ; attempt++) {
      try {
        reply = await super.call(
          serverUrl: serverUrl,
          operation: operation,
          params: params,
          token: token,
          allowLocalHttp: allowLocalHttp,
        );
        break;
      } on CollaborationApiException catch (error) {
        final retry = error.details['retryAfter'];
        if (error.code != 'rate_limited' ||
            attempt >= 3 ||
            retry is! int ||
            retry < 1 ||
            retry > 60)
          rethrow;
        await Future<void>.delayed(Duration(seconds: retry));
      }
    }
    if (operation == 'crypto2.scope.headPut') await onProposal?.call(reply);
    return reply;
  }
}

void main() {
  final path = Platform.environment['JIVIE_SCOPE_CACHE_HTTP_FIXTURE'];
  test(
    'verified pending head cannot satisfy forged active state and upgrades only after genuine activation',
    () async {
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback only');
      final wire = fixture['accounts']['owner']['session'] as Map;
      final user = wire['user'] as Map, device = wire['device'] as Map;
      final session = DeviceSession(
        AccountSession(
          serverUrl: url,
          serverId: wire['serverId'],
          accountId: user['accountId'],
          userId: user['id'],
          username: user['username'],
          displayName: user['displayName'],
          deviceId: device['id'],
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            device['expiresAt'] * 1000,
          ),
          allowLocalHttp: true,
        ),
        wire['token'],
      );
      final db = CollaborationDatabase(NativeDatabase.memory()),
          transport = _Transport();
      addTearDown(db.close);
      addTearDown(transport.close);
      final crypto = CryptoCodec(await SodiumInit.init());
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: transport,
          store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
          isCurrent: () => true,
        ),
      );
      final file = await account.prepareRecoveryFile();
      try {
        await account.verifyAndInitialize(file);
      } finally {
        file.fillRange(0, file.length, 0);
      }
      final access = SessionCryptoAccess(account: account),
          manager = ScopeCryptoManager(access),
          scope = crypto.randomId();
      await manager.createScope(id: scope, kind: 'household');
      var checked = false;
      transport.onProposal = (reply) async {
        final pending = await access.pendingHead(scope, reply['headHash']);
        expect(pending.active, false);
        final original = await account.directory.call('crypto2.scope.headGet', {
          'scopeId': scope,
          'headHash': pending.headHash,
        });
        transport.forgedCurrent = {...original, 'state': 'active'}
          ..remove('activationAuthorization');
        await expectLater(
          access.currentHead(scope, online: true),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'scope_keys_pending',
            ),
          ),
        );
        expect(
          await account.store.secure.read(
            'scope2:${account.store.partition}:$scope',
          ),
          isNull,
        );
        transport.forgedCurrent = null;
        checked = true;
      };
      final catalog = await account.directory.call('crypto2.scopes.catalog');
      final metadata =
          (catalog['scopes'] as List).singleWhere((s) => s['id'] == scope)
              as Map;
      final activated = await manager.initializeEmptyScope(
        scopeId: scope,
        accessRevision: metadata['accessRevision'],
        members: (metadata['members'] as List).cast<Map<String, dynamic>>(),
      );
      expect(checked, true);
      expect(activated.active, true);
      final current = await access.currentHead(scope, online: true);
      expect(current.active, true);
      expect(current.headHash, activated.headHash);
    },
    skip: path == null ? 'Synthetic loopback fixture not requested' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
