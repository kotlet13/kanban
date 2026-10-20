import 'dart:convert';

import '../collaboration_transport.dart';

typedef CryptoAuthorityRead =
    Future<Map<String, dynamic>> Function(
      String operation,
      Map<String, dynamic> params,
    );

/// Transport material for one existing bounded verified operation. A bundled
/// result is never authority: the ordinary signed-proof consumers still run.
class CryptoAuthoritySnapshot {
  CryptoAuthoritySnapshot({
    required this.read,
    required this.serverId,
    required this.accountId,
    required this.deviceId,
    required this.isValid,
    required this.onMutation,
    this.accountAfterGeneration,
    this.directoryAfterGenerations,
  });

  final CryptoAuthorityRead read;
  final String serverId, accountId, deviceId;
  final Future<bool> Function() isValid;
  final void Function() onMutation;
  final Future<int> Function()? accountAfterGeneration;
  final Future<Map<String, int>> Function()? directoryAfterGenerations;
  bool _active = true, _unsupported = false, _capabilityChecked = false;
  final _entries = <String, Map<String, dynamic>>{};
  final _attempted = <String>{};
  Future<void>? _loading;

  static const bundledReads = {
    'crypto2.account.status',
    'crypto2.account.directory',
    'crypto2.scopes.catalog',
    'crypto2.scope.headGet',
    'crypto2.directory.status',
    'crypto2.directory.read',
    'crypto2.scope.lifecycle.baseline',
    'crypto2.scope.lifecycle.current',
    'crypto2.scope.lifecycle.list',
    'crypto2.scope.financePolicy.current',
  };

  // Conservatively end the snapshot before unknown operations. In particular,
  // signed writes and unsigned scopeObservation.put cannot reuse its material.
  static const _otherReads = {
    'crypto2.access.consequences',
    'crypto2.access.invitationConsequences',
    'crypto2.access.leaveRequests',
    'crypto2.access.leaveStatus',
    'crypto2.access.pending',
    'crypto2.access.portions',
    'crypto2.account.entries',
    'crypto2.account.protectionCatalog',
    'crypto2.account.scopeObservations',
    'crypto2.blob.get',
    'crypto2.domain.checkpoints',
    'crypto2.domain.inventory',
    'crypto2.exports.certificates.get',
    'crypto2.exports.delegation.directory',
    'crypto2.exports.delegation.forOffer',
    'crypto2.exports.delegation.get',
    'crypto2.exports.evidence.directory',
    'crypto2.exports.offers',
    'crypto2.exports.recipient.directory',
    'crypto2.grants.list',
    'crypto2.grants.manifest',
    'crypto2.inbox.list',
    'crypto2.inbox.preferences.get',
    'crypto2.inlineDelete.evidence',
    'crypto2.inlineDelete.graph',
    'crypto2.inlineDelete.preview',
    'crypto2.invitations.acceptance',
    'crypto2.invitations.bridgeDigests',
    'crypto2.invitations.directory',
    'crypto2.invitations.list',
    'crypto2.invitations.pending',
    'crypto2.invitations.preview',
    'crypto2.invitations.resolve',
    'crypto2.invitations.status',
    'crypto2.legacy.lookup',
    'crypto2.migration.activation',
    'crypto2.migration.activation.control',
    'crypto2.migration.activation.refs',
    'crypto2.migration.archiveGet',
    'crypto2.migration.audit.artifact',
    'crypto2.migration.audit.list',
    'crypto2.migration.blob.get',
    'crypto2.migration.capture.commitments',
    'crypto2.migration.capture.discover',
    'crypto2.migration.capture.file',
    'crypto2.migration.capture.fileChunk',
    'crypto2.migration.capture.inventory',
    'crypto2.migration.capture.sourceCell',
    'crypto2.migration.capture.sourcePage',
    'crypto2.migration.capture.sources',
    'crypto2.migration.capture.status',
    'crypto2.migration.capture.topology',
    'crypto2.migration.discover',
    'crypto2.migration.domains.get',
    'crypto2.migration.domains.leaves',
    'crypto2.migration.exportCell',
    'crypto2.migration.exportPage',
    'crypto2.migration.fileChunk',
    'crypto2.migration.fileList',
    'crypto2.migration.generation.status',
    'crypto2.migration.inventory',
    'crypto2.migration.invitations.bridges',
    'crypto2.migration.legacy.inventory',
    'crypto2.migration.legacy.lookup',
    'crypto2.migration.legacy.status',
    'crypto2.migration.notifications.transforms',
    'crypto2.migration.origin',
    'crypto2.migration.ownAttestation',
    'crypto2.migration.stagedRecords',
    'crypto2.migration.status',
    'crypto2.migration.structure.contexts',
    'crypto2.migration.structure.targets',
    'crypto2.moderation.disclosure.status',
    'crypto2.moderation.reportPreview',
    'crypto2.projectRelocation.audit',
    'crypto2.projectRelocation.auditSources',
    'crypto2.projectRelocation.evidence',
    'crypto2.projectRelocation.own',
    'crypto2.projectRelocation.routingOwn',
    'crypto2.projectRelocation.routingUse',
    'crypto2.projectRelocation.status',
    'crypto2.projectRelocation.targetPreview',
    'crypto2.receipt.get',
    'crypto2.records.history',
    'crypto2.records.historyGet',
    'crypto2.records.pull',
    'crypto2.reminders.list',
    'crypto2.scheduling.migrationEvidence',
    'crypto2.scheduling.migrationWithdrawalEvidence',
    'crypto2.scheduling.own',
    'crypto2.scheduling.uses',
    'crypto2.scope.closureGet',
    'crypto2.scope.deletionDirectory',
    'crypto2.scope.deletionHead',
    'crypto2.scope.deletionPreview',
    'crypto2.scope.deletionStatus',
    'crypto2.scope.financeDraft.get',
    'crypto2.scope.financeDraft.list',
    'crypto2.scope.keyDraft.get',
    'crypto2.scope.keyDraft.list',
    'crypto2.scope.lifecycle.children',
    'crypto2.scope.lifecycle.pendingDelegations',
  };

