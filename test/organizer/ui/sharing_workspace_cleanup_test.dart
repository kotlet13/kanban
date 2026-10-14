import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/shared/organization_workspace.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

const _organizationId = '80000000-0000-4000-8000-000000000001';
const _organization = SharedScope(
  id: _organizationId,
  name: 'Test organization',
  kind: SharedScopeKind.organization,
  role: SharedRole.owner,
);
const _activeProject = SharedScope(
  id: '80000000-0000-4000-8000-000000000002',
  name: 'Active project',
  kind: SharedScopeKind.project,
  role: SharedRole.owner,
  organizationId: _organizationId,
);
const _archivedProject = SharedScope(
  id: '80000000-0000-4000-8000-000000000003',
  name: 'Archived project',
  kind: SharedScopeKind.project,
  role: SharedRole.owner,
  organizationId: _organizationId,
  archived: true,
);

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final scope in [sharingScope(), _organization, _activeProject]) {
      for (final view in SharingView.values) {
        testWidgets(
          '${scope.kind.name} $view has no member toolbar at $width',
          (tester) async {
            final controller = SharingUiController(
              initial: CollaborationState(
                session: sharingSession(),
                scopes: [scope, if (scope == _organization) _activeProject],
                data: {scope.id: sharingData()},
                organizationsSupported: true,
                householdPeopleSupported: true,
                recordContractVersion: 3,
                scopeArchivingSupported: true,
                scopeDeletionSupported: true,
              ),
            );
            await pumpPanel(
              tester,
              controller,
              SharingWorkspace(
                view: view,
                selectedScopeId: scope.id,
                onScopeSelected: (_) {},
                onConnect: () {},
                onMembers: (_) => fail('Work content must not open members'),
                showScopePicker: false,
              ),
              width: width,
            );
            expect(find.text('Člani'), findsNothing);
            expect(find.text('Povabi osebo'), findsNothing);
            expect(
              find.text('Dodaj projekt v organizacijo'),
              scope == _organization && view == SharingView.projects
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              find.byKey(ValueKey('scope-lifecycle-${scope.id}')),
              view == SharingView.agenda ? findsNothing : findsOneWidget,
            );
            if (view == SharingView.agenda) {
              expect(
                find.byKey(ValueKey('sharing-status-${scope.id}-$view')),
                findsOneWidget,
              );
            }
            expect(controller.memberLoads, 0);
            expect(controller.calls, isNot(contains('invitations')));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'organization fallback preserves active and archived projects at $width',
      (tester) async {
        final controller = SharingUiController(
          initial: CollaborationState(
            session: sharingSession(),
            scopes: [_organization, _activeProject, _archivedProject],
          ),
        );
        String? selected;
        await pumpPanel(
          tester,
          controller,
          OrganizationWorkspace(
            organization: _organization,
            allowProjectCreation: false,
            onProject: (id) => selected = id,
            onMembers: (_) {},
          ),
          width: width,
        );
        expect(find.text('Projekti organizacije'), findsOneWidget);
        expect(find.text('Dodaj projekt v organizacijo'), findsNothing);
        expect(find.text('Člani'), findsNothing);
        await tester.tap(find.text('Active project'));
        expect(selected, _activeProject.id);
        expect(find.text('Archived project'), findsNothing);
        await tester.tap(find.text('Arhivirano'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archived project'));
        expect(selected, _archivedProject.id);
        expect(tester.takeException(), isNull);
      },
    );

    for (final access in [
      'viewer',
      'archived',
      'blocked',
      'expired',
      'invalid',
    ]) {
      testWidgets(
        'organization project creation unavailable for $access at $width',
        (tester) async {
          final scope = SharedScope(
            id: _organizationId,
            name: _organization.name,
            kind: SharedScopeKind.organization,
            role: access == 'viewer' ? SharedRole.viewer : SharedRole.owner,
            archived: access == 'archived',
            blocked: access == 'blocked',
          );
          final session = sharingSession();
          final controller = SharingUiController(
            initial: CollaborationState(
              session: access == 'expired'
                  ? AccountSession(
                      serverUrl: session.serverUrl,
                      serverId: session.serverId,
                      accountId: session.accountId,
                      userId: session.userId,
                      username: session.username,
                      displayName: session.displayName,
                      deviceId: session.deviceId,
                      expiresAt: DateTime.utc(2000),
                    )
                  : session,
              sessionInvalid: access == 'invalid',
              scopes: [scope],
            ),
          );
          await pumpPanel(
            tester,
            controller,
            OrganizationWorkspace(
              organization: scope,
              onProject: (_) {},
              onMembers: (_) {},
            ),
            width: width,
          );
          expect(find.text('Dodaj projekt v organizacijo'), findsNothing);
          expect(find.text('Člani'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('household aggregate Utrip keeps sync without lifecycle menu', (
    tester,
  ) async {
    final household = SharedScope(
      id: _organizationId,
      name: 'Family home',
      kind: SharedScopeKind.household,
      role: SharedRole.owner,
      accessPolicyVersion: 3,
    );
    final controller = SharingUiController(
      initial: CollaborationState(
        session: sharingSession(),
        scopes: [household, _activeProject],
        data: {household.id: sharingData()},
        spaceProjectMembershipSupported: true,
        scopeArchivingSupported: true,
        scopeDeletionSupported: true,
        recordContractVersion: 3,
      ),
    );
    await pumpPanel(
      tester,
      controller,
      SharingWorkspace(
        view: SharingView.agenda,
        selectedScopeId: household.id,
        onScopeSelected: (_) {},
        onConnect: () {},
        showScopePicker: false,
      ),
      width: 390,
    );
    expect(find.byKey(ValueKey('scope-lifecycle-${household.id}')), findsNothing);
    expect(
      find.byKey(ValueKey('sharing-status-${household.id}-${SharingView.agenda}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('project form closes when organization editing is removed', (
    tester,
  ) async {
    final controller = SharingUiController(
      initial: CollaborationState(
        session: sharingSession(),
        scopes: [_organization],
      ),
    );
    await pumpPanel(
      tester,
      controller,
      OrganizationWorkspace(
        organization: _organization,
        onProject: (_) {},
        onMembers: (_) {},
      ),
    );
    await tester.tap(find.text('Dodaj projekt v organizacijo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sharing-submit')), findsOneWidget);
    controller.replace(
      CollaborationState(
        session: sharingSession(),
        scopes: [
          SharedScope(
            id: _organizationId,
            name: _organization.name,
            kind: SharedScopeKind.organization,
            role: SharedRole.owner,
            archived: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sharing-submit')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
