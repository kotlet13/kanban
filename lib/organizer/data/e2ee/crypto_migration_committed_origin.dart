import 'crypto_business_router.dart';
import 'crypto_migration_captured_choices.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../collaboration_transport.dart';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart';
import 'crypto_capture_v3.dart';
import 'crypto_inventory_json.dart';
import 'crypto_business_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_activation_v3.dart';
import 'crypto_migration_business_parity_v3.dart';
import 'crypto_migration_commitments_v3.dart';
import 'crypto_migration_own_attestation.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_migration_witness.dart';
import 'crypto_migration_witness_transport.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';
import 'scope_crypto_codec.dart' show VerifiedScopeHead;

class VerifiedCryptoMigrationControl {
  VerifiedCryptoMigrationControl._(
    Map<String, dynamic> activation,
    Map<String, dynamic> header,
    Map<String, dynamic> leaf,
  ) : activation = _freeze(activation) as Map<String, dynamic>,
      contributionHeader = _freeze(header) as Map<String, dynamic>,
      controlLeaf = _freeze(leaf) as Map<String, dynamic>;
  final Map<String, dynamic> activation, contributionHeader, controlLeaf;
  static Object? _freeze(Object? value) => value is Map
      ? Map<String, dynamic>.unmodifiable(
          value.map((k, v) => MapEntry(k as String, _freeze(v))),
        )
      : value is List
      ? List<Object?>.unmodifiable(value.map(_freeze))
      : value;
}

class _VerifiedPublication {
  _VerifiedPublication(
    this.activation,
    this.header,
    this.certificatePayload,
    this.contribution,
    this.contributionPayload,
    this.contributionHeader,
    this.prefix,
  );
  final Map<String, dynamic> activation,
      header,
      certificatePayload,
      contribution,
      contributionPayload,
      contributionHeader;
  final VerifiedAccountDirectory prefix;
}

/// A full final-publication check, produced only by the private genesis reader.
/// Own anchors are inclusion facts under the already FILE-verified own prefix;
/// Session still owns complete normal-chain admission and floor promotion.
class VerifiedCryptoMigrationGenesisDescriptor {
  VerifiedCryptoMigrationGenesisDescriptor._(
    this.scopeId,
    this.headHash,
    this.migrationId,
    Map<String, dynamic> descriptor,
    List<Map<String, dynamic>> anchors,
    List<Map<String, dynamic>> members,
  ) : descriptor = Map.unmodifiable(descriptor),
      identityMembers = List.unmodifiable(
        members.map(
          (m) => Map<String, dynamic>.unmodifiable({
            for (final key in [
              'accountId',
              'directoryHeadHash',
              'rootSigningKeyBase64',
              'rootEncryptionKeyBase64',
            ])
              key: m[key],
          }),
        ),
      ),
      ownPublicationAnchors = List.unmodifiable(
        anchors.map((a) => Map<String, dynamic>.unmodifiable(a)),
      );
  final String scopeId, headHash, migrationId;
  final Map<String, dynamic> descriptor;
  final List<Map<String, dynamic>> ownPublicationAnchors;
  final List<Map<String, dynamic>> identityMembers;
}

/// Read-only authority for a signed Capture3 genesis. A transport origin hint
/// is deliberately unnecessary: the signed metadata tag always enters here.
/// Historical author approval is bound to the final manager activation and
/// included own-log events, rather than the author's current device status.
class CryptoMigrationCommittedOrigin {
  CryptoMigrationCommittedOrigin(this.access);
  CryptoMigrationCommittedOrigin._genesis(
    this.access,
    this._genesis,
    this._contentKey,
  );
  final SessionCryptoAccess access;
  VerifiedScopeHead? _genesis;
  Future<CryptoKeyLease> Function()? _contentKey;
  bool _genesisActive = true;
  VerifiedCryptoOwnContentContribution? _ownContentBootstrap;
  CryptoMigrationDescriptorAdmission? _descriptorAdmission;
  final _ownPublicationAnchors = <String, Map<String, dynamic>>{};
  String? _verifiedGenesisMigration;
  // Immutable proof results only; every lookup still validates current scoped
  // READ and pins both the exact current head and verified own directory head.
  final _provenance = <String, Uint8List>{};

  /// No provisional head or generic authority is returned. Session supplies an
  /// independently verified genesis and an ephemeral CONTENT-only key loader,
  /// then re-verifies the full normal chain before promoting any scope floor.
  Future<VerifiedCryptoMigrationGenesisDescriptor> scopeDescriptorFromGenesis(
    VerifiedScopeHead genesis,
    Future<CryptoKeyLease> Function() contentKey, {
    VerifiedCryptoOwnContentContribution? ownContentBootstrap,
    CryptoMigrationDescriptorAdmission? descriptorAdmission,
  }) async {
    if (genesis.epoch != 1 ||
        genesis.body['previousHeadHash'] != cryptoZeroHash) {
      throw const FormatException('crypto_migration_genesis_context');
    }
    final reader = CryptoMigrationCommittedOrigin._genesis(
      access,
      genesis,
      contentKey,
    );
    reader._ownContentBootstrap = ownContentBootstrap;
    reader._descriptorAdmission = descriptorAdmission;
    try {
      final descriptor = await reader.scopeDescriptor(genesis.scopeId);
      return VerifiedCryptoMigrationGenesisDescriptor._(
        genesis.scopeId,
        genesis.headHash,
        reader._verifiedGenesisMigration!,
        descriptor,
        reader._ownPublicationAnchors.values.toList(),
        genesis.members,
      );
    } finally {
      reader._genesisActive = false;
      reader._contentKey = null;
      reader._ownContentBootstrap = null;
      reader._descriptorAdmission = null;
    }
  }

  Future<VerifiedScopeHead> _current(String scope) async {
    final genesis = _genesis;
    if (genesis == null) return access.currentHead(scope);
    if (!_genesisActive || scope != genesis.scopeId) {
      throw const FormatException('crypto_migration_genesis_context');
    }
    return genesis;
  }

  Future<VerifiedScopeHead> _head(String scope, String hash) async {
    final genesis = _genesis;
    if (genesis == null) return access.headAt(scope, hash);
    if (!_genesisActive ||
        scope != genesis.scopeId ||
        hash != genesis.headHash) {
      throw const FormatException('crypto_migration_genesis_context');
    }
    return genesis;
  }

  Future<CryptoKeyLease> _key(String scope, String domain, int epoch) async {
    final genesis = _genesis;
    if (genesis == null) return access.getScopeKey(scope, domain, epoch);
    if (!_genesisActive ||
        scope != genesis.scopeId ||
        domain != 'content' ||
        epoch != 1 ||
        _contentKey == null) {
      throw const FormatException('crypto_migration_genesis_context');
    }
    return _contentKey!();
  }

