import 'package:kanban/organizer/data/collaboration_repository.dart'
    show newSharedId;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/presentation/shared/space_picker.dart';
import 'package:kanban/organizer/presentation/shared/organization_workspace.dart';
import 'package:kanban/organizer/presentation/people/people_page.dart';
import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';
import 'organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer, mobileTab;

const orgId = '80000000-0000-4000-8000-000000000001';
const org = SharedScope(
  id: orgId,
  name: 'Synthetic organization',
  kind: SharedScopeKind.organization,
  role: SharedRole.owner,
  requiredRecordContractVersion: 3,
);

class CreationController extends SharingUiController {
  CreationController()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          organizationsSupported: true,
          recordContractVersion: 3,
          scopes: [org],
        ),
      );
  final requests = <Map<String, Object?>>[];
  final created = <String, SharedScope>{};
  Completer<void>? beforeReply;
  bool loseFirst = true;
  @override
  Future<String> createScope(
    String name, {
    SharedScopeKind kind = SharedScopeKind.household,
    String? organizationId,
    String? id,
    String? requestId,
  }) async {
    requests.add({
      'name': name,
      'kind': kind.name,
      'organizationId': organizationId,
      'id': id,
      'requestId': requestId,
    });
    final scopeId = id ?? newSharedId();
    created.putIfAbsent(
      scopeId,
      () => SharedScope(
        id: scopeId,
        name: name,
        kind: kind,
        organizationId: organizationId,
        role: SharedRole.owner,
      ),
    );
    await beforeReply?.future;
    if (loseFirst) {
      loseFirst = false;
      throw const CollaborationException('network');
    }
    return scopeId;
  }
}

class CostUiController extends SharingUiController {
  CostUiController(CollaborationState initial) : super(initial: initial);
  LocalTask? savedTask;
  bool compound = false;
  @override
  Future<void> updateTask(String scopeId, LocalTask draft) async {
    savedTask = draft;
  }

