import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/attachment_models.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

const _table = '20000000-0000-4000-8000-000000000001';
const _file = '20000000-0000-4000-8000-000000000002';
const _wire = '20000000-0000-4000-8000-000000000003';

class _Server extends FakeServer {
  int caps = 0, documentCalls = 0;
  bool supported = true;
  Object? capabilityFailure;
  Completer<void>? capabilityGate;
  late SpreadsheetDocument document;
  Future<void> Function(String)? beforeDocument;
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (operation == 'capabilities') {
      caps++;
      await capabilityGate?.future;
      if (capabilityFailure != null) throw capabilityFailure!;
      final result = await super.call(operation, params, token);
      (result['features'] as Map).addAll(<String, bool>{
        'spreadsheets': supported,
        'attachments': supported,
      });
      return result;
    }
    if (operation.startsWith('tables.') ||
        operation.startsWith('attachments.')) {
      documentCalls++;
      await beforeDocument?.call(operation);
      if (operation == 'tables.list') {
        return {
          'sheets': [document.toJson()],
        };
      }
      if (operation == 'tables.get') {
        return {'sheet': document.toJson(), 'lease': null};
      }
      if (operation == 'attachments.list') return {'attachments': <Object>[]};
      throw StateError('No mutation/download in preview fixture: $operation');
    }
    return super.call(operation, params, token);
  }
}

class _Clock {
  DateTime now = DateTime.now();
}

class _Fixture {
  _Fixture(this.db, this.repo, this.server, this.clock, this.scope);
  final CollaborationDatabase db;
  final CollaborationRepository repo;
  final _Server server;
  final _Clock clock;
  final String scope;
  String get partition => repo.state.session!.partition;
  Future<SharedDocumentsContext> open({void Function()? denied}) =>
      repo.openDocuments(
        scope,
        localPreviewFeature: 'spreadsheets',
        onAccessLost: denied,
      );
}

Future<_Fixture> _fixture() async {
  final server = _Server(), clock = _Clock();
  final db = CollaborationDatabase(NativeDatabase.memory());
  final repo = CollaborationRepository(
    db,
    FakeTransport(server),
    MemorySessionStore(),
    clock: () => clock.now,
    contentRouteGuard: const SyntheticContentRouteGuard(),
  );
  addTearDown(repo.close);
  await repo.initialize();
  await repo.login(
    serverUrl: 'https://synthetic.invalid',
    username: 'alice',
    password: 'synthetic',
  );
  final scope = await repo.createScope('Preview fixture');
  server.scopes[scope]!['kind'] = 'organization';
  await repo.syncNow();
  server.document = SpreadsheetDocument(
    id: _table,
    scopeId: scope,
    title: 'Verified local table',
    cells: {'A1': 'local cell'},
    revision: 1,
    updatedAt: 1,
  );
  final context = await repo.openDocuments(scope);
  await context.putCache('table', _table, server.document.toJson());
  await context.rememberTable(server.document);
  final metadata = AttachmentMetadata(
    id: _file,
    scopeId: scope,
    targetType: 'table',
    targetId: _table,
    name: 'local.pdf',
    mime: 'application/pdf',
    size: 4,
    sha256: 'a' * 64,
    createdAt: 1,
    complete: true,
    offset: 4,
  );
  await context.putCache('attachments', 'table:$_table', [metadata.toJson()]);
  server.caps = 0;
  server.documentCalls = 0;
  return _Fixture(db, repo, server, clock, scope);
}

