import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/shared/scope_lifecycle_menu.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

class LifecycleUiController extends SharingUiController {
  LifecycleUiController(SharedScope scope) : super(initial: CollaborationState(session: sharingSession(), scopes: [scope], data: {scope.id: sharingData()}, scopeDeletionSupported: true, scopeArchivingSupported: true));
  bool canDelete = true;
  final deleted = <String>[];
  final archived = <(String, bool)>[];
  @override
  Future<Map<String, dynamic>> previewScopeDeletion(String scopeId, {String? projectId}) async => {'scopeId': scopeId, 'projectId': projectId, 'name': initial.scopes.single.name, 'scopeNames': [initial.scopes.single.name], 'counts': {'projects': 1, 'tasks': 2, 'events': 3, 'ideas': 4, 'photos': 5, 'finance': 6, 'other': 0}, 'canDelete': canDelete, 'previewHash': 'a' * 64};
  @override
  Future<void> deleteScopeContents(Map<String, dynamic> preview, {String? projectId}) async { deleted.add(preview['scopeId'] as String); }
  @override
  Future<void> archiveProjectScope(String scopeId, {required bool archived, String? requestId}) async { this.archived.add((scopeId, archived)); }
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('task heading has contextual archive and counted deletion at $width', (tester) async {
      final scope = sharingScope(), controller = LifecycleUiController(sharingScope());
      await pumpPanel(tester, controller, SharingWorkspace(view: SharingView.tasks, selectedScopeId: scope.id, onScopeSelected: (_) {}, onConnect: () {}), width: width);
      expect(find.text('Arhiviraj'), findsNothing);
      final menu = find.byKey(ValueKey('scope-lifecycle-${scope.id}'));
      expect(menu, findsOneWidget);
      await tester.tap(menu); await tester.pumpAndSettle();
      await tester.tap(find.text('Arhiviraj')); await tester.pumpAndSettle();
      expect(controller.archived, [(scope.id, true)]);
      await tester.tap(menu); await tester.pumpAndSettle();
      await tester.tap(find.text('Izbriši')); await tester.pumpAndSettle();
      expect(find.textContaining('Trajno izbriši'), findsOneWidget);
      expect(find.textContaining('Opravila: 2'), findsOneWidget);
      expect(find.textContaining('Fotografije: 5'), findsOneWidget);
      expect(controller.deleted, isEmpty);
      await tester.tap(find.text('Prekliči')); await tester.pumpAndSettle();
      expect(controller.deleted, isEmpty);
      await tester.tap(menu); await tester.pumpAndSettle();
      await tester.tap(find.text('Izbriši')); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scope-delete-confirm'))); await tester.pumpAndSettle();
      expect(controller.deleted, [scope.id]);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('financial blocker disables irreversible confirmation', (tester) async {
    final scope = sharingScope(), controller = LifecycleUiController(sharingScope())..canDelete = false;
    await pumpPanel(tester, controller, ScopeLifecycleMenu(scope: scope), width: 390);
    await tester.tap(find.byKey(ValueKey('scope-lifecycle-${scope.id}'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Izbriši')); await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('scope-delete-confirm'))).onPressed, isNull);
    expect(controller.deleted, isEmpty);
    expect(find.textContaining('Izbris je zadržan'), findsOneWidget);
  });
  testWidgets('viewer has no scope management menu', (tester) async {
    final scope = sharingScope(role: SharedRole.viewer), controller = LifecycleUiController(sharingScope(role: SharedRole.viewer));
    await pumpPanel(tester, controller, ScopeLifecycleMenu(scope: scope), width: 390);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });
  testWidgets('member can archive but full scope deletion stays with owner', (tester) async {
    final scope = sharingScope(role: SharedRole.member), controller = LifecycleUiController(sharingScope(role: SharedRole.member));
    final policy3 = SharedScope.fromJson({...scope.toJson(), 'accessPolicyVersion': 3});
    final policyController = LifecycleUiController(policy3);
    await pumpPanel(tester, policyController, ScopeLifecycleMenu(scope: policy3), width: 390);
    await tester.tap(find.byKey(ValueKey('scope-lifecycle-${scope.id}'))); await tester.pumpAndSettle();
    expect(find.text('Arhiviraj'), findsOneWidget);
    expect(find.text('Izbriši'), findsNothing);
    expect(controller.deleted, isEmpty);
  });
}
