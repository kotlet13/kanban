import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'scheduled_reminder_repository_test.dart'
    show ReminderTransport, now, later;

// Synthetic metadata service only. Production repository, capability handling,
// SQL queue, model and acknowledgement checks remain real. Delivery/fanout is
// covered separately by the multi-account HTTP fixture, not by this transport.
class _Transport extends ReminderTransport {
  _Transport() : super(FakeServer());
  bool recipientsSupported = true, omitReplyPolicy = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities') {
      return {
        ...reply,
        'features': <String, dynamic>{
          ...Map<String, dynamic>.from(reply['features'] as Map),
          'taskReminderRecipients': recipientsSupported,
        },
      };
    }
    if (operation == 'reminders.put' && params['recipientPolicy'] != null) {
      final item = Map<String, dynamic>.from(reply['reminder'] as Map)
        ..['recipientPolicy'] = params['recipientPolicy'];
      reminders[params['id'] as String] = item;
      replay[params['requestId'] as String] = {'reminder': item};
      return {
        'reminder': {
          ...item,
        }..removeWhere((key, _) => omitReplyPolicy && key == 'recipientPolicy'),
      };
    }
    return reply;
  }
}

// Explicit metadata acquisition seam, matching the synthetic legacy transport.
// Merely permitting legacy content does not replace the production E2EE account
// readiness guard. Real signed reminder parsing has its separate test file.
class _MetadataRouter implements CryptoDomainRouter {
  _MetadataRouter(this.transport);
  final _Transport transport;
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) => transport.call(
    serverUrl: session.profile.serverUrl,
    operation: operation,
    params: params,
    token: session.token,
    allowLocalHttp: session.profile.allowLocalHttp,
  );
}

Future<
  ({
    CollaborationRepository repo,
    _Transport transport,
    String scope,
    String task,
  })
>
_fixture({bool supported = true}) async {
  final transport = _Transport()..recipientsSupported = supported;
  final repo = CollaborationRepository(
    CollaborationDatabase(NativeDatabase.memory()),
    transport,
    MemorySessionStore(),
    clock: () => now,
    contentRouteGuard: const SyntheticContentRouteGuard(),
    cryptoRouter: _MetadataRouter(transport),
  );
  addTearDown(repo.close);
  await repo.initialize();
  await repo.login(
    serverUrl: 'https://example.test/',
    username: 'alice',
    password: 'synthetic',
  );
  final scope = await repo.createScope('Recipient policy');
  final task = await repo.createTask(
    scopeId: scope,
    title: 'Task',
    dueAt: later,
  );
  await repo.syncNow();
  return (repo: repo, transport: transport, scope: scope, task: task);
}

