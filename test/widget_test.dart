import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/widgets/jivie_brand_mark.dart';
import 'organizer/ui/organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer;

void main() {
  testWidgets('app starts in the personal organizer without credentials', (
    tester,
  ) async {
    final storage = MemoryOrganizerStorage();
    await pumpOrganizer(tester, storage);
    expect(find.byType(JivieBrandMark), findsOneWidget);
    final spacePicker = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(DropdownButton<String>),
    );
    expect(spacePicker, findsOneWidget);
    expect(
      tester.widget<DropdownButton<String>>(spacePicker).value,
      'local:local',
    );
    expect(find.text('Osebno'), findsOneWidget);
    expect(find.text('Jivie'), findsNothing);
    expect(find.text('Začni z enim opravilom.'), findsOneWidget);
    expect(storage.writes, 0);
    await tester.tap(find.byKey(const ValueKey('organizer-menu-open')));
    await tester.pumpAndSettle();
    expect(find.text('Jivie'), findsOneWidget);
    expect(storage.writes, 0);
    expect(tester.takeException(), isNull);
  });
}
