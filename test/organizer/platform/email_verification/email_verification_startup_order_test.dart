import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/platform/email_verification/email_verification_link.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_coordinator.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_startup.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../../ui/sharing_ui_fixture.dart';

class _Links implements InvitationLinkSource {
  _Links(this.uri);
  final Uri uri;
  final stream = StreamController<Uri>.broadcast();
  @override
  Future<Uri?> initialLink() async => uri;
  @override
  Stream<Uri> get links => stream.stream;
}

void main() {
  testWidgets(
    'cold email review waits above delayed required setup and preserves saved invitation',
    (tester) async {
      final session = sharingSession();
      final controller = SharingUiController(
        initial: CollaborationState(session: session),
      );
      final setup = Completer<AccountCryptoStartupAction?>();
      final key = GlobalKey<NavigatorState>();
      final source = _Links(
        EmailVerificationLink(
          serverUrl: session.serverUrl,
          serverId: session.serverId,
          accountId: session.accountId,
          email: 'target@example.test',
          token: 'fhv1_${'a' * 64}',
        ).toUri(),
      );
      final invitations = MemoryPendingInvitationStore();
      final token = 'fhi2_${'b' * 64}';
      await invitations.write(
        PendingInvitation(serverUrl: session.serverUrl, token: token),
      );
      final container = ProviderContainer(
        overrides: [
          collaborationProvider.overrideWith(() => controller),
          invitationLinkSourceProvider.overrideWithValue(source),
          pendingInvitationStoreProvider.overrideWithValue(invitations),
          accountCryptoStartupActionProvider.overrideWith(
            (ref) => setup.future,
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(source.stream.close);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: key,
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) =>
                InvitationLinkCoordinator(navigatorKey: key, child: child!),
            home: const AccountCryptoStartupCoordinator(
              child: Scaffold(body: Text('home')),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Potrdi e-pošto'), findsNothing);
      setup.complete(
        AccountCryptoStartupAction(
          identity: '${session.partition}:${session.deviceId}',
          builder: (_) => const Scaffold(body: Text('required setup retained')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('target@example.test'), findsOneWidget);
      expect((await invitations.read())?.token, token);
      expect(container.read(pendingInvitationLinkProvider)?.token, token);
      expect(container.read(invitationLinkErrorProvider), isFalse);
      await tester.tap(find.text('Zapri'));
      await tester.pumpAndSettle();
      expect(find.text('required setup retained'), findsOneWidget);
      expect(
        container.read(collaborationProvider).valueOrNull?.session?.accountId,
        session.accountId,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
