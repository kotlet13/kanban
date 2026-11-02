import 'dart:convert';

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_business_router.dart';
import 'crypto_active_outbox.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart' show isCryptoCanonicalUuid;
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';

/// A new, verified assertion can fulfill an obsolete checkpoint assertion.
/// This is local derived-work bookkeeping, never a server terminal outcome.
/// The prefix is deliberately absent from FILE local-intent export allowlists.
class CryptoCheckpointSupersession {
  CryptoCheckpointSupersession(this.context);
  final CryptoBusinessSession context;

  Future<int> reconcile(
    String scope,
    String domain,
    CryptoReadContext read,
  ) async {
    final db = context.database, partition = context.partition;
    final inventory = await db.rows(
      "SELECT request_id,LENGTH(CAST(signed_body AS BLOB))+COALESCE(LENGTH(CAST(response AS BLOB)),0) AS bytes FROM crypto_outbox WHERE partition=? AND operation='crypto2.domain.checkpoint' AND state='blocked' AND ${cryptoActiveOutboxPredicate()} ORDER BY sequence LIMIT 65",
      [partition],
    );
    if (inventory.isEmpty ||
        inventory.length > 64 ||
        inventory.fold<int>(0, (n, r) => n + (r['bytes'] as int)) > 1048576) {
      return 0;
    }
    return context.access.withVerifiedOperation(() async {
      void current() {
        if (!context.account.directory.isCurrent()) {
          throw const CryptoAuthorityPending('crypto_stale_identity');
        }
      }

      final profile = context.account.directory.session.profile;
      final own = await context.account.directory.requireFresh();
      own.activeDevice(profile.deviceId);
      final head = await context.access.currentHead(scope, online: true);
      if (!head.active ||
          head.headHash != read.headHash ||
          head.epoch != read.epoch ||
          head.accessRevision != read.accessRevision ||
          !await context.hasReusableCheckpoint(scope, domain, read)) {
        return 0;
      }
      final checkpoints = await db.rows(
        'SELECT c.* FROM crypto_domain_checkpoints c JOIN crypto_scope_state s ON s.partition=c.partition AND s.scope_id=c.scope_id AND s.domain=c.domain WHERE c.partition=? AND c.scope_id=? AND c.domain=? AND c.head_hash=? AND c.epoch=? AND c.access_revision=? AND c.sequence=s.scope_sequence AND s.complete=1 LIMIT 2',
        [
          partition,
          scope,
          domain,
          read.headHash,
          read.epoch,
          read.accessRevision,
        ],
      );
      if (checkpoints.length != 1) return 0;
      final checkpoint = checkpoints.single;
      final replacement = _decode(checkpoint['authorization']);
      if (replacement == null) return 0;
      final next = replacement.command, payload = replacement.payload;
      if (!_identity(next, ownAccount: false) ||
          payload['scopeId'] != scope ||
          payload['domain'] != domain ||
          payload['membershipHeadHash'] != read.headHash ||
          payload['epoch'] != read.epoch ||
          payload['accessRevision'] != read.accessRevision ||
          payload['expectedSequence'] != checkpoint['sequence'] ||
          payload['manifestHash'] != checkpoint['manifest_hash'] ||
          payload['recordCount'] != checkpoint['record_count'] ||
          payload['historyBasis'] != checkpoint['history_basis']) {
        return 0;
      }
      await context.access.verifyDomainCheckpoint(
        replacement.proof,
        onlineAuthorDirectory: true,
      );
      final nextRow = await context.queue.store.outgoing(next['requestId']);
      // A fully verified downloaded attestation need not have an outgoing row
      // on this device. Never manufacture a receipt for that remote assertion.
      final localReplacement =
          nextRow != null &&
          _applied(nextRow, replacement.proof) &&
          await _hash(replacement.proof) == nextRow['request_hash'];
      if (nextRow != null && !localReplacement) return 0;
      var changed = 0;
      for (final item in inventory) {
        current();
        final old = await context.queue.store.outgoing(
          item['request_id'] as String,
        );
        if (old == null || old['state'] != 'blocked') continue;
        final previous = _decode(old['signed_body']);
        if (previous == null ||
            !_identity(previous.command) ||
            previous.command['requestId'] != old['request_id'] ||
            old['operation'] != 'crypto2.domain.checkpoint' ||
            await _hash(previous.proof) != old['request_hash'] ||
            !_eligibleReason(old['response'])) {
          continue;
        }
        final before = previous.payload;
        if (before['scopeId'] != scope ||
            before['domain'] != domain ||
            before['expectedSequence'] is! int ||
            (before['expectedSequence'] as int) >
                (payload['expectedSequence'] as int) ||
            before['epoch'] is! int ||
            before['accessRevision'] is! int ||
            (before['epoch'] as int) > read.epoch ||
            (before['accessRevision'] as int) > read.accessRevision) {
          continue;
        }
        // At the same sequence nothing may change silently. A later verified
        // inventory covers all locally known records/anchors via reuse checks;
        // this only retires a derived assertion, never a user record/intent.
        final sameInventory =
            before['manifestHash'] == payload['manifestHash'] &&
            before['recordCount'] == payload['recordCount'] &&
            before['historyBasis'] == payload['historyBasis'];
        if ((!sameInventory &&
                before['expectedSequence'] == payload['expectedSequence']) ||
            (before['epoch'] == read.epoch &&
                before['membershipHeadHash'] != read.headHash)) {
          continue;
        }
        final marker =
            'crypto_checkpoint_superseded_v1:$partition:${old['request_id']}';
        final oldMarker = (await db.rows(
          'SELECT value FROM local_meta WHERE name=?',
          [marker],
        )).firstOrNull?['value'];
        if ((await db.rows(
          'SELECT 1 FROM crypto_outbox_records WHERE partition=? AND request_id=? LIMIT 1',
          [partition, old['request_id']],
        )).isNotEmpty) {
          continue;
        }
        try {
          final verified = await context.access.verifyDomainCheckpoint(
            previous.proof,
            onlineAuthorDirectory: true,
          );
          if (!await _descends(head, verified.head)) continue;
        } on CryptoAuthorityPending {
          continue;
        } on FormatException {
          continue;
        }
        if (!await context.queue.hasUnknownHeldReceipt(
          requestId: old['request_id'] as String,
          requestHash: old['request_hash'] as String,
          checkCurrent: () async => current(),
        )) {
          continue;
        }
        // A receipt lookup is an asynchronous boundary. Recheck live authority
        // and full local inventory before the atomic bookkeeping commit.
        context.access.invalidateAuthorityOperation();
        final finalOwn = await context.account.directory.requireFresh();
        finalOwn.activeDevice(profile.deviceId);
        final finalHead = await context.access.currentHead(scope, online: true);
        if (finalOwn.headHash != own.headHash ||
            finalOwn.deviceSnapshotHash != own.deviceSnapshotHash ||
            finalHead.headHash != read.headHash ||
            !await context.hasReusableCheckpoint(scope, domain, read)) {
          continue;
        }
        final details = utf8.decode(
          CryptoJson.encode({
            'version': localReplacement ? 1 : 2,
            'oldRequestHash': old['request_hash'],
            'newRequestId': next['requestId'],
            'newRequestHash': await _hash(replacement.proof),
            if (!localReplacement)
              'replacementAuthorization': checkpoint['authorization'],
            if (!localReplacement)
              'replacementSequence': checkpoint['sequence'],
            if (!localReplacement)
              'replacementManifest': checkpoint['manifest_hash'],
            'scopeId': scope,
            'domain': domain,
            'oldHeadHash': before['membershipHeadHash'],
            'newHeadHash': read.headHash,
          }),
        );
        final saved = await db.transaction(() async {
          current();
          final stillOld = await context.queue.store.outgoing(
            old['request_id'] as String,
          );
          final stillNext = await context.queue.store.outgoing(
            next['requestId'],
          );
          if ((await db.rows('SELECT value FROM local_meta WHERE name=?', [
                marker,
              ])).firstOrNull?['value'] !=
              oldMarker) {
            return false;
          }
          if (stillOld == null ||
              stillOld['state'] != 'blocked' ||
              stillOld['request_hash'] != old['request_hash'] ||
              stillOld['signed_body'] != old['signed_body'] ||
              stillOld['response'] != old['response'] ||
              (localReplacement
                  ? (stillNext == null ||
                        stillNext['request_hash'] != nextRow['request_hash'] ||
                        !_applied(stillNext, replacement.proof))
                  : stillNext != null) ||
              !await context.hasReusableCheckpoint(scope, domain, read) ||
              (await db.rows(
                'SELECT 1 FROM crypto_outbox_records WHERE partition=? AND request_id=? LIMIT 1',
                [partition, old['request_id']],
              )).isNotEmpty) {
            return false;
          }
          if ((await db.rows(
                'SELECT 1 FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? AND snapshot_id=? AND authorization=?',
                [
                  partition,
                  scope,
                  domain,
                  checkpoint['snapshot_id'],
                  checkpoint['authorization'],
                ],
              )).length !=
              1) {
            return false;
          }
          await db.execute(
            'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
            [marker, details],
          );
          await db.execute(
            'INSERT INTO crypto_outbox_attempts(partition,request_id,event,details) VALUES(?,?,?,?)',
            [
              partition,
              old['request_id'],
              'checkpoint_superseded_locally',
              details,
            ],
          );
          await db.execute(
            'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
            [
              'held_receipt_refresh_v1:$partition',
              'checkpoint:${old['request_id']}:${context.codec.crypto.randomId()}',
            ],
          );
          current();
          return true;
        });
        if (saved) changed++;
      }
      return changed;
    }, freshBoundary: true);
  }

