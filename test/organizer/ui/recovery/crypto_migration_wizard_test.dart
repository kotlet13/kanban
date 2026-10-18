import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/l10n.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_coordinator.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_migration_wizard.dart';

const _id = '11111111-1111-4111-8111-111111111111';

class _Controller implements CryptoMigrationController {
  final events = StreamController<CryptoMigrationState>.broadcast();
  List<CryptoMigrationCandidate> candidates = [
    const CryptoMigrationCandidate(
      scopeId: _id,
      kind: 'household',
      role: 'owner',
      accessRevision: 0,
    ),
  ];
  CryptoMigrationState state = const CryptoMigrationState(
    scopeId: _id,
    phase: CryptoMigrationPhase.discovery,
    canContinue: true,
  );
  int prepares = 0, resumes = 0;
  bool fail = false;
  @override
  Stream<CryptoMigrationState> get changes => events.stream;
  @override
  Future<List<CryptoMigrationCandidate>> discoverAvailable() async {
    if (fail) throw StateError('secret backend detail');
    return candidates;
  }

  @override
  Future<CryptoMigrationState> inspect(String scopeId) async => state;
  @override
  Future<CryptoMigrationState> prepare(String scopeId) async {
    prepares++;
    return state = const CryptoMigrationState(
      scopeId: _id,
      phase: CryptoMigrationPhase.waitingContributors,
      migrationId: _id,
      pendingContributionCount: 2,
    );
  }

  @override
  Future<CryptoMigrationState> resume(String migrationId) async {
    resumes++;
    return state;
  }

  int retries = 0;
  @override
  Future<CryptoMigrationState> retryPending(String migrationId) async {
    retries++;
    return state;
  }

  int archives = 0;
  @override
  Future<CryptoMigrationState> archiveAndVerify(
    String migrationId, {
    required Uint8List recoveryFile,
  }) async {
    expect(recoveryFile, [7]);
    archives++;
    return state;
  }

  int fences = 0;
  @override
  Future<CryptoMigrationInventoryReview> review(String migrationId) async =>
      const CryptoMigrationInventoryReview(
        inventoryHash: 'reviewed',
        tableCount: 2,
        rowCount: 4,
        fileCount: 1,
        fileBytes: 32,
        pendingContributionCount: 0,
        unavailableContributionCount: 0,
      );
  @override
  Future<CryptoMigrationState> fence(
    String migrationId, {
    required String reviewedInventoryHash,
  }) async {
    expect(reviewedInventoryHash, 'reviewed');
    fences++;
    return state;
  }

  @override
  Future<void> close() async => events.close();
}

class _Files extends RecoveryFileIo {
  final buffer = Uint8List.fromList([7]);
  @override
  Future<Uint8List?> pick() async => buffer;
}

