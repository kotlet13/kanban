import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
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
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';

class _MemorySecure implements AccountCryptoStore {
  final rows = <String, String>{};
  @override
  Future<String?> read(String partition) async => rows[partition];
  @override
  Future<void> write(String partition, String value) async {
    rows[partition] = value;
  }
}

DeviceSession _session(String url, Map<String, dynamic> wire) {
  final user = wire['user'] as Map, device = wire['device'] as Map;
  return DeviceSession(
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
}

class _TrackedHttp extends HttpCollaborationTransport {
  final operations = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

void main() {
  final path = Platform.environment['JIVIE_SIMPLE_SHARING_HTTP_FIXTURE'];
  test(
    'real no-card accept pending owner grant and encrypted history read',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback only');
      }
      final crypto = CryptoCodec(await SodiumInit.init());
      final http = _TrackedHttp();
      final databases = <CollaborationDatabase>[];
      final files = <Uint8List>[];
      AccountCryptoV2Workflow make(DeviceSession session) {
        final db = CollaborationDatabase(NativeDatabase.memory());
        databases.add(db);
        return AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(crypto),
            session: session,
            transport: http,
            store: CryptoIdentityStore(
              db,
              _MemorySecure(),
              session.profile.partition,
            ),
            isCurrent: () => true,
          ),
        );
      }

      final owner = make(
        _session(url, fixture['accounts']['owner']['session']),
      );
      final guest = make(
        _session(url, fixture['accounts']['other']['session']),
      );
      try {
        for (final account in [owner, guest]) {
          final file = await account.prepareRecoveryFile();
          files.add(file);
          await account.verifyAndInitialize(file);
        }
        final ownerAccess = SessionCryptoAccess(account: owner);
        final guestAccess = SessionCryptoAccess(account: guest);
        final manager = ScopeCryptoManager(ownerAccess);
        Future<String> scope() async {
          final id = crypto.randomId();
          await manager.createScope(id: id, kind: 'household');
          final page = await owner.directory.call('crypto2.scopes.catalog');
          final metadata =
              (page['scopes'] as List).singleWhere((v) => v['id'] == id) as Map;
          await manager.initializeEmptyScope(
            scopeId: id,
            accessRevision: metadata['accessRevision'],
            members: (metadata['members'] as List).cast<Map<String, dynamic>>(),
          );
          return id;
        }

        final sender = InviteCryptoRepository(ownerAccess);
        final receiver = InviteCryptoRepository(guestAccess);
        Future<Map<String, dynamic>> invite(String id) =>
            sender.dispatch('invitations3.create', {
              'scopeId': id,
              'recipient': fixture['accounts']['other']['username'],
              'role': 'member',
              'language': 'en',
              'requestId': crypto.randomId(),
            });
        final firstScope = await scope();
        final runtime = CryptoBusinessSession(
          owner,
          ownerAccess,
          owner.store.database,
        );
        final record = crypto.randomId(), now = DateTime.utc(2026, 10, 19);
        final raw =
            Map<String, dynamic>.from(
                LocalProject(
                  id: record,
                  title: 'No-card encrypted history',
                  description: 'Synthetic private history',
                  createdAt: now,
                  updatedAt: now,
                  area: ProjectArea.home,
                ).toJson(),
              )
              ..remove('id')
              ..remove('revision')
              ..remove('createdByAccountId')
              ..remove('updatedByAccountId');
        await runtime.publishRaw(
          scopeId: firstScope,
          id: record,
          type: 'project',
          operationId: crypto.randomId(),
          expectedRevision: 0,
          rawPayload: raw,
          localHash: await CryptoBusinessJson.hash(raw),
        );
        final first = await invite(firstScope);
        final firstId = first['invitation']['id'] as String;
        final inspected = await receiver.inspect(token: first['localToken']);
        expect(
          (await receiver.accept(inspected, actionId: firstId))['state'],
          'pendingKeys',
        );
        await expectLater(
          guest.directory.call('crypto2.records.pull', {
            'scopeId': firstScope,
            'domain': 'content',
            'afterSequence': 0,
            'limit': 50,
          }),
          throwsA(isA<CollaborationException>()),
        );
        final recipient = await sender.acceptedRecipient(firstScope, firstId);
        await sender.admit(recipient, await manager.reviewRotation(firstScope));
        expect(await receiver.resumeAccepted(firstId), firstScope);
        final guestRuntime = CryptoBusinessSession(
          guest,
          guestAccess,
          guest.store.database,
        );
        await guestRuntime.pullVerified(firstScope, 'content');
        final restored = await guestRuntime.record(
          firstScope,
          'content',
          record,
        );
        expect(
          (jsonDecode(restored!['raw_payload'] as String) as Map)['title'],
          raw['title'],
        );
        for (final (account, peer) in [(owner, guest), (guest, owner)]) {
          final rows = await account.store.database.rows(
            'SELECT verification_method FROM crypto_trusted_identities WHERE account_id=?',
            [peer.directory.accountId],
          );
          expect(rows.single['verification_method'], 'hostDirectory');
        }
        debugPrint(
          'PASS: no-card accept/pending/admit/decrypt with hostDirectory pins',
        );
      } finally {
        for (final file in files) {
          file.fillRange(0, file.length, 0);
        }
        http.close();
        for (final db in databases) {
          await db.close();
        }
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
