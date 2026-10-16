import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/shared/sharing_account_page.dart';
import 'package:kanban/organizer/presentation/shared/invitation_wizard.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/presentation/shared/sharing_pending_invitations.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'local_spaces_navigation_test.dart'
    show LocalSpaceUiController, loadCaptureFonts;
import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';

const _scope = SharedScope(
  id: sharingScopeId,
  name: 'Naš skupni dom',
  kind: SharedScopeKind.household,
  role: SharedRole.owner,
  accessPolicyVersion: 3,
);

class _ShellController extends SharingUiController {
  _ShellController({bool local = false, SharedRole role = SharedRole.owner})
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          selectedSpaceId: local ? null : sharingScopeId,
          scopes: local
              ? []
              : [
                  SharedScope(
                    id: _scope.id,
                    name: _scope.name,
                    kind: _scope.kind,
                    role: role,
                    accessPolicyVersion: 3,
                  ),
                ],
          emailInvitationsSupported: true,
          scopedInvitationsSupported: true,
          spaceProjectMembershipSupported: true,
        ),
      );
  List<String>? publicationTargets;
  int publications = 0;
  @override
  Future<SharedInvitation> createRecipientInvitation({
    required String scopeId,
    required String recipient,
    SharedRole role = SharedRole.member,
    String language = 'sl',
    String? requestId,
    String? accessScope,
  }) => super.createEmailInvitation(
    scopeId: scopeId,
    recipientEmail: recipient,
    role: role,
    language: language,
    requestId: requestId,
    accessScope: accessScope,
  );

  @override
  Future<LocalSpacesPublicationPreview> previewLocalSpacesPublication(
    List<String> ids,
  ) async {
    publicationTargets = ids;
    return LocalSpacesPublicationPreview(
      partition: sharingSession().partition,
      serverUrl: sharingSession().serverUrl,
      accountName: 'Prva oseba',
      fingerprint: 'qa',
      spaces: [
        const LocalSpacePublicationItem(
          space: LocalSpace(
            id: 'qa-household',
            name: 'Lokalni dom',
            kind: LocalSpaceKind.household,
          ),
          recordCount: 2,
          gardenCount: 0,
        ),
      ],
    );
  }

  @override
  Future<void> publishLocalSpaces(LocalSpacesPublicationPreview preview) async {
    publications++;
    state = AsyncData(
      CollaborationState(
        session: sharingSession(),
        scopes: [
          const SharedScope(
            id: 'qa-household',
            name: 'Lokalni dom',
            kind: SharedScopeKind.household,
            role: SharedRole.owner,
            accessPolicyVersion: 3,
          ),
        ],
        emailInvitationsSupported: true,
        scopedInvitationsSupported: true,
        spaceProjectMembershipSupported: true,
      ),
    );
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['JIVIE_UI_CAPTURE'] != '1') return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/qa/invitation-simplification');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final local in [false, true]) {
    testWidgets('Utrip opens received invitations directly local=$local', (
      tester,
    ) async {
      final controller = _ShellController(local: local)
        ..incomingInvitations = [
          SharedInvitationPreview(
            scopeName: 'Povabljeni prostor',
            scopeId: sharingScopeId,
            kind: SharedScopeKind.household,
            recipientUsername: 'first',
            inviterName: 'Povabitelj',
            invitationId: 'notice-test',
            contractVersion: 3,
            accessScope: 'space',
            role: SharedRole.viewer,
            expiresAt: DateTime.utc(2099),
            registrationAllowed: false,
            requiresExplicitAcceptance: true,
          ),
        ];
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: controller,
        localSpacesController: LocalSpaceUiController(LocalSpaceKind.personal),
        repaintBoundaryKey: GlobalKey(),
      );
      await tester.tap(
        find.byKey(const ValueKey('received-invitation-notice')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SharingPendingInvitations), findsOneWidget);
      expect(find.byType(SharingAccountPage), findsNothing);
      expect(find.textContaining('Povabljeni prostor'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'first launch opens invitation directly without setup or account page',
    (tester) async {
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: SharingUiController(
          initial: CollaborationState(),
        ),
        localSpacesController: LocalSpaceUiController(LocalSpaceKind.personal),
        repaintBoundaryKey: GlobalKey(),
      );
      final invitation = find.byKey(const ValueKey('first-launch-invitation'));
      await tester.ensureVisible(invitation);
      await tester.tap(invitation);
      await tester.pumpAndSettle();
      expect(find.byType(InvitationWizard), findsOneWidget);
      expect(find.byType(SharingAccountPage), findsNothing);
      expect(
        find.byKey(const ValueKey('invitation-flow-input')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Share opens exact space directly and one send reaches members $width',
      (tester) async {
        await loadCaptureFonts(tester);
        if (Platform.environment['JIVIE_UI_CAPTURE'] == '1') {
          await tester.runAsync(() async {
            final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
            final data = await File(
              '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
            ).readAsBytes();
            await (FontLoader(
              'Roboto',
            )..addFont(Future.value(ByteData.sublistView(data)))).load();
          });
        }
        final controller = _ShellController();
        final key = GlobalKey();
        await pumpOrganizer(
          tester,
          MemoryOrganizerStorage(),
          width: width,
          localSpacesController: LocalSpaceUiController(
            LocalSpaceKind.personal,
          ),
          collaborationController: controller,
          repaintBoundaryKey: key,
        );
        await tester.tap(find.byKey(const ValueKey('organizer-share-space')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sharing-recipient')), findsOneWidget);
        expect(find.byType(SharingMembersPage), findsNothing);
        expect(find.byType(SharingAccountPage), findsNothing);
        expect(find.byKey(const ValueKey('sharing-scopeId')), findsNothing);
        expect(controller.memberLoads, 0);
        await tester.enterText(
          find.byKey(const ValueKey('sharing-recipient')),
          'oseba@example.test',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        await _capture(tester, key, 'share-${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.pumpAndSettle();
        expect(
          controller.calls.where((c) => c == 'emailInvite:oseba@example.test'),
          hasLength(1),
        );
        expect(controller.emailInviteTargets.single.$1, sharingScopeId);
        expect(controller.emailInviteTargets.single.$2, 'space');
        expect(find.byType(SharingMembersPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final invite in [false, true]) {
    testWidgets(
      'contextual ${invite ? 'Share' : 'Connect'} never reselects local space',
      (tester) async {
        final controller = _ShellController(local: true);
        await pumpOrganizer(
          tester,
          MemoryOrganizerStorage(),
          localSpacesController: LocalSpaceUiController(
            LocalSpaceKind.household,
          ),
          collaborationController: controller,
          repaintBoundaryKey: GlobalKey(),
        );
        if (invite) {
          await tester.tap(find.byKey(const ValueKey('organizer-share-space')));
        } else {
          await mobileTab(tester, 'Nastavitve prostora');
          await tester.ensureVisible(
            find.widgetWithText(OutlinedButton, 'Poveži in sinhroniziraj'),
          );
          await tester.tap(
            find.widgetWithText(OutlinedButton, 'Poveži in sinhroniziraj'),
          );
        }
        await tester.pumpAndSettle();
        expect(controller.publicationTargets, ['qa-household']);
        expect(
          find.byKey(const ValueKey('confirm-space-connection')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('connect-local-space-qa-household')),
          findsNothing,
        );
        expect(find.byType(SharingAccountPage), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('confirm-space-connection')),
        );
        await tester.pumpAndSettle();
        expect(controller.publications, 1);
        expect(controller.state.requireValue.selectedSpaceId, 'qa-household');
        expect(
          find.byKey(const ValueKey('sharing-recipient')),
          invite ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('viewer has no share action', (tester) async {
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      collaborationController: _ShellController(role: SharedRole.viewer),
      localSpacesController: LocalSpaceUiController(LocalSpaceKind.personal),
      repaintBoundaryKey: GlobalKey(),
    );
    expect(find.byKey(const ValueKey('organizer-share-space')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
