import '../account_work_coordinator.dart';
import 'crypto_migration_generation.dart';
import 'crypto_migration_structure_workflow.dart';
import 'crypto_legacy_upload_drain.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../collaboration_transport.dart';
import '../../domain/shared_payload_validation.dart' show isSharedUuid;
import 'account_crypto_v2_workflow.dart';
import 'crypto_sync_repository.dart';
import 'crypto_sync_store.dart';
import 'session_crypto_access.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_capture_keys.dart';
import 'crypto_archive_cold_database.dart';
import 'crypto_migration_pipeline.dart';
import 'crypto_migration_pending_work.dart';
import 'crypto_business_router.dart';

class CryptoMigrationCandidate {
  const CryptoMigrationCandidate({
    required this.scopeId,
    required this.kind,
    required this.role,
    required this.accessRevision,
    this.parentScopeId,
    this.cryptoState,
    this.headHash,
    this.cryptoOrigin = false,
  });
  final String scopeId, kind, role;
  final int accessRevision;
  final String? parentScopeId, cryptoState, headHash;
  final bool cryptoOrigin;
}

class CryptoMigrationInventoryReview {
  const CryptoMigrationInventoryReview({
    required this.inventoryHash,
    required this.tableCount,
    required this.rowCount,
    required this.fileCount,
    required this.fileBytes,
    required this.pendingContributionCount,
    required this.unavailableContributionCount,
  });
  final String inventoryHash;
  final int tableCount,
      rowCount,
      fileCount,
      fileBytes,
      pendingContributionCount,
      unavailableContributionCount;
}

enum CryptoMigrationPhase {
  discovery,
  preparing,
  waitingContributors,
  archiving,
  verifying,
  ready,
  committed,
  unavailable,
  blocked,
}

/// Immutable UI state. Unknown server responses never mark committed or hide
/// existing local data. Only explicit signed receipts advance local authority.
class CryptoMigrationState {
  const CryptoMigrationState({
    required this.scopeId,
    required this.phase,
    this.migrationId,
    this.componentId,
    this.pendingContributionCount = 0,
    this.unavailableContributionCount = 0,
    this.progress = 0,
    this.canContinue = false,
    this.errorCode,
    this.retryAfterSeconds,
    this.legacyCleanupPending = false,
  });
  final String scopeId;
  final String? migrationId, componentId, errorCode;
  final CryptoMigrationPhase phase;
  final int pendingContributionCount, unavailableContributionCount;
  final double progress;
  final bool canContinue;
  final int? retryAfterSeconds;
  final bool legacyCleanupPending;
  bool get localDataAvailable => true;
}

/// Resumable account-bound migration controller. Raw archives and their proof
/// are distinct from domain projection; neither old outboxes nor source rows
/// are deleted by preparation, fencing or a lost response.
class CryptoMigrationCoordinator {
  CryptoMigrationCoordinator({required this.account, this.coldDatabase})
    : access = SessionCryptoAccess(account: account);
  final Future<CryptoArchiveColdDatabase> Function()? coldDatabase;
  final AccountCryptoV2Workflow account;
  final SessionCryptoAccess access;
  final _changes = StreamController<CryptoMigrationState>.broadcast();
  final _stopped = Completer<void>();
  Stream<CryptoMigrationState> get changes => _changes.stream;
  Future<void> close() {
    if (!_stopped.isCompleted) _stopped.complete();
    return _changes.close();
  }

  String get _partition => account.store.partition;
  CryptoSyncStore get _store =>
      CryptoSyncStore(account.store.database, _partition);
  CryptoSyncRepository get _queue => CryptoSyncRepository(
    crypto: account.directory.reducer.crypto,
    session: account.directory.session,
    transport: account.directory.transport,
    store: _store,
    signingKey: access.signingKey,
    authorKey: access.recordAuthority,
    contentKey: access.recordKey,
    readContext: access.readContext,
    project: (_) async {
      throw const CryptoProjectionPending();
    },
    isCurrent: account.directory.isCurrent,
    beforeDelivery: access.beforeDelivery,
  );

