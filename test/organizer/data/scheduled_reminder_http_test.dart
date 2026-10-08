// Opt-in synthetic loopback only; fixture credentials and bodies are never logged.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';

import 'collaboration_repository_test.dart' show MemorySessionStore;
import 'family_upgrade_http_test.dart' show ControlledHttp;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final fixturePath = Platform.environment['KANBAN_REMINDER_HTTP_FIXTURE'];
  test(
    'real HTTP reminders: durable offline put, lost ACK, two-device conflict, edit, cancel and target reschedule',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString())
              as Map<String, dynamic>;
      final url = fixture['server'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Fresh synthetic loopback fixture required');
      }
      final owner = fixture['owner'] as Map<String, dynamic>;
      final directory = await Directory.systemTemp.createTemp('reminder-http-');
      final repositories = <CollaborationRepository>[];
      Future<CollaborationRepository> open(
        String name,
        ControlledHttp transport,
        MemorySessionStore store,
      ) async {
        final repo = CollaborationRepository(
          CollaborationDatabase(
            NativeDatabase(File('${directory.path}/$name.sqlite')),
          ),
          transport,
          store,
        );
        repositories.add(repo);
        await repo.initialize();
        return repo;
      }

      Future<void> login(CollaborationRepository repo) => repo.login(
        serverUrl: url,
        username: owner['username'] as String,
        password: owner['password'] as String,
        allowLocalHttp: true,
      );
      Future<void> synced(CollaborationRepository repo) async {
        await repo.syncNow();
        expect(
          repo.state.lastError,
          isNull,
          reason: 'Synthetic HTTP sync must finish before inspecting data',
        );
      }

      try {
        var transport = ControlledHttp();
        final store = MemorySessionStore();
        var a = await open('a', transport, store);
        await login(a);
        final scope = await a.createScope(
          'Synthetic reminders ${newSharedId()}',
        );
        final date = DateTime.now().toUtc().add(const Duration(days: 1));
        final task = await a.createTask(
          scopeId: scope,
          title: 'Synthetic reminder target',
          dueAt: date.add(const Duration(hours: 4)),
        );
        await synced(a);
        final b = await open('b', ControlledHttp(), MemorySessionStore());
        await login(b);
        await synced(b);
        transport.offline = true;
        final id = await a.putReminder(
          scopeId: scope,
          targetType: 'task',
          targetId: task,
          remindAt: date,
          expectedPartition: a.state.session!.partition,
        );
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).syncState,
          'queued',
        );
        await a.close();
        repositories.remove(a);
        transport = ControlledHttp()..loseReply = 'reminders.put';
        a = await open('a', transport, store);
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).syncState,
          'queued',
        );
        await a.syncNow();
        expect(a.state.lastError?.code, 'network');
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).syncState,
          'queued',
        );
        await synced(a);
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).revision,
          1,
        );
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).syncState,
          'synced',
        );
        expect(await a.database.rows('SELECT * FROM commands'), isEmpty);
        await synced(b);
        expect(
          b.state.scheduledReminders.singleWhere((r) => r.id == id).revision,
          1,
        );
        await a.putReminder(
          id: id,
          scopeId: scope,
          targetType: 'task',
          targetId: task,
          remindAt: date.add(const Duration(hours: 1)),
          expectedRevision: 1,
        );
        await synced(a);
        await b.putReminder(
          id: id,
          scopeId: scope,
          targetType: 'task',
          targetId: task,
          remindAt: date.add(const Duration(hours: 2)),
          expectedRevision: 1,
        );
        await b.syncNow();
        expect(
          b.state.scheduledReminders.singleWhere((r) => r.id == id).syncState,
          'blocked',
        );
        expect(
          b.state.scheduledReminders.singleWhere((r) => r.id == id).syncError,
          'reminder_conflict',
        );
        final draft = b.state.scheduledReminders.singleWhere((r) => r.id == id);
        await b.putReminder(
          id: id,
          scopeId: scope,
          targetType: 'task',
          targetId: task,
          remindAt: draft.remindAt,
          expectedRevision: draft.revision,
        );
        await synced(b);
        expect(
          b.state.scheduledReminders.singleWhere((r) => r.id == id).revision,
          3,
        );
        await synced(a);
        transport.offline = true;
        await a.cancelReminder(
          a.state.scheduledReminders.singleWhere((r) => r.id == id),
          expectedPartition: a.state.session!.partition,
        );
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).state,
          'cancelled',
        );
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).syncState,
          'queued',
        );
        transport.offline = false;
        transport.loseReply = 'reminders.cancel';
        await a.syncNow();
        expect(a.state.lastError?.code, 'network');
        await synced(a);
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).state,
          'cancelled',
        );
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).syncState,
          'synced',
        );
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).revision,
          4,
        );
        await a.putReminder(
          id: id,
          scopeId: scope,
          targetType: 'task',
          targetId: task,
          remindAt: date,
          expectedRevision: 4,
        );
        await synced(a);
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).revision,
          5,
        );
        final target = a.state.dataForScope(scope).tasks.single;
        await a.updateTask(
          scope,
          target.copyWith(dueAt: date.add(const Duration(days: 1))),
        );
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).state,
          'cancelled',
        );
        await synced(a);
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).state,
          'cancelled',
        );
        expect(
          a.state.scheduledReminders.singleWhere((r) => r.id == id).revision,
          6,
        );
        await synced(b);
        expect(
          b.state.scheduledReminders.singleWhere((r) => r.id == id).state,
          'cancelled',
        );
        expect(
          b.state.scheduledReminders.singleWhere((r) => r.id == id).revision,
          6,
        );
      } finally {
        for (final repo in repositories) {
          await repo.close();
        }
        await directory.delete(recursive: true);
      }
    },
    skip: fixturePath == null
        ? 'Requires explicit fresh KANBAN_REMINDER_HTTP_FIXTURE'
        : false,
  );
}
