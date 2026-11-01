import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/onboarding/account_password_card.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

class PasswordUiController extends SharingUiController {
  PasswordUiController({bool supported = true})
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          passwordChangeSupported: supported,
          resetSupported: true,
        ),
      );
  int changes = 0, requests = 0, resets = 0;
  String? currentPassword, newPassword, otp;
  String? failure;
  Completer<void>? pending;
  @override
  Future<void> changeAccountPassword({
    required String currentPassword,
    required String newPassword,
    String? otp,
  }) async {
    changes++;
    this.currentPassword = currentPassword;
    this.newPassword = newPassword;
    this.otp = otp;
    await pending?.future;
    if (failure != null) throw CollaborationException(failure!);
  }

  @override
  Future<void> requestSignedInPasswordReset({String language = 'sl'}) async {
    requests++;
  }

  @override
  Future<void> confirmSignedInPasswordReset({
    required String token,
    required String password,
    String? otp,
  }) async {
    resets++;
    replace(
      CollaborationState(
        session: initial.session,
        sessionInvalid: true,
        passwordChangeSupported: true,
        resetSupported: true,
      ),
    );
  }
}

Future<void> openChange(
  WidgetTester tester,
  PasswordUiController c, {
  String language = 'sl',
}) async {
  await pumpPanel(
    tester,
    c,
    AccountPasswordCard(session: c.initial.session!),
    language: language,
  );
  await tester.tap(
    find.widgetWithText(
      FilledButton,
      language == 'sl' ? 'Spremeni geslo' : 'Change password',
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fill(
  WidgetTester tester, {
  String confirm = ' new password 123 ',
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), ' old password ');
  await tester.enterText(fields.at(1), ' new password 123 ');
  await tester.enterText(fields.at(2), confirm);
  await tester.enterText(fields.at(3), '123456');
}

Future<void> submit(WidgetTester tester, String label) async {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, label),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'direct change validates confirmation then forwards literal passwords without account setup',
    (tester) async {
      final c = PasswordUiController();
      await openChange(tester, c);
      await fill(tester, confirm: 'different');
      await submit(tester, 'Spremeni geslo');
      expect(c.changes, 0);
      await tester.enterText(
        find.byType(TextFormField).at(2),
        ' new password 123 ',
      );
      await submit(tester, 'Spremeni geslo');
      expect(c.changes, 1);
      expect(c.currentPassword, ' old password ');
      expect(c.newPassword, ' new password 123 ');
      expect(c.otp, '123456');
      expect(c.requests, 0);
      expect(c.resets, 0);
      expect(
        find.text('Geslo je spremenjeno. Ta naprava ostane prijavljena.'),
        findsOneWidget,
      );
      expect(c.state.requireValue.session!.deviceId, sharingSession().deviceId);
    },
  );
  testWidgets(
    'step-up failure stays in form and keeps current session in English',
    (tester) async {
      final c = PasswordUiController()..failure = 'invalid_credentials';
      await openChange(tester, c, language: 'en');
      await fill(tester);
      await submit(tester, 'Change password');
      expect(
        find.text(
          'The current password or two-factor code is incorrect. Your session stays active.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(c.state.requireValue.session, isNotNull);
    },
  );
  testWidgets(
    'lost response explains uncertainty and never automatically retries password change',
    (tester) async {
      final c = PasswordUiController()..failure = 'network';
      await openChange(tester, c);
      await fill(tester);
      await submit(tester, 'Spremeni geslo');
      expect(
        find.textContaining('Geslo je morda že spremenjeno.'),
        findsOneWidget,
      );
      expect(c.changes, 1);
      expect(c.state.requireValue.session, isNotNull);
    },
  );
  testWidgets('old server renders immediate graceful unsupported option', (
    tester,
  ) async {
    final c = PasswordUiController(supported: false);
    await pumpPanel(
      tester,
      c,
      AccountPasswordCard(session: c.initial.session!),
    );
    expect(
      find.textContaining('potrebna posodobitev strežnika'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Spremeni geslo'),
    );
    expect(button.onPressed, isNull);
    expect(c.changes, 0);
  });
  testWidgets(
    'email reset confirmation warns all sessions and fixes account without server username inputs',
    (tester) async {
      final c = PasswordUiController();
      await pumpPanel(
        tester,
        c,
        AccountPasswordCard(session: c.initial.session!),
      );
      await tester.tap(
        find.widgetWithText(TextButton, 'Pozabljeno geslo? Pošlji e-pošto'),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('odjavi vse naprave, tudi to'),
        ),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(c.requests, 0);
      final buttons = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      );
      await tester.tap(buttons.last);
      await tester.pumpAndSettle();
      expect(c.requests, 1);
      expect(c.resets, 0);
    },
  );
  testWidgets(
    'account switch closes password form before credentials can be submitted',
    (tester) async {
      final c = PasswordUiController();
      await openChange(tester, c);
      await fill(tester);
      c.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.changes, 0);
    },
  );
  testWidgets(
    'confirmed email reset disables password actions and exposes sign-in without clearing account',
    (tester) async {
      final c = PasswordUiController();
      bool signIn = false;
      await pumpPanel(
        tester,
        c,
        AccountPasswordCard(
          session: c.initial.session!,
          onSignIn: () => signIn = true,
        ),
      );
      // The reset action is the final text button before the modal opens.
      final action = find.byType(TextButton).last;
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'same-account-code',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'new password 123',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'new password 123',
      );
      final submitButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();
      expect(c.resets, 1);
      expect(c.state.requireValue.sessionInvalid, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Spremeni geslo'),
            )
            .onPressed,
        isNull,
      );
      final login = find.widgetWithText(TextButton, 'Prijavi se');
      await tester.ensureVisible(login);
      await tester.tap(login);
      await tester.pump();
      expect(signIn, isTrue);
      expect(c.state.requireValue.session, isNotNull);
    },
  );
}
