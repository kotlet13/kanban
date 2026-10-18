import 'dart:convert';

import '../../domain/collaboration_models.dart';
import '../../domain/notification_models.dart';
import '../../domain/shared_payload_validation.dart';
import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_migration_notification_read.dart';
import 'crypto_project_relocation_notification_read.dart';
import 'crypto_record_address.dart';
import 'crypto_scheduling_use.dart';
import 'crypto_sync_repository.dart';

/// Existing inbox and reminder actions keep their durable UI queue. Their
/// metadata commands have separate immutable signed transport receipts; opening
/// a notification resolves content only through verified encrypted records.
class CryptoBusinessNotifications {
  CryptoBusinessNotifications(this.context);
  final CryptoBusinessSession context;
  static const operations = {
    'inbox.list',
    'inbox.sync',
    'inbox.open',
    'inbox.group',
    'inbox.read',
    'inbox.preferences.get',
    'inbox.preferences.set',
    'reminders.list',
    'reminders.put',
    'reminders.cancel',
  };
  bool supports(String operation) => operations.contains(operation);

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    if (!supports(operation)) {
      throw const FormatException('crypto_notification_operation');
    }
    final payload = Map<String, dynamic>.from(params)
      ..remove('requestId')
      ..remove('recordContractVersion')
      ..remove('financeContractVersion');
    final write = const {
      'inbox.read',
      'inbox.preferences.set',
      'reminders.put',
      'reminders.cancel',
    }.contains(operation);
    final use = CryptoSchedulingUse(context);
    String? resumedRequest;
    if (write) {
      final requestId = params['requestId'];
      if (!isCryptoCanonicalUuid(requestId)) {
        throw const FormatException('crypto_notification_request_id');
      }
      final old = await context.database.rows(
        'SELECT request_id FROM crypto_command_keys WHERE partition=? AND action_key=?',
        [context.partition, 'notification:$operation:$requestId'],
      );
      if (old.length == 1) {
        resumedRequest = old.single['request_id'] as String;
        final outgoing = await context.queue.store.outgoing(resumedRequest);
        if (outgoing == null) {
          throw const CryptoAuthorityPending('notification_journal_pending');
        }
        final signed = jsonDecode(outgoing['signed_body'] as String) as Map;
        final command = use.body(signed),
            original = Map<String, dynamic>.from(command['payload'] as Map);
        final comparable = Map<String, dynamic>.from(original)
          ..removeWhere(
            (key, _) => const {
              'targetIdentity',
              'useProof',
              'accountEventProof',
              'targetDueAtEpoch',
              'targetRevision',
              'targetRecordProofHash',
            }.contains(key),
          );
        final wanted = Map<String, dynamic>.from(payload);
        if (operation == 'reminders.put') {
          wanted['targetId'] = _address(
            wanted['scopeId'],
            wanted['targetType'],
            wanted['targetId'],
          ).wireId;
        }
        if (command['operation'] != 'crypto2.$operation' ||
            !use.same(comparable, wanted)) {
          throw const FormatException('crypto_immutable_notification_intent');
        }
        payload
          ..clear()
          ..addAll(original);
      }
    }
    if (operation == 'reminders.put' && resumedRequest == null) {
      await _target(
        payload['scopeId'],
        payload['targetType'],
        payload['targetId'],
      );
      final address = _address(
        payload['scopeId'],
        payload['targetType'],
        payload['targetId'],
      );
      payload['targetId'] = address.wireId;
      payload['targetIdentity'] = address.identity;
      if ((payload['scheduleMode'] ?? 'absolute') == 'deadline') {
        final row = await context.wireRecord(
          payload['scopeId'],
          cryptoRecordDomain(payload['targetType']),
          address.wireId,
        );
        final raw = row == null
            ? null
            : jsonDecode(row['raw_payload'] as String) as Map;
        final date = raw?['dueAt'];
        if (date is! String) {
          throw const CryptoAuthorityPending(
            'scheduling_decrypted_due_pending',
          );
        }
        final due = DateTime.parse(date).millisecondsSinceEpoch ~/ 1000;
        if (DateTime.parse(payload['remindAt']).millisecondsSinceEpoch ~/
                1000 !=
            due - (payload['offsetMinutes'] as int) * 60) {
          throw const FormatException('scheduling_original_due_mismatch');
        }
        payload.addAll(
          await use.relative(
            scope: payload['scopeId'],
            type: payload['targetType'],
            wire: address.wireId,
            reminderId: payload['id'],
            requestId: params['requestId'] as String,
            due: due,
          ),
        );
      } else {
        payload.addAll(
          await use.withdrawal(payload['id'], params['requestId'] as String),
        );
      }
    } else if (operation == 'reminders.cancel' && resumedRequest == null) {
      payload.addAll(
        await use.withdrawal(payload['id'], params['requestId'] as String),
      );
    }
    final Map<String, dynamic> reply;
    if (write) {
      final requestId = params['requestId'];
      if (!isSharedUuid(requestId)) {
        throw const FormatException('crypto_notification_request_id');
      }
      final id =
          resumedRequest ??
          await context.queue.enqueueCommand(
            actionKey: 'notification:$operation:$requestId',
            operation: 'crypto2.$operation',
            payload: payload,
            requestId: requestId as String,
          );
      await context.queue.resumeUnresolved(requestIds: {id});
      reply = await context.queue.commandResult(id);
      await use.accepted(payload);
    } else {
      reply = await context.account.directory.call(
        'crypto2.$operation',
        payload,
      );
    }
    if (operation == 'inbox.open') return _open(reply);
    if (reply['items'] is List) {
      return {
        ...reply,
        'items': [for (final value in reply['items'] as List) _inbox(value)],
      };
    }
    if (reply['item'] != null) return {'item': _inbox(reply['item'])};
    if (reply['reminder'] != null) {
      return {
        'reminder': await _reminder(reply['reminder'], historicalAck: write),
      };
    }
    if (reply['reminders'] is List) {
      return {
        ...reply,
        'reminders': [
          for (final value in reply['reminders'] as List)
            await _reminder(value),
        ],
      };
    }
    if (operation.startsWith('inbox.preferences.')) {
      final raw = reply['preferences'];
      if (raw is! Map ||
          raw.keys.any((k) => !sharedNotificationCategories.contains(k))) {
        throw const FormatException('crypto_notification_preferences');
      }
      return {
        'preferences': {
          for (final key in raw.keys)
            key: SharedNotificationSettings.fromJson(
              Map<String, dynamic>.from(raw[key] as Map),
            ).toJson(),
        },
      };
    }
    throw const FormatException('crypto_notification_response');
  }

  Map<String, dynamic> _inbox(Object? raw) {
    final wire = Map<String, dynamic>.from(raw as Map);
    final identity = _routingIdentity(wire);
    final entry = SharedInboxEntry.fromJson({
      ...wire,
      'targetId': identity['canonicalId'],
    });
    if (entry.id < 1 ||
        entry.revision < 1 ||
        entry.sequence < 1 ||
        !isSharedUuid(entry.scopeId) ||
        !isSharedUuid(entry.targetId) ||
        !sharedNotificationCategories.contains(entry.category) ||
        entry.targetRevision < 0) {
      throw const FormatException('crypto_notification_identity');
    }
    // A generic server delivery row is routing state, never decrypted content.
    return {
      ...Map<String, dynamic>.from(entry.toJson()),
      if (wire['targetIdentity'] == null) 'routingPending': true,
    };
  }

  Future<Map<String, dynamic>?> _target(
    Object? scope,
    Object? type,
    Object? id,
  ) async {
    if (!isSharedUuid(scope) || !isSharedUuid(id) || type is! String) {
      throw const FormatException('crypto_notification_target');
    }
    final domain = cryptoRecordDomain(type);
    await context.pullVerified(scope as String, domain);
    final row = await context.record(scope, domain, id as String, type: type);
    if (row == null) return null;
    if (row['type'] != type) {
      throw const FormatException('crypto_notification_target_type');
    }
    return Map<String, dynamic>.from(
      jsonDecode(row['projection'] as String) as Map,
    );
  }

  CryptoRecordAddress _address(
    Object? scope,
    Object? type,
    Object? canonicalId,
  ) {
    if (scope is! String || type is! String || canonicalId is! String) {
      throw const FormatException('crypto_notification_identity');
    }
    return CryptoRecordAddress.forType(
      serverId: context.account.directory.session.profile.serverId,
      scopeId: scope,
      type: type,
      canonicalId: canonicalId,
    );
  }

  Map<String, dynamic> _routingIdentity(Map wire) {
    final raw = wire['targetIdentity'];
    if (raw == null) {
      // Retain an unavailable generic delivery row. Its opaque wire ID is not
      // promoted to a canonical content address and _open never materializes it.
      if (!isCryptoWireRecordId(wire['targetId'])) {
        throw const FormatException('crypto_notification_identity');
      }
      return {'sourceKind': 'unavailable', 'canonicalId': wire['targetId']};
    }
    if (raw is! Map || raw.length != 2) {
      throw const CryptoAuthorityPending('notification_identity_pending');
    }
    final identity = Map<String, dynamic>.from(raw);
    if (wire['targetType'] == 'membership') {
      if (identity['sourceKind'] != 'membership' ||
          !isCryptoCanonicalUuid(identity['canonicalId']) ||
          wire['targetId'] != identity['canonicalId']) {
        throw const FormatException(
          'crypto_notification_identity_substitution',
        );
      }
      return identity;
    }
    final address = _address(
      wire['scopeId'],
      wire['targetType'],
      identity['canonicalId'],
    );
    if (identity['sourceKind'] != address.sourceKind ||
        address.wireId != wire['targetId']) {
      throw const FormatException('crypto_notification_identity_substitution');
    }
    return identity;
  }

  Future<Map<String, dynamic>> _open(Map<String, dynamic> reply) async {
    final rawItem = Map<String, dynamic>.from(reply['item'] as Map);
    final item = _inbox(rawItem);
    final target = Map<String, dynamic>.from(reply['target'] as Map);
    if (target.length != 3 ||
        target['scopeId'] != item['scopeId'] ||
        target['id'] != rawItem['targetId'] ||
        target['type'] != item['targetType']) {
      throw const FormatException('crypto_notification_target_substitution');
    }
    final record =
        target['type'] == 'membership' || rawItem['targetIdentity'] == null
        ? null
        : await _target(target['scopeId'], target['type'], item['targetId']);
    Map<String, dynamic>? parent;
    if (record != null &&
        record['deleted'] != true &&
        target['type'] == 'shoppingItem') {
      final payload = record['payload'] as Map;
      parent = await _target(
        target['scopeId'],
        'shoppingList',
        payload['listId'],
      );
    }
    return {
      'item': item,
      'target': {...target, 'id': item['targetId']},
      'record': record,
      'contextRecord': parent,
    };
  }

  Future<bool> _knownActiveOwnProof(
    Map<String, dynamic> proof,
    Map command,
    Map device,
  ) async {
    if (device['revokedGeneration'] == null) return true;
    final anchors = await context.database.rows(
      "SELECT signed_body FROM crypto_outbox WHERE partition=? AND request_id=? AND operation=? AND state='applied'",
      [context.partition, command['requestId'], command['operation']],
    );
    // Restored raw evidence remains in quarantine and never populates this
    // active journal. Applied entries have verified exact mutation receipts.
    return anchors.length == 1 &&
        anchors.single['signed_body'] == utf8.decode(CryptoJson.encode(proof));
  }

  Future<Map<String, dynamic>> _cancelledAck(
    Map<String, dynamic> wire,
    Map<String, dynamic> proof,
    Map<String, dynamic> putProof,
  ) async {
    final own = await context.account.directory.cachedVerifiedDirectory();
    final command = CryptoSchedulingUse(context).body(proof),
        p = command['payload'];
    final device = own.devices.where(
      (d) => d['deviceId'] == command['deviceId'],
    );
    final rows = await context.database.rows(
      "SELECT signed_body FROM crypto_outbox WHERE partition=? AND request_id=? AND operation='crypto2.reminders.cancel' AND state='applied'",
      [context.partition, command['requestId']],
    );
    if (device.length != 1 ||
        rows.length != 1 ||
        rows.single['signed_body'] != utf8.decode(CryptoJson.encode(proof)) ||
        command['version'] != 2 ||
        command['serverId'] != own.serverId ||
        command['accountId'] != own.accountId ||
        command['signer'] != 'device' ||
        p is! Map ||
        p['scopeId'] != wire['scopeId'] ||
        p['id'] != wire['id'] ||
        p['expectedRevision'] is! int ||
        wire['revision'] != p['expectedRevision'] + 1 ||
        wire['state'] != 'cancelled') {
      throw const FormatException('crypto_reminder_cancel_receipt');
    }
    context.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device.single['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    final put = CryptoSchedulingUse(context).body(putProof),
        d = own.devices.where((d) => d['deviceId'] == put['deviceId']);
    final migrated =
        put['operation'] == 'crypto2.migration.notificationTransform';
    final original = migrated ? put['canonical'] : put['payload'];
    if (d.length != 1 ||
        put['accountId'] != own.accountId ||
        put['serverId'] != own.serverId ||
        original is! Map ||
        original['id'] != wire['id'] ||
        (!migrated && put['operation'] != 'crypto2.reminders.put')) {
      throw const FormatException('crypto_reminder_cancel_routing');
    }
    context.account.directory.reducer.crypto.verifyDomain(
      putProof,
      cryptoBase64(d.single['signingKeyBase64'], length: 32),
      migrated ? 'JivieE2EE/notificationTransform/v3\n' : cryptoDirectoryDomain,
    );
    final canonical = migrated
        ? original['canonicalTargetId']
        : (original['targetIdentity'] as Map)['canonicalId'];
    // Minimal own outcome only. No target read, scheduler activation or scope
    // floor is derived from these retained routing coordinates.
    return Map<String, dynamic>.from(
      SharedScheduledReminder.fromJson({
        ...wire,
        'targetId': canonical,
        'remindAt': original['remindAt'],
        'state': 'cancelled',
      }).toJson(),
    );
  }

  Future<Map<String, dynamic>> _relocatedReminder(
    Map<String, dynamic> wire,
    Map<String, dynamic> proof,
    Map<String, dynamic> putProof,
    bool historicalAck,
  ) async {
    final routed = await CryptoProjectRelocationNotificationRead(context)
        .verify(
          scopeId: wire['scopeId'],
          targetId: wire['targetId'],
          reminderId: wire['id'],
        );
    final use = CryptoSchedulingUse(context);
    if (routed.put == null || !use.same(routed.put, putProof)) {
      throw const FormatException('crypto_relocation_reminder_put');
    }
    final put = use.body(putProof),
        own = await context.account.directory.cachedVerifiedDirectory();
    final migrated =
        put['operation'] == 'crypto2.migration.notificationTransform';
    final original = Map<String, dynamic>.from(
      (migrated ? put['canonical'] : put['payload']) as Map,
    );
    final devices = own.devices.where((d) => d['deviceId'] == put['deviceId']);
    if (devices.length != 1 ||
        put['accountId'] != own.accountId ||
        put['serverId'] != own.serverId ||
        (!migrated &&
            (put['version'] != 2 ||
                put['signer'] != 'device' ||
                put['operation'] != 'crypto2.reminders.put')) ||
        migrated && (put['version'] != 3 || put['kind'] != 'reminder') ||
        original['id'] != wire['id'] ||
        original['targetType'] != wire['targetType'] ||
        original['scopeId'] == wire['scopeId']) {
      throw const FormatException('crypto_relocation_reminder_original');
    }
    context.account.directory.reducer.crypto.verifyDomain(
      putProof,
      cryptoBase64(devices.single['signingKeyBase64'], length: 32),
      migrated ? 'JivieE2EE/notificationTransform/v3\n' : cryptoDirectoryDomain,
    );
    final identity = Map<String, dynamic>.from(
      (routed.target['metadata'] as Map)['identity'] as Map,
    );
    final canonical = migrated
        ? original['canonicalTargetId']
        : (original['targetIdentity'] as Map?)?['canonicalId'];
    if (identity['canonicalId'] != canonical ||
        !_sameIdentity(wire['targetIdentity'], identity) ||
        wire['revision'] is! int ||
        !const {'pending', 'cancelled', 'delivered'}.contains(wire['state']) ||
        wire['scheduleMode'] != (original['scheduleMode'] ?? 'absolute') ||
        wire['offsetMinutes'] != original['offsetMinutes']) {
      throw const FormatException('crypto_relocation_reminder_identity');
    }
    final command = use.body(proof);
    if (!use.same(proof, putProof)) {
      final d = own.devices.where((d) => d['deviceId'] == command['deviceId']);
      final p = command['payload'];
      if (d.length != 1 ||
          command['operation'] != 'crypto2.reminders.cancel' ||
          command['version'] != 2 ||
          command['accountId'] != own.accountId ||
          command['serverId'] != own.serverId ||
          command['signer'] != 'device' ||
          p is! Map ||
          p['scopeId'] != wire['scopeId'] ||
          p['id'] != wire['id'] ||
          p['expectedRevision'] is! int ||
          wire['revision'] < p['expectedRevision'] + 1 ||
          wire['state'] != 'cancelled') {
        throw const FormatException('crypto_relocation_reminder_cancel');
      }
      context.account.directory.reducer.crypto.verifyDomain(
        proof,
        cryptoBase64(d.single['signingKeyBase64'], length: 32),
        cryptoDirectoryDomain,
      );
      if (!await _knownActiveOwnProof(proof, command, d.single)) {
        throw const CryptoAuthorityPending(
          'crypto_reminder_consent_review_required',
        );
      }
    }
    if (wire['state'] == 'pending' && !historicalAck) {
      final domain = routed.target['domain'];
      await context.pullVerified(wire['scopeId'], domain);
      final row = await context.wireRecord(
        wire['scopeId'],
        domain,
        wire['targetId'],
      );
      final record = await use.recordBody(
        wire['scopeId'],
        wire['targetType'],
        wire['targetId'],
      );
      final metadata = record['metadata'] as Map,
          state = metadata['reminderState'];
      if (row == null ||
          row['deleted'] == 1 ||
          row['crypto_revision'] != wire['targetRevision'] ||
          state is! Map ||
          state['closed'] != false ||
          state['scheduleRevision'] != wire['scheduleRevision']) {
        throw const CryptoAuthorityPending('reminder_target_changed');
      }
      if ((original['scheduleMode'] ?? 'absolute') == 'deadline') {
        final ownUse = await use.own(wire['id']);
        if (ownUse == null || ownUse['active'] != true) {
          throw const CryptoAuthorityPending('scheduling_use_cancelled');
        }
        await use.verify(
          {
            for (final key in const [
              'authorization',
              'directoryHeadHash',
              'eventCommandHash',
            ])
              key: ownUse[key],
          },
          wire['scopeId'],
          wire['targetType'],
          wire['targetId'],
          metadata,
        );
        final date = (jsonDecode(row['raw_payload'] as String) as Map)['dueAt'];
        if (date is! String ||
            original['offsetMinutes'] is! int ||
            DateTime.parse(wire['remindAt']).millisecondsSinceEpoch ~/ 1000 !=
                DateTime.parse(date).millisecondsSinceEpoch ~/ 1000 -
                    original['offsetMinutes'] * 60) {
          throw const FormatException(
            'crypto_reminder_relative_time_substitution',
          );
        }
      } else if (wire['remindAt'] != original['remindAt']) {
        throw const FormatException('crypto_reminder_time_substitution');
      }
    } else {
      wire['remindAt'] = original['remindAt'];
    }
    return Map<String, dynamic>.from(
      SharedScheduledReminder.fromJson({
        ...wire,
        'targetId': canonical,
      }).toJson(),
    );
  }

  bool _sameIdentity(Object? a, Object? b) =>
      CryptoSchedulingUse(context).same(a, b);

  Future<Map<String, dynamic>> _migratedReminder(
    Map<String, dynamic> wire,
    Map<String, dynamic> currentProof,
    Map<String, dynamic> transformProof,
    bool historicalAck,
  ) async {
    final verified = await CryptoMigrationNotificationRead(context).verify(
      scopeId: wire['scopeId'],
      targetId: wire['targetId'],
      proof: transformProof,
      ownTransform: true,
    );
    final c = Map<String, dynamic>.from(verified.body['canonical'] as Map);
    for (final field in const [
      'id',
      'scopeId',
      'targetId',
      'targetType',
      'scheduleMode',
      'offsetMinutes',
    ]) {
      if (wire[field] != c[field]) {
        throw const FormatException('crypto_migrated_reminder_substitution');
      }
    }
    if (wire['revision'] is! int ||
        wire['revision'] < c['revision'] ||
        !const {'pending', 'cancelled', 'delivered'}.contains(wire['state'])) {
      throw const FormatException('crypto_migrated_reminder_state');
    }
    final current = CryptoSchedulingUse(context).body(currentProof);
    if (!CryptoSchedulingUse(context).same(currentProof, transformProof)) {
      final own = await context.account.directory.cachedVerifiedDirectory();
      final device = own.devices.where(
        (d) => d['deviceId'] == current['deviceId'],
      );
      final p = current['payload'];
      if (device.length != 1 ||
          current['version'] != 2 ||
          current['operation'] != 'crypto2.reminders.cancel' ||
          current['serverId'] != own.serverId ||
          current['accountId'] != own.accountId ||
          current['signer'] != 'device' ||
          p is! Map ||
          p['id'] != c['id'] ||
          p['scopeId'] != c['scopeId'] ||
          p['expectedRevision'] is! int ||
          wire['revision'] < p['expectedRevision'] + 1 ||
          wire['state'] != 'cancelled') {
        throw const FormatException('crypto_migrated_reminder_cancel');
      }
      context.account.directory.reducer.crypto.verifyDomain(
        currentProof,
        cryptoBase64(device.single['signingKeyBase64'], length: 32),
        cryptoDirectoryDomain,
      );
      if (!await _knownActiveOwnProof(currentProof, current, device.single)) {
        throw const CryptoAuthorityPending(
          'crypto_reminder_consent_review_required',
        );
      }
    } else if (c['state'] == 'cancelled' && wire['state'] != 'cancelled') {
      throw const FormatException('crypto_migrated_reminder_resurrection');
    }
    final identity = _routingIdentity({
      ...wire,
      'targetIdentity': {
        'sourceKind': _address(
          c['scopeId'],
          c['targetType'],
          c['canonicalTargetId'],
        ).sourceKind,
        'canonicalId': c['canonicalTargetId'],
      },
    });
    if (wire['state'] == 'pending' && !historicalAck) {
      await context.pullVerified(c['scopeId'], c['domain']);
      final row = await context.wireRecord(
        c['scopeId'],
        c['domain'],
        c['targetId'],
      );
      if (row == null ||
          row['deleted'] == 1 ||
          row['type'] != c['targetType'] ||
          row['crypto_revision'] != wire['targetRevision']) {
        throw const CryptoAuthorityPending('reminder_target_pending');
      }
      final metadata = await CryptoSchedulingUse(
        context,
      ).recordBody(c['scopeId'], c['targetType'], c['targetId']);
      final state = (metadata['metadata'] as Map)['reminderState'];
      if (state is! Map ||
          state['closed'] != false ||
          state['scheduleRevision'] != wire['scheduleRevision'] ||
          state['consentGeneration'] != c['consentGeneration']) {
        throw const CryptoAuthorityPending('reminder_target_changed');
      }
      if (c['scheduleMode'] == 'deadline') {
        final use = verified.body['useAuthorization'];
        if (use is! Map) {
          throw const FormatException('crypto_migrated_reminder_use');
        }
        final ownUse = await CryptoSchedulingUse(context).own(c['id']);
        if (ownUse == null || ownUse['active'] != true) {
          throw const CryptoAuthorityPending('scheduling_use_cancelled');
        }
        await CryptoSchedulingUse(context).verify(
          {
            for (final key in const [
              'authorization',
              'directoryHeadHash',
              'eventCommandHash',
            ])
              key: ownUse[key],
          },
          c['scopeId'],
          c['targetType'],
          c['targetId'],
          metadata['metadata'],
        );
        final due = (jsonDecode(row['raw_payload'] as String) as Map)['dueAt'];
        if (due is! String ||
            c['offsetMinutes'] is! int ||
            DateTime.parse(wire['remindAt']).millisecondsSinceEpoch ~/ 1000 !=
                DateTime.parse(due).millisecondsSinceEpoch ~/ 1000 -
                    c['offsetMinutes'] * 60) {
          throw const FormatException(
            'crypto_reminder_relative_time_substitution',
          );
        }
      } else if (wire['remindAt'] != c['remindAt']) {
        throw const FormatException('crypto_reminder_time_substitution');
      }
    } else {
      wire['remindAt'] = c['remindAt'];
    }
    final value = SharedScheduledReminder.fromJson({
      ...wire,
      'targetId': identity['canonicalId'],
    });
    return Map<String, dynamic>.from(value.toJson());
  }

  Future<Map<String, dynamic>> _reminder(
    Object? raw, {
    bool historicalAck = false,
  }) async {
    final wire = Map<String, dynamic>.from(raw as Map);
    final proof = Map<String, dynamic>.from(wire['authorization'] as Map);
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final putCandidate = wire['putAuthorization'];
    if (historicalAck &&
        command['operation'] == 'crypto2.reminders.cancel' &&
        putCandidate is Map) {
      return _cancelledAck(
        wire,
        proof,
        Map<String, dynamic>.from(putCandidate),
      );
    }
    if (putCandidate is Map) {
      final old = CryptoSchedulingUse(context).body(putCandidate);
      final source =
          old['operation'] == 'crypto2.migration.notificationTransform'
          ? old['canonical']
          : old['payload'];
      if (source is Map && source['scopeId'] != wire['scopeId']) {
        return _relocatedReminder(
          wire,
          proof,
          Map<String, dynamic>.from(putCandidate),
          historicalAck,
        );
      }
    }
    if (putCandidate is Map &&
        (CryptoJson.decode(cryptoBase64(putCandidate['commandBase64']))
                as Map)['operation'] ==
            'crypto2.migration.notificationTransform') {
      return _migratedReminder(
        wire,
        proof,
        Map<String, dynamic>.from(putCandidate),
        historicalAck,
      );
    }
    final directory = await context.account.directory.cachedVerifiedDirectory();
    final devices = directory.devices.where(
      (d) => d['deviceId'] == command['deviceId'],
    );
    if (devices.length != 1 ||
        command['version'] != 2 ||
        command['serverId'] != directory.serverId ||
        command['accountId'] != directory.accountId ||
        command['signer'] != 'device' ||
        !const {
          'crypto2.reminders.put',
          'crypto2.reminders.cancel',
        }.contains(command['operation'])) {
      throw const FormatException('crypto_reminder_authorization');
    }
    context.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(devices.single['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    final putProof = Map<String, dynamic>.from(wire['putAuthorization'] as Map);
    final put =
        CryptoJson.decode(cryptoBase64(putProof['commandBase64'])) as Map;
    final putDevices = directory.devices.where(
      (d) => d['deviceId'] == put['deviceId'],
    );
    if (putDevices.length != 1 ||
        put['version'] != 2 ||
        put['serverId'] != directory.serverId ||
        put['accountId'] != directory.accountId ||
        put['signer'] != 'device' ||
        put['operation'] != 'crypto2.reminders.put') {
      throw const FormatException('crypto_reminder_target_authorization');
    }
    context.account.directory.reducer.crypto.verifyDomain(
      putProof,
      cryptoBase64(putDevices.single['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    final original = put['payload'] as Map;
    if (original['scopeId'] != wire['scopeId'] ||
        original['id'] != wire['id'] ||
        original['targetId'] != wire['targetId'] ||
        original['targetType'] != wire['targetType']) {
      throw const FormatException('crypto_reminder_target_substitution');
    }
    final identity = _routingIdentity({
      ...wire,
      'targetIdentity': original['targetIdentity'],
    });
    if (CryptoJson.encode(wire['targetIdentity']).toString() !=
        CryptoJson.encode(original['targetIdentity']).toString()) {
      throw const FormatException('crypto_reminder_identity_substitution');
    }
    final intent = command['payload'] as Map;
    if (wire['scopeId'] != intent['scopeId'] ||
        wire['id'] != intent['id'] ||
        wire['revision'] is! int ||
        wire['revision'] < (intent['expectedRevision'] as int) + 1 ||
        (command['operation'] == 'crypto2.reminders.put' &&
            (wire['targetType'] != intent['targetType'] ||
                wire['targetId'] != intent['targetId'])) ||
        (command['operation'] == 'crypto2.reminders.cancel' &&
            wire['state'] != 'cancelled')) {
      throw const FormatException('crypto_reminder_substitution');
    }
    // Historical device signatures authenticate the original own intent, not
    // scheduler honesty or its time of execution. Current target content is
    // independently authenticated when opened; no content is accepted here.
    // A revoked signature alone cannot establish pre-revocation consent on a
    // blank installation. Exact immutable locally staged intent is an anchor.
    final putTrusted = await _knownActiveOwnProof(
      putProof,
      put,
      putDevices.single,
    );
    final currentTrusted = await _knownActiveOwnProof(
      proof,
      command,
      devices.single,
    );
    final recoveryPending = !putTrusted || !currentTrusted;
    if (recoveryPending) {
      wire['state'] = 'recoveryPending';
      wire['syncState'] = 'recoveryPending';
      wire['syncError'] = 'crypto_reminder_consent_review_required';
      wire['remindAt'] = original['remindAt'];
    } else if (wire['state'] == 'pending' && !historicalAck) {
      final finance = const {
        'financeEntry',
        'personalFinanceEntry',
      }.contains(wire['targetType']);
      final domain = finance ? 'finance' : 'content';
      await context.pullVerified(wire['scopeId'], domain);
      final target = await context.wireRecord(
        wire['scopeId'],
        domain,
        wire['targetId'],
      );
      if (target == null ||
          target['deleted'] == 1 ||
          target['type'] != wire['targetType']) {
        throw const CryptoAuthorityPending('reminder_target_pending');
      }
      final observations = await context.database.rows(
        'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND verdict=?',
        [
          context.partition,
          wire['scopeId'],
          domain,
          wire['targetId'],
          target['crypto_revision'],
          'verified',
        ],
      );
      if (observations.length != 1) {
        throw const CryptoAuthorityPending('reminder_target_pending');
      }
      final recordWire =
          jsonDecode(observations.single['wire'] as String) as Map;
      final record =
          CryptoJson.decode(
                cryptoBase64(
                  recordWire['authorization']['recordProof']['commandBase64'],
                ),
              )
              as Map;
      final schedule = record['metadata']['reminderState'];
      if (schedule is! Map ||
          schedule['closed'] != false ||
          wire['targetRevision'] != target['crypto_revision'] ||
          wire['scheduleRevision'] != schedule['scheduleRevision']) {
        throw const CryptoAuthorityPending('reminder_target_changed');
      }
      if ((original['scheduleMode'] ?? 'absolute') == 'deadline') {
        final plaintext = jsonDecode(target['raw_payload'] as String) as Map;
        final date = plaintext['dueAt'];
        final due = date is String
                ? DateTime.parse(date).millisecondsSinceEpoch ~/ 1000
                : null,
            offset = original['offsetMinutes'];
        if (due == null ||
            offset is! int ||
            DateTime.parse(wire['remindAt']).millisecondsSinceEpoch ~/ 1000 !=
                due - offset * 60) {
          throw const FormatException(
            'crypto_reminder_relative_time_substitution',
          );
        }
      }
    } else if (historicalAck || wire['state'] != 'pending') {
      // Settle exact original receipts without promoting an old scheduler
      // projection over current record floors. Cancelled/delivered rows cannot
      // schedule an alarm and retain the signed own-intent time as metadata.
      wire['remindAt'] = original['remindAt'];
    }
    final value = SharedScheduledReminder.fromJson({
      ...wire,
      'targetId': identity['canonicalId'],
    });
    if (!isSharedUuid(value.id) ||
        !isSharedUuid(value.scopeId) ||
        !isSharedUuid(value.targetId)) {
      throw const FormatException('crypto_reminder_identity');
    }
    if (command['operation'] == 'crypto2.reminders.put') {
      if ((wire['scheduleMode'] ?? 'absolute') !=
              (intent['scheduleMode'] ?? 'absolute') ||
          wire['offsetMinutes'] != intent['offsetMinutes']) {
        throw const FormatException('crypto_reminder_schedule_substitution');
      }
      if ((intent['scheduleMode'] ?? 'absolute') == 'absolute' &&
          DateTime.parse(wire['remindAt']).toUtc().millisecondsSinceEpoch ~/
                  1000 !=
              DateTime.parse(
                    intent['remindAt'],
                  ).toUtc().millisecondsSinceEpoch ~/
                  1000) {
        throw const FormatException('crypto_reminder_time_substitution');
      }
    }
    return Map<String, dynamic>.from(value.toJson());
  }
}
