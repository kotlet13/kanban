import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_v3.dart';
import 'crypto_json.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_notification_codec.dart';
import 'crypto_migration_notification_control.dart';
import 'crypto_migration_prepared_target.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// Existing remote reminders are reviewed explicitly before immutable staging.
/// All bytes/use IDs are journaled before HTTP. No job becomes active here.
class CryptoMigrationNotificationProducer {
  CryptoMigrationNotificationProducer(this.runtime);
  final CryptoBusinessSession runtime;
  static final _certificates = <String, Future<void>>{};

  /// Finalize exactly the selection already compared by a fresh FILE process
  /// and accepted by verify3. Empty selections follow the same signed path.
  /// This creates no active reminder/job; final component SQL installs later.
  Future<Map<String, dynamic>> certifyAndAnchor(
    VerifiedCryptoMigrationColdBusiness verified,
  ) async {
    final key = '${runtime.partition}:${verified.header['captureId']}';
    final task = (_certificates[key] ?? Future<void>.value()).then(
      (_) => _certifyAndAnchor(verified),
    );
    final marker = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _certificates[key] = marker;
    try {
      return await task;
    } finally {
      if (identical(_certificates[key], marker)) _certificates.remove(key);
    }
  }

  Future<Map<String, dynamic>> _certifyAndAnchor(
    VerifiedCryptoMigrationColdBusiness verified,
  ) async {
    final h = verified.header;
    final common = <String, dynamic>{
      'version': 3,
      for (final k in [
        'serverId',
        'accountId',
        'migrationId',
        'captureId',
        'sourceInventoryRoot',
      ])
        k: h[k],
    };
    CryptoMigrationNotificationCodec.context(common);
    if (common['serverId'] !=
            runtime.account.directory.session.profile.serverId ||
        common['accountId'] != runtime.account.directory.accountId) {
      throw const FormatException('crypto_notification_migration_context');
    }
    final section = verified.controlSections['notifications'];
    if (section == null || section['kind'] != 'notifications') {
      throw const FormatException('crypto_notification_migration_cold_parity');
    }
    CryptoMigrationNotificationCodec.fields(section, {'kind', 'count', 'root'});
    final verification = await CryptoMigrationColdBusiness(
      runtime.account,
    ).verificationAuthorization(verified);
    final coldHash = await cryptoSha256(CryptoJson.encode(verification));
    final current = await runtime.account.directory.requireFresh();
    final prefixes = <String, VerifiedAccountDirectory>{};
    Future<VerifiedAccountDirectory> prefix(String reference) async {
      if (prefixes[reference] != null) return prefixes[reference]!;
      final pin = await runtime.account.store.anchor(current.accountId);
      if (pin == null) {
        throw const CryptoAuthorityPending(
          'crypto_control_file_anchor_pending',
        );
      }
      VerifiedAccountDirectory? state;
      await for (final entry in runtime.account.store.streamEntries(
        current.accountId,
      )) {
        state = await runtime.account.directory.reducer.apply(
          previous: state,
          entry: entry,
          serverId: current.serverId,
          accountId: current.accountId,
          pinnedRootFingerprint:
              pin['genesisFingerprint'] ?? pin['fingerprint'],
        );
        if (!current.includesAnchor(state.generation, state.headHash)) {
          throw const FormatException('crypto_control_directory_fork');
        }
        if (state.headHash == reference) {
          if (state.deviceSnapshotHash != current.deviceSnapshotHash ||
              state.identityEpochId != current.identityEpochId) {
            throw const CryptoAuthorityPending('crypto_control_signer_changed');
          }
          return prefixes[reference] = state;
        }
      }
      throw const CryptoAuthorityPending('crypto_control_directory_pending');
    }

    Future<void> checkOwn(
      Map<String, dynamic> proof,
      Map body,
      String domain,
    ) async {
      final p = await prefix(body['authorDirectoryHeadHash']);
      runtime.codec.crypto.verifyDomain(
        proof,
        cryptoBase64(
          p.activeDevice(body['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        domain,
      );
    }

    await runtime.db.execute(
      'CREATE TEMP TABLE IF NOT EXISTS crypto_notification_certificate_leaves('
      'capture_id TEXT NOT NULL,binding_id TEXT NOT NULL,leaf_hash TEXT NOT NULL,kind TEXT NOT NULL,'
      'PRIMARY KEY(capture_id,binding_id),UNIQUE(capture_id,leaf_hash))',
    );
    await runtime.db.execute(
      'DELETE FROM crypto_notification_certificate_leaves WHERE capture_id=?',
      [h['captureId']],
    );
    final counts = {
      for (final k in CryptoMigrationNotificationCodec.kinds) k: 0,
    };
    String? after;
    while (true) {
      final page = await runtime.account.directory
          .call('crypto2.migration.notifications.transforms', {
            'migrationId': h['migrationId'],
            'captureId': h['captureId'],
            'sourceInventoryRoot': h['sourceInventoryRoot'],
            if (after != null) 'afterBindingId': after,
            'limit': 20,
          });
      if (page['transforms'] is! List ||
          (page['transforms'] as List).length > 20 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_notification_migration_page');
      }
      for (final item in page['transforms'] as List) {
        if (item is! Map) {
          throw const FormatException('crypto_notification_migration_shape');
        }
        CryptoMigrationNotificationCodec.fields(item, {
          'bindingId',
          'authorization',
        });
        final proof = Map<String, dynamic>.from(item['authorization'] as Map);
        final body = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
        );
        CryptoMigrationNotificationCodec.fields(body, {
          ...CryptoMigrationNotificationCodec.contextFields,
          'operation',
          'deviceId',
          'bindingId',
          'kind',
          'canonical',
          'authorDirectoryHeadHash',
          'useAuthorization',
        });
        if (body['operation'] != 'crypto2.migration.notificationTransform' ||
            body['bindingId'] != item['bindingId'] ||
            !isCryptoCanonicalUuid(body['bindingId']) ||
            after != null && after.compareTo(body['bindingId']) >= 0 ||
            !counts.containsKey(body['kind'])) {
          throw const FormatException('crypto_notification_migration_context');
        }
        for (final k in common.keys) {
          if (body[k] != common[k]) {
            throw const FormatException(
              'crypto_notification_migration_context',
            );
          }
        }
        await checkOwn(proof, body, 'JivieE2EE/notificationTransform/v3\n');
        final transformHash = await cryptoSha256([
          ...utf8.encode('JivieNotificationTransform/v3\n'),
          ...CryptoJson.encode(proof),
        ]);
        final leafHash = await CryptoMigrationNotificationCodec.leafDigest({
          'bindingId': body['bindingId'],
          'kind': body['kind'],
          'transformHash': transformHash,
          'useProofHash': body['useAuthorization'] == null
              ? null
              : await cryptoSha256(CryptoJson.encode(body['useAuthorization'])),
        });
        await runtime.db.execute(
          'INSERT INTO crypto_notification_certificate_leaves VALUES(?,?,?,?)',
          [h['captureId'], body['bindingId'], leafHash, body['kind']],
        );
        counts[body['kind']] = counts[body['kind']]! + 1;
        after = body['bindingId'];
      }
      if (page['hasMore'] == false) break;
      if ((page['transforms'] as List).isEmpty ||
          page['nextAfterBindingId'] != after) {
        throw const FormatException('crypto_notification_migration_cursor');
      }
    }
    Stream<String> leaves() async* {
      String? last;
      while (true) {
        final rows = await runtime.db.rows(
          'SELECT leaf_hash FROM crypto_notification_certificate_leaves WHERE capture_id=?'
          '${last == null ? '' : ' AND leaf_hash>?'} ORDER BY leaf_hash LIMIT 20',
          [h['captureId'], if (last != null) last],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          last = row['leaf_hash'] as String;
          yield last;
        }
      }
    }

    final count = counts.values.fold<int>(0, (a, b) => a + b);
    final selection = await CryptoMigrationNotificationCodec.selectionRoot(
      common,
      count,
      leaves(),
    );
    if (section['count'] != count || section['root'] != selection) {
      throw const FormatException('crypto_notification_migration_cold_parity');
    }
    final actionKey = 'notification3certify:${h['captureId']}';
    final prior = await runtime.db.rows(
      'SELECT o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o'
      ' ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
      [runtime.partition, actionKey],
    );
    late Map<String, dynamic> header;
    if (prior.isNotEmpty) {
      if (prior.length != 1) {
        throw const FormatException('crypto_immutable_command');
      }
      final p = jsonDecode(prior.single['signed_body'] as String) as Map;
      final command =
          CryptoJson.decode(cryptoBase64(p['commandBase64'])) as Map;
      if (command['operation'] != 'crypto2.migration.notifications.certify') {
        throw const FormatException('crypto_immutable_command');
      }
      header = Map<String, dynamic>.from(command['payload']['header'] as Map);
    } else {
      header = {
        ...common,
        'archiveManifestHash': h['archiveManifestHash'],
        'coldParityProofHash': coldHash,
        'authorDirectoryHeadHash': current.headHash,
        'transformCount': count,
        'sourceCounts': counts,
        'transformRoot': '0' * 64,
      };
      header['transformRoot'] =
          await CryptoMigrationNotificationCodec.transformRoot(
            header,
            leaves(),
          );
    }
    CryptoMigrationNotificationCodec.header(header);
    for (final k in common.keys) {
      if (header[k] != common[k]) {
        throw const FormatException('crypto_immutable_command');
      }
    }
    if (header['archiveManifestHash'] != h['archiveManifestHash'] ||
        header['coldParityProofHash'] != coldHash ||
        header['transformCount'] != count ||
        !CryptoMigrationColdEvidence.same(header['sourceCounts'], counts) ||
        header['transformRoot'] !=
            await CryptoMigrationNotificationCodec.transformRoot(
              header,
              leaves(),
            )) {
      throw const FormatException('crypto_immutable_command');
    }
    final request = await runtime.queue.enqueueCommand(
      actionKey: actionKey,
      operation: 'crypto2.migration.notifications.certify',
      payload: {'header': header},
    );
    await runtime.queue.resumeUnresolved(requestIds: {request});
    final result = await runtime.queue.commandResult(request);
    final row = (await runtime.queue.store.outgoing(request))!;
    final certificate = Map<String, dynamic>.from(
      jsonDecode(row['signed_body'] as String) as Map,
    );
    final certificateHash = await cryptoSha256(CryptoJson.encode(certificate));
    if (result['certificateHash'] != certificateHash ||
        result['transformRoot'] != header['transformRoot'] ||
        result['transformCount'] != count ||
        result['selectionRoot'] != selection ||
        result['scopeToken'] !=
            await CryptoMigrationNotificationCodec.scopeToken(header) ||
        result['state'] != 'certified') {
      throw const FormatException('crypto_notification_migration_certificate');
    }
    final certificateCommand =
        CryptoJson.decode(cryptoBase64(certificate['commandBase64'])) as Map;
    await checkOwn(certificate, {
      ...header,
      'deviceId': certificateCommand['deviceId'],
    }, cryptoDirectoryDomain);
    final event = await runtime.account.attestMigration(
      migrationId: h['migrationId'],
      scopeToken: await CryptoMigrationNotificationCodec.scopeToken(header),
      domain: 'content',
      attestationHash: certificateHash,
    );
    final observed = await runtime.account.directory.cachedVerifiedDirectory();
    if (!observed.includesAnchor(event['generation'], event['headHash'])) {
      throw const FormatException('crypto_notification_migration_event');
    }
    runtime.access.invalidateAuthorityOperation();
    final anchor = await runtime.queue.enqueueCommand(
      actionKey: 'notification3anchor:${h['captureId']}',
      operation: 'crypto2.migration.notifications.anchor',
      payload: {
        'migrationId': h['migrationId'],
        'captureId': h['captureId'],
        'sourceInventoryRoot': h['sourceInventoryRoot'],
        'certificateHash': certificateHash,
        'eventHeadHash': event['headHash'],
        'eventCommandHash': event['commandHash'],
      },
    );
    await runtime.queue.resumeUnresolved(requestIds: {anchor});
    final anchored = await runtime.queue.commandResult(anchor);
    if (anchored['state'] != 'anchored' ||
        anchored['certificateHash'] != certificateHash ||
        anchored['migrationId'] != h['migrationId']) {
      throw const FormatException('crypto_notification_migration_event');
    }
    return {
      ...common,
      'selectionRoot': selection,
      'transformRoot': header['transformRoot'],
      'transformCount': count,
      'sourceCounts': counts,
      'certificateHash': certificateHash,
      'authorization': certificate,
      'eventHeadHash': event['headHash'],
      'eventCommandHash': event['commandHash'],
      'eventAuthorization': event['authorization'],
      'state': 'anchored',
    };
  }

  Future<Map<String, dynamic>> stageAll(
    CryptoCaptureKeyDescriptor capture, {
    required bool acceptedRemoteDateDisclosure,
  }) async {
    final status = await CryptoCaptureCoordinator(
      runtime.account,
    ).verifiedStatus(capture);
    final common = <String, dynamic>{
      'version': 3,
      'serverId': runtime.account.directory.session.profile.serverId,
      'accountId': runtime.account.directory.accountId,
      'migrationId': capture.migrationId,
      'captureId': capture.captureId,
      'sourceInventoryRoot': status['inventoryRoot'],
    };
    Stream<CryptoCaptureBinding> bindings() async* {
      String? cursor;
      while (true) {
        final page = await runtime.db.rows(
          'SELECT binding_id,binding FROM crypto_capture_sources WHERE partition=? AND capture_id=?'
          '${cursor == null ? '' : ' AND binding_id>?'} ORDER BY binding_id LIMIT 20',
          [runtime.partition, capture.captureId, if (cursor != null) cursor],
        );
        if (page.isEmpty) break;
        for (final row in page) {
          cursor = row['binding_id'] as String;
          yield CryptoCaptureBinding.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(row['binding'] as String) as Map,
            ),
          );
        }
      }
    }

    if (await CryptoCaptureV3.inventoryRoot(
          serverId: common['serverId'],
          captureId: capture.captureId,
          migrationId: capture.migrationId,
          accountId: common['accountId'],
          sourceCount: status['sourceCount'],
          bindings: bindings(),
        ) !=
        common['sourceInventoryRoot']) {
      throw const FormatException(
        'crypto_notification_migration_source_incomplete',
      );
    }
    final counts = {
      for (final k in CryptoMigrationNotificationCodec.kinds) k: 0,
    };
    var total = 0;
    final leafPrefix = 'notification3leaf:${common['sourceInventoryRoot']}:';
    String? after;
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=?'
        '${after == null ? '' : ' AND binding_id>?'} ORDER BY binding_id LIMIT 20',
        [runtime.partition, capture.captureId, if (after != null) after],
      );
      if (rows.isEmpty) break;
      final transforms = <Map<String, dynamic>>[];
      for (final row in rows) {
        after = row['binding_id'] as String;
        final source = CryptoCaptureSourceContext.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(row['context'] as String) as Map,
          ),
        );
        final kind =
            CryptoMigrationNotificationControl.tableKinds[source.sourceTable];
        if (kind == null) continue;
        final binding = CryptoCaptureBinding.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(row['binding'] as String) as Map,
          ),
        );
        if (binding.bindingId != after ||
            source.migrationId != capture.migrationId ||
            source.captureId != capture.captureId ||
            source.accountId != common['accountId'] ||
            source.serverId != common['serverId']) {
          throw const FormatException('crypto_notification_migration_source');
        }
        final saved = await runtime.db.rows(
          'SELECT payload,authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state=?',
          [
            runtime.partition,
            capture.captureId,
            'notification3:$after',
            'notificationMigrationTransform',
          ],
        );
        late Map<String, dynamic> body, proof;
        if (saved.isNotEmpty) {
          if (saved.length != 1) {
            throw const FormatException(
              'crypto_notification_migration_journal',
            );
          }
          body = Map<String, dynamic>.from(
            CryptoJson.decode(
                  Uint8List.fromList(
                    (saved.single['payload'] as List).cast<int>(),
                  ),
                )
                as Map,
          );
          proof = Map<String, dynamic>.from(
            CryptoJson.decode(
                  Uint8List.fromList(
                    (saved.single['authorization'] as List).cast<int>(),
                  ),
                )
                as Map,
          );
          for (final k in common.keys) {
            if (body[k] != common[k]) {
              throw const FormatException('crypto_immutable_command');
            }
          }
          if (body['kind'] != kind || body['bindingId'] != after) {
            throw const FormatException('crypto_immutable_command');
          }
        } else {
          final raw = CryptoMigrationColdEvidence.cells(
            Map<String, dynamic>.from(
              jsonDecode(row['typed_row'] as String) as Map,
            ),
          );
          final prepared = await _canonical(
            capture,
            source.sourceTable,
            raw,
            acceptedRemoteDateDisclosure,
          );
          final own = await runtime.account.directory.requireFresh();
          own.activeDevice(runtime.account.deviceId);
          body = {
            ...common,
            'operation': 'crypto2.migration.notificationTransform',
            'deviceId': runtime.account.deviceId,
            'bindingId': after,
            'kind': kind,
            'canonical': prepared.canonical,
            'authorDirectoryHeadHash': own.headHash,
            'useAuthorization': null,
          };
          final c = prepared.canonical;
          if (kind == 'reminder' &&
              prepared.target != null &&
              c['scheduleMode'] == 'deadline' &&
              c['state'] != 'cancelled') {
            final r = prepared.target!.record;
            final use = {
              ...common,
              'version': 3,
              'operation': 'crypto2.migration.schedulingUse',
              'scopeId': c['scopeId'],
              'targetId': c['targetId'],
              'targetType': c['targetType'],
              'domain': c['domain'],
              'useId': runtime.codec.crypto.randomId(),
              'sourceScheduleRevision': c['scheduleRevision'],
              'schedulePutId': c['id'],
              'consentGeneration': c['consentGeneration'],
              'scopeLifecycleHash': c['scopeLifecycleHash'],
              'projectBarrier': c['projectBarrier'],
              'expiresAtEpoch': null,
              'mode': 'relative',
              'membershipHeadHash': r['membershipHeadHash'],
              'accessRevision': r['accessRevision'],
              'targetRevision': c['targetRevision'],
              'targetRecordProofHash': c['targetRecordProofHash'],
              'deviceId': runtime.account.deviceId,
              'authorDirectoryHeadHash': own.headHash,
              'bindingId': after,
              'originalState': c['state'],
            };
            final key = await runtime.account.signingKey();
            try {
              body['useAuthorization'] = runtime.codec.crypto.signDomain(
                use,
                key.key,
                'JivieE2EE/migrationSchedulingUse/v3\n',
              );
            } finally {
              key.release();
            }
          }
          final key = await runtime.account.signingKey();
          try {
            proof = runtime.codec.crypto.signDomain(
              body,
              key.key,
              'JivieE2EE/notificationTransform/v3\n',
            );
          } finally {
            key.release();
          }
          await runtime.db.execute(
            'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
            [
              runtime.partition,
              capture.captureId,
              'notification3:$after',
              'notificationMigrationTransform',
              CryptoJson.encode(body),
              CryptoJson.encode(proof),
            ],
          );
        }
        // Journaling never makes server-returned settings or dates authoritative;
        // the independent FILE cold control compares the full source afterward.
        final transformHash = await cryptoSha256([
          ...utf8.encode('JivieNotificationTransform/v3\n'),
          ...CryptoJson.encode(proof),
        ]);
        final leaf = {
          'bindingId': after,
          'kind': kind,
          'transformHash': transformHash,
          'useProofHash': body['useAuthorization'] == null
              ? null
              : await cryptoSha256(CryptoJson.encode(body['useAuthorization'])),
        };
        final leafHash = await CryptoMigrationNotificationCodec.leafDigest(
          leaf,
        );
        final prior = await runtime.db.rows(
          'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
          [runtime.partition, capture.captureId, '$leafPrefix$leafHash'],
        );
        if (prior.isEmpty) {
          await runtime.db.execute(
            'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
            [
              runtime.partition,
              capture.captureId,
              '$leafPrefix$leafHash',
              'notificationMigrationLeaf',
              CryptoJson.encode(leaf),
            ],
          );
        } else if (!CryptoMigrationColdEvidence.same(
          CryptoJson.decode(
            Uint8List.fromList((prior.single['payload'] as List).cast<int>()),
          ),
          leaf,
        )) {
          throw const FormatException('crypto_immutable_command');
        }
        total++;
        counts[kind] = counts[kind]! + 1;
        transforms.add({'authorization': proof, 'previousTransformHash': null});
      }
      if (transforms.isNotEmpty) {
        final first =
            (CryptoJson.decode(
                  cryptoBase64(
                    transforms.first['authorization']['commandBase64'],
                  ),
                )
                as Map)['bindingId'];
        final last =
            (CryptoJson.decode(
                  cryptoBase64(
                    transforms.last['authorization']['commandBase64'],
                  ),
                )
                as Map)['bindingId'];
        final request = await runtime.queue.enqueueCommand(
          actionKey: 'notification3:${capture.captureId}:$first:$last',
          operation: 'crypto2.migration.notifications.stage',
          payload: {
            'migrationId': capture.migrationId,
            'captureId': capture.captureId,
            'sourceInventoryRoot': common['sourceInventoryRoot'],
            'transforms': transforms,
          },
        );
        await runtime.queue.resumeUnresolved(requestIds: {request});
        await runtime.queue.commandResult(request);
      }
    }
    Stream<String> digests() async* {
      String? afterId;
      while (true) {
        final page = await runtime.db.rows(
          'SELECT intent_id FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state=? AND intent_id LIKE ?'
          '${afterId == null ? '' : ' AND intent_id>?'} ORDER BY intent_id LIMIT 20',
          [
            runtime.partition,
            capture.captureId,
            'notificationMigrationLeaf',
            '$leafPrefix%',
            if (afterId != null) afterId,
          ],
        );
        if (page.isEmpty) break;
        for (final row in page) {
          afterId = row['intent_id'] as String;
          yield afterId.substring(leafPrefix.length);
        }
      }
    }

    return {
      ...common,
      'selectionRoot': await CryptoMigrationNotificationCodec.selectionRoot(
        common,
        total,
        digests(),
      ),
      'transformCount': total,
      'sourceCounts': counts,
    };
  }

  int _n(Map<String, String?> row, String key) =>
      CryptoMigrationColdEvidence.integer(row[key]);
  Future<_NotificationCanonical> _canonical(
    CryptoCaptureKeyDescriptor capture,
    String table,
    Map<String, String?> r,
    bool consent,
  ) async {
    if (table == 'familyhub_inbox_state') {
      return _NotificationCanonical({
        'sequence': _n(r, 'sequence'),
        'visibilityRevision': _n(r, 'visibility_revision'),
      });
    }
    if (table == 'familyhub_inbox_preferences') {
      return _NotificationCanonical({
        'scopeId': r['scope_id'],
        'category': r['category'],
        'settings': {
          'inApp': true,
          'sound': true,
          'push': true,
          'email': false,
          ...(r['settings'] == null ? {} : jsonDecode(r['settings']!) as Map),
        },
      });
    }
    if (table == 'familyhub_deliveries' || table == 'familyhub_push_jobs') {
      return _NotificationCanonical({
        'rowKind': table == 'familyhub_push_jobs' ? 'push' : 'delivery',
        'inboxId': _n(r, 'inbox_id'),
        'state': r['state'],
        'attempts': _n(r, 'attempts'),
        'nextAttempt': _n(r, 'next_attempt'),
        'expiresAt': _n(r, 'expires_at'),
        'leaseToken': r['lease_token'],
        'leaseUntil': r['lease_until'] == null ? null : _n(r, 'lease_until'),
        'sentAt': r['sent_at'] == null ? null : _n(r, 'sent_at'),
        if (table == 'familyhub_push_jobs') ...{
          'deviceId': r['device_id'],
          'registrationRevision': _n(r, 'registration_revision'),
          'tokenHash': r['token_hash'],
        },
      });
    }
    if (table == 'familyhub_inbox') {
      return _NotificationCanonical({
        'rowKind': 'inbox',
        'id': _n(r, 'id'),
        'eventKey': r['event_key'],
        'scopeId': r['scope_id'],
        'category': r['category'],
        'kind': 'crypto2.${r['kind']}',
        'audience': r['audience'],
        'actorAccountId': r['actor_account_id'],
        'targetType': r['target_type'],
        'canonicalTargetId': r['target_id'],
        'targetId': r['target_type'] == 'membership'
            ? r['target_id']
            : cryptoWireRecordId(
                runtime.account.directory.session.profile.serverId,
                r['scope_id']!,
                r['target_type']!,
                r['target_id']!,
              ),
        'targetRevision': _n(r, 'target_revision'),
        'groupKey': r['group_key'],
        'createdAt': r['created_at'],
        'readAt': r['read_at'],
        'revision': _n(r, 'revision'),
        'sequence': _n(r, 'sequence'),
        'inApp': r['in_app'] == '1',
      });
    }
    if (table != 'familyhub_reminders') {
      throw const FormatException('crypto_notification_migration_kind');
    }
    if (r['schedule_mode'] == 'deadline' &&
        r['state'] != 'cancelled' &&
        !consent) {
      throw const CryptoAuthorityPending(
        'crypto_migration_remote_date_consent_required',
      );
    }
    final type = r['target_type']!,
        scope = r['scope_id']!,
        canonical = r['target_id']!,
        domain = cryptoRecordDomain(type);
    final wire = cryptoWireRecordId(
      runtime.account.directory.session.profile.serverId,
      scope,
      type,
      canonical,
    );
    CryptoPreparedMigrationTarget? target;
    try {
      target = await prepareCryptoMigrationTarget(
        context: runtime,
        migrationId: capture.migrationId,
        scopeId: scope,
        domain: domain,
        wireId: wire,
      );
    } on CryptoProjectionPending {
      if (r['state'] == 'pending') rethrow;
    }
    final state = target?.record['metadata']['reminderState'] as Map?;
    if (target != null &&
        (state == null || !isCryptoCanonicalUuid(state['consentGeneration']))) {
      throw const CryptoAuthorityPending(
        'crypto_migration_schedule_generation_pending',
      );
    }
    final needsBarrier =
        r['state'] == 'pending' ||
        r['schedule_mode'] == 'deadline' && r['state'] != 'cancelled';
    final lifecycle = target == null
        ? null
        : await (await runtime.access.migrationCandidate(
            scopeId: scope,
            migrationId: capture.migrationId,
            captureId: capture.captureId,
            headHash: target.record['membershipHeadHash'] as String,
          )).lifecycleHash();
    final project = target == null || !needsBarrier
        ? null
        : await _projectBarrier(capture, target.record);
    return _NotificationCanonical({
      'id': r['id'],
      'scopeId': scope,
      'targetType': type,
      'canonicalTargetId': canonical,
      'targetId': wire,
      'domain': domain,
      'targetRevision': target == null
          ? 0
          : target.record['expectedRevision'] + 1,
      'targetRecordProofHash': target?.proofHash,
      'scheduleRevision':
          state?['scheduleRevision'] ?? runtime.codec.crypto.randomId(),
      'consentGeneration': state?['consentGeneration'],
      'scopeLifecycleHash': lifecycle,
      'projectBarrier': project,
      'remindAt': r['remind_at'],
      'remindEpoch': _n(r, 'remind_epoch'),
      'revision': _n(r, 'revision'),
      'state': r['state'],
      'scheduleMode': r['schedule_mode'],
      'offsetMinutes': r['offset_minutes'] == null
          ? null
          : _n(r, 'offset_minutes'),
    }, target);
  }

  Future<Map<String, dynamic>?> _projectBarrier(
    CryptoCaptureKeyDescriptor capture,
    Map record,
  ) async {
    final queue = List<Map>.from(
      (record['metadata']['referenceVersions'] as List).map(
        (v) => Map.from(v as Map),
      ),
    );
    final seen = <String>{};
    Map<String, dynamic>? found;
    while (queue.isNotEmpty) {
      final r = queue.removeAt(0);
      if (r['scopeId'] != record['scopeId'] || !seen.add(r['id'])) continue;
      if (seen.length > 100) {
        throw const FormatException('crypto_reference_graph_limit');
      }
      final target = await prepareCryptoMigrationTarget(
        context: runtime,
        migrationId: capture.migrationId,
        scopeId: r['scopeId'],
        domain: r['domain'],
        wireId: r['id'],
        expectedProofHash: r['recordProofHash'],
      );
      if (target.record['expectedRevision'] + 1 != r['revision']) {
        throw const FormatException('crypto_notification_migration_reference');
      }
      final m = target.record['metadata'] as Map;
      if (target.record['type'] == 'project') {
        final state = m['projectState'];
        if (found != null ||
            target.record['deleted'] != false ||
            state is! Map ||
            state['archived'] != false ||
            !isCryptoCanonicalUuid(state['consentGeneration'])) {
          throw const FormatException('crypto_notification_migration_project');
        }
        found = {
          'id': r['id'],
          'consentGeneration': state['consentGeneration'],
        };
      }
      queue.addAll(
        (m['referenceVersions'] as List).map((v) => Map.from(v as Map)),
      );
    }
    return found;
  }
}

class _NotificationCanonical {
  _NotificationCanonical(this.canonical, [this.target]);
  final Map<String, dynamic> canonical;
  final CryptoPreparedMigrationTarget? target;
}
