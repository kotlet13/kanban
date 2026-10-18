import 'dart:typed_data';

import 'account_directory_v2.dart';
import 'crypto_access_coordinator.dart';
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_manager.dart';

/// A leave request is consent to an exact removal, never key-management power.
/// Minimal status is an authenticated server outcome, not scope/head authority.
class CryptoBusinessLeave {
  CryptoBusinessLeave(this.context);
  final CryptoBusinessSession context;
  static final _hash = RegExp(r'^[a-f0-9]{64}$');

  Map<String, dynamic> _map(Object value) => Map<String, dynamic>.from(
    CryptoJson.decode(Uint8List.fromList((value as List).cast<int>())) as Map,
  );
  Map<String, dynamic> _command(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );

  Future<Map<String, dynamic>?> _saved(String scope, String key) async {
    final rows = await context.database.rows(
      'SELECT i.authorization FROM crypto_membership_action_keys a JOIN crypto_membership_intents i ON i.partition=a.partition AND i.scope_id=a.scope_id AND i.intent_id=a.request_id WHERE a.partition=? AND a.scope_id=? AND a.action_key=?',
      [context.partition, scope, key],
    );
    return rows.isEmpty ? null : _map(rows.single['authorization']!);
  }

  Future<void> _own(Map proof, String scope) async {
    final c = _command(proof), p = c['payload'] as Map;
    final own = await context.account.directory.requireFresh();
    _shape(c, scope);
    if (c['accountId'] != own.accountId) {
      throw const FormatException('crypto_leave_own_request');
    }
    final author = await CryptoAccessCoordinator(
      context,
    ).ownDirectoryAt(p['authorDirectoryHeadHash']);
    context.account.directory.reducer.crypto.verifyDomain(
      Map<String, dynamic>.from(proof),
      cryptoBase64(
        author.activeDevice(c['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
  }

  void _shape(Map c, String scope) {
    final p = c['payload'];
    if (c.length != 8 ||
        c.keys.any(
          (k) => !const {
            'version',
            'operation',
            'requestId',
            'serverId',
            'accountId',
            'deviceId',
            'signer',
            'payload',
          }.contains(k),
        ) ||
        c['version'] != 2 ||
        c['operation'] != 'crypto2.access.leaveRequest' ||
        c['serverId'] != context.account.directory.session.profile.serverId ||
        c['signer'] != 'device' ||
        !isCryptoCanonicalUuid(c['requestId']) ||
        !isCryptoCanonicalUuid(c['accountId']) ||
        !isCryptoCanonicalUuid(c['deviceId']) ||
        p is! Map ||
        p.length != 5 ||
        p.keys.any(
          (k) => !const {
            'scopeId',
            'membershipHeadHash',
            'expectedAccessRevision',
            'authorDirectoryHeadHash',
            'expiresAtEpoch',
          }.contains(k),
        ) ||
        p['scopeId'] != scope ||
        !_hash.hasMatch(p['membershipHeadHash'] as String? ?? '') ||
        !_hash.hasMatch(p['authorDirectoryHeadHash'] as String? ?? '') ||
        p['expectedAccessRevision'] is! int ||
        p['expectedAccessRevision'] < 0 ||
        p['expectedAccessRevision'] > 9007199254740991 ||
        p['expiresAtEpoch'] is! int ||
        p['expiresAtEpoch'] < 0 ||
        p['expiresAtEpoch'] > 9007199254740991) {
      throw const FormatException('crypto_leave_request_shape');
    }
  }

  Future<Map<String, dynamic>> request(String scope, String requestId) async {
    final key = 'leaveRequest:$requestId';
    final saved = await _saved(scope, key);
    late Map<String, dynamic> payload;
    if (saved != null) {
      await _own(saved, scope);
      if (_command(saved)['requestId'] != requestId) {
        throw const FormatException('crypto_leave_request_correlation');
      }
      payload = Map<String, dynamic>.from(_command(saved)['payload'] as Map);
    } else {
      final head = await context.access.currentHead(scope, online: true);
      final own = await context.account.directory.requireFresh();
      if (head.member(own.accountId)['role'] == 'owner') {
        throw const CryptoAuthorityPending('scope_owner_transfer_required');
      }
      payload = {
        'scopeId': scope,
        'membershipHeadHash': head.headHash,
        'expectedAccessRevision': head.accessRevision,
        'authorDirectoryHeadHash': own.headHash,
        'expiresAtEpoch':
            DateTime.now().millisecondsSinceEpoch ~/ 1000 + 604740,
      };
    }
    final result = await ScopeCryptoManager(context.access).leaveCommand(
      'crypto2.access.leaveRequest',
      scope,
      payload,
      actionKey: key,
      requestId: requestId,
    );
    final proof = Map<String, dynamic>.from(result['authorization'] as Map);
    await _own(proof, scope);
    final hash = await cryptoSha256(CryptoJson.encode(proof));
    if (result['requestHash'] != hash || result['state'] != 'pending') {
      throw const FormatException('crypto_leave_request_receipt');
    }
    final value = await status(scope, proof);
    if (value['state'] == 'applied') {
      return {
        'removed': true,
        'scopeId': scope,
        'accountId': context.account.directory.accountId,
      };
    }
    throw CryptoAuthorityPending(
      value['state'] == 'pending'
          ? 'crypto_leave_approval_required'
          : 'crypto_leave_renewal_required',
    );
  }

  Future<Map<String, dynamic>> status(String scope, Map proof) async {
    await _own(proof, scope);
    final hash = await cryptoSha256(CryptoJson.encode(proof));
    final value = await context.account.directory.call(
      'crypto2.access.leaveStatus',
      {'requestHash': hash},
    );
    if (value.length != 4 ||
        value.keys.any(
          (key) => !const {
            'requestHash',
            'state',
            'intentHash',
            'headHash',
          }.contains(key),
        ) ||
        value['requestHash'] != hash ||
        !const {
          'pending',
          'applied',
          'cancelled',
          'expired',
          'renewalRequired',
        }.contains(value['state']) ||
        value['state'] == 'applied' &&
            (!_hash.hasMatch(value['intentHash'] as String? ?? '') ||
                !_hash.hasMatch(value['headHash'] as String? ?? ''))) {
      throw const FormatException('crypto_leave_status');
    }
    return {...value, 'authorization': proof};
  }

  Future<List<Map<String, dynamic>>> mine() async {
    final values = <Map<String, dynamic>>[];
    String? after;
    do {
      final rows = await context.database.rows(
        "SELECT a.scope_id,a.request_id,i.authorization FROM crypto_membership_action_keys a JOIN crypto_membership_intents i ON i.partition=a.partition AND i.scope_id=a.scope_id AND i.intent_id=a.request_id WHERE a.partition=? AND a.action_key LIKE 'leaveRequest:%' AND a.request_id>? ORDER BY a.request_id LIMIT 20",
        [context.partition, after ?? ''],
      );
      for (final row in rows) {
        after = row['request_id'] as String;
        final proof = _map(row['authorization']!);
        values.add({
          ...await status(row['scope_id'] as String, proof),
          'scopeId': row['scope_id'],
        });
      }
      if (rows.length < 20) break;
      if (values.length > 1000) {
        throw const FormatException('crypto_leave_inventory_limit');
      }
    } while (true);
    return values;
  }

  Future<List<Map<String, dynamic>>> pending(String scope) async {
    final items = <Map<String, dynamic>>[];
    String? after;
    do {
      final page = await context.account.directory.call(
        'crypto2.access.leaveRequests',
        {'scopeId': scope, 'limit': 20, if (after != null) 'afterHash': after},
      );
      final rows = page['requests'];
      if (rows is! List || rows.length > 20 || page['hasMore'] is! bool) {
        throw const FormatException('crypto_leave_page');
      }
      for (final raw in rows) {
        final item = Map<String, dynamic>.from(raw as Map);
        final hash = item['requestHash'];
        if (item.length != 2 ||
            !_hash.hasMatch(hash as String? ?? '') ||
            after != null && (hash as String).compareTo(after) <= 0) {
          throw const FormatException('crypto_leave_page_order');
        }
        after = hash;
        try {
          await verify(scope, item);
          items.add(item);
        } on CryptoAuthorityPending catch (error) {
          // Old requests cannot monopolize discovery after a scope generation
          // changes. Their own status explicitly requires renewed consent.
          if (error.reason != 'crypto_leave_renewal_required') rethrow;
        }
      }
      if (page['nextAfterHash'] != after ||
          page['hasMore'] == true && rows.isEmpty) {
        throw const FormatException('crypto_leave_cursor');
      }
      if (page['hasMore'] != true) break;
      if (items.length > 400) {
        throw const FormatException('crypto_leave_inventory_limit');
      }
    } while (true);
    return items;
  }

  Future<Map<String, dynamic>> verify(String scope, Map item) async {
    final proof = Map<String, dynamic>.from(item['authorization'] as Map),
        c = _command(proof),
        p = c['payload'] as Map;
    _shape(c, scope);
    if (await cryptoSha256(CryptoJson.encode(proof)) != item['requestHash']) {
      throw const FormatException('crypto_leave_hash');
    }
    final head = await context.access.currentHead(scope, online: true);
    if (p['membershipHeadHash'] != head.headHash ||
        p['expectedAccessRevision'] != head.accessRevision ||
        p['expiresAtEpoch'] <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw const CryptoAuthorityPending('crypto_leave_renewal_required');
    }
    final member = head.member(c['accountId']);
    if (member['role'] == 'owner') {
      throw const FormatException('crypto_leave_owner');
    }
    final current = await context.access.currentMemberDirectory(
      scope,
      head.headHash,
      c['accountId'],
    );
    final author = await context.access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head.headHash,
      accountId: c['accountId'],
      directoryHeadHash: p['authorDirectoryHeadHash'],
      online: true,
    );
    if (author.deviceSnapshotHash != current.deviceSnapshotHash ||
        member['deviceSnapshotHash'] != current.deviceSnapshotHash) {
      throw const CryptoAuthorityPending('crypto_leave_renewal_required');
    }
    final device = current.activeDevice(c['deviceId']);
    context.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    return c;
  }

  Future<Map<String, dynamic>> prepare(String scope, Map item) async {
    final hash = item['requestHash'] as String;
    final proof = Map<String, dynamic>.from(item['authorization'] as Map);
    final command = _command(proof);
    _shape(command, scope);
    if (hash != await cryptoSha256(CryptoJson.encode(proof))) {
      throw const FormatException('crypto_leave_hash');
    }
    final id = 'leaveManager:$hash';
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [context.partition, scope, id],
    );
    late Map<String, dynamic> state;
    if (rows.isEmpty) {
      state = {
        'requestHash': hash,
        'authorization': proof,
        'requestId': context.account.directory.reducer.crypto.randomId(),
      };
      await context.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          context.partition,
          scope,
          id,
          'leaveManager',
          CryptoJson.encode(state),
        ],
      );
    } else {
      state = _map(rows.single['payload']!);
    }
    if (state['requestHash'] != hash ||
        !isCryptoCanonicalUuid(state['requestId'])) {
      throw const FormatException('crypto_leave_plan');
    }
    if (await _saved(scope, 'access:${state['requestId']}:prepare') == null) {
      await verify(scope, item);
    }
    final result = await CryptoAccessCoordinator(context).prepare(
      scopeId: scope,
      requestId: state['requestId'],
      action: {'kind': 'memberRemove', 'accountId': command['accountId']},
      leaveRequestHash: hash,
    );
    return result;
  }

