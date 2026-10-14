import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/password_visibility.dart';

void main() {
  for (final locale in ['sl', 'en']) {
    testWidgets(
      'password visibility preserves input and hides on reentry $locale',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        Widget screen() => MaterialApp(
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: PasswordVisibility(
              builder: (obscure, toggle) => TextFormField(
                controller: controller,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(suffixIcon: toggle),
              ),
            ),
          ),
        );
        await tester.pumpWidget(screen());
        await tester.enterText(
          find.byType(TextFormField),
          'synthetic-password',
        );
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).obscureText,
          isTrue,
        );
        await tester.tap(
          find.byTooltip(locale == 'sl' ? 'Pokaži geslo' : 'Show password'),
        );
        await tester.pump();
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).obscureText,
          isFalse,
        );
        expect(controller.text, 'synthetic-password');
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .enableSuggestions,
          isFalse,
        );
        await tester.tap(
          find.byTooltip(locale == 'sl' ? 'Skrij geslo' : 'Hide password'),
        );
        await tester.pump();
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).obscureText,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(screen());
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).obscureText,
          isTrue,
        );
        expect(controller.text, 'synthetic-password');
      },
    );
  }
}
