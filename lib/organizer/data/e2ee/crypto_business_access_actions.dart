import 'dart:convert';
import 'dart:typed_data';

import 'crypto_access_coordinator.dart';
import 'crypto_business_router.dart';
import 'crypto_record_address.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';
import '../../domain/collaboration_models.dart' show CollaborationException;

/// Existing management actions prepare a closed component change. Every scope
/// manager reviews its own exact future state through Pending approvals; retry
/// of the original application request finishes the complete atomic component.
class CryptoBusinessAccessActions {
  CryptoBusinessAccessActions(this.context);
  final CryptoBusinessSession context;
  static const operations = {
    'scopes.setLeader',
    'scopes.accessMigrationPreview',
    'scopes.accessMigrationApply',
  };
  bool supports(String operation) => operations.contains(operation);

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    if (!supports(operation) || !isCryptoCanonicalUuid(params['scopeId'])) {
      throw const FormatException('crypto_access_application_action');
    }
    if (operation == 'scopes.accessMigrationPreview') return _preview(params);
    if (operation == 'scopes.accessMigrationApply') return _apply(params);
    if (params.length != 4 ||
        !params.keys.every(
          const {'scopeId', 'requestId', 'accountId', 'enabled'}.contains,
        ) ||
        !isCryptoCanonicalUuid(params['scopeId']) ||
        !isCryptoCanonicalUuid(params['requestId']) ||
        !isCryptoCanonicalUuid(params['accountId']) ||
        params['enabled'] is! bool) {
      throw const FormatException('crypto_access_application_action');
    }
    final scope = params['scopeId'] as String;
    final coordinator = CryptoAccessCoordinator(context);
    final prepared = await coordinator.prepare(
      scopeId: scope,
      requestId: params['requestId'] as String,
      action: {
        'kind': 'leader',
        'accountId': params['accountId'],
        'enabled': params['enabled'],
      },
    );
    final prior = await coordinator.reconcile(scope, prepared);
    if (prior == null) {
      // finish checks the entire sorted affected set before allocating the
      // activation nonce. Waiting for review is resumable, not a rejected send.
      await coordinator.finish(
        scopeId: scope,
        prepared: prepared,
        cancel: false,
      );
    }
    // Members come from the independently verified latest head/descriptor. A
    // later legitimate leader change is preserved when an old ACK is retried.
    return context.members(scope);
  }

  String _previewId(int version) => 'accessPolicyPreview:$version';
  Map<String, dynamic> _decode(Object? value) => Map<String, dynamic>.from(
    CryptoJson.decode(Uint8List.fromList((value as List).cast<int>())) as Map,
  );

  Future<Map<String, dynamic>> _preview(
    Map<String, Object?> params, {
    bool replanned = false,
  }) async {
    if (params.keys.any(
          (k) => !const {'scopeId', 'targetVersion'}.contains(k),
        ) ||
        params['targetVersion'] != null &&
            !const [2, 3].contains(params['targetVersion'])) {
      throw const FormatException('crypto_access_policy_preview');
    }
    final scope = params['scopeId'] as String,
        version = params['targetVersion'] as int? ?? 2;
    final head = await context.access.currentHead(scope, online: true);
    final descriptor = await context.access.verifiedScopeDescriptor(scope);
    if (head.member(context.account.directory.accountId)['role'] != 'owner') {
      throw const CryptoAuthorityPending('scope_management_forbidden');
    }
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [context.partition, scope, _previewId(version)],
    );
    late Map<String, dynamic> state;
    if (rows.isEmpty) {
      state = {
        'version': 2,
        'scopeId': scope,
        'targetVersion': version,
        'sourceHeadHash': head.headHash,
        'fromVersion': descriptor['accessPolicyVersion'],
        'prepareRequestId': context.account.directory.reducer.crypto.randomId(),
      };
      await context.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          context.partition,
          scope,
          _previewId(version),
          'accessPolicyPreview',
          CryptoJson.encode(state),
        ],
      );
    } else {
      state = _decode(rows.single['payload']);
    }
    if (state['version'] != 2 ||
        state['scopeId'] != scope ||
        state['targetVersion'] != version ||
        !isCryptoCanonicalUuid(state['prepareRequestId'])) {
      throw const FormatException('crypto_access_policy_preview_context');
    }
    final coordinator = CryptoAccessCoordinator(context);
    final prepared = await coordinator.prepare(
      scopeId: scope,
      requestId: state['prepareRequestId'],
      action: {'kind': 'accessPolicy', 'targetVersion': version},
    );
    if (state['sourceHeadHash'] != head.headHash) {
      return _restartPreview(
        params,
        coordinator,
        prepared,
        replanned: replanned,
      );
    }
    // The actor reviews the root's exact consequence commitment here; every
    // child manager sees and signs its own count/IDs in Pending approvals.
    final proof = prepared['authorization'] as Map;
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final snapshot = (command['payload'] as Map)['consequenceSnapshot'] as Map?;
    late List<Map<String, dynamic>> pending;
    try {
      pending = await coordinator.pendingApprovals(scope);
    } on CollaborationException catch (error) {
      if (!const {
        'crypto_access_consequences_changed',
        'crypto_access_component_changed',
        'crypto_access_intent_expired',
      }.contains(error.code)) {
        rethrow;
      }
      return _restartPreview(
        params,
        coordinator,
        prepared,
        replanned: replanned,
      );
    }
    if (!pending.any((p) => p['intentHash'] == prepared['intentHash'])) {
      return _restartPreview(
        params,
        coordinator,
        prepared,
        replanned: replanned,
      );
    }
    final projects = <Map<String, dynamic>>[];
    final tokens = await coordinator.affectedScopeTokens(prepared);
    var visible = 0;
    for (final candidate in await context.catalog()) {
      final sid = candidate['id'] as String;
      if (!tokens.contains(await coordinator.scopeToken(sid, scope))) continue;
      visible++;
      if (sid == scope || candidate['headHash'] == null) continue;
      final local = await context.database.rows(
        'SELECT data FROM scopes WHERE partition=? AND id=?',
        [context.partition, sid],
      );
      final name = local.isEmpty
          ? 'Project'
          : (jsonDecode(local.single['data'] as String) as Map)['name'];
      try {
        final source = await context.access.currentHead(sid, online: true);
        if (source.member(context.account.directory.accountId)['manageKeys'] !=
            true) {
          continue;
        }
        final proposal = (await coordinator.pendingApprovals(
          sid,
        )).where((p) => p['intentHash'] == prepared['intentHash']).single;
        final future = (proposal['future'] as Map)['members'] as List;
        final readers = <Map<String, dynamic>>[],
            writers = <Map<String, dynamic>>[];
        for (final raw in future) {
          final member = raw as Map, id = member['accountId'];
          final old = source.members
              .where((m) => m['accountId'] == id)
              .firstOrNull;
          final entry = {
            'accountId': id,
            'displayName': id,
            'accessSource': 'projectMembership',
          };
          if (member['financeRole'] == 'write' &&
              old?['financeRole'] != 'write') {
            writers.add(entry);
          } else if (member['financeRole'] == 'read' &&
              (old == null || old['financeRole'] == 'none')) {
            readers.add(entry);
          }
        }
        projects.add({
          'scopeId': sid,
          'name': name,
          'financeWasEnabled': source.commitment('finance') != null,
          'additionalReaders': readers,
          'additionalWriters': writers,
        });
      } on CryptoAuthorityPending {
        /* Its own manager reviews the private scope. */
      }
    }
    return {
      'scopeId': scope,
      'fromVersion': state['fromVersion'],
      'toVersion': version,
      'previewHash': prepared['intentHash'],
      'projects': projects,
      'canApply': true,
      'blockers': [],
      'pendingInvitationsRevoked': snapshot?['invitationCount'] ?? 0,
      'revokedInvitationIds': <String>[],
      'affectedCount': prepared['affectedCount'],
      'hiddenApprovalCount': tokens.length - visible,
    };
  }

  Future<Map<String, dynamic>> _restartPreview(
    Map<String, Object?> params,
    CryptoAccessCoordinator coordinator,
    Map<String, dynamic> prepared, {
    required bool replanned,
  }) async {
    if (replanned) {
      throw const CryptoAuthorityPending('crypto_access_preview_changed');
    }
    // An explicit request for a new preview cancels the known old preparation;
    // its signed command/receipt are retained. Closed domains can only return
    // to writable use through the existing fresh-key recovery transition.
    final scope = params['scopeId'] as String,
        version = params['targetVersion'] as int? ?? 2;
    final outcome = await coordinator.finish(
      scopeId: scope,
      prepared: prepared,
      cancel: true,
    );
    if (outcome['cleanupRequired'] == true) {
      throw const CryptoAuthorityPending('crypto_access_cleanup_required');
    }
    final head = await context.access.currentHead(scope, online: true);
    final descriptor = await context.access.verifiedScopeDescriptor(scope);
    final next = {
      'version': 2,
      'scopeId': scope,
      'targetVersion': version,
      'sourceHeadHash': head.headHash,
      'fromVersion': descriptor['accessPolicyVersion'],
      'prepareRequestId': context.account.directory.reducer.crypto.randomId(),
    };
    await context.database.execute(
      'UPDATE crypto_membership_intents SET payload=? WHERE partition=? AND scope_id=? AND intent_id=?',
      [CryptoJson.encode(next), context.partition, scope, _previewId(version)],
    );
    return _preview(params, replanned: true);
  }

  Future<Map<String, dynamic>> _apply(Map<String, Object?> params) async {
    if (params.keys.any(
          (k) => !const {
            'scopeId',
            'targetVersion',
            'previewHash',
            'requestId',
          }.contains(k),
        ) ||
        !isCryptoCanonicalUuid(params['requestId']) ||
        params['previewHash'] is! String ||
        params['targetVersion'] != null &&
            !const [2, 3].contains(params['targetVersion'])) {
      throw const FormatException('crypto_access_policy_apply');
    }
    final scope = params['scopeId'] as String,
        version = params['targetVersion'] as int? ?? 2;
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [context.partition, scope, _previewId(version)],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('crypto_access_preview_required');
    }
    final state = _decode(rows.single['payload']);
    final coordinator = CryptoAccessCoordinator(context);
    final prepared = await coordinator.prepare(
      scopeId: scope,
      requestId: state['prepareRequestId'],
      action: {'kind': 'accessPolicy', 'targetVersion': version},
    );
    if (prepared['intentHash'] != params['previewHash']) {
      throw const FormatException('crypto_access_preview_binding');
    }
    final actionId = 'accessPolicyApply:${params['requestId']}';
    final prior = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [context.partition, scope, actionId],
    );
    if (prior.isEmpty) {
      await context.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          context.partition,
          scope,
          actionId,
          'accessPolicyApply',
          CryptoJson.encode(params),
        ],
      );
    } else if (base64Encode(
          CryptoJson.encode(_decode(prior.single['payload'])),
        ) !=
        base64Encode(CryptoJson.encode(params))) {
      throw const FormatException('crypto_access_policy_immutable');
    }
    if (await coordinator.reconcile(scope, prepared) == null) {
      await coordinator.finish(
        scopeId: scope,
        prepared: prepared,
        cancel: false,
      );
    }
    final scopes = (await context.scopes())['scopes'] as List;
    return {'scope': scopes.cast<Map>().singleWhere((s) => s['id'] == scope)};
  }
}
