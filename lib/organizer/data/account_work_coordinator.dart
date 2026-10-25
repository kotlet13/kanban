import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../domain/collaboration_models.dart';
import 'collaboration_transport.dart';

enum AccountWorkKind {
  sync,
  account,
  protection,
  invitation,
  foregroundInvitation,
  documents,
  recovery,
  migration,
  scopeManagement,
  cleanup,
  legacyCrypto,
  unspecified,
}

enum AccountWorkPriority { interactive, background }

enum AccountWorkEventKind {
  queued,
  started,
  completed,
  failed,
  shared,
  stale,
  cooldown,
  overloaded,
}

/// This identity is an immutable authority tuple supplied by the repository.
/// It is held only in memory and is never included in diagnostics.
class AccountWorkOwner {
  const AccountWorkOwner({
    required this.serverUrl,
    required this.identity,
    required this.isCurrent,
  });
  final String serverUrl;
  final Object identity;
  final bool Function() isCurrent;
}

class AccountWorkEvent {
  const AccountWorkEvent(
    this.event,
    this.kind,
    this.priority,
    this.operation,
    this.activeReads,
    this.pendingReads,
    this.job,
    this.at,
    this.queueWait,
  );
  final AccountWorkEventKind event;
  final AccountWorkKind kind;
  final AccountWorkPriority priority;
  final String operation;
  final int activeReads, pendingReads;
  final int job;
  final DateTime at;
  final Duration queueWait;
}

class _Job {
  _Job(this.owner, this.kind, this.priority, this.started, this.ordinal);
  final AccountWorkCoordinator owner;
  final AccountWorkKind kind;
  final AccountWorkPriority priority;
  final DateTime started;
  final int ordinal;
}

class _Read {
  _Read(
    this.owner,
    this.job,
    this.operation,
    this.bytes,
    this.send,
    this.queuedAt,
  );
  final AccountWorkOwner owner;
  final _Job job;
  final String operation;
  final int bytes;
  final CollaborationAttempt send;
  final DateTime queuedAt;
  final result = Completer<Map<String, dynamic>>();
}

class _Flight {
  _Flight(
    this.owner,
    this.job,
    this.generation,
    this.started,
    this.bytes,
    this.result,
  );
  final AccountWorkOwner owner;
  final _Job job;
  final int generation, bytes;
  final DateTime started;
  final Future<Map<String, dynamic>> result;
}

/// One account network boundary. Only reads wait; writes/unknown operations
/// dispatch immediately, preserving existing final-guard-to-send sequencing.
/// There is no workflow mutex, proof cache, automatic retry or signed rewrite.
class AccountWorkCoordinator {
  AccountWorkCoordinator({
    DateTime Function()? clock,
    this.maxConcurrentReads = 2,
    this.maxPendingReads = 64,
    this.maxPendingBytes = 512 * 1024,
    this.onEvent,
  }) : clock = clock ?? DateTime.now {
    if (maxConcurrentReads < 1 || maxPendingReads < 1 || maxPendingBytes < 1) {
      throw ArgumentError('account_work_limits');
    }
  }
  final DateTime Function() clock;
  final int maxConcurrentReads, maxPendingReads, maxPendingBytes;
  final void Function(AccountWorkEvent)? onEvent;
  static final _jobZone = Object();
  final _pending = Queue<_Read>();
  final _events = Queue<AccountWorkEvent>();
  final _flights = <String, _Flight>{};
  final _cooldowns = <String, DateTime>{};
  int _activeReads = 0,
      _pendingBytes = 0,
      _generation = 0,
      _interactiveRuns = 0;
  int _jobSequence = 0;
  bool _closed = false;
  List<AccountWorkEvent> get events => List.unmodifiable(_events);