  void _current() {
    if (_stopped.isCompleted ||
        !account.directory.isCurrent() ||
        account.directory.session.profile.partition != _partition) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
  }

  CryptoMigrationState _emit(CryptoMigrationState value) {
    if (!_changes.isClosed) _changes.add(value);
    return value;
  }

  Future<void> _journal(String scopeId, Map<String, dynamic> value) async {
    _current();
    await account.store.database.execute(
      'INSERT INTO crypto_migrations(partition,id,state,journal) VALUES(?,?,?,?) ON CONFLICT(partition,id) DO UPDATE SET state=excluded.state,journal=excluded.journal',
      [_partition, scopeId, value['phase'] ?? 'preparing', jsonEncode(value)],
    );
  }

  Future<Map<String, dynamic>?> _local(String scopeId) async {
    final rows = await account.store.database.rows(
      'SELECT journal FROM crypto_migrations WHERE partition=? AND id=?',
      [_partition, scopeId],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['journal'] as String) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _command(
    String action,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final queue = _queue;
    final id = await queue.enqueueCommand(
      actionKey: 'migration:$action',
      operation: operation,
      payload: payload,
    );
    await queue.resumeUnresolved(requestIds: {id});
    return queue.commandResult(id);
  }

  Future<List<CryptoMigrationCandidate>> discoverAvailable() =>
      withAccountWorkJob(
        account.directory.transport,
        AccountWorkKind.migration,
        () => _accountWorkDiscoverAvailable(),
      );

  Future<List<CryptoMigrationCandidate>> _accountWorkDiscoverAvailable() async {
    _current();
    final result = <CryptoMigrationCandidate>[];
    String? after;
    final seen = <String>{};
    do {
      final page = await account.directory.call('crypto2.scopes.catalog', {
        'limit': 50,
        if (after != null) 'afterId': after,
      });
      _current();
      if (page['scopes'] is! List ||
          page['scopes'].length > 50 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_catalog_shape');
      }
      String? last;
      for (final value in page['scopes'] as List) {
        if (value is! Map ||
            !isSharedUuid(value['id']) ||
            value['kind'] is! String ||
            value['role'] is! String ||
            value['accessRevision'] is! int ||
            value['accessRevision'] < 0 ||
            seen.length >= 100000 ||
            after != null && after.compareTo(value['id']) >= 0 ||
            !seen.add(value['id'] as String)) {
          throw const FormatException('crypto_catalog_shape');
        }
        if (last != null && last.compareTo(value['id']) >= 0) {
          throw const FormatException('crypto_catalog_cursor');
        }
        last = value['id'];
        result.add(
          CryptoMigrationCandidate(
            scopeId: value['id'],
            kind: value['kind'],
            role: value['role'],
            accessRevision: value['accessRevision'],
            parentScopeId: value['parentScopeId'] as String?,
            cryptoState: value['cryptoState'] as String?,
            headHash: value['headHash'] as String?,
            cryptoOrigin: value['cryptoOrigin'] == true,
          ),
        );
      }
      if (page['hasMore'] != true) break;
      final next = page['nextAfterId'];
      if (!isSharedUuid(next) || next != last || page['scopes'].isEmpty) {
        throw const FormatException('crypto_catalog_cursor');
      }
      after = next as String;
    } while (true);
    return List.unmodifiable(result);
  }

  /// Catalog values route discovery only. Both new-origin and migrated scopes
  /// must pass the normal signed-head/descriptor verifier before UI readiness.
  /// Migrated descriptors require the final scoped publication and all links;
  /// a local journal or an unsigned server committed bit is never sufficient.
  Future<CryptoMigrationState?> _published(String scopeId) async {
    final candidates = await discoverAvailable();
    final matches = candidates.where((c) => c.scopeId == scopeId).toList();
    if (matches.length != 1) {
      throw const CryptoAuthorityPending('crypto_migration_scope_unavailable');
    }
    final candidate = matches.single;
    if (candidate.headHash == null ||
        !['active', 'committed', 'retired'].contains(candidate.cryptoState)) {
      return null;
    }
    final head = await access.currentHead(scopeId, online: true);
    if (head.headHash != candidate.headHash ||
        head.accessRevision != candidate.accessRevision) {
      throw const CryptoAuthorityPending('crypto_catalog_changed');
    }
    _current();
    final migration = await access.recoveredMigrationGenesis(scopeId);
    return _emit(
      CryptoMigrationState(
        scopeId: scopeId,
        migrationId: migration?.migrationId,
        phase: CryptoMigrationPhase.committed,
        progress: 1,
        legacyCleanupPending: migration != null,
      ),
    );
  }

  Future<CryptoMigrationState> inspect(String scopeId) => withAccountWorkJob(
    account.directory.transport,
    AccountWorkKind.migration,
    () => _accountWorkInspect(scopeId),
  );

  Future<CryptoMigrationState> _accountWorkInspect(String scopeId) async {
    if (!isSharedUuid(scopeId)) {
      throw const FormatException('crypto_migration_scope');
    }
    final published = await _published(scopeId);
    if (published != null) return published;
    final local = await _local(scopeId);
    if (local?['migrationId'] is String) {
      return resume(local!['migrationId'] as String);
    }
    final found = await account.directory.call(
      'crypto2.migration.capture.discover',
      {'scopeId': scopeId},
    );
    _validateDiscovery(found);
    await _journal(scopeId, {
      'version': 3,
      'phase': 'discovery',
      'componentId': found['componentId'],
      'discovery': found,
    });
    return _emit(
      CryptoMigrationState(
        scopeId: scopeId,
        phase: CryptoMigrationPhase.discovery,
        componentId: found['componentId'],
        canContinue: true,
      ),
    );
  }

  void _validateDiscovery(Map<String, dynamic> found) {
    if (found['captureVersion'] != 3 ||
        !isSharedUuid(found['componentId']) ||
        found['ownedScopeIds'] is! List ||
        (found['ownedScopeIds'] as List).any((id) => !isSharedUuid(id)) ||
        found['receiptSelections'] is! List) {
      throw const FormatException('crypto_capture_discovery');
    }
  }

  Future<CryptoCaptureKeyDescriptor> _capture(String migrationId) async {
    final rows = await account.store.database.rows(
      'SELECT journal FROM crypto_capture_runs WHERE partition=? AND migration_id=?',
      [_partition, migrationId],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_capture_original_context_required',
      );
    }
    final value = CryptoCaptureKeyDescriptor.fromJson(
      jsonDecode(rows.single['journal'] as String) as Map,
    );
    if (value.migrationId != migrationId) {
      throw const FormatException('crypto_capture_context');
    }
    return value;
  }

