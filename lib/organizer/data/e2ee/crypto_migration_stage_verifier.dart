import 'crypto_migration_cold_business.dart';
import 'crypto_migration_captured_choices.dart';
import 'crypto_finance_choice_capture.dart';
import 'crypto_migration_idea_payload.dart';
import 'dart:convert';

import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_v3.dart';
import 'crypto_migration_witness.dart';
import 'crypto_migration_file_object.dart';
import 'crypto_migration_witness_transport.dart';
import 'crypto_inventory_json.dart';
import 'crypto_business_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'account_directory_v2.dart';
import 'crypto_migration_scope_baseline.dart';
import 'session_crypto_access.dart';

// Private exact-proof coordinate. Only verifyTaskDependency can mint it, and
// only preparatory or isolated FILE code can consume its projection records.
class _TaskDependency {
  _TaskDependency(this.hash, this.scope, this.head, this.preparing);
  final String hash, scope, head;
  final CryptoMigrationCandidate? preparing;
}

/// Exact signed stage/capture binding, before any frozen scope read is opened.
/// This grants only a candidate coordinate for isolated parity, never WRITE.
class VerifiedCryptoMigrationStageCandidate {
  VerifiedCryptoMigrationStageCandidate._(
    this.scopeId,
    this.domain,
    this.headHash,
    this.authorizationHash,
    this.captureId,
    this.sourceInventoryRoot,
  );
  final String scopeId,
      domain,
      headHash,
      authorizationHash,
      captureId,
      sourceInventoryRoot;
}

/// Purpose-limited verification of a captured migration contribution. These
/// records are NOT ordinary writable records and grant no live projection or
/// historical timing authority. Active reads additionally need final anchored
/// manager provenance; this verifier is used only by isolated cold parity.
class CryptoMigrationStageVerifier {
  CryptoMigrationStageVerifier(this.context);
  final CryptoBusinessSession context;

  Future<VerifiedCryptoMigrationStageCandidate> frozenCandidate({
    required Map<String, dynamic> authorization,
    required VerifiedCryptoCaptureArchive coldArchive,
    required VerifiedAccountDirectory contributor,
  }) async {
    final publicKey = cryptoBase64(
      contributor.activeDevice(
        (CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
            as Map)['deviceId'],
      )['signingKeyBase64'],
      length: 32,
    );
    final command = context.codec.crypto.verifyDomain(
      authorization,
      publicKey,
      'JivieE2EE/v2\n',
    );
    final p = command['payload'];
    if (command['version'] != 2 ||
        command['operation'] != 'crypto2.migration.recordsStage' ||
        command['signer'] != 'device' ||
        command['accountId'] != contributor.accountId ||
        contributor.accountId != context.account.directory.accountId ||
        command['serverId'] !=
            context.account.directory.session.profile.serverId ||
        p is! Map ||
        p['captureVersion'] != 3 ||
        p['captureId'] != coldArchive.capture.captureId ||
        p['migrationId'] != coldArchive.capture.migrationId ||
        p['sourceInventoryRoot'] != coldArchive.sourceInventoryRoot ||
        p['sourceBindings'] is! List ||
        p['batch'] is! Map) {
      throw const FormatException('crypto_migration_frozen_candidate');
    }
    final proofs = p['batch']['records'];
    if (proofs is! List || proofs.isEmpty || proofs.length > 32) {
      throw const FormatException('crypto_migration_frozen_candidate');
    }
    String? scope, domain, head;
    final hashes = <String>{};
    for (final raw in proofs) {
      final proof = Map<String, dynamic>.from(raw as Map);
      final record = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      context.codec.validateUntrustedRecord(record);
      scope ??= record['scopeId'];
      domain ??= record['domain'];
      head ??= record['membershipHeadHash'];
      if (record['scopeId'] != scope ||
          record['domain'] != domain ||
          record['membershipHeadHash'] != head ||
          record['accountId'] != contributor.accountId ||
          record['deviceId'] != command['deviceId'] ||
          record['expectedRevision'] != 0 ||
          record['previousRecordHash'] != '0' * 64 ||
          !hashes.add(await context.codec.digest(proof))) {
        throw const FormatException('crypto_migration_frozen_candidate');
      }
      final digest = await context.codec.digest(proof);
      final matches = (p['sourceBindings'] as List)
          .cast<Map>()
          .where(
            (b) =>
                b['recordProofHash'] == digest ||
                (b['companionProofHashes'] as List).contains(digest),
          )
          .toList();
      if (matches.length != 1 ||
          CryptoJson.encode(record['metadata']['migrationOrigin']).toString() !=
              CryptoJson.encode({
                'version': 3,
                'migrationId': p['migrationId'],
                'captureId': p['captureId'],
                'bindingId': matches.single['bindingId'],
                'sourceInventoryRoot': p['sourceInventoryRoot'],
              }).toString()) {
        throw const FormatException('crypto_migration_frozen_tag');
      }
      await context.codec.verifyWire(
        serverId: command['serverId'],
        wire: {
          ...record,
          'revision': 1,
          'sequence': 1,
          'authorization': {
            'recordProof': proof,
            'batchCommitment': p['batch']['commitment'],
          },
        },
        trustedSigningKey: publicKey,
        currentEpoch: true,
      );
    }
    final covered = <String>{};
    for (final raw in p['sourceBindings']) {
      final b = Map<String, dynamic>.from(raw as Map);
      if (b['scopeId'] != scope ||
          b['domain'] != domain ||
          !covered.add(b['recordProofHash']) ||
          !hashes.contains(b['recordProofHash'])) {
        throw const FormatException('crypto_migration_frozen_candidate');
      }
      final captured = await context.database.rows(
        'SELECT binding FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id=?',
        [context.partition, coldArchive.capture.captureId, b['bindingId']],
      );
      if (captured.length != 1) {
        throw const CryptoAuthorityPending(
          'crypto_migration_cold_source_pending',
        );
      }
      final sourceBinding = CryptoCaptureBinding.fromJson(
        jsonDecode(captured.single['binding'] as String),
      );
      if (sourceBinding.scopeId != scope || sourceBinding.domain != domain) {
        throw const FormatException('crypto_migration_frozen_candidate');
      }
      for (final hash in b['companionProofHashes'] as List) {
        if (!covered.add(hash) || !hashes.contains(hash)) {
          throw const FormatException('crypto_migration_frozen_candidate');
        }
      }
    }
    if (covered.length != hashes.length ||
        !coldArchive.capture.receiptSelections.any(
          (s) => s['scopeId'] == scope && s['domain'] == domain,
        )) {
      throw const FormatException('crypto_migration_frozen_candidate');
    }
    return VerifiedCryptoMigrationStageCandidate._(
      scope!,
      domain!,
      head!,
      await context.codec.digest(authorization),
      coldArchive.capture.captureId,
      coldArchive.sourceInventoryRoot,
    );
  }

