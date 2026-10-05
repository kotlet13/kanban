import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/presentation/organizer_actions.dart';
import 'package:kanban/organizer/presentation/finance_page.dart';
import 'sharing_ui_fixture.dart';

class WorkspaceController extends OrganizerController {
  WorkspaceController(this.snapshot);
  final OrganizerSnapshot snapshot;
  int creates = 0;
  @override
  Future<OrganizerSnapshot> build() async => snapshot;
  @override
  Future<void> createTask({
    required String title,
    String notes = '',
    String? projectId,
    DateTime? dueAt,
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    creates++;
  }
}

Future<void> pumpWorkspace(
  WidgetTester tester,
  WorkspaceController personal,
  SharingUiController shared, {
  bool finance = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        organizerProvider.overrideWith(() => personal),
        collaborationProvider.overrideWith(() => shared),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final snapshot = ref.watch(organizerProvider).valueOrNull;
              ref.watch(collaborationProvider);
              if (snapshot == null) return const SizedBox();
              final actions = OrganizerActions(context, ref, snapshot);
              return finance
                  ? OrganizerFinancePage(snapshot: snapshot, actions: actions)
                  : TextButton(
                      onPressed: () => actions.task(),
                      child: const Text('Create'),
                    );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'private personal editor closes immediately on account change before workspace refresh',
    (tester) async {
      final personal = WorkspaceController(
            OrganizerSnapshot(workspaceKey: 'privateA'),
          ),
          shared = SharingUiController();
      await pumpWorkspace(tester, personal, shared);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('organizer-save')), findsOneWidget);
      shared.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
      expect(personal.creates, 0);
    },
  );
  testWidgets(
    'anonymous local editor stays local after unrelated login when workspace unchanged',
    (tester) async {
      final personal = WorkspaceController(OrganizerSnapshot()),
          shared = SharingUiController(initial: CollaborationState());
      await pumpWorkspace(tester, personal, shared);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      shared.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('organizer-save')), findsOneWidget);
      expect(personal.creates, 0);
    },
  );
  testWidgets(
    'incomplete private finance hides aggregate while retaining visible pending records',
    (tester) async {
      final now = DateTime.utc(2026, 10, 5);
      final personal = WorkspaceController(
        OrganizerSnapshot(
          workspaceKey: 'privateA',
          financeEntries: [
            FinanceEntry(
              id: 'one',
              title: 'Čakajoči osebni strošek',
              amountMinor: 100,
              currency: 'EUR',
              kind: FinanceEntryKind.expense,
              occurredAt: now,
              projectId: null,
              notes: '',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      final shared = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          privateSync: const PrivateSyncState(
            available: true,
            enabled: true,
            scopeId: sharingScopeId,
          ),
          financeSnapshotComplete: {sharingScopeId: false},
        ),
      );
      await pumpWorkspace(tester, personal, shared, finance: true);
      expect(find.text('Čakajoči osebni strošek'), findsOneWidget);
      expect(find.text('Stanje'), findsNothing);
      expect(find.textContaining('še ni v celoti prenesen'), findsOneWidget);
    },
  );
}
