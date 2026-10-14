import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/inbox/notification_target_view.dart';
import 'package:kanban/organizer/presentation/organizer_shell.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'organizer_ui_test.dart';
import 'sharing_ui_fixture.dart';

void main() {
  final now = DateTime(2026, 10, 14);
  testWidgets(
    'shopping notification opens whole list and highlights changed checked item',
    (tester) async {
      final storage = MemoryOrganizerStorage();
      storage.snapshot = OrganizerSnapshot().copyWith(
        shoppingLists: [
          LocalShoppingList(
            id: 'list',
            title: 'Tedenski nakupi',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        shoppingItems: [
          LocalShoppingItem(
            id: 'first',
            listId: 'list',
            title: 'Mleko',
            quantity: '2 l',
            isChecked: false,
            createdAt: now,
            updatedAt: now,
          ),
          LocalShoppingItem(
            id: 'changed',
            listId: 'list',
            title: 'Korenje',
            quantity: '1 kg',
            isChecked: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      await pumpOrganizer(
        tester,
        storage,
        collaborationController: SharingUiController(),
      );
      final context = tester.element(find.byType(OrganizerShell));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShoppingNotificationPage(
            target: NotificationTarget(
              records: const [
                NotificationRecordTarget(
                  type: 'shoppingItem',
                  recordId: 'changed',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tedenski nakupi'), findsOneWidget);
      expect(find.text('Mleko'), findsOneWidget);
      expect(find.text('Korenje'), findsOneWidget);
      expect(find.byTooltip('Sprememba iz obvestila'), findsOneWidget);
      expect(storage.snapshot.shoppingItems.last.isChecked, true);
      expect(storage.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'shopping page stops showing shared data after membership revocation',
    (tester) async {
      final controller = SharingUiController();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: controller,
      );
      final context = tester.element(find.byType(OrganizerShell));
      final target = NotificationTarget(
        serverUrl: sharingSession().serverUrl,
        serverId: sharingSession().serverId,
        accountId: sharingSession().accountId,
        scopeId: sharingScopeId,
        records: const [
          NotificationRecordTarget(type: 'shoppingItem', recordId: 'item'),
        ],
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShoppingNotificationPage(target: target),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mleko za skupno gospodinjstvo'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShoppingNotificationPage)),
      );
      final state = container.read(collaborationProvider).requireValue;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      controller.state = AsyncData(
        CollaborationState(
          session: state.session,
          scopes: [sharingScope(revoked: true)],
          data: state.data,
          localAccessAllowed: state.localAccessAllowed,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mleko za skupno gospodinjstvo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