  Future<CryptoMigrationState> prepare(String scopeId) =>
      _limited(scopeId, () => _prepare(scopeId));

  Future<CryptoMigrationState> _prepare(String scopeId) async {
    final published = await _published(scopeId);
    if (published != null) return published;
    try {
      await CryptoLegacyUploadDrain.beforeCapture(
        account.store.database,
        account.directory.session,
        scopeId,
        account.store.secure,
      );
    } on CryptoAuthorityPending catch (error) {
      if (error.reason != 'crypto_migration_pending_upload') rethrow;
      return _emit(
        CryptoMigrationState(
          scopeId: scopeId,
          phase: CryptoMigrationPhase.blocked,
          errorCode: error.reason,
          canContinue: true,
        ),
      );
    }
    final capture = await CryptoCaptureCoordinator(account).prepare(scopeId);
    await _journal(scopeId, {
      'version': 3,
      'phase': 'preparing',
      'migrationId': capture.migrationId,
      'componentId': capture.componentId,
      'capture': capture.toJson(),
    });
    return resume(capture.migrationId);
  }

  Future<CryptoMigrationState> retryPending(String migrationId) async {
    _current();
    // Each typed producer retries only its own immutable action, including any
    // private capture sidecar. Do not deliver arbitrary unrelated user queues.
    return resume(migrationId);
  }

