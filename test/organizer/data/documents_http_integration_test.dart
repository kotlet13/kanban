import '../support/synthetic_content_route_guard.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/attachment_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore, code;

class _Http extends HttpCollaborationTransport {
  bool offline = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) {
    if (offline) throw const CollaborationException('network');
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
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final port = Platform.environment['JIVIE_DOCUMENTS_HTTP_PORT'];
  test(
    'real Dart/PHP tables leases attachments and offline restart',
    () async {
      if (!const ['18500', '18501'].contains(port)) {
        throw StateError('Dedicated synthetic fixture only');
      }
      final container = port == '18500'
          ? 'familyhub-documents-tests-sqlite-1'
          : 'familyhub-documents-tests-mariadb-1';
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final names = ['dart_docs_${stamp}_a', 'dart_docs_${stamp}_b'];
      final password = 'synthetic-${newSharedId()}';
      Future<void> seed(String script) async {
        final result = await Process.run('docker', [
          'exec',
          container,
          'php',
          '-r',
          "require '/var/www/app/app/common.php'; if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || !FAMILYHUB_DEVELOPMENT_MODE) { exit(91); } $script",
        ]);
        expect(
          result.exitCode,
          0,
          reason: 'Isolated synthetic fixture preparation',
        );
      }

      await seed(
        "foreach (json_decode(base64_decode('${base64Encode(utf8.encode(jsonEncode(names)))}'),true) as \$name) { \$container['userModel']->create(['username'=>\$name,'password'=>'$password','role'=>'app-user','name'=>\$name]); }",
      );
      final directory = await Directory.systemTemp.createTemp(
        'jivie-documents-http-',
      );
      final stores = [MemorySessionStore(), MemorySessionStore()];
      final transports = [_Http(), _Http()];
      final repositories = <CollaborationRepository>[];
      Future<CollaborationRepository> open(int index) async {
        final repo = CollaborationRepository(
          CollaborationDatabase(
            NativeDatabase(File('${directory.path}/$index.sqlite')),
          ),
          transports[index],
          stores[index],
          contentRouteGuard: const SyntheticContentRouteGuard(),
        );
        await repo.initialize();
        repositories.add(repo);
        return repo;
      }

      addTearDown(() async {
        for (final repo in repositories) {
          await repo.close();
        }
        await directory.delete(recursive: true);
      });
      final a = await open(0);
      var b = await open(1);
      for (final (index, repo) in [(0, a), (1, b)]) {
        await repo.login(
          serverUrl: 'http://127.0.0.1:$port',
          username: names[index],
          password: password,
          allowLocalHttp: true,
        );
        await repo.acceptSharedContentPolicy(await repo.sharedContentPolicy());
      }
      final scope = await a.createScope(
        'Synthetic shared tables',
        kind: SharedScopeKind.organization,
      );
      final member = b.state.session!;
      await seed(
        "\$pdo=\$container['db']->getConnection();\$s=\$pdo->prepare('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)');\$s->execute(['$scope',${member.userId},'${member.accountId}','member']);",
      );
      await b.syncNow();
      final ca = await a.openDocuments(scope),
          cb = await b.openDocuments(scope);
      expect(ca.spreadsheetsSupported, isTrue);
      expect(ca.attachmentsSupported, isTrue);
      final ga = ca.tables, gb = cb.tables;
      final table = await ga.create('Equipment');
      expect((await gb.list()).single.id, table.id);
      final ownerLease = await ga.acquire(table.id);
      expect(ownerLease.token, isNotNull);
      expect((await ga.acquire(table.id)).token, ownerLease.token);
      await expectLater(gb.acquire(table.id), throwsA(code('table_locked')));
      final locked = await gb.read(table.id);
      expect(locked.lease!.holderAccountId, a.state.session!.accountId);
      expect(locked.lease!.token, isNull);
      final saved = await ga.save(table.id, ownerLease.token!, 1, table.title, {
        'A1': '3',
        'A2': '4',
        'A3': '=SUM(A1:A2)',
      });
      expect(saved.revision, 2);
      expect((await gb.read(table.id)).document.cells['A3'], '=SUM(A1:A2)');
      await ga.release(table.id, ownerLease.token!);
      final memberLease = await gb.acquire(table.id);
      final updated = await gb.save(
        table.id,
        memberLease.token!,
        2,
        table.title,
        {'A1': '5', 'A2': '4', 'A3': '=SUM(A1:A2)'},
      );
      expect(updated.revision, 3);
      await expectLater(
        ga.save(table.id, ownerLease.token!, 2, 'Stale', {}),
        throwsA(code('lease_lost')),
      );
      await gb.release(table.id, memberLease.token!);
      final target = AttachmentTarget(
        scopeId: scope,
        targetType: 'table',
        targetId: table.id,
      );
      final fa = ca.attachments(target), fb = cb.attachments(target);
      final bytes = Uint8List.fromList(
        utf8.encode('Synthetic document\n${'safe document text\n' * 20000}'),
      );
      await fa.upload(name: 'notes.txt', mime: 'text/plain', bytes: bytes);
      final file = (await fb.list()).single;
      expect(await fb.download(file), bytes);
      expect(
        (await b.previewContentReport(
          scopeId: scope,
          targetType: 'table',
          targetId: table.id,
        )).type,
        'table',
      );
      expect(
        (await b.previewContentReport(
          scopeId: scope,
          targetType: 'attachment',
          targetId: file.id,
        )).type,
        'attachment',
      );
      await b.close();
      repositories.remove(b);
      transports[1] = _Http()..offline = true;
      b = await open(1);
      final offline = await b.openDocuments(scope);
      expect(offline.online, isFalse);
      expect((await offline.tables.read(table.id)).document.cells['A1'], '5');
      final offlineFiles = offline.attachments(target);
      expect((await offlineFiles.list()).single.id, file.id);
      expect(offlineFiles.localBytes(file), bytes);
      expect(await offlineFiles.download(file), bytes);
      await expectLater(
        offline.tables.acquire(table.id),
        throwsA(code('network')),
      );
      transports[1].offline = false;
      final fresh = await b.openDocuments(scope);
      await fresh.attachments(target).delete(file);
      expect(await fresh.attachments(target).list(), isEmpty);
      final finalLease = await fresh.tables.acquire(table.id);
      await fresh.tables.delete(table.id, finalLease.token!, 3);
      expect(await fresh.tables.list(), isEmpty);
    },
    skip: port == null
        ? 'Opt in to dedicated compose.documents-tests.yaml fixture'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
