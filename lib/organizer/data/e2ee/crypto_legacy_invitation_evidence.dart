import 'dart:convert';
import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_legacy_invitation_capsule.dart';
import 'crypto_migration_invitation_codec.dart';
import 'crypto_migration_activation_v3.dart';
import 'crypto_migration_commitments_v3.dart';
import 'scope_crypto_codec.dart';

/// Checks a token-specific retained bridge against a complete verified creator
/// directory prefix. The caller still performs independent identity comparison;
/// a server-delivered root or successful capsule opening is not a trust pin.
class VerifiedCryptoLegacyInvitationEvidence {
  VerifiedCryptoLegacyInvitationEvidence._(
    Map<String, dynamic> value,
    this.creatorAccountId,
    this.creatorProofHash,
  ) : acceptancePayload = Map.unmodifiable(value);
  final Map<String, dynamic> acceptancePayload;
  final String creatorAccountId, creatorProofHash;
}

Future<VerifiedCryptoLegacyInvitationEvidence>
verifyCryptoLegacyInvitationEvidence({
  required CryptoLegacyInvitationCapsule capsules,
  required Map<String, dynamic> proof,
  required Map<String, dynamic> evidence,
  required Map<String, dynamic> invitation,
  required VerifiedAccountDirectory creator,
  required Future<VerifiedAccountDirectory> Function(String) directoryAt,
  required Future<Map<String, dynamic>> Function(String?) digestPage,
  Future<Map<String, dynamic>> Function(int afterGeneration)?
  activationDirectoryPage,
  required Future<void> Function(VerifiedAccountDirectory) requireKnownPrefix,
  Future<void> Function(Map<String, dynamic> originalRecipient)?
  verifyRecipientBinding,
  String? token,
  bool compareRecipient = true,
}) async {
  final codec = capsules.crypto;
  await requireKnownPrefix(creator);
  Map<String, dynamic> body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  Future<Map<String, dynamic>> verify(
    Map<String, dynamic> signed,
    String reference,
    String device,
  ) async {
    final prefix = await directoryAt(reference);
    if (!creator.includesAnchor(prefix.generation, prefix.headHash)) {
      throw const FormatException('crypto_invitation_bridge_directory');
    }
    final actor = prefix.activeDevice(device);
    return codec.verifyDomain(
      signed,
      cryptoBase64(actor['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
  }

  final command = body(proof),
      p = Map<String, dynamic>.from(command['payload'] as Map),
      context = Map<String, dynamic>.from(p['context'] as Map);
  CryptoMigrationInvitationCodec.fields(command, {
    'version',
    'operation',
    'requestId',
    'serverId',
    'accountId',
    'deviceId',
    'signer',
    'payload',
  });
  CryptoMigrationInvitationCodec.fields(p, {
    'context',
    'sourceKind',
    'invitationBindingId',
    'authorDirectoryHeadHash',
    'capsuleHash',
    'capsuleSize',
  });
  if (command['version'] != 2 ||
      command['operation'] != 'crypto2.invitations.bridgeLegacy' ||
      command['signer'] != 'device' ||
      command['serverId'] != creator.serverId ||
      command['accountId'] != creator.accountId ||
      p['sourceKind'] != 'invitation' ||
      p['invitationBindingId'] != context['bindingId']) {
    throw const FormatException('crypto_invitation_bridge_context');
  }
  await verify(proof, p['authorDirectoryHeadHash'], command['deviceId']);
  final encoded = cryptoBase64(evidence['capsuleBase64']);
  if (encoded.length > 24576 ||
      encoded.length != p['capsuleSize'] ||
      await cryptoSha256(encoded) != p['capsuleHash']) {
    throw const FormatException('crypto_invitation_bridge_capsule');
  }
  final envelope = Map<String, dynamic>.from(CryptoJson.decode(encoded) as Map);
  final metadata = token == null
      ? capsules.openUntrustedMetadataFromHash(
          envelope: envelope,
          context: context,
          oldTokenHash: invitation['tokenHash'],
        )
      : await capsules.openUntrustedMetadata(
          envelope: envelope,
          context: context,
          token: token,
        );
  if (metadata['invitationId'] != invitation['id'] ||
      metadata['scopeId'] != invitation['scopeId'] ||
      metadata['tokenHash'] != invitation['tokenHash'] ||
      metadata['role'] != invitation['role'] ||
      metadata['expiresAtEpoch'] != invitation['expiresAtEpoch'] ||
      metadata['acceptedAtEpoch'] != null ||
      metadata['revokedAtEpoch'] != null) {
    throw const FormatException('crypto_invitation_bridge_binding');
  }
  if (compareRecipient &&
      base64Encode(CryptoJson.encode(metadata['recipient'])) !=
          base64Encode(CryptoJson.encode(invitation['recipient']))) {
    final original = Map<String, dynamic>.from(metadata['recipient'] as Map),
        current = Map<String, dynamic>.from(invitation['recipient'] as Map);
    if (original['kind'] != 'email' ||
        original['kind'] != current['kind'] ||
        original['value'] != current['value'] ||
        original['accountId'] != null ||
        current['accountId'] is! String ||
        verifyRecipientBinding == null) {
      throw const FormatException('crypto_invitation_bridge_recipient');
    }
    await verifyRecipientBinding(original);
  }
  final cert = Map<String, dynamic>.from(
        evidence['certificateAuthorization'] as Map,
      ),
      c = body(cert);
  CryptoMigrationInvitationCodec.fields(c, {
    'version',
    'operation',
    'requestId',
    'serverId',
    'accountId',
    'deviceId',
    'signer',
    'payload',
  });
  CryptoMigrationInvitationCodec.fields(c['payload'] as Map, {'header'});
  final h = Map<String, dynamic>.from(c['payload']['header'] as Map);
  CryptoMigrationInvitationCodec.header(h);
  if (c['version'] != 2 ||
      c['operation'] != 'crypto2.migration.invitations.certify' ||
      c['signer'] != 'device' ||
      c['serverId'] != creator.serverId ||
      c['accountId'] != creator.accountId ||
      h['accountId'] != creator.accountId) {
    throw const FormatException('crypto_invitation_bridge_certificate');
  }
  for (final k in [
    'serverId',
    'migrationId',
    'captureId',
    'sourceInventoryRoot',
  ]) {
    if (h[k] != context[k]) {
      throw const FormatException('crypto_invitation_bridge_certificate');
    }
  }
  await verify(cert, h['authorDirectoryHeadHash'], c['deviceId']);
  final certHash = await cryptoSha256(CryptoJson.encode(cert));
  final event = Map<String, dynamic>.from(
        evidence['eventAuthorization'] as Map,
      ),
      e = body(event);
  if (e['operation'] != 'crypto2.account.migrationAttest' ||
      e['accountId'] != creator.accountId ||
      e['serverId'] != creator.serverId ||
      e['payload']['migrationId'] != h['migrationId'] ||
      e['payload']['domain'] != 'content' ||
      e['payload']['scopeToken'] !=
          await CryptoMigrationInvitationCodec.scopeToken(h) ||
      e['payload']['attestationHash'] != certHash ||
      await cryptoSha256(cryptoBase64(event['commandBase64'])) !=
          evidence['eventCommandHash']) {
    throw const FormatException('crypto_invitation_bridge_event');
  }
  final included = await directoryAt(evidence['eventHeadHash']);
  if (!creator.includesAnchor(included.generation, included.headHash) ||
      included.generation != e['payload']['expectedGeneration'] + 1 ||
      included.headHash !=
          await cryptoSha256([
            ...utf8.encode(cryptoDirectoryLogDomain),
            ...CryptoJson.encode({
              'serverId': creator.serverId,
              'accountId': creator.accountId,
              'generation': included.generation,
              'previousHeadHash': e['payload']['previousHeadHash'],
              'commandHash': evidence['eventCommandHash'],
              'signatureBase64': event['signatureBase64'],
            }),
          ])) {
    throw const FormatException('crypto_invitation_bridge_event');
  }
  final bridgeHash = await cryptoSha256(CryptoJson.encode(proof));
  final ownLeaf = await CryptoMigrationInvitationCodec.leafDigest({
    'bindingId': context['bindingId'],
    'kind': 'invitation',
    'bridgeHash': bridgeHash,
    'capsuleHash': p['capsuleHash'],
  });
  var present = 0;
  Stream<String> hashes() async* {
    String? after;
    while (true) {
      final page = await digestPage(after);
      if (page['digests'] is! List ||
          (page['digests'] as List).length > 20 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_invitation_bridge_digest_page');
      }
      for (final hash in page['digests'] as List) {
        CryptoMigrationInvitationCodec.digest(hash);
        if (after != null && after.compareTo(hash) >= 0) {
          throw const FormatException('crypto_invitation_bridge_digest_order');
        }
        after = hash;
        if (hash == ownLeaf) present++;
        yield hash;
      }
      if (page['hasMore'] == false) break;
      if ((page['digests'] as List).isEmpty || page['nextAfterHash'] != after) {
        throw const FormatException('crypto_invitation_bridge_digest_cursor');
      }
    }
  }

  if (await CryptoMigrationInvitationCodec.bridgeRoot(h, hashes()) !=
          h['bridgeRoot'] ||
      present != 1) {
    throw const FormatException('crypto_invitation_bridge_inclusion');
  }
  if (activationDirectoryPage == null || evidence['cutover'] is! Map) {
    throw const FormatException('crypto_invitation_cutover_pending');
  }
  final cutover = Map<String, dynamic>.from(evidence['cutover'] as Map),
      activationProof = Map<String, dynamic>.from(
        cutover['authorization'] as Map,
      ),
      activation = body(activationProof),
      publicationEvent = Map<String, dynamic>.from(
        cutover['eventAuthorization'] as Map,
      ),
      publication = body(publicationEvent),
      headProof = Map<String, dynamic>.from(
        cutover['membershipAuthorization'] as Map,
      ),
      headCommand = body(headProof),
      headBody = Map<String, dynamic>.from(headCommand['payload'] as Map),
      scopeCodec = ScopeCryptoCodec(codec);
  CryptoMigrationActivationV3.validate(activation);
  scopeCodec.validateBody(headBody);
  if (headCommand['version'] != 2 ||
      headCommand['operation'] != 'crypto2.scope.headPut' ||
      headCommand['accountId'] != creator.accountId ||
      headCommand['serverId'] != creator.serverId ||
      headCommand['signer'] != 'device' ||
      headBody['scopeId'] != metadata['scopeId'] ||
      await scopeCodec.headHash(headBody) != context['membershipHeadHash'] ||
      activation['serverId'] != creator.serverId ||
      activation['scopeId'] != metadata['scopeId'] ||
      activation['membershipHeadHash'] != context['membershipHeadHash'] ||
      activation['migrationId'] != context['migrationId'] ||
      activation['componentCommitment'] !=
          await CryptoMigrationCommitmentsV3.componentCommitment(
            serverId: creator.serverId,
            migrationId: activation['migrationId'],
            componentId: activation['componentId'],
            inventoryCommitment: activation['inventoryCommitment'],
          )) {
    throw const FormatException('crypto_invitation_cutover_context');
  }
  await verify(
    headProof,
    headBody['authorDirectoryHeadHash'],
    headCommand['deviceId'],
  );
  final managers = (headBody['members'] as List)
      .whereType<Map>()
      .where(
        (m) =>
            m['accountId'] == activation['managerAccountId'] &&
            m['manageKeys'] == true,
      )
      .toList();
  if (managers.length != 1) {
    throw const FormatException('crypto_invitation_cutover_manager');
  }
  final manager = managers.single;
  final fingerprint = codec.fingerprint(
    cryptoBase64(manager['rootSigningKeyBase64'], length: 32),
    cryptoBase64(manager['rootEncryptionKeyBase64'], length: 32),
  );
  final prefixes = <String, VerifiedAccountDirectory>{};
  VerifiedAccountDirectory? managerState;
  var after = 0;
  final wanted = {
    activation['managerDirectoryHeadHash'],
    publication['payload']['previousHeadHash'],
    cutover['managerEventHeadHash'],
  };
  for (var pageNumber = 0; pageNumber < 200; pageNumber++) {
    final page = await activationDirectoryPage(after);
    final entries = page['entries'];
    if (entries is! List || entries.isEmpty || entries.length > 50) {
      throw const FormatException('crypto_invitation_cutover_directory');
    }
    for (final entry in entries) {
      managerState = await AccountDirectoryV2(codec).apply(
        previous: managerState,
        entry: Map<String, dynamic>.from(entry as Map),
        serverId: creator.serverId,
        accountId: activation['managerAccountId'],
        pinnedRootFingerprint: fingerprint,
      );
      if (wanted.contains(managerState.headHash)) {
        prefixes[managerState.headHash] = managerState;
      }
      after = managerState.generation;
    }
    if (page['hasMore'] == false) {
      if (page['headHash'] != managerState!.headHash ||
          page['generation'] != managerState.generation ||
          page['snapshotHash'] != managerState.snapshotHash) {
        throw const FormatException('crypto_invitation_cutover_directory');
      }
      break;
    }
    if (pageNumber == 199 ||
        page['hasMore'] != true ||
        page['nextGeneration'] != after) {
      throw const FormatException('crypto_invitation_cutover_directory');
    }
  }
  final author = prefixes[activation['managerDirectoryHeadHash']],
      eventPrior = prefixes[publication['payload']['previousHeadHash']],
      eventIncluded = prefixes[cutover['managerEventHeadHash']];
  if (managerState != null) {
    if (managerState.accountId == creator.accountId &&
        !creator.includesAnchor(
          managerState.generation,
          managerState.headHash,
        )) {
      throw const FormatException('crypto_invitation_cutover_known_fork');
    }
    await requireKnownPrefix(managerState);
  }
  if (author == null ||
      eventPrior == null ||
      eventIncluded == null ||
      author.deviceSnapshotHash != manager['deviceSnapshotHash'] ||
      eventPrior.deviceSnapshotHash != author.deviceSnapshotHash ||
      publication['version'] != 2 ||
      publication['operation'] != 'crypto2.account.migrationAttest' ||
      publication['accountId'] != author.accountId ||
      publication['serverId'] != creator.serverId ||
      publication['signer'] != 'device') {
    throw const FormatException('crypto_invitation_cutover_event');
  }
  final signingKey = cryptoBase64(
    author.activeDevice(publication['deviceId'])['signingKeyBase64'],
    length: 32,
  );
  codec.verifyDomain(
    activationProof,
    signingKey,
    'JivieMigrationActivation/v3\n',
  );
  codec.verifyDomain(
    publicationEvent,
    cryptoBase64(
      eventPrior.activeDevice(publication['deviceId'])['signingKeyBase64'],
      length: 32,
    ),
    cryptoDirectoryDomain,
  );
  final publicationHash = await cryptoSha256(
    cryptoBase64(publicationEvent['commandBase64']),
  );
  if (publication['payload']['migrationId'] != activation['migrationId'] ||
      publication['payload']['domain'] != 'content' ||
      publication['payload']['scopeToken'] !=
          await CryptoMigrationActivationV3.token(activation) ||
      publication['payload']['attestationHash'] !=
          await cryptoSha256(CryptoJson.encode(activationProof)) ||
      eventIncluded.generation != eventPrior.generation + 1 ||
      eventIncluded.headHash !=
          await cryptoSha256([
            ...utf8.encode(cryptoDirectoryLogDomain),
            ...CryptoJson.encode({
              'serverId': creator.serverId,
              'accountId': author.accountId,
              'generation': eventIncluded.generation,
              'previousHeadHash': eventPrior.headHash,
              'commandHash': publicationHash,
              'signatureBase64': publicationEvent['signatureBase64'],
            }),
          ])) {
    throw const FormatException('crypto_invitation_cutover_event');
  }
  final control = Map<String, dynamic>.from(cutover['control'] as Map),
      controlHash = await CryptoMigrationActivationV3.controlHash(control),
      digests = (cutover['controlDigests'] as List).cast<String>();
  if (digests.length > 5000 ||
      digests.where((d) => d == controlHash).length != 1 ||
      await CryptoMigrationActivationV3.controlRoot(
            activation,
            Stream.fromIterable(digests),
          ) !=
          activation['controlRoot'] ||
      control['scopeId'] != metadata['scopeId'] ||
      control['kind'] != 'invitations' ||
      control['captureId'] != h['captureId'] ||
      control['sourceInventoryRoot'] != h['sourceInventoryRoot'] ||
      control['certificateHash'] != certHash ||
      control['eventCommandHash'] != evidence['eventCommandHash'] ||
      control['selectionCount'] != h['bridgeCount']) {
    throw const FormatException('crypto_invitation_cutover_control');
  }
  return VerifiedCryptoLegacyInvitationEvidence._(
    {
      'scopeId': metadata['scopeId'],
      'invitationId': metadata['invitationId'],
      'tokenHash': metadata['tokenHash'],
      'role': metadata['role'],
      'expiresAt': metadata['expiresAtEpoch'],
      'membershipHeadHash': context['membershipHeadHash'],
      'authorDirectoryHeadHash': p['authorDirectoryHeadHash'],
    },
    creator.accountId,
    bridgeHash,
  );
}