Matcher _code(String value) =>
    isA<CollaborationException>().having((e) => e.code, 'code', value);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'new capability never expands an already queued scheduler-only intent',
    () async {
      final f = await _fixture(supported: false);
      final oldId = await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later,
      );
      final oldBytes = (await f.repo.database.rows(
        'SELECT params FROM commands WHERE entity_key=?',
        ['reminder:$oldId'],
      )).single['params'];
      expect(
        (jsonDecode(oldBytes as String) as Map).containsKey('recipientPolicy'),
        isFalse,
      );
      f.transport.recipientsSupported = true;
      f.transport.beforeCommands = () async {
        f.transport.beforeCommands = null;
        expect(
          (await f.repo.database.rows(
            'SELECT params FROM commands WHERE entity_key=?',
            ['reminder:$oldId'],
          )).single['params'],
          oldBytes,
        );
      };
      await f.repo.syncNow();
      f.transport.beforeCommands = null;
      expect(f.repo.state.taskReminderRecipientsSupported, isTrue);
      expect(
        f.transport.calls.single.params.containsKey('recipientPolicy'),
        isFalse,
      );

      final newId = await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later.add(const Duration(hours: 1)),
        recipientPolicy: taskReminderRecipientPolicy,
      );
      expect(
        f.repo.state.scheduledReminders
            .singleWhere((r) => r.id == newId)
            .recipientPolicy,
        taskReminderRecipientPolicy,
      );
      final command =
          jsonDecode(
                (await f.repo.database.rows(
                      'SELECT params FROM commands WHERE entity_key=?',
                      ['reminder:$newId'],
                    )).single['params']
                    as String,
              )
              as Map;
      expect(command['recipientPolicy'], taskReminderRecipientPolicy);
      await f.repo.syncNow();
      expect(
        f.transport.calls.last.params['recipientPolicy'],
        taskReminderRecipientPolicy,
      );
      expect(
        f.repo.state.scheduledReminders
            .singleWhere((r) => r.id == newId)
            .syncState,
        'synced',
      );
    },
  );

  test(
    'unsupported or invalid audience is refused before a durable queue row',
    () async {
      final f = await _fixture(supported: false);
      await expectLater(
        f.repo.putReminder(
          scopeId: f.scope,
          targetType: 'task',
          targetId: f.task,
          remindAt: later,
          recipientPolicy: taskReminderRecipientPolicy,
        ),
        throwsA(_code('client_upgrade_required')),
      );
      await expectLater(
        f.repo.putReminder(
          scopeId: f.scope,
          targetType: 'event',
          targetId: f.task,
          remindAt: later,
          recipientPolicy: taskReminderRecipientPolicy,
        ),
        throwsA(_code('validation_error')),
      );
      await expectLater(
        f.repo.putReminder(
          scopeId: f.scope,
          targetType: 'task',
          targetId: f.task,
          remindAt: later,
          recipientPolicy: 'everyone',
        ),
        throwsA(_code('validation_error')),
      );
      expect(await f.repo.database.rows('SELECT id FROM commands'), isEmpty);
      expect(f.repo.state.scheduledReminders, isEmpty);
    },
  );

  test(
    'capability loss retains exact new consent and never sends a downgraded put',
    () async {
      final f = await _fixture();
      final id = await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later,
        recipientPolicy: taskReminderRecipientPolicy,
      );
      final before = (await f.repo.database.rows(
        'SELECT params FROM commands WHERE entity_key=?',
        ['reminder:$id'],
      )).single['params'];
      f.transport.recipientsSupported = false;
      await f.repo.syncNow();
      expect(f.repo.state.lastError, _code('client_upgrade_required'));
      expect(f.transport.calls, isEmpty);
      expect(
        (await f.repo.database.rows(
          'SELECT params,state FROM commands WHERE entity_key=?',
          ['reminder:$id'],
        )).single,
        {'params': before, 'state': 'pending'},
      );
      expect(
        f.repo.state.scheduledReminders.single.recipientPolicy,
        taskReminderRecipientPolicy,
      );
    },
  );

  test(
    'omitted acknowledged audience cannot consume the queued explicit intent',
    () async {
      final f = await _fixture();
      await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later,
        recipientPolicy: taskReminderRecipientPolicy,
      );
      f.transport.omitReplyPolicy = true;
      await f.repo.syncNow();
      expect(f.repo.state.lastError, _code('invalid_response'));
      expect(
        await f.repo.database.rows('SELECT id FROM commands'),
        hasLength(1),
      );
      expect(f.repo.state.scheduledReminders.single.syncState, 'queued');
    },
  );

  test(
    'owner cancel retains original audience without adding policy to cancel command',
    () async {
      final f = await _fixture();
      await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later,
        recipientPolicy: taskReminderRecipientPolicy,
      );
      await f.repo.syncNow();
      await f.repo.cancelReminder(f.repo.state.scheduledReminders.single);
      await f.repo.syncNow();
      expect(f.transport.calls.last.operation, 'reminders.cancel');
      expect(
        f.transport.calls.last.params.containsKey('recipientPolicy'),
        isFalse,
      );
      expect(f.repo.state.scheduledReminders.single.state, 'cancelled');
      expect(
        f.repo.state.scheduledReminders.single.recipientPolicy,
        taskReminderRecipientPolicy,
      );
    },
  );

  test(
    'model preserves explicit audience and rejects ambiguous or non-task policy',
    () {
      final original = SharedScheduledReminder(
        id: newSharedId(),
        scopeId: newSharedId(),
        targetId: newSharedId(),
        targetType: 'task',
        remindAt: later,
        revision: 1,
        state: 'pending',
        recipientPolicy: taskReminderRecipientPolicy,
      ).toJson();
      expect(
        SharedScheduledReminder.fromJson(Map.from(original)).recipientPolicy,
        taskReminderRecipientPolicy,
      );
      expect(
        SharedScheduledReminder.fromJson(
          Map.from(original)..remove('recipientPolicy'),
        ).toJson().containsKey('recipientPolicy'),
        isFalse,
      );
      for (final replacement in [
        {'recipientPolicy': null},
        {'recipientPolicy': 'everyone'},
        {'targetType': 'event'},
      ]) {
        expect(
          () => SharedScheduledReminder.fromJson({...original, ...replacement}),
          throwsFormatException,
        );
      }
    },
  );
}
