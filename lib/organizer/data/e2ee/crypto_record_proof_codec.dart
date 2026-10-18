import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:sodium/sodium.dart';

import 'crypto_codec.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// Record-scoped proofs disclose no sibling plaintext, scope or record IDs.
/// The commitment authenticates the complete atomic batch using digests only.
bool _isCryptoRecordId(Object? value) =>
    isCryptoCanonicalUuid(value) || isCryptoWireRecordId(value);

class CryptoRecordProofCodec {
  CryptoRecordProofCodec(this.crypto);
  final CryptoCodec crypto;
  static final _recordDomain = utf8.encode('JivieE2EE/record/v2\n');
  static final _batchDomain = utf8.encode('JivieE2EE/batch/v2\n');

  Map<String, dynamic> _sign(
    Map<String, dynamic> body,
    SecureKey key,
    List<int> domain,
  ) {
    final bytes = CryptoJson.encode(body);
    return {
      'commandBase64': base64Encode(bytes),
      'signatureBase64': base64Encode(
        crypto.sodium.crypto.sign.detached(
          message: Uint8List.fromList([...domain, ...bytes]),
          secretKey: key,
        ),
      ),
    };
  }

  Map<String, dynamic> _verify(
    Map<String, dynamic> proof,
    Uint8List key,
    List<int> domain,
  ) {
    return crypto.verifyDomain(proof, key, utf8.decode(domain));
  }

  Map<String, dynamic> signCommand(
    Map<String, dynamic> command,
    SecureKey key,
  ) {
    if (command['version'] != 2) {
      throw const FormatException('crypto_command_version');
    }
    return _sign(command, key, utf8.encode('JivieE2EE/v2\n'));
  }

