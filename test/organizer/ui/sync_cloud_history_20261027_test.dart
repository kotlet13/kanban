import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status_projection.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

void main() {
  final historical = DateTime.utc(2026, 10, 26, 10, 20);
  final current = DateTime.utc(2026, 10, 27, 10, 20);
  for (final status in ['historical', 'checked', 'synced']) {
    testWidgets(
      '$status cloud shows honest icon, color, tooltip and timestamps',
      (tester) async {
        final state = CollaborationState(
          session: sharingSession(),
          previousSuccessfulSyncAt: historical,
          lastSuccessfulChangeCheckAt: status == 'checked' ? current : null,
          lastSuccessfulSyncAt: status == 'synced' ? current : null,
        );
        final controller = SharingUiController(initial: state);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [collaborationProvider.overrideWith(() => controller)],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(brightness: Brightness.light),
              home: Scaffold(
                body: SharingStatus(
                  state: state,
                  onSync: () {},
                  onConflicts: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final icon = tester.widget<Icon>(
          find.byIcon(Icons.cloud_done_outlined),
        );
        expect(icon.color == Colors.green.shade700, status == 'synced');
        final cloud = tester.widget<IconButton>(
          find.byKey(const ValueKey('sharing-sync-status-cloud')),
        );
        if (status == 'historical') {
          expect(
            cloud.tooltip,
            contains('Previously synced; current state not yet checked'),
          );
          expect(cloud.tooltip, contains('Last successful data sync:'));
        } else if (status == 'checked') {
          expect(cloud.tooltip, contains('Account changes checked'));
          expect(cloud.tooltip, contains('Last successful data sync:'));
        } else {
          expect(cloud.tooltip, contains('Synced'));
        }
        await tester.tap(
          find.byKey(const ValueKey('sharing-sync-status-cloud')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .toList();
        expect(
          texts.any(
            (text) =>
                text.startsWith('Last successful data sync:') &&
                !text.contains('Not confirmed'),
          ),
          isTrue,
        );
        final check = texts.singleWhere(
          (text) => text.startsWith('Last successful change check:'),
        );
        expect(check.contains('Not confirmed'), status != 'checked');
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'history never overrides queues, refresh debt, invalid access, error or active work',
    () {
      SharingSyncStatus status(CollaborationState state) =>
          SharingStatusProjection.fromState(state, now: current).status;
      final session = sharingSession();
      for (final state in [
        CollaborationState(
          session: session,
          previousSuccessfulSyncAt: historical,
          pendingCount: 1,
        ),
        CollaborationState(
          session: session,
          previousSuccessfulSyncAt: historical,
          hasUnresolvedSyncWork: true,
        ),
      ]) {
        expect(status(state), SharingSyncStatus.pending);
      }
      expect(
        status(
          CollaborationState(
            session: session,
            previousSuccessfulSyncAt: historical,
            syncRequiresRefresh: true,
          ),
        ),
        SharingSyncStatus.unknown,
      );
      expect(
        status(
          CollaborationState(
            session: session,
            previousSuccessfulSyncAt: historical,
            isSyncing: true,
          ),
        ),
        SharingSyncStatus.syncing,
      );
      expect(
        status(
          CollaborationState(
            session: session,
            previousSuccessfulSyncAt: historical,
            sessionInvalid: true,
          ),
        ),
        SharingSyncStatus.problem,
      );
      expect(
        status(
          CollaborationState(
            session: session,
            previousSuccessfulSyncAt: historical,
            lastError: const CollaborationException('forbidden'),
          ),
        ),
        SharingSyncStatus.problem,
      );
      expect(
        status(
          CollaborationState(
            session: session,
            previousSuccessfulSyncAt: historical,
            lastError: const CollaborationException('network'),
          ),
        ),
        SharingSyncStatus.offline,
      );
    },
  );
}