  Future<CryptoMigrationState> resume(String migrationId) => withAccountWorkJob(
    account.directory.transport,
    AccountWorkKind.migration,
    () => _accountWorkResume(migrationId),
  );

  Future<CryptoMigrationState> _accountWorkResume(String migrationId) async {
    if (!isSharedUuid(migrationId)) {
      throw const FormatException('crypto_migration_id');
    }
    final rows = await account.store.database.rows(
      "SELECT id,journal FROM crypto_migrations WHERE partition=? AND json_extract(journal,'\$.migrationId')=?",
      [_partition, migrationId],
    );
    final status = await account.directory.call('crypto2.migration.status', {
      'migrationId': migrationId,
    });
    if (status['migrationId'] != migrationId ||
        !isSharedUuid(status['componentId']) ||
        status['pendingContributionCount'] is! int ||
        status['pendingContributionCount'] < 0) {
      throw const FormatException('crypto_migration_status');
    }
    late String scopeId;
    Map<String, dynamic> local = {};
    if (rows.length == 1) {
      scopeId = rows.single['id'] as String;
      local = Map<String, dynamic>.from(
        jsonDecode(rows.single['journal'] as String),
      );
      if (local['componentId'] != status['componentId']) {
        throw const FormatException('crypto_migration_status');
      }
    } else if (rows.isEmpty &&
        status['scopeIds'] is List &&
        (status['scopeIds'] as List).isNotEmpty &&
        isSharedUuid(status['scopeIds'][0])) {
      scopeId = status['scopeIds'][0];
    } else {
      throw const CryptoAuthorityPending(
        'crypto_capture_original_context_required',
      );
    }
    if (['committed', 'retired'].contains(status['state'])) {
      final published = await _published(scopeId);
      if (published != null) return published;
      throw const CryptoAuthorityPending('crypto_migration_provenance_pending');
    }
    final unavailable = status['unavailableContributionCount'];
    if (unavailable is! int || unavailable < 0) {
      throw const FormatException('crypto_migration_status');
    }
    final phase = status['state'] == 'aborted'
        ? CryptoMigrationPhase.blocked
        : status['ownState'] == 'unavailable'
        ? CryptoMigrationPhase.unavailable
        : status['state'] == 'verified'
        ? CryptoMigrationPhase.verifying
        : status['state'] == 'fenced'
        ? CryptoMigrationPhase.archiving
        : status['ownState'] == 'fenced'
        ? CryptoMigrationPhase.waitingContributors
        : CryptoMigrationPhase.preparing;
    await _journal(scopeId, {
      ...local,
      'version': 3,
      'phase': phase.name,
      'componentId': status['componentId'],
      'migrationId': migrationId,
      'status': status,
    });
    return _emit(
      CryptoMigrationState(
        scopeId: scopeId,
        migrationId: migrationId,
        componentId: status['componentId'],
        phase: phase,
        pendingContributionCount: status['pendingContributionCount'],
        unavailableContributionCount: unavailable,
        errorCode: status['state'] == 'aborted'
            ? 'crypto_migration_aborted'
            : null,
        canContinue: [
          CryptoMigrationPhase.preparing,
          CryptoMigrationPhase.archiving,
          CryptoMigrationPhase.verifying,
        ].contains(phase),
      ),
    );
  }

  Future<CryptoMigrationInventoryReview> review(String migrationId) async {
    final capture = await _capture(migrationId);
    return _limited(capture.rootScopeId, () => _review(migrationId));
  }

