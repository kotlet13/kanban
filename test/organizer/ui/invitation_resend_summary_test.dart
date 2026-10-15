import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/theme/jivie_theme.dart';

import 'sharing_ui_fixture.dart';
import 'sharing_ui_test.dart' show enterSharing, tapSharing;

SharedInvitation invitation(
  String id, {
  String? email = 'recipient@example.test',
  String scopeId = sharingScopeId,
  String status = 'pending',
  SharedRole role = SharedRole.member,
}) => SharedInvitation(
  id: id,
  scopeId: scopeId,
  recipientUsername: email == null ? 'legacy-user' : '',
  recipientEmail: email,
  contractVersion: email == null ? 1 : 3,
  accessScope: email == null ? null : 'space',
  role: role,
  expiresAt: status == 'expired' ? DateTime.utc(2000) : DateTime.utc(2099),
  acceptedAt: status == 'accepted' ? sharingTestNow : null,
  revokedAt: status == 'revoked' ? sharingTestNow : null,
);

class _Invitations extends SharingUiController {
  _Invitations(this.entries)
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          selectedSpaceId: sharingScopeId,
          emailInvitationsSupported: true,
        ),
      );
  final List<SharedInvitation> entries;
  final revoked = <String>[];
  int sequence = 0;
  @override
  Future<List<SharedInvitation>> invitations(String scopeId) async =>
      List.of(entries);
  @override
  Future<void> revokeInvitation(String scopeId, String invitationId) async {
    revoked.add(invitationId);
    final index = entries.indexWhere(
      (entry) => entry.id == invitationId && entry.scopeId == scopeId,
    );
    final old = entries[index];
    entries[index] = invitation(
      old.id,
      email: old.recipientEmail,
      scopeId: old.scopeId,
      role: old.role,
      status: 'revoked',
    );
  }

  @override
  Future<SharedInvitation> createEmailInvitation({
    required String scopeId,
    required String recipientEmail,
    SharedRole role = SharedRole.member,
    String language = 'sl',
    String? requestId,
    String? accessScope,
  }) async {
    final entry = invitation(
      'new-${++sequence}',
      email: recipientEmail,
      scopeId: scopeId,
      role: role,
    );
    entries.add(entry);
    return entry;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Invitations controller, {
  String locale = 'sl',
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [collaborationProvider.overrideWith(() => controller)],
      child: MaterialApp(
        locale: Locale(locale),
        theme: buildJivieTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SharingMembersPage(
              scope: sharingScope(),
              session: sharingSession(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder row(String id) => find.byKey(ValueKey('sharing-invitation-$id'));
Future<void> revoke(WidgetTester tester, String id) async {
  final button = find.byKey(ValueKey('sharing-revoke-invitation-$id'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final configuration in [(320.0, 'sl'), (390.0, 'en'), (1280.0, 'sl')]) {
    testWidgets(
      'cancel and reissue one email ${configuration.$1}/${configuration.$2}',
      (tester) async {
        final controller = _Invitations([
          invitation('old', email: ' Recipient@Example.test '),
        ]);
        await _pump(
          tester,
          controller,
          width: configuration.$1,
          locale: configuration.$2,
        );
        await revoke(tester, 'old');
        final l = AppLocalizations.of(
          tester.element(find.byType(SharingMembersPage)),
        )!;
        expect(find.textContaining(l.sharingRevoked), findsOneWidget);
        for (final id in ['new-1', 'new-2']) {
          final invite = find.text(l.sharingInvitePerson);
          await tester.ensureVisible(invite);
          await tester.tap(invite);
          await tester.pumpAndSettle();
          await enterSharing(tester, 'recipient', 'recipient@example.test');
          await tapSharing(tester, 'sharing-submit');
          expect(row('old'), findsNothing);
          expect(row(id), findsOneWidget);
          expect(
            find.textContaining(l.sharingInvitationResent),
            findsOneWidget,
          );
          expect(find.textContaining(l.sharingRevoked), findsNothing);
          await revoke(tester, id);
          expect(find.textContaining(l.sharingInvitationResent), findsNothing);
          expect(find.textContaining(l.sharingRevoked), findsOneWidget);
        }
        expect(controller.entries, hasLength(3)); // History was not deleted.
        expect(controller.revoked, ['old', 'new-1', 'new-2']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final status in ['pending', 'accepted', 'expired', 'revoked']) {
    testWidgets('latest invitation preserves $status status', (tester) async {
      final controller = _Invitations([
        invitation('old', status: 'revoked'),
        invitation('current', status: status, role: SharedRole.viewer),
      ]);
      await _pump(tester, controller);
      final l = AppLocalizations.of(
        tester.element(find.byType(SharingMembersPage)),
      )!;
      expect(row('old'), findsNothing);
      expect(row('current'), findsOneWidget);
      final label = switch (status) {
        'accepted' => l.sharingAccepted,
        'expired' => l.sharingExpired,
        'revoked' => l.sharingRevoked,
        _ => l.sharingInvitationResent,
      };
      expect(find.textContaining(label), findsOneWidget);
      expect(find.textContaining(l.sharingViewer), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sharing-revoke-invitation-current')),
        status == 'pending' ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('first invitation has no resend label', (tester) async {
    await _pump(tester, _Invitations([invitation('first')]));
    expect(row('first'), findsOneWidget);
    expect(find.textContaining('Ponovno poslano povabilo'), findsNothing);
  });

  testWidgets('different emails, scopes and legacy invites stay distinct', (
    tester,
  ) async {
    final controller = _Invitations([
      invitation('first', status: 'revoked'),
      invitation('other-email', email: 'other@example.test'),
      invitation('other-scope', scopeId: 'another-scope'),
      invitation('legacy-old', email: null, status: 'revoked'),
      invitation('legacy-new', email: null),
    ]);
    await _pump(tester, controller);
    for (final entry in controller.entries) {
      expect(row(entry.id), findsOneWidget);
    }
    expect(find.textContaining('Ponovno poslano povabilo'), findsNothing);
  });

  testWidgets('multiple valid links remain individually revocable', (
    tester,
  ) async {
    final controller = _Invitations([
      invitation('older-active', role: SharedRole.viewer),
      invitation('newer-active'),
    ]);
    await _pump(tester, controller);
    expect(row('older-active'), findsOneWidget);
    expect(row('newer-active'), findsOneWidget);
    await revoke(tester, 'newer-active');
    expect(controller.revoked, ['newer-active']);
    expect(row('older-active'), findsOneWidget);
    expect(row('newer-active'), findsNothing);
    await revoke(tester, 'older-active');
    expect(controller.revoked, ['newer-active', 'older-active']);
    expect(tester.takeException(), isNull);
  });
}
