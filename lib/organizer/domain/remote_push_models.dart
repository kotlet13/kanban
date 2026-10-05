import 'collaboration_models.dart' show AccountSession;
import 'notification_models.dart';

/// Provider data contains only recipient identity and a persisted inbox reference.
class RemotePushReference {
  const RemotePushReference({
    required this.serverId,
    required this.accountId,
    required this.notificationId,
  });
  final String serverId, accountId;
  final int notificationId;
  static RemotePushReference parse(Map<String, Object?> data) {
    const keys = {'type', 'serverId', 'accountId', 'notificationId'};
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    if (data.length != keys.length ||
        !data.keys.every(keys.contains) ||
        data['type'] != 'familyhub.inbox.v1' ||
        data['serverId'] is! String ||
        !uuid.hasMatch(data['serverId'] as String) ||
        data['accountId'] is! String ||
        !uuid.hasMatch(data['accountId'] as String) ||
        data['notificationId'] is! String ||
        !RegExp(
          r'^[1-9][0-9]{0,15}$',
        ).hasMatch(data['notificationId'] as String)) {
      throw const FormatException('Invalid push reference');
    }
    final id = BigInt.parse(data['notificationId'] as String);
    if (id > BigInt.parse('9007199254740991')) {
      throw const FormatException('Invalid push reference');
    }
    return RemotePushReference(
      serverId: data['serverId'] as String,
      accountId: data['accountId'] as String,
      notificationId: id.toInt(),
    );
  }

  static RemotePushReference? tryParse(Map<String, Object?> data) {
    try {
      return parse(data);
    } on FormatException {
      return null;
    }
  }

  bool matches(AccountSession session) =>
      serverId == session.serverId && accountId == session.accountId;
  Map<String, String> toData() => {
    'type': 'familyhub.inbox.v1',
    'serverId': serverId,
    'accountId': accountId,
    'notificationId': '$notificationId',
  };
}

/// Capture before awaiting SDK token retrieval, never infer identity afterwards.
class RemotePushIdentity {
  const RemotePushIdentity({required this.partition, required this.deviceId});
  factory RemotePushIdentity.fromSession(AccountSession session) =>
      RemotePushIdentity(
        partition: session.partition,
        deviceId: session.deviceId,
      );
  final String partition, deviceId;
  bool matches(AccountSession session) =>
      partition == session.partition && deviceId == session.deviceId;
  bool same(RemotePushIdentity other) =>
      partition == other.partition && deviceId == other.deviceId;
  Map<String, String> toJson() => {
    'partition': partition,
    'deviceId': deviceId,
  };
  factory RemotePushIdentity.fromJson(Map<String, dynamic> json) {
    if (json['partition'] is! String ||
        (json['partition'] as String).isEmpty ||
        json['deviceId'] is! String) {
      throw const FormatException('Invalid push identity');
    }
    return RemotePushIdentity(
      partition: json['partition'] as String,
      deviceId: json['deviceId'] as String,
    );
  }
}

enum RemotePushRegistrationStatus {
  disabled,
  pendingRegistration,
  registered,
  pendingUnregistration,
  unavailable,
  blocked,
}

class RemotePushRegistrationState {
  const RemotePushRegistrationState({
    this.identity,
    this.status = RemotePushRegistrationStatus.disabled,
    this.errorCode,
  });
  final RemotePushIdentity? identity;
  final RemotePushRegistrationStatus status;
  final String? errorCode;
}

enum RemotePushOpenStatus {
  requiresLogin,
  wrongAccount,
  requiresConnection,
  permissionDenied,
  deleted,
  offline,
  available,
}

class RemotePushOpenResult {
  const RemotePushOpenResult({required this.status, this.target});
  final RemotePushOpenStatus status;
  final NotificationTarget? target;
}
