import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/platform/notification_providers.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/sharing_ui_fixture.dart';
import 'local_notification_adapter_test.dart' show FakeScheduler;
import 'notification_coordinator_test.dart' show host;

class _Organizer extends OrganizerController {
  _Organizer(this.snapshot);
  final OrganizerSnapshot snapshot;
  @override
  Future<OrganizerSnapshot> build() async => snapshot;
}

class _Spaces extends LocalSpacesController {
  final calls = <({String id, String workspace, Set<String>? ruleIds})>[];
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState();
  @override
  Future<void> materializeFinanceOccurrences(
    String localSpaceId, {
    required String expectedWorkspaceKey,
    DateTime? through,
    Set<String>? ruleIds,
  }) async {
    calls.add((
      id: localSpaceId,
      workspace: expectedWorkspaceKey,
      ruleIds: ruleIds,
    ));
  }
}

void main() {
  for (final version in [2, 3, 4]) {
    testWidgets(
      'private contract$version automatic materialization retains supported-version gate',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final now = DateTime(2026, 10, 18);
        final session = sharingSession();
        final workspace = 'private:${session.partition}';
        final snapshot = OrganizerSnapshot(
          workspaceKey: workspace,
          financeRecurrenceRules: [
            FinanceRecurrenceRule(
              id: 'rule',
              title: 'Synthetic rule',
              kind: FinanceRecurrenceKind.expense,
              currency: 'EUR',
              estimatedAmountMinor: 123,
              startYear: 2027,
              startMonth: 9,
              monthDay: 20,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
        final shared = SharingUiController(
          initial: CollaborationState(
            session: session,
            scopes: [sharingScope()],
            privateSync: PrivateSyncState(
              enabled: true,
              scopeId: sharingScopeId,
              partition: session.partition,
            ),
            privateRecordIds: const {'rule': 'rule'},
            financeContractVersion: version,
            financeSnapshotComplete: const {sharingScopeId: true},
            financePolicies: const {
              sharingScopeId: SharedFinancePolicy(
                enabled: true,
                grant: SharedFinanceGrant.write,
              ),
            },
          ),
        );
        final spaces = _Spaces();
        await tester.pumpWidget(
          host([
            organizerProvider.overrideWith(() => _Organizer(snapshot)),
            organizerClockProvider.overrideWithValue(() => now),
            collaborationProvider.overrideWith(() => shared),
            localSpacesProvider.overrideWith(() => spaces),
            localNotificationSchedulerProvider.overrideWithValue(
              FakeScheduler(),
            ),
          ], const Text('ready')),
        );
        await tester.pumpAndSettle();
        expect(
          spaces.calls,
          version == 2 || version == 3
              ? [(id: 'local', workspace: workspace, ruleIds: null)]
              : isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
