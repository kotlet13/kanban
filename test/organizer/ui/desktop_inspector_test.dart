import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/desktop/desktop_inspector.dart';
import 'package:kanban/organizer/presentation/finance/finance_access_guard.dart';
import 'package:kanban/organizer/presentation/finance/finance_plan_forms.dart';
import 'package:kanban/organizer/presentation/organizer_editors.dart';
import 'package:kanban/organizer/presentation/shared/sharing_session_boundary.dart';
import 'package:kanban/organizer/presentation/shared/sharing_forms.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'package:kanban/organizer/data/organizer_storage.dart';
import 'sharing_ui_fixture.dart';

class MemoryOrganizerStorage implements OrganizerStorage {
  OrganizerSnapshot snapshot = OrganizerSnapshot();
  int writes = 0;
  @override
  Future<OrganizerSnapshot> read() async => snapshot;
  @override
  Future<void> write(OrganizerSnapshot next) async {
    snapshot = next;
    writes++;
  }

  @override
  Future<void> close() async {}
}

final _save = find.byKey(const ValueKey('organizer-save'));
final _title = find.byKey(const ValueKey('organizer-title-field'));
final _cancel = find.widgetWithText(TextButton, 'Cancel');

class _Host {
  final inspector = OrganizerDesktopInspectorController();
  final navigator = GlobalKey<NavigatorState>();
  final panel = GlobalKey();
  late BuildContext context;
  late WidgetRef ref;
  int interactions = 0;
}

