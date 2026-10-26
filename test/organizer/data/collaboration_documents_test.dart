import '../support/synthetic_content_route_guard.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/attachment_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

class _DocumentsServer extends FakeServer {
  final sheets = <String, Map<String, dynamic>>{};
  final attachments = <String, Map<String, dynamic>>{};
  final bytes = <String, List<int>>{};
  final requests = <String, List<Map<String, Object?>>>{};
  bool supported = true, denied = false, corrupt = false, loseCreate = false;
  Future<void> Function(String)? beforeDocuments;
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (operation == 'capabilities') {
      final result = await super.call(operation, params, token);
      (result['features'] as Map).addAll(<String, bool>{
        'spreadsheets': supported,
        'attachments': supported,
      });
      return result;
    }
    if (!operation.startsWith('tables.') &&
        !operation.startsWith('attachments.')) {
      return super.call(operation, params, token);
    }
    requests.putIfAbsent(operation, () => []).add(Map.of(params));
    await beforeDocuments?.call(operation);
    if (denied) throw const CollaborationApiException('permission_revoked');
    final id = params['id'] as String?;
    if (operation == 'tables.list') return {'sheets': sheets.values.toList()};
    if (operation == 'tables.get') return {'sheet': sheets[id], 'lease': null};
    if (operation == 'tables.create') {
      final sheet = sheets.putIfAbsent(
        id!,
        () => {
          'id': id,
          'scopeId': params['scopeId'],
          'title': params['title'],
          'cells': <String, String>{},
          'revision': 1,
          'updatedAt': 1800000000,
        },
      );
      if (loseCreate) {
        loseCreate = false;
        throw const CollaborationException('network');
      }
      return {'sheet': sheet};
    }
    if (operation == 'tables.acquire' || operation == 'tables.renew') {
      return {
        'lease': {
          'token': 'a' * 64,
          'holderName': 'Alice',
          'holderAccountId': accountIds['alice'],
          'holderDeviceId': params['testDevice'] ?? 'device',
          'expiresAt': DateTime.utc(2099).millisecondsSinceEpoch ~/ 1000,
        },
      };
    }
    if (operation == 'tables.save') {
      final old = sheets[id]!;
      if (params['expectedRevision'] != old['revision']) {
        throw const CollaborationException('table_conflict');
      }
      sheets[id!] = {
        ...old,
        'title': params['title'],
        'cells': params['cells'],
        'revision': (old['revision'] as int) + 1,
      };
      return {'sheet': sheets[id]};
    }
    if (operation == 'tables.release') return {'released': true};
    if (operation == 'tables.delete') {
      sheets.remove(id);
      return {'deleted': true};
    }
    if (operation == 'attachments.list') {
      return {
        'attachments': attachments.values
            .where((m) => m['complete'] == true)
            .toList(),
      };
    }
    if (operation == 'attachments.begin') {
      attachments.putIfAbsent(
        id!,
        () => {
          ...params,
          'id': id,
          'createdAt': 1800000000,
          'complete': false,
          'offset': 0,
        },
      );
      bytes.putIfAbsent(id, () => []);
      return {'attachment': attachments[id]};
    }
    if (operation == 'attachments.chunk') {
      final data = base64Decode(params['dataBase64'] as String);
      final content = bytes[id]!;
      if (content.length == params['offset']) content.addAll(data);
      attachments[id]!['offset'] = content.length;
      return {'attachment': attachments[id]};
    }
    if (operation == 'attachments.complete') {
      attachments[id]!['complete'] = true;
      return {'attachment': attachments[id]};
    }
    if (operation == 'attachments.get') {
      final offset = params['offset'] as int, content = bytes[id]!;
      final end = (offset + (params['limit'] as int)).clamp(0, content.length);
      return {
        'attachment': attachments[id],
        'offset': offset,
        'total': content.length,
        'done': end == content.length,
        'dataBase64': base64Encode(
          corrupt ? List.filled(end - offset, 0) : content.sublist(offset, end),
        ),
      };
    }
    if (operation == 'attachments.delete') {
      attachments.remove(id);
      bytes.remove(id);
      return {'deleted': true};
    }
    throw StateError(operation);
  }
}