  Future<String> digest(Map<String, dynamic> proof) async =>
      (await Sha256().hash(
        CryptoJson.encode(proof),
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Map<String, dynamic> sealRecord({
    required String serverId,
    required String accountId,
    required String deviceId,
    required String batchId,
    required String scopeId,
    required String id,
    required String type,
    required int expectedRevision,
    required int epoch,
    required int accessRevision,
    required String membershipHeadHash,
    required String domain,
    required int contentContract,
    required String operationId,
    required String previousRecordHash,
    required bool deleted,
    required Uint8List? plaintext,
    required Map<String, dynamic> metadata,
    required SecureKey contentKey,
    required SecureKey signingKey,
  }) {
    if (![
          serverId,
          accountId,
          deviceId,
          batchId,
          scopeId,
        ].every(isCryptoCanonicalUuid) ||
        !_isCryptoRecordId(id) ||
        expectedRevision < 0 ||
        epoch < 1 ||
        accessRevision < 0 ||
        contentContract < 1 ||
        !['content', 'finance'].contains(domain) ||
        !isCryptoCanonicalUuid(operationId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(membershipHeadHash) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(previousRecordHash) ||
        (expectedRevision == 0 && previousRecordHash != '0' * 64) ||
        (deleted != (plaintext == null))) {
      throw const FormatException('crypto_record_context');
    }
    final body = <String, dynamic>{
      'version': 2,
      'operation': 'crypto2.record',
      'serverId': serverId,
      'accountId': accountId,
      'deviceId': deviceId,
      'batchId': batchId,
      'scopeId': scopeId,
      'id': id,
      'type': type,
      'expectedRevision': expectedRevision,
      'deleted': deleted,
      'epoch': epoch,
      'accessRevision': accessRevision,
      'membershipHeadHash': membershipHeadHash,
      'domain': domain,
      'contentContract': contentContract,
      'operationId': operationId,
      'previousRecordHash': previousRecordHash,
      'envelopeBase64': null,
      'metadata': {
        ...metadata,
        if (!metadata.containsKey('referenceVersions') &&
            metadata['references'] is List &&
            (metadata['references'] as List).isEmpty)
          'referenceVersions': <Map<String, dynamic>>[],
      },
    };
    _validateRecord(body, requireIdentity: true);
    if (!deleted) {
      body['envelopeBase64'] = base64Encode(
        CryptoJson.encode(
          crypto.encrypt(
            plaintext: plaintext!,
            key: contentKey,
            context: _context(body),
          ),
        ),
      );
    }
    return _sign(body, signingKey, _recordDomain);
  }

  Future<Map<String, dynamic>> commitBatch({
    required String serverId,
    required String accountId,
    required String deviceId,
    required String batchId,
    required List<Map<String, dynamic>> records,
    required SecureKey signingKey,
    required Future<String> Function(Map<String, dynamic> record)
    projectionToken,
  }) async {
    if (records.isEmpty || records.length > 32) {
      throw const FormatException('crypto_batch_size');
    }
    final hashes = await Future.wait(records.map(digest));
    hashes.sort();
    if (hashes.toSet().length != hashes.length) {
      throw const FormatException('crypto_duplicate_record');
    }
    final groups = <String, List<String>>{}, contexts = <String, String>{};
    for (final proof in records) {
      final record =
          CryptoJson.decode(cryptoBase64(proof['commandBase64']))
              as Map<String, dynamic>;
      validateUntrustedRecord(record);
      final token = await projectionToken(record);
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
        throw const FormatException('crypto_projection_token');
      }
      final context = utf8.decode(
        CryptoJson.encode(_projectionContext(record)),
      );
      if (contexts[token] != null && contexts[token] != context) {
        throw const FormatException('crypto_projection_group_mixed');
      }
      contexts[token] = context;
      (groups[token] ??= []).add(await digest(proof));
    }
    final tokens = groups.keys.toList()..sort();
    return _sign(
      {
        'version': 2,
        'operation': 'crypto2.batchCommitment',
        'serverId': serverId,
        'accountId': accountId,
        'deviceId': deviceId,
        'batchId': batchId,
        'recordDigests': hashes,
        'projectionGroups': [
          for (final token in tokens)
            {'token': token, 'recordDigests': groups[token]!..sort()},
        ],
      },
      signingKey,
      _batchDomain,
    );
  }

  Map<String, dynamic> _projectionContext(Map<String, dynamic> record) => {
    for (final field in [
      'serverId',
      'batchId',
      'scopeId',
      'domain',
      'epoch',
      'membershipHeadHash',
    ])
      field: record[field],
  };
  String projectionGroupToken(
    Map<String, dynamic> record,
    SecureKey contentKey,
  ) {
    validateUntrustedRecord(record);
    final hash = crypto.sodium.crypto.genericHash(
      message: Uint8List.fromList([
        ...utf8.encode('JivieProjectionGroup/v2\n'),
        ...CryptoJson.encode(_projectionContext(record)),
      ]),
      key: contentKey,
      outLen: 32,
    );
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _validateProjectionGroups(Map<String, dynamic> commitment) {
    final groups = commitment['projectionGroups'],
        all = commitment['recordDigests'];
    if (groups is! List ||
        groups.isEmpty ||
        groups.length > 32 ||
        all is! List) {
      throw const FormatException('crypto_projection_groups');
    }
    final partition = <String>[];
    String last = '';
    for (final group in groups) {
      if (group is! Map ||
          group.length != 2 ||
          group['token'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(group['token']) ||
          (group['token'] as String).compareTo(last) <= 0 ||
          group['recordDigests'] is! List) {
        throw const FormatException('crypto_projection_groups');
      }
      last = group['token'];
      final hashes = (group['recordDigests'] as List);
      if (hashes.isEmpty ||
          hashes.length > 32 ||
          hashes.any(
            (h) => h is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(h),
          ) ||
          hashes.toSet().length != hashes.length ||
          jsonEncode([...hashes]..sort()) != jsonEncode(hashes)) {
        throw const FormatException('crypto_projection_groups');
      }
      partition.addAll(hashes.cast<String>());
    }
    partition.sort();
    if (partition.toSet().length != partition.length ||
        jsonEncode(partition) != jsonEncode(all)) {
      throw const FormatException('crypto_projection_partition');
    }
  }

  List<String> expectedProjectionDigests({
    required Map<String, dynamic> record,
    required Map<String, dynamic> commitment,
    required SecureKey contentKey,
  }) {
    try {
      final body =
          CryptoJson.decode(cryptoBase64(commitment['commandBase64']))
              as Map<String, dynamic>;
      _validateProjectionGroups(body);
      final token = projectionGroupToken(record, contentKey);
      final groups = (body['projectionGroups'] as List)
          .where((g) => g['token'] == token)
          .toList();
      if (groups.length != 1) {
        throw const FormatException('crypto_projection_group_missing');
      }
      return List<String>.unmodifiable(
        (groups.single['recordDigests'] as List).cast<String>(),
      );
    } on TypeError {
      throw const FormatException('crypto_projection_groups');
    }
  }

  /// Validate author, own record and opaque batch membership before decrypting.
  /// Caller obtains [trustedSigningKey] from the pinned, verified directory.
  Future<Map<String, dynamic>> verifyWire({
    required String serverId,
    required Map<String, dynamic> wire,
    required Uint8List trustedSigningKey,
    required bool currentEpoch,
    String? closedRecordProofHash,
  }) async {
    try {
      return await _verifyWire(
        serverId: serverId,
        wire: wire,
        trustedSigningKey: trustedSigningKey,
        currentEpoch: currentEpoch,
        closedRecordProofHash: closedRecordProofHash,
      );
    } on TypeError {
      throw const FormatException('crypto_proof_shape');
    } on SodiumException {
      throw const FormatException('crypto_authentication');
    }
  }

  Future<Map<String, dynamic>> _verifyWire({
    required String serverId,
    required Map<String, dynamic> wire,
    required Uint8List trustedSigningKey,
    required bool currentEpoch,
    String? closedRecordProofHash,
  }) async {
    final authorization = Map<String, dynamic>.from(
      wire['authorization'] as Map,
    );
    if (authorization.length != 2) {
      throw const FormatException('crypto_authorization_shape');
    }
    final proof = Map<String, dynamic>.from(
      authorization['recordProof'] as Map,
    );
    final record = _verify(proof, trustedSigningKey, _recordDomain);
    _validateRecord(record);
    if (wire['revision'] is! int ||
        (wire['revision'] as int) < 1 ||
        wire['metadata'] is! Map ||
        wire['deleted'] is! bool) {
      throw const FormatException('crypto_record_context');
    }
    if (!currentEpoch &&
        (closedRecordProofHash == null ||
            closedRecordProofHash != await digest(proof))) {
      throw const FormatException('crypto_record_outside_epoch_closure');
    }
    final commitment = _verify(
      Map<String, dynamic>.from(authorization['batchCommitment'] as Map),
      trustedSigningKey,
      _batchDomain,
    );
    final expected = {
      'version': 2,
      'operation': 'crypto2.record',
      'serverId': serverId,
      'accountId': record['accountId'],
      'deviceId': record['deviceId'],
      'batchId': record['batchId'],
      'scopeId': wire['scopeId'],
      'id': wire['id'],
      'type': wire['type'],
      'expectedRevision': (wire['revision'] as int) - 1,
      'deleted': wire['deleted'],
      'epoch': wire['epoch'],
      'accessRevision': record['accessRevision'],
      'membershipHeadHash': record['membershipHeadHash'],
      'domain': record['domain'],
      'contentContract': record['contentContract'],
      'operationId': record['operationId'],
      'previousRecordHash': record['previousRecordHash'],
      'envelopeBase64': wire['envelopeBase64'],
      'metadata': wire['metadata'],
    };
    if (base64Encode(CryptoJson.encode(expected)) !=
            base64Encode(CryptoJson.encode(record)) ||
        !(wire['revision'] is int && (wire['revision'] as int) > 0) ||
        ![
          serverId,
          record['accountId'],
          record['deviceId'],
          record['batchId'],
          wire['scopeId'],
        ].every(isCryptoCanonicalUuid) ||
        !_isCryptoRecordId(wire['id'])) {
      throw const FormatException('crypto_record_substitution');
    }
    final hashes = commitment['recordDigests'];
    if (commitment.length != 8 ||
        commitment['version'] != 2 ||
        commitment['operation'] != 'crypto2.batchCommitment' ||
        [
          'serverId',
          'accountId',
          'deviceId',
          'batchId',
        ].any((k) => commitment[k] != record[k]) ||
        hashes is! List ||
        hashes.isEmpty ||
        hashes.length > 32 ||
        hashes.any(
          (h) => h is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(h),
        ) ||
        hashes.toSet().length != hashes.length ||
        jsonEncode([...hashes]..sort()) != jsonEncode(hashes) ||
        !hashes.contains(await digest(proof))) {
      throw const FormatException('crypto_batch_commitment');
    }
    _validateProjectionGroups(commitment);
    if (wire['deleted'] is! bool ||
        (wire['deleted'] == true) != (wire['envelopeBase64'] == null)) {
      throw const FormatException('crypto_tombstone');
    }
    return record;
  }

  void validateUntrustedRecord(Map<String, dynamic> record) {
    try {
      _validateRecord(record);
    } on TypeError {
      throw const FormatException('crypto_record_context');
    } on RangeError {
      throw const FormatException('crypto_record_context');
    }
  }

  void _validateRecord(Map<String, dynamic> r, {bool requireIdentity = false}) {
    if (r['version'] != 2 ||
        r['operation'] != 'crypto2.record' ||
        ![
          'serverId',
          'accountId',
          'deviceId',
          'batchId',
          'scopeId',
          'operationId',
        ].every((k) => isCryptoCanonicalUuid(r[k])) ||
        !_isCryptoRecordId(r['id']) ||
        r['expectedRevision'] is! int ||
        (r['expectedRevision'] as int) < 0 ||
        r['epoch'] is! int ||
        (r['epoch'] as int) < 1 ||
        r['accessRevision'] is! int ||
        (r['accessRevision'] as int) < 0 ||
        r['contentContract'] != (r['domain'] == 'finance' ? 3 : 6) ||
        !['content', 'finance'].contains(r['domain']) ||
        r['type'] is! String ||
        (r['type'] as String).isEmpty ||
        r['type'].length > 80 ||
        r['deleted'] is! bool ||
        r['metadata'] is! Map ||
        ![
          r['membershipHeadHash'],
          r['previousRecordHash'],
        ].every((v) => v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v)) ||
        (r['expectedRevision'] == 0 && r['previousRecordHash'] != '0' * 64) ||
        (r['expectedRevision'] != 0 && r['previousRecordHash'] == '0' * 64)) {
      throw const FormatException('crypto_record_context');
    }
    final metadata = r['metadata'] as Map;
    if (metadata.length !=
            3 +
                (metadata.containsKey('identity') ? 1 : 0) +
                (metadata.containsKey('referenceVersions') ? 1 : 0) +
                (metadata.containsKey('repairOf') ? 1 : 0) +
                (metadata.containsKey('reminderState') ? 1 : 0) +
                (metadata.containsKey('notificationState') ? 1 : 0) +
                (metadata.containsKey('projectState') ? 1 : 0) +
                (metadata.containsKey('auditState') ? 1 : 0) +
                (metadata.containsKey('schedulingUse') ? 1 : 0) +
                (metadata.containsKey('migrationOrigin') ? 1 : 0) +
                (metadata.containsKey('inlineDeletion') ? 1 : 0) +
                (metadata.containsKey('projectRelocation') ? 1 : 0) ||
        !['references', 'uniqueRefs', 'blobIds'].every(metadata.containsKey) ||
        metadata.keys.any(
          (k) => ![
            'references',
            'uniqueRefs',
            'blobIds',
            'identity',
            'referenceVersions',
            'repairOf',
            'reminderState',
            'notificationState',
            'projectState',
            'auditState',
            'schedulingUse',
            'migrationOrigin',
            'inlineDeletion',
            'projectRelocation',
          ].contains(k),
        )) {
      throw const FormatException('crypto_metadata_shape');
    }
    final purposes = [
      'migrationOrigin',
      'inlineDeletion',
      'projectRelocation',
    ].where(metadata.containsKey).length;
    if (purposes > 1)
      throw const FormatException('crypto_record_purpose_overlap');
    if (metadata.containsKey('projectRelocation')) {
      final tag = metadata['projectRelocation'];
      if (tag is! Map ||
          tag.length != 4 ||
          !tag.keys.toSet().containsAll({
            'version',
            'actionId',
            'planHash',
            'side',
          }) ||
          tag['version'] != 2 ||
          !isCryptoCanonicalUuid(tag['actionId']) ||
          tag['planHash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(tag['planHash']) ||
          !['source', 'target'].contains(tag['side']) ||
          tag['side'] == 'source' &&
              (r['expectedRevision'] < 1 ||
                  r['deleted'] != true &&
                      !(r['type'] == 'scopeMetadata' &&
                          r['domain'] == 'content')) ||
          tag['side'] == 'target' && r['expectedRevision'] != 0) {
        throw const FormatException('crypto_project_relocation_tag');
      }
    }
    if (metadata.containsKey('inlineDeletion')) {
      final tag = metadata['inlineDeletion'];
      if (tag is! Map ||
          tag.length != 3 ||
          !tag.keys.toSet().containsAll({'version', 'actionId', 'planHash'}) ||
          tag['version'] != 2 ||
          !isCryptoCanonicalUuid(tag['actionId']) ||
          tag['planHash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(tag['planHash']) ||
          metadata.containsKey('migrationOrigin') ||
          r['deleted'] != true ||
          r['expectedRevision'] < 1) {
        throw const FormatException('crypto_inline_deletion_tag');
      }
    }
    if (metadata.containsKey('migrationOrigin')) {
      final origin = metadata['migrationOrigin'];
      if (origin is! Map ||
          origin.length != 5 ||
          !origin.keys.toSet().containsAll({
            'version',
            'migrationId',
            'captureId',
            'bindingId',
            'sourceInventoryRoot',
          }) ||
          origin['version'] != 3 ||
          ![
            'migrationId',
            'captureId',
            'bindingId',
          ].every((key) => isCryptoCanonicalUuid(origin[key])) ||
          origin['sourceInventoryRoot'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(origin['sourceInventoryRoot'])) {
        throw const FormatException('crypto_migration_origin_shape');
      }
    }
    if (metadata.containsKey('schedulingUse')) {
      final use = metadata['schedulingUse'];
      if (use is! Map ||
          use.length != 3 ||
          !use.keys.toSet().containsAll({
            'authorization',
            'directoryHeadHash',
            'eventCommandHash',
          }) ||
          ![use['directoryHeadHash'], use['eventCommandHash']].every(
            (v) => v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v),
          ) ||
          use['authorization'] is! Map)
        throw const FormatException('crypto_scheduling_use');
      final proof = use['authorization'] as Map;
      if (proof.length != 2 ||
          !proof.keys.toSet().containsAll({'commandBase64', 'signatureBase64'}))
        throw const FormatException('crypto_scheduling_use');
      cryptoBase64(proof['signatureBase64'], length: 64);
      final body = CryptoJson.decode(
        cryptoBase64(proof['commandBase64'], max: 16384),
      );
      if (body is! Map ||
          !(body['version'] == 2 &&
                  body['operation'] == 'crypto2.scheduling.use' ||
              body['version'] == 3 &&
                  body['operation'] == 'crypto2.migration.schedulingUse') ||
          body['serverId'] != r['serverId'] ||
          body['scopeId'] != r['scopeId'] ||
          body['targetId'] != r['id'] ||
          body['targetType'] != r['type'] ||
          body['domain'] != r['domain'])
        throw const FormatException('crypto_scheduling_use');
    }
    final audit = metadata['auditState'];
    if (metadata.containsKey('auditState')) {
      if (r['domain'] != 'finance' ||
          audit is! Map ||
          audit.length != 2 ||
          audit['version'] != 1 ||
          audit['changedAt'] is! String)
        throw const FormatException('crypto_audit_state');
      final match = RegExp(
        r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?Z$',
      ).firstMatch(audit['changedAt']);
      if (match == null) throw const FormatException('crypto_audit_time');
      final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
      final parsed = DateTime.utc(
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
        parts[5],
      );
      if (parts[0] < 1970 ||
          parts[0] > 9999 ||
          parsed.year != parts[0] ||
          parsed.month != parts[1] ||
          parsed.day != parts[2] ||
          parsed.hour != parts[3] ||
          parsed.minute != parts[4] ||
          parsed.second != parts[5])
        throw const FormatException('crypto_audit_time');
    }
    final identity = metadata['identity'];
    if (requireIdentity && identity == null)
      throw const FormatException('crypto_record_identity_required');
    if (identity != null) {
      if (identity is! Map ||
          identity.length != 2 ||
          !identity.containsKey('sourceKind') ||
          !identity.containsKey('canonicalId') ||
          identity['sourceKind'] is! String ||
          identity['canonicalId'] is! String)
        throw const FormatException('crypto_record_identity');
      final address = CryptoRecordAddress(
        serverId: r['serverId'],
        scopeId: r['scopeId'],
        domain: r['domain'],
        type: r['type'],
        sourceKind: identity['sourceKind'],
        canonicalId: identity['canonicalId'],
      );
      if (address.wireId != r['id'])
        throw const FormatException('crypto_record_identity');
    }
    final notifiable = [
      'project',
      'task',
      'event',
      'shoppingList',
      'shoppingItem',
      'idea',
      'financeAccount',
      'financeEntry',
      'financeTransfer',
      'personalFinanceEntry',
      'personalFinanceAccount',
      'financeRecurrenceRule',
      'paymentEvent',
      'paymentProjection',
      'cashMovement',
    ].contains(r['type']);
    final notification = metadata['notificationState'];
    if (notifiable != metadata.containsKey('notificationState') ||
        (notifiable && notification == null) ||
        notification != null &&
            (notification is! Map ||
                notification.length != 4 ||
                notification['version'] != 1 ||
                ![
                  'created',
                  'updated',
                  'completed',
                  'checked',
                  'deleted',
                ].contains(notification['kind']) ||
                notification['assigneeAccountIds'] is! List ||
                (notification['assigneeAccountIds'] as List).length > 20 ||
                !(notification['assigneeAccountIds'] as List).every(
                  isCryptoCanonicalUuid,
                ) ||
                (notification['groupTargetId'] != null &&
                    !_isCryptoRecordId(notification['groupTargetId'])))) {
      throw const FormatException('crypto_notification_state');
    }
    if (notification != null) {
      final ids = (notification['assigneeAccountIds'] as List).cast<String>();
      if (ids.toSet().length != ids.length ||
          ids.join(':') != ([...ids]..sort()).join(':') ||
          (r['domain'] == 'finance' &&
              (ids.isNotEmpty || notification['groupTargetId'] != null))) {
        throw const FormatException('crypto_notification_state');
      }
    }
    final project = metadata['projectState'];
    if ((r['type'] == 'project') != metadata.containsKey('projectState') ||
        (r['type'] == 'project' && project == null) ||
        project != null &&
            (project is! Map ||
                project.length !=
                    (project.containsKey('consentGeneration') ? 3 : 2) ||
                (project.containsKey('consentGeneration') &&
                    !isCryptoCanonicalUuid(project['consentGeneration'])) ||
                project['version'] != 1 ||
                project['archived'] is! bool)) {
      throw const FormatException('crypto_project_state');
    }
    final reminder = metadata['reminderState'];
    final remindable = [
      'task',
      'event',
      'financeEntry',
      'personalFinanceEntry',
    ].contains(r['type']);
    if (remindable && r['deleted'] == false && reminder == null ||
        reminder != null &&
            (!remindable ||
                reminder is! Map ||
                reminder.length !=
                    (reminder.containsKey('consentGeneration') ? 5 : 4) ||
                (reminder.containsKey('consentGeneration') &&
                    !isCryptoCanonicalUuid(reminder['consentGeneration'])) ||
                reminder['version'] != 1 ||
                reminder['closed'] is! bool ||
                !isCryptoCanonicalUuid(reminder['scheduleRevision']) ||
                (reminder['dueAtEpoch'] != null &&
                    (reminder['dueAtEpoch'] is! int ||
                        reminder['dueAtEpoch'] < 0 ||
                        reminder['dueAtEpoch'] > 9007199254740991)))) {
      throw const FormatException('crypto_reminder_state');
    }
    for (final item in {
      'references': 100,
      'uniqueRefs': 10,
      'blobIds': 20,
    }.entries) {
      if (metadata[item.key] is! List ||
          (metadata[item.key] as List).length > item.value) {
        throw const FormatException('crypto_metadata_shape');
      }
    }
    final references = <String>{};
    for (final reference in metadata['references'] as List) {
      if (reference is! Map ||
          reference.length != 2 ||
          !isCryptoCanonicalUuid(reference['scopeId']) ||
          !_isCryptoRecordId(reference['id']) ||
          !references.add('${reference['scopeId']}:${reference['id']}')) {
        throw const FormatException('crypto_metadata_reference');
      }
    }
    final versions = metadata['referenceVersions'];
    if ((references.isNotEmpty && versions == null) ||
        (versions != null &&
            (versions is! List ||
                versions.length > 32 ||
                versions.length != references.length))) {
      throw const FormatException('crypto_reference_versions');
    }
    String lastVersion = '';
    final versionPairs = <String>{};
    for (final v in versions as List? ?? const []) {
      if (v is! Map ||
          v.length != 5 ||
          !isCryptoCanonicalUuid(v['scopeId']) ||
          !_isCryptoRecordId(v['id']) ||
          !['content', 'finance'].contains(v['domain']) ||
          v['revision'] is! int ||
          v['revision'] < 1 ||
          v['recordProofHash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(v['recordProofHash'])) {
        throw const FormatException('crypto_reference_versions');
      }
      final pair = '${v['scopeId']}:${v['id']}';
      final ordered = '${v['scopeId']}:${v['domain']}:${v['id']}';
      if (!references.contains(pair) ||
          !versionPairs.add(pair) ||
          ordered.compareTo(lastVersion) <= 0) {
        throw const FormatException('crypto_reference_versions');
      }
      lastVersion = ordered;
    }
    final unique = (metadata['uniqueRefs'] as List),
        blobs = (metadata['blobIds'] as List);
    if (unique.any(
          (v) => v is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(v),
        ) ||
        blobs.any((v) => !isCryptoCanonicalUuid(v)) ||
        unique.toSet().length != unique.length ||
        blobs.toSet().length != blobs.length) {
      throw const FormatException('crypto_metadata_reference');
    }
    final repair = (r['metadata'] as Map)['repairOf'];
    if (repair != null &&
        (repair is! Map ||
            repair.length != 2 ||
            repair['revision'] != r['expectedRevision'] ||
            repair['revision'] == 0 ||
            repair['recordProofHash'] != r['previousRecordHash'])) {
      throw const FormatException('crypto_repair_context');
    }
  }

  Uint8List? openVerified(Map<String, dynamic> record, SecureKey key) {
    if (record['deleted'] == true) return null;
    return crypto.decrypt(
      envelope:
          CryptoJson.decode(cryptoBase64(record['envelopeBase64']))
              as Map<String, dynamic>,
      key: key,
      context: _context(record),
    );
  }

  Map<String, dynamic> _context(Map<String, dynamic> r) => {
    'version': 2,
    'purpose': 'contentRecord',
    'serverId': r['serverId'],
    'accountId': r['accountId'],
    'deviceId': r['deviceId'],
    'batchId': r['batchId'],
    'scopeId': r['scopeId'],
    'recordId': r['id'],
    'type': r['type'],
    'revision': (r['expectedRevision'] as int) + 1,
    'epoch': r['epoch'],
    'metadata': r['metadata'],
    if ((r['metadata'] as Map).containsKey('identity'))
      'identity': r['metadata']['identity'],
    'deleted': r['deleted'],
    'domain': r['domain'],
    'accessRevision': r['accessRevision'],
    'membershipHeadHash': r['membershipHeadHash'],
    'contentContract': r['contentContract'],
    'operationId': r['operationId'],
    'previousRecordHash': r['previousRecordHash'],
  };
}
