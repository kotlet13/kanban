import 'dart:async';

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
  Future<Set<String>>? ownershipRead;
  int creates = 0;
  @override
  Future<OrganizerSnapshot> build() async => snapshot;
  @override
  Future<Set<String>> deviceLocalRecordIds() async =>
      ownershipRead ??
      (snapshot.workspaceKey == 'local' ? snapshot.recordIds : <String>{});
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
  testWidgets('local task editor opens without waiting for ownership storage', (
    tester,
  ) async {
    final ownership = Completer<Set<String>>();
    final personal = WorkspaceController(OrganizerSnapshot())
      ..ownershipRead = ownership.future;
    await pumpWorkspace(tester, personal, SharingUiController());
    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('organizer-save')), findsOneWidget);
    ownership.complete(<String>{});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
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
    'private editor never opens after account switch while ownership read is pending',
    (tester) async {
      final ownershipRead = Completer<Set<String>>();
      final personal = WorkspaceController(
        OrganizerSnapshot(workspaceKey: 'privateA'),
      )..ownershipRead = ownershipRead.future;
      final shared = SharingUiController();
      await pumpWorkspace(tester, personal, shared);
      await tester.tap(find.text('Create'));
      await tester.pump();
      expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
      shared.switchAccount();
      await tester.pump();
      ownershipRead.complete(<String>{});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
      expect(personal.creates, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'incomplete private finance hides aggregate while retaining visible pending records',
    (tester) async {
      final now = DateTime.utc(2026, 10, 5);
      final personal = WorkspaceController(
        OrganizerSnapshot(
          workspaceKey: 'private:${sharingSession().partition}',
          financeEntries: [
            FinanceEntry(
              id: 'one',
              title: 'Čakajoči osebni strošek',
              status: FinanceEntryStatus.planned,
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
          privateRecordIds: {'one': 'one'},
        ),
      );
      await pumpWorkspace(tester, personal, shared, finance: true);
      expect(find.text('Čakajoči osebni strošek'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('planned-finance-one')))
            .onTap,
        isNull,
      );
      expect(find.text('Stanje'), findsNothing);
      expect(find.text('Napoved po datumih'), findsNothing);
      expect(find.text('Pričakovana neto sprememba'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('še ni v celoti prenesen'), findsOneWidget);
    },
  );
}