  // Handles are created only after complete root verification in this reader.
  // Imported/restored SQL cannot create a handle; missing rows cause a rewalk.
  final _domainRuns = <String, String>{};
  bool _spoolStarted = false;
  CryptoRecordProofCodec get codec =>
      CryptoRecordProofCodec(access.account.directory.reducer.crypto);
  String get server => access.account.directory.session.profile.serverId;
  static Map<String, dynamic> map(Object? value) =>
      Map<String, dynamic>.from(value as Map);
  static Map<String, dynamic> body(Map<String, dynamic> proof) =>
      map(CryptoJson.decode(cryptoBase64(proof['commandBase64'])));
  static bool same(Object? a, Object? b) =>
      CryptoInventoryJson.canonical(a) == CryptoInventoryJson.canonical(b);

  /// No head/key authority: authenticate only the own FILE-rooted contribution
  /// which commits this exact genesis, before its full descriptor is readable.
  Future<VerifiedCryptoOwnContentContribution> ownContentContributionForGenesis(
    String scopeId,
    String headHash,
  ) async {
    final canonical = await _reserved(scopeId, 'scopeMetadata');
    final wire = cryptoWireRecordId(
      server,
      scopeId,
      'scopeMetadata',
      canonical,
    );
    final evidence = await access.account.directory.call(
      'crypto2.migration.origin',
      {'scopeId': scopeId, 'domain': 'content', 'id': wire, 'limit': 50},
    );
    final record = body(map(evidence['recordProof']));
    if (record['scopeId'] != scopeId ||
        record['membershipHeadHash'] != headHash ||
        record['type'] != 'scopeMetadata' ||
        record['domain'] != 'content' ||
        record['id'] != wire ||
        record['expectedRevision'] != 0) {
      throw const FormatException('crypto_migration_scope_descriptor');
    }
    final own = await access.account.directory.cachedVerifiedDirectory();
    final result = await CryptoMigrationOwnAttestation(access.account, own)
        .contentGenesisContribution(
          scopeId: scopeId,
          headHash: headHash,
          certificateAuthorization: map(evidence['certificateAuthorization']),
        );
    if (record['metadata']['migrationOrigin']['migrationId'] !=
        result.migrationId) {
      throw const FormatException('crypto_own_content_genesis_context');
    }
    return result;
  }

  Future<void> _requireOwnContentCertificate(
    Map<String, dynamic> certificate,
  ) async {
    final token = _ownContentBootstrap;
    if (token == null) {
      return;
    }
    await token.requireCurrent(
      access.account,
      scope: _genesis!.scopeId,
      genesisHash: _genesis!.headHash,
      certificate: certificate,
    );
  }