  Future<CryptoMigrationInventoryReview> _review(String migrationId) async {
    final capture = await _capture(migrationId);
    final sealed = await CryptoCaptureCoordinator(
      account,
    ).captureSources(capture);
    final tables = <String>{};
    var count = 0, files = 0, bytes = 0;
    var after = '';
    while (true) {
      final rows = await account.store.database.rows(
        'SELECT binding_id,context,typed_row FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? ORDER BY binding_id LIMIT 1',
        [_partition, capture.captureId, after],
      );
      if (rows.isEmpty) break;
      final row = rows.single;
      after = row['binding_id'] as String;
      final context = jsonDecode(row['context'] as String) as Map;
      final table = context['sourceTable'] as String;
      tables.add(table);
      count++;
      if (['familyhub_attachments', 'familyhub_idea_assets'].contains(table)) {
        final typed = jsonDecode(row['typed_row'] as String) as Map;
        final cell = typed['size_bytes'] ?? typed['byte_size'] ?? typed['size'];
        final value = cell is Map ? cell['valueBase64'] : null;
        final size = value is String
            ? int.tryParse(utf8.decode(base64Decode(value)))
            : null;
        if (size == null || size < 0) {
          throw const FormatException('crypto_migration_file_size');
        }
        files++;
        bytes += size;
      }
    }
    if (count != sealed['sourceCount']) {
      throw const FormatException('crypto_capture_source_incomplete');
    }
    final local = (await _local(capture.rootScopeId)) ?? {};
    await _journal(capture.rootScopeId, {
      ...local,
      'reviewedRoot': sealed['inventoryRoot'],
    });
    final state = await resume(migrationId);
    return CryptoMigrationInventoryReview(
      inventoryHash: sealed['inventoryRoot'],
      tableCount: tables.length,
      rowCount: count,
      fileCount: files,
      fileBytes: bytes,
      pendingContributionCount: state.pendingContributionCount,
      unavailableContributionCount: state.unavailableContributionCount,
    );
  }

  Future<CryptoMigrationState> fence(
    String migrationId, {
    required String reviewedInventoryHash,
  }) async {
    final capture = await _capture(migrationId);
    return _limited(
      capture.rootScopeId,
      () => _fence(migrationId, reviewedInventoryHash: reviewedInventoryHash),
    );
  }

  Future<CryptoMigrationState> _fence(
    String migrationId, {
    required String reviewedInventoryHash,
  }) async {
    final capture = await _capture(migrationId);
    final local = await _local(capture.rootScopeId);
    if (local?['reviewedRoot'] != reviewedInventoryHash) {
      throw const CryptoAuthorityPending('crypto_capture_review_required');
    }
    await CryptoMigrationPendingWork(
      CryptoBusinessSession(account, access, account.store.database),
    ).drain(capture);
    await CryptoCaptureCoordinator(
      account,
    ).fence(capture, reviewedInventoryRoot: reviewedInventoryHash);
    return resume(migrationId);
  }

  Future<CryptoMigrationState> archiveAndVerify(
    String migrationId, {
    required Uint8List recoveryFile,
    bool acceptedRemoteDateDisclosure = false,
    CryptoMigrationStructureReviewer? reviewStructure,
  }) async {
    final capture = await _capture(migrationId);
    try {
      return await _limited(
        capture.rootScopeId,
        () => _archiveAndVerify(
          migrationId,
          recoveryFile: recoveryFile,
          acceptedRemoteDateDisclosure: acceptedRemoteDateDisclosure,
          reviewStructure: reviewStructure,
        ),
      );
    } on CryptoAuthorityPending catch (error) {
      if (!const {
        'crypto_account_choices_capture_review_pending',
        'crypto_account_choices_capture_companion_pending',
        'crypto_account_choices_manager_review_required',
        'crypto_account_choices_request_pending',
        'crypto_account_choices_recipient_pending',
        'crypto_structure_context_contributors_pending',
        'crypto_migration_dependencies_pending',
      }.contains(error.reason)) {
        rethrow;
      }
      final local = (await _local(capture.rootScopeId)) ?? {};
      await _journal(capture.rootScopeId, {
        ...local,
        'phase': CryptoMigrationPhase.waitingContributors.name,
        'errorCode': error.reason,
      });
      return _emit(
        CryptoMigrationState(
          scopeId: capture.rootScopeId,
          migrationId: migrationId,
          componentId: capture.componentId,
          phase: CryptoMigrationPhase.waitingContributors,
          pendingContributionCount: 1,
          canContinue: true,
          errorCode: error.reason,
        ),
      );
    }
  }

