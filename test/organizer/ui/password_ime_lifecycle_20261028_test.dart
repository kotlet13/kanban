import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/preserved_installation_files.dart';
import 'package:kanban/organizer/presentation/password_visibility.dart';
import 'package:kanban/organizer/presentation/recovery/preserved_installation_files_page.dart';

class _EmptyFiles implements PreservedInstallationFiles {
  @override
  Future<List<PreservedInstallationFile>> list({String? afterId}) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> screen(
    WidgetTester tester, {
    required TextEditingController controller,
    required FocusNode passwordFocus,
    bool secret = true,
    bool enabled = true,
    FocusNode? normalFocus,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(
          children: [
            PasswordVisibility(
              secret: secret,
              enabled: enabled,
              builder: (obscure, toggle) => TextField(
                key: const ValueKey('credential'),
                controller: controller,
                focusNode: passwordFocus,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: !secret,
                enableIMEPersonalizedLearning: !secret,
                autofillHints: secret ? const [AutofillHints.password] : null,
                decoration: InputDecoration(suffixIcon: toggle),
              ),
            ),
            TextField(key: const ValueKey('normal'), focusNode: normalFocus),
          ],
        ),
      ),
    ),
  );

  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  }

  testWidgets(
    'focused Android password releases its private input client on background',
    (tester) async {
      final controller = TextEditingController(text: 'synthetic-password');
      final focus = FocusNode(), normal = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      addTearDown(normal.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await screen(
        tester,
        controller: controller,
        passwordFocus: focus,
        normalFocus: normal,
      );
      await tester.showKeyboard(find.byKey(const ValueKey('credential')));
      expect(focus.hasFocus, true);
      expect(tester.testTextInput.hasAnyClients, true);
      expect(
        tester.testTextInput.setClientArgs!['enableIMEPersonalizedLearning'],
        false,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        focus.hasFocus,
        true,
        reason: 'IME and autofill can temporarily make Android inactive',
      );
      expect(tester.testTextInput.hasAnyClients, true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(focus.hasFocus, false);
      expect(tester.testTextInput.hasAnyClients, false);
      expect(controller.text, 'synthetic-password');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, false);
      await tester.showKeyboard(find.byKey(const ValueKey('normal')));
      expect(
        tester.testTextInput.setClientArgs!['enableIMEPersonalizedLearning'],
        true,
      );
      expect(tester.testTextInput.setClientArgs!['obscureText'], false);
      expect(controller.text, 'synthetic-password');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Android background leaves a different focused editor connected',
    (tester) async {
      final controller = TextEditingController(text: 'password stays local');
      final focus = FocusNode(), normal = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      addTearDown(normal.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await screen(
        tester,
        controller: controller,
        passwordFocus: focus,
        normalFocus: normal,
      );
      await tester.showKeyboard(find.byKey(const ValueKey('normal')));
      await background(tester);
      expect(normal.hasFocus, true);
      expect(tester.testTextInput.hasAnyClients, true);
      expect(
        tester.testTextInput.setClientArgs!['enableIMEPersonalizedLearning'],
        true,
      );
      expect(controller.text, 'password stays local');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'ordinary wrapper field keeps its own input client in Android background',
    (tester) async {
      final controller = TextEditingController(text: 'ordinary input');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await screen(
        tester,
        controller: controller,
        passwordFocus: focus,
        secret: false,
      );
      await tester.showKeyboard(find.byKey(const ValueKey('credential')));
      await background(tester);
      expect(focus.hasFocus, true);
      expect(tester.testTextInput.hasAnyClients, true);
      expect(
        tester.testTextInput.setClientArgs!['enableIMEPersonalizedLearning'],
        true,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'iOS password keeps existing background autofill focus behavior',
    (tester) async {
      final controller = TextEditingController(text: 'synthetic-password');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await screen(tester, controller: controller, passwordFocus: focus);
      await tester.showKeyboard(find.byKey(const ValueKey('credential')));
      await background(tester);
      expect(focus.hasFocus, true);
      expect(tester.testTextInput.hasAnyClients, true);
      expect(
        tester.testTextInput.setClientArgs!['enableIMEPersonalizedLearning'],
        false,
      );
      expect(controller.text, 'synthetic-password');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'disabled revealed password releases input without changing its value or privacy',
    (tester) async {
      final controller = TextEditingController(text: 'synthetic-password');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await screen(tester, controller: controller, passwordFocus: focus);
      await tester.showKeyboard(find.byKey(const ValueKey('credential')));
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(
        tester.testTextInput.setClientArgs!['enableIMEPersonalizedLearning'],
        false,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .autofillHints,
        [AutofillHints.password],
      );
      await screen(
        tester,
        controller: controller,
        passwordFocus: focus,
        enabled: false,
      );
      await tester.pump();
      expect(focus.hasFocus, false);
      expect(tester.testTextInput.hasAnyClients, false);
      expect(controller.text, 'synthetic-password');
      await screen(tester, controller: controller, passwordFocus: focus);
      await tester.pump();
      expect(focus.hasFocus, false);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'preserved installation password uses private input and background cleanup',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preservedInstallationFilesProvider.overrideWithValue(
              Future.value(_EmptyFiles()),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PreservedInstallationFilesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      expect(editor.obscureText, true);
      expect(editor.autocorrect, false);
      expect(editor.enableSuggestions, false);
      expect(editor.enableIMEPersonalizedLearning, false);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.showKeyboard(field);
      await background(tester);
      expect(tester.testTextInput.hasAnyClients, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