Future<_Host> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  SharingUiController? shared,
  double width = 1280,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final host = _Host();
  addTearDown(host.inspector.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(
          () => shared ?? SharingUiController(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: host.navigator,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(platform: platform),
        home: OrganizerDesktopInspectorScope(
          controller: host.inspector,
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(collaborationProvider);
                host.context = context;
                host.ref = ref;
                return ListenableBuilder(
                  listenable: host.inspector,
                  builder: (context, _) => LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        if (!host.inspector.isOpen ||
                            constraints.maxWidth > 900)
                          Expanded(
                            child: TextButton(
                              onPressed: () => host.interactions++,
                              child: const Text('Underlying list'),
                            ),
                          ),
                        if (host.inspector.isOpen)
                          SizedBox(
                            width: constraints.maxWidth > 900
                                ? 520
                                : constraints.maxWidth,
                            child: OrganizerDesktopInspectorPanel(
                              key: host.panel,
                              controller: host.inspector,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

Future<void> _open(
  WidgetTester tester,
  _Host host, {
  OrganizerEditorKind kind = OrganizerEditorKind.task,
  OrganizerDraft? draft,
  Future<void> Function(OrganizerDraft)? onSave,
  Future<void> Function()? onDelete,
  Widget Function(Widget)? wrap,
}) async {
  unawaited(
    showOrganizerEditor(
      host.context,
      heading: 'Edit record',
      kind: kind,
      draft: draft ?? OrganizerDraft(title: 'Initial'),
      onSave: onSave ?? (_) async {},
      onDelete: onDelete,
      wrap: wrap,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'recorded finance uses inspector and retains ledger identity on Save',
    (tester) async {
      final storage = MemoryOrganizerStorage();
      final repository = OrganizerRepository(storage);
      await repository.initialize();
      await repository.createFinanceEntry(
        title: 'Recorded',
        amountMinor: 500,
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime(2026, 10, 12),
      );
      addTearDown(() async {
        final closing = repository.close();
        await tester.pump();
        await tester.runAsync(() => closing);
      });
      final entry = repository.snapshot.financeEntries.single;
      final host = await _pump(tester);
      unawaited(
        showRecordedFinanceOccurrenceEditor(
          host.context,
          entry: entry,
          onSave: repository.updateFinanceEntry,
        ),
      );
      await tester.pumpAndSettle();
      expect(host.inspector.isOpen, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Underlying list').hitTestable(), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('sharing-recorded-title')),
        'Corrected',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sharing-actual-amount')),
        '12.50',
      );
      expect(repository.snapshot.financeEntries.single.amountMinor, 500);
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      final saved = repository.snapshot.financeEntries.single;
      expect(saved.title, 'Corrected');
      expect(saved.amountMinor, 1250);
      expect(saved.id, entry.id);
      expect(saved.currency, entry.currency);
      expect(saved.kind, entry.kind);
      expect(saved.ledgerAccountId, entry.ledgerAccountId);
      expect(host.inspector.isOpen, isFalse);
      expect(host.navigator.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account sharing form remains modal on desktop', (tester) async {
    final host = await _pump(tester);
    unawaited(
      showSharingForm(
        host.context,
        title: 'Register',
        fields: const [SharingField(id: 'email', label: 'Email')],
        submitLabel: 'Register',
        onSubmit: (_) async {},
        errorMessage: (_) => 'Error',
      ),
    );
    await tester.pumpAndSettle();
    expect(host.inspector.isOpen, isFalse);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(host.navigator.currentState!.canPop(), isFalse);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'nonmodal ${platform.name} editor saves once to real repository',
      (tester) async {
        final storage = MemoryOrganizerStorage();
        final repository = OrganizerRepository(storage);
        await repository.initialize();
        addTearDown(() async {
          final closing = repository.close();
          await tester.pump();
          await tester.runAsync(() => closing);
        });
        final host = await _pump(tester, platform: platform);
        await _open(
          tester,
          host,
          onSave: (d) => repository.createTask(title: d.title, notes: d.notes),
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Underlying list').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Underlying list'));
        expect(host.interactions, 1);
        await tester.enterText(_title, 'Saved from inspector');
        expect(repository.snapshot.tasks, isEmpty);
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(repository.snapshot.tasks.single.title, 'Saved from inspector');
        expect(storage.writes, 1);
        expect(host.inspector.isOpen, isFalse);
        expect(host.navigator.currentState!.canPop(), isFalse);
        expect(find.text('Underlying list'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'another open and resizing retain dirty form until explicit Cancel',
    (tester) async {
      final storage = MemoryOrganizerStorage();
      final repository = OrganizerRepository(storage);
      await repository.initialize();
      addTearDown(() async {
        final closing = repository.close();
        await tester.pump();
        await tester.runAsync(() => closing);
      });
      final host = await _pump(tester);
      Future<void> save(OrganizerDraft d) =>
          repository.createTask(title: d.title);
      await _open(tester, host, onSave: save);
      await tester.enterText(_title, 'Unsaved draft');
      await _open(
        tester,
        host,
        draft: OrganizerDraft(title: 'Second row'),
        onSave: save,
      );
      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(find.text('Second row'), findsNothing);
      tester.view.physicalSize = const Size(680, 900);
      await tester.pumpAndSettle();
      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(_save.hitTestable(), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();
      expect(find.text('Unsaved draft'), findsOneWidget);
      await tester.tap(_cancel);
      await tester.pumpAndSettle();
      expect(repository.snapshot.tasks, isEmpty);
      expect(storage.writes, 0);
      expect(host.inspector.isOpen, isFalse);
      expect(host.navigator.currentState!.canPop(), isFalse);
    },
  );

  testWidgets(
    'Delete confirmation is a separate dialog and closes only inspector',
    (tester) async {
      final repository = OrganizerRepository(MemoryOrganizerStorage());
      await repository.initialize();
      await repository.createTask(title: 'Existing');
      addTearDown(() async {
        final closing = repository.close();
        await tester.pump();
        await tester.runAsync(() => closing);
      });
      final host = await _pump(tester);
      await _open(
        tester,
        host,
        onDelete: () =>
            repository.deleteTask(repository.snapshot.tasks.single.id),
      );
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(repository.snapshot.tasks, hasLength(1));
      expect(host.inspector.isOpen, isTrue);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repository.snapshot.tasks, isEmpty);
      expect(host.inspector.isOpen, isFalse);
      expect(host.navigator.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('busy save disables Cancel and failures retain draft', (
    tester,
  ) async {
    final host = await _pump(tester);
    final save = Completer<void>();
    await _open(tester, host, onSave: (_) => save.future);
    await tester.enterText(_title, 'Retry title');
    await tester.tap(_save);
    await tester.pump();
    expect(tester.widget<TextButton>(_cancel).onPressed, isNull);
    save.completeError(const FormatException('failed'));
    await tester.pumpAndSettle();
    expect(host.inspector.isOpen, isTrue);
    expect(find.text('Retry title'), findsOneWidget);
    expect(_save.hitTestable(), findsOneWidget);
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(host.inspector.isOpen, isFalse);
  });

  for (final kind in [
    OrganizerEditorKind.project,
    OrganizerEditorKind.event,
    OrganizerEditorKind.finance,
  ]) {
    testWidgets(
      '${kind.name} inspector validates and saves unchanged domain data',
      (tester) async {
        final storage = MemoryOrganizerStorage();
        final repository = OrganizerRepository(storage);
        await repository.initialize();
        addTearDown(() async {
          final closing = repository.close();
          await tester.pump();
          await tester.runAsync(() => closing);
        });
        final host = await _pump(tester);
        final date = DateTime(2026, 10, 12, 15);
        await _open(
          tester,
          host,
          kind: kind,
          draft: OrganizerDraft(date: date, amount: '12.50'),
          onSave: (d) => switch (kind) {
            OrganizerEditorKind.project => repository.createProject(
              title: d.title,
            ),
            OrganizerEditorKind.event => repository.createEvent(
              title: d.title,
              startsAt: d.date!,
            ),
            _ => repository.createFinanceEntry(
              title: d.title,
              amountMinor: parseMoneyMinor(d.amount),
              kind: d.kind,
              occurredAt: d.date!,
              currency: d.currency,
            ),
          },
        );
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(host.inspector.isOpen, isTrue);
        expect(storage.writes, 0);
        await tester.enterText(_title, 'Saved ${kind.name}');
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(storage.writes, 1);
        if (kind == OrganizerEditorKind.project) {
          expect(repository.snapshot.projects.single.title, 'Saved project');
        } else if (kind == OrganizerEditorKind.event) {
          expect(repository.snapshot.events.single.startsAt, date.toUtc());
        } else {
          expect(repository.snapshot.financeEntries.single.amountMinor, 1250);
          expect(repository.snapshot.financeEntries.single.currency, 'EUR');
        }
        expect(host.inspector.isOpen, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'account guard closes inspector and guarded Delete dialog together',
    (tester) async {
      final shared = SharingUiController();
      final host = await _pump(tester, shared: shared);
      final guard = SharingSessionGuard(host.context, host.ref);
      var deletes = 0;
      await _open(
        tester,
        host,
        onDelete: () async => deletes++,
        wrap: (child) => SharingSessionBoundary(guard: guard, child: child),
      );
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      shared.switchAccount();
      await tester.pumpAndSettle();
      expect(host.inspector.isOpen, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(deletes, 0);
      expect(host.navigator.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('wide ${platform.name} tablet keeps modal editor', (
      tester,
    ) async {
      final host = await _pump(tester, platform: platform);
      await _open(tester, host);
      expect(host.inspector.isOpen, isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(_cancel);
      await tester.pumpAndSettle();
      expect(host.navigator.currentState!.canPop(), isFalse);
    });
  }

  testWidgets('account guard pops scoped route and keeps organizer root', (
    tester,
  ) async {
    final shared = SharingUiController();
    final host = await _pump(tester, shared: shared);
    final guard = SharingSessionGuard(host.context, host.ref);
    var writes = 0;
    await _open(
      tester,
      host,
      onSave: (_) async => writes++,
      wrap: (child) => SharingSessionBoundary(guard: guard, child: child),
    );
    await tester.enterText(_title, 'Old account draft');
    shared.switchAccount();
    await tester.pumpAndSettle();
    expect(host.inspector.isOpen, isFalse);
    expect(writes, 0);
    expect(host.navigator.currentState!.canPop(), isFalse);
    expect(find.text('Underlying list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoked finance access closes inspector without writes', (
    tester,
  ) async {
    CollaborationState sharedState(SharedFinanceGrant grant) =>
        CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          financePolicies: {
            sharingScopeId: SharedFinancePolicy(enabled: true, grant: grant),
          },
          financeSnapshotComplete: {sharingScopeId: true},
        );
    final shared = SharingUiController(
      initial: sharedState(SharedFinanceGrant.write),
    );
    final host = await _pump(tester, shared: shared);
    final guard = FinanceAccessGuard(
      host.context,
      host.ref,
      sharingScopeId,
      write: true,
    );
    expect(guard.isCurrent, isTrue);
    var writes = 0;
    await _open(
      tester,
      host,
      kind: OrganizerEditorKind.finance,
      draft: OrganizerDraft(
        title: 'Private expense',
        amount: '12',
        date: DateTime(2026),
      ),
      onSave: (_) async => writes++,
      wrap: guard.wrap,
    );
    shared.replace(sharedState(SharedFinanceGrant.read));
    await tester.pumpAndSettle();
    expect(host.inspector.isOpen, isFalse);
    expect(writes, 0);
    expect(host.navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
