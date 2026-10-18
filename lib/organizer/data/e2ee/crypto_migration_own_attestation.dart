import 'dart:convert';
import 'dart:typed_data';

import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart';
import 'crypto_account_archive.dart';
import 'crypto_capture_legacy.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_business_parity_v3.dart';
import 'crypto_migration_commitments_v3.dart';
import 'crypto_migration_committed_origin.dart';
import 'crypto_migration_invitation_codec.dart';
import 'crypto_migration_notification_codec.dart';
import 'crypto_migration_receipt_codec.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart' show CryptoAuthorityPending;
import 'session_crypto_access.dart'
    show SessionCryptoAccess, VerifiedRecoveredMigrationGenesis;

/// An own FILE-rooted commitment to one CONTENT genesis header. This is only
/// provisional identity evidence for the private descriptor reader; the final
/// certificate/activation must still be verified before ordinary admission.
final class VerifiedCryptoOwnContentContribution {
  VerifiedCryptoOwnContentContribution._(
    this._account,
    this.ownHeadHash,
    this.scopeId,
    this.headHash,
    this.migrationId,
    this.headerHash,
    this.certificateHash,
    this.commandHash,
    Map<String, dynamic> contribution,
  ) : _contribution = CryptoJson.encode(contribution);
  final AccountCryptoV2Workflow _account;
  final String ownHeadHash,
      scopeId,
      headHash,
      migrationId,
      headerHash,
      certificateHash,
      commandHash;
  final List<int> _contribution;
  Map<String, dynamic> get contribution => Map<String, dynamic>.from(
    CryptoJson.decode(Uint8List.fromList(_contribution)) as Map,
  );

  Future<void> requireCurrent(
    AccountCryptoV2Workflow account, {
    required String scope,
    required String genesisHash,
    Map<String, dynamic>? certificate,
  }) async {
    if (!identical(account, _account) ||
        !account.directory.isCurrent() ||
        scope != scopeId ||
        genesisHash != headHash ||
        (await account.directory.cachedVerifiedDirectory()).headHash !=
            ownHeadHash ||
        certificate != null &&
            await cryptoSha256(CryptoJson.encode(certificate)) !=
                certificateHash) {
      throw const CryptoAuthorityPending('scope_recovery_publication_changed');
    }
  }
}

/// A routing classification, never scope/key/write authority. Only this verifier
/// can create it after an original signature intersects the verified own log.
class VerifiedCryptoOwnAttestation {
  VerifiedCryptoOwnAttestation._(
    this.kind,
    this.descriptor, [
    this.scopedClaim,
    Set<String> coveredCommands = const {},
  ]) : _coveredCommands = Set.unmodifiable(coveredCommands);
  final String kind;
  final Map<String, dynamic>? descriptor;
  final Map<String, dynamic>? scopedClaim;
  final Set<String> _coveredCommands;
  Future<Set<String>> coveredCommandsFor(
    VerifiedRecoveredMigrationGenesis recovered,
  ) async =>
      await matchesRecoveredGenesis(recovered) ? _coveredCommands : const {};
  bool get privateControl => kind == 'privateControl';
  bool get privateArtifact => kind == 'privateArtifact';
  bool get scopedContribution => kind == 'scopedContribution';

