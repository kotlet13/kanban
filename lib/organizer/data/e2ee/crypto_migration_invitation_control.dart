import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_v3.dart';
import 'crypto_json.dart';
import 'crypto_legacy_invitation_capsule.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_invitation_codec.dart';
import 'crypto_migration_invitations.dart';
import 'crypto_record_address.dart';

/// Complete FILE-source comparison before a finalized verify3 signature. No
/// live keys, outbox, global peer pins or invitation acceptance are installed.
class CryptoMigrationInvitationControl implements CryptoMigrationColdControl {
  CryptoMigrationInvitationControl(
    this.runtime,
    this.archive, {
    required this.recoveryFile,
  }) : evidence = CryptoMigrationColdEvidence(runtime, archive);
  final CryptoBusinessSession runtime;
  final VerifiedCryptoCaptureArchive archive;
  final Uint8List recoveryFile;
  final CryptoMigrationColdEvidence evidence;
  bool _prepared = false;
  bool _failed = false;

  Future<void> _prepare() async {
    if (_prepared) return;
    await runtime.db.execute(
      'CREATE TABLE IF NOT EXISTS cold_invitation_bridges(binding_id TEXT PRIMARY KEY,kind TEXT,'
      'proof TEXT,capsule TEXT,bridge_hash TEXT,leaf_hash TEXT,invitation_binding TEXT,'
      'invitation_id TEXT,verified INTEGER NOT NULL DEFAULT 0)',
    );
    await runtime.db.execute('DELETE FROM cold_invitation_bridges');
    String? after;
    while (true) {
      final page = await runtime.account.directory
          .call('crypto2.migration.invitations.bridges', {
            'migrationId': archive.capture.migrationId,
            'captureId': archive.capture.captureId,
            'sourceInventoryRoot': archive.sourceInventoryRoot,
            if (after != null) 'afterBindingId': after,
            'limit': 20,
          });
      if (page['bridges'] is! List ||
          (page['bridges'] as List).length > 20 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_invitation_bridge_page');
      }
      for (final raw in page['bridges'] as List) {
        final item = Map<String, dynamic>.from(raw as Map);
        CryptoMigrationInvitationCodec.fields(item, {
          'bindingId',
          'authorization',
          'capsuleBase64',
        });
        final proof = Map<String, dynamic>.from(item['authorization'] as Map),
            command =
                CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
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
        final p = Map<String, dynamic>.from(command['payload'] as Map);
        CryptoMigrationInvitationCodec.fields(p, {
          'context',
          'sourceKind',
          'invitationBindingId',
          'authorDirectoryHeadHash',
          'capsuleHash',
          'capsuleSize',
        });
        final c = Map<String, dynamic>.from(p['context'] as Map);
        CryptoMigrationInvitationCodec.fields(
          c,
          CryptoLegacyInvitationCapsule.contextFields,
        );
        if (command['version'] != 2 ||
            command['operation'] != 'crypto2.invitations.bridgeLegacy' ||
            command['signer'] != 'device' ||
            command['serverId'] != evidence.common['serverId'] ||
            command['accountId'] != evidence.common['accountId'] ||
            !isCryptoCanonicalUuid(command['requestId']) ||
            !isCryptoCanonicalUuid(command['deviceId']) ||
            c['version'] != 3 ||
            c['purpose'] != 'legacyInvitationBridge' ||
            c['bindingId'] != item['bindingId'] ||
            !CryptoMigrationInvitationCodec.kinds.contains(p['sourceKind']) ||
            !isCryptoCanonicalUuid(p['invitationBindingId']) ||
            after != null && after.compareTo(c['bindingId']) >= 0) {
          throw const FormatException('crypto_invitation_bridge_context');
        }
        for (final k in [
          'serverId',
          'migrationId',
          'captureId',
          'sourceInventoryRoot',
        ]) {
          if (c[k] != evidence.common[k]) {
            throw const FormatException('crypto_invitation_bridge_context');
          }
        }
        for (final k in ['scopeId', 'bridgeId', 'bindingId']) {
          if (!isCryptoCanonicalUuid(c[k])) {
            throw const FormatException('crypto_invitation_bridge_context');
          }
        }
        for (final k in ['sourceCommitment', 'membershipHeadHash']) {
          CryptoMigrationInvitationCodec.digest(c[k]);
        }
        await evidence.verifyOwn(
          proof,
          p['authorDirectoryHeadHash'],
          command['deviceId'],
          cryptoDirectoryDomain,
        );
        Future<void> requireManager() async {
          final head = await runtime.access.recoveryCandidateHead(c['scopeId']);
          if (head.scopeId != c['scopeId'] ||
              head.headHash != c['membershipHeadHash'] ||
              !head.body['members'].any(
                (m) =>
                    m['accountId'] == command['accountId'] &&
                    m['manageKeys'] == true,
              )) {
            throw const FormatException('crypto_invitation_bridge_manager');
          }
        }

        // The FILE verifier does not install candidate heads in the ordinary
        // cache. Read only this signed bridge's exact frozen head instead.
        final frozen = await runtime.access.readOnlyFrozenDirectory(
          c['scopeId'],
          c['membershipHeadHash'],
        );
        if (frozen != null) {
          await requireManager();
        } else {
          await runtime.access.withReadOnlyFrozenScope<void>(
            scopeId: c['scopeId'],
            candidateHeadHash: c['membershipHeadHash'],
            recoveryFile: recoveryFile,
            body: requireManager,
          );
        }
        if (p['sourceKind'] == 'invitation') {
          final bytes = cryptoBase64(item['capsuleBase64']);
          if (bytes.length > 24576 ||
              p['capsuleSize'] != bytes.length ||
              p['capsuleHash'] != await cryptoSha256(bytes) ||
              c['bindingId'] != p['invitationBindingId']) {
            throw const FormatException('crypto_invitation_bridge_capsule');
          }
        } else if (item['capsuleBase64'] != null ||
            p['capsuleHash'] != null ||
            p['capsuleSize'] != 0) {
          throw const FormatException('crypto_invitation_bridge_mail');
        }
        final hash = await cryptoSha256(CryptoJson.encode(proof));
        final leaf = await CryptoMigrationInvitationCodec.leafDigest({
          'bindingId': c['bindingId'],
          'kind': p['sourceKind'],
          'bridgeHash': hash,
          'capsuleHash': p['capsuleHash'],
        });
        await runtime.db.execute(
          'INSERT INTO cold_invitation_bridges VALUES(?,?,?,?,?,?,?,NULL,0)',
          [
            c['bindingId'],
            p['sourceKind'],
            jsonEncode(proof),
            item['capsuleBase64'],
            hash,
            leaf,
            p['invitationBindingId'],
          ],
        );
        after = c['bindingId'];
      }
      if (page['hasMore'] == false) break;
      if ((page['bridges'] as List).isEmpty ||
          page['nextAfterBindingId'] != after) {
        throw const FormatException('crypto_invitation_bridge_cursor');
      }
    }
    _prepared = true;
  }

