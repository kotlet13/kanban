import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/onboarding/account_email_card.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_wizard.dart';
import 'package:kanban/organizer/presentation/shared/content_moderation.dart';
import 'package:kanban/organizer/presentation/shared/sharing_auth.dart';
import 'package:kanban/organizer/presentation/shared/sharing_conflicts.dart';
import 'package:kanban/organizer/presentation/shared/sharing_pending_invitations.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status_dialog.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status_projection.dart';
import 'package:kanban/organizer/presentation/shared/sharing_sync_conflicts.dart';
import 'package:kanban/organizer/state/account_crypto_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

final _at = DateTime.utc(2026, 10, 31, 12);
SyncFailureDetails _failure(String reason, {String? scopeId}) =>
    SyncFailureDetails(
      stage: SyncFailureStage.download,
      occurredAt: _at,
      reason: reason,
      scopeId: scopeId,
    );

class _Controller extends SharingUiController {
  _Controller(CollaborationState initial) : super(initial: initial);
  final emailReadPartitions = <String>[];
  final rulesReadScopes = <String?>[];
  var rulesAccepted = 0;
  var failNextLogin = false;
  final submittedServers = <String>[];
  @override
  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
    String? otp,
    bool allowLocalHttp = false,
    String deviceName = 'Jivie',
  }) async {
    submittedServers.add(serverUrl);
    replace(CollaborationState());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (failNextLogin) {
      failNextLogin = false;
      throw const CollaborationException('invalid_credentials');
    }
    await super.login(
      serverUrl: serverUrl,
      username: username,
      password: password,
      otp: otp,
      allowLocalHttp: allowLocalHttp,
      deviceName: deviceName,
    );
  }

  @override
  Future<AccountStatus> accountStatus() async {
    emailReadPartitions.add(state.requireValue.session!.partition);
    return const AccountStatus(emailVerified: false, resetAvailable: false);
  }

  @override
  Future<SharedContentPolicy> sharedContentPolicy({String? scopeId}) async {
    rulesReadScopes.add(scopeId);
    final session = state.requireValue.session!;
    return SharedContentPolicy(
      serverId: session.serverId,
      partition: session.partition,
      deviceId: session.deviceId,
      policyVersion: 1,
      title: 'Shared rules',
      textSl: 'Pravila deljenja.',
      textEn: 'Shared content rules.',
      recipientName: 'Administrator',
      accepted: false,
    );
  }

  @override
  Future<void> acceptSharedContentPolicy(SharedContentPolicy policy) async {
    rulesAccepted++;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Controller controller, {
  String locale = 'sl',
  bool narrow = false,
}) async {
  if (narrow) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        securePendingInvitationProvider.overrideWith((ref) async => null),
        accountCryptoPreviewProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(narrow ? 1.3 : 1)),
          child: child!,
        ),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(collaborationProvider).valueOrNull;
              return TextButton(
                onPressed: state == null
                    ? null
                    : () => showSharingStatusDetails(
                        context,
                        state: state,
                        scopeId: sharingScopeId,
                        onSync: () {},
                        onConflicts: () =>
                            showSharingSyncConflicts(context, ref),
                      ),
                child: const Text('Open sync'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open sync'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

CollaborationState _state(
  String reason, {
  bool invalid = false,
  String? scopeId = sharingScopeId,
  List<SharedConflict> conflicts = const [],
}) => CollaborationState(
  session: sharingSession(),
  sessionInvalid: invalid,
  scopes: [sharingScope()],
  emailVerificationSupported: true,
  emailInvitationsSupported: true,
  conflicts: conflicts,
  syncFailures: [_failure(reason, scopeId: scopeId)],
);

void main() {
  testWidgets(
    'email opens existing account card for same session; switching account closes it',
    (tester) async {
      final controller = _Controller(_state('email_verification_required'));
      await _pump(tester, controller);
      expect(find.textContaining('Prizadeti prostor:'), findsOneWidget);
      await _tap(tester, 'sync-remediation-email');
      final card = tester.widget<AccountEmailCard>(
        find.byType(AccountEmailCard),
      );
      expect(card.session.partition, sharingSession().partition);
      expect(controller.emailReadPartitions, [sharingSession().partition]);
      expect(controller.calls, isEmpty);
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byType(AccountEmailCard), findsNothing);
      expect(controller.emailReadPartitions, [sharingSession().partition]);
    },
  );

  testWidgets(
    'protection review opens existing read-only panel before any setup wizard',
    (tester) async {
      final controller = _Controller(_state('crypto_migration_required'));
      await _pump(tester, controller);
      await _tap(tester, 'sync-remediation-protection');
      expect(find.byType(AccountCryptoPanel), findsOneWidget);
      expect(find.byType(AccountCryptoWizard), findsNothing);
      expect(controller.calls, isEmpty);
    },
  );

  testWidgets(
    'invalid session login survives its own null-session transition and reports failure then success',
    (tester) async {
      final controller = _Controller(_state('auth_required', invalid: true));
      await _pump(tester, controller);
      await _tap(tester, 'sync-remediation-session');
      final auth = tester.widget<SharingAuthPanel>(
        find.byType(SharingAuthPanel),
      );
      expect(auth.loginOnly, isTrue);
      expect(auth.initialServer, sharingSession().serverUrl);
      expect(controller.loginAttempts, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('sharing-username')),
        'first',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sharing-password')),
        'synthetic-password',
      );
      controller.failNextLogin = true;
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-connect')));
      await tester.tap(find.byKey(const ValueKey('sharing-connect')));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byType(SharingAuthPanel), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(SharingAuthPanel), findsOneWidget);
      expect(controller.submittedServers, [sharingSession().serverUrl]);
      await _tap(tester, 'sharing-connect');
      expect(find.byType(SharingAuthPanel), findsNothing);
      expect(controller.submittedServers, [
        sharingSession().serverUrl,
        sharingSession().serverUrl,
      ]);
      expect(controller.loginAttempts, [null]);
    },
  );

  testWidgets(
    'invitation action opens existing explicit received-invitation screen',
    (tester) async {
      final controller = _Controller(_state('invitation_acceptance_required'));
      await _pump(tester, controller);
      await _tap(tester, 'sync-remediation-invitations');
      final invitations = tester.widget<SharingPendingInvitations>(
        find.byType(SharingPendingInvitations),
      );
      expect(invitations.session.partition, sharingSession().partition);
      expect(controller.calls, isEmpty);
    },
  );

  testWidgets(
    'rules action preserves exact failure scope and requires explicit acceptance',
    (tester) async {
      final controller = _Controller(_state('policy_acceptance_required'));
      await _pump(tester, controller);
      await _tap(tester, 'sync-remediation-rules');
      expect(find.byType(SharedContentPolicyDialog), findsOneWidget);
      expect(controller.rulesReadScopes, [sharingScopeId]);
      expect(controller.rulesAccepted, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('shared-policy-accept')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('conflict action reaches real current-session conflict review', (
    tester,
  ) async {
    final conflict = SharedConflict(
      id: 'private-conflict',
      scopeId: sharingScopeId,
      recordId: 'private-record',
      recordType: SharedRecordType.task,
      reason: 'conflict',
      localPayload: {'title': 'Local'},
      remotePayload: {'title': 'Remote'},
    );
    final controller = _Controller(_state('conflict', conflicts: [conflict]));
    await _pump(tester, controller);
    await _tap(tester, 'sync-remediation-conflicts');
    expect(find.byType(SharingConflictsPage), findsOneWidget);
    expect(controller.calls, isEmpty);
  });

  testWidgets(
    'unknown crypto has honest account scope, no repair action and private-safe copy',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final controller = _Controller(
        CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          lastError: const CollaborationException(
            'crypto_pending:token=secret@example.test',
          ),
        ),
      );
      await _pump(tester, controller, locale: 'en');
      expect(
        find.text('Account: the exact space is not confirmed.'),
        findsOneWidget,
      );
      expect(find.textContaining('cause is not yet confirmed'), findsOneWidget);
      expect(find.textContaining('upgrade'), findsNothing);
      expect(find.textContaining('recreat'), findsNothing);
      for (final action in [
        'email',
        'protection',
        'session',
        'invitations',
        'approvals',
        'rules',
        'conflicts',
      ]) {
        expect(find.byKey(ValueKey('sync-remediation-$action')), findsNothing);
      }
      await _tap(tester, 'sync-error-details');
      await _tap(tester, 'sync-copy-diagnostics');
      final decoded = jsonDecode(copied!) as Map<String, dynamic>;
      expect((decoded['syncFailures'] as List).single, {
        'stage': 'unknown',
        'reason': 'unknown',
      });
      for (final private in [
        sharingScopeId,
        sharingSession().accountId,
        sharingSession().serverUrl,
        sharingScope().name,
        'secret@',
        'token=',
      ]) {
        expect(copied, isNot(contains(private)));
      }
    },
  );

  testWidgets(
    'narrow scaled dialog displays long scope reason and details without overflow',
    (tester) async {
      final controller = _Controller(_state('finance_forbidden'));
      await _pump(tester, controller, narrow: true);
      expect(find.textContaining(sharingScope().name), findsWidgets);
      expect(find.textContaining('nima potrebnega dostopa'), findsOneWidget);
      await _tap(tester, 'sync-error-details');
      expect(
        find.byKey(const ValueKey('sync-safe-diagnostics')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('structured failure prevents green even if older summary is clear', () {
    final state = CollaborationState(
      session: sharingSession(),
      lastSuccessfulSyncAt: _at,
      syncFailures: [_failure('unknown')],
    );
    expect(
      SharingStatusProjection.fromState(state, now: _at).status,
      SharingSyncStatus.problem,
    );
  });
}
