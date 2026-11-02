import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/sync_failure_panel.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

final _at = DateTime.utc(2026, 11, 1, 10);

CollaborationState _state(
  String reason, {
  SyncFailureStage stage = SyncFailureStage.recordPolicy,
  DateTime? at,
}) => CollaborationState(
  session: sharingSession(),
  syncFailures: [
    SyncFailureDetails(stage: stage, reason: reason, occurredAt: at ?? _at),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  SharingUiController controller, {
  String locale = 'en',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [collaborationProvider.overrideWith(() => controller)],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(collaborationProvider).valueOrNull;
                final background = ref.watch(
                  collaborationBackgroundErrorProvider,
                );
                if (state == null) return const SizedBox.shrink();
                return SyncFailurePanel(
                  state: state,
                  failures: sharingSyncFailures(state, background),
                  actionsEnabled: true,
                  navigationEnabled: true,
                  onConflicts: () {},
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _displayed(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const ValueKey('sync-safe-diagnostics')))
    .data!;

List<String> _recordCopies(WidgetTester tester) {
  final copies = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copies.add((call.arguments as Map)['text'] as String);
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
  return copies;
}

void main() {
  for (final entry in {
    'crypto_payment_checkpoint_pending': 'Podpisanega potrdila',
    'crypto_payment_records_pending': 'Nekateri finančni zapisi',
    'crypto_payment_projections_pending': 'Povezanih plačil',
  }.entries) {
    testWidgets(
      '20261102 payment explanation ${entry.key} exports safe category without setup action',
      (tester) async {
        final controller = SharingUiController(
          initial: _state(entry.key, stage: SyncFailureStage.linkedPayments),
        );
        await _pump(tester, controller, locale: 'sl');
        expect(find.textContaining(entry.value), findsOneWidget);
        expect(find.text('Preglej zaščito računa'), findsNothing);
        await _tap(tester, 'sync-error-details');
        expect(_displayed(tester), contains(entry.key));
        expect(_displayed(tester), contains('linkedPayments'));
      },
    );
  }
  testWidgets(
    'details and copy retain displayed attempt across async changes and tap race; reopening refreshes',
    (tester) async {
      final copies = _recordCopies(tester);
      final initial = _state(
        'crypto_reconciliation_required',
        stage: SyncFailureStage.preflight,
      );
      final controller = SharingUiController(initial: initial);
      await _pump(tester, controller);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SyncFailurePanel)),
      );
      final openDisplayedAttempt = tester
          .widget<TextButton>(find.byKey(const ValueKey('sync-error-details')))
          .onPressed!;

      // A provider update before the next frame must not replace the attempt
      // whose panel the user was reading when they tapped Error details.
      final newer = _state(
        'directory_proof_pending',
        at: _at.add(const Duration(minutes: 1)),
      );
      controller.replace(newer);
      openDisplayedAttempt();
      await tester.pumpAndSettle();
      final snapshot = _displayed(tester);
      expect(snapshot, syncFailureDiagnosticsJson(initial.syncFailures));
      expect(snapshot, contains('crypto_reconciliation_required'));
      expect(snapshot, isNot(contains('directory_proof_pending')));

      final changed = Completer<void>();
      final update = changed.future.then((_) {
        controller.replace(CollaborationState(session: sharingSession()));
        container.read(collaborationBackgroundErrorProvider.notifier).state =
            const CollaborationException('timeout');
      });
      changed.complete();
      await update;
      await tester.pumpAndSettle();
      expect(_displayed(tester), snapshot);
      await _tap(tester, 'sync-copy-diagnostics');
      expect(copies, [snapshot]);

      // Exercise the Copy callback before the provider update paints a frame.
      final copyDisplayedAttempt = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('sync-copy-diagnostics')),
          )
          .onPressed!;
      controller.replace(newer);
      container.read(collaborationBackgroundErrorProvider.notifier).state =
          null;
      copyDisplayedAttempt();
      await tester.pumpAndSettle();
      expect(_displayed(tester), snapshot);
      expect(copies, [snapshot, snapshot]);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await _tap(tester, 'sync-error-details');
      final refreshed = _displayed(tester);
      expect(refreshed, syncFailureDiagnosticsJson(newer.syncFailures));
      await _tap(tester, 'sync-copy-diagnostics');
      expect(copies.last, refreshed);
      expect(((jsonDecode(refreshed) as Map)['syncFailures'] as List).single, {
        'stage': 'recordPolicy',
        'reason': 'directory_proof_pending',
        'occurredAt': newer.syncFailures.single.occurredAt!.toIso8601String(),
      });
    },
  );

  testWidgets(
    'switching accounts blocks stale Copy before a frame and closes snapshot',
    (tester) async {
      final copies = _recordCopies(tester);
      final controller = SharingUiController(
        initial: _state('directory_proof_pending'),
      );
      await _pump(tester, controller);
      await _tap(tester, 'sync-error-details');
      final staleCopy = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('sync-copy-diagnostics')),
          )
          .onPressed!;
      controller.switchAccount();
      staleCopy();
      await tester.pumpAndSettle();
      expect(copies, isEmpty);
      expect(find.byKey(const ValueKey('sync-safe-diagnostics')), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['sl', 'en']) {
    testWidgets(
      '$locale directory proof explains signer evidence and retry without permission/key action',
      (tester) async {
        final controller = SharingUiController(
          initial: _state('directory_proof_pending'),
        );
        await _pump(tester, controller, locale: locale);
        final sl = locale == 'sl';
        expect(
          find.textContaining(
            sl ? 'Preverjanje pravil za zapise:' : 'Verifying record rules:',
          ),
          findsOneWidget,
        );
        for (final text
            in sl
                ? [
                    'Dokazila o identiteti podpisnika še ni bilo mogoče pridobiti ali preveriti',
                    'sama ne pomeni manjkajočih dovoljenj',
                    'ne zahteva novega računa ali ključev',
                    'Izberi »Uskladi zdaj«, da aplikacija ponovi preverjanje',
                  ]
                : [
                    'signer’s identity could not yet be obtained or verified',
                    'does not mean missing permissions',
                    'does not require a new account or keys',
                    'Choose “Sync now” to retry verification',
                  ]) {
          expect(find.textContaining(text), findsOneWidget);
        }
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'sync-remediation-',
                ),
          ),
          findsNothing,
        );
        expect(
          find.textContaining(sl ? 'Preveri omrežje' : 'Check your network'),
          findsNothing,
        );
        expect(controller.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
