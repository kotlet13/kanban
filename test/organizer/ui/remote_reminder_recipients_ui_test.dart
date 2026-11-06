import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/inbox/remote_reminder_editor.dart';

import 'remote_reminder_ui_test.dart' as fixture;

const _shared = 'schedulerAndTaskAssignees';

Finder _policy([String? id]) =>
    find.byKey(ValueKey('remote-reminder-recipient-policy-$id'));

Future<void> _open(
  WidgetTester tester,
  fixture.ReminderController controller, {
  double width = 390,
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await fixture.pump(tester, controller, width: width);
  await tester.tap(find.byType(RemoteReminderButton));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('remote-reminder-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 1100.0]) {
    testWidgets('new task reminder offers both recipients at ${width}px', (
      tester,
    ) async {
      final controller = fixture.ReminderController(
        fixture.state(taskReminderRecipientsSupported: true),
      );
      await _open(tester, controller, width: width);
      expect(tester.state<FormFieldState<String>>(_policy()).value, _shared);
      expect(tester.takeException(), isNull);
      await _save(tester);
      expect(controller.calls, ['put']);
      expect(controller.savedRecipientPolicy, _shared);
      expect(controller.savedOffset, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('explicit personal choice keeps task reminder personal', (
    tester,
  ) async {
    final controller = fixture.ReminderController(
      fixture.state(taskReminderRecipientsSupported: true),
    );
    await _open(tester, controller);
    await tester.ensureVisible(_policy());
    await tester.tap(_policy());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Samo ti').last);
    await tester.pumpAndSettle();
    await _save(tester);
    expect(controller.savedRecipientPolicy, isNull);
    expect(controller.calls, ['put']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a legacy personal reminder does not expand recipients', (
    tester,
  ) async {
    final controller = fixture.ReminderController(
      fixture.state(
        taskReminderRecipientsSupported: true,
        reminders: [fixture.reminder()],
      ),
    );
    await _open(tester, controller);
    expect(
      tester.state<FormFieldState<String>>(_policy(fixture.reminderId)).value,
      'self',
    );
    await _save(tester);
    expect(controller.savedId, fixture.reminderId);
    expect(controller.savedRevision, 4);
    expect(controller.savedRecipientPolicy, isNull);
    expect(controller.calls, ['put']);
  });

  testWidgets('editing shared reminder keeps its explicit recipient policy', (
    tester,
  ) async {
    final controller = fixture.ReminderController(
      fixture.state(
        taskReminderRecipientsSupported: true,
        reminders: [fixture.reminder(recipientPolicy: _shared)],
      ),
    );
    await _open(tester, controller);
    expect(
      tester.state<FormFieldState<String>>(_policy(fixture.reminderId)).value,
      _shared,
    );
    await _save(tester);
    expect(controller.savedId, fixture.reminderId);
    expect(controller.savedRevision, 4);
    expect(controller.savedRecipientPolicy, _shared);
  });

  testWidgets('older server offers and saves only a personal reminder', (
    tester,
  ) async {
    final controller = fixture.ReminderController(fixture.state());
    await _open(tester, controller);
    expect(_policy(), findsNothing);
    await _save(tester);
    expect(controller.calls, ['put']);
    expect(controller.savedRecipientPolicy, isNull);
  });

  testWidgets('deadline choice preserves the shared recipient policy', (
    tester,
  ) async {
    final controller = fixture.ReminderController(
      fixture.state(
        taskReminderRecipientsSupported: true,
        recordContractVersion: 6,
      ),
    );
    await _open(tester, controller);
    final mode = find.byKey(const ValueKey('reminder-schedule-mode-null'));
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 uro pred rokom').last);
    await tester.pumpAndSettle();
    await _save(tester);
    expect(controller.calls, ['put']);
    expect(controller.savedRecipientPolicy, _shared);
    expect(controller.savedOffset, 60);
    expect(
      controller.savedAt,
      fixture.now.add(const Duration(days: 1, hours: -1)).toUtc(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'capability loss cannot silently save a shared intent as personal',
    (tester) async {
      final controller = fixture.ReminderController(
        fixture.state(taskReminderRecipientsSupported: true),
      );
      await _open(tester, controller);
      controller.replace(fixture.state());
      await tester.pumpAndSettle();
      await _save(tester);
      expect(controller.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
