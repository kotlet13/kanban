import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/onboarding/account_email_card.dart';
import 'package:kanban/organizer/presentation/shared/sharing_account_page.dart';
import 'package:kanban/organizer/presentation/shared/sharing_auth.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

class FeedbackController extends SharingUiController {
  FeedbackController({super.initial});
  Object? enrollmentError, verificationError, registrationError;
  Completer<void>? enrollmentSync, verification;
  bool verified = false;
  int statusLoads = 0;

  @override
  Future<AccountStatus> accountStatus() async {
    statusLoads++;
    return AccountStatus(
      email: verified ? 'first@example.test' : null,
      pendingEmail: verified ? null : 'first@example.test',
      emailVerified: verified,
      resetAvailable: verified,
    );
  }

  @override
  Future<void> confirmEmailVerification(String token) async {
    calls.add('confirm:$token');
    await verification?.future;
    if (verificationError != null) throw verificationError!;
    verified = true;
  }

  @override
  Future<void> enroll({
    required String serverUrl,
    required String code,
    required String username,
    required String password,
    required String name,
    String deviceName = 'Jivie',
    bool allowLocalHttp = false,
  }) async {
    calls.add('enroll:$username');
    replace(CollaborationState());
    if (enrollmentError != null) throw enrollmentError!;
    final enrolledSession = sharingSession();
    replace(CollaborationState(session: enrolledSession));
    await enrollmentSync?.future;
    if (state.valueOrNull?.session?.deviceId != enrolledSession.deviceId) {
      throw const CollaborationException('session_changed');
    }
  }

  @override
  Future<void> registerWithInvitation({
    required String serverUrl,
    required String invitationToken,
    required String username,
    required String name,
    required String password,
    bool allowLocalHttp = false,
    String deviceName = 'Jivie',
  }) async {
    if (registrationError != null) throw registrationError!;
    await super.registerWithInvitation(
      serverUrl: serverUrl,
      invitationToken: invitationToken,
      username: username,
      name: name,
      password: password,
      allowLocalHttp: allowLocalHttp,
      deviceName: deviceName,
    );
  }
}

Future<void> enterFields(
  WidgetTester tester,
  Map<String, String> values,
) async {
  for (final pair in values.entries) {
    expect(
      find.byKey(ValueKey('sharing-${pair.key}')),
      findsWidgets,
      reason: pair.key,
    );
    final field = find.byKey(ValueKey('sharing-${pair.key}')).last;
    await tester.ensureVisible(field);
    await tester.enterText(field, pair.value);
  }
}

