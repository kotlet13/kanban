import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/presentation/shared/space_picker.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';

const _survivor = SharedScope(
  id: '10000000-0000-4000-8000-000000000009',
  name: 'Surviving household',
  kind: SharedScopeKind.household,
  role: SharedRole.owner,
);

class _DeletionTransition extends SharingUiController {
  _DeletionTransition()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          selectedSpaceId: sharingScopeId,
          scopes: [sharingScope(), _survivor],
          data: {sharingScopeId: sharingData()},
          scopeDeletionSupported: true,
          scopeArchivingSupported: true,
        ),
      );
  int previews = 0, deletions = 0;
  @override
  Future<Map<String, dynamic>> previewScopeDeletion(
    String scopeId, {
    String? projectId,
  }) async {
    previews++;
    return {
      'scopeId': scopeId,
      'name': initial.scopes.first.name,
      'scopeNames': [initial.scopes.first.name],
      'counts': {
        'projects': 0,
        'tasks': 0,
        'events': 0,
        'ideas': 0,
        'photos': 0,
        'finance': 0,
        'other': 0,
      },
      'canDelete': true,
      'previewHash': 'a' * 64,
    };
  }

  @override
  Future<void> deleteScopeContents(
    Map<String, dynamic> preview, {
    String? projectId,
  }) async {
    deletions++;
    // Match the repository's confirmed-delete state: retain selected_space and
    // its tombstone, mark both deleted and revoked, keep unrelated scopes/data.
    // Server/crypto deletion is exercised separately by the actual HTTP flow.
    replace(
      CollaborationState(
        session: sharingSession(),
        selectedSpaceId: sharingScopeId,
        scopes: [
          SharedScope.fromJson({
            ...initial.scopes.first.toJson(),
            'deleted': true,
            'revoked': true,
          }),
          _survivor,
        ],
        data: initial.data,
        scopeDeletionSupported: true,
        scopeArchivingSupported: true,
      ),
    );
  }
}

void main() {
  testWidgets(
    'deleting selected space leaves a locked chooser and allows surviving selection',
    (tester) async {
      final controller = _DeletionTransition();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: controller,
      );
      await mobileTab(tester, 'Nastavitve prostora');
      final delete = find.byKey(
        const ValueKey('space-settings-$sharingScopeId-delete'),
      );
      expect(delete, findsOneWidget);
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(controller.previews, 1);
      expect(controller.deletions, 0);
      final confirm = find.byKey(const ValueKey('scope-delete-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(controller.deletions, 1);
      expect(controller.state.requireValue.selectedSpaceId, sharingScopeId);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SharingMembersPage), findsNothing);
      expect(delete, findsNothing);
      expect(
        find.byKey(const ValueKey('space-settings-$sharingScopeId-archive')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('space-settings-scope-$sharingScopeId')),
        findsNothing,
      );
      final picker = tester.widget<OrganizerSpacePickerButton>(
        find.byType(OrganizerSpacePickerButton),
      );
      expect(picker.value, sharingScopeId);
      expect(picker.icon, Icons.lock_outline);
      expect(picker.label, isNot(sharingScope().name));
      final survivingChoice = find.byKey(
        ValueKey('space-settings-scope-${_survivor.id}'),
      );
      expect(survivingChoice, findsOneWidget);
      await tester.ensureVisible(survivingChoice);
      await tester.tap(survivingChoice);
      await tester.pumpAndSettle();
      expect(controller.state.requireValue.selectedSpaceId, _survivor.id);
      expect(
        tester
            .widget<OrganizerSpacePickerButton>(
              find.byType(OrganizerSpacePickerButton),
            )
            .label,
        _survivor.name,
      );
      expect(find.byType(SharingMembersPage), findsOneWidget);
      expect(controller.deletions, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
