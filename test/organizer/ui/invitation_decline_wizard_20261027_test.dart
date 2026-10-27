import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/presentation/shared/invitation_wizard.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

import 'sharing_ui_fixture.dart';

final _link = InvitationLink(
  serverUrl: 'https://sharing.example.test',
  token: 'fhi3_${'b' * 64}',
);

class _Controller extends SharingUiController {
  _Controller({
    super.initial,
    this.encrypted = false,
  }) {
    emailPreview = true;
  }
  final bool encrypted;
  final bool viewer = false, awaitingApproval = false;
  int previews = 0, clears = 0;
  Object? clearError;
  @override
  Future<void> clearPendingInvitation({String? expectedToken}) async {
    clears++;
    if (clearError != null) throw clearError!;
    await super.clearPendingInvitation(expectedToken: expectedToken);
  }

  Completer<void>? previewGate, acceptGate;
  int selectFailures = 0;
  Completer<void>? acceptedScopeGate, unrelatedSyncGate;
  Object? acceptedScopeError;
  final acceptedScopePreparations = <String>[];
  @override
  Future<void> prepareAcceptedScope(String id) async {
    acceptedScopePreparations.add(id);
    await acceptedScopeGate?.future;
    if (acceptedScopeError != null) throw acceptedScopeError!;
  }

  @override
  Future<void> syncNow() async {
    await unrelatedSyncGate?.future;
    await super.syncNow();
  }

  @override
  Future<void> acceptInvitation(String token) async {
    await acceptGate?.future;
    await super.acceptInvitation(token);
  }

  @override
  Future<void> selectSpace(String? id) async {
    if (selectFailures > 0) {
      selectFailures--;
      throw const CollaborationException('network');
    }
    await super.selectSpace(id);
  }

  @override
  Future<SharedInvitationPreview> previewInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) async {
    previews++;
    await previewGate?.future;
    final p = await super.previewInvitation(serverUrl: serverUrl, token: token);
    return SharedInvitationPreview(
      scopeName: p.scopeName,
      scopeId: p.scopeId,
      kind: p.kind,
      recipientUsername: p.recipientUsername,
      recipientEmail: p.recipientEmail,
      inviterName: p.inviterName,
      invitationId: encrypted ? 'saved-invite' : p.invitationId,
      role: viewer ? SharedRole.viewer : SharedRole.member,
      expiresAt: p.expiresAt,
      registrationAllowed: p.registrationAllowed,
      contractVersion: encrypted ? 4 : 3,
      awaitingApproval: awaitingApproval,
      accessScope: 'space',
      requiresExplicitAcceptance: true,
    );
  }

  @override
  Future<void> loginForInvitation({
    required String serverUrl,
    required String invitationToken,
    required String username,
    required String password,
    String? otp,
    String deviceName = 'Jivie',
  }) => login(
    serverUrl: serverUrl,
    username: username,
    password: password,
    otp: otp,
  );
}

