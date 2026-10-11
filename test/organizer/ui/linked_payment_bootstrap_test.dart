import 'dart:async';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/l10n.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/linked_payments_repository.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_workspace.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/linked_payments_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import '../data/collaboration_repository_test.dart' show MemorySessionStore;
import '../data/linked_payments_repository_test.dart' show PaymentTransport;

class BootstrapTransport extends PaymentTransport {
  bool supported = true;
  String? target;
  Object? snapshotError;
  bool wrongSource = false;
  bool denyPolicy = false;
  bool readOnlyTarget = false;
  Future<void> Function()? beforeSnapshotReply;
  final snapshotScopes = <String>[];

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'finance3.payments') {
      snapshotScopes.add(params['scopeId'] as String);
      if (params['scopeId'] == target && snapshotError != null) {
        throw snapshotError!;
      }
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities') {
      return {
        ...reply,
        'features': <String, dynamic>{
          ...reply['features'] as Map,
          'linkedPayments': supported,
        },
      };
    }
    if (operation == 'finance2.policy') {
      return {
        ...reply,
        if (readOnlyTarget && params['scopeId'] == target) 'grant': 'read',
        if (denyPolicy && params['scopeId'] == target) ...{
          'grant': 'none',
          'revision': 2,
        },
        'linkedPaymentsRequired':
            paymentEvents.values.any(
              (event) => event['sourceScopeId'] == params['scopeId'],
            ) ||
            (targetProjections[params['scopeId']]?.isNotEmpty ?? false),
      };
    }
    if (operation == 'finance3.paymentCommit' &&
        params['personalTarget'] is Map) {
      final target = params['personalTarget'] as Map;
      targetProjections[target['scopeId'] as String] = [
        PaymentProjection(
              event: PaymentEvent.fromJson(
                reply['event'] as Map<String, dynamic>,
              ),
              state: PaymentProjectionState.complete,
              privateAccountId: target['accountId'] as String,
            ).toJson()
            as Map<String, dynamic>,
      ];
    }
    if (operation == 'finance3.payments' && params['scopeId'] == target) {
      final hook = beforeSnapshotReply;
      beforeSnapshotReply = null;
      await hook?.call();
      if (wrongSource) {
        return {
          ...reply,
          'events': [
            PaymentEvent(
              eventId: newSharedId(),
              sourceScopeId: newSharedId(),
              sourceEntryId: newSharedId(),
              sourceRevision: 1,
              payerAccountId: newSharedId(),
              amountMinor: 3000,
              currency: 'EUR',
              paidAt: DateTime.now().toUtc(),
              expectReimbursement: true,
              revision: 1,
            ).toJson(),
          ],
        };
      }
    }
    return reply;
  }
}

class Fixture {
  Fixture(
    this.db,
    this.shared,
    this.transport,
    this.project,
    this.card,
    this.entry,
  );
  final CollaborationDatabase db;
  final CollaborationRepository shared;
  final BootstrapTransport transport;
  final String project, card, entry;
  PaymentSpaceRef get source =>
      PaymentSpaceRef(project, partition: shared.state.session!.partition);
  LinkedPaymentsRepository get payments =>
      LinkedPaymentsRepository(db, collaboration: shared);

