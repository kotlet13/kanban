import 'dart:async';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/onboarding/account_email_card.dart';
import 'sharing_ui_fixture.dart';
import 'onboarding_ui_test.dart' show pumpPanel;
import 'auth_feedback_ui_test.dart' show enterFields, submitForm;

class _Controller extends SharingUiController {
  _Controller()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          emailVerificationSupported: true,
        ),
      );
  int statusReads = 0;
  final confirm = Completer<AccountStatus>();
  @override
  Future<AccountStatus> accountStatus() async {
    statusReads++;
    return const AccountStatus(emailVerified: false, resetAvailable: false);
  }

  @override
  Future<AccountStatus> confirmEmailVerification(String token) =>
      confirm.future;
}

void main() {
  for (final switched in [false, true]) {
    testWidgets(
      'confirmation uses returned status without another read, switched=$switched',
      (tester) async {
        final controller = _Controller();
        await pumpPanel(
          tester,
          controller,
          AccountEmailCard(session: sharingSession()),
        );
        await tester.tap(find.text('Potrdi kodo iz e-pošte'));
        await tester.pumpAndSettle();
        await enterFields(tester, {'token': 'synthetic-token'});
        await submitForm(tester);
        await tester.pump();
        if (switched) {
          controller.switchAccount();
          await tester.pumpAndSettle();
        }
        controller.confirm.complete(
          const AccountStatus(
            email: 'verified@example.test',
            emailVerified: true,
            resetAvailable: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          controller.statusReads,
          1,
        ); // Initial mount only; confirm returned status.
        expect(
          find.text('verified@example.test'),
          switched ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('E-poštni naslov je potrjen.'),
          switched ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