Future<void> submitForm(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('sharing-submit'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
}

Future<void> enrollFirst(WidgetTester tester, {String language = 'sl'}) async {
  final open = find.text(
    language == 'sl' ? 'Prvi račun s kodo' : 'First account with a code',
  );
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  await enterFields(tester, {
    'server': 'https://sharing.example.test',
    'code': 'one-use-code',
    'username': 'first',
    'name': 'Prva oseba',
    'password': 'long-password',
    'confirm': 'long-password',
  });
  await submitForm(tester);
}

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final language in ['sl', 'en']) {
      testWidgets(
        'enrollment confirms saved sign-in and opens account overview $width $language',
        (tester) async {
          final controller = FeedbackController(initial: CollaborationState());
          await pumpPanel(
            tester,
            controller,
            SharingAccountPage(onScopeSelected: (_) {}),
            width: width,
            language: language,
          );
          await enrollFirst(tester, language: language);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(SharingAuthPanel), findsNothing);
          expect(find.text('https://sharing.example.test'), findsOneWidget);
          expect(
            find.text(
              language == 'sl'
                  ? 'Račun je ustvarjen. Prijavljen si kot first.'
                  : 'Your account is created. You are signed in as first.',
            ),
            findsOneWidget,
          );
          expect(controller.calls, ['enroll:first']);
          expect(controller.privateEnabledRevision, null);
          expect(controller.state.valueOrNull!.privateSync.enabled, false);
          expect(tester.takeException(), null);
        },
      );
    }
  }

  testWidgets(
    'enrollment waits initial sync after saved-session boundary closes',
    (tester) async {
      final controller = FeedbackController(initial: CollaborationState())
        ..enrollmentSync = Completer<void>();
      await pumpPanel(
        tester,
        controller,
        SharingAccountPage(onScopeSelected: (_) {}),
      );
      await enrollFirst(tester);
      await tester.pump();
      expect(find.textContaining('Seja je potekla.'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      controller.enrollmentSync!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SharingAuthPanel), findsNothing);
      expect(
        find.text('Račun je ustvarjen. Prijavljen si kot first.'),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
    },
  );

  testWidgets('account switch during enrollment sync has no stale success', (
    tester,
  ) async {
    final controller = FeedbackController(initial: CollaborationState())
      ..enrollmentSync = Completer<void>();
    await pumpPanel(
      tester,
      controller,
      SharingAccountPage(onScopeSelected: (_) {}),
    );
    await enrollFirst(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    controller.switchAccount();
    controller.enrollmentSync!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(controller.state.valueOrNull?.session?.username, 'second');
    expect(tester.takeException(), null);
  });

  testWidgets('created account with failed session save opens ordinary login', (
    tester,
  ) async {
    final controller = FeedbackController(initial: CollaborationState())
      ..enrollmentError = const CollaborationException(
        'account_created_session_not_saved',
      );
    int connected = 0;
    await pumpPanel(
      tester,
      controller,
      SharingAuthPanel(onStart: () {}, onConnected: () => connected++),
    );
    await enrollFirst(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('sharing-code')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('sharing-username')))
          .controller!
          .text,
      'first',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('sharing-password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      find.textContaining('Začetne kode ali povabila ne uporabi znova.'),
      findsWidgets,
    );
    expect(connected, 0);
    await enterFields(tester, {'password': 'long-password'});
    await tester.ensureVisible(find.byKey(const ValueKey('sharing-connect')));
    await tester.tap(find.byKey(const ValueKey('sharing-connect')));
    await tester.pumpAndSettle();
    expect(controller.calls, ['enroll:first']);
    expect(controller.loginAttempts, [null]);
    expect(connected, 1);
    expect(tester.takeException(), null);
  });

  testWidgets(
    'created account failure still guides login after previous account is cleared',
    (tester) async {
      final controller =
          FeedbackController(
              initial: CollaborationState(
                session: sharingSession(second: true),
              ),
            )
            ..enrollmentError = const CollaborationException(
              'account_created_session_not_saved',
            );
      await pumpPanel(
        tester,
        controller,
        Consumer(
          builder: (context, ref, _) {
            ref.watch(collaborationProvider);
            return SharingAuthPanel(onStart: () {}, onConnected: () {});
          },
        ),
      );
      await enrollFirst(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.textContaining('Začetne kode ali povabila ne uporabi znova.'),
        findsWidgets,
      );
      expect(controller.state.valueOrNull?.session, null);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('sharing-username')),
            )
            .controller!
            .text,
        'first',
      );
      expect(tester.takeException(), null);
    },
  );

  testWidgets('invalid enrollment code keeps form without success or login', (
    tester,
  ) async {
    final controller = FeedbackController(initial: CollaborationState())
      ..enrollmentError = const CollaborationException('bootstrap_invalid');
    await pumpPanel(
      tester,
      controller,
      SharingAuthPanel(onStart: () {}, onConnected: () {}),
    );
    await enrollFirst(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(controller.state.valueOrNull?.session, null);
    expect(controller.loginAttempts, isEmpty);
    expect(tester.takeException(), null);
  });

  for (final failed in [false, true]) {
    testWidgets(
      'invitation registration handles saved-session failure=$failed',
      (tester) async {
        final controller = FeedbackController(initial: CollaborationState());
        if (failed) {
          controller.registrationError = const CollaborationException(
            'account_created_session_not_saved',
          );
        }
        int connected = 0;
        await pumpPanel(
          tester,
          controller,
          SharingAuthPanel(
            onStart: () {},
            onConnected: () => connected++,
            invitationMode: true,
            initialServer: 'https://sharing.example.test',
            initialToken: 'invitation-token',
          ),
        );
        await tester.tap(find.byKey(const ValueKey('sharing-preview-invite')));
        await tester.pumpAndSettle();
        await enterFields(tester, {
          'display-name': 'Druga oseba',
          'password': 'long-password',
          'confirm-password': 'long-password',
        });
        final connect = find.byKey(const ValueKey('sharing-connect'));
        await tester.ensureVisible(connect);
        await tester.tap(connect);
        await tester.pumpAndSettle();
        if (failed) {
          expect(connected, 0);
          expect(
            find.byKey(const ValueKey('sharing-invitation-token')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('sharing-confirm-password')),
            findsNothing,
          );
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(const ValueKey('sharing-username')),
                )
                .controller!
                .text,
            'second',
          );
          expect(
            find.textContaining('Začetne kode ali povabila ne uporabi znova.'),
            findsOneWidget,
          );
        } else {
          expect(connected, 1);
          expect(
            find.text('Račun je ustvarjen. Prijavljen si kot second.'),
            findsOneWidget,
          );
          expect(controller.privateEnabledRevision, null);
        }
        expect(tester.takeException(), null);
      },
    );
  }

  for (final failed in [false, true]) {
    testWidgets('email confirmation feedback reflects server success=$failed', (
      tester,
    ) async {
      final controller = FeedbackController(
        initial: CollaborationState(
          session: sharingSession(),
          emailVerificationSupported: true,
        ),
      )..verification = Completer<void>();
      if (failed) {
        controller.verificationError = const CollaborationException(
          'account_token_invalid',
        );
      }
      await pumpPanel(
        tester,
        controller,
        AccountEmailCard(session: sharingSession()),
      );
      await tester.tap(find.text('Potrdi kodo iz e-pošte'));
      await tester.pumpAndSettle();
      await enterFields(tester, {'token': 'email-code'});
      await submitForm(tester);
      await tester.pump();
      expect(find.text('E-poštni naslov je potrjen.'), findsNothing);
      controller.verification!.complete();
      await tester.pumpAndSettle();
      if (failed) {
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('E-poštni naslov je potrjen.'), findsNothing);
        expect(find.text('Potrjen naslov'), findsNothing);
        expect(controller.statusLoads, 1);
      } else {
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('E-poštni naslov je potrjen.'), findsOneWidget);
        expect(find.text('Potrjen naslov'), findsOneWidget);
        expect(find.text('first@example.test'), findsOneWidget);
        expect(find.text('Naslov še ni potrjen'), findsNothing);
        expect(controller.statusLoads, 2);
      }
      expect(tester.takeException(), null);
    });
  }

  testWidgets('email request does not claim verification', (tester) async {
    final controller = FeedbackController(
      initial: CollaborationState(
        session: sharingSession(),
        emailVerificationSupported: true,
      ),
    );
    await pumpPanel(
      tester,
      controller,
      AccountEmailCard(session: sharingSession()),
    );
    await tester.tap(find.text('Nastavi ali spremeni e-pošto'));
    await tester.pumpAndSettle();
    await enterFields(tester, {
      'email': 'first@example.test',
      'password': 'long-password',
    });
    await submitForm(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Potrditvena koda je zahtevana.'),
      findsOneWidget,
    );
    expect(find.text('E-poštni naslov je potrjen.'), findsNothing);
    expect(find.text('Naslov še ni potrjen'), findsOneWidget);
  });

  testWidgets('late email confirmation after account switch has no success', (
    tester,
  ) async {
    final controller = FeedbackController(
      initial: CollaborationState(
        session: sharingSession(),
        emailVerificationSupported: true,
      ),
    )..verification = Completer<void>();
    await pumpPanel(
      tester,
      controller,
      AccountEmailCard(session: sharingSession()),
    );
    await tester.tap(find.text('Potrdi kodo iz e-pošte'));
    await tester.pumpAndSettle();
    await enterFields(tester, {'token': 'email-code'});
    await submitForm(tester);
    await tester.pump();
    controller.switchAccount();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    controller.verification!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('E-poštni naslov je potrjen.'), findsNothing);
    expect(controller.statusLoads, 1);
    expect(tester.takeException(), null);
  });

  testWidgets('cancelling email code has no feedback or refresh', (
    tester,
  ) async {
    final controller = FeedbackController(
      initial: CollaborationState(
        session: sharingSession(),
        emailVerificationSupported: true,
      ),
    );
    await pumpPanel(
      tester,
      controller,
      AccountEmailCard(session: sharingSession()),
    );
    await tester.tap(find.text('Potrdi kodo iz e-pošte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prekliči'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(controller.calls, isEmpty);
    expect(controller.statusLoads, 1);
  });

  testWidgets(
    'verified email feedback and refreshed state fit English desktop',
    (tester) async {
      final controller = FeedbackController(
        initial: CollaborationState(
          session: sharingSession(),
          emailVerificationSupported: true,
        ),
      );
      await pumpPanel(
        tester,
        controller,
        AccountEmailCard(session: sharingSession()),
        width: 1440,
        language: 'en',
      );
      await tester.tap(find.text('Confirm email code'));
      await tester.pumpAndSettle();
      await enterFields(tester, {'token': 'email-code'});
      await submitForm(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Your email address is verified.'), findsOneWidget);
      expect(find.text('Verified address'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );

  testWidgets('revoked session does not claim it will renew automatically', (
    tester,
  ) async {
    final controller = FeedbackController(
      initial: CollaborationState(
        session: sharingSession(),
        sessionRenewalSupported: true,
        sessionInvalid: true,
      ),
    );
    await pumpPanel(
      tester,
      controller,
      SharingAccountPage(onScopeSelected: (_) {}),
    );
    expect(
      find.text('Prijava na tej napravi se ob uporabi samodejno podaljšuje.'),
      findsNothing,
    );
  });

  for (final supported in [false, true]) {
    testWidgets('session renewal claim requires capability=$supported', (
      tester,
    ) async {
      final controller = FeedbackController(
        initial: CollaborationState(
          session: sharingSession(),
          sessionRenewalSupported: supported,
        ),
      );
      await pumpPanel(
        tester,
        controller,
        SharingAccountPage(onScopeSelected: (_) {}),
      );
      expect(
        find.text('Prijava na tej napravi se ob uporabi samodejno podaljšuje.'),
        supported ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('Seja velja do'),
        supported ? findsNothing : findsOneWidget,
      );
      expect(controller.privateEnabledRevision, null);
      expect(tester.takeException(), null);
    });
  }
}
