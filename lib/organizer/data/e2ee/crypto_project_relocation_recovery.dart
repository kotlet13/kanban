import 'dart:collection';
import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_project_relocation_codec.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// Only an exact independently verified OWN account-log event can construct
/// this token. It discovers old scope candidates; it grants no current READ,
/// membership, key or monotonic floor. Bootstrap must verify the exact target
/// head/activation against the retained publication before using any candidate.
class VerifiedOwnProjectRelocation {
  VerifiedOwnProjectRelocation._({
    required Map<String, dynamic> source,
    required Map<String, dynamic> target,
    required this.eventGeneration,
    required this.eventHeadHash,
    required this.eventCommandHash,
    required this.publicationRoot,
  }) : source = UnmodifiableMapView(source),
       target = UnmodifiableMapView(target);
  final Map<String, dynamic> source, target;
  final int eventGeneration;
  final String eventHeadHash, eventCommandHash, publicationRoot;
}

/// Bounded network/page processing is driven by the complete verified lineage,
/// never by an unsigned server action list or imported local cursor.
class CryptoProjectRelocationRecovery {
  CryptoProjectRelocationRecovery(this.access);
  final SessionCryptoAccess access;
  Future<VerifiedAccountDirectory> _prefix(
    VerifiedAccountDirectory own,
    String reference,
  ) async {
    final pin = await access.account.store.anchor(own.accountId);
    if (pin == null) {
      throw const CryptoAuthorityPending('crypto_relocation_own_anchor');
    }
    VerifiedAccountDirectory? state;
    await for (final entry in access.account.store.streamEntries(
      own.accountId,
    )) {
      state = await access.account.directory.reducer.apply(
        previous: state,
        entry: entry,
        serverId: own.serverId,
        accountId: own.accountId,
        pinnedRootFingerprint: pin['genesisFingerprint'] ?? pin['fingerprint'],
      );
      if (state.headHash == reference) {
        if (!own.includesAnchor(state.generation, reference)) {
          throw const FormatException('crypto_relocation_own_fork');
        }
        return state;
      }
    }
    throw const CryptoAuthorityPending('crypto_relocation_own_prefix_pending');
  }

  Stream<VerifiedOwnProjectRelocation> discover() async* {
    final account = access.account;
    final own = await account.directory.requireFresh();
    final epoch = own.identityEpochId;
    final seen = <String>{};
    await for (final event in account.store.verifiedOperationEntries(
      own,
      'crypto2.account.projectRelocation',
    )) {
      final eventProof = Map<String, dynamic>.from(
        event['authorization'] as Map,
      );
      final command = CryptoProjectRelocationCodec.body(eventProof);
      final payload = command['payload'] as Map;
      if (command['operation'] != 'crypto2.account.projectRelocation' ||
          command['accountId'] != own.accountId ||
          command['serverId'] != own.serverId ||
          !own.includesAnchor(event['generation'], event['headHash']) ||
          !seen.add(payload['actionId'])) {
        throw const FormatException('crypto_relocation_own_event');
      }
      final evidence = await account.directory
          .call('crypto2.projectRelocation.own', {
            'actionId': payload['actionId'],
            'eventCommandHash': event['commandHash'],
            'publicationRoot': payload['publicationRoot'],
          });
      if (evidence['eventGeneration'] != event['generation'] ||
          evidence['eventHeadHash'] != event['headHash'] ||
          evidence['eventCommandHash'] != event['commandHash'] ||
          base64Encode(CryptoJson.encode(evidence['eventAuthorization'])) !=
              base64Encode(CryptoJson.encode(eventProof))) {
        throw const FormatException('crypto_relocation_own_event_substitution');
      }
      final proofs = evidence['publications'] as Map;
      CryptoProjectRelocationCodec.exact(proofs, {'source', 'target'});
      final headers = <String, Map<String, dynamic>>{};
      final hashes = <String, String>{};
      for (final side in const ['source', 'target']) {
        final proof = Map<String, dynamic>.from(proofs[side] as Map);
        final body = CryptoProjectRelocationCodec.body(proof);
        CryptoProjectRelocationCodec.publication(body);
        if (body['side'] != side ||
            body['serverId'] != own.serverId ||
            body['accountId'] != own.accountId ||
            body['deviceId'] != command['deviceId'] ||
            body['requestId'] != command['requestId'] ||
            body['actionId'] != payload['actionId']) {
          throw const FormatException('crypto_relocation_own_publication');
        }
        final prefix = await _prefix(own, body['authorDirectoryHeadHash']);
        if (prefix.generation >= event['generation'] ||
            prefix.identityEpochId != payload['identityEpochId']) {
          throw const FormatException('crypto_relocation_own_timing');
        }
        // Historical validity comes from exact own-event inclusion. Current
        // device status is deliberately not substituted for that old timing.
        final signer = prefix.activeDevice(body['deviceId']);
        account.directory.reducer.crypto.verifyDomain(
          proof,
          cryptoBase64(signer['signingKeyBase64'], length: 32),
          CryptoProjectRelocationCodec.publicationDomain,
        );
        headers[side] = body;
        hashes[side] = await CryptoProjectRelocationCodec.proofHash(proof);
      }
      if (headers['source']!['scopeId'] == headers['target']!['scopeId'] ||
          headers['source']!['planHash'] != headers['target']!['planHash'] ||
          await CryptoProjectRelocationCodec.publicationRoot(
                hashes['source']!,
                hashes['target']!,
              ) !=
              payload['publicationRoot']) {
        throw const FormatException('crypto_relocation_own_pair');
      }
      final fresh = await account.directory.requireFresh();
      if (!account.directory.isCurrent() ||
          fresh.identityEpochId != epoch ||
          !fresh.includesAnchor(own.generation, own.headHash)) {
        throw const CryptoAuthorityPending(
          'crypto_relocation_identity_changed',
        );
      }
      yield VerifiedOwnProjectRelocation._(
        source: headers['source']!,
        target: headers['target']!,
        eventGeneration: event['generation'],
        eventHeadHash: event['headHash'],
        eventCommandHash: event['commandHash'],
        publicationRoot: payload['publicationRoot'],
      );
    }
  }
}