Future<void> _pump(
  WidgetTester tester,
  _Controller controller, {
  String locale = 'en',
  bool largeText = false,
  Future<bool> Function()? onFinished,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [recoveryFileIoProvider.overrideWithValue(_Files())],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
          child: child!,
        ),
        home: CryptoMigrationWizard(
          controller: controller,
          onFinished: onFinished,
          cachedLabels: const {_id: 'Home'},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'declined unavailable-scope completion stays open and does not acknowledge protection',
    (tester) async {
      final controller = _Controller()..candidates = [];
      var attempts = 0;
      await _pump(
        tester,
        controller,
        onFinished: () async {
          attempts++;
          return false;
        },
      );
      final done = find.widgetWithText(TextButton, 'Done');
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.byType(CryptoMigrationWizard), findsOneWidget);
      expect(find.text('Continue locally'), findsOneWidget);
    },
  );

  for (final locale in ['sl', 'en']) {
    testWidgets(
      '320px 2x $locale waiting and retained history stay scrollable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final phase in [
          CryptoMigrationPhase.waitingContributors,
          CryptoMigrationPhase.committed,
        ]) {
          final controller = _Controller()
            ..state = CryptoMigrationState(
              scopeId: _id,
              phase: phase,
              pendingContributionCount:
                  phase == CryptoMigrationPhase.waitingContributors ? 2 : 0,
            );
          await _pump(tester, controller, locale: locale, largeText: true);
          expect(tester.takeException(), isNull);
          final done = find.widgetWithText(
            TextButton,
            phase == CryptoMigrationPhase.committed
                ? (locale == 'sl' ? 'Končano' : 'Done')
                : (locale == 'sl' ? 'Nadaljuj lokalno' : 'Continue locally'),
          );
          await tester.scrollUntilVisible(done, 160);
          await tester.ensureVisible(done);
          await tester.pumpAndSettle();
          expect(done.hitTestable(), findsOneWidget);
          expect(find.text(_id), findsNothing);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }

  testWidgets('prepare retains local data and waits without repeated consent', (
    tester,
  ) async {
    final c = _Controller();
    await _pump(tester, c);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text(_id), findsNothing);
    await tester.tap(find.text('Continue protection setup'));
    await tester.pumpAndSettle();
    expect(c.prepares, 1);
    expect(find.text('Waiting for 2 contributors.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('migration_local_preserved')),
      findsOneWidget,
    );
    expect(find.text('Continue protection setup'), findsNothing);
  });
  testWidgets('unavailable contributor cannot authorize preparation', (
    tester,
  ) async {
    final c = _Controller()
      ..state = const CryptoMigrationState(
        scopeId: _id,
        phase: CryptoMigrationPhase.unavailable,
        unavailableContributionCount: 1,
      );
    await _pump(tester, c);
    expect(find.text('Continue protection setup'), findsNothing);
    expect(c.prepares, 0);
    expect(find.textContaining('update and open Jivie'), findsOneWidget);
  });
  testWidgets('existing journal resumes without another prepare', (
    tester,
  ) async {
    final c = _Controller()
      ..state = const CryptoMigrationState(
        scopeId: _id,
        phase: CryptoMigrationPhase.archiving,
        migrationId: _id,
        canContinue: true,
      );
    await _pump(tester, c);
    await tester.tap(find.text('Retry verification'));
    await tester.pumpAndSettle();
    expect(c.archives, 1);
    expect(c.resumes, 0);
    expect(c.prepares, 0);
  });
  testWidgets(
    'explicit existing journal retry reaches unresolved receipt reconciliation',
    (tester) async {
      final c = _Controller()
        ..state = const CryptoMigrationState(
          scopeId: _id,
          phase: CryptoMigrationPhase.verifying,
          migrationId: _id,
          canContinue: true,
        );
      await _pump(tester, c);
      await tester.tap(find.text('Retry verification'));
      await tester.pumpAndSettle();
      expect(c.retries, 1);
      expect(c.resumes, 0);
      expect(c.prepares, 0);
    },
  );
  testWidgets(
    'fresh account has explicit finish and no empty-data replacement',
    (tester) async {
      final c = _Controller()..candidates = [];
      await _pump(tester, c);
      expect(find.text('Done'), findsOneWidget);
      expect(
        find.textContaining('local data remains available'),
        findsOneWidget,
      );
    },
  );
  testWidgets('Slovenian pending and safe error preserve retry', (
    tester,
  ) async {
    final c = _Controller()..fail = true;
    await _pump(tester, c, locale: 'sl');
    expect(find.text('Zaščita povezanih podatkov'), findsOneWidget);
    expect(find.textContaining('secret backend detail'), findsNothing);
    c.fail = false;
    await tester.tap(find.text('Ponovi preverjanje'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
  testWidgets('fence requires review consent and cancel sends nothing', (
    tester,
  ) async {
    final c = _Controller()
      ..state = const CryptoMigrationState(
        scopeId: _id,
        phase: CryptoMigrationPhase.preparing,
        migrationId: _id,
        canContinue: true,
      );
    await _pump(tester, c);
    await tester.tap(find.text('Retry verification'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('4 saved rows and 1 files.'), findsOneWidget);
    expect(c.fences, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.fences, 0);
    await tester.tap(find.text('Retry verification'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirm this data'));
    await tester.pumpAndSettle();
    expect(c.fences, 1);
  });
}