// Measures the real repository chunk loop, with a synthetic legacy transport.
// This is not a cryptographic authority or HTTP-count fixture.
class _DownloadContext
    implements CryptoDomainRouter, CryptoDocumentDownloadContext {
  int starts = 0, finishes = 0, chunks = 0;
  Map<String, Object?>? identity;
  bool active = false;
  @override
  Future<T> withDocumentDownload<T>({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> identity,
    required Future<T> Function() read,
  }) async {
    expect(operation, 'attachments.get');
    expect(active, false);
    starts++;
    this.identity = Map.of(identity);
    active = true;
    try {
      return await read();
    } finally {
      active = false;
      finishes++;
    }
  }

  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) => throw StateError('Legacy fixture only');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late _DocumentsServer server;
  late FakeTransport transport;
  late CollaborationDatabase database;
  late CollaborationRepository repository;
  late SharedDocumentsContext context;
  late String scopeId;
  late _DownloadContext downloadContext;
  setUp(() async {
    server = _DocumentsServer();
    downloadContext = _DownloadContext();
    transport = FakeTransport(server);
    database = CollaborationDatabase(NativeDatabase.memory());
    repository = CollaborationRepository(
      database,
      transport,
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: downloadContext,
    );
    await repository.initialize();
    await repository.login(
      serverUrl: 'https://synthetic.invalid',
      username: 'alice',
      password: 'synthetic',
    );
    scopeId = await repository.createScope('Documents');
    server.scopes[scopeId]!['kind'] = 'organization';
    await repository.syncNow();
    context = await repository.openDocuments(scopeId);
  });
  tearDown(() async => repository.close());
  AttachmentGateway files() => context.attachments(
    AttachmentTarget(scopeId: scopeId, targetType: 'scope', targetId: scopeId),
  );
  Uint8List fileBytes() =>
      Uint8List.fromList(utf8.encode('%PDF-1.7\n${'document data\n' * 30000}'));

  for (final size in [1024, attachmentChunkBytes]) {
    test('P2 single chunk skips combined preparation: $size bytes', () async {
      final gateway = files();
      final bytes = Uint8List.fromList(
        utf8.encode('%PDF-1.7\n${'x' * (size - 9)}'),
      );
      expect(bytes.length, size);
      await gateway.upload(
        name: 'small.pdf',
        mime: 'application/pdf',
        bytes: bytes,
      );
      final metadata = (await gateway.list()).single;
      expect(await gateway.download(metadata), bytes);
      expect(downloadContext.starts, 0);
      expect(server.requests['attachments.get']!.length, 1);
    });
  }
  for (final outcome in ['complete', 'corrupt', 'logout']) {
    test('P2 one bounded download context per file: $outcome', () async {
      final gateway = files(), bytes = fileBytes();
      await gateway.upload(
        name: 'download.pdf',
        mime: 'application/pdf',
        bytes: bytes,
      );
      final metadata = (await gateway.list()).single;
      server.beforeDocuments = (op) async {
        if (op != 'attachments.get') return;
        expect(downloadContext.active, true);
        final query = Map<String, Object?>.of(server.requests[op]!.last)
          ..remove('offset')
          ..remove('limit');
        expect(query, downloadContext.identity);
        downloadContext.chunks++;
        if (outcome == 'logout' && downloadContext.chunks == 2) {
          await repository.signOut();
        }
      };
      server.corrupt = outcome == 'corrupt';
      if (outcome == 'complete') {
        expect(await gateway.download(metadata), bytes);
      } else {
        await expectLater(
          gateway.download(metadata),
          throwsA(isA<CollaborationException>()),
        );
      }
      expect(downloadContext.starts, 1);
      expect(downloadContext.finishes, 1);
      expect(downloadContext.active, false);
      expect(downloadContext.chunks, greaterThan(1));
    });
  }

  test(
    'new tables persist raw formulas, conflict revisions and local drafts',
    () async {
      final gateway = context.tables;
      final doc = await gateway.create('Equipment');
      final saved = await gateway.save(
        doc.id,
        'a' * 64,
        doc.revision,
        'Equipment',
        {'A1': '3', 'B1': '=A1*2'},
      );
      expect(saved.revision, 2);
      expect((await gateway.read(doc.id)).document.cells['B1'], '=A1*2');
      await expectLater(
        gateway.save(doc.id, 'a' * 64, 1, 'Old', {}),
        throwsA(code('table_conflict')),
      );
      await gateway.storeDraft(
        SpreadsheetDraft(
          tableId: doc.id,
          baseRevision: 2,
          title: 'Draft',
          cells: {'A1': '4'},
          updatedAt: 1800000000,
        ),
      );
      expect((await gateway.loadDraft(doc.id))!.cells, {'A1': '4'});
      await gateway.clearDraft(doc.id);
      expect(await gateway.loadDraft(doc.id), isNull);
    },
  );
  test(
    'lost create reply retries the same durable request and object id',
    () async {
      server.loseCreate = true;
      await expectLater(
        context.tables.create('Retry'),
        throwsA(code('network')),
      );
      final second = await context.tables.create('Retry');
      final calls = server.requests['tables.create']!;
      expect(calls[0]['id'], calls[1]['id']);
      expect(calls[0]['requestId'], calls[1]['requestId']);
      expect(server.sheets.length, 1);
      expect(second.title, 'Retry');
    },
  );
  test(
    'offline cached reads survive context reopen, but edits stay online',
    () async {
      final doc = await context.tables.create('Offline');
      await context.tables.list();
      await context.tables.read(doc.id);
      transport.offline = true;
      final reopened = await repository.openDocuments(scopeId);
      expect(reopened.online, isFalse);
      expect((await reopened.tables.read(doc.id)).document.title, 'Offline');
      expect((await reopened.tables.list()).single.id, doc.id);
      await expectLater(
        reopened.tables.acquire(doc.id),
        throwsA(code('network')),
      );
    },
  );
  test(
    'permission rejection purges cached document data without losing drafts',
    () async {
      final doc = await context.tables.create('Shared');
      await context.tables.storeDraft(
        SpreadsheetDraft(
          tableId: doc.id,
          baseRevision: 1,
          title: 'Own work',
          cells: {'A1': 'draft'},
          updatedAt: 1,
        ),
      );
      server.denied = true;
      await expectLater(
        context.tables.read(doc.id),
        throwsA(code('permission_revoked')),
      );
      transport.offline = true;
      await expectLater(
        context.tables.read(doc.id),
        throwsA(code('permission_revoked')),
      );
      final cached = await database.rows(
        "SELECT name FROM local_meta WHERE name LIKE 'document_cache:%'",
      );
      expect(cached, isEmpty);
      expect(
        await database.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'table_draft:%'",
        ),
        hasLength(1),
      );
    },
  );
  test(
    'late old-account response never enters cache or the next account',
    () async {
      final doc = await context.tables.create('Alice');
      final entered = Completer<void>(), resume = Completer<void>();
      server.beforeDocuments = (op) async {
        if (op == 'tables.get') {
          entered.complete();
          await resume.future;
        }
      };
      final pending = context.tables.read(doc.id);
      final assertion = expectLater(pending, throwsA(code('session_changed')));
      await entered.future;
      await repository.signOut();
      resume.complete();
      await assertion;
      expect(context.isCurrent, isFalse);
    },
  );
  test(
    'unsupported capabilities stop requests with a clear upgrade error',
    () async {
      server.supported = false;
      final old = await repository.openDocuments(scopeId);
      expect(old.spreadsheetsSupported, isFalse);
      await expectLater(
        old.tables.list(),
        throwsA(code('documents_upgrade_required')),
      );
      expect(server.requests['tables.list'], isNull);
    },
  );
  test(
    'chunk upload/download verifies hash and uses independent request receipts',
    () async {
      final gateway = files(), bytes = fileBytes();
      final progress = <double>[];
      await gateway.upload(
        name: 'manual.pdf',
        mime: 'application/pdf',
        bytes: bytes,
        onProgress: progress.add,
      );
      final metadata = (await gateway.list()).single;
      expect(progress.last, 1);
      expect(server.requests['attachments.chunk']!.length, greaterThan(1));
      expect(
        server.requests['attachments.begin']!.single['requestId'],
        isNot(server.requests['attachments.complete']!.single['requestId']),
      );
      expect(await gateway.download(metadata), bytes);
      final hash = await Sha256().hash(bytes);
      expect(
        metadata.sha256,
        hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      );
      transport.offline = true;
      final offline = files();
      expect(await offline.download(metadata), bytes);
    },
  );
  test('corrupt bytes and mismatched target never export data', () async {
    final gateway = files();
    await gateway.upload(
      name: 'manual.pdf',
      mime: 'application/pdf',
      bytes: fileBytes(),
    );
    final metadata = (await gateway.list()).single;
    server.corrupt = true;
    await expectLater(
      gateway.download(metadata),
      throwsA(code('invalid_response')),
    );
    final wrong = context.attachments(
      AttachmentTarget(
        scopeId: scopeId,
        targetType: 'table',
        targetId: newSharedId(),
      ),
    );
    await expectLater(
      wrong.download(metadata),
      throwsA(code('permission_revoked')),
    );
  });
  test('late attachment download after logout yields no bytes', () async {
    final gateway = files();
    await gateway.upload(
      name: 'manual.pdf',
      mime: 'application/pdf',
      bytes: fileBytes(),
    );
    final metadata = (await gateway.list()).single;
    final entered = Completer<void>(), resume = Completer<void>();
    server.beforeDocuments = (op) async {
      if (op == 'attachments.get') {
        entered.complete();
        await resume.future;
      }
    };
    final pending = gateway.download(metadata);
    final assertion = expectLater(pending, throwsA(code('session_changed')));
    await entered.future;
    await repository.signOut();
    resume.complete();
    await assertion;
    expect(gateway.isCurrent, isFalse);
  });
  test(
    'deleted attachment purges bytes and repeat mutations have distinct ids',
    () async {
      final gateway = files();
      await gateway.upload(
        name: 'manual.pdf',
        mime: 'application/pdf',
        bytes: fileBytes(),
      );
      final metadata = (await gateway.list()).single;
      await gateway.delete(metadata);
      expect(await gateway.list(), isEmpty);
      expect(gateway.localBytes(metadata), isNull);
      expect(
        await database.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'document_cache:%:file:%'",
        ),
        isEmpty,
      );
    },
  );
  test(
    'offline reopened list exposes only verified persisted file bytes',
    () async {
      final gateway = files();
      final original = fileBytes();
      await gateway.upload(
        name: 'cached.pdf',
        mime: 'application/pdf',
        bytes: original,
      );
      final file = (await gateway.list()).single;
      transport.offline = true;
      final reopened = await repository.openDocuments(scopeId);
      final offline = reopened.attachments(file.target);
      expect(offline.localBytes(file), isNull);
      expect((await offline.list()).single.id, file.id);
      expect(offline.localBytes(file), original);
    },
  );
  test(
    'late older read returns the highest acknowledged local revision',
    () async {
      final table = await context.tables.create('Current');
      final old = Map<String, dynamic>.from(server.sheets[table.id]!);
      final entered = Completer<void>(), resume = Completer<void>();
      var held = false;
      server.beforeDocuments = (operation) async {
        if (operation == 'tables.get' && !held) {
          held = true;
          entered.complete();
          await resume.future;
        }
      };
      final pending = context.tables.read(table.id);
      await entered.future;
      await context.tables.save(table.id, 'a' * 64, 1, 'New title', {
        'A1': 'Latest',
      });
      server.sheets[table.id] = old;
      resume.complete();
      final visible = await pending;
      expect(visible.document.revision, 2);
      expect(visible.document.cells['A1'], 'Latest');
    },
  );
  test(
    'known deletion cannot reappear in an offline cached table list',
    () async {
      final table = await context.tables.create('Delete');
      await context.tables.list();
      await context.tables.delete(table.id, 'a' * 64, 1);
      transport.offline = true;
      expect(await context.tables.list(), isEmpty);
    },
  );
  test('request receipts are device-bound after account relogin', () async {
    server.loseCreate = true;
    await expectLater(context.tables.create('Retry'), throwsA(code('network')));
    final first = server.requests['tables.create']!.single['requestId'];
    await repository.signOut();
    await repository.login(
      serverUrl: 'https://synthetic.invalid',
      username: 'alice',
      password: 'synthetic',
    );
    await repository.syncNow();
    final reopened = await repository.openDocuments(scopeId);
    await reopened.tables.create('Retry');
    expect(server.requests['tables.create']!.last['requestId'], isNot(first));
  });
  test(
    'queued old-partition draft survives logout without new-account access',
    () async {
      final table = await context.tables.create('Own draft');
      final gateway = context.tables, partition = context.partition;
      await repository.signOut();
      await gateway.storeDraft(
        SpreadsheetDraft(
          tableId: table.id,
          baseRevision: 1,
          title: 'Keystroke',
          cells: {'A1': 'Last input'},
          updatedAt: 1,
        ),
      );
      final rows = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['table_draft:$partition:$scopeId:${table.id}'],
      );
      expect(jsonDecode(rows.single['value'] as String)['cells'], {
        'A1': 'Last input',
      });
      await expectLater(
        gateway.loadDraft(table.id),
        throwsA(code('session_changed')),
      );
    },
  );
  test(
    'confirmed account deletion rejects even queued local draft writes',
    () async {
      final doc = await context.tables.create('Delete account');
      final gateway = context.tables;
      await database.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'deleted_account:${context.partition}',
        '1',
      ]);
      await expectLater(
        gateway.storeDraft(
          SpreadsheetDraft(
            tableId: doc.id,
            baseRevision: 1,
            title: 'Late',
            cells: {'A1': 'must not return'},
            updatedAt: 1,
          ),
        ),
        throwsA(code('account_deleted')),
      );
      expect(
        await database.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'table_draft:%'",
        ),
        isEmpty,
      );
    },
  );
}
