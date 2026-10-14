import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kanban/l10n/l10n.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/platform/backup_preferences_replay.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/presentation/shared/space_picker.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/notification_local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/portable_backup_provider.dart';

import '../data/collaboration_repository_test.dart'
    show FakeServer, MemorySessionStore;
import '../data/local_space_publication_test.dart' show PublicationTransport;
import 'backup_ui_fixture.dart';

class _SelectionDatabase extends CollaborationDatabase {
  _SelectionDatabase() : super(NativeDatabase.memory());
  void Function()? afterSelectionRead;
  final selectionWrites = <Object?>[];

  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) {
    if (args.length == 2 &&
        sql.startsWith('INSERT INTO local_meta') &&
        args.first.toString().startsWith('selected_space:')) {
      selectionWrites.add(args[1]);
    }
    return super.execute(sql, args);
  }

  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final result = await super.rows(sql, args);
    if (sql == 'SELECT data FROM scopes WHERE partition=? AND id=?') {
      final action = afterSelectionRead;
      afterSelectionRead = null;
      action?.call();
    }
    return result;
  }
}

class _Fixture {
  _Fixture(
    this.database,
    this.repository,
    this.spaces,
    this.home,
    this.pending,
  );
  final _SelectionDatabase database;
  final CollaborationRepository repository;
  final LocalSpacesRepository spaces;
  final LocalSpace home;
  final MemoryPendingInvitationStore pending;
  late ProviderContainer container;

  static Future<_Fixture> create() async {
    final db = _SelectionDatabase();
    await SqliteOrganizerStorage(db).initialize();
    final pending = MemoryPendingInvitationStore();
    final repository = CollaborationRepository(
      db,
      PublicationTransport(FakeServer()),
      MemorySessionStore(),
      invitationStore: pending,
      ownsDatabase: false,
    );
    await repository.initialize();
    await repository.login(
      serverUrl: 'https://publication.example.test',
      username: 'alice',
      password: 'synthetic-password',
    );
    await repository.createScope('Unrelated existing household');
    final spaces = LocalSpacesRepository(db);
    final home = await spaces.createSpace(
      kind: LocalSpaceKind.household,
      name: 'SLT selected household',
    );
    await spaces.selectSpace(home.id);
    return _Fixture(db, repository, spaces, home, pending);
  }

  Future<void> bind(String scope, {String? partition}) async {
    await database.transaction(() async {
      await database.execute('UPDATE local_spaces SET data=? WHERE id=?', [
        jsonEncode(
          LocalSpace(
            id: home.id,
            kind: home.kind,
            name: home.name,
            binding: LocalSpaceBinding(
              partition: partition ?? repository.state.session!.partition,
              scopeId: scope,
            ),
          ).toJson(),
        ),
        home.id,
      ]);
      await database.touchPersonal();
    });
    database.personalChanged();
  }

  Future<void> mount(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'app_locale_code': 'sl',
      'app_theme_mode': 'light',
    });
    container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWith((ref) async => database),
        collaborationRepositoryProvider.overrideWith((ref) async => repository),
        pendingInvitationStoreProvider.overrideWithValue(pending),
        organizerStorageProvider.overrideWithValue(
          () async => SqliteOrganizerStorage(database),
        ),
        invitationLinkSourceProvider.overrideWithValue(null),
        portableBackupProvider.overrideWith(EmptyBackupUiController.new),
        backupPreferencesReplayProvider.overrideWith((ref) async => {}),
        notificationLocalSnapshotsProvider.overrideWith(
          (ref) async => [await ref.watch(organizerProvider.future)],
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('sl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: OrganizerSpacePicker(onSelected: (_) {}, onConnect: () {}),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await container.read(collaborationProvider.future);
      await container.read(localSpacesProvider.future);
      await container.read(organizerProvider.future);
    });
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await _run(tester, () async {
      await repository.close();
      await database.close();
    });
  }

  OrganizerSpacePickerButton picker(WidgetTester tester) =>
      tester.widget<OrganizerSpacePickerButton>(
        find.descendant(
          of: find.byType(OrganizerSpacePicker).first,
          matching: find.byType(OrganizerSpacePickerButton),
        ),
      );
}

