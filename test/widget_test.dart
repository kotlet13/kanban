import 'package:flutter_test/flutter_test.dart';
import 'organizer/ui/organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer;

void main() {
  testWidgets('app starts in the personal organizer without credentials', (
    tester,
  ) async {
    final storage = MemoryOrganizerStorage();
    await pumpOrganizer(tester, storage);
    expect(find.text('Jivie'), findsOneWidget);
    expect(find.text('Začni z enim opravilom.'), findsOneWidget);
    expect(storage.writes, 0);
  });
}
