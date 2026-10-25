import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart'
    show CryptoAuthorityPending;
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import '../data/collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;
import '../support/synthetic_content_route_guard.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/editor_actions.dart';
import 'package:kanban/organizer/presentation/finance/finance_entry_accounts.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';

const parentId = '10000000-0000-4000-8000-000000000001';
const projectId = '10000000-0000-4000-8000-000000000002';
const bankId = '10000000-0000-4000-8000-000000000003';
const otherId = '10000000-0000-4000-8000-000000000004';
const project = SharedScope(
  id: projectId,
  name: 'Project',
  kind: SharedScopeKind.project,
  role: SharedRole.owner,
  parentScopeId: parentId,
);
const policy = SharedFinancePolicy(
  enabled: true,
  grant: SharedFinanceGrant.write,
  revision: 1,
);
final now = DateTime.utc(2026, 10, 24);
SharedFinanceAccountChoice choice({
  String id = bankId,
  bool archived = false,
}) => SharedFinanceAccountChoice(
  scopeId: parentId,
  id: id,
  name: id == bankId ? 'Cached bank' : 'Other bank',
  currency: 'EUR',
  archived: archived,
);
SharedFinanceEntry entry({String? taskId}) => SharedFinanceEntry(
  id: '10000000-0000-4000-8000-000000000005',
  accountId: bankId,
  accountScopeId: parentId,
  kind: FinanceEntryKind.expense,
  amountMinor: 1234,
  currency: 'EUR',
  title: 'Existing entry',
  notes: 'Original note',
  taskId: taskId,
  occurredAt: now,
  createdAt: now,
  updatedAt: now,
);
CollaborationState snapshot({
  List<SharedFinanceAccountChoice> choices = const [],
  SharedFinanceEntry? existing,
}) => CollaborationState(
  session: sharingSession(),
  financeSupported: true,
  organizationFinanceSupported: true,
  financeContractVersion: 3,
  scopes: [
    const SharedScope(
      id: parentId,
      name: 'Parent',
      kind: SharedScopeKind.household,
      role: SharedRole.owner,
    ),
    project,
  ],
  selectedSpaceId: projectId,
  financePolicies: {projectId: policy},
  financeSnapshotComplete: {projectId: true},
  financeAccountChoices: {projectId: choices},
  data: {
    projectId: SharedScopeData(
      financeEntries: [if (existing != null) existing],
    ),
  },
);

class _Controller extends SharingUiController {
  _Controller(CollaborationState initial) : super(initial: initial);
  final refresh = Completer<void>();
  Completer<void>? policyWait;
  int refreshCalls = 0, policyCalls = 0;
  SharedFinanceEntry? updated;
  String? createdAccount, createdAccountScope;
  @override
  Future<void> refreshFinanceEntryAccountChoices(String scopeId) async {
    refreshCalls++;
    await refresh.future;
  }

  @override
  Future<SharedContentPolicy> sharedContentPolicy({String? scopeId}) async {
    policyCalls++;
    await policyWait?.future;
    return super.sharedContentPolicy(scopeId: scopeId);
  }

  @override
  Future<void> updateFinanceEntry(
    String scopeId,
    SharedFinanceEntry draft,
  ) async {
    updated = draft;
  }

  @override
  Future<String> createFinanceEntry({
    required String scopeId,
    required String accountId,
    String? accountScopeId,
    String? projectId,
    required FinanceEntryKind kind,
    SharedFinanceStatus status = SharedFinanceStatus.posted,
    required int amountMinor,
    required String currency,
    required String title,
    String notes = '',
    String category = '',
    String? payerAccountId,
    String? recipientAccountId,
    required DateTime occurredAt,
  }) async {
    createdAccount = accountId;
    createdAccountScope = accountScopeId;
    return 'created';
  }
}

class _SelectorRegressionTransport extends FakeTransport {
  _SelectorRegressionTransport() : super(FakeServer());
  final entered = Completer<void>();
  final response = Completer<Map<String, dynamic>>();
  final operations = <String>[];
  final requestedScopes = <Object?>[];
  final policyReplies = <SharedFinancePolicy>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    requestedScopes.add(params['scopeId']);
    if (operation == 'finance4.accountChoices') {
      entered.complete();
      return response.future;
    }
    if (operation == 'finance4.policy') {
      return (policyReplies.isEmpty ? policy : policyReplies.removeAt(0))
          .toJson();
    }
    throw StateError('Unexpected selector regression operation $operation');
  }
}

