import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/presentation/shared/invitation_recipient_field.dart';

const alice = InvitationRecipient(
  accountId: '00000000-0000-4000-a000-000000000001',
  username: 'alice_qa',
  displayName: 'Alice Example',
);
const mike = InvitationRecipient(
  accountId: '00000000-0000-4000-a000-000000000002',
  username: 'mike_qa',
  displayName: 'Mike Example',
);

Future<void> pumpField(
  WidgetTester tester,
  TextEditingController controller, {
  required Future<List<InvitationRecipient>> Function(String) search,
  bool Function()? current,
  void Function(InvitationRecipient?)? selected,
  bool enabled = true,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: InvitationRecipientField(
        controller: controller,
        enabled: enabled,
        label: 'Recipient',
        validator: (_) => null,
        isCurrent: current ?? () => true,
        search: search,
        onSelected: selected ?? (_) {},
      ),
    ),
  ),
);
Future<void> searchDelay(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets(
    'minimum query and debounce avoid short email and superseded searches; selection uses exact identity',
    (tester) async {
      final controller = TextEditingController();
      final queries = <String>[];
      InvitationRecipient? selected;
      await pumpField(
        tester,
        controller,
        search: (query) async {
          queries.add(query);
          return [alice];
        },
        selected: (value) => selected = value,
      );
      await tester.enterText(find.byType(TextFormField), 'a');
      await searchDelay(tester);
      await tester.enterText(find.byType(TextFormField), 'a@example.invalid');
      await searchDelay(tester);
      expect(queries, isEmpty);
      await tester.enterText(find.byType(TextFormField), 'Al');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextFormField), 'Ali');
      await tester.pump(const Duration(milliseconds: 349));
      expect(queries, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(queries, ['Ali']);
      await tester.tap(find.text('Alice Example'));
      await tester.pump();
      expect(controller.text, 'alice_qa');
      expect(selected?.accountId, alice.accountId);
      await searchDelay(tester);
      expect(queries, ['Ali']);
      await tester.enterText(find.byType(TextFormField), 'alice_other');
      expect(selected, isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'out of order response cannot replace newer recipient suggestions',
    (tester) async {
      final controller = TextEditingController();
      final requests = <String, Completer<List<InvitationRecipient>>>{};
      await pumpField(
        tester,
        controller,
        search: (query) => (requests[query] = Completer()).future,
      );
      await tester.enterText(find.byType(TextFormField), 'Al');
      await searchDelay(tester);
      await tester.enterText(find.byType(TextFormField), 'Mi');
      await searchDelay(tester);
      requests['Mi']!.complete([mike]);
      await tester.pump();
      requests['Al']!.complete([alice]);
      await tester.pump();
      expect(find.text('Mike Example'), findsOneWidget);
      expect(find.text('Alice Example'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'changed session rejects pending result and cannot select a recipient',
    (tester) async {
      final controller = TextEditingController();
      final request = Completer<List<InvitationRecipient>>();
      var current = true;
      await pumpField(
        tester,
        controller,
        current: () => current,
        search: (_) => request.future,
      );
      await tester.enterText(find.byType(TextFormField), 'Al');
      await searchDelay(tester);
      current = false;
      request.complete([alice]);
      await tester.pump();
      expect(find.byType(ListTile), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('cleared query discards in flight results and cancels debounce', (
    tester,
  ) async {
    final controller = TextEditingController();
    final request = Completer<List<InvitationRecipient>>();
    var calls = 0;
    await pumpField(
      tester,
      controller,
      search: (_) {
        calls++;
        return request.future;
      },
    );
    await tester.enterText(find.byType(TextFormField), 'Al');
    await searchDelay(tester);
    await tester.enterText(find.byType(TextFormField), '');
    request.complete([alice]);
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'Mi');
    await tester.enterText(find.byType(TextFormField), '');
    await searchDelay(tester);
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('disabled form hides old suggestions and suppresses response', (
    tester,
  ) async {
    final controller = TextEditingController();
    final request = Completer<List<InvitationRecipient>>();
    await pumpField(tester, controller, search: (_) => request.future);
    await tester.enterText(find.byType(TextFormField), 'Al');
    await searchDelay(tester);
    await pumpField(
      tester,
      controller,
      enabled: false,
      search: (_) => request.future,
    );
    request.complete([alice]);
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'search failure retains exact recipient input with recovery copy',
    (tester) async {
      final controller = TextEditingController();
      await pumpField(
        tester,
        controller,
        search: (_) async => throw StateError('synthetic failure'),
      );
      await tester.enterText(find.byType(TextFormField), 'exact_username');
      await searchDelay(tester);
      expect(controller.text, 'exact_username');
      expect(find.textContaining('Search is unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('pending response after disposal is ignored', (tester) async {
    final controller = TextEditingController();
    final request = Completer<List<InvitationRecipient>>();
    await pumpField(tester, controller, search: (_) => request.future);
    await tester.enterText(find.byType(TextFormField), 'Al');
    await searchDelay(tester);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    request.complete([alice]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
