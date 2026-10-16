import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/widgets/jivie_brand_mark.dart';
import 'package:kanban/organizer/presentation/shared/space_picker.dart';
import 'package:kanban/organizer/presentation/planning/utrip_overview.dart';
import 'organizer/ui/organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer, mobileTab;

void main() {
  testWidgets('app starts in the personal organizer without credentials', (
    tester,
  ) async {
    final storage = MemoryOrganizerStorage();
    await pumpOrganizer(tester, storage);
    expect(find.byType(JivieBrandMark), findsOneWidget);
    final spacePicker = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(OrganizerSpacePickerButton),
    );
    expect(spacePicker, findsOneWidget);
    expect(
      tester.widget<OrganizerSpacePickerButton>(spacePicker).value,
      'local:local',
    );
    expect(find.text('Osebno'), findsOneWidget);
    expect(find.text('Jivie'), findsNothing);
    expect(find.byType(OrganizerUtripOverview), findsOneWidget);
    expect(storage.snapshot.tasks, isEmpty);
    expect(storage.writes, 0);
    await mobileTab(tester, 'Več');
    expect(find.text('Račun'), findsOneWidget);
    expect(storage.writes, 0);
    expect(tester.takeException(), isNull);
  });
}
