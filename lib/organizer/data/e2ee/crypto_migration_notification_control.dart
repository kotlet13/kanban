import 'dart:convert';
import 'dart:typed_data';

import '../../domain/notification_models.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_json.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_notification_codec.dart';
import 'crypto_record_address.dart';

/// Complete, private source-consent comparison BEFORE the finalized verify3
/// signature. The selection root deliberately has no certificate dependency.
class CryptoMigrationNotificationControl implements CryptoMigrationColdControl {
  CryptoMigrationNotificationControl(
    this.runtime,
    this.archive, {
    required this.recoveryFile,
  }) : evidence = CryptoMigrationColdEvidence(runtime, archive);
  final CryptoBusinessSession runtime;
  final VerifiedCryptoCaptureArchive archive;
  final Uint8List recoveryFile;
  final CryptoMigrationColdEvidence evidence;
  static const tableKinds = {
    'familyhub_reminders': 'reminder',
    'familyhub_inbox': 'inbox',
    'familyhub_deliveries': 'inbox',
    'familyhub_push_jobs': 'inbox',
    'familyhub_inbox_preferences': 'preference',
    'familyhub_inbox_state': 'inboxState',
  };
  bool _prepared = false;
  Map<String, dynamic> _body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  void _fields(Map value, Set<String> fields) =>
      CryptoMigrationNotificationCodec.fields(value, fields);
  Future<void> _prepare() async {
    if (_prepared) return;
    await runtime.db.execute(
      'CREATE TABLE IF NOT EXISTS cold_notification_transforms('
      'binding_id TEXT PRIMARY KEY,kind TEXT,proof TEXT,transform_hash TEXT,leaf_hash TEXT,use_hash TEXT,verified INTEGER NOT NULL DEFAULT 0)',
    );
    String? after;
    while (true) {
      final page = await runtime.account.directory
          .call('crypto2.migration.notifications.transforms', {
            'migrationId': archive.capture.migrationId,
            'captureId': archive.capture.captureId,
            'sourceInventoryRoot': archive.sourceInventoryRoot,
            if (after != null) 'afterBindingId': after,
            'limit': 20,
          });
      if (page['transforms'] is! List ||
          (page['transforms'] as List).length > 20 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_notification_migration_page');
      }
      for (final raw in page['transforms'] as List) {
        final item = Map<String, dynamic>.from(raw as Map);
        _fields(item, {'bindingId', 'authorization'});
        final proof = Map<String, dynamic>.from(item['authorization'] as Map),
            b = _body(item['authorization']);
        _fields(b, {
          'version',
          'operation',
          'serverId',
          'accountId',
          'migrationId',
          'captureId',
          'sourceInventoryRoot',
          'bindingId',
          'kind',
          'canonical',
          'deviceId',
          'authorDirectoryHeadHash',
          'useAuthorization',
        });
        if (b['version'] != 3 ||
            b['operation'] != 'crypto2.migration.notificationTransform' ||
            b['bindingId'] != item['bindingId'] ||
            !isCryptoCanonicalUuid(b['bindingId']) ||
            after != null && after.compareTo(b['bindingId']) >= 0 ||
            !CryptoMigrationNotificationCodec.kinds.contains(b['kind']) ||
            b['canonical'] is! Map) {
          throw const FormatException('crypto_notification_migration_context');
        }
        for (final k in [
          'serverId',
          'accountId',
          'migrationId',
          'captureId',
          'sourceInventoryRoot',
        ]) {
          if (b[k] != evidence.common[k]) {
            throw const FormatException(
              'crypto_notification_migration_context',
            );
          }
        }
        await evidence.verifyOwn(
          proof,
          b['authorDirectoryHeadHash'],
          b['deviceId'],
          'JivieE2EE/notificationTransform/v3\n',
        );
        final transformHash = await cryptoSha256([
          ...utf8.encode('JivieNotificationTransform/v3\n'),
          ...CryptoJson.encode(proof),
        ]);
        final useHash = b['useAuthorization'] == null
            ? null
            : await cryptoSha256(CryptoJson.encode(b['useAuthorization']));
        final leafHash = await CryptoMigrationNotificationCodec.leafDigest({
          'bindingId': b['bindingId'],
          'kind': b['kind'],
          'transformHash': transformHash,
          'useProofHash': useHash,
        });
        await runtime.db.execute(
          'INSERT INTO cold_notification_transforms(binding_id,kind,proof,transform_hash,leaf_hash,use_hash) VALUES(?,?,?,?,?,?)',
          [
            b['bindingId'],
            b['kind'],
            jsonEncode(proof),
            transformHash,
            leafHash,
            useHash,
          ],
        );
        after = b['bindingId'];
      }
      if (page['hasMore'] == false) break;
      if ((page['transforms'] as List).isEmpty ||
          page['nextAfterBindingId'] != after) {
        throw const FormatException('crypto_notification_migration_cursor');
      }
    }
    _prepared = true;
  }

