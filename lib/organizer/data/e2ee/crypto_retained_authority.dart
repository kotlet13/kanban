import 'dart:convert';

import '../authority_reuse_controller.dart';
import 'crypto_json.dart';

/// Exact transport evidence from a fully admitted live head. Every consumer
/// still replays its ordinary signatures, ancestry and local secure floors.
class CryptoAuthorityWireRead {
  CryptoAuthorityWireRead(this.operation, this.params, this.result, this.token);
  final String operation;
  final Map<String, dynamic> params, result;
  final Object token;
}

class _ScopeEvidence {
  _ScopeEvidence(
    this.token,
    this.floor,
    this.directories,
    this.reads,
    this.bytes,
  );
  final Object token;
  final String floor;
  final Map<String, String> directories;
  final Map<String, String> reads;
  final int bytes;
}

/// Process memory only; no keys, mutable inventories, receipts or projection
/// completeness. Scope tokens change on access hints, not ordinary content.
class CryptoRetainedAuthority {
  CryptoRetainedAuthority({
    required this.controller,
    required this.ownAccountId,
    required this.readSecure,
    required this.partition,
  });
  final AuthorityReuseController? controller;
  final String ownAccountId, partition;
  final Future<String?> Function(String) readSecure;
  static const maxScopes = 32, maxEntries = 512, maxBytes = 2 * 1024 * 1024;
  static const operations = {
    'crypto2.scope.headGet',
    'crypto2.directory.status',
    'crypto2.directory.read',
    'crypto2.scope.lifecycle.baseline',
    'crypto2.scope.lifecycle.current',
    'crypto2.scope.lifecycle.list',
    'crypto2.scope.financePolicy.current',
    'crypto2.scope.recordPolicy.status',
    'crypto2.scope.recordPolicy.baseline',
  };
  final _scopes = <String, _ScopeEvidence>{};
  int _bytes = 0, _entries = 0;
  bool get enabled => controller?.enabled == true;
  static String key(String op, Map<String, dynamic> params) {
    Object? order(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: order(value[k])};
      }
      if (value is List) return value.map(order).toList();
      return value;
    }

    return jsonEncode([op, order(params)]);
  }

  static Map<String, dynamic> copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  Future<String?> _directoryPin(String account) async {
    final raw = await readSecure('directory2:$partition:$account');
    if (raw == null) return null;
    if (account != ownAccountId) return raw;
    final pin = CryptoJson.decode(utf8.encode(raw)) as Map;
    // Own observation-only appends move the exact ancestry floor. The signed
    // consumer still checks that floor; only semantic authority is shared here.
    return jsonEncode({
      for (final field in const [
        'serverId',
        'accountId',
        'fingerprint',
        'rootSigningKeyBase64',
        'rootEncryptionKeyBase64',
        'identityEpochId',
        'snapshotHash',
        'deviceSnapshotHash',
        'trustState',
        'pendingRootTransition',
        'verificationMethod',
        'comparedGeneration',
        'comparedHeadHash',
      ])
        field: pin[field],
    });
  }

  void clear() {
    _scopes.clear();
    _bytes = 0;
    _entries = 0;
  }

  void evict(String scope) {
    final old = _scopes.remove(scope);
    if (old != null) {
      _bytes -= old.bytes;
      _entries -= old.reads.length;
    }
  }

  Future<Map<String, dynamic>?> read(
    String operation,
    Map<String, dynamic> params,
  ) async {
    final scope = params['scopeId'];
    if (!enabled ||
        scope is! String ||
        !operations.contains(operation) ||
        params.containsKey('pendingCapability') ||
        params.containsKey('commandBase64'))
      return null;
    final value = _scopes[scope];
    if (value == null) return null;
    if (!identical(value.token, controller!.tokenForScope(scope)) ||
        await readSecure('scope2:$partition:$scope') != value.floor) {
      evict(scope);
      return null;
    }
    for (final entry in value.directories.entries) {
      if (await _directoryPin(entry.key) != entry.value) {
        evict(scope);
        return null;
      }
    }
    if (!enabled || !identical(value.token, controller!.tokenForScope(scope)))
      return null;
    final encoded = value.reads[key(operation, params)];
    if (encoded == null) return null;
    final result = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    if (operation == 'crypto2.directory.status') {
      final account = params['accountId'];
      if (account is! String) return null;
      final raw = await readSecure('directory2:$partition:$account');
      if (raw != null) {
        final pin = CryptoJson.decode(utf8.encode(raw)) as Map;
        // Never feed an older latest-status into the normal rollback guard.
        if (result['generation'] is! int ||
            pin['generation'] is int &&
                result['generation'] < pin['generation'])
          return null;
      }
    }
    return result;
  }

  Future<void> admit({
    required String scope,
    required String headHash,
    required Iterable<String> accounts,
    required Iterable<CryptoAuthorityWireRead> reads,
    required Future<bool> Function() isValid,
  }) async {
    if (!enabled) return;
    final token = controller!.tokenForScope(scope);
    final floor = await readSecure('scope2:$partition:$scope');
    if (floor == null) return;
    final pinned = CryptoJson.decode(utf8.encode(floor)) as Map;
    if (pinned['headHash'] != headHash) return;
    final pins = <String, String>{};
    for (final account in {...accounts, ownAccountId}) {
      final pin = await _directoryPin(account);
      if (pin == null) return;
      pins[account] = pin;
    }
    final staged = <String, String>{};
    var bytes = 0;
    var includesHead = false;
    for (final read in reads) {
      if (!identical(read.token, token) ||
          read.params['scopeId'] != scope ||
          !operations.contains(read.operation) ||
          read.params.containsKey('pendingCapability'))
        continue;
      if (read.operation == 'crypto2.scope.headGet' &&
          !read.params.containsKey('headHash')) {
        if (read.result['headHash'] != headHash) return;
        includesHead = true;
      }
      final k = key(read.operation, read.params),
          encoded = jsonEncode(read.result);
      if (staged.containsKey(k)) continue;
      bytes += utf8.encode(k).length + utf8.encode(encoded).length;
      if (bytes > maxBytes || staged.length >= maxEntries) return;
      staged[k] = encoded;
    }
    if (!includesHead ||
        !enabled ||
        !identical(token, controller!.tokenForScope(scope)) ||
        await readSecure('scope2:$partition:$scope') != floor ||
        !await isValid())
      return;
    for (final pin in pins.entries) {
      if (await _directoryPin(pin.key) != pin.value) return;
    }
    if (!enabled ||
        !identical(token, controller!.tokenForScope(scope)) ||
        await readSecure('scope2:$partition:$scope') != floor ||
        !await isValid())
      return;
    evict(scope);
    while (_scopes.isNotEmpty &&
        (_scopes.length >= maxScopes ||
            _bytes + bytes > maxBytes ||
            _entries + staged.length > maxEntries)) {
      evict(_scopes.keys.first);
    }
    if (_bytes + bytes > maxBytes || _entries + staged.length > maxEntries)
      return;
    _scopes[scope] = _ScopeEvidence(token, floor, pins, staged, bytes);
    _bytes += bytes;
    _entries += staged.length;
  }
}
