import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations_sl.dart';
import 'package:kanban/l10n/app_localizations_en.dart';

void main() {
  final sl = AppLocalizationsSl();
  final en = AppLocalizationsEn();
  test('Slovenian grouped shopping uses singular dual few and other', () {
    expect(sl.inboxShoppingItemsCreated(1), 'Dodan je 1 izdelek');
    expect(sl.inboxShoppingItemsCreated(2), 'Dodana sta 2 izdelka');
    expect(sl.inboxShoppingItemsCreated(3), 'Dodani so 3 izdelki');
    expect(sl.inboxShoppingItemsCreated(4), 'Dodani so 4 izdelki');
    expect(sl.inboxShoppingItemsCreated(5), 'Dodanih je 5 izdelkov');
    expect(sl.inboxShoppingItemsCreated(101), 'Dodan je 101 izdelek');
    expect(sl.inboxShoppingItemsCreated(102), 'Dodana sta 102 izdelka');
    expect(sl.inboxShoppingItemsCreated(103), 'Dodani so 103 izdelki');
  });
  test('Slovenian task titles use the same grammatical categories', () {
    expect(sl.inboxTaskCreated(1), 'Dodano je 1 opravilo');
    expect(sl.inboxTaskCreated(2), 'Dodani sta 2 opravili');
    expect(sl.inboxTaskCreated(3), 'Dodana so 3 opravila');
    expect(sl.inboxTaskCreated(5), 'Dodanih je 5 opravil');
    expect(sl.inboxTasksAssigned(1), 'Dodeljeno ti je 1 opravilo');
    expect(sl.inboxTasksAssigned(2), 'Dodeljeni sta ti 2 opravili');
    expect(sl.inboxTasksAssigned(3), 'Dodeljena so ti 3 opravila');
    expect(sl.inboxTasksAssigned(5), 'Dodeljenih ti je 5 opravil');
    expect(sl.inboxPersonalReminders(1), 'Opomnik za 1 opravilo');
    expect(sl.inboxPersonalReminders(2), 'Opomnika za 2 opravili');
    expect(sl.inboxPersonalReminders(3), 'Opomniki za 3 opravila');
    expect(sl.inboxPersonalReminders(5), 'Opomniki za 5 opravil');
  });
  test('English singular is preserved by parallel ICU templates', () {
    expect(en.inboxShoppingItemsCreated(1), '1 item was added');
    expect(en.inboxShoppingItemsCreated(3), '3 items were added');
    expect(en.inboxTaskCreated(1), '1 task was added');
    expect(en.inboxTasksAssigned(1), '1 task was assigned to you');
    expect(en.inboxPersonalReminders(1), 'Reminder for 1 task');
  });
}