  @override
  Future<String> verify(CryptoMigrationColdSource source) async {
    await _prepare();
    final kind = tableKinds[source.context.sourceTable];
    if (kind == null) {
      throw const FormatException('crypto_notification_migration_kind');
    }
    final rows = await runtime.db.rows(
      'SELECT * FROM cold_notification_transforms WHERE binding_id=?',
      [source.binding.bindingId],
    );
    if (rows.length != 1 ||
        rows.single['kind'] != kind ||
        rows.single['verified'] != 0) {
      throw const FormatException('crypto_notification_migration_incomplete');
    }
    final proof = jsonDecode(rows.single['proof'] as String) as Map,
        b = _body(proof),
        c = b['canonical'] as Map;
    final raw = CryptoMigrationColdEvidence.cells(source.typedRow);
    switch (kind) {
      case 'reminder':
        await _reminder(b, c, raw);
        break;
      case 'inbox':
        _inbox(source.context.sourceTable, c, raw);
        break;
      case 'preference':
        _fields(c, {'scopeId', 'category', 'settings'});
        CryptoMigrationColdEvidence.compareColumns(c, raw, {
          'scopeId': 'scope_id',
          'category': 'category',
        });
        final settings = raw['settings'] == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(raw['settings']!) as Map);
        final expected = {
          'inApp': true,
          'sound': true,
          'push': true,
          'email': false,
          ...settings,
        };
        if (raw['account_id'] != evidence.common['accountId'] ||
            !sharedNotificationCategories.contains(c['category']) ||
            !CryptoMigrationColdEvidence.same(expected, c['settings'])) {
          throw const FormatException(
            'crypto_notification_migration_preference',
          );
        }
        _fields(c['settings'] as Map, {'inApp', 'sound', 'push', 'email'});
        if ((c['settings'] as Map).values.any((v) => v is! bool)) {
          throw const FormatException(
            'crypto_notification_migration_preference',
          );
        }
        break;
      case 'inboxState':
        _fields(c, {'sequence', 'visibilityRevision'});
        CryptoMigrationColdEvidence.compareColumns(c, raw, {
          'sequence': 'sequence',
          'visibilityRevision': 'visibility_revision',
        });
        if (raw['account_id'] != evidence.common['accountId']) {
          throw const FormatException('crypto_notification_migration_owner');
        }
        CryptoMigrationNotificationCodec.count(c['sequence']);
        CryptoMigrationNotificationCodec.count(c['visibilityRevision']);
        break;
    }
    if (kind != 'reminder' && b['useAuthorization'] != null) {
      throw const FormatException('crypto_notification_migration_use');
    }
    await runtime.db.execute(
      'UPDATE cold_notification_transforms SET verified=1 WHERE binding_id=?',
      [source.binding.bindingId],
    );
    return rows.single['transform_hash'] as String;
  }

  void _inbox(String table, Map c, Map<String, String?> source) {
    if (table == 'familyhub_inbox') {
      _fields(c, {
        'rowKind',
        'id',
        'eventKey',
        'scopeId',
        'category',
        'kind',
        'audience',
        'actorAccountId',
        'targetType',
        'canonicalTargetId',
        'targetId',
        'targetRevision',
        'groupKey',
        'createdAt',
        'readAt',
        'revision',
        'sequence',
        'inApp',
      });
      CryptoMigrationColdEvidence.compareColumns(c, source, {
        'id': 'id',
        'eventKey': 'event_key',
        'scopeId': 'scope_id',
        'category': 'category',
        'audience': 'audience',
        'actorAccountId': 'actor_account_id',
        'targetType': 'target_type',
        'canonicalTargetId': 'target_id',
        'targetRevision': 'target_revision',
        'groupKey': 'group_key',
        'createdAt': 'created_at',
        'readAt': 'read_at',
        'revision': 'revision',
        'sequence': 'sequence',
        'inApp': 'in_app',
      });
      final wire = c['targetType'] == 'membership'
          ? c['canonicalTargetId']
          : cryptoWireRecordId(
              evidence.common['serverId'],
              c['scopeId'],
              c['targetType'],
              c['canonicalTargetId'],
            );
      if (c['rowKind'] != 'inbox' ||
          source['recipient_account_id'] != evidence.common['accountId'] ||
          c['kind'] != 'crypto2.${source['kind']}' ||
          c['targetId'] != wire) {
        throw const FormatException('crypto_notification_migration_inbox');
      }
    } else {
      final push = table == 'familyhub_push_jobs';
      final columns = {
        'inboxId': 'inbox_id',
        'state': 'state',
        'attempts': 'attempts',
        'nextAttempt': 'next_attempt',
        'expiresAt': 'expires_at',
        'leaseToken': 'lease_token',
        'leaseUntil': 'lease_until',
        'sentAt': 'sent_at',
        if (push) ...{
          'deviceId': 'device_id',
          'registrationRevision': 'registration_revision',
          'tokenHash': 'token_hash',
        },
      };
      _fields(c, {'rowKind', ...columns.keys});
      CryptoMigrationColdEvidence.compareColumns(c, source, columns);
      if (c['rowKind'] != (push ? 'push' : 'delivery')) {
        throw const FormatException('crypto_notification_migration_job');
      }
    }
  }

  Future<void> _reminder(Map b, Map c, Map<String, String?> source) async {
    _fields(c, {
      'id',
      'scopeId',
      'targetType',
      'canonicalTargetId',
      'targetId',
      'domain',
      'targetRevision',
      'targetRecordProofHash',
      'scheduleRevision',
      'consentGeneration',
      'scopeLifecycleHash',
      'projectBarrier',
      'remindAt',
      'remindEpoch',
      'revision',
      'state',
      'scheduleMode',
      'offsetMinutes',
    });
    CryptoMigrationColdEvidence.compareColumns(c, source, {
      'id': 'id',
      'scopeId': 'scope_id',
      'targetType': 'target_type',
      'canonicalTargetId': 'target_id',
      'remindAt': 'remind_at',
      'remindEpoch': 'remind_epoch',
      'revision': 'revision',
      'state': 'state',
      'scheduleMode': 'schedule_mode',
      'offsetMinutes': 'offset_minutes',
    });
    if (source['account_id'] != evidence.common['accountId'] ||
        !['pending', 'cancelled', 'delivered'].contains(c['state']) ||
        !['absolute', 'deadline'].contains(c['scheduleMode']) ||
        !isCryptoCanonicalUuid(c['scheduleRevision']) ||
        c['targetId'] !=
            cryptoWireRecordId(
              evidence.common['serverId'],
              c['scopeId'],
              c['targetType'],
              c['canonicalTargetId'],
            ) ||
        c['domain'] != cryptoRecordDomain(c['targetType'])) {
      throw const FormatException('crypto_notification_migration_reminder');
    }
    if (c['targetRecordProofHash'] == null) {
      if (c['state'] == 'pending' ||
          c['targetRevision'] != 0 ||
          c['consentGeneration'] != null ||
          c['scopeLifecycleHash'] != null ||
          c['projectBarrier'] != null ||
          b['useAuthorization'] != null) {
        throw const FormatException('crypto_notification_migration_target');
      }
      return;
    }
    final record = await evidence.record(
      c['scopeId'],
      c['targetId'],
      c['targetRecordProofHash'],
    );
    final state = (record['metadata'] as Map)['reminderState'] as Map;
    if (record['type'] != c['targetType'] ||
        record['expectedRevision'] + 1 != c['targetRevision'] ||
        state['scheduleRevision'] != c['scheduleRevision'] ||
        state['consentGeneration'] != c['consentGeneration']) {
      throw const FormatException('crypto_notification_migration_target');
    }
    final projection = await runtime.wireRecord(
      c['scopeId'],
      c['domain'],
      c['targetId'],
    );
    final payload =
        (jsonDecode(projection!['projection'] as String) as Map)['payload']
            as Map?;
    if (c['state'] == 'pending') {
      if (record['deleted'] != false ||
          state['closed'] != false ||
          payload == null) {
        throw const FormatException(
          'crypto_notification_migration_target_closed',
        );
      }
      final dates = [
        payload['dueAt'],
        payload['startAt'],
        payload['endAt'],
        payload['occurredAt'],
        if (payload.containsKey('plannedAt')) payload['plannedAt'],
      ];
      String date(Object? value) {
        final d = DateTime.parse(value as String).toUtc();
        return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}.${(d.millisecond * 1000 + d.microsecond).toString().padLeft(6, '0')}Z';
      }

      final canonical = await cryptoSha256(
        utf8.encode(
          jsonEncode(dates.map((v) => v == null ? null : date(v)).toList()),
        ),
      );
      final legacy = await cryptoSha256(utf8.encode(jsonEncode(dates)));
      if (source['target_fingerprint'] != canonical &&
          source['target_fingerprint'] != legacy) {
        throw const FormatException(
          'crypto_notification_migration_source_consent',
        );
      }
      if (c['scheduleMode'] == 'deadline') {
        if (c['targetType'] != 'task' ||
            payload['dueAt'] == null ||
            c['offsetMinutes'] is! int ||
            c['offsetMinutes'] < 0 ||
            DateTime.parse(payload['dueAt']).toUtc().millisecondsSinceEpoch ~/
                        1000 -
                    c['offsetMinutes'] * 60 !=
                c['remindEpoch']) {
          throw const FormatException('crypto_notification_migration_due');
        }
      }
    }
    if (c['state'] == 'pending' || b['useAuthorization'] != null) {
      // The exact source-bound staged record was already verified in the
      // isolated FILE pass. Enter its frozen verifier without requiring a
      // previous scratch pass's deliberately discarded in-memory head cache.
      final lifecycle = await runtime.access.withReadOnlyFrozenScope<String>(
        scopeId: c['scopeId'],
        candidateHeadHash: record['membershipHeadHash'],
        recoveryFile: recoveryFile,
        body: () => runtime.access.verifiedLifecycleHash(c['scopeId']),
      );
      if (lifecycle != c['scopeLifecycleHash'] ||
          !CryptoMigrationColdEvidence.same(
            await _projectBarrier(record),
            c['projectBarrier'],
          )) {
        throw const FormatException('crypto_notification_migration_barrier');
      }
    }
    if (b['useAuthorization'] == null) {
      if (c['state'] == 'pending' && c['scheduleMode'] == 'deadline') {
        throw const FormatException('crypto_notification_migration_use');
      }
      return;
    }
    final use = Map<String, dynamic>.from(b['useAuthorization'] as Map),
        u = _body(use);
    _fields(u, {
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
      'migrationId',
      'captureId',
      'sourceInventoryRoot',
      'bindingId',
      'originalState',
    });
    if (u['version'] != 3 ||
        u['operation'] != 'crypto2.migration.schedulingUse' ||
        u['mode'] != 'relative' ||
        !isCryptoCanonicalUuid(u['useId']) ||
        c['scheduleMode'] != 'deadline' ||
        c['state'] == 'cancelled') {
      throw const FormatException('crypto_notification_migration_use');
    }
    for (final k in [
      'serverId',
      'accountId',
      'deviceId',
      'authorDirectoryHeadHash',
      'migrationId',
      'captureId',
      'sourceInventoryRoot',
      'bindingId',
    ]) {
      if (u[k] != b[k]) {
        throw const FormatException('crypto_notification_migration_use');
      }
    }
    for (final k in [
      'scopeId',
      'targetId',
      'targetType',
      'domain',
      'consentGeneration',
      'scopeLifecycleHash',
      'targetRevision',
      'targetRecordProofHash',
    ]) {
      if (u[k] != c[k]) {
        throw const FormatException('crypto_notification_migration_use');
      }
    }
    if (u['schedulePutId'] != c['id'] ||
        u['originalState'] != c['state'] ||
        u['sourceScheduleRevision'] != c['scheduleRevision'] ||
        u['membershipHeadHash'] != record['membershipHeadHash'] ||
        u['accessRevision'] != record['accessRevision'] ||
        !CryptoMigrationColdEvidence.same(
          u['projectBarrier'],
          c['projectBarrier'],
        ) ||
        u['expiresAtEpoch'] != null &&
            (u['expiresAtEpoch'] is! int ||
                u['expiresAtEpoch'] < 0 ||
                u['expiresAtEpoch'] > 253402300799 ||
                c['state'] == 'pending' &&
                    u['expiresAtEpoch'] <=
                        DateTime.now().millisecondsSinceEpoch ~/ 1000)) {
      throw const FormatException('crypto_notification_migration_use');
    }
    await evidence.verifyOwn(
      use,
      u['authorDirectoryHeadHash'],
      u['deviceId'],
      'JivieE2EE/migrationSchedulingUse/v3\n',
    );
  }

  Future<Map<String, dynamic>?> _projectBarrier(Map record) async {
    final pending = List<Map>.from(
      ((record['metadata'] as Map)['referenceVersions'] as List).map(
        (r) => Map.from(r as Map),
      ),
    );
    final seen = <String>{};
    Map<String, dynamic>? found;
    while (pending.isNotEmpty) {
      final r = pending.removeAt(0);
      if (r['scopeId'] != record['scopeId'] || !seen.add(r['id'])) continue;
      if (seen.length > 100) {
        throw const FormatException('crypto_reference_graph_limit');
      }
      final target = await evidence.record(
        r['scopeId'],
        r['id'],
        r['recordProofHash'],
      );
      if (target['domain'] != r['domain'] ||
          target['expectedRevision'] + 1 != r['revision']) {
        throw const FormatException('crypto_notification_migration_reference');
      }
      final m = target['metadata'] as Map;
      if (target['type'] == 'project') {
        final p = m['projectState'];
        if (found != null ||
            target['deleted'] != false ||
            p is! Map ||
            p['archived'] != false ||
            !isCryptoCanonicalUuid(p['consentGeneration'])) {
          throw const FormatException('crypto_notification_migration_project');
        }
        found = {'id': r['id'], 'consentGeneration': p['consentGeneration']};
      }
      pending.addAll(
        (m['referenceVersions'] as List).map((r) => Map.from(r as Map)),
      );
    }
    return found;
  }

  @override
  Future<Map<String, dynamic>> finish() async {
    await _prepare();
    final counts = {
      for (final k in CryptoMigrationNotificationCodec.kinds) k: 0,
    };
    final totals = await runtime.db.rows(
      'SELECT kind,verified,COUNT(*) AS n FROM cold_notification_transforms GROUP BY kind,verified',
    );
    var total = 0;
    for (final row in totals) {
      if (row['verified'] != 1) {
        throw const FormatException('crypto_notification_migration_extra');
      }
      final n = row['n'] as int;
      counts[row['kind'] as String] = n;
      total += n;
    }
    Stream<String> hashes() async* {
      String? after;
      while (true) {
        final rows = await runtime.db.rows(
          'SELECT leaf_hash FROM cold_notification_transforms'
          '${after == null ? '' : ' WHERE leaf_hash>?'} ORDER BY leaf_hash LIMIT 20',
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
      'kind': 'notifications',
      'count': total,
      'root': await CryptoMigrationNotificationCodec.selectionRoot(
        evidence.common,
        total,
        hashes(),
      ),
    };
  }
}
