import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/payment_completion_diagnostics.dart';
import 'package:kanban/organizer/presentation/shared/sync_failure_panel.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

final _at = DateTime.utc(2026, 11, 2, 17);

CollaborationState _state(PaymentCompletionDiagnostics details) =>
    CollaborationState(
      session: sharingSession(),
      scopes: [sharingScope()],
      syncFailures: [
        SyncFailureDetails(
          stage: SyncFailureStage.linkedPayments,
          occurredAt: _at,
          reason: 'crypto_payment_checkpoint_pending',
          scopeId: sharingScopeId,
          completionDiagnostics: details,
        ),
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
                if (state == null) return const SizedBox.shrink();
                return SyncFailurePanel(
                  state: state,
                  failures: state.syncFailures,
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
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

String _displayed(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const ValueKey('sync-safe-diagnostics')))
    .data!;

Finder _remediationActions() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('sync-remediation-'),
);

void main() {
  for (final locale in ['sl', 'en']) {
    testWidgets(
      '$locale precise payment history stop shows quarantined safe reason without speculative action',
      (tester) async {
        final controller = SharingUiController(
          initial: _state(
            const PaymentCompletionDiagnostics(
              checkpointStep: PaymentCheckpointStep.projectedHistoryUnverified,
              recordVerdict: PaymentRecordVerdict.quarantined,
              recordReason: 'directory_proof_pending',
            ),
          ),
        );
        await _pump(tester, controller, locale: locale);
        expect(
          find.textContaining(
            locale == 'sl'
                ? 'Zgodovina finančnega zapisa v lokalnem prikazu še ni preverjena.'
                : 'The financial record history in the local display is not yet verified.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale == 'sl'
                ? 'Stanje zapisa: zadržan.'
                : 'Record state: quarantined.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale == 'sl'
                ? 'Varna oznaka vzroka zapisa: directory_proof_pending.'
                : 'Safe record reason: directory_proof_pending.',
          ),
          findsOneWidget,
        );
        expect(_remediationActions(), findsNothing);
        expect(controller.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$locale final received proof mismatch reports exact stop without inventing record reason',
      (tester) async {
        final controller = SharingUiController(
          initial: _state(
            const PaymentCompletionDiagnostics(
              checkpointStep:
                  PaymentCheckpointStep.completionReceivedProofUnmatched,
              recordVerdict: PaymentRecordVerdict.received,
            ),
          ),
        );
        await _pump(tester, controller, locale: locale);
        expect(
          find.textContaining(
            locale == 'sl'
                ? 'Dokazilo prejetega finančnega zapisa se pri končnem preverjanju ne ujema s potrjenim stanjem.'
                : 'The evidence for a received financial record does not match the verified state at the final check.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale == 'sl'
                ? 'Stanje zapisa: prejet.'
                : 'Record state: received.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale == 'sl'
                ? 'Varna oznaka vzroka zapisa:'
                : 'Safe record reason:',
          ),
          findsNothing,
        );
        expect(_remediationActions(), findsNothing);
        expect(controller.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'split final payment state and cursor diagnostics explain distinct stops in SL and EN with independent sample context',
    (tester) async {
      for (final locale in ['sl', 'en']) {
        final sl = locale == 'sl';
        final controller = SharingUiController(
          initial: _state(
            const PaymentCompletionDiagnostics(
              checkpointStep: PaymentCheckpointStep.completionStateMissing,
              recordVerdict: PaymentRecordVerdict.received,
              recordReason: 'directory_proof_pending',
            ),
          ),
        );
        // Dispose the previous locale's provider before installing its fixture.
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(tester, controller, locale: locale);
        final missingState = sl
            ? 'Pri končnem preverjanju manjka lokalno stanje finančnega prostora.'
            : 'The final verification is missing the local financial scope state.';
        final cursorBehind = sl
            ? 'Lokalni prikaz finančnih podatkov še ni dosegel preverjenega zaporedja zapisov.'
            : 'The local financial display has not yet reached the verified record sequence.';
        final sampleContext = sl
            ? 'Podrobnosti vzorčenega čakajočega zapisa; ta zapis ni nujno tisti, ki je ustavil preverjanje.'
            : 'Details of a sampled pending record; this may differ from the record that stopped verification.';
        expect(find.textContaining(missingState), findsOneWidget);
        expect(find.textContaining(cursorBehind), findsNothing);
        expect(find.textContaining(sampleContext), findsOneWidget);
        controller.replace(
          _state(
            const PaymentCompletionDiagnostics(
              checkpointStep:
                  PaymentCheckpointStep.completionProjectionCursorBehind,
              recordVerdict: PaymentRecordVerdict.received,
              recordReason: 'directory_proof_pending',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(cursorBehind), findsOneWidget);
        expect(find.textContaining(missingState), findsNothing);
        expect(find.textContaining(sampleContext), findsOneWidget);
        expect(_remediationActions(), findsNothing);
        await _tap(tester, 'sync-error-details');
        expect(
          find.textContaining(
            sl
                ? 'Stanje in vzrok opisujeta vzorčeni čakajoči zapis, ki ni nujno tisti, ki je ustavil preverjanje.'
                : 'The state and reason describe a sampled pending record, which may differ from the record that stopped verification.',
          ),
          findsOneWidget,
        );
        expect(
          _displayed(tester),
          contains('completionProjectionCursorBehind'),
        );
        expect(controller.calls, isEmpty);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'precise payment details sanitize display and export and copy the identical captured attempt',
    (tester) async {
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
      const privateReason =
          'directory_proof_pending:record=private-record;token=secret@example.test';
      final initial = _state(
        const PaymentCompletionDiagnostics(
          checkpointStep: PaymentCheckpointStep.receivedInventoryUncovered,
          recordVerdict: PaymentRecordVerdict.quarantined,
          recordReason: privateReason,
        ),
      );
      final controller = SharingUiController(initial: initial);
      await _pump(tester, controller);
      expect(
        find.textContaining('Safe record reason: unknown.'),
        findsOneWidget,
      );
      expect(find.textContaining(privateReason), findsNothing);
      await _tap(tester, 'sync-error-details');
      expect(
        find.textContaining(
          'precise payment verification step, record state and safe record reason when available',
        ),
        findsOneWidget,
      );
      final snapshot = _displayed(tester);
      expect((jsonDecode(snapshot) as Map)['syncFailures'], [
        {
          'stage': 'linkedPayments',
          'reason': 'crypto_payment_checkpoint_pending',
          'occurredAt': _at.toIso8601String(),
          'completionDiagnostics': {
            'checkpointStep': 'receivedInventoryUncovered',
            'recordVerdict': 'quarantined',
            'recordReason': 'unknown',
          },
        },
      ]);
      for (final private in [
        sharingScopeId,
        sharingScope().name,
        sharingSession().accountId,
        sharingSession().deviceId,
        sharingSession().serverUrl,
        'private-record',
        'secret@',
        'token=',
      ]) {
        expect(snapshot, isNot(contains(private)));
      }
      final changed = _state(
        const PaymentCompletionDiagnostics(
          checkpointStep: PaymentCheckpointStep.completionCountMismatch,
        ),
      );
      controller.replace(changed);
      await tester.pumpAndSettle();
      expect(_displayed(tester), snapshot);
      await _tap(tester, 'sync-copy-diagnostics');
      expect(copies, [snapshot]);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await _tap(tester, 'sync-error-details');
      final fresh = _displayed(tester);
      expect(fresh, contains('completionCountMismatch'));
      expect(fresh, isNot(contains('receivedInventoryUncovered')));
      await _tap(tester, 'sync-copy-diagnostics');
      expect(copies, [snapshot, fresh]);
      expect(controller.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