  // Reviewed explicit subset. Unknown endpoints remain immediate barriers,
  // including unsigned writes; names ending in get/status are not inferred.
  static const readOperations = {
    'capabilities',
    'account.changes',
    'account.status',
    'account.email.status',
    'moderation.policyStatus',
    'invitations.preview',
    'scopes.list',
    'scopes.members',
    'crypto2.account.status',
    'crypto2.account.directory',
    'crypto2.account.entries',
    'crypto2.account.protectionCatalog',
    'crypto2.account.scopeObservations',
    'crypto2.authority.snapshot',
    'crypto2.scopes.catalog',
    'crypto2.scope.headGet',
    'crypto2.scope.memberLabels',
    'crypto2.directory.status',
    'crypto2.directory.read',
    'crypto2.scope.lifecycle.baseline',
    'crypto2.scope.lifecycle.current',
    'crypto2.scope.lifecycle.list',
    'crypto2.scope.lifecycle.children',
    'crypto2.scope.lifecycle.pendingDelegations',
    'crypto2.scope.financePolicy.current',
    'crypto2.domain.inventory',
    'crypto2.domain.checkpoints',
    'crypto2.records.pull',
    'crypto2.records.history',
    'crypto2.records.historyGet',
    'crypto2.receipt.get',
    'crypto2.grants.list',
    'crypto2.grants.manifest',
    'crypto2.blob.get',
    'crypto2.scope.recordPolicy.status',
    'crypto2.scope.recordPolicy.baseline',
    'crypto2.invitations.preview',
    'crypto2.invitations.pending',
    'crypto2.invitations.acceptance',
    'crypto2.invitations.status',
    'crypto2.invitations.list',
    'crypto2.invitations.directory',
    'crypto2.invitations.resolve',
    'crypto2.invitations.resolvePreauthorization',
    'crypto2.invitations.bridgeDigests',
    'crypto2.inbox.list',
    'crypto2.inbox.preferences.get',
    'crypto2.reminders.list',
    'crypto2.exports.certificates.get',
    'crypto2.exports.offers',
    'crypto2.exports.recipient.directory',
    'crypto2.exports.delegation.directory',
    'crypto2.exports.delegation.get',
    'crypto2.exports.delegation.forOffer',
    'crypto2.exports.evidence.directory',
    'crypto2.scope.closureGet',
    'crypto2.scope.deletionPreview',
    'crypto2.scope.deletionStatus',
    'crypto2.scope.deletionHead',
    'crypto2.scope.deletionDirectory',
    'crypto2.access.pending',
    'crypto2.access.consequences',
    'crypto2.access.invitationConsequences',
    'crypto2.access.portions',
    'crypto2.access.leaveRequests',
    'crypto2.access.leaveStatus',
    'crypto2.inlineDelete.preview',
    'crypto2.inlineDelete.graph',
    'crypto2.inlineDelete.evidence',
    'crypto2.migration.status',
    'crypto2.migration.inventory',
    'crypto2.migration.discover',
    'crypto2.migration.archiveGet',
    'crypto2.migration.fileList',
    'crypto2.migration.fileChunk',
    'crypto2.migration.stagedRecords',
    'crypto2.migration.blob.get',
    'crypto2.migration.legacy.status',
    'crypto2.migration.legacy.lookup',
    'crypto2.migration.legacy.inventory',
    'crypto2.migration.origin',
    'crypto2.migration.ownAttestation',
    'crypto2.migration.capture.status',
    'crypto2.migration.capture.inventory',
    'crypto2.migration.capture.discover',
    'crypto2.migration.capture.sources',
    'crypto2.migration.capture.sourcePage',
    'crypto2.migration.capture.sourceCell',
    'crypto2.migration.capture.file',
    'crypto2.migration.capture.fileChunk',
    'crypto2.migration.capture.commitments',
    'crypto2.migration.capture.topology',
    'crypto2.migration.exportPage',
    'crypto2.migration.exportCell',
    'crypto2.migration.generation.status',
    'crypto2.migration.structure.targets',
    'crypto2.migration.structure.contexts',
    'crypto2.migration.notifications.transforms',
    'crypto2.migration.invitations.bridges',
  };

  _Job? get _inherited {
    final value = Zone.current[_jobZone];
    return value is _Job && identical(value.owner, this) ? value : null;
  }

  /// Attribution only: no permit is retained across UI, DB, crypto or locks.
  Future<T> withJob<T>(
    AccountWorkKind kind,
    Future<T> Function() body, {
    AccountWorkPriority priority = AccountWorkPriority.interactive,
  }) {
    if (_inherited != null) return body();
    return runZoned(
      body,
      zoneValues: {
        _jobZone: _Job(this, kind, priority, clock(), ++_jobSequence),
      },
    );
  }

  bool _current(AccountWorkOwner owner) => !_closed && owner.isCurrent();
  void _check(AccountWorkOwner owner) {
    if (!_current(owner)) throw const CollaborationException('session_changed');
  }

  void _event(
    AccountWorkEventKind event,
    _Job job,
    String operation, {
    Duration queueWait = Duration.zero,
  }) {
    final safe = RegExp(r'^[a-zA-Z0-9._]{1,96}$').hasMatch(operation)
        ? operation
        : 'unknown';
    final value = AccountWorkEvent(
      event,
      job.kind,
      job.priority,
      safe,
      _activeReads,
      _pending.length,
      job.ordinal,
      clock().toUtc(),
      queueWait,
    );
    if (_events.length == 128) _events.removeFirst();
    _events.add(value);
    try {
      onEvent?.call(value);
    } catch (_) {}
  }

