import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
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

class PolicyConnectionController extends ConnectionController {
  bool accepted = false;
  int acceptanceCalls = 0;
  int publishAttempts = 0;
  Object? policyError;
  Object? acceptanceError;

  @override
  Future<SharedContentPolicy> sharedContentPolicy({String? scopeId}) async {
    if (policyError != null) throw policyError!;
    final session = state.requireValue.session!;
    return SharedContentPolicy(
      serverId: session.serverId,
      partition: session.partition,
      deviceId: session.deviceId,
      policyVersion: 1,
      title: 'Rules',
      textSl: 'Pravila izbranega strežnika.',
      textEn: 'Selected server rules.',
      recipientName: 'Skrbnik izbranega strežnika',
      accepted: accepted,
    );
  }

  @override
  Future<void> acceptSharedContentPolicy(SharedContentPolicy policy) async {
    acceptanceCalls++;
    if (acceptanceError != null) throw acceptanceError!;
    expect(policy.partition, state.requireValue.session!.partition);
    accepted = true;
  }

  @override
  Future<void> publishLocalSpaces(LocalSpacesPublicationPreview preview) async {
    publishAttempts++;
    if (!accepted) {
      throw const CollaborationException('policy_acceptance_required');
    }
    await super.publishLocalSpaces(preview);
  }
}

Future<void> confirmConnection(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('connect-local-space-qa-household')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('preview-space-connection')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('confirm-space-connection')));
  await tester.pumpAndSettle();
}

Future<void> acceptRules(WidgetTester tester) async {
  final checkbox = find.byKey(const ValueKey('shared-policy-checkbox'));
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('shared-policy-accept')));
  await tester.pumpAndSettle();
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
      expect(
        find.text('4 zapisi · 1 vrt · Ideje: 0 · Osnutki idej: 0'),
        findsOneWidget,
      );
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
  testWidgets('first connection asks for rules then publishes exactly once', (
    tester,
  ) async {
    final controller = PolicyConnectionController();
    await host(tester, controller);
    await confirmConnection(tester);
    expect(
      find.byKey(const ValueKey('shared-policy-checkbox')),
      findsOneWidget,
    );
    expect(controller.publishAttempts, 0);
    expect(controller.acceptanceCalls, 0);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('shared-policy-checkbox')),
          )
          .value,
      false,
    );
    await acceptRules(tester);
    expect(controller.acceptanceCalls, 1);
    expect(controller.publishAttempts, 1);
    expect(controller.published, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled rules keep selected local space without upload', (
    tester,
  ) async {
    final controller = PolicyConnectionController();
    await host(tester, controller);
    await confirmConnection(tester);
    await tester.tap(find.text('Prekliči'));
    await tester.pumpAndSettle();
    expect(controller.publishAttempts, 0);
    expect(controller.acceptanceCalls, 0);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('connect-local-space-qa-household')),
          )
          .value,
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account switch during rules never publishes to another account',
    (tester) async {
      final controller = PolicyConnectionController();
      await host(tester, controller);
      await confirmConnection(tester);
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shared-policy-accept')), findsNothing);
      expect(controller.publishAttempts, 0);
      expect(controller.acceptanceCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable rules show error and never upload', (tester) async {
    final controller = PolicyConnectionController()
      ..policyError = const CollaborationException('network');
    await host(tester, controller);
    await confirmConnection(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-policy-accept')), findsNothing);
    expect(controller.publishAttempts, 0);
    expect(controller.acceptanceCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed acceptance stays open and retry publishes once', (
    tester,
  ) async {
    final controller = PolicyConnectionController()
      ..acceptanceError = const CollaborationException('network');
    await host(tester, controller);
    await confirmConnection(tester);
    await acceptRules(tester);
    expect(find.byKey(const ValueKey('shared-policy-accept')), findsOneWidget);
    expect(controller.publishAttempts, 0);
    controller.acceptanceError = null;
    await tester.tap(find.byKey(const ValueKey('shared-policy-accept')));
    await tester.pumpAndSettle();
    expect(controller.acceptanceCalls, 2);
    expect(controller.publishAttempts, 1);
    expect(controller.published, 1);
    expect(tester.takeException(), isNull);
  });
}
