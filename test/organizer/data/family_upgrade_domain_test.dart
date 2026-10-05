import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/organizer_projections.dart';
import 'package:kanban/organizer/domain/shared_dates.dart';

void main() {
  final now = DateTime.utc(2026, 10, 4);
  test(
    'shared ledger aggregates exactly beyond JS safe integer, keeps currencies and planned transfers separate',
    () {
      final accounts = [
        SharedFinanceAccount(
          id: 'eur',
          name: 'EUR',
          currency: 'EUR',
          createdAt: now,
          updatedAt: now,
        ),
        SharedFinanceAccount(
          id: 'eur2',
          name: 'EUR2',
          currency: 'EUR',
          createdAt: now,
          updatedAt: now,
        ),
        SharedFinanceAccount(
          id: 'usd',
          name: 'USD',
          currency: 'USD',
          openingBalanceMinor: 500,
          createdAt: now,
          updatedAt: now,
        ),
      ];
      const amount = 9000000000000;
      final entries = List.generate(
        1100,
        (i) => SharedFinanceEntry(
          id: 'income$i',
          accountId: 'eur',
          kind: FinanceEntryKind.income,
          amountMinor: amount,
          currency: 'EUR',
          title: 'Income',
          occurredAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      entries.add(
        SharedFinanceEntry(
          id: 'planned',
          accountId: 'eur',
          kind: FinanceEntryKind.expense,
          status: SharedFinanceStatus.planned,
          amountMinor: 999,
          currency: 'EUR',
          title: 'Planned',
          occurredAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final transfer = SharedFinanceTransfer(
        id: 'transfer',
        fromAccountId: 'eur',
        toAccountId: 'eur2',
        amountMinor: 101,
        currency: 'EUR',
        title: 'Transfer',
        occurredAt: now,
        createdAt: now,
        updatedAt: now,
      );
      final totals = summarizeSharedFinance(
        accounts: accounts,
        entries: entries,
        transfers: [transfer],
      );
      final exact = BigInt.from(amount) * BigInt.from(1100);
      expect(totals['EUR']!.incomeMinor, exact);
      expect(totals['EUR']!.expenseMinor, BigInt.zero);
      expect(totals['EUR']!.balanceMinor, exact);
      expect(totals['EUR']!.accountBalances['eur'], exact - BigInt.from(101));
      expect(totals['EUR']!.accountBalances['eur2'], BigInt.from(101));
      expect(totals['USD']!.balanceMinor, BigInt.from(500));
      expect(formatSharedMoneyMinor(exact), '99000000000000.00');
      expect(parseSharedMoneyMinor('-1,25', allowSigned: true), -125);
      expect(parseSharedMoneyMinor('0', allowSigned: true, allowZero: true), 0);
      expect(() => parseSharedMoneyMinor('1.001'), throwsFormatException);
      expect(
        () => parseSharedMoneyMinor('90000000000.01'),
        throwsFormatException,
      );
    },
  );
  test(
    'daily agenda uses exclusive interval end at midnight and includes zero-duration event on its own day',
    () {
      final midnight = DateTime(2026, 10, 5);
      final events = [
        SharedEvent(
          id: 'previous',
          title: 'Previous day',
          startAt: midnight.subtract(const Duration(hours: 2)),
          endAt: midnight,
          createdAt: now,
          updatedAt: now,
        ),
        SharedEvent(
          id: 'instant',
          title: 'Instant',
          startAt: midnight,
          endAt: midnight,
          createdAt: now,
          updatedAt: now,
        ),
      ];
      final agenda = dailyAgenda(
        SharedScopeData(events: events),
        scopeId: 'scope',
        day: midnight,
      );
      expect(agenda.map((e) => e.id), ['instant']);
    },
  );
  test(
    'old personal backup remains readable and next schema cannot silently discard schedules',
    () {
      final task = LocalTask(
        id: '12345678-1234-4234-8234-123456789abc',
        title: 'Legacy',
        notes: '',
        projectId: null,
        dueAt: null,
        isCompleted: false,
        createdAt: now,
        updatedAt: now,
      );
      final data = OrganizerSnapshot(tasks: [task]).toJson();
      final oldTask = (data['tasks'] as List).single as Map;
      for (final key in [
        'startAt',
        'endAt',
        'assigneeAccountIds',
        'createdByAccountId',
        'updatedByAccountId',
      ]) {
        oldTask.remove(key);
      }
      final legacy = {
        'format': 'vsakdan-personal-backup',
        'schemaVersion': 1,
        'workspace': 'personal',
        'data': data,
      };
      final restored = OrganizerBackupCodec.decode(jsonEncode(legacy));
      expect(restored.tasks.single.title, 'Legacy');
      expect(restored.tasks.single.assigneeAccountIds, isEmpty);
      final updated = restored.copyWith(
        tasks: [
          restored.tasks.single.copyWith(
            startAt: now,
            endAt: now.add(const Duration(hours: 1)),
          ),
        ],
      );
      final encoded = jsonDecode(OrganizerBackupCodec.encode(updated)) as Map;
      expect(encoded['schemaVersion'], 2);
      expect(
        OrganizerBackupCodec.decode(jsonEncode(encoded)).tasks.single.startAt,
        now,
      );
      encoded['schemaVersion'] = 3;
      expect(
        () => OrganizerBackupCodec.decode(jsonEncode(encoded)),
        throwsFormatException,
      );
    },
  );
  test(
    'scheduled reminders use their own category, independent of activity settings',
    () {
      final session = AccountSession(
        serverUrl: 'https://example.test/',
        serverId: 'server',
        accountId: 'account',
        userId: 1,
        username: 'User',
        displayName: 'User',
        deviceId: 'device',
        expiresAt: now,
      );
      final scope = SharedScope(
        id: 'scope',
        name: 'Scope',
        kind: SharedScopeKind.household,
        role: SharedRole.owner,
      );
      final task = LocalTask(
        id: 'task',
        title: 'Task',
        notes: '',
        projectId: null,
        dueAt: now,
        isCompleted: false,
        createdAt: now,
        updatedAt: now,
      );
      final event = SharedEvent(
        id: 'event',
        title: 'Event',
        startAt: now,
        createdAt: now,
        updatedAt: now,
      );
      CollaborationState state(bool reminders, bool tasks) =>
          CollaborationState(
            session: session,
            scopes: [scope],
            data: {
              'scope': SharedScopeData(tasks: [task], events: [event]),
            },
            scheduledReminders: [
              SharedScheduledReminder(
                id: 'custom',
                scopeId: 'scope',
                targetType: 'task',
                targetId: 'task',
                remindAt: now,
                revision: 1,
                state: 'pending',
              ),
            ],
            notificationPreferences: {
              'scope': SharedNotificationPreferences(
                scopeId: 'scope',
                categories: {
                  'reminders': SharedNotificationSettings(inApp: reminders),
                  'tasks': SharedNotificationSettings(inApp: tasks),
                  'events': const SharedNotificationSettings(inApp: false),
                },
              ),
            },
          );
      expect(
        desiredReminderPlans(
          personal: OrganizerSnapshot(),
          shared: state(false, true),
        ),
        isEmpty,
      );
      expect(
        desiredReminderPlans(
          personal: OrganizerSnapshot(),
          shared: state(true, false),
        ).map((p) => p.reason),
        containsAll(['custom_reminder', 'event_start']),
      );
      final automatic = CollaborationState(
        session: session,
        scopes: [scope],
        data: {
          'scope': SharedScopeData(tasks: [task]),
        },
        notificationPreferences: state(true, false).notificationPreferences,
      );
      expect(
        desiredReminderPlans(
          personal: OrganizerSnapshot(),
          shared: automatic,
        ).single.reason,
        'task_due',
      );
    },
  );
  test(
    'shared dates accept precision aliases but reject normalized impossible calendar dates',
    () {
      expect(
        readSharedDate({'x': '2026-10-04T12:00:00Z'}, 'x'),
        readSharedDate({'x': '2026-10-04T12:00:00.000000Z'}, 'x'),
      );
      expect(
        () => readSharedDate({'x': '2026-02-30T12:00:00Z'}, 'x'),
        throwsFormatException,
      );
      expect(
        () => readSharedDate({'x': '2026-10-04T12:00:00+00:00'}, 'x'),
        throwsFormatException,
      );
    },
  );
}
