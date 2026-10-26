import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/presentation/garden/garden_editor.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/garden_provider.dart';
import 'sharing_ui_fixture.dart';

final now = DateTime.utc(2026, 10, 25);
Garden fixture() => Garden(
  id: '10000000-0000-4000-8000-000000000001',
  name: 'Synthetic garden',
  notes: 'Original draft',
  createdAt: now,
  updatedAt: now,
);

class _GardenController extends GardenController {
  _GardenController(this.garden, {this.error});
  final Garden garden;
  final Object? error;
  Garden? submitted;
  @override
  Future<GardenSnapshot> build() async => GardenSnapshot(gardens: [garden]);
  @override
  Future<void> updateGarden(
    Garden draft, {
    String? expectedWorkspaceKey,
  }) async {
    submitted = draft;
    if (error != null) throw error!;
  }
}

class _SharedController extends SharingUiController {
  _SharedController()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          selectedSpaceId: sharingScopeId,
        ),
      );
  int policyCalls = 0;
  @override
  Future<SharedContentPolicy> sharedContentPolicy({String? scopeId}) async {
    policyCalls++;
    throw StateError('Unrelated shared policy must not gate a local garden');
  }
}

Future<void> _host(
  WidgetTester tester,
  _GardenController garden,
  _SharedController shared,
) async {
  final infrastructure = await sharingUiInfrastructureOverrides(tester, shared);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...infrastructure,
        gardenProvider.overrideWith(() => garden),
        collaborationProvider.overrideWith(() => shared),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('Under editor')),
        routes: {'/garden': (_) => GardenEditor(garden: garden.garden)},
      ),
    ),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.text('Under editor'));
  Navigator.of(context).pushNamed('/garden');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('local garden save bypasses unrelated selected shared policy', (
    tester,
  ) async {
    final garden = _GardenController(fixture());
    final shared = _SharedController();
    await _host(tester, garden, shared);
    await tester.tap(find.byKey(const ValueKey('garden-save')));
    await tester.pumpAndSettle();
    expect(shared.policyCalls, 0);
    expect(garden.submitted?.notes, 'Original draft');
    expect(find.byType(GardenEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'typed authority failure keeps garden draft and shows its cause',
    (tester) async {
      final garden = _GardenController(
        fixture(),
        error: const CryptoAuthorityPending('crypto_stale_identity'),
      );
      final shared = _SharedController();
      await _host(tester, garden, shared);
      final note = find.widgetWithText(TextFormField, 'Original draft');
      await tester.ensureVisible(note);
      await tester.enterText(note, 'Original draft plus unsaved beds');
      await tester.tap(find.byKey(const ValueKey('garden-save')));
      await tester.pumpAndSettle();
      expect(find.byType(GardenEditor), findsOneWidget);
      expect(find.text('Original draft plus unsaved beds'), findsOneWidget);
      final l = AppLocalizations.of(tester.element(find.byType(GardenEditor)))!;
      expect(find.text(l.sharingAccountChanged), findsOneWidget);
      expect(find.text(l.gardenSaveError), findsNothing);
      expect(shared.policyCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
