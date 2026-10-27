import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status_projection.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';

final _checked = DateTime.utc(2026, 10, 27, 9, 30);
SharingSyncStatus _status(
  CollaborationState state, {
  SharingStatusSupplement supplement = const SharingStatusSupplement(),
  bool private = false,
}) => SharingStatusProjection.fromState(
  state,
  now: _checked,
  supplement: supplement,
  privateSync: private,
).status;

void main() {
  test(
    'change check is distinct from transfer and all existing debt has precedence',
    () {
      CollaborationState state({
        int pending = 0,
        int blocked = 0,
        bool unresolved = false,
        bool refresh = false,
        CollaborationException? error,
        bool invalid = false,
      }) => CollaborationState(
        session: sharingSession(),
        lastSuccessfulChangeCheckAt: _checked,
        pendingCount: pending,
        blockedCount: blocked,
        hasUnresolvedSyncWork: unresolved,
        syncRequiresRefresh: refresh,
        lastError: error,
        sessionInvalid: invalid,
      );
      expect(_status(state()), SharingSyncStatus.checked);
      expect(_status(state(pending: 1)), SharingSyncStatus.pending);
      expect(_status(state(unresolved: true)), SharingSyncStatus.pending);
      expect(_status(state(blocked: 1)), SharingSyncStatus.problem);
      expect(_status(state(refresh: true)), SharingSyncStatus.unknown);
      expect(
        _status(state(error: const CollaborationException('network'))),
        SharingSyncStatus.offline,
      );
      expect(_status(state(invalid: true)), SharingSyncStatus.problem);
      expect(
        _status(
          state(),
          supplement: const SharingStatusSupplement(requiresRefresh: true),
        ),
        SharingSyncStatus.unknown,
      );
      expect(
        _status(
          state(),
          supplement: const SharingStatusSupplement(pendingCount: 1),
        ),
        SharingSyncStatus.pending,
      );
      expect(
        _status(
          state(),
          supplement: const SharingStatusSupplement(hasProblem: true),
        ),
        SharingSyncStatus.problem,
      );
    },
  );

  test(
    'full sync history cannot hide separately projected crypto or admission debt',
    () {
      expect(
        _status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _checked,
            hasUnresolvedSyncWork: true,
          ),
        ),
        SharingSyncStatus.pending,
      );
      expect(
        _status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulSyncAt: _checked,
            syncRequiresRefresh: true,
          ),
        ),
        SharingSyncStatus.unknown,
      );
      expect(
        _status(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulChangeCheckAt: _checked,
          ),
          private: true,
        ),
        SharingSyncStatus.disabled,
      );
    },
  );

  for (final locale in ['sl', 'en']) {
    testWidgets(
      '$locale check detail is live and keeps transfer timestamps unconfirmed',
      (tester) async {
        final controller = SharingUiController(
          initial: CollaborationState(
            session: sharingSession(),
            lastChangeCheckAttemptAt: _checked,
            lastSuccessfulChangeCheckAt: _checked,
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
                    return state == null
                        ? const SizedBox()
                        : SharingStatus(
                            state: state,
                            onSync: () {},
                            onConflicts: () {},
                          );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('sharing-sync-status-cloud')),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(AlertDialog)),
        )!;
        expect(find.text(l.syncStatusChecked), findsOneWidget);
        expect(
          find.text('${l.syncStatusLastSuccess}: ${l.syncStatusNotConfirmed}'),
          findsOneWidget,
        );
        expect(
          find.text(
            '${l.syncStatusLastAttempt}: ${l.syncStatusNeverAttempted}',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('${l.syncStatusLastChangeCheckSuccess}:'),
          findsOneWidget,
        );
        expect(
          find.textContaining('${l.syncStatusLastChangeCheckAttempt}:'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
        controller.replace(
          CollaborationState(
            session: sharingSession(),
            lastSuccessfulChangeCheckAt: _checked,
            pendingCount: 1,
          ),
        );
        await tester.pump();
        expect(find.text(l.syncStatusPending), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