  @override
  Future<void> saveTaskWithCost(
    String scopeId,
    LocalTask task, {
    bool isNew = false,
    TaskCostDraft? cost,
    bool removeCost = false,
    int? expectedFinanceRevision,
  }) async {
    savedTask = task;
    compound = true;
  }
}

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('People menu appears once at $width', (tester) async {
      await pumpOrganizer(tester, MemoryOrganizerStorage(), width: width);
      if (width < 600) {
        await mobileTab(tester, 'Več');
      }
      expect(find.text('Osebe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'organization lost reply Save retries same identity/body at $width',
      (tester) async {
        final controller = CreationController();
        String? selected;
        await pumpPanel(
          tester,
          controller,
          OrganizerSpacePicker(
            onSelected: (id) => selected = id,
            onConnect: () {},
          ),
          width: width,
        );
        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('+ Nov prostor').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<String>, 'Gospodinjstvo'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Organizacija').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'New organization',
        );
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.pumpAndSettle();
        expect(controller.requests.length, 1);
        expect(selected, isNull);
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.pumpAndSettle();
        expect(controller.requests.length, 2);
        expect(controller.requests[0], controller.requests[1]);
        expect(controller.created.length, 1);
        expect(selected, controller.requests.first['id']);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'organization project lost reply preserves parent and request at $width',
      (tester) async {
        final controller = CreationController();
        String? selected;
        await pumpPanel(
          tester,
          controller,
          OrganizationWorkspace(
            organization: org,
            onProject: (id) => selected = id,
            onMembers: (_) {},
          ),
          width: width,
        );
        await tester.tap(find.text('Dodaj projekt v organizacijo'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Organizacija: Synthetic organization'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Na začetku vidi projekt samo ustvarjalec.'),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField).first, 'Project');
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.pumpAndSettle();
        expect(controller.requests[0], controller.requests[1]);
        expect(controller.requests.first['organizationId'], orgId);
        expect(controller.created.length, 1);
        expect(selected, isNull);
        await tester.tap(
          find.byKey(const ValueKey('organization-created-open')),
        );
        await tester.pumpAndSettle();
        expect(selected, controller.requests.first['id']);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('person expansion filters assigned/subject tasks at $width', (
      tester,
    ) async {
      final person = HouseholdPerson(
        id: 'person',
        name: 'Synthetic person',
        createdAt: sharingTestNow,
        updatedAt: sharingTestNow,
      );
      LocalTask task(
        String id, {
        String? assignee,
        List<String> subjects = const [],
      }) => LocalTask(
        id: id,
        title: id,
        notes: '',
        projectId: null,
        dueAt: null,
        isCompleted: false,
        assigneePersonId: assignee,
        subjectPersonIds: subjects,
        createdAt: sharingTestNow,
        updatedAt: sharingTestNow,
      );
      await pumpPanel(
        tester,
        SharingUiController(),
        OrganizerPeoplePage(
          people: [person],
          tasks: [
            task('Assigned', assignee: 'person'),
            task('Subject', subjects: ['person']),
            task('Other'),
          ],
          readOnly: true,
        ),
        width: width,
      );
      expect(
        find.text('Profil osebe nima prijave ali dostopnih pravic.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Synthetic person'));
      await tester.pumpAndSettle();
      expect(find.text('Assigned'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'created project opens its own members and ignores later identity change',
    (tester) async {
      final controller = CreationController()..loseFirst = false;
      String? members, selected;
      await pumpPanel(
        tester,
        controller,
        OrganizationWorkspace(
          organization: org,
          onProject: (id) => selected = id,
          onMembers: (id) => members = id,
        ),
      );
      await tester.tap(find.text('Dodaj projekt v organizacijo'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Private project');
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('organization-created-members')),
      );
      await tester.pumpAndSettle();
      expect(members, controller.requests.single['id']);
      expect(members, isNot(orgId));
      expect(selected, isNull);
      members = null;
      await tester.tap(find.text('Dodaj projekt v organizacijo'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Another project');
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('organization-created-members')),
        findsNothing,
      );
      expect(members, isNull);
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'late creation response after account switch cannot select old scope',
    (tester) async {
      final controller = CreationController()
        ..loseFirst = false
        ..beforeReply = Completer<void>();
      String? selected;
      await pumpPanel(
        tester,
        controller,
        OrganizerSpacePicker(
          onSelected: (id) => selected = id,
          onConnect: () {},
        ),
      );
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Nov prostor').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Old account organization',
      );
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pump();
      controller.switchAccount();
      await tester.pumpAndSettle();
      controller.beforeReply!.complete();
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  for (final grant in [
    SharedFinanceGrant.none,
    SharedFinanceGrant.read,
    SharedFinanceGrant.write,
  ]) {
    testWidgets(
      'shared task cost sends financial mutation only with write grant $grant',
      (tester) async {
        final base = sharingData(), task = base.tasks.single;
        final account = SharedFinanceAccount(
          id: 'ledger',
          name: 'Ledger',
          currency: 'EUR',
          createdAt: sharingTestNow,
          updatedAt: sharingTestNow,
        );
        final entry = SharedFinanceEntry(
          id: 'cost',
          accountId: 'ledger',
          ledgerAccountId: 'ledger',
          taskId: task.id,
          kind: FinanceEntryKind.expense,
          status: SharedFinanceStatus.planned,
          amountMinor: 1234,
          currency: 'EUR',
          title: task.title,
          occurredAt: sharingTestNow,
          createdAt: sharingTestNow,
          updatedAt: sharingTestNow,
        );
        final data = SharedScopeData(
          projects: base.projects,
          tasks: base.tasks,
          financeAccounts: grant == SharedFinanceGrant.none ? [] : [account],
          financeEntries: grant == SharedFinanceGrant.none ? [] : [entry],
        );
        final scope = sharingScope(role: SharedRole.member),
            state = CollaborationState(
              session: sharingSession(),
              scopes: [scope],
              data: {scope.id: data},
              recordContractVersion: 3,
              financeContractVersion: 2,
              financePolicies: {
                scope.id: SharedFinancePolicy(
                  enabled: true,
                  grant: grant,
                  revision: 1,
                ),
              },
              financeSnapshotComplete: {scope.id: true},
            );
        final controller = CostUiController(state);
        await pumpPanel(
          tester,
          controller,
          Consumer(
            builder: (context, ref, _) {
              ref.watch(collaborationProvider);
              return TextButton(
                onPressed: () => CollaborationActions(
                  context,
                  ref,
                  scope,
                  data,
                ).task(task: task),
                child: const Text('Edit task'),
              );
            },
          ),
        );
        expect(controller.state.requireValue.scopes.single.canEdit, isTrue);
        await tester.tap(find.text('Edit task'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(TextFormField), findsWidgets);
        await tester.enterText(find.byType(TextFormField).first, 'Edited task');
        await tester.tap(find.byKey(const ValueKey('organizer-save')));
        await tester.pumpAndSettle();
        expect(controller.savedTask?.title, 'Edited task');
        expect(controller.compound, grant == SharedFinanceGrant.write);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
