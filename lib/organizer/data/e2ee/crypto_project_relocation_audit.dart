import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_document_blob.dart';
import 'crypto_json.dart';
import 'crypto_project_relocation_codec.dart';
import 'crypto_sync_repository.dart';

/// Complete target-scoped manager-attested historical snapshots. These entries
/// preserve original values/time claims, but never pretend to carry the old
/// original author's signature after transformation into a new namespace.
class CryptoProjectRelocationAudit {
  CryptoProjectRelocationAudit(this.context);
  final CryptoBusinessSession context;
  static bool same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));
  Future<List<Map<String, dynamic>>> history(
    String scope,
    String canonical, {
    int? beforeRevision,
  }) async {
    final own = await context.account.directory.requireFresh();
    own.activeDevice(context.account.deviceId);
    final read = await context.access.readContext(scope, 'finance');
    final genesis = await context.access.verifiedRelocationGenesis(scope);
    final header = genesis.header;
    final head = await context.access.headAt(scope, genesis.headHash);
    final hashes = <String>[], result = <Map<String, dynamic>>[];
    String? after;
    var count = 0;
    final key = await context.access.getScopeKey(scope, 'finance', 1);
    try {
      while (true) {
        final page = await context.account.directory.call(
          'crypto2.projectRelocation.audit',
          {
            'scopeId': scope,
            'limit': 20,
            if (after != null) 'afterHash': after,
          },
        );
        final publication = Map<String, dynamic>.from(
          page['publication'] as Map,
        );
        final body = CryptoProjectRelocationCodec.body(publication);
        if (!same(body, header) ||
            body['side'] != 'target' ||
            page['scopeId'] != scope)
          throw const FormatException('crypto_relocation_audit_publication');
        final values = page['proofs'];
        if (values is! List || values.length > 20)
          throw const FormatException('crypto_relocation_audit_page');
        for (final value in values) {
          final proof = Map<String, dynamic>.from(value as Map);
          final digest = await CryptoProjectRelocationCodec.proofHash(proof);
          if (after != null && after.compareTo(digest) >= 0 ||
              ++count > header['auditCount'])
            throw const FormatException('crypto_relocation_audit_order');
          after = digest;
          hashes.add(digest);
          CryptoProjectRelocationCodec.exact(proof, {
            'commandBase64',
            'signatureBase64',
          });
          cryptoBase64(proof['signatureBase64'], length: 64);
          final encoded = cryptoBase64(proof['commandBase64'], max: 262144);
          final raw = Map<String, dynamic>.from(
            CryptoJson.decode(encoded) as Map,
          );
          if (base64Encode(CryptoJson.encode(raw)) != proof['commandBase64'])
            throw const FormatException('crypto_relocation_audit_canonical');
          CryptoProjectRelocationCodec.exact(raw, {
            'version',
            'operation',
            'serverId',
            'scopeId',
            'actionId',
            'planHash',
            'sourceToken',
            'recordId',
            'epoch',
            'membershipHeadHash',
            'accessRevision',
            'blobIds',
            'envelopeBase64',
            'accountId',
            'deviceId',
            'authorDirectoryHeadHash',
          });
          if (raw['version'] != 2 ||
              raw['operation'] != 'crypto2.projectRelocation.auditSnapshot' ||
              raw['serverId'] != own.serverId ||
              raw['scopeId'] != scope ||
              raw['actionId'] != header['actionId'] ||
              raw['planHash'] != header['planHash'] ||
              raw['membershipHeadHash'] != head.headHash ||
              raw['epoch'] != 1 ||
              raw['accessRevision'] != head.accessRevision ||
              raw['accountId'] != header['accountId'] ||
              raw['deviceId'] != header['deviceId'])
            throw const FormatException('crypto_relocation_audit_context');
          final directory = await context.access.directoryAt(
            scopeId: scope,
            scopeHeadHash: head.headHash,
            accountId: raw['accountId'],
            directoryHeadHash: raw['authorDirectoryHeadHash'],
            online: true,
            allowUnverifiedContact: true,
          );
          final member = head.member(directory.accountId);
          if (directory.deviceSnapshotHash != member['deviceSnapshotHash'] ||
              directory.snapshot['rootSigningKeyBase64'] !=
                  member['rootSigningKeyBase64'] ||
              directory.snapshot['rootEncryptionKeyBase64'] !=
                  member['rootEncryptionKeyBase64'] ||
              member['manageKeys'] != true ||
              member['financeRole'] != 'write')
            throw const FormatException('crypto_relocation_audit_signer');
          final device = directory.activeDevice(raw['deviceId']);
          context.codec.crypto.verifyDomain(
            proof,
            cryptoBase64(device['signingKeyBase64'], length: 32),
            'JivieProjectRelocationAudit/v2\n',
          );
          final aad = Map<String, dynamic>.from(raw)..remove('envelopeBase64');
          final bytes = context.codec.crypto.decrypt(
            envelope: Map<String, dynamic>.from(
              CryptoJson.decode(cryptoBase64(raw['envelopeBase64'])) as Map,
            ),
            key: key.key,
            context: {'purpose': 'projectRelocationAudit', ...aad},
          );
          try {
            var snapshot = Map<String, dynamic>.from(
              jsonDecode(utf8.decode(bytes)) as Map,
            );
            if (snapshot.length == 2 &&
                snapshot['version'] == 2 &&
                snapshot['entryBlob'] is Map) {
              final d = Map<String, dynamic>.from(snapshot['entryBlob'] as Map);
              if (d['scopeId'] != scope ||
                  d['domain'] != 'finance' ||
                  d['epoch'] != 1 ||
                  d['membershipHeadHash'] != head.headHash ||
                  !same(raw['blobIds'], [d['id']]))
                throw const FormatException('crypto_relocation_audit_blob');
              final expanded = await CryptoDocumentBlob(context).open(d);
              try {
                snapshot = Map<String, dynamic>.from(
                  jsonDecode(utf8.decode(expanded)) as Map,
                );
              } finally {
                expanded.fillRange(0, expanded.length, 0);
              }
            } else if ((raw['blobIds'] as List).isNotEmpty) {
              throw const FormatException('crypto_relocation_audit_blob');
            }
            CryptoProjectRelocationCodec.exact(snapshot, {
              'version',
              'sourceEvidenceHash',
              'entry',
            });
            final sourceHash = snapshot['sourceEvidenceHash'];
            CryptoProjectRelocationCodec.hashValue(sourceHash);
            final token = await cryptoSha256([
              ...utf8.encode('JivieProjectRelocationAuditSource/v2\n'),
              ...CryptoJson.encode({
                'version': 2,
                'serverId': own.serverId,
                'actionId': header['actionId'],
                'scopeId': scope,
                'sourceEvidenceHash': sourceHash,
              }),
            ]);
            if (snapshot['version'] != 2 ||
                token != raw['sourceToken'] ||
                snapshot['entry'] is! Map)
              throw const FormatException('crypto_relocation_audit_source');
            final entry = Map<String, dynamic>.from(snapshot['entry'] as Map);
            final record = context
                .address(
                  scope,
                  'finance',
                  'financeEntry',
                  entry['recordId'] as String,
                )
                .wireId;
            // All user finance record types share the finance_records wire
            // namespace. A raw filtered server list cannot prove completeness.
            if (entry['scopeId'] != scope ||
                record != raw['recordId'] ||
                entry['sourceEvidenceHash'] != sourceHash ||
                entry['revision'] is! int ||
                entry['revision'] < 1)
              throw const FormatException('crypto_relocation_audit_entry');
            if (entry['recordId'] == canonical &&
                (beforeRevision == null || entry['revision'] < beforeRevision))
              result.add({
                ...entry,
                'revisionNamespace': 'relocated',
                'historyBasis': 'managerAttestedProjectRelocation',
                'sourceEvidenceHash': digest,
                'originalRevisionNamespace': entry['revisionNamespace'],
              });
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
        if (page['hasMore'] == false) break;
        if (page['hasMore'] != true ||
            values.isEmpty ||
            page['nextAfterHash'] != after)
          throw const FormatException('crypto_relocation_audit_cursor');
      }
      if (count != header['auditCount'] ||
          await CryptoProjectRelocationCodec.digestRoot('audit', hashes) !=
              header['auditRoot'])
        throw const FormatException('crypto_relocation_audit_incomplete');
      final fresh = await context.account.directory.requireFresh(),
          current = await context.access.readContext(scope, 'finance');
      if (!context.account.directory.isCurrent() ||
          fresh.identityEpochId != own.identityEpochId ||
          fresh.deviceSnapshotHash != own.deviceSnapshotHash ||
          fresh.rootFingerprint != own.rootFingerprint ||
          current.headHash != read.headHash ||
          current.accessRevision != read.accessRevision)
        throw const CryptoAuthorityPending(
          'crypto_relocation_audit_read_changed',
        );
      result.sort((a, b) => (b['revision'] as int).compareTo(a['revision']));
      return result;
    } finally {
      key.release();
    }
  }
}
