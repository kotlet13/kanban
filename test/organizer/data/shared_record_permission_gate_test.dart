import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore, code;
import 'collaboration_rich_planning_test.dart' show RichServer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CollaborationRepository repository;
  late CollaborationDatabase db;
  late RichServer server;
  late String scope, partition, actor, other;
  final now = DateTime.utc(2026, 10, 24);

  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    server = RichServer();
    repository = CollaborationRepository(
      db,
      FakeTransport(server),
      MemorySessionStore(),
      clock: () => now,
      contentRouteGuard: const SyntheticContentRouteGuard(),
    );
    await repository.initialize();
    await repository.login(
      serverUrl: 'https://synthetic.invalid/kanboard',
      username: 'alice',
      password: 'synthetic',
    );
    scope = await repository.createScope('Permission scope');
    partition = repository.state.session!.partition;
    actor = server.accountIds['alice']!;
    other = server.accountIds['bob']!;
  });
  tearDown(() => repository.close());

  Future<void> role(String value) async {
    final scopes = await db.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [partition, scope],
    );
    final data = jsonDecode(scopes.single['data'] as String) as Map;
    await db.execute('UPDATE scopes SET data=? WHERE partition=? AND id=?', [
      jsonEncode({...data, 'role': value, 'recordPolicyVersion': 1}),
      partition,
      scope,
    ]);
    await repository.refreshLocal();
  }

  Map<String, dynamic> payload(Map<String, Object?> value) =>
      Map<String, dynamic>.from(value)
        ..remove('id')
        ..remove('revision')
        ..remove('createdByAccountId')
        ..remove('updatedByAccountId');
  Future<void> accepted(
    String type,
    String id,
    Map<String, dynamic> data,
    String creator,
  ) async {
    final canonical = {
      'id': id,
      'type': type,
      'revision': 1,
      'deleted': false,
      'payload': data,
      'createdByAccountId': creator,
      'updatedByAccountId': creator,
    };
    await db.execute(
      'INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted,remote) VALUES(?,?,?,?,1,1,?,0,?)',
      [partition, scope, id, type, jsonEncode(data), jsonEncode(canonical)],
    );
    await repository.refreshLocal();
  }

  LocalTask task({required Iterable<String> assignees}) => LocalTask(
    id: newSharedId(),
    title: 'Accepted task',
    notes: 'Accepted note',
    projectId: null,
    dueAt: null,
    isCompleted: false,
    assigneeAccountIds: assignees,
    createdAt: now,
    updatedAt: now,
    revision: 1,
  );

  test(
    'viewer assigned by accepted predecessor can edit task but cannot delete or reassign',
    () async {
      final original = task(assignees: [actor]);
      await accepted('task', original.id, payload(original.toJson()), other);
      await role('viewer');
      final calls = server.calls.length;
      await repository.updateTask(scope, original.copyWith(notes: 'Own draft'));
      expect(
        repository.state.dataForScope(scope).tasks.single.notes,
        'Own draft',
      );
      expect(await db.rows('SELECT * FROM outbox'), hasLength(1));
      final draft = repository.state.dataForScope(scope).tasks.single;
      await expectLater(
        repository.updateTask(
          scope,
          draft.copyWith(assigneeAccountIds: [other]),
        ),
        throwsA(code('record_assignment_forbidden')),
      );
      await expectLater(
        repository.deleteTask(scope, original.id),
        throwsA(code('record_delete_forbidden')),
      );
      expect(await db.rows('SELECT * FROM outbox'), hasLength(1));
      expect(
        repository.state.scopes.singleWhere((s) => s.id == scope).canRead,
        true,
      );
      expect(
        server.calls.length,
        calls,
        reason: 'Local mutation and admission do not wait for HTTP',
      );
    },
  );

  test(
    'self assignment in submitted draft does not grant task editing authority',
    () async {
      final original = task(assignees: [other]);
      await accepted('task', original.id, payload(original.toJson()), other);
      await role('member');
      await expectLater(
        repository.updateTask(
          scope,
          original.copyWith(notes: 'Forged edit', assigneeAccountIds: [actor]),
        ),
        throwsA(code('record_edit_forbidden')),
      );
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
      expect(
        repository.state.dataForScope(scope).tasks.single.notes,
        'Accepted note',
      );
    },
  );

  test(
    'every reader checkbox command preserves all other shopping fields and cannot rename',
    () async {
      final list = LocalShoppingList(
        id: newSharedId(),
        title: 'List',
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );
      final item = LocalShoppingItem(
        id: newSharedId(),
        listId: list.id,
        title: 'Milk',
        quantity: '2',
        isChecked: false,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );
      await accepted('shoppingList', list.id, payload(list.toJson()), other);
      await accepted('shoppingItem', item.id, payload(item.toJson()), other);
      await role('viewer');
      await repository.setShoppingItemChecked(scope, item.id, true);
      final changed = repository.state.dataForScope(scope).shoppingItems.single;
      expect(changed.isChecked, true);
      expect(changed.title, 'Milk');
      expect(changed.quantity, '2');
      await expectLater(
        repository.updateShoppingItem(
          scope,
          changed.copyWith(title: 'Other product'),
        ),
        throwsA(code('record_edit_forbidden')),
      );
      expect(await db.rows('SELECT * FROM outbox'), hasLength(1));
    },
  );

  test(
    'author cannot cascade delete list containing another author record; entire transaction rolls back',
    () async {
      final list = LocalShoppingList(
        id: newSharedId(),
        title: 'Own list',
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );
      final own = LocalShoppingItem(
        id: newSharedId(),
        listId: list.id,
        title: 'Own',
        quantity: '1',
        isChecked: false,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );
      // A separate immutable identity represents the other member's entry.
      final otherItem = LocalShoppingItem(
        id: newSharedId(),
        listId: list.id,
        title: 'Other',
        quantity: '1',
        isChecked: false,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );
      await accepted('shoppingList', list.id, payload(list.toJson()), actor);
      await accepted('shoppingItem', own.id, payload(own.toJson()), actor);
      await accepted(
        'shoppingItem',
        otherItem.id,
        payload(otherItem.toJson()),
        other,
      );
      await role('member');
      await expectLater(
        repository.deleteShoppingList(scope, list.id),
        throwsA(code('record_delete_forbidden')),
      );
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
      expect(repository.state.dataForScope(scope).shoppingItems, hasLength(2));
      expect(repository.state.dataForScope(scope).shoppingLists, hasLength(1));
    },
  );
}