class _RepositorySelectorController extends _Controller {
  _RepositorySelectorController(this.repository) : super(repository.state);
  final CollaborationRepository repository;
  final finished = Completer<void>();
  @override
  Future<void> refreshFinanceEntryAccountChoices(String scopeId) async {
    refreshCalls++;
    try {
      await repository.refreshFinanceAccountChoices(
        scopeId,
        refreshPolicy: false,
      );
    } finally {
      finished.complete();
    }
  }
}

Future<
  ({
    CollaborationDatabase database,
    CollaborationRepository repository,
    SharedFinanceEntry original,
  })
>
_targetPolicyFixture(
  WidgetTester tester,
  _SelectorRegressionTransport transport,
) async {
  late CollaborationDatabase database;
  late CollaborationRepository repository;

  final sessions = MemorySessionStore();
  final profile = AccountSession.fromJson({
    ...sharingSession().toJson(),
    'serverUrl': 'https://sharing.example.test/',
  });
  sessions.value = DeviceSession(profile, 'synthetic-selector-session');
  final original = entry().copyWith(revision: 1);
  await tester.runAsync(() async {
    database = CollaborationDatabase(NativeDatabase.memory());
    await database.execute(
      'INSERT INTO accounts(partition,profile) VALUES(?,?)',
      [profile.partition, jsonEncode(profile.toJson())],
    );
    await database.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
      'capabilities:${profile.partition}',
      jsonEncode(<String, dynamic>{
        'recordContractVersions': [1],
        'financeContractVersions': [1, 2, 3],
        'organizationFinanceContractVersions': [1],
        'features': <String, dynamic>{
          'recordSync': true,
          'finance': true,
          'organizationFinance': true,
        },
      }),
    ]);
    await database.execute(
      'INSERT INTO scopes(partition,id,data,finance_policy,finance_complete,finance_cursor) VALUES(?,?,?,?,1,7)',
      [
        profile.partition,
        projectId,
        jsonEncode(project.toJson()),
        jsonEncode(policy.toJson()),
      ],
    );
    await database.execute(
      'INSERT INTO finance_records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,?,1,1,?,0)',
      [
        profile.partition,
        projectId,
        original.id,
        'financeEntry',
        jsonEncode(original.toJson()),
      ],
    );
    repository = CollaborationRepository(
      database,
      transport,
      sessions,
      ownsDatabase: false,
      contentRouteGuard: const SyntheticContentRouteGuard(),
    );
    await database.execute(
      'INSERT INTO scopes(partition,id,data,finance_policy,finance_complete,finance_cursor) VALUES(?,?,?,?,1,11)',
      [
        profile.partition,
        parentId,
        jsonEncode(snapshot().scopes.first.toJson()),
        jsonEncode(policy.toJson()),
      ],
    );
    final parentAccount = SharedFinanceAccount(
      id: bankId,
      name: 'Parent account',
      currency: 'EUR',
      createdAt: now,
      updatedAt: now,
    );
    await database.execute(
      'INSERT INTO finance_records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,?,1,1,?,0)',
      [
        profile.partition,
        parentId,
        bankId,
        'financeAccount',
        jsonEncode(parentAccount.toJson()),
      ],
    );
    await repository.initialize();
  });
  return (database: database, repository: repository, original: original);
}

