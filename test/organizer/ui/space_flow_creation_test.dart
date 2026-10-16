import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/space_creation_draft.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/presentation/shared/create_space_dialog.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'sharing_ui_fixture.dart';
import 'local_spaces_navigation_test.dart' show capture, loadCaptureFonts;

class _Local extends LocalSpacesController {
  final created = <LocalSpace>[];
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState();
  @override
  Future<LocalSpace> createSpace({
    required LocalSpaceKind kind,
    required String name,
    String address = '',
  }) async {
    final value = LocalSpace(
      id: 'local-created',
      kind: kind,
      name: name,
      address: address,
    );
    created.add(value);
    return value;
  }
}

class _Cloud extends SharingUiController {
  _Cloud({bool loggedIn = true, this.organizations = true})
    : super(
        initial: CollaborationState(
          session: loggedIn ? sharingSession() : null,
          organizationsSupported: organizations,
        ),
      );
  final bool organizations;
  final requests = <Map<String, Object?>>[];
  bool fail = false;
  void otherAccount() => state = AsyncData(
    CollaborationState(
      session: sharingSession(second: true),
      organizationsSupported: organizations,
    ),
  );
  void signedIn() => state = AsyncData(
    CollaborationState(
      session: sharingSession(),
      organizationsSupported: organizations,
    ),
  );
  @override
  Future<String> createScope(
    String name, {
    SharedScopeKind kind = SharedScopeKind.household,
    String address = '',
    String? organizationId,
    String? parentScopeId,
    String? id,
    String? requestId,
  }) async {
    requests.add({
      'id': id,
      'requestId': requestId,
      'name': name,
      'kind': kind,
      'address': address,
    });
    if (fail) throw const CollaborationException('network_error');
    return id!;
  }
}

Future<CollaborationDatabase> _hostPreflight(
  WidgetTester tester,
  _Cloud cloud,
) async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  await SqliteOrganizerStorage(db).initialize();
  addTearDown(db.close);
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => cloud),
        localSpacesProvider.overrideWith(_Local.new),
        localDatabaseProvider.overrideWith((ref) async => db),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCreateOrganizerSpace(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('sharing-name')),
    'Valid space',
  );
  await tester.tap(find.byKey(const ValueKey('space-flow-cloud')));
  await tester.pumpAndSettle();
  return db;
}