  /// Minimal descriptor baseline after current READ. Discovery of the genesis
  /// is untrusted; authority() authenticates its complete final provenance.
  Future<Map<String, dynamic>> scopeDescriptor(String scopeId) async {
    final canonical = await _reserved(scopeId, 'scopeMetadata');
    final wire = cryptoWireRecordId(
      server,
      scopeId,
      'scopeMetadata',
      canonical,
    );
    late Map<String, dynamic> evidence;
    try {
      evidence = await access.account.directory.call(
        'crypto2.migration.origin',
        {'scopeId': scopeId, 'domain': 'content', 'id': wire, 'limit': 50},
      );
    } on CollaborationApiException catch (error) {
      if (const {
        'crypto_migration_origin_missing',
        'crypto_migration_activation_pending',
      }.contains(error.code)) {
        throw const CryptoAuthorityPending(
          'crypto_migration_provenance_pending',
        );
      }
      rethrow;
    }
    final record = body(map(evidence['recordProof']));
    await _requireOwnContentCertificate(
      map(evidence['certificateAuthorization']),
    );
    if (record['type'] != 'scopeMetadata' ||
        record['id'] != wire ||
        record['scopeId'] != scopeId) {
      throw const FormatException('crypto_migration_scope_descriptor');
    }
    final authorized = await authority(record);
    final verified = await codec.verifyWire(
      serverId: server,
      wire: {
        ...record,
        'revision': 1,
        'sequence': 1,
        'authorization': {
          'recordProof': evidence['recordProof'],
          'batchCommitment': evidence['batchCommitment'],
        },
      },
      trustedSigningKey: authorized.signingKey,
      currentEpoch: authorized.currentEpoch,
      closedRecordProofHash: authorized.closedRecordProofHash,
    );
    final key = await _key(scopeId, 'content', record['epoch']);
    try {
      final bytes = codec.openVerified(verified, key.key);
      if (bytes == null) {
        throw const FormatException('crypto_migration_scope_descriptor');
      }
      try {
        final envelope = map(CryptoJson.decode(bytes));
        final raw = await verifyCryptoMigrationWitness(
          record: record,
          origin: authorized.migrationOrigin!,
          recordProofHash: authorized.closedRecordProofHash!,
          envelope: envelope,
          reservedId: _reserved,
        );
        _verifiedGenesisMigration =
            record['metadata']['migrationOrigin']['migrationId'] as String;
        final token = _ownContentBootstrap;
        if (token != null) {
          final certificate = map(evidence['certificateAuthorization']);
          await _requireOwnContentCertificate(certificate);
          final checked =
              await CryptoMigrationOwnAttestation(
                access.account,
                await access.account.directory.cachedVerifiedDirectory(),
              ).contentGenesisContribution(
                scopeId: token.scopeId,
                headHash: token.headHash,
                certificateAuthorization: certificate,
              );
          if (checked.commandHash != token.commandHash ||
              checked.headerHash != token.headerHash ||
              _verifiedGenesisMigration != token.migrationId) {
            throw const FormatException('crypto_own_content_genesis_context');
          }
          final item = checked.contribution;
          final ch = map(
            map(body(map(item['authorization']))['payload'])['header'],
          );
          // Only after all ordinary CONTENT provenance and source witness checks
          // succeeded may this included own event become a normal scoped anchor.
          await event(
            map(item['eventAuthorization']),
            map(item['authorization']),
            scopeId: token.scopeId,
            headHash: token.headHash,
            accountId: access.account.directory.accountId,
            prefixHead: ch['authorDirectoryHeadHash'],
            migrationId: token.migrationId,
            domain: 'content',
            token: ch['scopeToken'],
          );
          await _requireOwnContentCertificate(certificate);
        }
        return {
          'id': scopeId,
          'kind': raw!['kind'],
          'accessPolicyVersion': raw['accessPolicyVersion'],
          'parentScopeToken': raw['parentScopeToken'],
          'financePolicy': raw['financePolicy'],
          if (raw.containsKey('financeTopology'))
            'financeTopology': raw['financeTopology'],
          if (raw.containsKey('leaderAccountIds'))
            'leaderAccountIds': raw['leaderAccountIds'],
        };
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    } finally {
      key.release();
    }
  }

  Future<CryptoRecordAuthority> authority(
    Map<String, dynamic> record, {
    Map<String, dynamic>? evidenceFor,
  }) async {
    codec.validateUntrustedRecord(record);
    if (_genesis != null &&
        (!_genesisActive ||
            record['domain'] != 'content' ||
            record['type'] != 'scopeMetadata' ||
            record['scopeId'] != _genesis!.scopeId ||
            record['membershipHeadHash'] != _genesis!.headHash ||
            record['epoch'] != 1 ||
            record['id'] !=
                cryptoWireRecordId(
                  server,
                  _genesis!.scopeId,
                  'scopeMetadata',
                  await _reserved(_genesis!.scopeId, 'scopeMetadata'),
                ))) {
      throw const FormatException('crypto_migration_genesis_context');
    }
    final tag = map(record['metadata']['migrationOrigin']);
    CryptoMigrationBusinessParityV3.exact(tag, {
      'version',
      'migrationId',
      'captureId',
      'bindingId',
      'sourceInventoryRoot',
    });
    if (tag['version'] != 3 ||
        record['expectedRevision'] != 0 ||
        record['previousRecordHash'] != cryptoZeroHash ||
        record['serverId'] != server) {
      throw const FormatException('crypto_migration_origin_context');
    }
    final current = await _current(record['scopeId']);
    final admission = _descriptorAdmission;
    if (_genesis != null && admission != null) {
      // Only the already restricted deterministic CONTENT descriptor reader
      // can consume this ephemeral signed-admission transport capability.
      await admission.requireContext(
        access,
        record['scopeId'],
        current.headHash,
      );
    } else {
      final member = current.member(access.account.directory.accountId);
      if (record['domain'] == 'finance' && member['financeRole'] == 'none') {
        throw const CryptoAuthorityPending('crypto_migration_read_denied');
      }
    }
    final ownPin = await access.account.directory.cachedVerifiedDirectory();
    final contextKey = await cryptoSha256(
      CryptoJson.encode({
        'scopeId': record['scopeId'],
        'headHash': current.headHash,
        'accountId': ownPin.accountId,
        'ownDirectoryHeadHash': ownPin.headHash,
        'deviceId': access.account.deviceId,
        'evidenceFor': evidenceFor,
        'recordBodyHash': await cryptoSha256(CryptoJson.encode(record)),
      }),
    );
    late Map<String, dynamic> evidence;
    try {
      evidence = await access.account.directory
          .call('crypto2.migration.origin', {
            'scopeId': record['scopeId'],
            'domain': record['domain'],
            'id': record['id'],
            'recordBodyHash': await cryptoSha256(CryptoJson.encode(record)),
            if (evidenceFor != null) 'evidenceFor': evidenceFor,
            'limit': 50,
          });
    } on CollaborationApiException catch (error) {
      if ([
        'crypto_migration_origin_missing',
        'crypto_migration_activation_pending',
      ].contains(error.code)) {
        throw const CryptoAuthorityPending(
          'crypto_migration_provenance_pending',
        );
      }
      rethrow;
    }
    final proof = map(evidence['recordProof']);
    await _requireOwnContentCertificate(
      map(evidence['certificateAuthorization']),
    );
    if (!same(body(proof), record)) {
      throw const FormatException('crypto_migration_origin_record');
    }
    final proofHash = await codec.digest(proof);
    // The live origin lookup above always enforces current READ/availability,
    // including the exact historical evidenceFor restriction. Only immutable
    // cryptographic work after that independent gate may use the memo.
    final memoKey =
        '$contextKey:${await codec.digest(map(evidence['certificateAuthorization']))}:${await codec.digest(map(evidence['contributionAuthorization']))}';
    final retained = _provenance[memoKey];
    if (retained != null) {
      final value = map(jsonDecode(utf8.decode(retained)));
      if (value['closedRecordProofHash'] != proofHash) {
        throw const FormatException('crypto_migration_origin_record');
      }
      for (final raw in value['ownPublicationAnchors'] as List) {
        final anchor = map(raw);
        if (!ownPin.includesAnchor(anchor['generation'], anchor['headHash'])) {
          throw const FormatException('crypto_migration_origin_own_event');
        }
        _ownPublicationAnchors[anchor['headHash']] = anchor;
      }
      return CryptoRecordAuthority(
        signingKey: cryptoBase64(value['signingKeyBase64'], length: 32),
        currentEpoch: value['currentEpoch'],
        closedRecordProofHash: value['closedRecordProofHash'],
        historyBasis: value['historyBasis'],
        migrationOrigin: map(value['migrationOrigin']),
        migrationWitness: value['migrationWitness'] == null
            ? null
            : map(value['migrationWitness']),
      );
    }
    final publication = await _publicationEvidence(record, tag, evidence);
    final header = publication.header,
        cp = publication.certificatePayload,
        contribution = publication.contribution,
        payload = publication.contributionPayload,
        ch = publication.contributionHeader,
        prefix = publication.prefix;
    final domain = record['domain'] as String;
    final leaf = map(evidence['leaf']);
    final leafHash = await CryptoMigrationCommitmentsV3.leafHash(header, leaf);
    if (leafHash != evidence['leafHash'] ||
        leaf['recordProofHash'] != proofHash ||
        leaf['contributorAccountId'] != record['accountId'] ||
        leaf['contributorAccountId'] != contribution['accountId'] ||
        leaf['contributorDeviceId'] != record['deviceId'] ||
        leaf['contributorDeviceSnapshotHash'] != prefix.deviceSnapshotHash ||
        leaf['coldParityHash'] != ch['coldParityProofHash'] ||
        ![
          'captureId',
          'bindingId',
          'sourceInventoryRoot',
        ].every((k) => leaf[k] == tag[k]) ||
        leaf['wireId'] != record['id'] ||
        leaf['type'] != record['type']) {
      throw const FormatException('crypto_migration_origin_leaf');
    }
    if (ch['leafCount'] != header['materializedRecordProofCount'] ||
        (cp['assignments'] as List).any(
          (a) =>
              a['accountId'] != contribution['accountId'] &&
              a['leafCount'] != 0,
        )) {
      throw const FormatException('crypto_migration_origin_materializer');
    }
    await _root(
      evidence,
      header,
      cp['domainRoot'],
      leafHash,
      record,
      ch,
      payload['leafSetRoot'],
      evidenceFor,
    );
    final sourceBinding = map(evidence['sourceBinding']);
    CryptoMigrationBusinessParityV3.exact(sourceBinding, {
      'bindingId',
      'scopeId',
      'sourceKind',
      'canonicalId',
      'wireId',
      'domain',
      'type',
      'legacyRevision',
      'recordProofHash',
      'companionProofHashes',
      'witness',
      'objects',
    });
    if (sourceBinding['bindingId'] != tag['bindingId'] ||
        sourceBinding['scopeId'] != record['scopeId'] ||
        sourceBinding['domain'] != domain ||
        ![
          sourceBinding['recordProofHash'],
          ...(sourceBinding['companionProofHashes'] as List),
        ].contains(proofHash) ||
        leaf['legacyRevision'] != sourceBinding['legacyRevision']) {
      throw const FormatException('crypto_migration_origin_binding');
    }
    final keyBytes = cryptoBase64(
      prefix.activeDevice(record['deviceId'])['signingKeyBase64'],
      length: 32,
    );
    final verified = await codec.verifyWire(
      serverId: server,
      wire: {
        ...record,
        'revision': 1,
        'sequence': 1,
        'authorization': {
          'recordProof': proof,
          'batchCommitment': evidence['batchCommitment'],
        },
      },
      trustedSigningKey: keyBytes,
      currentEpoch: current.headHash == record['membershipHeadHash'],
      closedRecordProofHash: proofHash,
    );
    Map<String, dynamic>? witness;
    late Map<String, dynamic> origin;
    if (record['type'] == 'scopeMetadata') {
      if (sourceBinding['witness'] != null ||
          leaf['witnessCipherManifestHash'] != null ||
          leaf['materializationRole'] != 'primary' ||
          sourceBinding['recordProofHash'] != proofHash) {
        throw const FormatException('crypto_migration_origin_metadata');
      }
      origin = {
        ...sourceBinding,
        'sourceTable': 'familyhub_scopes',
        'sourceId': leaf['canonicalId'],
        'sourceRowHash': null,
        'captureVersion': 3,
        'recordProofHash': proofHash,
      };
    } else if (leaf['materializationRole'] == 'financeAccountChoice') {
      final descriptor = map(sourceBinding['witness']);
      final context = CryptoMigrationWitnessContext(map(descriptor['context']));
      if (record['type'] != 'financeAccountChoice' ||
          sourceBinding['type'] != 'financeEntry' ||
          descriptor['cipherManifestHash'] !=
              leaf['witnessCipherManifestHash'] ||
          context.value['sourceCommitment'] != leaf['sourceCommitment'] ||
          context.value['serverId'] != server ||
          context.value['migrationId'] != tag['migrationId'] ||
          ![
            'captureId',
            'bindingId',
            'sourceInventoryRoot',
          ].every((k) => context.value[k] == tag[k]) ||
          context.value['accountId'] != record['accountId'] ||
          context.value['scopeId'] != record['scopeId'] ||
          context.value['domain'] != domain ||
          context.value['membershipHeadHash'] != record['membershipHeadHash'] ||
          context.value['epoch'] != record['epoch'] ||
          context.value['accessRevision'] != record['accessRevision'] ||
          ![
            'type',
            'sourceKind',
            'canonicalId',
            'wireId',
          ].every((k) => context.value[k] == sourceBinding[k])) {
        throw const FormatException('crypto_account_choices_capture_companion');
      }
      origin = {
        ...sourceBinding,
        'captureVersion': 3,
        'sourceTable': 'familyhub_finance_records',
        'recordProofHash': proofHash,
        'primaryRecordProofHash': sourceBinding['recordProofHash'],
        'sourceKind': leaf['sourceKind'],
        'canonicalId': leaf['canonicalId'],
        'wireId': leaf['wireId'],
        'type': leaf['type'],
        'materializationRole': 'financeAccountChoice',
      };
    } else {
      final descriptor = map(sourceBinding['witness']);
      final context = CryptoMigrationWitnessContext(map(descriptor['context']));
      if (descriptor['cipherManifestHash'] !=
              leaf['witnessCipherManifestHash'] ||
          context.value['sourceCommitment'] != leaf['sourceCommitment'] ||
          context.value['serverId'] != server ||
          context.value['migrationId'] != tag['migrationId'] ||
          ![
            'captureId',
            'bindingId',
            'sourceInventoryRoot',
          ].every((k) => context.value[k] == tag[k]) ||
          context.value['accountId'] != record['accountId'] ||
          context.value['scopeId'] != record['scopeId'] ||
          context.value['domain'] != domain ||
          context.value['membershipHeadHash'] != record['membershipHeadHash'] ||
          context.value['epoch'] != record['epoch'] ||
          context.value['accessRevision'] != record['accessRevision']) {
        throw const FormatException('crypto_migration_origin_witness');
      }
      if (![
        'type',
        'sourceKind',
        'canonicalId',
        'wireId',
      ].every((k) => context.value[k] == sourceBinding[k])) {
        throw const FormatException('crypto_migration_origin_witness_identity');
      }
      final consumer = CryptoMigrationWitness(
        database: access.account.store.database,
        partition: access.account.store.partition,
        crypto: codec.crypto,
      );
      final localKey = await _key(record['scopeId'], domain, record['epoch']);
      try {
        witness = await consumer.openProduced(
          context: context,
          descriptor: descriptor,
          domainKey: localKey.key,
        );
      } finally {
        localKey.release();
      }
      if (witness == null) {
        await CryptoMigrationWitnessTransport(
          read: (op, p) async {
            final page = await access.account.directory.call(
              'crypto2.blob.get',
              {
                'scopeId': record['scopeId'],
                'domain': domain,
                'accessRevision': current.accessRevision,
                'id': p['id'],
                'offset': p['offset'],
                if (evidenceFor != null) ...{
                  'evidenceFor': evidenceFor,
                  'evidenceRecord': {
                    'id': record['id'],
                    'revision': 1,
                    'recordProofHash': proofHash,
                  },
                },
              },
            );
            return {
              ...page,
              'complete': true,
              'nextOffset':
                  (p['offset'] as int) +
                  cryptoBase64(page['dataBase64']).length,
            };
          },
        ).download(
          consumer: consumer,
          context: context,
          descriptor: descriptor,
        );
        final key = await _key(record['scopeId'], domain, record['epoch']);
        try {
          witness = await consumer.open(
            context: context,
            descriptor: descriptor,
            domainKey: key.key,
          );
        } finally {
          key.release();
        }
      }
      final sourceContext = CryptoCaptureSourceContext.fromJson(
        map(witness['context']),
      );
      final source = await CryptoMigrationRecordSource.decode(
        table: sourceContext.sourceTable,
        domain: domain,
        row: map(witness['typedRow']),
        serverId: server,
        reservedId: _reserved,
      );
      if (source.canonicalId != sourceBinding['canonicalId'] ||
          source.type != sourceBinding['type'] ||
          source.legacyRevision != sourceBinding['legacyRevision']) {
        throw const FormatException('crypto_migration_origin_source_identity');
      }
      origin = {
        ...sourceBinding,
        'captureVersion': 3,
        'sourceTable': source.table,
        'sourceId': source.sourceId,
        'sourceRowHash': source.rowHash,
        'recordProofHash': proofHash,
        'primaryRecordProofHash': sourceBinding['recordProofHash'],
        'sourceKind': leaf['sourceKind'],
        'canonicalId': leaf['canonicalId'],
        'wireId': leaf['wireId'],
        'type': leaf['type'],
        'materializationRole': leaf['materializationRole'],
      };
    }
    final key = await _key(record['scopeId'], domain, record['epoch']);
    try {
      final plain = codec.openVerified(verified, key.key);
      try {
        if (leaf['materializationRole'] == 'financeAccountChoice') {
          if (plain == null) {
            throw const FormatException(
              'crypto_account_choices_capture_companion',
            );
          }
          final raw = map(map(jsonDecode(utf8.decode(plain)))['payload']);
          final runtime = CryptoBusinessSession(
            access.account,
            access,
            access.account.store.database,
          );
          origin['derivedPayloadHash'] =
              await CryptoMigrationCapturedChoices.verifyCompanion(
                runtime,
                raw: raw,
                record: record,
                sourceBinding: {
                  ...sourceBinding,
                  'sourceCommitment': leaf['sourceCommitment'],
                },
                head: await _head(
                  record['scopeId'],
                  record['membershipHeadHash'],
                ),
              );
        }
        await verifyCryptoMigrationWitness(
          record: record,
          origin: origin,
          recordProofHash: proofHash,
          envelope: plain == null ? null : map(jsonDecode(utf8.decode(plain))),
          detachedWitness: witness,
          reservedId: _reserved,
        );
      } finally {
        plain?.fillRange(0, plain.length, 0);
      }
    } finally {
      key.release();
    }
    if (access.account.directory.isCurrent() &&
        (await access.account.directory.cachedVerifiedDirectory()).headHash ==
            ownPin.headHash) {
      final bytes = CryptoBusinessJson.encode({
        'signingKeyBase64': base64Encode(keyBytes),
        'currentEpoch': current.headHash == record['membershipHeadHash'],
        'closedRecordProofHash': proofHash,
        'historyBasis': 'migrationCapturedSource',
        'migrationOrigin': origin,
        'migrationWitness': witness,
        'ownPublicationAnchors': _ownPublicationAnchors.values.toList(),
      });
      if (bytes.length <= 256 * 1024) {
        final cacheKey = memoKey;
        final old = _provenance.remove(cacheKey);
        old?.fillRange(0, old.length, 0);
        _provenance[cacheKey] = bytes;
        while (_provenance.length > 8) {
          final expired = _provenance.remove(_provenance.keys.first)!;
          expired.fillRange(0, expired.length, 0);
        }
      } else {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    return CryptoRecordAuthority(
      signingKey: keyBytes,
      currentEpoch: current.headHash == record['membershipHeadHash'],
      closedRecordProofHash: proofHash,
      historyBasis: 'migrationCapturedSource',
      migrationOrigin: origin,
      migrationWitness: witness,
    );
  }

  Future<_VerifiedPublication> _publicationEvidence(
    Map<String, dynamic> record,
    Map<String, dynamic> tag,
    Map<String, dynamic> evidence, {
    bool selectedNotifications = false,
  }) async {
    final activationProof = map(evidence['activationAuthorization']);
    final activation = body(activationProof);
    await verifyActivation(
      activationProof,
      map(evidence['activationEventAuthorization']),
    );
    if (activation['scopeId'] != record['scopeId'] ||
        activation['migrationId'] != tag['migrationId'] ||
        activation['membershipHeadHash'] != record['membershipHeadHash']) {
      throw const FormatException('crypto_migration_origin_activation');
    }
    final certProof = map(evidence['certificateAuthorization']);
    final cert = body(certProof),
        cp = map(cert['payload']),
        header = map(cp['header']);
    CryptoMigrationBusinessParityV3.exact(cp, {
      'header',
      'assignments',
      'domainRoot',
      'contributions',
    });
    await CryptoMigrationCommitmentsV3.validateHeader(header);
    final domain = record['domain'] as String;
    if (cert['operation'] != 'crypto2.migration.domains.certify' ||
        header['scopeId'] != record['scopeId'] ||
        header['domain'] != domain ||
        header['managerAccountId'] != activation['managerAccountId'] ||
        ![
          'serverId',
          'migrationId',
          'componentId',
          'componentCommitment',
          'inventoryCommitment',
          'membershipHeadHash',
        ].every((k) => header[k] == activation[k]) ||
        await codec.digest(certProof) !=
            activation['${domain}CertificateHash']) {
      throw const FormatException('crypto_migration_origin_certificate');
    }
    await command(
      certProof,
      scopeId: record['scopeId'],
      headHash: record['membershipHeadHash'],
      accountId: header['managerAccountId'],
      directoryHeadHash: header['managerDirectoryHeadHash'],
      manager: true,
    );
    await event(
      map(evidence['certificateEventAuthorization']),
      certProof,
      scopeId: record['scopeId'],
      headHash: record['membershipHeadHash'],
      accountId: header['managerAccountId'],
      prefixHead: header['managerDirectoryHeadHash'],
      migrationId: tag['migrationId'],
      domain: domain,
      token: header['scopeToken'],
    );
    final contributionProof = map(evidence['contributionAuthorization']);
    final contribution = body(contributionProof),
        payload = map(contribution['payload']);
    CryptoMigrationBusinessParityV3.exact(payload, {
      'header',
      'leafSetRoot',
      'controlSections',
      'scopeControlSections',
      'controlLinks',
    });
    final ch = map(payload['header']);
    CryptoMigrationCommitmentsV3.validateContribution(ch);
    final assignment = (cp['assignments'] as List)
        .where((a) => a['accountId'] == contribution['accountId'])
        .toList();
    final included = (cp['contributions'] as List)
        .where(
          (a) =>
              same(a['authorization'], contributionProof) &&
              same(
                a['eventAuthorization'],
                evidence['contributionEventAuthorization'],
              ),
        )
        .toList();
    if (assignment.length != 1 ||
        included.length != 1 ||
        contribution['operation'] != 'crypto2.migration.domains.contribute' ||
        ch['headerHash'] !=
            await CryptoMigrationCommitmentsV3.headerHash(header) ||
        ![
          'serverId',
          'migrationId',
          'scopeToken',
          'domain',
        ].every((k) => ch[k] == header[k]) ||
        ch['captureId'] != tag['captureId'] ||
        ch['sourceInventoryRoot'] != tag['sourceInventoryRoot'] ||
        ch['captureId'] != assignment.single['captureId'] ||
        ch['sourceInventoryRoot'] != assignment.single['sourceInventoryRoot'] ||
        ch['portionToken'] != assignment.single['portionToken'] ||
        ch['leafCount'] != assignment.single['leafCount'] ||
        ch['sourceRowCount'] != assignment.single['sourceRowCount']) {
      throw const FormatException('crypto_migration_origin_contribution');
    }
    final prefix = await command(
      contributionProof,
      scopeId: record['scopeId'],
      headHash: record['membershipHeadHash'],
      accountId: contribution['accountId'],
      directoryHeadHash: ch['authorDirectoryHeadHash'],
    );
    final sourceHead = await _head(
      record['scopeId'],
      record['membershipHeadHash'],
    );
    final sourceMember = sourceHead.member(contribution['accountId']);
    if (domain == 'finance'
        ? !['read', 'write'].contains(sourceMember['financeRole'])
        : sourceMember['role'] != 'owner') {
      throw const FormatException('crypto_migration_origin_materializer');
    }
    await event(
      map(evidence['contributionEventAuthorization']),
      contributionProof,
      scopeId: record['scopeId'],
      headHash: record['membershipHeadHash'],
      accountId: contribution['accountId'],
      prefixHead: ch['authorDirectoryHeadHash'],
      migrationId: tag['migrationId'],
      domain: domain,
      token: header['scopeToken'],
    );
    await _controls(
      evidence,
      activation,
      payload,
      ch,
      selectedNotifications: selectedNotifications,
    );
    return _VerifiedPublication(
      activation,
      header,
      cp,
      contribution,
      payload,
      ch,
      prefix,
    );
  }

  /// Domain-readable control provenance without disclosing private verify3.
  /// Current READ is independent of immutable historical publication evidence.
  Future<VerifiedCryptoMigrationControl> verifyControlEvidence({
    required Map<String, dynamic> evidence,
    required Map<String, dynamic> contributionAuthorization,
    required Map<String, dynamic> contributionEventAuthorization,
    required Map<String, dynamic> certificateAuthorization,
    required Map<String, dynamic> certificateEventAuthorization,
    String domain = 'finance',
    String kind = 'audit',
  }) async {
    if (_genesis != null) {
      throw const FormatException('crypto_migration_control_genesis_forbidden');
    }
    final activation = body(map(evidence['authorization'])),
        scope = activation['scopeId'] as String;
    if (!const ['content', 'finance'].contains(domain) ||
        !const ['audit', 'notifications'].contains(kind)) {
      throw const FormatException('crypto_migration_control_context');
    }
    final read = await access.readContext(scope, domain);
    final current = await _current(scope);
    if (current.headHash != read.headHash ||
        domain == 'finance' &&
            !['read', 'write'].contains(
              current.member(access.account.directory.accountId)['financeRole'],
            )) {
      throw const CryptoAuthorityPending('crypto_finance_read_required');
    }
    final ch = map(map(body(contributionAuthorization)['payload'])['header']);
    final complete = <String, dynamic>{
      'activationAuthorization': evidence['authorization'],
      'activationEventAuthorization': evidence['eventAuthorization'],
      'certificateAuthorization': certificateAuthorization,
      'certificateEventAuthorization': certificateEventAuthorization,
      'contributionAuthorization': contributionAuthorization,
      'contributionEventAuthorization': contributionEventAuthorization,
      'controlEvidence': evidence,
    };
    final verified = await _publicationEvidence(
      {
        'scopeId': scope,
        'membershipHeadHash': activation['membershipHeadHash'],
        'domain': domain,
      },
      {
        'migrationId': activation['migrationId'],
        'captureId': ch['captureId'],
        'sourceInventoryRoot': ch['sourceInventoryRoot'],
      },
      complete,
      selectedNotifications: domain == 'content' && kind == 'notifications',
    );
    final controls = (evidence['controls'] as List).cast<Map>();
    final selected = controls.where((c) => c['kind'] == kind).toList();
    if (selected.length != 1) {
      throw const FormatException('crypto_migration_audit_control');
    }
    // No cached result can bypass the current caller's identity/READ pins.
    if (!access.account.directory.isCurrent() ||
        (await _current(scope)).headHash != current.headHash) {
      throw const CryptoAuthorityPending('crypto_scope_head_changed');
    }
    return VerifiedCryptoMigrationControl._(
      verified.activation,
      verified.contributionHeader,
      Map<String, dynamic>.from(selected.single),
    );
  }

  Future<void> verifyActivation(
    Map<String, dynamic> proof,
    Map<String, dynamic> ownEvent,
  ) async {
    final h = body(proof);
    CryptoMigrationActivationV3.validate(h);
    final head = await _head(h['scopeId'], h['membershipHeadHash']);
    final member = head.member(h['managerAccountId']);
    if (h['serverId'] != server ||
        member['manageKeys'] != true ||
        h['componentCommitment'] !=
            await CryptoMigrationCommitmentsV3.componentCommitment(
              serverId: server,
              migrationId: h['migrationId'],
              componentId: h['componentId'],
              inventoryCommitment: h['inventoryCommitment'],
            )) {
      throw const FormatException('crypto_migration_origin_activation');
    }
    final prefix = await _prefix(
      h['scopeId'],
      h['membershipHeadHash'],
      h['managerAccountId'],
      h['managerDirectoryHeadHash'],
    );
    final eventBody = body(ownEvent);
    codec.crypto.verifyDomain(
      proof,
      cryptoBase64(
        prefix.activeDevice(eventBody['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      'JivieMigrationActivation/v3\n',
    );
    await event(
      ownEvent,
      proof,
      scopeId: h['scopeId'],
      headHash: h['membershipHeadHash'],
      accountId: h['managerAccountId'],
      prefixHead: h['managerDirectoryHeadHash'],
      migrationId: h['migrationId'],
      domain: 'content',
      token: await CryptoMigrationActivationV3.token(h),
    );
  }

  Future<void> _controls(
    Map<String, dynamic> evidence,
    Map<String, dynamic> activation,
    Map<String, dynamic> contribution,
    Map<String, dynamic> contributionHeader, {
    bool selectedNotifications = false,
  }) async {
    final controlEvidence = map(evidence['controlEvidence']);
    if (!same(
          controlEvidence['authorization'],
          evidence['activationAuthorization'],
        ) ||
        !same(
          controlEvidence['eventAuthorization'],
          evidence['activationEventAuthorization'],
        )) {
      throw const FormatException('crypto_migration_origin_controls');
    }
    final digests = (controlEvidence['controlDigests'] as List).cast<String>();
    if (digests.length > 5000 ||
        await CryptoMigrationActivationV3.controlRoot(
              activation,
              Stream.fromIterable(digests),
            ) !=
            activation['controlRoot']) {
      throw const FormatException('crypto_migration_origin_controls');
    }
    final sections = map(contribution['controlSections']);
    final scopedAudit = CryptoMigrationBusinessParityV3.scopedAudit(
      contribution['scopeControlSections'],
    );
    final links = map(contribution['controlLinks']);
    CryptoMigrationBusinessParityV3.exact(links, {
      'notifications',
      'invitations',
    });
    for (final link in links.values) {
      CryptoMigrationBusinessParityV3.exact(link, {
        'certificateHash',
        'eventCommandHash',
      });
    }
    CryptoMigrationBusinessParityV3.exact(
      sections,
      CryptoMigrationBusinessParityV3.requiredSections,
    );
    final controls = controlEvidence['controls'];
    if (controls is! List ||
        controls.length != (selectedNotifications ? 1 : 5)) {
      throw const FormatException('crypto_migration_origin_controls');
    }
    final seen = <String>{};
    for (final raw in controls) {
      final leaf = map(raw), kind = leaf['kind'];
      // This scoped endpoint discloses only its requested notification leaf.
      // Ordinary record/audit evidence still requires all five controls.
      if (selectedNotifications && kind != 'notifications') {
        throw const FormatException('crypto_migration_origin_controls');
      }
      final hash = await CryptoMigrationActivationV3.controlHash(leaf);
      if ((kind == 'notifications' || kind == 'invitations') &&
          !same(contribution['controlLinks'][kind], {
            'certificateHash': leaf['certificateHash'],
            'eventCommandHash': leaf['eventCommandHash'],
          })) {
        throw const FormatException('crypto_migration_origin_control_links');
      }
      if (!seen.add(kind) ||
          !digests.contains(hash) ||
          leaf['scopeId'] != activation['scopeId'] ||
          leaf['portionToken'] != contributionHeader['portionToken'] ||
          leaf['captureId'] != contributionHeader['captureId'] ||
          leaf['sourceInventoryRoot'] !=
              contributionHeader['sourceInventoryRoot'] ||
          leaf['verify3ProofHash'] !=
              contributionHeader['coldParityProofHash'] ||
          (kind == 'audit' ? scopedAudit : sections[kind]) is! Map ||
          !same(kind == 'audit' ? scopedAudit : sections[kind], {
            'kind': kind,
            'count': leaf['selectionCount'],
            'root': leaf['selectionRoot'],
          })) {
        throw const FormatException('crypto_migration_origin_controls');
      }
    }
  }

  Future<VerifiedAccountDirectory> _prefix(
    String scope,
    String head,
    String account,
    String hash,
  ) async {
    final source = await _head(scope, head);
    final member = source.member(account);
    final prefix = await access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head,
      accountId: account,
      directoryHeadHash: hash,
      online: true,
      allowUnverifiedContact: true,
    );
    if (prefix.snapshot['rootSigningKeyBase64'] !=
            member['rootSigningKeyBase64'] ||
        prefix.snapshot['rootEncryptionKeyBase64'] !=
            member['rootEncryptionKeyBase64']) {
      throw const FormatException('crypto_migration_origin_issuer_root');
    }
    return prefix;
  }

  Future<VerifiedAccountDirectory> command(
    Map<String, dynamic> proof, {
    required String scopeId,
    required String headHash,
    required String accountId,
    required String directoryHeadHash,
    bool manager = false,
  }) async {
    final c = body(proof),
        source = await _head(scopeId, headHash),
        member = source.member(accountId);
    CryptoMigrationBusinessParityV3.exact(c, {
      'version',
      'operation',
      'serverId',
      'accountId',
      'deviceId',
      'requestId',
      'signer',
      'payload',
    });
    final prefix = await _prefix(
      scopeId,
      headHash,
      accountId,
      directoryHeadHash,
    );
    if (c['serverId'] != server ||
        c['accountId'] != accountId ||
        c['signer'] != 'device' ||
        manager && member['manageKeys'] != true) {
      throw const FormatException('crypto_migration_origin_issuer');
    }
    codec.crypto.verifyDomain(
      proof,
      cryptoBase64(
        prefix.activeDevice(c['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    return prefix;
  }

  Future<void> event(
    Map<String, dynamic> proof,
    Map<String, dynamic> attestation, {
    required String scopeId,
    required String headHash,
    required String accountId,
    required String prefixHead,
    required String migrationId,
    required String domain,
    required String token,
    CryptoMigrationCandidate? candidate,
  }) async {
    if (candidate != null) {
      if (candidate.migrationId != migrationId ||
          candidate.head.scopeId != scopeId ||
          candidate.head.headHash != headHash) {
        throw const FormatException('crypto_migration_candidate_event');
      }
      // Recheck this opaque capability before using its exact genesis solely
      // to verify an attestation event. No record authority is exposed.
      await candidate.lifecycleHash();
      final reader = CryptoMigrationCommittedOrigin._genesis(
        access,
        candidate.head,
        null,
      );
      try {
        await reader.event(
          proof,
          attestation,
          scopeId: scopeId,
          headHash: headHash,
          accountId: accountId,
          prefixHead: prefixHead,
          migrationId: migrationId,
          domain: domain,
          token: token,
        );
      } finally {
        reader._genesisActive = false;
      }
      return;
    }
    final c = body(proof), p = map(c['payload']);
    CryptoMigrationBusinessParityV3.exact(c, {
      'version',
      'operation',
      'serverId',
      'accountId',
      'deviceId',
      'requestId',
      'signer',
      'payload',
    });
    CryptoMigrationBusinessParityV3.exact(p, {
      'expectedGeneration',
      'previousHeadHash',
      'identityEpochId',
      'resultingSnapshotHash',
      'migrationId',
      'domain',
      'scopeToken',
      'attestationHash',
    });
    if (!CryptoMigrationBusinessParityV3.count(p['expectedGeneration']) ||
        p['expectedGeneration'] < 1 ||
        !CryptoMigrationBusinessParityV3.hash(p['previousHeadHash'])) {
      throw const FormatException('crypto_migration_origin_event');
    }
    if (c['serverId'] != server ||
        c['accountId'] != accountId ||
        c['operation'] != 'crypto2.account.migrationAttest' ||
        p['migrationId'] != migrationId ||
        p['domain'] != domain ||
        p['scopeToken'] != token ||
        p['attestationHash'] != await codec.digest(attestation)) {
      throw const FormatException('crypto_migration_origin_event');
    }
    final hash = await cryptoSha256([
      ...utf8.encode(cryptoDirectoryLogDomain),
      ...CryptoJson.encode({
        'serverId': server,
        'accountId': accountId,
        'generation': p['expectedGeneration'] + 1,
        'previousHeadHash': p['previousHeadHash'],
        'commandHash': await cryptoSha256(cryptoBase64(proof['commandBase64'])),
        'signatureBase64': proof['signatureBase64'],
      }),
    ]);
    final prefix = await _prefix(scopeId, headHash, accountId, prefixHead);
    final included = await _prefix(scopeId, headHash, accountId, hash);
    if (!included.includesAnchor(prefix.generation, prefix.headHash) ||
        prefix.identityEpochId != p['identityEpochId'] ||
        included.generation != p['expectedGeneration'] + 1) {
      throw const FormatException('crypto_migration_origin_event');
    }
    if (accountId == access.account.directory.accountId) {
      final own = await access.account.directory.cachedVerifiedDirectory();
      if (!own.includesAnchor(included.generation, included.headHash)) {
        throw const FormatException('crypto_migration_origin_own_event');
      }
      _ownPublicationAnchors[included.headHash] = {
        'scopeId': scopeId,
        'membershipHeadHash': headHash,
        'generation': included.generation,
        'headHash': included.headHash,
        'commandHash': await cryptoSha256(cryptoBase64(proof['commandBase64'])),
        'attestationHash': p['attestationHash'],
      };
    }
  }

  Future<void> _root(
    Map<String, dynamic> first,
    Map<String, dynamic> header,
    Object? root,
    String requiredLeaf,
    Map record,
    Map<String, dynamic> contributionHeader,
    Object? contributionRoot,
    Map<String, dynamic>? evidenceFor,
  ) async {
    final db = access.account.store.database,
        partition = access.account.store.partition;
    final certificateKey = await codec.digest(
      map(first['certificateAuthorization']),
    );
    final runKey =
        '$certificateKey:${await codec.digest(map(first['contributionAuthorization']))}';
    await db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_migration_read_digests('
      'partition TEXT NOT NULL,run_id TEXT NOT NULL,leaf_hash TEXT NOT NULL,'
      'PRIMARY KEY(partition,run_id,leaf_hash))',
    );
    if (!_spoolStarted) {
      // Derived session caches only. A concurrent reader losing its rows must
      // rewalk the proof; missing rows never establish absence or authority.
      await db.execute(
        'DELETE FROM crypto_migration_read_digests WHERE partition=?',
        [partition],
      );
      _spoolStarted = true;
    }
    final prior = _domainRuns[runKey];
    if (prior != null &&
        (await db.rows(
              'SELECT 1 FROM crypto_migration_read_digests WHERE partition=? AND run_id=? AND leaf_hash=?',
              [partition, prior, requiredLeaf],
            )).length ==
            1) {
      return;
    }
    final run = codec.crypto.randomId();
    final contributionSink = Sha256().newHashSink();
    contributionSink.add([
      ...utf8.encode('JivieMigrationContribution/v3\n'),
      ...CryptoInventoryJson.encode(contributionHeader),
      10,
    ]);
    var found = false;
    Stream<String> hashes() async* {
      Map<String, dynamic> page = first;
      String? after;
      while (true) {
        final values = page['leafDigests'];
        if (values is! List || values.length > 50) {
          throw const FormatException('crypto_migration_origin_inventory');
        }
        for (final item in values) {
          final hash = item is String ? item : item['leafHash'];
          if (!CryptoMigrationBusinessParityV3.hash(hash) ||
              after != null && after.compareTo(hash) >= 0) {
            throw const FormatException('crypto_migration_origin_inventory');
          }
          after = hash;
          found = found || hash == requiredLeaf;
          contributionSink.add(utf8.encode('$hash\n'));
          await db.execute(
            'INSERT INTO crypto_migration_read_digests VALUES(?,?,?)',
            [partition, run, hash],
          );
          yield hash as String;
        }
        if (page['hasMore'] == false) break;
        if (page['hasMore'] != true ||
            page['nextAfterHash'] != after ||
            after == null) {
          throw const FormatException('crypto_migration_origin_inventory');
        }
        page = await access.account.directory.call('crypto2.migration.origin', {
          'scopeId': record['scopeId'],
          'domain': record['domain'],
          'id': record['id'],
          'recordProofHash': first['leaf']['recordProofHash'],
          if (evidenceFor != null) 'evidenceFor': evidenceFor,
          'afterHash': after,
          'limit': 50,
        });
        if (!same(
              page['certificateAuthorization'],
              first['certificateAuthorization'],
            ) ||
            !same(page['leaf'], first['leaf'])) {
          throw const FormatException('crypto_migration_origin_inventory');
        }
      }
    }

    var complete = false;
    try {
      if (await CryptoMigrationCommitmentsV3.domainRoot(header, hashes()) !=
              root ||
          !found) {
        throw const FormatException('crypto_migration_origin_inventory');
      }
      contributionSink.close();
      if (CryptoMigrationBusinessParityV3.hex(
            (await contributionSink.hash()).bytes,
          ) !=
          contributionRoot) {
        throw const FormatException('crypto_migration_origin_contribution');
      }
      _domainRuns[runKey] = run;
      complete = true;
      if (prior != null) {
        await db.execute(
          'DELETE FROM crypto_migration_read_digests WHERE partition=? AND run_id=?',
          [partition, prior],
        );
      }
      while (_domainRuns.length > 8) {
        final key = _domainRuns.keys.first,
            oldRun = _domainRuns.remove(_domainRuns.keys.first)!;
        if (key == runKey) {
          throw const FormatException('crypto_migration_origin_cache');
        }
        await db.execute(
          'DELETE FROM crypto_migration_read_digests WHERE partition=? AND run_id=?',
          [partition, oldRun],
        );
      }
    } finally {
      if (!complete) {
        await db.execute(
          'DELETE FROM crypto_migration_read_digests WHERE partition=? AND run_id=?',
          [partition, run],
        );
      }
    }
  }

  Future<String> _reserved(String scope, String namespace) async {
    final h = await cryptoSha256(
      utf8.encode('JivieReservedRecord/v2\n$server:$scope:$namespace'),
    );
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-a${h.substring(17, 20)}-${h.substring(20, 32)}';
  }
}