  Future<bool> requiresRemoteDateDisclosure(String migrationId) async {
    final capture = await _capture(migrationId);
    return (await account.store.database.rows(
      "SELECT 1 FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND json_extract(context,'\$.sourceTable')='familyhub_reminders' LIMIT 1",
      [_partition, capture.captureId],
    )).isNotEmpty;
  }

  Future<CryptoMigrationState> _archiveAndVerify(
    String migrationId, {
    required Uint8List recoveryFile,
    required bool acceptedRemoteDateDisclosure,
    CryptoMigrationStructureReviewer? reviewStructure,
  }) async {
    final state = await resume(migrationId);
    if (![
      CryptoMigrationPhase.archiving,
      CryptoMigrationPhase.verifying,
    ].contains(state.phase)) {
      throw const CryptoAuthorityPending(
        'crypto_migration_contributors_pending',
      );
    }
    final capture = await _capture(migrationId);
    await CryptoMigrationPipeline(
      account,
      coldDatabase: coldDatabase,
      reviewStructure: reviewStructure,
      progress: (phase) async {
        final local = (await _local(capture.rootScopeId)) ?? {};
        await _journal(capture.rootScopeId, {...local, 'step': phase});
        _emit(
          CryptoMigrationState(
            scopeId: capture.rootScopeId,
            migrationId: migrationId,
            componentId: capture.componentId,
            phase: CryptoMigrationPhase.verifying,
          ),
        );
      },
    ).run(
      capture: capture,
      recoveryFile: recoveryFile,
      // Existing date disclosure needs its separate explicit review; the
      // ordinary migration consent does not silently authorize new disclosure.
      acceptedRemoteDateDisclosure: acceptedRemoteDateDisclosure,
    );
    return inspect(capture.rootScopeId);
  }

  /// Server throttling is a durable pause, not a reason to replace signed
  /// requests. A restart observes the saved deadline before any next HTTP.
  /// The caller may leave the wizard immediately and resume with the same FILE.
  Future<T> _limited<T>(String scopeId, Future<T> Function() action) =>
      withAccountWorkJob(
        account.directory.transport,
        AccountWorkKind.migration,
        () => _accountWorkLimited(scopeId, action),
      );

  Future<T> _accountWorkLimited<T>(
    String scopeId,
    Future<T> Function() action,
  ) async {
    final local = await _local(scopeId);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final notBefore = local?['retryNotBefore'];
    if (notBefore is int && notBefore > now) {
      final remaining = notBefore - now;
      if (remaining > 60) {
        throw const CryptoAuthorityPending('crypto_migration_retry_deadline');
      }
      await _pause(scopeId, remaining);
    }
    try {
      return await withCollaborationRateLimitPause(
        action,
        pause: (seconds) => _pause(scopeId, seconds),
      );
    } on CollaborationApiException catch (error) {
      final retry = error.details['retryAfter'];
      if (error.code != 'rate_limited' ||
          retry is! int ||
          retry < 1 ||
          retry > 60) {
        rethrow;
      }
      final current = (await _local(scopeId)) ?? <String, dynamic>{};
      await _journal(scopeId, {
        ...current,
        'retryNotBefore': DateTime.now().millisecondsSinceEpoch ~/ 1000 + retry,
        'errorCode': 'crypto_migration_rate_limited',
      });
      final phase = CryptoMigrationPhase.values.firstWhere(
        (p) => p.name == current['phase'],
        orElse: () => CryptoMigrationPhase.preparing,
      );
      _emit(
        CryptoMigrationState(
          scopeId: scopeId,
          migrationId: current['migrationId'],
          componentId: current['componentId'],
          phase: phase,
          canContinue: true,
          errorCode: 'crypto_migration_rate_limited',
          retryAfterSeconds: retry,
        ),
      );
      rethrow;
    }
  }

