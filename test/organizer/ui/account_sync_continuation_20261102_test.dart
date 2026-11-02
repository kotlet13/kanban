import 'dart:convert';
import 'dart:typed_data';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/presentation/shared/sync_failure_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_startup.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_wizard.dart';
import 'package:kanban/organizer/presentation/recovery/account_protection_page.dart';
import 'package:kanban/organizer/presentation/recovery/scope_recovery_page.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status_dialog.dart';
import 'package:kanban/organizer/state/account_crypto_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';

class _Store implements CryptoIdentityStore {
  _Store(this.partition);
  @override
  final String partition;
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('No storage mutation');
}

class _Directory implements AccountDirectoryRepository {
  @override
  bool Function() get isCurrent =>
      () => true;
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('No directory mutation');
}

class _Protection implements AccountProtectionPageController {
  @override
  bool isCurrent(AccountSession? session) =>
      session?.partition == sharingSession().partition;
  @override
  Future<bool> needsLegacyMigration() async => false;
  @override
  Future<Map<String, dynamic>?> unavailableReview() async => null;
  @override
  Future<void> complete({
    Map<String, dynamic>? reviewedUnavailable,
    void Function(int)? onPause,
  }) async => throw const CryptoAuthorityPending('network');
  @override
  Future<bool> hasIncompleteScopeRecovery() async => false;
  @override
  Future<List<Map<String, dynamic>>> pendingScopeActions() async => [];
  @override
  Future<void> restoreScopesFromFile(Uint8List file) async =>
      throw StateError('No file import');
  @override
  Future<String?> scopeLabel(String scope) async => null;
  @override
  void close() {}
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.session) : store = _Store(session.partition);
  final AccountSession session;
  @override
  final directory = _Directory();
  @override
  Future<String> localPhase() async => 'ready';
  @override
  Future<Map<String, dynamic>> status() async => {'initialized': true};
  @override
  Future<bool> hasIncompleteScopeRecovery() async => false;
  @override
  final CryptoIdentityStore store;
  @override
  String get deviceId => session.deviceId;
  @override
  Future<bool> hasSavedSetup() async => false;
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('No crypto mutation');
}

void main() {
  test('scope error retains safe cause and strips raw payload', () {
    final known = scopeRecoveryFailure(
      const CryptoAuthorityPending('scope_review_policy_projection_pending'),
    );
    expect(known.reason, 'scope_review_policy_projection_pending');
    expect(known.stage, SyncFailureStage.completion);
    expect(known.occurredAt?.isUtc, true);
    final unknown = scopeRecoveryFailure(
      const CryptoAuthorityPending('secret:alice@example.com'),
    );
    final output = syncFailureDiagnosticsJson([known, unknown]);
    expect(output, isNot(contains('alice')));
    expect(output, isNot(contains('secret')));
    expect(
      (jsonDecode(output)['syncFailures'] as List).last['reason'],
      'unknown',
    );
  });

  for (final row in [
    (
      AccountProtectionStartupStatus.reviewRequired,
      AccountProtectionStartupReason.completionMissing,
      true,
    ),
    (
      AccountProtectionStartupStatus.recoveryRequired,
      AccountProtectionStartupReason.scopeRecovery,
      true,
    ),
    (
      AccountProtectionStartupStatus.recoveryRequired,
      AccountProtectionStartupReason.accountRecovery,
      false,
    ),
  ]) {
    testWidgets('startup routes ${row.$2.name} without invoking recovery', (
      tester,
    ) async {
      final session = sharingSession();
      final account = _Account(session);
      final controller = SharingUiController(
        initial: CollaborationState(session: session),
      );
      final container = ProviderContainer(
        overrides: [
          collaborationProvider.overrideWith(() => controller),
          accountCryptoPreviewProvider.overrideWith((ref) async => account),
          accountProtectionStartupAssessmentProvider.overrideWith(
            (ref) async => AccountProtectionStartupAssessment(row.$1, row.$2),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(collaborationProvider.future);
      final action = await container.read(
        accountCryptoStartupActionProvider.future,
      );
      expect(action, isNotNull);
      Widget? built;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              built = action!.builder(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        built,
        row.$3 ? isA<AccountProtectionEntry>() : isA<AccountCryptoWizard>(),
      );
    });
  }

  for (final locale in ['sl', 'en']) {
    testWidgets('hidden queue visible and drained status updates $locale', (
      tester,
    ) async {
      final session = sharingSession();
      final controller = SharingUiController(
        initial: CollaborationState(
          session: session,
          hasUnresolvedSyncWork: true,
          pendingSyncCommandCount: 2,
          blockedSyncCommandCount: 1,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [collaborationProvider.overrideWith(() => controller)],
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
                            onSync: () {},
                            onConflicts: () {},
                          ),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          locale == 'sl'
              ? 'Priprava sinhronizacije še ni končana'
              : 'Sync preparation is not finished',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          locale == 'sl'
              ? 'Čakajoče zahteve sinhronizacije: 2'
              : 'Pending sync requests: 2',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          locale == 'sl'
              ? 'Zadržane zahteve sinhronizacije: 1'
              : 'Held sync requests: 1',
        ),
        findsOneWidget,
      );
      controller.replace(
        CollaborationState(
          session: session,
          lastSuccessfulSyncAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          locale == 'sl'
              ? 'Zadržane zahteve sinhronizacije:'
              : 'Held sync requests:',
        ),
        findsNothing,
      );
      expect(
        find.text(
          locale == 'sl'
              ? 'Priprava sinhronizacije še ni končana'
              : 'Sync preparation is not finished',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final fromSync in [false, true]) {
    testWidgets(
      'new continuation entry from ${fromSync ? "sync error" : "prepared account"}',
      (tester) async {
        final session = sharingSession();
        final account = _Account(session);
        final failure = SyncFailureDetails(
          stage: SyncFailureStage.completion,
          occurredAt: null,
          reason: 'crypto_scope_recovery_incomplete',
        );
        final controller = SharingUiController(
          initial: CollaborationState(
            session: session,
            syncFailures: [failure],
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collaborationProvider.overrideWith(() => controller),
              accountCryptoPreviewProvider.overrideWith((ref) async => account),
              accountProtectionPageControllerProvider.overrideWithValue(
                (_) => _Protection(),
              ),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(collaborationProvider).valueOrNull;
                  ref.watch(accountCryptoPreviewProvider);
                  if (state == null) return const SizedBox();
                  return Scaffold(
                    body: fromSync
                        ? SingleChildScrollView(
                            child: SyncFailurePanel(
                              state: state,
                              failures: [failure],
                              actionsEnabled: true,
                              navigationEnabled: true,
                              onConflicts: () {},
                            ),
                          )
                        : TextButton(
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AccountCryptoWizard(workflow: account),
                              ),
                            ),
                            child: const Text('wizard'),
                          ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (fromSync) {
          await tester.tap(find.text('Review account protection'));
        } else {
          await tester.tap(find.text('wizard'));
          await tester.pumpAndSettle();
          final button = find.byKey(const ValueKey('account_crypto_migration'));
          await tester.scrollUntilVisible(
            button,
            300,
            scrollable: find
                .descendant(
                  of: find.byType(AccountCryptoWizard),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.tap(button);
        }
        await tester.pumpAndSettle();
        expect(find.byType(AccountProtectionEntry), findsOneWidget);
        expect(find.byType(AccountProtectionPage), findsOneWidget);
        expect(
          find.text(
            'The connection failed. Check your network and choose Continue.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('account-protection-import-file')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