Future<void> _flush() async {
  for (var n = 0; n < 12; n++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'warm guarded previews need no RPC; fresh support and known canonical deletion still win',
    () async {
      final f = await _fixture();
      f.server.capabilityGate = Completer<void>();
      final context = await f.open();
      final tables = context.tables as SpreadsheetLocalPreview;
      expect(f.server.caps, 0);
      expect(
        (await tables.cachedRead(_table))!.document.cells['A1'],
        'local cell',
      );
      expect((await tables.cachedRead(_table))!.lease, isNull);
      expect((await tables.cachedList())!.single.id, _table);
      final files = context.attachments(
        AttachmentTarget(
          scopeId: f.scope,
          targetType: 'table',
          targetId: _table,
        ),
      );
      expect(
        (await (files as AttachmentLocalPreview).cachedList())!.single.id,
        _file,
      );
      expect(
        files.localBytes(
          (await (files as AttachmentLocalPreview).cachedList())!.single,
        ),
        isNull,
      );
      f.server.supported = false;
      final tableRead = expectLater(
        context.tables.list(),
        throwsA(code('documents_upgrade_required')),
      );
      final fileRead = expectLater(
        files.list(),
        throwsA(code('documents_upgrade_required')),
      );
      await _flush();
      expect(f.server.caps, 1);
      expect(f.server.documentCalls, 0);
      f.server.capabilityGate!.complete();
      await Future.wait([tableRead, fileRead]);
      expect(f.server.caps, 1);
      expect(f.server.documentCalls, 0);
      // Explicit preverified canonical tombstone SQL seam; no crypto admission
      // or receipt verification is claimed by this local read fixture.
      await f.db.execute(
        'INSERT INTO crypto_business_addresses VALUES(?,?,?,?,?,?,?)',
        [f.partition, f.scope, 'content', 'tables', _table, _wire, 'table'],
      );
      await f.db.execute(
        'INSERT INTO crypto_business_records VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          f.partition,
          f.scope,
          'content',
          _wire,
          'table',
          2,
          0,
          'b' * 64,
          1,
          null,
          jsonEncode({'id': _table, 'deleted': true}),
          'verifiedCheckpoint',
          'crypto',
        ],
      );
      expect(await tables.cachedList(), isEmpty);
      await expectLater(
        tables.cachedRead(_table),
        throwsA(code('table_unavailable')),
      );
      expect(await (files as AttachmentLocalPreview).cachedList(), isEmpty);
      // Unknown/malformed cached capabilities stay on the loading/fresh path.
      await f.db.execute('UPDATE local_meta SET value=? WHERE name=?', [
        jsonEncode({'features': null}),
        'capabilities:${f.partition}',
      ]);
      f.server.supported = true;
      f.server.capabilityGate = Completer<void>();
      var opened = false;
      final cold = f.open().then((value) {
        opened = true;
        return value;
      });
      await _flush();
      expect(opened, isFalse);
      expect(f.server.caps, 2);
      f.server.capabilityGate!.complete();
      expect((await cold).spreadsheetsSupported, isTrue);
    },
  );

  test(
    'failed first capability preparation resets and explicit retry obtains a new attempt',
    () async {
      final f = await _fixture();
      final context = await f.open();
      f.server.capabilityFailure = const CollaborationApiException(
        'rate_limited',
        details: {'retryAfter': 1},
      );
      await expectLater(context.tables.list(), throwsA(code('rate_limited')));
      expect(f.server.caps, 1);
      expect(f.server.documentCalls, 0);
      expect(context.isCurrent, isTrue);
      expect(
        (await (context.tables as SpreadsheetLocalPreview).cachedRead(
          _table,
        ))!.lease,
        isNull,
      );
      f.clock.now = f.clock.now.add(const Duration(seconds: 2));
      f.server.capabilityFailure = null;
      expect(
        (await context.tables.list()).single.title,
        'Verified local table',
      );
      expect(f.server.caps, 2);
      expect(f.server.documentCalls, 1);
    },
  );

  test(
    'fresh preparation denial clears preview context while preserving a captured local draft',
    () async {
      final f = await _fixture();
      var denied = 0;
      final context = await f.open(denied: () => denied++);
      await context.tables.storeDraft(
        SpreadsheetDraft(
          tableId: _table,
          baseRevision: 1,
          title: 'Unsaved',
          cells: {'A1': 'draft'},
          updatedAt: 1,
        ),
      );
      expect(
        (await (context.tables as SpreadsheetLocalPreview).cachedList())!
            .length,
        1,
      );
      f.server.capabilityFailure = const CollaborationApiException(
        'device_revoked',
      );
      await expectLater(context.tables.list(), throwsA(code('device_revoked')));
      expect(denied, 1);
      expect(context.isCurrent, isFalse);
      expect(f.server.documentCalls, 0);
      await expectLater(
        (context.tables as SpreadsheetLocalPreview).cachedList(),
        throwsA(code('permission_revoked')),
      );
      expect(
        await f.db.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'document_cache:%'",
        ),
        isEmpty,
      );
      final drafts = await f.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['table_draft:${f.partition}:${f.scope}:$_table'],
      );
      expect(jsonDecode(drafts.single['value'] as String)['cells'], {
        'A1': 'draft',
      });
    },
  );
  test(
    'coordinator document read ignores only its own query projection',
    () async {
      final f = await _fixture();
      final context = await f.open();
      var listEvents = 0, detailEvents = 0;
      final list = context.tableChanges().listen((_) => listEvents++);
      final detail = context.tableChanges(_table).listen((_) => detailEvents++);
      addTearDown(list.cancel);
      addTearDown(detail.cancel);
      f.server.beforeDocument = (_) => f.db.transaction(() async {
        f.db.documentsChanged(f.partition, f.scope, type: 'table', id: _table);
      });
      await context.tables.list();
      await _flush();
      expect(listEvents, 0); // The list already receives this verified result.
      expect(detailEvents, 1); // The other reader still needs it.
      await context.tables.read(_table);
      await _flush();
      expect(listEvents, 1);
      expect(detailEvents, 1);
      expect(f.server.documentCalls, 2);
    },
  );

  test(
    'coordinator remote commit during a document read remains visible',
    () async {
      final f = await _fixture();
      final context = await f.open();
      final entered = Completer<void>(), release = Completer<void>();
      f.server.beforeDocument = (_) async {
        entered.complete();
        await release.future;
        await f.db.transaction(() async {
          f.db.documentsChanged(
            f.partition,
            f.scope,
            type: 'table',
            id: _table,
          );
        });
      };
      var events = 0;
      final sub = context.tableChanges(_table).listen((_) => events++);
      addTearDown(sub.cancel);
      final read = context.tables.read(_table);
      await entered.future;
      // An independent coordinator job, outside the reader's async zone.
      await f.db.transaction(() async {
        f.db.documentsChanged(f.partition, f.scope, type: 'table', id: _table);
      });
      await _flush();
      expect(events, 1);
      release.complete();
      await read;
      await _flush();
      expect(events, 1);
    },
  );

  test(
    'coordinator document targeting preserves drafts and access denial',
    () async {
      final f = await _fixture();
      final context = await f.open();
      final target = AttachmentTarget(
        scopeId: f.scope,
        targetType: 'table',
        targetId: _table,
      );
      var tables = 0, attachments = 0;
      final ts = context.tableChanges(_table).listen((_) => tables++);
      final ats = context
          .attachmentChanges(target)
          .listen((_) => attachments++);
      addTearDown(ts.cancel);
      addTearDown(ats.cancel);
      await context.tables.storeDraft(
        SpreadsheetDraft(
          tableId: _table,
          baseRevision: 1,
          title: 'Unsaved',
          cells: {'A1': 'draft'},
          updatedAt: 1,
        ),
      );
      await f.db.transaction(() async {
        f.db.documentsChanged(
          f.partition,
          f.scope,
          type: 'attachment',
          id: _file,
          targetType: 'table',
          targetId: 'other-table',
        );
        f.db.documentsChanged(
          f.partition,
          f.scope,
          type: 'table',
          id: 'other-table',
        );
      });
      await _flush();
      expect([tables, attachments], [0, 0]);
      f.db.documentsChanged(
        f.partition,
        f.scope,
        type: 'attachment',
        id: _file,
        targetType: 'table',
        targetId: _table,
      );
      await _flush();
      expect([tables, attachments], [0, 1]);
      f.server.capabilityFailure = const CollaborationApiException(
        'device_revoked',
      );
      await expectLater(context.tables.list(), throwsA(code('device_revoked')));
      f.db.documentsChanged(f.partition, f.scope, type: 'table', id: _table);
      await _flush();
      expect([tables, attachments], [0, 1]);
      expect(context.isCurrent, isFalse);
      final drafts = await f.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['table_draft:${f.partition}:${f.scope}:$_table'],
      );
      expect(jsonDecode(drafts.single['value'] as String)['cells'], {
        'A1': 'draft',
      });
    },
  );
}
