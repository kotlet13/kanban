import 'dart:async';
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
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';

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

void main() {
  final path = Platform.environment['JIVIE_PROTECTION_HTTP_FIXTURE'];
  test(
    'signed empty protection completion resumes exact request offline; unavailable review binds pins',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      if (fixture['synthetic'] != true ||
          Uri.parse(fixture['serverUrl']).host != '127.0.0.1')
        throw StateError('Synthetic only');
      final session = _session(
        fixture['serverUrl'],
        fixture['accounts']['owner']['session'],
      );
      final db = CollaborationDatabase(NativeDatabase.memory());
      final secure = _MemorySecure();
      final crypto = CryptoCodec(await SodiumInit.init());
      final workflow = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: HttpCollaborationTransport(),
          store: CryptoIdentityStore(db, secure, session.profile.partition),
          isCurrent: () => true,
        ),
      );
      try {
        final file = await workflow.prepareRecoveryFile();
        try {
          await workflow.verifyAndInitialize(file);
        } finally {
          file.fillRange(0, file.length, 0);
        }
        final service = AccountProtectionReady(workflow);
        await service.complete();
        final completed = await service.cachedCompletion();
        expect(completed, isNotNull);
        final head =
            (await workflow.directory.cachedVerifiedDirectory()).headHash;
        await service
            .complete(); // Same completed catalog reuses its exact request.
        expect(
          (await workflow.directory.cachedVerifiedDirectory()).headHash,
          head,
        );
        expect(await service.matchesCurrentCatalog(completed!), isTrue);
        final missing = crypto.randomId();
        await db.execute(
          'INSERT INTO crypto_scope_heads VALUES(?,?,?,?,?,?,?,?,?)',
          [
            session.profile.partition,
            missing,
            'a' * 64,
            1,
            1,
            '1',
            '0' * 64,
            Uint8List.fromList([123, 125]),
            Uint8List.fromList([123, 125]),
          ],
        );
        await secure.write(
          'scope2:${session.profile.partition}:$missing',
          'local verified secure floor',
        );
        await expectLater(
          service.complete(),
          throwsA(isA<CryptoAuthorityPending>()),
        );
        final review = await service.unavailableReview();
        expect(review!['missingScopes'], hasLength(1));
        await service.complete(reviewedUnavailable: review);
        expect(await service.cachedCompletion(), isNotNull);
        await secure.write(
          'scope2:${session.profile.partition}:$missing',
          'newer verified floor',
        );
        expect(await service.cachedCompletion(), isNull);
        final created = crypto.randomId();
        await ScopeCryptoManager(
          SessionCryptoAccess(account: workflow),
        ).createScope(id: created, kind: 'household');
        expect(await service.matchesCurrentCatalog(completed), isFalse);
      } finally {
        await db.close();
      }
    },
    skip: path == null,
  );
}
