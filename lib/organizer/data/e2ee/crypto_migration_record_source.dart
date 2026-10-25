import 'crypto_migration_captured_choices.dart';
import 'crypto_migration_idea_payload.dart';
import 'crypto_finance_topology.dart';
import 'dart:convert';

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_inventory_json.dart';
import 'crypto_business_json.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'crypto_capture_v3.dart';
import 'crypto_migration_witness.dart';
import 'crypto_migration_file_object.dart';
import 'crypto_migration_payments.dart';

/// Exact source row plus its separate wire coordinate. The raw typed row remains
/// the parity source; model serialization never reconstructs its unknown fields.
class CryptoMigrationRecordSource {
  CryptoMigrationRecordSource._({
    required this.table,
    required this.domain,
    required this.scopeId,
    required this.sourceId,
    required this.canonicalId,
    required this.type,
    required this.legacyRevision,
    required this.deleted,
    required this.rowHash,
    required this.rawPayload,
    required this.typedRow,
  });
  final String table, domain, scopeId, sourceId, canonicalId, type, rowHash;
  final int legacyRevision;
  final bool deleted;
  final Map<String, dynamic>? rawPayload;
  final Map<String, dynamic> typedRow;

  /// Transport authorship is retained separately from the business payload.
  /// These values become authoritative only after the caller verifies the
  /// captured-row hash and its migration binding; the importer is not author.
  String? get _creatorColumn => switch (table) {
    'familyhub_records' ||
    'familyhub_finance_records' ||
    'familyhub_tables' => 'created_by',
    'familyhub_attachments' => 'owner_account_id',
    _ => null,
  };
  bool get hasCapturedCreator =>
      _creatorColumn != null && typedRow.containsKey(_creatorColumn);
  String? get createdByAccountId => _accountColumn(_creatorColumn);

  String? get updatedByAccountId => _accountColumn(
    const {'familyhub_records', 'familyhub_finance_records'}.contains(table)
        ? 'updated_by'
        : null,
  );

  String? _accountColumn(String? name) {
    if (name == null || !typedRow.containsKey(name)) return null;
    final cell = typedRow[name];
    if (cell is! Map ||
        cell.length != 2 ||
        cell['type'] is! String ||
        !cell.containsKey('valueBase64')) {
      throw const FormatException('crypto_migration_source_author');
    }
    final encoded = cell['valueBase64'];
    if (encoded == null) return null;
    if (encoded is! String) {
      throw const FormatException('crypto_migration_source_author');
    }
    final bytes = base64Decode(encoded);
    if (base64Encode(bytes) != encoded) {
      throw const FormatException('crypto_migration_source_author');
    }
    final account = utf8.decode(bytes);
    if (account.isEmpty)
      return null; // Existing account-deletion anonymization.
    if (!isCryptoCanonicalUuid(account)) {
      throw const FormatException('crypto_migration_source_author');
    }
    return account;
  }

  CryptoMigrationRecordSource withScopeBaseline(Map<String, dynamic> baseline) {
    if (table != 'familyhub_scopes' ||
        type != 'scopeMetadata' ||
        rawPayload == null) {
      throw const FormatException('crypto_migration_scope_baseline_source');
    }
    return CryptoMigrationRecordSource._(
      table: table,
      domain: domain,
      scopeId: scopeId,
      sourceId: sourceId,
      canonicalId: canonicalId,
      type: type,
      legacyRevision: legacyRevision,
      deleted: deleted,
      rowHash: rowHash,
      typedRow: typedRow,
      rawPayload: {...rawPayload!, ...baseline},
    );
  }

