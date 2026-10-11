import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../data/collaboration_repository_test.dart'
    show FakeServer, MemorySessionStore;
import '../data/private_sync_test_support.dart' show PersonalTransport;

// This fixture explicitly uses its loopback server rather than Flutter's
// default widget-test HTTP400 stub. No global HTTP override is changed.
class LoopbackClientFactory extends HttpOverrides {}

class OutageFixture {
  late HttpServer server;
  late CollaborationRepository repository;
  late ProviderContainer container;
  late CollaborationController controller;
  late String scope, account, originalTask;
  String mode = 'online';
  String denial = 'finance_forbidden';
  final backend = PersonalTransport(FakeServer());

  Future<void> initialize() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      final operation = body['op'] as String;
      if (mode != 'online') {
        request.response.statusCode = mode == 'plain403' ? 403 : 503;
        if (mode == 'typed' && operation == 'finance.policy') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'v': 1,
              'error': {'code': denial},
            }),
          );
        } else {
          request.response.headers.contentType = ContentType.text;
          request.response.write('Test2 setup is closed.');
        }
      } else {
        request.response.headers.contentType = ContentType.json;
        try {
          final authorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          final data = await backend.call(
            serverUrl: 'https://synthetic.invalid',
            operation: operation,
            params: Map<String, Object?>.from(body['params'] as Map),
            token: authorization?.replaceFirst('Bearer ', ''),
          );
          request.response.write(jsonEncode({'v': 1, 'data': data}));
        } on CollaborationException catch (error) {
          request.response.statusCode = 400;
          request.response.write(
            jsonEncode({
              'v': 1,
              'error': {'code': error.code},
            }),
          );
        }
      }
      await request.response.close();
    });
    repository = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      HttpCollaborationTransport(
        client: IOClient(LoopbackClientFactory().createHttpClient(null)),
      ),
      MemorySessionStore(),
    );
    await repository.initialize();
    await repository.login(
      serverUrl: 'http://127.0.0.1:${server.port}/isolated-test2/',
      username: 'alice',
      password: 'synthetic-password',
      allowLocalHttp: true,
    );
    scope = await repository.createScope('Synthetic outage household');
    await repository.syncNow();
    account = await repository.createFinanceAccount(
      scopeId: scope,
      name: 'Synthetic cached EUR account',
      currency: 'EUR',
      openingBalanceMinor: 10000,
    );
    originalTask = await repository.createTask(
      scopeId: scope,
      title: 'Original downloaded task',
    );
    await repository.syncNow();
    expect(repository.state.lastError, isNull);
    expect(repository.state.financePolicyForScope(scope).canRead, true);
    container = ProviderContainer(
      overrides: [
        collaborationRepositoryProvider.overrideWith((ref) async => repository),
      ],
    );
    container.listen(collaborationProvider, (_, _) {});
    await container.read(collaborationProvider.future);
    controller = container.read(collaborationProvider.notifier);
  }

  Future<void> queueOfflineWork() async {
    mode = 'plain503';
    await controller.createTask(scopeId: scope, title: 'New offline task');
    await controller.updateTask(
      scope,
      repository.state
          .dataForScope(scope)
          .tasks
          .firstWhere((t) => t.id == originalTask)
          .copyWith(title: 'Edited offline task'),
    );
    await controller.createFinanceEntry(
      scopeId: scope,
      accountId: account,
      kind: FinanceEntryKind.expense,
      amountMinor: 700,
      currency: 'EUR',
      title: 'Offline expense seven EUR',
      occurredAt: DateTime.now().toUtc(),
    );
  }

  Future<Map<String, dynamic>> export() async =>
      jsonDecode(await controller.exportUnsentWork()) as Map<String, dynamic>;

  Future<void> close() async {
    container.dispose();
    await repository.close();
    await server.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'real HTTP503 controller exports queued tasks and cached-authorized finance unchanged',
    () async {
      final f = OutageFixture();
      await f.initialize();
      addTearDown(f.close);
      await f.queueOfflineWork();
      final db = f.repository.database;
      final before = await db.rows(
        'SELECT op_id,request FROM outbox ORDER BY sequence',
      );
      final financeBefore = await db.rows(
        'SELECT op_id,request FROM finance_outbox ORDER BY sequence',
      );
      expect(before, hasLength(2));
      expect(financeBefore, hasLength(1));
      final doc = await f.export();
      expect(doc['format'], 'vsakdan-unsent-work');
      expect(doc['operations'], hasLength(2));
      expect(doc['financeOperations'], hasLength(1));
      expect(
        doc['financeOperations'][0]['operation']['payload']['amountMinor'],
        700,
      );
      expect(
        doc['operations'].map((row) => row['operation']['payload']['title']),
        containsAll(['New offline task', 'Edited offline task']),
      );
      expect(
        await db.rows('SELECT op_id,request FROM outbox ORDER BY sequence'),
        before,
      );
      expect(
        await db.rows(
          'SELECT op_id,request FROM finance_outbox ORDER BY sequence',
        ),
        financeBefore,
      );
      expect(f.repository.state.financePolicyForScope(f.scope).canRead, true);
    },
  );

  for (final denial in ['finance_forbidden', 'permission_revoked']) {
    test(
      'typed $denial atHTTP503 suppresses finance and remains denied during later outage',
      () async {
        final f = OutageFixture();
        await f.initialize();
        addTearDown(f.close);
        await f.queueOfflineWork();
        f.mode = 'typed';
        f.denial = denial;
        final doc = await f.export();
        expect(doc['operations'], hasLength(2));
        expect(doc['financeOperations'], isEmpty);
        expect(
          f.repository.state.financePolicyForScope(f.scope).canRead,
          false,
        );
        expect(
          f.repository.state.dataForScope(f.scope).financeEntries,
          isEmpty,
        );
        f.mode = 'plain503';
        expect((await f.export())['financeOperations'], isEmpty);
        expect(
          await f.repository.database.rows('SELECT op_id FROM finance_outbox'),
          hasLength(1),
        );
      },
    );
  }

  for (final failure in ['plain403', 'server_identity_changed']) {
    test('export does not fall back after $failure', () async {
      final f = OutageFixture();
      await f.initialize();
      addTearDown(f.close);
      await f.queueOfflineWork();
      f.mode = failure == 'plain403' ? 'plain403' : 'typed';
      f.denial = failure;
      await expectLater(
        f.export(),
        throwsA(
          isA<CollaborationException>().having(
            (error) => error.code,
            'code',
            failure == 'plain403' ? 'invalid_response' : failure,
          ),
        ),
      );
    });
  }
}