  /// A foreign owner's task is a signed dependency, never part of this
  /// reader's private FILE comparison. Its exact two-proof batch and complete
  /// typed witness are checked by the same canonical verifier below.
  Future<List<CryptoProjectionRecord>> verifyTaskDependency({
    required String migrationId,
    required String scopeId,
    required String taskWireId,
    required Map<String, dynamic> authorization,
    String? expectedTaskHash,
    String? expectedIntentHash,
    CryptoMigrationCandidate? preparing,
  }) async {
    if (preparing != null) {
      if (!preparing.isFor(context.access, scopeId) ||
          preparing.migrationId != migrationId) {
        throw const FormatException('crypto_migration_task_dependency');
      }
    } else {
      await context.access.requireReadOnlyFrozenScope(scopeId);
    }
    final head = preparing?.head ?? await context.access.currentHead(scopeId),
        decoded = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
              as Map,
        ),
        p = Map<String, dynamic>.from(decoded['payload'] as Map),
        batch = Map<String, dynamic>.from(p['batch'] as Map),
        proofs = (batch['records'] as List).cast<Map>();
    if (decoded.length != 8 ||
        decoded['version'] != 2 ||
        decoded['operation'] != 'crypto2.migration.recordsStage' ||
        decoded['signer'] != 'device' ||
        decoded['serverId'] !=
            context.account.directory.session.profile.serverId ||
        p.length != 6 ||
        p['captureVersion'] != 3 ||
        p['migrationId'] != migrationId ||
        proofs.length != 2 ||
        (p['sourceBindings'] as List).length != 1 ||
        head.member(decoded['accountId'])['role'] != 'owner') {
      throw const FormatException('crypto_migration_task_dependency');
    }
    final binding = Map<String, dynamic>.from(
          (p['sourceBindings'] as List).single,
        ),
        byType = <String, Map<String, dynamic>>{},
        hashes = <String, String>{};
    for (final proof in proofs) {
      final body = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      final type = body['type'];
      if (!const {'task', 'taskDerivationIntent'}.contains(type) ||
          byType.containsKey(type) ||
          body['scopeId'] != scopeId ||
          body['domain'] != 'content' ||
          body['membershipHeadHash'] != head.headHash) {
        throw const FormatException('crypto_migration_task_dependency');
      }
      byType[type] = body;
      hashes[type] = await context.codec.digest(
        Map<String, dynamic>.from(proof),
      );
    }
    if (byType['task']?['id'] != taskWireId ||
        binding['recordProofHash'] != hashes['task'] ||
        (binding['companionProofHashes'] as List).length != 1 ||
        (binding['companionProofHashes'] as List).single !=
            hashes['taskDerivationIntent'] ||
        expectedTaskHash != null && hashes['task'] != expectedTaskHash ||
        expectedIntentHash != null &&
            hashes['taskDerivationIntent'] != expectedIntentHash) {
      throw const FormatException('crypto_migration_task_dependency');
    }
    // Authenticate the owner and the complete task/intent projection BEFORE
    // trusting any witness coordinate or downloading its ciphertext.
    final author = await context.access.currentMemberDirectory(
          scopeId,
          head.headHash,
          decoded['accountId'],
        ),
        owner = head.member(decoded['accountId']);
    if (author.deviceSnapshotHash != owner['deviceSnapshotHash'] ||
        author.identityEpochId != owner['identityEpochId']) {
      throw const CryptoAuthorityPending('crypto_migration_authority_changed');
    }
    final signingKey = cryptoBase64(
      author.activeDevice(decoded['deviceId'])['signingKeyBase64'],
      length: 32,
    );
    context.codec.crypto.verifyDomain(
      authorization,
      signingKey,
      'JivieE2EE/v2\n',
    );
    final earlyKey = preparing == null
        ? await context.access.getScopeKey(scopeId, 'content', head.epoch)
        : await preparing.key('content');
    try {
      for (final proof in proofs) {
        final body = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
        );
        await context.codec.verifyWire(
          serverId: decoded['serverId'],
          wire: {
            ...body,
            'revision': 1,
            'sequence': 1,
            'authorization': {
              'recordProof': proof,
              'batchCommitment': batch['commitment'],
            },
          },
          trustedSigningKey: signingKey,
          currentEpoch: true,
        );
      }
      final expected = context.codec.expectedProjectionDigests(
            record: byType['task']!,
            commitment: Map<String, dynamic>.from(batch['commitment'] as Map),
            contentKey: earlyKey.key,
          ),
          actual = hashes.values.toList()..sort();
      if (CryptoInventoryJson.canonical(expected) !=
          CryptoInventoryJson.canonical(actual)) {
        throw const FormatException('crypto_migration_stage_coverage');
      }
    } finally {
      earlyKey.release();
    }
    final descriptor = Map<String, dynamic>.from(binding['witness'] as Map),
        witnessContext = CryptoMigrationWitnessContext(
          Map<String, dynamic>.from(descriptor['context'] as Map),
        );
    if (witnessContext.value['accountId'] != decoded['accountId'] ||
        witnessContext.value['migrationId'] != migrationId ||
        witnessContext.value['captureId'] != p['captureId'] ||
        witnessContext.value['sourceInventoryRoot'] !=
            p['sourceInventoryRoot'] ||
        witnessContext.value['scopeId'] != scopeId ||
        witnessContext.value['domain'] != 'content' ||
        witnessContext.value['wireId'] != taskWireId ||
        witnessContext.value['type'] != 'task') {
      throw const FormatException('crypto_migration_task_dependency');
    }
    final witness = CryptoMigrationWitness(
      database: context.db,
      partition: context.partition,
      crypto: context.codec.crypto,
    );
    await CryptoMigrationWitnessTransport(
      read: context.account.directory.call,
    ).download(
      consumer: witness,
      context: witnessContext,
      descriptor: descriptor,
    );
    final key = preparing == null
        ? await context.access.getScopeKey(scopeId, 'content', head.epoch)
        : await preparing.key('content');
    late Map<String, dynamic> opened;
    try {
      opened = await witness.open(
        context: witnessContext,
        descriptor: descriptor,
        domainKey: key.key,
      );
    } finally {
      key.release();
    }
    final sourceContext = CryptoCaptureSourceContext.fromJson(
      Map<String, dynamic>.from(opened['context'] as Map),
    );
    if (sourceContext.sourceTable != 'familyhub_records' ||
        sourceContext.scopeId != scopeId ||
        sourceContext.domain != 'content' ||
        sourceContext.accountId != decoded['accountId'] ||
        sourceContext.captureId != p['captureId'] ||
        sourceContext.migrationId != migrationId) {
      throw const FormatException('crypto_migration_task_dependency');
    }
    final original = await CryptoMigrationRecordSource.decode(
      table: sourceContext.sourceTable,
      domain: 'content',
      row: Map<String, dynamic>.from(opened['typedRow'] as Map),
      serverId: context.account.directory.session.profile.serverId,
      reservedId: context.reservedRecordId,
    );
    if (original.type != 'task' ||
        original.scopeId != scopeId ||
        context
                .address(scopeId, 'content', 'task', original.canonicalId)
                .wireId !=
            taskWireId) {
      throw const FormatException('crypto_migration_task_dependency');
    }
    return _verify(
      migrationId: migrationId,
      authorization: authorization,
      taskDependency: _TaskDependency(
        await context.codec.digest(authorization),
        scopeId,
        head.headHash,
        preparing,
      ),
      capturedBinding: (_) async => witnessContext.binding,
      openWitness: (_) async => opened,
      source: (_) async => original,
    );
  }

  Future<List<CryptoProjectionRecord>> verify({
    required String migrationId,
    required Map<String, dynamic> authorization,
    VerifiedCryptoCaptureArchive? coldArchive,
    VerifiedCryptoMigrationStageCandidate? frozenCandidate,
    Future<CryptoCaptureBinding> Function(Map<String, dynamic>)?
    capturedBinding,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? openWitness,
    required Future<CryptoMigrationRecordSource> Function(Map<String, dynamic>)
    source,
  }) => _verify(
    migrationId: migrationId,
    authorization: authorization,
    coldArchive: coldArchive,
    frozenCandidate: frozenCandidate,
    capturedBinding: capturedBinding,
    openWitness: openWitness,
    source: source,
  );

  Future<List<CryptoProjectionRecord>> _verify({
    required String migrationId,
    required Map<String, dynamic> authorization,
    VerifiedCryptoCaptureArchive? coldArchive,
    VerifiedCryptoMigrationStageCandidate? frozenCandidate,
    _TaskDependency? taskDependency,
    Future<CryptoCaptureBinding> Function(Map<String, dynamic> binding)?
    capturedBinding,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> binding)?
    openWitness,
    required Future<CryptoMigrationRecordSource> Function(
      Map<String, dynamic> binding,
    )
    source,
  }) async {
    final decoded = CryptoJson.decode(
      cryptoBase64(authorization['commandBase64']),
    );
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 8 ||
        decoded['version'] != 2 ||
        decoded['operation'] != 'crypto2.migration.recordsStage' ||
        decoded['signer'] != 'device' ||
        decoded['serverId'] !=
            context.account.directory.session.profile.serverId ||
        ![
          'requestId',
          'accountId',
          'deviceId',
        ].every((k) => isCryptoCanonicalUuid(decoded[k]))) {
      throw const FormatException('crypto_migration_stage_authorization');
    }
    final payload = decoded['payload'];
    final captured = payload is Map && payload['captureVersion'] == 3;
    if (payload is! Map ||
        payload.length != (captured ? 6 : 4) ||
        payload['migrationId'] != migrationId ||
        (captured
            ? payload['sourceInventoryRoot'] is! String
            : payload['inventoryHash'] is! String) ||
        payload['sourceBindings'] is! List ||
        payload['batch'] is! Map) {
      throw const FormatException('crypto_migration_stage_authorization');
    }
    if (captured &&
        taskDependency == null &&
        (coldArchive == null ||
            frozenCandidate == null ||
            frozenCandidate.authorizationHash !=
                await context.codec.digest(authorization) ||
            frozenCandidate.captureId != coldArchive.capture.captureId ||
            frozenCandidate.sourceInventoryRoot !=
                coldArchive.sourceInventoryRoot ||
            capturedBinding == null ||
            openWitness == null ||
            coldArchive.capture.captureId != payload['captureId'] ||
            coldArchive.capture.migrationId != migrationId ||
            coldArchive.sourceInventoryRoot !=
                payload['sourceInventoryRoot'])) {
      throw const CryptoAuthorityPending(
        'crypto_migration_cold_source_pending',
      );
    }
    if (taskDependency != null &&
        (!captured ||
            taskDependency.hash != await context.codec.digest(authorization) ||
            capturedBinding == null ||
            openWitness == null)) {
      throw const FormatException('crypto_migration_task_dependency');
    }
    final batch = payload['batch'] as Map, proofs = batch['records'];
    if (proofs is! List ||
        proofs.isEmpty ||
        proofs.length > 32 ||
        batch['commitment'] is! Map ||
        payload['sourceBindings'].isEmpty ||
        payload['sourceBindings'].length > 32) {
      throw const FormatException('crypto_migration_stage_authorization');
    }
    final first = CryptoJson.decode(
      cryptoBase64((proofs.first as Map)['commandBase64']),
    );
    if (first is! Map<String, dynamic>) {
      throw const FormatException('crypto_migration_stage_authorization');
    }
    context.codec.validateUntrustedRecord(first);
    if (captured &&
        (first['scopeId'] !=
                (taskDependency?.scope ?? frozenCandidate!.scopeId) ||
            first['domain'] !=
                (taskDependency == null
                    ? frozenCandidate!.domain
                    : 'content') ||
            first['membershipHeadHash'] !=
                (taskDependency?.head ?? frozenCandidate!.headHash))) {
      throw const FormatException('crypto_migration_frozen_candidate');
    }
    final head =
        taskDependency?.preparing?.head ??
        await context.access.currentHead(first['scopeId'], online: true);
    final member = head.member(decoded['accountId']);
    if (first['domain'] == 'finance' && member['financeRole'] == 'none') {
      throw const FormatException('crypto_migration_contributor_role');
    }
    final author = await context.access.currentMemberDirectory(
      head.scopeId,
      head.headHash,
      decoded['accountId'],
    );
    if (author.deviceSnapshotHash != member['deviceSnapshotHash'] ||
        author.identityEpochId != member['identityEpochId']) {
      throw const CryptoAuthorityPending('crypto_migration_authority_changed');
    }
    final device = author.activeDevice(decoded['deviceId']);
    context.codec.crypto.verifyDomain(
      authorization,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      'JivieE2EE/v2\n',
    );
    final values = <String, CryptoProjectionRecord>{};
    final hashes = <String>[];
    final key = taskDependency?.preparing == null
        ? await context.access.getScopeKey(
            head.scopeId,
            first['domain'],
            head.epoch,
          )
        : await taskDependency!.preparing!.key('content');
    try {
      for (final raw in proofs) {
        final proof = Map<String, dynamic>.from(raw as Map);
        final body = CryptoJson.decode(cryptoBase64(proof['commandBase64']));
        if (body is! Map<String, dynamic>) {
          throw const FormatException('crypto_migration_stage_authorization');
        }
        context.codec.validateUntrustedRecord(body);
        if (body['scopeId'] != head.scopeId ||
            body['domain'] != first['domain'] ||
            body['membershipHeadHash'] != head.headHash ||
            body['epoch'] != head.epoch ||
            body['accessRevision'] != head.accessRevision ||
            body['accountId'] != decoded['accountId'] ||
            body['deviceId'] != decoded['deviceId'] ||
            body['batchId'] != batch['batchId'] ||
            body['expectedRevision'] != 0 ||
            body['previousRecordHash'] != '0' * 64) {
          throw const FormatException('crypto_migration_stage_binding');
        }
        if (captured) {
          final digest = await context.codec.digest(proof);
          final matches = (payload['sourceBindings'] as List)
              .cast<Map>()
              .where(
                (b) =>
                    b['recordProofHash'] == digest ||
                    (b['companionProofHashes'] as List).contains(digest),
              )
              .toList();
          if (matches.length != 1 ||
              CryptoJson.encode(
                    body['metadata']['migrationOrigin'],
                  ).toString() !=
                  CryptoJson.encode({
                    'version': 3,
                    'migrationId': payload['migrationId'],
                    'captureId': payload['captureId'],
                    'bindingId': matches.single['bindingId'],
                    'sourceInventoryRoot': payload['sourceInventoryRoot'],
                  }).toString()) {
            throw const FormatException('crypto_migration_frozen_tag');
          }
        }
        final wire = {
          ...body,
          'revision': 1,
          'sequence': 1,
          'authorization': {
            'recordProof': proof,
            'batchCommitment': batch['commitment'],
          },
        };
        final record = await context.codec.verifyWire(
          serverId: decoded['serverId'],
          wire: wire,
          trustedSigningKey: cryptoBase64(
            device['signingKeyBase64'],
            length: 32,
          ),
          currentEpoch: true,
        );
        final hash = await context.codec.digest(proof);
        if (values.containsKey(hash)) {
          throw const FormatException('crypto_migration_stage_duplicate');
        }
        final plaintext = context.codec.openVerified(record, key.key);
        values[hash] = CryptoProjectionRecord(
          wire,
          record,
          plaintext,
          historyBasis: 'migrationCapturedSource',
          batchKey: await context.codec.digest(
            Map<String, dynamic>.from(batch['commitment'] as Map),
          ),
        );
        hashes.add(hash);
      }
      hashes.sort();
      final expected = context.codec.expectedProjectionDigests(
        record: first,
        commitment: Map<String, dynamic>.from(batch['commitment'] as Map),
        contentKey: key.key,
      );
      if (CryptoInventoryJson.canonical(hashes) !=
          CryptoInventoryJson.canonical(expected)) {
        throw const FormatException('crypto_migration_stage_coverage');
      }
      final covered = <String>{};
      for (final rawBinding in payload['sourceBindings']) {
        final binding = Map<String, dynamic>.from(rawBinding as Map);
        var original = await source(binding);
        if (captured && original.type == 'scopeMetadata') {
          original = original.withScopeBaseline(
            await CryptoMigrationScopeBaseline(
              database: context.database,
              partition: context.partition,
              captureId: payload['captureId'],
              accountId: decoded['accountId'],
            ).load(original.scopeId),
          );
        }
        Map<String, dynamic>? detached;
        if (captured && original.table != 'familyhub_scopes') {
          final expected = await capturedBinding!(binding);
          final descriptor = Map<String, dynamic>.from(
            binding['witness'] as Map,
          );
          final witnessContext = CryptoMigrationWitnessContext(
            Map<String, dynamic>.from(descriptor['context'] as Map),
          );
          if (CryptoInventoryJson.canonical(witnessContext.binding.toJson()) !=
                  CryptoInventoryJson.canonical(expected.toJson()) ||
              witnessContext.value['sourceInventoryRoot'] !=
                  payload['sourceInventoryRoot']) {
            throw const FormatException('crypto_migration_witness_binding');
          }
          detached = await openWitness!(binding);
        }
        final primary = values[binding['recordProofHash']];
        if (primary == null || !covered.add(binding['recordProofHash'])) {
          throw const FormatException('crypto_migration_stage_coverage');
        }
        final address = cryptoRecordAddressFromMetadata(primary.record);
        if (original.table == 'familyhub_scopes' &&
            member['manageKeys'] != true) {
          throw const FormatException(
            'crypto_migration_scope_manager_required',
          );
        }
        final companions = (binding['companionProofHashes'] as List)
            .cast<String>();
        final expectedBinding = captured
            ? <String, dynamic>{
                'bindingId': binding['bindingId'],
                'scopeId': original.scopeId,
                'sourceKind': address.sourceKind,
                'canonicalId': address.canonicalId,
                'wireId': address.wireId,
                'domain': original.domain,
                'type': original.type,
                'legacyRevision': original.legacyRevision,
                'recordProofHash': binding['recordProofHash'],
                'companionProofHashes': companions,
                'witness': binding['witness'],
                'objects': binding['objects'],
              }
            : original.binding(
                address,
                binding['recordProofHash'],
                companionProofHashes: companions,
              );
        if (CryptoInventoryJson.canonical(binding) !=
                CryptoInventoryJson.canonical(expectedBinding) ||
            captured &&
                original.type == 'scopeMetadata' &&
                binding['witness'] != null ||
            primary.record['deleted'] != original.deleted) {
          throw const FormatException('crypto_migration_source_binding');
        }
        if (primary.plaintext != null) {
          final envelope = jsonDecode(utf8.decode(primary.plaintext!));
          final marker = envelope is Map ? envelope['payload'] : null;
          final derivesSource =
              captured &&
              marker is Map &&
              (marker.length == 2 ||
                  marker.length == 3 &&
                      marker.containsKey('accountChoiceWitness') &&
                      CryptoMigrationCapturedChoices.needed(original)) &&
              marker['migrationPayload'] == 3 &&
              marker['bindingId'] == binding['bindingId'];
          var expectedRaw = original.rawPayload == null
              ? null
              : <String, dynamic>{
                  ...original.rawPayload!,
                  if (captured &&
                      original.type == 'attachment' &&
                      (binding['objects'] as List).length == 1)
                    'cryptoBlob': binding['objects'][0]['blob'],
                };
          if (captured && original.type == 'idea' && expectedRaw != null) {
            expectedRaw = decorateCryptoMigrationIdea(
              original.rawPayload!,
              binding['objects'] as List,
              CryptoMigrationWitnessContext(
                Map<String, dynamic>.from(binding['witness']['context'] as Map),
              ),
            );
          }
          if (captured &&
              CryptoMigrationCapturedChoices.needed(original) &&
              envelope is Map) {
            expectedRaw = await CryptoMigrationCapturedChoices.expectedPrimary(
              original,
              primary.record,
              Map<String, dynamic>.from(envelope),
              context.reservedRecordId,
            );
          }
          if (envelope is! Map ||
              envelope.length !=
                  (captured || original.table == 'familyhub_scopes' ? 3 : 4) ||
              envelope['format'] != 2 ||
              CryptoInventoryJson.canonical(envelope['identity']) !=
                  CryptoInventoryJson.canonical(address.identity) ||
              !derivesSource &&
                  CryptoBusinessJson.canonical(envelope['payload']) !=
                      CryptoBusinessJson.canonical(expectedRaw)) {
            throw const FormatException('crypto_migration_business_parity');
          }
        } else if (!original.deleted) {
          throw const FormatException('crypto_migration_business_parity');
        }
        final origin = <String, dynamic>{
          ...original.binding(
            address,
            binding['recordProofHash'],
            companionProofHashes: companions,
          ),
          if (captured) ...binding,
          if (captured) 'captureVersion': 3,
        };
        final semantic = await verifyCryptoMigrationWitness(
          record: primary.record,
          origin: origin,
          detachedWitness: detached,
          recordProofHash: binding['recordProofHash'],
          envelope: primary.plaintext == null
              ? null
              : Map<String, dynamic>.from(
                  jsonDecode(utf8.decode(primary.plaintext!)) as Map,
                ),
          reservedId: context.reservedRecordId,
        );
        var expectedSemantic = original.rawPayload == null
            ? null
            : <String, dynamic>{
                ...original.rawPayload!,
                if (captured &&
                    original.type == 'attachment' &&
                    (binding['objects'] as List).length == 1)
                  'cryptoBlob': binding['objects'][0]['blob'],
              };
        if (captured && original.type == 'idea' && expectedSemantic != null) {
          expectedSemantic = decorateCryptoMigrationIdea(
            original.rawPayload!,
            binding['objects'] as List,
            CryptoMigrationWitnessContext(
              Map<String, dynamic>.from(binding['witness']['context'] as Map),
            ),
          );
        }
        if (captured && CryptoMigrationCapturedChoices.needed(original)) {
          expectedSemantic =
              await CryptoMigrationCapturedChoices.expectedPrimary(
                original,
                primary.record,
                Map<String, dynamic>.from(
                  jsonDecode(utf8.decode(primary.plaintext!)),
                ),
                context.reservedRecordId,
              );
        }
        if (CryptoBusinessJson.canonical(semantic) !=
            CryptoBusinessJson.canonical(expectedSemantic)) {
          throw const FormatException('crypto_migration_business_parity');
        }
        if (captured && original.type == 'attachment' && !original.deleted) {
          final descriptor = Map<String, dynamic>.from(
            binding['witness'] as Map,
          );
          final bytes =
              await CryptoMigrationFileObject(
                database: context.database,
                partition: context.partition,
                crypto: context.codec.crypto,
              ).open(
                transport: CryptoMigrationWitnessTransport(
                  queue: context.queue,
                  read: context.account.directory.call,
                ),
                context: CryptoMigrationWitnessContext(
                  Map<String, dynamic>.from(descriptor['context'] as Map),
                ),
                object: Map<String, dynamic>.from(
                  (binding['objects'] as List).single as Map,
                ),
                domainKey: key.key,
                plainSize: original.rawPayload!['size'],
                plainSha256: original.rawPayload!['sha256'],
              );
          bytes.fillRange(0, bytes.length, 0);
        }
        values[binding['recordProofHash']] = CryptoProjectionRecord(
          primary.wire,
          primary.record,
          primary.plaintext,
          historyBasis: primary.historyBasis,
          batchKey: primary.batchKey,
          migrationOrigin: Map<String, dynamic>.unmodifiable(origin),
          migrationWitness: detached,
        );
        for (final hash in companions) {
          final companion = values[hash];
          if (companion == null ||
              !covered.add(hash) ||
              companion.plaintext == null ||
              companion.record['operationId'] !=
                  primary.record['operationId']) {
            throw const FormatException('crypto_migration_companion_binding');
          }
          if (captured &&
              CryptoMigrationCapturedChoices.needed(original) &&
              companion.record['type'] == 'financeAccountChoice') {
            final envelope = Map<String, dynamic>.from(
              jsonDecode(utf8.decode(companion.plaintext!)),
            );
            final raw = Map<String, dynamic>.from(envelope['payload']);
            final exactBinding = await capturedBinding!(binding);
            final derivedHash =
                await CryptoMigrationCapturedChoices.verifyCompanion(
                  context,
                  raw: raw,
                  record: companion.record,
                  sourceBinding: {
                    ...binding,
                    'sourceCommitment': exactBinding.sourceCommitment,
                  },
                  head: head,
                );
            final child = await CryptoMigrationColdSource.load(
              context,
              coldArchive!,
              binding['bindingId'],
            );
            await CryptoFinanceChoiceCapture.verifyTargetSelection(
              raw,
              childSource: child,
              childArchive: coldArchive,
              exactTargetHead: head,
              reservedId: context.reservedRecordId,
            );
            final a = cryptoRecordAddressFromMetadata(companion.record);
            final companionOrigin = <String, dynamic>{
              ...origin,
              'sourceKind': a.sourceKind,
              'canonicalId': a.canonicalId,
              'wireId': a.wireId,
              'type': companion.record['type'],
              'recordProofHash': hash,
              'materializationRole': 'financeAccountChoice',
              'derivedPayloadHash': derivedHash,
            };
            await verifyCryptoMigrationWitness(
              record: companion.record,
              origin: companionOrigin,
              recordProofHash: hash,
              envelope: envelope,
              reservedId: context.reservedRecordId,
            );
            values[hash] = CryptoProjectionRecord(
              companion.wire,
              companion.record,
              companion.plaintext,
              historyBasis: companion.historyBasis,
              batchKey: companion.batchKey,
              migrationOrigin: companionOrigin,
            );
            continue;
          }
          if (captured &&
              original.type == 'financeEntry' &&
              companion.record['type'] == 'taskDerivationResolution') {
            final companionAddress = cryptoRecordAddressFromMetadata(
              companion.record,
            );
            final companionOrigin = <String, dynamic>{
              ...origin,
              'sourceKind': companionAddress.sourceKind,
              'canonicalId': companionAddress.canonicalId,
              'wireId': companionAddress.wireId,
              'type': companion.record['type'],
              'recordProofHash': hash,
              'primaryRecordProofHash': binding['recordProofHash'],
              'materializationRole': 'taskDerivationResolution',
            };
            await verifyCryptoMigrationWitness(
              record: companion.record,
              origin: companionOrigin,
              detachedWitness: detached,
              recordProofHash: hash,
              envelope: Map<String, dynamic>.from(
                jsonDecode(utf8.decode(companion.plaintext!)) as Map,
              ),
              reservedId: context.reservedRecordId,
            );
            values[hash] = CryptoProjectionRecord(
              companion.wire,
              companion.record,
              companion.plaintext,
              historyBasis: companion.historyBasis,
              batchKey: companion.batchKey,
              migrationOrigin: companionOrigin,
              migrationWitness: detached,
            );
            continue;
          }
          if (original.type != 'task' ||
              companion.record['type'] != 'taskDerivationIntent') {
            throw const FormatException('crypto_migration_companion_binding');
          }
          final id = await context.reservedRecordId(
            original.scopeId,
            'taskDerivation:${original.canonicalId}',
          );
          final expectedAddress = context.address(
            original.scopeId,
            'content',
            'taskDerivationIntent',
            id,
          );
          final raw = original.rawPayload;
          final expected = {
            'version': 1,
            'taskId': original.canonicalId,
            'targetOperationId': primary.record['operationId'],
            'targetCryptoRevision': 1,
            'deadlineEpoch': raw?['dueAt'] == null
                ? null
                : DateTime.parse(
                        raw!['dueAt'],
                      ).toUtc().millisecondsSinceEpoch ~/
                      1000,
            'completed': raw?['isCompleted'] ?? false,
            'deleted': original.deleted,
          };
          final envelope = jsonDecode(utf8.decode(companion.plaintext!)) as Map;
          if (companion.record['id'] != expectedAddress.wireId ||
              envelope['format'] != 2 ||
              CryptoInventoryJson.canonical(envelope['identity']) !=
                  CryptoInventoryJson.canonical(expectedAddress.identity) ||
              CryptoBusinessJson.canonical(envelope['payload']) !=
                  CryptoInventoryJson.canonical(expected)) {
            throw const FormatException('crypto_migration_companion_binding');
          }
          final companionOrigin = <String, dynamic>{
            ...origin,
            'sourceKind': expectedAddress.sourceKind,
            'canonicalId': expectedAddress.canonicalId,
            'wireId': expectedAddress.wireId,
            'type': companion.record['type'],
            'recordProofHash': hash,
            'materializationRole': 'taskDerivationIntent',
          };
          await verifyCryptoMigrationWitness(
            record: companion.record,
            origin: companionOrigin,
            detachedWitness: detached,
            recordProofHash: hash,
            envelope: Map<String, dynamic>.from(envelope),
            reservedId: context.reservedRecordId,
          );
          values[hash] = CryptoProjectionRecord(
            companion.wire,
            companion.record,
            companion.plaintext,
            historyBasis: companion.historyBasis,
            batchKey: companion.batchKey,
            migrationOrigin: companionOrigin,
            migrationWitness: detached,
          );
        }
      }
      if (covered.length != values.length) {
        throw const FormatException('crypto_migration_stage_coverage');
      }
      return values.values.toList(growable: false);
    } catch (_) {
      for (final value in values.values) {
        value.plaintext?.fillRange(0, value.plaintext!.length, 0);
      }
      rethrow;
    } finally {
      key.release();
    }
  }
}
