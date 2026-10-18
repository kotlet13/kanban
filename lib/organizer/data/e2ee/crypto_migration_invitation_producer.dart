import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_migration_invitation_codec.dart';
import 'crypto_capture_v3.dart';
import 'crypto_json.dart';
import 'crypto_legacy_invitation_capsule.dart';
import 'crypto_migration_invitations.dart';
import 'crypto_record_address.dart';

/// Immutable source-bound producer. A replay reuses the original nonce, inner
/// signature and outer command; staging never sends an invitation or mail.
class CryptoMigrationInvitations {
  CryptoMigrationInvitations(this.runtime);
  final CryptoBusinessSession runtime;
  static String _canonical(Object? value) =>
      base64Encode(CryptoJson.encode(value));

  Future<Map<String, dynamic>> stageCaptured({
    required CryptoCaptureKeyDescriptor capture,
    required String sourceInventoryRoot,
    required CryptoCaptureBinding binding,
    required Map<String, dynamic> witness,
    Map<String, dynamic>? invitationBridge,
  }) async {
    final source = CryptoCaptureSourceContext.fromJson(
      Map<String, dynamic>.from(witness['context'] as Map),
    );
    await CryptoCaptureV3.verifyWitness(
      binding: binding,
      context: source,
      witness: witness,
    );
    final decoded = decodeCryptoMigrationInvitationSource(
      context: source,
      row: Map<String, dynamic>.from(witness['typedRow'] as Map),
    );
    if (capture.captureId != source.captureId ||
        capture.migrationId != source.migrationId ||
        runtime.account.directory.accountId != source.accountId ||
        runtime.account.directory.session.profile.serverId != source.serverId) {
      throw const FormatException('crypto_invitation_bridge_context');
    }
    final action = 'legacyInvitation:${capture.captureId}:${binding.bindingId}';
    final rows = await runtime.db.rows(
      'SELECT scope_id,payload FROM crypto_export_drafts WHERE partition=? AND action_id=?',
      [runtime.partition, action],
    );
    late Map<String, dynamic> saved;
    if (rows.isNotEmpty) {
      saved = Map<String, dynamic>.from(
        jsonDecode(rows.single['payload'] as String) as Map,
      );
      if (saved['captureId'] != source.captureId ||
          saved['migrationId'] != source.migrationId ||
          saved['sourceInventoryRoot'] != sourceInventoryRoot ||
          saved['sourceCommitment'] != binding.sourceCommitment ||
          saved['invitationId'] != decoded.id ||
          saved['bindingId'] != binding.bindingId ||
          saved['kind'] != (decoded.isMail ? 'mail' : 'invitation')) {
        throw const FormatException('crypto_invitation_bridge_immutable');
      }
    } else {
      if (decoded.isMail &&
          (invitationBridge == null ||
              invitationBridge['invitationId'] != decoded.id ||
              !isCryptoCanonicalUuid(invitationBridge['scopeId']) ||
              !isCryptoCanonicalUuid(invitationBridge['bindingId']) ||
              !isCryptoCanonicalUuid(invitationBridge['bridgeId']))) {
        throw const FormatException(
          'crypto_invitation_bridge_invitation_pending',
        );
      }
      final scope = decoded.scopeId ?? invitationBridge!['scopeId'] as String;
      final candidate = await runtime.access.migrationCandidate(
        scopeId: scope,
        migrationId: source.migrationId,
        captureId: source.captureId,
      );
      final head = candidate.head;
      if (!head.body['members'].any(
        (m) => m['accountId'] == source.accountId && m['manageKeys'] == true,
      )) {
        throw const FormatException('crypto_invitation_bridge_manager');
      }
      final own = await runtime.account.directory.requireFresh();
      final c = <String, dynamic>{
        'version': 3,
        'purpose': 'legacyInvitationBridge',
        'serverId': source.serverId,
        'migrationId': source.migrationId,
        'captureId': source.captureId,
        'sourceInventoryRoot': sourceInventoryRoot,
        'bridgeId': decoded.isMail
            ? invitationBridge!['bridgeId']
            : runtime.codec.crypto.randomId(),
        'bindingId': binding.bindingId,
        'sourceCommitment': binding.sourceCommitment,
        'scopeId': scope,
        'membershipHeadHash': head.headHash,
      };
      String? encoded;
      if (!decoded.isMail) {
        encoded = base64Encode(
          CryptoJson.encode(
            CryptoLegacyInvitationCapsule(runtime.codec.crypto).sealMetadata(
              context: c,
              metadata: cryptoLegacyInvitationMetadata(decoded),
              oldTokenHash: decoded.facts['tokenHash'],
            ),
          ),
        );
      } else if (invitationBridge!['membershipHeadHash'] != head.headHash) {
        throw const FormatException('crypto_invitation_bridge_head_changed');
      }
      final p = <String, dynamic>{
        'context': c,
        'sourceKind': decoded.isMail ? 'mail' : 'invitation',
        'invitationBindingId': decoded.isMail
            ? invitationBridge!['bindingId']
            : binding.bindingId,
        'authorDirectoryHeadHash': own.headHash,
        'capsuleHash': encoded == null
            ? null
            : await cryptoSha256(cryptoBase64(encoded)),
        'capsuleSize': encoded == null ? 0 : cryptoBase64(encoded).length,
      };
      final lease = await runtime.queue.signingKey();
      late Map<String, dynamic> proof;
      try {
        proof = runtime.codec.signCommand({
          'version': 2,
          'operation': 'crypto2.invitations.bridgeLegacy',
          'requestId': runtime.codec.crypto.randomId(),
          'serverId': source.serverId,
          'accountId': source.accountId,
          'deviceId': runtime.account.directory.session.profile.deviceId,
          'signer': 'device',
          'payload': p,
        }, lease.key);
      } finally {
        lease.release();
      }
      saved = {
        'captureId': source.captureId,
        'migrationId': source.migrationId,
        'sourceInventoryRoot': sourceInventoryRoot,
        'sourceCommitment': binding.sourceCommitment,
        'invitationId': decoded.id,
        'bindingId': binding.bindingId,
        'kind': decoded.isMail ? 'mail' : 'invitation',
        'scopeId': scope,
        'bridgeId': c['bridgeId'],
        'membershipHeadHash': head.headHash,
        'authorization': proof,
        'capsuleBase64': encoded,
      };
      if (!runtime.account.directory.isCurrent()) {
        throw const FormatException('crypto_identity_changed');
      }
      await runtime.db.execute(
        'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)',
        [runtime.partition, scope, action, jsonEncode(saved)],
      );
    }
    final request = await runtime.queue.enqueueCommand(
      actionKey: action,
      operation: 'crypto2.migration.invitations.stage',
      payload: {
        'migrationId': source.migrationId,
        'captureId': source.captureId,
        'sourceInventoryRoot': sourceInventoryRoot,
        'bridges': [
          {
            'authorization': saved['authorization'],
            'capsuleBase64': saved['capsuleBase64'],
          },
        ],
      },
    );
    await runtime.queue.resumeUnresolved(requestIds: {request});
    await runtime.queue.commandResult(request);
    return {
      for (final k in [
        'invitationId',
        'bindingId',
        'scopeId',
        'bridgeId',
        'membershipHeadHash',
      ])
        k: saved[k],
    };
  }

