import 'dart:async';
import 'dart:convert';

import '../collaboration_transport.dart';
import '../device_session_store.dart';

/// Public protocol metadata for one ordinary sync, never signed authority.
/// Anonymous and bearer requests remain separate, even on today's public API.
class CryptoCapabilityDiscovery {
  CryptoCapabilityDiscovery._(this.transport, this.session, this.isCurrent);

  final CollaborationTransport transport;
  final DeviceSession session;
  final bool Function() isCurrent;
  static final _zoneKey = Object();
  final _pending = <String?, Future<Map<String, dynamic>>>{};
  bool _active = true;

  static Future<T> withSync<T>(
    Future<T> Function() body, {
    required CollaborationTransport transport,
    required DeviceSession session,
    required bool Function() isCurrent,
  }) async {
    final scope = CryptoCapabilityDiscovery._(transport, session, isCurrent);
    try {
      // A nested sync gets a new scope; it never inherits another cycle's data.
      return await runZoned(body, zoneValues: {_zoneKey: scope});
    } finally {
      scope._close();
    }
  }

  static Future<Map<String, dynamic>> read({
    required CollaborationTransport transport,
    required DeviceSession session,
    bool authenticated = false,
  }) {
    Future<Map<String, dynamic>> fetch() => transport.call(
      serverUrl: session.profile.serverUrl,
      operation: 'capabilities',
      token: authenticated ? session.token : null,
      allowLocalHttp: session.profile.allowLocalHttp,
    );

    final scope = Zone.current[_zoneKey];
    if (scope is! CryptoCapabilityDiscovery ||
        !identical(scope.transport, transport) ||
        !identical(scope.session, session) ||
        !scope._available()) {
      return fetch();
    }
    return scope._read(authenticated ? session.token : null, fetch);
  }

  bool _available() {
    if (_active && !isCurrent()) _close();
    return _active;
  }

  void _close() {
    _active = false;
    _pending.clear();
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  Future<Map<String, dynamic>> _read(
    String? token,
    Future<Map<String, dynamic>> Function() fetch,
  ) async {
    final pending = _pending.putIfAbsent(token, () => fetch().then(_copy));
    try {
      final result = await pending;
      if (!_available() || result['serverId'] != session.profile.serverId) {
        if (identical(_pending[token], pending)) _pending.remove(token);
      }
      // Consumers retain their own validation and cannot edit retained metadata.
      return _copy(result);
    } catch (_) {
      if (identical(_pending[token], pending)) _pending.remove(token);
      rethrow;
    }
  }
}
