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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _invite = VerifiedCryptoInvitation(
  {
    'invitation': {'id': 'invite', 'scopeId': 'scope', 'role': 'viewer'},
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
  }) async => _review;
}

class _Invites extends InviteCryptoRepository {
  _Invites(_Account account) : super(SessionCryptoAccess(account: account));
  Object? trustError, grantError;
  Completer<void>? trustGate, grantGate;
  String? resumed;
  int trusts = 0, accepts = 0, grants = 0, resumes = 0;
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
  }) async => _invite;
  @override
  Future<VerifiedCryptoInvitation> acceptedRecipient(
    String scopeId,
    String invitationId,
  ) async => _invite;
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
    return {};
  }

  @override
  Future<void> admit(
    VerifiedCryptoInvitation recipient,
    ScopeRotationReview reviewedInventory,
  ) async {
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
    'ux26 verified final permissions override stale preview metadata',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = _Account(), invites = _Invites(_Account());
      await _pump(
        tester,
        account,
        invites,
        preview: SharedInvitationPreview(
          scopeName: 'Encrypted space',
          scopeId: 'scope',
          kind: SharedScopeKind.project,
          recipientUsername: 'recipient',
          role: SharedRole.owner,
          expiresAt: DateTime.utc(2099),
          registrationAllowed: false,
          invitationId: 'invite',
          contractVersion: 4,
          projectFinanceIncluded: true,
        ),
      );
      expect(find.text('Access: Can view'), findsOneWidget);
      expect(find.text('No access to finances'), findsOneWidget);
      expect(find.text('Owner'), findsNothing);
      expect(
        find.textContaining('includes access to all finances'),
        findsNothing,
      );
      expect(find.textContaining('older access rules'), findsNothing);
      expect(invites.accepts, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'ux26 restored accepted preview retains explicit waiting without accepting again',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = _Account(), invites = _Invites(_Account());
      await _pump(
        tester,
        account,
        invites,
        preview: SharedInvitationPreview(
          scopeName: 'Encrypted space',
          scopeId: 'scope',
          kind: SharedScopeKind.project,
          recipientUsername: 'recipient',
          role: SharedRole.viewer,
          expiresAt: DateTime.utc(2099),
          registrationAllowed: false,
          invitationId: 'invite',
          contractVersion: 4,
          awaitingApproval: true,
        ),
      );
      expect(
        find.textContaining('owner still needs to approve'),
        findsOneWidget,
      );
      expect(find.text('Join project'), findsNothing);
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-retry')));
      await tester.pumpAndSettle();
      expect(invites.accepts, 0);
      expect(invites.resumes, 2);
      expect(
        find.textContaining('owner still needs to approve'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['en', 'sl']) {
    testWidgets(
      'ux26 approval shows permissions without internal counts $locale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final account = _Account(), invites = _Invites(_Account());
        await _pump(tester, account, invites, owner: true, locale: locale);
        expect(
          find.text(
            locale == 'sl' ? 'Brez dostopa do financ' : 'No access to finances',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale == 'sl' ? 'zgornjimi dovoljenji' : 'permissions above',
          ),
          findsOneWidget,
        );
        expect(
          find.text(locale == 'sl' ? 'Vsebina: 3' : 'Content: 3'),
          findsNothing,
        );
        expect(invites.grants, 0);
        expect(invites.accepts, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'ux26 recipient sees one honest preview then waits without another Join',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = _Account(), invites = _Invites(_Account());
      await _pump(
        tester,
        account,
        invites,
        preview: SharedInvitationPreview(
          scopeName: 'Encrypted space',
          scopeNameAvailable: false,
          scopeId: 'scope',
          kind: SharedScopeKind.project,
          recipientUsername: 'recipient',
          role: SharedRole.viewer,
          expiresAt: DateTime.utc(2099),
          registrationAllowed: false,
          inviterName: 'Sender',
          inviterUsername: 'sender.account',
          inviterAccountId: 'sender-account',
          invitationId: 'invite',
          contractVersion: 4,
        ),
      );
      expect(find.text('Encrypted space'), findsNothing);
      expect(
        find.textContaining(
          'name becomes visible after the owner confirms access',
        ),
        findsOneWidget,
      );
      expect(find.text('Invited by Sender (sender.account)'), findsOneWidget);
      expect(find.text('Join project'), findsOneWidget);
      expect(find.textContaining('sharing.example.test'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
      );
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('owner still needs to approve'),
        findsOneWidget,
      );
      expect(find.text('Join project'), findsNothing);
      expect(find.text('Check access'), findsOneWidget);
      expect(invites.accepts, 1);
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-retry')));
      await tester.pumpAndSettle();
      expect(invites.accepts, 1);
      expect(find.text('Join project'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'ux26 resume opens approved target once and throttles duplicate lifecycle events',
    (tester) async {
      final account = _Account(), invites = _Invites(_Account());
      await _pump(tester, account, invites);
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-confirm')));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        invites.resumes,
        1,
        reason: 'The startup read and immediate resume are coalesced',
      );
      invites.resumed = 'scope';
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5100)),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(invites.resumes, 2);
      expect(invites.accepts, 1);
      expect(invites.grants, 0);
      expect(find.byType(CryptoInvitationPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('ux26 stale account resume cannot refresh or accept invitation', (
    tester,
  ) async {
    final account = _Account(), invites = _Invites(_Account());
    await _pump(tester, account, invites);
    account.directory.current = false;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5100)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(invites.resumes, 1);
    expect(invites.accepts, 0);
    expect(invites.grants, 0);
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['en', 'sl']) {
    testWidgets('recipient deliberately joins without card or code $locale', (
      tester,
    ) async {
      final account = _Account(), invites = _Invites(_Account());
      await _pump(tester, account, invites, locale: locale);
      expect(invites.trusts, 1);
      expect(invites.accepts, 0);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-confirm')));
      await tester.pumpAndSettle();
      expect(invites.accepts, 1);
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
      expect(
        find.textContaining(
          locale == 'sl'
              ? 'Lastnik mora še odobriti'
              : 'owner still needs to approve',
        ),
        findsOneWidget,
      );
      invites.resumed = 'scope';
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-retry')));
      await tester.pumpAndSettle();
      expect(find.byType(CryptoInvitationPage), findsNothing);
      expect(invites.accepts, 1);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'owner sees role and history then grants with one confirmation $locale',
      (tester) async {
        final account = _Account(), invites = _Invites(_Account());
        String? result;
        await _pump(
          tester,
          account,
          invites,
          owner: true,
          locale: locale,
          onResult: (v) => result = v,
        );
        expect(invites.grants, 0);
        expect(
          find.text(
            locale == 'sl' ? 'Brez dostopa do financ' : 'No access to finances',
          ),
          findsOneWidget,
        );
        expect(
          find.text(locale == 'sl' ? 'Vsebina: 3' : 'Content: 3'),
          findsNothing,
        );
        expect(find.byType(AlertDialog), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('crypto-invitation-confirm')),
        );
        await tester.pumpAndSettle();
        expect(invites.grants, 1);
        expect(result, 'scope');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('closing owner review never grants access', (tester) async {
    final account = _Account(), invites = _Invites(_Account());
    await _pump(tester, account, invites, owner: true);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(invites.grants, 0);
  });
  testWidgets(
    'changed root blocks Join and generic retry with clear explanation',
    (tester) async {
      final account = _Account(),
          invites = _Invites(_Account())
            ..trustError = const CryptoDirectoryException(
              'directory_root_changed',
            );
      await _pump(tester, account, invites);
      expect(find.textContaining('account identity changed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('crypto-invitation-retry')),
            )
            .onPressed,
        isNull,
      );
      expect(invites.accepts, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late identity result after account switch cannot enable grant', (
    tester,
  ) async {
    final account = _Account(),
        invites = _Invites(_Account())..trustGate = Completer<void>();
    await _pump(tester, account, invites, owner: true, settle: false);
    account.directory.current = false;
    invites.trustGate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('crypto-invitation-confirm')),
      findsNothing,
    );
    expect(invites.grants, 0);
  });
  testWidgets(
    'owner failed grant offers immediate pending approvals continuation',
    (tester) async {
      final account = _Account(),
          invites = _Invites(_Account())
            ..grantError = StateError('interrupted child preparation');
      await _pump(tester, account, invites, owner: true);
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-confirm')));
      await tester.pumpAndSettle();
      final pending = find.byKey(
        const ValueKey('crypto-invitation-pending-approvals'),
      );
      expect(pending, findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Pending approvals'),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(pending).onPressed, isNotNull);
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
      expect(invites.grants, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('grant stays disabled while its result is pending', (
    tester,
  ) async {
    final account = _Account(),
        invites = _Invites(_Account())..grantGate = Completer<void>();
    await _pump(tester, account, invites, owner: true);
    await tester.tap(find.byKey(const ValueKey('crypto-invitation-confirm')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('crypto-invitation-confirm')),
          )
          .onPressed,
      isNull,
    );
    invites.grantGate!.complete();
    await tester.pumpAndSettle();
    expect(invites.grants, 1);
    expect(tester.takeException(), isNull);
  });
}
