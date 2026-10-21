import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import '../collaboration_transport.dart' show CollaborationApiException;
import '../../domain/collaboration_models.dart' show SharedScope;
import 'crypto_business_json.dart';
import 'crypto_business_router.dart';
import 'crypto_finance_choice_selection_codec.dart';
import 'crypto_finance_choice_capture.dart';
import 'crypto_json.dart';
import 'crypto_finance_audit_evidence.dart';
import 'crypto_lifecycle_evidence.dart';
import 'crypto_record_address.dart';
import 'crypto_scoped_exports.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart' show CryptoMigrationCandidate;
import 'scope_crypto_codec.dart' show VerifiedScopeHead;

/// A sanitized, explicitly endorsed derivation. It does not transfer parent
/// ledger membership, parent keys, balances or transaction completeness.
class CryptoFinanceAccountChoices {
  CryptoFinanceAccountChoices(this.context);
  final CryptoBusinessSession context;
  static const type = 'financeAccountChoice';
  static const variant = CryptoFinanceChoiceSelectionCodec.variant;
  static const maxChoices = 5000;
  Map<String, dynamic> _map(Object? v) {
    if (v is! Map) throw const FormatException('crypto_account_choices_shape');
    return Map<String, dynamic>.from(v);
  }

  Map<String, dynamic> _body(Map proof) =>
      CryptoFinanceChoiceSelectionCodec.body(proof);
  Future<String> _hash(Object? v) => cryptoSha256(CryptoJson.encode(v));
  bool _same(Object? a, Object? b) =>
      CryptoBusinessJson.canonical(a) == CryptoBusinessJson.canonical(b);
  String get partition => context.partition;
  Future<void> _schema() async {
    await context.db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_export_drafts(partition TEXT NOT NULL,scope_id TEXT NOT NULL,action_id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(partition,scope_id,action_id))',
    );
    await context.db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_account_choice_selections(partition TEXT NOT NULL,action_id TEXT NOT NULL,scope_id TEXT NOT NULL,selection TEXT NOT NULL,PRIMARY KEY(partition,action_id))',
    );
  }

  Future<Map<String, dynamic>> _send(
    String action,
    String scope,
    String operation,
    Map<String, dynamic> intent,
    Future<Map<String, dynamic>> Function(String) build, {
    CryptoMigrationCandidate? candidate,
  }) async {
    await _schema();
    final identity = await CryptoBusinessJson.hash({
      'operation': operation,
      'intent': intent,
    });
    final rows = await context.db.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [partition, scope, action],
    );
    late Map<String, dynamic> saved;
    if (rows.isEmpty) {
      final request = context.codec.crypto.randomId();
      saved = {
        'intentHash': identity,
        'operation': operation,
        'requestId': request,
        'payload': await build(request),
        if (candidate != null)
          'candidateContext': {
            'scopeId': candidate.head.scopeId,
            'migrationId': candidate.migrationId,
            'captureId': candidate.captureId,
          },
      };
      await context.db.execute(
        'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)',
        [partition, scope, action, CryptoBusinessJson.canonical(saved)],
      );
    } else {
      saved = _map(jsonDecode(rows.single['payload'] as String));
      if (saved['intentHash'] != identity) {
        throw const FormatException('scoped_export_immutable_intent');
      }
    }
    final request = await context.queue.enqueueCommand(
      actionKey: 'scopedExport:$action',
      operation: operation,
      requestId: saved['requestId'],
      payload: _map(saved['payload']),
    );
    await context.queue.resumeUnresolved(requestIds: {request});
    final outgoing = await context.queue.store.outgoing(request);
    if (outgoing?['state'] == 'rejected') {
      final receipt = _map(jsonDecode(outgoing!['response'] as String));
      final failure = _map(receipt['response']);
      final details = failure['details'];
      throw CollaborationApiException(
        failure['errorCode'] as String,
        details: details is Map
            ? Map<String, dynamic>.from(details)
            : details is List && details.isEmpty
            ? const <String, dynamic>{}
            : throw const FormatException(
                'crypto_account_choices_receipt_details',
              ),
      );
    }
    final response = await context.queue.commandResult(request);
    final row = (await context.db.rows(
      'SELECT signed_body FROM crypto_outbox WHERE partition=? AND request_id=?',
      [partition, request],
    )).single;
    return {
      ...response,
      'requestAuthorization': _map(jsonDecode(row['signed_body'] as String)),
      'preparedPayload': saved['payload'],
    };
  }

  Future<Map<String, dynamic>> _sign(
    Map<String, dynamic> body,
    String domain,
  ) async {
    final lease = await context.account.signingKey();
    try {
      return context.codec.crypto.signDomain(body, lease.key, domain);
    } finally {
      lease.release();
    }
  }

  Future<String> manifestId(String scope) =>
      context.reservedRecordId(scope, 'financeAccountChoices');

  /// Source-side FILE derivation only. No target archive or target key is used.
  Future<Map<String, dynamic>> proposeCapturedSelection(
    VerifiedCapturedFinanceAccountChoices verified, {
    required CryptoMigrationCandidate candidate,
    required String actionId,
  }) async {
    final raw = verified.raw,
        selection = _map(raw['capture3']),
        captured = _map(selection['context']),
        source = _map(captured['source']),
        target = _map(captured['target']),
        own = await context.account.directory.requireFresh();
    if (!candidate.isFor(context.access, source['scopeId']) ||
        candidate.captureId != source['captureId'] ||
        candidate.migrationId != source['migrationId'] ||
        candidate.head.headHash != source['membershipHeadHash'] ||
        source['accountId'] != own.accountId ||
        verified.rawHash != await CryptoBusinessJson.hash(raw)) {
      throw const FormatException('crypto_account_choices_capture_source');
    }
    final lease = await candidate.key('finance');
    lease.release();
    await _schema();
    final old = await context.db.rows(
      'SELECT selection FROM crypto_account_choice_selections WHERE partition=? AND action_id=?',
      [partition, actionId],
    );
    if (old.isEmpty) {
      await context.db.execute(
        'INSERT INTO crypto_account_choice_selections VALUES(?,?,?,?)',
        [
          partition,
          actionId,
          target['scopeId'],
          CryptoBusinessJson.canonical(selection),
        ],
      );
    } else if (!_same(
      jsonDecode(old.single['selection'] as String),
      selection,
    )) {
      throw const FormatException('crypto_account_choices_immutable_selection');
    }
    final result = await _send(
      actionId,
      target['scopeId'],
      'crypto2.exports.propose',
      {'selectionHash': raw['selectionHash']},
      (_) async => {
        'variant': variant,
        'selectionProof': await _sign({
          'version': 2,
          'operation': 'crypto2.exports.offer',
          'variant': variant,
          'purpose': type,
          'serverId': own.serverId,
          'sourceScopeId': source['scopeId'],
          'sourceHeadHash': source['membershipHeadHash'],
          'targetScopeId': target['scopeId'],
          'targetHeadHash': target['membershipHeadHash'],
          'selectionCount': verified.choices.length,
          'selectionHash': raw['selectionHash'],
          'capture3Context': captured,
          'accountId': own.accountId,
          'deviceId': context.account.deviceId,
          'authorDirectoryHeadHash': own.headHash,
          'deviceSnapshotHash': own.deviceSnapshotHash,
        }, CryptoScopedExports.offerDomain),
      },
      candidate: candidate,
    );
    return {
      ...result,
      'offerAuthorization': result['preparedPayload']['selectionProof'],
      'selectionActionId': actionId,
    };
  }

  /// The source issuer checks every source account against a complete verified
  /// checkpoint and signs the whole salted selection, including the empty set.
  Future<Map<String, dynamic>> prepare(
    String target, {
    required String actionId,
  }) async {
    CryptoFinanceChoiceSelectionCodec.uuid(actionId);
    await _schema();
    final oldDraft = await context.db.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [partition, target, actionId],
    );
    if (oldDraft.isNotEmpty) {
      final saved = _map(jsonDecode(oldDraft.single['payload'] as String));
      if (saved['operation'] != 'crypto2.exports.propose' ||
          saved['payload']['variant'] != variant) {
        throw const FormatException('scoped_export_immutable_intent');
      }
      final oldProof = _map(saved['payload']['selectionProof']);
      final offer = _body(oldProof);
      final result = await _send(actionId, target, 'crypto2.exports.propose', {
        'selectionHash': offer['selectionHash'],
      }, (_) async => _map(saved['payload']));
      return {
        ...result,
        'offerAuthorization': oldProof,
        'selectionActionId': actionId,
      };
    }
    await context.pullVerified(target, 'content', attest: false);
    final scopes = await context.db.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [partition, target],
    );
    if (scopes.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_parent_pending',
      );
    }
    final scope = _map(jsonDecode(scopes.single['data'] as String));
    final parent = SharedScope.fromJson(scope).parentSpaceId;
    if (scope['kind'] != 'project' ||
        parent != null && !isCryptoCanonicalUuid(parent)) {
      throw const FormatException('crypto_account_choices_target');
    }
    if (parent == null) {
      // A project-only member can read an already endorsed target manifest,
      // but cannot derive a fresh selection from an undisclosed parent ledger.
      throw const CryptoAuthorityPending(
        'crypto_account_choices_parent_unavailable',
      );
    }
    final source = parent;
    await context.pullVerified(source, 'finance');
    final read = await context.access.readContext(source, 'finance');
    if (!await context.hasReusableCheckpoint(source, 'finance', read)) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_inventory_pending',
      );
    }
    final checkpointRows = await context.db.rows(
      'SELECT c.authorization FROM crypto_domain_checkpoints c JOIN crypto_scope_state s ON s.partition=c.partition AND s.scope_id=c.scope_id AND s.domain=c.domain WHERE c.partition=? AND c.scope_id=? AND c.domain=? AND c.head_hash=? AND c.sequence=s.scope_sequence ORDER BY c.sequence DESC LIMIT 1',
      [partition, source, 'finance', read.headHash],
    );
    if (checkpointRows.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_inventory_pending',
      );
    }
    final checkpoint = _map(
      jsonDecode(checkpointRows.single['authorization'] as String),
    );
    await context.access.verifyDomainCheckpoint(checkpoint);
    final cp = _map(_body(checkpoint)['payload']);
    final rows = await context.db.rows(
      "SELECT * FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain='finance' AND type='financeAccount' AND deleted=0 ORDER BY id",
      [partition, source],
    );
    if (rows.length > maxChoices) {
      throw const CryptoAuthorityPending('crypto_account_choices_capacity');
    }
    final choices = <Map<String, dynamic>>[],
        sourceRecords = <Map<String, dynamic>>[];
    for (final row in rows) {
      final identity = _map(jsonDecode(row['projection'] as String));
      final canonical = identity['id'];
      final verified = await CryptoFinanceAuditEvidence(
        context,
      ).currentPayload(source, canonical, type: 'financeAccount');
      final raw = _map(verified['raw']);
      choices.add({
        'accountId': canonical,
        'accountScopeId': source,
        'name': raw['name'],
        'currency': raw['currency'],
        'archived': raw['archived'],
        'sourceRevision': identity['revision'],
      });
      sourceRecords.add({
        'id': row['id'],
        'recordProofHash': row['record_proof_hash'],
      });
    }
    choices.sort(
      (a, b) => (a['accountId'] as String).compareTo(b['accountId']),
    );
    sourceRecords.sort((a, b) => (a['id'] as String).compareTo(b['id']));
    final selected = CryptoFinanceChoiceSelectionCodec.choices(choices, source);
    final own = await context.account.directory.requireFresh(),
        head = await context.access.currentHead(target, online: true);
    await context.db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_account_choice_selections(partition TEXT NOT NULL,action_id TEXT NOT NULL,scope_id TEXT NOT NULL,selection TEXT NOT NULL,PRIMARY KEY(partition,action_id))',
    );
    final retained = await context.db.rows(
      'SELECT selection FROM crypto_account_choice_selections WHERE partition=? AND action_id=? AND scope_id=?',
      [partition, actionId, target],
    );
    final retainedSelection = retained.isEmpty
        ? null
        : _map(jsonDecode(retained.single['selection'] as String));
    final salt = retainedSelection == null
        ? context.codec.crypto.sodium.randombytes.buf(32)
        : cryptoBase64(retainedSelection['selectionSaltBase64'], length: 32);
    late String saltBase64;
    try {
      saltBase64 = base64Encode(salt);
    } finally {
      salt.fillRange(0, salt.length, 0);
    }
    final base = <String, dynamic>{
      'version': 2,
      'variant': variant,
      'purpose': 'financeAccountChoice',
      'serverId': own.serverId,
      'sourceScopeId': source,
      'sourceHeadHash': read.headHash,
      'sourceCheckpoint': {
        'proofHash': await _hash(checkpoint),
        'sequence': cp['expectedSequence'],
        'manifestHash': cp['manifestHash'],
      },
      'targetScopeId': target,
      'targetHeadHash': head.headHash,
      'selectionCount': selected.length,
      'sourceRecordRoot': await cryptoSha256(
        utf8.encode('JivieFinanceAccountChoiceSource/v2\n') +
            CryptoJson.encode(sourceRecords),
      ),
    };
    if (retainedSelection != null) {
      final retainedContext = _map(retainedSelection['context']);
      for (final key in [
        'serverId',
        'sourceScopeId',
        'sourceHeadHash',
        'targetScopeId',
        'targetHeadHash',
        'selectionCount',
        'sourceRecordRoot',
      ]) {
        if (base[key] != retainedContext[key]) {
          throw const CryptoAuthorityPending(
            'crypto_account_choices_selection_changed',
          );
        }
      }
      if (!_same(retainedSelection['choices'], selected) ||
          !_same(retainedSelection['sourceRecords'], sourceRecords)) {
        throw const CryptoAuthorityPending(
          'crypto_account_choices_selection_changed',
        );
      }
      base
        ..clear()
        ..addAll(retainedContext);
    }
    final selectionHash = await CryptoFinanceChoiceSelectionCodec.selectionHash(
      base,
      selected,
      saltBase64,
    );
    final selection = {
      'context': base,
      'choices': selected,
      'sourceRecords': sourceRecords,
      'selectionSaltBase64': saltBase64,
    };
    if (CryptoBusinessJson.encode(selection).length > 190000) {
      throw const CryptoAuthorityPending('crypto_account_choices_capacity');
    }
    await context.db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_account_choice_selections(partition TEXT NOT NULL,action_id TEXT NOT NULL,scope_id TEXT NOT NULL,selection TEXT NOT NULL,PRIMARY KEY(partition,action_id))',
    );
    final previous = await context.db.rows(
      'SELECT selection FROM crypto_account_choice_selections WHERE partition=? AND action_id=?',
      [partition, actionId],
    );
    if (previous.isEmpty) {
      await context.db.execute(
        'INSERT INTO crypto_account_choice_selections VALUES(?,?,?,?)',
        [partition, actionId, target, CryptoBusinessJson.canonical(selection)],
      );
    } else if (!_same(
      jsonDecode(previous.single['selection'] as String),
      selection,
    )) {
      throw const FormatException('crypto_account_choices_immutable_selection');
    }
    final result = await _send(
      actionId,
      target,
      'crypto2.exports.propose',
      {'selectionHash': selectionHash},
      (_) async => {
        'variant': variant,
        'selectionProof': await _sign({
          ...base,
          'operation': 'crypto2.exports.offer',
          'selectionHash': selectionHash,
          'accountId': own.accountId,
          'deviceId': context.account.deviceId,
          'authorDirectoryHeadHash': own.headHash,
          'deviceSnapshotHash': own.deviceSnapshotHash,
        }, CryptoScopedExports.offerDomain),
      },
    );
    return {
      ...result,
      'offerAuthorization': result['preparedPayload']['selectionProof'],
      'selectionActionId': actionId,
    };
  }

  /// Manager review is deliberately independent of finance READ. It approves
  /// an issuer identity, exact opaque complete-set hash and selected writer.
  Future<Map<String, dynamic>> approve(
    String scope,
    Map<String, dynamic> offerProof, {
    required String actionId,
    required String recipientAccountId,
    required String recipientDeviceId,
    CryptoMigrationCandidate? candidate,
  }) async {
    final offer = _body(offerProof),
        own = await context.account.directory.requireFresh(),
        head =
            candidate?.head ??
            await context.access.currentHead(scope, online: true);
    if (candidate != null) {
      if (!candidate.isFor(context.access, scope) ||
          offer['capture3Context']?['target']?['migrationId'] !=
              candidate.migrationId) {
        throw const FormatException('crypto_account_choices_capture_target');
      }
      await candidate.lifecycleHash();
    }
    if (head.member(own.accountId)['manageKeys'] != true) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_manager_required',
      );
    }
    if (offer['targetScopeId'] != scope) {
      throw const FormatException('crypto_account_choices_target');
    }
    if (offer['targetHeadHash'] != head.headHash) {
      throw const CryptoAuthorityPending('crypto_account_choices_head_changed');
    }
    if (!offer.containsKey('capture3Context')) {
      CryptoFinanceChoiceSelectionCodec.context(offer);
    }
    final issuer = await context.access.currentMemberDirectory(
      scope,
      head.headHash,
      offer['accountId'],
    );
    final reference = await context.access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head.headHash,
      accountId: offer['accountId'],
      directoryHeadHash: offer['authorDirectoryHeadHash'],
    );
    if (issuer.deviceSnapshotHash != offer['deviceSnapshotHash'] ||
        reference.deviceSnapshotHash != issuer.deviceSnapshotHash) {
      throw const CryptoAuthorityPending('scoped_export_issuer_changed');
    }
    context.codec.crypto.verifyDomain(
      offerProof,
      cryptoBase64(
        reference.activeDevice(offer['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      CryptoScopedExports.offerDomain,
    );
    if (!(candidate == null ? const {'write'} : const {'read', 'write'})
        .contains(head.member(recipientAccountId)['financeRole'])) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_writer_required',
      );
    }
    final recipient = await context.access.currentMemberDirectory(
          scope,
          head.headHash,
          recipientAccountId,
        ),
        device = recipient.activeDevice(recipientDeviceId);
    final offerHash = await _hash(offerProof);
    await _schema();
    final retained = await context.db.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [partition, scope, actionId],
    );
    late Map<String, dynamic> bridge;
    if (retained.isEmpty) {
      bridge = {
        'accountId': recipient.accountId,
        'deviceId': recipientDeviceId,
        'directoryHeadHash': recipient.headHash,
        'deviceSnapshotHash': recipient.deviceSnapshotHash,
        'encryptionPublicKeyBase64': device['encryptionKeyBase64'],
      };
    } else {
      final saved = _map(jsonDecode(retained.single['payload'] as String));
      final payload = _map(saved['payload']);
      bridge = _map(payload['bridgeRecipient']);
      CryptoFinanceChoiceSelectionCodec.closed(bridge, {
        'accountId',
        'deviceId',
        'directoryHeadHash',
        'deviceSnapshotHash',
        'encryptionPublicKeyBase64',
      });
      if (saved['operation'] != 'crypto2.exports.delegate' ||
          payload['variant'] != variant ||
          payload['offerHash'] != offerHash ||
          payload['scopeId'] != scope ||
          payload['membershipHeadHash'] != head.headHash ||
          payload['expectedAccessRevision'] != head.accessRevision ||
          payload['selectionHash'] != offer['selectionHash'] ||
          payload['issuerAccountId'] != issuer.accountId ||
          payload['issuerIdentityEpochId'] != issuer.identityEpochId ||
          payload['issuerDeviceSnapshotHash'] != issuer.deviceSnapshotHash ||
          payload['issuerRootSigningKeyBase64'] !=
              issuer.snapshot['rootSigningKeyBase64'] ||
          payload['issuerRootEncryptionKeyBase64'] !=
              issuer.snapshot['rootEncryptionKeyBase64'] ||
          bridge['accountId'] != recipientAccountId ||
          bridge['deviceId'] != recipientDeviceId) {
        throw const FormatException('scoped_export_immutable_intent');
      }
      if (bridge['deviceSnapshotHash'] != recipient.deviceSnapshotHash ||
          bridge['encryptionPublicKeyBase64'] !=
              device['encryptionKeyBase64']) {
        throw const CryptoAuthorityPending('scoped_export_recipient_changed');
      }
    }
    final result = await _send(
      actionId,
      scope,
      'crypto2.exports.delegate',
      {'offerHash': offerHash, 'bridgeRecipient': bridge},
      (_) async => {
        'variant': variant,
        'offerHash': offerHash,
        'scopeId': scope,
        'membershipHeadHash': head.headHash,
        'expectedAccessRevision': head.accessRevision,
        'authorDirectoryHeadHash': own.headHash,
        'delegationId': actionId,
        'selectionHash': offer['selectionHash'],
        'issuerAccountId': issuer.accountId,
        'issuerDirectoryHeadHash': issuer.headHash,
        'issuerRootSigningKeyBase64': issuer.snapshot['rootSigningKeyBase64'],
        'issuerRootEncryptionKeyBase64':
            issuer.snapshot['rootEncryptionKeyBase64'],
        'issuerIdentityEpochId': issuer.identityEpochId,
        'issuerDeviceSnapshotHash': issuer.deviceSnapshotHash,
        'bridgeRecipient': bridge,
      },
      candidate: candidate,
    );
    return {
      ...result,
      'delegationAuthorization': result['requestAuthorization'],
    };
  }

  /// The review card contains a complete-set commitment and eligible target
  /// devices. It does not open the parent ledger or disclose account names.
  Future<Map<String, dynamic>> reviewOffer(
    String scope,
    Map<String, dynamic> proof, {
    CryptoMigrationCandidate? candidate,
  }) async {
    final offer = _body(proof);
    if (!offer.containsKey('capture3Context')) {
      CryptoFinanceChoiceSelectionCodec.context(offer);
    }
    if (offer['variant'] != variant ||
        offer['purpose'] != type ||
        offer['operation'] != 'crypto2.exports.offer' ||
        offer['targetScopeId'] != scope) {
      throw const FormatException('crypto_account_choices_target');
    }
    final head =
        candidate?.head ??
        await context.access.currentHead(scope, online: true);
    if (candidate != null) {
      if (!candidate.isFor(context.access, scope) ||
          offer['capture3Context']?['target']?['migrationId'] !=
              candidate.migrationId) {
        throw const FormatException('crypto_account_choices_capture_target');
      }
      await candidate.lifecycleHash();
    }
    if (head.headHash != offer['targetHeadHash'] ||
        head.member(context.account.directory.accountId)['manageKeys'] !=
            true) {
      throw const CryptoAuthorityPending('crypto_account_choices_head_changed');
    }
    final issuer = await context.access.currentMemberDirectory(
      scope,
      head.headHash,
      offer['accountId'],
    );
    final reference = await context.access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head.headHash,
      accountId: offer['accountId'],
      directoryHeadHash: offer['authorDirectoryHeadHash'],
    );
    if (reference.deviceSnapshotHash != issuer.deviceSnapshotHash ||
        issuer.deviceSnapshotHash != offer['deviceSnapshotHash']) {
      throw const CryptoAuthorityPending('scoped_export_issuer_changed');
    }
    context.codec.crypto.verifyDomain(
      proof,
      cryptoBase64(
        reference.activeDevice(offer['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      CryptoScopedExports.offerDomain,
    );
    final writers = <Map<String, dynamic>>[];
    for (final member in head.members.where(
      (m) => (candidate == null ? const {'write'} : const {'read', 'write'})
          .contains(m['financeRole']),
    )) {
      final directory = await context.access.currentMemberDirectory(
        scope,
        head.headHash,
        member['accountId'],
      );
      final cached = await context.db.rows(
        'SELECT data FROM members WHERE partition=? AND scope_id=? AND account_id=?',
        [partition, scope, directory.accountId],
      );
      final label = cached.isEmpty
          ? null
          : _map(jsonDecode(cached.single['data'] as String));
      final displayName = label?['displayName'] ?? label?['username'];
      for (final device in directory.devices) {
        if (device['revokedGeneration'] != null ||
            device['identityEpochId'] != directory.identityEpochId) {
          continue;
        }
        writers.add({
          'accountId': directory.accountId,
          'deviceId': device['deviceId'],
          if (displayName is String && displayName.isNotEmpty)
            'displayName': displayName,
        });
        if (writers.length > 128) {
          throw const CryptoAuthorityPending('crypto_account_choices_capacity');
        }
      }
    }
    if ((candidate?.head ??
                await context.access.currentHead(scope, online: true))
            .headHash !=
        head.headHash) {
      throw const CryptoAuthorityPending('crypto_account_choices_head_changed');
    }
    return {
      'selectionHash': offer['selectionHash'],
      'selectionCount': offer['selectionCount'],
      'issuerAccountId': offer['accountId'],
      'writers': List.unmodifiable(writers),
    };
  }

  Future<Map<String, dynamic>> certify(
    String scope, {
    required String selectionActionId,
    required Map<String, dynamic> offerAuthorization,
    required Map<String, dynamic> delegationAuthorization,
    required String actionId,
    CryptoMigrationCandidate? candidate,
  }) async {
    final rows = await context.db.rows(
      'SELECT selection FROM crypto_account_choice_selections WHERE partition=? AND action_id=? AND scope_id=?',
      [partition, selectionActionId, scope],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_selection_missing',
      );
    }
    final selection = _map(jsonDecode(rows.single['selection'] as String)),
        offer = _body(offerAuthorization),
        d = _map(_body(delegationAuthorization)['payload']);
    await _verifyManager(
      offer,
      delegationAuthorization,
      issuerCandidate: candidate,
    );
    if (d['offerHash'] != await _hash(offerAuthorization) ||
        d['selectionHash'] != offer['selectionHash']) {
      throw const FormatException('crypto_account_choices_delegation');
    }
    final result = await _send(
      actionId,
      scope,
      'crypto2.exports.certify',
      {
        'offerHash': await _hash(offerAuthorization),
        'delegationHash': await _hash(delegationAuthorization),
      },
      candidate: candidate,
      (request) async {
        final bridgeContext = {
          'variant': variant,
          'offerHash': await _hash(offerAuthorization),
          'delegationHash': await _hash(delegationAuthorization),
          'selectionHash': offer['selectionHash'],
          'requestId': request,
          'recipient': d['bridgeRecipient'],
        };
        final bytes = CryptoBusinessJson.encode({
          'context': bridgeContext,
          'selection': selection,
        });
        try {
          if (bytes.length > 196608) {
            throw const CryptoAuthorityPending(
              'crypto_account_choices_capacity',
            );
          }
          final cipher = context.codec.crypto.sodium.crypto.box.seal(
            message: bytes,
            publicKey: cryptoBase64(
              d['bridgeRecipient']['encryptionPublicKeyBase64'],
              length: 32,
            ),
          );
          return {
            'variant': variant,
            'offerHash': await _hash(offerAuthorization),
            'delegationHash': await _hash(delegationAuthorization),
            'certificateProof': await _sign({
              ...offer,
              'operation': 'crypto2.exports.certificate',
              'offerHash': await _hash(offerAuthorization),
              'delegationHash': await _hash(delegationAuthorization),
              'bridge': {
                'recipient': d['bridgeRecipient'],
                'requestId': request,
                'sealedDisclosureBase64': base64Encode(cipher),
                'ciphertextHash': await cryptoSha256(cipher),
              },
            }, CryptoScopedExports.certificateDomain),
          };
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      },
    );
    // Discovery acceleration only. The original selection and signed commands
    // remain immutable; restoring without this marker safely retries them.
    await context.db.execute(
      'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
      ['$partition:accountChoiceCertified:$selectionActionId', actionId],
    );
    return {
      ...result,
      'certificateAuthorization': result['preparedPayload']['certificateProof'],
    };
  }

  /// Fresh issuance through the existing source-authorized delegation proof
  /// route. No child ACL, directory cache, secure floor or contact is installed.
  Future<VerifiedAccountDirectory> _capturedDelegationDirectory(
    Map<String, dynamic> proof, {
    required bool recipient,
  }) async {
    final command = _body(proof), p = _map(command['payload']);
    final expectedAccount = recipient
        ? p['bridgeRecipient']['accountId']
        : command['accountId'];
    final expectedReference = recipient
        ? p['bridgeRecipient']['directoryHeadHash']
        : p['authorDirectoryHeadHash'];
    final own = await context.account.directory.requireFresh();
    final known = await context.account.store.anchor(expectedAccount);
    VerifiedAccountDirectory? state;
    String? fingerprint, header;
    var after = 0;
    final digest = await _hash(proof),
        reducer = context.account.directory.reducer;
    while (true) {
      if (!context.account.directory.isCurrent()) {
        throw const CryptoAuthorityPending(
          'crypto_account_choices_authority_changed',
        );
      }
      final page = await context.account.directory.call(
        recipient
            ? 'crypto2.exports.recipient.directory'
            : 'crypto2.exports.delegation.directory',
        {
          'variant': variant,
          'delegationHash': digest,
          'afterGeneration': after,
          'limit': 20,
        },
      );
      final pageHeader = CryptoBusinessJson.canonical({
        for (final k in [
          'accountId',
          'generation',
          'headHash',
          'snapshotHash',
          'deviceSnapshotHash',
        ])
          k: page[k],
      });
      if (page['accountId'] != expectedAccount ||
          page['generation'] is! int ||
          page['generation'] < 1 ||
          page['proofs'] is! List ||
          (page['proofs'] as List).length > 20 ||
          header != null && header != pageHeader) {
        throw const FormatException('crypto_account_choices_directory');
      }
      header ??= pageHeader;
      for (final raw in page['proofs'] as List) {
        final authorization = _map(raw),
            b = _body(authorization),
            payload = _map(b['payload']);
        fingerprint ??= reducer.crypto.fingerprint(
          cryptoBase64(payload['rootSigningKeyBase64'], length: 32),
          cryptoBase64(payload['rootEncryptionKeyBase64'], length: 32),
        );
        final commandHash = await cryptoSha256(
          cryptoBase64(authorization['commandBase64']),
        );
        final generation = (state?.generation ?? 0) + 1,
            previous = state?.headHash ?? cryptoZeroHash;
        final hash = await cryptoSha256([
          ...utf8.encode(cryptoDirectoryLogDomain),
          ...CryptoJson.encode({
            'serverId': own.serverId,
            'accountId': expectedAccount,
            'generation': generation,
            'previousHeadHash': previous,
            'commandHash': commandHash,
            'signatureBase64': authorization['signatureBase64'],
          }),
        ]);
        state = await reducer.apply(
          previous: state,
          entry: {
            'generation': generation,
            'previousHeadHash': previous,
            'commandHash': commandHash,
            'headHash': hash,
            'authorization': authorization,
          },
          serverId: own.serverId,
          accountId: expectedAccount,
          pinnedRootFingerprint: fingerprint,
        );
        if (state.generation > page['generation']) {
          throw const FormatException('crypto_account_choices_directory');
        }
      }
      if (page['hasMore'] != true) {
        if (state == null ||
            state.generation != page['generation'] ||
            state.headHash != page['headHash'] ||
            state.snapshotHash != page['snapshotHash'] ||
            state.deviceSnapshotHash != page['deviceSnapshotHash'] ||
            !state.verifiedHeaders.any(
              (h) => h.headHash == expectedReference,
            ) ||
            known != null &&
                !state.includesAnchor(known['generation'], known['headHash'])) {
          throw const FormatException('crypto_account_choices_directory');
        }
        if (expectedAccount == own.accountId) {
          if (state.rootFingerprint != own.rootFingerprint ||
              state.deviceSnapshotHash != own.deviceSnapshotHash) {
            throw const CryptoAuthorityPending(
              'crypto_account_choices_authority_changed',
            );
          }
        } else {
          await context.access.identities.requireVerified(
            expectedAccount,
            state.rootFingerprint,
          );
        }
        if ((await context.account.directory.cachedVerifiedDirectory())
                .headHash !=
            own.headHash) {
          throw const CryptoAuthorityPending(
            'crypto_account_choices_authority_changed',
          );
        }
        return state;
      }
      if (state == null ||
          state.generation <= after ||
          page['nextGeneration'] != state.generation) {
        throw const FormatException('crypto_account_choices_directory_cursor');
      }
      after = state.generation;
    }
  }

  Future<void> _verifyManager(
    Map<String, dynamic> offer,
    Map<String, dynamic> proof, {
    Map<String, dynamic>? snapshotRecord,
    CryptoMigrationCandidate? issuerCandidate,
    VerifiedScopeHead? exactTargetHead,
    bool onlineAuthorDirectory = false,
  }) async {
    final command = _body(proof),
        p = _map(command['payload']),
        frozenOwn =
            offer.containsKey('capture3Context') &&
                snapshotRecord != null &&
                issuerCandidate == null
            ? await context.access.readOnlyFrozenDirectory(
                offer['targetScopeId'],
                offer['targetHeadHash'],
              )
            : null,
        own = frozenOwn ?? await context.account.directory.requireFresh(),
        head =
            exactTargetHead ??
            (issuerCandidate != null
                ? issuerCandidate.head
                : snapshotRecord == null
                ? await context.access.currentHead(
                    offer['targetScopeId'],
                    online: true,
                  )
                : await context.access.headAt(
                    offer['targetScopeId'],
                    offer['targetHeadHash'],
                  ));
    if (issuerCandidate != null) {
      if (!issuerCandidate.isFor(context.access, offer['sourceScopeId']) ||
          issuerCandidate.head.headHash != offer['sourceHeadHash'] ||
          offer['accountId'] != own.accountId ||
          !offer.containsKey('capture3Context')) {
        throw const FormatException('crypto_account_choices_capture_source');
      }
      final key = await issuerCandidate.key('finance');
      key.release();
      // This side verifies the exact intended manager signature. The target
      // independently verifies its own manager role/head before publication.
      if (p['scopeId'] != offer['targetScopeId'] ||
          p['membershipHeadHash'] != offer['targetHeadHash'] ||
          p['selectionHash'] != offer['selectionHash'] ||
          p['issuerAccountId'] != own.accountId ||
          p['issuerRootSigningKeyBase64'] !=
              own.snapshot['rootSigningKeyBase64'] ||
          p['issuerRootEncryptionKeyBase64'] !=
              own.snapshot['rootEncryptionKeyBase64'] ||
          p['issuerDeviceSnapshotHash'] != own.deviceSnapshotHash ||
          command['operation'] != 'crypto2.exports.delegate' ||
          command['serverId'] != own.serverId) {
        throw const FormatException('crypto_account_choices_delegation');
      }
      if (p['bridgeRecipient']['accountId'] !=
          offer['capture3Context']['target']['accountId']) {
        throw const FormatException('crypto_account_choices_capture_recipient');
      }
      final manager = await _capturedDelegationDirectory(
        proof,
        recipient: false,
      );
      final recipient = await _capturedDelegationDirectory(
        proof,
        recipient: true,
      );
      final recipientDevice = recipient.activeDevice(
        p['bridgeRecipient']['deviceId'],
      );
      if (recipient.deviceSnapshotHash !=
              p['bridgeRecipient']['deviceSnapshotHash'] ||
          recipientDevice['encryptionKeyBase64'] !=
              p['bridgeRecipient']['encryptionPublicKeyBase64']) {
        throw const CryptoAuthorityPending(
          'crypto_account_choices_recipient_changed',
        );
      }
      context.codec.crypto.verifyDomain(
        proof,
        cryptoBase64(
          manager.activeDevice(command['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        cryptoDirectoryDomain,
      );
      return;
    }
    if (snapshotRecord == null && head.headHash != offer['targetHeadHash']) {
      throw const CryptoAuthorityPending('crypto_account_choices_head_changed');
    }
    CryptoFinanceChoiceSelectionCodec.closed(p, {
      'variant',
      'offerHash',
      'scopeId',
      'membershipHeadHash',
      'expectedAccessRevision',
      'authorDirectoryHeadHash',
      'delegationId',
      'selectionHash',
      'issuerAccountId',
      'issuerDirectoryHeadHash',
      'issuerRootSigningKeyBase64',
      'issuerRootEncryptionKeyBase64',
      'issuerIdentityEpochId',
      'issuerDeviceSnapshotHash',
      'bridgeRecipient',
    });
    CryptoFinanceChoiceSelectionCodec.closed(command, {
      'version',
      'operation',
      'requestId',
      'serverId',
      'accountId',
      'deviceId',
      'signer',
      'payload',
    });
    if (command['version'] != 2 ||
        command['operation'] != 'crypto2.exports.delegate' ||
        command['serverId'] != own.serverId ||
        command['signer'] != 'device' ||
        p['variant'] != variant ||
        p['scopeId'] != offer['targetScopeId'] ||
        p['membershipHeadHash'] != head.headHash ||
        p['expectedAccessRevision'] != head.accessRevision ||
        p['selectionHash'] != offer['selectionHash'] ||
        p['issuerAccountId'] != offer['accountId'] ||
        head.member(command['accountId'])['manageKeys'] != true) {
      throw const FormatException('crypto_account_choices_delegation');
    }
    final reference = await context.access.directoryAt(
      scopeId: head.scopeId,
      scopeHeadHash: head.headHash,
      accountId: command['accountId'],
      directoryHeadHash: p['authorDirectoryHeadHash'],
      allowUnverifiedContact: snapshotRecord != null,
      online:
          offer.containsKey('capture3Context') && snapshotRecord != null ||
          onlineAuthorDirectory,
    );
    if (snapshotRecord == null) {
      final current = await context.access.currentMemberDirectory(
        head.scopeId,
        head.headHash,
        command['accountId'],
      );
      if (reference.deviceSnapshotHash != current.deviceSnapshotHash) {
        throw const CryptoAuthorityPending('scoped_export_manager_changed');
      }
    } else {
      final member = head.member(command['accountId']);
      if (reference.deviceSnapshotHash != member['deviceSnapshotHash'] ||
          [
            'rootSigningKeyBase64',
            'rootEncryptionKeyBase64',
            'identityEpochId',
            'recoveryRootEpochId',
          ].any((k) => reference.snapshot[k] != member[k])) {
        throw const FormatException(
          'crypto_account_choices_historical_manager',
        );
      }
    }
    context.codec.crypto.verifyDomain(
      proof,
      cryptoBase64(
        reference.activeDevice(command['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    if (frozenOwn != null) {
      await context.access.readOnlyFrozenDirectory(
        offer['targetScopeId'],
        offer['targetHeadHash'],
      );
    }
  }

  /// Every descriptor is covered by this whole-selection signature and manager
  /// endorsement. No per-account fallback may claim a complete empty set.
  Future<List<Map<String, dynamic>>> verify(
    Map<String, dynamic> raw, {
    required String expectedScopeId,
  }) => _verify(raw, expectedScopeId: expectedScopeId);
  Future<List<Map<String, dynamic>>> _verify(
    Map<String, dynamic> raw, {
    required String expectedScopeId,
    Map<String, dynamic>? snapshotRecord,
    Map<String, dynamic>? migrationOrigin,
    bool onlineAuthorDirectory = false,
  }) async {
    final frozenOwn =
        raw.containsKey('capture3') &&
            snapshotRecord != null &&
            migrationOrigin != null
        ? await context.access.readOnlyFrozenDirectory(
            expectedScopeId,
            snapshotRecord['membershipHeadHash'],
          )
        : null;
    final verifyingOwn =
        frozenOwn ?? await context.account.directory.requireFresh();
    final currentRead = await context.access.readContext(
      expectedScopeId,
      'finance',
    );
    if (raw.containsKey('capture3')) {
      if (snapshotRecord == null || migrationOrigin == null) {
        throw const CryptoAuthorityPending(
          'crypto_account_choices_capture_provenance_pending',
        );
      }
      CryptoFinanceChoiceCapture.validate(raw);
      final capture = _map(raw['capture3']),
          captured = _map(capture['context']),
          target = _map(captured['target']),
          source = _map(captured['source']),
          tag = _map(snapshotRecord['metadata']['migrationOrigin']);
      if (migrationOrigin['captureVersion'] != 3 ||
          migrationOrigin['materializationRole'] != type ||
          migrationOrigin['derivedPayloadHash'] !=
              await CryptoBusinessJson.hash(raw) ||
          await CryptoFinanceChoiceCapture.selectionHash(capture) !=
              raw['selectionHash'] ||
          snapshotRecord['scopeId'] != expectedScopeId ||
          snapshotRecord['membershipHeadHash'] !=
              target['membershipHeadHash'] ||
          snapshotRecord['metadata']['identity']['canonicalId'] !=
              await manifestId(expectedScopeId) ||
          target['scopeId'] != expectedScopeId ||
          target['migrationId'] != tag['migrationId'] ||
          target['captureId'] != tag['captureId'] ||
          target['sourceInventoryRoot'] != tag['sourceInventoryRoot'] ||
          captured['childBinding']['bindingId'] != tag['bindingId']) {
        throw const FormatException('crypto_account_choices_capture_authority');
      }
      await verifyCapturedHandoff(
        raw,
        exactTargetHead: await context.access.headAt(
          expectedScopeId,
          target['membershipHeadHash'],
        ),
      );
      final descriptor = await context.verifiedBusinessScopeDescriptor(
        expectedScopeId,
      );
      if (descriptor['kind'] != 'project' ||
          descriptor['parentScopeToken'] !=
              await CryptoLifecycleEvidence(
                context.access,
              ).parentToken(expectedScopeId, source['scopeId'])) {
        throw const FormatException('crypto_account_choices_parent_binding');
      }
      final finalOwn = frozenOwn == null
          ? await context.account.directory.cachedVerifiedDirectory()
          : await context.access.readOnlyFrozenDirectory(
              expectedScopeId,
              snapshotRecord['membershipHeadHash'],
            );
      if (!context.account.directory.isCurrent() ||
          finalOwn?.identityEpochId != verifyingOwn.identityEpochId ||
          finalOwn?.deviceSnapshotHash != verifyingOwn.deviceSnapshotHash ||
          (await context.access.readContext(
                expectedScopeId,
                'finance',
              )).headHash !=
              currentRead.headHash) {
        throw const CryptoAuthorityPending(
          'crypto_account_choices_head_changed',
        );
      }
      return CryptoFinanceChoiceSelectionCodec.choices(
        capture['choices'],
        source['scopeId'],
      );
    }
    CryptoFinanceChoiceSelectionCodec.closed(raw, {
      'version',
      'variant',
      'selection',
      'offerAuthorization',
      'delegationAuthorization',
      'certificateAuthorization',
    });
    if (raw['version'] != 2 || raw['variant'] != variant) {
      throw const FormatException('crypto_account_choices_shape');
    }
    final selection = _map(raw['selection']),
        offer = _body(_map(raw['offerAuthorization'])),
        certificate = _body(_map(raw['certificateAuthorization'])),
        delegation = _map(raw['delegationAuthorization']);
    if (offer['targetScopeId'] != expectedScopeId) {
      throw const FormatException('crypto_account_choices_target');
    }
    final scopes = await context.db.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [partition, expectedScopeId],
    );
    if (scopes.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_parent_pending',
      );
    }
    final currentScope = _map(jsonDecode(scopes.single['data'] as String));
    final descriptor = await context.verifiedBusinessScopeDescriptor(
      expectedScopeId,
    );
    if (descriptor['kind'] != 'project' ||
        descriptor['parentScopeToken'] !=
            await CryptoLifecycleEvidence(
              context.access,
            ).parentToken(expectedScopeId, offer['sourceScopeId'])) {
      throw const FormatException('crypto_account_choices_parent_binding');
    }
    if (currentScope['kind'] != 'project' ||
        SharedScope.fromJson(currentScope).parentSpaceId !=
            offer['sourceScopeId']) {
      throw const FormatException('crypto_account_choices_parent_binding');
    }
    CryptoFinanceChoiceSelectionCodec.closed(selection, {
      'context',
      'choices',
      'sourceRecords',
      'selectionSaltBase64',
    });
    CryptoFinanceChoiceSelectionCodec.closed(_map(selection['context']), {
      'version',
      'variant',
      'purpose',
      'serverId',
      'sourceScopeId',
      'sourceHeadHash',
      'sourceCheckpoint',
      'targetScopeId',
      'targetHeadHash',
      'selectionCount',
      'sourceRecordRoot',
    });
    CryptoFinanceChoiceSelectionCodec.closed(offer, {
      'version',
      'variant',
      'purpose',
      'serverId',
      'sourceScopeId',
      'sourceHeadHash',
      'sourceCheckpoint',
      'targetScopeId',
      'targetHeadHash',
      'selectionCount',
      'sourceRecordRoot',
      'operation',
      'selectionHash',
      'accountId',
      'deviceId',
      'authorDirectoryHeadHash',
      'deviceSnapshotHash',
    });
    if (offer['version'] != 2 ||
        offer['operation'] != 'crypto2.exports.offer' ||
        offer['variant'] != variant ||
        offer['purpose'] != 'financeAccountChoice') {
      throw const FormatException('crypto_account_choices_offer');
    }
    final choices = CryptoFinanceChoiceSelectionCodec.choices(
      selection['choices'],
      offer['sourceScopeId'],
    );
    if (choices.length != offer['selectionCount'] ||
        await CryptoFinanceChoiceSelectionCodec.selectionHash(
              offer,
              choices,
              selection['selectionSaltBase64'],
            ) !=
            offer['selectionHash'] ||
        !_same(selection['context'], {
          for (final key in _map(selection['context']).keys) key: offer[key],
        })) {
      throw const FormatException('crypto_account_choices_selection');
    }
    if (snapshotRecord != null &&
        (snapshotRecord['scopeId'] != expectedScopeId ||
            snapshotRecord['type'] != type ||
            snapshotRecord['domain'] != 'finance' ||
            snapshotRecord['membershipHeadHash'] != offer['targetHeadHash'])) {
      throw const FormatException('crypto_account_choices_snapshot_binding');
    }
    final onlineOrdinaryDirectory =
        onlineAuthorDirectory &&
        context.access.canReadAuthorDirectoryOnline &&
        !raw.containsKey('capture3') &&
        (snapshotRecord == null
            ? offer['targetHeadHash'] == currentRead.headHash
            : snapshotRecord['membershipHeadHash'] == currentRead.headHash &&
                  snapshotRecord['epoch'] == currentRead.epoch &&
                  snapshotRecord['accessRevision'] ==
                      currentRead.accessRevision);
    await _verifyManager(
      offer,
      delegation,
      snapshotRecord: snapshotRecord,
      onlineAuthorDirectory: onlineOrdinaryDirectory,
    );
    final d = _map(_body(delegation)['payload']);
    final issuer = await context.access.directoryAt(
      scopeId: offer['targetScopeId'],
      scopeHeadHash: offer['targetHeadHash'],
      accountId: offer['accountId'],
      directoryHeadHash: offer['authorDirectoryHeadHash'],
      allowUnverifiedContact: true,
      online: onlineOrdinaryDirectory,
    );
    if (issuer.deviceSnapshotHash != offer['deviceSnapshotHash'] ||
        issuer.identityEpochId != d['issuerIdentityEpochId'] ||
        issuer.deviceSnapshotHash != d['issuerDeviceSnapshotHash'] ||
        issuer.snapshot['rootSigningKeyBase64'] !=
            d['issuerRootSigningKeyBase64'] ||
        issuer.snapshot['rootEncryptionKeyBase64'] !=
            d['issuerRootEncryptionKeyBase64']) {
      throw const CryptoAuthorityPending('scoped_export_issuer_changed');
    }
    final device = issuer.activeDevice(offer['deviceId']);
    context.codec.crypto.verifyDomain(
      _map(raw['offerAuthorization']),
      cryptoBase64(device['signingKeyBase64'], length: 32),
      CryptoScopedExports.offerDomain,
    );
    context.codec.crypto.verifyDomain(
      _map(raw['certificateAuthorization']),
      cryptoBase64(device['signingKeyBase64'], length: 32),
      CryptoScopedExports.certificateDomain,
    );
    final expected = {
      ...offer,
      'operation': 'crypto2.exports.certificate',
      'offerHash': await _hash(raw['offerAuthorization']),
      'delegationHash': await _hash(delegation),
      'bridge': certificate['bridge'],
    };
    if (!_same(certificate, expected) ||
        d['offerHash'] != expected['offerHash']) {
      throw const FormatException('crypto_account_choices_certificate');
    }
    final sourceRecords = selection['sourceRecords'];
    if (sourceRecords is! List ||
        sourceRecords.length != choices.length ||
        await cryptoSha256(
              utf8.encode('JivieFinanceAccountChoiceSource/v2\n') +
                  CryptoJson.encode(sourceRecords),
            ) !=
            offer['sourceRecordRoot']) {
      throw const FormatException('crypto_account_choices_source_set');
    }
    final expectedIds = {
      for (final c in choices)
        context
            .address(
              offer['sourceScopeId'],
              'finance',
              'financeAccount',
              c['accountId'],
            )
            .wireId,
    };
    String? last;
    for (final v in sourceRecords) {
      final r = _map(v);
      CryptoFinanceChoiceSelectionCodec.closed(r, {'id', 'recordProofHash'});
      CryptoFinanceChoiceSelectionCodec.hash(r['recordProofHash']);
      if (!expectedIds.remove(r['id']) ||
          last != null && (r['id'] as String).compareTo(last) <= 0) {
        throw const FormatException('crypto_account_choices_source_set');
      }
      last = r['id'];
    }
    if (expectedIds.isNotEmpty) {
      throw const FormatException('crypto_account_choices_source_set');
    }
    // Online availability checks relevant account IDs/proofs, not every
    // unrelated parent transaction after the authenticated derivation snapshot.
    // The signature attests the authorized issuer derivation; this online check
    // cannot cryptographically prove that an untrusted host withheld no change.
    if (snapshotRecord == null) {
      final available = await context.account.directory
          .call('crypto2.exports.certificates.get', {
            'scopeId': offer['targetScopeId'],
            'certificateHash': await _hash(raw['certificateAuthorization']),
          });
      if (!_same(available['authorization'], raw['certificateAuthorization'])) {
        throw const FormatException(
          'crypto_account_choices_certificate_substitution',
        );
      }
    }
    final finalOwn = await context.account.directory.requireFresh();
    final finalRead = await context.access.readContext(
      offer['targetScopeId'],
      'finance',
    );
    if (!context.account.directory.isCurrent() ||
        finalOwn.identityEpochId != verifyingOwn.identityEpochId ||
        finalOwn.deviceSnapshotHash != verifyingOwn.deviceSnapshotHash ||
        finalRead.headHash !=
            (snapshotRecord == null
                ? offer['targetHeadHash']
                : currentRead.headHash)) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_authority_changed',
      );
    }
    return choices;
  }

  /// Verifies the sanitized split-role handoff without opening a parent FILE.
  Future<String> verifyCapturedHandoff(
    Map<String, dynamic> raw, {
    required VerifiedScopeHead exactTargetHead,
  }) async {
    CryptoFinanceChoiceCapture.validate(raw);
    final selection = _map(raw['capture3']),
        captured = _map(selection['context']),
        offerProof = _map(raw['offerAuthorization']),
        offer = _body(offerProof),
        certificateProof = _map(raw['certificateAuthorization']),
        certificate = _body(certificateProof),
        delegation = _map(raw['delegationAuthorization']),
        p = _map(_body(delegation)['payload']);
    CryptoFinanceChoiceSelectionCodec.closed(offer, {
      'version',
      'operation',
      'variant',
      'purpose',
      'serverId',
      'sourceScopeId',
      'sourceHeadHash',
      'targetScopeId',
      'targetHeadHash',
      'selectionCount',
      'selectionHash',
      'capture3Context',
      'accountId',
      'deviceId',
      'authorDirectoryHeadHash',
      'deviceSnapshotHash',
    });
    if (!_same(offer['capture3Context'], captured) ||
        offer['version'] != 2 ||
        offer['variant'] != variant ||
        offer['purpose'] != type ||
        offer['operation'] != 'crypto2.exports.offer' ||
        offer['serverId'] != captured['serverId'] ||
        offer['sourceScopeId'] != captured['source']['scopeId'] ||
        offer['sourceHeadHash'] != captured['source']['membershipHeadHash'] ||
        offer['targetScopeId'] != exactTargetHead.scopeId ||
        offer['targetHeadHash'] != exactTargetHead.headHash ||
        captured['target']['membershipHeadHash'] != exactTargetHead.headHash ||
        offer['accountId'] != captured['source']['accountId'] ||
        offer['selectionHash'] != raw['selectionHash'] ||
        offer['selectionCount'] != (selection['choices'] as List).length ||
        offer['selectionHash'] !=
            await CryptoFinanceChoiceCapture.selectionHash(selection) ||
        p['offerHash'] != await _hash(offerProof)) {
      throw const FormatException('crypto_account_choices_capture_handoff');
    }
    await _verifyManager(
      offer,
      delegation,
      exactTargetHead: exactTargetHead,
      snapshotRecord: {'membershipHeadHash': exactTargetHead.headHash},
    );
    final issuer = await context.access.directoryAt(
      scopeId: exactTargetHead.scopeId,
      scopeHeadHash: exactTargetHead.headHash,
      accountId: offer['accountId'],
      directoryHeadHash: offer['authorDirectoryHeadHash'],
      allowUnverifiedContact: true,
      online: true,
    );
    if (issuer.snapshot['rootSigningKeyBase64'] !=
            p['issuerRootSigningKeyBase64'] ||
        issuer.snapshot['rootEncryptionKeyBase64'] !=
            p['issuerRootEncryptionKeyBase64'] ||
        issuer.identityEpochId != p['issuerIdentityEpochId'] ||
        issuer.deviceSnapshotHash != p['issuerDeviceSnapshotHash'] ||
        offer['deviceSnapshotHash'] != issuer.deviceSnapshotHash) {
      throw const FormatException('crypto_account_choices_capture_issuer');
    }
    final key = cryptoBase64(
      issuer.activeDevice(offer['deviceId'])['signingKeyBase64'],
      length: 32,
    );
    context.codec.crypto.verifyDomain(
      offerProof,
      key,
      CryptoScopedExports.offerDomain,
    );
    context.codec.crypto.verifyDomain(
      certificateProof,
      key,
      CryptoScopedExports.certificateDomain,
    );
    final expected = {
      ...offer,
      'operation': 'crypto2.exports.certificate',
      'offerHash': await _hash(offerProof),
      'delegationHash': await _hash(delegation),
      'bridge': certificate['bridge'],
    };
    if (!_same(expected, certificate) ||
        !_same(certificate['bridge']['recipient'], p['bridgeRecipient'])) {
      throw const FormatException('crypto_account_choices_capture_certificate');
    }
    final bridge = _map(certificate['bridge']),
        recipient = _map(bridge['recipient']);
    CryptoFinanceChoiceSelectionCodec.closed(bridge, {
      'recipient',
      'requestId',
      'sealedDisclosureBase64',
      'ciphertextHash',
    });
    CryptoFinanceChoiceSelectionCodec.closed(recipient, {
      'accountId',
      'deviceId',
      'directoryHeadHash',
      'deviceSnapshotHash',
      'encryptionPublicKeyBase64',
    });
    CryptoFinanceChoiceSelectionCodec.uuid(bridge['requestId']);
    for (final k in ['accountId', 'deviceId']) {
      CryptoFinanceChoiceSelectionCodec.uuid(recipient[k]);
    }
    for (final k in ['directoryHeadHash', 'deviceSnapshotHash']) {
      CryptoFinanceChoiceSelectionCodec.hash(recipient[k]);
    }
    cryptoBase64(recipient['encryptionPublicKeyBase64'], length: 32);
    final cipher = cryptoBase64(bridge['sealedDisclosureBase64']);
    if (cipher.length < 48 ||
        cipher.length > 196656 ||
        await cryptoSha256(cipher) != bridge['ciphertextHash'] ||
        !const {'read', 'write'}.contains(
          exactTargetHead.member(recipient['accountId'])['financeRole'],
        )) {
      throw const FormatException('crypto_account_choices_capture_recipient');
    }
    return CryptoBusinessJson.hash(raw);
  }

  Future<Map<String, dynamic>> materialize(
    String scope, {
    required Map<String, dynamic> offerAuthorization,
    required Map<String, dynamic> delegationAuthorization,
    required Map<String, dynamic> certificateAuthorization,
    required String operationId,
    CryptoMigrationCandidate? candidate,
  }) async {
    final certificate = _body(certificateAuthorization),
        d = _map(_body(delegationAuthorization)['payload']),
        recipient = _map(d['bridgeRecipient']);
    final own = await context.account.directory.requireFresh();
    if (recipient['accountId'] != own.accountId ||
        recipient['deviceId'] != context.account.deviceId ||
        recipient['deviceSnapshotHash'] != own.deviceSnapshotHash) {
      throw const CryptoAuthorityPending('scoped_export_recipient_changed');
    }
    final key = await context.account.encryptionKey();
    Uint8List? bytes;
    late Map<String, dynamic> selection;
    try {
      bytes = context.codec.crypto.sodium.crypto.box.sealOpen(
        cipherText: cryptoBase64(
          certificate['bridge']['sealedDisclosureBase64'],
        ),
        publicKey: key.publicKey,
        secretKey: key.secretKey,
      );
      final envelope = _map(jsonDecode(utf8.decode(bytes)));
      final expected = {
        'variant': variant,
        'offerHash': await _hash(offerAuthorization),
        'delegationHash': await _hash(delegationAuthorization),
        'selectionHash': certificate['selectionHash'],
        'requestId': certificate['bridge']['requestId'],
        'recipient': recipient,
      };
      if (!_same(envelope['context'], expected)) {
        throw const FormatException('crypto_account_choices_bridge');
      }
      selection = _map(envelope['selection']);
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      key.secretKey.dispose();
    }
    final captured = certificate.containsKey('capture3Context');
    final raw = {
      'version': 2,
      'variant': variant,
      if (captured) 'capture3': selection else 'selection': selection,
      if (captured) 'selectionHash': certificate['selectionHash'],
      'offerAuthorization': offerAuthorization,
      'delegationAuthorization': delegationAuthorization,
      'certificateAuthorization': certificateAuthorization,
    };
    if (captured) {
      if (candidate == null ||
          !candidate.isFor(context.access, scope) ||
          candidate.head.headHash != certificate['targetHeadHash'] ||
          candidate.migrationId !=
              certificate['capture3Context']['target']['migrationId'] ||
          !const {
            'read',
            'write',
          }.contains(candidate.head.member(own.accountId)['financeRole'])) {
        throw const CryptoAuthorityPending(
          'crypto_account_choices_capture_candidate_required',
        );
      }
      final lease = await candidate.key('finance');
      lease.release();
      final hash = await verifyCapturedHandoff(
        raw,
        exactTargetHead: candidate.head,
      );
      final handoffKey =
          'migration_choice_handoff:$partition:${certificate['capture3Context']['target']['captureId']}:$scope';
      final existing = await context.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [handoffKey],
      );
      final encoded = CryptoBusinessJson.canonical(raw);
      if (existing.isEmpty) {
        await context.db.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?)',
          [handoffKey, encoded],
        );
      } else if (existing.single['value'] != encoded) {
        throw const FormatException('crypto_account_choices_immutable_handoff');
      }
      return {'capturedRaw': raw, 'derivedPayloadHash': hash};
    }
    await verify(raw, expectedScopeId: scope);
    final id = await manifestId(scope),
        previous = await context.record(scope, 'finance', id, type: type);
    final claimed = await _reconcileMaterializationClaim(
      scope,
      id,
      operationId,
      previous?['crypto_revision'] as int? ?? 0,
      raw,
    );
    if (claimed != null) return claimed;
    return _publishMaterialization(
      scope,
      id,
      operationId,
      previous?['crypto_revision'] as int? ?? 0,
      raw,
    );
  }

  Future<Map<String, dynamic>> _publishMaterialization(
    String scope,
    String id,
    String operationId,
    int expectedRevision,
    Map<String, dynamic> raw,
  ) async {
    try {
      return await context.publishRaw(
        scopeId: scope,
        domain: 'finance',
        id: id,
        type: type,
        operationId: operationId,
        expectedRevision: expectedRevision,
        rawPayload: raw,
        localHash: await CryptoBusinessJson.hash(raw),
      );
    } on CryptoAuthorityPending catch (error) {
      if (error.reason != 'crypto_business_delivery_pending') rethrow;
      final rejected = await _conflictedMaterialization(scope, id, operationId);
      if (rejected == null) rethrow;
      // This is a derived shared cache. Another authorized materializer may
      // have won its CAS; only a fresh, fully verified current choice can serve
      // instead. The rejected request/receipt and its revision claim stay put.
      await context.pullVerified(scope, 'finance');
      final current = await _currentManifest(scope);
      final row = current['row'] as Map;
      if (row['crypto_revision'] is! int ||
          row['crypto_revision'] <= rejected['expectedRevision']) {
        rethrow;
      }
      return _map(jsonDecode(row['projection'] as String));
    }
  }

  /// A newer certificate is a different derived intent, not permission to
  /// replace an older revision claim. Finish its exact owner first, then use
  /// only an independently verified, advanced current choice.
  Future<Map<String, dynamic>?> _reconcileMaterializationClaim(
    String scope,
    String id,
    String operation,
    int expectedRevision,
    Map<String, dynamic> incoming,
  ) async {
    final existing = await context.db.rows(
      'SELECT 1 FROM crypto_business_requests WHERE partition=? AND operation_id=?',
      [partition, operation],
    );
    if (existing.isNotEmpty) return null;
    final claims = await context.db.rows(
      'SELECT c.request_id,b.operation_id FROM crypto_outbox_records c LEFT JOIN crypto_business_requests b ON b.partition=c.partition AND b.request_id=c.request_id WHERE c.partition=? AND c.scope_id=? AND c.domain=? AND c.record_id=? AND c.expected_revision=?',
      [
        partition,
        scope,
        'finance',
        context.address(scope, 'finance', type, id).wireId,
        expectedRevision,
      ],
    );
    if (claims.isEmpty) return null;
    if (claims.length != 1 || claims.single['operation_id'] is! String) {
      throw const FormatException('crypto_account_choices_conflict_binding');
    }
    final owner = claims.single['operation_id'] as String;
    if (owner == operation) return null; // Existing exact-intent retry path.
    Future<Map<String, dynamic>> boundOwner() async {
      final saved = await _materializationRequest(scope, id, owner);
      if (saved == null ||
          saved['row']['request_id'] != claims.single['request_id'] ||
          saved['record']['expectedRevision'] != expectedRevision) {
        throw const FormatException('crypto_account_choices_conflict_binding');
      }
      return saved;
    }

    var saved = await boundOwner();
    if (const {'pending', 'blocked'}.contains(saved['row']['state'])) {
      await context.queue.resumeUnresolved(
        requestIds: {claims.single['request_id'] as String},
      );
      saved = await boundOwner();
    }
    final state = saved['row']['state'];
    final receipt = await _materializationReceipt(saved);
    if (state != 'rejected' && state != 'applied' ||
        receipt == null ||
        state == 'rejected' && !_isMaterializationConflict(receipt) ||
        state == 'applied' &&
            (receipt.containsKey('outcome') &&
                    receipt['outcome'] != 'applied' ||
                receipt['status'] != 200)) {
      throw const CryptoAuthorityPending('crypto_business_delivery_pending');
    }
    context.financeReads?.invalidate();
    return context.access.withVerifiedOperation(() async {
      await context.pullVerified(scope, 'finance');
      final helper = CryptoFinanceAuditEvidence(context);
      late Map<String, dynamic> base;
      try {
        base = await helper.currentPayload(scope, id, type: type);
      } finally {
        await helper.close();
      }
      final row = base['row'] as Map,
          record = _map(base['record']),
          wire = _map(base['wire']),
          raw = _map(base['raw']);
      final revision = row['crypto_revision'];
      if (revision is! int ||
          revision <= expectedRevision ||
          wire['revision'] != revision ||
          record['expectedRevision'] + 1 != revision) {
        throw const CryptoAuthorityPending('crypto_business_delivery_pending');
      }
      if (!raw.containsKey('capture3')) {
        // The signed winner can be a valid historical derivation whose head
        // is no longer current. It establishes the physical CAS base only;
        // its stale selection must never satisfy a current-choice read.
        await _verify(raw, expectedScopeId: scope, snapshotRecord: record);
        if (_manifestBinding(raw)['targetHeadHash'] !=
            (await context.access.currentHead(scope, online: true)).headHash) {
          await verify(incoming, expectedScopeId: scope);
          final current = await context.record(
            scope,
            'finance',
            id,
            type: type,
          );
          if (current == null ||
              current['deleted'] != 0 ||
              current['crypto_revision'] != revision ||
              current['record_proof_hash'] != row['record_proof_hash']) {
            throw const CryptoAuthorityPending(
              'crypto_account_choices_authority_changed',
            );
          }
          return _publishMaterialization(
            scope,
            id,
            operation,
            revision,
            incoming,
          );
        }
      }
      final current = await _currentManifest(scope);
      final currentRow = current['row'] as Map;
      if (currentRow['crypto_revision'] is! int ||
          currentRow['crypto_revision'] <= expectedRevision) {
        throw const CryptoAuthorityPending('crypto_business_delivery_pending');
      }
      return _map(jsonDecode(currentRow['projection'] as String));
    }, freshBoundary: true);
  }

  Future<Map<String, dynamic>?> _materializationRequest(
    String scope,
    String id,
    String operation, {
    String? requiredState,
  }) async {
    final rows = await context.db.rows(
      'SELECT b.scope_id,b.domain,b.record_id,o.request_id,o.request_hash,o.signed_body,o.state FROM crypto_business_requests b JOIN crypto_outbox o ON o.partition=b.partition AND o.request_id=b.request_id WHERE b.partition=? AND b.operation_id=?',
      [partition, operation],
    );
    if (rows.length != 1 ||
        requiredState != null && rows.single['state'] != requiredState) {
      return null;
    }
    final row = rows.single;
    if (row['scope_id'] != scope ||
        row['domain'] != 'finance' ||
        row['record_id'] != id) {
      throw const FormatException('crypto_account_choices_conflict_binding');
    }
    final signed = _map(jsonDecode(row['signed_body'] as String));
    final own = await context.account.directory.requireFresh();
    final command = context.codec.crypto.verifyDomain(
      signed,
      cryptoBase64(
        own.activeDevice(context.account.deviceId)['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    final records = command['payload'] is Map
        ? command['payload']['records']
        : null;
    if (command['operation'] != 'crypto2.records.batch' ||
        command['version'] != 2 ||
        command['signer'] != 'device' ||
        command['requestId'] != row['request_id'] ||
        command['accountId'] != own.accountId ||
        command['serverId'] != own.serverId ||
        command['deviceId'] != context.account.deviceId ||
        records is! List ||
        records.length != 1 ||
        await cryptoSha256(cryptoBase64(signed['commandBase64'])) !=
            row['request_hash']) {
      throw const FormatException('crypto_account_choices_conflict_binding');
    }
    final record = _body(_map(records.single));
    context.codec.validateUntrustedRecord(record);
    if (record['scopeId'] != scope ||
        record['serverId'] != own.serverId ||
        record['accountId'] != own.accountId ||
        record['deviceId'] != context.account.deviceId ||
        record['batchId'] != command['payload']['batchId'] ||
        record['domain'] != 'finance' ||
        record['type'] != type ||
        record['operationId'] != operation ||
        record['deleted'] != false ||
        record['id'] != context.address(scope, 'finance', type, id).wireId) {
      throw const FormatException('crypto_account_choices_conflict_binding');
    }
    return {'row': row, 'signed': signed, 'record': record};
  }

  Future<Map<String, dynamic>?> _materializationReceipt(
    Map<String, dynamic> saved,
  ) async {
    final row = saved['row'] as Map;
    final receipt = await context.account.directory.call(
      'crypto2.receipt.get',
      {'requestId': row['request_id'], 'requestHash': row['request_hash']},
    );
    if (receipt['outcome'] == 'unknown') return null;
    if (receipt['requestId'] != row['request_id'] ||
        receipt['requestHash'] != row['request_hash'] ||
        !_same(receipt['authorization'], saved['signed'])) {
      throw const FormatException('crypto_receipt_substitution');
    }
    return receipt;
  }

  bool _isMaterializationConflict(Map<String, dynamic> receipt) =>
      (!receipt.containsKey('outcome') || receipt['outcome'] == 'rejected') &&
      receipt['status'] == 409 &&
      receipt['response'] is Map &&
      receipt['response']['errorCode'] == 'conflict';

  Future<Map<String, dynamic>?> _conflictedMaterialization(
    String scope,
    String id,
    String operation,
  ) async {
    final saved = await _materializationRequest(
      scope,
      id,
      operation,
      requiredState: 'rejected',
    );
    if (saved == null || saved['row']['state'] != 'rejected') return null;
    final receipt = await _materializationReceipt(saved);
    return receipt != null && _isMaterializationConflict(receipt)
        ? saved['record'] as Map<String, dynamic>
        : null;
  }

  Future<Map<String, dynamic>> prepareFinancialRecord(
    String scope,
    Map<String, dynamic> raw,
  ) async {
    if (raw['accountScopeId'] == null || raw['accountScopeId'] == scope) {
      if (raw.containsKey('accountChoiceWitness')) {
        throw const FormatException(
          'crypto_account_choices_unexpected_witness',
        );
      }
      return raw;
    }
    await ensure(scope);
    final id = await manifestId(scope),
        row = await context.record(scope, 'finance', id, type: type);
    if (row == null || row['deleted'] == 1) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_publication_required',
      );
    }
    final verified = await _currentManifest(scope),
        manifest = _map(verified['raw']),
        selected = (verified['choices'] as List).cast<Map<String, dynamic>>();
    _financialChoice(raw, selected);
    final offer = _manifestBinding(manifest);
    return {
      ...raw,
      'accountChoiceWitness': {
        'version': 2,
        'manifestId': id,
        'revision': row['crypto_revision'],
        'recordProofHash': row['record_proof_hash'],
        'targetHeadHash': offer['targetHeadHash'],
        'selectionHash': offer['selectionHash'],
      },
    };
  }

  void _financialChoice(
    Map<String, dynamic> raw,
    List<Map<String, dynamic>> selected, {
    bool allowArchived = false,
  }) {
    final matches = selected.where(
      (c) =>
          c['accountId'] == raw['accountId'] &&
          c['accountScopeId'] == raw['accountScopeId'],
    );
    if (matches.length != 1 ||
        matches.single['currency'] != raw['currency'] ||
        !allowArchived && matches.single['archived'] != false) {
      throw const FormatException('crypto_account_choices_financial_binding');
    }
  }

  Future<void> verifyFinancialRecord(
    String scope,
    Map<String, dynamic> raw, {
    Map<String, dynamic>? record,
    CryptoBusinessProjection? verifiedManifest,
  }) async {
    if (raw['accountScopeId'] == null || raw['accountScopeId'] == scope) {
      if (raw.containsKey('accountChoiceWitness')) {
        throw const FormatException(
          'crypto_account_choices_unexpected_witness',
        );
      }
      return;
    }
    final witness = _map(raw['accountChoiceWitness']);
    CryptoFinanceChoiceSelectionCodec.closed(witness, {
      'version',
      'manifestId',
      'revision',
      'recordProofHash',
      'targetHeadHash',
      'selectionHash',
    });
    if (witness['version'] != 2 ||
        witness['manifestId'] != await manifestId(scope) ||
        witness['revision'] is! int ||
        witness['revision'] < 1 ||
        witness['revision'] > 9007199254740991) {
      throw const FormatException('crypto_account_choices_financial_witness');
    }
    for (final k in ['recordProofHash', 'targetHeadHash', 'selectionHash']) {
      CryptoFinanceChoiceSelectionCodec.hash(witness[k]);
    }
    if (record == null) {
      final row = await context.record(
        scope,
        'finance',
        witness['manifestId'],
        type: type,
      );
      if (row == null ||
          row['deleted'] == 1 ||
          row['crypto_revision'] != witness['revision'] ||
          row['record_proof_hash'] != witness['recordProofHash']) {
        throw const CryptoAuthorityPending(
          'crypto_account_choices_financial_manifest_changed',
        );
      }
      final verified = await _currentManifest(scope),
          manifest = _map(verified['raw']),
          selected = (verified['choices'] as List).cast<Map<String, dynamic>>(),
          offer = _manifestBinding(manifest);
      if (offer['selectionHash'] != witness['selectionHash'] ||
          offer['targetHeadHash'] != witness['targetHeadHash']) {
        throw const FormatException('crypto_account_choices_financial_witness');
      }
      _financialChoice(raw, selected);
      return;
    }
    if (record['scopeId'] != scope || record['domain'] != 'finance') {
      throw const FormatException('crypto_account_choices_financial_scope');
    }
    final id = context
        .address(scope, 'finance', type, witness['manifestId'])
        .wireId;
    final refs = (record['metadata']['referenceVersions'] as List)
        .whereType<Map>()
        .where(
          (r) =>
              r['scopeId'] == scope &&
              r['domain'] == 'finance' &&
              r['id'] == id,
        )
        .toList();
    if (refs.length != 1 ||
        refs.single['revision'] != witness['revision'] ||
        refs.single['recordProofHash'] != witness['recordProofHash']) {
      throw const FormatException('crypto_account_choices_financial_reference');
    }
    if (verifiedManifest != null) {
      final manifestRecord = verifiedManifest.record;
      final origin = verifiedManifest.migrationOrigin;
      if (manifestRecord['scopeId'] != scope ||
          manifestRecord['domain'] != 'finance' ||
          manifestRecord['type'] != type ||
          manifestRecord['id'] != id ||
          manifestRecord['expectedRevision'] + 1 != witness['revision'] ||
          verifiedManifest.raw == null ||
          verifiedManifest.wire == null ||
          await context.codec.digest(
                _map(verifiedManifest.wire!['authorization']['recordProof']),
              ) !=
              witness['recordProofHash'] ||
          manifestRecord['membershipHeadHash'] != witness['targetHeadHash'] ||
          origin?['captureVersion'] != 3 ||
          origin?['materializationRole'] != type ||
          origin?['derivedPayloadHash'] !=
              await CryptoBusinessJson.hash(verifiedManifest.raw)) {
        throw const FormatException(
          'crypto_account_choices_financial_reference',
        );
      }
      final manifest = verifiedManifest.raw!;
      if (_manifestBinding(manifest)['selectionHash'] !=
          witness['selectionHash']) {
        throw const FormatException('crypto_account_choices_financial_witness');
      }
      final selected = await _verify(
        manifest,
        expectedScopeId: scope,
        snapshotRecord: manifestRecord,
        migrationOrigin: origin,
      );
      _financialChoice(
        raw,
        selected,
        allowArchived: record['metadata']['migrationOrigin'] != null,
      );
      return;
    }
    final roots = await context.db.rows(
      'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? ORDER BY revision DESC LIMIT 1',
      [partition, scope, 'finance', id],
    );
    if (roots.isEmpty) throw const CryptoProjectionPending();
    final root = _map(jsonDecode(roots.single['wire'] as String)),
        rootProof = _map(root['authorization']['recordProof']);
    final chain = await context.access.openHistoryChain(root);
    if (chain.nextRevision < witness['revision']) {
      throw const CryptoProjectionPending();
    }
    final evidenceFor = {
      'scopeId': scope,
      'id': id,
      'revision': root['revision'],
      'recordProofHash': await context.codec.digest(rootProof),
    };
    var fetches = 0;
    while (chain.nextRevision >= witness['revision']) {
      final revision = chain.nextRevision, hash = chain.nextHash;
      Map<String, dynamic> item;
      if (revision == root['revision']) {
        item = root;
      } else {
        List<Map<String, Object?>> cached = [];
        for (final table in [
          'crypto_received',
          'crypto_business_history_proofs',
          'crypto_business_ack_history',
        ]) {
          cached = await context.db.rows(
            'SELECT wire FROM $table WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
            [partition, scope, 'finance', id, revision],
          );
          cached = cached
              .where(
                (r) =>
                    _body(
                      _map(
                        _map(
                          jsonDecode(r['wire'] as String),
                        )['authorization']['recordProof'],
                      ),
                    )['expectedRevision'] ==
                    revision - 1,
              )
              .toList();
          if (cached.isNotEmpty) break;
        }
        if (cached.isNotEmpty) {
          final matches = <Map<String, dynamic>>[];
          for (final row in cached) {
            final candidate = _map(jsonDecode(row['wire'] as String));
            if (await context.codec.digest(
                  _map(candidate['authorization']['recordProof']),
                ) ==
                hash) {
              matches.add(candidate);
            }
          }
          if (matches.length != 1) {
            throw const FormatException('crypto_account_choices_history_fork');
          }
          item = matches.single;
        } else {
          if (++fetches > 32) throw const CryptoProjectionPending();
          final read = await context.access.readContext(scope, 'finance');
          final response = await context.account.directory
              .call('crypto2.records.historyGet', {
                'scopeId': scope,
                'domain': 'finance',
                'accessRevision': read.accessRevision,
                'id': id,
                'revision': revision,
                'recordProofHash': hash,
                'evidenceFor': evidenceFor,
              });
          item = _map(response['record']);
        }
      }
      final authority = await chain.authority(item),
          proof = _map(item['authorization']['recordProof']),
          body = _body(proof);
      await context.db.execute(
        'INSERT OR IGNORE INTO crypto_business_history_proofs(partition,scope_id,domain,record_id,revision,proof_hash,wire,history_basis) VALUES(?,?,?,?,?,?,?,?)',
        [
          partition,
          scope,
          'finance',
          id,
          revision,
          await context.codec.digest(proof),
          jsonEncode(item),
          authority.historyBasis ?? 'currentEpoch',
        ],
      );
      if (revision == witness['revision']) {
        if (hash != witness['recordProofHash'] ||
            body['type'] != type ||
            body['membershipHeadHash'] != witness['targetHeadHash'] ||
            body['metadata']['identity']['canonicalId'] !=
                witness['manifestId']) {
          throw const FormatException(
            'crypto_account_choices_financial_witness',
          );
        }
        final manifest = await CryptoFinanceAuditEvidence(
              context,
            ).openSnapshotPayload(item, authority),
            offer = _manifestBinding(manifest);
        if (offer['selectionHash'] != witness['selectionHash']) {
          throw const FormatException(
            'crypto_account_choices_financial_witness',
          );
        }
        final selected = await _verify(
          manifest,
          expectedScopeId: scope,
          snapshotRecord: body,
          migrationOrigin: authority.migrationOrigin,
        );
        _financialChoice(
          raw,
          selected,
          allowArchived: record['metadata']['migrationOrigin'] != null,
        );
        return;
      }
    }
    throw const CryptoProjectionPending();
  }

  Future<List<Map<String, dynamic>>> pendingOffers(String scope) async {
    final result = <Map<String, dynamic>>[];
    String? after;
    for (var page = 0; page < 64; page++) {
      final response = await context.account.directory
          .call('crypto2.exports.offers', {
            'scopeId': scope,
            'variant': variant,
            'stage': 'offers',
            'limit': 20,
            if (after != null) 'afterHash': after,
          });
      for (final v in response['items'] as List) {
        final item = _map(v), body = _body(_map(item['authorization']));
        if (body['targetScopeId'] != scope ||
            body['variant'] != variant ||
            await _hash(item['authorization']) != item['hash']) {
          throw const FormatException(
            'crypto_account_choices_offer_substitution',
          );
        }
        result.add({
          'offerAuthorization': item['authorization'],
          'offerHash': item['hash'],
          'selectionCount': body['selectionCount'],
          'selectionHash': body['selectionHash'],
          'issuerAccountId': body['accountId'],
        });
      }
      if (response['hasMore'] == false) return List.unmodifiable(result);
      final next = response['nextAfterHash'];
      if (next is! String || after != null && next.compareTo(after) <= 0) {
        throw const FormatException('crypto_account_choices_cursor');
      }
      after = next;
    }
    throw const CryptoAuthorityPending(
      'crypto_account_choices_discovery_pending',
    );
  }

  Future<List<Map<String, dynamic>>> ownPending() async {
    await _schema();
    final rows = await context.db.rows(
      "SELECT s.action_id,s.scope_id FROM crypto_account_choice_selections s WHERE s.partition=? AND NOT EXISTS(SELECT 1 FROM local_meta m WHERE m.name=?||s.action_id) ORDER BY s.rowid DESC LIMIT 65",
      [partition, '$partition:accountChoiceCertified:'],
    );
    if (rows.length > 64) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_discovery_pending',
      );
    }
    return List.unmodifiable([
      for (final r in rows)
        {'selectionActionId': r['action_id'], 'scopeId': r['scope_id']},
    ]);
  }

  Future<Map<String, dynamic>> finish(
    String scope,
    String selectionActionId,
  ) async {
    final offered = await prepare(scope, actionId: selectionActionId),
        offerProof = _map(offered['offerAuthorization']),
        offerHash = await _hash(offerProof);
    final offer = _body(offerProof);
    final sourceCandidate = offer.containsKey('capture3Context')
        ? await context.access.migrationCandidate(
            scopeId: offer['sourceScopeId'],
            migrationId: offer['capture3Context']['source']['migrationId'],
            captureId: offer['capture3Context']['source']['captureId'],
          )
        : null;
    final response = await context.account.directory.call(
      'crypto2.exports.delegation.forOffer',
      {'variant': variant, 'scopeId': scope, 'offerHash': offerHash},
    );
    if (response['authorization'] == null) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_manager_review_required',
      );
    }
    final delegation = _map(response['authorization']);
    final action = await context.reservedRecordId(
      scope,
      'accountChoiceSelection:certify:$offerHash',
    );
    final certified = await certify(
      scope,
      selectionActionId: selectionActionId,
      offerAuthorization: offerProof,
      delegationAuthorization: delegation,
      actionId: action,
      candidate: sourceCandidate,
    );
    final certificate = _map(certified['certificateAuthorization']);
    final recipient = _body(delegation)['payload']['bridgeRecipient'];
    if (!offer.containsKey('capture3Context') &&
        recipient['accountId'] == context.account.directory.accountId &&
        recipient['deviceId'] == context.account.deviceId) {
      final op = await context.reservedRecordId(
        scope,
        'accountChoiceSelection:materialize:${await _hash(certificate)}',
      );
      await materialize(
        scope,
        offerAuthorization: offerProof,
        delegationAuthorization: delegation,
        certificateAuthorization: certificate,
        operationId: op,
      );
    }
    return {
      'offerAuthorization': offerProof,
      'delegationAuthorization': delegation,
      'certificateAuthorization': certificate,
      if (offer.containsKey('capture3Context'))
        'capture3Context': offer['capture3Context'],
      'materializationRequired':
          offer.containsKey('capture3Context') ||
          recipient['accountId'] != context.account.directory.accountId ||
          recipient['deviceId'] != context.account.deviceId,
    };
  }

  Future<bool> materializeAvailable(
    String scope, {
    CryptoMigrationCandidate? candidate,
  }) async {
    String? after;
    for (var page = 0; page < 64; page++) {
      final response = await context.account.directory
          .call('crypto2.exports.offers', {
            'scopeId': scope,
            'variant': variant,
            'stage': 'certificates',
            if (candidate != null) 'captureId': candidate.captureId,
            'limit': 1,
            if (after != null) 'afterHash': after,
          });
      for (final value in response['items'] as List) {
        final item = _map(value),
            certificate = _map(item['authorization']),
            body = _body(certificate);
        late Map<String, dynamic> offerResponse;
        // The issuer's fetch can reject an obsolete source before materialize.
        // Only ordinary discovery skips it; captured derivations stay strict.
        try {
          offerResponse = await context.account.directory
              .call('crypto2.exports.delegation.forOffer', {
                'variant': variant,
                'scopeId': scope,
                'offerHash': body['offerHash'],
                'includeOffer': true,
              });
        } on CollaborationApiException catch (e) {
          if (candidate != null ||
              body.containsKey('capture3Context') ||
              !const {
                'crypto_account_choices_source_set_changed',
                'crypto_export_source_changed',
                'crypto_scope_head_changed',
                'crypto_export_issuer_changed',
              }.contains(e.code)) {
            rethrow;
          }
          continue;
        }
        final delegation = _map(offerResponse['authorization']);
        final offer = _map(offerResponse['offerAuthorization']);
        try {
          await materialize(
            scope,
            candidate: candidate,
            offerAuthorization: offer,
            delegationAuthorization: delegation,
            certificateAuthorization: certificate,
            operationId: await context.reservedRecordId(
              scope,
              'accountChoiceSelection:materialize:${await _hash(certificate)}',
            ),
          );
          return true;
        } on CollaborationApiException catch (e) {
          if (!const {
            'crypto_account_choices_source_set_changed',
            'crypto_export_source_changed',
            'crypto_scope_head_changed',
            'crypto_export_issuer_changed',
          }.contains(e.code)) {
            rethrow;
          }
        } on CryptoAuthorityPending catch (e) {
          if (candidate != null ||
              body.containsKey('capture3Context') ||
              e.reason != 'crypto_account_choices_head_changed') {
            rethrow;
          }
        }
      }
      if (response['hasMore'] == false) return false;
      final next = response['nextAfterHash'];
      if (next is! String || after != null && next.compareTo(after) <= 0) {
        throw const FormatException('crypto_account_choices_cursor');
      }
      after = next;
    }
    throw const CryptoAuthorityPending(
      'crypto_account_choices_discovery_pending',
    );
  }

  /// A pull can install an accepted manifest before its lost ACK is read.
  /// Settle only older, strictly bound ordinary materializations after current
  /// verification. Unknown outcomes never authorize a resend or a new intent.
  Future<Map<String, dynamic>> _readAndReconcileTerminal(String scope) async {
    final result = await read(scope), id = await manifestId(scope);
    final current = await context.record(scope, 'finance', id, type: type);
    if (current == null) return result;
    final raw = _map(jsonDecode(current['raw_payload'] as String));
    if (raw.containsKey('capture3')) return result;
    final claims = await context.db.rows(
      "SELECT c.request_id,c.expected_revision,b.operation_id FROM crypto_outbox_records c JOIN crypto_business_requests b ON b.partition=c.partition AND b.request_id=c.request_id JOIN crypto_outbox o ON o.partition=c.partition AND o.request_id=c.request_id WHERE c.partition=? AND c.scope_id=? AND c.domain='finance' AND c.record_id=? AND b.scope_id=? AND b.domain='finance' AND b.record_id=? AND o.state='pending' AND c.expected_revision<? ORDER BY o.sequence LIMIT 32",
      [
        partition,
        scope,
        context.address(scope, 'finance', type, id).wireId,
        scope,
        id,
        current['crypto_revision'],
      ],
    );
    final selected = <String>{};
    for (final claim in claims) {
      final saved = await _materializationRequest(
        scope,
        id,
        claim['operation_id'] as String,
      );
      if (saved == null ||
          saved['row']['request_id'] != claim['request_id'] ||
          saved['record']['expectedRevision'] != claim['expected_revision']) {
        throw const FormatException('crypto_account_choices_conflict_binding');
      }
      selected.add(claim['request_id'] as String);
    }
    if (selected.isNotEmpty) {
      await context.queue.reconcileTerminalReceipts(requestIds: selected);
    }
    return result;
  }

  /// Same-actor roles may advance the already authorized derivation directly.
  /// Split roles remain durable review/materialization work in Approvals.
  Future<Map<String, dynamic>> ensure(String scope) async {
    var replaceStale = false;
    try {
      return await _readAndReconcileTerminal(scope);
    } on CryptoAuthorityPending catch (e) {
      if (!const {
        'crypto_account_choices_publication_required',
        'crypto_account_choices_head_changed',
      }.contains(e.reason)) {
        rethrow;
      }
      replaceStale = e.reason == 'crypto_account_choices_head_changed';
    } on CollaborationApiException catch (e) {
      if (!_stale(e.code)) rethrow;
      replaceStale = true;
    }
    final own = await context.account.directory.requireFresh(),
        head = await context.access.currentHead(scope, online: true),
        member = head.member(own.accountId);
    if (member['financeRole'] == 'write' && await materializeAvailable(scope)) {
      try {
        return await _readAndReconcileTerminal(scope);
      } on CryptoAuthorityPending catch (e) {
        if (!const {
          'crypto_account_choices_publication_required',
          'crypto_account_choices_head_changed',
        }.contains(e.reason)) {
          rethrow;
        }
        replaceStale =
            replaceStale || e.reason == 'crypto_account_choices_head_changed';
      } on CollaborationApiException catch (e) {
        if (!_stale(e.code)) rethrow;
        replaceStale = true;
      }
    }
    await context.db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_account_choice_selections(partition TEXT NOT NULL,action_id TEXT NOT NULL,scope_id TEXT NOT NULL,selection TEXT NOT NULL,PRIMARY KEY(partition,action_id))',
    );
    final existing = await context.db.rows(
      'SELECT action_id FROM crypto_account_choice_selections WHERE partition=? AND scope_id=? ORDER BY rowid DESC LIMIT 1',
      [partition, scope],
    );
    var action = replaceStale || existing.isEmpty
        ? context.codec.crypto.randomId()
        : existing.single['action_id'] as String;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final offered = await prepare(scope, actionId: action);
        if (member['manageKeys'] == true && member['financeRole'] == 'write') {
          final offer = _map(offered['offerAuthorization']);
          await approve(
            scope,
            offer,
            actionId: await context.reservedRecordId(
              scope,
              'accountChoiceSelection:approve:${await _hash(offer)}',
            ),
            recipientAccountId: own.accountId,
            recipientDeviceId: context.account.deviceId,
          );
        }
        await finish(scope, action);
        return await _readAndReconcileTerminal(scope);
      } on CollaborationApiException catch (e) {
        if (attempt != 0 || !_stale(e.code)) rethrow;
      } on CryptoAuthorityPending catch (e) {
        if (attempt != 0 ||
            !const {
              'crypto_account_choices_head_changed',
              'scoped_export_source_changed',
            }.contains(e.reason)) {
          rethrow;
        }
      }
      // Only a new derived cache generation is prepared. Every old signed
      // request remains retained unchanged; ordinary same-record CAS prevents
      // competing generations from replacing each other's accepted effect.
      action = context.codec.crypto.randomId();
    }
    throw const CryptoAuthorityPending(
      'crypto_account_choices_publication_required',
    );
  }

  bool _stale(String code) => const {
    'crypto_account_choices_source_set_changed',
    'crypto_account_choices_checkpoint_changed',
    'crypto_export_source_changed',
    'crypto_scope_head_changed',
    'crypto_export_issuer_changed',
    'crypto_export_offer_expired',
  }.contains(code);

  bool supportsType(String value) => value == type;
  Map<String, dynamic>? validateRaw(
    String domain,
    String recordType,
    Map<String, dynamic> raw,
  ) {
    if (recordType != type) return null;
    if (domain != 'finance' ||
        raw['variant'] != variant ||
        raw['version'] != 2) {
      throw const FormatException('crypto_account_choices_shape');
    }
    if (raw.containsKey('capture3')) {
      CryptoFinanceChoiceCapture.validate(raw);
      return raw;
    }
    CryptoFinanceChoiceSelectionCodec.closed(raw, {
      'version',
      'variant',
      'selection',
      'offerAuthorization',
      'delegationAuthorization',
      'certificateAuthorization',
    });
    final offer = _body(_map(raw['offerAuthorization']));
    CryptoFinanceChoiceSelectionCodec.context(offer);
    CryptoFinanceChoiceSelectionCodec.choices(
      _map(raw['selection'])['choices'],
      offer['sourceScopeId'],
    );
    return raw;
  }

  Future<Map<String, dynamic>?> projectRecord(
    CryptoProjectionRecord value,
    Map<String, dynamic> raw,
  ) async {
    if (value.record['type'] != type) return null;
    final scope = value.record['scopeId'] as String;
    if (value.record['domain'] != 'finance' ||
        value.record['metadata']['identity']['canonicalId'] !=
            await manifestId(scope)) {
      throw const FormatException('crypto_account_choices_record_binding');
    }
    validateRaw('finance', type, raw);
    await _verify(
      raw,
      expectedScopeId: scope,
      snapshotRecord: value.record,
      migrationOrigin: value.migrationOrigin,
      onlineAuthorDirectory:
          context.onlineAccountChoiceDirectories && !value.historicalOnly,
    );
    return raw;
  }

  Future<void> validateFinanceGroup(
    List<CryptoBusinessProjection> batch, {
    bool forWrite = false,
  }) async {
    for (final value in batch.where((v) => v.record['type'] == type)) {
      if (value.historicalOnly) throw const CryptoProjectionPending();
      final scope = value.record['scopeId'] as String,
          identity = (value.record['metadata'] as Map?)?['identity'] as Map?;
      if ((identity?['canonicalId'] ?? value.record['id']) !=
              await manifestId(scope) ||
          value.record['domain'] != 'finance') {
        throw const FormatException('crypto_account_choices_record_binding');
      }
      if (value.raw != null) {
        validateRaw('finance', type, value.raw!);
        if (forWrite) {
          await verify(value.raw!, expectedScopeId: scope);
        } else {
          await _verify(
            value.raw!,
            expectedScopeId: scope,
            snapshotRecord: value.record,
            migrationOrigin: value.migrationOrigin,
          );
        }
      }
    }
  }

  Future<Map<String, dynamic>> read(String scope) async {
    await context.pullVerified(scope, 'finance');
    final verified = await _currentManifest(scope),
        raw = _map(verified['raw']),
        choices = (verified['choices'] as List).cast<Map<String, dynamic>>(),
        offer = _manifestBinding(raw),
        policy = await context.financePolicy(scope);
    return {
      'accounts': [
        for (final c in choices)
          {
            'id': c['accountId'],
            'scopeId': c['accountScopeId'],
            'name': c['name'],
            'currency': c['currency'],
            'archived': c['archived'],
          },
      ],
      'accountScopeId': offer['sourceScopeId'],
      'accessRevision': policy['revision'],
      // A captured manifest has its own canonical cache revision; it does not
      // invent a parent checkpoint sequence for pre-cutover legacy data.
      'accountSequence': raw.containsKey('capture3')
          ? verified['row']['crypto_revision']
          : _body(
              _map(raw['offerAuthorization']),
            )['sourceCheckpoint']['sequence'],
    };
  }

  Map<String, dynamic> _manifestBinding(Map<String, dynamic> raw) {
    if (!raw.containsKey('capture3')) {
      return _body(_map(raw['offerAuthorization']));
    }
    final capture = _map(_map(raw['capture3'])['context']);
    return {
      'sourceScopeId': capture['source']['scopeId'],
      'targetHeadHash': capture['target']['membershipHeadHash'],
      'selectionHash': raw['selectionHash'],
    };
  }

  Future<Map<String, dynamic>> _currentManifest(String scope) async {
    final id = await manifestId(scope);
    final row = await context.record(scope, 'finance', id, type: type);
    if (row == null || row['deleted'] == 1) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_publication_required',
      );
    }
    final helper = CryptoFinanceAuditEvidence(context);
    try {
      final verified = await helper.currentPayload(scope, id, type: type),
          raw = _map(verified['raw']),
          record = _map(verified['record']),
          authority = verified['authority'] as CryptoRecordAuthority;
      if (raw.containsKey('capture3')) {
        if ((await context.access.currentHead(scope, online: true)).headHash !=
            _manifestBinding(raw)['targetHeadHash']) {
          throw const CryptoAuthorityPending(
            'crypto_account_choices_head_changed',
          );
        }
        return {
          ...verified,
          'choices': await _verify(
            raw,
            expectedScopeId: scope,
            snapshotRecord: record,
            migrationOrigin: authority.migrationOrigin,
          ),
        };
      }
      return {
        ...verified,
        'choices': await _verify(
          raw,
          expectedScopeId: scope,
          onlineAuthorDirectory: context.onlineAccountChoiceDirectories,
        ),
      };
    } finally {
      await helper.close();
    }
  }

  static Future<void> verifyDelivery(dynamic access, Map command) async {
    final runtime = CryptoBusinessSession(
          access.account,
          access,
          access.account.store.database,
        ),
        helper = CryptoFinanceAccountChoices(
          CryptoBusinessSession(
            access.account,
            access,
            access.account.store.database,
          ),
        );
    await helper._schema();
    final rows = await runtime.db.rows(
      "SELECT payload FROM crypto_export_drafts WHERE partition=? AND json_extract(payload,'\$.requestId')=?",
      [runtime.partition, command['requestId']],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('scoped_export_intent_missing');
    }
    final saved = helper._map(jsonDecode(rows.single['payload'] as String));
    if (saved['operation'] != command['operation'] ||
        !helper._same(saved['payload'], command['payload'])) {
      throw const FormatException('scoped_export_intent_substitution');
    }
    await access.account.directory.requireFresh();
    final p = helper._map(command['payload']);
    final candidateContext = saved['candidateContext'];
    final candidate = candidateContext == null
        ? null
        : await access.migrationCandidate(
            scopeId: candidateContext['scopeId'],
            migrationId: candidateContext['migrationId'],
            captureId: candidateContext['captureId'],
          );
    if (command['operation'] == 'crypto2.exports.delegate') {
      final head =
          candidate?.head ??
          await access.currentHead(p['scopeId'], online: true);
      if (candidate != null) {
        final response = await access.account.directory
            .call('crypto2.exports.delegation.forOffer', {
              'variant': variant,
              'scopeId': p['scopeId'],
              'offerHash': p['offerHash'],
              'includeOffer': true,
            });
        final offer = helper._body(helper._map(response['offerAuthorization']));
        if (!offer.containsKey('capture3Context') ||
            offer['targetHeadHash'] != head.headHash ||
            offer['capture3Context']['target']['migrationId'] !=
                candidate.migrationId) {
          throw const FormatException('crypto_account_choices_capture_target');
        }
        await candidate.lifecycleHash();
      }
      if (head.headHash != p['membershipHeadHash'] ||
          head.accessRevision != p['expectedAccessRevision'] ||
          head.member(access.account.directory.accountId)['manageKeys'] !=
              true) {
        throw const CryptoAuthorityPending(
          'crypto_account_choices_manager_required',
        );
      }
    } else {
      final b = helper._body(
        helper._map(
          p[command['operation'] == 'crypto2.exports.propose'
              ? 'selectionProof'
              : 'certificateProof'],
        ),
      );
      if (candidate != null) {
        if (!b.containsKey('capture3Context') ||
            !candidate.isFor(access, b['sourceScopeId']) ||
            candidate.captureId !=
                b['capture3Context']['source']['captureId']) {
          throw const FormatException('crypto_account_choices_capture_source');
        }
        final key = await candidate.key('finance');
        key.release();
      } else {
        if (b.containsKey('capture3Context')) {
          throw const CryptoAuthorityPending(
            'crypto_account_choices_capture_candidate_required',
          );
        }
        await access.readContext(b['sourceScopeId'], 'finance');
      }
      final head =
          candidate?.head ??
          await access.currentHead(b['sourceScopeId'], online: true);
      if (head.headHash != b['sourceHeadHash']) {
        throw const CryptoAuthorityPending('scoped_export_source_changed');
      }
    }
  }
}
