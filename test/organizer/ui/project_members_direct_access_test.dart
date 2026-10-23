import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/presentation/shared/sharing_member_label.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

const target = '00000000-0000-4000-a000-000000000001';
const project = '00000000-0000-4000-a000-000000000002';

class _MembersController extends SharingUiController {
  _MembersController({bool ready = true})
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          selectedSpaceId: target,
          scopes: [
            SharedScope(
              id: target,
              name: 'Exact project space',
              kind: SharedScopeKind.project,
              role: SharedRole.owner,
              projectRootId: ready ? project : null,
              accessPolicyVersion: 3,
            ),
          ],
          data: {
            target: SharedScopeData(
              projects: [
                LocalProject(
                  id: project,
                  title: 'Exact project',
                  description: '',
                  createdAt: DateTime.utc(2026),
                  updatedAt: DateTime.utc(2026),
                  area: ProjectArea.personal,
                ),
              ],
            ),
          },
        ),
      );
  final loadedScopes = <String>[];
  @override
  Future<List<SharedMember>> members(String scopeId) async {
    loadedScopes.add(scopeId);
    return [
      const SharedMember(
        userId: 1,
        accountId: 'account-B',
        username: 'beta',
        displayName: 'Preizkus B',
        role: SharedRole.member,
        active: true,
      ),
    ];
  }
}

Widget panel() => SharingWorkspace(
  view: SharingView.projects,
  selectedScopeId: target,
  selectedProjectId: project,
  onProjectSelected: (_) {},
  onScopeSelected: (_) {},
  showScopePicker: false,
  onConnect: () {},
);
void main() {
  testWidgets(
    'direct project action opens exact membership and closes on account change',
    (tester) async {
      final controller = _MembersController();
      await pumpPanel(tester, controller, panel(), width: 1280);
      final action = find.text('Člani in deljenje');
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(SharingMembersPage), findsOneWidget);
      expect(controller.loadedScopes, [target]);
      expect(find.text('Člani in deljenje · Exact project'), findsOneWidget);
      expect(find.text('Preizkus B'), findsOneWidget);
      controller.replace(
        CollaborationState(session: sharingSession(second: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SharingMembersPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unready root reports membership readiness without external finance claim',
    (tester) async {
      final controller = _MembersController(ready: false);
      await pumpPanel(tester, controller, panel(), width: 1280, language: 'en');
      await tester.tap(find.text('Sharing and members'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Membership for this project is not ready yet. Finish synchronizing the project first.',
        ),
        findsOneWidget,
      );
      expect(controller.loadedScopes, isEmpty);
      expect(find.byType(SharingMembersPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('editor Members reuses exact project route', (tester) async {
    final controller = _MembersController();
    await pumpPanel(tester, controller, panel(), width: 1280);
    await tester.tap(
      find.byKey(const ValueKey('content-actions-record-$target-$project')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uredi projekt'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-editor-sharing')));
    await tester.pumpAndSettle();
    expect(find.byType(SharingMembersPage), findsOneWidget);
    expect(controller.loadedScopes, [target]);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'missing member labels are localized and distinguish exact accounts',
    (tester) async {
      final controller = _MembersController();
      await pumpPanel(
        tester,
        controller,
        Builder(
          builder: (context) => Column(
            children: [
              for (final account in ['account-one', 'account-two'])
                Text(
                  sharingMemberLabel(
                    context,
                    SharedMember(
                      userId: 0,
                      accountId: account,
                      username: account,
                      displayName: '',
                      role: SharedRole.member,
                      active: true,
                      labelUnavailable: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      expect(find.text('Ime še ni pridobljeno · account-one'), findsOneWidget);
      expect(find.text('Ime še ni pridobljeno · account-two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
