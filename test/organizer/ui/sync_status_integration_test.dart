import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/linked_payments_provider.dart';
import 'package:kanban/organizer/data/linked_payments_repository.dart';
import 'package:kanban/organizer/presentation/finance/linked_payments_section.dart';
import 'sharing_ui_fixture.dart';
import 'local_spaces_navigation_test.dart' show loadCaptureFonts;

CollaborationState tasksState({bool syncing = false, bool error = false}) =>
    CollaborationState(
      session: sharingSession(),
      scopes: [sharingScope()],
      data: {sharingScopeId: sharingData()},
      isSyncing: syncing,
      lastError: error ? const CollaborationException('network') : null,
      pendingCount: error ? 2 : 0,
      lastSuccessfulSyncAt: DateTime.utc(2026, 10, 10, 9),
    );

Future<void> captureStatus(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (Platform.environment['JIVIE_UI_CAPTURE'] != '1') return;
  await tester.pump(const Duration(milliseconds: 100));
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  boundary.markNeedsPaint();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/qa/jivie-sync-status');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> pumpWorkspace(
  WidgetTester tester,
  SharingUiController controller,
  GlobalKey captureKey,
  double width, {
  Widget? content,
  List<Override> extraOverrides = const [],
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadCaptureFonts(tester);
  if (Platform.environment['JIVIE_UI_CAPTURE'] == '1') {
    await tester.runAsync(() async {
      final root = Platform.resolvedExecutable.split('/bin/cache/').first;
      final sf = File('/System/Library/Fonts/SFNS.ttf');
      final data =
          await (await sf.exists()
                  ? sf
                  : File(
                      '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
                    ))
              .readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        ...extraOverrides,
      ],
      child: RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('sl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff2563eb),
            ),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child:
                    content ??
                    SharingWorkspace(
                      view: SharingView.tasks,
                      selectedScopeId: sharingScopeId,
                      showScopePicker: false,
                      onScopeSelected: (_) {},
                      onConnect: () {},
                    ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

class EmptyLocalUi extends LocalSpacesController {
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState();
}

class PaymentUiRepository implements LinkedPaymentsRepository {
  final refreshed = <PaymentSpaceRef>[];
  final resumed = <bool>[];
  Object? error;
  @override
  Future<PaymentSnapshot> refresh(PaymentSpaceRef space) async {
    refreshed.add(space);
    if (error != null) throw error!;
    return paymentSnapshot();
  }

  @override
  Future<void> resumePending() async {
    resumed.add(true);
    if (error != null) throw error!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PaymentSnapshot paymentSnapshot({int pending = 0, bool fresh = true}) =>
    PaymentSnapshot(
      pendingCount: pending,
      fresh: fresh,
      events: [
        PaymentEvent(
          eventId: 'payment',
          sourceScopeId: 'local',
          sourceEntryId: 'expense',
          sourceRevision: 1,
          payerAccountId: 'owner',
          amountMinor: 100,
          currency: 'EUR',
          paidAt: sharingTestNow,
          expectReimbursement: false,
          revision: 1,
        ),
      ],
    );

void main() {
  testWidgets(
    'finance-only cloud action opens financial comparison instead of empty general editor',
    (tester) async {
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          data: {sharingScopeId: sharingData()},
          financeSupported: true,
          financePolicies: {
            sharingScopeId: const SharedFinancePolicy(
              enabled: true,
              grant: SharedFinanceGrant.write,
            ),
          },
          financeSnapshotComplete: {sharingScopeId: true},
          financeConflicts: [
            SharedFinanceConflict(
              id: 'finance-conflict',
              scopeId: sharingScopeId,
              recordId: 'entry',
              recordType: SharedFinanceRecordType.personalFinanceEntry,
              reason: 'conflict',
              localPayload: {
                'title': 'Preverjen finančni vnos',
                'amountMinor': 100,
                'currency': 'EUR',
                'kind': 'expense',
                'occurredAt': '2026-10-05T10:00:00Z',
              },
              remotePayload: {
                'title': 'Druga finančna različica',
                'amountMinor': 200,
                'currency': 'EUR',
                'kind': 'expense',
                'occurredAt': '2026-10-05T10:00:00Z',
              },
            ),
          ],
        ),
      );
      await pumpWorkspace(tester, controller, GlobalKey(), 390);
      await tester.tap(find.byKey(const ValueKey('sharing-sync-status-cloud')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('Preglej spremembe'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sporne finančne spremembe'), findsOneWidget);
      await tester.tap(find.text('Na tej napravi'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Preverjen finančni vnos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets(
    'linked payment cloud and open overlay update supplemental counts with explicit label',
    (tester) async {
      final controller = SharingUiController(initial: tasksState());
      final snapshot = ValueNotifier(paymentSnapshot(pending: 3));
      final repo = PaymentUiRepository();
      await pumpWorkspace(
        tester,
        controller,
        GlobalKey(),
        390,
        extraOverrides: [
          localSpacesProvider.overrideWith(EmptyLocalUi.new),
          linkedPaymentsRepositoryProvider.overrideWith((ref) async => repo),
        ],
        content: ValueListenableBuilder<PaymentSnapshot>(
          valueListenable: snapshot,
          builder: (context, current, _) => LinkedPaymentsSection(
            space: const PaymentSpaceRef('local'),
            snapshot: current,
          ),
        ),
      );
      expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sharing-sync-status-cloud')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Osebna plačila in povračila'), findsNWidgets(2));
      expect(find.text('Čakajoče spremembe: 3'), findsOneWidget);
      expect(find.text('Čakajoče spremembe: 0'), findsOneWidget);
      snapshot.value = paymentSnapshot();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Čakajoče spremembe: 3'), findsNothing);
      expect(find.text('Čakajoče spremembe: 0'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('resume-linked-payments')),
        findsNothing,
      );
      await tester.tap(find.text('Zapri'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      snapshot.dispose();
    },
  );
  testWidgets(
    'linked refresh pending repository load cannot follow a newer space',
    (tester) async {
      final controller = SharingUiController(initial: tasksState());
      final space = ValueNotifier(const PaymentSpaceRef('local-a'));
      final ready = Completer<LinkedPaymentsRepository>();
      final repo = PaymentUiRepository();
      await pumpWorkspace(
        tester,
        controller,
        GlobalKey(),
        390,
        extraOverrides: [
          localSpacesProvider.overrideWith(EmptyLocalUi.new),
          linkedPaymentsRepositoryProvider.overrideWith((ref) => ready.future),
        ],
        content: ValueListenableBuilder<PaymentSpaceRef>(
          valueListenable: space,
          builder: (context, current, _) => LinkedPaymentsSection(
            space: current,
            snapshot: paymentSnapshot(fresh: false),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('sharing-sync-status-cloud')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Osveži povezana plačila'));
      await tester.pump();
      space.value = const PaymentSpaceRef('local-b');
      await tester.pump();
      ready.complete(repo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.refreshed, isEmpty);
      expect(repo.resumed, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      space.dispose();
    },
  );
  testWidgets(
    'a saved linked retry callback does nothing after its parent disappears',
    (tester) async {
      final controller = SharingUiController(initial: tasksState());
      final visible = ValueNotifier(true);
      final repo = PaymentUiRepository();
      await pumpWorkspace(
        tester,
        controller,
        GlobalKey(),
        390,
        extraOverrides: [
          localSpacesProvider.overrideWith(EmptyLocalUi.new),
          linkedPaymentsRepositoryProvider.overrideWith((ref) async => repo),
        ],
        content: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, show, _) => show
              ? LinkedPaymentsSection(
                  space: const PaymentSpaceRef('local'),
                  snapshot: paymentSnapshot(pending: 1),
                )
              : const SizedBox.shrink(),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('sharing-sync-status-cloud')));
      await tester.pump(const Duration(milliseconds: 300));
      final retry = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('resume-linked-payments')),
          )
          .onPressed;
      visible.value = false;
      await tester.pump();
      retry!();
      await tester.pump();
      expect(repo.resumed, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      visible.dispose();
    },
  );
  testWidgets(
    'wide selected project and shopping layouts keep one cloud each',
    (tester) async {
      for (final view in [SharingView.projects, SharingView.shopping]) {
        final controller = SharingUiController(initial: tasksState());
        await pumpWorkspace(
          tester,
          controller,
          GlobalKey(),
          1280,
          content: SharingWorkspace(
            view: view,
            selectedScopeId: sharingScopeId,
            selectedProjectId: 'project',
            selectedListId: 'list',
            showScopePicker: false,
            onScopeSelected: (_) {},
            onConnect: () {},
          ),
        );
        expect(find.byType(SharingStatus), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'workspace cloud keeps title, add button and task geometry at $width',
      (tester) async {
        final controller = SharingUiController(initial: tasksState());
        final key = GlobalKey();
        await pumpWorkspace(tester, controller, key, width);
        final title = find.text('Opravila');
        final add = find.widgetWithText(FilledButton, 'Dodaj opravilo');
        final task = find.text('Pripravi zemljo');
        expect(title, findsOneWidget);
        expect(add, findsOneWidget);
        expect(task, findsOneWidget);
        expect(find.byType(SharingStatus), findsOneWidget);
        final titleRect = tester.getRect(title),
            addRect = tester.getRect(add),
            taskRect = tester.getRect(task);
        final slot = find.byKey(const ValueKey('sharing-sync-status-slot'));
        final slotRect = tester.getRect(slot);
        expect(slotRect.size, const Size(88, 48));
        expect(slotRect.top, closeTo(titleRect.center.dy - 24, 1));
        expect(find.text('Ni čakajočih sprememb'), findsNothing);
        await captureStatus(tester, key, '${width.toInt()}-idle');
        controller.replace(tasksState(syncing: true));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.getRect(title), titleRect);
        expect(tester.getRect(add), addRect);
        expect(tester.getRect(task), taskRect);
        expect(tester.getRect(slot), slotRect);
        await captureStatus(tester, key, '${width.toInt()}-syncing');
        controller.replace(tasksState(error: true));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.getRect(title), titleRect);
        expect(tester.getRect(add), addRect);
        expect(tester.getRect(task), taskRect);
        expect(tester.getRect(slot), slotRect);
        await captureStatus(tester, key, '${width.toInt()}-error');
        await tester.tap(
          find.byKey(const ValueKey('sharing-sync-status-cloud')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Sinhronizacija'), findsOneWidget);
        expect(find.text('Čakajoče spremembe: 2'), findsOneWidget);
        await captureStatus(tester, key, '${width.toInt()}-overlay');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
