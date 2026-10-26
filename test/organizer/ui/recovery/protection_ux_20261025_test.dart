import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_coordinator.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_startup.dart';
import 'package:kanban/organizer/presentation/recovery/account_protection_startup_notice.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_migration_wizard.dart';

const changed = AccountProtectionStartupAssessment(
  AccountProtectionStartupStatus.catalogChanged,
  AccountProtectionStartupReason.catalogChanged,
);
const current = AccountProtectionStartupAssessment(
  AccountProtectionStartupStatus.current,
  AccountProtectionStartupReason.none,
);
const pending = AccountProtectionStartupAssessment(
  AccountProtectionStartupStatus.pending,
  AccountProtectionStartupReason.network,
);
final identity = StateProvider((ref) => 'account-a:device-a');

Future<void> pumpPage(
  WidgetTester tester,
  ProviderContainer container,
  Widget page, {
  double width = 390,
  String language = 'sl',
  double scale = 1.5,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget noticeHome({VoidCallback? onLocal}) => Scaffold(
  body: SingleChildScrollView(
    child: Column(
      children: [
        const AccountProtectionStartupNotice(),
        TextButton(
          onPressed: onLocal ?? () {},
          child: const Text('Retained workspace'),
        ),
      ],
    ),
  ),
);

ProviderContainer noticeContainer({
  required Future<AccountProtectionStartupAssessment?> Function(Ref ref) assess,
  required WidgetBuilder review,
}) => ProviderContainer(
  overrides: [
    accountCryptoStartupIdentityProvider.overrideWith(
      (ref) => ref.watch(identity),
    ),
    accountProtectionStartupAssessmentProvider.overrideWith(assess),
    accountProtectionReviewActionProvider.overrideWith(
      (ref) => AccountCryptoStartupAction(
        identity: ref.watch(identity),
        builder: review,
      ),
    ),
  ],
);

class MigrationFixture implements CryptoMigrationCoordinator {
  MigrationFixture(this.state);
  final CryptoMigrationState state;
  final events = StreamController<CryptoMigrationState>.broadcast();
  int prepares = 0;
  @override
  Stream<CryptoMigrationState> get changes => events.stream;
  @override
  Future<List<CryptoMigrationCandidate>> discoverAvailable() async => [
    const CryptoMigrationCandidate(
      scopeId: 'scope-12345678',
      kind: 'household',
      role: 'owner',
      accessRevision: 1,
      cryptoState: 'ready',
    ),
  ];
  @override
  Future<CryptoMigrationState> inspect(String scopeId) async => state;
  @override
  Future<CryptoMigrationState> prepare(String scopeId) async {
    prepares++;
    return state;
  }

  @override
  Future<void> close() => events.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'changed protection is optional and returning refreshes once without repeating review',
    (tester) async {
      var reads = 0, builds = 0, finished = false;
      final container = noticeContainer(
        assess: (ref) async {
          ref.watch(accountCryptoStartupIdentityProvider);
          reads++;
          return finished ? current : changed;
        },
        review: (context) {
          builds++;
          return Scaffold(
            body: TextButton(
              onPressed: () {
                finished = true;
                Navigator.pop(context);
              },
              child: const Text('Explicitly finish'),
            ),
          );
        },
      );
      addTearDown(container.dispose);
      await pumpPage(tester, container, noticeHome());
      expect(find.text('Retained workspace'), findsOneWidget);
      expect(builds, 0);
      await tester.tap(find.byKey(const ValueKey('account-protection-review')));
      await tester.pumpAndSettle();
      expect(builds, 1);
      tester.view.physicalSize = const Size(430, 900);
      await tester.pumpAndSettle();
      expect(builds, 1);
      await tester.tap(find.text('Explicitly finish'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(
        find.byKey(const ValueKey('account-protection-startup-notice')),
        findsNothing,
      );
      expect(find.text('Retained workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing review preserves changed state and switching identity closes old review without an extra refresh',
    (tester) async {
      var reads = 0;
      final container = noticeContainer(
        assess: (ref) async {
          ref.watch(accountCryptoStartupIdentityProvider);
          reads++;
          return changed;
        },
        review: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close review'),
          ),
        ),
      );
      addTearDown(container.dispose);
      await pumpPage(tester, container, noticeHome());
      await tester.tap(find.byKey(const ValueKey('account-protection-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close review'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(
        find.byKey(const ValueKey('account-protection-review')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('account-protection-review')));
      await tester.pumpAndSettle();
      container.read(identity.notifier).state = 'account-b:device-b';
      await tester.pumpAndSettle();
      expect(find.text('Close review'), findsNothing);
      expect(
        reads,
        3,
      ); // New identity only; old review return did not refresh it.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposing the notice removes only its owned review and never an unrelated current route',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      var reads = 0;
      final container = noticeContainer(
        assess: (ref) async {
          reads++;
          return changed;
        },
        review: (_) => const Scaffold(body: Text('Owned protection review')),
      );
      addTearDown(container.dispose);
      await pumpPage(
        tester,
        container,
        Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, show, _) => Column(
              children: [
                if (show) const AccountProtectionStartupNotice(),
                const Text('Underlying workspace'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('account-protection-review')));
      await tester.pumpAndSettle();
      final navigator = Navigator.of(
        tester.element(find.text('Owned protection review')),
      );
      visible.value = false;
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) =>
                const Scaffold(body: Text('Unrelated current route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unrelated current route'), findsOneWidget);
      expect(
        reads,
        1,
      ); // Disposal does not refresh a no-longer-owned assessment.
      container.read(identity.notifier).state = 'account-b:device-b';
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Owned protection review'), findsNothing);
      expect(find.text('Underlying workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending retry is singleflight while the workspace remains usable',
    (tester) async {
      var reads = 0, localActions = 0;
      final gate = Completer<AccountProtectionStartupAssessment?>();
      final container = noticeContainer(
        assess: (ref) {
          reads++;
          return reads == 1 ? Future.value(pending) : gate.future;
        },
        review: (_) => const SizedBox(),
      );
      addTearDown(container.dispose);
      await pumpPage(
        tester,
        container,
        noticeHome(onLocal: () => localActions++),
      );
      final retry = find.byKey(const ValueKey('account-protection-retry'));
      await tester.tap(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Preverjamo stanje zaščite.'), findsOneWidget);
      expect(retry, findsNothing);
      await tester.tap(find.text('Retained workspace'));
      expect(localActions, 1);
      gate.complete(current);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-protection-startup-notice')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed refresh never presents retained changed evidence as a fresh review',
    (tester) async {
      var fail = false;
      final container = noticeContainer(
        assess: (ref) async {
          if (fail) throw StateError('private failure');
          return changed;
        },
        review: (_) => const SizedBox(),
      );
      addTearDown(container.dispose);
      await pumpPage(tester, container, noticeHome());
      fail = true;
      container.invalidate(accountProtectionStartupAssessmentProvider);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-protection-review')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('account-protection-retry')),
        findsOneWidget,
      );
      expect(find.textContaining('private failure'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in [
    AccountProtectionStartupStatus.current,
    AccountProtectionStartupStatus.setupRequired,
    AccountProtectionStartupStatus.recoveryRequired,
    AccountProtectionStartupStatus.reviewRequired,
  ]) {
    testWidgets(
      'notice does not duplicate required routes or current status $status',
      (tester) async {
        final container = noticeContainer(
          assess: (ref) async => AccountProtectionStartupAssessment(
            status,
            AccountProtectionStartupReason.none,
          ),
          review: (_) => const SizedBox(),
        );
        addTearDown(container.dispose);
        await pumpPage(tester, container, noticeHome());
        expect(
          find.byKey(const ValueKey('account-protection-startup-notice')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final layout in [(390.0, 'sl', 1.5), (1440.0, 'en', 1.0)]) {
    testWidgets(
      'completed wizard exposes one explicit primary with collapsed technical tools $layout',
      (tester) async {
        final fixture = MigrationFixture(
          const CryptoMigrationState(
            scopeId: 'scope-12345678',
            phase: CryptoMigrationPhase.committed,
            legacyCleanupPending: true,
          ),
        );
        var finishes = 0;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await pumpPage(
          tester,
          container,
          CryptoMigrationWizard(
            controller: AccountMigrationController(fixture),
            cachedLabels: const {'scope-12345678': 'Known home'},
            onFinished: () async {
              finishes++;
              return false;
            },
          ),
          width: layout.$1,
          language: layout.$2,
          scale: layout.$3,
        );
        expect(finishes, 0);
        expect(fixture.prepares, 0);
        expect(find.text('Known home'), findsNothing);
        expect(find.byType(FilledButton), findsOneWidget);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(finishes, 1);
        final details = find.byKey(
          const ValueKey('migration_protection_details'),
        );
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(find.text('Known home'), findsOneWidget);
        final tools = find.byKey(
          const ValueKey('migration_scope_details_scope-12345678'),
        );
        final toolsHeader = find.descendant(
          of: tools,
          matching: find.text(
            layout.$2 == 'sl' ? 'Podrobnosti zaščite' : 'Protection details',
          ),
        );
        await tester.scrollUntilVisible(
          toolsHeader,
          250,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 12,
        );
        await tester.pumpAndSettle();
        await tester.tap(toolsHeader);
        await tester.pumpAndSettle();
        expect(
          find.text(
            layout.$2 == 'sl'
                ? 'Priprava zaščite financ'
                : 'Prepare financial protection',
          ),
          findsOneWidget,
        );
        expect(finishes, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pending preparation and blocked recovery remain visible outside technical details',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final fixture = MigrationFixture(
        const CryptoMigrationState(
          scopeId: 'scope-12345678',
          phase: CryptoMigrationPhase.discovery,
          canContinue: true,
        ),
      );
      await pumpPage(
        tester,
        container,
        CryptoMigrationWizard(
          controller: AccountMigrationController(fixture),
          cachedLabels: const {'scope-12345678': 'Pending home'},
        ),
      );
      expect(find.text('Pending home'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Nadaljuj pripravo zaščite'),
        findsOneWidget,
      );
      expect(fixture.prepares, 0);
      fixture.events.add(
        const CryptoMigrationState(
          scopeId: 'scope-12345678',
          phase: CryptoMigrationPhase.blocked,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('migration_scope_recovery_scope-12345678')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Nadaljuj pripravo zaščite'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
