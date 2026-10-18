import 'dart:convert';
import 'dart:io';

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
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

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

class _LostAck implements CollaborationTransport {
  _LostAck(this.inner);
  final CollaborationTransport inner;
  bool lose = false, blocked = false;
  int writes = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (blocked && operation == 'crypto2.receipt.get')
      throw const CollaborationException('network');
    final result = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'crypto2.device.rebind') {
      writes++;
      if (lose) {
        lose = false;
        blocked = true;
        throw const CollaborationException('network');
      }
    }
    return result;
  }

  @override
  void close() {}
}

void main() {
  final path = Platform.environment['JIVIE_CRYPTO2_HTTP_FIXTURE'];
  test(
    'same-phone fresh login rebinds approved local keys, lost ACK resumes and retired key cannot approve again',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map,
          url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback only');
      final crypto = CryptoCodec(await SodiumInit.init()),
          http = HttpCollaborationTransport(),
          db = CollaborationDatabase(NativeDatabase.memory()),
          secure = _MemorySecure();
      final initial = _session(url, fixture['accounts']['owner']['session']);
      AccountCryptoV2Workflow make(DeviceSession s, CollaborationTransport t) =>
          AccountCryptoV2Workflow(
            AccountDirectoryRepository(
              reducer: AccountDirectoryV2(crypto),
              session: s,
              transport: t,
              store: CryptoIdentityStore(db, secure, s.profile.partition),
              isCurrent: () => true,
            ),
          );
      try {
        final original = make(initial, http),
            file = await original.prepareRecoveryFile();
        try {
          await original.verifyAndInitialize(file);
        } finally {
          file.fillRange(0, file.length, 0);
        }
        final before = await original.directory.requireFresh();
        await http.call(
          serverUrl: url,
          operation: 'auth.revoke',
          params: {'deviceId': initial.profile.deviceId},
          token: initial.token,
          allowLocalHttp: true,
        );
        Future<DeviceSession> login() async => _session(
          url,
          await http.call(
            serverUrl: url,
            operation: 'auth.login',
            params: {
              'username': fixture['accounts']['owner']['username'],
              'password': fixture['accounts']['owner']['password'],
              'deviceName': 'Synthetic relogin same phone',
            },
            allowLocalHttp: true,
          ),
        );
        final next = await login(),
            transport = _LostAck(http)..lose = true,
            rebound = make(next, transport);
        expect(await rebound.canRebindLocalDevice(), true);
        await expectLater(
          rebound.rebindLocalDevice(),
          throwsA(isA<CollaborationException>()),
        );
        expect(await rebound.localPhase(), 'pending');
        transport.blocked = false;
        await rebound.resume();
        expect(transport.writes, 1);
        final after = await rebound.directory.requireFresh();
        expect(after.identityEpochId, before.identityEpochId);
        expect(
          after.snapshot['rootEncryptionKeyBase64'],
          before.snapshot['rootEncryptionKeyBase64'],
        );
        expect(
          () => after.activeDevice(initial.profile.deviceId),
          throwsA(isA<CryptoDirectoryException>()),
        );
        after.activeDevice(next.profile.deviceId);
        expect(
          await db.rows(
            'SELECT device_id FROM crypto_identity_secrets WHERE partition=?',
            [next.profile.partition],
          ),
          hasLength(2),
        );
        // Only local material for the now-revoked predecessor is visible to a new
        // session in this isolated copy. It cannot authorize a third device.
        final third = await login(),
            copy = CollaborationDatabase(NativeDatabase.memory());
        try {
          final oldRows = await db.rows(
            'SELECT * FROM crypto_identity_secrets WHERE partition=? AND device_id=?',
            [next.profile.partition, initial.profile.deviceId],
          );
          final row = oldRows.single;
          await copy.execute(
            'INSERT INTO crypto_identity_secrets VALUES(?,?,?,?,?,?,?,?,?,?)',
            [
              next.profile.partition,
              row['device_id'],
              row['signing_secret'],
              row['encryption_secret'],
              row['signing_public'],
              row['encryption_public'],
              row['phase'],
              null,
              row['encrypted_root'],
              row['identity_epoch_id'],
            ],
          );
          final denied = AccountCryptoV2Workflow(
            AccountDirectoryRepository(
              reducer: AccountDirectoryV2(crypto),
              session: third,
              transport: http,
              store: CryptoIdentityStore(copy, secure, third.profile.partition),
              isCurrent: () => true,
            ),
          );
          expect(await denied.canRebindLocalDevice(), false);
          await expectLater(
            denied.rebindLocalDevice(),
            throwsA(isA<CryptoDirectoryException>()),
          );
        } finally {
          await copy.close();
        }
      } finally {
        await db.close();
        http.close();
      }
    },
    skip: path == null ? 'Synthetic HTTP fixture not supplied' : false,
  );
}