  void _checkCooldown(AccountWorkOwner owner) {
    final until = _cooldowns[owner.serverUrl];
    if (until == null) return;
    final ms = until.difference(clock()).inMilliseconds;
    if (ms <= 0) {
      _cooldowns.remove(owner.serverUrl);
      return;
    }
    throw CollaborationApiException(
      'rate_limited',
      details: {'retryAfter': (ms + 999) ~/ 1000},
    );
  }

  Future<Map<String, dynamic>> runAttempt({
    required AccountWorkOwner owner,
    required String operation,
    required Map<String, Object?> params,
    required CollaborationAttempt send,
  }) {
    final explicitJob = _inherited;
    final job =
        explicitJob ??
        _Job(
          this,
          AccountWorkKind.unspecified,
          AccountWorkPriority.interactive,
          clock(),
          ++_jobSequence,
        );
    try {
      _check(owner);
      _checkCooldown(owner);
    } catch (error, stack) {
      _event(
        error is CollaborationApiException
            ? AccountWorkEventKind.cooldown
            : AccountWorkEventKind.stale,
        job,
        operation,
      );
      return Future.error(error, stack);
    }
    // Signed bodies are barriers even if an endpoint was incorrectly listed.
    final read =
        readOperations.contains(operation) &&
        !params.containsKey('commandBase64');
    if (!read) {
      _generation++;
      _flights.clear();
      return _send(owner, job, operation, send);
    }
    final encoded = jsonEncode(params), bytes = utf8.encode(encoded).length;
    // Only metadata hints within an explicit compatible phase can singleflight.
    // No crypto proof, receipt, completed response or independent phase reuse.
    final share =
        explicitJob != null &&
        const {'capabilities', 'account.changes'}.contains(operation) &&
        clock().difference(job.started) >= Duration.zero &&
        clock().difference(job.started) < const Duration(seconds: 5) &&
        bytes <= maxPendingBytes;
    final key = share ? jsonEncode([operation, _ordered(params)]) : null;
    final previous = key == null ? null : _flights[key];
    if (previous != null &&
        identical(previous.owner.identity, owner.identity) &&
        identical(previous.job, job) &&
        previous.generation == _generation &&
        _current(previous.owner) &&
        clock().difference(previous.started) >= Duration.zero &&
        clock().difference(previous.started) < const Duration(seconds: 5)) {
      _event(AccountWorkEventKind.shared, job, operation);
      return previous.result.then((value) {
        _check(owner);
        return _copy(value);
      });
    }
    if (_pending.length >= maxPendingReads ||
        _pendingBytes + bytes > maxPendingBytes) {
      _event(AccountWorkEventKind.overloaded, job, operation);
      return Future.error(
        const CollaborationApiException(
          'account_work_overloaded',
          details: {'retryAfter': 1},
        ),
      );
    }
    final request = _Read(owner, job, operation, bytes, send, clock());
    _pending.add(request);
    _pendingBytes += bytes;
    _event(AccountWorkEventKind.queued, job, operation);
    if (key != null &&
        _flights.length < 64 &&
        _flights.values.fold<int>(0, (n, f) => n + f.bytes) + bytes <=
            512 * 1024) {
      final flight = _Flight(
        owner,
        job,
        _generation,
        clock(),
        bytes,
        request.result.future,
      );
      _flights[key] = flight;
      // Register both outcomes without an unobserved error-producing future.
      request.result.future.then<void>(
        (_) {
          if (identical(_flights[key], flight)) _flights.remove(key);
        },
        onError: (Object _, StackTrace __) {
          if (identical(_flights[key], flight)) _flights.remove(key);
        },
      );
    }
    _drain();
    return key == null
        ? request.result.future
        : request.result.future.then(_copy);
  }

