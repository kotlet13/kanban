import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

final now = DateTime.utc(2026, 10, 4, 12);

class MemoryStorage implements OrganizerStorage {
  OrganizerSnapshot value = OrganizerSnapshot();
  bool failWrite = false;
  bool failAfterWrite = false;
  int writes = 0;
  int activeWrites = 0;
  int maxActiveWrites = 0;

  @override
  Future<OrganizerSnapshot> read() async => value;

  @override
  Future<void> write(OrganizerSnapshot snapshot) async {
    activeWrites++;
    if (activeWrites > maxActiveWrites) maxActiveWrites = activeWrites;
    try {
      await Future<void>.delayed(Duration.zero);
      if (failWrite) throw const FileSystemException('Simulated write failure');
      value = OrganizerBackupCodec.decode(
        OrganizerBackupCodec.encode(snapshot),
      );
      writes++;
      if (failAfterWrite) {
        throw const FileSystemException('Simulated flush failure after commit');
      }
    } finally {
      activeWrites--;
    }
  }

  @override
  Future<void> close() async {}
}

OrganizerRepository repository(OrganizerStorage storage) {
  var id = 0;
  return OrganizerRepository(
    storage,
    clock: () => now,
    idGenerator: () => 'local-${id++}',
  );
}

Future<void> populate(OrganizerRepository repo) async {
  await repo.createProject(title: 'Garden', area: ProjectArea.home);
  final project = repo.snapshot.projects.single;
  await repo.createTask(
    title: 'Plant seeds',
    projectId: project.id,
    dueAt: now.subtract(const Duration(hours: 1)),
  );
  await repo.createShoppingList(title: 'Groceries');
  await repo.createShoppingItem(
    listId: repo.snapshot.shoppingLists.single.id,
    title: 'Apples',
    quantity: '2 kg',
  );
  await repo.createEvent(
    title: 'Dinner',
    startsAt: now,
    endsAt: now.add(const Duration(hours: 1)),
    projectId: project.id,
  );
  await repo.createFinanceEntry(
    title: 'Salary',
    amountMinor: 100001,
    kind: FinanceEntryKind.income,
    occurredAt: now,
    projectId: project.id,
  );
  await repo.createFinanceEntry(
    title: 'Seeds',
    amountMinor: 1234,
    kind: FinanceEntryKind.expense,
    occurredAt: now,
    projectId: project.id,
  );
  await repo.createFinanceEntry(
    title: 'Foreign expense',
    amountMinor: 200,
    currency: 'USD',
    kind: FinanceEntryKind.expense,
    occurredAt: now,
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test('first launch has empty personal data and needs no account', () async {
    final repo = repository(MemoryStorage());
    final value = await repo.initialize();
    expect(value.recordIds, isEmpty);
    expect(value.revision, 0);
    await repo.close();
  });

  test('real Hive survives close and reopen with every record type', () async {
    final directory = await Directory.systemTemp.createTemp('organizer-test-');
    try {
      final first = repository(
        await HiveOrganizerStorage.open(directory: directory.path),
      );
      await first.initialize();
      await populate(first);
      await first.setShoppingItemChecked(
        first.snapshot.shoppingItems.single.id,
        true,
      );
      await first.markReminderRead(first.snapshot.reminders.single.id);
      final committed = first.snapshot.toJson();
      await first.close();

      final second = repository(
        await HiveOrganizerStorage.open(directory: directory.path),
      );
      await second.initialize();
      await second.refreshReminders();
      expect(second.snapshot.toJson(), committed);
      expect(second.snapshot.balanceForCurrency('EUR'), 98767);
      expect(second.snapshot.balanceForCurrency('USD'), -200);
      expect(second.snapshot.projects.single.area, ProjectArea.home);
      await second.close();
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'many overlapping writes preserve records and run one at a time',
    () async {
      final storage = MemoryStorage();
      final repo = repository(storage);
      await repo.initialize();
      await Future.wait(
        List.generate(40, (i) => repo.createTask(title: 'Task $i')),
      );
      expect(repo.snapshot.tasks.length, 40);
      expect(repo.snapshot.recordIds.length, 40);
      expect(repo.snapshot.revision, 40);
      expect(storage.maxActiveWrites, 1);
      await repo.close();
    },
  );

  test('stale edit is rejected after a completion change', () async {
    final repo = repository(MemoryStorage());
    await repo.initialize();
    await repo.createTask(title: 'Initial');
    final stale = repo.snapshot.tasks.single;
    final completed = repo.setTaskCompleted(stale.id, true);
    final rejectedEdit = expectLater(
      repo.updateTask(stale.copyWith(title: 'Edited')),
      throwsA(isA<OrganizerConflictException>()),
    );
    await completed;
    await rejectedEdit;
    expect(repo.snapshot.tasks.single.isCompleted, isTrue);
    expect(repo.snapshot.tasks.single.title, 'Initial');
    await repo.updateTask(repo.snapshot.tasks.single.copyWith(title: 'Edited'));
    expect(repo.snapshot.tasks.single.isCompleted, isTrue);
    expect(repo.snapshot.tasks.single.title, 'Edited');
    await repo.close();
  });

  test(
    'failed write publishes no phantom record and next write succeeds',
    () async {
      final storage = MemoryStorage();
      final repo = repository(storage);
      await repo.initialize();
      await repo.createProject(title: 'Existing');
      final committed = repo.snapshot.toJson();
      storage.failWrite = true;
      await expectLater(
        repo.createTask(title: 'Unsaved'),
        throwsA(isA<FileSystemException>()),
      );
      expect(repo.snapshot.toJson(), committed);
      expect(storage.value.toJson(), committed);
      storage.failWrite = false;
      await repo.createTask(title: 'Saved');
      expect(repo.snapshot.tasks.single.title, 'Saved');
      await repo.close();
    },
  );

  test(
    'uncertain flush failure reconciles persisted state before next write',
    () async {
      final storage = MemoryStorage();
      final repo = repository(storage);
      await repo.initialize();
      storage.failAfterWrite = true;
      await expectLater(
        repo.createTask(title: 'Written'),
        throwsA(isA<FileSystemException>()),
      );
      expect(repo.snapshot.tasks.single.title, 'Written');
      storage.failAfterWrite = false;
      await repo.createTask(title: 'Next');
      expect(repo.snapshot.tasks.map((v) => v.title), ['Written', 'Next']);
      await repo.close();
    },
  );

  test(
    'project deletion preserves linked records; list deletion removes its items',
    () async {
      final repo = repository(MemoryStorage());
      await repo.initialize();
      await populate(repo);
      await repo.deleteProject(repo.snapshot.projects.single.id);
      expect(repo.snapshot.projects, isEmpty);
      expect(repo.snapshot.tasks.single.projectId, isNull);
      expect(repo.snapshot.events.single.projectId, isNull);
      expect(
        repo.snapshot.financeEntries.every((v) => v.projectId == null),
        isTrue,
      );
      expect(repo.snapshot.financeEntries.length, 3);
      await repo.deleteShoppingList(repo.snapshot.shoppingLists.single.id);
      expect(repo.snapshot.shoppingItems, isEmpty);
      await repo.close();
    },
  );

  test(
    'due inbox is idempotent and rescheduling/completion clears stale reminders',
    () async {
      final storage = MemoryStorage();
      final repo = repository(storage);
      await repo.initialize();
      await repo.createTask(title: 'Due', dueAt: now);
      final reminder = repo.snapshot.reminders.single;
      await repo.markReminderRead(reminder.id);
      final writes = storage.writes;
      await repo.refreshReminders();
      await repo.refreshReminders();
      expect(storage.writes, writes);
      expect(repo.snapshot.reminders.single.id, reminder.id);
      expect(repo.snapshot.reminders.single.isRead, isTrue);
      await repo.updateTask(
        repo.snapshot.tasks.single.copyWith(
          dueAt: now.add(const Duration(days: 1)),
        ),
      );
      expect(repo.snapshot.reminders, isEmpty);
      await repo.updateTask(repo.snapshot.tasks.single.copyWith(dueAt: now));
      expect(repo.snapshot.reminders.length, 1);
      await repo.setTaskCompleted(repo.snapshot.tasks.single.id, true);
      expect(repo.snapshot.reminders, isEmpty);
      await repo.close();
    },
  );

  test(
    'export restores all data into empty workspace and collision never overwrites',
    () async {
      final first = repository(MemoryStorage());
      await first.initialize();
      await populate(first);
      final backup = await first.exportBackup();
      final restored = repository(MemoryStorage());
      await restored.initialize();
      await restored.importBackup(backup);
      final expected = first.snapshot.toJson()..remove('revision');
      final actual = restored.snapshot.toJson()..remove('revision');
      expect(actual, expected);
      final before = restored.snapshot.toJson();
      await expectLater(
        restored.importBackup(backup),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(restored.snapshot.toJson(), before);
      await first.close();
      await restored.close();
    },
  );

  test('valid disjoint import preserves existing records', () async {
    final storage = MemoryStorage();
    final repo = repository(storage);
    await repo.initialize();
    await repo.createProject(title: 'Keep');
    final imported = OrganizerRepository(
      MemoryStorage(),
      clock: () => now,
      idGenerator: () => 'different-id',
    );
    await imported.initialize();
    await imported.createTask(title: 'Import');
    await repo.importBackup(await imported.exportBackup());
    expect(repo.snapshot.projects.single.title, 'Keep');
    expect(repo.snapshot.tasks.single.title, 'Import');
    await repo.close();
    await imported.close();
  });

  test(
    'invalid schema, fractional money, refs, dates and duplicates reject atomically',
    () async {
      final storage = MemoryStorage();
      final repo = repository(storage);
      await repo.initialize();
      await populate(repo);
      final backup = await repo.exportBackup();
      final original = repo.snapshot.toJson();
      final modifications = <void Function(Map<String, dynamic>)>[
        (json) => json['schemaVersion'] = 3,
        (json) => json['schemaVersion'] = 1.0,
        (json) => json['workspace'] = 'other-user',
        (json) => json['data']['financeEntries'][0]['amountMinor'] = 1.5,
        (json) => json['data']['financeEntries'][0]['amountMinor'] = 0,
        (json) => json['data']['financeEntries'][0]['currency'] = 'JPY',
        (json) => json['data']['tasks'][0]['projectId'] = 'missing',
        (json) => json['data']['shoppingItems'][0]['listId'] = 'missing',
        (json) =>
            json['data']['events'][0]['endsAt'] = '2026-02-30T00:00:00.000Z',
        (json) => json['data']['tasks'][0]['revision'] = -1,
        (json) => json['data']['tasks'][0]['title'] = ' ',
        (json) =>
            json['data']['tasks'][0]['id'] = json['data']['projects'][0]['id'],
      ];
      final writes = storage.writes;
      for (final modify in modifications) {
        final json = jsonDecode(backup) as Map<String, dynamic>;
        modify(json);
        await expectLater(
          repo.importBackup(jsonEncode(json)),
          throwsFormatException,
        );
        expect(repo.snapshot.toJson(), original);
      }
      expect(storage.writes, writes);
      await repo.close();
    },
  );

  test('bad existing storage is reported and is not reset', () async {
    final directory = await Directory.systemTemp.createTemp(
      'organizer-corrupt-',
    );
    try {
      final storage = await HiveOrganizerStorage.open(
        directory: directory.path,
      );
      final box = Hive.box<String>(HiveOrganizerStorage.boxName);
      const corrupt = '{"schemaVersion":999}';
      await box.put('committed_snapshot', corrupt);
      final repo = repository(storage);
      await expectLater(repo.initialize(), throwsFormatException);
      expect(box.get('committed_snapshot'), corrupt);
      await repo.close();
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  test('integer money parsing is exact and currencies stay separated', () {
    expect(parseMoneyMinor('0.29'), 29);
    expect(parseMoneyMinor('1,01'), 101);
    expect(parseMoneyMinor('12'), 1200);
    expect(formatMoneyMinor(-29), '-0.29');
    for (final invalid in ['0', '-1', '1.001', 'NaN', '1e2', '1,000.00']) {
      expect(() => parseMoneyMinor(invalid), throwsFormatException);
    }
    expect(() => parseMoneyMinor('90000000000.01'), throwsFormatException);
  });

  test(
    'provider works against injected local storage and publishes successful edits',
    () async {
      final storage = MemoryStorage();
      final container = ProviderContainer(
        overrides: [
          organizerStorageProvider.overrideWithValue(() async => storage),
        ],
      );
      try {
        expect((await container.read(organizerProvider.future)).tasks, isEmpty);
        await container
            .read(organizerProvider.notifier)
            .createTask(title: 'Offline');
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(organizerProvider).requireValue.tasks.single.title,
          'Offline',
        );
        storage.failWrite = true;
        await expectLater(
          container.read(organizerProvider.notifier).createTask(title: 'Fail'),
          throwsA(isA<FileSystemException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(container.read(organizerProvider).requireValue.tasks.length, 1);
      } finally {
        container.dispose();
      }
    },
  );

  test(
    'provider retries a failed open using a new storage factory call',
    () async {
      final storage = MemoryStorage();
      var opens = 0;
      final container = ProviderContainer(
        overrides: [
          organizerStorageProvider.overrideWithValue(() async {
            if (opens++ == 0) {
              throw const FileSystemException('Temporary open failure');
            }
            return storage;
          }),
        ],
      );
      try {
        await expectLater(
          container.read(organizerProvider.future),
          throwsA(isA<FileSystemException>()),
        );
        container.invalidate(organizerRepositoryProvider);
        expect((await container.read(organizerProvider.future)).tasks, isEmpty);
        await container
            .read(organizerProvider.notifier)
            .createTask(title: 'Recovered');
        expect(storage.value.tasks.single.title, 'Recovered');
        expect(opens, 2);
      } finally {
        container.dispose();
      }
    },
  );

  test(
    'provider recreation closes and reopens Hive after queued writes finish',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'organizer-provider-',
      );
      final container = ProviderContainer(
        overrides: [
          organizerStorageProvider.overrideWithValue(
            () => HiveOrganizerStorage.open(directory: directory.path),
          ),
        ],
      );
      try {
        await container.read(organizerProvider.future);
        final writing = container
            .read(organizerProvider.notifier)
            .createTask(title: 'Survives replacement');
        container.invalidate(organizerRepositoryProvider);
        await writing;
        final value = await container.read(organizerProvider.future);
        expect(value.tasks.single.title, 'Survives replacement');
        await container
            .read(organizerProvider.notifier)
            .createTask(title: 'After reopening');
        expect(
          (await container.read(organizerProvider.future)).tasks.length,
          2,
        );
      } finally {
        final repo = await container.read(organizerRepositoryProvider.future);
        container.dispose();
        await repo.close();
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('close drains accepted mutations and rejects later ones', () async {
    final storage = MemoryStorage();
    final repo = repository(storage);
    await repo.initialize();
    final accepted = repo.createTask(title: 'Accepted');
    final closing = repo.close();
    await expectLater(repo.createTask(title: 'Too late'), throwsStateError);
    await accepted;
    await closing;
    await repo.close();
    expect(storage.value.tasks.single.title, 'Accepted');
  });

  test('money totals cannot exceed exact integer range on web', () {
    final snapshot = OrganizerSnapshot(
      financeEntries: List.generate(
        1002,
        (i) => FinanceEntry(
          id: 'entry-$i',
          title: 'Income',
          amountMinor: maxMoneyMinor,
          currency: 'EUR',
          kind: FinanceEntryKind.income,
          occurredAt: now,
          projectId: null,
          notes: '',
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    expect(snapshot.validate, throwsFormatException);
  });

  test(
    'timer/resume refresh due inbox, capture errors and dispose callbacks',
    () async {
      var time = now;
      void Function()? tick;
      final storage = MemoryStorage();
      final container = ProviderContainer(
        overrides: [
          organizerStorageProvider.overrideWithValue(() async => storage),
          organizerClockProvider.overrideWithValue(() => time),
          organizerReminderSchedulerProvider.overrideWithValue((callback) {
            tick = callback;
            return () => tick = null;
          }),
        ],
      );
      try {
        await container.read(organizerProvider.future);
        final controller = container.read(organizerProvider.notifier);
        await controller.createTask(
          title: 'Later',
          dueAt: now.add(const Duration(seconds: 30)),
        );
        expect(
          container.read(organizerProvider).requireValue.reminders,
          isEmpty,
        );
        time = now.add(const Duration(minutes: 1));
        storage.failWrite = true;
        tick!();
        await controller.exportBackup();
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(organizerReminderRefreshErrorProvider),
          isA<FileSystemException>(),
        );
        expect(
          container.read(organizerProvider).requireValue.reminders,
          isEmpty,
        );
        storage.failWrite = false;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await controller.exportBackup();
        await Future<void>.delayed(Duration.zero);
        expect(
          container
              .read(organizerProvider)
              .requireValue
              .reminders
              .single
              .taskId,
          storage.value.tasks.single.id,
        );
        expect(container.read(organizerReminderRefreshErrorProvider), isNull);
      } finally {
        container.dispose();
        expect(tick, isNull);
      }
    },
  );
}
