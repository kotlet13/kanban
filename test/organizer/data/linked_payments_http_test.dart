// Only explicitly opted-in synthetic loopback data. No credentials/body logging.
import 'dart:convert';
import 'dart:io';
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
import 'collaboration_repository_test.dart' show MemorySessionStore;
import 'family_upgrade_http_test.dart' show ControlledHttp;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['KANBAN_PLANNING_HTTP_FIXTURE'];
  test(
    'real HTTP deferred local publication preserves payment and refunds through lost receipt and second client',
    () async {
      final fixture =
              jsonDecode(await File(path!).readAsString())
                  as Map<String, dynamic>,
          url = fixture['server'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback fixture required');
      }
      final owner = (fixture['owner'] ?? fixture) as Map<String, dynamic>;
      Future<(CollaborationDatabase, CollaborationRepository, ControlledHttp)>
      client([File? file, MemorySessionStore? sessions]) async {
        final db = CollaborationDatabase(
              file == null ? NativeDatabase.memory() : NativeDatabase(file),
            ),
            http = ControlledHttp(),
            repo = CollaborationRepository(
              db,
              http,
              sessions ?? MemorySessionStore(),
              ownsDatabase: false,
            );
        await SqliteOrganizerStorage(db).initialize();
        await repo.initialize();
        await repo.login(
          serverUrl: url,
          username: owner['username'] as String,
          password: owner['password'] as String,
          allowLocalHttp: true,
        );
        addTearDown(() async {
          await repo.close();
          await db.close();
        });
        return (db, repo, http);
      }

      final (db, shared, http) = await client();
      final spaces = LocalSpacesRepository(db),
          org = await spaces.createSpace(
            kind: LocalSpaceKind.organization,
            name: 'Synthetic publication organization',
          ),
          home = await spaces.createSpace(
            kind: LocalSpaceKind.household,
            name: 'Synthetic household projection',
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
            name: 'Synthetic private account',
            currency: 'EUR',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        rules: [],
        expectedRevision: personal.snapshot.revision,
        expectedWorkspaceKey: 'local',
      );
      await shared.enablePrivateSync(
        expectedRevision: (await shared.previewPrivateSync()).revision,
      );
      await shared.syncNow();
      expect(shared.state.lastError, isNull);
      await personal.close();
      final source = OrganizerRepository(
        SqliteOrganizerStorage(db, workspaceId: org.id),
      );
      await source.initialize();
      await source.createProject(title: 'Synthetic local project');
      final project = source.snapshot.projects.single;
      await source.saveFinancePlan(
        accounts: [
          LocalFinanceAccount(
            id: orgAccount,
            name: 'Synthetic organization account',
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
        title: 'One synthetic expense',
        amountMinor: 3000,
        kind: FinanceEntryKind.expense,
        occurredAt: now,
        projectId: project.id,
        ledgerAccountId: orgAccount,
      );
      final entry = source.snapshot.financeEntries.single;
      await source.close();
      final payments = LinkedPaymentsRepository(db, collaboration: shared);
      final eventId = await payments.recordPersonalPayment(
        PaymentSourceRef(
          space: PaymentSpaceRef(org.id),
          entryId: entry.id,
          expectedRevision: entry.revision,
        ),
        personal: const PaymentSpaceRef('local'),
        personalAccountId: privateAccount,
        household: PaymentSpaceRef(home.id),
        paidAt: now,
        expectReimbursement: true,
      );
      expect(
        (await db.rows(
          "SELECT state FROM linked_payment_intents",
        )).single['state'],
        'waiting_source_publication',
      );
      expect(
        (await payments.read(
          const PaymentSpaceRef('local'),
        )).cashBurdenByCurrency['EUR'],
        BigInt.from(3000),
      );
      await payments.reimburse(
        PaymentSpaceRef(org.id),
        eventId,
        expectedRevision: 1,
        amountMinor: 1000,
        paidAt: now,
        organizationAccountId: orgAccount,
      );
      final leg = (await payments.read(
        PaymentSpaceRef(org.id),
      )).events.single.reimbursements.single.legId;
      http.loseReply = 'finance3.paymentCommit';
      await expectLater(
        shared.publishLocalSpaces(
          await shared.previewLocalSpacesPublication([org.id, home.id]),
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'network',
          ),
        ),
      );
      await payments.resumePending();
      final intermediate = await payments.refresh(
        const PaymentSpaceRef('local'),
      );
      final paymentAccount = intermediate.projections
          .firstWhere((p) => p.eventId == eventId)
          .privateAccountId!;
      Iterable<PaymentCashMovement> ownCash(PaymentSnapshot s) =>
          s.cashMovements.where((m) => m.accountId == paymentAccount);
      expect(ownCash(intermediate).length, 2);
      expect(
        ownCash(intermediate).fold<int>(0, (sum, m) => sum + m.amountMinor),
        -2000,
      );
      final cachedIntermediate = await payments.read(
        const PaymentSpaceRef('local'),
      );
      expect(ownCash(cachedIntermediate).length, 2);
      expect(
        ownCash(
          cachedIntermediate,
        ).fold<int>(0, (sum, m) => sum + m.amountMinor),
        -2000,
      );

      final remote = PaymentSpaceRef(
        project.id,
        partition: shared.state.session!.partition,
      );
      final first = await payments.refresh(remote);
      expect(first.events.single.eventId, eventId);
      expect(first.events.single.reimbursements.single.legId, leg);
      await payments.reimburse(
        remote,
        eventId,
        expectedRevision: 2,
        amountMinor: 2000,
        paidAt: now.add(const Duration(days: 1)),
        organizationAccountId: orgAccount,
        organizationAccountScope: PaymentSpaceRef(
          org.id,
          partition: remote.partition,
        ),
      );
      await shared.syncNow();
      expect(shared.state.lastError, isNull);
      final directory = await Directory.systemTemp.createTemp(
        'jivie-http-payments-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final secondFile = File('${directory.path}/second.sqlite'),
          sessions = MemorySessionStore();
      final (secondDb, second, _) = await client(secondFile, sessions);
      await second.enablePrivateSync(
        expectedRevision: (await second.previewPrivateSync()).revision,
      );
      await second.syncNow();
      expect(second.state.lastError, isNull);
      final secondPayments = LinkedPaymentsRepository(
        secondDb,
        collaboration: second,
      );
      final sourceSnapshot = await secondPayments.refresh(
        PaymentSpaceRef(project.id, partition: second.state.session!.partition),
      );
      expect(sourceSnapshot.events.single.revision, 3);
      expect(sourceSnapshot.events.single.reimbursedMinor, 3000);
      final privateSnapshot = await secondPayments.refresh(
        const PaymentSpaceRef('local'),
      );
      expect(
        privateSnapshot.projections
            .firstWhere((p) => p.eventId == eventId)
            .cashBurdenMinor,
        0,
      );
      final cachedPrivate = await secondPayments.read(
        const PaymentSpaceRef('local'),
      );
      expect(ownCash(cachedPrivate).length, 3);
      expect(
        ownCash(cachedPrivate).fold<int>(0, (sum, m) => sum + m.amountMinor),
        0,
      );

      expect(
        ownCash(privateSnapshot).fold<int>(0, (sum, m) => sum + m.amountMinor),
        0,
      );
      final householdSnapshot = await secondPayments.refresh(
        PaymentSpaceRef(home.id, partition: second.state.session!.partition),
      );
      expect(householdSnapshot.projections.single.eventId, eventId);
      expect(householdSnapshot.projections.single.privateAccountId, isNull);
      final parent = await secondPayments.refresh(
        PaymentSpaceRef(org.id, partition: second.state.session!.partition),
      );
      expect(
        parent.cashMovements.fold<int>(0, (sum, m) => sum + m.amountMinor),
        -3000,
      );
      expect(
        second.state.dataForScope(project.id).financeEntries.single.amountMinor,
        3000,
      );
      const password = 'loopback complete encrypted backup';
      final backup = PortableBackupRepository(
        secondDb,
        SqliteOrganizerStorage(secondDb),
        MemoryBackupUiPreferencesStore(),
        collaboration: () => second,
      );
      final bytes = await backup.exportEncryptedBackup(password);
      expect(
        (await backup.inspectEncryptedBackup(
          bytes,
          password,
        )).hasRemoteRecovery,
        true,
      );
      await second.close();
      await secondDb.close();
      final reopenedDb = CollaborationDatabase(NativeDatabase(secondFile)),
          offline = ControlledHttp()..offline = true;
      final reopened = CollaborationRepository(
        reopenedDb,
        offline,
        sessions,
        ownsDatabase: false,
      );
      addTearDown(() async {
        await reopened.close();
        await reopenedDb.close();
      });
      await SqliteOrganizerStorage(reopenedDb).initialize();
      await reopened.initialize();
      final offlineCash = await LinkedPaymentsRepository(
        reopenedDb,
        collaboration: reopened,
      ).read(const PaymentSpaceRef('local'));
      expect(ownCash(offlineCash).length, 3);
      expect(
        ownCash(offlineCash).fold<int>(0, (sum, m) => sum + m.amountMinor),
        0,
      );
      expect(
        offlineCash.projections
            .firstWhere((p) => p.eventId == eventId)
            .event
            .reimbursedMinor,
        3000,
      );
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