  static Future<CryptoMigrationRecordSource> decode({
    required String table,
    required String domain,
    required Map<String, dynamic> row,
    String? serverId,
    required Future<String> Function(String scopeId, String namespace)
    reservedId,
  }) async {
    String? text(String column) {
      final cell = row[column];
      if (cell is! Map ||
          cell.length != 2 ||
          cell['type'] is! String ||
          !cell.containsKey('valueBase64')) {
        throw const FormatException('crypto_migration_source_cell');
      }
      final value = cell['valueBase64'];
      if (value == null) return null;
      if (value is! String) {
        throw const FormatException('crypto_migration_source_cell');
      }
      final bytes = base64Decode(value);
      if (base64Encode(bytes) != value) {
        throw const FormatException('crypto_migration_source_cell');
      }
      return utf8.decode(bytes);
    }

    int integer(String column) {
      final value = text(column);
      if (value == null || !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(value)) {
        throw const FormatException('crypto_migration_source_integer');
      }
      final number = int.tryParse(value);
      if (number == null || number > 9007199254740991) {
        throw const FormatException('crypto_migration_source_integer');
      }
      return number;
    }

    if (!['content', 'finance'].contains(domain)) {
      throw const FormatException('crypto_migration_source_domain');
    }
    if (const {
      'familyhub_payment_events',
      'familyhub_payment_projections',
      'familyhub_payment_cash',
    }.contains(table)) {
      if (domain != 'finance') {
        throw const FormatException('crypto_migration_source_domain');
      }
      final payment = decodeCryptoMigrationPaymentSource(
        table: table,
        row: row,
      );
      return CryptoMigrationRecordSource._(
        table: table,
        domain: domain,
        scopeId: payment.scopeId,
        sourceId: payment.canonicalId,
        canonicalId: payment.canonicalId,
        type: payment.type,
        legacyRevision: payment.legacyRevision,
        deleted: false,
        rowHash: await CryptoInventoryJson.hash(row),
        rawPayload: payment.rawPayload,
        typedRow: Map<String, dynamic>.unmodifiable(row),
      );
    }
    final sourceId = text('id'),
        scopeId = table == 'familyhub_scopes' ? sourceId : text('scope_id');
    if (!isCryptoCanonicalUuid(sourceId) || !isCryptoCanonicalUuid(scopeId)) {
      throw const FormatException('crypto_migration_source_identity');
    }
    late String canonicalId = sourceId as String, type;
    late int revision;
    var deleted = false;
    Map<String, dynamic>? payload;
    if (['familyhub_records', 'familyhub_finance_records'].contains(table)) {
      type = text('type') ?? '';
      revision = integer('revision');
      if (revision < 1) {
        throw const FormatException('crypto_migration_source_revision');
      }
      final removed = integer('deleted');
      if (removed > 1) {
        throw const FormatException('crypto_migration_source_deleted');
      }
      deleted = removed == 1;
      final raw = text('payload');
      // Tombstones retain their original payload in the typed archive, while
      // their authenticated new current record has no decrypted business value.
      if (!deleted) {
        final decoded = raw == null ? null : jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('crypto_migration_source_payload');
        }
        payload = decoded;
      }
      if (cryptoRecordDomain(type) != domain ||
          cryptoRecordSourceKind(type) !=
              (table == 'familyhub_records' ? 'records' : 'finance_records')) {
        throw const FormatException('crypto_migration_source_type');
      }
    } else if (table == 'familyhub_scopes') {
      if (domain != 'content') {
        throw const FormatException('crypto_migration_source_domain');
      }
      canonicalId = await reservedId(scopeId as String, 'scopeMetadata');
      type = 'scopeMetadata';
      revision = integer('metadata_revision');
      final archived = integer('archived');
      if (archived > 1) {
        throw const FormatException('crypto_migration_source_deleted');
      }
      final kind = text('kind'), policy = integer('access_policy_version');
      if (![
            'personal',
            'household',
            'organization',
            'project',
          ].contains(kind) ||
          ![1, 2, 3].contains(policy)) {
        throw const FormatException('crypto_migration_scope_descriptor');
      }
      final parent = text('parent_scope_id') ?? text('organization_id');
      if (parent != null &&
          (!isCryptoCanonicalUuid(parent) ||
              !isCryptoCanonicalUuid(serverId))) {
        throw const FormatException('crypto_migration_scope_descriptor');
      }
      payload = {
        'namespaceVersion': 1,
        'scopeId': scopeId,
        'name': text('name'),
        'address': text('address'),
        'archived': archived == 1,
        'kind': kind,
        'accessPolicyVersion': policy,
        'legacyMetadataRevision': revision,
        'parentScopeToken': parent == null
            ? null
            : await cryptoSha256([
                ...utf8.encode('JivieParentLifecycleScope/v2\n'),
                ...CryptoJson.encode({
                  'version': 2,
                  'serverId': serverId,
                  'scopeId': scopeId,
                  'parentScopeId': parent,
                }),
              ]),
      };
    } else if (table == 'familyhub_tables') {
      if (domain != 'content') {
        throw const FormatException('crypto_migration_source_domain');
      }
      type = 'table';
      revision = integer('revision');
      final removed = integer('deleted');
      if (revision < 1 || removed > 1) {
        throw const FormatException('crypto_migration_source_revision');
      }
      deleted = removed == 1;
      if (!deleted) {
        final cells = jsonDecode(text('cells') ?? 'null');
        if (cells is! Map<String, dynamic>) {
          throw const FormatException('crypto_migration_source_payload');
        }
        payload = {
          'id': sourceId,
          'scopeId': scopeId,
          'title': text('title'),
          'cells': cells,
          'revision': revision,
          'updatedAt': integer('updated_at'),
        };
      }
    } else if (table == 'familyhub_attachments') {
      if (domain != 'content') {
        throw const FormatException('crypto_migration_source_domain');
      }
      type = 'attachment';
      revision = 1; // Immutable metadata has no legacy revision column.
      final removed = integer('deleted'), complete = integer('complete');
      if (removed > 1 || complete > 1) {
        throw const FormatException('crypto_migration_source_deleted');
      }
      deleted = removed == 1;
      if (!deleted && complete == 0) {
        throw const CryptoAuthorityPending('crypto_migration_pending_upload');
      }
      if (!deleted) {
        payload = {
          'id': sourceId,
          'scopeId': scopeId,
          'targetType': text('target_type'),
          'targetId': text('target_id'),
          'name': text('name'),
          'mime': text('mime'),
          'size': integer('size'),
          'sha256': text('sha256'),
          'createdAt': integer('created_at'),
          'complete': true,
          'offset': integer('received'),
        };
      }
    } else {
      // Documents/payment sidecars need their actual blob/semantic adapters.
      // Keeping their exact row and pending state is preferable to publishing a
      // fabricated model or treating an unfinished attachment as complete.
      throw const CryptoAuthorityPending(
        'crypto_migration_source_adapter_pending',
      );
    }
    return CryptoMigrationRecordSource._(
      table: table,
      domain: domain,
      scopeId: scopeId as String,
      sourceId: sourceId!,
      canonicalId: canonicalId,
      type: type,
      legacyRevision: revision,
      deleted: deleted,
      rowHash: await cryptoSha256(CryptoInventoryJson.encode(row)),
      rawPayload: payload,
      typedRow: Map<String, dynamic>.unmodifiable(row),
    );
  }

  Map<String, dynamic> binding(
    CryptoRecordAddress address,
    String proofHash, {
    List<String> companionProofHashes = const [],
  }) {
    if (address.scopeId != scopeId ||
        address.domain != domain ||
        address.type != type ||
        address.canonicalId != canonicalId) {
      throw const FormatException('crypto_migration_source_address');
    }
    return {
      'sourceTable': table,
      'scopeId': scopeId,
      'sourceId': sourceId,
      'sourceKind': address.sourceKind,
      'canonicalId': canonicalId,
      'wireId': address.wireId,
      'domain': domain,
      'type': type,
      'legacyRevision': legacyRevision,
      'sourceRowHash': rowHash,
      'recordProofHash': proofHash,
      'companionProofHashes': companionProofHashes,
    };
  }
}

