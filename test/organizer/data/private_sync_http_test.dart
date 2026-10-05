// Explicit isolated synthetic loopback fixture. No credentials/bodies in logs.
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;
import 'family_upgrade_http_test.dart' show ControlledHttp;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['KANBAN_PERSONAL_HTTP_FIXTURE'];
  test(
    'real HTTP enrollment/mail/reset + two personal SQLite clients, finance unlink and encrypted replay recovery',
    () async {
      final fixture =
              jsonDecode(await File(path!).readAsString())
                  as Map<String, dynamic>,
          url = fixture['server'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Isolated loopback fixture required');
      }
      final owner = fixture['owner'] as Map<String, dynamic>,
          nonadmin = fixture['nonadmin'] as Map<String, dynamic>;
      final directory = await Directory.systemTemp.createTemp('private-http-');
      addTearDown(() => directory.delete(recursive: true));
      Future<
        ({
          CollaborationDatabase db,
          SqliteOrganizerStorage storage,
          OrganizerRepository personal,
          CollaborationRepository shared,
          ControlledHttp http,
          PortableBackupRepository backup,
          MemorySessionStore store,
        })
      >
      client(String name, {MemorySessionStore? existingStore}) async {
        final db = CollaborationDatabase(
              NativeDatabase(File('${directory.path}/$name.sqlite')),
            ),
            http = ControlledHttp(),
            store = existingStore ?? MemorySessionStore();
        final storage = SqliteOrganizerStorage(db);
        await storage.initialize();
        final personal = OrganizerRepository(storage);
        await personal.initialize();
        final shared = CollaborationRepository(
          db,
          http,
          store,
          ownsDatabase: false,
        );
        await shared.initialize();
        final backup = PortableBackupRepository(
          db,
          storage,
          MemoryBackupUiPreferencesStore(),
          collaboration: () => shared,
        );
        addTearDown(() async {
          await personal.close();
          await shared.close();
          await db.close();
        });
        return (
          db: db,
          storage: storage,
          personal: personal,
          shared: shared,
          http: http,
          backup: backup,
          store: store,
        );
      }

      Future<void> login(CollaborationRepository repo, String password) =>
          repo.login(
            serverUrl: url,
            username: owner['username'] as String,
            password: password,
            allowLocalHttp: true,
          );
      Future<String> mailCode(String prefix) async {
        final cron = await Process.run('docker', [
          'exec',
          fixture['container'] as String,
          'php',
          '/var/www/app/plugins/FamilyHub/cli/account-mail.php',
          '--limit=20',
        ]);
        if (cron.exitCode != 0) throw StateError('Synthetic mail cron failed');
        final capture = await Process.run('docker', [
          'exec',
          fixture['container'] as String,
          'php',
          '-r',
          'echo file_get_contents(\$argv[1]);',
          fixture['capturePath'] as String,
        ]);
        if (capture.exitCode != 0) {
          throw StateError('Synthetic mail capture unavailable');
        }
        final messages =
            (jsonDecode(capture.stdout as String) as Map)['messages'] as List;
        final matches = <String>[];
        for (final value in messages) {
          final body = (value as Map)['body'] as String;
          matches.addAll(
            RegExp(
              '$prefix'
              r'[0-9a-f]{64}',
            ).allMatches(body).map((m) => m.group(0)!),
          );
        }
        if (matches.isEmpty) {
          throw StateError('Synthetic mail code was not delivered');
        }
        return matches.last;
      }

      final a = await client('a'), b = await client('b');
      final originalPassword = owner['password'] as String;
      await a.shared.enroll(
        serverUrl: url,
        code: (fixture['bootstrap'] as Map)['code'] as String,
        username: owner['username'] as String,
        password: originalPassword,
        name: owner['displayName'] as String,
        allowLocalHttp: true,
      );
      await a.personal.createProject(title: 'Local-only until opt-in');
      final originalId = a.personal.snapshot.projects.single.id;
      await a.personal.createFinanceEntry(
        title: 'Exact private amount',
        amountMinor: 12345,
        currency: 'EUR',
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.utc(2026),
        projectId: originalId,
      );
      expect(a.shared.state.privateSync.enabled, false);
      expect(a.shared.state.scopes, isEmpty);
      await a.personal.reload();
      await a.shared.enablePrivateSync(
        expectedRevision: (await a.shared.previewPrivateSync()).revision,
      );
      await a.personal.reload();
      expect(a.shared.state.lastError, isNull);
      await login(b.shared, originalPassword);
      await b.personal.reload();
      await b.shared.enablePrivateSync(
        expectedRevision: (await b.shared.previewPrivateSync()).revision,
      );
      await b.personal.reload();
      expect(b.personal.snapshot.financeEntries.single.amountMinor, 12345);
      expect(b.personal.snapshot.financeEntries.single.projectId, originalId);
      final outsider = await client('outsider');
      await outsider.shared.login(
        serverUrl: url,
        username: nonadmin['username'] as String,
        password: nonadmin['password'] as String,
        allowLocalHttp: true,
      );
      final scope = a.shared.state.privateSync.scopeId!;
      for (final operation in [
        'sync2.pull',
        'finance.pull',
        'scopes.members',
        'invitations.create',
      ]) {
        try {
          await outsider.http.call(
            serverUrl: url,
            operation: operation,
            params: {
              'scopeId': scope,
              'cursor': 0,
              'recipientUsername': 'nobody',
              'role': 'member',
              'requestId': newSharedId(),
            },
            token: outsider.store.value!.token,
            allowLocalHttp: true,
          );
          fail('Outsider must be denied');
        } on CollaborationException catch (e) {
          expect(
            const [
              'permission_revoked',
              'finance_forbidden',
              'validation_error',
            ].contains(e.code),
            true,
          );
        }
      }
      a.http.offline = true;
      await a.personal.createProject(title: 'Offline temporary');
      final temporary = a.personal.snapshot.projects.last.id;
      await a.personal.createFinanceEntry(
        title: 'Unlinked offline',
        amountMinor: 399,
        currency: 'EUR',
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.utc(2026),
        projectId: temporary,
      );
      await a.personal.deleteProject(temporary);
      final finance = a.personal.snapshot.financeEntries.firstWhere(
        (f) => f.amountMinor == 12345,
      );
      await a.personal.updateFinanceEntry(finance.copyWith(amountMinor: 12999));
      const backupPassword = 'isolated long backup password';
      final bytes = await a.backup.exportEncryptedBackup(backupPassword),
          preview = await a.backup.inspectEncryptedBackup(
            bytes,
            backupPassword,
          );
      a.http.offline = false;
      a.http.loseReply = 'finance.push';
      await a.shared.syncNow();
      await a.shared.syncNow();
      await a.shared.syncNow();
      expect(a.shared.state.lastError, isNull);
      await b.shared.syncNow();
      await b.personal.reload();
      expect(b.personal.snapshot.financeEntries.length, 2);
      expect(
        b.personal.snapshot.financeEntries.any((f) => f.projectId == temporary),
        false,
      );
      final recovery = await client('recovery');
      await login(recovery.shared, originalPassword);
      await recovery.personal.reload();
      await recovery.backup.restoreEncryptedBackup(
        bytes,
        backupPassword,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await recovery.storage.read()).revision,
      );
      await recovery.backup.resumeRestoredWork(
        preview.backupId,
        password: backupPassword,
      );
      await recovery.personal.reload();
      expect(recovery.shared.state.lastError, isNull);
      expect(recovery.personal.snapshot.financeEntries.length, 2);
      expect(
        recovery.personal.snapshot.financeEntries.any(
          (f) => f.amountMinor == 12999,
        ),
        true,
      );
      expect(await recovery.db.rows('SELECT * FROM finance_outbox'), isEmpty);
      expect(a.shared.state.emailVerificationSupported, true);
      await a.shared.requestEmailVerification(
        email: 'owner@synthetic.invalid',
        password: originalPassword,
      );
      await a.shared.confirmEmailVerification(await mailCode('fhv1_'));
      expect((await a.shared.accountStatus()).emailVerified, true);
      await a.shared.requestPasswordReset(
        serverUrl: url,
        username: owner['username'] as String,
        allowLocalHttp: true,
      );
      final resetCode = await mailCode('fhr1_'),
          changedPassword = '$originalPassword changed';
      await a.shared.confirmPasswordReset(
        serverUrl: url,
        token: resetCode,
        password: changedPassword,
        allowLocalHttp: true,
      );
      expect(a.shared.state.sessionInvalid, true);
      await b.shared.syncNow();
      expect(b.shared.state.sessionInvalid, true);
      await b.personal.reload();
      expect(b.personal.snapshot.financeEntries, isEmpty);
      await login(b.shared, changedPassword);
      await b.shared.syncNow();
      await b.personal.reload();
      expect(b.personal.snapshot.financeEntries.length, 2);
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
