import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/invitation_recipient_field.dart';
import 'package:kanban/organizer/presentation/shared/sharing_forms.dart';

void expectLiteralInput(TextField field) {
  expect(field.keyboardType, TextInputType.emailAddress);
  expect(field.autocorrect, isFalse);
  expect(field.enableSuggestions, isFalse);
  expect(field.textCapitalization, TextCapitalization.none);
  expect(field.smartDashesType, SmartDashesType.disabled);
  expect(field.smartQuotesType, SmartQuotesType.disabled);
}

Widget host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'inviteReview recipient search keeps email dots and exact input',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var searches = 0;
      await tester.pumpWidget(
        host(
          InvitationRecipientField(
            controller: controller,
            enabled: true,
            label: 'Recipient',
            validator: (_) => null,
            isCurrent: () => true,
            search: (_) async {
              searches++;
              return [];
            },
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectLiteralInput(tester.widget<TextField>(find.byType(TextField)));
      const exact = 'Ime.Priimek@example.com';
      await tester.enterText(find.byType(TextFormField), exact);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.text, exact);
      expect(searches, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inviteReview exact recipient fallback disables smart input', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSharingForm(
              context,
              title: 'Invitation',
              fields: const [
                SharingField(
                  id: 'recipient',
                  label: 'Recipient',
                  sensitive: true,
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
              submitLabel: 'Send',
              errorMessage: (_) => 'Error',
              onSubmit: (values) async => submitted = values['recipient'],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('sharing-recipient'));
    expectLiteralInput(
      tester.widget<TextField>(
        find.descendant(of: finder, matching: find.byType(TextField)),
      ),
    );
    const exact = 'Ime.Priimek@example.com';
    await tester.enterText(finder, exact);
    expect(tester.widget<TextFormField>(finder).controller!.text, exact);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(submitted, exact);
    expect(tester.takeException(), isNull);
  });
}