  @override
  Future<String> verify(CryptoMigrationColdSource source) => compareCaptured(
    context: source.context,
    binding: source.binding,
    typedRow: source.typedRow,
  );

  /// Comparison only, never an authority token or a proof of full inventory.
  /// The production complete-source producer alone supplies section coverage.
  Future<String> compareCaptured({
    required CryptoCaptureSourceContext context,
    required CryptoCaptureBinding binding,
    required Map<String, dynamic> typedRow,
  }) async {
    try {
      await _prepare();
      final decoded = decodeCryptoMigrationInvitationSource(
        context: context,
        row: typedRow,
      );
      final rows = await runtime.db.rows(
        'SELECT * FROM cold_invitation_bridges WHERE binding_id=?',
        [binding.bindingId],
      );
      if (rows.length != 1 ||
          rows.single['verified'] != 0 ||
          rows.single['kind'] != (decoded.isMail ? 'mail' : 'invitation')) {
        throw const FormatException('crypto_invitation_bridge_incomplete');
      }
      final row = rows.single,
          proof = jsonDecode(row['proof'] as String) as Map,
          command =
              CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
          p = command['payload'] as Map,
          c = Map<String, dynamic>.from(p['context'] as Map);
      if (c['sourceCommitment'] != binding.sourceCommitment) {
        throw const FormatException('crypto_invitation_bridge_binding');
      }
      if (!decoded.isMail) {
        final envelope = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(row['capsule'])) as Map,
        );
        final metadata = CryptoLegacyInvitationCapsule(runtime.codec.crypto)
            .openUntrustedMetadataFromHash(
              envelope: envelope,
              context: c,
              oldTokenHash: decoded.facts['tokenHash'],
            );
        if (!CryptoMigrationColdEvidence.same(
          metadata,
          cryptoLegacyInvitationMetadata(decoded),
        )) {
          throw const FormatException(
            'crypto_invitation_bridge_source_changed',
          );
        }
      }
      await runtime.db.execute(
        'UPDATE cold_invitation_bridges SET verified=1,invitation_id=? WHERE binding_id=?',
        [decoded.id, binding.bindingId],
      );
      return row['bridge_hash'] as String;
    } catch (_) {
      _failed = true;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> finish() async {
    if (_failed) {
      throw const FormatException('crypto_invitation_bridge_incomplete');
    }
    await _prepare();
    if ((await runtime.db.rows(
          'SELECT 1 FROM cold_invitation_bridges WHERE verified<>1 LIMIT 1',
        )).isNotEmpty ||
        (await runtime.db.rows(
          "SELECT 1 FROM cold_invitation_bridges m LEFT JOIN cold_invitation_bridges i ON i.binding_id=m.invitation_binding AND i.kind='invitation' WHERE m.kind='mail' AND (i.binding_id IS NULL OR i.invitation_id<>m.invitation_id) LIMIT 1",
        )).isNotEmpty) {
      throw const FormatException('crypto_invitation_bridge_incomplete');
    }
    String? afterMail;
    while (true) {
      final mails = await runtime.db.rows(
        "SELECT m.binding_id,m.proof,i.proof AS invitation_proof FROM cold_invitation_bridges m JOIN cold_invitation_bridges i ON i.binding_id=m.invitation_binding WHERE m.kind='mail' ${afterMail == null ? '' : 'AND m.binding_id>?'} ORDER BY m.binding_id LIMIT 20",
        [if (afterMail != null) afterMail],
      );
      if (mails.isEmpty) break;
      for (final row in mails) {
        final m =
            CryptoJson.decode(
                  cryptoBase64(
                    (jsonDecode(row['proof'] as String)
                        as Map)['commandBase64'],
                  ),
                )
                as Map;
        final i =
            CryptoJson.decode(
                  cryptoBase64(
                    (jsonDecode(row['invitation_proof'] as String)
                        as Map)['commandBase64'],
                  ),
                )
                as Map;
        for (final k in ['bridgeId', 'scopeId', 'membershipHeadHash']) {
          if (m['payload']['context'][k] != i['payload']['context'][k]) {
            throw const FormatException('crypto_invitation_bridge_mail');
          }
        }
        afterMail = row['binding_id'] as String;
      }
    }
    final count =
        (await runtime.db.rows(
              'SELECT COUNT(*) n FROM cold_invitation_bridges',
            )).single['n']
            as int;
    Stream<String> hashes() async* {
      String? after;
      while (true) {
        final rows = await runtime.db.rows(
          'SELECT leaf_hash FROM cold_invitation_bridges ${after == null ? '' : 'WHERE leaf_hash>?'} ORDER BY leaf_hash LIMIT 20',
          [if (after != null) after],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          after = row['leaf_hash'] as String;
          yield after;
        }
      }
    }

    return {
      'kind': 'invitations',
      'count': count,
      'root': await CryptoMigrationInvitationCodec.selectionRoot(
        evidence.common,
        count,
        hashes(),
      ),
    };
  }
}
