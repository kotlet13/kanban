import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/collaboration_models.dart';
import 'collaboration_transport.dart';

/// A pending capability is kept outside backups, URLs, and ordinary preferences.
/// Server identity is pinned before presenting/sending the capability. Account
/// identity is pinned before acceptance so a lost reply can safely be retried.
class PendingInvitation {
  const PendingInvitation({
    required this.serverUrl,
    required this.token,
    this.serverId,
    this.expiresAt,
    this.accountPartition,
    this.invitationId,
  });
  final String serverUrl, token;
  final String? serverId, accountPartition, invitationId;
  final DateTime? expiresAt;
  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'token': token,
    'serverId': serverId,
    'expiresAt': expiresAt?.toUtc().millisecondsSinceEpoch,
    'accountPartition': accountPartition,
    'invitationId': invitationId,
  };
  factory PendingInvitation.fromJson(Map<String, dynamic> json) {
    final token = json['token'] as String;
    if (!RegExp(r'^fhi[12]_[a-f0-9]{64}$').hasMatch(token)) {
      throw const FormatException();
    }
    return PendingInvitation(
      serverUrl: normalizeCollaborationServer(json['serverUrl'] as String),
      token: token,
      serverId: json['serverId'] as String?,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['expiresAt'] as int,
              isUtc: true,
            ),
      accountPartition: json['accountPartition'] as String?,
      invitationId: json['invitationId'] as String?,
    );
  }
}

abstract interface class PendingInvitationStore {
  Future<PendingInvitation?> read();
  Future<void> write(PendingInvitation? invitation);
}

// Native link receivers and repositories share this queue for the same backing
// record. A complete read/check/write stays atomic even across repository reloads.
// All secure-store instances address the same key and therefore share one queue.
final _pendingInvitationQueues = Expando<Future<void>>();
final _securePendingInvitationQueueIdentity = Object();

extension PendingInvitationStoreSerialization on PendingInvitationStore {
  /// Persist a parsed native link inside the same atomic queue as account work.
  Future<void> receiveLink({
    required String serverUrl,
    required String token,
    required bool Function() isCurrent,
  }) => serialized(() async {
    final base = normalizeCollaborationServer(serverUrl);
    final old = await read();
    if (!isCurrent()) return;
    if (old?.token == token && old?.serverUrl != base) {
      throw const CollaborationException('invitation_identity_mismatch');
    }
    if (old?.token != token || old?.serverUrl != base) {
      await write(PendingInvitation(serverUrl: base, token: token));
    }
  });

  Future<T> serialized<T>(Future<T> Function() action) {
    final identity = this is SecurePendingInvitationStore
        ? _securePendingInvitationQueueIdentity
        : this;
    final previous = _pendingInvitationQueues[identity] ?? Future<void>.value();
    final result = previous.then((_) => action());
    _pendingInvitationQueues[identity] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}

class SecurePendingInvitationStore implements PendingInvitationStore {
  const SecurePendingInvitationStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'jivie_pending_invitation_v1';
  @override
  Future<PendingInvitation?> read() async {
    try {
      final value = await _storage.read(key: _key);
      return value == null
          ? null
          : PendingInvitation.fromJson(
              jsonDecode(value) as Map<String, dynamic>,
            );
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<void> write(PendingInvitation? invitation) async {
    try {
      final value = invitation == null ? null : jsonEncode(invitation.toJson());
      if (value == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: value);
      }
      if (await _storage.read(key: _key) != value) {
        throw const CollaborationException('secure_storage');
      }
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }
}

class MemoryPendingInvitationStore implements PendingInvitationStore {
  PendingInvitation? value;
  @override
  Future<PendingInvitation?> read() async => value;
  @override
  Future<void> write(PendingInvitation? invitation) async {
    value = invitation;
  }
}