  Future<void> _pause(String scopeId, int seconds) async {
    _current();
    access.invalidateAuthorityOperation();
    final local = (await _local(scopeId)) ?? <String, dynamic>{};
    final phase = CryptoMigrationPhase.values.firstWhere(
      (p) => p.name == local['phase'],
      orElse: () => CryptoMigrationPhase.preparing,
    );
    await _journal(scopeId, {
      ...local,
      'retryNotBefore': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds,
      'ratePauseCount': (local['ratePauseCount'] as int? ?? 0) + 1,
      'errorCode': 'crypto_migration_rate_limited',
    });
    _emit(
      CryptoMigrationState(
        scopeId: scopeId,
        migrationId: local['migrationId'],
        componentId: local['componentId'],
        phase: phase,
        errorCode: 'crypto_migration_rate_limited',
        retryAfterSeconds: seconds,
      ),
    );
    final elapsed = Completer<void>();
    final timer = Timer(Duration(seconds: seconds), elapsed.complete);
    try {
      await Future.any([elapsed.future, _stopped.future]);
    } finally {
      timer.cancel();
    }
    _current();
    access.invalidateAuthorityOperation();
    final current = (await _local(scopeId)) ?? local;
    await _journal(scopeId, {
      ...current,
      'retryNotBefore': null,
      'errorCode': null,
    });
  }

  CryptoMigrationGeneration get generation => CryptoMigrationGeneration(
    CryptoBusinessSession(account, access, account.store.database),
  );

