import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status_dialog.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

CollaborationState _state(String reason, {int held = 19}) => CollaborationState(
  session: sharingSession(),
  hasUnresolvedSyncWork: held > 0,
  blockedSyncCommandCount: held,
  // A previous success must not turn a retained failure green.
  lastSuccessfulSyncAt: DateTime.utc(2026, 11, 1),
  syncFailures: [
    SyncFailureDetails(
      stage: SyncFailureStage.completion,
      occurredAt: DateTime.utc(2026, 11, 2),
      reason: reason,
      scopeId: sharingScopeId,
    ),
  ],
);

Future<void> _open(
  WidgetTester tester,
  SharingUiController controller, {
  String locale = 'en',
  double width = 1100,
  required VoidCallback onSync,
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
                        onSync: onSync,
                        onConflicts: () {},
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
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final layout in [('sl', 360.0), ('en', 1100.0)]) {
    testWidgets(
      'held nineteen requests explain receipt check and invoke existing manual retry ${layout.$1}',
      (tester) async {
        var retries = 0;
        final controller = SharingUiController(
          initial: _state('crypto_command_receipt_pending'),
        );
        await _open(
          tester,
          controller,
          locale: layout.$1,
          width: layout.$2,
          onSync: () => retries++,
        );
        final sl = layout.$1 == 'sl';
        expect(
          find.text(
            sl
                ? 'Zadržane zahteve sinhronizacije: 19'
                : 'Held sync requests: 19',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            sl
                ? 'Strežniškega izida obstoječe zahteve'
                : 'The server outcome of an existing sync request',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('sharing-held-sync-guidance')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('sharing-sync-dialog-status')),
              )
              .data,
          sl
              ? 'Sinhronizacija potrebuje tvojo pozornost'
              : 'Synchronization needs your attention',
        );
        expect(
          find.byKey(const ValueKey('sync-remediation-protection')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('sync-remediation-session')),
          findsNothing,
        );
        await _tap(tester, 'sharing-sync-dialog-refresh');
        expect(retries, 1);
        expect(controller.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final row in [
    (
      'crypto_command_rejected',
      'The server rejected an existing sync request.',
      0,
    ),
    (
      'crypto_held_sync_inventory_limit',
      'The safe limit for checking held requests was reached.',
      19,
    ),
    (
      'crypto_payment_quarantined',
      'A linked payment is held because its verification is incomplete.',
      0,
    ),
  ]) {
    testWidgets('safe copied reason and truthful status for ${row.$1}', (
      tester,
    ) async {
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
      final controller = SharingUiController(
        initial: _state(row.$1, held: row.$3),
      );
      await _open(tester, controller, onSync: () {});
      expect(find.textContaining(row.$2), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('sharing-sync-dialog-status')),
            )
            .data,
        'Synchronization needs your attention',
      );
      expect(
        find.byKey(const ValueKey('sharing-held-sync-guidance')),
        row.$3 > 0 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('sync-remediation-protection')),
        findsNothing,
      );
      await _tap(tester, 'sync-error-details');
      await _tap(tester, 'sync-copy-diagnostics');
      expect(copies, hasLength(1));
      expect((jsonDecode(copies.single)['syncFailures'] as List).single, {
        'stage': 'completion',
        'reason': row.$1,
        'occurredAt': DateTime.utc(2026, 11, 2).toIso8601String(),
      });
      expect(copies.single, isNot(contains(sharingScopeId)));
      expect(copies.single, isNot(contains(sharingSession().accountId)));
      expect(copies.single, isNot(contains(sharingSession().serverUrl)));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'captured held retry cannot act after account switch before a frame',
    (tester) async {
      var retries = 0;
      final controller = SharingUiController(
        initial: _state('crypto_command_receipt_pending'),
      );
      await _open(tester, controller, onSync: () => retries++);
      final retry = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('sharing-sync-dialog-refresh')),
          )
          .onPressed!;
      controller.switchAccount();
      retry();
      await tester.pumpAndSettle();
      expect(retries, 0);
      expect(
        find.byKey(const ValueKey('sharing-held-sync-guidance')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held receipt recheck publishes busy attempt and waits for verified completion before green',
    (tester) async {
      final initial = _state('crypto_command_receipt_pending');
      final controller = SharingUiController(initial: initial);
      final receipts = Completer<void>();
      final verification = Completer<void>();
      final attemptedAt = DateTime.utc(2026, 11, 2, 12);
      var retries = 0;
      late Future<void> work;
      await _open(
        tester,
        controller,
        onSync: () {
          retries++;
          work = () async {
            controller.replace(
              CollaborationState(
                session: initial.session,
                isSyncing: true,
                hasUnresolvedSyncWork: true,
                blockedSyncCommandCount: 19,
                lastSyncAttemptAt: attemptedAt,
                lastSuccessfulSyncAt: initial.lastSuccessfulSyncAt,
                syncFailures: initial.syncFailures,
              ),
            );
            await receipts.future;
            // Transport settlement alone cannot confirm a fresh full sync.
            controller.replace(
              CollaborationState(
                session: initial.session,
                syncRequiresRefresh: true,
                lastSyncAttemptAt: attemptedAt,
                lastSuccessfulSyncAt: initial.lastSuccessfulSyncAt,
              ),
            );
            await verification.future;
            controller.replace(
              CollaborationState(
                session: initial.session,
                lastSyncAttemptAt: attemptedAt,
                lastSuccessfulSyncAt: attemptedAt.add(
                  const Duration(seconds: 2),
                ),
              ),
            );
          }();
          unawaited(work);
        },
      );
      await _tap(tester, 'sharing-sync-dialog-refresh');
      String status() => tester
          .widget<Text>(
            find.byKey(const ValueKey('sharing-sync-dialog-status')),
          )
          .data!;
      TextButton retry() => tester.widget<TextButton>(
        find.byKey(const ValueKey('sharing-sync-dialog-refresh')),
      );
      expect(status(), 'Syncing …');
      expect(retry().onPressed, isNull);
      expect(controller.state.requireValue.lastSyncAttemptAt, attemptedAt);
      expect(
        controller.state.requireValue.lastSuccessfulSyncAt,
        initial.lastSuccessfulSyncAt,
      );
      expect(find.textContaining('Held sync requests: 19'), findsOneWidget);

      receipts.complete();
      await tester.pumpAndSettle();
      expect(status(), isNot('Synced'));
      expect(retry().onPressed, isNotNull);
      expect(
        find.byKey(const ValueKey('sharing-held-sync-guidance')),
        findsNothing,
      );
      expect(
        controller.state.requireValue.lastSuccessfulSyncAt,
        initial.lastSuccessfulSyncAt,
      );

      verification.complete();
      await work;
      await tester.pumpAndSettle();
      expect(status(), 'Synced');
      expect(retry().onPressed, isNotNull);
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