  Future<void> finish(String scope, Map item) async {
    final plan = await prepare(scope, item);
    await CryptoAccessCoordinator(
      context,
    ).finish(scopeId: scope, prepared: plan, cancel: false);
    await context.database.execute(
      "UPDATE crypto_membership_intents SET state='leaveManagerCompleted' WHERE partition=? AND scope_id=? AND intent_id=?",
      [context.partition, scope, 'leaveManager:${item['requestHash']}'],
    );
  }

  Future<void> cancelPlan(String scope, Map item) async {
    final plan = await prepare(scope, item);
    await CryptoAccessCoordinator(
      context,
    ).finish(scopeId: scope, prepared: plan, cancel: true);
    // Immutable closures stay in place. Pending approvals will expose the
    // independent manager recovery path instead of claiming writable old keys.
    await context.database.execute(
      "UPDATE crypto_membership_intents SET state='leaveManagerCancelled' WHERE partition=? AND scope_id=? AND intent_id=?",
      [context.partition, scope, 'leaveManager:${item['requestHash']}'],
    );
  }

  Future<List<Map<String, dynamic>>> managerPlans(String scope) async {
    final rows = await context.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='leaveManager' ORDER BY intent_id LIMIT 400",
      [context.partition, scope],
    );
    return [for (final row in rows) _map(row['payload']!)];
  }

  Future<void> cancel(String scope, Map proof) async {
    await _own(proof, scope);
    final hash = await cryptoSha256(CryptoJson.encode(proof)),
        id = 'leaveCancel:$hash';
    final saved = await _saved(scope, id);
    final request = saved == null
        ? context.account.directory.reducer.crypto.randomId()
        : _command(saved)['requestId'] as String;
    final result = await ScopeCryptoManager(context.access).leaveCommand(
      'crypto2.access.leaveCancel',
      scope,
      {'requestHash': hash},
      actionKey: id,
      requestId: request,
    );
    if (result['requestHash'] != hash || result['state'] != 'cancelled') {
      throw const FormatException('crypto_leave_cancel_receipt');
    }
  }
}
