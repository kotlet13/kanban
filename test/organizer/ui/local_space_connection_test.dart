import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/presentation/onboarding/local_space_connection_panel.dart';
import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

const localHousehold = LocalSpace(
  id: 'qa-household',
  name: 'QA lokalno gospodinjstvo',
  kind: LocalSpaceKind.household,
);

class ConnectionCatalog extends LocalSpacesController {
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    spaces: [
      const LocalSpace(id: 'local', name: '', kind: LocalSpaceKind.personal),
      localHousehold,
      LocalSpace(
        id: 'already-linked',
        name: 'QA povezano gospodinjstvo',
        kind: LocalSpaceKind.household,
        binding: LocalSpaceBinding(
          partition: sharingSession().partition,
          scopeId: sharingScopeId,
        ),
      ),
    ],
  );
}

class ConnectionController extends SharingUiController {
  int published = 0;
  List<String>? chosen;
  @override
  Future<LocalSpacesPublicationPreview> previewLocalSpacesPublication(
    List<String> ids,
  ) async {
    chosen = ids;
    return LocalSpacesPublicationPreview(
      partition: sharingSession().partition,
      serverUrl: sharingSession().serverUrl,
      accountName: 'QA ciljni račun',
      fingerprint: 'hash',
      spaces: [
        const LocalSpacePublicationItem(
          space: localHousehold,
          recordCount: 4,
          gardenCount: 1,
        ),
      ],
    );
  }

  @override
  Future<void> publishLocalSpaces(LocalSpacesPublicationPreview preview) async {
    published++;
  }
}

Future<void> host(WidgetTester tester, ConnectionController controller) =>
    pumpPanel(
      tester,
      controller,
      ProviderScope(
        overrides: [localSpacesProvider.overrideWith(ConnectionCatalog.new)],
        child: const LocalSpaceConnectionPanel(),
      ),
    );
void main() {
  testWidgets(
    'login never uploads local spaces; explicit preview precedes publication',
    (tester) async {
      final controller = ConnectionController();
      await host(tester, controller);
      expect(controller.published, 0);
      expect(controller.chosen, isNull);
      expect(find.text('QA povezano gospodinjstvo'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('connect-local-space-qa-household')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preview-space-connection')));
      await tester.pumpAndSettle();
      expect(controller.published, 0);
      expect(controller.chosen, ['qa-household']);
      expect(find.text('QA ciljni račun'), findsOneWidget);
      expect(find.text(sharingSession().serverUrl), findsOneWidget);
      expect(find.text('4 zapisi · 1 vrt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-space-connection')));
      await tester.pumpAndSettle();
      expect(controller.published, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account change closes connection preview and preserves unsent spaces',
    (tester) async {
      final controller = ConnectionController();
      await host(tester, controller);
      await tester.tap(
        find.byKey(const ValueKey('connect-local-space-qa-household')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preview-space-connection')));
      await tester.pumpAndSettle();
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-space-connection')),
        findsNothing,
      );
      expect(controller.published, 0);
      expect(find.text(localHousehold.name), findsOneWidget);
    },
  );
}