  /// Routing alone cannot settle an own contribution. Require ordinary READ
  /// and the exact contribution/event in the fully verified final certificate.
  Future<bool> matchesFinalFinanceContribution(
    SessionCryptoAccess access,
    VerifiedRecoveredMigrationGenesis recovered,
  ) async {
    if (!scopedContribution || descriptor == null || scopedClaim == null) {
      return false;
    }
    final claim = scopedClaim!;
    if (claim['domain'] != 'finance' ||
        claim['migrationId'] != recovered.migrationId ||
        claim['scopeToken'] !=
            await CryptoMigrationCommitmentsV3.scopeToken(
              serverId: access.account.directory.session.profile.serverId,
              migrationId: recovered.migrationId,
              scopeId: recovered.scopeId,
              domain: 'finance',
            )) {
      return false;
    }
    // This is the normal authority path, after FILE recovery completed the
    // scope. No genesis candidate or provisional verifier is accepted here.
    final read = await access.readContext(recovered.scopeId, 'finance');
    final normal = await access.recoveredMigrationGenesis(recovered.scopeId);
    if (normal == null ||
        normal.headHash != recovered.headHash ||
        normal.migrationId != recovered.migrationId) {
      throw const CryptoAuthorityPending(
        'crypto_own_attestation_scoped_pending',
      );
    }
    final own = await access.account.directory.cachedVerifiedDirectory();
    final page = await access.account.directory.call(
      'crypto2.migration.audit.list',
      {'scopeId': recovered.scopeId, 'limit': 1},
    );
    if (page['version'] != 3 ||
        page['scopeId'] != recovered.scopeId ||
        page['migrationId'] != recovered.migrationId ||
        page['contexts'] is! List ||
        (page['contexts'] as List).isEmpty ||
        (page['contexts'] as List).length > 100) {
      throw const FormatException(
        'crypto_own_attestation_contribution_context',
      );
    }
    final same = CryptoMigrationCommittedOrigin.same;
    final contexts = (page['contexts'] as List)
        .where(
          (c) =>
              c is Map &&
              same(
                c['contributionAuthorization'],
                descriptor!['authorization'],
              ) &&
              same(
                c['contributionEventAuthorization'],
                descriptor!['eventAuthorization'],
              ),
        )
        .toList();
    if (contexts.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_own_attestation_scoped_pending',
      );
    }
    final context = Map<String, dynamic>.from(contexts.single as Map);
    final verified = await CryptoMigrationCommittedOrigin(access)
        .verifyControlEvidence(
          evidence: {
            ...Map<String, dynamic>.from(page['activationEvidence'] as Map),
            'controls': context['controls'],
          },
          contributionAuthorization: Map<String, dynamic>.from(
            descriptor!['authorization'] as Map,
          ),
          contributionEventAuthorization: Map<String, dynamic>.from(
            descriptor!['eventAuthorization'] as Map,
          ),
          certificateAuthorization: Map<String, dynamic>.from(
            page['certificateAuthorization'] as Map,
          ),
          certificateEventAuthorization: Map<String, dynamic>.from(
            page['certificateEventAuthorization'] as Map,
          ),
        );
    if (verified.activation['scopeId'] != recovered.scopeId ||
        verified.activation['membershipHeadHash'] != recovered.headHash ||
        verified.activation['migrationId'] != recovered.migrationId ||
        !same(verified.contributionHeader, claim)) {
      throw const FormatException(
        'crypto_own_attestation_contribution_context',
      );
    }
    if (!access.account.directory.isCurrent() ||
        (await access.account.directory.cachedVerifiedDirectory()).headHash !=
            own.headHash ||
        (await access.readContext(recovered.scopeId, 'finance')).headHash !=
            read.headHash) {
      throw const CryptoAuthorityPending('scope_recovery_publication_changed');
    }
    return true;
  }

  /// Discovery/completeness only, after the caller independently recovers this
  /// exact genesis and migration through the full final publication verifier.
  Future<bool> matchesRecoveredGenesis(
    VerifiedRecoveredMigrationGenesis recovered,
  ) async {
    final claim = scopedClaim;
    if (kind != 'scopedSource' ||
        claim == null ||
        claim['migrationId'] != recovered.migrationId ||
        claim['membershipHeadHash'] != recovered.headHash) {
      return false;
    }
    if (claim['scopeId'] != null) return claim['scopeId'] == recovered.scopeId;
    final token = await cryptoSha256([
      ...utf8.encode('JivieStructureSourceToken/v3\n'),
      ...CryptoJson.encode({
        'version': 3,
        'serverId': claim['serverId'],
        'migrationId': recovered.migrationId,
        'accountId': claim['accountId'],
        'scopeId': recovered.scopeId,
      }),
    ]);
    return token == claim['scopeToken'];
  }
}

class CryptoMigrationOwnAttestation {
  CryptoMigrationOwnAttestation(this.account, this.own);
  final AccountCryptoV2Workflow account;
  final VerifiedAccountDirectory own;
  final _prefixes = <String, VerifiedAccountDirectory>{};

