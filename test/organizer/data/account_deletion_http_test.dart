// Opt-in isolated synthetic HTTP fixture only. No credentials/bodies in output.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/account_deletion_store.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import 'collaboration_repository_test.dart' show MemorySessionStore, code;
import 'family_upgrade_http_test.dart' show ControlledHttp;

class _IsolatedFixture {
  _IsolatedFixture(this.server, this.container);
  final String server, container;

  static Future<_IsolatedFixture> read(String path) async {
    final j = jsonDecode(await File(path).readAsString());
    if (j is! Map<String, dynamic> ||
        j['synthetic'] != true ||
        j['server'] is! String ||
        j['container'] is! String) {
      throw StateError('Explicit isolated synthetic fixture required');
    }
    final uri = Uri.parse(j['server'] as String);
    if (uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.port != 18384 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(j['container'] as String).startsWith(
          'kanban-familyhub-account-deletion-final',
        )) {
      throw StateError(
        'Only the dedicated loopback deletion fixture is allowed',
      );
    }
    // Deliberately do not read owner/bootstrap credentials from this fixture.
    return _IsolatedFixture(uri.toString(), j['container'] as String);
  }

  Future<String> _php(String code, Map<String, Object?> input) async {
    final process = await Process.start('docker', [
      'exec',
      '-i',
      container,
      'php',
      '-r',
      [
        r"require '/var/www/app/app/common.php'; if(session_status()===PHP_SESSION_ACTIVE){session_abort();} "
            r"if(!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE!==true || !defined('FAMILYHUB_ACCOUNT_MODE') || FAMILYHUB_ACCOUNT_MODE!=='self_hosted'){exit(12);} "
            r'$input=json_decode(stream_get_contents(STDIN),true,16,JSON_THROW_ON_ERROR); ',
        code,
      ].join(),
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    process.stdin.write(jsonEncode(input));
    await process.stdin.close();
    final result = await process.exitCode;
    final value = await output;
    await errors;
    if (result != 0) {
      throw StateError('Isolated synthetic database operation failed');
    }
    return value.trim();
  }

  Future<({int id, String username, String password})> createUser() async {
    final username = 'httpdel_${newSharedId().replaceAll('-', '')}';
    final password = 'Jivie-test-${newSharedId()}';
    final value = await _php(
      r"$id=$container['userModel']->create(['username'=>$input['username'],'password'=>$input['password'],'name'=>'Synthetic HTTP deletion','role'=>'app-user']); if(!$id){exit(13);} echo $id;",
      {'username': username, 'password': password},
    );
    final id = int.tryParse(value);
    if (id == null || id < 1) {
      throw StateError('Synthetic user creation not confirmed');
    }
    return (id: id, username: username, password: password);
  }

  Future<bool> userExists(int id) async =>
      await _php(
        r"$p=$container['db']->getConnection();$q=$p->prepare('SELECT COUNT(*) FROM users WHERE id=?');$q->execute([$input['id']]);echo $q->fetchColumn();",
        {'id': id},
      ) ==
      '1';
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['KANBAN_ACCOUNT_DELETION_HTTP_FIXTURE'];
  final skipped = path == null || path.isEmpty;

  Future<
    ({
      CollaborationRepository repo,
      ControlledHttp http,
      MemoryAccountDeletionStore receipts,
    })
  >
  client() async {
    final http = ControlledHttp(), receipts = MemoryAccountDeletionStore();
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      http,
      MemorySessionStore(),
      deletionStore: receipts,
    );
    await repo.initialize();
    addTearDown(repo.close);
    return (repo: repo, http: http, receipts: receipts);
  }

  test(
    'real HTTP deletion: decoded preview and explicit own scope removal delete the Kanboard user',
    () async {
      final fixture = await _IsolatedFixture.read(path!);
      final user = await fixture.createUser();
      final c = await client();
      await c.repo.login(
        serverUrl: fixture.server,
        username: user.username,
        password: user.password,
        allowLocalHttp: true,
      );
      expect(await fixture.userExists(user.id), true);
      final initial = await c.repo.previewAccountDeletion();
      expect(initial['canDelete'], true);
      final scope = await c.repo.createScope('Synthetic owned HTTP scope');
      final preview = await c.repo.previewAccountDeletion();
      expect(preview['canDelete'], false);
      final owned = (preview['ownedScopes'] as List)
          .cast<Map<String, dynamic>>();
      expect(owned.single['id'], scope);
      expect(owned.single['canDeleteScope'], true);
      Map<String, Object?>? receipt;
      c.http.before = (operation, params) async {
        if (operation == 'account.deletion.confirm') {
          // Keep only the narrow proof; never retain a password/request body.
          receipt = {
            'operationId': params['operationId'],
            'receiptToken': params['receiptToken'],
          };
        }
      };
      await c.repo.confirmAccountDeletion(
        previewHash: preview['previewHash'] as String,
        password: user.password,
        ownedScopeDeletions: [scope],
        review: preview,
      );
      expect(c.repo.state.session, null);
      expect(c.receipts.requests, isEmpty);
      expect(await fixture.userExists(user.id), false);
      final status = await c.http.call(
        serverUrl: fixture.server,
        operation: 'account.deletion.status',
        params: receipt!,
        allowLocalHttp: true,
      );
      expect(status['deleted'], true);
      expect(status['cleanupPending'], false);
      expect(status['cancelled'], false);
    },
    skip: skipped,
  );

  test(
    'real HTTP unknown-before-send is safely cancelled then fresh review deletes only the synthetic user',
    () async {
      final fixture = await _IsolatedFixture.read(path!);
      final user = await fixture.createUser();
      final c = await client();
      await c.repo.login(
        serverUrl: fixture.server,
        username: user.username,
        password: user.password,
        allowLocalHttp: true,
      );
      final preview = await c.repo.previewAccountDeletion();
      var dropped = false;
      c.http.before = (operation, _) async {
        if (operation == 'account.deletion.confirm' && !dropped) {
          dropped = true;
          throw const CollaborationException(
            'network',
          ); // no HTTP mutation sent
        }
      };
      await expectLater(
        c.repo.confirmAccountDeletion(
          previewHash: preview['previewHash'] as String,
          password: user.password,
          review: preview,
        ),
        throwsA(code('network')),
      );
      final pending = c.receipts.requests.single;
      expect(c.repo.state.deletionPending, true);
      expect(await fixture.userExists(user.id), true);
      final unknown = await c.http.call(
        serverUrl: fixture.server,
        operation: 'account.deletion.status',
        params: {
          'operationId': pending.operationId,
          'receiptToken': pending.receiptToken,
        },
        allowLocalHttp: true,
      );
      expect(unknown['deleted'], false);
      expect(unknown['cancelled'], false);
      expect(await c.repo.cancelPendingAccountDeletion(pending), true);
      expect(c.repo.state.deletionPending, false);
      expect(c.repo.state.session, isNotNull);
      expect(c.receipts.requests, isEmpty);
      expect(await fixture.userExists(user.id), true);
      final cancelled = await c.http.call(
        serverUrl: fixture.server,
        operation: 'account.deletion.status',
        params: {
          'operationId': pending.operationId,
          'receiptToken': pending.receiptToken,
        },
        allowLocalHttp: true,
      );
      expect(cancelled['cancelled'], true);
      expect(cancelled['deleted'], false);
      final fresh = await c.repo.previewAccountDeletion();
      await c.repo.confirmAccountDeletion(
        previewHash: fresh['previewHash'] as String,
        password: user.password,
        review: fresh,
      );
      expect(c.repo.state.session, null);
      expect(c.receipts.requests, isEmpty);
      expect(await fixture.userExists(user.id), false);
    },
    skip: skipped,
  );
}
