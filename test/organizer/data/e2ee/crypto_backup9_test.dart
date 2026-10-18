import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/portable_backup_document.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const _scope = '00000000-0000-4000-8000-000000000001';
final _profile = AccountSession(
  serverUrl: 'https://synthetic.invalid/',
  serverId: '00000000-0000-4000-8000-000000000002',
  accountId: '00000000-0000-4000-8000-000000000003',
  userId: 1,
  username: 'synthetic',
  displayName: 'Synthetic',
  deviceId: '00000000-0000-4000-8000-000000000004',
  expiresAt: DateTime.utc(2030),
);
void main() {
  test(
    'real encrypted backup9 retains raw crypto evidence, excludes private keys and installs same-account reconciliation fence before any legacy request',
    () async {
      final a = CollaborationDatabase(NativeDatabase.memory()),
          b = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(a.close);
      addTearDown(b.close);
      final source = SqliteOrganizerStorage(a),
          target = SqliteOrganizerStorage(b);
      await source.initialize();
      await target.initialize();
      a.activatePersonal(_profile);
      final p = _profile.partition;
      await a.execute(
        "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,epoch,floor,access_revision) VALUES(?,?,'content','active',3,3,8)",
        [p, _scope],
      );
      await a.execute(
        "INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash) VALUES(?,'request','crypto2.records.batch',? ,?)",
        [
          p,
          '{"signatureBase64":"exact signature","commandBase64":"exact ciphertext"}',
          'a' * 64,
        ],
      );
      await a.execute(
        "INSERT INTO crypto_scope_keys VALUES(?,?,'content',3,'epoch','key',?,'head',?,1,1)",
        [
          p,
          _scope,
          Uint8List.fromList(utf8.encode('SECRET never generic JSON')),
          Uint8List.fromList([1, 2]),
        ],
      );
      final backup = PortableBackupRepository(
        a,
        source,
        MemoryBackupUiPreferencesStore(),
      );
      const password = 'synthetic sufficiently long password';
      final bytes = await backup.exportEncryptedBackup(password);
      final doc = await backup.crypto.decrypt(bytes, password);
      expect(doc['version'], 9);
      expect(doc['databaseVersion'], 11);
      validateBackupDocument(doc);
      final evidence = doc['cryptoEvidence'] as Map;
      expect(jsonEncode(evidence), isNot(contains('SECRET')));
      expect(jsonEncode(evidence), isNot(contains('crypto_scope_keys')));
      final rows = (evidence['tables'] as Map)['crypto_outbox'] as List;
      expect(
        (rows.single as Map)['signed_body'],
        '{"signatureBase64":"exact signature","commandBase64":"exact ciphertext"}',
      );
      final restore = PortableBackupRepository(
        b,
        target,
        MemoryBackupUiPreferencesStore(),
      );
      await restore.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await target.read()).revision,
      );
      expect(await b.rows('SELECT * FROM crypto_outbox'), isEmpty);
      expect(await b.rows('SELECT * FROM crypto_scope_keys'), isEmpty);
      expect(await b.rows('SELECT * FROM crypto_scope_state'), isEmpty);
      expect(await b.rows('SELECT * FROM restored_backups'), hasLength(1));
      await expectLater(
        routeProtectedCryptoDomain(
          database: b,
          session: DeviceSession(_profile, 'synthetic'),
          operation: 'sync6.push',
          params: {
            'scopeId': _scope,
            'operation': {'private': 'must never be sent'},
          },
          router: null,
          checkCurrent: () {},
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'crypto_reconciliation_required',
          ),
        ),
      );
      // Loading an old backup never deletes this conservative floor/fence.
      final old = Map<String, dynamic>.from(doc)
        ..remove('cryptoEvidence')
        ..remove('cryptoPrivateDrafts')
        ..['version'] = 8
        ..['databaseVersion'] = 10;
      validateBackupDocument(old);
      final oldBytes = await backup.crypto.encrypt(old, password);
      await restore.restoreEncryptedBackup(
        oldBytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await target.read()).revision,
      );
      expect(await b.rows('SELECT * FROM crypto_scope_state'), isEmpty);
      expect(
        (await b.rows(
          'SELECT minimum_transport FROM crypto_restore_fences',
        )).single['minimum_transport'],
        2,
      );
    },
  );
}
