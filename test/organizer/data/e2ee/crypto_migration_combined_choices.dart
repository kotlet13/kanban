// Support for the existing public Capture3 representative, not another suite.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/crypto_archive_cold_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_structure_workflow.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

/// Two independent FILEs and journals. The parent READ issuer is deliberately
/// not a child member; the target manager has NONE on the parent ledger.
class CombinedCaptureChoices {
  CombinedCaptureChoices._(
    this.fixture,
    this.ownerDb,
    this.owner,
    this.ownerFile,
    this.coordinator,
  );
  final Map<String, dynamic> fixture;
  final CollaborationDatabase ownerDb;
  final AccountCryptoV2Workflow owner;
  final Uint8List ownerFile;
  final CryptoMigrationCoordinator coordinator;
  final reviewedPurposes = <String>{};
  String? _ownerInventoryHash;

  static Future<CombinedCaptureChoices> create({
    required Map<String, dynamic> fixture,
    required Directory coldParent,
    required DeviceSession Function(Map) session,
    required AccountCryptoV2Workflow Function(
      CollaborationDatabase,
      DeviceSession,
    )
    workflow,
    required AccountCryptoV2Workflow reader,
  }) async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    final owner = workflow(
      db,
      session((fixture['parentOwner'] as Map)['session'] as Map),
    );
    final file = await owner.prepareRecoveryFile();
    try {
      await owner.verifyAndInitialize(file);
      final a = SessionCryptoAccess(account: owner),
          b = SessionCryptoAccess(account: reader),
          aDirectory = await owner.directory.requireFresh(),
          bDirectory = await reader.directory.requireFresh(),
          scope = fixture['scopeId'] as String;
      await a.verifyContactCard(
        scope,
        bDirectory.accountId,
        await b.identities.publicCard(bDirectory),
      );
      await b.verifyContactCard(
        scope,
        aDirectory.accountId,
        await a.identities.publicCard(aDirectory),
      );
      return CombinedCaptureChoices._(
        fixture,
        db,
        owner,
        file,
        CryptoMigrationCoordinator(
          account: owner,
          coldDatabase: () =>
              CryptoArchiveColdDatabase.create(parent: coldParent),
        ),
      );
    } catch (_) {
      file.fillRange(0, file.length, 0);
      await db.close();
      rethrow;
    }
  }

  Future<bool> _review(CryptoMigrationStructureReview review) async {
    expect({
      fixture['scopeId'],
      fixture['childScopeId'],
    }, contains(review.scopeId));
    expect({
      'scopeContext',
      'parentAccess',
      'financeAccountChoices',
    }, contains(review.purpose));
    if (review.purpose == 'financeAccountChoices') {
      // The callback is reached only after the production offer verifier. It
      // must present sanitized choices, never the issuer's original ledger.
      expect(jsonEncode(review.facts), isNot(contains('openingBalanceMinor')));
      expect(review.facts['recipient'], isA<Map>());
    }
    reviewedPurposes.add(review.purpose);
    return true; // Explicit synthetic human review; production UI asks the user.
  }

  Future<void> prepareOwner(String migration) async {
    final prepared = await coordinator.prepare(fixture['scopeId']);
    expect(prepared.migrationId, migration);
    final review = await coordinator.review(migration);
    expect(
      review.rowCount,
      greaterThan(8 + (fixture['extraRecords'] as int? ?? 0)),
    );
    _ownerInventoryHash = review.inventoryHash;
  }

  Future<void> fenceOwner(String migration) async {
    await coordinator.fence(
      migration,
      reviewedInventoryHash: _ownerInventoryHash!,
    );
  }

  /// Alternate the two ordinary public coordinators, retaining their original
  /// requests. Only the finite, known peer-wait states may advance the driver.
  Future<CryptoMigrationState> finish({
    required String migration,
    required CryptoMigrationCoordinator readerCoordinator,
    required AccountCryptoV2Workflow reader,
    required Uint8List readerFile,
  }) async {
    final manager = ScopeCryptoManager(SessionCryptoAccess(account: reader));
    String? financeDraft;
    var contributed = false, granted = false, ownerInitialized = false;
    final waits = <String>[];
    var dependencyDenialsChecked = false;
    for (var round = 0; round < 12; round++) {
      for (final ownerTurn in [true, false]) {
        if (!ownerTurn && !ownerInitialized) continue;
        if (!ownerTurn && !dependencyDenialsChecked) {
          await _denyForeignWitnessWidening(reader);
          dependencyDenialsChecked = true;
        }
        try {
          final state = await (ownerTurn ? coordinator : readerCoordinator)
              .archiveAndVerify(
                migration,
                recoveryFile: ownerTurn ? ownerFile : readerFile,
                reviewStructure: _review,
              );
          if (state.phase == CryptoMigrationPhase.committed) {
            expect(reviewedPurposes, contains('scopeContext'));
            expect(reviewedPurposes, contains('financeAccountChoices'));
            final ownAccess = SessionCryptoAccess(account: owner);
            expect(
              (await ownAccess.currentHead(
                fixture['scopeId'],
                online: true,
              )).member(owner.directory.accountId)['financeRole'],
              'none',
            );
            expect(
              (await ownAccess.currentHead(
                fixture['childScopeId'],
                online: true,
              )).members.where(
                (member) => member['accountId'] == reader.directory.accountId,
              ),
              isEmpty,
            );
            expect(
              await reader.store.database.rows(
                'SELECT 1 FROM crypto_scope_keys WHERE partition=? AND scope_id=?',
                [reader.store.partition, fixture['childScopeId']],
              ),
              isEmpty,
            );
            return await readerCoordinator.inspect(fixture['scopeId']);
          }
          if (ownerTurn) ownerInitialized = true;
          expect(state.phase, CryptoMigrationPhase.waitingContributors);
          waits.add(state.errorCode ?? 'waitingContributors');
        } on CryptoAuthorityPending catch (error) {
          if (ownerTurn &&
              error.reason == 'finance_key_contribution_required') {
            financeDraft ??=
                (await manager.financeDrafts(
                      fixture['scopeId'],
                    )).single['draftId']
                    as String;
            if (!contributed) {
              await manager.contributeFinanceDraft(
                fixture['scopeId'],
                financeDraft,
              );
              contributed = true;
            } else if (!granted) {
              await manager.publishFinanceGrants(
                fixture['scopeId'],
                financeDraft,
              );
              granted = true;
            } else {
              rethrow;
            }
          } else if (!const {
            'crypto_migration_managers_pending',
            'crypto_migration_contributors_pending',
            'crypto_migration_contributions_pending',
            'crypto_migration_dependencies_pending',
            'crypto_structure_context_contributors_pending',
            'crypto_account_choices_capture_review_pending',
            'crypto_account_choices_capture_companion_pending',
            'crypto_account_choices_manager_review_required',
            'crypto_account_choices_request_pending',
            'crypto_account_choices_recipient_pending',
          }.contains(error.reason)) {
            rethrow;
          }
          if (ownerTurn &&
              error.reason != 'finance_key_contribution_required') {
            ownerInitialized = true;
          }
          waits.add(error.reason);
        }
      }
    }
    fail('Combined public coordinator did not progress: $waits');
  }

  Future<void> _denyForeignWitnessWidening(
    AccountCryptoV2Workflow reader,
  ) async {
    final rows = await ownerDb.rows(
      "SELECT record_proof,source_binding FROM crypto_migration_staged_records WHERE scope_id=? AND domain='content'",
      [fixture['scopeId']],
    );
    final task = rows.singleWhere((row) {
      final proof = jsonDecode(row['record_proof'] as String) as Map,
          body = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      return body['type'] == 'task' &&
          body['metadata']['identity']['canonicalId'] == fixture['taskId'];
    });
    final binding = jsonDecode(task['source_binding'] as String) as Map,
        witness = binding['witness'] as Map,
        context = witness['context'] as Map,
        base = <String, dynamic>{
          'captureVersion': 3,
          for (final key in [
            'migrationId',
            'captureId',
            'sourceInventoryRoot',
            'bindingId',
            'scopeId',
            'domain',
            'epoch',
            'membershipHeadHash',
            'accessRevision',
          ])
            key: context[key],
          'purpose': 'typedWitness',
          'id': witness['segments'][0]['id'],
          'offset': 0,
        };
    for (final changed in [
      {...base, 'domain': 'finance'},
      {...base, 'sourceInventoryRoot': '0' * 64},
    ]) {
      await expectLater(
        reader.directory.call('crypto2.migration.blob.get', changed),
        throwsA(
          isA<CollaborationApiException>().having(
            (error) => error.code,
            'exact dependency boundary',
            anyOf(
              'crypto_migration_dependency_forbidden',
              'crypto_migration_dependency_binding',
            ),
          ),
        ),
      );
    }
  }

  /// Existing explicit recovery protection: the manager never receives finance keys.
  Future<void> protectRecoveredParent({
    required AccountCryptoV2Workflow recoveredReader,
    Future<void> Function(Map<String, Object?> references)? checkpoint,
  }) async {
    final scope = fixture['scopeId'] as String,
        managerAccess = SessionCryptoAccess(account: owner),
        contributorAccess = SessionCryptoAccess(account: recoveredReader),
        manager = ScopeCryptoManager(managerAccess),
        contributor = ScopeCryptoManager(contributorAccess);
    final source = await managerAccess.recoveryCandidateHead(scope);
    expect(source.member(owner.directory.accountId)['manageKeys'], true);
    expect(source.member(owner.directory.accountId)['financeRole'], 'none');
    expect(
      source.member(recoveredReader.directory.accountId)['financeRole'],
      'read',
    );
    final blocked = await recoveredReader.store.database.rows(
      "SELECT request_id,signed_body,request_hash,state,response FROM crypto_outbox WHERE partition=? AND operation='crypto2.domain.checkpoint' AND state='blocked' AND json_extract(signed_body,'\$.commandBase64') IS NOT NULL ORDER BY request_id",
      [recoveredReader.store.partition],
    );
    final review = await manager.reviewRotation(scope);
    Future<void> save(String phase, {String? financeReviewId}) async =>
        checkpoint?.call({
          'phase': phase,
          'parentProtectionReviewId': review.id,
          'parentProtectionSourceHeadHash': review.sourceHeadHash,
          if (financeReviewId != null) 'parentFinanceReviewId': financeReviewId,
        });
    Future<dynamic> confirm() =>
        manager.confirmRotation(review, acceptedCandidateHistory: true);
    final missingFinance = isA<CryptoAuthorityPending>().having(
      (error) => error.reason,
      'reason',
      'finance_key_contribution_required',
    );
    await save('parentProtectionReviewReady');
    await expectLater(confirm(), throwsA(missingFinance));
    await save('parentProtectionDraftReady');
    final financeReview = await contributor.reviewRotation(
      scope,
      financeOnly: true,
    );
    await save(
      'parentProtectionFinanceReviewReady',
      financeReviewId: financeReview.id,
    );
    await contributor.contributeFinanceDraft(
      scope,
      review.id,
      reviewedInventory: financeReview,
    );
    await save('parentProtectionContributionReady');
    await expectLater(confirm(), throwsA(missingFinance));
    await save('parentProtectionGrantsReady');
    await contributor.publishFinanceGrants(scope, review.id);
    await save('parentProtectionFinanceGrantsReady');
    final active = await confirm();
    expect(active.epoch, source.epoch + 1);
    expect(active.accessRevision, source.accessRevision);
    expect(active.member(owner.directory.accountId)['financeRole'], 'none');
    expect(
      active.member(recoveredReader.directory.accountId)['financeRole'],
      'read',
    );
    await save('parentProtectionActivated');
    await contributorAccess.hydrateScopeKeys(scope);
    expect(
      await recoveredReader.store.database.rows(
        "SELECT request_id,signed_body,request_hash,state,response FROM crypto_outbox WHERE partition=? AND operation='crypto2.domain.checkpoint' AND request_id IN (${List.filled(blocked.length, '?').join(',')}) ORDER BY request_id",
        [
          recoveredReader.store.partition,
          ...blocked.map((row) => row['request_id']),
        ],
      ),
      blocked,
    );
  }

  Future<void> finalRemoval({
    required AccountCryptoV2Workflow recoveredReader,
    required CryptoBusinessRouter readerRouter,
    required void Function(String operation) loseAcceptedReply,
    Future<void> Function(Map<String, Object?> references)?
    checkpointBeforeDelete,
  }) async {
    final scope = fixture['scopeId'] as String,
        child = fixture['childScopeId'] as String,
        reader = recoveredReader,
        ownerAccess = SessionCryptoAccess(account: owner),
        readerAccess = SessionCryptoAccess(account: reader),
        ownerRouter = CryptoBusinessRouter(
          database: ownerDb,
          accountFor: (_) async => owner,
        );
    Future<Map<String, dynamic>> call(
      CryptoBusinessRouter router,
      AccountCryptoV2Workflow account,
      String operation,
      String target, [
      Map<String, Object?> params = const {},
    ]) => router.dispatch(
      session: account.directory.session,
      operation: operation,
      params: {'scopeId': target, ...params},
      protectedScopeIds: {target},
    );
    final choice = await call(
      ownerRouter,
      owner,
      'finance4.accountChoices',
      child,
    );
    expect(choice['accountScopeId'], scope);
    expect((choice['accounts'] as List).single, {
      'id': fixture['ledgerId'],
      'scopeId': scope,
      'name': 'PRIVATE_CAPTURED_LEDGER',
      'currency': 'EUR',
      'archived': false,
    });
    expect(jsonEncode(choice), isNot(contains('openingBalanceMinor')));
    expect(
      (await call(readerRouter, reader, 'finance4.pull', scope, {
        'cursor': 0,
      }))['organizationFinanceComplete'],
      false,
    );

    // Existing explicit invitation/admission and finance grant make the child
    // readable for the final complete-checkpoint/last-link assertion. Until this
    // point the issuer had neither child membership nor its finance key.
    final sender = InviteCryptoRepository(ownerAccess),
        receiver = InviteCryptoRepository(readerAccess),
        invitation = await sender.dispatch('invitations3.create', {
          'scopeId': child,
          'recipient': fixture['username'],
          'role': 'member',
          'language': 'en',
          'requestId': owner.directory.reducer.crypto.randomId(),
        }),
        id = invitation['invitation']['id'] as String,
        inspected = await receiver.inspect(token: invitation['localToken']);
    await receiver.compareCreator(
      inspected,
      await ownerAccess.identities.publicCard(
        await owner.directory.requireFresh(),
      ),
    );
    await receiver.accept(inspected, actionId: id);
    final recipient = await sender.acceptedRecipient(child, id);
    await sender.compareCreator(
      recipient,
      await readerAccess.identities.publicCard(
        await reader.directory.requireFresh(),
      ),
    );
    await sender.admit(
      recipient,
      await ScopeCryptoManager(ownerAccess).reviewRotation(child),
    );
    expect(await receiver.resumeAccepted(id), child);
    await call(ownerRouter, owner, 'finance4.grant', child, {
      'accountId': reader.directory.accountId,
      'grant': 'read',
      'requestId': owner.directory.reducer.crypto.randomId(),
    });
    await readerAccess.hydrateScopeKeys(child);
    await call(ownerRouter, owner, 'finance4.pull', child, {'cursor': 0});
    await protectRecoveredParent(
      recoveredReader: reader,
      checkpoint: checkpointBeforeDelete,
    );
    final before = await call(readerRouter, reader, 'finance4.pull', scope, {
      'cursor': 0,
    });
    expect(before['organizationFinanceComplete'], true);
    expect(before['organizationFinanceScopeIds'], [child]);
    final beforeSequence =
        (before['organizationFinanceSequences'] as Map)[child] as int;
    final original = (await ownerDb.rows(
      "SELECT raw_payload FROM crypto_business_records WHERE scope_id=? AND type='financeEntry' AND deleted=0",
      [child],
    )).single;
    final preserved = Map<String, dynamic>.from(
      jsonDecode(original['raw_payload'] as String) as Map,
    )..remove('accountChoiceWitness');
    expect(preserved, jsonDecode(fixture['childEntryPayload']));
    final operation = <String, Object?>{
      'opId': owner.directory.reducer.crypto.randomId(),
      'recordId': fixture['childEntryId'],
      'type': 'financeEntry',
      'expectedRevision': 5,
      'deleted': true,
      'payload': null,
    };
    await checkpointBeforeDelete?.call({
      'phase': 'beforeLastLinkDelete',
      'invitationId': id,
      'beforeSequence': beforeSequence,
      'operation': operation,
    });
    loseAcceptedReply('crypto2.records.batch');
    // The ordinary dispatcher retains and resolves the original signed request
    // after the synthetic accepted-reply loss; no replacement semantic intent.
    Map<String, dynamic>? firstAck;
    try {
      firstAck = await call(ownerRouter, owner, 'finance4.push', child, {
        'operation': operation,
      });
    } on CryptoAuthorityPending catch (error) {
      expect(error.reason, 'crypto_business_delivery_pending');
    }
    final originalRequest = await ownerDb.rows(
      'SELECT o.request_id,o.signed_body,o.request_hash FROM crypto_business_requests b JOIN crypto_outbox o ON o.partition=b.partition AND o.request_id=b.request_id WHERE b.partition=? AND b.operation_id=?',
      [owner.store.partition, operation['opId']],
    );
    expect(originalRequest, hasLength(1));
    final ack = await call(ownerRouter, owner, 'finance4.push', child, {
      'operation': operation,
    });
    if (firstAck != null) expect(ack, firstAck);
    expect(
      await ownerDb.rows(
        'SELECT o.request_id,o.signed_body,o.request_hash FROM crypto_business_requests b JOIN crypto_outbox o ON o.partition=b.partition AND o.request_id=b.request_id WHERE b.partition=? AND b.operation_id=?',
        [owner.store.partition, operation['opId']],
      ),
      originalRequest,
    );
    await call(ownerRouter, owner, 'finance4.pull', child, {'cursor': 0});
    final after = await call(readerRouter, reader, 'finance4.pull', scope, {
      'cursor': 0,
    });
    expect(after['organizationFinanceComplete'], true);
    expect(after['organizationFinanceScopeIds'], [child]);
    expect(
      (after['organizationFinanceSequences'] as Map)[child],
      greaterThan(beforeSequence),
    );
    final removed = (await ownerDb.rows(
      "SELECT deleted,legacy_revision,crypto_revision FROM crypto_business_records WHERE scope_id=? AND type='financeEntry'",
      [child],
    )).single;
    expect(removed['deleted'], 1);
    expect(removed['legacy_revision'], 5);
    expect(removed['crypto_revision'], 2);
  }

  Future<void> close() async {
    await coordinator.close();
    await ownerDb.close();
    ownerFile.fillRange(0, ownerFile.length, 0);
  }
}
