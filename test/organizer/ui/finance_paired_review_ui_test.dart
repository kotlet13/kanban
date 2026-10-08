import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_conflicts.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'sharing_ui_fixture.dart';

void main() {
  testWidgets(
    'financial review presents local linked task and fresh canonical task alongside monetary versions',
    (tester) async {
      final localDue = DateTime.utc(2026, 10, 15),
          remoteDue = DateTime.utc(2026, 10, 20);
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          financePolicies: {
            sharingScopeId: const SharedFinancePolicy(
              enabled: true,
              grant: SharedFinanceGrant.write,
            ),
          },
          financeSnapshotComplete: {sharingScopeId: true},
          data: {
            sharingScopeId: SharedScopeData(
              tasks: [
                LocalTask(
                  id: 'task',
                  title: 'Fresh canonical task title',
                  notes: '',
                  projectId: null,
                  dueAt: remoteDue,
                  isCompleted: false,
                  createdAt: sharingTestNow,
                  updatedAt: sharingTestNow,
                ),
              ],
            ),
          },
          conflicts: [
            SharedConflict(
              id: 'generic-op',
              scopeId: sharingScopeId,
              recordId: 'task',
              recordType: SharedRecordType.task,
              reason: 'conflict',
              remoteDeleted: false,
              localPayload: {
                'title': 'Local task title',
                'dueAt': localDue.toIso8601String(),
              },
              remotePayload: {
                'title': 'Old historical task title',
                'dueAt': localDue.toIso8601String(),
              },
            ),
          ],
          financeConflicts: [
            SharedFinanceConflict(
              id: 'financial-op',
              scopeId: sharingScopeId,
              recordId: 'cost',
              recordType: SharedFinanceRecordType.financeEntry,
              reason: 'conflict',
              localPayload: {
                'taskId': 'task',
                'title': 'Local cost',
                'amountMinor': 100,
                'currency': 'EUR',
                'status': 'planned',
              },
              remotePayload: {
                'taskId': 'task',
                'title': 'Canonical cost',
                'amountMinor': 120,
                'currency': 'EUR',
                'status': 'planned',
              },
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [collaborationProvider.overrideWith(() => controller)],
          child: MaterialApp(
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(collaborationProvider);
                  return TextButton(
                    onPressed: () =>
                        showFinanceConflicts(context, ref, sharingScopeId),
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Local task title'), findsOneWidget);
      expect(find.text('Fresh canonical task title'), findsOneWidget);
      expect(find.text('Old historical task title'), findsNothing);
      expect(find.textContaining('15.'), findsOneWidget);
      expect(find.textContaining('20.'), findsOneWidget);
      expect(find.textContaining('hkrati bodo obravnavane'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