  /// Moves only local discovery pointers after the exact atomic A receipt.
  /// The complete old capture row/journal remain an immutable retained record.
  Future<CryptoMigrationState> adoptGenerationSuccessor({
    required String scopeId,
    required String generationId,
  }) async {
    final result = await generation.status(generationId);
    final context = Map<String, dynamic>.from(result['context'] as Map);
    final newId = context['newMigrationId'];
    if (result['state'] != 'superseded' || !isSharedUuid(newId)) {
      throw const CryptoAuthorityPending(
        'crypto_migration_generation_not_superseded',
      );
    }
    final migrationId = context['migrationId'];
    final receipt = await generation.finish(
      generationId,
      result['contextHash'],
    );
    if (receipt['state'] != 'superseded' || receipt['migrationId'] != newId) {
      throw const FormatException('crypto_migration_generation_receipt');
    }
    await account.store.database.transaction(() async {
      final db = account.store.database;
      final rows = await db.rows(
        'SELECT * FROM crypto_capture_runs WHERE partition=? AND root_scope_id=?',
        [_partition, scopeId],
      );
      if (rows.isNotEmpty &&
          rows.single['migration_id'] != migrationId &&
          rows.single['migration_id'] != newId) {
        throw const FormatException(
          'crypto_migration_generation_local_context',
        );
      }
      final name =
          'migration_superseded_generation:$_partition:$generationId:$scopeId';
      final old = await db.rows('SELECT value FROM local_meta WHERE name=?', [
        name,
      ]);
      if (old.isEmpty) {
        await db.execute('INSERT INTO local_meta VALUES(?,?)', [
          name,
          jsonEncode({
            'journal': await _local(scopeId),
            'captureRun': rows.isEmpty ? null : rows.single,
            'receipt': receipt,
          }),
        ]);
      }
      await db.execute(
        'DELETE FROM crypto_capture_runs WHERE partition=? AND root_scope_id=? AND migration_id=?',
        [_partition, scopeId, migrationId],
      );
      final key = 'migration_generation_successor:$_partition:$newId';
      final mapping = await db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      );
      if (mapping.isEmpty) {
        await db.execute('INSERT INTO local_meta VALUES(?,?)', [
          key,
          generationId,
        ]);
      } else if (mapping.single['value'] != generationId) {
        throw const FormatException('crypto_migration_generation_immutable');
      }
      await _journal(scopeId, {
        'version': 3,
        'phase': 'discovery',
        'predecessorMigrationId': migrationId,
        'generationId': generationId,
      });
    });
    return prepare(scopeId);
  }

  Future<CryptoMigrationState> abort(String migrationId) async {
    final state = await resume(migrationId);
    final result = await _command(
      'abort:$migrationId',
      'crypto2.migration.abort',
      {'migrationId': migrationId},
    );
    if (result['state'] != 'aborted' || result['legacyPreserved'] != true) {
      throw const FormatException('crypto_migration_abort_ack');
    }
    final local = (await _local(state.scopeId))!;
    await _journal(state.scopeId, {
      ...local,
      'phase': 'blocked',
      'aborted': true,
      'abortReceipt': result,
    });
    return _emit(
      CryptoMigrationState(
        scopeId: state.scopeId,
        migrationId: migrationId,
        componentId: state.componentId,
        phase: CryptoMigrationPhase.blocked,
        errorCode: 'crypto_migration_aborted',
      ),
    );
  }

  /// Explicitly begin another attempt after the exact safe abort receipt.
  /// Old requests, keys, source rows and encrypted stage are never rewritten.
  Future<CryptoMigrationState> replan(
    String scopeId,
  ) => _limited(scopeId, () async {
    final local = await _local(scopeId);
    if (local == null ||
        local['aborted'] != true ||
        local['migrationId'] is! String) {
      throw const CryptoAuthorityPending('crypto_migration_abort_required');
    }
    final migrationId = local['migrationId'] as String;
    // Receipt-first lookup uses the immutable original signed abort.
    await abort(migrationId);
    final db = account.store.database;
    await db.transaction(() async {
      final latest = (await _local(scopeId))!;
      final rows = await db.rows(
        'SELECT * FROM crypto_capture_runs WHERE partition=? AND root_scope_id=?',
        [_partition, scopeId],
      );
      final evidence = {
        'journal': latest,
        'captureRun': rows.isEmpty ? null : rows.single,
      };
      final name = 'migration_aborted_generation:$_partition:$migrationId';
      final prior = await db.rows('SELECT value FROM local_meta WHERE name=?', [
        name,
      ]);
      final encoded = jsonEncode(evidence);
      if (prior.isEmpty) {
        await db.execute('INSERT INTO local_meta VALUES(?,?)', [name, encoded]);
      } else if (prior.single['value'] != encoded) {
        throw const FormatException(
          'crypto_migration_aborted_evidence_changed',
        );
      }
      if (rows.isNotEmpty && rows.single['migration_id'] != migrationId) {
        throw const CryptoAuthorityPending(
          'crypto_capture_generation_conflict',
        );
      }
      // Only the active lookup pointer moves. Its complete original row is
      // retained above; capture keys/sources/commands remain immutable.
      await db.execute(
        'DELETE FROM crypto_capture_runs WHERE partition=? AND root_scope_id=? AND migration_id=?',
        [_partition, scopeId, migrationId],
      );
      await _journal(scopeId, {
        'version': 3,
        'phase': 'discovery',
        'predecessorMigrationId': migrationId,
      });
    });
    return _prepare(scopeId);
  });
}
