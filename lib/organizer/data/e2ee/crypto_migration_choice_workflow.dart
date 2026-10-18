import 'crypto_account_archive.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'crypto_archive_cold_database.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_v3.dart';
import 'crypto_finance_account_choices.dart';
import 'crypto_finance_choice_capture.dart';
import 'crypto_json.dart';
import 'crypto_migration_captured_choices.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_migration_structure_workflow.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// Finite reverse destination request followed by the existing offer, explicit
/// target-manager review, issuer certificate and recipient sealed handoff.
/// Neither participant opens the other participant's private FILE archive.
class CryptoMigrationChoiceWorkflow {
  CryptoMigrationChoiceWorkflow(this.runtime, {this.review, this.coldDatabase});
  final CryptoBusinessSession runtime;
  final CryptoMigrationStructureReviewer? review;
  final Future<CryptoArchiveColdDatabase> Function()? coldDatabase;
  bool _settling = false;
  static const variant = 'financeAccountChoicesRequest';

  Map<String, dynamic> _body(Map<String, dynamic> proof) =>
      Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );

  Future<void> run({
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required VerifiedCryptoCaptureArchive archive,
    required Uint8List recoveryFile,
  }) async {
    final targets = <String, Map<String, dynamic>>{};
    var after = '';
    while (true) {
      final rows = await runtime.db.rows(
        "SELECT binding_id,context,binding,typed_row FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? ORDER BY binding_id LIMIT 1",
        [runtime.partition, capture.captureId, after],
      );
      if (rows.isEmpty) break;
      final row = rows.single;
      after = row['binding_id'] as String;
      final c = Map<String, dynamic>.from(jsonDecode(row['context'] as String));
      if (c['sourceTable'] != 'familyhub_finance_records' ||
          c['domain'] != 'finance') {
        continue;
      }
      final source = await CryptoMigrationRecordSource.decode(
        table: c['sourceTable'],
        domain: 'finance',
        row: Map<String, dynamic>.from(jsonDecode(row['typed_row'] as String)),
        serverId: runtime.account.directory.session.profile.serverId,
        reservedId: runtime.reservedRecordId,
      );
      if (!CryptoMigrationCapturedChoices.needed(source)) continue;
      targets.putIfAbsent(
        source.scopeId,
        () => {
          'sourceScopeId': source.rawPayload!['accountScopeId'],
          'binding': jsonDecode(row['binding'] as String),
        },
      );
    }
    for (final entry in targets.entries) {
      final cap = await runtime.access.migrationCandidate(
        scopeId: entry.key,
        migrationId: capture.migrationId,
        captureId: capture.captureId,
      );
      final request = await CryptoCaptureCoordinator(runtime.account).queue
          .enqueueCommand(
            actionKey:
                'capture:${capture.captureId}:choiceRequest:${entry.key}',
            operation: 'crypto2.migration.structure.context',
            payload: {
              'migrationId': capture.migrationId,
              'captureId': capture.captureId,
              'sourceInventoryRoot': archive.sourceInventoryRoot,
              'variant': variant,
              'scopeId': entry.key,
              'membershipHeadHash': cap.head.headHash,
              ...entry.value,
            },
          );
      await runtime.queue.resumeUnresolved(requestIds: {request});
      await runtime.queue.commandResult(request);
    }
    final selected = <String>{
      ...capture.scopeIds,
      ...capture.receiptSelections
          .where((s) => const ['content', 'finance'].contains(s['domain']))
          .map((s) => s['scopeId']!),
    };
    final service = CryptoFinanceAccountChoices(runtime);
    for (final scope in selected.toList()..sort()) {
      final cap = await runtime.access.migrationCandidate(
        scopeId: scope,
        migrationId: capture.migrationId,
        captureId: capture.captureId,
      );
      if (!const ['read', 'write'].contains(
        cap.head.member(runtime.account.directory.accountId)['financeRole'],
      )) {
        continue;
      }
      if (!CryptoFinanceChoiceCapture.isSourceMaterializer(
        cap.head,
        runtime.account.directory.accountId,
      )) {
        continue;
      }
      String? cursor;
      while (true) {
        final page = await runtime.account.directory
            .call('crypto2.migration.structure.contexts', {
              'migrationId': capture.migrationId,
              'captureId': capture.captureId,
              'sourceInventoryRoot': archive.sourceInventoryRoot,
              'variant': variant,
              'scopeId': scope,
              'membershipHeadHash': cap.head.headHash,
              if (cursor != null) 'afterScopeId': cursor,
              'limit': 20,
            });
        final requests = (page['requests'] as List).cast<Map>();
        for (final request in requests) {
          final command = _body(Map<String, dynamic>.from(request)),
              p = command['payload'] as Map;
          final target = <String, dynamic>{
            'migrationId': p['migrationId'],
            'captureId': p['captureId'],
            'accountId': command['accountId'],
            'sourceInventoryRoot': p['sourceInventoryRoot'],
            'scopeId': p['scopeId'],
            'membershipHeadHash': p['membershipHeadHash'],
          };
          final action = await runtime.reservedRecordId(
            scope,
            'captureChoices:${await runtime.codec.digest(Map<String, dynamic>.from(request))}',
          );
          final saltName = 'migration_choice_salt:${runtime.partition}:$action';
          final saved = await runtime.db.rows(
            'SELECT value FROM local_meta WHERE name=?',
            [saltName],
          );
          final salt = saved.isEmpty
              ? base64Encode(runtime.codec.crypto.sodium.randombytes.buf(32))
              : saved.single['value'] as String;
          if (saved.isEmpty) {
            await runtime.db.execute(
              'INSERT INTO local_meta(name,value) VALUES(?,?)',
              [saltName, salt],
            );
          }
          final verified =
              await CryptoCaptureArchive(
                runtime.account,
                coldDatabase: coldDatabase,
              ).withVerifiedSourceFromFile(
                capture: capture,
                manifest: manifest,
                externalFile: recoveryFile,
                use: (cold, account, ownArchive) async {
                  final own = CryptoBusinessSession(
                    account,
                    SessionCryptoAccess(account: account),
                    cold.database,
                  );
                  final accounts = <CryptoMigrationColdSource>[];
                  var cursor = '';
                  var bytes = 0;
                  while (true) {
                    final rows = await own.db.rows(
                      "SELECT binding_id,typed_row FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND json_extract(context,'\$.scopeId')=? AND json_extract(context,'\$.domain')='finance' AND binding_id>? ORDER BY binding_id LIMIT 1",
                      [own.partition, capture.captureId, scope, cursor],
                    );
                    if (rows.isEmpty) break;
                    cursor = rows.single['binding_id'] as String;
                    final source = await CryptoMigrationColdSource.load(
                      own,
                      ownArchive,
                      cursor,
                    );
                    if (source.context.sourceTable !=
                        'familyhub_finance_records') {
                      continue;
                    }
                    final decoded = await CryptoMigrationRecordSource.decode(
                      table: source.context.sourceTable,
                      domain: 'finance',
                      row: source.typedRow,
                      serverId: source.context.serverId,
                      reservedId: own.reservedRecordId,
                    );
                    if (decoded.deleted || decoded.type != 'financeAccount') {
                      continue;
                    }
                    bytes += (rows.single['typed_row'] as String).length;
                    if (bytes > 16 * 1024 * 1024 || accounts.length >= 5000) {
                      throw const CryptoAuthorityPending(
                        'crypto_account_choices_capture_capacity',
                      );
                    }
                    accounts.add(source);
                  }
                  final raw =
                      await CryptoFinanceChoiceCapture.deriveSourceSelection(
                        serverId: account.directory.session.profile.serverId,
                        sourceAccountId: account.directory.accountId,
                        sourceArchive: ownArchive,
                        sourceParentAccountRows: accounts,
                        exactSourceHead: cap.head,
                        targetContext: target,
                        childBinding: CryptoCaptureBinding.fromJson(
                          Map<String, dynamic>.from(p['binding']),
                        ),
                        selectionSaltBase64: salt,
                        reservedId: own.reservedRecordId,
                      );
                  return CryptoFinanceChoiceCapture.verifySourceSelection(
                    raw,
                    serverId: account.directory.session.profile.serverId,
                    sourceAccountId: account.directory.accountId,
                    sourceArchive: ownArchive,
                    sourceParentAccountRows: accounts,
                    exactSourceHead: cap.head,
                    reservedId: own.reservedRecordId,
                  );
                },
              );
          final offered = await service.proposeCapturedSelection(
            verified,
            candidate: cap,
            actionId: action,
          );
          final proof = Map<String, dynamic>.from(
            offered['offerAuthorization'],
          );
          final reply = await runtime.account.directory
              .call('crypto2.exports.delegation.forOffer', {
                'variant': CryptoFinanceAccountChoices.variant,
                'scopeId': p['scopeId'],
                'offerHash': await runtime.codec.digest(proof),
              });
          if (reply['authorization'] != null) {
            final delegation = _body(
              Map<String, dynamic>.from(reply['authorization']),
            );
            final recipient = delegation['payload']['bridgeRecipient'];
            if (recipient['accountId'] != command['accountId'] ||
                recipient['deviceId'] != command['deviceId']) {
              throw const FormatException(
                'crypto_account_choices_request_recipient',
              );
            }
            await service.certify(
              p['scopeId'],
              selectionActionId: action,
              offerAuthorization: proof,
              delegationAuthorization: Map<String, dynamic>.from(
                reply['authorization'],
              ),
              actionId: await runtime.reservedRecordId(
                scope,
                'captureChoicesCert:$action',
              ),
              candidate: cap,
            );
          }
        }
        if (page['hasMore'] != true) break;
        final next = page['nextScopeId'];
        if (next is! String || cursor != null && next.compareTo(cursor) <= 0) {
          throw const FormatException('crypto_account_choices_cursor');
        }
        cursor = next;
      }
    }
    var approved = false;
    for (final scope in selected.toList()..sort()) {
      final cap = await runtime.access.migrationCandidate(
        scopeId: scope,
        migrationId: capture.migrationId,
        captureId: capture.captureId,
      );
      if (cap.head.member(runtime.account.directory.accountId)['manageKeys'] ==
          true) {
        String? cursor;
        while (true) {
          final page = await runtime.account.directory
              .call('crypto2.exports.offers', {
                'scopeId': scope,
                'variant': CryptoFinanceAccountChoices.variant,
                'stage': 'offers',
                'limit': 20,
                if (cursor != null) 'afterHash': cursor,
              });
          for (final item in page['items'] as List) {
            final proof = Map<String, dynamic>.from(item['authorization']),
                offer = _body(proof);
            if (offer['capture3Context']?['target']?['migrationId'] !=
                capture.migrationId) {
              continue;
            }
            final details = await service.reviewOffer(
              scope,
              proof,
              candidate: cap,
            );
            final requestPage = await runtime.account.directory
                .call('crypto2.migration.structure.contexts', {
                  'migrationId': capture.migrationId,
                  'captureId': capture.captureId,
                  'sourceInventoryRoot': archive.sourceInventoryRoot,
                  'variant': variant,
                  'scopeId': scope,
                  'membershipHeadHash': cap.head.headHash,
                  'targetRequest': true,
                });
            final matching = (requestPage['requests'] as List)
                .cast<Map>()
                .map((r) => _body(Map<String, dynamic>.from(r)))
                .where(
                  (r) =>
                      r['accountId'] ==
                          offer['capture3Context']['target']['accountId'] &&
                      r['payload']['captureId'] ==
                          offer['capture3Context']['target']['captureId'] &&
                      r['payload']['binding']['bindingId'] ==
                          offer['capture3Context']['childBinding']['bindingId'] &&
                      r['payload']['membershipHeadHash'] ==
                          offer['targetHeadHash'],
                )
                .toList();
            if (matching.length != 1) {
              throw const CryptoAuthorityPending(
                'crypto_account_choices_request_pending',
              );
            }
            final recipientAccount = matching.single['accountId'],
                recipientDevice = matching.single['deviceId'];
            final recipients = (details['writers'] as List)
                .cast<Map>()
                .where(
                  (w) =>
                      w['accountId'] == recipientAccount &&
                      w['deviceId'] == recipientDevice,
                )
                .toList();
            if (recipients.length != 1) {
              throw const CryptoAuthorityPending(
                'crypto_account_choices_recipient_pending',
              );
            }
            final action = await runtime.reservedRecordId(
              scope,
              'captureChoicesApprove:${item['hash']}',
            );
            final prior = await runtime.db.rows(
              'SELECT 1 FROM crypto_export_drafts WHERE partition=? AND action_id=?',
              [runtime.partition, action],
            );
            if (prior.isEmpty) {
              if (review == null ||
                  !await review!(
                    CryptoMigrationStructureReview(
                      scopeId: scope,
                      purpose: 'financeAccountChoices',
                      issuerFingerprint: '',
                      facts: {
                        ...details,
                        'members': <Object>[],
                        'recipient': recipients.single,
                      },
                      members: const [],
                    ),
                  )) {
                throw const CryptoAuthorityPending(
                  'crypto_account_choices_manager_review_required',
                );
              }
            }
            await service.approve(
              scope,
              proof,
              actionId: action,
              recipientAccountId: recipientAccount,
              recipientDeviceId: recipientDevice,
              candidate: cap,
            );
            approved = true;
          }
          if (page['hasMore'] != true) break;
          final next = page['nextAfterHash'];
          if (next is! String ||
              cursor != null && next.compareTo(cursor) <= 0) {
            throw const FormatException('crypto_account_choices_cursor');
          }
          cursor = next;
        }
      }
      if (targets.containsKey(scope)) {
        await service.materializeAvailable(scope, candidate: cap);
      }
    }
    if (approved && !_settling) {
      _settling = true;
      await run(
        capture: capture,
        manifest: manifest,
        archive: archive,
        recoveryFile: recoveryFile,
      );
    }
  }
}
