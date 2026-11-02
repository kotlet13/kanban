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

CollaborationState sampleState({int records = 2}) => CollaborationState(
  session: sharingSession(),
  syncTransfer: SyncTransferEvidence(
    startedAt: _at,
    contentPages: 1,
    contentRecords: records,
  ),
  syncFailures: [
    SyncFailureDetails(
      stage: SyncFailureStage.preflight,
      occurredAt: _at,
      reason: 'crypto_command_receipt_pending',
      heldDiagnostics: HeldSyncDiagnostics(
        remaining: 3,
        samples: [
          const HeldCommandDiagnostic(
            operation: 'crypto2.domain.checkpoint',
            receipt: HeldReceiptResult.unknown,
            resume: HeldResumeResult.guardBlocked,
            currentReason: 'crypto_device_keys_pending',
            retainedReason: 'scope_rotation_required',
          ),
        ],
      ),
    ),
  ],
);
void main() {
  test(
    'safe export bounds samples and strips untrusted operation and reason strings',
    () {
      final details = HeldSyncDiagnostics(
        remaining: 100,
        samples: List.generate(
          30,
          (_) => const HeldCommandDiagnostic(
            operation: 'private@example.invalid',
            currentReason: 'secret-key',
            retainedReason: 'private-scope',
          ),
        ),
      );
      final json = syncFailureDiagnosticsJson([
        SyncFailureDetails(
          stage: SyncFailureStage.preflight,
          occurredAt: _at,
          reason: 'crypto_command_receipt_pending',
          scopeId: 'secret-id',
          heldDiagnostics: details,
        ),
      ]);
      expect(json, isNot(contains('secret')));
      expect(json, isNot(contains('private')));
      final data = jsonDecode(json) as Map;
      final held = (data['syncFailures'] as List).single['heldCommands'];
      expect(held['remaining'], 100);
      expect(held['samples'], hasLength(20));
      expect(held['samples'][0]['operation'], 'other');
    },
  );
  for (final locale in ['sl', 'en']) {
    testWidgets(
      'partial receipt UI $locale shows committed downloads and separates fresh from retained reason',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = SharingUiController(initial: sampleState());
        await _pump(tester, controller, locale: locale);
        expect(
          find.byKey(const ValueKey('sync-transfer-evidence')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('sync-held-count')), findsOneWidget);
        expect(
          find.textContaining(
            locale == 'sl' ? 'Trenutni razlog' : 'Current reason',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale == 'sl'
                ? 'Prej shranjen razlog'
                : 'Previously retained reason',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            locale == 'sl'
                ? 'Preglej zaščito računa'
                : 'Review account protection',
          ),
          findsNothing,
        );
        await _tap(tester, 'sync-error-details');
        final data = jsonDecode(_displayed(tester)) as Map;
        expect(data['transfer']['appliedContentRecords'], 2);
        expect(
          data['syncFailures'][0]['heldCommands']['samples'][0]['receipt'],
          'unknown',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'diagnostic copy freezes held sample and transfer counts while later sync updates',
    (tester) async {
      final copies = _recordCopies(tester);
      final first = sampleState();
      final controller = SharingUiController(initial: first);
      await _pump(tester, controller);
      await _tap(tester, 'sync-error-details');
      final shown = _displayed(tester);
      controller.replace(sampleState(records: 99));
      await tester.pumpAndSettle();
      await _tap(tester, 'sync-copy-diagnostics');
      expect(copies.single, shown);
      expect(
        shown,
        syncFailureDiagnosticsJson(
          first.syncFailures,
          transfer: first.syncTransfer,
        ),
      );
      expect(jsonDecode(shown)['transfer']['appliedContentRecords'], 2);
    },
  );
  testWidgets(
    'held blockers explain protection in plain language at mobile width',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = SharingUiController(initial: sampleState());
      await _pump(tester, controller, locale: 'sl');
      expect(
        find.textContaining(
          'Za ta del uskladitve je potreben pregled priprave zaščite',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('scope_rotation_required'), findsNothing);
      expect(find.textContaining('crypto_device_keys_pending'), findsNothing);
      await _tap(tester, 'sync-error-details');
      expect(_displayed(tester), contains('scope_rotation_required'));
      expect(_displayed(tester), contains('crypto_device_keys_pending'));
      expect(tester.takeException(), isNull);
    },
  );
}
