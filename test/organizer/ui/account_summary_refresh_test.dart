import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/onboarding/account_email_card.dart';
import 'package:kanban/organizer/presentation/shared/sharing_pending_invitations.dart';
import 'package:kanban/organizer/state/account_summary_refresh_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

class _SummaryController extends SharingUiController {
  _SummaryController()
    : super(initial: CollaborationState(session: sharingSession()));

  bool ready = false;
  int emailReads = 0, inboxReads = 0;
  Completer<void>? oldReads;

  @override
  Future<AccountStatus> accountStatus() async {
    emailReads++;
    final observedReady = ready;
    if (!observedReady) await oldReads?.future;
    return AccountStatus(
      email: observedReady ? 'verified@example.test' : null,
      emailVerified: observedReady,
      resetAvailable: false,
    );
  }

  @override
  Future<List<SharedInvitationPreview>> pendingInvitations() async {
    inboxReads++;
    final observedReady = ready;
    if (!observedReady) await oldReads?.future;
    if (!observedReady) {
      throw const CollaborationException('crypto_reconciliation_required');
    }
    return [];
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _SummaryController controller,
) async {
  final container = ProviderContainer(
    overrides: [
      collaborationProvider.overrideWith(() => controller),
      securePendingInvitationProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);
  await container.read(collaborationProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                AccountEmailCard(session: sharingSession()),
                SharingPendingInvitations(
                  session: sharingSession(),
                  supported: true,
                  onAccepted: (_) {},
                ),
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          body: TextButton(
                            onPressed: () {
                              controller.ready = true;
                              refreshAccountSummaries(
                                container,
                                partition: sharingSession().partition,
                                deviceId: sharingSession().deviceId,
                              );
                              Navigator.of(context).pop();
                            },
                            child: const Text('Completed protection'),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open protection'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets(
    'leaving protection without completion does not reload summaries',
    (tester) async {
      final controller = _SummaryController();
      await _pump(tester, controller);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open protection'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Completed protection'))).pop();
      await tester.pumpAndSettle();
      expect(controller.emailReads, 1);
      expect(controller.inboxReads, 1);
      expect(
        find.textContaining('Protection for the connected account'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'protection completion refreshes the mounted email and failed inbox once',
    (tester) async {
      final controller = _SummaryController();
      await _pump(tester, controller);
      await tester.pumpAndSettle();
      expect(find.text('No email address is set yet.'), findsOneWidget);
      expect(
        find.textContaining('Protection for the connected account'),
        findsOneWidget,
      );
      expect(controller.emailReads, 1);
      expect(controller.inboxReads, 1);
      final emailState = tester.state(find.byType(AccountEmailCard));

      await tester.tap(find.text('Open protection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed protection'));
      await tester.pumpAndSettle();

      expect(tester.state(find.byType(AccountEmailCard)), same(emailState));
      expect(find.text('verified@example.test'), findsOneWidget);
      expect(
        find.textContaining('Protection for the connected account'),
        findsNothing,
      );
      expect(find.text('Try again'), findsNothing);
      expect(controller.emailReads, 2);
      expect(controller.inboxReads, 2);
      // Ordinary collaboration rebuilds do not turn this into polling.
      controller.replace(controller.initial);
      await tester.pumpAndSettle();
      expect(controller.emailReads, 2);
      expect(controller.inboxReads, 2);
      expect(
        controller.calls,
        isEmpty,
        reason: 'No enrollment, FILE or mutation action',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('older in-flight summary results cannot replace the refresh', (
    tester,
  ) async {
    final controller = _SummaryController()..oldReads = Completer<void>();
    final container = await _pump(tester, controller);
    controller.ready = true;
    expect(
      refreshAccountSummaries(
        container,
        partition: sharingSession().partition,
        deviceId: sharingSession().deviceId,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.text('verified@example.test'), findsOneWidget);
    controller.oldReads!.complete();
    await tester.pumpAndSettle();
    expect(find.text('verified@example.test'), findsOneWidget);
    expect(
      find.textContaining('Protection for the connected account'),
      findsNothing,
    );
    expect(controller.emailReads, 2);
    expect(controller.inboxReads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completion from another account or device cannot refresh summaries',
    (tester) async {
      final controller = _SummaryController();
      final container = await _pump(tester, controller);
      await tester.pumpAndSettle();
      for (final identity in [
        (sharingSession(second: true).partition, sharingSession().deviceId),
        (sharingSession().partition, sharingSession(second: true).deviceId),
      ]) {
        expect(
          refreshAccountSummaries(
            container,
            partition: identity.$1,
            deviceId: identity.$2,
          ),
          isFalse,
        );
      }
      controller.replace(
        CollaborationState(session: sharingSession(second: true)),
      );
      expect(
        refreshAccountSummaries(
          container,
          partition: sharingSession().partition,
          deviceId: sharingSession().deviceId,
        ),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(controller.emailReads, 1);
      expect(controller.inboxReads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completion in another provider container cannot refresh these cards',
    (tester) async {
      final controller = _SummaryController();
      await _pump(tester, controller);
      await tester.pumpAndSettle();
      final otherController = _SummaryController();
      final other = ProviderContainer(
        overrides: [collaborationProvider.overrideWith(() => otherController)],
      );
      addTearDown(other.dispose);
      await other.read(collaborationProvider.future);
      expect(
        refreshAccountSummaries(
          other,
          partition: sharingSession().partition,
          deviceId: sharingSession().deviceId,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(controller.emailReads, 1);
      expect(controller.inboxReads, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
