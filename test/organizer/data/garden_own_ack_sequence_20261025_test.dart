import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/domain/garden_models.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Protected dispatch unexpected');
}

// This fixture exercises the real durable garden adapter and real push/ACK/pull
// transaction. Its in-memory legacy transport does not exercise encrypted proof
// verification; the production ACK condition must remain independent of it.
class _Transport extends FakeTransport {
  _Transport(super.server);
  void Function(Map<String, dynamic>)? alterNextAck;

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'scopes.members') {
      return {
        'members': [
          {
            'accountId': server.accountIds[server.tokens[token]],
            'userId': 1,
            'username': 'alice',
            'displayName': 'Alice',
            'role': 'owner',
            'active': true,
          },
        ],
      };
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation.replaceFirst('sync6.', 'sync.'),
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities') {
      return {
        ...result,
        'recordContractVersions': [1, 2, 3, 4, 5, 6],
        'features': {
          ...Map<String, dynamic>.from(result['features'] as Map),
          'gardens': true,
        },
      };
    }
    if (operation.endsWith('.push')) {
      final record = result['record'] as Map<String, dynamic>;
      record['createdByAccountId'] = server.accountIds[server.tokens[token]];
      record['updatedByAccountId'] = server.accountIds[server.tokens[token]];
      // Encrypted business serialization sorts keys; the candidate's original
      // insertion order cannot be part of the continuity condition.
      if (record['payload'] != null) {
        record['payload'] = jsonDecode(
          CryptoBusinessJson.canonical(record['payload']),
        );
      }
      final alter = alterNextAck;
      alterNextAck = null;
      alter?.call(record);
      server.records[params['scopeId']]![record['id']] = record;
    }
    return result;
  }
}

class _Fixture {
  final db = CollaborationDatabase(NativeDatabase.memory());
  final server = FakeServer();
  late final transport = _Transport(server);
  late final shared = CollaborationRepository(
    db,
    transport,
    MemorySessionStore(),
    ownsDatabase: false,
    contentRouteGuard: const SyntheticContentRouteGuard(),
    cryptoRouter: _LegacyRouter(),
  );
  late String scope;
  late GardenRepository gardens;
  late SharedGardenStorage storage;
  final now = DateTime.utc(2026, 10, 25, 10, 29, 28, 123, 456);

  Future<void> open() async {
    await shared.initialize();
    await shared.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    scope = await shared.createScope('Synthetic household');
    storage = SharedGardenStorage(
      shared,
      shared.state.session!.partition,
      scope,
    );
    gardens = GardenRepository(storage, clock: () => now);
    await gardens.initialize();
    await gardens.createGarden(
      name: 'Synthetic garden',
      widthMeters: 8,
      heightMeters: 10,
      areas: const [
        GardenArea(
          id: '11111111-1111-4111-8111-111111111111',
          label: 'Existing bed',
          x: .1,
          y: .1,
          width: .3,
          height: .3,
        ),
      ],
      seasons: [GardenSeason(year: 2026)],
      expectedWorkspaceKey: storage.workspaceKey,
    );
    await sync();
  }

  Future<void> sync() async {
    await shared.syncNow();
    expect(shared.state.lastError, isNull);
    expect(await db.rows('SELECT op_id FROM outbox'), isEmpty);
    await gardens.reload();
  }

  void publishRemote(Garden? garden) {
    final id = garden?.id ?? gardens.snapshot.gardens.single.id;
    final previous = server.records[scope]![id]!;
    server.records[scope]![id] = {
      ...previous,
      'revision': (previous['revision'] as int) + 1,
      'sequence': server.sequence[scope] = server.sequence[scope]! + 1,
      'deleted': garden == null,
      'payload': garden?.toJson(),
    };
  }

