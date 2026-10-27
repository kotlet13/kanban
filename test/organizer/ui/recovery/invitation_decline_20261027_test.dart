import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import '../sharing_ui_fixture.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inherited_invitation_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_preauthorized_invitation.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_invitation_page.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

class _Directory implements AccountDirectoryRepository {
  bool current = true;
  @override
  DeviceSession get session => DeviceSession(sharingSession(), "token");
  @override
  bool Function() get isCurrent =>
      () => current;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account implements AccountCryptoV2Workflow {
  @override
  final _Directory directory = _Directory();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VerifiedDirectory implements VerifiedAccountDirectory {
  @override
  String get accountId => sharingSession().accountId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _invite = VerifiedCryptoInvitation(
  {
    'invitation': {
      'id': 'invite',
      'scopeId': 'scope',
      'role': 'viewer',
      'state': 'pending',
    },
    'creatorAuthorization': {
      'commandBase64':
          'eyJhY2NvdW50SWQiOiIzMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJvcGVyYXRpb24iOiJjcnlwdG8yLmludml0YXRpb25zLmNyZWF0ZSIsInBheWxvYWQiOnsiZXhwaXJlc0F0Ijo0MDcwOTA4ODAwLCJpbnZpdGF0aW9uSWQiOiJpbnZpdGUiLCJyZWNpcGllbnQiOnsia2luZCI6InVzZXJuYW1lIiwidmFsdWUiOiJyZWNpcGllbnQifSwicm9sZSI6InZpZXdlciIsInNjb3BlSWQiOiJzY29wZSJ9LCJ2ZXJzaW9uIjoyfQ==',
    },
    'proposedMember': {
      'accountId': 'recipient',
      'role': 'viewer',
      'financeRole': 'none',
      'manageKeys': false,
    },
  },
  _VerifiedDirectory(),
  [],
);
final _review = ScopeRotationReview({
  'reviewId': 'review',
  'scopeId': 'scope',
  'domains': {
    'core': {'count': 3},
  },
});

class _Manager extends ScopeCryptoManager {
  _Manager(super.access);
  @override
  Future<List<ScopeRotationReview>> pendingRotationReviews(
    String scopeId,
  ) async => [];
  @override
  Future<ScopeRotationReview> reviewRotation(
    String scopeId, {
    Uint8List? recoveryFile,
    bool financeOnly = false,
    VerifiedInheritedInvitationAdmission? inheritedInvitationAdmission,
    VerifiedPreauthorizedInvitationAdmission? preauthorizedInvitationAdmission,
    String? fixedReviewId,
  }) async => _review;
}

class _Invites extends InviteCryptoRepository {
  _Invites(_Account account) : super(SessionCryptoAccess(account: account));
  Object? trustError, grantError;
  Completer<void>? trustGate, grantGate;
  String? resumed;
  String? resumedAfterAccept;
  int trusts = 0, accepts = 0, grants = 0, resumes = 0;
  int declines = 0;
  Object? declineError;
  Completer<void>? declineGate;
  final declineActionIds = <String>[];
  @override
  Future<void> decline(
    VerifiedCryptoInvitation invite, {
    required String actionId,
  }) async {
    declines++;
    declineActionIds.add(actionId);
    await declineGate?.future;
    if (declineError != null) throw declineError!;
  }

  VerifiedCryptoInvitation inspectedInvitation = _invite;
  @override
  ScopeCryptoManager get manager => _Manager(access);
  @override
  Future<String?> resumeAccepted(String invitationId) async {
    resumes++;
    return resumed;
  }

  @override
  Future<VerifiedCryptoInvitation> inspect({
    String? token,
    String? invitationId,
  }) async => inspectedInvitation;
  @override
  Future<VerifiedCryptoInvitation> acceptedRecipient(
    String scopeId,
    String invitationId, {
    String? acceptanceProofHash,
  }) async => _invite;
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
    accepts++;
    if (resumedAfterAccept != null) resumed = resumedAfterAccept;
    return {};
  }

  @override
  Future<void> admit(
    VerifiedCryptoInvitation recipient,
    ScopeRotationReview reviewedInventory, {
    Future<void> Function(VerifiedCryptoInvitation)? beforeDisclosure,
    Future<void> Function()? freshDisclosureBoundary,
  }) async {
    grants++;
    await grantGate?.future;
    if (grantError != null) throw grantError!;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Account account,
  _Invites invites, {
  bool owner = false,
  bool supported = true,
  Future<void> Function()? onDeclined,
  bool settle = true,
  String locale = 'en',
  ValueChanged<String?>? onResult,
  SharedInvitationPreview? preview,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: Locale(locale),
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
              onPressed: () async {
                final result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => CryptoInvitationPage(
                      account: account,
                      repository: invites,
                      invitationId: 'invite',
                      preview: preview,
                      declineSupported: supported,
                      onDeclined: onDeclined,
                      scopeId: owner ? 'scope' : null,
                    ),
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets(
    'decline27 recipient button confirms decline once and returns no accepted scope',
    (tester) async {
      final account = _Account(), invites = _Invites(_Account());
      invites.declineGate = Completer<void>();
      var cleanups = 0;
      String? result = 'still-open';
      await _pump(
        tester,
        account,
        invites,
        locale: 'sl',
        onDeclined: () async {
          cleanups++;
        },
        onResult: (value) => result = value,
      );
      final decline = find.byKey(const ValueKey('crypto-invitation-decline'));
      expect(find.text('Zavrni povabilo'), findsOneWidget);
      expect(find.text('Nadaljuj lokalno'), findsNothing);
      tester.widget<OutlinedButton>(decline).onPressed!();
      tester.widget<OutlinedButton>(decline).onPressed!();
      await tester.pump();
      expect(invites.declines, 1);
      expect(tester.widget<OutlinedButton>(decline).onPressed, isNull);
      expect(cleanups, 0);
      invites.declineGate!.complete();
      await tester.pumpAndSettle();
      expect(cleanups, 1);
      expect(result, isNull);
      expect(invites.accepts, 0);
      expect(invites.grants, 0);
    },
  );
  testWidgets(
    'decline27 failure retains invitation and retries the same action',
    (tester) async {
      final account = _Account(), invites = _Invites(_Account());
      invites.declineError = const FormatException('network');
      var cleanups = 0;
      await _pump(
        tester,
        account,
        invites,
        onDeclined: () async {
          cleanups++;
        },
      );
      final decline = find.byKey(const ValueKey('crypto-invitation-decline'));
      await tester.tap(decline);
      await tester.pumpAndSettle();
      expect(cleanups, 0);
      expect(decline, findsOneWidget);
      expect(invites.inspectedInvitation.invitation['state'], 'pending');
      invites.declineError = null;
      await tester.tap(decline);
      await tester.pumpAndSettle();
      expect(invites.declines, 2);
      expect(invites.declineActionIds.toSet(), hasLength(1));
      expect(cleanups, 1);
    },
  );
  testWidgets(
    'decline27 old identity completion cannot clear invitation or close another session',
    (tester) async {
      final account = _Account(), invites = _Invites(_Account());
      invites.declineGate = Completer<void>();
      var cleanups = 0;
      await _pump(
        tester,
        account,
        invites,
        onDeclined: () async {
          cleanups++;
        },
      );
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-decline')));
      await tester.pump();
      account.directory.current = false;
      invites.declineGate!.complete();
      await tester.pumpAndSettle();
      expect(cleanups, 0);
      expect(find.byType(CryptoInvitationPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('crypto-invitation-decline')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'decline27 accepted waiting for keys offers no decline or local action',
    (tester) async {
      final account = _Account(), invites = _Invites(_Account());
      invites.inspectedInvitation = VerifiedCryptoInvitation(
        {
          ..._invite.response,
          'invitation': {..._invite.invitation, 'state': 'accepted'},
        },
        _VerifiedDirectory(),
        [],
      );
      await _pump(tester, account, invites);
      expect(
        find.byKey(const ValueKey('crypto-invitation-decline')),
        findsNothing,
      );
      expect(find.text('Continue locally'), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      expect(invites.declines, 0);
    },
  );
  for (final owner in [false, true]) {
    testWidgets(
      'decline27 ${owner ? 'owner grant' : 'unsupported host'} keeps Back and no local invitation action',
      (tester) async {
        final account = _Account(), invites = _Invites(_Account());
        await _pump(tester, account, invites, owner: owner, supported: owner);
        expect(
          find.byKey(const ValueKey('crypto-invitation-decline')),
          findsNothing,
        );
        expect(find.text('Continue locally'), findsNothing);
        expect(find.byType(BackButton), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(CryptoInvitationPage), findsNothing);
        expect(invites.declines, 0);
        expect(invites.accepts, 0);
        expect(invites.grants, 0);
      },
    );
  }
  testWidgets(
    'decline27 confirmed decline cleanup failure skips lifecycle reload and retries cleanup only',
    (tester) async {
      final account = _Account(), invites = _Invites(_Account());
      var cleanups = 0;
      await _pump(
        tester,
        account,
        invites,
        onDeclined: () async {
          cleanups++;
          if (cleanups == 1) throw const FormatException('local_storage');
        },
      );
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-decline')));
      await tester.pumpAndSettle();
      expect(cleanups, 1);
      expect(invites.declines, 1);
      final resumes = invites.resumes;
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('crypto-invitation-decline')),
        findsNothing,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(invites.resumes, resumes);
      await tester.tap(
        find.byKey(const ValueKey('crypto-invitation-declined-close')),
      );
      await tester.pumpAndSettle();
      expect(cleanups, 2);
      expect(invites.declines, 1);
      expect(find.byType(CryptoInvitationPage), findsNothing);
    },
  );
}
