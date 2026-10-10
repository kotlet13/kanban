import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/organizer_widgets.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status_projection.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

final _success = DateTime.utc(2026, 10, 10, 10, 20);
final _attempt = DateTime.utc(2026, 10, 10, 10, 30);
SharedFinanceConflict _financeConflict() => SharedFinanceConflict(
  id: 'finance',
  scopeId: sharingScopeId,
  recordId: 'entry',
  recordType: SharedFinanceRecordType.financeEntry,
  reason: 'conflict',
);

Future<void> _pump(
  WidgetTester tester,
  SharingUiController controller, {
  double width = 390,
  double textScale = 1,
  bool reduceMotion = true,
  String locale = 'sl',
  VoidCallback? onSync,
  VoidCallback? onConflicts,
  VoidCallback? onExport,
  VoidCallback? onConnect,
  bool allowLocalActions = false,
  ValueNotifier<bool>? busy,
  ValueNotifier<SharingStatusSupplement>? supplement,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [collaborationProvider.overrideWith(() => controller)],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(collaborationProvider).valueOrNull;
                return state == null
                    ? const SizedBox()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OrganizerHeading(
                            title: 'Opravila in načrtovani projekti',
                            titleAccessory: SharingStatus(
                              state: state,
                              onSync: onSync ?? () {},
                              onConflicts: onConflicts ?? () {},
                              onExport: onExport,
                              onConnect: onConnect,
                              scopeId: sharingScopeId,
                              allowLocalActions: allowLocalActions,
                              busyListenable: busy,
                              supplementListenable: supplement,
                            ),
                          ),
                          const Text(
                            'Vsebina',
                            key: ValueKey('stable-content'),
                          ),
                        ],
                      );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _details(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('sharing-sync-status-cloud')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test(
    'confirmed green requires successful complete sync and every queue clear',
    () {
      SharingSyncStatus status(
        CollaborationState state, {
        bool private = false,
      }) => SharingStatusProjection.fromState(
        state,
        now: DateTime.utc(2026),
        privateSync: private,
      ).status;
      expect(
        status(CollaborationState(session: sharingSession())),
        SharingSyncStatus.unknown,
      );
      expect(
        status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _success,
          ),
        ),
        SharingSyncStatus.synced,
      );
      expect(
        status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _success,
            financePendingCount: 1,
          ),
        ),
        SharingSyncStatus.pending,
      );
      expect(
        status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _success,
            financeConflicts: [_financeConflict()],
          ),
        ),
        SharingSyncStatus.problem,
      );
      expect(
        status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _success,
            financeBlockedCount: 1,
          ),
        ),
        SharingSyncStatus.problem,
      );
      expect(
        status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _success,
            sessionInvalid: true,
          ),
        ),
        SharingSyncStatus.problem,
      );
      expect(
        status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _success,
          ),
          private: true,
        ),
        SharingSyncStatus.disabled,
      );
      expect(
        status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _success,
            privateSync: const PrivateSyncState(enabled: true, paused: true),
          ),
          private: true,
        ),
        SharingSyncStatus.paused,
      );
      final counts = SharingStatusProjection.fromState(
        CollaborationState(
          session: sharingSession(),
          pendingCount: 5,
          financePendingCount: 3,
          blockedCount: 2,
          financeBlockedCount: 1,
        ),
        now: DateTime.utc(2026),
      );
      expect(counts.pending, 5);
      expect(counts.blocked, 3);
    },
  );

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'all statuses reserve identical heading and content positions $width at 1.5 text scale',
      (tester) async {
        final controller = SharingUiController(
          initial: CollaborationState(session: sharingSession()),
        );
        await _pump(tester, controller, width: width, textScale: 1.5);
        final headingRect = tester.getRect(find.byType(OrganizerHeading));
        final contentRect = tester.getRect(
          find.byKey(const ValueKey('stable-content')),
        );
        for (final state in [
          CollaborationState(),
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _success,
          ),
          CollaborationState(session: sharingSession(), pendingCount: 3),
          CollaborationState(session: sharingSession(), isSyncing: true),
          CollaborationState(
            session: sharingSession(),
            lastError: const CollaborationException('network'),
          ),
          CollaborationState(
            session: sharingSession(),
            financeConflicts: [_financeConflict()],
          ),
        ]) {
          controller.replace(state);
          await tester.pump();
          expect(
            tester.getSize(find.byType(SharingStatus)),
            const Size(88, 48),
          );
          expect(tester.getRect(find.byType(OrganizerHeading)), headingRect);
          expect(
            tester.getRect(find.byKey(const ValueKey('stable-content'))),
            contentRect,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'overlay updates during sync and reports account evidence without duplicate finance counts',
    (tester) async {
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          pendingCount: 5,
          financePendingCount: 3,
          blockedCount: 2,
          financeBlockedCount: 1,
          financeConflicts: [_financeConflict()],
          lastSuccessfulSyncAt: _success,
          lastSyncAttemptAt: _attempt,
          lastError: const CollaborationException('network'),
        ),
      );
      await _pump(tester, controller);
      await _details(tester);
      expect(find.text('Strežnik ni dosegljiv'), findsOneWidget);
      expect(find.text('Čakajoče spremembe: 5'), findsOneWidget);
      expect(find.text('Sporne spremembe: 1'), findsOneWidget);
      expect(find.text('Zadržane spremembe: 3'), findsOneWidget);
      expect(find.textContaining('veljajo za ta račun'), findsOneWidget);
      expect(find.textContaining('Zadnja uspešna uskladitev:'), findsOneWidget);
      controller.replace(
        CollaborationState(
          session: sharingSession(),
          isSyncing: true,
          lastSyncAttemptAt: _attempt,
        ),
      );
      await tester.pump();
      expect(find.text('Usklajujem …'), findsOneWidget);
      final refresh = tester.widget<TextButton>(
        find.byKey(const ValueKey('sharing-sync-dialog-refresh')),
      );
      expect(refresh.onPressed, isNull);
      controller.replace(
        CollaborationState(
          session: sharingSession(),
          lastSuccessfulSyncAt: _attempt,
          lastSyncAttemptAt: _attempt,
        ),
      );
      await tester.pump();
      expect(find.text('Usklajeno'), findsOneWidget);
      expect(find.text('Čakajoče spremembe: 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual sync conflicts and local rescue actions stay in details',
    (tester) async {
      var refreshes = 0, conflicts = 0, exports = 0;
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          pendingCount: 1,
          financeConflicts: [_financeConflict()],
        ),
      );
      await _pump(
        tester,
        controller,
        onSync: () => refreshes++,
        onConflicts: () => conflicts++,
        onExport: () => exports++,
      );
      expect(find.text('Uskladi zdaj'), findsNothing);
      await _details(tester);
      await tester.tap(
        find.byKey(const ValueKey('sharing-sync-dialog-refresh')),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Preglej spremembe'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(TextButton, 'Shrani moje neusklajene spremembe'),
      );
      await tester.pump();
      expect([refreshes, conflicts, exports], [1, 1, 1]);
      controller.replace(
        CollaborationState(
          session: sharingSession(),
          sessionInvalid: true,
          pendingCount: 1,
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('sharing-sync-dialog-refresh')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.widgetWithText(TextButton, 'Shrani moje neusklajene spremembe'),
      );
      expect(exports, 2);
    },
  );

  testWidgets(
    'unknown server errors are localized and account switch removes all previous evidence and actions',
    (tester) async {
      var refreshes = 0;
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          lastSuccessfulSyncAt: _success,
          lastError: const CollaborationException(
            'unrecognized_private_diagnostic',
          ),
        ),
      );
      await _pump(tester, controller, onSync: () => refreshes++);
      await _details(tester);
      expect(
        find.textContaining('unrecognized_private_diagnostic'),
        findsNothing,
      );
      controller.switchAccount();
      await tester.pump();
      expect(find.textContaining('Zadnja uspešna uskladitev:'), findsNothing);
      expect(
        find.byKey(const ValueKey('sharing-sync-dialog-refresh')),
        findsNothing,
      );
      expect(refreshes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('local mode exposes local retry only when explicitly enabled', (
    tester,
  ) async {
    var refreshes = 0;
    final controller = SharingUiController(initial: CollaborationState());
    await _pump(
      tester,
      controller,
      allowLocalActions: true,
      onSync: () => refreshes++,
    );
    await _details(tester);
    expect(find.text('Lokalno na tej napravi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sharing-sync-dialog-refresh')));
    expect(refreshes, 1);
  });

  testWidgets('supplement status and counts stay live in the open dialog', (
    tester,
  ) async {
    final controller = SharingUiController(
      initial: CollaborationState(
        session: sharingSession(),
        lastSuccessfulSyncAt: _success,
      ),
    );
    final supplement = ValueNotifier(
      const SharingStatusSupplement(label: 'Povezana plačila'),
    );
    addTearDown(supplement.dispose);
    await _pump(tester, controller, supplement: supplement);
    await _details(tester);
    expect(find.text('Usklajeno'), findsOneWidget);
    supplement.value = const SharingStatusSupplement(
      label: 'Povezana plačila',
      pendingCount: 4,
      blockedCount: 1,
      hasProblem: true,
    );
    await tester.pump();
    expect(find.text('Čakajoče spremembe: 4'), findsOneWidget);
    expect(find.text('Zadržane spremembe: 1'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
    supplement.value = const SharingStatusSupplement(
      label: 'Povezana plačila',
      requiresRefresh: true,
    );
    await tester.pump();
    expect(find.text('Uskladitev še ni potrjena'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
    supplement.value = const SharingStatusSupplement(
      label: 'Povezana plačila',
      isOffline: true,
    );
    await tester.pump();
    expect(find.text('Strežnik ni dosegljiv'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('revoked or blocked context cannot inherit account green', () {
    for (final scope in [
      sharingScope(revoked: true),
      sharingScope(blocked: true),
    ]) {
      final state = CollaborationState(
        session: sharingSession(),
        scopes: [scope],
        lastSuccessfulSyncAt: _success,
      );
      expect(
        SharingStatusProjection.fromState(
          state,
          now: DateTime.utc(2026),
          scopeId: sharingScopeId,
        ).status,
        SharingSyncStatus.problem,
      );
    }
  });

  testWidgets(
    'reduced motion stops the refresh rotation while the fixed slot remains',
    (tester) async {
      final controller = SharingUiController(
        initial: CollaborationState(session: sharingSession(), isSyncing: true),
      );
      await _pump(tester, controller, reduceMotion: false);
      final rotation = tester
          .widget<RotationTransition>(
            find.byKey(const ValueKey('sharing-sync-refresh-rotation')),
          )
          .turns;
      await tester.pump(const Duration(milliseconds: 250));
      expect(rotation.value, greaterThan(0));
      await _pump(tester, controller, reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        MediaQuery.of(
          tester.element(
            find.byKey(const ValueKey('sharing-sync-status-cloud')),
          ),
        ).disableAnimations,
        true,
      );
      expect(
        find.byKey(const ValueKey('sharing-sync-refresh-rotation')),
        findsNothing,
      );
      expect(tester.getSize(find.byType(SharingStatus)), const Size(88, 48));
      expect(tester.takeException(), isNull);
    },
  );
}