  Future<void> close() async {
    await gardens.close();
    await shared.close();
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('second season edit survives own first bed-save ACK', () async {
    final f = _Fixture();
    await f.open();
    addTearDown(f.close);
    final initial = f.gardens.snapshot.gardens.single;
    await f.gardens.updateGarden(
      initial.copyWith(areas: [initial.areas.single.copyWith(x: .2)]),
      expectedWorkspaceKey: f.storage.workspaceKey,
    );
    // The next editor opens immediately after Save, while autosync is pending.
    final secondEditorBase = f.gardens.snapshot.gardens.single;
    final candidatePayload = jsonEncode(secondEditorBase.toJson());
    await f.sync();
    final afterOwnAck = f.gardens.snapshot.gardens.single;
    expect(afterOwnAck.createdAt, secondEditorBase.createdAt);
    expect(afterOwnAck.areas.single.x, .2);
    // Expected to fail before the fix: only local_revision changes on own ACK.
    expect(
      afterOwnAck.revision,
      secondEditorBase.revision,
      reason: 'Identical own ACK must not invalidate the next editor',
    );
    expect(jsonEncode(afterOwnAck.toJson()), candidatePayload);
    await f.gardens.updateGarden(
      secondEditorBase.copyWith(
        seasons: [
          GardenSeason(
            year: 2026,
            plantings: [
              GardenPlanting(
                id: '22222222-2222-4222-8222-222222222222',
                areaId: initial.areas.single.id,
                crop: 'Carrot',
              ),
            ],
          ),
        ],
      ),
      expectedWorkspaceKey: f.storage.workspaceKey,
    );
    final saved = f.gardens.snapshot.gardens.single;
    expect(saved.areas.single.x, .2);
    expect(saved.seasons.single.plantings.single.crop, 'Carrot');
    expect(saved.createdAt, initial.createdAt);
    expect(saved.revision, secondEditorBase.revision + 1);
    await f.sync();
    expect(f.gardens.snapshot.gardens.single.toJson(), saved.toJson());
  });

  test(
    'a real newer garden from the same account still rejects stale season',
    () async {
      final f = _Fixture();
      await f.open();
      addTearDown(f.close);
      final opened = f.gardens.snapshot.gardens.single;
      f.publishRemote(opened.copyWith(notes: 'A real newer change'));
      await f.sync();
      final current = f.gardens.snapshot.gardens.single;
      expect(current.revision, opened.revision + 1);
      expect(current.notes, 'A real newer change');
      await expectLater(
        f.gardens.updateGarden(
          opened.copyWith(seasons: [GardenSeason(year: 2027)]),
          expectedWorkspaceKey: f.storage.workspaceKey,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(
        (await f.storage.read()).gardens.single.toJson(),
        current.toJson(),
      );
      expect(await f.db.rows('SELECT op_id FROM outbox'), isEmpty);
    },
  );

  test(
    'delete then exact-payload restore cannot revalidate the old garden editor',
    () async {
      final f = _Fixture();
      await f.open();
      addTearDown(f.close);
      final opened = f.gardens.snapshot.gardens.single;
      f.publishRemote(null);
      await f.sync();
      expect(f.gardens.snapshot.gardens, isEmpty);
      f.publishRemote(opened);
      await f.sync();
      final restored = f.gardens.snapshot.gardens.single;
      expect(restored.createdAt, opened.createdAt);
      expect(restored.revision, opened.revision + 2);
      await expectLater(
        f.gardens.updateGarden(
          opened.copyWith(notes: 'Stale editor after restore'),
          expectedWorkspaceKey: f.storage.workspaceKey,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(
        (await f.storage.read()).gardens.single.toJson(),
        restored.toJson(),
      );
      expect(await f.db.rows('SELECT op_id FROM outbox'), isEmpty);
    },
  );

  test(
    'an advanced canonical response cannot masquerade as this garden ACK',
    () async {
      final f = _Fixture();
      await f.open();
      addTearDown(f.close);
      final opened = f.gardens.snapshot.gardens.single;
      await f.gardens.updateGarden(
        opened.copyWith(notes: 'First saved change'),
      );
      final nextEditor = f.gardens.snapshot.gardens.single;
      f.transport.alterNextAck = (record) {
        record['revision'] = (record['revision'] as int) + 1;
        record['sequence'] = f.server.sequence[f.scope] =
            f.server.sequence[f.scope]! + 1;
      };
      await f.sync();
      final advanced = f.gardens.snapshot.gardens.single;
      expect(advanced.revision, nextEditor.revision + 1);
      await expectLater(
        f.gardens.updateGarden(nextEditor.copyWith(notes: 'Must stay a draft')),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(
        (await f.storage.read()).gardens.single.toJson(),
        advanced.toJson(),
      );
      expect(await f.db.rows('SELECT op_id FROM outbox'), isEmpty);
    },
  );
}