  /// The untrusted certificate is only a carrier for the exact OWN signed
  /// header commitment. Its manager authority is checked later by the complete
  /// committed-origin reader, never inferred here from the server response.
  Future<VerifiedCryptoOwnContentContribution> contentGenesisContribution({
    required String scopeId,
    required String headHash,
    required Map<String, dynamic> certificateAuthorization,
  }) async {
    if (!account.directory.isCurrent() ||
        (await account.directory.cachedVerifiedDirectory()).headHash !=
            own.headHash) {
      throw const CryptoAuthorityPending('scope_recovery_identity_changed');
    }
    final certificate = _body(certificateAuthorization),
        p = _map(certificate['payload']),
        h = _map(p['header']);
    _exact(p, {'header', 'domainRoot', 'assignments', 'contributions'});
    await CryptoMigrationCommitmentsV3.validateHeader(h);
    final contributions = p['contributions'], assignments = p['assignments'];
    if (certificate['operation'] != 'crypto2.migration.domains.certify' ||
        certificate['serverId'] != own.serverId ||
        h['serverId'] != own.serverId ||
        h['scopeId'] != scopeId ||
        h['membershipHeadHash'] != headHash ||
        h['domain'] != 'content' ||
        contributions is! List ||
        contributions.isEmpty ||
        contributions.length > 1000 ||
        assignments is! List ||
        assignments.length != contributions.length) {
      throw const FormatException('crypto_own_content_genesis_context');
    }
    final selected = contributions
        .where((c) => c is Map && c['accountId'] == own.accountId)
        .toList();
    final assigned = assignments
        .where((a) => a is Map && a['accountId'] == own.accountId)
        .toList();
    if (selected.length != 1 || assigned.length != 1) {
      throw const CryptoAuthorityPending('crypto_own_content_genesis_pending');
    }
    final item = _map(selected.single);
    _exact(item, {'accountId', 'authorization', 'eventAuthorization'});
    final commandHash = await _nestedContribution(item, h);
    final ch = _map(
          _map(_body(_map(item['authorization']))['payload'])['header'],
        ),
        assignment = _map(assigned.single);
    _exact(assignment, {
      'accountId',
      'portionToken',
      'captureId',
      'sourceInventoryRoot',
      'sourceRowCount',
      'leafCount',
    });
    if (![
      'portionToken',
      'captureId',
      'sourceInventoryRoot',
      'sourceRowCount',
      'leafCount',
    ].every((k) => assignment[k] == ch[k])) {
      throw const FormatException('crypto_own_content_genesis_assignment');
    }
    final result = VerifiedCryptoOwnContentContribution._(
      account,
      own.headHash,
      scopeId,
      headHash,
      h['migrationId'],
      await CryptoMigrationCommitmentsV3.headerHash(h),
      await cryptoSha256(CryptoJson.encode(certificateAuthorization)),
      commandHash,
      item,
    );
    await result.requireCurrent(account, scope: scopeId, genesisHash: headHash);
    return result;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('crypto_own_attestation_shape');
    }
    return Map<String, dynamic>.from(value);
  }

  static void _exact(Map value, Set<String> keys) =>
      CryptoMigrationBusinessParityV3.exact(value, keys);

  static bool _archiveSegments(Object? value) {
    if (value is! List || value.isEmpty || value.length > 16) return false;
    final ids = <String>{};
    for (var index = 0; index < value.length; index++) {
      final item = _map(value[index]);
      _exact(item, {'id', 'index', 'size', 'sha256'});
      if (!isCryptoCanonicalUuid(item['id']) ||
          !ids.add(item['id']) ||
          item['index'] != index ||
          item['size'] is! int ||
          item['size'] < 1 ||
          item['size'] > 23068672 ||
          !CryptoMigrationBusinessParityV3.hash(item['sha256'])) {
        return false;
      }
    }
    return true;
  }

  static Map<String, dynamic> _body(Map<String, dynamic> proof) {
    _exact(proof, {'commandBase64', 'signatureBase64'});
    cryptoBase64(proof['signatureBase64'], length: 64);
    final bytes = cryptoBase64(proof['commandBase64']);
    if (bytes.length > 1024 * 1024) {
      throw const FormatException('crypto_own_attestation_capacity');
    }
    final body = _map(CryptoJson.decode(bytes));
    if (base64Encode(CryptoJson.encode(body)) != base64Encode(bytes)) {
      throw const FormatException('crypto_own_attestation_canonical');
    }
    return body;
  }

  Future<VerifiedAccountDirectory> _prefix(String hash) async {
    if (_prefixes[hash] != null) return _prefixes[hash]!;
    final pin = await account.store.anchor(own.accountId);
    if (pin == null ||
        (pin['genesisFingerprint'] ?? pin['fingerprint']) is! String) {
      throw const CryptoAuthorityPending('crypto_own_attestation_pending');
    }
    VerifiedAccountDirectory? state;
    await for (final entry in account.store.streamEntries(own.accountId)) {
      state = await account.directory.reducer.apply(
        previous: state,
        entry: entry,
        serverId: own.serverId,
        accountId: own.accountId,
        pinnedRootFingerprint: pin['genesisFingerprint'] ?? pin['fingerprint'],
      );
      if (!own.includesAnchor(state.generation, state.headHash)) {
        throw const FormatException('crypto_own_attestation_fork');
      }
      if (state.headHash == hash) {
        if (_prefixes.length >= 8) _prefixes.remove(_prefixes.keys.first);
        return _prefixes[hash] = state;
      }
    }
    throw const CryptoAuthorityPending('crypto_own_attestation_pending');
  }

  Future<void> _signature(
    Map<String, dynamic> proof,
    String reference,
    String device,
    String domain,
    int eventGeneration,
  ) async {
    final prefix = await _prefix(reference);
    if (prefix.generation >= eventGeneration) {
      throw const FormatException('crypto_own_attestation_signer_timing');
    }
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(prefix.activeDevice(device)['signingKeyBase64'], length: 32),
      domain,
    );
  }

  void _artifactSignature(Map<String, dynamic> proof, String device) {
    // The earlier included event authenticates the descriptor itself. A later
    // verify3 may be signed by a replacement device; this signature establishes
    // own-account routing only, never historical scope or write authority.
    final matches = own.devices.where((d) => d['deviceId'] == device).toList();
    if (matches.length != 1) {
      throw const CryptoAuthorityPending('crypto_own_attestation_pending');
    }
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(matches.single['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
  }

  /// Unknown, absent or ambiguous proofs remain incomplete. In particular an
  /// unsigned server classification never removes a scope-recovery obligation.
  Future<String> _includedOwnEvent(Map<String, dynamic> proof) async {
    final body = _body(proof), p = _map(body['payload']);
    if (body['operation'] != 'crypto2.account.migrationAttest' ||
        body['serverId'] != own.serverId ||
        body['accountId'] != own.accountId) {
      throw const FormatException('crypto_own_attestation_nested_event');
    }
    final commandHash = await cryptoSha256(
      cryptoBase64(proof['commandBase64']),
    );
    final entry = await account.store.entryByHash(own.accountId, commandHash);
    if (entry == null ||
        base64Encode(CryptoJson.encode(entry['authorization'])) !=
            base64Encode(CryptoJson.encode(proof))) {
      throw const CryptoAuthorityPending('crypto_own_attestation_pending');
    }
    final before = await _prefix(p['previousHeadHash']);
    final after = await account.directory.reducer.apply(
      previous: before,
      entry: entry,
      serverId: own.serverId,
      accountId: own.accountId,
      pinnedRootFingerprint: before.rootFingerprint,
    );
    if (!own.includesAnchor(after.generation, after.headHash)) {
      throw const FormatException('crypto_own_attestation_nested_event');
    }
    return commandHash;
  }

  Future<String> _nestedContribution(
    Map<String, dynamic> item,
    Map<String, dynamic> header,
  ) async {
    final proof = _map(item['authorization']),
        body = _body(proof),
        p = _map(body['payload']);
    _exact(body, {
      'version',
      'operation',
      'serverId',
      'accountId',
      'deviceId',
      'requestId',
      'signer',
      'payload',
    });
    _exact(p, {
      'header',
      'leafSetRoot',
      'controlSections',
      'scopeControlSections',
      'controlLinks',
    });
    final h = _map(p['header']);
    CryptoMigrationCommitmentsV3.validateContribution(h);
    final sections = _map(p['controlSections']),
        links = _map(p['controlLinks']);
    _exact(sections, CryptoMigrationBusinessParityV3.requiredSections);
    for (final kind in sections.keys) {
      final section = _map(sections[kind]);
      _exact(section, {'kind', 'count', 'root'});
      if (section['kind'] != kind ||
          !CryptoMigrationBusinessParityV3.count(section['count']) ||
          !CryptoMigrationBusinessParityV3.hash(section['root'])) {
        throw const FormatException(
          'crypto_own_attestation_nested_contribution',
        );
      }
    }
    final scoped = _map(p['scopeControlSections']);
    _exact(scoped, {'audit'});
    final scopedAudit = _map(scoped['audit']);
    _exact(scopedAudit, {'kind', 'count', 'root'});
    if (scopedAudit['kind'] != 'audit' ||
        !CryptoMigrationBusinessParityV3.count(scopedAudit['count']) ||
        !CryptoMigrationBusinessParityV3.hash(scopedAudit['root'])) {
      throw const FormatException('crypto_own_attestation_nested_contribution');
    }
    _exact(links, {'invitations', 'notifications'});
    for (final raw in links.values) {
      final link = _map(raw);
      _exact(link, {'certificateHash', 'eventCommandHash'});
      if (!link.values.every(CryptoMigrationBusinessParityV3.hash)) {
        throw const FormatException(
          'crypto_own_attestation_nested_contribution',
        );
      }
    }
    final event = _map(item['eventAuthorization']),
        eventBody = _body(event),
        ep = _map(eventBody['payload']);
    final commandHash = await _includedOwnEvent(event);
    if (body['version'] != 2 ||
        body['signer'] != 'device' ||
        body['operation'] != 'crypto2.migration.domains.contribute' ||
        body['accountId'] != own.accountId ||
        body['serverId'] != own.serverId ||
        !isCryptoCanonicalUuid(body['requestId']) ||
        !CryptoMigrationBusinessParityV3.hash(p['leafSetRoot']) ||
        h['headerHash'] !=
            await CryptoMigrationCommitmentsV3.headerHash(header) ||
        h['scopeToken'] != header['scopeToken'] ||
        h['migrationId'] != header['migrationId'] ||
        h['domain'] != header['domain'] ||
        ep['migrationId'] != h['migrationId'] ||
        ep['domain'] != h['domain'] ||
        ep['scopeToken'] != h['scopeToken'] ||
        ep['attestationHash'] != await cryptoSha256(CryptoJson.encode(proof))) {
      throw const FormatException('crypto_own_attestation_nested_contribution');
    }
    await _signature(
      proof,
      h['authorDirectoryHeadHash'],
      body['deviceId'],
      cryptoDirectoryDomain,
      ep['expectedGeneration'] + 1,
    );
    return commandHash;
  }

  Future<VerifiedCryptoOwnAttestation> classify(
    Map<String, dynamic> entry,
  ) async {
    final event = _map(entry['authorization']), eventBody = _body(event);
    final ep = _map(eventBody['payload']);
    _exact(eventBody, {
      'version',
      'operation',
      'serverId',
      'accountId',
      'deviceId',
      'requestId',
      'signer',
      'payload',
    });
    _exact(ep, {
      'expectedGeneration',
      'previousHeadHash',
      'identityEpochId',
      'resultingSnapshotHash',
      'migrationId',
      'domain',
      'scopeToken',
      'attestationHash',
    });
    final commandHash = await cryptoSha256(
      cryptoBase64(event['commandBase64']),
    );
    final generation = entry['generation'];
    final eventHash = await cryptoSha256([
      ...utf8.encode(cryptoDirectoryLogDomain),
      ...CryptoJson.encode({
        'serverId': own.serverId,
        'accountId': own.accountId,
        'generation': generation,
        'previousHeadHash': ep['previousHeadHash'],
        'commandHash': commandHash,
        'signatureBase64': event['signatureBase64'],
      }),
    ]);
    if (generation is! int ||
        generation != ep['expectedGeneration'] + 1 ||
        eventBody['version'] != 2 ||
        eventBody['signer'] != 'device' ||
        eventBody['operation'] != 'crypto2.account.migrationAttest' ||
        eventBody['serverId'] != own.serverId ||
        eventBody['accountId'] != own.accountId ||
        eventHash != entry['headHash'] ||
        !own.includesAnchor(generation, eventHash)) {
      throw const FormatException('crypto_own_attestation_inclusion');
    }
    await _signature(
      event,
      ep['previousHeadHash'],
      eventBody['deviceId'],
      cryptoDirectoryDomain,
      generation,
    );
    final response = await account.directory.call(
      'crypto2.migration.ownAttestation',
      {
        'eventCommandHash': commandHash,
        for (final key in [
          'migrationId',
          'domain',
          'scopeToken',
          'attestationHash',
        ])
          key: ep[key],
      },
    );
    _exact(response, {'eventAuthorization', 'authorizations'});
    if (base64Encode(CryptoJson.encode(response['eventAuthorization'])) !=
        base64Encode(CryptoJson.encode(event))) {
      throw const FormatException('crypto_own_attestation_event_substitution');
    }
    final proofs = response['authorizations'];
    if (proofs is! List || proofs.length != 1) {
      throw const CryptoAuthorityPending('crypto_own_attestation_pending');
    }
    final proof = _map(proofs.single), body = _body(proof);
    final directHash = await cryptoSha256(CryptoJson.encode(proof));
    if (body['version'] == 3 &&
        body['mode'] is String &&
        body.containsKey('generationId')) {
      _exact(body, {
        'version',
        'serverId',
        'migrationId',
        'generationId',
        'mode',
        'contextHash',
        'accountId',
        'deviceId',
        'authorDirectoryHeadHash',
        'deviceSnapshotHash',
      });
      final token = await cryptoSha256([
        ...utf8.encode('JivieMigrationGenerationToken/v3\n'),
        ...CryptoJson.encode({
          'version': 3,
          'serverId': body['serverId'],
          'migrationId': body['migrationId'],
          'generationId': body['generationId'],
        }),
      ]);
      if (body['serverId'] != own.serverId ||
          body['accountId'] != own.accountId ||
          body['migrationId'] != ep['migrationId'] ||
          !isCryptoCanonicalUuid(body['generationId']) ||
          !isCryptoCanonicalUuid(body['deviceId']) ||
          !const {'supersede', 'continue'}.contains(body['mode']) ||
          ep['domain'] != 'content' ||
          token != ep['scopeToken'] ||
          directHash != ep['attestationHash'] ||
          ![
            'contextHash',
            'authorDirectoryHeadHash',
            'deviceSnapshotHash',
          ].every((k) => CryptoMigrationBusinessParityV3.hash(body[k]))) {
        throw const FormatException('crypto_own_attestation_generation');
      }
      await _signature(
        proof,
        body['authorDirectoryHeadHash'],
        body['deviceId'],
        'JivieMigrationGenerationApproval/v3\n',
        generation,
      );
      return VerifiedCryptoOwnAttestation._('privateControl', null);
    }
    if (body['operation'] == 'crypto2.migration.structure.sourceCertificate') {
      _exact(body, {
        'version',
        'serverId',
        'migrationId',
        'captureId',
        'accountId',
        'sourceInventoryRoot',
        'membershipHeadHash',
        'sourceBindingCount',
        'sourceCommitmentRoot',
        'contentStructureHash',
        'deviceId',
        'authorDirectoryHeadHash',
        'operation',
        'scopeToken',
        'sourceStatementHash',
      });
      CryptoMigrationReceiptCodec.common({
        for (final key in [
          'version',
          'serverId',
          'migrationId',
          'captureId',
          'accountId',
          'sourceInventoryRoot',
        ])
          key: body[key],
      });
      if (body['serverId'] != own.serverId ||
          body['accountId'] != own.accountId ||
          body['migrationId'] != ep['migrationId'] ||
          body['scopeToken'] != ep['scopeToken'] ||
          ep['domain'] != 'content' ||
          directHash != ep['attestationHash'] ||
          !isCryptoCanonicalUuid(body['deviceId']) ||
          !CryptoMigrationBusinessParityV3.count(body['sourceBindingCount']) ||
          ![
            'membershipHeadHash',
            'sourceCommitmentRoot',
            'contentStructureHash',
            'authorDirectoryHeadHash',
            'sourceStatementHash',
            'scopeToken',
          ].every((key) => CryptoMigrationBusinessParityV3.hash(body[key]))) {
        throw const FormatException('crypto_own_attestation_scoped_source');
      }
      await _signature(
        proof,
        body['authorDirectoryHeadHash'],
        body['deviceId'],
        'JivieE2EE/structureSourceCertificate/v3\n',
        generation,
      );
      return VerifiedCryptoOwnAttestation._(
        'scopedSource',
        null,
        Map<String, dynamic>.unmodifiable(body),
      );
    }
    // Scoped attestations already covered by full genesis recovery need no
    // classifier. Uncovered scoped/unknown operations remain obligations.
    if (body['version'] != 2 ||
        body['signer'] != 'device' ||
        body['serverId'] != own.serverId ||
        body['accountId'] != own.accountId) {
      throw const CryptoAuthorityPending(
        'crypto_own_attestation_scoped_pending',
      );
    }
    _exact(body, {
      'version',
      'operation',
      'serverId',
      'accountId',
      'deviceId',
      'requestId',
      'signer',
      'payload',
    });
    if (!isCryptoCanonicalUuid(body['requestId']) ||
        !isCryptoCanonicalUuid(body['deviceId'])) {
      throw const FormatException('crypto_own_attestation_command');
    }
    final p = _map(body['payload']);
    String reference;
    switch (body['operation']) {
      case 'crypto2.migration.domains.contribute':
        _exact(p, {
          'header',
          'leafSetRoot',
          'controlSections',
          'scopeControlSections',
          'controlLinks',
        });
        final h = _map(p['header']);
        CryptoMigrationCommitmentsV3.validateContribution(h);
        if (h['domain'] != 'finance' ||
            h['serverId'] != own.serverId ||
            h['migrationId'] != ep['migrationId'] ||
            h['domain'] != ep['domain'] ||
            h['scopeToken'] != ep['scopeToken'] ||
            directHash != ep['attestationHash']) {
          throw const CryptoAuthorityPending(
            'crypto_own_attestation_scoped_pending',
          );
        }
        await _signature(
          proof,
          h['authorDirectoryHeadHash'],
          body['deviceId'],
          cryptoDirectoryDomain,
          generation,
        );
        return VerifiedCryptoOwnAttestation._(
          'scopedContribution',
          Map<String, dynamic>.unmodifiable({
            'authorization': proof,
            'eventAuthorization': event,
          }),
          Map<String, dynamic>.unmodifiable(h),
        );
      case 'crypto2.migration.domains.certify':
        _exact(p, {'header', 'domainRoot', 'assignments', 'contributions'});
        final h = _map(p['header']);
        await CryptoMigrationCommitmentsV3.validateHeader(h);
        final assignments = p['assignments'],
            contributions = p['contributions'];
        if (assignments is! List ||
            assignments.length > 1000 ||
            assignments.isEmpty ||
            contributions is! List ||
            contributions.length != assignments.length ||
            !CryptoMigrationBusinessParityV3.hash(p['domainRoot'])) {
          throw const FormatException('crypto_own_attestation_domain');
        }
        String? prior;
        final ownContributions = <String>{};
        for (var i = 0; i < assignments.length; i++) {
          final a = _map(assignments[i]), c = _map(contributions[i]);
          _exact(a, {
            'accountId',
            'portionToken',
            'captureId',
            'sourceInventoryRoot',
            'sourceRowCount',
            'leafCount',
          });
          _exact(c, {'accountId', 'authorization', 'eventAuthorization'});
          if (!isCryptoCanonicalUuid(a['accountId']) ||
              !isCryptoCanonicalUuid(a['captureId']) ||
              prior != null && prior.compareTo(a['accountId']) >= 0 ||
              c['accountId'] != a['accountId'] ||
              ![
                'portionToken',
                'sourceInventoryRoot',
              ].every((key) => CryptoMigrationBusinessParityV3.hash(a[key])) ||
              ![
                'sourceRowCount',
                'leafCount',
              ].every((key) => CryptoMigrationBusinessParityV3.count(a[key]))) {
            throw const FormatException('crypto_own_attestation_domain');
          }
          _body(_map(c['authorization']));
          _body(_map(c['eventAuthorization']));
          prior = a['accountId'];
          if (c['accountId'] == own.accountId)
            ownContributions.add(await _nestedContribution(c, h));
        }
        if (directHash != ep['attestationHash'] ||
            h['migrationId'] != ep['migrationId'] ||
            h['domain'] != ep['domain'] ||
            h['scopeToken'] != ep['scopeToken'] ||
            h['serverId'] != own.serverId ||
            h['managerAccountId'] != own.accountId) {
          throw const FormatException('crypto_own_attestation_domain');
        }
        await _signature(
          proof,
          h['managerDirectoryHeadHash'],
          body['deviceId'],
          cryptoDirectoryDomain,
          generation,
        );
        return VerifiedCryptoOwnAttestation._(
          'scopedSource',
          null,
          Map<String, dynamic>.unmodifiable({
            'scopeId': h['scopeId'],
            'membershipHeadHash': h['membershipHeadHash'],
            'migrationId': h['migrationId'],
          }),
          ownContributions,
        );
      case 'crypto2.migration.invitations.certify':
      case 'crypto2.migration.notifications.certify':
        _exact(p, {'header'});
        final h = _map(p['header']);
        final invitations =
            body['operation'] == 'crypto2.migration.invitations.certify';
        if (invitations) {
          CryptoMigrationInvitationCodec.header(h);
        } else {
          CryptoMigrationNotificationCodec.header(h);
        }
        final token = invitations
            ? await CryptoMigrationInvitationCodec.scopeToken(h)
            : await CryptoMigrationNotificationCodec.scopeToken(h);
        if (directHash != ep['attestationHash'] ||
            token != ep['scopeToken'] ||
            h['migrationId'] != ep['migrationId'] ||
            ep['domain'] != 'content' ||
            h['serverId'] != own.serverId ||
            h['accountId'] != own.accountId) {
          throw const FormatException('crypto_own_attestation_control');
        }
        reference = h['authorDirectoryHeadHash'];
        await _signature(
          proof,
          reference,
          body['deviceId'],
          cryptoDirectoryDomain,
          generation,
        );
        return VerifiedCryptoOwnAttestation._('privateControl', null);
      case 'crypto2.migration.legacy.certify':
        _exact(p, {
          'header',
          'manifestRoot',
          'authorDirectoryHeadHash',
          'archiveSegments',
        });
        final h = _map(p['header']);
        // Reconstructing the closed header also checks all routing/hash fields.
        final checked = CryptoLegacyReceiptInventory.header(
          serverId: h['serverId'],
          accountId: h['accountId'],
          captureId: h['captureId'],
          migrationId: h['migrationId'],
          domain: h['domain'],
          sourceInventoryRoot: h['sourceInventoryRoot'],
          archiveManifestHash: h['archiveManifestHash'],
          receiptSelectionHash: h['receiptSelectionHash'],
          receiptCount: h['receiptCount'],
        );
        if (base64Encode(CryptoJson.encode(checked)) !=
                base64Encode(CryptoJson.encode(h)) ||
            !_archiveSegments(p['archiveSegments']) ||
            !CryptoMigrationBusinessParityV3.hash(p['manifestRoot']) ||
            directHash != ep['attestationHash'] ||
            h['migrationId'] != ep['migrationId'] ||
            h['domain'] != ep['domain'] ||
            h['serverId'] != own.serverId ||
            h['accountId'] != own.accountId ||
            await CryptoLegacyReceiptInventory.scopeToken(h) !=
                ep['scopeToken']) {
          throw const FormatException('crypto_own_attestation_receipts');
        }
        reference = p['authorDirectoryHeadHash'];
        await _signature(
          proof,
          reference,
          body['deviceId'],
          cryptoDirectoryDomain,
          generation,
        );
        return VerifiedCryptoOwnAttestation._('privateControl', null);
      case 'crypto2.migration.verify3':
        _exact(p, {'header', 'summary', 'localIntent'});
        final header = _map(p['header']);
        _exact(header, {
          'version',
          'serverId',
          'migrationId',
          'captureId',
          'componentId',
          'componentCommitment',
          'accountId',
          'sourceInventoryRoot',
          'sourceCount',
          'archiveManifestHash',
        });
        final summary = _map(p['summary']);
        _exact(summary, {
          'version',
          'sourceRowCount',
          'primaryRecordProofCount',
          'companionProofCount',
          'archiveContextRowCount',
          'userFileCount',
          'userFileBytes',
          'witnessBlobCount',
          'adapterCounts',
          'hash',
        });
        final adapterCounts = _map(summary['adapterCounts']);
        _exact(adapterCounts, CryptoMigrationBusinessParityV3.adapters);
        if (header['version'] != 3 ||
            summary['version'] != 3 ||
            !isCryptoCanonicalUuid(header['componentId']) ||
            !CryptoMigrationBusinessParityV3.count(header['sourceCount']) ||
            !['componentCommitment', 'archiveManifestHash'].every(
              (key) => CryptoMigrationBusinessParityV3.hash(header[key]),
            ) ||
            !CryptoMigrationBusinessParityV3.hash(summary['hash']) ||
            !summary.entries
                .where(
                  (e) => !{'version', 'adapterCounts', 'hash'}.contains(e.key),
                )
                .every((e) => CryptoMigrationBusinessParityV3.count(e.value)) ||
            !adapterCounts.values.every(
              CryptoMigrationBusinessParityV3.count,
            )) {
          throw const FormatException('crypto_own_attestation_artifact');
        }
        final local = _map(p['localIntent']);
        _exact(local, {'descriptor', 'eventAuthorization'});
        final descriptor = _map(local['descriptor']);
        _exact(descriptor, {'context', 'manifest', 'intentCount'});
        final context = _map(descriptor['context']);
        _exact(context, {
          'version',
          'serverId',
          'migrationId',
          'captureId',
          'accountId',
          'sourceInventoryRoot',
          'artifactId',
          'purpose',
        });
        CryptoMigrationReceiptCodec.common({
          for (final key in [
            'version',
            'serverId',
            'migrationId',
            'captureId',
            'accountId',
            'sourceInventoryRoot',
          ])
            key: context[key],
        });
        final manifest = CryptoArchiveManifest.fromJson(
          _map(descriptor['manifest']),
        );
        _exact(_map(descriptor['manifest']), {
          'migrationId',
          'keyId',
          'segments',
          'cipherManifestHash',
          'artifactId',
          'artifactKind',
          'artifactContext',
        });
        if (!_archiveSegments(descriptor['manifest']['segments']) ||
            !isCryptoCanonicalUuid(manifest.keyId) ||
            !CryptoMigrationBusinessParityV3.hash(
              manifest.cipherManifestHash,
            ) ||
            base64Encode(CryptoJson.encode(manifest.artifactContext)) !=
                base64Encode(CryptoJson.encode(context)) ||
            [
              'serverId',
              'migrationId',
              'captureId',
              'accountId',
              'sourceInventoryRoot',
            ].any((key) => header[key] != context[key])) {
          throw const FormatException('crypto_own_attestation_artifact');
        }
        final token = await cryptoSha256([
          ...utf8.encode('JivieMigrationLocalIntentToken/v3\n'),
          ...CryptoInventoryJson.encode(
            Map<String, dynamic>.from(context)..remove('purpose'),
          ),
        ]);
        if (context['purpose'] != 'migrationLocalIntents' ||
            context['serverId'] != own.serverId ||
            context['accountId'] != own.accountId ||
            context['migrationId'] != ep['migrationId'] ||
            ep['domain'] != 'content' ||
            !isCryptoCanonicalUuid(context['artifactId']) ||
            manifest.artifactKind != 'migrationLocalIntentsV3' ||
            manifest.artifactId != context['artifactId'] ||
            manifest.migrationId != ep['migrationId'] ||
            !CryptoMigrationBusinessParityV3.count(descriptor['intentCount']) ||
            token != ep['scopeToken'] ||
            await cryptoSha256(CryptoInventoryJson.encode(descriptor)) !=
                ep['attestationHash'] ||
            base64Encode(CryptoJson.encode(local['eventAuthorization'])) !=
                base64Encode(CryptoJson.encode(event))) {
          throw const FormatException('crypto_own_attestation_artifact');
        }
        _artifactSignature(proof, body['deviceId']);
        return VerifiedCryptoOwnAttestation._(
          'privateArtifact',
          Map<String, dynamic>.unmodifiable(descriptor),
        );
      default:
        throw const CryptoAuthorityPending(
          'crypto_own_attestation_scoped_pending',
        );
    }
  }
}