Future<void> _pumpEntry(
  WidgetTester tester,
  _Controller controller, {
  SharedFinanceEntry? existing,
  bool doubleOpen = false,
}) async {
  tester.view.physicalSize = const Size(800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final overrides = await sharingUiInfrastructureOverrides(tester, controller);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overrides,
        collaborationProvider.overrideWith(() => controller),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final current = ref.watch(collaborationProvider).valueOrNull;
              return TextButton(
                key: const ValueKey('open-finance'),
                onPressed: current == null
                    ? null
                    : () {
                        final actions = SharedFinanceActions(
                          context,
                          ref,
                          project,
                          current,
                        );
                        unawaited(actions.entry(existing));
                        if (doubleOpen) unawaited(actions.entry(existing));
                      },
                child: const Text('Open finance'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-finance')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder field(String id) => find.byKey(ValueKey('sharing-$id'));
String text(WidgetTester tester, String id) =>
    tester.widget<TextFormField>(field(id)).controller!.text;
bool saveEnabled(WidgetTester tester) => tester
    .widget<EditorSaveButton>(find.byKey(const ValueKey('sharing-submit')))
    .enabled;
Future<void> refreshFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> closeEntry(WidgetTester tester) async {
  await tester.tap(find.text('Cancel').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'finance local-first cold entry renders while refresh awaits and preserves typed draft without selecting a late account',
    (tester) async {
      final controller = _Controller(snapshot());
      await _pumpEntry(tester, controller, doubleOpen: true);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(controller.refreshCalls, 1);
      expect(controller.refresh.isCompleted, isFalse);
      expect(field('title'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(field('title'), 'Typed locally');
      await tester.enterText(field('notes'), 'Keep my notes');
      await tester.enterText(field('amount'), '3.50');
      controller.replace(snapshot(choices: [choice()]));
      controller.refresh.complete();
      await refreshFrames(tester);
      expect(text(tester, 'title'), 'Typed locally');
      expect(text(tester, 'notes'), 'Keep my notes');
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(field('account'))
            .initialValue,
        isNull,
      );
      expect(saveEnabled(tester), isFalse);
      await tester.ensureVisible(field('account'));
      await tester.tap(field('account'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Cached bank · EUR · Parent space account').last,
      );
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(controller.createdAccount, bankId);
      expect(controller.createdAccountScope, parentId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finance local-first warm unavailable original account can save offline notes unchanged',
    (tester) async {
      final original = entry();
      final controller = _Controller(snapshot(existing: original));
      await _pumpEntry(tester, controller, existing: original);
      expect(saveEnabled(tester), isTrue);
      expect(controller.refresh.isCompleted, isFalse);
      await tester.enterText(field('notes'), 'Edited offline');
      controller.refresh.completeError(const CollaborationException('network'));
      await tester.pumpAndSettle();
      expect(text(tester, 'notes'), 'Edited offline');
      expect(saveEnabled(tester), isTrue);
      expect(
        find.byKey(const ValueKey('finance-entry-accounts-unavailable')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(controller.updated?.accountId, original.accountId);
      expect(controller.updated?.accountScopeId, original.accountScopeId);
      expect(controller.updated?.notes, 'Edited offline');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finance local-first disappearing new destination retains dropdown value and notes but blocks save',
    (tester) async {
      final controller = _Controller(snapshot(choices: [choice()]));
      await _pumpEntry(tester, controller);
      await tester.enterText(field('notes'), 'Keep on removal');
      controller.replace(snapshot(choices: [choice(id: otherId)]));
      await refreshFrames(tester);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(field('account'))
            .initialValue,
        '$parentId:$bankId',
      );
      expect(text(tester, 'notes'), 'Keep on removal');
      expect(saveEnabled(tester), isFalse);
      expect(controller.createdAccount, isNull);
      expect(tester.takeException(), isNull);
      controller.refresh.complete();
      await refreshFrames(tester);
      await closeEntry(tester);
    },
  );

  testWidgets(
    'finance local-first late refresh after closing cannot update disposed editor',
    (tester) async {
      final controller = _Controller(snapshot(choices: [choice()]));
      await _pumpEntry(tester, controller);
      await closeEntry(tester);
      controller.replace(snapshot(choices: [choice(id: otherId)]));
      controller.refresh.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.updated, isNull);
      expect(controller.createdAccount, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finance local-first identity change closes pending editor and ignores old refresh',
    (tester) async {
      final controller = _Controller(snapshot(choices: [choice()]));
      await _pumpEntry(tester, controller);
      controller.switchAccount();
      await refreshFrames(tester);
      await tester.pump(const Duration(milliseconds: 300));
      controller.refresh.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.updated, isNull);
      expect(controller.createdAccount, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finance local-first source-linked occurrence opens without unused account preparation',
    (tester) async {
      final original = entry(taskId: '10000000-0000-4000-8000-000000000006');
      final controller = _Controller(snapshot(existing: original));
      await _pumpEntry(tester, controller, existing: original);
      expect(field('recorded-title'), findsOneWidget);
      expect(controller.refreshCalls, 0);
      expect(
        find.byKey(const ValueKey('finance-entry-accounts-loading')),
        findsNothing,
      );
      await closeEntry(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finance local-first rechecks removed destination after awaited policy without losing draft',
    (tester) async {
      final controller = _Controller(snapshot(choices: [choice()]))
        ..policyWait = Completer<void>();
      await _pumpEntry(tester, controller);
      await tester.enterText(field('title'), 'Policy waiting');
      await tester.enterText(field('amount'), '1.25');
      await tester.enterText(field('notes'), 'Keep while policy awaits');
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pump();
      expect(controller.policyCalls, 1);
      controller.replace(snapshot());
      await refreshFrames(tester);
      controller.policyWait!.complete();
      controller.refresh.complete();
      await tester.pumpAndSettle();
      expect(controller.createdAccount, isNull);
      expect(text(tester, 'notes'), 'Keep while policy awaits');
      expect(saveEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
      await closeEntry(tester);
    },
  );

  test(
    'finance local-first account updates notify only changed options/status and exact archived original remains valid',
    () {
      final original = entry();
      final accounts = FinanceEntryAccounts(
        scopeId: projectId,
        original: original,
        unavailableLabel: 'Unavailable',
        initial: snapshot(choices: [choice(archived: true)]),
      );
      var notifications = 0;
      accounts.addListener(() => notifications++);
      accounts.update(snapshot(choices: [choice(archived: true)]));
      expect(notifications, 0);
      accounts.loading = true;
      accounts.finishRefresh(
        snapshot(choices: [choice(archived: true)]),
        failed: false,
      );
      expect(notifications, 1);
      expect(accounts.option('$parentId:$bankId'), isNotNull);
      accounts.update(
        snapshot(
          choices: [
            choice(archived: true),
            choice(id: otherId, archived: true),
          ],
        ),
      );
      expect(notifications, 1);
      expect(accounts.option('$parentId:$otherId'), isNull);
      accounts.update(snapshot());
      expect(notifications, 2);
      expect(accounts.option('$parentId:$bankId')?.id, bankId);
      expect(accounts.option(bankId), isNull);
      accounts.dispose();
    },
  );
  testWidgets(
    'finance selector-only regression defers newer access revision without resetting policy projection or typed draft',
    (tester) async {
      late CollaborationDatabase database;
      late CollaborationRepository repository;
      final transport = _SelectorRegressionTransport();
      final sessions = MemorySessionStore();
      final profile = AccountSession.fromJson({
        ...sharingSession().toJson(),
        'serverUrl': 'https://sharing.example.test/',
      });
      sessions.value = DeviceSession(profile, 'synthetic-selector-session');
      final original = entry().copyWith(revision: 1);
      await tester.runAsync(() async {
        database = CollaborationDatabase(NativeDatabase.memory());
        await database.execute(
          'INSERT INTO accounts(partition,profile) VALUES(?,?)',
          [profile.partition, jsonEncode(profile.toJson())],
        );
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?)',
          [
            'capabilities:${profile.partition}',
            jsonEncode(<String, dynamic>{
              'recordContractVersions': [1],
              'financeContractVersions': [1, 2, 3],
              'organizationFinanceContractVersions': [1],
              'features': <String, dynamic>{
                'recordSync': true,
                'finance': true,
                'organizationFinance': true,
              },
            }),
          ],
        );
        await database.execute(
          'INSERT INTO scopes(partition,id,data,finance_policy,finance_complete,finance_cursor) VALUES(?,?,?,?,1,7)',
          [
            profile.partition,
            projectId,
            jsonEncode(project.toJson()),
            jsonEncode(policy.toJson()),
          ],
        );
        await database.execute(
          'INSERT INTO finance_records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,?,1,1,?,0)',
          [
            profile.partition,
            projectId,
            original.id,
            'financeEntry',
            jsonEncode(original.toJson()),
          ],
        );
        repository = CollaborationRepository(
          database,
          transport,
          sessions,
          ownsDatabase: false,
          contentRouteGuard: const SyntheticContentRouteGuard(),
        );
        await repository.initialize();
      });
      final controller = _RepositorySelectorController(repository);
      final subscription = repository.changes.listen(controller.replace);
      addTearDown(() async {
        await subscription.cancel();
        await repository.close();
        await database.close();
      });
      expect(repository.state.financePolicyForScope(projectId).revision, 1);
      expect(repository.state.financeSnapshotComplete[projectId], isTrue);
      await _pumpEntry(tester, controller, existing: original);
      await tester.runAsync(
        () => transport.entered.future.timeout(const Duration(seconds: 2)),
      );
      await tester.enterText(field('notes'), 'Typed during selector wait');
      await tester.runAsync(() async {
        transport.response.complete(<String, dynamic>{
          'accounts': [choice().toJson()],
          'accountScopeId': parentId,
          'accountSequence': 8,
          'accessRevision': 2,
        });
        await controller.finished.future.timeout(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      expect(transport.operations, [
        'finance4.policy',
        'finance4.accountChoices',
      ]);
      expect(text(tester, 'notes'), 'Typed during selector wait');
      expect(
        find.byKey(const ValueKey('finance-entry-accounts-unavailable')),
        findsOneWidget,
      );
      expect(repository.state.financeSnapshotComplete[projectId], isTrue);
      expect(repository.state.financePolicyForScope(projectId).revision, 1);
      await tester.runAsync(() async {
        final stored = (await database.rows(
          'SELECT finance_policy,finance_complete,finance_cursor FROM scopes WHERE partition=? AND id=?',
          [profile.partition, projectId],
        )).single;
        expect(
          (jsonDecode(stored['finance_policy'] as String) as Map)['revision'],
          1,
        );
        expect(stored['finance_complete'], 1);
        expect(stored['finance_cursor'], 7);
        expect(
          await database.rows(
            'SELECT id FROM finance_records WHERE partition=? AND scope_id=?',
            [profile.partition, projectId],
          ),
          hasLength(1),
        );
        expect(
          await database.rows('SELECT value FROM local_meta WHERE name=?', [
            'finance_account_choices:${profile.partition}:$projectId',
          ]),
          isEmpty,
        );
      });
      expect(controller.updated, isNull);
      expect(tester.takeException(), isNull);
      await closeEntry(tester);
    },
  );
  testWidgets(
    'finance target policy verified read loss hides target cache and closes without selector preparation',
    (tester) async {
      final transport = _SelectorRegressionTransport()
        ..policyReplies.add(
          const SharedFinancePolicy(
            enabled: true,
            grant: SharedFinanceGrant.none,
            revision: 2,
          ),
        );
      final fixture = await _targetPolicyFixture(tester, transport);
      final controller = _RepositorySelectorController(fixture.repository);
      final sub = fixture.repository.changes.listen(controller.replace);
      addTearDown(() async {
        await sub.cancel();
        await fixture.repository.close();
        await fixture.database.close();
      });
      await _pumpEntry(tester, controller, existing: fixture.original);
      await tester.runAsync(
        () => controller.finished.future.timeout(const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();
      expect(transport.operations, ['finance4.policy']);
      expect(transport.requestedScopes, [projectId]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        fixture.repository.state.financePolicyForScope(projectId).canRead,
        isFalse,
      );
      await tester.runAsync(() async {
        expect(
          await fixture.database.rows(
            'SELECT id FROM finance_records WHERE scope_id=?',
            [projectId],
          ),
          isEmpty,
        );
        expect(
          await fixture.database.rows(
            'SELECT id FROM finance_records WHERE scope_id=?',
            [parentId],
          ),
          hasLength(1),
        );
      });
      expect(controller.updated, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finance target policy recheck after unscoped selector refusal applies only verified target write downgrade',
    (tester) async {
      final transport = _SelectorRegressionTransport()
        ..policyReplies.addAll([
          policy,
          const SharedFinancePolicy(
            enabled: true,
            grant: SharedFinanceGrant.read,
            revision: 2,
          ),
        ]);
      final fixture = await _targetPolicyFixture(tester, transport);
      final controller = _RepositorySelectorController(fixture.repository);
      final sub = fixture.repository.changes.listen(controller.replace);
      addTearDown(() async {
        await sub.cancel();
        await fixture.repository.close();
        await fixture.database.close();
      });
      await _pumpEntry(tester, controller, existing: fixture.original);
      await tester.runAsync(
        () => transport.entered.future.timeout(const Duration(seconds: 2)),
      );
      await tester.enterText(field('notes'), 'Before verified downgrade');
      await tester.runAsync(() async {
        transport.response.completeError(
          const CryptoAuthorityPending('scope_read_forbidden'),
        );
        await controller.finished.future.timeout(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      expect(transport.operations, [
        'finance4.policy',
        'finance4.accountChoices',
        'finance4.policy',
      ]);
      expect(transport.requestedScopes, [projectId, projectId, projectId]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        fixture.repository.state.financePolicyForScope(projectId).canRead,
        isTrue,
      );
      expect(
        fixture.repository.state.financePolicyForScope(projectId).canWrite,
        isFalse,
      );
      expect(
        fixture.repository.state.financePolicyForScope(parentId).canWrite,
        isTrue,
      );
      await tester.runAsync(() async {
        final rows = await fixture.database.rows(
          'SELECT id,finance_blocked FROM scopes ORDER BY id',
        );
        expect(
          rows.firstWhere((r) => r['id'] == projectId)['finance_blocked'],
          1,
        );
        expect(
          rows.firstWhere((r) => r['id'] == parentId)['finance_blocked'],
          0,
        );
      });
      expect(controller.updated, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
