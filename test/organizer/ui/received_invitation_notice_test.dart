import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/received_invitation_notice.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/received_invitation_notice_provider.dart';

import 'sharing_ui_fixture.dart';

CollaborationState noticeState({bool second = false, bool supported = true}) =>
    CollaborationState(
      session: sharingSession(second: second),
      usernameInvitationsSupported: supported,
      scopedInvitationsSupported: supported,
    );

SharedInvitationPreview noticeInvitation() => SharedInvitationPreview(
  scopeName: 'Invited private project',
  scopeId: sharingScopeId,
  kind: SharedScopeKind.project,
  recipientUsername: 'first',
  inviterName: 'Inviter',
  invitationId: 'invitation-3',
  contractVersion: 3,
  accessScope: 'project',
  role: SharedRole.viewer,
  expiresAt: DateTime.utc(2099),
  registrationAllowed: false,
  requiresExplicitAcceptance: true,
);

class _NoticeController extends SharingUiController {
  _NoticeController({CollaborationState? initial})
    : super(initial: initial ?? noticeState());
  int pendingCalls = 0;
  int? acceptedVersion;
  Completer<List<SharedInvitationPreview>>? paused;
  @override
  Future<List<SharedInvitationPreview>> pendingInvitations() {
    pendingCalls++;
    final wait = paused;
    paused = null;
    return wait?.future ?? Future.value(List.of(incomingInvitations));
  }

  @override
  Future<void> acceptPendingInvitation(
    String invitationId, {
    int contractVersion = 2,
  }) async {
    acceptedVersion = contractVersion;
    await super.acceptPendingInvitation(
      invitationId,
      contractVersion: contractVersion,
    );
  }

  @override
  Future<void> selectSpace(String? id) async {
    calls.add('select:$id');
  }
}

Future<ProviderContainer> _pumpNotice(
  WidgetTester tester,
  _NoticeController controller, {
  ValueChanged<String>? onAccepted,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  final container = ProviderContainer(
    overrides: [
      collaborationProvider.overrideWith(() => controller),
      securePendingInvitationProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ReceivedInvitationNotice(onAccepted: onAccepted ?? (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final result = container.read(receivedInvitationNoticeProvider);
  if (result.hasError) throw result.error!;
  return container;
}

void main() {
  testWidgets(
    'SMTP-off username notice opens dedicated explicit decision route',
    (tester) async {
      final controller = _NoticeController()
        ..incomingInvitations = [noticeInvitation()];
      String? accepted;
      await _pumpNotice(tester, controller, onAccepted: (id) => accepted = id);
      expect(
        find.byKey(const ValueKey('received-invitation-notice')),
        findsOneWidget,
      );
      expect(find.text('Invited private project'), findsNothing);
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.text('Invitations'), findsOneWidget);
      expect(find.textContaining('Invited private project'), findsWidgets);
      expect(controller.acceptedVersion, isNull);
      await tester.tap(
        find.byKey(const ValueKey('accept-pending-invitation-3')),
      );
      await tester.pumpAndSettle();
      expect(controller.acceptedVersion, 3);
      expect(accepted, sharingScopeId);
      expect(
        find.byKey(const ValueKey('received-invitation-notice')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'summary refreshes on resume and revision without timer polling',
    (tester) async {
      final controller = _NoticeController();
      final container = await _pumpNotice(tester, controller);
      expect(controller.pendingCalls, 1);
      controller.replace(noticeState());
      await tester.pumpAndSettle();
      expect(controller.pendingCalls, 1);
      await tester.pump(const Duration(minutes: 5));
      expect(controller.pendingCalls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.pendingCalls, 2);
      container.read(pendingInvitationRevisionProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(controller.pendingCalls, 3);
    },
  );

  testWidgets('late result from another account never becomes its notice', (
    tester,
  ) async {
    final late = Completer<List<SharedInvitationPreview>>();
    final controller = _NoticeController()..paused = late;
    await _pumpNotice(tester, controller);
    controller.replace(noticeState(second: true));
    await tester.pumpAndSettle();
    late.complete([noticeInvitation()]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('received-invitation-notice')),
      findsNothing,
    );
    expect(controller.pendingCalls, 2);
  });

  testWidgets(
    'unsupported and signed-out accounts perform no invitation lookup',
    (tester) async {
      final controller = _NoticeController(
        initial: noticeState(supported: false),
      );
      await _pumpNotice(tester, controller);
      expect(controller.pendingCalls, 0);
      controller.replace(CollaborationState());
      await tester.pumpAndSettle();
      expect(controller.pendingCalls, 0);
      expect(
        find.byKey(const ValueKey('received-invitation-notice')),
        findsNothing,
      );
    },
  );
  for (final locale in ['sl', 'en']) {
    testWidgets('compact $locale notice fits320px with2x text', (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _NoticeController()
        ..incomingInvitations = [noticeInvitation()];
      await _pumpNotice(
        tester,
        controller,
        locale: Locale(locale),
        textScale: 2,
      );
      expect(
        find.byKey(const ValueKey('received-invitation-notice')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
