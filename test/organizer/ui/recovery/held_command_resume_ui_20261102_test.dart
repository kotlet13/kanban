import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_wizard.dart';
import 'package:kanban/organizer/presentation/recovery/account_protection_page.dart';
import 'package:kanban/organizer/presentation/shared/sync_failure_panel.dart';
import 'package:kanban/organizer/state/account_crypto_provider.dart';
import 'package:kanban/organizer/state/account_summary_refresh_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import '../sharing_ui_fixture.dart';

class _Store implements CryptoIdentityStore {
  @override
  String get partition => sharingSession().partition;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Directory implements AccountDirectoryRepository {
  bool current = true;
  @override
  bool Function() get isCurrent =>
      () => current;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account implements AccountCryptoV2Workflow {
  int statusReads = 0, phaseReads = 0;
  @override
  final store = _Store();
  @override
  final _Directory directory = _Directory();
  @override
  String get deviceId => sharingSession().deviceId;
  @override
  Future<Map<String, dynamic>> status() async {
    statusReads++;
    return {'initialized': true};
  }

  @override
  Future<String> localPhase() async {
    phaseReads++;
    return 'ready';
  }

  @override
  Future<bool> hasSavedSetup() async => false;
  @override
  Future<bool> hasIncompleteScopeRecovery() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Protection implements AccountProtectionPageController {
  Future<bool> Function()? catalog;
  Future<void> Function()? completing;
  bool closed = false;
  int completes = 0;
  @override
  bool isCurrent(AccountSession? session) =>
      !closed &&
      session?.partition == sharingSession().partition &&
      session?.deviceId == sharingSession().deviceId;
  @override
  Future<bool> needsLegacyMigration() async => await catalog?.call() ?? false;
  @override
  Future<Map<String, dynamic>?> unavailableReview() async => null;
  @override
  Future<void> complete({
    Map<String, dynamic>? reviewedUnavailable,
    void Function(int)? onPause,
  }) async {
    completes++;
    await completing?.call();
  }

  @override
  Future<List<Map<String, dynamic>>> pendingScopeActions() async => [];
  @override
  Future<bool> hasIncompleteScopeRecovery() async => false;
  @override
  Future<void> restoreScopesFromFile(Uint8List file) async =>
      throw StateError('Unexpected import');
  @override
  Future<String?> scopeLabel(String scopeId) async => null;
  @override
  void close() => closed = true;
}

class _Harness {
  final account = _Account();
  final protection = _Protection();
  late SharingUiController collaboration;
  late ProviderContainer container;
}

Future<_Harness> _pumpWizard(
  WidgetTester tester, {
  String locale = 'en',
  Size size = const Size(360, 800),
  double scale = 1.3,
  _Harness? harness,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final h = harness ?? _Harness();
  h.collaboration = SharingUiController(
    initial: CollaborationState(session: sharingSession()),
  );
  final session = sharingSession();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => h.collaboration),
        accountProtectionPageControllerProvider.overrideWithValue(
          (_) => h.protection,
        ),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) {
            h.container = ProviderScope.containerOf(context);
            ref.watch(collaborationProvider);
            ref.watch(
              accountSummaryRefreshProvider((
                session.partition,
                session.deviceId,
              )),
            );
            return AccountCryptoWizard(workflow: h.account);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Future<void> _open(WidgetTester tester, {bool settle = true}) async {
  final action = find.byKey(const ValueKey('account_crypto_migration'));
  await tester.scrollUntilVisible(action, 200);
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

int _refreshes(_Harness h) {
  final session = sharingSession();
  return h.container.read(
    accountSummaryRefreshProvider((session.partition, session.deviceId)),
  );
}

// STOP3: retained future UX fixture only. Wizard behavior and its ARB copy were
// reverted after the bounded attempts; these five controls must not run again
// without explicit user authorization.
const _wizardStop = true;
String _futureNotice(String locale) => locale == 'sl'
    ? 'Preverjanje zaščite računa in razpoložljivih prostorov je uspešno končano. To še ne potrjuje, da so vse spremembe usklajene. Vrni se na uskladitev in izberi »Uskladi zdaj« za preverjanje preostalih sprememb.'
    : 'Account and available space protection checks completed successfully. This does not confirm that all changes are synced. Return to sync and choose “Sync now” to check the remaining changes.';
String _futureReviewLabel(String locale) =>
    locale == 'sl' ? 'Znova preglej zaščito' : 'Review protection again';

void main() {
  for (final locale in ['en', 'sl']) {
    testWidgets(
      'completed protection returns truthful $locale notice and refreshed wizard summary',
      (tester) async {
        final h = await _pumpWizard(
          tester,
          locale: locale,
          size: locale == 'en' ? const Size(360, 800) : const Size(1100, 900),
        );
        expect(h.account.statusReads, 1);
        await _open(tester);
        expect(find.byType(AccountProtectionEntry), findsNothing);
        expect(h.protection.completes, 1);
        expect(h.account.statusReads, 2);
        expect(h.account.phaseReads, 2);
        expect(_refreshes(h), 1);
        final l = await AppLocalizations.delegate.load(Locale(locale));
        await tester.ensureVisible(
          find.byKey(const ValueKey('account_crypto_prepared')),
        );
        expect(find.text(_futureNotice(locale)), findsOneWidget);
        expect(find.text(l.accountRecoveryV2Prepared), findsNothing);
        await tester.scrollUntilVisible(
          find.text(_futureReviewLabel(locale)),
          100,
        );
        await tester.pumpAndSettle();
        expect(find.text(_futureReviewLabel(locale)), findsOneWidget);
        expect(h.collaboration.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
      skip: _wizardStop,
    );
  }

  testWidgets(
    'canceled protection review preserves preparation text without success refresh',
    (tester) async {
      final pending = Completer<bool>();
      final h = _Harness()..protection.catalog = () => pending.future;
      await _pumpWizard(tester, harness: h);
      await _open(tester, settle: false);
      Navigator.of(tester.element(find.byType(AccountProtectionEntry))).pop();
      await tester.pumpAndSettle();
      expect(h.account.statusReads, 1);
      expect(h.protection.completes, 0);
      expect(_refreshes(h), 0);
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(_futureNotice('en')), findsNothing);
      expect(find.text(l.accountRecoveryV2Prepared), findsOneWidget);
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    skip: _wizardStop,
  );

  testWidgets(
    'true result from stale directory never refreshes or labels wizard protection verified',
    (tester) async {
      final h = _Harness();
      h.protection.completing = () async {
        h.account.directory.current = false;
      };
      await _pumpWizard(tester, harness: h);
      await _open(tester);
      expect(h.protection.completes, 1);
      expect(h.account.statusReads, 1);
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(_futureNotice('en')), findsNothing);
      expect(find.text(l.accountRecoveryV2Prepared), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: _wizardStop,
  );

  testWidgets(
    'account switch while protection completes cannot report success in the other account',
    (tester) async {
      final pending = Completer<void>();
      final h = _Harness()..protection.completing = () => pending.future;
      await _pumpWizard(tester, harness: h);
      await _open(tester, settle: false);
      expect(h.protection.completes, 1);
      h.collaboration.switchAccount();
      pending.complete();
      await tester.pumpAndSettle();
      expect(h.account.statusReads, 1);
      expect(find.text(_futureNotice('en')), findsNothing);
      expect(_refreshes(h), 0);
      expect(tester.takeException(), isNull);
    },
    skip: _wizardStop,
  );

  for (final locale in ['en', 'sl']) {
    testWidgets(
      'rotation failure explains key update and opens guarded existing protection $locale route',
      (tester) async {
        final failure = SyncFailureDetails(
          stage: SyncFailureStage.upload,
          occurredAt: DateTime.utc(2026, 11, 2),
          reason: 'scope_rotation_required',
          scopeId: sharingScopeId,
        );
        final controller = SharingUiController(
          initial: CollaborationState(
            session: sharingSession(),
            scopes: [sharingScope()],
            syncFailures: [failure],
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collaborationProvider.overrideWith(() => controller),
              accountCryptoPreviewProvider.overrideWith((ref) async => null),
            ],
            child: MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(collaborationProvider).valueOrNull;
                    if (state == null) return const SizedBox.shrink();
                    return SingleChildScrollView(
                      child: SyncFailurePanel(
                        state: state,
                        failures: [failure],
                        actionsEnabled: true,
                        navigationEnabled: true,
                        onConflicts: () {},
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l = await AppLocalizations.delegate.load(Locale(locale));
        expect(
          find.textContaining(l.syncScopeRotationRequired),
          findsOneWidget,
        );
        final action = find.byKey(
          const ValueKey('sync-remediation-protection'),
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(AccountCryptoPanel), findsOneWidget);
        expect(controller.calls, isEmpty);
        controller.switchAccount();
        await tester.pumpAndSettle();
        expect(find.byType(AccountCryptoPanel), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'held receipt pending explanation cautions against treating retained prior reason as current cause',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Text(
              syncFailureExplanation(context, 'crypto_command_receipt_pending'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('describes that earlier attempt'),
        findsOneWidget,
      );
      expect(
        find.textContaining('does not by itself confirm the current cause'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