Future<T> _run<T>(WidgetTester tester, Future<T> Function() action) async {
  T? result;
  Object? failure;
  StackTrace? trace;
  var done = false;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (value) {
          result = value;
          done = true;
        },
        onError: (Object error, StackTrace stack) {
          failure = error;
          trace = stack;
          done = true;
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
  });
  for (var i = 0; !done && i < 500; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  if (!done) throw StateError('Synthetic database action did not finish');
  return result as T;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  testWidgets(
    'account-only consumer leaves organizer and platform DB unopened',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      f.container = ProviderContainer(
        overrides: [
          collaborationRepositoryProvider.overrideWith(
            (ref) async => f.repository,
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Text(
                ref
                        .watch(collaborationProvider)
                        .valueOrNull
                        ?.session
                        ?.username ??
                    'Loading',
              ),
            ),
          ),
        ),
      );
      await _run(tester, () => f.container.read(collaborationProvider.future));
      await tester.pumpAndSettle();
      expect(find.text('alice'), findsOneWidget);
      expect(f.container.exists(localSpacesProvider), false);
      expect(f.container.exists(organizerRepositoryProvider), false);
      expect(f.container.exists(localDatabaseProvider), false);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets('real publication follows exact selected binding at $width', (
      tester,
    ) async {
      final fixture = await tester.runAsync(_Fixture.create);
      final f = fixture!;
      await f.mount(tester, width);
      await _run(tester, () async {
        await f.container
            .read(organizerProvider.notifier)
            .createTask(title: 'Preserved published task');
      });
      await tester.pumpAndSettle();
      expect(f.picker(tester).value, 'local:${f.home.id}');
      await _run(tester, () async {
        final controller = f.container.read(collaborationProvider.notifier);
        final preview = await controller.previewLocalSpacesPublication([
          f.home.id,
        ]);
        await controller.publishLocalSpaces(preview);
      });
      await tester.pumpAndSettle();
      final binding = f.container
          .read(localSpacesProvider)
          .requireValue
          .selectedSpace!
          .binding!;
      expect(binding.partition, f.repository.state.session!.partition);
      expect(f.repository.state.selectedSpaceId, binding.scopeId);
      expect(f.picker(tester).value, binding.scopeId);
      await tester.tap(find.byType(OrganizerSpacePickerButton).first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('space-choice-${binding.scopeId}')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Zapri'));
      await tester.pumpAndSettle();
      expect(
        f.repository.state.dataForScope(binding.scopeId).tasks.single.title,
        'Preserved published task',
      );
      await _run(tester, () async {
        expect(
          (await SqliteOrganizerStorage(
            f.database,
          ).localSnapshot(workspace: f.home.id)).tasks.single.title,
          'Preserved published task',
        );
      });
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }

  testWidgets('binding waits for its exact scope and survives late arrival', (
    tester,
  ) async {
    final f = (await tester.runAsync(_Fixture.create))!;
    late String target;
    await _run(tester, () async {
      target = await f.repository.createScope('Late household');
      await f.database.execute('DELETE FROM scopes WHERE id=?', [target]);
      await f.repository.refreshLocal();
    });
    await f.mount(tester, 1280);
    // Mount's initial refresh can discover it; remove it once more before binding.
    await _run(tester, () async {
      await f.database.execute('DELETE FROM scopes WHERE id=?', [target]);
      await f.repository.refreshLocal();
      await f.bind(target);
    });
    await tester.pumpAndSettle();
    expect(f.repository.state.selectedSpaceId, isNull);
    expect(f.picker(tester).value, 'local:${f.home.id}');
    await tester.tap(find.byType(OrganizerSpacePickerButton).first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('space-choice-local:${f.home.id}')),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Zapri'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
    await _run(tester, f.repository.syncNow);
    await tester.pumpAndSettle();
    expect(f.repository.state.selectedSpaceId, target);
    expect(f.picker(tester).value, target);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('another account binding never selects a same-ID remote scope', (
    tester,
  ) async {
    final f = (await tester.runAsync(_Fixture.create))!;
    await f.mount(tester, 390);
    final target = f.repository.state.scopes.first.id;
    await _run(
      tester,
      () => f.bind(target, partition: 'another-server-and-account'),
    );
    await tester.pumpAndSettle();
    expect(f.repository.state.selectedSpaceId, isNull);
    expect(f.picker(tester).value, 'local:${f.home.id}');
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  for (final allSpaces in [false, true]) {
    testWidgets('explicit ${allSpaces ? 'All' : 'local'} wins awaited handoff', (
      tester,
    ) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      await f.mount(tester, 390);
      Future<void>? userChoice;
      final controller = f.container.read(collaborationProvider.notifier);
      final target = f.repository.state.scopes.first.id;
      f.database.selectionWrites.clear();
      final navigationZone = Zone.current;
      f.database.afterSelectionRead = () => navigationZone.run(() {
        // The old handoff already started its transaction and awaited the scope
        // read. An explicit navigation intent must invalidate its pending write.
        userChoice = allSpaces
            ? controller.selectAllSpaces()
            : controller
                  .selectSpace(null)
                  .then(
                    (_) => f.container
                        .read(localSpacesProvider.notifier)
                        .selectSpace('local'),
                  );
      });
      await _run(tester, () => f.bind(target));
      await tester.pumpAndSettle();
      expect(userChoice, isNotNull);
      await _run(tester, () => userChoice!);
      await tester.pumpAndSettle();
      expect(f.repository.state.selectedSpaceId, isNull);
      expect(f.database.selectionWrites, isNot(contains(target)));
      expect(f.repository.state.allSpacesSelected, allSpaces);
      expect(
        f.picker(tester).value,
        allSpaces ? OrganizerSpacePicker.allAction : 'local:local',
      );
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }

  testWidgets('account exit cancels awaited handoff without a late error', (
    tester,
  ) async {
    final f = (await tester.runAsync(_Fixture.create))!;
    await f.mount(tester, 390);
    Future<bool>? accountExit;
    final controller = f.container.read(collaborationProvider.notifier);
    final target = f.repository.state.scopes.first.id;
    f.database.selectionWrites.clear();
    final navigationZone = Zone.current;
    f.database.afterSelectionRead = () => navigationZone.run(() {
      accountExit = controller.signOut();
    });
    await _run(tester, () => f.bind(target));
    await tester.pumpAndSettle();
    expect(accountExit, isNotNull);
    await _run(tester, () => accountExit!);
    await tester.pumpAndSettle();
    expect(f.repository.state.session, isNull);
    expect(f.repository.state.selectedSpaceId, isNull);
    expect(f.database.selectionWrites, isNot(contains(target)));
    expect(f.container.read(collaborationBackgroundErrorProvider), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });
}
