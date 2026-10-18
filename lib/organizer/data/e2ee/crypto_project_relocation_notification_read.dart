import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_project_relocation_codec.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// Final manager routing, separate from the owner's original scheduling
/// signature. The card grants neither parent READ nor new owner consent.
class VerifiedProjectRelocationNotification {
  VerifiedProjectRelocationNotification._(
    this.route,
    this.publication,
    this.put,
    this.use,
    this.target,
  );
  final Map<String, dynamic> route, publication, target;
  final Map<String, dynamic>? put, use;
}

class CryptoProjectRelocationNotificationRead {
  CryptoProjectRelocationNotificationRead(this.runtime);
  final CryptoBusinessSession runtime;
  Map<String, dynamic> map(Object? value) {
    if (value is! Map) {
      throw const FormatException('crypto_relocation_notification_shape');
    }
    return Map<String, dynamic>.from(value);
  }

  Map<String, dynamic> body(Map proof) =>
      map(CryptoJson.decode(cryptoBase64(proof['commandBase64'])));
  bool same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

  Future<VerifiedProjectRelocationNotification> verify({
    required String scopeId,
    required String targetId,
    String? reminderId,
    Map<String, dynamic>? useProof,
  }) async {
    final own = await runtime.account.directory.requireFresh();
    final genesis = await runtime.access.verifiedRelocationGenesis(scopeId);
    final header = genesis.header;
    final read = await runtime.access.readContext(
      scopeId,
      useProof == null ? 'content' : body(useProof)['domain'],
    );
    final useHash = useProof == null
        ? null
        : await cryptoSha256(CryptoJson.encode(useProof));
    final op = reminderId == null
        ? 'crypto2.projectRelocation.routingUse'
        : 'crypto2.projectRelocation.routingOwn';
    final selector = {
      'scopeId': scopeId,
      if (reminderId != null) ...{
        'kind': 'reminder',
        'id': reminderId,
      } else ...{
        'targetId': targetId,
        'useProofHash': useHash,
      },
    };
    Map<String, dynamic>? first;
    final hashes = <String>[];
    String? after;
    while (true) {
      final page = await runtime.account.directory.call(op, {
        ...selector,
        'limit': 32,
        if (after != null) 'afterHash': after,
      });
      final stable = Map<String, dynamic>.from(page)
        ..remove('digests')
        ..remove('hasMore')
        ..remove('nextAfterHash');
      if (first == null) {
        first = stable;
      } else if (!same(first, stable)) {
        throw const FormatException(
          'crypto_relocation_notification_page_changed',
        );
      }
      if (!same(body(map(page['publication'])), header)) {
        throw const FormatException(
          'crypto_relocation_notification_publication',
        );
      }
      final values = page['digests'];
      if (values is! List || values.length > 32) {
        throw const FormatException('crypto_relocation_notification_page');
      }
      for (final value in values) {
        CryptoProjectRelocationCodec.hashValue(value);
        if (after != null && after.compareTo(value) >= 0 ||
            hashes.length >= header['notificationCount']) {
          throw const FormatException('crypto_relocation_notification_order');
        }
        hashes.add(value);
        after = value;
      }
      if (page['hasMore'] == false) break;
      if (page['hasMore'] != true ||
          values.isEmpty ||
          page['nextAfterHash'] != after) {
        throw const FormatException('crypto_relocation_notification_cursor');
      }
    }
    final proof = map(first['authorization']), route = body(proof);
    CryptoProjectRelocationCodec.exact(route, {
      'version',
      'serverId',
      'actionId',
      'planHash',
      'routeId',
      'kind',
      'sourceRecordProofHash',
      'originalPutProofHash',
      'originalUseProofHash',
      'originalUseEventCommandHash',
      'targetScopeId',
      'targetId',
      'targetType',
      'targetRecordProofHash',
      'accountId',
      'deviceId',
      'authorDirectoryHeadHash',
    });
    if (route['version'] != 2 ||
        route['serverId'] != own.serverId ||
        route['kind'] != 'reminder' ||
        route['actionId'] != header['actionId'] ||
        route['planHash'] != header['planHash'] ||
        route['accountId'] != header['accountId'] ||
        route['deviceId'] != header['deviceId'] ||
        route['targetScopeId'] != scopeId ||
        route['targetId'] != targetId ||
        hashes.length != header['notificationCount'] ||
        !hashes.contains(await cryptoSha256(CryptoJson.encode(proof))) ||
        await CryptoProjectRelocationCodec.digestRoot(
              'notifications',
              hashes,
            ) !=
            header['notificationRoot']) {
      throw const FormatException('crypto_relocation_notification_binding');
    }
    final prefix = await runtime.access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: genesis.headHash,
      accountId: route['accountId'],
      directoryHeadHash: route['authorDirectoryHeadHash'],
      online: true,
    );
    runtime.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(
        prefix.activeDevice(route['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      'JivieProjectRelocationNotification/v2\n',
    );
    final put = first['putAuthorization'] == null
        ? null
        : map(first['putAuthorization']);
    final use = first['useAuthorization'] == null
        ? null
        : map(first['useAuthorization']);
    if ((put != null &&
            await cryptoSha256(CryptoJson.encode(put)) !=
                route['originalPutProofHash']) ||
        (use != null &&
            await cryptoSha256(CryptoJson.encode(use)) !=
                route['originalUseProofHash']) ||
        useProof != null &&
            (!same(useProof, use) ||
                route['originalUseProofHash'] != useHash)) {
      throw const FormatException('crypto_relocation_notification_original');
    }
    final targetDomain = cryptoRecordDomain(route['targetType']);
    await runtime.access.readContext(scopeId, targetDomain);
    final wire = await runtime.account.directory
        .call('crypto2.records.historyGet', {
          'scopeId': scopeId,
          'domain': targetDomain,
          'accessRevision': read.accessRevision,
          'id': targetId,
          'revision': 1,
        });
    final recordWire = map(wire['record']);
    final targetProof = map(map(recordWire['authorization'])['recordProof']);
    final target = body(targetProof);
    final authority = await runtime.access.recordAuthority(target);
    await runtime.codec.verifyWire(
      serverId: own.serverId,
      wire: recordWire,
      trustedSigningKey: authority.signingKey,
      currentEpoch: authority.currentEpoch,
      closedRecordProofHash: authority.closedRecordProofHash,
    );
    if (await runtime.codec.digest(targetProof) !=
            route['targetRecordProofHash'] ||
        target['expectedRevision'] != 0 ||
        target['type'] != route['targetType'] ||
        map(map(target['metadata'])['projectRelocation'])['actionId'] !=
            header['actionId']) {
      throw const FormatException('crypto_relocation_notification_target');
    }
    if (!runtime.account.directory.isCurrent() ||
        (await runtime.access.readContext(
              scopeId,
              target['domain'],
            )).headHash !=
            read.headHash) {
      throw const CryptoAuthorityPending(
        'crypto_relocation_notification_read_changed',
      );
    }
    return VerifiedProjectRelocationNotification._(
      route,
      header,
      put,
      use,
      target,
    );
  }
}
