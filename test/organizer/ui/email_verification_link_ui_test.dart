import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/platform/email_verification/email_verification_link.dart';
import 'package:kanban/organizer/platform/email_verification/email_verification_link_review.dart';
import 'package:kanban/organizer/presentation/onboarding/account_email_card.dart';
import 'sharing_ui_fixture.dart';
import 'onboarding_ui_test.dart' show pumpPanel;

class _Controller extends SharingUiController {
  _Controller()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          emailVerificationSupported: true,
        ),
      );
  int reads = 0, confirmations = 0;
  AccountStatus status = const AccountStatus(
    emailVerified: false,
    resetAvailable: false,
    pendingEmail: 'target@example.test',
  );
  @override
  Future<AccountStatus> accountStatus() async {
    reads++;
    return status;
  }

  @override
  Future<AccountStatus> confirmEmailVerificationLink(
    String token, {
    required String accountId,
    required String serverId,
    required String email,
  }) async {
    confirmations++;
    expect(accountId, sharingSession().accountId);
    expect(serverId, sharingSession().serverId);
    expect(email, 'target@example.test');
    return const AccountStatus(
      email: 'target@example.test',
      emailVerified: true,
      resetAvailable: true,
    );
  }
}

EmailVerificationLink link({bool foreign = false}) => EmailVerificationLink(
  serverUrl: sharingSession().serverUrl,
  serverId: sharingSession().serverId,
  accountId: foreign
      ? sharingSession(second: true).accountId
      : sharingSession().accountId,
  email: 'target@example.test',
  token: 'fhv1_${'a' * 64}',
);

void main() {
  testWidgets(
    'pending email primary confirmation becomes verified without wizard reset',
    (tester) async {
      final controller = _Controller();
      final reported = <AccountStatus?>[];
      await pumpPanel(
        tester,
        controller,
        AccountEmailCard(
          session: sharingSession(),
          onStatusChanged: reported.add,
        ),
      );
      expect(
        find.widgetWithText(FilledButton, 'Potrdi e-pošto'),
        findsOneWidget,
      );
      expect(reported.last?.emailVerified, isFalse);
      controller.status = const AccountStatus(
        email: 'target@example.test',
        emailVerified: true,
        resetAvailable: true,
      );
      await tester.tap(find.text('Preveri potrditev e-pošte'));
      await tester.pumpAndSettle();
      expect(find.text('Potrjen naslov'), findsOneWidget);
      expect(find.text('Potrdi e-pošto'), findsNothing);
      expect(reported.last?.emailVerified, isTrue);
      expect(controller.reads, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pending checks pause in background and resume fresh with same card',
    (tester) async {
      final controller = _Controller();
      await pumpPanel(
        tester,
        controller,
        AccountEmailCard(session: sharingSession()),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 40));
      expect(controller.reads, 1);
      controller.status = const AccountStatus(
        email: 'target@example.test',
        emailVerified: true,
        resetAvailable: true,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.reads, 2);
      expect(find.text('Potrjen naslov'), findsOneWidget);
      await tester.pump(const Duration(seconds: 35));
      expect(controller.reads, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('link review sends no confirmation before explicit action', (
    tester,
  ) async {
    final controller = _Controller();
    await pumpPanel(
      tester,
      controller,
      EmailVerificationLinkReview(link: link()),
    );
    expect(controller.confirmations, 0);
    expect(controller.reads, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Potrdi e-pošto'));
    await tester.pumpAndSettle();
    expect(controller.confirmations, 1);
    expect(find.text('E-poštni naslov je potrjen.'), findsOneWidget);
    expect(controller.initial.session?.accountId, sharingSession().accountId);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('foreign email link offers no confirmation or account switch', (
    tester,
  ) async {
    final controller = _Controller();
    await pumpPanel(
      tester,
      controller,
      EmailVerificationLinkReview(link: link(foreign: true)),
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('drugemu računu'), findsOneWidget);
    expect(controller.confirmations, 0);
    expect(controller.initial.session?.accountId, sharingSession().accountId);
    await tester.pumpWidget(const SizedBox());
  });
}