  static Future<Fixture> create({
    bool supported = true,
    bool privateSync = false,
  }) async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    final storage = SqliteOrganizerStorage(db);
    await storage.initialize();
    final personal = OrganizerRepository(storage);
    await personal.initialize();
    final now = DateTime.now().toUtc();
    final card = newSharedId();
    await personal.saveFinancePlan(
      accounts: [
        LocalFinanceAccount(
          id: card,
          name: 'Bootstrap personal card',
          currency: 'EUR',
          openingBalanceMinor: 0,
          openingBalanceAt: now.subtract(const Duration(days: 1)),
          createdAt: now,
          updatedAt: now,
        ),
      ],
      rules: [],
      expectedRevision: personal.snapshot.revision,
      expectedWorkspaceKey: 'local',
    );
    await personal.close();
    final transport = BootstrapTransport()
      ..supported = supported
      ..scoped = true;
    final shared = CollaborationRepository(
      db,
      transport,
      MemorySessionStore(),
      ownsDatabase: false,
    );
    await shared.initialize();
    await shared.login(
      serverUrl: 'https://bootstrap.example.test',
      username: 'alice',
      password: 'synthetic-password',
    );
    if (privateSync) {
      await shared.enablePrivateSync(
        expectedRevision: (await shared.previewPrivateSync()).revision,
      );
    }
    final spaces = LocalSpacesRepository(db);
    final org = await spaces.createSpace(
      kind: LocalSpaceKind.organization,
      name: 'Bootstrap organization',
    );
    final local = OrganizerRepository(
      SqliteOrganizerStorage(db, workspaceId: org.id),
    );
    await local.initialize();
    await local.createProject(title: 'Bootstrap project');
    final project = local.snapshot.projects.single.id;
    await local.close();
    await shared.publishLocalSpaces(
      await shared.previewLocalSpacesPublication([org.id]),
    );
    final account = await shared.createFinanceAccount(
      scopeId: project,
      name: 'Bootstrap source account',
      currency: 'EUR',
      openingBalanceMinor: 10000,
    );
    final entry = await shared.createFinanceEntry(
      scopeId: project,
      accountId: account,
      kind: FinanceEntryKind.expense,
      amountMinor: 3000,
      currency: 'EUR',
      title: 'First linked expense',
      occurredAt: now,
    );
    await shared.syncNow();
    await shared.selectSpace(project);
    transport.target = project;
    return Fixture(db, shared, transport, project, card, entry);
  }

  Future<void> close() async {
    await shared.close();
    await db.close();
  }
}

