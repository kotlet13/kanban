import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'held_diagnostics_ui_test.dart' show pumpHeldPanel;
import 'sharing_ui_fixture.dart';

void main() {
  for (final language in ['sl', 'en']) {
    testWidgets(
      '19 equal held checkpoints show one summary and preserve export $language',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final failure = SyncFailureDetails(
          stage: SyncFailureStage.preflight,
          occurredAt: DateTime.utc(2026, 11, 2),
          reason: 'crypto_command_receipt_pending',
          heldDiagnostics: HeldSyncDiagnostics(
            remaining: 19,
            samples: List.generate(
              19,
              (_) => const HeldCommandDiagnostic(
                operation: 'crypto2.domain.checkpoint',
                receipt: HeldReceiptResult.unknown,
                resume: HeldResumeResult.ineligible,
                retainedReason: 'scope_reauthorization_required',
              ),
            ),
          ),
        );
        final state = CollaborationState(
          session: sharingSession(),
          syncFailures: [failure],
        );
        await pumpHeldPanel(
          tester,
          SharingUiController(initial: state),
          locale: language,
        );
        expect(find.byKey(const ValueKey('sync-held-group')), findsOneWidget);
        final summary = tester
            .widget<Text>(find.byKey(const ValueKey('sync-held-group')))
            .data!;
        expect(summary, startsWith('19 × '));
        expect(summary.length, lessThan(300));
        expect(
          find.textContaining('scope_reauthorization_required'),
          findsNothing,
        );
        final details = find.byKey(const ValueKey('sync-error-details'));
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        final json = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('sync-safe-diagnostics')),
            )
            .data!;
        expect(
          jsonDecode(json)['syncFailures'][0]['heldCommands']['samples'],
          hasLength(19),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