  static String _key(String operation, Map<String, dynamic> params) {
    Object? ordered(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: ordered(value[key])};
      }
      if (value is List) return value.map(ordered).toList();
      return value;
    }

    return jsonEncode([operation, ordered(params)]);
  }

  void close() {
    _active = false;
    _entries.clear();
    _attempted.clear();
  }

  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> params,
  ) async {
    if (!bundledReads.contains(operation) && !_otherReads.contains(operation) ||
        params.containsKey('commandBase64')) {
      close();
      onMutation();
      return read(operation, params);
    }
    if (!bundledReads.contains(operation) ||
        params.containsKey('pendingCapability')) {
      return read(operation, params);
    }
    if (!_active || _unsupported || !await isValid()) {
      _entries.clear();
      return read(operation, params);
    }
    final key = _key(operation, params);
    final previous = _loading;
    if (previous != null) {
      await previous;
      if (!_active || _unsupported || !await isValid()) {
        _entries.clear();
        return read(operation, params);
      }
    }
    if (!_entries.containsKey(key)) {
      final scope = params['scopeId'];
      final selector = scope is String ? scope : '';
      // Exact historical/paginated reads absent from the first bundle fall
      // back to their original endpoint; they do not create retry loops.
      if (!params.containsKey('headHash') &&
          !params.containsKey('directoryHeadHash') &&
          (params['afterGeneration'] ?? 0) == 0 &&
          (params['afterRevision'] ?? 0) == 0 &&
          !params.containsKey('afterId') &&
          !params.containsKey('afterAccountId') &&
          _attempted.add(selector)) {
        final task = _load({
          if (scope is String) 'scopeId': scope,
          'includeChildren': true,
        });
        _loading = task;
        try {
          await task;
        } finally {
          if (identical(_loading, task)) _loading = null;
        }
      }
    }
    if (!_active || !await isValid()) {
      _entries.clear();
      return read(operation, params);
    }
    final entry = _entries[key];
    if (entry == null) return read(operation, params);
    final error = entry['error'];
    if (error is Map) {
      throw CollaborationApiException(
        error['code'] as String,
        details: Map<String, dynamic>.from(error['details'] as Map),
      );
    }
    // Callers may decorate returned maps. Never mutate retained wire material.
    return Map<String, dynamic>.from(
      jsonDecode(jsonEncode(entry['result'])) as Map,
    );
  }

  Future<void> _load(Map<String, dynamic> selector) async {
    if (!_active || _unsupported || !await isValid()) return;
    if (!_capabilityChecked) {
      Map<String, dynamic> capabilities;
      try {
        capabilities = await read('capabilities', {});
      } on CollaborationApiException catch (error) {
        if (error.code != 'unsupported_operation') rethrow;
        _unsupported = true;
        return;
      }
      if (!_active || _unsupported || !await isValid()) return;
      if (capabilities['serverId'] != serverId) {
        throw const FormatException('crypto_authority_snapshot_server');
      }
      _capabilityChecked = true;
      final versions = capabilities['cryptoAuthoritySnapshotVersions'];
      if (versions is! List || !versions.contains(1)) {
        _unsupported = true;
        return;
      }
    }
    Map<String, dynamic> response;
    try {
      final after = await accountAfterGeneration?.call() ?? 0;
      final directoryAfter =
          await directoryAfterGenerations?.call() ?? const <String, int>{};
      if (!_active || !await isValid()) return;
      response = await read('crypto2.authority.snapshot', {
        ...selector,
        'accountAfterGeneration': after,
        if (directoryAfter.isNotEmpty)
          'directoryAfterGenerations': directoryAfter,
      });
    } on CollaborationApiException catch (error) {
      if (!const {
        'unsupported_operation',
        'crypto_authority_snapshot_capacity',
      }.contains(error.code)) {
        rethrow;
      }
      _unsupported = true;
      return;
    }
    if (!_active || !await isValid()) return;
    if (response['version'] != 1 ||
        response['serverId'] != serverId ||
        response['accountId'] != accountId ||
        response['deviceId'] != deviceId ||
        response['entries'] is! List ||
        (response['entries'] as List).length > 512 ||
        utf8.encode(jsonEncode(response)).length > 1280 * 1024) {
      throw const FormatException('crypto_authority_snapshot_identity');
    }
    final staged = <String, Map<String, dynamic>>{};
    for (final raw in response['entries'] as List) {
      if (raw is! Map ||
          !bundledReads.contains(raw['operation']) ||
          raw['params'] is! Map ||
          (raw.containsKey('result') == raw.containsKey('error'))) {
        throw const FormatException('crypto_authority_snapshot_entry');
      }
      final entry = Map<String, dynamic>.from(raw);
      final params = Map<String, dynamic>.from(entry['params'] as Map);
      if (params.containsKey('scopeId') &&
          params['pendingCapability'] != selector['pendingCapability']) {
        throw const FormatException('crypto_authority_snapshot_capability');
      }
      final error = entry['error'];
      if (entry.containsKey('result') && entry['result'] is! Map ||
          entry.containsKey('error') &&
              (error is! Map ||
                  error['code'] is! String ||
                  error['details'] is! Map ||
                  error['status'] is! int)) {
        throw const FormatException('crypto_authority_snapshot_result');
      }
      final key = _key(entry['operation'] as String, params);
      if (staged.containsKey(key)) {
        throw const FormatException('crypto_authority_snapshot_duplicate');
      }
      staged[key] = entry;
    }
    if (_active && await isValid()) {
      _entries.addAll(staged);
      for (final entry in staged.values) {
        if (entry['operation'] == 'crypto2.scope.headGet') {
          _attempted.add((entry['params'] as Map)['scopeId'] as String);
        }
      }
    }
  }
}
