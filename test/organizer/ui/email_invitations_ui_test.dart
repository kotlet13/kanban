import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/app.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';
import 'sharing_ui_test.dart';

SharedInvitationPreview emailPreview() => SharedInvitationPreview(
  scopeName: 'Povabljeni dom',
  scopeId: sharingScopeId,
  kind: SharedScopeKind.household,
  recipientUsername: '',
  recipientEmail: 'recipient@example.test',
  inviterName: 'Povabitelj',
  invitationId: 'email-invite',
  contractVersion: 2,
  role: SharedRole.member,
  expiresAt: DateTime.utc(2099),
  registrationAllowed: false,
  requiresExplicitAcceptance: true,
);

Future<void> prepareInvite(WidgetTester tester) async {
  await openAccount(tester, width: 320);
  await tester.tap(find.widgetWithText(ChoiceChip, 'Imam povabilo'));
  await tester.pumpAndSettle();
  await enterSharing(tester, 'server', 'https://sharing.example.test');
  await enterSharing(tester, 'invitation-token', 'synthetic-email-token');
  await tapSharing(tester, 'sharing-preview-invite');
}

void main() {
  testWidgets(
    'email recipient chooses username, registers then explicitly accepts',
    (tester) async {
      final controller = SharingUiController(initial: CollaborationState())
        ..emailPreview = true;
      await pumpSharing(tester, controller, width: 320);
      await prepareInvite(tester);
      final username = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('sharing-username')),
          matching: find.byType(TextField),
        ),
      );
      expect(username.readOnly, false);
      expect(find.widgetWithText(ChoiceChip, 'Ustvari račun'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Ustvari račun'),
        findsOneWidget,
      );
      expect(find.text('Ustvari račun in sprejmi'), findsNothing);
      expect(find.text('Že imam račun'), findsOneWidget);
      await enterSharing(tester, 'username', 'chosen.username');
      await enterSharing(tester, 'display-name', 'Druga oseba');
      await enterSharing(tester, 'password', 'synthetic-password');
      await enterSharing(tester, 'confirm-password', 'synthetic-password');
      await tapSharing(tester, 'sharing-connect');
      expect(controller.registeredUsername, 'chosen.username');
      expect(controller.calls, isNot(contains('accept')));
      expect(controller.savedInvitation, isNotNull);
      expect(find.text('Povabil/a te je Povabitelj'), findsOneWidget);
      expect(
        find.text('Račun je ustvarjen. Prijavljen si kot second.'),
        findsOneWidget,
      );
      await tapSharing(tester, 'accept-pending-email-invite');
      expect(controller.calls, contains('accept'));
      expect(controller.state.requireValue.selectedSpaceId, sharingScopeId);
      expect(controller.savedInvitation, isNull);
      expect(
        find.text('Povabilo je sprejeto. Prostor je odprt.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing email recipient signs in without joining until acceptance',
    (tester) async {
      final controller = SharingUiController(initial: CollaborationState())
        ..emailPreview = true;
      await pumpSharing(tester, controller, width: 320);
      await prepareInvite(tester);
      await tapSharing(tester, 'sharing-existing-account');
      expect(find.byKey(const ValueKey('sharing-display-name')), findsNothing);
      await enterSharing(tester, 'username', 'first');
      await enterSharing(tester, 'password', 'synthetic-password');
      await tapSharing(tester, 'sharing-connect');
      expect(controller.loginAttempts, [null]);
      expect(controller.calls, isNot(contains('accept')));
      expect(
        find.byKey(const ValueKey('accept-pending-email-invite')),
        findsOneWidget,
      );
      expect(find.text('Prijavljen/a si kot first.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lost registration response changes to login while retaining invitation and username',
    (tester) async {
      final controller = SharingUiController(initial: CollaborationState())
        ..emailPreview = true
        ..invitationRegistrationError = const CollaborationException(
          'invitation_authentication_required',
        );
      await pumpSharing(tester, controller, width: 320);
      await prepareInvite(tester);
      await enterSharing(tester, 'username', 'chosen');
      await enterSharing(tester, 'display-name', 'Name');
      await enterSharing(tester, 'password', 'synthetic-password');
      await enterSharing(tester, 'confirm-password', 'synthetic-password');
      await tapSharing(tester, 'sharing-connect');
      expect(find.byKey(const ValueKey('sharing-display-name')), findsNothing);
      expect(controller.savedInvitation?.token, 'synthetic-email-token');
      expect(find.textContaining('račun že obstaja'), findsOneWidget);
      await tapSharing(tester, 'sharing-connect');
      expect(controller.loginAttempts, [null]);
      expect(controller.calls, isNot(contains('accept')));
      expect(
        find.byKey(const ValueKey('accept-pending-email-invite')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('signed-in email inbox invites need no pasted code', (
    tester,
  ) async {
    final controller = SharingUiController()
      ..incomingInvitations = [emailPreview()];
    await pumpSharing(tester, controller);
    await openAccount(tester);
    expect(find.text('Povabil/a te je Povabitelj'), findsOneWidget);
    expect(find.text('Povabilo za recipient@example.test'), findsOneWidget);
    await tapSharing(tester, 'accept-pending-email-invite');
    expect(controller.calls, contains('acceptPending:email-invite'));
    expect(controller.state.requireValue.selectedSpaceId, sharingScopeId);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expired saved invitation does not hide inbox and can be removed',
    (tester) async {
      final controller = SharingUiController()
        ..incomingInvitations = [emailPreview()]
        ..savedInvitation = const PendingInvitation(
          serverUrl: 'https://sharing.example.test',
          token: 'expired-test-token',
        )
        ..invitationPreviewError = const CollaborationException(
          'invitation_expired',
        );
      await pumpSharing(tester, controller);
      await openAccount(tester);
      expect(
        find.byKey(const ValueKey('accept-pending-email-invite')),
        findsOneWidget,
      );
      await tapSharing(tester, 'dismiss-saved-invitation');
      expect(controller.savedInvitation, isNull);
      expect(
        find.byKey(const ValueKey('accept-pending-email-invite')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unsupported server explains update instead of asking for username',
    (tester) async {
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
        ),
      );
      await pumpSharing(tester, controller, width: 320);
      await openMembers(tester);
      await tester.ensureVisible(find.text('Povabi osebo'));
      await tester.tap(find.text('Povabi osebo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Skrbnik mora nadgraditi FamilyHub'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sharing-recipient')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retrying a lost email-create response reuses its request id', (
    tester,
  ) async {
    final controller = SharingUiController()..loseEmailCreateResponse = true;
    await pumpSharing(tester, controller, width: 320);
    await openMembers(tester);
    await tester.ensureVisible(find.text('Povabi osebo'));
    await tester.tap(find.text('Povabi osebo'));
    await tester.pumpAndSettle();
    await enterSharing(tester, 'recipient', 'Recipient@Example.test');
    await tapSharing(tester, 'sharing-submit');
    expect(controller.emailInviteRequestIds, hasLength(1));
    expect(find.byKey(const ValueKey('sharing-recipient')), findsOneWidget);
    await tapSharing(tester, 'sharing-submit');
    expect(controller.emailInviteRequestIds, hasLength(2));
    expect(controller.emailInviteRequestIds.first, isNotNull);
    expect(controller.emailInviteRequestIds.toSet(), hasLength(1));
    expect(controller.calls, contains('emailInvite:recipient@example.test'));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'email invitation dialog remains accessible with keyboard at $width',
      (tester) async {
        final controller = SharingUiController();
        await pumpSharing(tester, controller, width: width);
        if (width < 900) {
          await openMembers(tester);
        } else {
          final container = ProviderScope.containerOf(
            tester.element(find.byType(KanbanApp)),
          );
          await container
              .read(collaborationProvider.notifier)
              .selectSpace(sharingScopeId);
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(ListTile, 'Nastavitve prostora'),
          );
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.text('Povabi osebo'));
        await tester.tap(find.text('Povabi osebo'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = FakeViewPadding(bottom: width < 900 ? 280 : 0);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await enterSharing(tester, 'recipient', 'recipient@example.test');
        await tapSharing(tester, 'sharing-submit');
        expect(
          controller.calls,
          contains('emailInvite:recipient@example.test'),
        );
        expect(
          find.textContaining('je pripravljeno za pošiljanje'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