// Advance provider notifications as well as the native SQLite event loop.
Future<T> advance<T>(WidgetTester tester, Future<T> Function() action) async {
  T? value;
  Object? failure;
  StackTrace? trace;
  var done = false;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (result) {
          value = result;
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
  if (!done) throw StateError('Synthetic bootstrap action did not finish');
  return value as T;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  for (final privateSync in [false, true]) {
    testWidgets(
      'new published project empty fetch enables first payment privateSync=$privateSync',
      (tester) async {
        final f = (await tester.runAsync(
          () => Fixture.create(privateSync: privateSync),
        ))!;
        expect(
          f.shared.state
              .financePolicyForScope(f.project)
              .linkedPaymentsRequired,
          false,
        );
        expect(
          f.shared.state.scopes
              .firstWhere((s) => s.id == f.project)
              .organizationId,
          isNotNull,
        );
        final container = ProviderContainer(
          overrides: [
            localDatabaseProvider.overrideWith((ref) async => f.db),
            collaborationRepositoryProvider.overrideWith(
              (ref) async => f.shared,
            ),
            organizerStorageProvider.overrideWithValue(
              () async => SqliteOrganizerStorage(f.db),
            ),
          ],
        );
        final listener = container.listen(
          linkedPaymentsProvider(paymentSpaceKey(f.source)),
          (_, _) {},
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('sl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final shared = ref
                          .watch(collaborationProvider)
                          .valueOrNull;
                      final local = ref.watch(localSpacesProvider).valueOrNull;
                      if (shared == null || local == null) {
                        return const Text('Loading');
                      }
                      return SharedFinanceWorkspace(
                        scope: shared.scopes.firstWhere(
                          (s) => s.id == f.project,
                        ),
                        state: shared,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        final snapshot = await advance(
          tester,
          () => container.read(
            linkedPaymentsProvider(paymentSpaceKey(f.source)).future,
          ),
        );
        await tester.pumpAndSettle();
        expect(snapshot.events, isEmpty);
        expect(snapshot.projections, isEmpty);
        final action = find.byKey(ValueKey('personal-payment-${f.entry}'));
        expect(action, findsOneWidget);
        expect(snapshot.fresh, true);
        expect(f.transport.snapshotScopes, contains(f.project));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('sharing-personal-account')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Bootstrap personal card').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('sharing-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await advance(tester, () async {
          for (var i = 0; i < 30 && f.transport.paymentCalls == 0; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        });
        await tester.pumpAndSettle();
        await advance(tester, f.shared.syncNow);
        final paid = await advance(tester, () => f.payments.read(f.source));
        expect(paid.events.single.sourceEntryId, f.entry);
        expect(paid.events.single.amountMinor, 3000);
        expect(f.transport.paymentEvents, hasLength(1));
        expect(
          f.shared.state.dataForScope(f.project).financeEntries,
          hasLength(1),
        );
        final personal = await advance(
          tester,
          () => f.payments.read(const PaymentSpaceRef('local')),
        );
        expect(personal.fresh, true);
        expect(personal.cashBurdenByCurrency['EUR'], BigInt.from(3000));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        listener.close();
        container.dispose();
        await advance(tester, f.close);
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }

  test(
    'server without linked capability keeps ordinary finance sync working',
    () async {
      final f = await Fixture.create(supported: false);
      addTearDown(f.close);
      expect(f.shared.state.lastError, isNull);
      expect(f.shared.state.financeSnapshotComplete[f.project], true);
      expect(f.transport.snapshotScopes, isEmpty);
      expect((await f.payments.read(f.source)).fresh, false);
    },
  );

  for (final failure in ['wrong_scope', 'network', 'denied']) {
    test(
      'failed bootstrap $failure never creates an empty freshness proof',
      () async {
        final f = await Fixture.create(supported: false);
        addTearDown(f.close);
        f.transport.supported = true;
        f.transport.wrongSource = failure == 'wrong_scope';
        f.transport.snapshotError = switch (failure) {
          'network' => const CollaborationException('network'),
          'denied' => const CollaborationApiException('finance_forbidden'),
          _ => null,
        };
        final key = 'linked_payment_complete:${f.source.key}';
        await f.shared.syncNow();
        expect(
          await f.db.rows('SELECT value FROM local_meta WHERE name=?', [key]),
          isEmpty,
        );
        if (failure == 'denied') {
          expect(
            f.shared.state.financePolicyForScope(f.project).canRead,
            false,
          );
        } else {
          expect(
            f.shared.state.lastError?.code,
            failure == 'wrong_scope' ? 'invalid_response' : 'network',
          );
          expect((await f.payments.read(f.source)).fresh, false);
        }
      },
    );
  }

  test(
    'late empty bootstrap response cannot attest a departed account',
    () async {
      final f = await Fixture.create(supported: false);
      addTearDown(f.close);
      final source = f.source;
      final entered = Completer<void>(), release = Completer<void>();
      f.transport.supported = true;
      f.transport.beforeSnapshotReply = () async {
        entered.complete();
        await release.future;
      };
      final sync = f.shared.syncNow();
      await entered.future;
      await f.shared.signOut();
      release.complete();
      await sync;
      expect(f.shared.state.session, isNull);
      expect(f.shared.state.lastError, isNull);
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          'linked_payment_complete:${source.key}',
        ]),
        isEmpty,
      );
    },
  );

  test(
    'empty household and read-only project do not request payment bootstrap',
    () async {
      final f = await Fixture.create(supported: false);
      addTearDown(f.close);
      f.transport.supported = true;
      f.transport.readOnlyTarget = true;
      final home = await f.shared.createScope('Ordinary household');
      await f.shared.syncNow();
      expect(f.transport.snapshotScopes, isNot(contains(home)));
      expect(f.transport.snapshotScopes, isNot(contains(f.project)));
      expect(f.shared.state.financePolicyForScope(f.project).canRead, true);
      expect(f.shared.state.financePolicyForScope(f.project).canWrite, false);
      expect(f.shared.state.financeSnapshotComplete[f.project], true);
    },
  );

  test('newer finance denial defeats an in-flight empty snapshot', () async {
    final f = await Fixture.create(supported: false);
    addTearDown(f.close);
    final source = f.source;
    final entered = Completer<void>(), release = Completer<void>();
    f.transport.supported = true;
    f.transport.beforeSnapshotReply = () async {
      entered.complete();
      await release.future;
    };
    final sync = f.shared.syncNow();
    await entered.future;
    f.transport.denyPolicy = true;
    await f.shared.refreshFinancePolicy(f.project);
    release.complete();
    await sync;
    expect(f.shared.state.financePolicyForScope(f.project).canRead, false);
    expect(f.shared.state.lastError?.code, 'finance_access_changed');
    expect(
      await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
        'linked_payment_complete:${source.key}',
      ]),
      isEmpty,
    );
  });
}
