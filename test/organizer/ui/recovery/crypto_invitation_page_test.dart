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
  int trusts = 0, accepts = 0, grants = 0;
  @override
  ScopeCryptoManager get manager => _Manager(access);
  @override
  Future<String?> resumeAccepted(String invitationId) async => resumed;
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
          findsOneWidget,
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