  static Object? _ordered(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _ordered(value[key])};
    }
    if (value is List) return value.map(_ordered).toList();
    return value;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  _Read _next() {
    final interactive = _pending
        .where((r) => r.job.priority == AccountWorkPriority.interactive)
        .firstOrNull;
    final background = _pending
        .where((r) => r.job.priority == AccountWorkPriority.background)
        .firstOrNull;
    final next =
        interactive != null && (_interactiveRuns < 3 || background == null)
        ? interactive
        : background ?? interactive!;
    _interactiveRuns = next.job.priority == AccountWorkPriority.interactive
        ? _interactiveRuns + 1
        : 0;
    _pending.remove(next);
    _pendingBytes -= next.bytes;
    return next;
  }

  void _drain() {
    while (_activeReads < maxConcurrentReads && _pending.isNotEmpty) {
      final request = _next();
      _activeReads++;
      _send(
            request.owner,
            request.job,
            request.operation,
            request.send,
            queuedAt: request.queuedAt,
          )
          .then(
            (value) {
              request.result.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              request.result.completeError(error, stack);
            },
          )
          .whenComplete(() {
            _activeReads--;
            _drain();
          });
    }
  }

  Future<Map<String, dynamic>> _send(
    AccountWorkOwner owner,
    _Job job,
    String operation,
    CollaborationAttempt send, {
    DateTime? queuedAt,
  }) async {
    // A locally rejected cooldown must never extend the observed server limit.
    try {
      _check(owner);
      _checkCooldown(owner);
    } catch (error) {
      _event(
        error is CollaborationApiException
            ? AccountWorkEventKind.cooldown
            : AccountWorkEventKind.stale,
        job,
        operation,
      );
      rethrow;
    }
    try {
      _event(
        AccountWorkEventKind.started,
        job,
        operation,
        queueWait: queuedAt == null
            ? Duration.zero
            : clock().difference(queuedAt),
      );
      final reply = await send();
      _check(owner);
      _event(AccountWorkEventKind.completed, job, operation);
      return reply;
    } catch (error) {
      if (error is CollaborationApiException && error.code == 'rate_limited') {
        final retry = error.details['retryAfter'];
        final seconds = retry is int && retry >= 1 && retry <= 86400
            ? retry
            : 15;
        final until = clock().add(Duration(seconds: seconds));
        if (_cooldowns.length == 16 &&
            !_cooldowns.containsKey(owner.serverUrl)) {
          _cooldowns.remove(_cooldowns.keys.first);
        }
        if (_cooldowns[owner.serverUrl] == null ||
            until.isAfter(_cooldowns[owner.serverUrl]!)) {
          _cooldowns[owner.serverUrl] = until;
        }
      }
      _event(AccountWorkEventKind.failed, job, operation);
      rethrow;
    }
  }

  void cancelStale() {
    for (final request in _pending.toList()) {
      if (_current(request.owner)) continue;
      _pending.remove(request);
      _pendingBytes -= request.bytes;
      request.result.completeError(
        const CollaborationException('session_changed'),
      );
      _event(AccountWorkEventKind.stale, request.job, request.operation);
    }
    _flights.removeWhere((_, flight) => !_current(flight.owner));
  }

  void close() {
    _closed = true;
    _generation++;
    cancelStale();
  }
}

typedef AccountWorkOwnerResolver =
    AccountWorkOwner Function(
      String serverUrl,
      String? token,
      String operation,
      bool allowLocalHttp,
    );

class CoordinatedCollaborationTransport implements CollaborationTransport {
  CoordinatedCollaborationTransport({
    required this.inner,
    required this.coordinator,
    required this.ownerFor,
  });
  final CollaborationTransport inner;
  final AccountWorkCoordinator coordinator;
  final AccountWorkOwnerResolver ownerFor;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) {
    final owner = ownerFor(serverUrl, token, operation, allowLocalHttp);
    // Snapshot parameters before waiting, retaining opaque signed bytes exactly.
    final frozen = jsonDecode(jsonEncode(params)) as Map<String, dynamic>;
    Future<Map<String, dynamic>> gate(CollaborationAttempt send) =>
        coordinator.runAttempt(
          owner: owner,
          operation: operation,
          params: frozen,
          send: send,
        );
    final delegate = inner;
    if (delegate is CollaborationSingleAttemptTransport) {
      return (delegate as CollaborationSingleAttemptTransport)
          .callWithAttemptGate(
            serverUrl: serverUrl,
            operation: operation,
            params: frozen,
            token: token,
            allowLocalHttp: allowLocalHttp,
            gate: gate,
          );
    }
    return gate(
      () => delegate.call(
        serverUrl: serverUrl,
        operation: operation,
        params: frozen,
        token: token,
        allowLocalHttp: allowLocalHttp,
      ),
    );
  }

  @override
  void close() {
    coordinator.close();
    inner.close();
  }
}

Future<T> withAccountWorkJob<T>(
  CollaborationTransport transport,
  AccountWorkKind kind,
  Future<T> Function() body, {
  AccountWorkPriority priority = AccountWorkPriority.interactive,
}) => transport is CoordinatedCollaborationTransport
    ? transport.coordinator.withJob(kind, body, priority: priority)
    : body();
