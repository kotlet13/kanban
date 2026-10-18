import 'dart:convert';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_keys.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_commitments_v3.dart';

/// Exact historical work classification only; never scope/key/WRITE authority.
abstract final class CryptoMigrationSupersededSetup {
  static Map<String, dynamic> body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  static bool same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));
  static Future<bool> verifies({
    required CryptoCodec crypto,
    required VerifiedAccountDirectory own,
    required VerifiedAccountDirectory approvalDirectory,
    required VerifiedAccountDirectory oldDirectory,
    required VerifiedAccountDirectory prepareDirectory,
    required CryptoCaptureKeyDescriptor capture,
    required String scopeId,
    required Map draft,
    required Map context,
    required Map approval,
    required Map eventEntry,
    required Map oldProposal,
    required Map finish,
    required Map receipt,
    required Map prepare,
  }) async {
    try {
      final a = body(approval),
          old = body(oldProposal),
          f = body(finish),
          p = body(prepare),
          e = body(eventEntry['authorization'] as Map);
      final contextHash = await cryptoSha256([
        ...utf8.encode('JivieMigrationGenerationContext/v3\n'),
        ...CryptoJson.encode(context),
      ]);
      final oldHead = await cryptoSha256([
        ...utf8.encode('JivieScopeHead/v2\n'),
        ...CryptoJson.encode(draft['body']),
      ]);
      if (context['version'] != 3 ||
          context['mode'] != 'supersede' ||
          context['serverId'] != own.serverId ||
          context['newMigrationId'] != capture.migrationId ||
          context['migrationId'] == capture.migrationId ||
          context['componentId'] != capture.componentId ||
          !same(context['published'], []) ||
          draft['headHash'] != oldHead ||
          draft['body']['scopeId'] != scopeId ||
          draft['body']['epoch'] != 1 ||
          draft['body']['previousHeadHash'] != cryptoZeroHash ||
          !same(old['payload'], draft['body']))
        return false;
      final tokens = <String>[];
      for (final id in capture.scopeIds) {
        tokens.add(
          await CryptoMigrationCommitmentsV3.scopeToken(
            serverId: own.serverId,
            migrationId: context['migrationId'],
            scopeId: id,
            domain: 'content',
          ),
        );
      }
      tokens.sort();
      final scopes = (context['scopes'] as List).cast<Map>();
      final contextTokens = scopes.map((s) => s['scopeToken']).toSet();
      if (!capture.scopeIds.contains(scopeId) ||
          contextTokens.length != scopes.length ||
          tokens.any((token) => !contextTokens.contains(token))) {
        return false;
      }
      final token = await CryptoMigrationCommitmentsV3.scopeToken(
        serverId: own.serverId,
        migrationId: context['migrationId'],
        scopeId: scopeId,
        domain: 'content',
      );
      final matching = scopes.where((s) => s['scopeToken'] == token).toList();
      if (matching.length != 1 ||
          matching.single['headHash'] != oldHead ||
          matching.single['candidateHeadHash'] == oldHead ||
          matching.single['candidateHeadHash'] == null)
        return false;
      if (a['version'] != 3 ||
          a['mode'] != 'supersede' ||
          a['serverId'] != own.serverId ||
          a['accountId'] != own.accountId ||
          a['migrationId'] != context['migrationId'] ||
          a['generationId'] != context['generationId'] ||
          a['contextHash'] != contextHash ||
          a['authorDirectoryHeadHash'] != approvalDirectory.headHash ||
          a['deviceSnapshotHash'] != approvalDirectory.deviceSnapshotHash)
        return false;
      for (final directory in [
        approvalDirectory,
        oldDirectory,
        prepareDirectory,
      ]) {
        if (directory.accountId != own.accountId ||
            !own.includesAnchor(directory.generation, directory.headHash))
          return false;
      }
      final approvalDevice = approvalDirectory.activeDevice(a['deviceId']);
      if (approvalDevice['keyringWrite'] != true) return false;
      crypto.verifyDomain(
        Map<String, dynamic>.from(approval),
        cryptoBase64(approvalDevice['signingKeyBase64'], length: 32),
        'JivieMigrationGenerationApproval/v3\n',
      );
      if (old['operation'] != 'crypto2.scope.headPut' ||
          old['accountId'] != own.accountId ||
          old['serverId'] != own.serverId ||
          old['payload']['authorDirectoryHeadHash'] != oldDirectory.headHash)
        return false;
      crypto.verifyDomain(
        Map<String, dynamic>.from(oldProposal),
        cryptoBase64(
          oldDirectory.activeDevice(old['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        cryptoDirectoryDomain,
      );
      final generationToken = await cryptoSha256([
        ...utf8.encode('JivieMigrationGenerationToken/v3\n'),
        ...CryptoJson.encode({
          'version': 3,
          'serverId': own.serverId,
          'migrationId': context['migrationId'],
          'generationId': context['generationId'],
        }),
      ]);
      final ep = e['payload'] as Map;
      if (e['operation'] != 'crypto2.account.migrationAttest' ||
          e['accountId'] != own.accountId ||
          e['serverId'] != own.serverId ||
          ep['migrationId'] != context['migrationId'] ||
          ep['scopeToken'] != generationToken ||
          ep['domain'] != 'content' ||
          ep['attestationHash'] !=
              await cryptoSha256(CryptoJson.encode(approval)) ||
          eventEntry['generation'] != ep['expectedGeneration'] + 1 ||
          !own.includesAnchor(eventEntry['generation'], eventEntry['headHash']))
        return false;
      final eventHash = await cryptoSha256([
        ...utf8.encode(cryptoDirectoryLogDomain),
        ...CryptoJson.encode({
          'serverId': own.serverId,
          'accountId': own.accountId,
          'generation': eventEntry['generation'],
          'previousHeadHash': ep['previousHeadHash'],
          'commandHash': await cryptoSha256(
            cryptoBase64(eventEntry['authorization']['commandBase64']),
          ),
          'signatureBase64': eventEntry['authorization']['signatureBase64'],
        }),
      ]);
      if (eventHash != eventEntry['headHash']) return false;
      if (f['operation'] != 'crypto2.migration.generation.finish' ||
          f['serverId'] != own.serverId ||
          f['accountId'] != own.accountId ||
          f['deviceId'] != a['deviceId'] ||
          !same(f['payload'], {
            'generationId': context['generationId'],
            'contextHash': contextHash,
          }))
        return false;
      crypto.verifyDomain(
        Map<String, dynamic>.from(finish),
        cryptoBase64(approvalDevice['signingKeyBase64'], length: 32),
        cryptoDirectoryDomain,
      );
      // Same exact receipt contract used by the existing immutable command queue.
      if (receipt['status'] != 200 ||
          receipt['requestId'] != f['requestId'] ||
          receipt['requestHash'] !=
              await cryptoSha256(cryptoBase64(finish['commandBase64'])) ||
          !same(receipt['authorization'], finish) ||
          receipt['response']?['state'] != 'superseded' ||
          receipt['response']?['migrationId'] != capture.migrationId ||
          receipt['response']?['generationId'] != context['generationId'])
        return false;
      final pp = Map<String, dynamic>.from(p['payload'] as Map)
        ..remove('authorDirectoryHeadHash');
      if (p['operation'] != 'crypto2.migration.capture.prepare' ||
          p['serverId'] != own.serverId ||
          p['accountId'] != own.accountId ||
          p['payload']['authorDirectoryHeadHash'] !=
              prepareDirectory.headHash ||
          !same(pp, capture.toJson()))
        return false;
      crypto.verifyDomain(
        Map<String, dynamic>.from(prepare),
        cryptoBase64(
          prepareDirectory.activeDevice(p['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        cryptoDirectoryDomain,
      );
      return true;
    } on FormatException {
      return false;
    }
  }
}