class _CryptoStore implements CryptoIdentityStore {
  @override
  String get partition => sharingSession().partition;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CryptoAccount implements AccountCryptoV2Workflow {
  @override
  final CryptoIdentityStore store = _CryptoStore();
  @override
  Future<String> localPhase() async => 'ready';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CryptoCollaboration implements CollaborationRepository {
  _CryptoCollaboration(this.account);
  final AccountCryptoV2Workflow account;
  @override
  Future<AccountCryptoV2Workflow> connectedCryptoAccount() async => account;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CryptoDirectory implements VerifiedAccountDirectory {
  @override
  String get accountId => sharingSession().accountId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CryptoInvites extends InviteCryptoRepository {
  _CryptoInvites(_CryptoAccount account)
    : super(SessionCryptoAccess(account: account));
  int trusts = 0, accepts = 0, resumes = 0, declines = 0;
  Object? declineError;
  Completer<void>? declineGate;
  @override
  Future<void> decline(
    VerifiedCryptoInvitation invite, {
    required String actionId,
  }) async {
    declines++;
    await declineGate?.future;
    if (declineError != null) throw declineError!;
  }

  Object? trustError, resumeError;
  Completer<void>? trustGate;
  Future<void> Function()? afterAccept;
  String? resumedScope, resumedAfterAccept;
  Completer<void>? resumeGate;
  Completer<void>? inspectionGate;
  Object? inspectionError;
  VerifiedCryptoInvitation? inspectedInvitation;
  int inspections = 0;
  @override
  Future<String?> resumeAccepted(String invitationId) async {
    resumes++;
    await resumeGate?.future;
    if (resumeError != null) throw resumeError!;
    return resumedScope;
  }

  @override
  Future<VerifiedCryptoInvitation> inspect({
    String? token,
    String? invitationId,
  }) async {
    inspections++;
    await inspectionGate?.future;
    if (inspectionError != null) throw inspectionError!;
    return inspectedInvitation ??
        VerifiedCryptoInvitation(
          {
            'invitation': {
              'id': 'saved-invite',
              'scopeId': sharingScopeId,
              'role': 'viewer',
            },
            'creatorAuthorization': {
              'commandBase64':
                  'eyJhY2NvdW50SWQiOiIzMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJvcGVyYXRpb24iOiJjcnlwdG8yLmludml0YXRpb25zLmNyZWF0ZSIsInBheWxvYWQiOnsiZXhwaXJlc0F0Ijo0MDcwOTA4ODAwLCJpbnZpdGF0aW9uSWQiOiJzYXZlZC1pbnZpdGUiLCJyZWNpcGllbnQiOnsia2luZCI6InVzZXJuYW1lIiwidmFsdWUiOiJyZWNpcGllbnQifSwicm9sZSI6InZpZXdlciIsInNjb3BlSWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEifSwidmVyc2lvbiI6Mn0=',
            },
          },
          _CryptoDirectory(),
          [],
        );
  }

  @override
  Future<void> trustCreatorFromDirectory(
    VerifiedCryptoInvitation invite,
  ) async {
    trusts++;
    await trustGate?.future;
    if (trustError != null) throw trustError!;
  }

  @override
  Future<Map<String, dynamic>> accept(
    VerifiedCryptoInvitation invite, {
    required String actionId,
  }) async {
    await trustCreatorFromDirectory(invite);
    accepts++;
    if (resumedAfterAccept != null) resumedScope = resumedAfterAccept;
    await afterAccept?.call();
    return {};
  }
}

VerifiedCryptoInvitation _boundInvitation() => VerifiedCryptoInvitation(
  {
    'invitation': {
      'id': 'saved-invite',
      'scopeId': sharingScopeId,
      'role': 'viewer',
      'state': 'pending',
    },
    'creatorAuthorization': {
      'commandBase64': base64Encode(
        CryptoJson.encode({
          'accountId': sharingSession().accountId,
          'operation': 'crypto2.invitations.create',
          'version': 2,
          'payload': {
            'invitationId': 'saved-invite',
            'scopeId': sharingScopeId,
            'role': 'viewer',
            'expiresAt': 4070908800,
            'recipient': {
              'kind': 'username',
              'value': 'first',
              'accountId': sharingSession().accountId,
            },
          },
        }),
      ),
    },
  },
  _CryptoDirectory(),
  [],
);
Future<void> _pump(
  WidgetTester tester,
  _Controller controller,
  _CryptoInvites crypto,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        collaborationRepositoryProvider.overrideWith(
          (ref) async => _CryptoCollaboration(crypto.access.account),
        ),
        pendingInvitationStoreProvider.overrideWithValue(
          MemoryPendingInvitationStore(),
        ),
        securePendingInvitationProvider.overrideWith(
          (ref) async => controller.savedInvitation,
        ),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => InvitationWizard(
                    initialLink: _link,
                    cryptoRepository: (_) => crypto,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

_Controller _controller() => _Controller(
  encrypted: true,
  initial: CollaborationState(
    session: sharingSession(),
    invitationDeclineSupported: true,
  ),
);
void main() {
  testWidgets(
    'decline27 wizard bound recipient decline closes and clears only after confirmation',
    (tester) async {
      final controller = _controller();
      final crypto = _CryptoInvites(_CryptoAccount())
        ..inspectedInvitation = _boundInvitation();
      crypto.declineGate = Completer<void>();
      await _pump(tester, controller, crypto);
      expect(crypto.inspections, 1);
      expect(find.text('Zavrni povabilo'), findsOneWidget);
      expect(find.text('Nadaljuj lokalno'), findsNothing);
      final button = find.byKey(const ValueKey('invitation-flow-decline'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(controller.clears, 0);
      expect(controller.savedInvitation?.token, _link.token);
      expect(crypto.declines, 1);
      crypto.declineGate!.complete();
      await tester.pumpAndSettle();
      expect(controller.clears, 1);
      expect(controller.savedInvitation, isNull);
      expect(find.byType(InvitationWizard), findsNothing);
      expect(crypto.accepts, 0);
    },
  );
  testWidgets(
    'decline27 wizard failures preserve invitation and confirmed cleanup cannot cross accounts',
    (tester) async {
      final controller = _controller();
      final crypto = _CryptoInvites(_CryptoAccount())
        ..inspectedInvitation = _boundInvitation();
      crypto.declineError = const FormatException('network');
      await _pump(tester, controller, crypto);
      final button = find.byKey(const ValueKey('invitation-flow-decline'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.clears, 0);
      expect(controller.savedInvitation?.token, _link.token);
      expect(button, findsOneWidget);
      crypto.declineError = null;
      controller.clearError = const FormatException('local_storage');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.clears, 1);
      expect(crypto.declines, 2);
      final close = find.byKey(
        const ValueKey('invitation-flow-declined-close'),
      );
      expect(close, findsOneWidget);
      final oldClose = tester.widget<TextButton>(close).onPressed!;
      controller.replace(
        CollaborationState(
          session: sharingSession(second: true),
          invitationDeclineSupported: true,
        ),
      );
      await tester.pumpAndSettle();
      controller.clearError = null;
      oldClose();
      await tester.pumpAndSettle();
      expect(controller.clears, 1);
      expect(controller.savedInvitation?.token, _link.token);
      expect(find.text('Povabilo je zavrnjeno.'), findsNothing);
      expect(crypto.accepts, 0);
    },
  );
}