  /// Certify only after verify3 has accepted the same complete frozen selection.
  /// The certificate and own-log companion are durable, independently retried
  /// commands; neither operation activates old tokens or grants scope keys.
  Future<Map<String, dynamic>> certifyAndAnchor({
    required CryptoCaptureKeyDescriptor capture,
    required String sourceInventoryRoot,
    required String archiveManifestHash,
    required String coldParityProofHash,
  }) async {
    for (final hash in [
      sourceInventoryRoot,
      archiveManifestHash,
      coldParityProofHash,
    ]) {
      CryptoMigrationInvitationCodec.digest(hash);
    }
    final selected = await _selection(capture, sourceInventoryRoot);
    final action = 'legacyInvitationCertificate:${capture.captureId}';
    final prior = await runtime.db.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND action_id=?',
      [runtime.partition, action],
    );
    late Map<String, dynamic> header;
    if (prior.isNotEmpty) {
      header = Map<String, dynamic>.from(
        jsonDecode(prior.single['payload'] as String) as Map,
      );
      CryptoMigrationInvitationCodec.header(header);
      final expected = {
        ...selected['common'] as Map<String, dynamic>,
        'archiveManifestHash': archiveManifestHash,
        'coldParityProofHash': coldParityProofHash,
        'sourceCounts': selected['sourceCounts'],
        'bridgeCount': selected['bridgeCount'],
      };
      for (final key in expected.keys) {
        if (_canonical(header[key]) != _canonical(expected[key])) {
          throw const FormatException(
            'crypto_invitation_migration_certificate_immutable',
          );
        }
      }
      if (await CryptoMigrationInvitationCodec.bridgeRoot(
            header,
            _leafDigests(sourceInventoryRoot),
          ) !=
          header['bridgeRoot']) {
        throw const FormatException(
          'crypto_invitation_migration_selection_changed',
        );
      }
    } else {
      final own = await runtime.account.directory.requireFresh();
      header = {
        ...selected['common'] as Map<String, dynamic>,
        'archiveManifestHash': archiveManifestHash,
        'coldParityProofHash': coldParityProofHash,
        'authorDirectoryHeadHash': own.headHash,
        'bridgeCount': selected['bridgeCount'],
        'sourceCounts': selected['sourceCounts'],
        'bridgeRoot': '0' * 64,
      };
      header['bridgeRoot'] = await CryptoMigrationInvitationCodec.bridgeRoot(
        header,
        _leafDigests(sourceInventoryRoot),
      );
      await runtime.db.execute(
        'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)',
        [runtime.partition, capture.rootScopeId, action, jsonEncode(header)],
      );
    }
    final request = await runtime.queue.enqueueCommand(
      actionKey: action,
      operation: 'crypto2.migration.invitations.certify',
      payload: {'header': header},
    );
    await runtime.queue.resumeUnresolved(requestIds: {request});
    final result = await runtime.queue.commandResult(request);
    final outgoing = await runtime.queue.store.outgoing(request);
    final authorization = Map<String, dynamic>.from(
      jsonDecode(outgoing!['signed_body'] as String) as Map,
    );
    final certificateHash = await runtime.codec.digest(authorization);
    final scopeToken = await CryptoMigrationInvitationCodec.scopeToken(header);
    final expected = {
      'migrationId': capture.migrationId,
      'captureId': capture.captureId,
      'certificateHash': certificateHash,
      'selectionRoot': selected['selectionRoot'],
      'bridgeRoot': header['bridgeRoot'],
      'bridgeCount': header['bridgeCount'],
      'scopeToken': scopeToken,
      'state': 'certified',
    };
    if (_canonical(result) != _canonical(expected)) {
      throw const FormatException(
        'crypto_invitation_migration_certificate_response',
      );
    }
    final entry = await runtime.account.attestMigration(
      migrationId: capture.migrationId,
      scopeToken: scopeToken,
      domain: 'content',
      attestationHash: certificateHash,
    );
    final event = Map<String, dynamic>.from(entry['authorization'] as Map);
    final eventCommandHash = await cryptoSha256(
      cryptoBase64(event['commandBase64']),
    );
    final anchor = await runtime.queue.enqueueCommand(
      actionKey: '$action:anchor',
      operation: 'crypto2.migration.invitations.anchor',
      payload: {
        'migrationId': capture.migrationId,
        'captureId': capture.captureId,
        'sourceInventoryRoot': sourceInventoryRoot,
        'certificateHash': certificateHash,
        'eventHeadHash': entry['headHash'],
        'eventCommandHash': eventCommandHash,
      },
    );
    await runtime.queue.resumeUnresolved(requestIds: {anchor});
    final anchored = await runtime.queue.commandResult(anchor);
    if (_canonical(anchored) !=
        _canonical({
          'migrationId': capture.migrationId,
          'certificateHash': certificateHash,
          'state': 'anchored',
        })) {
      throw const FormatException(
        'crypto_invitation_migration_anchor_response',
      );
    }
    return {
      ...header,
      'selectionRoot': selected['selectionRoot'],
      'certificateHash': certificateHash,
      'eventHeadHash': entry['headHash'],
      'eventCommandHash': eventCommandHash,
      'authorization': authorization,
      'eventAuthorization': event,
      'state': 'anchored',
    };
  }

  Stream<Map<String, Object?>> _sources(String captureId) async* {
    String? after;
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=?'
        '${after == null ? '' : ' AND binding_id>?'} ORDER BY binding_id LIMIT 20',
        [runtime.partition, captureId, if (after != null) after],
      );
      if (rows.isEmpty) return;
      for (final row in rows) {
        after = row['binding_id'] as String;
        yield row;
      }
    }
  }

  Stream<String> _leafDigests(String root) async* {
    final prefix = 'invitation3leaf:$root:';
    String? after;
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT action_id FROM crypto_export_drafts WHERE partition=? AND action_id LIKE ?'
        '${after == null ? '' : ' AND action_id>?'} ORDER BY action_id LIMIT 20',
        [runtime.partition, '$prefix%', if (after != null) after],
      );
      if (rows.isEmpty) return;
      for (final row in rows) {
        after = row['action_id'] as String;
        yield after.substring(prefix.length);
      }
    }
  }

  Future<Map<String, dynamic>> _selection(
    CryptoCaptureKeyDescriptor capture,
    String root,
  ) async {
    final status = await CryptoCaptureCoordinator(
      runtime.account,
    ).verifiedStatus(capture);
    final common = <String, dynamic>{
      'version': 3,
      'serverId': runtime.account.directory.session.profile.serverId,
      'accountId': runtime.account.directory.accountId,
      'migrationId': capture.migrationId,
      'captureId': capture.captureId,
      'sourceInventoryRoot': root,
    };
    Stream<CryptoCaptureBinding> bindings() async* {
      await for (final row in _sources(capture.captureId)) {
        yield CryptoCaptureBinding.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(row['binding'] as String) as Map,
          ),
        );
      }
    }

    if (status['inventoryRoot'] != root ||
        await CryptoCaptureV3.inventoryRoot(
              serverId: common['serverId'],
              captureId: capture.captureId,
              migrationId: capture.migrationId,
              accountId: common['accountId'],
              sourceCount: status['sourceCount'],
              bindings: bindings(),
            ) !=
            root) {
      throw const FormatException(
        'crypto_invitation_migration_source_incomplete',
      );
    }
    final counts = {'invitation': 0, 'mail': 0};
    var count = 0;
    await for (final row in _sources(capture.captureId)) {
      final source = CryptoCaptureSourceContext.fromJson(
        Map<String, dynamic>.from(jsonDecode(row['context'] as String) as Map),
      );
      final kind = switch (source.sourceTable) {
        'familyhub_invitations' => 'invitation',
        'familyhub_invitation_mail' => 'mail',
        _ => null,
      };
      if (kind == null) continue;
      final binding = CryptoCaptureBinding.fromJson(
        Map<String, dynamic>.from(jsonDecode(row['binding'] as String) as Map),
      );
      final drafts = await runtime.db.rows(
        'SELECT payload FROM crypto_export_drafts WHERE partition=? AND action_id=?',
        [
          runtime.partition,
          'legacyInvitation:${capture.captureId}:${binding.bindingId}',
        ],
      );
      if (drafts.length != 1) {
        throw const FormatException(
          'crypto_invitation_migration_source_incomplete',
        );
      }
      final saved = Map<String, dynamic>.from(
        jsonDecode(drafts.single['payload'] as String) as Map,
      );
      final proof = Map<String, dynamic>.from(saved['authorization'] as Map);
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final payload = command['payload'] as Map;
      final context = payload['context'] as Map;
      if (command['operation'] != 'crypto2.invitations.bridgeLegacy' ||
          command['serverId'] != common['serverId'] ||
          command['accountId'] != common['accountId'] ||
          payload['sourceKind'] != kind ||
          source.serverId != common['serverId'] ||
          source.accountId != common['accountId'] ||
          source.captureId != capture.captureId ||
          source.migrationId != capture.migrationId ||
          binding.bindingId != row['binding_id'] ||
          saved['sourceInventoryRoot'] != root ||
          saved['sourceCommitment'] != binding.sourceCommitment ||
          context['sourceCommitment'] != binding.sourceCommitment ||
          context['bindingId'] != binding.bindingId ||
          context['sourceInventoryRoot'] != root) {
        throw const FormatException('crypto_invitation_migration_source');
      }
      final hash = await CryptoMigrationInvitationCodec.leafDigest({
        'bindingId': binding.bindingId,
        'kind': kind,
        'bridgeHash': await runtime.codec.digest(proof),
        'capsuleHash': payload['capsuleHash'],
      });
      await runtime.db.execute(
        'INSERT OR IGNORE INTO crypto_export_drafts VALUES(?,?,?,?)',
        [
          runtime.partition,
          capture.rootScopeId,
          'invitation3leaf:$root:$hash',
          jsonEncode({'bindingId': binding.bindingId}),
        ],
      );
      counts[kind] = counts[kind]! + 1;
      count++;
    }
    final selection = await CryptoMigrationInvitationCodec.selectionRoot(
      common,
      count,
      _leafDigests(root),
    );
    return {
      'common': common,
      'sourceCounts': counts,
      'bridgeCount': count,
      'selectionRoot': selection,
    };
  }
}
