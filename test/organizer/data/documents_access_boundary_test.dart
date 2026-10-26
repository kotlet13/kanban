import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

class _Server extends FakeServer {
  final sheets = <String, Map<String, dynamic>>{};
  final receipts = <String, Map<String, dynamic>>{};
  final documentCalls = <({String operation, Map<String, Object?> params})>[];
  Future<void> Function(String)? afterReply;
  String? denial;
  int committedSaves = 0;

  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (operation == 'capabilities') {
      final result = await super.call(operation, params, token);
      (result['features'] as Map)['spreadsheets'] = true;
      return result;
    }
    if (!operation.startsWith('tables.')) {
      return super.call(operation, params, token);
    }
    documentCalls.add((operation: operation, params: Map.of(params)));
    if (denial != null) throw CollaborationApiException(denial!);
    final sid = params['scopeId'] as String, id = params['id'] as String;
    if (members[sid]?[tokens[token]] != 'owner') {
      throw const CollaborationApiException('permission_revoked');
    }
    final request = params['requestId'] as String?;
    Map<String, dynamic> result;
    if (request != null && receipts.containsKey(request)) {
      result = receipts[request]!;
    } else if (operation == 'tables.create') {
      sheets[id] = {
        'id': id,
        'scopeId': sid,
        'title': params['title'],
        'cells': <String, String>{},
        'revision': 1,
        'updatedAt': 1800000000,
      };
      result = {'sheet': sheets[id]};
    } else if (operation == 'tables.save') {
      final old = sheets[id]!;
      if (old['revision'] != params['expectedRevision']) {
        throw const CollaborationApiException('revision_conflict');
      }
      sheets[id] = {
        ...old,
        'title': params['title'],
        'cells': Map<String, String>.from(params['cells'] as Map),
        'revision': (old['revision'] as int) + 1,
      };
      committedSaves++;
      result = {'sheet': sheets[id]};
    } else if (operation == 'tables.get') {
      result = {'sheet': sheets[id], 'lease': null};
    } else if (operation == 'tables.release') {
      result = {'released': true};
    } else {
      throw StateError('Unexpected document operation: $operation');
    }
    if (request != null) receipts[request] = result;
    await afterReply?.call(operation);
    return result;
  }

  String authority() => jsonEncode({
    'scopes': scopes,
    'members': members,
    'revocations': confirmedRevocations.map((k, v) => MapEntry(k, v.toList())),
  });
}

class _Fixture {
  _Fixture(this.server, this.db, this.repo, this.parent, this.child);
  final _Server server;
  final CollaborationDatabase db;
  final CollaborationRepository repo;
  final String parent, child;
  bool visible = true;
  int accessLost = 0;
  String get partition => repo.state.session!.partition;
  SharedScope scope(String id) =>
      repo.state.scopes.singleWhere((s) => s.id == id);
  Future<SharedDocumentsContext> open() => repo.openDocuments(
    parent,
    visible: () => visible,
    onAccessLost: () => accessLost++,
  );
  Future<List<Map<String, dynamic>>> caches() => db.rows(
    'SELECT name,value FROM local_meta WHERE substr(name,1,?)=? ORDER BY name',
    [
      'document_cache:$partition:$parent:'.length,
      'document_cache:$partition:$parent:',
    ],
  );
}