void main() {
  for (final field in ['name', 'address']) {
    testWidgets(
      'preflight rejects Unicode $field before durable dispatch and allows correction',
      (tester) async {
        final cloud = _Cloud();
        final db = await _hostPreflight(tester, cloud);
        final input = find.byKey(ValueKey('sharing-$field'));
        await tester.enterText(input, 'č' * (field == 'name' ? 101 : 501));
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.pumpAndSettle();
        expect(cloud.requests, isEmpty);
        expect(await SpaceCreationDraftStore(db).read(), isNull);
        expect(tester.widget<TextFormField>(input).enabled, true);
        expect(
          find.text(
            'Ustvarjanje še ni potrjeno. Poskusi znova. Podatki ostanejo enaki, da ne nastane dvojnik.',
          ),
          findsNothing,
        );
        await tester.enterText(input, 'Corrected');
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.pumpAndSettle();
        expect(cloud.requests, hasLength(1));
        expect(cloud.requests.single[field], 'Corrected');
        expect(await SpaceCreationDraftStore(db).read(), isNull);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'preflight rejects unsupported cloud organization without locking draft',
    (tester) async {
      final cloud = _Cloud(organizations: false);
      final db = await _hostPreflight(tester, cloud);
      await tester.tap(find.byKey(const ValueKey('sharing-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organizacija').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(cloud.requests, isEmpty);
      expect(await SpaceCreationDraftStore(db).read(), isNull);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('sharing-name')))
            .enabled,
        true,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('space-flow-cloud')),
            )
            .onChanged,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('sharing-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gospodinjstvo').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(cloud.requests.single['kind'], SharedScopeKind.household);
      expect(await SpaceCreationDraftStore(db).read(), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final kind in LocalSpaceKind.values.where(
      (k) => k != LocalSpaceKind.personal,
    )) {
      for (final loggedIn in [true, false]) {
        testWidgets(
          'cloud ${kind.name} loggedIn=$loggedIn creates one destination with address at $width',
          (tester) async {
            await loadCaptureFonts(tester);
            final captureKey = GlobalKey();
            final cloud = _Cloud(loggedIn: loggedIn), local = _Local();
            var authCalls = 0;
            final db = CollaborationDatabase(NativeDatabase.memory());
            await SqliteOrganizerStorage(db).initialize();
            addTearDown(db.close);
            await tester.binding.setSurfaceSize(Size(width, 900));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            CreatedOrganizerSpace? result;
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  collaborationProvider.overrideWith(() => cloud),
                  localSpacesProvider.overrideWith(() => local),
                  localDatabaseProvider.overrideWith((ref) async => db),
                ],
                child: MaterialApp(
                  builder: (context, child) =>
                      RepaintBoundary(key: captureKey, child: child!),
                  theme: ThemeData(fontFamily: 'CupertinoSystemText'),
                  locale: const Locale('sl'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () async {
                          result = await showCreateOrganizerSpace(
                            context,
                            onAuthenticate: () async {
                              authCalls++;
                              expect(find.text('New space'), findsOneWidget);
                              expect(find.text('Address 1'), findsOneWidget);
                              cloud.signedIn();
                              return true;
                            },
                          );
                        },
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('open'));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<CheckboxListTile>(
                    find.byKey(const ValueKey('space-flow-cloud')),
                  )
                  .value,
              false,
            );
            await tester.enterText(
              find.byKey(const ValueKey('sharing-name')),
              'New space',
            );
            await tester.enterText(
              find.byKey(const ValueKey('sharing-address')),
              'Address 1',
            );
            if (kind == LocalSpaceKind.organization) {
              await tester.tap(find.byKey(const ValueKey('sharing-kind')));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Organizacija').last);
              await tester.pumpAndSettle();
            }
            await tester.ensureVisible(
              find.byKey(const ValueKey('space-flow-cloud')),
            );
            await tester.tap(find.byKey(const ValueKey('space-flow-cloud')));
            await tester.pumpAndSettle();
            await capture(
              tester,
              captureKey,
              'space-flow-create-${kind.name}-${width.toInt()}-$loggedIn',
            );
            cloud.fail = true;
            await tester.tap(find.byKey(const ValueKey('sharing-submit')));
            await tester.pumpAndSettle();
            expect(cloud.requests, hasLength(1));
            expect(authCalls, loggedIn ? 0 : 1);
            expect(local.created, isEmpty);
            expect(
              (await SpaceCreationDraftStore(db).read())!['requestId'],
              cloud.requests.single['requestId'],
            );
            await tester.tap(find.text('Prekliči'));
            await tester.pumpAndSettle();
            cloud.otherAccount();
            await tester.tap(find.text('open'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('space-flow-resume-create')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('sharing-submit')));
            await tester.pumpAndSettle();
            expect(
              find.text(
                'Za nadaljevanje uporabi prvotni račun. Lahko ustvariš tudi drug lokalni prostor.',
              ),
              findsOneWidget,
            );
            expect(cloud.requests, hasLength(1));
            await tester.tap(find.text('Prekliči'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('open'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('space-flow-new-local')),
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<CheckboxListTile>(
                    find.byKey(const ValueKey('space-flow-cloud')),
                  )
                  .onChanged,
              isNull,
            );
            await tester.enterText(
              find.byKey(const ValueKey('sharing-name')),
              'Separate local',
            );
            await tester.tap(find.byKey(const ValueKey('sharing-submit')));
            await tester.pumpAndSettle();
            expect(local.created.single.name, 'Separate local');
            expect(cloud.requests, hasLength(1));
            expect(
              (await SpaceCreationDraftStore(db).read())!['requestId'],
              cloud.requests.single['requestId'],
            );
            cloud.signedIn();
            await tester.tap(find.text('open'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('space-flow-resume-create')),
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<TextFormField>(
                    find.byKey(const ValueKey('sharing-name')),
                  )
                  .enabled,
              false,
            );
            cloud.fail = false;
            await tester.tap(find.byKey(const ValueKey('sharing-submit')));
            await tester.pumpAndSettle();
            expect(cloud.requests, hasLength(2));
            expect(cloud.requests.first, cloud.requests.last);
            expect(cloud.requests.last['address'], 'Address 1');
            expect(cloud.requests.last['name'], 'New space');
            expect(result!.connected, true);
            expect(local.created, hasLength(1));
            expect(await SpaceCreationDraftStore(db).read(), isNull);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
