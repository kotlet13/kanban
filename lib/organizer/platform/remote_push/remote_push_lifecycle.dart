import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../state/collaboration_provider.dart';
import 'firebase_mobile_config.dart';
import 'remote_push_sdk.dart';

enum RemotePushDevicePhase {
  unsupported,
  unconfigured,
  invalidConfiguration,
  needsAccount,
  disabled,
  preparing,
  denied,
  waitingApns,
  registered,
  offline,
  serverUnavailable,
  cleanupRequired,
  error,
}

class RemotePushDeviceState {
  const RemotePushDeviceState(
    this.phase, {
    this.optedIn = false,
    this.errorCode,
    this.bindingKey,
  });
  final RemotePushDevicePhase phase;
  final bool optedIn;
  final String? errorCode, bindingKey;
  bool get ready => phase == RemotePushDevicePhase.registered;
}

class RemotePushBinding {
  const RemotePushBinding({
    required this.identity,
    required this.session,
    required this.optedIn,
    required this.serverSupported,
    required this.language,
    this.serverProjectId,
    this.accountUsable = true,
    this.blockedReason,
  });
  final RemotePushIdentity identity;
  final AccountSession session;
  final bool optedIn, serverSupported, accountUsable;
  final String language;
  final String? serverProjectId, blockedReason;
  String get key => '${identity.partition}:${identity.deviceId}';
}

/// Serializes SDK ownership, not business writes. Epoch is advanced synchronously
/// before any awaits, so a late permission/token/registration from A cannot bind B.
class RemotePushLifecycle {
  RemotePushLifecycle({
    required this.sdk,
    required this.preferences,
    required this.config,
    required this.onState,
    required this.configure,
    required this.disable,
    required this.receive,
    required this.onOpened,
  });
  final RemotePushSdk sdk;
  final SharedPreferences preferences;
  final FirebaseMobileConfig? config;
  final void Function(RemotePushDeviceState) onState;
  final Future<RemotePushRegistrationState> Function(
    RemotePushIdentity,
    String,
    String,
    String,
    String,
  )
  configure;
  final Future<RemotePushRegistrationState> Function(RemotePushIdentity)
  disable;
  final Future<bool> Function(RemotePushReference) receive;
  final void Function(RemotePushReference) onOpened;
  static const _identityKey = 'organizer_remote_push_sdk_identity_v1',
      _cleanupKey = 'organizer_remote_push_sdk_cleanup_v1';
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _disposed = false, _initialized = false, _acceptTokens = false;
  RemotePushBinding? _binding;
  String? _lastToken;
  bool _registrationSuppressed = false;
  String? _activeSignature;
  RemotePushDeviceState state = const RemotePushDeviceState(
    RemotePushDevicePhase.disabled,
  );
  void _status(RemotePushDevicePhase phase, {String? code}) {
    state = RemotePushDeviceState(
      phase,
      optedIn: _binding?.optedIn ?? false,
      errorCode: code,
      bindingKey: _binding?.key,
    );
    if (!_disposed) onState(state);
  }

  Future<void> _persist(String key, Object value) async {
    final success = value is bool
        ? await preferences.setBool(key, value)
        : await preferences.setString(key, value as String);
    if (!success) throw StateError('Remote push preference storage failed');
  }