Future<_Fixture> _fixture() async {
  final server = _Server(), db = CollaborationDatabase(NativeDatabase.memory());
  final repo = CollaborationRepository(
    db,
    FakeTransport(server),
    MemorySessionStore(),
    contentRouteGuard: const SyntheticContentRouteGuard(),
  );
  addTearDown(repo.close);
  await repo.initialize();
  await repo.login(
    serverUrl: 'https://synthetic.invalid',
    username: 'alice',
    password: 'synthetic',
  );
  final parent = await repo.createScope('Organization'),
      child = await repo.createScope('Child');
  server.scopes[parent]!['kind'] = 'organization';
  server.scopes[child]!.addAll({
    'kind': 'project',
    'parentScopeId': parent,
    'parentScopeKind': 'organization',
  });
  await repo.syncNow();
  return _Fixture(server, db, repo, parent, child);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'successful save after local visibility loss retains scope authority and original receipt',
    () async {
      final f = await _fixture(), context = await f.open();
      final table = await context.tables.create('Table');
      final saved = await context.tables.save(
        table.id,
        'a' * 64,
        1,
        table.title,
        {'A1': 'first'},
      );
      await context.tables.storeDraft(
        SpreadsheetDraft(
          tableId: table.id,
          baseRevision: 2,
          title: table.title,
          cells: {'A1': 'second'},
          updatedAt: 1,
        ),
      );
      final caches = await f.caches(), authority = f.server.authority();
      f.server.afterReply = (operation) async {
        if (operation == 'tables.save') f.visible = false;
      };
      await expectLater(
        context.tables.save(table.id, 'a' * 64, saved.revision, table.title, {
          'A1': 'second',
        }),
        throwsA(code('document_context_changed')),
      );
      expect(f.server.committedSaves, 2);
      expect(f.server.sheets[table.id]!['revision'], 3);
      expect(f.scope(f.parent).revoked, isFalse);
      expect(f.scope(f.parent).blocked, isFalse);
      expect(f.scope(f.child).canRead, isTrue);
      expect(f.accessLost, 0);
      expect(await f.caches(), caches);
      expect(f.server.authority(), authority);
      f.visible = true;
      f.server.afterReply = null;
      expect(
        context.isCurrent,
        isFalse,
        reason:
            'A stale handle cannot revive when its route becomes visible again',
      );
      final calls = f.server.documentCalls.length;
      await expectLater(
        context.tables.release(table.id, 'a' * 64),
        throwsA(code('document_context_changed')),
      );
      expect(f.server.documentCalls.length, calls);
      final reopened = await f.open();
      expect((await reopened.tables.loadDraft(table.id))!.cells, {
        'A1': 'second',
      });
      final pending = await f.db.rows(
        "SELECT name,value FROM local_meta WHERE name LIKE 'document_request:%'",
      );
      expect(pending, hasLength(1));
      final recovered = await reopened.tables.save(
        table.id,
        'a' * 64,
        2,
        table.title,
        {'A1': 'second'},
      );
      expect(recovered.revision, 3);
      final saveCalls = f.server.documentCalls
          .where((c) => c.operation == 'tables.save')
          .toList();
      expect(
        saveCalls[1].params,
        saveCalls[2].params,
        reason: 'Explicit recovery uses the original immutable request',
      );
      expect(
        f.server.committedSaves,
        2,
        reason: 'The successful mutation is not applied twice',
      );
      expect(
        await f.db.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'document_request:%'",
        ),
        isEmpty,
      );
    },
  );

  test(
    'confirmed API scope denial still blocks parent and purges cache while preserving draft',
    () async {
      final f = await _fixture(), context = await f.open();
      final table = await context.tables.create('Table');
      await context.tables.storeDraft(
        SpreadsheetDraft(
          tableId: table.id,
          baseRevision: 1,
          title: table.title,
          cells: {'A1': 'draft'},
          updatedAt: 1,
        ),
      );
      f.server.confirmRevocation(f.parent, 'alice');
      f.server.denial = 'permission_revoked';
      await expectLater(
        context.tables.read(table.id),
        throwsA(
          isA<CollaborationApiException>().having(
            (e) => e.code,
            'code',
            'permission_revoked',
          ),
        ),
      );
      expect(f.scope(f.parent).revoked, isTrue);
      expect(f.scope(f.parent).blocked, isTrue);
      expect(f.scope(f.child).revoked, isFalse);
      expect(f.accessLost, 1);
      expect(await f.caches(), isEmpty);
      expect(
        await f.db.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'table_draft:%'",
        ),
        hasLength(1),
      );
      final calls = f.server.documentCalls.length;
      await expectLater(
        context.tables.read(table.id),
        throwsA(code('permission_revoked')),
      );
      expect(f.server.documentCalls.length, calls);
    },
  );

  test(
    'local reconciliation block during successful read cannot become persistent revocation',
    () async {
      final f = await _fixture(), context = await f.open();
      final table = await context.tables.create('Table');
      final caches = await f.caches(), authority = f.server.authority();
      f.server.afterReply = (operation) async {
        if (operation != 'tables.get') return;
        await f.db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
          'scope_reconciliation:${f.partition}:${f.parent}',
          'crypto_pending',
        ]);
        await f.repo.refreshLocal();
      };
      await expectLater(
        context.tables.read(table.id),
        throwsA(code('document_context_changed')),
      );
      expect(f.scope(f.parent).blocked, isTrue);
      expect(f.scope(f.parent).revoked, isFalse);
      final row = (await f.db.rows(
        'SELECT data,blocked FROM scopes WHERE partition=? AND id=?',
        [f.partition, f.parent],
      )).single;
      expect((jsonDecode(row['data'] as String) as Map)['revoked'], isFalse);
      expect(
        row['blocked'],
        0,
        reason:
            'Reconciliation is a temporary read projection, not an ACL block',
      );
      expect(f.scope(f.child).canRead, isTrue);
      expect(f.accessLost, 0);
      expect(await f.caches(), caches);
      expect(f.server.authority(), authority);
    },
  );

  test(
    'late successful old-account save cannot revoke scopes or publish into next account',
    () async {
      final f = await _fixture(), context = await f.open();
      final table = await context.tables.create('Table'),
          originalPartition = f.partition;
      final entered = Completer<void>(), resume = Completer<void>();
      f.server.afterReply = (operation) async {
        if (operation == 'tables.save') {
          entered.complete();
          await resume.future;
        }
      };
      final pending = context.tables.save(table.id, 'a' * 64, 1, table.title, {
        'A1': 'late',
      });
      final assertion = expectLater(pending, throwsA(code('session_changed')));
      await entered.future;
      await f.repo.signOut();
      await f.repo.login(
        serverUrl: 'https://synthetic.invalid',
        username: 'bob',
        password: 'synthetic',
      );
      resume.complete();
      await assertion;
      expect(f.repo.state.session!.partition, isNot(originalPartition));
      expect(f.repo.state.scopes, isEmpty);
      final prior = await f.db.rows(
        'SELECT data FROM scopes WHERE partition=?',
        [originalPartition],
      );
      expect(prior, hasLength(2));
      expect(
        prior.every(
          (r) => (jsonDecode(r['data'] as String) as Map)['revoked'] == false,
        ),
        isTrue,
      );
      expect(f.server.committedSaves, 1);
      expect(context.isCurrent, isFalse);
      expect(f.accessLost, 0);
    },
  );

  test(
    'late successful lease release after route disposal cannot revoke parent',
    () async {
      final f = await _fixture(), context = await f.open();
      final table = await context.tables.create('Table');
      final authority = f.server.authority(), caches = await f.caches();
      final entered = Completer<void>(), resume = Completer<void>();
      f.server.afterReply = (operation) async {
        if (operation == 'tables.release') {
          entered.complete();
          await resume.future;
        }
      };
      final release = context.tables.release(table.id, 'a' * 64);
      final assertion = expectLater(
        release,
        throwsA(code('document_context_changed')),
      );
      await entered.future;
      f.visible = false;
      resume.complete();
      await assertion;
      expect(f.scope(f.parent).revoked, isFalse);
      expect(f.scope(f.parent).blocked, isFalse);
      expect(f.scope(f.child).canRead, isTrue);
      expect(f.server.authority(), authority);
      expect(await f.caches(), caches);
      expect(f.accessLost, 0);
      f.visible = true;
      expect(context.isCurrent, isFalse);
      expect(
        f.server.documentCalls.where((c) => c.operation == 'tables.release'),
        hasLength(1),
      );
    },
  );

  test(
    'unsupported local table scope stays rejected without revoking readable scope',
    () async {
      final f = await _fixture();
      f.server.scopes[f.parent]!['kind'] = 'household';
      await f.repo.syncNow();
      final context = await f.open();
      await expectLater(
        context.tables.create('Unsupported'),
        throwsA(code('tables_scope_unsupported')),
      );
      expect(f.scope(f.parent).revoked, isFalse);
      expect(f.scope(f.parent).canRead, isTrue);
      expect(f.server.documentCalls, isEmpty);
      expect(f.accessLost, 0);
    },
  );
}
