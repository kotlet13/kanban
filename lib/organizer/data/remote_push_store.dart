import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/collaboration_models.dart';
import 'device_session_store.dart';
import '../domain/shared_payload_validation.dart';

/// Sensitive registration intent and its immutable prepared CAS request. Never
/// persist this in SQLite, logs, preferences or the ordinary recovery export.
class RemotePushIntent {
  const RemotePushIntent({
    required this.identity,
    required this.generation,
    required this.enabled,
    this.token,
    this.platform,
    this.language,
    this.projectId,
    this.expectedRevision,
    this.confirmedRevision,
    required this.status,
    this.errorCode,
  });
  final RemotePushIdentity identity;
  final String generation;
  final bool enabled;
  final String? token, platform, language, projectId, errorCode;
  final int? expectedRevision, confirmedRevision;
  final RemotePushRegistrationStatus status;
  bool get pending =>
      status == RemotePushRegistrationStatus.pendingRegistration ||
      status == RemotePushRegistrationStatus.pendingUnregistration ||
      status == RemotePushRegistrationStatus.unavailable;
  RemotePushIntent copy({
    int? expectedRevision,
    int? confirmedRevision,
    RemotePushRegistrationStatus? status,
    String? errorCode,
  }) => RemotePushIntent(
    identity: identity,
    generation: generation,
    enabled: enabled,
    token: token,
    platform: platform,
    language: language,
    projectId: projectId,
    expectedRevision: expectedRevision ?? this.expectedRevision,
    confirmedRevision: confirmedRevision ?? this.confirmedRevision,
    status: status ?? this.status,
    errorCode: errorCode,
  );
  RemotePushRegistrationState get publicState => RemotePushRegistrationState(
    identity: identity,
    status: status,
    errorCode: errorCode,
  );
  Map<String, Object?> toJson() => {
    'identity': identity.toJson(),
    'generation': generation,
    'enabled': enabled,
    'token': token,
    'platform': platform,
    'language': language,
    'projectId': projectId,
    'expectedRevision': expectedRevision,
    'confirmedRevision': confirmedRevision,
    'status': status.name,
    'errorCode': errorCode,
  };
  factory RemotePushIntent.fromJson(Map<String, dynamic> j) {
    final enabled = j['enabled'];
    final token = j['token'];
    final revision = j['expectedRevision'];
    final confirmed = j['confirmedRevision'];
    if (enabled is! bool ||
        !isSharedUuid(j['generation']) ||
        (revision != null && (revision is! int || revision < 0)) ||
        (confirmed != null && (confirmed is! int || confirmed < 0)) ||
        (enabled &&
            (token is! String ||
                token.isEmpty ||
                token.length > 4096 ||
                !RegExp(r'^[\x21-\x7e]+$').hasMatch(token) ||
                !const ['ios', 'android'].contains(j['platform']) ||
                !const ['sl', 'en'].contains(j['language']) ||
                j['projectId'] is! String ||
                !RegExp(
                  r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$',
                ).hasMatch(j['projectId'] as String))) ||
        (!enabled &&
            [
              token,
              j['platform'],
              j['language'],
              j['projectId'],
            ].any((v) => v != null))) {
      throw const FormatException('Invalid secure push intent');
    }
    return RemotePushIntent(
      identity: RemotePushIdentity.fromJson(
        j['identity'] as Map<String, dynamic>,
      ),
      generation: j['generation'] as String,
      enabled: enabled,
      token: token as String?,
      platform: j['platform'] as String?,
      language: j['language'] as String?,
      projectId: j['projectId'] as String?,
      expectedRevision: revision as int?,
      confirmedRevision: j['confirmedRevision'] as int?,
      status: RemotePushRegistrationStatus.values.byName(j['status'] as String),
      errorCode: j['errorCode'] as String?,
    );
  }
}

/// Old-device revocation bearer lives only in a separate secure cleanup key.
class RemotePushCleanup {
  const RemotePushCleanup(this.session);
  final DeviceSession session;
  String get deviceId => session.profile.deviceId;
  bool matches(AccountSession profile) =>
      session.profile.partition == profile.partition &&
      deviceId == profile.deviceId;
  Map<String, Object?> toJson() => {
    'profile': session.profile.toJson(),
    'token': session.token,
  };
  factory RemotePushCleanup.fromJson(Map<String, dynamic> json) =>
      RemotePushCleanup(
        DeviceSession(
          AccountSession.fromJson(json['profile'] as Map<String, dynamic>),
          json['token'] as String,
        ),
      );
}

abstract interface class RemotePushStore {
  Future<RemotePushIntent?> read();
  Future<void> write(RemotePushIntent intent);
  Future<void> clear();
  Future<List<RemotePushCleanup>> readCleanups();
  Future<void> writeCleanups(List<RemotePushCleanup> cleanups);
}

class SecureRemotePushStore implements RemotePushStore {
  const SecureRemotePushStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'organizer_remote_push_intent_v1';
  static const _cleanupKey = 'organizer_remote_push_cleanup_v1';

  @override
  Future<List<RemotePushCleanup>> readCleanups() async {
    try {
      final value = await _storage.read(key: _cleanupKey);
      return value == null
          ? []
          : (jsonDecode(value) as List)
                .map(
                  (j) => RemotePushCleanup.fromJson(j as Map<String, dynamic>),
                )
                .toList();
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<void> writeCleanups(List<RemotePushCleanup> cleanups) async {
    try {
      final value = jsonEncode(cleanups.map((c) => c.toJson()).toList());
      await _storage.write(key: _cleanupKey, value: value);
      if (await _storage.read(key: _cleanupKey) != value) {
        throw const CollaborationException('secure_storage');
      }
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<RemotePushIntent?> read() async {
    try {
      final value = await _storage.read(key: _key);
      return value == null
          ? null
          : RemotePushIntent.fromJson(
              jsonDecode(value) as Map<String, dynamic>,
            );
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<void> write(RemotePushIntent intent) async {
    try {
      final value = jsonEncode(intent.toJson());
      await _storage.write(key: _key, value: value);
      if (await _storage.read(key: _key) != value) {
        throw const CollaborationException('secure_storage');
      }
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
      if (await _storage.read(key: _key) != null) {
        throw const CollaborationException('secure_storage');
      }
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }
}