/// Checks an encrypted captured-source witness against an independently
/// authenticated migration binding. The binding must come from the dedicated
/// stage/cutover verifier, never from the envelope itself.
Future<Map<String, dynamic>?> verifyCryptoMigrationWitness({
  required Map<String, dynamic> record,
  required Map<String, dynamic> origin,
  required String recordProofHash,
  required Map<String, dynamic>? envelope,
  Map<String, dynamic>? detachedWitness,
  void Function(CryptoMigrationRecordSource source)? onVerifiedSource,
  required Future<String> Function(String scopeId, String namespace) reservedId,
}) async {
  final address = cryptoRecordAddressFromMetadata(record);
  final captured = origin['captureVersion'] == 3;
  if (origin['recordProofHash'] != recordProofHash ||
      origin['scopeId'] != address.scopeId ||
      origin['domain'] != address.domain ||
      origin['sourceKind'] != address.sourceKind ||
      origin['canonicalId'] != address.canonicalId ||
      origin['wireId'] != address.wireId ||
      origin['type'] != record['type'] ||
      origin['legacyRevision'] is! int ||
      (origin['legacyRevision'] as int) < 0 ||
      (origin['legacyRevision'] == 0 &&
          (origin['sourceTable'] != 'familyhub_scopes' ||
              record['type'] != 'scopeMetadata'))) {
    throw const FormatException('crypto_migration_witness_binding');
  }
  if (captured && origin['materializationRole'] == 'financeAccountChoice') {
    final raw = envelope?['payload'];
    if (record['type'] != 'financeAccountChoice' ||
        record['domain'] != 'finance' ||
        record['deleted'] != false ||
        record['expectedRevision'] != 0 ||
        record['previousRecordHash'] != '0' * 64 ||
        raw is! Map ||
        origin['derivedPayloadHash'] != await CryptoBusinessJson.hash(raw) ||
        address.canonicalId !=
            await reservedId(address.scopeId, 'financeAccountChoices') ||
        envelope!.length != 3 ||
        envelope['format'] != 2 ||
        CryptoBusinessJson.canonical(envelope['identity']) !=
            CryptoBusinessJson.canonical(address.identity)) {
      throw const FormatException('crypto_account_choices_capture_companion');
    }
    return Map<String, dynamic>.from(raw);
  }
  CryptoCaptureSourceContext? detachedContext;
  if (captured && origin['sourceTable'] != 'familyhub_scopes') {
    if (detachedWitness == null || origin['witness'] is! Map) {
      throw const CryptoAuthorityPending('crypto_migration_witness_pending');
    }
    final descriptor = Map<String, dynamic>.from(origin['witness'] as Map);
    final context = CryptoMigrationWitnessContext(
      Map<String, dynamic>.from(descriptor['context'] as Map),
    );
    detachedContext = CryptoCaptureSourceContext.fromJson(
      Map<String, dynamic>.from(detachedWitness['context'] as Map),
    );
    context.requireSource(detachedContext);
    if (context.value['bindingId'] != origin['bindingId'] ||
        context.value['scopeId'] != record['scopeId'] ||
        context.value['domain'] != record['domain'] ||
        context.value['membershipHeadHash'] != record['membershipHeadHash'] ||
        context.value['epoch'] != record['epoch'] ||
        context.value['accessRevision'] != record['accessRevision'] ||
        context.value['accountId'] != record['accountId'] ||
        detachedContext.sourceTable != origin['sourceTable']) {
      throw const FormatException('crypto_migration_witness_binding');
    }
    await CryptoCaptureV3.verifyWitness(
      binding: context.binding,
      context: detachedContext,
      witness: detachedWitness,
    );
  }
  if (envelope == null) {
    if (record['deleted'] != true) {
      throw const FormatException('crypto_migration_witness_required');
    }
    if (captured) {
      final source = await CryptoMigrationRecordSource.decode(
        table: detachedContext!.sourceTable,
        domain: address.domain,
        row: Map<String, dynamic>.from(detachedWitness!['typedRow'] as Map),
        serverId: record['serverId'],
        reservedId: reservedId,
      );
      if (source.rowHash != origin['sourceRowHash'] ||
          source.sourceId != origin['sourceId'] ||
          source.legacyRevision != origin['legacyRevision'] ||
          !source.deleted ||
          source.type != record['type'] ||
          source.canonicalId != address.canonicalId) {
        throw const FormatException('crypto_migration_business_parity');
      }
      onVerifiedSource?.call(source);
    }
    return null;
  }
  if (origin['sourceTable'] == 'familyhub_scopes' &&
      record['type'] == 'scopeMetadata') {
    // Closed privacy exception: the exact source row (including private owner,
    // parent and unknown SQL fields) stays only in the contributor's archive.
    // The anchored transformation certificate binds this exact record proof;
    // cold parity compares this descriptor against the full private typed row.
    final raw = envelope['payload'];
    final fields = {
      'namespaceVersion',
      'scopeId',
      'name',
      'address',
      'archived',
      'kind',
      'accessPolicyVersion',
      'legacyMetadataRevision',
      'parentScopeToken',
      if (captured) 'financePolicy',
      if (captured &&
          raw is Map &&
          const ['household', 'organization'].contains(raw['kind']))
        'financeTopology',
      if (captured && raw is Map && raw['kind'] == 'organization')
        'leaderAccountIds',
    };
    if (envelope.length != 3 ||
        raw is! Map ||
        raw.length != fields.length ||
        raw.keys.any((key) => !fields.contains(key)) ||
        raw['namespaceVersion'] != 1 ||
        raw['scopeId'] != record['scopeId'] ||
        raw['name'] is! String ||
        (raw['address'] != null && raw['address'] is! String) ||
        raw['archived'] is! bool ||
        ![
          'personal',
          'household',
          'organization',
          'project',
        ].contains(raw['kind']) ||
        ![1, 2, 3].contains(raw['accessPolicyVersion']) ||
        raw['legacyMetadataRevision'] != origin['legacyRevision'] ||
        (raw['parentScopeToken'] != null &&
            (raw['parentScopeToken'] is! String ||
                !RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(raw['parentScopeToken'])))) {
      throw const FormatException('crypto_migration_scope_descriptor');
    }
    if (captured) {
      if (const ['household', 'organization'].contains(raw['kind'])) {
        if (raw['financeTopology'] is! Map) {
          throw const FormatException('crypto_finance_topology_pending');
        }
        await CryptoFinanceTopology.validate(
          Map<String, dynamic>.from(raw['financeTopology']),
          serverId: record['serverId'],
          scopeId: record['scopeId'],
        );
      }
      final policy = raw['financePolicy'];
      if (policy is! Map ||
          policy.length != 5 ||
          !policy.keys.every(
            {
              'enabled',
              'revision',
              'requiredContractVersion',
              'policyHash',
              'grantCount',
            }.contains,
          ) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(
            policy['policyHash'] is String ? policy['policyHash'] : '',
          ) ||
          policy['grantCount'] is! int ||
          policy['grantCount'] < 0 ||
          policy['grantCount'] > 1000000 ||
          policy['enabled'] is! bool ||
          policy['revision'] is! int ||
          policy['revision'] < 0 ||
          policy['revision'] > 9007199254740991 ||
          policy['requiredContractVersion'] is! int ||
          ![1, 2, 3].contains(policy['requiredContractVersion'])) {
        throw const FormatException('crypto_migration_scope_finance_policy');
      }
      if (raw['kind'] == 'organization') {
        final leaders = raw['leaderAccountIds'];
        String? prior;
        if (leaders is! List || leaders.length > 1000) {
          throw const FormatException('crypto_migration_scope_leaders');
        }
        for (final id in leaders) {
          if (!isCryptoCanonicalUuid(id) ||
              prior != null && prior.compareTo(id) >= 0) {
            throw const FormatException('crypto_migration_scope_leaders');
          }
          prior = id;
        }
        if (raw['accessPolicyVersion'] == 3 && leaders.isNotEmpty) {
          throw const FormatException('crypto_migration_scope_leaders');
        }
      }
    }
    return Map<String, dynamic>.from(raw);
  }
  final witness = captured
      ? <String, dynamic>{
          'version': 2,
          'sourceTable': detachedContext!.sourceTable,
          'typedRow': detachedWitness!['typedRow'],
        }
      : envelope['migrationSource'];
  if (envelope.length != (captured ? 3 : 4) ||
      witness is! Map<String, dynamic> ||
      witness.length != 3 ||
      witness['version'] != 2 ||
      witness['sourceTable'] != origin['sourceTable'] ||
      witness['typedRow'] is! Map<String, dynamic>) {
    throw const FormatException('crypto_migration_witness_required');
  }
  final source = await CryptoMigrationRecordSource.decode(
    table: witness['sourceTable'] as String,
    domain: address.domain,
    row: Map<String, dynamic>.from(witness['typedRow'] as Map),
    serverId: record['serverId'] as String,
    reservedId: reservedId,
  );
  if (source.rowHash != origin['sourceRowHash'] ||
      source.sourceId != origin['sourceId'] ||
      source.legacyRevision != origin['legacyRevision']) {
    throw const FormatException('crypto_migration_business_parity');
  }
  final marker = envelope['payload'];
  final derived =
      captured &&
      marker is Map &&
      (marker.length == 2 ||
          marker.length == 3 &&
              marker.containsKey('accountChoiceWitness') &&
              CryptoMigrationCapturedChoices.needed(source)) &&
      marker['migrationPayload'] == 3 &&
      marker['bindingId'] == origin['bindingId'];
  var expectedPayload = source.rawPayload;
  if (captured && CryptoMigrationCapturedChoices.needed(source)) {
    expectedPayload = await CryptoMigrationCapturedChoices.expectedPrimary(
      source,
      record,
      envelope,
      reservedId,
    );
  }
  if (captured) {
    final objects = origin['objects'];
    if (objects is! List ||
        objects.length > (source.type == 'idea' ? 20 : 1) ||
        (objects.isNotEmpty &&
            (!const {'attachment', 'idea'}.contains(source.type) ||
                source.deleted))) {
      throw const FormatException('crypto_migration_file_binding');
    }
    if (source.type == 'idea' && !source.deleted) {
      final descriptor = Map<String, dynamic>.from(origin['witness'] as Map);
      expectedPayload = decorateCryptoMigrationIdea(
        source.rawPayload!,
        objects,
        CryptoMigrationWitnessContext(
          Map<String, dynamic>.from(descriptor['context'] as Map),
        ),
      );
      for (final object in objects) {
        if (!(record['metadata']['blobIds'] as List).contains(
          object['blob']['id'],
        )) {
          throw const FormatException('crypto_migration_file_binding');
        }
      }
    }
    if (source.type == 'attachment' && !source.deleted) {
      if (objects.length != 1) {
        throw const CryptoAuthorityPending('crypto_migration_file_pending');
      }
      final descriptor = Map<String, dynamic>.from(origin['witness'] as Map);
      final object = objects.single;
      if (object is! Map || object['plainSize'] != source.rawPayload!['size']) {
        throw const FormatException('crypto_migration_file_binding');
      }
      final blob = CryptoMigrationFileObject.descriptor(
        CryptoMigrationWitnessContext(
          Map<String, dynamic>.from(descriptor['context'] as Map),
        ),
        object,
      );
      if (!(record['metadata']['blobIds'] as List).contains(blob['id'])) {
        throw const FormatException('crypto_migration_file_binding');
      }
      expectedPayload = {...source.rawPayload!, 'cryptoBlob': blob};
    }
  }
  final semanticPayload = derived ? expectedPayload : envelope['payload'];
  if (origin['materializationRole'] == 'taskDerivationIntent') {
    if (derived) {
      throw const FormatException('crypto_migration_companion_binding');
    }
    final canonical = await reservedId(
      source.scopeId,
      'taskDerivation:${source.canonicalId}',
    );
    final raw = source.rawPayload;
    final expected = {
      'version': 1,
      'taskId': source.canonicalId,
      'targetOperationId': record['operationId'],
      'targetCryptoRevision': 1,
      'deadlineEpoch': raw?['dueAt'] == null
          ? null
          : DateTime.parse(raw!['dueAt']).toUtc().millisecondsSinceEpoch ~/
                1000,
      'completed': raw?['isCompleted'] ?? false,
      'deleted': source.deleted,
    };
    if (source.type != 'task' ||
        record['type'] != 'taskDerivationIntent' ||
        record['deleted'] != false ||
        address.canonicalId != canonical ||
        CryptoBusinessJson.canonical(expected) !=
            CryptoBusinessJson.canonical(envelope['payload'])) {
      throw const FormatException('crypto_migration_companion_binding');
    }
  } else if (origin['materializationRole'] == 'taskDerivationResolution') {
    final taskId = source.rawPayload?['taskId'];
    final raw = envelope['payload'];
    if (!captured ||
        source.type != 'financeEntry' ||
        source.deleted ||
        taskId is! String ||
        record['type'] != 'taskDerivationResolution' ||
        record['deleted'] != false ||
        raw is! Map ||
        raw.length != 10) {
      throw const FormatException('crypto_migration_companion_binding');
    }
    final intentId = await reservedId(source.scopeId, 'taskDerivation:$taskId');
    final id = await reservedId(source.scopeId, 'taskResolution:$taskId');
    final versions = ((record['metadata'] as Map)['referenceVersions'] as List)
        .cast<Map>();
    String? hash(String type, String id) =>
        versions
                .where(
                  (v) =>
                      v['scopeId'] == source.scopeId &&
                      v['revision'] == 1 &&
                      v['domain'] == cryptoRecordDomain(type) &&
                      v['id'] ==
                          cryptoWireRecordId(
                            record['serverId'],
                            source.scopeId,
                            type,
                            id,
                          ),
                )
                .singleOrNull?['recordProofHash']
            as String?;
    final intentHash = hash('taskDerivationIntent', intentId),
        taskHash = hash('task', taskId),
        expenseHash = hash('financeEntry', source.canonicalId);
    if (versions.length != 3 ||
        intentHash == null ||
        taskHash == null ||
        expenseHash == null ||
        expenseHash != origin['primaryRecordProofHash'] ||
        address.canonicalId != id ||
        raw['version'] != 1 ||
        raw['taskId'] != taskId ||
        raw['intentId'] != intentId ||
        !isCryptoCanonicalUuid(raw['targetOperationId']) ||
        raw['targetCryptoRevision'] != 1 ||
        raw['intentProofHash'] != intentHash ||
        raw['taskProofHash'] != taskHash ||
        raw['financeEntryId'] != source.canonicalId ||
        raw['financeRecordProofHash'] != expenseHash ||
        !['derived', 'legacyPending'].contains(raw['state'])) {
      throw const FormatException('crypto_migration_companion_binding');
    }
  } else if ((origin['materializationRole'] ?? 'primary') != 'primary' ||
      source.deleted != record['deleted'] ||
      source.type != record['type'] ||
      source.canonicalId != address.canonicalId ||
      CryptoBusinessJson.canonical(expectedPayload) !=
          CryptoBusinessJson.canonical(semanticPayload)) {
    throw const FormatException('crypto_migration_business_parity');
  }
  onVerifiedSource?.call(source);
  return Map<String, dynamic>.from(semanticPayload as Map);
}