  Future<void> update(
    RemotePushBinding? binding, {
    bool requestPermission = false,
    bool force = false,
  }) {
    final signature = binding == null
        ? 'signed-out'
        : '${binding.key}:${binding.optedIn}:${binding.serverSupported}:${binding.serverProjectId}:${binding.language}:${binding.accountUsable}:${binding.blockedReason}';
    if (!force && signature == _activeSignature) return _tail;
    _activeSignature = signature;
    final previous = _binding;
    _binding = binding;
    final generation = ++_generation;
    _acceptTokens = false;
    final result = _tail.then(
      (_) => _apply(binding, previous, generation, requestPermission),
    );
    _tail = result.catchError((Object error, StackTrace stack) {});
    return result;
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  Future<void> _initialize(int generation) async {
    final initial = await sdk.initialize(
      config!,
      onForeground: (data) {
        if (!_current(generation) || !(_binding?.optedIn ?? false)) return;
        final reference = RemotePushReference.tryParse(data);
        if (reference != null && reference.matches(_binding!.session)) {
          unawaited(_receive(reference, generation));
        }
      },
      onOpened: (data) {
        if (!_current(generation)) return;
        final reference = RemotePushReference.tryParse(data);
        if (reference != null) onOpened(reference);
      },
      onToken: (token) {
        if (_current(generation) &&
            _acceptTokens &&
            token.isNotEmpty &&
            token != _lastToken) {
          final binding = _binding!;
          final operation = _tail.then(
            (_) => _register(binding, token, generation),
          );
          _tail = operation.catchError((Object error, StackTrace stack) {});
        }
      },
      onError: () {
        if (_current(generation)) _status(RemotePushDevicePhase.error);
      },
    );
    _initialized = true;
    if (_current(generation) && initial != null) {
      final reference = RemotePushReference.tryParse(initial);
      if (reference != null) onOpened(reference);
    }
  }

  Future<void> _receive(RemotePushReference reference, int generation) async {
    try {
      await receive(reference);
    } catch (_) {
      if (_current(generation)) _status(RemotePushDevicePhase.offline);
    }
  }

  Future<void> _cleanup(
    RemotePushBinding? previous,
    int generation, {
    bool unregister = true,
  }) async {
    if (!_initialized) await _initialize(generation);
    // Stop renewal before preference/network work; neither can postpone SDK cleanup.
    await sdk.stopListening();
    await sdk.setAutoInit(false);
    Object? storageError;
    try {
      await _persist(_cleanupKey, true);
    } catch (e) {
      storageError = e;
    }
    _acceptTokens = false;
    if (previous != null && unregister) {
      try {
        await disable(previous.identity);
      } catch (_) {}
    }
    await sdk.deleteToken();
    _lastToken = null;
    if (storageError != null) throw storageError;
    await _persist(_cleanupKey, false);
    if (!await preferences.remove(_identityKey)) {
      throw StateError('Remote push ownership cleanup failed');
    }
  }

  Future<void> _apply(
    RemotePushBinding? binding,
    RemotePushBinding? previous,
    int generation,
    bool prompt,
  ) async {
    if (!_current(generation)) return;
    if (!sdk.supported) {
      _status(RemotePushDevicePhase.unsupported);
      return;
    }
    if (config == null) {
      _status(RemotePushDevicePhase.unconfigured);
      return;
    }
    try {
      final stored = preferences.getString(_identityKey);
      final requiresCleanup =
          preferences.getBool(_cleanupKey) == true ||
          (stored != null &&
              (binding?.key != stored || binding?.optedIn != true));
      if (requiresCleanup ||
          (_initialized && previous != null && previous.key != binding?.key)) {
        if (!_initialized) await _initialize(generation);
        await _cleanup(
          previous ?? binding,
          generation,
          unregister:
              binding?.blockedReason == null || binding?.optedIn != true,
        );
        if (!_current(generation)) return;
      }
      if (binding == null) {
        _status(RemotePushDevicePhase.needsAccount);
        return;
      }
      if (!binding.accountUsable ||
          !binding.session.expiresAt.isAfter(DateTime.now())) {
        if (_initialized || stored != null) await _cleanup(binding, generation);
        if (_current(generation)) _status(RemotePushDevicePhase.needsAccount);
        return;
      }
      if (!binding.optedIn) {
        _status(RemotePushDevicePhase.disabled);
        return;
      }
      if (binding.blockedReason != null && !prompt) {
        if (_initialized || stored != null) {
          await _cleanup(binding, generation, unregister: false);
        }
        if (_current(generation)) {
          _status(RemotePushDevicePhase.error, code: binding.blockedReason);
        }
        return;
      }
      if (binding.blockedReason != null &&
          prompt &&
          (_initialized || stored != null)) {
        await _cleanup(binding, generation, unregister: false);
        if (!_current(generation)) return;
      }
      if (!binding.serverSupported) {
        if (_initialized || stored != null) await _cleanup(binding, generation);
        if (!_current(generation)) return;
        _status(RemotePushDevicePhase.serverUnavailable);
        return;
      }
      if (binding.serverProjectId != config!.projectId) {
        if (_initialized || stored != null) await _cleanup(binding, generation);
        if (_current(generation)) {
          _status(
            RemotePushDevicePhase.serverUnavailable,
            code: 'push_project_mismatch',
          );
        }
        return;
      }
      _status(RemotePushDevicePhase.preparing);
      await _persist(_identityKey, binding.key);
      await _initialize(generation);
      if (!_current(generation)) return;
      var permission = await sdk.permissionStatus();
      if (prompt && permission != RemotePushPermission.granted) {
        permission = await sdk.requestPermission();
      }
      if (!_current(generation)) return;
      if (permission != RemotePushPermission.granted) {
        await _cleanup(binding, generation);
        if (!_current(generation)) return;
        _status(RemotePushDevicePhase.denied);
        return;
      }
      if (!await sdk.prepareApns()) {
        if (_current(generation)) _status(RemotePushDevicePhase.waitingApns);
        return;
      }
      if (!_current(generation)) return;
      await sdk.setAutoInit(true);
      if (!_current(generation)) return;
      final token = await sdk.token();
      if (!_current(generation)) return;
      if (token == null || token.isEmpty) {
        _status(RemotePushDevicePhase.waitingApns);
        return;
      }
      _acceptTokens = true;
      await _register(binding, token, generation);
    } catch (error) {
      if (_current(generation)) {
        _status(
          preferences.getBool(_cleanupKey) == true
              ? RemotePushDevicePhase.cleanupRequired
              : RemotePushDevicePhase.error,
          code: error is CollaborationException ? error.code : null,
        );
      }
    }
  }

  Future<void> _register(
    RemotePushBinding binding,
    String token,
    int generation,
  ) async {
    if (!_current(generation)) return;
    _registrationSuppressed = true;
    _status(RemotePushDevicePhase.preparing);
    try {
      final result = await configure(
        binding.identity,
        token,
        sdk.platform,
        binding.language,
        config!.projectId,
      );
      if (!_current(generation)) return;
      _lastToken = token;
      _registrationSuppressed = false;
      if ({
        RemotePushRegistrationStatus.unavailable,
        RemotePushRegistrationStatus.blocked,
      }.contains(result.status)) {
        _acceptTokens = false;
        await _cleanup(
          binding,
          generation,
          unregister: result.status != RemotePushRegistrationStatus.blocked,
        );
        if (_current(generation)) {
          _status(
            result.status == RemotePushRegistrationStatus.unavailable
                ? RemotePushDevicePhase.serverUnavailable
                : RemotePushDevicePhase.error,
            code: result.errorCode,
          );
        }
        return;
      }
      applyRegistration(result);
    } catch (error) {
      if (_current(generation)) {
        _status(
          RemotePushDevicePhase.error,
          code: error is CollaborationException ? error.code : null,
        );
      }
    }
  }

  void applyRegistration(RemotePushRegistrationState registration) {
    if (!(_binding?.accountUsable ?? false) ||
        !(_binding?.session.expiresAt.isAfter(DateTime.now()) ?? false) ||
        !(_binding?.optedIn ?? false) ||
        !(_binding?.serverSupported ?? false) ||
        !_acceptTokens ||
        _registrationSuppressed ||
        _disposed) {
      return;
    }
    final phase = switch (registration.status.name) {
      'registered' => RemotePushDevicePhase.registered,
      'pendingRegistration' ||
      'pendingUnregistration' => RemotePushDevicePhase.offline,
      'unavailable' => RemotePushDevicePhase.serverUnavailable,
      'blocked' => RemotePushDevicePhase.error,
      _ => RemotePushDevicePhase.disabled,
    };
    _status(phase, code: registration.errorCode);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _acceptTokens = false;
    unawaited(sdk.stopListening());
  }
}
