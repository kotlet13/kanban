import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/linked_payments_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:kanban/organizer/domain/linked_payment_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'local_space_publication_test.dart' show PublicationTransport;
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;

class PaymentTransport extends PublicationTransport {
  PaymentTransport() : super(FakeServer());
  bool losePaymentReply = false, wrongReply = false;
  Future<void> Function()? beforePaymentReply;
  int paymentCalls = 0;
  final blockedRequests = <String>{};
  final paymentEvents = <String, Map<String, dynamic>>{},
      paymentReplays = <String, Map<String, dynamic>>{},
      paymentRequests = <String, String>{},
      targetProjections = <String, List<Map<String, dynamic>>>{};
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'capabilities') {
      final caps = await super.call(serverUrl: serverUrl, operation: operation);
      caps['features'] = <String, dynamic>{
        ...caps['features'] as Map,
        'linkedPayments': true,
      };
      return caps;
    }
    if (operation == 'finance3.payments') {
      return {
        'events': [
          for (final event in paymentEvents.values)
            if (event['sourceScopeId'] == params['scopeId']) event,
        ],
        'projections': targetProjections[params['scopeId']] ?? [],
        'cashMovements': [],
        'accessRevision': 1,
        'scopeSequence': finances.sequence[params['scopeId']] ?? 0,
      };
    }
    if (operation.startsWith('finance3.payment')) {
      paymentCalls++;
      if (offline) throw const CollaborationException('network');
      final request = params['requestId'] as String;
      if (blockedRequests.contains(request)) {
        throw const CollaborationException('payment_changed');
      }
      if (paymentReplays.containsKey(request)) {
        expect(jsonEncode(params), paymentRequests[request]);
        return jsonDecode(jsonEncode(paymentReplays[request]))
            as Map<String, dynamic>;
      }
      final eventId = params['eventId'] as String;
      Map<String, dynamic> event;
      if (operation == 'finance3.paymentCommit') {
        final entry = finances.records[params['scopeId']]![params['entryId']]!;
        final payload = entry['payload'] as Map;
        event = {
          'eventId': eventId,
          'sourceScopeId': params['scopeId'],
          'sourceEntryId': params['entryId'],
          'sourceRevision': (entry['revision'] as int) + 1,
          'payerAccountId': server.accountIds[server.tokens[token]],
          'amountMinor': payload['amountMinor'],
          'currency': payload['currency'],
          'paidAt': params['paidAt'],
          'expectReimbursement': params['expectReimbursement'],
          'revision': 1,
          'reimbursements': [],
        };
      } else if (operation == 'finance3.paymentProject') {
        event = {...paymentEvents[eventId]!};
      } else {
        event = {...paymentEvents[eventId]!};
        event['revision'] = (event['revision'] as int) + 1;
        event['reimbursements'] = [
          ...event['reimbursements'] as List,
          {
            'legId': params['legId'],
            'amountMinor': params['amountMinor'],
            'paidAt': params['paidAt'],
            'approvedByAccountId': server.accountIds[server.tokens[token]],
            'organizationAccountId': params['organizationAccountId'],
            'organizationAccountScopeId': params['organizationAccountScopeId'],
          },
        ];
      }
      paymentEvents[eventId] = event;
      if (params['householdScopeId'] != null) {
        targetProjections[params['householdScopeId'] as String] = [
          PaymentProjection(
                event: PaymentEvent.fromJson(event),
                state: PaymentProjectionState.complete,
              ).toJson()
              as Map<String, dynamic>,
        ];
      }
      final reply = {'event': event};
      paymentReplays[request] =
          jsonDecode(jsonEncode(reply)) as Map<String, dynamic>;
      paymentRequests[request] = jsonEncode(params);
      if (losePaymentReply) {
        losePaymentReply = false;
        throw const CollaborationException('network');
      }
      await beforePaymentReply?.call();
      if (wrongReply) {
        return {
          'event': {...event, 'sourceEntryId': newSharedId()},
        };
      }
      return jsonDecode(jsonEncode(reply)) as Map<String, dynamic>;
    }
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Future<
    (
      CollaborationDatabase,
      LocalSpacesRepository,
      LocalSpace,
      LocalSpace,
      String,
      String,
      String,
    )
  >
  fixture([File? file]) async {
    final db = CollaborationDatabase(
          file == null ? NativeDatabase.memory() : NativeDatabase(file),
        ),
        storage = SqliteOrganizerStorage(db);
    await storage.initialize();
    final spaces = LocalSpacesRepository(db),
        org = await spaces.createSpace(
          kind: LocalSpaceKind.organization,
          name: 'Organization',
        ),
        home = await spaces.createSpace(
          kind: LocalSpaceKind.household,
          name: 'Household',
        );
    final now = DateTime.now().toUtc(),
        privateAccount = newSharedId(),
        orgAccount = newSharedId();
    final personal = OrganizerRepository(
      SqliteOrganizerStorage(db, workspaceId: 'local'),
    );
    await personal.initialize();
    await personal.saveFinancePlan(
      accounts: [
        LocalFinanceAccount(
          id: privateAccount,
          name: 'Private account',
          currency: 'EUR',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      rules: [],
      expectedRevision: personal.snapshot.revision,
      expectedWorkspaceKey: 'local',
    );
    await personal.close();
    final source = OrganizerRepository(
      SqliteOrganizerStorage(db, workspaceId: org.id),
    );
    await source.initialize();
    await source.saveFinancePlan(
      accounts: [
        LocalFinanceAccount(
          id: orgAccount,
          name: 'Organization account',
          currency: 'EUR',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      rules: [],
      expectedRevision: source.snapshot.revision,
      expectedWorkspaceKey: org.id,
    );
    await source.createFinanceEntry(
      title: 'One canonical expense',
      amountMinor: 3000,
      kind: FinanceEntryKind.expense,
      occurredAt: now,
      ledgerAccountId: orgAccount,
    );
    final entry = source.snapshot.financeEntries.single.id;
    await source.close();
    return (db, spaces, org, home, privateAccount, orgAccount, entry);
  }

  Future<(CollaborationRepository, PaymentTransport, LinkedPaymentsRepository)>
  connected(CollaborationDatabase db) async {
    final transport = PaymentTransport(),
        shared = CollaborationRepository(
          db,
          transport,
          MemorySessionStore(),
          ownsDatabase: false,
        );
    await shared.initialize();
    await shared.login(
      serverUrl: 'https://example.test',
      username: 'alice',
      password: 'secret',
    );
    addTearDown(shared.close);
    return (
      shared,
      transport,
      LinkedPaymentsRepository(db, collaboration: shared),
    );
  }

  test(
    'immutable old commit receipt cannot downgrade a newer cached refund',
    () async {
      final (db, spaces, org, home, privateAccount, orgAccount, entry) =
          await fixture();
      addTearDown(db.close);
      final (shared, transport, payments) = await connected(db);
      await shared.publishLocalSpaces(
        await shared.previewLocalSpacesPublication([org.id]),
      );
      final remote = PaymentSpaceRef(
            org.id,
            partition: shared.state.session!.partition,
          ),
          now = DateTime.now().toUtc();
      transport.losePaymentReply = true;
      await expectLater(
        payments.recordPersonalPayment(
          PaymentSourceRef(
            space: remote,
            entryId: entry,
            expectedRevision: shared.state
                .dataForScope(org.id)
                .financeEntries
                .single
                .revision,
          ),
          personal: const PaymentSpaceRef('local'),
          personalAccountId: privateAccount,
          paidAt: now,
          expectReimbursement: true,
        ),
        throwsA(isA<CollaborationException>()),
      );
      final id = transport.paymentEvents.keys.single;
      final newer = {
        ...transport.paymentEvents[id]!,
        'revision': 2,
        'reimbursements': [
          PaymentReimbursement(
            legId: newSharedId(),
            amountMinor: 1000,
            paidAt: now,
            approvedByAccountId: shared.state.session!.accountId,
            organizationAccountId: orgAccount,
            organizationAccountScopeId: org.id,
          ).toJson(),
        ],
      };
      transport.paymentEvents[id] = newer;
      await payments.refresh(remote);
      final canonical = PaymentEvent.fromJson({
        ...newer,
        'sourcePartition': remote.partition,
      });
      await db.execute(
        'INSERT INTO linked_payment_projections(space_key,event_id,data) VALUES(?,?,?)',
        [
          'local:local',
          id,
          jsonEncode(
            PaymentProjection(
              event: canonical,
              state: PaymentProjectionState.complete,
              privateAccountId: privateAccount,
            ).toJson(),
          ),
        ],
      );
      await payments.resumePending();
      expect((await payments.read(remote)).events.single.revision, 2);
      expect(
        (await payments.read(
          const PaymentSpaceRef('local'),
        )).receivableByCurrency['EUR'],
        BigInt.from(2000),
      );
    },
  );

  test(
    'wrong-source payment receipt is rejected before any sidecar write',
    () async {
      final (db, spaces, org, home, privateAccount, orgAccount, entry) =
          await fixture();
      addTearDown(db.close);
      final (shared, transport, payments) = await connected(db);
      await shared.publishLocalSpaces(
        await shared.previewLocalSpacesPublication([org.id]),
      );
      final remote = PaymentSpaceRef(
        org.id,
        partition: shared.state.session!.partition,
      );
      transport.wrongReply = true;
      await expectLater(
        payments.recordPersonalPayment(
          PaymentSourceRef(
            space: remote,
            entryId: entry,
            expectedRevision: shared.state
                .dataForScope(org.id)
                .financeEntries
                .single
                .revision,
          ),
          personal: const PaymentSpaceRef('local'),
          personalAccountId: privateAccount,
          paidAt: DateTime.now().toUtc(),
          expectReimbursement: true,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
      expect(await db.rows('SELECT * FROM linked_payment_events'), isEmpty);
      expect(
        await db.rows('SELECT * FROM linked_payment_projections'),
        isEmpty,
      );
      expect(
        (await db.rows(
          'SELECT state FROM linked_payment_intents',
        )).single['state'],
        'pending',
      );
      transport.wrongReply = false;
      await shared.syncNow();
      expect(shared.state.lastError, isNull);
      expect((await payments.read(remote)).events.length, 1);
    },
  );

  test(
    'confirmed finance denial during payment reply cannot reactivate projections',
    () async {
      final (db, spaces, org, home, privateAccount, orgAccount, entry) =
          await fixture();
      addTearDown(db.close);
      final (shared, transport, payments) = await connected(db);
      await shared.publishLocalSpaces(
        await shared.previewLocalSpacesPublication([org.id]),
      );
      final remote = PaymentSpaceRef(
        org.id,
        partition: shared.state.session!.partition,
      );
      transport.beforePaymentReply = () async {
        await db.execute(
          'UPDATE scopes SET finance_blocked=1 WHERE partition=? AND id=?',
          [remote.partition, remote.id],
        );
      };
      await expectLater(
        payments.recordPersonalPayment(
          PaymentSourceRef(
            space: remote,
            entryId: entry,
            expectedRevision: shared.state
                .dataForScope(org.id)
                .financeEntries
                .single
                .revision,
          ),
          personal: const PaymentSpaceRef('local'),
          personalAccountId: privateAccount,
          paidAt: DateTime.now().toUtc(),
          expectReimbursement: true,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'finance_access_changed',
          ),
        ),
      );
      expect(await db.rows('SELECT * FROM linked_payment_events'), isEmpty);
      expect(
        await db.rows('SELECT * FROM linked_payment_projections'),
        isEmpty,
      );
      expect(
        (await db.rows(
          'SELECT state FROM linked_payment_intents',
        )).single['state'],
        'pending',
      );
    },
  );

  test(
    'paid task cost allows safe task timeline edits without moving actual cash dates',
    () async {
      final (db, spaces, org, home, privateAccount, orgAccount, entry) =
          await fixture();
      addTearDown(db.close);
      final repo = OrganizerRepository(
        SqliteOrganizerStorage(db, workspaceId: org.id),
      );
      await repo.initialize();
      addTearDown(repo.close);
      final now = DateTime.now().toUtc();
      final task = LocalTask(
        id: newSharedId(),
        title: 'Task cost',
        notes: '',
        projectId: null,
        dueAt: now,
        isCompleted: false,
        createdAt: now,
        updatedAt: now,
      );
      await repo.saveTaskWithCost(
        task: task,
        isNew: true,
        cost: TaskCostDraft(
          amountMinor: 3000,
          currency: 'EUR',
          ledgerAccountId: orgAccount,
        ),
        expectedWorkspaceKey: org.id,
      );
      final cost = repo.snapshot.financeEntries.firstWhere(
            (e) => e.taskId == task.id,
          ),
          payments = LinkedPaymentsRepository(db);
      await payments.recordPersonalPayment(
        PaymentSourceRef(
          space: PaymentSpaceRef(org.id),
          entryId: cost.id,
          expectedRevision: cost.revision,
        ),
        personal: const PaymentSpaceRef('local'),
        personalAccountId: privateAccount,
        paidAt: now,
        expectReimbursement: true,
      );
      await repo.reload();
      await repo.updateTask(
        repo.snapshot.tasks.single.copyWith(
          dueAt: now.add(const Duration(days: 7)),
          title: 'Revised task',
        ),
      );
      await repo.saveTaskWithCost(
        task: repo.snapshot.tasks.single.copyWith(
          dueAt: now.add(const Duration(days: 9)),
        ),
        expectedWorkspaceKey: org.id,
      );
      final paid = repo.snapshot.financeEntries.firstWhere(
        (e) => e.id == cost.id,
      );
      expect(paid.paidAt, now);
      expect(paid.occurredAt, now);
      expect(paid.plannedAt, now.add(const Duration(days: 9)));
      await expectLater(
        repo.updateFinanceEntry(paid.copyWith(amountMinor: 4000)),
        throwsA(isA<OrganizerConflictException>()),
      );
    },
  );

  test(
    'later household publication attaches an existing payment with a replayable projection request',
    () async {
      final (db, spaces, org, home, privateAccount, orgAccount, entry) =
          await fixture();
      addTearDown(db.close);
      final (shared, transport, payments) = await connected(db);
      final now = DateTime.now().toUtc();
      final event = await payments.recordPersonalPayment(
        PaymentSourceRef(
          space: PaymentSpaceRef(org.id),
          entryId: entry,
          expectedRevision: 0,
        ),
        personal: const PaymentSpaceRef('local'),
        personalAccountId: privateAccount,
        household: PaymentSpaceRef(home.id),
        paidAt: now,
        expectReimbursement: true,
      );
      await shared.publishLocalSpaces(
        await shared.previewLocalSpacesPublication([org.id]),
      );
      expect(transport.targetProjections[home.id], isNull);
      transport.losePaymentReply = true;
      await expectLater(
        shared.publishLocalSpaces(
          await shared.previewLocalSpacesPublication([home.id]),
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'network',
          ),
        ),
      );
      await Future.wait([payments.resumePending(), payments.resumePending()]);
      expect(transport.paymentCalls, 3);
      final target = PaymentSpaceRef(
        home.id,
        partition: shared.state.session!.partition,
      );
      expect((await payments.read(target)).projections.single.eventId, event);
      expect(transport.paymentRequests.length, 2);
      await payments.resumePending();
      expect(transport.paymentRequests.length, 2);
    },
  );

  test(
    'a rejected immutable intent does not starve an independent pending payment',
    () async {
      final (db, spaces, org, home, privateAccount, orgAccount, entry) =
          await fixture();
      addTearDown(db.close);
      final repo = OrganizerRepository(
        SqliteOrganizerStorage(db, workspaceId: org.id),
      );
      await repo.initialize();
      await repo.createFinanceEntry(
        title: 'Independent expense',
        amountMinor: 1000,
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.now().toUtc(),
        ledgerAccountId: orgAccount,
      );
      final second = repo.snapshot.financeEntries
          .firstWhere((e) => e.id != entry)
          .id;
      await repo.close();
      final (shared, transport, payments) = await connected(db);
      await shared.publishLocalSpaces(
        await shared.previewLocalSpacesPublication([org.id]),
      );
      final source = PaymentSpaceRef(
        org.id,
        partition: shared.state.session!.partition,
      );
      Future<String> pay(String id) => payments.recordPersonalPayment(
        PaymentSourceRef(
          space: source,
          entryId: id,
          expectedRevision: shared.state
              .dataForScope(org.id)
              .financeEntries
              .firstWhere((e) => e.id == id)
              .revision,
        ),
        personal: const PaymentSpaceRef('local'),
        personalAccountId: privateAccount,
        paidAt: DateTime.now().toUtc(),
        expectReimbursement: true,
      );
      transport.wrongReply = true;
      await expectLater(pay(entry), throwsA(isA<CollaborationException>()));
      transport.wrongReply = false;
      final first = (await db.rows(
        'SELECT id,data FROM linked_payment_intents',
      )).single;
      transport.blockedRequests.add(first['id'] as String);
      transport.losePaymentReply = true;
      await expectLater(pay(second), throwsA(isA<CollaborationException>()));
      await expectLater(
        payments.resumePending(),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'payment_changed',
          ),
        ),
      );
      expect(
        (await db.rows(
          "SELECT id FROM linked_payment_intents WHERE state='pending'",
        )).single['id'],
        first['id'],
      );
      expect(
        (await db.rows('SELECT data FROM linked_payment_intents WHERE id=?', [
          first['id'],
        ])).single['data'],
        first['data'],
      );
      expect((await payments.read(source)).events.single.sourceEntryId, second);
      expect(
        (await db.rows('SELECT value FROM local_meta WHERE name=?', [
          'linked_payment_error:${first['id']}',
        ])).single['value'],
        'payment_changed',
      );
      final before = transport.paymentCalls;
      await shared.signOut();
      await shared.login(
        serverUrl: 'https://example.test',
        username: 'bob',
        password: 'secret',
      );
      await payments.resumePending();
      expect(transport.paymentCalls, before);
      expect(
        (await payments.read(const PaymentSpaceRef('local'))).pendingCount,
        0,
      );

      expect(
        (await db.rows('SELECT data FROM linked_payment_intents WHERE id=?', [
          first['id'],
        ])).single['data'],
        first['data'],
      );
      await shared.signOut();
      await shared.login(
        serverUrl: 'https://example.test',
        username: 'alice',
        password: 'secret',
      );
      final afterSameAccountLogin = transport.paymentCalls;
      transport.blockedRequests.clear();
      await payments.resumePending();
      expect(
        (await db.rows('SELECT state FROM linked_payment_intents WHERE id=?', [
          first['id'],
        ])).single['state'],
        'complete',
      );
      expect(transport.paymentCalls, afterSameAccountLogin + 1);
      expect(
        (await db.rows('SELECT data FROM linked_payment_intents WHERE id=?', [
          first['id'],
        ])).single['data'],
        first['data'],
      );
    },
  );

  test(
    'explicit publication preserves local event and leg IDs through lost receipt then remote reimbursement',
    () async {
      final (db, spaces, org, home, privateAccount, orgAccount, entry) =
          await fixture();
      addTearDown(db.close);
      final transport = PaymentTransport(),
          shared = CollaborationRepository(
            db,
            transport,
            MemorySessionStore(),
            ownsDatabase: false,
          );
      await shared.initialize();
      await shared.login(
        serverUrl: 'https://example.test',
        username: 'alice',
        password: 'secret',
      );
      addTearDown(shared.close);
      final payments = LinkedPaymentsRepository(db, collaboration: shared),
          now = DateTime.now().toUtc();
      final event = await payments.recordPersonalPayment(
        PaymentSourceRef(
          space: PaymentSpaceRef(org.id),
          entryId: entry,
          expectedRevision: 0,
        ),
        personal: const PaymentSpaceRef('local'),
        personalAccountId: privateAccount,
        household: PaymentSpaceRef(home.id),
        paidAt: now,
        expectReimbursement: true,
      );
      await payments.reimburse(
        PaymentSpaceRef(org.id),
        event,
        expectedRevision: 1,
        amountMinor: 1000,
        paidAt: now,
        organizationAccountId: orgAccount,
      );
      final leg = (await payments.read(
        PaymentSpaceRef(org.id),
      )).events.single.reimbursements.single.legId;
      final preview = await shared.previewLocalSpacesPublication([
        org.id,
        home.id,
      ]);
      expect(
        preview.spaces
            .firstWhere((s) => s.space.id == home.id)
            .linkedPaymentCount,
        1,
      );
      transport.losePaymentReply = true;
      await expectLater(
        shared.publishLocalSpaces(preview),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'network',
          ),
        ),
      );
      final pending = (await db.rows(
        "SELECT id,data FROM linked_payment_intents WHERE state='pending'",
      )).single;
      await payments.resumePending();
      expect(transport.paymentEvents.keys.single, event);
      expect(
        (transport.paymentEvents[event]!['reimbursements'] as List)
            .single['legId'],
        leg,
      );
      expect(
        await db.rows(
          "SELECT id FROM linked_payment_intents WHERE state='pending'",
        ),
        isEmpty,
      );
      final remote = PaymentSpaceRef(
        org.id,
        partition: shared.state.session!.partition,
      );
      await payments.reimburse(
        remote,
        event,
        expectedRevision: 2,
        amountMinor: 2000,
        paidAt: now.add(const Duration(days: 1)),
        organizationAccountId: orgAccount,
      );
      expect(
        (await payments.read(
          const PaymentSpaceRef('local'),
        )).cashBurdenByCurrency['EUR'],
        BigInt.zero,
      );
      expect((await payments.read(remote)).events.single.revision, 3);
      expect(
        transport.paymentRequests.values.every(
          (body) => !body.contains(privateAccount),
        ),
        true,
      );
      expect(
        (jsonDecode(pending['data'] as String) as Map)['params']['eventId'],
        event,
      );
    },
  );
  test(
    'local 30 paid and 10 then 20 reimbursement preserve one expense and cash movements across restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'jivie-payments-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/local.sqlite');
      var (db, spaces, org, home, privateAccount, orgAccount, entry) =
          await fixture(file);
      var payments = LinkedPaymentsRepository(db);
      final source = PaymentSpaceRef(org.id);
      final now = DateTime.now().toUtc();
      final event = await payments.recordPersonalPayment(
        PaymentSourceRef(space: source, entryId: entry, expectedRevision: 0),
        personal: const PaymentSpaceRef('local'),
        personalAccountId: privateAccount,
        household: PaymentSpaceRef(home.id),
        paidAt: now,
        expectReimbursement: true,
      );
      expect(
        (await SqliteOrganizerStorage(
          db,
          workspaceId: org.id,
        ).read()).financeEntries.single.paidAt,
        now,
      );
      expect(
        (await payments.read(
          const PaymentSpaceRef('local'),
        )).cashBurdenByCurrency['EUR'],
        BigInt.from(3000),
      );
      await payments.reimburse(
        source,
        event,
        expectedRevision: 1,
        amountMinor: 1000,
        paidAt: now,
        organizationAccountId: orgAccount,
      );
      final personal = await payments.read(const PaymentSpaceRef('local')),
          household = await payments.read(PaymentSpaceRef(home.id));
      expect(personal.complete, true);
      expect(personal.cashBurdenByCurrency['EUR'], BigInt.from(2000));
      expect(personal.receivableByCurrency['EUR'], BigInt.from(2000));
      expect(
        personal.cashMovements.fold<int>(0, (sum, m) => sum + m.amountMinor),
        -2000,
      );
      expect(household.projections.single.privateAccountId, isNull);
      expect(household.cashMovements, isEmpty);
      expect(
        (await payments.read(source)).cashMovements.single.amountMinor,
        -1000,
      );
      expect(
        (await SqliteOrganizerStorage(
          db,
          workspaceId: 'local',
        ).read()).financeEntries,
        isEmpty,
      );
      final edit = OrganizerRepository(
        SqliteOrganizerStorage(db, workspaceId: org.id),
      );
      await edit.initialize();
      await expectLater(
        edit.deleteFinanceEntry(entry),
        throwsA(isA<OrganizerConflictException>()),
      );
      await edit.close();
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      await SqliteOrganizerStorage(db).initialize();
      payments = LinkedPaymentsRepository(db);
      addTearDown(db.close);
      expect((await payments.read(source)).events.single.eventId, event);
      await payments.reimburse(
        source,
        event,
        expectedRevision: 2,
        amountMinor: 2000,
        paidAt: now.add(const Duration(days: 1)),
        organizationAccountId: orgAccount,
      );
      expect(
        (await payments.read(
          const PaymentSpaceRef('local'),
        )).cashBurdenByCurrency['EUR'],
        BigInt.zero,
      );
      expect(
        (await SqliteOrganizerStorage(
          db,
          workspaceId: org.id,
        ).read()).financeEntries.single.amountMinor,
        3000,
      );
      await expectLater(
        payments.reimburse(
          source,
          event,
          expectedRevision: 3,
          amountMinor: 1,
          paidAt: now,
          organizationAccountId: orgAccount,
        ),
        throwsA(anything),
      );
    },
  );
  test(
    'encrypted local payment roundtrip preserves exact event legs cash and keeps source guarded',
    () async {
      final (db, spaces, org, home, privateAccount, orgAccount, entry) =
          await fixture();
      addTearDown(db.close);
      final payments = LinkedPaymentsRepository(db),
          now = DateTime.now().toUtc(),
          source = PaymentSpaceRef(org.id);
      final event = await payments.recordPersonalPayment(
        PaymentSourceRef(space: source, entryId: entry, expectedRevision: 0),
        personal: const PaymentSpaceRef('local'),
        personalAccountId: privateAccount,
        household: PaymentSpaceRef(home.id),
        paidAt: now,
        expectReimbursement: true,
      );
      await payments.reimburse(
        source,
        event,
        expectedRevision: 1,
        amountMinor: 1000,
        paidAt: now,
        organizationAccountId: orgAccount,
      );
      final backup = PortableBackupRepository(
        db,
        SqliteOrganizerStorage(db),
        MemoryBackupUiPreferencesStore(),
      );
      const password = 'linked payment backup password';
      final bytes = await backup.exportEncryptedBackup(password);
      final target = CollaborationDatabase(NativeDatabase.memory()),
          storage = SqliteOrganizerStorage(target);
      await storage.initialize();
      addTearDown(target.close);
      final restore = PortableBackupRepository(
        target,
        storage,
        MemoryBackupUiPreferencesStore(),
      );
      await restore.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await storage.read()).revision,
      );
      expect(
        (await LinkedPaymentsRepository(
          target,
        ).read(source)).events.single.toJson(),
        (await payments.read(source)).events.single.toJson(),
      );
      expect(
        (await LinkedPaymentsRepository(
          target,
        ).read(const PaymentSpaceRef('local'))).cashBurdenByCurrency['EUR'],
        BigInt.from(2000),
      );
      expect(
        await target.rows('SELECT * FROM linked_payment_cash'),
        await db.rows('SELECT * FROM linked_payment_cash'),
      );
      final cash = (await db.rows(
        'SELECT space_key,movement_id,data FROM linked_payment_cash',
      )).single;
      final corrupt = {
        ...jsonDecode(cash['data'] as String) as Map<String, dynamic>,
        'accountId': newSharedId(),
      };
      await db.execute(
        'UPDATE linked_payment_cash SET data=? WHERE space_key=? AND movement_id=?',
        [jsonEncode(corrupt), cash['space_key'], cash['movement_id']],
      );
      final malformed = await backup.exportEncryptedBackup(password);
      await db.execute(
        'UPDATE linked_payment_cash SET data=? WHERE space_key=? AND movement_id=?',
        [cash['data'], cash['space_key'], cash['movement_id']],
      );
      await expectLater(
        restore.restoreEncryptedBackup(
          malformed,
          password,
          mode: BackupRestoreMode.replace,
          expectedPersonalRevision: (await storage.read()).revision,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_conflict',
          ),
        ),
      );
      expect(
        (await LinkedPaymentsRepository(
          target,
        ).read(source)).events.single.revision,
        2,
      );
      expect(
        (await target.rows(
          'SELECT data FROM linked_payment_cash',
        )).single['data'],
        cash['data'],
      );
      await LinkedPaymentsRepository(target).reimburse(
        source,
        event,
        expectedRevision: 2,
        amountMinor: 2000,
        paidAt: now,
        organizationAccountId: orgAccount,
      );
      await expectLater(
        restore.restoreEncryptedBackup(
          bytes,
          password,
          mode: BackupRestoreMode.merge,
          expectedPersonalRevision: (await storage.read()).revision,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_conflict',
          ),
        ),
      );
      expect(
        (await LinkedPaymentsRepository(
          target,
        ).read(source)).events.single.revision,
        3,
      );
      await restore.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await storage.read()).revision,
      );
      expect(
        (await LinkedPaymentsRepository(
          target,
        ).read(source)).events.single.revision,
        2,
      );
      expect(
        (await target.rows('SELECT * FROM linked_payment_cash')).length,
        1,
      );
    },
  );
}
