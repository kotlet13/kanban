import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/presentation/today_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/widgets/jivie_startup_logo.dart';

import 'organizer_ui_test.dart' show MemoryOrganizerStorage, pumpOrganizer;
import 'sharing_ui_fixture.dart';

class HeldLocalSpaces extends LocalSpacesController {
  final ready = Completer<LocalSpacesState>();
  @override
  Future<LocalSpacesState> build() => ready.future;
}

class HeldCollaboration extends SharingUiController {
  HeldCollaboration(CollaborationState initial) : super(initial: initial);
  final ready = Completer<CollaborationState>();
  @override
  Future<CollaborationState> build() => ready.future;
  void refreshLoading() => state = const AsyncLoading();
}

class HeldStorage extends MemoryOrganizerStorage {
  final ready = Completer<OrganizerSnapshot>();
  @override
  Future<OrganizerSnapshot> read() => ready.future;
}

LocalSpacesState localSelection() => LocalSpacesState(
  selectedSpaceId: 'saved-local',
  spaces: const [
    LocalSpace(
      id: 'saved-local',
      kind: LocalSpaceKind.organization,
      name: 'Saved local workspace',
    ),
  ],
);

void expectOnlyStartupLogo() {
  expect(find.byType(JivieStartupLogo), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.byType(OrganizerTodayPage), findsNothing);
  expect(find.byType(SharingWorkspace), findsNothing);
  expect(
    find.byKey(const ValueKey('organizer-destination-pulse')),
    findsNothing,
  );
}

void main() {
  for (final localFirst in [true, false]) {
    testWidgets(
      'initial workspace waits for both local restores, local first $localFirst',
      (tester) async {
        final selected = CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          selectedSpaceId: sharingScopeId,
          data: {sharingScopeId: sharingData()},
          // Background work may already be pending when local restore finishes.
          isSyncing: true,
        );
        final local = HeldLocalSpaces();
        final shared = HeldCollaboration(selected);
        await pumpOrganizer(
          tester,
          MemoryOrganizerStorage(),
          localSpacesController: local,
          collaborationController: shared,
          repaintBoundaryKey: GlobalKey(),
        );
        expectOnlyStartupLogo();
        if (localFirst) {
          local.ready.complete(localSelection());
        } else {
          shared.ready.complete(selected);
        }
        await tester.pumpAndSettle();
        expectOnlyStartupLogo();
        if (localFirst) {
          shared.ready.complete(selected);
        } else {
          local.ready.complete(localSelection());
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(JivieStartupLogo), findsNothing);
        expect(find.byType(OrganizerTodayPage), findsNothing);
        final workspace = tester.widget<SharingWorkspace>(
          find.byType(SharingWorkspace),
        );
        expect(workspace.view, SharingView.agenda);
        expect(workspace.selectedScopeId, sharingScopeId);
        expect(shared.state.requireValue.isSyncing, isTrue);
        expect(shared.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'local last workspace opens Pulse and later refresh keeps shell',
    (tester) async {
      final local = HeldLocalSpaces();
      final shared = HeldCollaboration(CollaborationState());
      shared.ready.complete(CollaborationState());
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        localSpacesController: local,
        collaborationController: shared,
        repaintBoundaryKey: GlobalKey(),
      );
      expectOnlyStartupLogo();
      local.ready.complete(localSelection());
      await tester.pumpAndSettle();
      expect(find.byType(JivieStartupLogo), findsNothing);
      expect(find.byType(OrganizerTodayPage), findsOneWidget);
      expect(find.text('Saved local workspace'), findsWidgets);
      expect(find.byKey(const ValueKey('content-_Area.today')), findsOneWidget);
      shared.refreshLoading();
      await tester.pump();
      expect(find.byType(JivieStartupLogo), findsNothing);
      expect(find.byKey(const ValueKey('content-_Area.today')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('local data load failure releases logo into existing retry UI', (
    tester,
  ) async {
    final local = HeldLocalSpaces();
    local.ready.complete(localSelection());
    final shared = HeldCollaboration(CollaborationState());
    shared.ready.complete(CollaborationState());
    final storage = HeldStorage();
    await pumpOrganizer(
      tester,
      storage,
      localSpacesController: local,
      collaborationController: shared,
      repaintBoundaryKey: GlobalKey(),
    );
    expectOnlyStartupLogo();
    storage.ready.completeError(StateError('synthetic local read failure'));
    await tester.pumpAndSettle();
    expect(find.byType(JivieStartupLogo), findsNothing);
    final context = tester.element(find.byType(Scaffold).first);
    final l = AppLocalizations.of(context)!;
    expect(find.text(l.organizerLoadError), findsOneWidget);
    expect(find.widgetWithText(FilledButton, l.organizerRetry), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
