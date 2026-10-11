import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/onboarding/getting_started.dart';
import 'package:kanban/organizer/presentation/onboarding/private_sync_panel.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';
import 'package:kanban/organizer/presentation/onboarding/account_email_card.dart';
import 'package:kanban/organizer/presentation/shared/sharing_auth.dart';
import 'package:kanban/organizer/presentation/onboarding/account_recovery_actions.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';

Future<void> pumpPanel(
  WidgetTester tester,
  SharingUiController controller,
  Widget panel, {
  double width = 390,
  String language = 'sl',
  bool dark = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        securePendingInvitationProvider.overrideWith(
          (ref) async => controller.savedInvitation,
        ),
      ],
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: panel)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final language in ['sl', 'en']) {
      testWidgets(
        'setup choices fit $width $language and keep local available',
        (tester) async {
          await pumpPanel(
            tester,
            SharingUiController(initial: CollaborationState()),
            const GettingStartedChoices(),
            width: width,
            language: language,
            dark: language == 'en',
          );
          expect(find.byType(ListTile), findsNWidgets(3));
          expect(tester.takeException(), null);
        },
      );
    }
  }
  testWidgets(
    'private sync is not uploaded by login or viewing; explicit preview then confirmation required',
    (tester) async {
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          privateSync: const PrivateSyncState(available: true),
        ),
      );
      await pumpPanel(tester, controller, PrivateSyncPanel(onConnect: () {}));
      expect(controller.privatePreviewLoads, 0);
      expect(controller.privateEnabledRevision, null);
      await tester.tap(find.text('Preglej pred vključitvijo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.privatePreviewLoads, 1);
      expect(controller.privateEnabledRevision, null);
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.text('Vključi zasebno sinhronizacijo'));
      await tester.pumpAndSettle();
      expect(controller.privateEnabledRevision, 7);
    },
  );
  testWidgets(
    'switching accounts while private preview is open prevents upload',
    (tester) async {
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          privateSync: const PrivateSyncState(available: true),
        ),
      );
      await pumpPanel(tester, controller, PrivateSyncPanel(onConnect: () {}));
      await tester.tap(find.text('Preglej pred vključitvijo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(controller.privateEnabledRevision, null);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  for (final scheme in ['jivie', 'vsakdan']) {
    testWidgets(
      '$scheme invitation pasted into blank server field prepares correct source without joining',
      (tester) async {
        final controller = SharingUiController(initial: CollaborationState());
        await pumpPanel(
          tester,
          controller,
          SharingAuthPanel(
            onStart: () {},
            onConnected: () {},
            invitationMode: true,
          ),
        );
        final link = InvitationLink(
          serverUrl: 'https://invited.example.test/path',
          token: 'fhi1_${'a' * 64}',
        );
        await tester.enterText(
          find.byKey(const ValueKey('sharing-invitation-token')),
          link.toUri().replace(scheme: scheme).toString(),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('sharing-preview-invite')),
        );
        await tester.tap(find.byKey(const ValueKey('sharing-preview-invite')));
        await tester.pumpAndSettle();
        expect(controller.previewServer, link.serverUrl);
        expect(controller.previewToken, link.token);
        expect(find.text('Povabljeni dom'), findsOneWidget);
        expect(controller.registeredUsername, null);
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets(
    'first-account form validates matching password then enrolls without administrator credential',
    (tester) async {
      final controller = SharingUiController(initial: CollaborationState());
      await pumpPanel(
        tester,
        controller,
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showAccountEnrollment(context, ref),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      for (final pair in {
        'server': 'https://example.test',
        'code': 'one-use-code',
        'username': 'owner',
        'name': 'Ime',
        'password': 'long-password',
        'confirm': 'different',
      }.entries) {
        final field = find.byKey(ValueKey('sharing-${pair.key}')).last;
        await tester.ensureVisible(field);
        await tester.enterText(field, pair.value);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-submit')));
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(controller.calls, isEmpty);
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-confirm')));
      await tester.enterText(
        find.byKey(const ValueKey('sharing-confirm')),
        'long-password',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-submit')));
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(controller.calls, ['enroll:owner']);
    },
  );
  testWidgets(
    'anonymous recovery form closes after account changes without sending stale request',
    (tester) async {
      final controller = SharingUiController(initial: CollaborationState());
      await pumpPanel(
        tester,
        controller,
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showPasswordResetRequest(context, ref),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.calls, isEmpty);
    },
  );
  testWidgets(
    'first email verification is available even before reset is eligible',
    (tester) async {
      final controller = SharingUiController(
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
      final change = find.widgetWithText(
        TextButton,
        'Nastavi ali spremeni e-pošto',
      );
      expect(tester.widget<TextButton>(change).onPressed, isNotNull);
      await tester.tap(change);
      await tester.pumpAndSettle();
      for (final pair in {
        'email': 'owner@example.test',
        'password': 'password',
      }.entries) {
        final field = find.byKey(ValueKey('sharing-${pair.key}')).last;
        await tester.ensureVisible(field);
        await tester.enterText(field, pair.value);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-submit')));
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(controller.calls, ['email:owner@example.test']);
    },
  );
  testWidgets('password reset request stays generic and does not sign in', (
    tester,
  ) async {
    final controller = SharingUiController(initial: CollaborationState());
    await pumpPanel(
      tester,
      controller,
      Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => showPasswordResetRequest(context, ref),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final pair in {
      'server': 'https://example.test',
      'username': 'unknown',
    }.entries) {
      final field = find.byKey(ValueKey('sharing-${pair.key}')).last;
      await tester.ensureVisible(field);
      await tester.enterText(field, pair.value);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('sharing-submit')));
    await tester.tap(find.byKey(const ValueKey('sharing-submit')));
    await tester.pumpAndSettle();
    expect(controller.calls, ['resetRequested:unknown']);
    expect(controller.state.valueOrNull?.session, null);
  });
  testWidgets('known revoked session has no private upload or resume action', (
    tester,
  ) async {
    final controller = SharingUiController(
      initial: CollaborationState(
        session: sharingSession(),
        sessionInvalid: true,
        privateSync: const PrivateSyncState(
          available: true,
          enabled: true,
          paused: true,
        ),
      ),
    );
    await pumpPanel(tester, controller, PrivateSyncPanel(onConnect: () {}));
    expect(find.text('Preglej pred vključitvijo'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(controller.privatePreviewLoads, 0);
  });
  testWidgets(
    'personal financial conflict opens a readable own-entry comparison without account fields',
    (tester) async {
      final scope = SharedScope(
        id: sharingScopeId,
        name: 'Zasebno',
        kind: SharedScopeKind.personal,
        role: SharedRole.owner,
      );
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          privateSync: const PrivateSyncState(
            available: true,
            enabled: true,
            scopeId: sharingScopeId,
          ),
          scopes: [scope],
          financeSnapshotComplete: {sharingScopeId: true},
          financePolicies: {
            sharingScopeId: const SharedFinancePolicy(
              enabled: true,
              grant: SharedFinanceGrant.write,
            ),
          },
          financeConflicts: [
            SharedFinanceConflict(
              id: 'conflict',
              scopeId: sharingScopeId,
              recordId: 'entry',
              recordType: SharedFinanceRecordType.personalFinanceEntry,
              reason: 'conflict',
              localPayload: {
                'title': 'Moj osebni strošek',
                'amountMinor': 120,
                'currency': 'EUR',
                'kind': 'expense',
                'occurredAt': '2026-10-05T10:00:00Z',
              },
              remotePayload: {
                'title': 'Strežniški osebni strošek',
                'amountMinor': 150,
                'currency': 'EUR',
                'kind': 'expense',
                'occurredAt': '2026-10-05T10:00:00Z',
              },
            ),
          ],
        ),
      );
      await pumpPanel(tester, controller, PrivateSyncPanel(onConnect: () {}));
      final privateStatus = find.byKey(const ValueKey('private-sync-status'));
      await tester.tap(
        find.descendant(
          of: privateStatus,
          matching: find.byKey(const ValueKey('sharing-sync-status-cloud')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sporne finančne spremembe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Na tej napravi'));
      await tester.pumpAndSettle();
      expect(find.text('Moj osebni strošek'), findsOneWidget);
      expect(find.textContaining('accountId'), findsNothing);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'first-account flow forwards the explicitly checked loopback development connection',
    (tester) async {
      final controller = SharingUiController(initial: CollaborationState());
      await pumpPanel(
        tester,
        controller,
        SharingAuthPanel(
          onStart: () {},
          onConnected: () {},
          initialServer: 'http://127.0.0.1:18770',
        ),
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Prvi račun s kodo'));
      await tester.tap(find.text('Prvi račun s kodo'));
      await tester.pumpAndSettle();
      for (final pair in {
        'code': 'one-use-code',
        'username': 'owner',
        'name': 'Ime',
        'password': 'long-password',
        'confirm': 'long-password',
      }.entries) {
        final field = find.byKey(ValueKey('sharing-${pair.key}')).last;
        await tester.ensureVisible(field);
        await tester.enterText(field, pair.value);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-submit')));
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(controller.enrollmentAllowLocalHttp, true);
    },
  );
}