  Future<bool> _descends(VerifiedScopeHead head, VerifiedScopeHead old) async {
    var cursor = head;
    for (var i = 0; i < 64 && cursor.epoch > old.epoch; i++) {
      final previous = await context.access.headAt(
        head.scopeId,
        cursor.body['previousHeadHash'],
      );
      if (previous.epoch >= cursor.epoch ||
          previous.accessRevision > cursor.accessRevision) {
        return false;
      }
      cursor = previous;
    }
    return cursor.headHash == old.headHash;
  }

  bool _identity(Map command, {bool ownAccount = true}) {
    final profile = context.account.directory.session.profile;
    return command.length == 8 &&
        command['version'] == 2 &&
        command['operation'] == 'crypto2.domain.checkpoint' &&
        command['signer'] == 'device' &&
        command['serverId'] == profile.serverId &&
        (!ownAccount || command['accountId'] == profile.accountId) &&
        isCryptoCanonicalUuid(command['accountId']) &&
        isCryptoCanonicalUuid(command['deviceId']) &&
        command['requestId'] is String;
  }

  Future<String> _hash(Map<String, dynamic> proof) =>
      cryptoSha256(cryptoBase64(proof['commandBase64']));

  bool _applied(Map row, Map<String, dynamic> proof) {
    if (row['operation'] != 'crypto2.domain.checkpoint' ||
        row['state'] != 'applied') {
      return false;
    }
    try {
      final receipt = jsonDecode(row['response'] as String) as Map;
      return receipt['status'] == 200 &&
          receipt['requestId'] == row['request_id'] &&
          receipt['requestHash'] == row['request_hash'] &&
          jsonEncode(CryptoJson.encode(receipt['authorization'])) ==
              jsonEncode(CryptoJson.encode(proof)) &&
          jsonEncode(
                CryptoJson.encode(jsonDecode(row['signed_body'] as String)),
              ) ==
              jsonEncode(CryptoJson.encode(proof));
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  bool _eligibleReason(Object? raw) {
    try {
      final response = jsonDecode(raw as String) as Map;
      return response['outcome'] == 'unresolved' &&
          response['reason'] == 'authority_pending' &&
          const {
            'scope_rotation_required',
            'scope_reauthorization_required',
          }.contains(response['code']);
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  ({Map<String, dynamic> proof, Map command, Map payload})? _decode(
    Object? raw,
  ) {
    try {
      final proof = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
      if (proof.length != 2 ||
          !proof.containsKey('commandBase64') ||
          !proof.containsKey('signatureBase64')) {
        return null;
      }
      cryptoBase64(proof['signatureBase64'], length: 64);
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      return (
        proof: proof,
        command: command,
        payload: command['payload'] as Map,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
