import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_invitation_page.dart';
import 'package:kanban/organizer/presentation/shared/sharing_pending_invitations.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';

// Navigation/target-preparation seam only. CryptoInvitationPage is returned as
// though its separate signed acceptance/resume succeeded; no acceptance replay.
class _Directory implements AccountDirectoryRepository {
  @override
  DeviceSession get session => DeviceSession(sharingSession(), 'synthetic');
  @override
  bool Function() get isCurrent =>
      () => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Account implements AccountCryptoV2Workflow {
  @override
  final directory = _Directory();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Repository implements CollaborationRepository {
  @override
  Future<AccountCryptoV2Workflow> connectedCryptoAccount() async => _Account();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Controller extends SharingUiController {
  _Controller() {
    incomingInvitations = [
      SharedInvitationPreview(
        scopeName: 'Accepted target',
        scopeId: sharingScopeId,
        kind: SharedScopeKind.household,
        recipientUsername: 'recipient',
        inviterName: 'Inviter',
        invitationId: 'accepted27',
        contractVersion: 4,
        role: SharedRole.viewer,
        expiresAt: DateTime.utc(2099),
        registrationAllowed: false,
        requiresExplicitAcceptance: true,
      ),
    ];
  }
  final prepared = <String>[];
  final unrelated = Completer<void>();
  Object? prepareFailure;
  Completer<void>? prepareGate;
  @override
  Future<void> prepareAcceptedScope(String scope) async {
    prepared.add(scope);
    await prepareGate?.future;
    if (prepareFailure != null) throw prepareFailure!;
  }

  @override
  Future<void> syncNow() async {
    calls.add('background-demand');
    await unrelated.future;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Controller controller,
  List<String> accepted,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        collaborationRepositoryProvider.overrideWith(
          (ref) async => _Repository(),
        ),
        securePendingInvitationProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SharingPendingInvitations(
            session: sharingSession(),
            supported: true,
            onAccepted: accepted.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('accept-pending-accepted27')));
  await tester.pumpAndSettle();
  expect(find.byType(CryptoInvitationPage), findsOneWidget);
  Navigator.of(
    tester.element(find.byType(CryptoInvitationPage)),
  ).pop(sharingScopeId);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'pendingaccept27 target callback completes before unrelated sync and later failure stays contained',
    (tester) async {
      final controller = _Controller(), accepted = <String>[];
      await _pump(tester, controller, accepted);
      expect(controller.prepared, [sharingScopeId]);
      expect(accepted, [sharingScopeId]);
      expect(controller.state.valueOrNull?.selectedSpaceId, sharingScopeId);
      expect(controller.calls, contains('background-demand'));
      controller.unrelated.completeError(
        const CollaborationException('network'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pendingaccept27 unready target cannot select or report accepted',
    (tester) async {
      final controller = _Controller()
        ..prepareFailure = const CollaborationException(
          'crypto_reconciliation_required',
        );
      final accepted = <String>[];
      await _pump(tester, controller, accepted);
      expect(controller.prepared, [sharingScopeId]);
      expect(accepted, isEmpty);
      expect(controller.state.valueOrNull?.selectedSpaceId, isNull);
      expect(controller.calls, isNot(contains('background-demand')));
      expect(tester.takeException(), isNull);
    },
  );
}
