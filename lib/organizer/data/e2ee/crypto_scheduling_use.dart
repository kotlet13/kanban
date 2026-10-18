import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_migration_notification_read.dart';
import 'crypto_project_relocation_notification_read.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// Explicit consent to disclose this target's future deadline changes. Delivery
/// completion is separate: it never creates another notification or withdraws
/// consent. An entirely unseen withheld cancellation has the directory's same
/// latest-prefix limitation; known cancellation and revocation floors prevail.
class CryptoSchedulingUse {
  CryptoSchedulingUse(this.context);
  final CryptoBusinessSession context;
  static const domain = 'JivieE2EE/schedulingUse/v2\n';
  static const fields = {
    'version',
    'operation',
    'serverId',
    'scopeId',
    'targetId',
    'targetType',
    'domain',
    'useId',
    'sourceScheduleRevision',
    'schedulePutId',
    'consentGeneration',
    'scopeLifecycleHash',
    'projectBarrier',
    'expiresAtEpoch',
    'mode',
    'membershipHeadHash',
    'accessRevision',
    'targetRevision',
    'targetRecordProofHash',
    'accountId',
    'deviceId',
    'authorDirectoryHeadHash',
  };

  Map<String, dynamic> body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );

  Future<String> token(Map b) => cryptoSha256([
    ...utf8.encode('JivieScheduleUse/v2\n'),
    ...CryptoJson.encode({
      for (final key in const [
        'serverId',
        'accountId',
        'scopeId',
        'targetId',
        'useId',
      ])
        key: b[key],
    }),
  ]);

  Future<Map<String, dynamic>> recordBody(
    String scope,
    String type,
    String wire,
  ) async {
    final kind = cryptoRecordDomain(type);
    final row = await context.wireRecord(scope, kind, wire);
    if (row == null || row['deleted'] == 1 || row['type'] != type) {
      throw const CryptoAuthorityPending('scheduling_target_pending');
    }
    final observed = await context.database.rows(
      'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND verdict=?',
      [
        context.partition,
        scope,
        kind,
        wire,
        row['crypto_revision'],
        'verified',
      ],
    );
    if (observed.length != 1) {
      throw const CryptoAuthorityPending('scheduling_target_pending');
    }
    final raw = jsonDecode(observed.single['wire'] as String) as Map;
    return body(raw['authorization']['recordProof'] as Map);
  }

  Future<Map<String, dynamic>?> projectBarrier(
    String scope,
    Map metadata,
  ) async {
    final pending = (metadata['references'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final seen = <String>{};
    Map<String, dynamic>? found;
    while (pending.isNotEmpty) {
      final ref = pending.removeAt(0);
      if (ref['scopeId'] != scope || !seen.add(ref['id'])) continue;
      if (seen.length > 100) {
        throw const FormatException('scheduling_reference_limit');
      }
      Map<String, Object?>? row;
      for (final kind in const ['content', 'finance']) {
        row = await context.wireRecord(scope, kind, ref['id']);
        if (row != null) break;
      }
      if (row == null) {
        throw const CryptoAuthorityPending('scheduling_project_pending');
      }
      final r = await recordBody(scope, row['type'] as String, ref['id']);
      final m = r['metadata'] as Map;
      if (r['type'] == 'project') {
        final state = m['projectState'];
        if (state is! Map ||
            state['archived'] != false ||
            !isCryptoCanonicalUuid(state['consentGeneration']) ||
            found != null) {
          throw const CryptoAuthorityPending(
            'scheduling_project_consent_pending',
          );
        }
        found = {
          'id': ref['id'],
          'consentGeneration': state['consentGeneration'],
        };
      }
      pending.addAll(
        (m['references'] as List).map(
          (v) => Map<String, dynamic>.from(v as Map),
        ),
      );
    }
    return found;
  }

  bool same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

  Future<Map<String, dynamic>> verify(
    Map raw,
    String scope,
    String type,
    String wire,
    Map metadata,
  ) async {
    if (raw.length != 3 ||
        !raw.keys.toSet().containsAll({
          'authorization',
          'directoryHeadHash',
          'eventCommandHash',
        })) {
      throw const FormatException('scheduling_use_shape');
    }
    final proof = Map<String, dynamic>.from(raw['authorization'] as Map),
        b = body(raw['authorization']);
    final relocated = b['scopeId'] != scope || b['targetId'] != wire;
    final routed = relocated
        ? await CryptoProjectRelocationNotificationRead(
            context,
          ).verify(scopeId: scope, targetId: wire, useProof: proof)
        : null;
    final migration = b['version'] == 3;
    final acceptedFields = {
      ...fields,
      if (migration) ...{
        'migrationId',
        'captureId',
        'sourceInventoryRoot',
        'bindingId',
        'originalState',
      },
    };
    if (b.length != acceptedFields.length ||
        b.keys.any((k) => !acceptedFields.contains(k)) ||
        (!migration && b['version'] != 2) ||
        b['operation'] !=
            (migration
                ? 'crypto2.migration.schedulingUse'
                : 'crypto2.scheduling.use') ||
        b['serverId'] != context.account.directory.session.profile.serverId ||
        (!relocated && (b['scopeId'] != scope || b['targetId'] != wire)) ||
        b['targetType'] != type ||
        b['domain'] != cryptoRecordDomain(type) ||
        b['mode'] != 'relative') {
      throw const FormatException('scheduling_use_binding');
    }
    final head = await context.access.currentHead(scope, online: true);
    final members = head.members.where((m) => m['accountId'] == b['accountId']);
    if (members.length != 1) {
      throw const CryptoAuthorityPending('scheduling_use_permission_revoked');
    }
    final member = members.single;
    if (b['domain'] == 'finance' && member['financeRole'] == 'none') {
      throw const CryptoAuthorityPending('scheduling_use_permission_revoked');
    }
    final current = await context.access.currentMemberDirectory(
      scope,
      head.headHash,
      b['accountId'],
    );
    final migrated = migration && !relocated
        ? await CryptoMigrationNotificationRead(
            context,
          ).verify(scopeId: scope, targetId: wire, proof: proof)
        : null;
    final referenced = await context.access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head.headHash,
      accountId: b['accountId'],
      directoryHeadHash: b['authorDirectoryHeadHash'],
      online: true,
    );
    if (!migration &&
        !relocated &&
        referenced.deviceSnapshotHash != current.deviceSnapshotHash) {
      throw const CryptoAuthorityPending('scheduling_use_device_changed');
    }
    context.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(
        (migration || relocated ? referenced : current).activeDevice(
          b['deviceId'],
        )['signingKeyBase64'],
        length: 32,
      ),
      migration ? 'JivieE2EE/migrationSchedulingUse/v3\n' : domain,
    );
    if (!relocated) {
      final source = await context.access.headAt(
        scope,
        b['membershipHeadHash'],
      );
      final prior = source.member(b['accountId']);
      if (source.accessRevision != b['accessRevision'] ||
          b['domain'] == 'finance' && prior['financeRole'] == 'none') {
        throw const FormatException('scheduling_use_source_authority');
      }
    }
    final useToken = await token(b),
        proofHash = await cryptoSha256(CryptoJson.encode(proof));
    Map<String, dynamic>? latest;
    await for (final entry in context.account.store.verifiedOperationEntries(
      current,
      'crypto2.account.scheduleUse',
    )) {
      if (!current.includesAnchor(entry['generation'], entry['headHash'])) {
        throw const FormatException('scheduling_use_event_fork');
      }
      final event = body(entry['authorization']);
      if (event['payload']['useToken'] == useToken) {
        latest = entry;
        break;
      }
    }
    if (latest == null) {
      final baselineHash =
          migrated?.control.controlLeaf['eventCommandHash'] ??
          routed?.route['originalUseEventCommandHash'];
      var included = false;
      if (migration && baselineHash == raw['eventCommandHash']) {
        await for (final entry
            in context.account.store.verifiedOperationEntries(
              current,
              'crypto2.account.migrationAttest',
            )) {
          if (entry['commandHash'] == baselineHash &&
              current.includesAnchor(entry['generation'], entry['headHash'])) {
            included = true;
            break;
          }
        }
      }
      if (!included) {
        throw const CryptoAuthorityPending(
          'scheduling_use_latest_event_pending',
        );
      }
    } else {
      final eventPayload = body(latest['authorization'])['payload'] as Map;
      if (latest['commandHash'] != raw['eventCommandHash']) {
        throw const CryptoAuthorityPending(
          'scheduling_use_latest_event_pending',
        );
      }
      if (eventPayload['useProofHash'] != proofHash ||
          eventPayload['active'] != true) {
        throw const CryptoAuthorityPending('scheduling_use_cancelled');
      }
    }
    Map<String, dynamic>? relocatedProject;
    if (routed != null) {
      final initial = routed.target['metadata'] as Map;
      if ((initial['reminderState'] as Map?)?['consentGeneration'] !=
          b['consentGeneration']) {
        throw const FormatException('scheduling_relocation_consent');
      }
      relocatedProject = await projectBarrier(scope, initial);
      if ((b['projectBarrier'] == null) != (relocatedProject == null) ||
          b['projectBarrier'] != null &&
              b['projectBarrier']['consentGeneration'] !=
                  relocatedProject!['consentGeneration']) {
        throw const FormatException('scheduling_relocation_project');
      }
    }
    final state = metadata['reminderState'];
    if (state is! Map ||
        state['closed'] != false ||
        state['consentGeneration'] != b['consentGeneration'] ||
        await context.access.verifiedLifecycleHash(scope) !=
            (routed?.publication['lifecycleHash'] ?? b['scopeLifecycleHash']) ||
        !same(
          await projectBarrier(scope, metadata),
          routed == null ? b['projectBarrier'] : relocatedProject,
        ) ||
        b['expiresAtEpoch'] != null &&
            (b['expiresAtEpoch'] is! int ||
                b['expiresAtEpoch'] <=
                    DateTime.now().millisecondsSinceEpoch ~/ 1000)) {
      throw const CryptoAuthorityPending('scheduling_use_barrier_changed');
    }
    return {
      'authorization': proof,
      'directoryHeadHash': current.headHash,
      'eventCommandHash': latest?['commandHash'] ?? raw['eventCommandHash'],
    };
  }

  /// No server boolean or unsigned empty list can create date permission.
  Future<Map<String, dynamic>?> forTarget(
    String scope,
    String type,
    String wire,
    Map metadata,
  ) async {
    String? after;
    while (true) {
      final page = await context.account.directory
          .call('crypto2.scheduling.uses', {
            'scopeId': scope,
            'targetId': wire,
            'domain': cryptoRecordDomain(type),
            if (after != null) 'afterToken': after,
          });
      for (final value in page['uses'] as List) {
        try {
          return await verify(
            Map<String, dynamic>.from(value as Map),
            scope,
            type,
            wire,
            metadata,
          );
        } on CryptoAuthorityPending catch (error) {
          if (!const {
            'scheduling_use_cancelled',
            'scheduling_use_barrier_changed',
            'scheduling_use_permission_revoked',
            'scheduling_use_device_changed',
          }.contains(error.reason)) {
            rethrow;
          }
        } on CryptoDirectoryException catch (error) {
          if (error.code != 'directory_device_revoked') rethrow;
        }
      }
      if (page['hasMore'] != true) return null;
      final next = page['nextAfterToken'];
      if (next is! String || after != null && next.compareTo(after) <= 0) {
        throw const FormatException('scheduling_use_cursor');
      }
      after = next;
    }
  }

  Future<Map<String, dynamic>?> own(
    String reminderId, {
    bool withdrawalOnly = false,
  }) async {
    final reply = await context.account.directory.call(
      'crypto2.scheduling.own',
      {'reminderId': reminderId},
    );
    final raw = reply['use'];
    if (raw == null) return null;
    final value = Map<String, dynamic>.from(raw as Map);
    final proof = Map<String, dynamic>.from(value['authorization'] as Map),
        b = body(proof);
    final own = await context.account.directory.requireFresh();
    if (b['accountId'] != own.accountId || b['schedulePutId'] != reminderId) {
      throw const FormatException('scheduling_own_substitution');
    }
    final routed =
        !withdrawalOnly &&
            value['scopeId'] != null &&
            (value['scopeId'] != b['scopeId'] ||
                value['targetId'] != b['targetId'])
        ? await CryptoProjectRelocationNotificationRead(context).verify(
            scopeId: value['scopeId'],
            targetId: value['targetId'],
            reminderId: reminderId,
            useProof: proof,
          )
        : null;
    final t = await token(b), h = await cryptoSha256(CryptoJson.encode(proof));
    Map<String, dynamic>? latest;
    await for (final entry in context.account.store.verifiedOperationEntries(
      own,
      'crypto2.account.scheduleUse',
    )) {
      if (!own.includesAnchor(entry['generation'], entry['headHash'])) {
        throw const FormatException('scheduling_own_fork');
      }
      final e = body(entry['authorization']);
      if (e['payload']['useToken'] == t) {
        latest = entry;
        break;
      }
    }
    if (latest == null && b['version'] == 3 && withdrawalOnly) {
      final eventHash = await CryptoMigrationNotificationRead(
        context,
      ).verifyOwnWithdrawal(proof, reminderId);
      if (eventHash != value['eventCommandHash']) {
        throw const CryptoAuthorityPending('scheduling_own_event_pending');
      }
      return {...value, 'active': true};
    }
    if (latest == null && b['version'] == 3) {
      final baseline = routed == null
          ? await CryptoMigrationNotificationRead(context).verify(
              scopeId: b['scopeId'],
              targetId: b['targetId'],
              proof: proof,
            )
          : null;
      if ((baseline?.control.controlLeaf['eventCommandHash'] ??
              routed?.route['originalUseEventCommandHash']) !=
          value['eventCommandHash']) {
        throw const CryptoAuthorityPending('scheduling_own_event_pending');
      }
      return {
        ...value,
        if (routed != null) ...{
          'effectiveScopeId': value['scopeId'],
          'effectiveTargetId': value['targetId'],
        },
        'active':
            b['expiresAtEpoch'] == null ||
            b['expiresAtEpoch'] > DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };
    }
    if (latest == null ||
        latest['commandHash'] != value['eventCommandHash'] ||
        body(latest['authorization'])['payload']['useProofHash'] != h) {
      throw const CryptoAuthorityPending('scheduling_own_event_pending');
    }
    return {
      ...value,
      if (routed != null) ...{
        'effectiveScopeId': value['scopeId'],
        'effectiveTargetId': value['targetId'],
      },
      'active': body(latest['authorization'])['payload']['active'],
    };
  }

  Future<Map<String, dynamic>> relative({
    required String scope,
    required String type,
    required String wire,
    required String reminderId,
    required String requestId,
    required int due,
  }) async {
    final r = await recordBody(scope, type, wire),
        metadata = r['metadata'] as Map;
    final state = metadata['reminderState'];
    if (state is! Map ||
        state['closed'] != false ||
        !isCryptoCanonicalUuid(state['consentGeneration'])) {
      throw const CryptoAuthorityPending(
        'scheduling_consent_generation_pending',
      );
    }
    final old = await own(reminderId);
    final previous = old == null ? null : body(old['authorization']);
    if (previous != null &&
        ((old?['effectiveScopeId'] ?? previous['scopeId']) != scope ||
            (old?['effectiveTargetId'] ?? previous['targetId']) != wire ||
            previous['targetType'] != type)) {
      throw const FormatException('scheduling_target_immutable');
    }
    if (old?['active'] == true &&
        previous != null &&
        (previous['version'] == 3 || old?['effectiveScopeId'] != null)) {
      await verify(
        {
          for (final key in const [
            'authorization',
            'directoryHeadHash',
            'eventCommandHash',
          ])
            key: old![key],
        },
        scope,
        type,
        wire,
        metadata,
      );
      final existing = await context.wireRecord(
        scope,
        cryptoRecordDomain(type),
        wire,
      );
      return {
        'useProof': old!['authorization'],
        'targetDueAtEpoch': due,
        'targetRevision': existing!['crypto_revision'],
        'targetRecordProofHash': existing['record_proof_hash'],
      };
    }
    final head = await context.access.currentHead(scope, online: true);
    final directory = await context.account.directory.requireFresh();
    final row = await context.wireRecord(scope, cryptoRecordDomain(type), wire);
    final crypto = context.account.directory.reducer.crypto;
    final b = <String, dynamic>{
      'version': 2,
      'operation': 'crypto2.scheduling.use',
      'serverId': directory.serverId,
      'scopeId': scope,
      'targetId': wire,
      'targetType': type,
      'domain': cryptoRecordDomain(type),
      'useId': previous?['useId'] ?? crypto.randomId(),
      'sourceScheduleRevision': state['scheduleRevision'],
      'schedulePutId': reminderId,
      'consentGeneration': state['consentGeneration'],
      'scopeLifecycleHash': await context.access.verifiedLifecycleHash(scope),
      'projectBarrier': await projectBarrier(scope, metadata),
      'expiresAtEpoch': null,
      'mode': 'relative',
      'membershipHeadHash': head.headHash,
      'accessRevision': head.accessRevision,
      'targetRevision': row!['crypto_revision'],
      'targetRecordProofHash': row['record_proof_hash'],
      'accountId': directory.accountId,
      'deviceId': context.account.deviceId,
      'authorDirectoryHeadHash': directory.headHash,
    };
    final lease = await context.account.signingKey();
    late Map<String, dynamic> proof;
    try {
      proof = crypto.signDomain(b, lease.key, domain);
    } finally {
      lease.release();
    }
    final event = await context.account.prepareScheduleUseEvent(
      requestId: requestId,
      useToken: await token(b),
      useProofHash: await cryptoSha256(CryptoJson.encode(proof)),
      active: true,
    );
    return {
      'useProof': proof,
      'accountEventProof': event.authorization,
      'targetDueAtEpoch': due,
      'targetRevision': row['crypto_revision'],
      'targetRecordProofHash': row['record_proof_hash'],
    };
  }

  Future<Map<String, dynamic>> withdrawal(
    String reminderId,
    String requestId,
  ) async {
    final old = await own(reminderId, withdrawalOnly: true);
    if (old == null || old['active'] != true) return {};
    final proof = Map<String, dynamic>.from(old['authorization'] as Map),
        b = body(proof);
    final event = await context.account.prepareScheduleUseEvent(
      requestId: requestId,
      useToken: await token(b),
      useProofHash: await cryptoSha256(CryptoJson.encode(proof)),
      active: false,
    );
    return {'accountEventProof': event.authorization};
  }

  Future<void> accepted(Map payload) async {
    final proof = payload['accountEventProof'];
    if (proof is! Map) return;
    final hash = await cryptoSha256(cryptoBase64(proof['commandBase64']));
    final state = await context.account.directory.requireFresh();
    final entry = await context.account.store.entryByHash(
      state.accountId,
      hash,
    );
    if (entry == null ||
        !state.includesAnchor(entry['generation'], entry['headHash'])) {
      throw const CryptoAuthorityPending(
        'scheduling_companion_receipt_pending',
      );
    }
    context.access.invalidateAuthorityOperation();
  }
}
